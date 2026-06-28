import SwiftUI

struct TimerRingView: View {
    let progress: Double
    let title: String
    let subtitle: String
    let state: ReminderRunState

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 12)

            Circle()
                .trim(from: 0, to: ringProgress)
                .stroke(
                    ringColor.gradient,
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 0.35), value: ringProgress)

            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(ringColor)

                Text(title)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 20)
        }
        .frame(width: 220, height: 220)
        .frame(maxWidth: .infinity)
    }

    private var ringProgress: Double {
        switch state {
        case .paused, .disabled, .outsideHours:
            return 0
        case .due:
            return 1
        case .running:
            return min(max(progress, 0.02), 1)
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
