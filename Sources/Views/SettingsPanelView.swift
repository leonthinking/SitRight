import AppKit
import SwiftUI
import UserNotifications

enum SettingsPane: String {
    case general
    case schedule
    case notifications
    case about
}

enum SettingsPanePresentation {
    static func title(for pane: SettingsPane) -> String {
        switch SettingsSelection.visiblePane(for: pane) {
        case .general:
            return "通用"
        case .notifications:
            return "通知"
        case .about:
            return "关于"
        case .schedule:
            preconditionFailure("Visible settings panes must not resolve to Schedule")
        }
    }
}

enum SettingsWindowSizingPolicy {
    static let defaultContentSize = NSSize(width: 520, height: 800)
    static let minimumContentSize = NSSize(width: 460, height: 520)
    static let legacySizeMigrationDefaultsKey =
        "sitright.settings.windowSizingV2Migrated"

    static func migrationTarget(
        currentContentSize: NSSize,
        maximumContentSize: NSSize
    ) -> NSSize {
        NSSize(
            width: min(
                max(currentContentSize.width, defaultContentSize.width),
                maximumContentSize.width
            ),
            height: min(
                max(currentContentSize.height, defaultContentSize.height),
                maximumContentSize.height
            )
        )
    }
}

@MainActor
enum SettingsWindowConfigurator {
    @discardableResult
    static func configure(
        _ window: NSWindow,
        shouldMigrateLegacySize: Bool
    ) -> Bool {
        window.contentMinSize = SettingsWindowSizingPolicy.minimumContentSize
        guard shouldMigrateLegacySize else { return false }

        let screen = window.screen ?? NSScreen.main
        let maximumContentSize = screen.map {
            window.contentRect(forFrameRect: $0.visibleFrame).size
        } ?? SettingsWindowSizingPolicy.defaultContentSize
        let targetSize = SettingsWindowSizingPolicy.migrationTarget(
            currentContentSize: window.contentLayoutRect.size,
            maximumContentSize: maximumContentSize
        )
        window.setContentSize(targetSize)

        if let screen {
            let constrainedFrame = window.constrainFrameRect(
                window.frame,
                to: screen
            )
            window.setFrame(constrainedFrame, display: false)
        }
        return true
    }
}

private final class SettingsWindowObserverView: NSView {
    var onWindowAvailable: ((NSWindow) -> Void)?
    var didMigrateLegacySize = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        notifyIfAttached()
    }

    func notifyIfAttached() {
        guard let window else { return }
        onWindowAvailable?(window)
    }
}

private struct SettingsWindowConfigurationView: NSViewRepresentable {
    @Binding var hasCompletedLegacySizeMigration: Bool

    func makeNSView(context: Context) -> SettingsWindowObserverView {
        let view = SettingsWindowObserverView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: SettingsWindowObserverView, context: Context) {
        update(nsView)
    }

    private func update(_ view: SettingsWindowObserverView) {
        let migrationBinding = $hasCompletedLegacySizeMigration
        view.onWindowAvailable = { [weak view] window in
            guard let view else { return }
            let shouldMigrate =
                !migrationBinding.wrappedValue &&
                !view.didMigrateLegacySize
            let didMigrate = SettingsWindowConfigurator.configure(
                window,
                shouldMigrateLegacySize: shouldMigrate
            )
            guard didMigrate else { return }

            view.didMigrateLegacySize = true
            DispatchQueue.main.async {
                migrationBinding.wrappedValue = true
            }
        }
        view.notifyIfAttached()
    }
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
        case .about:
            return SettingsRoute(visiblePane: .about, requestedSection: nil)
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
    @EnvironmentObject private var updateController: UpdateController

    @AppStorage(SettingsSelection.defaultsKey)
    private var selectedPane: SettingsPane = .general
    @AppStorage(SettingsSelection.requestedSectionDefaultsKey)
    private var requestedSectionRawValue = ""
    @AppStorage(SettingsWindowSizingPolicy.legacySizeMigrationDefaultsKey)
    private var hasCompletedLegacySizeMigration = false
    @State private var intervalSelectionOverride: ReminderIntervalChoice?
    @State private var presentedLegalNotice: LegalNotice?
    @FocusState private var focusedSetting: SettingsFocusTarget?
    @AccessibilityFocusState private var accessibilityFocusedSetting: SettingsFocusTarget?

    var body: some View {
        TabView(selection: visiblePaneSelection) {
            generalPane
                .tabItem {
                    Label(
                        SettingsPanePresentation.title(for: .general),
                        systemImage: "gearshape"
                    )
                }
                .tag(SettingsPane.general)

            notificationsPane
                .tabItem {
                    Label(
                        SettingsPanePresentation.title(for: .notifications),
                        systemImage: "bell"
                    )
                }
                .tag(SettingsPane.notifications)

            aboutPane
                .tabItem {
                    Label(
                        SettingsPanePresentation.title(for: .about),
                        systemImage: "info.circle"
                    )
                }
                .tag(SettingsPane.about)
        }
        .frame(
            minWidth: SettingsWindowSizingPolicy.minimumContentSize.width,
            idealWidth: SettingsWindowSizingPolicy.defaultContentSize.width,
            maxWidth: .infinity,
            minHeight: SettingsWindowSizingPolicy.minimumContentSize.height,
            idealHeight: SettingsWindowSizingPolicy.defaultContentSize.height,
            maxHeight: .infinity
        )
        .background {
            SettingsWindowConfigurationView(
                hasCompletedLegacySizeMigration:
                    $hasCompletedLegacySizeMigration
            )
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .onAppear {
            migrateSelectedPaneIfNeeded()
            reconcileLaunchAtLoginSetting()
        }
        .onChange(of: selectedPane) {
            migrateSelectedPaneIfNeeded()
        }
        .sheet(item: $presentedLegalNotice) { notice in
            LegalNoticeSheet(notice: notice)
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

    private var aboutPane: some View {
        Form {
            Section("SitRight 坐正") {
                HStack(spacing: 14) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 56, height: 56)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("SitRight 坐正")
                            .font(.headline)
                        Text(updateController.currentVersionText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }

            Section("版本更新") {
                Toggle(
                    "自动检查更新",
                    isOn: Binding(
                        get: {
                            updateController.automaticallyChecksForUpdates
                        },
                        set: {
                            updateController
                                .setAutomaticallyChecksForUpdates($0)
                        }
                    )
                )
                .disabled(!updateController.isConfigured)

                StatusMessage(
                    text: updateController.statusText,
                    systemImage: updateController.state.systemImage,
                    color: updateStatusColor
                )

                if let lastCheckText = updateController.lastCheckText {
                    Text(lastCheckText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("检查更新…") {
                        updateController.checkForUpdates()
                    }
                    .disabled(!updateController.canCheckForUpdates)

                    Spacer()

                    SettingsExternalLink(
                        title: "查看 GitHub Releases",
                        detail: "GitHub",
                        destination: UpdateConfiguration.releasesURL,
                        accessibilityHint: "在浏览器中打开 SitRight GitHub Releases"
                    )
                }

                Text(
                    "GitHub 社区预览版未经 Developer ID 公证；首次安装可能需要在系统设置中手动允许。"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Section("开源与社区") {
                Text("提交使用问题、功能建议、安全报告或 Bug 时，需要 GitHub 账号。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    presentedLegalNotice = .sitRight
                } label: {
                    SettingsNavigationRow(
                        title: "开源协议",
                        detail: "MIT"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint("查看 SitRight 的 MIT 开源协议")

                SettingsExternalLink(
                    title: "源代码",
                    detail: "GitHub",
                    destination: CommunityLinks.repositoryURL,
                    accessibilityHint: "在浏览器中打开 SitRight 源代码"
                )

                SettingsExternalLink(
                    title: "给 SitRight 点个 Star 🌟",
                    detail: "GitHub",
                    destination: CommunityLinks.starURL,
                    accessibilityHint: "在浏览器中打开 SitRight GitHub 仓库"
                )

                SettingsExternalLink(
                    title: "功能建议",
                    detail: "GitHub",
                    destination: CommunityLinks.featureRequestURL,
                    accessibilityHint: "在 GitHub 提交功能建议"
                )

                SettingsExternalLink(
                    title: "报告问题",
                    detail: "GitHub",
                    destination: CommunityLinks.bugReportURL,
                    accessibilityHint: "在 GitHub 报告 SitRight 问题"
                )

                SettingsExternalLink(
                    title: "使用帮助",
                    detail: "GitHub",
                    destination: CommunityLinks.supportRequestURL,
                    accessibilityHint: "在 GitHub 提交 SitRight 使用问题"
                )

                SettingsExternalLink(
                    title: "隐私说明",
                    detail: "GitHub",
                    destination: CommunityLinks.privacyURL,
                    accessibilityHint: "在浏览器中查看 SitRight 隐私说明"
                )

                SettingsExternalLink(
                    title: "安全问题",
                    detail: "私密报告",
                    destination: CommunityLinks.securityReportURL,
                    accessibilityHint: "在 GitHub 私密报告 SitRight 安全问题"
                )

                Button {
                    presentedLegalNotice = .thirdParty
                } label: {
                    SettingsNavigationRow(
                        title: "第三方许可",
                        detail: "Sparkle 2.9.2"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint("查看 SitRight 使用的第三方软件许可")
            }
        }
        .formStyle(.grouped)
    }

    private var updateStatusColor: Color {
        switch updateController.state {
        case .current:
            return .green
        case .available:
            return .blue
        case .unavailable, .failed, .noCompatibleUpdate:
            return .orange
        case .idle, .checking, .downloading, .installing:
            return .secondary
        }
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
                    } catch {
                        // The controller keeps a structured, recoverable issue
                        // that is rendered inline below this toggle.
                    }
                    settingsStore.update {
                        $0.launchAtLogin = launchAtLoginController.isRegistered
                    }
                }
            ))

            switch launchAtLoginController.recovery {
            case .approvalRequired:
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
            case .serviceNotFound, .operationFailed:
                VStack(alignment: .leading, spacing: 6) {
                    StatusMessage(
                        text: launchAtLoginController.issue?.userMessage ??
                            "macOS 暂时未能识别 SitRight 登录项",
                        systemImage: "exclamationmark.triangle.fill",
                        color: .orange
                    )

                    HStack(spacing: 12) {
                        Button("重新检测") {
                            refreshLaunchAtLoginStatus()
                        }
                        .buttonStyle(.link)
                        .font(.caption)

                        Button("打开登录项…") {
                            launchAtLoginController.openSystemSettingsLoginItems()
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                }
            case .none:
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
        synchronizeLaunchAtLoginSetting()
    }

    private func refreshLaunchAtLoginStatus() {
        launchAtLoginController.retryStatusDetection()
        synchronizeLaunchAtLoginSetting()
    }

    private func synchronizeLaunchAtLoginSetting() {
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

private struct SettingsNavigationRow: View {
    let title: String
    var detail: String? = nil
    var isExternal = false

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .foregroundStyle(.primary)

            Spacer(minLength: 12)

            if let detail {
                Text(detail)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Image(systemName: isExternal ? "arrow.up.right.square" : "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct SettingsExternalLink: View {
    let title: String
    var detail: String? = nil
    let destination: URL
    let accessibilityHint: String

    var body: some View {
        Link(destination: destination) {
            SettingsNavigationRow(
                title: title,
                detail: detail,
                isExternal: true
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint(accessibilityHint)
    }
}

struct LegalNoticeSheet: View {
    static let minimumContentSize = NSSize(width: 520, height: 460)

    let notice: LegalNotice

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(notice.title)
                    .font(.title2.bold())

                Spacer()

                Button("完成") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            ScrollView {
                if let noticeText {
                    Text(noticeText)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding()
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)

                        Text("无法读取许可文本")
                            .font(.headline)

                        SettingsExternalLink(
                            title: "在线查看\(notice.title)",
                            detail: "GitHub",
                            destination: notice.fallbackURL,
                            accessibilityHint: "在浏览器中打开\(notice.title)"
                        )
                    }
                    .frame(maxWidth: .infinity, minHeight: 300)
                    .padding()
                }
            }
        }
        .frame(
            minWidth: Self.minimumContentSize.width,
            minHeight: Self.minimumContentSize.height
        )
    }

    private var noticeText: String? {
        try? LegalNoticeLoader.text(for: notice)
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
