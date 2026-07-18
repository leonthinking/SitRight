import SwiftUI

struct TodayPanelView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var statsStore: StatsStore
    let engine: ReminderEngine

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
                dailyGoalCompleted: statsStore.today.dailyGoalActivityCount,
                reminderCompleted: statsStore.today.reminderCompletedCount,
                target: settingsStore.settings.dailyTarget,
                reminderOpportunities: statsStore.today.reminderOpportunityCount,
                responseRate: statsStore.today.responseRate,
                proactiveActivities: statsStore.today.qualifiedProactiveCount,
                legacyUnclassified: statsStore.today.legacyUnclassifiedCount,
                subtitle: statsStore.lastCompletedText
            )

            reminderText

            if let error = statsStore.lastErrorMessage {
                Label(error, systemImage: "externaldrive.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                engine.startActivity()
            } label: {
                Label(activityActionTitle, systemImage: activityActionIcon)
                    .frame(width: 100)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!engine.canCompleteReminder && !engine.canRecordManualActivity)
            .help(activityActionHelp)

            Button {
                engine.snooze()
            } label: {
                Label("延后", systemImage: "clock.arrow.circlepath")
                    .frame(width: 70)
            }
            .buttonStyle(.bordered)
            .disabled(!engine.canSnooze)

            Button {
                if case .paused = engine.state {
                    engine.resume()
                } else {
                    engine.pause()
                }
            } label: {
                Label(pauseTitle, systemImage: pauseIcon)
                    .frame(width: 70)
            }
            .buttonStyle(.bordered)
            .disabled(!settingsStore.settings.remindersEnabled)
        }
        .controlSize(.regular)
    }

    private var activityActionTitle: String {
        if engine.phase == .guiding { return "活动进行中" }
        return engine.canCompleteReminder ? "开始 1 分钟" : "主动活动 1 分钟"
    }

    private var activityActionIcon: String {
        engine.phase == .guiding ? "timer" : "arrow.triangle.2.circlepath"
    }

    private var activityActionHelp: String {
        if engine.canCompleteReminder {
            return "开始 60 秒活动；完整完成后才会计入目标"
        }
        if engine.canRecordManualActivity {
            return "主动开始 60 秒活动；完整完成后会计入目标并重新计时"
        }
        return "当前状态不能记录活动"
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
    let dailyGoalCompleted: Int
    let reminderCompleted: Int
    let target: Int
    let reminderOpportunities: Int
    let responseRate: Double?
    let proactiveActivities: Int
    let legacyUnclassified: Int
    let subtitle: String

    private var progress: Double {
        guard target > 0 else { return 0 }
        return min(Double(dailyGoalCompleted) / Double(target), 1)
    }

    private var responseText: String {
        guard let responseRate, reminderOpportunities > 0 else { return "暂无提醒" }
        let percentage = Int((responseRate * 100).rounded())
        return "\(percentage)% · \(reminderCompleted)/\(reminderOpportunities) 次提醒"
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("今日活动")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(dailyGoalCompleted)/\(target)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(progress >= 1 ? .green : .primary)
                }

                ProgressView(value: progress)
                    .tint(progress >= 1 ? .green : .blue)

                HStack(spacing: 14) {
                    Label("提醒后活动 \(reminderCompleted) 次", systemImage: "bell.badge")
                    Label("主动活动 \(proactiveActivities) 次", systemImage: "figure.walk")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if legacyUnclassified > 0 {
                    Label("未分类记录 \(legacyUnclassified) 次", systemImage: "archivebox")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if reminderOpportunities > 0 {
                    Text("提醒机会：\(responseText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } label: {
            Label("今日统计", systemImage: "chart.bar.fill")
                .font(.subheadline.weight(.semibold))
        }
    }
}
