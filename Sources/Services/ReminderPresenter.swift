import AppKit
import SwiftUI

enum ReminderAction: Hashable {
    case completed
    case snoozed
    case pausedToday
    case dismissed
}

enum ReminderPanelMeasurementTrigger: Equatable {
    case presentation
    case countdownTick
}

enum ReminderPanelSizingPolicy {
    static let width: CGFloat = 420
    static let minimumHeight: CGFloat = 300
    static let maximumContentHeight: CGFloat = 720
    static let screenEdgeMargin: CGFloat = 48
    static let hostingSizingOptions: NSHostingSizingOptions = []

    static func requestsMeasurement(for trigger: ReminderPanelMeasurementTrigger) -> Bool {
        trigger == .presentation
    }

    static func maximumHeight(for visibleFrame: NSRect?) -> CGFloat {
        guard let visibleFrame else { return maximumContentHeight }
        return min(
            maximumContentHeight,
            max(floor(visibleFrame.height - screenEdgeMargin), 1)
        )
    }

    static func fittingConstraint(maximumHeight: CGFloat) -> NSSize {
        NSSize(
            width: width,
            height: min(max(maximumHeight, 1), maximumContentHeight)
        )
    }

    static func normalized(
        _ measuredSize: NSSize,
        maximumHeight: CGFloat = maximumContentHeight
    ) -> NSSize {
        let clampedMaximumHeight = min(max(maximumHeight, 1), maximumContentHeight)
        let clampedMinimumHeight = min(minimumHeight, clampedMaximumHeight)
        return NSSize(
            width: width,
            height: min(
                max(ceil(measuredSize.height), clampedMinimumHeight),
                clampedMaximumHeight
            )
        )
    }
}

@MainActor
final class GuidePresentationGate {
    private var isWaitingForPopoverClose = false
    private var pendingPresentation: (() -> Void)?

    func waitForPopoverToClose() {
        isWaitingForPopoverClose = true
    }

    func submit(_ presentation: @escaping () -> Void) {
        guard isWaitingForPopoverClose else {
            presentation()
            return
        }
        pendingPresentation = presentation
    }

    func popoverDidClose() {
        isWaitingForPopoverClose = false
        let presentation = pendingPresentation
        pendingPresentation = nil
        presentation?()
    }

    func cancel() {
        isWaitingForPopoverClose = false
        pendingPresentation = nil
    }
}

@MainActor
final class ReminderPresenter: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var completion: ((ReminderAction) -> Void)?
    private let guidePresentationGate = GuidePresentationGate()

    func present(message: String, completion: @escaping (ReminderAction) -> Void) {
        present(content: ReminderPopupView(message: message) { [weak self] action in
            self?.dismiss()
            completion(action)
        }, completion: completion)
    }

    func presentGuide(endsAt: Date, completion: @escaping (ReminderAction) -> Void) {
        guidePresentationGate.submit { [weak self] in
            guard let self else { return }
            self.present(content: ReminderPopupView(
                message: "按你的身体状况，换个姿势或活动 60 秒。",
                isGuiding: true,
                guideEndsAt: endsAt
            ) { [weak self] action in
                self?.dismiss()
                completion(action)
            }, completion: completion)
        }
    }

    func waitForPopoverToCloseBeforePresentingGuide() {
        guidePresentationGate.waitForPopoverToClose()
    }

    func popoverDidCloseBeforeGuidePresentation() {
        guidePresentationGate.popoverDidClose()
    }

    private func present(content: some View, completion: @escaping (ReminderAction) -> Void) {
        dismiss()
        self.completion = completion

        let hostingController = NSHostingController(rootView: content)
        hostingController.sizingOptions = ReminderPanelSizingPolicy.hostingSizingOptions
        let maximumHeight = ReminderPanelSizingPolicy.maximumHeight(
            for: NSScreen.main?.visibleFrame
        )
        let contentSize = measuredContentSize(
            for: hostingController,
            maximumHeight: maximumHeight,
            trigger: .presentation
        )
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .fullSizeContentView, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.title = "SitRight 坐正"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = hostingController
        panel.delegate = self
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.closeButton)?.isHidden = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false

        self.panel = panel
        panel.center()
        panel.makeKey()
        panel.orderFrontRegardless()
    }

    private func measuredContentSize<Content: View>(
        for hostingController: NSHostingController<Content>,
        maximumHeight: CGFloat,
        trigger: ReminderPanelMeasurementTrigger
    ) -> NSSize {
        guard ReminderPanelSizingPolicy.requestsMeasurement(for: trigger) else {
            return NSSize(
                width: ReminderPanelSizingPolicy.width,
                height: ReminderPanelSizingPolicy.minimumHeight
            )
        }
        let measuredSize = hostingController.sizeThatFits(
            in: ReminderPanelSizingPolicy.fittingConstraint(
                maximumHeight: maximumHeight
            )
        )
        return ReminderPanelSizingPolicy.normalized(
            measuredSize,
            maximumHeight: maximumHeight
        )
    }

    func dismiss() {
        guidePresentationGate.cancel()
        completion = nil
        panel?.close()
        panel = nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let handler = completion
        completion = nil
        handler?(.dismissed)
        return true
    }
}
