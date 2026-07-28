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
enum ReminderPanelFactory {
    static func make(
        contentViewController: NSViewController,
        contentSize: NSSize
    ) -> NSPanel {
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
        panel.contentViewController = contentViewController

        // With automatic hosting sizing disabled, attaching an
        // NSHostingController whose preferredContentSize is still zero can
        // collapse the panel. Reapply the measured size before it is shown.
        panel.setContentSize(contentSize)

        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.closeButton)?.isHidden = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        return panel
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
    private(set) var panel: NSPanel?
    private var completion: ((ReminderAction) -> Void)?
    private var automaticDismissTask: Task<Void, Never>?
    private var pendingGuideDeadline: Date?
    private let guidePresentationGate = GuidePresentationGate()

    func present(message: String, completion: @escaping (ReminderAction) -> Void) {
        present(content: ReminderPopupView(message: message) { [weak self] action in
            self?.handlePresentedAction(action)
        }, completion: completion)
    }

    func presentGuide(endsAt: Date, completion: @escaping (ReminderAction) -> Void) {
        pendingGuideDeadline = endsAt
        guidePresentationGate.submit { [weak self] in
            guard let self,
                  let currentDeadline = self.pendingGuideDeadline else {
                return
            }
            self.pendingGuideDeadline = nil
            self.present(content: ReminderPopupView(
                message: "按你的身体状况，换个姿势或活动 60 秒。",
                isGuiding: true,
                guideEndsAt: currentDeadline
            ) { [weak self] action in
                self?.handlePresentedAction(action)
            }, completion: completion)
        }
    }

    func updateGuide(endsAt: Date) {
        if pendingGuideDeadline != nil {
            // The menu popover may still be closing, so there is no panel to
            // update yet. Preserve the Engine's latest deadline for the
            // deferred presentation instead of showing a stale countdown.
            pendingGuideDeadline = endsAt
            return
        }
        guard let panel,
              let hostingController =
                panel.contentViewController as? NSHostingController<ReminderPopupView>,
              hostingController.rootView.isGuiding,
              !hostingController.rootView.isCompletion else {
            return
        }

        let contentSize = panel.contentRect(forFrameRect: panel.frame).size
        let currentView = hostingController.rootView
        hostingController.rootView = ReminderPopupView(
            message: currentView.message,
            isGuiding: true,
            guideEndsAt: endsAt,
            onAction: currentView.onAction
        )
        // A short system sleep freezes Engine guide progress. Refresh only
        // the wall-clock deadline used by TimelineView, while preserving the
        // existing panel and its manually controlled content size.
        panel.setContentSize(contentSize)
    }

    func presentGuideCompletion(message: String) {
        guard let panel else { return }

        completion = nil
        automaticDismissTask?.cancel()

        let contentSize = panel.contentRect(forFrameRect: panel.frame).size
        let hostingController = NSHostingController(
            rootView: ReminderPopupView(
                message: message,
                isCompletion: true,
                onAction: { [weak self] _ in
                    self?.dismissGuideCompletion()
                }
            )
        )
        hostingController.sizingOptions = ReminderPanelSizingPolicy.hostingSizingOptions
        panel.contentViewController = hostingController

        // Keep the already visible guide panel stable. As with initial
        // presentation, attaching a hosting controller with automatic sizing
        // disabled can otherwise collapse the content area.
        panel.setContentSize(contentSize)

        automaticDismissTask = Task { @MainActor [weak self, weak panel] in
            try? await Task.sleep(
                for: .seconds(ReminderTiming.completionFeedbackDuration)
            )
            guard !Task.isCancelled,
                  let self,
                  let panel,
                  self.panel === panel else {
                return
            }
            self.panel = nil
            self.automaticDismissTask = nil
            panel.close()
        }
    }

    func dismissGuideCompletion() {
        guard completion == nil else { return }

        automaticDismissTask?.cancel()
        automaticDismissTask = nil
        let panelToClose = panel
        panel = nil
        panelToClose?.close()
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
        let panel = ReminderPanelFactory.make(
            contentViewController: hostingController,
            contentSize: contentSize
        )

        panel.delegate = self

        self.panel = panel
        panel.center()
        panel.makeKey()
        panel.orderFrontRegardless()
    }

    func handlePresentedAction(_ action: ReminderAction) {
        guard let handler = takeCompletion() else { return }
        let panelToClose = panel
        panel = nil
        panelToClose?.close()
        handler(action)
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
        pendingGuideDeadline = nil
        automaticDismissTask?.cancel()
        automaticDismissTask = nil
        completion = nil
        let panelToClose = panel
        panel = nil
        panelToClose?.close()
    }

    private func takeCompletion() -> ((ReminderAction) -> Void)? {
        let handler = completion
        completion = nil
        return handler
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let handler = takeCompletion()
        handler?(.dismissed)
        return true
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingPanel = notification.object as? NSPanel,
              closingPanel === panel else {
            return
        }
        automaticDismissTask?.cancel()
        automaticDismissTask = nil
        panel = nil
    }
}
