import SwiftUI

struct ReminderPopupView: View {
    let message: String
    let onAction: (ReminderAction) -> Void

    @State private var completed = false

    var body: some View {
        ZStack {
            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(.green.opacity(0.15))
                        .frame(width: 64, height: 64)
                    Image(systemName: "figure.stand")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.green)
                }

                VStack(spacing: 8) {
                    Text("该起身活动了")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text(message)
                        .font(.title3.weight(.medium))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Button {
                        completed = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                            onAction(.completed)
                        }
                    } label: {
                        Label("我已活动", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        onAction(.snoozed)
                    } label: {
                        Label("稍后提醒", systemImage: "clock.arrow.circlepath")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        onAction(.pausedToday)
                    } label: {
                        Label("暂停今天", systemImage: "moon")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(28)

            if completed {
                Image(systemName: "sparkles")
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(.orange)
                    .scaleEffect(completed ? 1.2 : 0.2)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 420, height: 300)
        .background(.regularMaterial)
        .animation(.bouncy(duration: 0.45), value: completed)
    }
}
