import XCTest
@testable import SitRight

final class ActivityHistoryTests: XCTestCase {
    func testRecordCompletedStoresCountsByDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 30, hour: 9)))

        var history = ActivityHistory()
        _ = history.recordCompleted(at: date, calendar: calendar)
        let day = history.recordCompleted(at: date, calendar: calendar)

        XCTAssertEqual(day.dateKey, "2026-06-30")
        XCTAssertEqual(day.completedCount, 2)
        XCTAssertEqual(history.day(for: date, calendar: calendar).completedCount, 2)
    }

    func testDaysReturnsZeroFilledDateRange() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let endDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 30)))
        let completedDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 28)))

        var history = ActivityHistory()
        _ = history.recordCompleted(at: completedDate, calendar: calendar)

        let days = history.days(endingAt: endDate, count: 4, calendar: calendar)

        XCTAssertEqual(days.map(\.dateKey), ["2026-06-27", "2026-06-28", "2026-06-29", "2026-06-30"])
        XCTAssertEqual(days.map(\.completedCount), [0, 1, 0, 0])
    }

    func testCurrentWeekAndStreakStats() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2

        let monday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 29)))
        let tuesday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 30)))
        let sunday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 28)))

        var history = ActivityHistory()
        _ = history.recordCompleted(at: sunday, calendar: calendar)
        _ = history.recordCompleted(at: monday, calendar: calendar)
        _ = history.recordCompleted(at: tuesday, calendar: calendar)
        _ = history.recordCompleted(at: tuesday, calendar: calendar)

        XCTAssertEqual(history.completedCountInCurrentWeek(endingAt: tuesday, calendar: calendar), 3)
        XCTAssertEqual(history.currentStreak(endingAt: tuesday, calendar: calendar), 3)
    }

    func testActivityHistoryStorePersistsLocally() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SitRightTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 30, hour: 9)))

        var history = ActivityHistory()
        _ = history.recordCompleted(at: date, calendar: calendar)
        try ActivityHistoryStore.save(history, storageDirectory: directory)

        let loaded = try ActivityHistoryStore.load(storageDirectory: directory)

        XCTAssertEqual(loaded.day(for: date, calendar: calendar).completedCount, 1)
    }

    func testLegacyActivityDayDecodesMissingCountersWithDefaults() throws {
        let data = try XCTUnwrap(
            """
            {
              "daysByKey": {
                "2026-07-01": {
                  "dateKey": "2026-07-01",
                  "completedCount": 2
                }
              }
            }
            """.data(using: .utf8)
        )

        let history = try JSONDecoder().decode(ActivityHistory.self, from: data)
        let date = try XCTUnwrap(Self.calendar.date(from: DateComponents(year: 2026, month: 7, day: 1)))
        let day = history.day(for: date, calendar: Self.calendar)

        XCTAssertEqual(day.completedCount, 2)
        XCTAssertEqual(day.postponedCount, 0)
        XCTAssertEqual(day.skippedCount, 0)
        XCTAssertNil(day.lastCompletedAt)
        XCTAssertTrue(day.reminderCycles.isEmpty)
        XCTAssertTrue(day.manualActivities.isEmpty)
        XCTAssertEqual(day.legacyUnclassifiedCount, 2)
        XCTAssertEqual(day.reminderCompletedCount, 0)
        XCTAssertEqual(day.manualActivityCount, 0)
        XCTAssertEqual(day.reminderOpportunityCount, 0)
        XCTAssertNil(day.responseRate)
        XCTAssertEqual(day.qualifiedActivityCount, 2)
    }

    func testReminderCycleLifecycleIsIdempotentAndDerivesResponseMetrics() throws {
        let triggeredAt = try makeDate(day: 1, hour: 9)
        let snoozedUntil = triggeredAt.addingTimeInterval(10 * 60)
        let presentedAgainAt = snoozedUntil
        let completedAt = triggeredAt.addingTimeInterval(12 * 60)
        let completedID = UUID()
        let skippedID = UUID()
        let pendingID = UUID()
        var history = ActivityHistory()

        _ = history.beginReminderCycle(id: completedID, at: triggeredAt, calendar: Self.calendar)
        _ = history.beginReminderCycle(id: completedID, at: triggeredAt, calendar: Self.calendar)
        _ = history.snoozeReminderCycle(id: completedID, snoozedUntil: snoozedUntil)
        _ = history.snoozeReminderCycle(id: completedID, snoozedUntil: snoozedUntil)
        _ = history.markReminderCyclePresented(id: completedID, at: presentedAgainAt)
        _ = history.markReminderCyclePresented(id: completedID, at: presentedAgainAt)
        _ = history.snoozeReminderCycle(id: completedID, snoozedUntil: snoozedUntil)
        _ = history.completeReminderCycle(id: completedID, at: completedAt)
        _ = history.completeReminderCycle(id: completedID, at: completedAt)

        _ = history.beginReminderCycle(
            id: skippedID,
            at: triggeredAt.addingTimeInterval(60 * 60),
            calendar: Self.calendar
        )
        _ = history.resolveReminderCycle(
            id: skippedID,
            outcome: .skipped,
            at: triggeredAt.addingTimeInterval(61 * 60)
        )
        _ = history.resolveReminderCycle(
            id: skippedID,
            outcome: .skipped,
            at: triggeredAt.addingTimeInterval(61 * 60)
        )

        _ = history.beginReminderCycle(
            id: pendingID,
            at: triggeredAt.addingTimeInterval(2 * 60 * 60),
            calendar: Self.calendar
        )

        let day = history.day(for: triggeredAt, calendar: Self.calendar)
        let completedCycle = try XCTUnwrap(day.reminderCycles.first { $0.id == completedID })

        XCTAssertEqual(day.reminderCycles.count, 3)
        XCTAssertEqual(day.completedCount, 1)
        XCTAssertEqual(day.reminderCompletedCount, 1)
        XCTAssertEqual(day.reminderOpportunityCount, 3)
        XCTAssertEqual(day.legacyUnclassifiedCount, 0)
        XCTAssertEqual(day.qualifiedActivityCount, 1)
        XCTAssertEqual(try XCTUnwrap(day.responseRate), 1.0 / 3.0, accuracy: 0.000_001)
        XCTAssertEqual(day.postponedCount, 1)
        XCTAssertEqual(day.skippedCount, 1)
        XCTAssertEqual(completedCycle.lastPresentedAt, presentedAgainAt)
        XCTAssertEqual(completedCycle.snoozeCount, 1)
        XCTAssertNil(completedCycle.snoozedUntil)
        XCTAssertEqual(completedCycle.outcome, .completed)
        XCTAssertEqual(completedCycle.resolvedAt, completedAt)
        XCTAssertEqual(completedCycle.completedAt, completedAt)
        XCTAssertEqual(day.lastActivityAt, completedAt)
        XCTAssertEqual(history.latestPendingCycle?.id, pendingID)
    }

    func testSettlingPendingCyclesExcludesSpecifiedCycleAndCountsChanges() throws {
        let date = try makeDate(day: 1, hour: 9)
        let excludedID = UUID()
        let settledID = UUID()
        let alreadyCompletedID = UUID()
        var history = ActivityHistory()
        _ = history.beginReminderCycle(id: excludedID, at: date, calendar: Self.calendar)
        _ = history.beginReminderCycle(
            id: settledID,
            at: date.addingTimeInterval(60),
            calendar: Self.calendar
        )
        _ = history.beginReminderCycle(
            id: alreadyCompletedID,
            at: date.addingTimeInterval(120),
            calendar: Self.calendar
        )
        _ = history.completeReminderCycle(id: alreadyCompletedID, at: date.addingTimeInterval(180))

        let settledCount = history.settlePendingReminderCycles(
            except: excludedID,
            outcome: .skipped,
            at: date.addingTimeInterval(240)
        )
        let day = history.day(for: date, calendar: Self.calendar)

        XCTAssertEqual(settledCount, 1)
        XCTAssertEqual(day.reminderCycles.first { $0.id == excludedID }?.outcome, .pending)
        XCTAssertEqual(day.reminderCycles.first { $0.id == settledID }?.outcome, .skipped)
        XCTAssertEqual(day.reminderCycles.first { $0.id == alreadyCompletedID }?.outcome, .completed)
        XCTAssertEqual(day.skippedCount, 1)
        XCTAssertEqual(
            history.settlePendingReminderCycles(
                except: excludedID,
                outcome: .skipped,
                at: date.addingTimeInterval(300)
            ),
            0
        )
    }

    func testManualActivityKeepsLegacyTotalButIsExcludedFromQualifiedMetrics() throws {
        let date = try makeDate(day: 1, hour: 9)
        let manualID = UUID()
        var history = ActivityHistory()

        _ = history.recordManualActivity(id: manualID, at: date, calendar: Self.calendar)
        _ = history.recordManualActivity(id: manualID, at: date, calendar: Self.calendar)

        let day = history.day(for: date, calendar: Self.calendar)
        XCTAssertEqual(day.completedCount, 1)
        XCTAssertEqual(day.manualActivityCount, 1)
        XCTAssertEqual(day.legacyUnclassifiedCount, 0)
        XCTAssertEqual(day.qualifiedActivityCount, 0)
        XCTAssertEqual(day.lastActivityAt, date)
        XCTAssertNil(day.responseRate)
        XCTAssertEqual(history.completedCountInCurrentWeek(endingAt: date, calendar: Self.calendar), 0)
        XCTAssertEqual(history.currentStreak(endingAt: date, calendar: Self.calendar), 0)
    }

    func testGuidedProactiveActivityIsDistinctFromLegacyManualRecord() throws {
        let date = try makeDate(day: 1, hour: 9)
        var history = ActivityHistory()
        let guideStart = date.addingTimeInterval(10)
        let result = try XCTUnwrap(history.completeGuidedActivity(
            activityID: UUID(),
            cycleID: nil,
            guideStartedAt: guideStart,
            completedAt: date.addingTimeInterval(70),
            calendar: Self.calendar
        ))

        XCTAssertTrue(result.didApply)
        XCTAssertEqual(result.day.manualActivityCount, 1)
        XCTAssertEqual(result.day.qualifiedProactiveCount, 1)
        XCTAssertEqual(result.day.dailyGoalActivityCount, 1)
        XCTAssertEqual(result.day.qualifiedActivityCount, 1)
        XCTAssertTrue(result.day.manualActivities[0].qualifiedAt != nil)

        let retry = history.completeGuidedActivity(
            activityID: result.day.manualActivities[0].id,
            cycleID: nil,
            guideStartedAt: guideStart,
            completedAt: date.addingTimeInterval(70),
            calendar: Self.calendar
        )
        XCTAssertEqual(retry?.didApply, false)
        XCTAssertEqual(history.day(for: date, calendar: Self.calendar).dailyGoalActivityCount, 1)
    }

    func testWeekAndStreakUseQualifiedActivitiesInsteadOfManualActivities() throws {
        var calendar = Self.calendar
        calendar.firstWeekday = 2
        let monday = try makeDate(day: 6, hour: 9)
        let tuesday = try makeDate(day: 7, hour: 9)
        let wednesday = try makeDate(day: 8, hour: 9)
        let cycleID = UUID()
        var history = ActivityHistory()

        _ = history.recordManualActivity(id: UUID(), at: monday, calendar: calendar)
        _ = history.beginReminderCycle(id: cycleID, at: tuesday, calendar: calendar)
        _ = history.completeReminderCycle(id: cycleID, at: tuesday.addingTimeInterval(60))
        _ = history.recordCompleted(at: wednesday, calendar: calendar)

        XCTAssertEqual(history.completedCountInCurrentWeek(endingAt: wednesday, calendar: calendar), 2)
        XCTAssertEqual(history.currentStreak(endingAt: wednesday, calendar: calendar), 2)
    }

    func testPausedAndNonWorkdaySnapshotsDoNotBreakStreak() throws {
        var calendar = Self.calendar
        calendar.firstWeekday = 2
        let friday = try makeDate(day: 3, hour: 9)
        let saturday = try makeDate(day: 4, hour: 9)
        let sunday = try makeDate(day: 5, hour: 9)
        let monday = try makeDate(day: 6, hour: 9)
        var history = ActivityHistory()

        _ = history.recordCompleted(at: friday, calendar: calendar)
        _ = history.updateDaySnapshot(
            at: saturday,
            dailyTarget: 8,
            eligibility: .nonWorkday,
            calendar: calendar
        )
        _ = history.updateDaySnapshot(
            at: sunday,
            dailyTarget: 8,
            eligibility: .paused,
            calendar: calendar
        )
        _ = history.recordCompleted(at: monday, calendar: calendar)

        XCTAssertEqual(history.currentStreak(endingAt: monday, calendar: calendar), 2)
    }

    func testCorruptHistoryWithoutBackupIsPreservedAndNotOverwritten() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let primaryURL = directory.appendingPathComponent(ActivityHistoryStore.fileName)
        let corruptData = Data("not-json".utf8)
        try corruptData.write(to: primaryURL)

        XCTAssertThrowsError(try ActivityHistoryStore.recordCompleted(storageDirectory: directory))
        XCTAssertEqual(try Data(contentsOf: primaryURL), corruptData)
    }

    func testCorruptPrimaryRecoversFromBackupAndPreservesCorruptCopy() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let date = try XCTUnwrap(Self.calendar.date(from: DateComponents(year: 2026, month: 7, day: 1)))

        var firstHistory = ActivityHistory()
        _ = firstHistory.recordCompleted(at: date, calendar: Self.calendar)
        try ActivityHistoryStore.save(firstHistory, storageDirectory: directory)

        var secondHistory = firstHistory
        _ = secondHistory.recordCompleted(at: date, calendar: Self.calendar)
        try ActivityHistoryStore.save(secondHistory, storageDirectory: directory)

        let primaryURL = directory.appendingPathComponent(ActivityHistoryStore.fileName)
        try Data("broken-primary".utf8).write(to: primaryURL)

        let result = try ActivityHistoryStore.loadResult(storageDirectory: directory)

        XCTAssertTrue(result.recoveredFromBackup)
        XCTAssertEqual(result.history.day(for: date, calendar: Self.calendar).completedCount, 1)
        let preservedFiles = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix(ActivityHistoryStore.corruptFilePrefix) }
        XCTAssertEqual(preservedFiles.count, 1)
        XCTAssertEqual(try ActivityHistoryStore.load(storageDirectory: directory), firstHistory)
    }

    func testMissingPrimaryRecoversFromValidBackup() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let date = try makeDate(day: 1, hour: 9)
        var backedUpHistory = ActivityHistory()
        _ = backedUpHistory.recordCompleted(at: date, calendar: Self.calendar)
        try ActivityHistoryStore.save(backedUpHistory, storageDirectory: directory)
        var latestHistory = backedUpHistory
        _ = latestHistory.recordCompleted(at: date, calendar: Self.calendar)
        try ActivityHistoryStore.save(latestHistory, storageDirectory: directory)

        let primaryURL = directory.appendingPathComponent(ActivityHistoryStore.fileName)
        let backupURL = directory.appendingPathComponent(ActivityHistoryStore.backupFileName)
        let backupData = try Data(contentsOf: backupURL)
        try FileManager.default.removeItem(at: primaryURL)

        let result = try ActivityHistoryStore.loadResult(storageDirectory: directory)

        XCTAssertTrue(result.recoveredFromBackup)
        XCTAssertEqual(result.history, backedUpHistory)
        XCTAssertEqual(try Data(contentsOf: primaryURL), backupData)
        XCTAssertEqual(try ActivityHistoryStore.load(storageDirectory: directory), backedUpHistory)
    }

    func testMissingPrimaryWithCorruptBackupBlocksOverwrite() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let primaryURL = directory.appendingPathComponent(ActivityHistoryStore.fileName)
        let backupURL = directory.appendingPathComponent(ActivityHistoryStore.backupFileName)
        let corruptData = Data("broken-backup".utf8)
        try corruptData.write(to: backupURL)

        XCTAssertThrowsError(try ActivityHistoryStore.recordCompleted(storageDirectory: directory))
        XCTAssertFalse(FileManager.default.fileExists(atPath: primaryURL.path))
        XCTAssertEqual(try Data(contentsOf: backupURL), corruptData)
    }

    func testSharedStorageMigrationCopiesMissingFilesWithoutOverwritingTarget() throws {
        let source = temporaryDirectory()
        let target = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: target)
        }
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        let copiedName = "copy.json"
        let preservedName = "preserve.json"
        try Data("source".utf8).write(to: source.appendingPathComponent(copiedName))
        try Data("source-version".utf8).write(to: source.appendingPathComponent(preservedName))
        try Data("target-version".utf8).write(to: target.appendingPathComponent(preservedName))

        try SharedStorage.migrateFiles(from: source, to: target, named: [copiedName, preservedName])

        XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent(copiedName)), Data("source".utf8))
        XCTAssertEqual(
            try Data(contentsOf: target.appendingPathComponent(preservedName)),
            Data("target-version".utf8)
        )
    }

    func testHistoryDatasetMigrationCreatesConsistentPairFromSourcePrimary() throws {
        let source = temporaryDirectory()
        let target = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: target)
        }
        let date = try makeDate(day: 1, hour: 9)
        var firstHistory = ActivityHistory()
        _ = firstHistory.recordCompleted(at: date, calendar: Self.calendar)
        try ActivityHistoryStore.save(firstHistory, storageDirectory: source)
        var sourcePrimaryHistory = firstHistory
        _ = sourcePrimaryHistory.recordCompleted(at: date, calendar: Self.calendar)
        try ActivityHistoryStore.save(sourcePrimaryHistory, storageDirectory: source)

        try ActivityHistoryStore.migrateDataset(from: source, to: target)

        let primaryData = try Data(
            contentsOf: target.appendingPathComponent(ActivityHistoryStore.fileName)
        )
        let backupData = try Data(
            contentsOf: target.appendingPathComponent(ActivityHistoryStore.backupFileName)
        )
        XCTAssertEqual(primaryData, backupData)
        XCTAssertEqual(
            try JSONDecoder().decode(ActivityHistory.self, from: primaryData),
            sourcePrimaryHistory
        )
    }

    func testHistoryDatasetMigrationFallsBackToValidSourceBackup() throws {
        let source = temporaryDirectory()
        let target = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: target)
        }
        let date = try makeDate(day: 1, hour: 9)
        var backupHistory = ActivityHistory()
        _ = backupHistory.recordCompleted(at: date, calendar: Self.calendar)
        try ActivityHistoryStore.save(backupHistory, storageDirectory: source)
        var secondHistory = backupHistory
        _ = secondHistory.recordCompleted(at: date, calendar: Self.calendar)
        try ActivityHistoryStore.save(secondHistory, storageDirectory: source)
        try Data("broken-primary".utf8).write(
            to: source.appendingPathComponent(ActivityHistoryStore.fileName)
        )

        try ActivityHistoryStore.migrateDataset(from: source, to: target)

        let primaryData = try Data(
            contentsOf: target.appendingPathComponent(ActivityHistoryStore.fileName)
        )
        let backupData = try Data(
            contentsOf: target.appendingPathComponent(ActivityHistoryStore.backupFileName)
        )
        XCTAssertEqual(primaryData, backupData)
        XCTAssertEqual(try JSONDecoder().decode(ActivityHistory.self, from: primaryData), backupHistory)
    }

    func testHistoryDatasetMigrationImportsSourceBackupWhenPrimaryIsMissing() throws {
        let source = temporaryDirectory()
        let target = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: target)
        }
        let date = try makeDate(day: 1, hour: 9)
        var backupHistory = ActivityHistory()
        _ = backupHistory.recordPostponed(at: date, calendar: Self.calendar)
        let backupData = try JSONEncoder().encode(backupHistory)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try backupData.write(
            to: source.appendingPathComponent(ActivityHistoryStore.backupFileName)
        )

        try ActivityHistoryStore.migrateDataset(from: source, to: target)

        XCTAssertEqual(
            try Data(contentsOf: target.appendingPathComponent(ActivityHistoryStore.fileName)),
            backupData
        )
        XCTAssertEqual(
            try Data(contentsOf: target.appendingPathComponent(ActivityHistoryStore.backupFileName)),
            backupData
        )
    }

    func testHistoryDatasetMigrationNeverMixesPartialTargetWithSource() throws {
        let source = temporaryDirectory()
        let targetWithPrimary = temporaryDirectory()
        let targetWithBackup = temporaryDirectory()
        let targetWithBoth = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: targetWithPrimary)
            try? FileManager.default.removeItem(at: targetWithBackup)
            try? FileManager.default.removeItem(at: targetWithBoth)
        }
        let date = try makeDate(day: 1, hour: 9)
        var sourceHistory = ActivityHistory()
        _ = sourceHistory.recordCompleted(at: date, calendar: Self.calendar)
        try ActivityHistoryStore.save(sourceHistory, storageDirectory: source)

        var targetHistory = ActivityHistory()
        _ = targetHistory.recordPostponed(at: date, calendar: Self.calendar)
        let targetData = try JSONEncoder().encode(targetHistory)
        try FileManager.default.createDirectory(at: targetWithPrimary, withIntermediateDirectories: true)
        try targetData.write(
            to: targetWithPrimary.appendingPathComponent(ActivityHistoryStore.fileName)
        )
        try FileManager.default.createDirectory(at: targetWithBackup, withIntermediateDirectories: true)
        try targetData.write(
            to: targetWithBackup.appendingPathComponent(ActivityHistoryStore.backupFileName)
        )
        try FileManager.default.createDirectory(at: targetWithBoth, withIntermediateDirectories: true)
        try targetData.write(
            to: targetWithBoth.appendingPathComponent(ActivityHistoryStore.fileName)
        )
        try targetData.write(
            to: targetWithBoth.appendingPathComponent(ActivityHistoryStore.backupFileName)
        )

        try ActivityHistoryStore.migrateDataset(from: source, to: targetWithPrimary)
        try ActivityHistoryStore.migrateDataset(from: source, to: targetWithBackup)
        try ActivityHistoryStore.migrateDataset(from: source, to: targetWithBoth)

        XCTAssertEqual(
            try Data(contentsOf: targetWithPrimary.appendingPathComponent(ActivityHistoryStore.fileName)),
            targetData
        )
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: targetWithPrimary.appendingPathComponent(ActivityHistoryStore.backupFileName).path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: targetWithBackup.appendingPathComponent(ActivityHistoryStore.fileName).path
        ))
        XCTAssertEqual(
            try Data(contentsOf: targetWithBackup.appendingPathComponent(ActivityHistoryStore.backupFileName)),
            targetData
        )
        XCTAssertEqual(
            try Data(contentsOf: targetWithBoth.appendingPathComponent(ActivityHistoryStore.fileName)),
            targetData
        )
        XCTAssertEqual(
            try Data(contentsOf: targetWithBoth.appendingPathComponent(ActivityHistoryStore.backupFileName)),
            targetData
        )
    }

    func testConcurrentHistoryRecordsDoNotLoseUpdates() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recordCount = 24

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<recordCount {
                group.addTask {
                    _ = try ActivityHistoryStore.recordCompleted(storageDirectory: directory)
                }
            }
            try await group.waitForAll()
        }

        let history = try ActivityHistoryStore.load(storageDirectory: directory)
        XCTAssertEqual(history.day().completedCount, recordCount)
    }

    func testConcurrentSameIdentifiersDoNotDuplicateTrustedCounts() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let date = try XCTUnwrap(Calendar.current.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 10,
            hour: 10
        )))
        let cycleID = UUID()
        let manualID = UUID()
        let operationCount = 24

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<operationCount {
                group.addTask {
                    _ = try ActivityHistoryStore.beginReminderCycle(
                        id: cycleID,
                        at: date,
                        storageDirectory: directory
                    )
                }
            }
            try await group.waitForAll()
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<operationCount {
                group.addTask {
                    _ = try ActivityHistoryStore.completeReminderCycle(
                        id: cycleID,
                        at: date.addingTimeInterval(60),
                        storageDirectory: directory
                    )
                    _ = try ActivityHistoryStore.recordManualActivity(
                        id: manualID,
                        at: date.addingTimeInterval(120),
                        storageDirectory: directory
                    )
                }
            }
            try await group.waitForAll()
        }

        let history = try ActivityHistoryStore.load(storageDirectory: directory)
        let day = history.day(for: date)
        XCTAssertEqual(day.reminderCycles.count, 1)
        XCTAssertEqual(day.manualActivities.count, 1)
        XCTAssertEqual(day.completedCount, 2)
        XCTAssertEqual(day.reminderCompletedCount, 1)
        XCTAssertEqual(day.manualActivityCount, 1)
        XCTAssertEqual(day.qualifiedActivityCount, 1)
    }

    func testConcurrentManualActivitiesAreAtomicallyRateLimitedAcrossIdentifiers() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let date = try XCTUnwrap(Calendar.current.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 10,
            hour: 23,
            minute: 59
        )))
        let attemptCount = 24
        let recordedCount = try await withThrowingTaskGroup(of: Bool.self) { group in
            for _ in 0..<attemptCount {
                group.addTask {
                    try ActivityHistoryStore.recordManualActivityIfEligible(
                        id: UUID(),
                        at: date,
                        minimumInterval: 5 * 60,
                        storageDirectory: directory
                    ).didRecord
                }
            }

            var count = 0
            for try await didRecord in group {
                if didRecord {
                    count += 1
                }
            }
            return count
        }

        let history = try ActivityHistoryStore.load(storageDirectory: directory)
        let day = history.day(for: date)
        XCTAssertEqual(recordedCount, 1)
        XCTAssertEqual(day.manualActivityCount, 1)
        XCTAssertEqual(day.completedCount, 1)
        XCTAssertEqual(history.latestActivityAt, date)
    }

    func testConcurrentHistoryRecordsAcrossProcessesDoNotLoseUpdates() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let startURL = directory.appendingPathComponent("start")
        let recordsPerWorker = 40
        let cycleID = UUID()
        let manualID = UUID()
        let recordDate = Date()
        let testBundleURL = Bundle(for: ActivityHistoryTests.self).bundleURL
        var workers: [(process: Process, output: Pipe)] = []

        for _ in 0..<2 {
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = [
                "xctest",
                "-XCTest",
                "ActivityHistoryTests/testCrossProcessHistoryWorker",
                testBundleURL.path
            ]
            var environment = ProcessInfo.processInfo.environment
            environment["SITRIGHT_HISTORY_WORKER_DIRECTORY"] = directory.path
            environment["SITRIGHT_HISTORY_WORKER_START"] = startURL.path
            environment["SITRIGHT_HISTORY_WORKER_COUNT"] = String(recordsPerWorker)
            environment["SITRIGHT_HISTORY_WORKER_CYCLE_ID"] = cycleID.uuidString
            environment["SITRIGHT_HISTORY_WORKER_MANUAL_ID"] = manualID.uuidString
            environment["SITRIGHT_HISTORY_WORKER_DATE"] = String(recordDate.timeIntervalSince1970)
            process.environment = environment
            process.standardOutput = output
            process.standardError = output
            try process.run()
            workers.append((process, output))
        }

        try Data().write(to: startURL, options: [.atomic])

        for worker in workers {
            worker.process.waitUntilExit()
            let output = String(
                data: worker.output.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            XCTAssertEqual(worker.process.terminationStatus, 0, output)
        }

        let history = try ActivityHistoryStore.load(storageDirectory: directory)
        let day = history.day(for: recordDate)
        XCTAssertEqual(day.completedCount, recordsPerWorker * workers.count + 2)
        XCTAssertEqual(day.reminderCycles.count, 1)
        XCTAssertEqual(day.reminderCompletedCount, 1)
        XCTAssertEqual(day.manualActivities.count, 1)
        XCTAssertEqual(day.manualActivityCount, 1)

        let primaryData = try Data(
            contentsOf: directory.appendingPathComponent(ActivityHistoryStore.fileName)
        )
        XCTAssertEqual(try JSONDecoder().decode(ActivityHistory.self, from: primaryData), history)
    }

    func testCrossProcessHistoryWorker() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let directoryPath = environment["SITRIGHT_HISTORY_WORKER_DIRECTORY"],
              let startPath = environment["SITRIGHT_HISTORY_WORKER_START"],
              let countText = environment["SITRIGHT_HISTORY_WORKER_COUNT"],
              let recordCount = Int(countText),
              let cycleIDText = environment["SITRIGHT_HISTORY_WORKER_CYCLE_ID"],
              let cycleID = UUID(uuidString: cycleIDText),
              let manualIDText = environment["SITRIGHT_HISTORY_WORKER_MANUAL_ID"],
              let manualID = UUID(uuidString: manualIDText),
              let dateText = environment["SITRIGHT_HISTORY_WORKER_DATE"],
              let dateInterval = TimeInterval(dateText) else {
            return
        }

        let deadline = Date().addingTimeInterval(10)
        while !FileManager.default.fileExists(atPath: startPath) {
            guard Date() < deadline else {
                XCTFail("Timed out waiting for the cross-process start signal")
                return
            }
            Thread.sleep(forTimeInterval: 0.001)
        }

        let directory = URL(fileURLWithPath: directoryPath, isDirectory: true)
        let recordDate = Date(timeIntervalSince1970: dateInterval)
        for _ in 0..<recordCount {
            _ = try ActivityHistoryStore.recordCompleted(
                at: recordDate,
                storageDirectory: directory
            )
            _ = try ActivityHistoryStore.beginReminderCycle(
                id: cycleID,
                at: recordDate,
                storageDirectory: directory
            )
            _ = try ActivityHistoryStore.completeReminderCycle(
                id: cycleID,
                at: recordDate,
                storageDirectory: directory
            )
            _ = try ActivityHistoryStore.recordManualActivity(
                id: manualID,
                at: recordDate,
                storageDirectory: directory
            )
        }
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SitRightActivityHistoryTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeDate(day: Int, hour: Int) throws -> Date {
        try XCTUnwrap(Self.calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: day,
            hour: hour
        )))
    }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()
}
