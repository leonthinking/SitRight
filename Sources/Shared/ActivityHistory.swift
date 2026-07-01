import Foundation

struct ActivityDay: Codable, Equatable, Identifiable {
    var dateKey: String
    var completedCount: Int
    var postponedCount: Int
    var skippedCount: Int
    var lastCompletedAt: Date?

    var id: String { dateKey }

    init(dateKey: String = ActivityDay.makeDateKey(for: Date())) {
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

struct ActivityHistory: Codable, Equatable {
    private(set) var daysByKey: [String: ActivityDay]

    init(daysByKey: [String: ActivityDay] = [:]) {
        self.daysByKey = daysByKey
    }

    var isEmpty: Bool {
        daysByKey.isEmpty
    }

    func day(for date: Date = Date(), calendar: Calendar = .current) -> ActivityDay {
        let key = ActivityDay.makeDateKey(for: date, calendar: calendar)
        return daysByKey[key] ?? ActivityDay(dateKey: key)
    }

    mutating func recordCompleted(at date: Date = Date(), calendar: Calendar = .current) -> ActivityDay {
        let key = ActivityDay.makeDateKey(for: date, calendar: calendar)
        var day = daysByKey[key] ?? ActivityDay(dateKey: key)
        day.completedCount += 1
        day.lastCompletedAt = date
        daysByKey[key] = day
        return day
    }

    mutating func recordPostponed(at date: Date = Date(), calendar: Calendar = .current) -> ActivityDay {
        let key = ActivityDay.makeDateKey(for: date, calendar: calendar)
        var day = daysByKey[key] ?? ActivityDay(dateKey: key)
        day.postponedCount += 1
        daysByKey[key] = day
        return day
    }

    mutating func recordSkipped(at date: Date = Date(), calendar: Calendar = .current) -> ActivityDay {
        let key = ActivityDay.makeDateKey(for: date, calendar: calendar)
        var day = daysByKey[key] ?? ActivityDay(dateKey: key)
        day.skippedCount += 1
        daysByKey[key] = day
        return day
    }

    mutating func upsert(_ day: ActivityDay) {
        daysByKey[day.dateKey] = day
    }

    func days(endingAt endDate: Date = Date(), count: Int, calendar: Calendar = .current) -> [ActivityDay] {
        guard count > 0 else { return [] }

        return stride(from: count - 1, through: 0, by: -1).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: endDate).map {
                day(for: $0, calendar: calendar)
            }
        }
    }

    func completedCountInCurrentWeek(endingAt date: Date = Date(), calendar: Calendar = .current) -> Int {
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: date) else {
            return days(endingAt: date, count: 7, calendar: calendar).reduce(0) { $0 + $1.completedCount }
        }

        var total = 0
        var cursor = weekInterval.start
        while cursor <= date {
            total += day(for: cursor, calendar: calendar).completedCount
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = nextDay
        }
        return total
    }

    func currentStreak(endingAt date: Date = Date(), calendar: Calendar = .current) -> Int {
        var streak = 0
        var cursor = calendar.startOfDay(for: date)

        while day(for: cursor, calendar: calendar).completedCount > 0 {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previousDay
        }

        return streak
    }
}

enum ActivityHistoryStore {
    static let fileName = "SitRightActivityHistory.json"

    static func load(storageDirectory: URL? = nil) -> ActivityHistory {
        do {
            let url: URL
            if let storageDirectory {
                url = storageDirectory.appendingPathComponent(fileName)
            } else if let readableURL = SharedStorage.readableFileURL(named: fileName) {
                url = readableURL
            } else {
                url = try SharedStorage.storageDirectory().appendingPathComponent(fileName)
            }

            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(ActivityHistory.self, from: data)
        } catch {
            return ActivityHistory()
        }
    }

    static func save(_ history: ActivityHistory, storageDirectory: URL? = nil) {
        do {
            let directory = try storageDirectory ?? SharedStorage.storageDirectory()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(history)
            try data.write(to: directory.appendingPathComponent(fileName), options: [.atomic])
        } catch {
            assertionFailure("Failed to save activity history: \(error)")
        }
    }

    static func recordCompleted(at date: Date = Date(), storageDirectory: URL? = nil) -> ActivityDay {
        var history = load(storageDirectory: storageDirectory)
        let day = history.recordCompleted(at: date)
        save(history, storageDirectory: storageDirectory)
        return day
    }
}
