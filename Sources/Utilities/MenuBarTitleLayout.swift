import Foundation
import CoreGraphics

enum MenuBarTitleLayout {
    static func fixedWidth(
        for state: ReminderRunState,
        remainingInterval: TimeInterval,
        language: AppLanguage = .simplifiedChinese
    ) -> CGFloat {
        switch state {
        case .running:
            let seconds = max(Int(remainingInterval.rounded()), 0)
            let hours = seconds / 3_600

            if hours > 0 {
                return String(hours).count > 1 ? 70 : 62
            }

            return 44
        case .paused, .disabled, .due, .outsideHours:
            return language.resolvedLanguage() == .english ? 48 : 36
        }
    }

    static func measurementText(
        for state: ReminderRunState,
        remainingInterval: TimeInterval,
        language: AppLanguage = .simplifiedChinese
    ) -> String {
        switch state {
        case .running:
            return countdownMeasurementText(for: remainingInterval)
        case .paused:
            return language.text("暂停", "Pause")
        case .disabled:
            return language.text("关闭", "Off")
        case .due:
            return language.text("活动", "Move")
        case .outsideHours:
            return language.text("休息", "Rest")
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
