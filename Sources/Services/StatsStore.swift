import Foundation

@MainActor
final class StatsStore: ObservableObject {
    @Published private(set) var today: DailyStats
    @Published private(set) var lastErrorMessage: String?

    private let defaults: UserDefaults
    private let storageKey = "sitright.dailyStats.v1"
    private let historyStorageDirectory: URL?
    private var history: ActivityHistory
    private var historyIsWritable: Bool
    private var currentDate: Date

    var latestPendingCycle: ReminderCycleRecord? {
        history.latestPendingCycle
    }

    var latestActivityAt: Date? {
        history.latestActivityAt
    }

    init(
        defaults: UserDefaults = .standard,
        historyStorageDirectory: URL? = nil,
        initialErrorMessage: String? = nil,
        date: Date = Date()
    ) {
        self.defaults = defaults
        self.historyStorageDirectory = historyStorageDirectory

        var loadedHistory = ActivityHistory()
        var storageIsWritable = true
        var errorMessage = initialErrorMessage

        do {
            let result = try ActivityHistoryStore.loadResult(storageDirectory: historyStorageDirectory)
            loadedHistory = result.history
            if result.recoveredFromBackup {
                errorMessage = "活动记录已从备份恢复"
            }
        } catch {
            storageIsWritable = false
            errorMessage = error.localizedDescription
        }

        if storageIsWritable,
           loadedHistory.isEmpty,
           let legacyToday = Self.loadLegacyToday(from: defaults, date: date) {
            loadedHistory.upsert(legacyToday)
            do {
                try ActivityHistoryStore.save(loadedHistory, storageDirectory: historyStorageDirectory)
            } catch {
                storageIsWritable = false
                errorMessage = error.localizedDescription
            }
        }

        self.history = loadedHistory
        self.today = loadedHistory.day(for: date)
        self.lastErrorMessage = errorMessage
        self.historyIsWritable = storageIsWritable
        self.currentDate = date
    }

    @discardableResult
    func refreshForCurrentDay(at date: Date = Date()) -> Bool {
        let currentKey = DailyStats.makeDateKey(for: date)
        currentDate = date
        guard today.dateKey != currentKey else { return false }

        let currentDay = history.day(for: date)
        today = currentDay
        saveLegacyToday()
        return true
    }

    @discardableResult
    func markCompleted(at date: Date = Date()) -> Bool {
        updateHistory {
            try ActivityHistoryStore.recordCompleted(at: date, storageDirectory: historyStorageDirectory)
        }
    }

    @discardableResult
    func markPostponed(at date: Date = Date()) -> Bool {
        updateHistory {
            try ActivityHistoryStore.recordPostponed(at: date, storageDirectory: historyStorageDirectory)
        }
    }

    @discardableResult
    func markSkipped(at date: Date = Date()) -> Bool {
        updateHistory {
            try ActivityHistoryStore.recordSkipped(at: date, storageDirectory: historyStorageDirectory)
        }
    }

    @discardableResult
    func beginReminderCycle(
        id: UUID,
        at date: Date = Date(),
        responseDeadline: Date? = nil
    ) -> Bool {
        updateHistory {
            try ActivityHistoryStore.beginReminderCycle(
                id: id,
                at: date,
                responseDeadline: responseDeadline,
                storageDirectory: historyStorageDirectory
            )
        }
    }

    @discardableResult
    func markReminderCyclePresented(
        id: UUID,
        at date: Date = Date(),
        responseDeadline: Date? = nil
    ) -> Bool {
        updateExistingHistory {
            try ActivityHistoryStore.markReminderCyclePresented(
                id: id,
                at: date,
                responseDeadline: responseDeadline,
                storageDirectory: historyStorageDirectory
            )
        }
    }

    @discardableResult
    func startReminderGuide(id: UUID, at date: Date = Date()) -> Bool {
        guard updateExistingHistory({
            try ActivityHistoryStore.startReminderGuide(
                id: id,
                at: date,
                storageDirectory: historyStorageDirectory
            )
        }) else { return false }

        // `recordExisting` intentionally remains idempotent for compatibility
        // with older callers. The engine needs the stronger guarantee that the
        // cycle it is about to guide is still pending and has this guide start
        // marker after the App Group transaction completed.
        return history.reminderCycle(id: id)?.guideStartedAt == date
    }

    @discardableResult
    func shiftReminderCycleWindow(id: UUID, by duration: TimeInterval) -> Bool {
        updateExistingHistory {
            try ActivityHistoryStore.shiftReminderCycleWindow(
                id: id,
                by: duration,
                storageDirectory: historyStorageDirectory
            )
        }
    }

    @discardableResult
    func completeGuidedActivity(
        activityID: UUID,
        cycleID: UUID?,
        guideStartedAt: Date,
        completedAt: Date
    ) -> Bool {
        guard historyIsWritable else { return false }

        do {
            guard let result = try ActivityHistoryStore.completeGuidedActivity(
                activityID: activityID,
                cycleID: cycleID,
                guideStartedAt: guideStartedAt,
                completedAt: completedAt,
                storageDirectory: historyStorageDirectory
            ) else {
                return false
            }
            history = result.history
            today = history.day(for: currentDate)
            lastErrorMessage = result.recoveredFromBackup ? "活动记录已从备份恢复" : nil
            saveLegacyToday()
            return result.didApply
        } catch {
            historyIsWritable = false
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func updateDaySnapshot(
        at date: Date = Date(),
        dailyTarget: Int,
        eligibility: ActivityDayEligibility
    ) -> Bool {
        currentDate = date
        _ = refreshForCurrentDay(at: date)
        guard today.dailyTargetSnapshot != max(dailyTarget, 1)
                || today.eligibilitySnapshot != eligibility else {
            return true
        }
        return updateHistory {
            try ActivityHistoryStore.updateDaySnapshot(
                at: date,
                dailyTarget: dailyTarget,
                eligibility: eligibility,
                storageDirectory: historyStorageDirectory
            )
        }
    }

    @discardableResult
    func snoozeReminderCycle(id: UUID, snoozedUntil: Date) -> Bool {
        updateExistingHistory {
            try ActivityHistoryStore.snoozeReminderCycle(
                id: id,
                snoozedUntil: snoozedUntil,
                storageDirectory: historyStorageDirectory
            )
        }
    }

    @discardableResult
    func completeReminderCycle(id: UUID, at date: Date = Date()) -> Bool {
        updateExistingHistory {
            try ActivityHistoryStore.completeReminderCycle(
                id: id,
                at: date,
                storageDirectory: historyStorageDirectory
            )
        }
    }

    @discardableResult
    func resolveReminderCycle(
        id: UUID,
        outcome: ReminderCycleOutcome,
        at date: Date = Date()
    ) -> Bool {
        updateExistingHistory {
            try ActivityHistoryStore.resolveReminderCycle(
                id: id,
                outcome: outcome,
                at: date,
                storageDirectory: historyStorageDirectory
            )
        }
    }

    @discardableResult
    func settlePendingReminderCycles(
        except excludedID: UUID? = nil,
        outcome: ReminderCycleOutcome,
        at date: Date = Date()
    ) -> Int? {
        guard historyIsWritable,
              outcome == .expired || outcome == .skipped else {
            return nil
        }

        do {
            let result = try ActivityHistoryStore.settlePendingReminderCycles(
                except: excludedID,
                outcome: outcome,
                at: date,
                storageDirectory: historyStorageDirectory
            )
            history = result.history
            today = history.day(for: currentDate)
            lastErrorMessage = result.recoveredFromBackup ? "活动记录已从备份恢复" : nil
            saveLegacyToday()
            return result.settledCount
        } catch {
            historyIsWritable = false
            lastErrorMessage = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func recordManualActivity(id: UUID, at date: Date = Date()) -> Bool {
        updateHistory {
            try ActivityHistoryStore.recordManualActivity(
                id: id,
                at: date,
                storageDirectory: historyStorageDirectory
            )
        }
    }

    @discardableResult
    func recordManualActivityIfEligible(
        id: UUID,
        at date: Date = Date(),
        minimumInterval: TimeInterval
    ) -> Bool {
        guard historyIsWritable else { return false }

        do {
            let result = try ActivityHistoryStore.recordManualActivityIfEligible(
                id: id,
                at: date,
                minimumInterval: minimumInterval,
                storageDirectory: historyStorageDirectory
            )
            history = result.history
            today = history.day(for: currentDate)
            lastErrorMessage = result.recoveredFromBackup ? "活动记录已从备份恢复" : nil
            saveLegacyToday()
            return result.didRecord
        } catch {
            historyIsWritable = false
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    var lastCompletedText: String {
        guard let date = today.lastCompletedAt else { return "今天还没有完成活动" }
        return "上次完成 \(date.formatted(date: .omitted, time: .shortened))"
    }

    private func saveLegacyToday() {
        guard let data = try? JSONEncoder().encode(today) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func updateHistory(
        _ operation: () throws -> ActivityHistoryStore.RecordResult
    ) -> Bool {
        guard historyIsWritable else { return false }

        do {
            let result = try operation()
            history = result.history
            today = history.day(for: currentDate)
            lastErrorMessage = result.recoveredFromBackup ? "活动记录已从备份恢复" : nil
            saveLegacyToday()
            return true
        } catch {
            historyIsWritable = false
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    private func updateExistingHistory(
        _ operation: () throws -> ActivityHistoryStore.RecordResult?
    ) -> Bool {
        guard historyIsWritable else { return false }

        do {
            guard let result = try operation() else { return false }
            history = result.history
            today = history.day(for: currentDate)
            lastErrorMessage = result.recoveredFromBackup ? "活动记录已从备份恢复" : nil
            saveLegacyToday()
            return true
        } catch {
            historyIsWritable = false
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    private static func loadLegacyToday(from defaults: UserDefaults, date: Date) -> DailyStats? {
        guard let data = defaults.data(forKey: "sitright.dailyStats.v1"),
              let decoded = try? JSONDecoder().decode(DailyStats.self, from: data),
              decoded.dateKey == DailyStats.makeDateKey(for: date) else {
            return nil
        }

        return decoded
    }
}
