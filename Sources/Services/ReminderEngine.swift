import Foundation

enum ReminderRunState: Equatable {
    case running
    case paused(until: Date?)
    case outsideHours
    case disabled
    case due
}

enum ReminderPhase: String, Codable, Equatable, Sendable {
    case accumulating
    case delivering
    case awaitingResponse
    case snoozed
    case guiding
    case overdue
    case paused
    case outsideSchedule
    case disabled
}

enum ReminderTiming {
    static let guidedActivityDuration: TimeInterval = 60
    static let responseWindow: TimeInterval = 10 * 60
    static let snoozeDuration: TimeInterval = 5 * 60
    static let longSuspensionThreshold: TimeInterval = 10 * 60
}

@MainActor
protocol ReminderNotificationManaging: AnyObject {
    func requestAuthorizationIfNeeded()
    func deliverReminder(
        body: String,
        soundEnabled: Bool,
        completion: @escaping (Bool) -> Void
    )
    func deliverReminder(
        cycleID: UUID,
        body: String,
        soundEnabled: Bool,
        completion: @escaping (Bool) -> Void
    )
    func cancelReminder(cycleID: UUID)
    func setReminderActionHandler(_ handler: @escaping (ReminderNotificationAction) -> Void)
}

extension ReminderNotificationManaging {
    func deliverReminder(
        cycleID: UUID,
        body: String,
        soundEnabled: Bool,
        completion: @escaping (Bool) -> Void
    ) {
        deliverReminder(body: body, soundEnabled: soundEnabled, completion: completion)
    }

    func cancelReminder(cycleID: UUID) {}
    func setReminderActionHandler(_ handler: @escaping (ReminderNotificationAction) -> Void) {}
}

extension NotificationManager: ReminderNotificationManaging {}

@MainActor
protocol ReminderPresenting: AnyObject {
    func present(message: String, completion: @escaping (ReminderAction) -> Void)
    func presentGuide(endsAt: Date, completion: @escaping (ReminderAction) -> Void)
    func dismiss()
}

extension ReminderPresenter: ReminderPresenting {}

extension ReminderPresenting {
    func presentGuide(endsAt: Date, completion: @escaping (ReminderAction) -> Void) {
        present(message: "按你的身体状况，换个姿势或活动 60 秒。", completion: completion)
    }
}

@MainActor
final class ReminderEngine: ObservableObject {
    @Published private(set) var now = Date()
    @Published private(set) var nextReminderAt: Date?
    @Published private(set) var state: ReminderRunState = .running
    @Published private(set) var currentReminderText: String?
    @Published private(set) var celebrationText: String?
    @Published private(set) var activeReminderCycle: ReminderCycleRecord?
    @Published private(set) var phase: ReminderPhase = .accumulating
    @Published private(set) var accumulatedEligibleSeconds: TimeInterval = 0
    @Published private(set) var opportunityCooldownSeconds: TimeInterval = 0
    @Published private(set) var guideElapsedSeconds: TimeInterval = 0

    private let settingsStore: SettingsStore
    private let statsStore: StatsStore
    private let notificationManager: ReminderNotificationManaging
    private let reminderPresenter: ReminderPresenting
    private let widgetSyncController: WidgetSyncController
    private let sessionStateStore: ReminderSessionStateStore
    private let nowProvider: () -> Date

    private var timer: Timer?
    private var isPaused = false
    private var pauseUntil: Date?
    private var reminderShowing = false
    private var pendingDeliveryID: UUID?
    private var celebrationTask: Task<Void, Never>?
    private var lastTickAt: Date?
    private var lastTickWasAllowed = false
    private var lastDateKey: String?
    private var deliveryBlocked = false
    private var guideActivityID: UUID?
    private var guideCycleID: UUID?
    private var guideStartedAt: Date?
    private var suspensionStartedAt: Date?
    private var suspensionIsSleep = false
    private var announcedGuideMilestones: Set<Int> = []
    private var lastPersistedCheckpoint: ReminderRuntimeCheckpoint?

    init(
        settingsStore: SettingsStore,
        statsStore: StatsStore,
        notificationManager: ReminderNotificationManaging,
        reminderPresenter: ReminderPresenting,
        widgetSyncController: WidgetSyncController,
        sessionStateStore: ReminderSessionStateStore,
        nowProvider: @escaping () -> Date = { Date() }
    ) {
        self.settingsStore = settingsStore
        self.statsStore = statsStore
        self.notificationManager = notificationManager
        self.reminderPresenter = reminderPresenter
        self.widgetSyncController = widgetSyncController
        self.sessionStateStore = sessionStateStore
        self.nowProvider = nowProvider

        self.settingsStore.onSettingsChanged = { [weak self] oldSettings, newSettings in
            self?.settingsDidChange(from: oldSettings, to: newSettings)
        }
        self.notificationManager.setReminderActionHandler { [weak self] action in
            self?.handleNotificationAction(action)
        }
    }

    func start(schedulesTimer: Bool = true) {
        start(at: nowProvider(), schedulesTimer: schedulesTimer)
    }

    func start(at startDate: Date, schedulesTimer: Bool = true) {
        now = startDate
        _ = statsStore.refreshForCurrentDay(at: startDate)
        lastDateKey = ActivityDay.makeDateKey(for: startDate)
        let checkpoint = sessionStateStore.loadCheckpoint()
        accumulatedEligibleSeconds = checkpoint.accumulatedEligibleSeconds
        opportunityCooldownSeconds = checkpoint.opportunityCooldownSeconds
        if let suspension = sessionStateStore.loadSuspension() {
            // A process can be terminated while the machine is asleep or the
            // session is locked, so the matching wake notification is not
            // guaranteed to arrive. Apply the same long-suspension boundary
            // during restoration before accepting another eligible second.
            let suspensionDuration = max(startDate.timeIntervalSince(suspension.startedAt), 0)
            if suspensionDuration >= ReminderTiming.longSuspensionThreshold {
                accumulatedEligibleSeconds = 0
                opportunityCooldownSeconds = 0
            }
            sessionStateStore.clearSuspension()
        }
        // Force a write when restoration changed the cadence because of a
        // persisted long suspension.
        lastPersistedCheckpoint = nil
        lastTickAt = startDate
        lastTickWasAllowed = SchedulePolicy.isAllowed(startDate, settings: settingsStore.settings)

        if settingsStore.settings.notificationsEnabled {
            notificationManager.requestAuthorizationIfNeeded()
        }

        let remindersEnabled = settingsStore.settings.remindersEnabled
        if remindersEnabled {
            restorePauseState(at: startDate)
        } else {
            clearPauseState()
        }

        if remindersEnabled, !isPaused {
            let pendingCycleToRestore = statsStore.latestPendingCycle
            _ = statsStore.settlePendingReminderCycles(
                except: pendingCycleToRestore?.id,
                outcome: .expired,
                at: startDate
            )
            restorePendingReminderCycle(at: startDate)
            refreshScheduleState(at: startDate)
        } else if remindersEnabled {
            pendingDeliveryID = nil
            _ = statsStore.settlePendingReminderCycles(outcome: .skipped, at: startDate)
            activeReminderCycle = nil
            if reminderShowing {
                clearActiveReminder()
            }
        } else if !remindersEnabled {
            pendingDeliveryID = nil
            _ = statsStore.settlePendingReminderCycles(outcome: .skipped, at: startDate)
            activeReminderCycle = nil
            if reminderShowing {
                clearActiveReminder()
            }
            nextReminderAt = nil
            state = .disabled
            phase = .disabled
        }
        updateTodaySnapshot(at: startDate)
        persistRuntimeCheckpoint()
        publishWidgetSnapshot()

        timer?.invalidate()
        guard schedulesTimer else { return }

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    func completeCurrentReminder() {
        startActivity()
    }

    func recordManualActivity() {
        startActivity()
    }

    func startActivity(cycleID requestedCycleID: UUID? = nil) {
        guard settingsStore.settings.remindersEnabled,
              guideActivityID == nil else { return }

        let actionDate = nowProvider()
        let cycle = activeReminderCycle
        if let requestedCycleID, cycle?.id != requestedCycleID { return }

        if let cycle {
            guard cycle.outcome == .pending,
                  cycle.snoozedUntil == nil,
                  cycle.responseDeadline.map({ actionDate <= $0 }) ?? false,
                  statsStore.startReminderGuide(id: cycle.id, at: actionDate) else {
                return
            }
            activeReminderCycle = statsStore.latestPendingCycle
            guideCycleID = cycle.id
        } else {
            guard canRecordManualActivity else { return }
            guideCycleID = nil
        }

        guideActivityID = UUID()
        guideStartedAt = actionDate
        guideElapsedSeconds = 0
        announcedGuideMilestones.removeAll()
        phase = .guiding
        state = .due
        currentReminderText = "按你的身体状况，换个姿势或活动 60 秒。"
        if let cycleID = guideCycleID {
            notificationManager.cancelReminder(cycleID: cycleID)
        }
        // Starting the activity is an explicit user action, so the guide gets
        // its own visible countdown even when passive strong popups are off.
        reminderShowing = true
        reminderPresenter.presentGuide(
            endsAt: actionDate.addingTimeInterval(ReminderTiming.guidedActivityDuration)
        ) { [weak self] action in
            self?.handleReminderAction(action)
        }
        lastTickAt = actionDate
        ReminderAccessibility.announce("已开始 60 秒活动")
        publishWidgetSnapshot()
    }

    func snooze(minutes: Int = 5) {
        guard canSnooze, let cycle = activeReminderCycle else { return }

        let actionDate = nowProvider()
        guard SchedulePolicy.isAllowed(actionDate, settings: settingsStore.settings) else {
            resolveActiveReminder(as: .expired, at: actionDate)
            clearActiveReminder()
            scheduleNextReminder(from: actionDate)
            publishWidgetSnapshot()
            return
        }
        let snoozedUntil = actionDate.addingTimeInterval(
            minutes == 5 ? ReminderTiming.snoozeDuration : TimeInterval(max(minutes, 1) * 60)
        )
        let newResponseDeadline = snoozedUntil.addingTimeInterval(ReminderTiming.responseWindow)
        guard SchedulePolicy.isContinuouslyAllowed(
            from: snoozedUntil,
            through: newResponseDeadline,
            settings: settingsStore.settings
        ) else { return }
        guard statsStore.snoozeReminderCycle(id: cycle.id, snoozedUntil: snoozedUntil) else { return }

        activeReminderCycle = statsStore.latestPendingCycle
        notificationManager.cancelReminder(cycleID: cycle.id)
        clearActiveReminder()
        nextReminderAt = snoozedUntil
        now = actionDate
        state = .running
        phase = .snoozed
        publishWidgetSnapshot()
    }

    func pause(minutes: Int? = nil) {
        guard settingsStore.settings.remindersEnabled else { return }

        let actionDate = nowProvider()
        cancelGuide()
        resolveActiveReminder(as: .skipped, at: actionDate)
        clearActiveReminder()

        let until = minutes.map { actionDate.addingTimeInterval(TimeInterval(max($0, 1) * 60)) }
        setPauseState(until.map(ReminderPauseState.until) ?? .indefinite)
        resetCadence()
        updateTodaySnapshot(at: actionDate, eligibility: .paused)
        publishWidgetSnapshot()
    }

    func pauseToday() {
        guard settingsStore.settings.remindersEnabled else { return }

        let actionDate = nowProvider()
        cancelGuide()
        resolveActiveReminder(as: .skipped, at: actionDate)
        clearActiveReminder()

        let tomorrow = Calendar.current.date(
            byAdding: .day,
            value: 1,
            to: Calendar.current.startOfDay(for: actionDate)
        )
        if let tomorrow {
            setPauseState(.until(tomorrow))
        } else {
            setPauseState(.indefinite)
        }
        resetCadence()
        updateTodaySnapshot(at: actionDate, eligibility: .paused)
        publishWidgetSnapshot()
    }

    func resume() {
        let actionDate = nowProvider()
        clearPauseState()
        resetCadence()
        lastTickAt = actionDate
        refreshScheduleState(at: actionDate)
        updateTodaySnapshot(at: actionDate)
        publishWidgetSnapshot()
    }

    func resetTimer() {
        let actionDate = nowProvider()
        cancelGuide()
        resolveActiveReminder(as: .skipped, at: actionDate)
        clearActiveReminder()
        clearPauseState()
        resetCadence()
        lastTickAt = actionDate
        refreshScheduleState(at: actionDate)
        publishWidgetSnapshot()
    }

    var remainingInterval: TimeInterval {
        switch phase {
        case .guiding:
            return max(ReminderTiming.guidedActivityDuration - guideElapsedSeconds, 0)
        case .awaitingResponse:
            return max(activeReminderCycle?.responseDeadline?.timeIntervalSince(now) ?? 0, 0)
        case .snoozed:
            return max(activeReminderCycle?.snoozedUntil?.timeIntervalSince(now) ?? 0, 0)
        case .overdue:
            return max(opportunityCooldownSeconds, 0)
        default:
            return max(reminderThreshold - accumulatedEligibleSeconds, 0)
        }
    }

    var canSnooze: Bool {
        guard phase == .awaitingResponse,
              let cycle = activeReminderCycle else {
            return false
        }
        return cycle.outcome == .pending
            && cycle.snoozeCount == 0
            && (cycle.responseDeadline.map { now <= $0 } ?? false)
    }

    var canCompleteReminder: Bool {
        phase == .awaitingResponse
            && activeReminderCycle?.outcome == .pending
            && activeReminderCycle?.snoozedUntil == nil
            && (activeReminderCycle?.responseDeadline.map { now <= $0 } ?? false)
    }

    var manualActivityAvailableAt: Date? {
        nil
    }

    var canRecordManualActivity: Bool {
        guard guideActivityID == nil,
              activeReminderCycle == nil,
              statsStore.latestPendingCycle == nil,
              pendingDeliveryID == nil,
              phase == .accumulating || phase == .overdue,
              SchedulePolicy.isAllowed(now, settings: settingsStore.settings) else {
            return false
        }
        return true
    }

    var countdownText: String {
        switch state {
        case .paused:
            return "已暂停"
        case .disabled:
            return "已关闭"
        case .due:
            return phase == .guiding ? TimeFormatting.countdown(remainingInterval) : "该活动了"
        case .outsideHours:
            return "非工作时间"
        case .running:
            if phase == .snoozed { return "已延后 \(TimeFormatting.countdown(remainingInterval))" }
            if phase == .overdue { return "等待下次提醒" }
            return TimeFormatting.countdown(remainingInterval)
        }
    }

    var menuBarTitle: String {
        switch state {
        case .paused:
            return "暂停"
        case .disabled:
            return "关闭"
        case .due:
            return phase == .guiding ? "60秒" : "活动"
        case .outsideHours:
            return "休息"
        case .running:
            return TimeFormatting.menuBarCountdown(remainingInterval)
        }
    }

    var statusText: String {
        switch phase {
        case .delivering:
            return "正在发送活动提醒"
        case .awaitingResponse:
            return "等待开始 1 分钟活动"
        case .snoozed:
            return "已延后 5 分钟"
        case .guiding:
            return "活动进行中，还剩 \(Int(ceil(remainingInterval))) 秒"
        case .overdue:
            return deliveryBlocked ? "活动时间已到，提醒渠道不可用" : "活动时间已到"
        case .paused:
            guard let pauseUntil else { return "已暂停" }
            return "暂停到 \(pauseUntil.formatted(date: .omitted, time: .shortened))"
        case .outsideSchedule:
            return "非提醒时段"
        case .disabled:
            return "提醒已关闭"
        case .accumulating:
            break
        }

        switch state {
        case .running:
            return "提醒进行中"
        case .paused(let until):
            guard let until else { return "已暂停" }
            return "暂停到 \(until.formatted(date: .omitted, time: .shortened))"
        case .outsideHours:
            return "非提醒时段"
        case .disabled:
            return "提醒已关闭"
        case .due:
            return "到活动时间了"
        }
    }

    var statusSystemImage: String {
        if phase == .guiding || phase == .awaitingResponse {
            return "figure.walk"
        }

        switch state {
        case .running:
            return "timer"
        case .paused:
            return "pause.circle"
        case .outsideHours:
            return "moon"
        case .disabled:
            return "power"
        case .due:
            return "arrow.triangle.2.circlepath"
        }
    }

    var progressFraction: Double {
        guard settingsStore.settings.intervalMinutes > 0 else {
            return 0
        }
        if phase == .guiding {
            return min(max(guideElapsedSeconds / ReminderTiming.guidedActivityDuration, 0), 1)
        }
        return min(max(accumulatedEligibleSeconds / reminderThreshold, 0), 1)
    }

    var nextReminderText: String {
        guard let nextReminderAt else { return "还没有安排下一次提醒" }
        return "下次 \(nextReminderAt.formatted(date: .omitted, time: .shortened))"
    }

    func tick() {
        tick(at: nowProvider())
    }

    func tick(at date: Date) {
        let previousState = state
        let previousNextReminderAt = nextReminderAt
        let previousNow = now
        now = date
        let didChangeDay = statsStore.refreshForCurrentDay(at: date)
        defer {
            if didChangeDay || previousState != state || previousNextReminderAt != nextReminderAt {
                publishWidgetSnapshot()
            }
        }

        // Sleep/lock notifications delimit a frozen interval. Timer callbacks
        // can still arrive while the session is inactive, so do not let those
        // callbacks advance either cadence clock (or the guide) a second time.
        if suspensionStartedAt != nil {
            lastTickAt = date
            return
        }

        let settings = settingsStore.settings
        guard settings.remindersEnabled else {
            state = .disabled
            phase = .disabled
            lastTickAt = date
            return
        }

        if isPaused {
            if let pauseUntil, now >= pauseUntil {
                clearPauseState()
                resetCadence()
                lastTickAt = date
                refreshScheduleState(at: date)
            } else {
                state = .paused(until: pauseUntil)
                phase = .paused
                lastTickAt = date
                return
            }
        }

        let dateKey = ActivityDay.makeDateKey(for: date)
        if lastDateKey != dateKey {
            resolveActiveReminder(as: .expired, at: date)
            cancelGuide()
            resetCadence()
            lastDateKey = dateKey
        }

        if phase == .guiding {
            let delta = max(date.timeIntervalSince(lastTickAt ?? previousNow), 0)
            guideElapsedSeconds = min(guideElapsedSeconds + delta, ReminderTiming.guidedActivityDuration)
            announceGuideMilestonesIfNeeded()
            lastTickAt = date
            if guideElapsedSeconds >= ReminderTiming.guidedActivityDuration {
                completeGuidedActivity(at: date)
            }
            publishWidgetSnapshot()
            return
        }

        let allowedNow = SchedulePolicy.isAllowed(date, settings: settings)
        let continuouslyAllowed = lastTickWasAllowed
            && SchedulePolicy.isContinuouslyAllowed(
                from: lastTickAt ?? date,
                through: date,
                settings: settings
            )

        guard allowedNow else {
            if lastTickWasAllowed || activeReminderCycle != nil {
                resolveActiveReminder(as: .expired, at: date)
                resetCadence()
            }
            lastTickWasAllowed = false
            lastTickAt = date
            state = .outsideHours
            phase = .outsideSchedule
            nextReminderAt = nextFreshReminderDate(after: date)
            updateTodaySnapshot(at: date)
            persistRuntimeCheckpoint()
            return
        }

        if !continuouslyAllowed, lastTickAt != nil {
            resetCadence()
        }
        let elapsed = continuouslyAllowed ? max(date.timeIntervalSince(lastTickAt ?? date), 0) : 0
        lastTickAt = date
        lastTickWasAllowed = true

        accumulatedEligibleSeconds = min(accumulatedEligibleSeconds + elapsed, reminderThreshold)
        if opportunityCooldownSeconds > 0 {
            opportunityCooldownSeconds = max(opportunityCooldownSeconds - elapsed, 0)
        }

        if let cycle = activeReminderCycle {
            if let snoozedUntil = cycle.snoozedUntil {
                if date >= snoozedUntil {
                    redeliverSnoozedCycle(cycle, at: date)
                } else {
                    phase = .snoozed
                    state = .running
                    nextReminderAt = snoozedUntil
                }
            } else if cycle.guideStartedAt == nil,
                      let responseDeadline = cycle.responseDeadline,
                      date > responseDeadline {
                expireOpportunity(at: date)
            } else {
                phase = .awaitingResponse
                state = .due
                nextReminderAt = cycle.responseDeadline
            }
        } else if accumulatedEligibleSeconds >= reminderThreshold {
            if opportunityCooldownSeconds > 0 || deliveryBlocked {
                phase = .overdue
                state = .due
                nextReminderAt = opportunityCooldownSeconds > 0
                    ? date.addingTimeInterval(opportunityCooldownSeconds)
                    : nil
            } else if hasFullResponseWindow(startingAt: date) {
                fireReminder()
            } else {
                phase = .overdue
                state = .outsideHours
                nextReminderAt = nextFreshReminderDate(after: date)
            }
        } else {
            phase = .accumulating
            state = .running
            refreshNextReminderDate(at: date)
        }

        updateTodaySnapshot(at: date)
        persistRuntimeCheckpoint()
    }

    private func fireReminder() {
        guard pendingDeliveryID == nil,
              activeReminderCycle == nil,
              hasAnyDeliveryChannel else {
            deliveryBlocked = true
            phase = .overdue
            state = .due
            nextReminderAt = nil
            return
        }

        let actionDate = now
        let message = ReminderMessages.reminder
        let settings = settingsStore.settings
        let cycleID = UUID()
        let responseDeadline = actionDate.addingTimeInterval(ReminderTiming.responseWindow)
        phase = .delivering

        if settings.popupEnabled {
            guard establishReminderCycle(
                id: cycleID,
                at: actionDate,
                responseDeadline: responseDeadline
            ) else {
                phase = .overdue
                return
            }

            if settings.notificationsEnabled {
                notificationManager.deliverReminder(
                    cycleID: cycleID,
                    body: message,
                    soundEnabled: settings.soundEnabled
                ) { _ in }
            }

            reminderShowing = true
            currentReminderText = message
            state = .due
            phase = .awaitingResponse
            nextReminderAt = responseDeadline
            reminderPresenter.present(message: message) { [weak self] action in
                self?.handleReminderAction(action)
            }
            return
        }

        let deliveryID = cycleID
        pendingDeliveryID = deliveryID
        notificationManager.deliverReminder(
            cycleID: cycleID,
            body: message,
            soundEnabled: settings.soundEnabled
        ) { [weak self] delivered in
            guard let self, self.pendingDeliveryID == deliveryID else { return }
            self.pendingDeliveryID = nil
            let completionDate = max(self.nowProvider(), self.now)

            if delivered,
               self.settingsStore.settings.remindersEnabled,
               SchedulePolicy.isAllowed(completionDate, settings: self.settingsStore.settings),
               self.hasFullResponseWindow(startingAt: completionDate) {
                let deadline = completionDate.addingTimeInterval(ReminderTiming.responseWindow)
                if self.establishReminderCycle(id: cycleID, at: completionDate, responseDeadline: deadline) {
                    self.phase = .awaitingResponse
                    self.state = .due
                    self.nextReminderAt = deadline
                }
            } else {
                self.deliveryBlocked = true
                self.phase = .overdue
                self.state = .due
                self.nextReminderAt = nil
            }
            self.publishWidgetSnapshot()
        }
    }

    private func handleReminderAction(_ action: ReminderAction) {
        switch action {
        case .completed:
            startActivity()
        case .snoozed:
            snooze()
        case .pausedToday:
            pauseToday()
        case .dismissed:
            if phase == .guiding {
                let actionDate = nowProvider()
                resolveActiveReminder(as: .skipped, at: actionDate)
                cancelGuide()
                clearActiveReminder()
                refreshScheduleState(at: actionDate)
                publishWidgetSnapshot()
            } else {
                clearActiveReminder()
            }
        }
    }

    private func settingsDidChange(from oldSettings: AppSettings, to newSettings: AppSettings) {
        if newSettings.notificationsEnabled && !oldSettings.notificationsEnabled {
            notificationManager.requestAuthorizationIfNeeded()
        }
        if newSettings.notificationsEnabled != oldSettings.notificationsEnabled
            || newSettings.popupEnabled != oldSettings.popupEnabled {
            deliveryBlocked = false
        }

        if !newSettings.remindersEnabled {
            pendingDeliveryID = nil
            let actionDate = nowProvider()
            cancelGuide()
            _ = statsStore.settlePendingReminderCycles(outcome: .skipped, at: actionDate)
            activeReminderCycle = nil
            clearActiveReminder()
            clearPauseState()
            nextReminderAt = nil
            state = .disabled
            phase = .disabled
            resetCadence()
            publishWidgetSnapshot()
            return
        }

        if !oldSettings.remindersEnabled {
            _ = statsStore.settlePendingReminderCycles(outcome: .skipped, at: nowProvider())
            activeReminderCycle = nil
        }

        if newSettings.hasReminderScheduleChange(comparedTo: oldSettings) {
            if isPaused {
                state = .paused(until: pauseUntil)
            } else {
                let actionDate = nowProvider()
                cancelGuide()
                resolveActiveReminder(as: .expired, at: actionDate)
                resetCadence()
                lastTickAt = actionDate
                refreshScheduleState(at: actionDate)
            }
        }

        if newSettings.dailyTarget != oldSettings.dailyTarget {
            updateTodaySnapshot(at: nowProvider())
        }

        publishWidgetSnapshot()
    }

    private func scheduleNextReminder(from baseDate: Date) {
        resetCadence()
        lastTickAt = baseDate
        refreshScheduleState(at: baseDate)
    }

    private func showCelebration(manual: Bool = false) {
        celebrationTask?.cancel()
        celebrationText = manual ? "已记录一次自主活动。" : ReminderMessages.randomCelebration()

        celebrationTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            celebrationText = nil
        }
    }

    private func establishReminderCycle(id: UUID, at date: Date, responseDeadline: Date) -> Bool {
        guard statsStore.beginReminderCycle(
            id: id,
            at: date,
            responseDeadline: responseDeadline
        ) else { return false }
        activeReminderCycle = statsStore.latestPendingCycle
        return activeReminderCycle?.id == id
    }

    private func restorePendingReminderCycle(at date: Date) {
        guard let pendingCycle = statsStore.latestPendingCycle else {
            activeReminderCycle = nil
            return
        }

        // Cycles written by older builds had no persisted deadline. Reconstruct
        // the original ten-minute response window without granting a new one.
        var restoredCycle = pendingCycle
        if restoredCycle.responseDeadline == nil {
            let legacyDeadline = restoredCycle.lastPresentedAt.addingTimeInterval(ReminderTiming.responseWindow)
            _ = statsStore.markReminderCyclePresented(
                id: restoredCycle.id,
                at: restoredCycle.lastPresentedAt,
                responseDeadline: legacyDeadline
            )
            restoredCycle = statsStore.latestPendingCycle ?? restoredCycle
        }

        let isCurrentDay = Calendar.current.isDate(restoredCycle.firstTriggeredAt, inSameDayAs: date)
        guard isCurrentDay,
              SchedulePolicy.isContinuouslyAllowed(
                from: restoredCycle.lastPresentedAt,
                through: date,
                settings: settingsStore.settings
              ) else {
            _ = statsStore.resolveReminderCycle(id: restoredCycle.id, outcome: .expired, at: date)
            activeReminderCycle = nil
            return
        }

        if restoredCycle.guideStartedAt != nil {
            _ = statsStore.resolveReminderCycle(id: restoredCycle.id, outcome: .expired, at: date)
            activeReminderCycle = nil
            accumulatedEligibleSeconds = reminderThreshold
            opportunityCooldownSeconds = reminderThreshold
            return
        }

        activeReminderCycle = restoredCycle
        if let snoozedUntil = restoredCycle.snoozedUntil, snoozedUntil > date {
            nextReminderAt = snoozedUntil
            phase = .snoozed
            return
        }

        if restoredCycle.snoozedUntil != nil {
            nextReminderAt = restoredCycle.snoozedUntil
            return
        }

        if let cycleDeadline = restoredCycle.responseDeadline,
           cycleDeadline >= date,
           Calendar.current.isDate(restoredCycle.firstTriggeredAt, inSameDayAs: date) {
            nextReminderAt = cycleDeadline
            phase = .awaitingResponse
        } else {
            _ = statsStore.resolveReminderCycle(
                id: restoredCycle.id,
                outcome: .expired,
                at: date
            )
            activeReminderCycle = nil
            accumulatedEligibleSeconds = reminderThreshold
            opportunityCooldownSeconds = reminderThreshold
        }
    }

    private func expireActiveReminderIfNeeded(at date: Date, settings: AppSettings) {
        guard let cycle = activeReminderCycle else { return }

        let isCurrentDay = Calendar.current.isDate(cycle.firstTriggeredAt, inSameDayAs: date)
        guard !isCurrentDay || !SchedulePolicy.isAllowed(date, settings: settings) else { return }

        resolveActiveReminder(as: .expired, at: date)
        clearActiveReminder()
    }

    private func resolveActiveReminder(as outcome: ReminderCycleOutcome, at date: Date) {
        pendingDeliveryID = nil
        guard let cycle = activeReminderCycle else { return }
        notificationManager.cancelReminder(cycleID: cycle.id)
        _ = statsStore.resolveReminderCycle(id: cycle.id, outcome: outcome, at: date)
        activeReminderCycle = nil
    }

    private func publishWidgetSnapshot() {
        widgetSyncController.publish(
            settings: settingsStore.settings,
            stats: statsStore.today,
            nextReminderAt: nextReminderAt,
            state: state,
            phase: phase,
            accumulatedEligibleSeconds: accumulatedEligibleSeconds,
            responseDeadline: activeReminderCycle?.responseDeadline,
            snoozedUntil: activeReminderCycle?.snoozedUntil,
            guideStartedAt: guideStartedAt,
            statusText: statusText,
            now: now
        )
    }

    private func clearActiveReminder() {
        reminderPresenter.dismiss()
        reminderShowing = false
        currentReminderText = nil
    }

    private func restorePauseState(at date: Date) {
        setPauseState(sessionStateStore.load(at: date), persist: false)
    }

    private func setPauseState(_ pauseState: ReminderPauseState, persist: Bool = true) {
        switch pauseState {
        case .none:
            isPaused = false
            pauseUntil = nil
        case .indefinite:
            isPaused = true
            pauseUntil = nil
            nextReminderAt = nil
            state = .paused(until: nil)
            phase = .paused
        case .until(let date):
            isPaused = true
            pauseUntil = date
            nextReminderAt = date
            state = .paused(until: date)
            phase = .paused
        }

        if persist {
            sessionStateStore.save(pauseState)
        }
    }

    private func clearPauseState() {
        setPauseState(.none)
    }

    private var reminderThreshold: TimeInterval {
        TimeInterval(max(settingsStore.settings.intervalMinutes, 1) * 60)
    }

    private var hasAnyDeliveryChannel: Bool {
        settingsStore.settings.popupEnabled || settingsStore.settings.notificationsEnabled
    }

    private func hasFullResponseWindow(startingAt date: Date) -> Bool {
        SchedulePolicy.isContinuouslyAllowed(
            from: date,
            through: date.addingTimeInterval(ReminderTiming.responseWindow),
            settings: settingsStore.settings
        )
    }

    private func handleNotificationAction(_ action: ReminderNotificationAction) {
        switch action {
        case .startActivity(let cycleID):
            startActivity(cycleID: cycleID)
        case .snooze(let cycleID):
            guard activeReminderCycle?.id == cycleID else { return }
            snooze()
        }
    }

    private func redeliverSnoozedCycle(_ cycle: ReminderCycleRecord, at date: Date) {
        guard cycle.snoozeCount == 1,
              hasFullResponseWindow(startingAt: date) else {
            expireOpportunity(at: date)
            return
        }
        let deadline = date.addingTimeInterval(ReminderTiming.responseWindow)
        guard statsStore.markReminderCyclePresented(
            id: cycle.id,
            at: date,
            responseDeadline: deadline
        ) else { return }
        activeReminderCycle = statsStore.latestPendingCycle
        let message = ReminderMessages.reminder
        if settingsStore.settings.notificationsEnabled {
            notificationManager.deliverReminder(
                cycleID: cycle.id,
                body: message,
                soundEnabled: settingsStore.settings.soundEnabled
            ) { _ in }
        }
        if settingsStore.settings.popupEnabled {
            reminderShowing = true
            currentReminderText = message
            reminderPresenter.present(message: message) { [weak self] action in
                self?.handleReminderAction(action)
            }
        }
        phase = .awaitingResponse
        state = .due
        nextReminderAt = deadline
    }

    private func expireOpportunity(at date: Date) {
        resolveActiveReminder(as: .expired, at: date)
        clearActiveReminder()
        accumulatedEligibleSeconds = reminderThreshold
        opportunityCooldownSeconds = reminderThreshold
        phase = .overdue
        state = .due
        nextReminderAt = date.addingTimeInterval(reminderThreshold)
        persistRuntimeCheckpoint()
    }

    private func completeGuidedActivity(at date: Date) {
        let wasProactive = guideCycleID == nil
        guard let activityID = guideActivityID,
              let startedAt = guideStartedAt,
              statsStore.completeGuidedActivity(
                activityID: activityID,
                cycleID: guideCycleID,
                guideStartedAt: startedAt,
                completedAt: date
              ) else {
            return
        }
        if let cycleID = guideCycleID {
            notificationManager.cancelReminder(cycleID: cycleID)
        }
        activeReminderCycle = nil
        cancelGuide()
        clearActiveReminder()
        resetCadence()
        lastTickAt = date
        lastTickWasAllowed = SchedulePolicy.isAllowed(date, settings: settingsStore.settings)
        showCelebration(manual: wasProactive)
        ReminderAccessibility.announce("活动完成")
        refreshScheduleState(at: date)
        updateTodaySnapshot(at: date)
        persistRuntimeCheckpoint()
    }

    private func cancelGuide() {
        guideActivityID = nil
        guideCycleID = nil
        guideStartedAt = nil
        guideElapsedSeconds = 0
        announcedGuideMilestones.removeAll()
    }

    private func resetCadence() {
        accumulatedEligibleSeconds = 0
        opportunityCooldownSeconds = 0
        deliveryBlocked = false
        nextReminderAt = nil
        lastPersistedCheckpoint = nil
        persistRuntimeCheckpoint()
    }

    private func refreshScheduleState(at date: Date) {
        now = date
        guard settingsStore.settings.remindersEnabled else {
            state = .disabled
            phase = .disabled
            nextReminderAt = nil
            return
        }
        guard !isPaused else {
            state = .paused(until: pauseUntil)
            phase = .paused
            return
        }
        guard SchedulePolicy.isAllowed(date, settings: settingsStore.settings) else {
            state = .outsideHours
            phase = .outsideSchedule
            nextReminderAt = nextFreshReminderDate(after: date)
            return
        }
        if let cycle = activeReminderCycle {
            if let snoozedUntil = cycle.snoozedUntil {
                state = .running
                phase = .snoozed
                nextReminderAt = snoozedUntil
            } else {
                state = .due
                phase = .awaitingResponse
                nextReminderAt = cycle.responseDeadline
            }
            return
        }
        state = .running
        phase = accumulatedEligibleSeconds >= reminderThreshold ? .overdue : .accumulating
        refreshNextReminderDate(at: date)
    }

    private func refreshNextReminderDate(at date: Date) {
        let remaining = max(reminderThreshold - accumulatedEligibleSeconds, 0)
        let candidate = date.addingTimeInterval(remaining)
        if SchedulePolicy.isContinuouslyAllowed(
            from: date,
            through: candidate.addingTimeInterval(ReminderTiming.responseWindow),
            settings: settingsStore.settings
        ) {
            nextReminderAt = candidate
        } else {
            nextReminderAt = nextFreshReminderDate(after: date)
            state = .outsideHours
        }
    }

    private func nextFreshReminderDate(after date: Date) -> Date? {
        var cursor = date
        for _ in 0..<21 {
            guard let nextAllowed = SchedulePolicy.nextAllowedDate(
                onOrAfter: cursor,
                settings: settingsStore.settings
            ) else { return nil }
            let candidate = nextAllowed.addingTimeInterval(reminderThreshold)
            if hasFullResponseWindow(startingAt: candidate) {
                return candidate
            }
            guard let nextDay = Calendar.current.date(
                byAdding: .day,
                value: 1,
                to: Calendar.current.startOfDay(for: nextAllowed)
            ) else { return nil }
            cursor = nextDay
        }
        return nil
    }

    private func persistRuntimeCheckpoint() {
        let checkpoint = ReminderRuntimeCheckpoint(
            accumulatedEligibleSeconds: min(max(accumulatedEligibleSeconds, 0), reminderThreshold),
            opportunityCooldownSeconds: min(max(opportunityCooldownSeconds, 0), reminderThreshold)
        )
        if let previous = lastPersistedCheckpoint,
           abs(previous.accumulatedEligibleSeconds - checkpoint.accumulatedEligibleSeconds) < 15,
           abs(previous.opportunityCooldownSeconds - checkpoint.opportunityCooldownSeconds) < 15 {
            return
        }
        sessionStateStore.saveCheckpoint(checkpoint)
        lastPersistedCheckpoint = checkpoint
    }

    private func updateTodaySnapshot(
        at date: Date,
        eligibility override: ActivityDayEligibility? = nil
    ) {
        let eligibility: ActivityDayEligibility
        if let override {
            eligibility = override
        } else if settingsStore.settings.workdaysOnly && Calendar.current.isDateInWeekend(date) {
            eligibility = .nonWorkday
        } else if isPaused {
            eligibility = .paused
        } else {
            eligibility = .scheduled
        }
        _ = statsStore.updateDaySnapshot(
            at: date,
            dailyTarget: settingsStore.settings.dailyTarget,
            eligibility: eligibility
        )
    }

    private func announceGuideMilestonesIfNeeded() {
        if guideElapsedSeconds >= 30, announcedGuideMilestones.insert(30).inserted {
            ReminderAccessibility.announce("活动已进行 30 秒")
        }
        if guideElapsedSeconds >= 50, announcedGuideMilestones.insert(50).inserted {
            ReminderAccessibility.announce("还剩 10 秒")
        }
    }

    func systemWillSleep(at date: Date = Date()) {
        guard suspensionStartedAt == nil else { return }
        suspensionStartedAt = date
        suspensionIsSleep = true
        sessionStateStore.saveSuspension(startedAt: date, isSleep: true)
        tick(at: date)
    }

    func sessionDidBecomeInactive(at date: Date = Date()) {
        guard suspensionStartedAt == nil else { return }
        suspensionStartedAt = date
        suspensionIsSleep = false
        sessionStateStore.saveSuspension(startedAt: date, isSleep: false)
        tick(at: date)
    }

    func suspensionDidEnd(at date: Date = Date()) {
        guard let suspensionStartedAt else { return }
        let duration = max(date.timeIntervalSince(suspensionStartedAt), 0)
        let wasSleep = suspensionIsSleep
        self.suspensionStartedAt = nil
        suspensionIsSleep = false
        sessionStateStore.clearSuspension()

        if duration >= ReminderTiming.longSuspensionThreshold {
            resolveActiveReminder(as: .expired, at: date)
            cancelGuide()
            clearActiveReminder()
            resetCadence()
            phase = .accumulating
            state = .running
        } else {
            if !wasSleep, phase == .guiding {
                guideElapsedSeconds = min(
                    guideElapsedSeconds + duration,
                    ReminderTiming.guidedActivityDuration
                )
            }
            if let cycle = activeReminderCycle,
               statsStore.shiftReminderCycleWindow(id: cycle.id, by: duration) {
                activeReminderCycle = statsStore.latestPendingCycle
            }
        }
        lastTickAt = date
        lastTickWasAllowed = SchedulePolicy.isAllowed(date, settings: settingsStore.settings)
        tick(at: date)
    }
}

private enum ReminderMessages {
    static let reminder = "到活动时间了。按你的身体状况，换个姿势或活动 60 秒。"

    static let celebrations = [
        "完成一次活动 🎉",
        "完成 60 秒活动。",
        "很好，完成了一次活动。",
        "完成，继续按自己的节奏活动。",
        "60 秒活动已记录。"
    ]

    static func randomReminder() -> String {
        reminder
    }

    static func randomCelebration() -> String {
        celebrations.randomElement() ?? celebrations[0]
    }
}

enum SchedulePolicy {
    static func isAllowed(_ date: Date, settings: AppSettings, calendar: Calendar = .current) -> Bool {
        if settings.workdaysOnly && calendar.isDateInWeekend(date) {
            return false
        }

        let minutes = minutesSinceMidnight(for: date, calendar: calendar)
        guard minutes >= settings.workStartMinutes, minutes < settings.workEndMinutes else {
            return false
        }

        if settings.lunchPauseEnabled,
           minutes >= settings.lunchStartMinutes,
           minutes < settings.lunchEndMinutes {
            return false
        }

        return true
    }

    static func shouldDisplayCountdown(
        at date: Date,
        nextReminderAt: Date?,
        settings: AppSettings,
        calendar: Calendar = .current
    ) -> Bool {
        guard isAllowed(date, settings: settings, calendar: calendar),
              let nextReminderAt else {
            return false
        }

        return calendar.isDate(date, inSameDayAs: nextReminderAt)
    }

    static func isContinuouslyAllowed(
        from startDate: Date,
        through endDate: Date,
        settings: AppSettings,
        calendar: Calendar = .current
    ) -> Bool {
        guard endDate >= startDate,
              isAllowed(startDate, settings: settings, calendar: calendar),
              isAllowed(endDate, settings: settings, calendar: calendar),
              let interval = allowedDateInterval(
                containing: startDate,
                settings: settings,
                calendar: calendar
              ) else {
            return false
        }

        return endDate < interval.end
    }

    static func nextReminderDate(
        from baseDate: Date,
        settings: AppSettings,
        calendar: Calendar = .current
    ) -> Date? {
        guard !allowedIntervals(settings: settings).isEmpty else {
            return nil
        }

        return dateByAddingAllowedTime(
            TimeInterval(max(settings.intervalMinutes, 1) * 60),
            to: baseDate,
            settings: settings,
            calendar: calendar
        )
    }

    static func nextAllowedDate(
        onOrAfter date: Date,
        settings: AppSettings,
        calendar: Calendar = .current
    ) -> Date? {
        for dayOffset in 0..<21 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: date)) else {
                continue
            }

            if settings.workdaysOnly && calendar.isDateInWeekend(day) {
                continue
            }

            for interval in allowedIntervals(settings: settings) {
                guard let start = wallClockDate(
                    minutesSinceMidnight: interval.start,
                    on: day,
                    calendar: calendar
                ), let end = wallClockDate(
                    minutesSinceMidnight: interval.end,
                    on: day,
                    calendar: calendar
                ) else {
                    continue
                }

                if dayOffset == 0 {
                    if date <= start { return start }
                    if date < end { return date }
                } else {
                    return start
                }
            }
        }

        return nil
    }

    private static func dateByAddingAllowedTime(
        _ duration: TimeInterval,
        to date: Date,
        settings: AppSettings,
        calendar: Calendar
    ) -> Date? {
        var remaining = max(duration, 0)
        let initialCursor: Date?
        if isAllowed(date, settings: settings, calendar: calendar) {
            initialCursor = date
        } else {
            initialCursor = nextAllowedDate(onOrAfter: date, settings: settings, calendar: calendar)
        }
        guard var cursor = initialCursor else { return nil }

        for _ in 0..<90 {
            guard let allowedInterval = allowedDateInterval(
                containing: cursor,
                settings: settings,
                calendar: calendar
            ) else {
                guard let nextStart = nextAllowedDate(
                    onOrAfter: cursor,
                    settings: settings,
                    calendar: calendar
                ), nextStart > cursor else {
                    return nil
                }
                cursor = nextStart
                continue
            }

            let available = allowedInterval.end.timeIntervalSince(cursor)
            if remaining < available {
                return cursor.addingTimeInterval(remaining)
            }

            remaining -= max(available, 0)
            guard let nextStart = nextAllowedDate(
                onOrAfter: allowedInterval.end,
                settings: settings,
                calendar: calendar
            ), nextStart > cursor else {
                return nil
            }

            if remaining <= 0 {
                return nextStart
            }

            cursor = nextStart
        }

        return cursor
    }

    private static func allowedIntervals(settings: AppSettings) -> [(start: Int, end: Int)] {
        guard settings.lunchPauseEnabled,
              settings.lunchStartMinutes < settings.lunchEndMinutes,
              settings.lunchStartMinutes < settings.workEndMinutes,
              settings.lunchEndMinutes > settings.workStartMinutes else {
            return [(settings.workStartMinutes, settings.workEndMinutes)]
        }

        let lunchStart = max(settings.lunchStartMinutes, settings.workStartMinutes)
        let lunchEnd = min(settings.lunchEndMinutes, settings.workEndMinutes)
        var intervals: [(start: Int, end: Int)] = []

        if settings.workStartMinutes < lunchStart {
            intervals.append((settings.workStartMinutes, lunchStart))
        }
        if lunchEnd < settings.workEndMinutes {
            intervals.append((lunchEnd, settings.workEndMinutes))
        }

        return intervals
    }

    private static func allowedDateInterval(
        containing date: Date,
        settings: AppSettings,
        calendar: Calendar
    ) -> DateInterval? {
        let day = calendar.startOfDay(for: date)
        if settings.workdaysOnly && calendar.isDateInWeekend(day) {
            return nil
        }

        for interval in allowedIntervals(settings: settings) {
            guard let start = wallClockDate(
                minutesSinceMidnight: interval.start,
                on: day,
                calendar: calendar
            ), let end = wallClockDate(
                minutesSinceMidnight: interval.end,
                on: day,
                calendar: calendar
            ),
                  date >= start,
                  date < end else {
                continue
            }

            return DateInterval(start: start, end: end)
        }

        return nil
    }

    private static func wallClockDate(
        minutesSinceMidnight: Int,
        on day: Date,
        calendar: Calendar
    ) -> Date? {
        let startOfDay = calendar.startOfDay(for: day)
        if minutesSinceMidnight == 24 * 60 {
            return calendar.date(byAdding: .day, value: 1, to: startOfDay)
        }

        guard (0..<(24 * 60)).contains(minutesSinceMidnight) else { return nil }
        return calendar.date(
            bySettingHour: minutesSinceMidnight / 60,
            minute: minutesSinceMidnight % 60,
            second: 0,
            of: startOfDay
        )
    }

    private static func minutesSinceMidnight(for date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}
