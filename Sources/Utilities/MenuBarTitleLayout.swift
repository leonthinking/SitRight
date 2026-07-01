import Foundation
import CoreGraphics

enum MenuBarTitleLayout {
    static func fixedWidth(for state: ReminderRunState, remainingInterval: TimeInterval) -> CGFloat {
        switch state {
        case .running:
            let seconds = max(Int(remainingInterval.rounded()), 0)
            let hours = seconds / 3_600

            if hours > 0 {
                return String(hours).count > 1 ? 70 : 62
            }

            return 44
        case .paused:
            return 52
        case .disabled:
            return 28
        case .due, .outsideHours:
            return 36
        }
    }

    static func measurementText(for state: ReminderRunState, remainingInterval: TimeInterval) -> String {
        switch state {
        case .running:
            return countdownMeasurementText(for: remainingInterval)
        case .paused:
            return "Paused"
        case .disabled:
            return "Off"
        case .due:
            return "Move"
        case .outsideHours:
            return "Rest"
        }
    }

    private static func countdownMeasurementText(for interval: TimeInterval) -> String {
        let seconds = max(Int(interval.rounded()), 0)
        let hours = seconds / 3_600

        if hours > 0 {
            let hourDigits = max(String(hours).count, 1)
            return "\(String(repeating: "8", count: hourDigits)):88:88"
        }

        return "88:88"
    }
}
