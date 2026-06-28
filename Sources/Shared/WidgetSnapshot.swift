import Foundation

struct WidgetSnapshot: Codable, Equatable {
    enum RunState: String, Codable {
        case running
        case paused
        case outsideHours
        case disabled
        case due
    }

    var updatedAt: Date
    var nextReminderAt: Date?
    var intervalMinutes: Int
    var state: RunState
    var statusText: String
    var completedCount: Int
    var dailyTarget: Int
    var dateKey: String

    static let empty = WidgetSnapshot(
        updatedAt: Date(),
        nextReminderAt: nil,
        intervalMinutes: 30,
        state: .disabled,
        statusText: "打开 SitRight 开始提醒",
        completedCount: 0,
        dailyTarget: 8,
        dateKey: makeDateKey(for: Date())
    )

    func progress(at date: Date = Date()) -> Double {
        guard state == .running || state == .due else { return 0 }
        guard let nextReminderAt else { return state == .due ? 1 : 0 }

        let total = TimeInterval(max(intervalMinutes, 1) * 60)
        let remaining = max(nextReminderAt.timeIntervalSince(date), 0)
        return min(max(1 - remaining / total, 0), 1)
    }

    var completionProgress: Double {
        guard dailyTarget > 0 else { return 0 }
        return min(Double(completedCount) / Double(dailyTarget), 1)
    }

    static func makeDateKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}

enum WidgetSnapshotStore {
    static let appGroupIdentifiers = [
        "973KFG9CL9.com.leon.SitRight",
        "group.com.leon.SitRight"
    ]
    static let fileName = "SitRightWidgetSnapshot.json"

    static func save(_ snapshot: WidgetSnapshot) {
        do {
            let directory = try storageDirectory()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: directory.appendingPathComponent(fileName), options: [.atomic])
        } catch {
            assertionFailure("Failed to save widget snapshot: \(error)")
        }
    }

    static func load() -> WidgetSnapshot {
        do {
            let url = try storageDirectory().appendingPathComponent(fileName)
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(WidgetSnapshot.self, from: data)
        } catch {
            return .empty
        }
    }

    private static func storageDirectory() throws -> URL {
        for identifier in appGroupIdentifiers {
            if let appGroupURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: identifier
            ) {
                return appGroupURL
            }
        }

        let supportURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return supportURL.appendingPathComponent("SitRight", isDirectory: true)
    }
}
