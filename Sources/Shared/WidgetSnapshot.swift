import Foundation

struct WidgetSnapshot: Codable, Equatable {
    enum RunState: String, Codable {
        case running
        case paused
        case outsideHours
        case disabled
        case due
    }

    enum ActivityPhase: String, Codable {
        case accumulating
        case delivering
        case awaitingResponse
        case snoozed
        case guiding
        case overdue
        case paused
        case outsideSchedule
        case disabled
    }

    var updatedAt: Date
    var nextReminderAt: Date?
    var intervalMinutes: Int
    var state: RunState
    var statusText: String
    /// Compatibility field retained for older App/Widget builds.
    var completedCount: Int
    var reminderCompletedCount: Int
    var reminderOpportunityCount: Int
    var manualActivityCount: Int
    var legacyUnclassifiedCount: Int
    var qualifiedActivityCount: Int
    var qualifiedProactiveCount: Int
    var dailyGoalActivityCount: Int
    var dailyTarget: Int
    var dateKey: String
    var phase: ActivityPhase?
    var accumulatedEligibleSeconds: TimeInterval?
    var responseDeadline: Date?
    var snoozedUntil: Date?
    var guideStartedAt: Date?
    var guideEndsAt: Date?

    private enum CodingKeys: String, CodingKey {
        case updatedAt
        case nextReminderAt
        case intervalMinutes
        case state
        case statusText
        case completedCount
        case reminderCompletedCount
        case reminderOpportunityCount
        case manualActivityCount
        case legacyUnclassifiedCount
        case qualifiedActivityCount
        case qualifiedProactiveCount
        case dailyGoalActivityCount
        case dailyTarget
        case dateKey
        case phase
        case accumulatedEligibleSeconds
        case responseDeadline
        case snoozedUntil
        case guideStartedAt
        case guideEndsAt
    }

    init(
        updatedAt: Date,
        nextReminderAt: Date?,
        intervalMinutes: Int,
        state: RunState,
        statusText: String,
        completedCount: Int,
        reminderCompletedCount: Int = 0,
        reminderOpportunityCount: Int = 0,
        manualActivityCount: Int = 0,
        legacyUnclassifiedCount: Int = 0,
        qualifiedActivityCount: Int = 0,
        qualifiedProactiveCount: Int = 0,
        dailyGoalActivityCount: Int? = nil,
        dailyTarget: Int,
        dateKey: String,
        phase: ActivityPhase? = nil,
        accumulatedEligibleSeconds: TimeInterval? = nil,
        responseDeadline: Date? = nil,
        snoozedUntil: Date? = nil,
        guideStartedAt: Date? = nil,
        guideEndsAt: Date? = nil
    ) {
        self.updatedAt = updatedAt
        self.nextReminderAt = nextReminderAt
        self.intervalMinutes = intervalMinutes
        self.state = state
        self.statusText = statusText
        self.completedCount = completedCount
        self.reminderCompletedCount = reminderCompletedCount
        self.reminderOpportunityCount = reminderOpportunityCount
        self.manualActivityCount = manualActivityCount
        self.legacyUnclassifiedCount = legacyUnclassifiedCount
        self.qualifiedActivityCount = qualifiedActivityCount
        self.qualifiedProactiveCount = qualifiedProactiveCount
        self.dailyGoalActivityCount = dailyGoalActivityCount
            ?? reminderCompletedCount + qualifiedProactiveCount
        self.dailyTarget = dailyTarget
        self.dateKey = dateKey
        self.phase = phase
        self.accumulatedEligibleSeconds = accumulatedEligibleSeconds
        self.responseDeadline = responseDeadline
        self.snoozedUntil = snoozedUntil
        self.guideStartedAt = guideStartedAt
        self.guideEndsAt = guideEndsAt
    }

    init(from decoder: Decoder) throws {
        let defaults = WidgetSnapshot.empty
        let container = try decoder.container(keyedBy: CodingKeys.self)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? defaults.updatedAt
        nextReminderAt = try container.decodeIfPresent(Date.self, forKey: .nextReminderAt)
        intervalMinutes = try container.decodeIfPresent(Int.self, forKey: .intervalMinutes) ?? defaults.intervalMinutes
        state = try container.decodeIfPresent(RunState.self, forKey: .state) ?? defaults.state
        statusText = try container.decodeIfPresent(String.self, forKey: .statusText) ?? defaults.statusText
        completedCount = try container.decodeIfPresent(Int.self, forKey: .completedCount) ?? defaults.completedCount
        reminderCompletedCount = try container.decodeIfPresent(
            Int.self,
            forKey: .reminderCompletedCount
        ) ?? 0
        reminderOpportunityCount = try container.decodeIfPresent(
            Int.self,
            forKey: .reminderOpportunityCount
        ) ?? 0
        manualActivityCount = try container.decodeIfPresent(Int.self, forKey: .manualActivityCount) ?? 0
        legacyUnclassifiedCount = try container.decodeIfPresent(
            Int.self,
            forKey: .legacyUnclassifiedCount
        ) ?? max(completedCount - reminderCompletedCount - manualActivityCount, 0)
        qualifiedActivityCount = try container.decodeIfPresent(
            Int.self,
            forKey: .qualifiedActivityCount
        ) ?? legacyUnclassifiedCount + reminderCompletedCount
        qualifiedProactiveCount = try container.decodeIfPresent(
            Int.self,
            forKey: .qualifiedProactiveCount
        ) ?? 0
        dailyGoalActivityCount = try container.decodeIfPresent(
            Int.self,
            forKey: .dailyGoalActivityCount
        ) ?? reminderCompletedCount + qualifiedProactiveCount
        dailyTarget = try container.decodeIfPresent(Int.self, forKey: .dailyTarget) ?? defaults.dailyTarget
        dateKey = try container.decodeIfPresent(String.self, forKey: .dateKey) ?? defaults.dateKey
        // A newer app may add a phase before an older widget is upgraded.
        // Decode the optional field defensively so one unknown value does not
        // invalidate the complete snapshot and fall back to `.empty`.
        if let rawPhase = try? container.decodeIfPresent(String.self, forKey: .phase) {
            phase = ActivityPhase(rawValue: rawPhase)
        } else {
            phase = nil
        }
        accumulatedEligibleSeconds = try container.decodeIfPresent(
            TimeInterval.self,
            forKey: .accumulatedEligibleSeconds
        )
        responseDeadline = try container.decodeIfPresent(Date.self, forKey: .responseDeadline)
        snoozedUntil = try container.decodeIfPresent(Date.self, forKey: .snoozedUntil)
        guideStartedAt = try container.decodeIfPresent(Date.self, forKey: .guideStartedAt)
        guideEndsAt = try container.decodeIfPresent(Date.self, forKey: .guideEndsAt)
    }

    static let empty = WidgetSnapshot(
        updatedAt: Date(),
        nextReminderAt: nil,
        intervalMinutes: 50,
        state: .disabled,
        statusText: "打开 SitRight 开始提醒",
        completedCount: 0,
        reminderCompletedCount: 0,
        reminderOpportunityCount: 0,
        manualActivityCount: 0,
        legacyUnclassifiedCount: 0,
        qualifiedActivityCount: 0,
        qualifiedProactiveCount: 0,
        dailyGoalActivityCount: 0,
        dailyTarget: 8,
        dateKey: makeDateKey(for: Date())
    )

    func progress(at date: Date = Date()) -> Double {
        if phase == .guiding, let guideStartedAt {
            let elapsed = max(date.timeIntervalSince(guideStartedAt), 0)
            return min(elapsed / 60, 1)
        }
        if let accumulatedEligibleSeconds {
            let total = TimeInterval(max(intervalMinutes, 1) * 60)
            return min(max(accumulatedEligibleSeconds / total, 0), 1)
        }
        guard state == .running || state == .due else { return 0 }
        guard let nextReminderAt else { return state == .due ? 1 : 0 }

        let total = TimeInterval(max(intervalMinutes, 1) * 60)
        let remaining = max(nextReminderAt.timeIntervalSince(date), 0)
        return min(max(1 - remaining / total, 0), 1)
    }

    var completionProgress: Double {
        guard dailyTarget > 0 else { return 0 }
        let count = max(dailyGoalActivityCount, reminderCompletedCount + qualifiedProactiveCount)
        return min(max(Double(count) / Double(dailyTarget), 0), 1)
    }

    var responseRate: Double? {
        guard reminderOpportunityCount > 0 else { return nil }
        return Double(reminderCompletedCount) / Double(reminderOpportunityCount)
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
    static let fileName = "SitRightWidgetSnapshot.json"

    @discardableResult
    static func save(_ snapshot: WidgetSnapshot, storageDirectory: URL? = nil) -> Bool {
        do {
            try SharedStorage.withExclusiveLock(storageDirectory: storageDirectory) { directory in
                try save(snapshot, to: directory)
            }
            return true
        } catch {
            return false
        }
    }

    static func load(storageDirectory: URL? = nil) -> WidgetSnapshot {
        do {
            if let storageDirectory {
                return load(from: storageDirectory)
            } else if let readableURL = SharedStorage.readableFileURL(named: fileName) {
                let data = try Data(contentsOf: readableURL)
                return try JSONDecoder().decode(WidgetSnapshot.self, from: data)
            } else {
                return load(from: try SharedStorage.storageDirectory())
            }
        } catch {
            return .empty
        }
    }

    static func load(from directory: URL) -> WidgetSnapshot {
        do {
            let data = try Data(contentsOf: directory.appendingPathComponent(fileName))
            return try JSONDecoder().decode(WidgetSnapshot.self, from: data)
        } catch {
            return .empty
        }
    }

    static func save(_ snapshot: WidgetSnapshot, to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: directory.appendingPathComponent(fileName), options: [.atomic])
    }

}
