import AppKit
import SwiftUI

enum ReminderAction {
    case completed
    case snoozed
    case pausedToday
}

@MainActor
final class ReminderPresenter {
    private var panel: NSPanel?

    func present(message: String, completion: @escaping (ReminderAction) -> Void) {
        dismiss()

        let content = ReminderPopupView(message: message) { [weak self] action in
            self?.dismiss()
            completion(action)
        }

        let hostingController = NSHostingController(rootView: content)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
            styleMask: [.titled, .fullSizeContentView],
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
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.closeButton)?.isHidden = true

        self.panel = panel
        panel.center()
        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        panel?.close()
        panel = nil
    }
}
