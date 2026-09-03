import SwiftUI

enum TimerRingLayout {
    static let diameter: CGFloat = 168
    static let accessibilityDiameter: CGFloat = 200
    static let lineWidth: CGFloat = 10
    static let strokeInset = lineWidth / 2
    static let partialLineCap: CGLineCap = .butt
    static let compactSubtitleWidth: CGFloat = 132
    static let compactSubtitleLineLimit = 2
    static let compactTitleWidth = diameter - 28
    static let compactTitleMinimumScale: CGFloat = 0.65

    static func diameter(usesAccessibilityLayout: Bool) -> CGFloat {
        usesAccessibilityLayout ? accessibilityDiameter : diameter
    }
}

enum TimerRingProgress {
    static func resolve(
        progress: Double,
        state: ReminderRunState,
        phase: ReminderPhase
    ) -> Double {
        let clampedProgress = min(max(progress, 0), 1)

        switch state {
        case .paused, .disabled, .outsideHours:
            return 0
        case .due:
            return phase == .guiding ? clampedProgress : 1
        case .running:
            return clampedProgress
        }
    }
}

enum TimerRingAccessibility {
    static func value(
        title: String,
        subtitle: String,
        language: AppLanguage
    ) -> String {
        language.text("\(title)，\(subtitle)", "\(title), \(subtitle)")
    }
}

struct TimerRingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title) private var scaledTitleSize: CGFloat = 28
    @ScaledMetric(relativeTo: .body) private var scaledIconSize: CGFloat = 18
    let progress: Double
    let contextLabel: String
    let title: String
    let subtitle: String
    let state: ReminderRunState
    let phase: ReminderPhase
    var language: AppLanguage = .simplifiedChinese

    var body: some View {
        VStack(spacing: usesAccessibilityLayout ? 8 : 0) {
            ringSurface
                .frame(width: ringDiameter, height: ringDiameter)

            if usesAccessibilityLayout {
                VStack(spacing: 3) {
                    Text(contextLabel)
                        .font(.body.weight(.medium))

                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(contextLabel)
        .accessibilityValue(TimerRingAccessibility.value(
            title: title,
            subtitle: subtitle,
            language: language
        ))
    }

    private var ringSurface: some View {
        ZStack {
            Circle()
                .inset(by: TimerRingLayout.strokeInset)
                .stroke(.quaternary, lineWidth: TimerRingLayout.lineWidth)
                .accessibilityHidden(true)

            progressRing

            VStack(spacing: 4) {
                if !usesAccessibilityLayout {
                    Text(contextLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: icon)
                    .font(
                        .system(
                            size: min(scaledIconSize, 28),
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(ringColor)
                    .accessibilityHidden(true)

                Text(title)
                    .font(
                        .system(
                            size: min(scaledTitleSize, 44),
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .monospacedDigit()
                    .minimumScaleFactor(TimerRingLayout.compactTitleMinimumScale)
                    .lineLimit(1)
                    .frame(maxWidth: TimerRingLayout.compactTitleWidth)

                if !usesAccessibilityLayout {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(TimerRingLayout.compactSubtitleLineLimit)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: TimerRingLayout.compactSubtitleWidth)
                }
            }
            .padding(.horizontal, 14)
        }
    }

    private var usesAccessibilityLayout: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    private var ringDiameter: CGFloat {
        TimerRingLayout.diameter(usesAccessibilityLayout: usesAccessibilityLayout)
    }

    private var ringProgress: Double {
        TimerRingProgress.resolve(
            progress: progress,
            state: state,
            phase: phase
        )
    }

    @ViewBuilder
    private var progressRing: some View {
        if ringProgress >= 1 {
            Circle()
                .inset(by: TimerRingLayout.strokeInset)
                .stroke(
                    ringColor.gradient,
                    style: StrokeStyle(
                        lineWidth: TimerRingLayout.lineWidth,
                        lineCap: .round
                    )
                )
                .accessibilityHidden(true)
        } else {
            Circle()
                .inset(by: TimerRingLayout.strokeInset)
                .trim(from: 0, to: ringProgress)
                .stroke(
                    ringColor.gradient,
                    style: StrokeStyle(
                        lineWidth: TimerRingLayout.lineWidth,
                        lineCap: TimerRingLayout.partialLineCap
                    )
                )
                .rotationEffect(.degrees(-90))
                .animation(
                    reduceMotion ? nil : .smooth(duration: 0.35),
                    value: ringProgress
                )
                .accessibilityHidden(true)
        }
    }

    private var ringColor: Color {
        switch state {
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

    private var icon: String {
        switch state {
        case .running:
            return "timer"
        case .paused:
            return "pause.circle.fill"
        case .outsideHours:
            return "moon.fill"
        case .disabled:
            return "power.circle.fill"
        case .due:
            return "figure.walk.circle.fill"
        }
    }
}
