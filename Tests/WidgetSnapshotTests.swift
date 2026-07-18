import XCTest
@testable import SitRight

@MainActor
final class WidgetSnapshotTests: XCTestCase {
    func testDueSnapshotProgressIsCompleteWhenNoNextReminderDate() {
        XCTAssertEqual(snapshot(state: .due, nextReminderAt: nil).progress(), 1)
    }

    func testNonRunningSnapshotsHaveNoCountdownProgress() {
        XCTAssertEqual(snapshot(state: .paused).progress(), 0)
        XCTAssertEqual(snapshot(state: .outsideHours).progress(), 0)
        XCTAssertEqual(snapshot(state: .disabled).progress(), 0)
    }

    func testCompletionProgressIsClampedToDailyTarget() {
        var snapshot = snapshot(state: .running)
        snapshot.completedCount = 20
        snapshot.reminderCompletedCount = 12
        snapshot.manualActivityCount = 7
        snapshot.dailyTarget = 8

        XCTAssertEqual(snapshot.completionProgress, 1)
    }

    func testCompletionProgressClampsNegativeCountToZero() {
        var snapshot = snapshot(state: .running)
        snapshot.completedCount = 10
        snapshot.reminderCompletedCount = -1

        XCTAssertEqual(snapshot.completionProgress, 0)
    }

    func testCompletionProgressCountsQualifiedActivitiesInsteadOfRawLegacyManualActivities() {
        var snapshot = snapshot(state: .running)
        snapshot.completedCount = 9
        snapshot.reminderCompletedCount = 2
        snapshot.manualActivityCount = 7
        snapshot.dailyGoalActivityCount = 2
        snapshot.dailyTarget = 8

        XCTAssertEqual(snapshot.completionProgress, 0.25)
    }

    func testResponseRateUsesReminderResponsesOverAllReminderOpportunities() throws {
        var snapshot = snapshot(state: .running)
        snapshot.completedCount = 10
        snapshot.reminderCompletedCount = 2
        snapshot.reminderOpportunityCount = 5
        snapshot.manualActivityCount = 8

        XCTAssertEqual(try XCTUnwrap(snapshot.responseRate), 0.4, accuracy: 0.000_001)

        snapshot.reminderOpportunityCount = 0
        XCTAssertNil(snapshot.responseRate)
    }

    func testLegacySnapshotDecodesMissingFieldsWithDefaults() throws {
        let data = try XCTUnwrap(
            """
            {
              "updatedAt": 0,
              "state": "running"
            }
            """.data(using: .utf8)
        )

        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)

        XCTAssertEqual(decoded.state, .running)
        XCTAssertEqual(decoded.intervalMinutes, 50)
        XCTAssertEqual(decoded.dailyTarget, 8)
        XCTAssertEqual(decoded.completedCount, 0)
        XCTAssertEqual(decoded.reminderCompletedCount, 0)
        XCTAssertEqual(decoded.reminderOpportunityCount, 0)
        XCTAssertEqual(decoded.manualActivityCount, 0)
        XCTAssertEqual(decoded.legacyUnclassifiedCount, 0)
        XCTAssertEqual(decoded.qualifiedActivityCount, 0)
        XCTAssertEqual(decoded.dailyGoalActivityCount, 0)
        XCTAssertNil(decoded.phase)
        XCTAssertNil(decoded.responseRate)
    }

    func testUnknownFuturePhaseDoesNotInvalidateSnapshot() throws {
        let data = try XCTUnwrap(
            """
            {
              "updatedAt": 0,
              "state": "running",
              "completedCount": 3,
              "phase": "futurePhase"
            }
            """.data(using: .utf8)
        )

        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)

        XCTAssertEqual(decoded.completedCount, 3)
        XCTAssertEqual(decoded.state, .running)
        XCTAssertNil(decoded.phase)
    }

    func testLegacySnapshotPreservesRawCountAsUnclassifiedQualifiedActivity() throws {
        let data = try XCTUnwrap(
            """
            {
              "updatedAt": 0,
              "state": "running",
              "completedCount": 6
            }
            """.data(using: .utf8)
        )

        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)

        XCTAssertEqual(decoded.completedCount, 6)
        XCTAssertEqual(decoded.reminderCompletedCount, 0)
        XCTAssertEqual(decoded.reminderOpportunityCount, 0)
        XCTAssertEqual(decoded.manualActivityCount, 0)
        XCTAssertEqual(decoded.legacyUnclassifiedCount, 6)
        XCTAssertEqual(decoded.qualifiedActivityCount, 6)
        XCTAssertEqual(decoded.completionProgress, 0)
        XCTAssertNil(decoded.responseRate)
    }

    func testPublishingUnchangedSnapshotDoesNotRewriteFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SitRightWidgetSyncTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let controller = WidgetSyncController(storageDirectory: directory, reloadTimelines: false)
        let settings = AppSettings()
        var stats = DailyStats(dateKey: "2026-07-10")

        controller.publish(
            settings: settings,
            stats: stats,
            nextReminderAt: Date(timeIntervalSince1970: 3_600),
            state: .running,
            statusText: "提醒进行中",
            now: Date(timeIntervalSince1970: 0)
        )
        let snapshotURL = directory.appendingPathComponent(WidgetSnapshotStore.fileName)
        let firstData = try Data(contentsOf: snapshotURL)

        controller.publish(
            settings: settings,
            stats: stats,
            nextReminderAt: Date(timeIntervalSince1970: 3_600),
            state: .running,
            statusText: "提醒进行中",
            now: Date(timeIntervalSince1970: 120)
        )
        XCTAssertEqual(try Data(contentsOf: snapshotURL), firstData)

        stats.completedCount = 1
        controller.publish(
            settings: settings,
            stats: stats,
            nextReminderAt: Date(timeIntervalSince1970: 3_600),
            state: .running,
            statusText: "提醒进行中",
            now: Date(timeIntervalSince1970: 121)
        )
        XCTAssertNotEqual(try Data(contentsOf: snapshotURL), firstData)
    }

    func testPublishingNewReminderOpportunityRewritesSnapshotWithoutRawCountChange() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SitRightWidgetOpportunityTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let controller = WidgetSyncController(storageDirectory: directory, reloadTimelines: false)
        let settings = AppSettings()
        let date = Date(timeIntervalSince1970: 3_600)
        var history = ActivityHistory()
        var stats = history.day(for: date)

        controller.publish(
            settings: settings,
            stats: stats,
            nextReminderAt: date.addingTimeInterval(3_600),
            state: .running,
            statusText: "提醒进行中",
            now: date
        )
        let snapshotURL = directory.appendingPathComponent(WidgetSnapshotStore.fileName)
        let firstData = try Data(contentsOf: snapshotURL)

        _ = history.beginReminderCycle(id: UUID(), at: date)
        stats = history.day(for: date)
        XCTAssertEqual(stats.completedCount, 0)
        controller.publish(
            settings: settings,
            stats: stats,
            nextReminderAt: date.addingTimeInterval(3_600),
            state: .running,
            statusText: "提醒进行中",
            now: date.addingTimeInterval(1)
        )

        XCTAssertNotEqual(try Data(contentsOf: snapshotURL), firstData)
        let saved = WidgetSnapshotStore.load(storageDirectory: directory)
        XCTAssertEqual(saved.completedCount, 0)
        XCTAssertEqual(saved.reminderCompletedCount, 0)
        XCTAssertEqual(saved.reminderOpportunityCount, 1)
        XCTAssertEqual(saved.responseRate, 0)
    }

    func testPublishingCopiesCompatibleAndDerivedActivityMetrics() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SitRightWidgetMetricTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let controller = WidgetSyncController(storageDirectory: directory, reloadTimelines: false)
        let settings = AppSettings()
        let date = Date(timeIntervalSince1970: 3_600)
        var history = ActivityHistory()
        let completedCycleID = UUID()
        let expiredCycleID = UUID()

        _ = history.recordCompleted(at: date)
        _ = history.beginReminderCycle(id: completedCycleID, at: date.addingTimeInterval(60))
        _ = history.completeReminderCycle(id: completedCycleID, at: date.addingTimeInterval(120))
        _ = history.beginReminderCycle(id: expiredCycleID, at: date.addingTimeInterval(180))
        _ = history.resolveReminderCycle(
            id: expiredCycleID,
            outcome: .expired,
            at: date.addingTimeInterval(240)
        )
        _ = history.beginReminderCycle(id: UUID(), at: date.addingTimeInterval(300))
        _ = history.recordManualActivity(id: UUID(), at: date.addingTimeInterval(360))
        let stats = history.day(for: date)

        controller.publish(
            settings: settings,
            stats: stats,
            nextReminderAt: date.addingTimeInterval(3_600),
            state: .running,
            statusText: "提醒进行中",
            now: date.addingTimeInterval(420)
        )

        let saved = WidgetSnapshotStore.load(storageDirectory: directory)
        XCTAssertEqual(saved.completedCount, 3)
        XCTAssertEqual(saved.reminderCompletedCount, 1)
        XCTAssertEqual(saved.reminderOpportunityCount, 3)
        XCTAssertEqual(saved.manualActivityCount, 1)
        XCTAssertEqual(saved.legacyUnclassifiedCount, 1)
        XCTAssertEqual(saved.qualifiedActivityCount, 2)
        XCTAssertEqual(try XCTUnwrap(saved.responseRate), 1.0 / 3.0, accuracy: 0.000_001)
    }

    func testPublishingSameSnapshotRetriesAfterWriteFailure() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SitRightWidgetSyncRetryTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("blocks-directory-creation".utf8).write(to: directory)
        let controller = WidgetSyncController(storageDirectory: directory, reloadTimelines: false)
        let settings = AppSettings()
        let stats = DailyStats(dateKey: "2026-07-10")
        let nextReminderAt = Date(timeIntervalSince1970: 3_600)

        controller.publish(
            settings: settings,
            stats: stats,
            nextReminderAt: nextReminderAt,
            state: .running,
            statusText: "提醒进行中",
            now: Date(timeIntervalSince1970: 0)
        )

        try FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        controller.publish(
            settings: settings,
            stats: stats,
            nextReminderAt: nextReminderAt,
            state: .running,
            statusText: "提醒进行中",
            now: Date(timeIntervalSince1970: 120)
        )

        let saved = WidgetSnapshotStore.load(storageDirectory: directory)
        XCTAssertEqual(saved.updatedAt, Date(timeIntervalSince1970: 120))
        XCTAssertEqual(saved.nextReminderAt, nextReminderAt)
        XCTAssertEqual(saved.state, .running)
    }

    private func snapshot(
        state: WidgetSnapshot.RunState,
        nextReminderAt: Date? = Date(timeIntervalSince1970: 45 * 60)
    ) -> WidgetSnapshot {
        WidgetSnapshot(
            updatedAt: Date(timeIntervalSince1970: 0),
            nextReminderAt: nextReminderAt,
            intervalMinutes: 45,
            state: state,
            statusText: "",
            completedCount: 0,
            dailyTarget: 8,
            dateKey: "2026-07-02"
        )
    }
}
