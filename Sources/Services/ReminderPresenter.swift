import AppKit
import SwiftUI

enum ReminderAction {
    case completed
    case snoozed
    case pausedToday
    case dismissed
}

@MainActor
final class ReminderPresenter: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var completion: ((ReminderAction) -> Void)?

    func present(message: String, completion: @escaping (ReminderAction) -> Void) {
        present(content: ReminderPopupView(message: message) { [weak self] action in
            self?.dismiss()
            completion(action)
        }, completion: completion)
    }

    func presentGuide(endsAt: Date, completion: @escaping (ReminderAction) -> Void) {
        present(content: ReminderPopupView(
            message: "按你的身体状况，换个姿势或活动 60 秒。",
            isGuiding: true,
            guideEndsAt: endsAt
        ) { [weak self] action in
            self?.dismiss()
            completion(action)
        }, completion: completion)
    }

    private func present(content: some View, completion: @escaping (ReminderAction) -> Void) {
        dismiss()
        self.completion = completion

        let hostingController = NSHostingController(rootView: content)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
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

    func dismiss() {
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
