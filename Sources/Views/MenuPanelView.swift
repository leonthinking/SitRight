import AppKit
import SwiftUI

enum TodayActionLayoutKind: Equatable {
    case running
    case awaitingResponse
    case snoozed
    case guiding
    case delivering
    case paused
    case outsideHours
    case disabled
}

enum TodayActionMode: Equatable {
    case running(canRecordManualActivity: Bool)
    case awaitingResponse(canSnooze: Bool)
    case snoozed(statusText: String)
    case guiding
    case delivering
    case paused
    case outsideHours
    case disabled

    var layoutKind: TodayActionLayoutKind {
        switch self {
        case .running:
            return .running
        case .awaitingResponse:
            return .awaitingResponse
        case .snoozed:
            return .snoozed
        case .guiding:
            return .guiding
        case .delivering:
            return .delivering
        case .paused:
            return .paused
        case .outsideHours:
            return .outsideHours
        case .disabled:
            return .disabled
        }
    }

    static func resolve(
        phase: ReminderPhase,
        state: ReminderRunState,
        canRecordManualActivity: Bool,
        canSnooze: Bool,
        snoozedStatusText: String
    ) -> TodayActionMode {
        switch state {
        case .disabled:
            return .disabled
        case .paused:
            return .paused
        case .outsideHours:
            return .outsideHours
        case .running, .due:
            break
        }

        switch phase {
        case .awaitingResponse:
            return .awaitingResponse(canSnooze: canSnooze)
        case .snoozed:
            return .snoozed(statusText: snoozedStatusText)
        case .guiding:
            return .guiding
        case .delivering:
            return .delivering
        case .paused:
            return .paused
        case .outsideSchedule:
            return .outsideHours
        case .disabled:
            return .disabled
        case .accumulating, .overdue:
            return .running(canRecordManualActivity: canRecordManualActivity)
        }
    }
}

enum TimerRingPresentationText {
    static func contextLabel(
        phase: ReminderPhase,
        state: ReminderRunState
    ) -> String {
        switch state {
        case .paused:
            return "提醒状态"
        case .outsideHours:
            return "当前状态"
        case .disabled:
            return "提醒状态"
        case .running, .due:
            break
        }

        switch phase {
        case .accumulating:
            return "距离下次提醒"
        case .snoozed:
            return "已延后"
        case .delivering:
            return "正在准备提醒"
        case .awaitingResponse, .guiding, .overdue:
            return "活动提醒"
        case .paused:
            return "提醒状态"
        case .outsideSchedule:
            return "当前状态"
        case .disabled:
            return "提醒状态"
        }
    }

    static func subtitle(
        phase: ReminderPhase,
        nextReminderAt: Date?,
        isProactiveGuide: Bool = false
    ) -> String {
        let timeText = nextReminderAt?.formatted(date: .omitted, time: .shortened)

        switch phase {
        case .accumulating:
            return timeText.map { "下次 \($0)" } ?? "还没有安排下一次提醒"
        case .delivering:
            return "正在准备本次提醒"
        case .awaitingResponse:
            return timeText.map { "请在 \($0) 前开始" } ?? "请尽快开始本次活动"
        case .snoozed:
            return timeText.map { "延后至 \($0)" } ?? "本次提醒已延后"
        case .guiding:
            return isProactiveGuide ? "主动活动，提醒节奏继续" : "完成后开始下一轮"
        case .overdue:
            return timeText.map { "等待至 \($0)" } ?? "等待下次可用提醒"
        case .paused:
            return "恢复后重新计时"
        case .outsideSchedule:
            return timeText.map { "下次 \($0)" } ?? "等待进入提醒时段"
        case .disabled:
            return "可在设置中开启"
        }
    }
}

struct MenuPanelPresentation: Equatable {
    let statusText: String
    let statusSystemImage: String
    let isCelebrating: Bool
    let timerContextLabel: String
    let countdownText: String
    let nextReminderText: String
    let progressFraction: Double
    let state: ReminderRunState
    let phase: ReminderPhase
    let currentReminderText: String?
    let actionMode: TodayActionMode

    @MainActor
    init(engine: ReminderEngine) {
        let celebrationText = engine.celebrationText
        statusText = celebrationText ?? engine.statusText
        statusSystemImage = celebrationText == nil ? engine.statusSystemImage : "sparkles"
        isCelebrating = celebrationText != nil
        timerContextLabel = TimerRingPresentationText.contextLabel(
            phase: engine.phase,
            state: engine.state
        )
        countdownText = engine.countdownText
        nextReminderText = TimerRingPresentationText.subtitle(
            phase: engine.phase,
            nextReminderAt: engine.nextReminderAt,
            isProactiveGuide: engine.isProactiveGuide
        )
        progressFraction = engine.progressFraction
        state = engine.state
        phase = engine.phase
        currentReminderText = engine.currentReminderText
        actionMode = TodayActionMode.resolve(
            phase: engine.phase,
            state: engine.state,
            canRecordManualActivity: engine.canRecordManualActivity,
            canSnooze: engine.canSnooze,
            snoozedStatusText: engine.countdownText
        )
    }
}

struct MenuPanelLayoutSignature: Equatable {
    let actionKind: TodayActionLayoutKind
    let hasCurrentReminder: Bool
    let hasStatsError: Bool
    let showsActivityBreakdown: Bool
    let showsLegacyRecords: Bool
    let showsResponseRate: Bool
    let showsAvailableUpdate: Bool

    @MainActor
    init(
        engine: ReminderEngine,
        statsStore: StatsStore,
        showsAvailableUpdate: Bool = false
    ) {
        let presentation = MenuPanelPresentation(engine: engine)
        let today = statsStore.today

        actionKind = presentation.actionMode.layoutKind
        hasCurrentReminder = presentation.currentReminderText != nil
        hasStatsError = statsStore.lastErrorMessage != nil
        showsActivityBreakdown =
            today.reminderOpportunityCount > 0 ||
            today.dailyGoalActivityCount > 0 ||
            today.reminderCompletedCount > 0 ||
            today.qualifiedProactiveCount > 0 ||
            today.legacyUnclassifiedCount > 0
        showsLegacyRecords = today.legacyUnclassifiedCount > 0
        showsResponseRate = today.reminderOpportunityCount > 0
        self.showsAvailableUpdate = showsAvailableUpdate
    }

    init(
        actionKind: TodayActionLayoutKind,
        hasCurrentReminder: Bool,
        hasStatsError: Bool,
        showsActivityBreakdown: Bool,
        showsLegacyRecords: Bool,
        showsResponseRate: Bool,
        showsAvailableUpdate: Bool = false
    ) {
        self.actionKind = actionKind
        self.hasCurrentReminder = hasCurrentReminder
        self.hasStatsError = hasStatsError
        self.showsActivityBreakdown = showsActivityBreakdown
        self.showsLegacyRecords = showsLegacyRecords
        self.showsResponseRate = showsResponseRate
        self.showsAvailableUpdate = showsAvailableUpdate
    }
}

struct MenuPanelView: View {
    @Environment(\.openSettings) private var openSettings
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var statsStore: StatsStore
    @EnvironmentObject private var updateController: UpdateController
    @ObservedObject private var refreshController: MenuPanelRefreshController

    @AppStorage(SettingsSelection.defaultsKey)
    private var selectedSettingsPane: SettingsPane = .general
    @AppStorage(SettingsSelection.requestedSectionDefaultsKey)
    private var requestedSettingsSectionRawValue = ""

    private let engine: ReminderEngine
    private let onRequestClose: () -> Void

    init(
        engine: ReminderEngine,
        refreshController: MenuPanelRefreshController,
        onRequestClose: @escaping () -> Void = {}
    ) {
        self.engine = engine
        self.refreshController = refreshController
        self.onRequestClose = onRequestClose
    }

    var body: some View {
        let presentation = MenuPanelPresentation(engine: engine)
        let progressPresentation = TodayProgressPresentation(
            dailyGoalCompleted: statsStore.today.dailyGoalActivityCount,
            reminderCompleted: statsStore.today.reminderCompletedCount,
            target: settingsStore.settings.dailyTarget,
            reminderOpportunities: statsStore.today.reminderOpportunityCount,
            responseRate: statsStore.today.responseRate,
            proactiveActivities: statsStore.today.qualifiedProactiveCount,
            legacyUnclassified: statsStore.today.legacyUnclassifiedCount,
            subtitle: statsStore.lastCompletedText
        )

        ViewThatFits(in: .vertical) {
            panelLayout(
                presentation: presentation,
                progressPresentation: progressPresentation,
                scrollsTodayContent: false
            )
            .fixedSize(horizontal: false, vertical: true)

            panelLayout(
                presentation: presentation,
                progressPresentation: progressPresentation,
                scrollsTodayContent: true
            )
        }
        .frame(width: 370)
        .onExitCommand {
            onRequestClose()
        }
    }

    private func panelLayout(
        presentation: MenuPanelPresentation,
        progressPresentation: TodayProgressPresentation,
        scrollsTodayContent: Bool
    ) -> some View {
        VStack(spacing: 14) {
            header(presentation)

            if let availableVersion = updateController.availableVersion {
                availableUpdate(version: availableVersion)
            }

            if scrollsTodayContent {
                ScrollView {
                    todayContent(
                        presentation: presentation,
                        progressPresentation: progressPresentation
                    )
                    .padding(.trailing, 4)
                }
            } else {
                todayContent(
                    presentation: presentation,
                    progressPresentation: progressPresentation
                )
            }

            Divider()

            footer
        }
        .padding(16)
    }

    private func todayContent(
        presentation: MenuPanelPresentation,
        progressPresentation: TodayProgressPresentation
    ) -> some View {
        TodayPanelView(
            engine: engine,
            presentation: presentation,
            progressPresentation: progressPresentation,
            statsErrorMessage: statsStore.lastErrorMessage,
            onOpenSettings: presentSettings
        )
    }

    private func header(_ presentation: MenuPanelPresentation) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(headerColor(for: presentation).opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: presentation.statusSystemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(headerColor(for: presentation))
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("SitRight 坐正")
                    .font(.headline)
                Text(presentation.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private func availableUpdate(version: String) -> some View {
        Button {
            onRequestClose()
            DispatchQueue.main.async {
                NSApplication.shared.activate(ignoringOtherApps: true)
                updateController.checkForUpdates()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("发现 SitRight v\(version)")
                        .font(.subheadline.weight(.semibold))
                    Text("查看更新说明并选择是否安装")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(10)
            .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("发现 SitRight \(version) 版本更新")
        .accessibilityHint("打开更新窗口")
    }

    private var footer: some View {
        HStack {
            Button {
                presentSettings(nil)
            } label: {
                Label("设置…", systemImage: "gearshape")
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("退出", systemImage: "power")
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.secondary)
    }

    private func presentSettings(_ pane: SettingsPane?) {
        if let pane {
            let route = SettingsSelection.route(for: pane)
            selectedSettingsPane = route.visiblePane
            requestedSettingsSectionRawValue = route.requestedSection?.rawValue ?? ""
        }
        onRequestClose()
        openSettings()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func headerColor(for presentation: MenuPanelPresentation) -> Color {
        if presentation.isCelebrating {
            return .orange
        }

        switch presentation.state {
        case .running:
            return .green
        case .paused:
            return .orange
        case .outsideHours:
            return .indigo
        case .disabled:
            return .secondary
        case .due:
            return .blue
        }
    }
}
