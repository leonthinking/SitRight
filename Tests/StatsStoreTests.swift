import XCTest
@testable import SitRight

@MainActor
final class StatsStoreTests: XCTestCase {
    func testRefreshChangesStatsOnlyWhenCalendarDayChanges() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = makeDefaults()
        let firstDay = try makeDate(year: 2026, month: 7, day: 10, hour: 10)
        let nextDay = try makeDate(year: 2026, month: 7, day: 11, hour: 10)
        let store = StatsStore(
            defaults: defaults,
            historyStorageDirectory: directory,
            date: firstDay
        )

        XCTAssertTrue(store.markCompleted(at: firstDay))
        XCTAssertFalse(store.refreshForCurrentDay(at: firstDay.addingTimeInterval(60)))
        XCTAssertEqual(store.today.completedCount, 1)

        XCTAssertTrue(store.refreshForCurrentDay(at: nextDay))
        XCTAssertEqual(store.today.dateKey, DailyStats.makeDateKey(for: nextDay))
        XCTAssertEqual(store.today.completedCount, 0)
        XCTAssertFalse(store.refreshForCurrentDay(at: nextDay.addingTimeInterval(60)))
    }

    func testCorruptHistorySurfacesErrorAndBlocksOverwrite() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let primaryURL = directory.appendingPathComponent(ActivityHistoryStore.fileName)
        let corruptData = Data("broken".utf8)
        try corruptData.write(to: primaryURL)

        let store = StatsStore(
            defaults: makeDefaults(),
            historyStorageDirectory: directory
        )

        XCTAssertNotNil(store.lastErrorMessage)
        XCTAssertFalse(store.markCompleted())
        XCTAssertEqual(try Data(contentsOf: primaryURL), corruptData)
    }

    func testLegacyTodayMigratesIntoEmptyActivityHistory() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = makeDefaults()
        let date = try makeDate(year: 2026, month: 7, day: 10, hour: 10)
        var legacy = DailyStats(dateKey: DailyStats.makeDateKey(for: date))
        legacy.completedCount = 3
        legacy.postponedCount = 2
        defaults.set(try JSONEncoder().encode(legacy), forKey: "sitright.dailyStats.v1")

        let store = StatsStore(defaults: defaults, historyStorageDirectory: directory, date: date)
        let history = try ActivityHistoryStore.load(storageDirectory: directory)

        XCTAssertEqual(store.today, legacy)
        XCTAssertEqual(history.day(for: date), legacy)
    }

    func testLegacyStatsFromAnotherDayAreNotMigrated() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = makeDefaults()
        let date = try makeDate(year: 2026, month: 7, day: 10, hour: 10)
        let previousDate = try makeDate(year: 2026, month: 7, day: 9, hour: 10)
        var legacy = DailyStats(dateKey: DailyStats.makeDateKey(for: previousDate))
        legacy.completedCount = 3
        defaults.set(try JSONEncoder().encode(legacy), forKey: "sitright.dailyStats.v1")

        let store = StatsStore(defaults: defaults, historyStorageDirectory: directory, date: date)

        XCTAssertEqual(store.today.completedCount, 0)
        XCTAssertTrue(try ActivityHistoryStore.load(storageDirectory: directory).isEmpty)
    }

    func testMarkOperationsUpdateIndependentCountersAndLegacyMirror() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = makeDefaults()
        let date = try makeDate(year: 2026, month: 7, day: 10, hour: 10)
        let store = StatsStore(defaults: defaults, historyStorageDirectory: directory, date: date)

        XCTAssertTrue(store.markCompleted(at: date))
        XCTAssertTrue(store.markPostponed(at: date))
        XCTAssertTrue(store.markSkipped(at: date))

        XCTAssertEqual(store.today.completedCount, 1)
        XCTAssertEqual(store.today.postponedCount, 1)
        XCTAssertEqual(store.today.skippedCount, 1)
        let legacyData = try XCTUnwrap(defaults.data(forKey: "sitright.dailyStats.v1"))
        XCTAssertEqual(try JSONDecoder().decode(DailyStats.self, from: legacyData), store.today)
    }

    func testBackupRecoverySurfacesMessageAndRemainsWritable() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let date = try makeDate(year: 2026, month: 7, day: 10, hour: 10)
        var first = ActivityHistory()
        _ = first.recordCompleted(at: date)
        try ActivityHistoryStore.save(first, storageDirectory: directory)
        var second = first
        _ = second.recordCompleted(at: date)
        try ActivityHistoryStore.save(second, storageDirectory: directory)
        try Data("broken-primary".utf8).write(
            to: directory.appendingPathComponent(ActivityHistoryStore.fileName)
        )

        let store = StatsStore(
            defaults: makeDefaults(),
            historyStorageDirectory: directory,
            date: date
        )

        XCTAssertEqual(store.lastErrorMessage, "活动记录已从备份恢复")
        XCTAssertEqual(store.today.completedCount, 1)
        XCTAssertTrue(store.markPostponed(at: date))
        XCTAssertNil(store.lastErrorMessage)
        XCTAssertEqual(store.today.postponedCount, 1)
    }

    func testMissingPrimaryBackupRecoverySurfacesMessageAndRemainsWritable() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let date = try makeDate(year: 2026, month: 7, day: 10, hour: 10)
        var backedUpHistory = ActivityHistory()
        _ = backedUpHistory.recordCompleted(at: date)
        try ActivityHistoryStore.save(backedUpHistory, storageDirectory: directory)
        var latestHistory = backedUpHistory
        _ = latestHistory.recordCompleted(at: date)
        try ActivityHistoryStore.save(latestHistory, storageDirectory: directory)
        try FileManager.default.removeItem(
            at: directory.appendingPathComponent(ActivityHistoryStore.fileName)
        )

        let store = StatsStore(
            defaults: makeDefaults(),
            historyStorageDirectory: directory,
            date: date
        )

        XCTAssertEqual(store.lastErrorMessage, "活动记录已从备份恢复")
        XCTAssertEqual(store.today.completedCount, 1)
        XCTAssertTrue(store.markPostponed(at: date))
        XCTAssertNil(store.lastErrorMessage)
        XCTAssertEqual(store.today.postponedCount, 1)
    }

    func testTrustedCycleAndManualOperationsRemainIdempotent() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = makeDefaults()
        let date = try makeDate(year: 2026, month: 7, day: 10, hour: 10)
        let cycleID = UUID()
        let manualID = UUID()
        let snoozedUntil = date.addingTimeInterval(5 * 60)
        let refiredAt = snoozedUntil
        let completedAt = refiredAt.addingTimeInterval(60)
        let store = StatsStore(defaults: defaults, historyStorageDirectory: directory, date: date)

        XCTAssertTrue(store.beginReminderCycle(id: cycleID, at: date))
        XCTAssertTrue(store.beginReminderCycle(id: cycleID, at: date))
        XCTAssertTrue(store.snoozeReminderCycle(id: cycleID, snoozedUntil: snoozedUntil))
        XCTAssertTrue(store.snoozeReminderCycle(id: cycleID, snoozedUntil: snoozedUntil))
        XCTAssertTrue(store.markReminderCyclePresented(id: cycleID, at: refiredAt))
        XCTAssertTrue(store.completeReminderCycle(id: cycleID, at: completedAt))
        XCTAssertTrue(store.completeReminderCycle(id: cycleID, at: completedAt))
        XCTAssertTrue(store.recordManualActivity(id: manualID, at: completedAt.addingTimeInterval(60)))
        XCTAssertTrue(store.recordManualActivity(id: manualID, at: completedAt.addingTimeInterval(60)))

        XCTAssertEqual(store.today.completedCount, 2)
        XCTAssertEqual(store.today.reminderCompletedCount, 1)
        XCTAssertEqual(store.today.manualActivityCount, 1)
        XCTAssertEqual(store.today.legacyUnclassifiedCount, 0)
        XCTAssertEqual(store.today.qualifiedActivityCount, 1)
        XCTAssertEqual(store.today.reminderOpportunityCount, 1)
        XCTAssertEqual(store.today.responseRate, 1)
        XCTAssertEqual(store.today.postponedCount, 1)
        XCTAssertNil(store.today.reminderCycles.first?.snoozedUntil)
        XCTAssertNil(store.latestPendingCycle)

        let legacyData = try XCTUnwrap(defaults.data(forKey: "sitright.dailyStats.v1"))
        let legacyMirror = try JSONDecoder().decode(DailyStats.self, from: legacyData)
        XCTAssertEqual(legacyMirror.completedCount, 2)
        XCTAssertEqual(legacyMirror, store.today)
    }

    func testLatestPendingCycleTracksRefireAndResolution() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let date = try makeDate(year: 2026, month: 7, day: 10, hour: 10)
        let firstID = UUID()
        let secondID = UUID()
        let store = StatsStore(
            defaults: makeDefaults(),
            historyStorageDirectory: directory,
            date: date
        )

        XCTAssertTrue(store.beginReminderCycle(id: firstID, at: date))
        XCTAssertTrue(store.beginReminderCycle(id: secondID, at: date.addingTimeInterval(60)))
        XCTAssertEqual(store.latestPendingCycle?.id, secondID)

        XCTAssertTrue(store.markReminderCyclePresented(id: firstID, at: date.addingTimeInterval(120)))
        XCTAssertEqual(store.latestPendingCycle?.id, firstID)

        XCTAssertTrue(store.resolveReminderCycle(
            id: firstID,
            outcome: .expired,
            at: date.addingTimeInterval(180)
        ))
        XCTAssertTrue(store.resolveReminderCycle(
            id: firstID,
            outcome: .skipped,
            at: date.addingTimeInterval(240)
        ))
        XCTAssertEqual(store.latestPendingCycle?.id, secondID)
        XCTAssertEqual(store.today.skippedCount, 0, "The first terminal outcome must win")
        XCTAssertEqual(
            try ActivityHistoryStore.latestPendingCycle(storageDirectory: directory)?.id,
            secondID
        )
    }

    func testSettlingPendingCyclesAtomicallyRefreshesStoreAndExcludesActiveCycle() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let date = try makeDate(year: 2026, month: 7, day: 10, hour: 10)
        let staleID = UUID()
        let activeID = UUID()
        let store = StatsStore(
            defaults: makeDefaults(),
            historyStorageDirectory: directory,
            date: date
        )

        _ = try ActivityHistoryStore.beginReminderCycle(
            id: staleID,
            at: date,
            storageDirectory: directory
        )
        _ = try ActivityHistoryStore.beginReminderCycle(
            id: activeID,
            at: date.addingTimeInterval(60),
            storageDirectory: directory
        )

        XCTAssertEqual(
            store.settlePendingReminderCycles(
                except: activeID,
                outcome: .expired,
                at: date.addingTimeInterval(120)
            ),
            1
        )
        XCTAssertEqual(store.latestPendingCycle?.id, activeID)
        XCTAssertEqual(store.today.reminderOpportunityCount, 2)

        let history = try ActivityHistoryStore.load(storageDirectory: directory)
        let day = history.day(for: date)
        XCTAssertEqual(day.reminderCycles.first { $0.id == staleID }?.outcome, .expired)
        XCTAssertEqual(day.reminderCycles.first { $0.id == activeID }?.outcome, .pending)
        XCTAssertEqual(
            store.settlePendingReminderCycles(outcome: .completed, at: date.addingTimeInterval(180)),
            nil
        )
    }

    func testResolvingPriorDayPendingCycleKeepsTodayOnCurrentDay() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let priorDay = try makeDate(year: 2026, month: 7, day: 9, hour: 17)
        let currentDay = try makeDate(year: 2026, month: 7, day: 10, hour: 9)
        let cycleID = UUID()
        _ = try ActivityHistoryStore.beginReminderCycle(
            id: cycleID,
            at: priorDay,
            storageDirectory: directory
        )
        let store = StatsStore(
            defaults: makeDefaults(),
            historyStorageDirectory: directory,
            date: currentDay
        )

        XCTAssertTrue(store.resolveReminderCycle(id: cycleID, outcome: .expired, at: currentDay))

        XCTAssertEqual(store.today.dateKey, DailyStats.makeDateKey(for: currentDay))
        XCTAssertEqual(store.today.completedCount, 0)
        let history = try ActivityHistoryStore.load(storageDirectory: directory)
        XCTAssertEqual(
            history.day(for: priorDay).reminderCycles.first?.outcome,
            .expired
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "SitRightStatsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SitRightStatsStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int) throws -> Date {
        try XCTUnwrap(Calendar.current.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour
        )))
    }
}
