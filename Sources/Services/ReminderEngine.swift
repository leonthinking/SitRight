import Foundation

enum ReminderRunState: Equatable {
    case running
    case paused(until: Date?)
    case outsideHours
    case disabled
    case due
}

@MainActor
final class ReminderEngine: ObservableObject {
    @Published private(set) var now = Date()
    @Published private(set) var nextReminderAt: Date?
    @Published private(set) var state: ReminderRunState = .running
    @Published private(set) var currentReminderText: String?
    @Published private(set) var celebrationText: String?

    private let settingsStore: SettingsStore
    private let statsStore: StatsStore
    private let notificationManager: NotificationManager
    private let reminderPresenter: ReminderPresenter
    private let widgetSyncController: WidgetSyncController

    private var timer: Timer?
    private var pauseUntil: Date?
    private var reminderShowing = false
    private var celebrationTask: Task<Void, Never>?

    init(
        settingsStore: SettingsStore,
        statsStore: StatsStore,
        notificationManager: NotificationManager,
        reminderPresenter: ReminderPresenter,
        widgetSyncController: WidgetSyncController
    ) {
        self.settingsStore = settingsStore
        self.statsStore = statsStore
        self.notificationManager = notificationManager
        self.reminderPresenter = reminderPresenter
        self.widgetSyncController = widgetSyncController

        self.settingsStore.onSettingsChanged = { [weak self] in
            self?.settingsDidChange()
        }
    }

    func start() {
        notificationManager.requestAuthorizationIfNeeded()
        scheduleNextReminder(from: Date())
        publishWidgetSnapshot()

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    func markCompleted() {
        reminderPresenter.dismiss()
        reminderShowing = false
        currentReminderText = nil

        statsStore.markCompleted()
        showCelebration()
        scheduleNextReminder(from: Date())
        publishWidgetSnapshot()
    }

    func snooze(minutes: Int = 10) {
        reminderPresenter.dismiss()
        reminderShowing = false
        currentReminderText = nil

        statsStore.markPostponed()
        nextReminderAt = Date().addingTimeInterval(TimeInterval(minutes * 60))
        state = .running
        publishWidgetSnapshot()
    }

    func pause(minutes: Int? = nil) {
        let until = minutes.map { Date().addingTimeInterval(TimeInterval($0 * 60)) }
        pauseUntil = until
        state = .paused(until: until)
        publishWidgetSnapshot()
    }

    func pauseToday() {
        reminderPresenter.dismiss()
        reminderShowing = false
        currentReminderText = nil

        let tomorrow = Calendar.current.date(
            byAdding: .day,
            value: 1,
            to: Calendar.current.startOfDay(for: Date())
        )
        pauseUntil = tomorrow
        nextReminderAt = tomorrow
        state = .paused(until: tomorrow)
        publishWidgetSnapshot()
    }

    func resume() {
        pauseUntil = nil
        scheduleNextReminder(from: Date())
        publishWidgetSnapshot()
    }

    func resetTimer() {
        reminderPresenter.dismiss()
        reminderShowing = false
        currentReminderText = nil
        scheduleNextReminder(from: Date())
        publishWidgetSnapshot()
    }

    var remainingInterval: TimeInterval {
        guard let nextReminderAt else { return 0 }
        return max(nextReminderAt.timeIntervalSince(now), 0)
    }

    var countdownText: String {
        switch state {
        case .paused:
            return "已暂停"
        case .disabled:
            return "已关闭"
        case .due:
            return "该活动了"
        case .outsideHours:
            return nextReminderAt == nil ? "非工作时间" : TimeFormatting.countdown(remainingInterval)
        case .running:
            return TimeFormatting.countdown(remainingInterval)
        }
    }

    var menuBarTitle: String {
        switch state {
        case .paused:
            return "Paused"
        case .disabled:
            return "Off"
        case .due:
            return "Move"
        case .outsideHours:
            return "Rest"
        case .running:
            return TimeFormatting.menuBarCountdown(remainingInterval)
        }
    }

    var statusText: String {
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
            return "该起身活动了"
        }
    }

    var statusSystemImage: String {
        switch state {
        case .running:
            return "figure.stand"
        case .paused:
            return "pause.circle"
        case .outsideHours:
            return "moon"
        case .disabled:
            return "power"
        case .due:
            return "figure.walk"
        }
    }

    var progressFraction: Double {
        guard case .running = state,
              settingsStore.settings.intervalMinutes > 0 else {
            return 0
        }

        let total = TimeInterval(settingsStore.settings.intervalMinutes * 60)
        return min(max(1 - remainingInterval / total, 0), 1)
    }

    var nextReminderText: String {
        guard let nextReminderAt else { return "还没有安排下一次提醒" }
        return "下次 \(nextReminderAt.formatted(date: .omitted, time: .shortened))"
    }

    private func tick() {
        now = Date()
        statsStore.refreshForCurrentDay()
        defer { publishWidgetSnapshot() }

        let settings = settingsStore.settings
        guard settings.remindersEnabled else {
            state = .disabled
            return
        }

        if let pauseUntil {
            if now >= pauseUntil {
                self.pauseUntil = nil
                scheduleNextReminder(from: now)
            } else {
                state = .paused(until: pauseUntil)
                return
            }
        }

        if reminderShowing {
            state = .due
            return
        }

        if nextReminderAt == nil {
            scheduleNextReminder(from: now)
        }

        guard let nextReminderAt else { return }

        if now >= nextReminderAt {
            if SchedulePolicy.isAllowed(now, settings: settings) {
                fireReminder()
            } else {
                scheduleNextReminder(from: now)
            }
            return
        }

        state = SchedulePolicy.isAllowed(now, settings: settings) ? .running : .outsideHours
    }

    private func fireReminder() {
        reminderShowing = true
        state = .due

        let message = ReminderMessages.randomReminder()
        currentReminderText = message

        let settings = settingsStore.settings
        if settings.notificationsEnabled {
            notificationManager.deliverReminder(body: message, soundEnabled: settings.soundEnabled)
        }

        if settings.popupEnabled {
            reminderPresenter.present(message: message) { [weak self] action in
                self?.handleReminderAction(action)
            }
        } else {
            reminderShowing = false
            scheduleNextReminder(from: Date())
        }
    }

    private func handleReminderAction(_ action: ReminderAction) {
        switch action {
        case .completed:
            markCompleted()
        case .snoozed:
            snooze()
        case .pausedToday:
            pauseToday()
        }
    }

    private func settingsDidChange() {
        notificationManager.requestAuthorizationIfNeeded()
        scheduleNextReminder(from: Date())
        publishWidgetSnapshot()
    }

    private func scheduleNextReminder(from baseDate: Date) {
        let settings = settingsStore.settings

        guard settings.remindersEnabled else {
            nextReminderAt = nil
            state = .disabled
            return
        }

        let interval = TimeInterval(settings.intervalMinutes * 60)
        let baseAllowed = SchedulePolicy.isAllowed(baseDate, settings: settings)
        let candidate: Date

        if baseAllowed {
            candidate = baseDate.addingTimeInterval(interval)
        } else {
            let nextStart = SchedulePolicy.nextAllowedDate(onOrAfter: baseDate, settings: settings)
            candidate = nextStart.addingTimeInterval(interval)
        }

        if SchedulePolicy.isAllowed(candidate, settings: settings) {
            nextReminderAt = candidate
        } else {
            nextReminderAt = SchedulePolicy.nextAllowedDate(onOrAfter: candidate, settings: settings)
        }

        now = Date()
        state = SchedulePolicy.isAllowed(now, settings: settings) ? .running : .outsideHours
    }

    private func showCelebration() {
        celebrationTask?.cancel()
        celebrationText = ReminderMessages.randomCelebration()

        celebrationTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            celebrationText = nil
        }
    }

    private func publishWidgetSnapshot() {
        widgetSyncController.publish(
            settings: settingsStore.settings,
            stats: statsStore.today,
            nextReminderAt: nextReminderAt,
            state: state,
            statusText: statusText,
            now: now
        )
    }
}

private enum ReminderMessages {
    static let reminders = [
        "抬头挺胸、起身活动",
        "肩颈放松一下，站起来走一走",
        "看远一点，给眼睛和背部一个短休息",
        "身体换个姿势，坐正再继续",
        "站起来活动 1 分钟，回来会更清醒"
    ]

    static let celebrations = [
        "完成一次活动 🎉",
        "很好，身体收到一次照顾。",
        "抬头挺胸完成一次。",
        "今天的肩颈少受一点罪。",
        "完成，继续保持轻松坐姿。"
    ]

    static func randomReminder() -> String {
        reminders.randomElement() ?? reminders[0]
    }

    static func randomCelebration() -> String {
        celebrations.randomElement() ?? celebrations[0]
    }
}

private enum SchedulePolicy {
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

    static func nextAllowedDate(onOrAfter date: Date, settings: AppSettings, calendar: Calendar = .current) -> Date {
        for dayOffset in 0..<21 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: date)) else {
                continue
            }

            if settings.workdaysOnly && calendar.isDateInWeekend(day) {
                continue
            }

            for interval in allowedIntervals(settings: settings) {
                guard let start = calendar.date(byAdding: .minute, value: interval.start, to: day),
                      let end = calendar.date(byAdding: .minute, value: interval.end, to: day) else {
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

        return date
    }

    private static func allowedIntervals(settings: AppSettings) -> [(start: Int, end: Int)] {
        guard settings.lunchPauseEnabled,
              settings.lunchStartMinutes > settings.workStartMinutes,
              settings.lunchEndMinutes < settings.workEndMinutes,
              settings.lunchStartMinutes < settings.lunchEndMinutes else {
            return [(settings.workStartMinutes, settings.workEndMinutes)]
        }

        return [
            (settings.workStartMinutes, settings.lunchStartMinutes),
            (settings.lunchEndMinutes, settings.workEndMinutes)
        ]
    }

    private static func minutesSinceMidnight(for date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}
