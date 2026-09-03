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

enum ReminderPopupLayoutElement: Hashable {
    case scrollViewport
    case message
    case countdown
    case cancel
    case done
    case completed
    case snoozed
    case pausedToday
}

private enum ReminderPopupLayoutCoordinateSpace {
    static let name = "ReminderPopupLayout"
}

private struct ReminderPopupLayoutReporter: ViewModifier {
    let element: ReminderPopupLayoutElement
    let observer: ((ReminderPopupLayoutElement, CGRect) -> Void)?

    func body(content: Content) -> some View {
        content.background {
            if let observer {
                GeometryReader { proxy in
                    let frame = proxy.frame(
                        in: .named(ReminderPopupLayoutCoordinateSpace.name)
                    )
                    Color.clear
                        .onAppear {
                            observer(element, frame)
                        }
                        .onChange(of: frame) { _, newFrame in
                            observer(element, newFrame)
                        }
                }
            }
        }
    }
}

private extension View {
    func reportReminderPopupLayout(
        _ element: ReminderPopupLayoutElement,
        to observer: ((ReminderPopupLayoutElement, CGRect) -> Void)?
    ) -> some View {
        modifier(ReminderPopupLayoutReporter(element: element, observer: observer))
    }
}

struct ReminderPopupView: View {
    let message: String
    let language: AppLanguage
    let isGuiding: Bool
    let isCompletion: Bool
    let guideEndsAt: Date?
    let onAction: (ReminderAction) -> Void
    let layoutObserver: ((ReminderPopupLayoutElement, CGRect) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        message: String,
        language: AppLanguage = .simplifiedChinese,
        isGuiding: Bool = false,
        isCompletion: Bool = false,
        guideEndsAt: Date? = nil,
        onAction: @escaping (ReminderAction) -> Void,
        layoutObserver: ((ReminderPopupLayoutElement, CGRect) -> Void)? = nil
    ) {
        self.message = message
        self.language = language
        self.isGuiding = isGuiding
        self.isCompletion = isCompletion
        self.guideEndsAt = guideEndsAt
        self.onAction = onAction
        self.layoutObserver = layoutObserver
    }

    var body: some View {
        ViewThatFits(in: .vertical) {
            popupContent
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                popupContent
                    .padding(.trailing, 4)
            }
            .reportReminderPopupLayout(.scrollViewport, to: layoutObserver)
        }
        .padding(28)
        .frame(width: ReminderPanelSizingPolicy.width)
        .coordinateSpace(name: ReminderPopupLayoutCoordinateSpace.name)
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
                Image(systemName: isCompletion ? "checkmark.circle.fill" : "timer")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.green)
            }
            .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(
                    isCompletion
                        ? language.text("活动完成", "Break complete")
                        : (isGuiding
                            ? language.text("活动进行中", "Break in progress")
                            : language.text("到活动时间了", "Time to move"))
                )
                    .font(.title.weight(.bold))
                    .fontDesign(.rounded)
                Text(message)
                    .font(.title3.weight(.medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .reportReminderPopupLayout(.message, to: layoutObserver)

                if isGuiding, let guideEndsAt {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let remaining = max(Int(ceil(guideEndsAt.timeIntervalSince(context.date))), 0)
                        let remainingText = language.quantity(
                            remaining,
                            simplifiedChineseUnit: "秒",
                            englishSingular: "second",
                            englishPlural: "seconds"
                        )
                        Text(language.text("还剩 \(remainingText)", "\(remainingText) remaining"))
                            .font(.title2.monospacedDigit().weight(.semibold))
                            .accessibilityLabel(language.text("活动剩余时间", "Break time remaining"))
                            .accessibilityValue(remainingText)
                            .reportReminderPopupLayout(.countdown, to: layoutObserver)
                    }
                }
            }

            actionSurface
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var actionSurface: some View {
        if isCompletion {
            Button(language.text("知道了", "Done")) {
                onAction(.dismissed)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .reportReminderPopupLayout(.done, to: layoutObserver)
            .accessibilityHint(language.text(
                "关闭活动完成反馈",
                "Close the break completion message"
            ))
        } else if isGuiding {
            Button {
                onAction(.dismissed)
            } label: {
                Label(language.text("取消活动", "Cancel break"), systemImage: "xmark.circle")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.cancelAction)
            .reportReminderPopupLayout(.cancel, to: layoutObserver)
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
                    language.text("开始 1 分钟活动", "Start a 1-minute break"),
                    systemImage: "arrow.triangle.2.circlepath"
                )
                .frame(maxWidth: fillsWidth ? .infinity : nil)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .reportReminderPopupLayout(.completed, to: layoutObserver)

        case .snoozed:
            Button {
                onAction(.snoozed)
            } label: {
                Label(
                    language.text("延后 5 分钟", "Remind me in 5 minutes"),
                    systemImage: "clock.arrow.circlepath"
                )
                    .frame(maxWidth: fillsWidth ? .infinity : nil)
            }
            .buttonStyle(.bordered)
            .reportReminderPopupLayout(.snoozed, to: layoutObserver)

        case .pausedToday:
            Button {
                onAction(.pausedToday)
            } label: {
                Label(language.text("暂停今天", "Pause for today"), systemImage: "moon")
                    .frame(maxWidth: fillsWidth ? .infinity : nil)
            }
            .buttonStyle(.bordered)
            .reportReminderPopupLayout(.pausedToday, to: layoutObserver)

        case .dismissed:
            EmptyView()
        }
    }
}
