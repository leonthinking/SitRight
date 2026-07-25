import SwiftUI

enum ReminderPopupActionAxis {
    case horizontal
    case vertical
}

enum ReminderPopupActionLayout {
    static func actions(for axis: ReminderPopupActionAxis) -> [ReminderAction] {
        switch axis {
        case .horizontal:
            return [.pausedToday, .snoozed, .completed]
        case .vertical:
            return [.completed, .snoozed, .pausedToday]
        }
    }
}

struct ReminderPopupView: View {
    let message: String
    let isGuiding: Bool
    let guideEndsAt: Date?
    let onAction: (ReminderAction) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
        ViewThatFits(in: .vertical) {
            popupContent
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                popupContent
                    .padding(.trailing, 4)
            }
        }
        .padding(28)
        .frame(width: ReminderPanelSizingPolicy.width)
        .background(.regularMaterial)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: message)
        .onExitCommand {
            onAction(.dismissed)
        }
    }

    private var popupContent: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(.green.opacity(0.15))
                    .frame(width: 64, height: 64)
                Image(systemName: "timer")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.green)
            }
            .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(isGuiding ? "活动进行中" : "到活动时间了")
                    .font(.title.weight(.bold))
                    .fontDesign(.rounded)
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

            actionSurface
        }
    }

    @ViewBuilder
    private var actionSurface: some View {
        if isGuiding {
            Button {
                onAction(.dismissed)
            } label: {
                Label("取消活动", systemImage: "xmark.circle")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.cancelAction)
        } else if dynamicTypeSize.isAccessibilitySize {
            verticalActions
        } else {
            ViewThatFits(in: .horizontal) {
                horizontalActions
                verticalActions
            }
        }
    }

    private var horizontalActions: some View {
        HStack(spacing: 10) {
            ForEach(
                ReminderPopupActionLayout.actions(for: .horizontal),
                id: \.self
            ) { action in
                actionButton(action, fillsWidth: false)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var verticalActions: some View {
        VStack(spacing: 10) {
            ForEach(
                ReminderPopupActionLayout.actions(for: .vertical),
                id: \.self
            ) { action in
                actionButton(action, fillsWidth: true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func actionButton(
        _ action: ReminderAction,
        fillsWidth: Bool
    ) -> some View {
        switch action {
        case .completed:
            Button {
                onAction(.completed)
            } label: {
                Label(
                    "开始 1 分钟活动",
                    systemImage: "arrow.triangle.2.circlepath"
                )
                .frame(maxWidth: fillsWidth ? .infinity : nil)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)

        case .snoozed:
            Button {
                onAction(.snoozed)
            } label: {
                Label("延后 5 分钟", systemImage: "clock.arrow.circlepath")
                    .frame(maxWidth: fillsWidth ? .infinity : nil)
            }
            .buttonStyle(.bordered)

        case .pausedToday:
            Button {
                onAction(.pausedToday)
            } label: {
                Label("暂停今天", systemImage: "moon")
                    .frame(maxWidth: fillsWidth ? .infinity : nil)
            }
            .buttonStyle(.bordered)

        case .dismissed:
            EmptyView()
        }
    }
}
