import AppKit
import SwiftUI
import UserNotifications

struct SettingsPanelView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var notificationManager: NotificationManager
    @EnvironmentObject private var launchAtLoginController: LaunchAtLoginController
    let engine: ReminderEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            reminderSection
            scheduleSection
            behaviorSection

            if let error = settingsStore.lastErrorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .onAppear {
            reconcileLaunchAtLoginSetting()
        }
    }

    private var reminderSection: some View {
        SettingsGroup(title: "提醒节奏", systemImage: "timer") {
            Toggle("启用提醒", isOn: binding(\.remindersEnabled))

            VStack(alignment: .leading, spacing: 8) {
                Picker("快捷间隔", selection: binding(\.intervalMinutes)) {
                    ForEach([30, 45, 50, 60], id: \.self) { minute in
                        Text("\(minute)").tag(minute)
                    }
                }
                .pickerStyle(.segmented)

                Stepper(
                    "自定义 \(settingsStore.settings.intervalMinutes) 分钟",
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
                Label(
                    "当前日程大约可安排 \(suggestedDailyMaximum) 次活动提醒；目标仍可保留。",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Button {
                engine.resetTimer()
            } label: {
                Label("从现在重新计时", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
    }

    private var scheduleSection: some View {
        SettingsGroup(title: "提醒时段", systemImage: "calendar") {
            Toggle("仅工作日提醒", isOn: binding(\.workdaysOnly))

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
    }

    private var behaviorSection: some View {
        SettingsGroup(title: "提醒方式", systemImage: "bell") {
            Toggle("状态栏倒计时", isOn: binding(\.menuBarCountdownEnabled))
            Toggle("强提醒弹窗", isOn: binding(\.popupEnabled))
            Toggle("系统通知", isOn: binding(\.notificationsEnabled))
            Toggle("通知声音", isOn: binding(\.soundEnabled))
                .disabled(!settingsStore.settings.notificationsEnabled)

            if settingsStore.settings.notificationsEnabled {
                notificationStatus
            }

            launchAtLoginToggle

            HStack(spacing: 8) {
                Button {
                    engine.snooze()
                } label: {
                    Label("延后 5 分钟", systemImage: "clock.arrow.circlepath")
                }
                .buttonStyle(.bordered)
                .disabled(!engine.canSnooze)

                Button {
                    engine.pauseToday()
                } label: {
                    Label("暂停今天", systemImage: "moon")
                }
                .buttonStyle(.bordered)
                .disabled(!settingsStore.settings.remindersEnabled)
            }

            Text("SitRight 不检测坐姿或真实运动，也不会读取键鼠活动。你可以站立、坐姿活动或采用适合身体状况的动作；完整完成 60 秒后才会计入目标。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var suggestedDailyMaximum: Int {
        let settings = settingsStore.settings
        let workMinutes = max(settings.workEndMinutes - settings.workStartMinutes, 0)
        let lunchMinutes = settings.lunchPauseEnabled
            ? max(settings.lunchEndMinutes - settings.lunchStartMinutes, 0)
            : 0
        let usableMinutes = max(workMinutes - lunchMinutes, 0)
        let interval = max(settings.intervalMinutes, 1)
        // A schedule gap resets the rolling cadence and the final opportunity
        // still needs a response window. Use a deliberately conservative
        // estimate for the warning rather than implying every raw interval is
        // a deliverable opportunity.
        let scheduleGaps = settings.lunchPauseEnabled ? 1 : 0
        return max((usableMinutes / interval) - scheduleGaps, 1)
    }

    private var launchAtLoginToggle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("开机启动", isOn: Binding(
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
                    Label("需要在系统设置中允许", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)

                    Spacer()

                    Button("打开登录项") {
                        launchAtLoginController.openSystemSettingsLoginItems()
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            case .notFound:
                Label("请从打包后的 .app 启动后设置", systemImage: "shippingbox")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .notRegistered, .enabled:
                EmptyView()
            }
        }
    }

    private var notificationStatus: some View {
        HStack(spacing: 8) {
            Label(notificationStatusText, systemImage: notificationStatusImage)
                .font(.caption)
                .foregroundStyle(notificationStatusColor)

            Spacer()

            if notificationManager.authorizationStatus == .denied {
                Button("打开系统设置") {
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
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else {
            return
        }
        NSWorkspace.shared.open(url)
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

private struct SettingsGroup<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 9) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
        }
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
                ForEach(Array(stride(from: range.lowerBound, through: range.upperBound, by: step)), id: \.self) { minutes in
                    Text(TimeFormatting.clockText(for: minutes)).tag(minutes)
                }
            }
            .labelsHidden()
            .frame(width: 118)
        }
    }
}
