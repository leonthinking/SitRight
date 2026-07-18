import SwiftUI

struct ReminderPopupView: View {
    let message: String
    let isGuiding: Bool
    let guideEndsAt: Date?
    let onAction: (ReminderAction) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        message: String,
        isGuiding: Bool = false,
        guideEndsAt: Date? = nil,
        onAction: @escaping (ReminderAction) -> Void
    ) {
        self.message = message
        self.isGuiding = isGuiding
        self.guideEndsAt = guideEndsAt
        self.onAction = onAction
    }

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(.green.opacity(0.15))
                    .frame(width: 64, height: 64)
                Image(systemName: "timer")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.green)
            }

            VStack(spacing: 8) {
                Text(isGuiding ? "活动进行中" : "到活动时间了")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text(message)
                    .font(.title3.weight(.medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                if isGuiding, let guideEndsAt {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let remaining = max(Int(ceil(guideEndsAt.timeIntervalSince(context.date))), 0)
                        Text("还剩 \(remaining) 秒")
                            .font(.title2.monospacedDigit().weight(.semibold))
                            .accessibilityLabel("活动剩余时间")
                            .accessibilityValue("\(remaining) 秒")
                    }
                }
            }

            HStack(spacing: 10) {
                if isGuiding {
                    Button {
                        onAction(.dismissed)
                    } label: {
                        Label("取消活动", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.cancelAction)
                } else {
                    Button {
                        onAction(.completed)
                    } label: {
                        Label("开始 1 分钟活动", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)

                    Button {
                        onAction(.snoozed)
                    } label: {
                        Label("延后 5 分钟", systemImage: "clock.arrow.circlepath")
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
        }
        .padding(28)
        .frame(width: 420, height: 300)
        .background(.regularMaterial)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: message)
        .onExitCommand {
            onAction(.dismissed)
        }
    }
}
