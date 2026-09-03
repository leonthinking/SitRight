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
    var language: AppLanguage = .simplifiedChinese

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
        let opportunityText = language.quantity(
            reminderOpportunities,
            simplifiedChineseUnit: "次提醒",
            englishSingular: "reminder",
            englishPlural: "reminders"
        )
        return language.text(
            "\(percentage)% · \(reminderCompleted)/\(opportunityText)",
            "\(percentage)% · \(reminderCompleted)/\(opportunityText)"
        )
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
                phase: presentation.phase,
                language: progressPresentation.language
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
                    Label(
                        progressPresentation.language.text(
                            "开始 1 分钟活动",
                            "Start a 1-minute break"
                        ),
                        systemImage: "figure.walk"
                    )
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .help(progressPresentation.language.text(
                    "开始 60 秒活动；完整完成后才会计入目标",
                    "Start a 60-second break. It counts toward your goal only when completed."
                ))

                awaitingSecondaryActions(canSnooze: canSnooze)
            }
            .controlSize(.regular)

        case .snoozed(let statusText):
            snoozedActions(statusText: statusText)
            .controlSize(.regular)

        case .guiding:
            StatusSurface(
                text: progressPresentation.language.text(
                    "活动进行中，请在引导弹窗中完成或取消",
                    "A break is in progress. Complete or cancel it in the guide window."
                ),
                systemImage: "timer",
                color: .green
            )

        case .delivering:
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
                Text(progressPresentation.language.text(
                    "正在发送活动提醒",
                    "Sending activity reminder"
                ))
                    .font(.subheadline)
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 32)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(progressPresentation.language.text(
                "正在发送活动提醒",
                "Sending activity reminder"
            ))

        case .paused:
            Button {
                engine.resume()
            } label: {
                Label(
                    progressPresentation.language.text("恢复提醒", "Resume reminders"),
                    systemImage: "play.fill"
                )
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

        case .outsideHours:
            Button {
                onOpenSettings(.schedule)
            } label: {
                Label(
                    progressPresentation.language.text(
                        "调整提醒时段…",
                        "Adjust Reminder Schedule…"
                    ),
                    systemImage: "calendar"
                )
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

        case .disabled:
            Button {
                onOpenSettings(.general)
            } label: {
                Label(
                    progressPresentation.language.text("打开设置…", "Open Settings…"),
                    systemImage: "gearshape"
                )
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
            Label(
                progressPresentation.language.text(
                    "主动活动 1 分钟",
                    "Take a 1-minute break"
                ),
                systemImage: "figure.walk"
            )
                .lineLimit(1)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!canRecordManualActivity)
        .help(
            canRecordManualActivity
                ? progressPresentation.language.text(
                    "主动开始 60 秒活动；完成后计入目标，通常保持原提醒时间",
                    "Start a proactive 60-second break. Completing it counts toward your goal and usually keeps the original reminder time."
                )
                : progressPresentation.language.text(
                    "当前状态不能记录主动活动",
                    "A proactive break cannot be recorded in the current state"
                )
        )
    }

    private func pauseButton(fillsWidth: Bool) -> some View {
        Button {
            engine.pause()
        } label: {
            Label(
                progressPresentation.language.text("暂停", "Pause"),
                systemImage: "pause.fill"
            )
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
                Label(
                    progressPresentation.language.text(
                        "从现在重新计时",
                        "Restart timer now"
                    ),
                    systemImage: "arrow.clockwise"
                )
            }

            Button {
                engine.pauseToday()
            } label: {
                Label(
                    progressPresentation.language.text("暂停今天", "Pause for today"),
                    systemImage: "moon"
                )
            }
        } label: {
            Label(
                progressPresentation.language.text("更多", "More"),
                systemImage: "ellipsis.circle"
            )
                .lineLimit(1)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
        }
        .menuStyle(.borderlessButton)
        .help(progressPresentation.language.text(
            "更多提醒操作",
            "More reminder actions"
        ))
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
        Button(progressPresentation.language.text(
            "延后 5 分钟",
            "Remind me in 5 minutes"
        )) {
            engine.snooze()
        }
        .buttonStyle(.bordered)
        .disabled(!canSnooze)
        .help(canSnooze
            ? progressPresentation.language.text(
                "将本次提醒延后 5 分钟",
                "Snooze this reminder for 5 minutes"
            )
            : progressPresentation.language.text(
                "本次提醒不能再次延后",
                "This reminder cannot be snoozed again"
            ))
        .frame(maxWidth: .infinity)
    }

    private func pauseTodayButton() -> some View {
        Button(progressPresentation.language.text("暂停今天", "Pause for today")) {
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
        Button(progressPresentation.language.text("重新计时", "Restart timer")) {
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
                Text(progressPresentation.language.text("当前提醒", "Current reminder"))
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
                    Text(presentation.language.text("目标进度", "Goal progress"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(presentation.dailyGoalCompleted)/\(presentation.target)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(presentation.progress >= 1 ? .green : .primary)
                }

                ProgressView(value: presentation.progress)
                    .tint(presentation.progress >= 1 ? .green : .accentColor)
                    .accessibilityLabel(presentation.language.text(
                        "今日活动目标",
                        "Today's activity goal"
                    ))
                    .accessibilityValue(
                        "\(presentation.dailyGoalCompleted)/\(presentation.target)"
                    )

                if presentation.showsActivityBreakdown {
                    activityBreakdown

                    if presentation.legacyUnclassified > 0 {
                        Label(
                            presentation.language.text(
                                "未分类记录 \(presentation.legacyUnclassified) 次",
                                "Unclassified records: \(presentation.legacyUnclassified)"
                            ),
                            systemImage: "archivebox"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    if let responseText = presentation.responseText {
                        Text(presentation.language.text(
                            "提醒响应：\(responseText)",
                            "Reminder response: \(responseText)"
                        ))
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
            Label(
                presentation.language.text("今日统计", "Today's stats"),
                systemImage: "chart.bar.fill"
            )
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
            presentation.language.text(
                "提醒后 \(presentation.reminderCompleted) 次",
                "After reminders: \(presentation.reminderCompleted)"
            ),
            systemImage: "bell.badge"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var proactiveActivityLabel: some View {
        Label(
            presentation.language.text(
                "主动 \(presentation.proactiveActivities) 次",
                "Proactive: \(presentation.proactiveActivities)"
            ),
            systemImage: "figure.walk"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
