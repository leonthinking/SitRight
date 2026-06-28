import Foundation

struct DailyStats: Codable, Equatable {
    var dateKey: String
    var completedCount: Int
    var postponedCount: Int
    var skippedCount: Int
    var lastCompletedAt: Date?

    init(dateKey: String = DailyStats.makeDateKey(for: Date())) {
        self.dateKey = dateKey
        self.completedCount = 0
        self.postponedCount = 0
        self.skippedCount = 0
        self.lastCompletedAt = nil
    }

    static func makeDateKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
