import AppKit
import Foundation

enum ReminderAccessibility {
    @MainActor
    static func announce(_ message: String) {
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }

    static func statusText(
        statusText: String,
        countdownText: String,
        state: ReminderRunState,
        showsCountdown: Bool
    ) -> String {
        guard showsCountdown, case .running = state else {
            return statusText
        }

        return "\(statusText)，剩余 \(countdownText)"
    }
}
