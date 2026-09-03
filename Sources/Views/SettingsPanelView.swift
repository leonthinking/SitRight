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
    static func title(
        for pane: SettingsPane,
        language: AppLanguage = .simplifiedChinese
    ) -> String {
        switch SettingsSelection.visiblePane(for: pane) {
        case .general:
            return language.text("通用", "General")
        case .notifications:
            return language.text("通知", "Notifications")
        case .about:
            return language.text("关于", "About")
        case .schedule:
            preconditionFailure("Visible settings panes must not resolve to Schedule")
        }
    }
}

enum SettingsWindowSizingPolicy {
    static let fixedContentWidth: CGFloat = 520
    static let defaultContentSize = NSSize(width: fixedContentWidth, height: 900)
    static let minimumContentSize = NSSize(width: fixedContentWidth, height: 520)
    static let priorDefaultContentSize = NSSize(width: 520, height: 800)
    static let preV2DefaultContentSize = NSSize(width: 460, height: 380)
    static let v2MigrationDefaultsKey =
        "sitright.settings.windowSizingV2Migrated"
    static let migrationDefaultsKey =
        "sitright.settings.windowSizingV3Migrated"

    static func migrationTarget(
        currentContentSize: NSSize,
        maximumContentSize: NSSize
    ) -> NSSize {
        normalizedTarget(
            currentContentSize: currentContentSize,
            maximumContentSize: maximumContentSize,
            promotesLegacyDefaultHeight: true
        )
    }

    static func restorationTarget(
        currentContentSize: NSSize,
        maximumContentSize: NSSize
    ) -> NSSize {
        normalizedTarget(
            currentContentSize: currentContentSize,
            maximumContentSize: maximumContentSize,
            promotesLegacyDefaultHeight: false
        )
    }

    private static func normalizedTarget(
        currentContentSize: NSSize,
        maximumContentSize: NSSize,
        promotesLegacyDefaultHeight: Bool
    ) -> NSSize {
        let isKnownLegacyDefaultHeight =
            approximatelyEqual(
                currentContentSize.height,
                priorDefaultContentSize.height
            ) ||
            approximatelyEqual(
                currentContentSize.height,
                preV2DefaultContentSize.height
            )
        let requestedHeight =
            promotesLegacyDefaultHeight && isKnownLegacyDefaultHeight
            ? defaultContentSize.height
            : max(currentContentSize.height, minimumContentSize.height)

        return NSSize(
            width: min(fixedContentWidth, maximumContentSize.width),
            height: min(requestedHeight, maximumContentSize.height)
        )
    }

    private static func approximatelyEqual(
        _ lhs: CGFloat,
        _ rhs: CGFloat
    ) -> Bool {
        abs(lhs - rhs) <= 1
    }
}

@MainActor
enum SettingsWindowConfigurator {
    @discardableResult
    static func configure(
        _ window: NSWindow,
        shouldMigrateLegacySize: Bool,
        maximumContentSize providedMaximumContentSize: NSSize? = nil
    ) -> Bool {
        window.contentMinSize = SettingsWindowSizingPolicy.minimumContentSize
        window.contentMaxSize = NSSize(
            width: SettingsWindowSizingPolicy.fixedContentWidth,
            height: CGFloat.greatestFiniteMagnitude
        )
        window.styleMask.insert(.resizable)

        let screen = window.screen ?? NSScreen.main
        let maximumContentSize =
            providedMaximumContentSize ??
            screen.map {
                window.contentRect(forFrameRect: $0.visibleFrame).size
            } ??
            SettingsWindowSizingPolicy.defaultContentSize
        let currentContentSize = window.contentLayoutRect.size
        let targetSize = shouldMigrateLegacySize
            ? SettingsWindowSizingPolicy.migrationTarget(
                currentContentSize: currentContentSize,
                maximumContentSize: maximumContentSize
            )
            : SettingsWindowSizingPolicy.restorationTarget(
                currentContentSize: currentContentSize,
                maximumContentSize: maximumContentSize
            )
        if currentContentSize != targetSize {
            window.setContentSize(targetSize)
        }

        if let screen {
            let constrainedFrame = window.constrainFrameRect(
                window.frame,
                to: screen
            )
            window.setFrame(constrainedFrame, display: false)
        }
        return shouldMigrateLegacySize
    }
}

private final class SettingsWindowObserverView: NSView {
    var onWindowAvailable: ((NSWindow) -> Void)?
    var didMigrateLegacySize = false
    private weak var observedWindow: NSWindow?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observeWindowIfNeeded()
        notifyIfAttached(scheduleFollowUp: true)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func notifyIfAttached(scheduleFollowUp: Bool = false) {
        guard let window else { return }
        onWindowAvailable?(window)

        guard scheduleFollowUp else { return }
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.window === window else { return }
            self.onWindowAvailable?(window)
        }
    }

    private func observeWindowIfNeeded() {
        guard observedWindow !== window else { return }
        for notificationName in [
            NSWindow.didResizeNotification,
            NSWindow.didChangeScreenNotification
        ] {
            NotificationCenter.default.removeObserver(
                self,
                name: notificationName,
                object: observedWindow
            )
        }
        observedWindow = window
        guard let window else { return }
        for notificationName in [
            NSWindow.didResizeNotification,
            NSWindow.didChangeScreenNotification
        ] {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowGeometryDidChange(_:)),
                name: notificationName,
                object: window
            )
        }
    }

    @objc
    private func windowGeometryDidChange(_ notification: Notification) {
        notifyIfAttached()
    }
}

private struct SettingsWindowConfigurationView: NSViewRepresentable {
    @Binding var hasCompletedLegacySizeMigration: Bool
    let activationController: SettingsWindowActivationController?

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
            activationController?.registerSettingsWindow(window)
            guard didMigrate else { return }

            view.didMigrateLegacySize = true
            DispatchQueue.main.async {
                migrationBinding.wrappedValue = true
            }
        }
        view.notifyIfAttached(scheduleFollowUp: true)
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

enum SettingsValuePickerOptions {
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

enum SettingsValuePresentation {
    static func dailyTarget(_ value: Int, language: AppLanguage) -> String {
        language.text(
            "\(value) 次",
            value == 1 ? "1 time" : "\(value) times"
        )
    }

    static func intervalMinutes(_ value: Int, language: AppLanguage) -> String {
        language.text("\(value) 分钟", "\(value) minutes")
    }
}

struct SettingsPanelView: View {
    @Environment(\.settingsWindowActivationController)
    private var settingsWindowActivationController
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var notificationManager: NotificationManager
    @EnvironmentObject private var launchAtLoginController: LaunchAtLoginController
    @EnvironmentObject private var updateController: UpdateController

    @AppStorage(SettingsSelection.defaultsKey)
    private var selectedPane: SettingsPane = .general
    @AppStorage(SettingsSelection.requestedSectionDefaultsKey)
    private var requestedSectionRawValue = ""
    @AppStorage(SettingsWindowSizingPolicy.migrationDefaultsKey)
    private var hasCompletedLegacySizeMigration = false
    @State private var intervalSelectionOverride: ReminderIntervalChoice?
    @State private var presentedLegalNotice: LegalNotice?
    @FocusState private var focusedSetting: SettingsFocusTarget?
    @AccessibilityFocusState private var accessibilityFocusedSetting: SettingsFocusTarget?

    var body: some View {
        content
            .environment(\.locale, language.locale)
    }

    private var content: some View {
        TabView(selection: visiblePaneSelection) {
            generalPane
                .tabItem {
                    Label(
                        SettingsPanePresentation.title(for: .general, language: language),
                        systemImage: "gearshape"
                    )
                }
                .tag(SettingsPane.general)

            notificationsPane
                .tabItem {
                    Label(
                        SettingsPanePresentation.title(for: .notifications, language: language),
                        systemImage: "bell"
                    )
                }
                .tag(SettingsPane.notifications)

            aboutPane
                .tabItem {
                    Label(
                        SettingsPanePresentation.title(for: .about, language: language),
                        systemImage: "info.circle"
                    )
                }
                .tag(SettingsPane.about)
        }
        .frame(
            minWidth: SettingsWindowSizingPolicy.fixedContentWidth,
            idealWidth: SettingsWindowSizingPolicy.fixedContentWidth,
            maxWidth: SettingsWindowSizingPolicy.fixedContentWidth,
            minHeight: SettingsWindowSizingPolicy.minimumContentSize.height,
            idealHeight: SettingsWindowSizingPolicy.defaultContentSize.height,
            maxHeight: .infinity
        )
        .background {
            SettingsWindowConfigurationView(
                hasCompletedLegacySizeMigration:
                    $hasCompletedLegacySizeMigration,
                activationController: settingsWindowActivationController
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
            LegalNoticeSheet(notice: notice, language: language)
                .environment(\.locale, language.locale)
        }
    }

    private var language: AppLanguage {
        settingsStore.settings.language
    }

    private var generalPane: some View {
        ScrollViewReader { proxy in
            Form {
                Section(language.text("提醒", "Reminders")) {
                    Toggle(language.text("启用提醒", "Enable reminders"), isOn: binding(\.remindersEnabled))

                    SettingsValuePickerRow(
                        title: language.text("提醒间隔", "Reminder interval"),
                        selection: intervalChoiceBinding
                    ) {
                        ForEach(ReminderIntervalChoice.presetMinutes, id: \.self) { minutes in
                            Text(SettingsValuePresentation.intervalMinutes(minutes, language: language))
                                .tag(ReminderIntervalChoice.preset(minutes))
                        }
                        Divider()
                        Text(language.text("自定义…", "Custom…"))
                            .tag(ReminderIntervalChoice.custom)
                    }

                    if effectiveIntervalChoice == .custom {
                        SettingsValuePickerRow(
                            title: language.text("自定义间隔", "Custom interval"),
                            selection: binding(\.intervalMinutes)
                        ) {
                            ForEach(
                                SettingsValuePickerOptions.values(
                                    in: 5...240,
                                    step: 5,
                                    including: settingsStore.settings.intervalMinutes
                                ),
                                id: \.self
                            ) { minutes in
                                Text(SettingsValuePresentation.intervalMinutes(minutes, language: language))
                                    .tag(minutes)
                            }
                        }
                    }

                    SettingsValuePickerRow(
                        title: language.text("每日活动目标", "Daily activity goal"),
                        selection: binding(\.dailyTarget)
                    ) {
                        ForEach(1...24, id: \.self) { target in
                            Text(SettingsValuePresentation.dailyTarget(target, language: language))
                                .tag(target)
                        }
                    }

                    if settingsStore.settings.dailyTarget > suggestedDailyMaximum {
                        let scheduledReminderCount = language.quantity(
                            suggestedDailyMaximum,
                            simplifiedChineseUnit: "次活动提醒",
                            englishSingular: "activity reminder",
                            englishPlural: "activity reminders"
                        )
                        StatusMessage(
                            text: language.text(
                                "当前日程大约可安排 \(scheduledReminderCount)；目标仍可保留。",
                                "Your schedule allows about \(scheduledReminderCount); you can still keep this goal."
                            ),
                            systemImage: "info.circle",
                            color: .secondary
                        )
                    }
                }

                Section(language.text("工作时段", "Work schedule")) {
                    Toggle(language.text("仅工作日提醒", "Remind on workdays only"), isOn: binding(\.workdaysOnly))
                        .focused($focusedSetting, equals: .workdaysOnly)
                        .accessibilityFocused(
                            $accessibilityFocusedSetting,
                            equals: .workdaysOnly
                        )

                    TimePickerRow(
                        title: language.text("开始", "Start"),
                        selection: binding(\.workStartMinutes),
                        range: 0...(23 * 60),
                        step: 30
                    )
                    TimePickerRow(
                        title: language.text("结束", "End"),
                        selection: binding(\.workEndMinutes),
                        range: 60...(24 * 60),
                        step: 30
                    )
                }
                .id(SettingsSectionDestination.workSchedule)

                Section(language.text("午休", "Lunch break")) {
                    Toggle(language.text("午休自动暂停", "Pause during lunch"), isOn: binding(\.lunchPauseEnabled))

                    if settingsStore.settings.lunchPauseEnabled {
                        TimePickerRow(
                            title: language.text("午休开始", "Lunch starts"),
                            selection: binding(\.lunchStartMinutes),
                            range: lunchStartRange,
                            step: 30
                        )
                        TimePickerRow(
                            title: language.text("午休结束", "Lunch ends"),
                            selection: binding(\.lunchEndMinutes),
                            range: lunchEndRange,
                            step: 30
                        )
                    }
                }

                Section(language.text("应用", "App")) {
                    SettingsValuePickerRow(
                        title: language.text("语言", "Language"),
                        selection: binding(\.language)
                    ) {
                        ForEach(AppLanguage.allCases) { option in
                            Text(option.displayName(presentationLanguage: language))
                                .tag(option)
                        }
                    }

                    Toggle(
                        language.text("状态栏显示倒计时", "Show countdown in menu bar"),
                        isOn: binding(\.menuBarCountdownEnabled)
                    )
                    launchAtLoginToggle
                }

                Section(language.text("隐私", "Privacy")) {
                    Text(language.text(
                        "SitRight 不检测坐姿、真实运动或键鼠活动。活动记录只来自你主动完成的 60 秒引导。",
                        "SitRight does not monitor posture, physical movement, or keyboard and mouse activity. Activity is recorded only when you complete a 60-second guided break."
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let error = settingsStore.lastErrorMessage {
                    Section {
                        StatusMessage(
                            text: language.localizedRuntimeMessage(error),
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
            Section(language.text("提醒方式", "Reminder methods")) {
                Toggle(language.text("强提醒弹窗", "Persistent reminder window"), isOn: binding(\.popupEnabled))
                Toggle(language.text("系统通知", "System notifications"), isOn: binding(\.notificationsEnabled))
                Toggle(language.text("通知声音", "Notification sound"), isOn: binding(\.soundEnabled))
                    .disabled(!settingsStore.settings.notificationsEnabled)

                if !settingsStore.settings.popupEnabled &&
                    !settingsStore.settings.notificationsEnabled {
                    StatusMessage(
                        text: language.text(
                            "两种提醒方式都已关闭；菜单栏仍会计时，但不会主动弹出提醒。",
                            "Both reminder methods are off. The menu bar timer will continue, but SitRight will not actively alert you."
                        ),
                        systemImage: "exclamationmark.triangle.fill",
                        color: .orange
                    )
                }
            }

            if settingsStore.settings.notificationsEnabled {
                Section(language.text("系统权限", "System permissions")) {
                    notificationStatus
                }
            }
        }
        .formStyle(.grouped)
    }

    private var aboutPane: some View {
        Form {
            Section(language.text("SitRight 坐正", "SitRight")) {
                HStack(spacing: 14) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 56, height: 56)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(language.text("SitRight 坐正", "SitRight"))
                            .font(.headline)
                        Text(updateController.currentVersionText(language: language))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }

            Section(language.text("版本更新", "Software updates")) {
                Toggle(
                    language.text("自动检查更新", "Automatically check for updates"),
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
                    text: updateController.statusText(language: language),
                    systemImage: updateController.state.systemImage,
                    color: updateStatusColor
                )

                if let lastCheckText = updateController.lastCheckText(language: language) {
                    Text(lastCheckText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button(language.text("检查更新…", "Check for Updates…")) {
                        updateController.checkForUpdates()
                    }
                    .disabled(!updateController.canCheckForUpdates)

                    Spacer()

                    SettingsExternalLink(
                        title: language.text("查看 GitHub Releases", "View GitHub Releases"),
                        detail: "GitHub",
                        destination: UpdateConfiguration.releasesURL,
                        accessibilityHint: language.text(
                            "在浏览器中打开 SitRight GitHub Releases",
                            "Open SitRight GitHub Releases in your browser"
                        )
                    )
                }

                Text(language.text(
                    "GitHub 社区预览版未经 Developer ID 公证；首次安装可能需要在系统设置中手动允许。",
                    "This GitHub community preview is not notarized with Developer ID. The first installation may need to be allowed manually in System Settings."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Section(language.text("开源与社区", "Open source and community")) {
                Text(language.text(
                    "提交使用问题、功能建议、安全报告或 Bug 时，需要 GitHub 账号。",
                    "A GitHub account is required to request support, suggest features, report security issues, or file bugs."
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    presentedLegalNotice = .sitRight
                } label: {
                    SettingsNavigationRow(
                        title: language.text("开源协议", "Open-source license"),
                        detail: "MIT"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint(language.text(
                    "查看 SitRight 的 MIT 开源协议",
                    "View SitRight's MIT License"
                ))

                SettingsExternalLink(
                    title: language.text("源代码", "Source code"),
                    detail: "GitHub",
                    destination: CommunityLinks.repositoryURL,
                    accessibilityHint: language.text(
                        "在浏览器中打开 SitRight 源代码",
                        "Open the SitRight source code in your browser"
                    )
                )

                SettingsExternalLink(
                    title: language.text("给 SitRight 点个 Star 🌟", "Star SitRight 🌟"),
                    detail: "GitHub",
                    destination: CommunityLinks.starURL,
                    accessibilityHint: language.text(
                        "在浏览器中打开 SitRight GitHub 仓库",
                        "Open the SitRight GitHub repository in your browser"
                    )
                )

                SettingsExternalLink(
                    title: language.text("功能建议", "Feature requests"),
                    detail: "GitHub",
                    destination: CommunityLinks.featureRequestURL,
                    accessibilityHint: language.text(
                        "在 GitHub 提交功能建议",
                        "Submit a feature request on GitHub"
                    )
                )

                SettingsExternalLink(
                    title: language.text("报告问题", "Report a bug"),
                    detail: "GitHub",
                    destination: CommunityLinks.bugReportURL,
                    accessibilityHint: language.text(
                        "在 GitHub 报告 SitRight 问题",
                        "Report a SitRight bug on GitHub"
                    )
                )

                SettingsExternalLink(
                    title: language.text("使用帮助", "Support"),
                    detail: "GitHub",
                    destination: CommunityLinks.supportRequestURL,
                    accessibilityHint: language.text(
                        "在 GitHub 提交 SitRight 使用问题",
                        "Request SitRight support on GitHub"
                    )
                )

                SettingsExternalLink(
                    title: language.text("隐私说明", "Privacy policy"),
                    detail: "GitHub",
                    destination: CommunityLinks.privacyURL,
                    accessibilityHint: language.text(
                        "在浏览器中查看 SitRight 隐私说明",
                        "Open the SitRight privacy policy in your browser"
                    )
                )

                SettingsExternalLink(
                    title: language.text("安全问题", "Security"),
                    detail: language.text("私密报告", "Private report"),
                    destination: CommunityLinks.securityReportURL,
                    accessibilityHint: language.text(
                        "在 GitHub 私密报告 SitRight 安全问题",
                        "Privately report a SitRight security issue on GitHub"
                    )
                )

                Button {
                    presentedLegalNotice = .thirdParty
                } label: {
                    SettingsNavigationRow(
                        title: language.text("第三方许可", "Third-party licenses"),
                        detail: "Sparkle 2.9.2"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint(language.text(
                    "查看 SitRight 使用的第三方软件许可",
                    "View third-party software licenses used by SitRight"
                ))
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
            Toggle(language.text("登录时打开 SitRight", "Open SitRight at login"), isOn: Binding(
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
                        text: language.text(
                            "需要在系统设置中允许",
                            "Approval is required in System Settings"
                        ),
                        systemImage: "exclamationmark.triangle.fill",
                        color: .orange
                    )

                    Spacer()

                    Button(language.text("打开登录项…", "Open Login Items…")) {
                        launchAtLoginController.openSystemSettingsLoginItems()
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            case .serviceNotFound, .operationFailed:
                VStack(alignment: .leading, spacing: 6) {
                    StatusMessage(
                        text: launchAtLoginController.issue?.userMessage(language: language) ??
                            language.text(
                                "macOS 暂时未能识别 SitRight 登录项",
                                "macOS cannot currently recognize the SitRight login item"
                            ),
                        systemImage: "exclamationmark.triangle.fill",
                        color: .orange
                    )

                    HStack(spacing: 12) {
                        Button(language.text("重新检测", "Check Again")) {
                            refreshLaunchAtLoginStatus()
                        }
                        .buttonStyle(.link)
                        .font(.caption)

                        Button(language.text("打开登录项…", "Open Login Items…")) {
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
                Button(language.text("打开系统设置…", "Open System Settings…")) {
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
            return language.text("等待系统授权", "Waiting for system permission")
        case .denied:
            return language.text("系统通知权限已关闭", "System notification permission is off")
        case .authorized, .provisional, .ephemeral:
            return language.text("系统通知可用", "System notifications are available")
        @unknown default:
            return language.text("通知权限状态未知", "Notification permission status is unknown")
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
    var language: AppLanguage = .simplifiedChinese

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(notice.title(language: language))
                    .font(.title2.bold())

                Spacer()

                Button(language.text("完成", "Done")) {
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

                        Text(language.text("无法读取许可文本", "Unable to load the license text"))
                            .font(.headline)

                        SettingsExternalLink(
                            title: language.text(
                                "在线查看\(notice.title(language: language))",
                                "View \(notice.title(language: language)) online"
                            ),
                            detail: "GitHub",
                            destination: notice.fallbackURL,
                            accessibilityHint: language.text(
                                "在浏览器中打开\(notice.title(language: language))",
                                "Open \(notice.title(language: language)) in your browser"
                            )
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

private struct SettingsValuePickerRow<Selection: Hashable, Options: View>: View {
    let title: String
    @Binding var selection: Selection
    private let options: Options

    init(
        title: String,
        selection: Binding<Selection>,
        @ViewBuilder options: () -> Options
    ) {
        self.title = title
        _selection = selection
        self.options = options()
    }

    var body: some View {
        LabeledContent(title) {
            Picker(title, selection: $selection) {
                options
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel(title)
        }
    }
}

private struct TimePickerRow: View {
    @Environment(\.locale) private var locale

    let title: String
    @Binding var selection: Int
    let range: ClosedRange<Int>
    let step: Int

    var body: some View {
        SettingsValuePickerRow(title: title, selection: $selection) {
            ForEach(
                SettingsValuePickerOptions.values(
                    in: range,
                    step: step,
                    including: selection
                ),
                id: \.self
            ) { minutes in
                Text(TimeFormatting.clockText(for: minutes, locale: locale))
                    .tag(minutes)
            }
        }
    }
}
