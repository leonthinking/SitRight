import AppKit
import SwiftUI
import UserNotifications

enum SettingsPane: String {
    case general
    case schedule
    case notifications
}

enum SettingsSectionDestination: String {
    case workSchedule
}

struct SettingsRoute: Equatable {
    let visiblePane: SettingsPane
    let requestedSection: SettingsSectionDestination?
}

enum SettingsSelection {
    static let defaultsKey = "sitright.settings.selectedPane"
    static let requestedSectionDefaultsKey = "sitright.settings.requestedSection"

    static func route(for pane: SettingsPane) -> SettingsRoute {
        switch pane {
        case .general:
            return SettingsRoute(visiblePane: .general, requestedSection: nil)
        case .schedule:
            return SettingsRoute(
                visiblePane: .general,
                requestedSection: .workSchedule
            )
        case .notifications:
            return SettingsRoute(visiblePane: .notifications, requestedSection: nil)
        }
    }

    static func visiblePane(for pane: SettingsPane) -> SettingsPane {
        route(for: pane).visiblePane
    }
}

struct SettingsSectionRequestState {
    private(set) var rawValue: String

    mutating func consume() -> SettingsSectionDestination? {
        guard let destination = SettingsSectionDestination(rawValue: rawValue) else {
            return nil
        }
        rawValue = ""
        return destination
    }
}

private enum SettingsFocusTarget: Hashable {
    case workdaysOnly
}

enum ReminderIntervalChoice: Hashable {
    case preset(Int)
    case custom

    static let presetMinutes = [30, 45, 50, 60]

    static func selection(for minutes: Int) -> ReminderIntervalChoice {
        presetMinutes.contains(minutes) ? .preset(minutes) : .custom
    }

    var minuteValue: Int? {
        guard case .preset(let minutes) = self else { return nil }
        return minutes
    }
}

enum TimePickerOptions {
    static func values(
        in range: ClosedRange<Int>,
        step: Int,
        including selection: Int
    ) -> [Int] {
        let safeStep = max(step, 1)
        var values = Array(
            stride(
                from: range.lowerBound,
                through: range.upperBound,
                by: safeStep
            )
        )
        values.append(range.upperBound)
        if range.contains(selection) {
            values.append(selection)
        }
        return Array(Set(values)).sorted()
    }
}

struct SettingsPanelView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var notificationManager: NotificationManager
    @EnvironmentObject private var launchAtLoginController: LaunchAtLoginController

    @AppStorage(SettingsSelection.defaultsKey)
    private var selectedPane: SettingsPane = .general
    @AppStorage(SettingsSelection.requestedSectionDefaultsKey)
    private var requestedSectionRawValue = ""
    @State private var intervalSelectionOverride: ReminderIntervalChoice?
    @FocusState private var focusedSetting: SettingsFocusTarget?
    @AccessibilityFocusState private var accessibilityFocusedSetting: SettingsFocusTarget?

    var body: some View {
        TabView(selection: visiblePaneSelection) {
            generalPane
                .tabItem {
                    Label("常规", systemImage: "gearshape")
                }
                .tag(SettingsPane.general)

            notificationsPane
                .tabItem {
                    Label("通知", systemImage: "bell")
                }
                .tag(SettingsPane.notifications)
        }
        .frame(width: 460, height: 380)
        .onAppear {
            migrateSelectedPaneIfNeeded()
            reconcileLaunchAtLoginSetting()
        }
        .onChange(of: selectedPane) {
            migrateSelectedPaneIfNeeded()
        }
    }

    private var generalPane: some View {
        ScrollViewReader { proxy in
            Form {
                Section("提醒") {
                    Toggle("启用提醒", isOn: binding(\.remindersEnabled))

                    Picker("提醒间隔", selection: intervalChoiceBinding) {
                        ForEach(ReminderIntervalChoice.presetMinutes, id: \.self) { minutes in
                            Text("\(minutes) 分钟")
                                .tag(ReminderIntervalChoice.preset(minutes))
                        }
                        Divider()
                        Text("自定义…")
                            .tag(ReminderIntervalChoice.custom)
                    }

                    if effectiveIntervalChoice == .custom {
                        Stepper(
                            "自定义间隔 \(settingsStore.settings.intervalMinutes) 分钟",
                            value: binding(\.intervalMinutes),
                            in: 5...240,
                            step: 5
                        )
                    }

                    Stepper(
                        "每日活动目标 \(settingsStore.settings.dailyTarget) 次",
                        value: binding(\.dailyTarget),
                        in: 1...24,
                        step: 1
                    )

                    if settingsStore.settings.dailyTarget > suggestedDailyMaximum {
                        StatusMessage(
                            text: "当前日程大约可安排 \(suggestedDailyMaximum) 次活动提醒；目标仍可保留。",
                            systemImage: "info.circle",
                            color: .secondary
                        )
                    }
                }

                Section("工作时段") {
                    Toggle("仅工作日提醒", isOn: binding(\.workdaysOnly))
                        .focused($focusedSetting, equals: .workdaysOnly)
                        .accessibilityFocused(
                            $accessibilityFocusedSetting,
                            equals: .workdaysOnly
                        )

                    TimePickerRow(
                        title: "开始",
                        selection: binding(\.workStartMinutes),
                        range: 0...(23 * 60),
                        step: 30
                    )
                    TimePickerRow(
                        title: "结束",
                        selection: binding(\.workEndMinutes),
                        range: 60...(24 * 60),
                        step: 30
                    )
                }
                .id(SettingsSectionDestination.workSchedule)

                Section("午休") {
                    Toggle("午休自动暂停", isOn: binding(\.lunchPauseEnabled))

                    if settingsStore.settings.lunchPauseEnabled {
                        TimePickerRow(
                            title: "午休开始",
                            selection: binding(\.lunchStartMinutes),
                            range: lunchStartRange,
                            step: 30
                        )
                        TimePickerRow(
                            title: "午休结束",
                            selection: binding(\.lunchEndMinutes),
                            range: lunchEndRange,
                            step: 30
                        )
                    }
                }

                Section("应用") {
                    Toggle("状态栏显示倒计时", isOn: binding(\.menuBarCountdownEnabled))
                    launchAtLoginToggle
                }

                Section("隐私") {
                    Text("SitRight 不检测坐姿、真实运动或键鼠活动。活动记录只来自你主动完成的 60 秒引导。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let error = settingsStore.lastErrorMessage {
                    Section {
                        StatusMessage(
                            text: error,
                            systemImage: "exclamationmark.triangle.fill",
                            color: .orange
                        )
                    }
                }
            }
            .formStyle(.grouped)
            .onAppear {
                fulfillSectionRequest(using: proxy)
            }
            .onChange(of: requestedSectionRawValue) {
                fulfillSectionRequest(using: proxy)
            }
        }
    }

    private var notificationsPane: some View {
        Form {
            Section("提醒方式") {
                Toggle("强提醒弹窗", isOn: binding(\.popupEnabled))
                Toggle("系统通知", isOn: binding(\.notificationsEnabled))
                Toggle("通知声音", isOn: binding(\.soundEnabled))
                    .disabled(!settingsStore.settings.notificationsEnabled)

                if !settingsStore.settings.popupEnabled &&
                    !settingsStore.settings.notificationsEnabled {
                    StatusMessage(
                        text: "两种提醒方式都已关闭；菜单栏仍会计时，但不会主动弹出提醒。",
                        systemImage: "exclamationmark.triangle.fill",
                        color: .orange
                    )
                }
            }

            if settingsStore.settings.notificationsEnabled {
                Section("系统权限") {
                    notificationStatus
                }
            }
        }
        .formStyle(.grouped)
    }

    private var effectiveIntervalChoice: ReminderIntervalChoice {
        intervalSelectionOverride ??
            ReminderIntervalChoice.selection(for: settingsStore.settings.intervalMinutes)
    }

    private var visiblePaneSelection: Binding<SettingsPane> {
        Binding(
            get: { SettingsSelection.visiblePane(for: selectedPane) },
            set: { selectedPane = SettingsSelection.visiblePane(for: $0) }
        )
    }

    private var intervalChoiceBinding: Binding<ReminderIntervalChoice> {
        Binding(
            get: { effectiveIntervalChoice },
            set: { choice in
                switch choice {
                case .preset(let minutes):
                    intervalSelectionOverride = nil
                    settingsStore.update { $0.intervalMinutes = minutes }
                case .custom:
                    intervalSelectionOverride = .custom
                }
            }
        )
    }

    private var suggestedDailyMaximum: Int {
        let settings = settingsStore.settings
        let workMinutes = max(settings.workEndMinutes - settings.workStartMinutes, 0)
        let lunchMinutes = settings.lunchPauseEnabled
            ? max(settings.lunchEndMinutes - settings.lunchStartMinutes, 0)
            : 0
        let usableMinutes = max(workMinutes - lunchMinutes, 0)
        let interval = max(settings.intervalMinutes, 1)
        let scheduleGaps = settings.lunchPauseEnabled ? 1 : 0
        return max((usableMinutes / interval) - scheduleGaps, 1)
    }

    private var launchAtLoginToggle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("登录时打开 SitRight", isOn: Binding(
                get: { launchAtLoginController.isRegistered },
                set: { isEnabled in
                    do {
                        try launchAtLoginController.setEnabled(isEnabled)
                        settingsStore.setError(nil)
                    } catch {
                        settingsStore.setError("开机启动设置失败：请从打包后的 .app 启动后再试")
                    }
                    settingsStore.update {
                        $0.launchAtLogin = launchAtLoginController.isRegistered
                    }
                }
            ))
            .disabled(launchAtLoginController.status == .notFound)

            switch launchAtLoginController.status {
            case .requiresApproval:
                HStack(spacing: 8) {
                    StatusMessage(
                        text: "需要在系统设置中允许",
                        systemImage: "exclamationmark.triangle.fill",
                        color: .orange
                    )

                    Spacer()

                    Button("打开登录项…") {
                        launchAtLoginController.openSystemSettingsLoginItems()
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            case .notFound:
                StatusMessage(
                    text: "请从打包后的 .app 启动后设置",
                    systemImage: "shippingbox",
                    color: .secondary
                )
            case .notRegistered, .enabled:
                EmptyView()
            }
        }
    }

    private var notificationStatus: some View {
        HStack(spacing: 8) {
            StatusMessage(
                text: notificationStatusText,
                systemImage: notificationStatusImage,
                color: notificationStatusColor
            )

            Spacer()

            if notificationManager.authorizationStatus == .denied {
                Button("打开系统设置…") {
                    openNotificationSettings()
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
    }

    private var notificationStatusText: String {
        if let error = notificationManager.lastErrorMessage {
            return error
        }

        switch notificationManager.authorizationStatus {
        case .notDetermined:
            return "等待系统授权"
        case .denied:
            return "系统通知权限已关闭"
        case .authorized, .provisional, .ephemeral:
            return "系统通知可用"
        @unknown default:
            return "通知权限状态未知"
        }
    }

    private var notificationStatusImage: String {
        switch notificationManager.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return "checkmark.circle.fill"
        case .denied:
            return "exclamationmark.triangle.fill"
        case .notDetermined:
            return "questionmark.circle"
        @unknown default:
            return "questionmark.circle"
        }
    }

    private var notificationStatusColor: Color {
        switch notificationManager.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .green
        case .denied:
            return .orange
        case .notDetermined:
            return .secondary
        @unknown default:
            return .secondary
        }
    }

    private var lunchStartRange: ClosedRange<Int> {
        let lowerBound = settingsStore.settings.workStartMinutes
        let upperBound = max(lowerBound, settingsStore.settings.workEndMinutes - 30)
        return lowerBound...upperBound
    }

    private var lunchEndRange: ClosedRange<Int> {
        let upperBound = settingsStore.settings.workEndMinutes
        let lowerBound = min(settingsStore.settings.lunchStartMinutes + 30, upperBound)
        return lowerBound...upperBound
    }

    private func openNotificationSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func migrateSelectedPaneIfNeeded() {
        let route = SettingsSelection.route(for: selectedPane)
        if let requestedSection = route.requestedSection {
            requestedSectionRawValue = requestedSection.rawValue
        }
        guard selectedPane != route.visiblePane else { return }
        selectedPane = route.visiblePane
    }

    private func fulfillSectionRequest(using proxy: ScrollViewProxy) {
        var request = SettingsSectionRequestState(rawValue: requestedSectionRawValue)
        guard let destination = request.consume() else { return }
        requestedSectionRawValue = request.rawValue

        DispatchQueue.main.async {
            proxy.scrollTo(destination, anchor: .top)
            focusedSetting = .workdaysOnly
            accessibilityFocusedSetting = .workdaysOnly
        }
    }

    private func reconcileLaunchAtLoginSetting() {
        launchAtLoginController.refreshStatus()
        let actualValue = launchAtLoginController.isRegistered
        guard settingsStore.settings.launchAtLogin != actualValue else { return }
        settingsStore.update { $0.launchAtLogin = actualValue }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { value in
                settingsStore.update { $0[keyPath: keyPath] = value }
            }
        )
    }
}

private struct StatusMessage: View {
    let text: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label {
            Text(text)
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(color)
        }
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct TimePickerRow: View {
    let title: String
    @Binding var selection: Int
    let range: ClosedRange<Int>
    let step: Int

    var body: some View {
        LabeledContent(title) {
            Picker(title, selection: $selection) {
                ForEach(
                    TimePickerOptions.values(
                        in: range,
                        step: step,
                        including: selection
                    ),
                    id: \.self
                ) { minutes in
                    Text(TimeFormatting.clockText(for: minutes))
                        .tag(minutes)
                }
            }
            .labelsHidden()
            .frame(width: 118)
        }
    }
}
