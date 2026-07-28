import Foundation

enum ReminderCycleOutcome: String, Codable, Equatable, Sendable {
    case pending
    case completed
    case expired
    case skipped
}

struct ReminderCycleRecord: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var firstTriggeredAt: Date
    var lastPresentedAt: Date
    var snoozeCount: Int
    var snoozedUntil: Date?
    var outcome: ReminderCycleOutcome
    var resolvedAt: Date?
    var completedAt: Date?
    var responseDeadline: Date?
    var guideStartedAt: Date?

    init(
        id: UUID,
        firstTriggeredAt: Date,
        lastPresentedAt: Date? = nil,
        snoozeCount: Int = 0,
        snoozedUntil: Date? = nil,
        outcome: ReminderCycleOutcome = .pending,
        resolvedAt: Date? = nil,
        completedAt: Date? = nil,
        responseDeadline: Date? = nil,
        guideStartedAt: Date? = nil
    ) {
        self.id = id
        self.firstTriggeredAt = firstTriggeredAt
        self.lastPresentedAt = lastPresentedAt ?? firstTriggeredAt
        self.snoozeCount = snoozeCount
        self.snoozedUntil = snoozedUntil
        self.outcome = outcome
        self.resolvedAt = resolvedAt
        self.completedAt = completedAt
        self.responseDeadline = responseDeadline
        self.guideStartedAt = guideStartedAt
    }
}

struct ManualActivityRecord: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var recordedAt: Date
    var guideStartedAt: Date?
    var qualifiedAt: Date?

    init(
        id: UUID,
        recordedAt: Date,
        guideStartedAt: Date? = nil,
        qualifiedAt: Date? = nil
    ) {
        self.id = id
        self.recordedAt = recordedAt
        self.guideStartedAt = guideStartedAt
        self.qualifiedAt = qualifiedAt
    }
}

enum ActivityDayEligibility: String, Codable, Equatable, Sendable {
    case scheduled
    case paused
    case nonWorkday
}

struct ActivityDay: Codable, Equatable, Identifiable {
    var dateKey: String
    var completedCount: Int
    var postponedCount: Int
    var skippedCount: Int
    var lastCompletedAt: Date?
    var reminderCycles: [ReminderCycleRecord]
    var manualActivities: [ManualActivityRecord]
    var dailyTargetSnapshot: Int?
    var eligibilitySnapshot: ActivityDayEligibility?

    var id: String { dateKey }

    var reminderCompletedCount: Int {
        Set(reminderCycles.lazy.filter { $0.outcome == .completed }.map(\.id)).count
    }

    var manualActivityCount: Int {
        Set(manualActivities.lazy.map(\.id)).count
    }

    var qualifiedProactiveCount: Int {
        Set(manualActivities.lazy.filter { $0.qualifiedAt != nil }.map(\.id)).count
    }

    var legacyUnclassifiedCount: Int {
        max(completedCount - reminderCompletedCount - manualActivityCount, 0)
    }

    var reminderOpportunityCount: Int {
        Set(reminderCycles.lazy.map(\.id)).count
    }

    var responseRate: Double? {
        guard reminderOpportunityCount > 0 else { return nil }
        return Double(reminderCompletedCount) / Double(reminderOpportunityCount)
    }

    var qualifiedActivityCount: Int {
        legacyUnclassifiedCount + reminderCompletedCount + qualifiedProactiveCount
    }

    var dailyGoalActivityCount: Int {
        reminderCompletedCount + qualifiedProactiveCount
    }

    var lastActivityAt: Date? {
        let reminderDates = reminderCycles.compactMap(\.completedAt)
        let manualDates = manualActivities.map(\.recordedAt)
        return ([lastCompletedAt].compactMap { $0 } + reminderDates + manualDates).max()
    }

    init(dateKey: String = ActivityDay.makeDateKey(for: Date())) {
        self.dateKey = dateKey
        self.completedCount = 0
        self.postponedCount = 0
        self.skippedCount = 0
        self.lastCompletedAt = nil
        self.reminderCycles = []
        self.manualActivities = []
        self.dailyTargetSnapshot = nil
        self.eligibilitySnapshot = nil
    }

    private enum CodingKeys: String, CodingKey {
        case dateKey
        case completedCount
        case postponedCount
        case skippedCount
        case lastCompletedAt
        case reminderCycles
        case manualActivities
        case dailyTargetSnapshot
        case eligibilitySnapshot
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dateKey = try container.decode(String.self, forKey: .dateKey)
        completedCount = try container.decodeIfPresent(Int.self, forKey: .completedCount) ?? 0
        postponedCount = try container.decodeIfPresent(Int.self, forKey: .postponedCount) ?? 0
        skippedCount = try container.decodeIfPresent(Int.self, forKey: .skippedCount) ?? 0
        lastCompletedAt = try container.decodeIfPresent(Date.self, forKey: .lastCompletedAt)
        reminderCycles = try container.decodeIfPresent([ReminderCycleRecord].self, forKey: .reminderCycles) ?? []
        manualActivities = try container.decodeIfPresent([ManualActivityRecord].self, forKey: .manualActivities) ?? []
        dailyTargetSnapshot = try container.decodeIfPresent(Int.self, forKey: .dailyTargetSnapshot)
        eligibilitySnapshot = try container.decodeIfPresent(ActivityDayEligibility.self, forKey: .eligibilitySnapshot)
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

    private enum CodingKeys: String, CodingKey {
        case daysByKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        daysByKey = try container.decodeIfPresent([String: ActivityDay].self, forKey: .daysByKey) ?? [:]
    }

    var isEmpty: Bool {
        daysByKey.isEmpty
    }

    var latestPendingCycle: ReminderCycleRecord? {
        daysByKey.values
            .flatMap(\.reminderCycles)
            .filter { $0.outcome == .pending }
            .max {
                if $0.lastPresentedAt == $1.lastPresentedAt {
                    return $0.firstTriggeredAt < $1.firstTriggeredAt
                }
                return $0.lastPresentedAt < $1.lastPresentedAt
            }
    }

    func reminderCycle(id: UUID) -> ReminderCycleRecord? {
        daysByKey.values
            .flatMap(\.reminderCycles)
            .first { $0.id == id }
    }

    var latestActivityAt: Date? {
        daysByKey.values.compactMap(\.lastActivityAt).max()
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

    mutating func beginReminderCycle(
        id: UUID,
        at firstTriggeredAt: Date = Date(),
        responseDeadline: Date? = nil,
        calendar: Calendar = .current
    ) -> ActivityDay {
        if let dayKey = dayKey(containingReminderCycleID: id), let day = daysByKey[dayKey] {
            return day
        }

        let key = ActivityDay.makeDateKey(for: firstTriggeredAt, calendar: calendar)
        var day = daysByKey[key] ?? ActivityDay(dateKey: key)
        day.reminderCycles.append(ReminderCycleRecord(
            id: id,
            firstTriggeredAt: firstTriggeredAt,
            responseDeadline: responseDeadline
        ))
        daysByKey[key] = day
        return day
    }

    mutating func markReminderCyclePresented(
        id: UUID,
        at date: Date = Date(),
        responseDeadline: Date? = nil
    ) -> ActivityDay? {
        updateReminderCycle(id: id) { cycle, _ in
            guard cycle.outcome == .pending else { return }
            cycle.lastPresentedAt = max(cycle.lastPresentedAt, date)
            cycle.snoozedUntil = nil
            cycle.responseDeadline = responseDeadline ?? cycle.responseDeadline
        }
    }

    mutating func snoozeReminderCycle(id: UUID, snoozedUntil: Date) -> ActivityDay? {
        updateReminderCycle(id: id) { cycle, day in
            guard cycle.outcome == .pending,
                  cycle.snoozeCount == 0,
                  cycle.snoozedUntil == nil,
                  snoozedUntil > cycle.lastPresentedAt else {
                return
            }

            cycle.snoozeCount += 1
            cycle.snoozedUntil = snoozedUntil
            day.postponedCount += 1
        }
    }

    mutating func completeReminderCycle(id: UUID, at date: Date = Date()) -> ActivityDay? {
        updateReminderCycle(id: id) { cycle, day in
            guard cycle.outcome == .pending else { return }

            cycle.outcome = .completed
            cycle.resolvedAt = date
            cycle.completedAt = date
            day.completedCount += 1
            day.lastCompletedAt = max(day.lastCompletedAt ?? date, date)
        }
    }

    mutating func startReminderGuide(id: UUID, at date: Date = Date()) -> ActivityDay? {
        updateReminderCycle(id: id) { cycle, _ in
            guard cycle.outcome == .pending,
                  cycle.guideStartedAt == nil,
                  cycle.responseDeadline.map({ date <= $0 }) ?? true else {
                return
            }
            cycle.guideStartedAt = date
        }
    }

    mutating func shiftReminderCycleWindow(id: UUID, by duration: TimeInterval) -> ActivityDay? {
        guard duration > 0 else { return nil }
        return updateReminderCycle(id: id) { cycle, _ in
            guard cycle.outcome == .pending else { return }
            cycle.responseDeadline = cycle.responseDeadline?.addingTimeInterval(duration)
            cycle.snoozedUntil = cycle.snoozedUntil?.addingTimeInterval(duration)
        }
    }

    mutating func completeGuidedActivity(
        activityID: UUID,
        cycleID: UUID?,
        guideStartedAt: Date,
        completedAt: Date,
        calendar: Calendar = .current
    ) -> (day: ActivityDay, didApply: Bool)? {
        if let cycleID {
            guard let dayKey = dayKey(containingReminderCycleID: cycleID),
                  var day = daysByKey[dayKey],
                  let index = day.reminderCycles.firstIndex(where: { $0.id == cycleID }) else {
                return nil
            }
            var cycle = day.reminderCycles[index]
            if cycle.outcome == .completed {
                return (day, false)
            }
            guard cycle.outcome == .pending,
                  cycle.guideStartedAt == guideStartedAt else {
                return nil
            }
            cycle.outcome = .completed
            cycle.resolvedAt = completedAt
            cycle.completedAt = completedAt
            day.reminderCycles[index] = cycle
            day.completedCount += 1
            day.lastCompletedAt = max(day.lastCompletedAt ?? completedAt, completedAt)
            daysByKey[dayKey] = day
            return (day, true)
        }

        if let dayKey = dayKey(containingManualActivityID: activityID),
           let day = daysByKey[dayKey] {
            return (day, false)
        }
        let key = ActivityDay.makeDateKey(for: completedAt, calendar: calendar)
        var day = daysByKey[key] ?? ActivityDay(dateKey: key)
        day.manualActivities.append(ManualActivityRecord(
            id: activityID,
            recordedAt: completedAt,
            guideStartedAt: guideStartedAt,
            qualifiedAt: completedAt
        ))
        day.completedCount += 1
        day.lastCompletedAt = max(day.lastCompletedAt ?? completedAt, completedAt)
        daysByKey[key] = day
        return (day, true)
    }

    mutating func resolveReminderCycle(
        id: UUID,
        outcome: ReminderCycleOutcome,
        at date: Date = Date()
    ) -> ActivityDay? {
        guard outcome == .expired || outcome == .skipped else { return nil }

        return updateReminderCycle(id: id) { cycle, day in
            guard cycle.outcome == .pending else { return }

            cycle.outcome = outcome
            cycle.resolvedAt = date
            cycle.completedAt = nil
            if outcome == .skipped {
                day.skippedCount += 1
            }
        }
    }

    mutating func recordManualActivity(
        id: UUID,
        at recordedAt: Date = Date(),
        calendar: Calendar = .current
    ) -> ActivityDay {
        if let dayKey = dayKey(containingManualActivityID: id), let day = daysByKey[dayKey] {
            return day
        }

        let key = ActivityDay.makeDateKey(for: recordedAt, calendar: calendar)
        var day = daysByKey[key] ?? ActivityDay(dateKey: key)
        // This is the legacy instant-record path. Missing guide fields deliberately
        // keep old records out of the new daily activity goal.
        day.manualActivities.append(ManualActivityRecord(id: id, recordedAt: recordedAt))
        day.completedCount += 1
        day.lastCompletedAt = max(day.lastCompletedAt ?? recordedAt, recordedAt)
        daysByKey[key] = day
        return day
    }

    mutating func settlePendingReminderCycles(
        except excludedID: UUID? = nil,
        outcome: ReminderCycleOutcome,
        at date: Date = Date()
    ) -> Int {
        guard outcome == .expired || outcome == .skipped else { return 0 }

        var settledCount = 0
        for dayKey in Array(daysByKey.keys) {
            guard var day = daysByKey[dayKey] else { continue }
            var didChangeDay = false

            for cycleIndex in day.reminderCycles.indices {
                guard day.reminderCycles[cycleIndex].outcome == .pending,
                      day.reminderCycles[cycleIndex].id != excludedID else {
                    continue
                }

                day.reminderCycles[cycleIndex].outcome = outcome
                day.reminderCycles[cycleIndex].resolvedAt = date
                day.reminderCycles[cycleIndex].completedAt = nil
                if outcome == .skipped {
                    day.skippedCount += 1
                }
                settledCount += 1
                didChangeDay = true
            }

            if didChangeDay {
                daysByKey[dayKey] = day
            }
        }

        return settledCount
    }

    mutating func upsert(_ day: ActivityDay) {
        daysByKey[day.dateKey] = day
    }

    mutating func updateDaySnapshot(
        at date: Date,
        dailyTarget: Int,
        eligibility: ActivityDayEligibility,
        calendar: Calendar = .current
    ) -> ActivityDay {
        let key = ActivityDay.makeDateKey(for: date, calendar: calendar)
        var day = daysByKey[key] ?? ActivityDay(dateKey: key)
        day.dailyTargetSnapshot = max(dailyTarget, 1)
        day.eligibilitySnapshot = eligibility
        daysByKey[key] = day
        return day
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
            return days(endingAt: date, count: 7, calendar: calendar).reduce(0) {
                $0 + $1.qualifiedActivityCount
            }
        }

        var total = 0
        var cursor = weekInterval.start
        while cursor <= date {
            total += day(for: cursor, calendar: calendar).qualifiedActivityCount
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = nextDay
        }
        return total
    }

    func currentStreak(endingAt date: Date = Date(), calendar: Calendar = .current) -> Int {
        var streak = 0
        var cursor = calendar.startOfDay(for: date)

        for _ in 0..<3_650 {
            let day = day(for: cursor, calendar: calendar)
            let isCurrentDay = calendar.isDate(cursor, inSameDayAs: date)
            if isCurrentDay,
               day.qualifiedActivityCount == 0,
               day.eligibilitySnapshot == .scheduled {
                // Do not break yesterday's streak merely because today is
                // still in progress and has not had its first activity yet.
                // Continue evaluating from the last completed day.
            } else if day.qualifiedActivityCount > 0 {
                streak += 1
            } else if day.eligibilitySnapshot == .paused
                || day.eligibilitySnapshot == .nonWorkday
                || (day.eligibilitySnapshot == nil && calendar.isDateInWeekend(cursor)) {
                // A deliberately neutral day neither adds to nor breaks a streak.
            } else {
                break
            }
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previousDay
        }

        return streak
    }

    private mutating func updateReminderCycle(
        id: UUID,
        mutation: (inout ReminderCycleRecord, inout ActivityDay) -> Void
    ) -> ActivityDay? {
        guard let dayKey = dayKey(containingReminderCycleID: id),
              var day = daysByKey[dayKey],
              let cycleIndex = day.reminderCycles.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        var cycle = day.reminderCycles[cycleIndex]
        mutation(&cycle, &day)
        day.reminderCycles[cycleIndex] = cycle
        daysByKey[dayKey] = day
        return day
    }

    private func dayKey(containingReminderCycleID id: UUID) -> String? {
        daysByKey.first { _, day in
            day.reminderCycles.contains { $0.id == id }
        }?.key
    }

    private func dayKey(containingManualActivityID id: UUID) -> String? {
        daysByKey.first { _, day in
            day.manualActivities.contains { $0.id == id }
        }?.key
    }
}

enum ActivityHistoryStore {
    static let fileName = "SitRightActivityHistory.json"
    static let backupFileName = "SitRightActivityHistory.backup.json"
    static let corruptFilePrefix = "SitRightActivityHistory.corrupt-"

    struct LoadResult {
        var history: ActivityHistory
        var recoveredFromBackup: Bool
    }

    struct RecordResult {
        var day: ActivityDay
        var history: ActivityHistory
        var recoveredFromBackup: Bool
    }

    struct ConditionalRecordResult {
        var day: ActivityDay
        var history: ActivityHistory
        var recoveredFromBackup: Bool
        var didRecord: Bool
    }

    struct GuidedCompletionResult {
        var day: ActivityDay
        var history: ActivityHistory
        var recoveredFromBackup: Bool
        var didApply: Bool
    }

    struct SettlementResult {
        var history: ActivityHistory
        var recoveredFromBackup: Bool
        var settledCount: Int
    }

    enum StoreError: LocalizedError {
        case unreadableHistory

        var errorDescription: String? {
            "活动历史文件和备份均无法读取，原文件已保留"
        }
    }

    static func load(storageDirectory: URL? = nil) throws -> ActivityHistory {
        try loadResult(storageDirectory: storageDirectory).history
    }

    static func loadResult(storageDirectory: URL? = nil) throws -> LoadResult {
        try SharedStorage.withExclusiveLock(storageDirectory: storageDirectory) { directory in
            try loadRecovering(from: directory)
        }
    }

    static func loadForDisplay(storageDirectory: URL? = nil) -> ActivityHistory {
        (try? load(storageDirectory: storageDirectory)) ?? ActivityHistory()
    }

    static func latestPendingCycle(storageDirectory: URL? = nil) throws -> ReminderCycleRecord? {
        try load(storageDirectory: storageDirectory).latestPendingCycle
    }

    static func save(_ history: ActivityHistory, storageDirectory: URL? = nil) throws {
        try SharedStorage.withExclusiveLock(storageDirectory: storageDirectory) { directory in
            try saveUnlocked(history, to: directory)
        }
    }

    static func migrateDevelopmentDatasetToAppGroupIfNeeded() throws {
        try SharedStorage.migrateDevelopmentHistoryDatasetToAppGroupIfNeeded(
            primaryFileName: fileName,
            backupFileName: backupFileName,
            validate: validateHistoryData
        )
    }

    static func migrateDataset(from sourceDirectory: URL, to targetDirectory: URL) throws {
        try SharedStorage.migrateHistoryDataset(
            from: sourceDirectory,
            to: targetDirectory,
            primaryFileName: fileName,
            backupFileName: backupFileName,
            validate: validateHistoryData
        )
    }

    static func recordCompleted(at date: Date = Date(), storageDirectory: URL? = nil) throws -> RecordResult {
        try record(at: date, storageDirectory: storageDirectory) { history in
            history.recordCompleted(at: date)
        }
    }

    static func recordPostponed(at date: Date = Date(), storageDirectory: URL? = nil) throws -> RecordResult {
        try record(at: date, storageDirectory: storageDirectory) { history in
            history.recordPostponed(at: date)
        }
    }

    static func recordSkipped(at date: Date = Date(), storageDirectory: URL? = nil) throws -> RecordResult {
        try record(at: date, storageDirectory: storageDirectory) { history in
            history.recordSkipped(at: date)
        }
    }

    static func beginReminderCycle(
        id: UUID,
        at firstTriggeredAt: Date = Date(),
        responseDeadline: Date? = nil,
        storageDirectory: URL? = nil
    ) throws -> RecordResult {
        try record(at: firstTriggeredAt, storageDirectory: storageDirectory) { history in
            history.beginReminderCycle(
                id: id,
                at: firstTriggeredAt,
                responseDeadline: responseDeadline
            )
        }
    }

    static func markReminderCyclePresented(
        id: UUID,
        at date: Date = Date(),
        responseDeadline: Date? = nil,
        storageDirectory: URL? = nil
    ) throws -> RecordResult? {
        try recordExisting(storageDirectory: storageDirectory) { history in
            history.markReminderCyclePresented(
                id: id,
                at: date,
                responseDeadline: responseDeadline
            )
        }
    }

    static func startReminderGuide(
        id: UUID,
        at date: Date = Date(),
        storageDirectory: URL? = nil
    ) throws -> RecordResult? {
        try recordExisting(storageDirectory: storageDirectory) { history in
            history.startReminderGuide(id: id, at: date)
        }
    }

    static func shiftReminderCycleWindow(
        id: UUID,
        by duration: TimeInterval,
        storageDirectory: URL? = nil
    ) throws -> RecordResult? {
        try recordExisting(storageDirectory: storageDirectory) { history in
            history.shiftReminderCycleWindow(id: id, by: duration)
        }
    }

    static func completeGuidedActivity(
        activityID: UUID,
        cycleID: UUID?,
        guideStartedAt: Date,
        completedAt: Date,
        storageDirectory: URL? = nil
    ) throws -> GuidedCompletionResult? {
        try SharedStorage.withExclusiveLock(storageDirectory: storageDirectory) { directory in
            let loadResult = try loadRecovering(from: directory)
            var history = loadResult.history
            guard let mutation = history.completeGuidedActivity(
                activityID: activityID,
                cycleID: cycleID,
                guideStartedAt: guideStartedAt,
                completedAt: completedAt
            ) else {
                return nil
            }
            if mutation.didApply {
                try saveUnlocked(history, to: directory)
            }
            return GuidedCompletionResult(
                day: mutation.day,
                history: history,
                recoveredFromBackup: loadResult.recoveredFromBackup,
                didApply: mutation.didApply
            )
        }
    }

    static func updateDaySnapshot(
        at date: Date,
        dailyTarget: Int,
        eligibility: ActivityDayEligibility,
        storageDirectory: URL? = nil
    ) throws -> RecordResult {
        try record(at: date, storageDirectory: storageDirectory) { history in
            history.updateDaySnapshot(
                at: date,
                dailyTarget: dailyTarget,
                eligibility: eligibility
            )
        }
    }

    static func snoozeReminderCycle(
        id: UUID,
        snoozedUntil: Date,
        storageDirectory: URL? = nil
    ) throws -> RecordResult? {
        try recordExisting(storageDirectory: storageDirectory) { history in
            history.snoozeReminderCycle(id: id, snoozedUntil: snoozedUntil)
        }
    }

    static func completeReminderCycle(
        id: UUID,
        at date: Date = Date(),
        storageDirectory: URL? = nil
    ) throws -> RecordResult? {
        try recordExisting(storageDirectory: storageDirectory) { history in
            history.completeReminderCycle(id: id, at: date)
        }
    }

    static func resolveReminderCycle(
        id: UUID,
        outcome: ReminderCycleOutcome,
        at date: Date = Date(),
        storageDirectory: URL? = nil
    ) throws -> RecordResult? {
        guard outcome == .expired || outcome == .skipped else { return nil }

        return try recordExisting(storageDirectory: storageDirectory) { history in
            history.resolveReminderCycle(id: id, outcome: outcome, at: date)
        }
    }

    static func recordManualActivity(
        id: UUID,
        at recordedAt: Date = Date(),
        storageDirectory: URL? = nil
    ) throws -> RecordResult {
        try record(at: recordedAt, storageDirectory: storageDirectory) { history in
            history.recordManualActivity(id: id, at: recordedAt)
        }
    }

    static func recordManualActivityIfEligible(
        id: UUID,
        at recordedAt: Date = Date(),
        minimumInterval: TimeInterval,
        storageDirectory: URL? = nil
    ) throws -> ConditionalRecordResult {
        try SharedStorage.withExclusiveLock(storageDirectory: storageDirectory) { directory in
            let loadResult = try loadRecovering(from: directory)
            var history = loadResult.history
            let latestActivityAt = history.latestActivityAt
            let intervalHasElapsed = latestActivityAt.map {
                recordedAt.timeIntervalSince($0) >= max(minimumInterval, 0)
            } ?? true
            let isEligible = history.latestPendingCycle == nil && intervalHasElapsed

            let day: ActivityDay
            let didRecord: Bool
            if isEligible {
                let previousHistory = history
                day = history.recordManualActivity(id: id, at: recordedAt)
                didRecord = history != previousHistory
                if didRecord {
                    try saveUnlocked(history, to: directory)
                }
            } else {
                day = history.day(for: recordedAt)
                didRecord = false
            }

            return ConditionalRecordResult(
                day: day,
                history: history,
                recoveredFromBackup: loadResult.recoveredFromBackup,
                didRecord: didRecord
            )
        }
    }

    static func settlePendingReminderCycles(
        except excludedID: UUID? = nil,
        outcome: ReminderCycleOutcome,
        at date: Date = Date(),
        storageDirectory: URL? = nil
    ) throws -> SettlementResult {
        try SharedStorage.withExclusiveLock(storageDirectory: storageDirectory) { directory in
            let loadResult = try loadRecovering(from: directory)
            var history = loadResult.history
            let settledCount = history.settlePendingReminderCycles(
                except: excludedID,
                outcome: outcome,
                at: date
            )
            if settledCount > 0 {
                try saveUnlocked(history, to: directory)
            }

            return SettlementResult(
                history: history,
                recoveredFromBackup: loadResult.recoveredFromBackup,
                settledCount: settledCount
            )
        }
    }

    private static func record(
        at date: Date,
        storageDirectory: URL?,
        mutate: (inout ActivityHistory) -> ActivityDay
    ) throws -> RecordResult {
        try SharedStorage.withExclusiveLock(storageDirectory: storageDirectory) { directory in
            let loadResult = try loadRecovering(from: directory)
            var history = loadResult.history
            let day = mutate(&history)
            try saveUnlocked(history, to: directory)
            return RecordResult(
                day: day,
                history: history,
                recoveredFromBackup: loadResult.recoveredFromBackup
            )
        }
    }

    private static func recordExisting(
        storageDirectory: URL?,
        mutate: (inout ActivityHistory) -> ActivityDay?
    ) throws -> RecordResult? {
        try SharedStorage.withExclusiveLock(storageDirectory: storageDirectory) { directory in
            let loadResult = try loadRecovering(from: directory)
            var history = loadResult.history
            guard let day = mutate(&history) else { return nil }
            try saveUnlocked(history, to: directory)
            return RecordResult(
                day: day,
                history: history,
                recoveredFromBackup: loadResult.recoveredFromBackup
            )
        }
    }

    private static func loadRecovering(from directory: URL) throws -> LoadResult {
        let primaryURL = directory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: primaryURL.path) else {
            let backupURL = directory.appendingPathComponent(backupFileName)
            guard FileManager.default.fileExists(atPath: backupURL.path) else {
                return LoadResult(history: ActivityHistory(), recoveredFromBackup: false)
            }

            guard let backupData = try? Data(contentsOf: backupURL),
                  let backupHistory = try? JSONDecoder().decode(ActivityHistory.self, from: backupData) else {
                throw StoreError.unreadableHistory
            }

            try backupData.write(to: primaryURL, options: [.atomic])
            return LoadResult(history: backupHistory, recoveredFromBackup: true)
        }

        do {
            return LoadResult(history: try decodeHistory(at: primaryURL), recoveredFromBackup: false)
        } catch {
            let backupURL = directory.appendingPathComponent(backupFileName)
            guard FileManager.default.fileExists(atPath: backupURL.path),
                  let backupData = try? Data(contentsOf: backupURL),
                  let backupHistory = try? JSONDecoder().decode(ActivityHistory.self, from: backupData) else {
                throw StoreError.unreadableHistory
            }

            let corruptURL = uniqueCorruptFileURL(in: directory)
            try FileManager.default.copyItem(at: primaryURL, to: corruptURL)
            try backupData.write(to: primaryURL, options: [.atomic])
            return LoadResult(history: backupHistory, recoveredFromBackup: true)
        }
    }

    private static func saveUnlocked(_ history: ActivityHistory, to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let primaryURL = directory.appendingPathComponent(fileName)
        let backupURL = directory.appendingPathComponent(backupFileName)
        if FileManager.default.fileExists(atPath: primaryURL.path) {
            let existingData = try Data(contentsOf: primaryURL)
            guard (try? JSONDecoder().decode(ActivityHistory.self, from: existingData)) != nil else {
                throw StoreError.unreadableHistory
            }
            try existingData.write(to: backupURL, options: [.atomic])
        }

        let data = try JSONEncoder().encode(history)
        try data.write(to: primaryURL, options: [.atomic])
    }

    private static func decodeHistory(at url: URL) throws -> ActivityHistory {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ActivityHistory.self, from: data)
    }

    private static func validateHistoryData(_ data: Data) throws {
        _ = try JSONDecoder().decode(ActivityHistory.self, from: data)
    }

    private static func uniqueCorruptFileURL(in directory: URL) -> URL {
        let timestamp = Int(Date().timeIntervalSince1970)
        var candidate = directory.appendingPathComponent("\(corruptFilePrefix)\(timestamp).json")
        var suffix = 1

        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(corruptFilePrefix)\(timestamp)-\(suffix).json")
            suffix += 1
        }

        return candidate
    }
}
