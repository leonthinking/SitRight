import SwiftUI

struct TodayPanelView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var statsStore: StatsStore
    @EnvironmentObject private var engine: ReminderEngine

    var body: some View {
        VStack(spacing: 16) {
            TimerRingView(
                progress: engine.progressFraction,
                title: engine.countdownText,
                subtitle: engine.nextReminderText,
                state: engine.state
            )

            actionRow

            TodayProgressView(
                completed: statsStore.today.completedCount,
                target: settingsStore.settings.dailyTarget,
                subtitle: statsStore.lastCompletedText
            )

            reminderText
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                engine.markCompleted()
            } label: {
                Label("已活动", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(.borderedProminent)

            Button {
                engine.snooze()
            } label: {
                Label("延后", systemImage: "clock.arrow.circlepath")
            }
            .buttonStyle(.bordered)

            Button {
                if case .paused = engine.state {
                    engine.resume()
                } else {
                    engine.pause()
                }
            } label: {
                Label(pauseTitle, systemImage: pauseIcon)
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.regular)
    }

    private var pauseTitle: String {
        if case .paused = engine.state { return "恢复" }
        return "暂停"
    }

    private var pauseIcon: String {
        if case .paused = engine.state { return "play.fill" }
        return "pause.fill"
    }

    @ViewBuilder
    private var reminderText: some View {
        if let text = engine.currentReminderText {
            GroupBox {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "bell.badge")
                        .foregroundStyle(.blue)
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Spacer()
                }
            } label: {
                Text("当前提醒")
                    .font(.subheadline.weight(.semibold))
            }
        }
    }
}

private struct TodayProgressView: View {
    let completed: Int
    let target: Int
    let subtitle: String

    private var progress: Double {
        guard target > 0 else { return 0 }
        return min(Double(completed) / Double(target), 1)
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("完成进度")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(completed)/\(target)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(progress >= 1 ? .green : .primary)
                }

                ProgressView(value: progress)
                    .tint(progress >= 1 ? .green : .blue)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } label: {
            Label("今日活动", systemImage: "chart.bar.fill")
                .font(.subheadline.weight(.semibold))
        }
    }
}
