import SwiftUI

struct TodayProgressPresentation: Equatable {
    let dailyGoalCompleted: Int
    let reminderCompleted: Int
    let target: Int
    let reminderOpportunities: Int
    let responseRate: Double?
    let proactiveActivities: Int
    let legacyUnclassified: Int
    let subtitle: String

    var progress: Double {
        guard target > 0 else { return 0 }
        return min(Double(dailyGoalCompleted) / Double(target), 1)
    }

    var showsActivityBreakdown: Bool {
        reminderOpportunities > 0 ||
            dailyGoalCompleted > 0 ||
            reminderCompleted > 0 ||
            proactiveActivities > 0 ||
            legacyUnclassified > 0
    }

    var responseText: String? {
        guard let responseRate, reminderOpportunities > 0 else { return nil }
        let percentage = Int((responseRate * 100).rounded())
        return "\(percentage)% · \(reminderCompleted)/\(reminderOpportunities) 次提醒"
    }
}

struct TodayPanelView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let engine: ReminderEngine
    let presentation: MenuPanelPresentation
    let progressPresentation: TodayProgressPresentation
    let statsErrorMessage: String?
    let onOpenSettings: (SettingsPane?) -> Void

    var body: some View {
        VStack(spacing: 14) {
            TimerRingView(
                progress: presentation.progressFraction,
                contextLabel: presentation.timerContextLabel,
                title: presentation.countdownText,
                subtitle: presentation.nextReminderText,
                state: presentation.state,
                phase: presentation.phase
            )

            actionSurface

            TodayProgressView(presentation: progressPresentation)

            currentReminder

            if let statsErrorMessage {
                Label {
                    Text(statsErrorMessage)
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "externaldrive.badge.exclamationmark")
                        .foregroundStyle(.orange)
                }
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var actionSurface: some View {
        switch presentation.actionMode {
        case .running(let canRecordManualActivity):
            runningActions(canRecordManualActivity: canRecordManualActivity)
            .controlSize(.regular)

        case .awaitingResponse(let canSnooze):
            VStack(spacing: 8) {
                Button {
                    engine.startActivity()
                } label: {
                    Label("开始 1 分钟活动", systemImage: "figure.walk")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .help("开始 60 秒活动；完整完成后才会计入目标")

                awaitingSecondaryActions(canSnooze: canSnooze)
            }
            .controlSize(.regular)

        case .snoozed(let statusText):
            snoozedActions(statusText: statusText)
            .controlSize(.regular)

        case .guiding:
            StatusSurface(
                text: "活动进行中，请在引导弹窗中完成或取消",
                systemImage: "timer",
                color: .green
            )

        case .delivering:
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
                Text("正在发送活动提醒")
                    .font(.subheadline)
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 32)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("正在发送活动提醒")

        case .paused:
            Button {
                engine.resume()
            } label: {
                Label("恢复提醒", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

        case .outsideHours:
            Button {
                onOpenSettings(.schedule)
            } label: {
                Label("调整提醒时段…", systemImage: "calendar")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

        case .disabled:
            Button {
                onOpenSettings(.general)
            } label: {
                Label("打开设置…", systemImage: "gearshape")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
    }

    @ViewBuilder
    private func runningActions(canRecordManualActivity: Bool) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 8) {
                runningPrimaryButton(
                    canRecordManualActivity: canRecordManualActivity,
                    fillsWidth: true
                )
                pauseButton(fillsWidth: true)
                moreMenu(fillsWidth: true)
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    runningPrimaryButton(
                        canRecordManualActivity: canRecordManualActivity,
                        fillsWidth: true
                    )
                    pauseButton(fillsWidth: false)
                    moreMenu(fillsWidth: false)
                }

                VStack(spacing: 8) {
                    runningPrimaryButton(
                        canRecordManualActivity: canRecordManualActivity,
                        fillsWidth: true
                    )
                    HStack(spacing: 8) {
                        pauseButton(fillsWidth: true)
                        moreMenu(fillsWidth: true)
                    }
                }
            }
        }
    }

    private func runningPrimaryButton(
        canRecordManualActivity: Bool,
        fillsWidth: Bool
    ) -> some View {
        Button {
            engine.startActivity()
        } label: {
            Label("主动活动 1 分钟", systemImage: "figure.walk")
                .lineLimit(1)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!canRecordManualActivity)
        .help(
            canRecordManualActivity
                ? "主动开始 60 秒活动；完成后计入目标，通常保持原提醒时间"
                : "当前状态不能记录主动活动"
        )
    }

    private func pauseButton(fillsWidth: Bool) -> some View {
        Button {
            engine.pause()
        } label: {
            Label("暂停", systemImage: "pause.fill")
                .lineLimit(1)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
        }
        .buttonStyle(.bordered)
    }

    private func moreMenu(fillsWidth: Bool) -> some View {
        Menu {
            Button {
                engine.resetTimer()
            } label: {
                Label("从现在重新计时", systemImage: "arrow.clockwise")
            }

            Button {
                engine.pauseToday()
            } label: {
                Label("暂停今天", systemImage: "moon")
            }
        } label: {
            Label("更多", systemImage: "ellipsis.circle")
                .lineLimit(1)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
        }
        .menuStyle(.borderlessButton)
        .help("更多提醒操作")
    }

    @ViewBuilder
    private func awaitingSecondaryActions(canSnooze: Bool) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 8) {
                snoozeButton(canSnooze: canSnooze)
                pauseTodayButton()
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    snoozeButton(canSnooze: canSnooze)
                    pauseTodayButton()
                }
                VStack(spacing: 8) {
                    snoozeButton(canSnooze: canSnooze)
                    pauseTodayButton()
                }
            }
        }
    }

    private func snoozeButton(canSnooze: Bool) -> some View {
        Button("延后 5 分钟") {
            engine.snooze()
        }
        .buttonStyle(.bordered)
        .disabled(!canSnooze)
        .help(canSnooze ? "将本次提醒延后 5 分钟" : "本次提醒不能再次延后")
        .frame(maxWidth: .infinity)
    }

    private func pauseTodayButton() -> some View {
        Button("暂停今天") {
            engine.pauseToday()
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func snoozedActions(statusText: String) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            snoozedVerticalActions(statusText: statusText)
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    snoozedStatus(statusText)
                    resetButton()
                    pauseTodayButton()
                }
                snoozedVerticalActions(statusText: statusText)
            }
        }
    }

    private func snoozedVerticalActions(statusText: String) -> some View {
        VStack(spacing: 8) {
            snoozedStatus(statusText)
            resetButton()
            pauseTodayButton()
        }
    }

    private func snoozedStatus(_ statusText: String) -> some View {
        StatusSurface(
            text: statusText,
            systemImage: "clock.arrow.circlepath",
            color: .blue
        )
    }

    private func resetButton() -> some View {
        Button("重新计时") {
            engine.resetTimer()
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var currentReminder: some View {
        if let text = presentation.currentReminderText {
            GroupBox {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "bell.badge")
                        .foregroundStyle(.blue)
                        .accessibilityHidden(true)
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

private struct StatusSurface: View {
    let text: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 32)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 7))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

private struct TodayProgressView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let presentation: TodayProgressPresentation

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("目标进度")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(presentation.dailyGoalCompleted)/\(presentation.target)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(presentation.progress >= 1 ? .green : .primary)
                }

                ProgressView(value: presentation.progress)
                    .tint(presentation.progress >= 1 ? .green : .accentColor)
                    .accessibilityLabel("今日活动目标")
                    .accessibilityValue(
                        "\(presentation.dailyGoalCompleted)/\(presentation.target)"
                    )

                if presentation.showsActivityBreakdown {
                    activityBreakdown

                    if presentation.legacyUnclassified > 0 {
                        Label(
                            "未分类记录 \(presentation.legacyUnclassified) 次",
                            systemImage: "archivebox"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    if let responseText = presentation.responseText {
                        Text("提醒响应：\(responseText)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(presentation.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } label: {
            Label("今日统计", systemImage: "chart.bar.fill")
                .font(.subheadline.weight(.semibold))
        }
    }

    @ViewBuilder
    private var activityBreakdown: some View {
        if dynamicTypeSize.isAccessibilitySize {
            activityBreakdownColumn
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    reminderActivityLabel
                    proactiveActivityLabel
                }
                activityBreakdownColumn
            }
        }
    }

    private var activityBreakdownColumn: some View {
        VStack(alignment: .leading, spacing: 5) {
            reminderActivityLabel
            proactiveActivityLabel
        }
    }

    private var reminderActivityLabel: some View {
        Label(
            "提醒后 \(presentation.reminderCompleted) 次",
            systemImage: "bell.badge"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var proactiveActivityLabel: some View {
        Label(
            "主动 \(presentation.proactiveActivities) 次",
            systemImage: "figure.walk"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
