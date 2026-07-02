import SwiftUI

struct SettingsPanelView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var engine: ReminderEngine

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
    }

    private var reminderSection: some View {
        SettingsGroup(title: "提醒节奏", systemImage: "timer") {
            Toggle("启用提醒", isOn: binding(\.remindersEnabled))

            VStack(alignment: .leading, spacing: 8) {
                Picker("快捷间隔", selection: binding(\.intervalMinutes)) {
                    ForEach([15, 30, 45, 60], id: \.self) { minute in
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
                "今日目标 \(settingsStore.settings.dailyTarget) 次",
                value: binding(\.dailyTarget),
                in: 1...24,
                step: 1
            )

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

            TimePickerRow(title: "开始", selection: binding(\.workStartMinutes), step: 30)
            TimePickerRow(title: "结束", selection: binding(\.workEndMinutes), step: 30)

            Toggle("午休自动暂停", isOn: binding(\.lunchPauseEnabled))

            if settingsStore.settings.lunchPauseEnabled {
                TimePickerRow(title: "午休开始", selection: binding(\.lunchStartMinutes), step: 30)
                TimePickerRow(title: "午休结束", selection: binding(\.lunchEndMinutes), step: 30)
            }
        }
    }

    private var behaviorSection: some View {
        SettingsGroup(title: "提醒方式", systemImage: "bell") {
            Toggle("状态栏倒计时", isOn: binding(\.menuBarCountdownEnabled))
            Toggle("弹窗提醒", isOn: binding(\.popupEnabled))
            Toggle("系统通知", isOn: binding(\.notificationsEnabled))
            Toggle("通知声音", isOn: binding(\.soundEnabled))
            launchAtLoginToggle

            HStack(spacing: 8) {
                Button {
                    engine.snooze()
                } label: {
                    Label("延后 5 分钟", systemImage: "clock.arrow.circlepath")
                }
                .buttonStyle(.bordered)

                Button {
                    engine.pauseToday()
                } label: {
                    Label("暂停今天", systemImage: "moon")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var launchAtLoginToggle: some View {
        Toggle("开机启动", isOn: Binding(
            get: { settingsStore.settings.launchAtLogin },
            set: { isEnabled in
                do {
                    try LaunchAtLoginController.setEnabled(isEnabled)
                    settingsStore.update { $0.launchAtLogin = isEnabled }
                    settingsStore.setError(nil)
                } catch {
                    settingsStore.setError("开机启动设置失败：请从打包后的 .app 启动后再试")
                    settingsStore.update { $0.launchAtLogin = LaunchAtLoginController.isEnabled }
                }
            }
        ))
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
    let step: Int

    var body: some View {
        LabeledContent(title) {
            Picker(title, selection: $selection) {
                ForEach(Array(stride(from: 0, through: 24 * 60, by: step)), id: \.self) { minutes in
                    Text(TimeFormatting.clockText(for: minutes)).tag(minutes)
                }
            }
            .labelsHidden()
            .frame(width: 118)
        }
    }
}
