import Foundation

enum TimeFormatting {
    static func countdown(_ interval: TimeInterval) -> String {
        let seconds = max(Int(interval.rounded()), 0)
        let minutes = seconds / 60
        let remainder = seconds % 60

        if minutes >= 60 {
            let hours = minutes / 60
            let minutePart = minutes % 60
            return "\(hours)h \(minutePart)m"
        }

        return String(format: "%02d:%02d", minutes, remainder)
    }

    static func compactCountdown(_ interval: TimeInterval) -> String {
        let seconds = max(Int(interval.rounded()), 0)
        if seconds < 60 { return "Now" }

        let minutes = Int(ceil(Double(seconds) / 60.0))
        if minutes < 60 { return "\(minutes)m" }

        let hours = minutes / 60
        let minutePart = minutes % 60
        return minutePart == 0 ? "\(hours)h" : "\(hours)h\(minutePart)m"
    }

    static func menuBarCountdown(_ interval: TimeInterval) -> String {
        let seconds = max(Int(interval.rounded()), 0)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainder = seconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainder)
        }

        return String(format: "%02d:%02d", minutes, remainder)
    }

    static func clockText(for minutes: Int) -> String {
        let hour = minutes / 60
        let minute = minutes % 60
        return String(format: "%02d:%02d", hour, minute)
    }
}
