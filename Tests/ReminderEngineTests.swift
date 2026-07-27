import XCTest
@testable import SitRight

@MainActor
final class ReminderEngineTests: XCTestCase {
    func testReminderStartsAfterAccumulatingEligibleThreshold() throws {
        let harness = makeHarness()
        defer { harness.cleanup() }
        harness.start()

        harness.advance(by: 5 * 60 - 1)
        XCTAssertEqual(harness.engine.phase, .accumulating)
        XCTAssertEqual(harness.presenter.presentedCount, 0)

        harness.advance(by: 1)
        XCTAssertEqual(harness.engine.phase, .awaitingResponse)
        XCTAssertEqual(harness.presenter.presentedCount, 1)
        XCTAssertEqual(harness.statsStore.today.reminderOpportunityCount, 1)
        XCTAssertEqual(
            harness.engine.activeReminderCycle?.responseDeadline,
            harness.clock.now.addingTimeInterval(ReminderTiming.responseWindow)
        )
    }

    func testPromptedActivityCountsOnlyAfterFullSixtySecondGuide() throws {
        let harness = makeHarness()
        defer { harness.cleanup() }
        try harness.triggerReminder()

        harness.presenter.send(.completed)
        XCTAssertEqual(harness.engine.phase, .guiding)
        XCTAssertEqual(harness.statsStore.today.dailyGoalActivityCount, 0)

        harness.advance(by: 59)
        XCTAssertEqual(harness.statsStore.today.dailyGoalActivityCount, 0)
        XCTAssertEqual(harness.engine.phase, .guiding)

        harness.advance(by: 1)
        XCTAssertEqual(harness.statsStore.today.reminderCompletedCount, 1)
        XCTAssertEqual(harness.statsStore.today.dailyGoalActivityCount, 1)
        XCTAssertEqual(harness.engine.phase, .accumulating)
        XCTAssertEqual(harness.engine.accumulatedEligibleSeconds, 0)
        XCTAssertEqual(
            harness.engine.celebrationText,
            ActivityGuideCompletionOutcome.reminderResponse.celebrationText
        )
        XCTAssertEqual(
            harness.presenter.completionMessages,
            [ActivityGuideCompletionOutcome.reminderResponse.celebrationText]
        )
    }

    func testPausingDuringGuideAbortsItAndAllowsAnotherActivity() {
        let harness = makeHarness()
        defer { harness.cleanup() }
        harness.start()

        harness.engine.startActivity()
        harness.advance(by: 20)
        harness.engine.pause(minutes: 1)
        XCTAssertNotEqual(harness.engine.phase, .guiding)
        XCTAssertTrue(harness.engine.guideElapsedSeconds == 0)

        harness.advance(by: 60)
        harness.engine.resume()
        XCTAssertTrue(harness.engine.canRecordManualActivity)
    }

    func testProactiveGuideCountsTowardGoalButNotReminderResponse() {
        let harness = makeHarness()
        defer { harness.cleanup() }
        harness.start()

        harness.engine.startActivity()
        harness.advance(by: 60)

        XCTAssertEqual(harness.statsStore.today.qualifiedProactiveCount, 1)
        XCTAssertEqual(harness.statsStore.today.reminderCompletedCount, 0)
        XCTAssertEqual(harness.statsStore.today.dailyGoalActivityCount, 1)
        XCTAssertEqual(harness.statsStore.today.reminderOpportunityCount, 0)
    }

    func testEarlyProactiveGuidePreservesOriginalReminderWhileCadenceContinues() throws {
        let harness = makeHarness { $0.intervalMinutes = 45 }
        defer { harness.cleanup() }
        harness.start()
        let originalReminderAt = try XCTUnwrap(harness.engine.nextReminderAt)
        harness.advance(by: 5 * 60)

        harness.engine.startActivity()
        harness.advance(by: ReminderTiming.guidedActivityDuration)

        XCTAssertEqual(harness.engine.accumulatedEligibleSeconds, 6 * 60)
        XCTAssertEqual(harness.engine.nextReminderAt, originalReminderAt)
        XCTAssertEqual(
            harness.engine.celebrationText,
            ActivityGuideCompletionOutcome.proactivePreservingCadence.celebrationText
        )
        XCTAssertEqual(
            harness.presenter.completionMessages,
            [ActivityGuideCompletionOutcome.proactivePreservingCadence.celebrationText]
        )
        XCTAssertEqual(harness.statsStore.today.qualifiedProactiveCount, 1)
        XCTAssertEqual(harness.statsStore.today.reminderOpportunityCount, 0)

        let snapshot = WidgetSnapshotStore.load(storageDirectory: harness.storageDirectory)
        XCTAssertEqual(snapshot.nextReminderAt, originalReminderAt)
        XCTAssertEqual(snapshot.accumulatedEligibleSeconds, 6 * 60)
        XCTAssertEqual(snapshot.qualifiedProactiveCount, 1)
    }

    func testProactiveGuideDoesNotRewriteWidgetSnapshotEveryTick() throws {
        let harness = makeHarness { $0.intervalMinutes = 45 }
        defer { harness.cleanup() }
        harness.start()
        harness.engine.startActivity()
        let snapshotURL = harness.storageDirectory.appendingPathComponent(
            WidgetSnapshotStore.fileName
        )
        let snapshotAtGuideStart = try Data(contentsOf: snapshotURL)

        harness.advance(by: 30)

        XCTAssertEqual(
            try Data(contentsOf: snapshotURL),
            snapshotAtGuideStart
        )
        XCTAssertEqual(harness.engine.accumulatedEligibleSeconds, 30)

        harness.advance(by: 30)

        XCTAssertNotEqual(
            try Data(contentsOf: snapshotURL),
            snapshotAtGuideStart
        )
        let completedSnapshot = WidgetSnapshotStore.load(
            storageDirectory: harness.storageDirectory
        )
        XCTAssertEqual(completedSnapshot.accumulatedEligibleSeconds, 60)
        XCTAssertEqual(completedSnapshot.qualifiedProactiveCount, 1)
    }

    func testProactiveGuideJustOutsideProtectionWindowPreservesCadence() throws {
        let harness = makeHarness { $0.intervalMinutes = 45 }
        defer { harness.cleanup() }
        harness.start()
        let originalReminderAt = try XCTUnwrap(harness.engine.nextReminderAt)
        harness.advance(by: 33 * 60 + 59)

        harness.engine.startActivity()
        harness.advance(by: ReminderTiming.guidedActivityDuration)

        XCTAssertEqual(harness.engine.remainingInterval, 10 * 60 + 1)
        XCTAssertEqual(harness.engine.nextReminderAt, originalReminderAt)
        XCTAssertEqual(
            harness.engine.celebrationText,
            ActivityGuideCompletionOutcome.proactivePreservingCadence.celebrationText
        )
    }

    func testProactiveGuideAtProtectionBoundarySatisfiesUpcomingReminder() {
        let harness = makeHarness { $0.intervalMinutes = 45 }
        defer { harness.cleanup() }
        harness.start()
        harness.advance(by: 34 * 60)

        harness.engine.startActivity()
        harness.advance(by: ReminderTiming.guidedActivityDuration)

        XCTAssertEqual(harness.engine.accumulatedEligibleSeconds, 0)
        XCTAssertEqual(harness.engine.remainingInterval, 45 * 60)
        XCTAssertEqual(
            harness.engine.nextReminderAt,
            harness.clock.now.addingTimeInterval(45 * 60)
        )
        XCTAssertEqual(
            harness.engine.celebrationText,
            ActivityGuideCompletionOutcome.proactiveSatisfyingUpcomingReminder.celebrationText
        )
        XCTAssertEqual(harness.statsStore.today.qualifiedProactiveCount, 1)
        XCTAssertEqual(harness.statsStore.today.reminderOpportunityCount, 0)
        XCTAssertEqual(harness.statsStore.today.reminderCompletedCount, 0)
    }

    func testProactiveGuideInsideProtectionWindowSatisfiesUpcomingReminder() {
        let harness = makeHarness { $0.intervalMinutes = 45 }
        defer { harness.cleanup() }
        harness.start()
        harness.advance(by: 34 * 60 + 1)

        harness.engine.startActivity()
        harness.advance(by: ReminderTiming.guidedActivityDuration)

        XCTAssertEqual(harness.engine.accumulatedEligibleSeconds, 0)
        XCTAssertEqual(harness.engine.remainingInterval, 45 * 60)
        XCTAssertEqual(
            harness.engine.celebrationText,
            ActivityGuideCompletionOutcome.proactiveSatisfyingUpcomingReminder.celebrationText
        )
        XCTAssertEqual(harness.statsStore.today.reminderOpportunityCount, 0)
    }

    func testCancellingProactiveGuideDoesNotScoreOrResetAndDueReminderStillFires() {
        let harness = makeHarness { $0.intervalMinutes = 45 }
        defer { harness.cleanup() }
        harness.start()
        harness.advance(by: 44 * 60 + 50)

        harness.engine.startActivity()
        harness.advance(by: 20)
        harness.presenter.send(.dismissed)

        XCTAssertEqual(harness.statsStore.today.dailyGoalActivityCount, 0)
        XCTAssertEqual(harness.engine.accumulatedEligibleSeconds, 45 * 60)
        XCTAssertEqual(harness.engine.phase, .overdue)
        XCTAssertEqual(harness.engine.nextReminderAt, harness.clock.now)

        harness.advance(by: 1)
        XCTAssertEqual(harness.engine.phase, .awaitingResponse)
        XCTAssertEqual(harness.statsStore.today.reminderOpportunityCount, 1)
        XCTAssertEqual(harness.presenter.presentedCount, 2)
    }

    func testGuideStartedBeforeDeadlineCanFinishAfterDeadline() throws {
        let harness = makeHarness()
        defer { harness.cleanup() }
        try harness.triggerReminder()
        let deadline = try XCTUnwrap(harness.engine.activeReminderCycle?.responseDeadline)

        harness.move(to: deadline.addingTimeInterval(-1))
        harness.engine.startActivity()
        harness.move(to: deadline.addingTimeInterval(59))

        XCTAssertEqual(harness.statsStore.today.reminderCompletedCount, 1)
        XCTAssertEqual(harness.engine.phase, .accumulating)
    }

    func testUnansweredOpportunityExpiresWithoutResettingActivityClock() throws {
        let harness = makeHarness()
        defer { harness.cleanup() }
        try harness.triggerReminder()
        let deadline = try XCTUnwrap(harness.engine.activeReminderCycle?.responseDeadline)

        harness.move(to: deadline.addingTimeInterval(1))

        XCTAssertEqual(harness.engine.phase, .overdue)
        XCTAssertNil(harness.engine.activeReminderCycle)
        XCTAssertEqual(harness.engine.accumulatedEligibleSeconds, 5 * 60)
        XCTAssertEqual(harness.engine.opportunityCooldownSeconds, 5 * 60)
        XCTAssertEqual(harness.statsStore.today.reminderOpportunityCount, 1)
        XCTAssertEqual(harness.statsStore.today.reminderCompletedCount, 0)
    }

    func testExpiredOpportunityCreatesNewOpportunityAfterEligibleCooldown() throws {
        let harness = makeHarness()
        defer { harness.cleanup() }
        try harness.triggerReminder()
        let deadline = try XCTUnwrap(harness.engine.activeReminderCycle?.responseDeadline)
        harness.move(to: deadline.addingTimeInterval(1))

        harness.advance(by: 5 * 60)

        XCTAssertEqual(harness.statsStore.today.reminderOpportunityCount, 2)
        XCTAssertEqual(harness.engine.phase, .awaitingResponse)
    }

    func testProactiveGuideCompletionDuringOverdueCooldownSatisfiesUpcomingReminder() throws {
        let harness = makeHarness()
        defer { harness.cleanup() }
        try harness.triggerReminder()
        let deadline = try XCTUnwrap(harness.engine.activeReminderCycle?.responseDeadline)
        harness.move(to: deadline.addingTimeInterval(1))

        harness.engine.startActivity()
        harness.advance(by: ReminderTiming.guidedActivityDuration)

        XCTAssertEqual(harness.engine.phase, .accumulating)
        XCTAssertEqual(harness.engine.accumulatedEligibleSeconds, 0)
        XCTAssertEqual(harness.engine.opportunityCooldownSeconds, 0)
        XCTAssertEqual(harness.engine.remainingInterval, 5 * 60)
        XCTAssertEqual(
            harness.engine.nextReminderAt,
            harness.clock.now.addingTimeInterval(5 * 60)
        )
        XCTAssertEqual(harness.statsStore.today.qualifiedProactiveCount, 1)
        XCTAssertEqual(harness.statsStore.today.reminderOpportunityCount, 1)
        XCTAssertEqual(harness.statsStore.today.reminderCompletedCount, 0)
    }

    func testCancellingProactiveGuideContinuesOverdueCooldownAndWidgetDeadline() throws {
        let harness = makeHarness()
        defer { harness.cleanup() }
        try harness.triggerReminder()
        let deadline = try XCTUnwrap(harness.engine.activeReminderCycle?.responseDeadline)
        harness.move(to: deadline.addingTimeInterval(1))

        harness.engine.startActivity()
        harness.advance(by: 30)
        harness.presenter.send(.dismissed)

        XCTAssertEqual(harness.engine.phase, .overdue)
        XCTAssertEqual(harness.engine.opportunityCooldownSeconds, 4 * 60 + 30)
        XCTAssertEqual(
            harness.engine.nextReminderAt,
            harness.clock.now.addingTimeInterval(4 * 60 + 30)
        )
        XCTAssertEqual(harness.statsStore.today.dailyGoalActivityCount, 0)
        XCTAssertEqual(harness.statsStore.today.reminderOpportunityCount, 1)

        let snapshot = WidgetSnapshotStore.load(
            storageDirectory: harness.storageDirectory
        )
        XCTAssertEqual(snapshot.nextReminderAt, harness.engine.nextReminderAt)
        XCTAssertEqual(snapshot.accumulatedEligibleSeconds, 5 * 60)
    }

    func testRestartDuringProactiveGuideRestoresAdvancedOverdueCooldown() throws {
        let defaults = makeDefaults()
        let directory = temporaryDirectory()
        let first = makeHarness(storageDirectory: directory, defaults: defaults)
        try first.triggerReminder()
        let deadline = try XCTUnwrap(first.engine.activeReminderCycle?.responseDeadline)
        first.move(to: deadline.addingTimeInterval(1))
        first.engine.startActivity()
        first.advance(by: 30)

        let restartDate = first.clock.now.addingTimeInterval(2)
        let restarted = makeHarness(
            storageDirectory: directory,
            defaults: defaults,
            date: restartDate
        )
        restarted.start()

        XCTAssertNotEqual(restarted.engine.phase, .guiding)
        XCTAssertEqual(restarted.engine.phase, .overdue)
        XCTAssertEqual(restarted.engine.opportunityCooldownSeconds, 4 * 60 + 30)
        XCTAssertEqual(
            restarted.engine.nextReminderAt,
            restartDate.addingTimeInterval(4 * 60 + 30)
        )
        XCTAssertEqual(restarted.statsStore.today.dailyGoalActivityCount, 0)
        restarted.cleanup()
    }

    func testSnoozeCanBeUsedOnlyOnceAndGetsFreshResponseWindow() throws {
        let harness = makeHarness()
        defer { harness.cleanup() }
        try harness.triggerReminder()
        let cycleID = try XCTUnwrap(harness.engine.activeReminderCycle?.id)
        let snoozeActionAt = harness.clock.now

        harness.engine.snooze()
        let snoozedUntil = snoozeActionAt.addingTimeInterval(ReminderTiming.snoozeDuration)
        XCTAssertEqual(harness.engine.phase, .snoozed)
        XCTAssertEqual(harness.engine.activeReminderCycle?.snoozeCount, 1)
        XCTAssertEqual(harness.engine.activeReminderCycle?.snoozedUntil, snoozedUntil)

        harness.engine.snooze()
        XCTAssertEqual(harness.engine.activeReminderCycle?.snoozeCount, 1)

        harness.move(to: snoozedUntil)
        XCTAssertEqual(harness.engine.phase, .awaitingResponse)
        XCTAssertEqual(harness.engine.activeReminderCycle?.id, cycleID)
        XCTAssertEqual(
            harness.engine.activeReminderCycle?.responseDeadline,
            snoozedUntil.addingTimeInterval(ReminderTiming.responseWindow)
        )
        XCTAssertFalse(harness.engine.canSnooze)
        XCTAssertEqual(harness.statsStore.today.reminderOpportunityCount, 1)
    }

    func testStaleAndDuplicateNotificationActionsAreIgnored() throws {
        let harness = makeHarness { settings in
            settings.popupEnabled = false
            settings.notificationsEnabled = true
        }
        defer { harness.cleanup() }
        try harness.triggerReminder()
        let cycleID = try XCTUnwrap(harness.engine.activeReminderCycle?.id)

        harness.notificationManager.send(.startActivity(cycleID: UUID()))
        XCTAssertEqual(harness.engine.phase, .awaitingResponse)

        harness.notificationManager.send(.startActivity(cycleID: cycleID))
        XCTAssertEqual(harness.engine.phase, .guiding)
        harness.notificationManager.send(.startActivity(cycleID: cycleID))
        harness.advance(by: 60)

        XCTAssertEqual(harness.statsStore.today.reminderCompletedCount, 1)
        harness.notificationManager.send(.startActivity(cycleID: cycleID))
        XCTAssertEqual(harness.statsStore.today.reminderCompletedCount, 1)
    }

    func testLateNotificationActionAfterResponseDeadlineIsIgnored() throws {
        let harness = makeHarness { settings in
            settings.popupEnabled = false
            settings.notificationsEnabled = true
        }
        defer { harness.cleanup() }
        try harness.triggerReminder()
        let cycleID = try XCTUnwrap(harness.engine.activeReminderCycle?.id)
        let deadline = try XCTUnwrap(harness.engine.activeReminderCycle?.responseDeadline)
        harness.move(to: deadline.addingTimeInterval(1))

        harness.notificationManager.send(.startActivity(cycleID: cycleID))

        XCTAssertNotEqual(harness.engine.phase, .guiding)
        XCTAssertEqual(harness.statsStore.today.dailyGoalActivityCount, 0)
    }

    func testNotificationFailureCreatesNoOpportunityAndDoesNotRetryEveryTick() throws {
        let notifier = StubNotificationManager(results: [false])
        let harness = makeHarness(notificationManager: notifier) { settings in
            settings.popupEnabled = false
            settings.notificationsEnabled = true
        }
        defer { harness.cleanup() }
        try harness.triggerReminder()

        XCTAssertEqual(notifier.deliveredCount, 1)
        XCTAssertEqual(harness.statsStore.today.reminderOpportunityCount, 0)
        XCTAssertEqual(harness.engine.phase, .overdue)

        for _ in 0..<20 { harness.advance(by: 1) }
        XCTAssertEqual(notifier.deliveredCount, 1)
        XCTAssertEqual(harness.statsStore.today.reminderOpportunityCount, 0)
    }

    func testNoDeliveryChannelsCreateNoFalseOpportunityOrRetryStorm() throws {
        let harness = makeHarness { settings in
            settings.popupEnabled = false
            settings.notificationsEnabled = false
        }
        defer { harness.cleanup() }
        try harness.triggerReminder()

        XCTAssertEqual(harness.notificationManager.deliveredCount, 0)
        XCTAssertEqual(harness.presenter.presentedCount, 0)
        XCTAssertEqual(harness.statsStore.today.reminderOpportunityCount, 0)
        XCTAssertEqual(harness.engine.phase, .overdue)
        for _ in 0..<20 { harness.advance(by: 1) }
        XCTAssertEqual(harness.notificationManager.deliveredCount, 0)
    }

    func testProactiveActivitySatisfiesDueRoundWhenNoDeliveryChannelExists() throws {
        let harness = makeHarness { settings in
            settings.popupEnabled = false
            settings.notificationsEnabled = false
        }
        defer { harness.cleanup() }
        try harness.triggerReminder()
        XCTAssertEqual(harness.engine.phase, .overdue)
        XCTAssertNil(harness.engine.nextReminderAt)

        harness.engine.startActivity()
        harness.advance(by: ReminderTiming.guidedActivityDuration)

        XCTAssertEqual(harness.engine.phase, .accumulating)
        XCTAssertEqual(harness.engine.remainingInterval, 5 * 60)
        XCTAssertEqual(
            harness.engine.nextReminderAt,
            harness.clock.now.addingTimeInterval(5 * 60)
        )
        XCTAssertEqual(
            harness.engine.celebrationText,
            ActivityGuideCompletionOutcome
                .proactiveSatisfyingUpcomingReminder
                .celebrationText
        )
        XCTAssertEqual(harness.statsStore.today.qualifiedProactiveCount, 1)
        XCTAssertEqual(harness.statsStore.today.reminderOpportunityCount, 0)
        XCTAssertEqual(harness.statsStore.today.reminderCompletedCount, 0)
    }

    func testProactiveActivitySatisfiesDueRoundAfterNotificationDeliveryFailure() throws {
        let notifier = StubNotificationManager(results: [false])
        let harness = makeHarness(notificationManager: notifier) { settings in
            settings.popupEnabled = false
            settings.notificationsEnabled = true
        }
        defer { harness.cleanup() }
        try harness.triggerReminder()
        XCTAssertEqual(harness.engine.phase, .overdue)
        XCTAssertNil(harness.engine.nextReminderAt)

        harness.engine.startActivity()
        harness.advance(by: ReminderTiming.guidedActivityDuration)

        XCTAssertEqual(harness.engine.phase, .accumulating)
        XCTAssertEqual(harness.engine.remainingInterval, 5 * 60)
        XCTAssertEqual(
            harness.engine.nextReminderAt,
            harness.clock.now.addingTimeInterval(5 * 60)
        )
        XCTAssertEqual(harness.statsStore.today.qualifiedProactiveCount, 1)
        XCTAssertEqual(harness.statsStore.today.reminderOpportunityCount, 0)
        XCTAssertEqual(harness.statsStore.today.reminderCompletedCount, 0)
    }

    func testNotificationOnlySuccessCreatesOnePendingOpportunity() throws {
        let harness = makeHarness { settings in
            settings.popupEnabled = false
            settings.notificationsEnabled = true
        }
        defer { harness.cleanup() }
        try harness.triggerReminder()

        XCTAssertEqual(harness.notificationManager.deliveredCount, 1)
        XCTAssertEqual(harness.statsStore.today.reminderOpportunityCount, 1)
        XCTAssertEqual(harness.engine.phase, .awaitingResponse)
        XCTAssertEqual(harness.presenter.presentedCount, 0)
    }

    func testLunchBreakDiscardsFortyNineMinutesAndRestartsFullThreshold() throws {
        let base = try makeLocalDate(hour: 11, minute: 10)
        let harness = makeHarness(date: base) { settings in
            settings.intervalMinutes = 50
            settings.workStartMinutes = 9 * 60
            settings.workEndMinutes = 18 * 60
            settings.lunchPauseEnabled = true
            settings.lunchStartMinutes = 12 * 60
            settings.lunchEndMinutes = 13 * 60 + 30
        }
        defer { harness.cleanup() }
        harness.start()
        harness.advance(by: 49 * 60)
        XCTAssertEqual(harness.engine.accumulatedEligibleSeconds, 49 * 60)

        harness.move(to: try makeLocalDate(hour: 12, minute: 1))
        XCTAssertEqual(harness.engine.phase, .outsideSchedule)
        XCTAssertEqual(harness.engine.accumulatedEligibleSeconds, 0)

        harness.move(to: try makeLocalDate(hour: 13, minute: 30))
        XCTAssertEqual(harness.engine.remainingInterval, 50 * 60)
    }

    func testPauseAndResumeRestartFullThresholdWithoutAddingCompletion() {
        let harness = makeHarness()
        defer { harness.cleanup() }
        harness.start()
        harness.advance(by: 4 * 60)

        harness.engine.pause()
        XCTAssertEqual(harness.engine.phase, .paused)
        harness.advance(by: 60 * 60)
        harness.engine.resume()

        XCTAssertEqual(harness.engine.remainingInterval, 5 * 60)
        XCTAssertEqual(harness.statsStore.today.dailyGoalActivityCount, 0)
        XCTAssertEqual(harness.statsStore.today.eligibilitySnapshot, .scheduled)
    }

    func testCrossDayAndWeekendStartWithFreshThreshold() throws {
        let friday = try makeLocalDate(year: 2026, month: 7, day: 3, hour: 17, minute: 56)
        let harness = makeHarness(date: friday) { settings in
            settings.intervalMinutes = 5
            settings.workdaysOnly = true
            settings.workStartMinutes = 9 * 60
            settings.workEndMinutes = 18 * 60
        }
        defer { harness.cleanup() }
        harness.start()
        harness.advance(by: 4 * 60)

        let monday = try makeLocalDate(year: 2026, month: 7, day: 6, hour: 9, minute: 0)
        harness.move(to: monday)

        XCTAssertEqual(harness.engine.phase, .accumulating)
        XCTAssertEqual(harness.engine.remainingInterval, 5 * 60)
        XCTAssertEqual(harness.engine.accumulatedEligibleSeconds, 0)
    }

    func testShortLockFreezesCadenceClock() {
        let harness = makeHarness()
        defer { harness.cleanup() }
        harness.start()
        harness.advance(by: 4 * 60)
        let lockedAt = harness.clock.now

        harness.engine.sessionDidBecomeInactive(at: lockedAt)
        harness.clock.now = lockedAt.addingTimeInterval(5 * 60)
        harness.engine.tick()
        harness.engine.suspensionDidEnd(at: harness.clock.now)

        XCTAssertEqual(harness.engine.accumulatedEligibleSeconds, 4 * 60)
        XCTAssertEqual(harness.engine.remainingInterval, 60)
    }

    func testLongLockResetsCadenceWithoutClaimingActivity() {
        let harness = makeHarness()
        defer { harness.cleanup() }
        harness.start()
        harness.advance(by: 4 * 60)
        let lockedAt = harness.clock.now

        harness.engine.sessionDidBecomeInactive(at: lockedAt)
        harness.clock.now = lockedAt.addingTimeInterval(10 * 60)
        harness.engine.suspensionDidEnd(at: harness.clock.now)

        XCTAssertEqual(harness.engine.accumulatedEligibleSeconds, 0)
        XCTAssertEqual(harness.engine.remainingInterval, 5 * 60)
        XCTAssertEqual(harness.statsStore.today.dailyGoalActivityCount, 0)
    }

    func testShortSleepPausesGuideButShortLockLetsGuideContinue() {
        let sleepHarness = makeHarness()
        defer { sleepHarness.cleanup() }
        sleepHarness.start()
        sleepHarness.engine.startActivity()
        sleepHarness.advance(by: 20)
        XCTAssertEqual(sleepHarness.engine.accumulatedEligibleSeconds, 20)
        let sleptAt = sleepHarness.clock.now
        sleepHarness.engine.systemWillSleep(at: sleptAt)
        sleepHarness.clock.now = sleptAt.addingTimeInterval(30)
        sleepHarness.engine.suspensionDidEnd(at: sleepHarness.clock.now)
        XCTAssertEqual(sleepHarness.engine.guideElapsedSeconds, 20)
        XCTAssertEqual(sleepHarness.engine.accumulatedEligibleSeconds, 20)
        XCTAssertEqual(
            sleepHarness.presenter.guideDeadlines,
            [
                sleptAt.addingTimeInterval(40),
                sleepHarness.clock.now.addingTimeInterval(40)
            ]
        )

        let lockHarness = makeHarness()
        defer { lockHarness.cleanup() }
        lockHarness.start()
        lockHarness.engine.startActivity()
        lockHarness.advance(by: 20)
        XCTAssertEqual(lockHarness.engine.accumulatedEligibleSeconds, 20)
        let lockedAt = lockHarness.clock.now
        lockHarness.engine.sessionDidBecomeInactive(at: lockedAt)
        lockHarness.clock.now = lockedAt.addingTimeInterval(30)
        lockHarness.engine.suspensionDidEnd(at: lockHarness.clock.now)
        XCTAssertEqual(lockHarness.engine.guideElapsedSeconds, 50)
        XCTAssertEqual(lockHarness.engine.accumulatedEligibleSeconds, 20)
        XCTAssertEqual(
            lockHarness.presenter.guideDeadlines,
            [lockedAt.addingTimeInterval(40)]
        )
    }

    func testLongSleepCancelsGuideAndDoesNotScore() {
        let harness = makeHarness()
        defer { harness.cleanup() }
        harness.start()
        harness.engine.startActivity()
        harness.advance(by: 20)
        let sleptAt = harness.clock.now

        harness.engine.systemWillSleep(at: sleptAt)
        harness.clock.now = sleptAt.addingTimeInterval(10 * 60)
        harness.engine.suspensionDidEnd(at: harness.clock.now)

        XCTAssertNotEqual(harness.engine.phase, .guiding)
        XCTAssertEqual(harness.statsStore.today.dailyGoalActivityCount, 0)
        XCTAssertEqual(harness.engine.remainingInterval, 5 * 60)
    }

    func testProactiveGuideCrossingWorkScheduleEndUsesScheduleReset() throws {
        let base = try XCTUnwrap(
            Calendar.current.date(
                byAdding: .second,
                value: 30,
                to: makeLocalDate(hour: 17, minute: 59)
            )
        )
        let harness = makeHarness(date: base) { settings in
            settings.intervalMinutes = 45
            settings.workStartMinutes = 9 * 60
            settings.workEndMinutes = 18 * 60
        }
        defer { harness.cleanup() }
        harness.start()

        harness.engine.startActivity()
        harness.advance(by: ReminderTiming.guidedActivityDuration)

        XCTAssertEqual(harness.statsStore.today.qualifiedProactiveCount, 1)
        XCTAssertEqual(harness.engine.accumulatedEligibleSeconds, 0)
        XCTAssertEqual(harness.engine.phase, .outsideSchedule)
        XCTAssertEqual(
            harness.engine.celebrationText,
            ActivityGuideCompletionOutcome.proactiveFollowingSchedule.celebrationText
        )
        XCTAssertEqual(
            harness.presenter.completionMessages,
            [ActivityGuideCompletionOutcome.proactiveFollowingSchedule.celebrationText]
        )
    }

    func testProactiveGuideNearScheduleEndUsesActualReminderDateForProtection() throws {
        let base = try makeLocalDate(hour: 17, minute: 13)
        let harness = makeHarness(date: base) { settings in
            settings.intervalMinutes = 45
            settings.workStartMinutes = 9 * 60
            settings.workEndMinutes = 18 * 60
        }
        defer { harness.cleanup() }
        harness.start()
        harness.advance(by: 40 * 60)
        let originalReminderAt = try XCTUnwrap(harness.engine.nextReminderAt)
        XCTAssertGreaterThan(
            originalReminderAt.timeIntervalSince(harness.clock.now),
            ReminderTiming.proactiveReminderProtectionWindow
        )

        harness.engine.startActivity()
        harness.advance(by: ReminderTiming.guidedActivityDuration)

        XCTAssertEqual(harness.engine.accumulatedEligibleSeconds, 41 * 60)
        XCTAssertEqual(harness.engine.nextReminderAt, originalReminderAt)
        XCTAssertEqual(
            harness.engine.celebrationText,
            ActivityGuideCompletionOutcome.proactivePreservingCadence.celebrationText
        )
    }

    func testScheduleSettingChangeDuringProactiveGuideCancelsGuideAndResetsCadence() {
        let harness = makeHarness { $0.intervalMinutes = 45 }
        defer { harness.cleanup() }
        harness.start()
        harness.advance(by: 5 * 60)
        harness.engine.startActivity()
        harness.advance(by: 20)

        harness.settingsStore.update { $0.intervalMinutes = 60 }

        XCTAssertNotEqual(harness.engine.phase, .guiding)
        XCTAssertEqual(harness.statsStore.today.dailyGoalActivityCount, 0)
        XCTAssertEqual(harness.engine.accumulatedEligibleSeconds, 0)
        XCTAssertEqual(harness.engine.remainingInterval, 60 * 60)
    }

    func testDateChangeDuringProactiveGuideCancelsGuideWithoutScoring() throws {
        let base = try XCTUnwrap(
            Calendar.current.date(
                byAdding: .second,
                value: 30,
                to: makeLocalDate(hour: 23, minute: 59)
            )
        )
        let harness = makeHarness(date: base) { $0.intervalMinutes = 45 }
        defer { harness.cleanup() }
        harness.start()
        harness.engine.startActivity()

        harness.advance(by: ReminderTiming.guidedActivityDuration)

        XCTAssertNotEqual(harness.engine.phase, .guiding)
        XCTAssertEqual(harness.statsStore.today.dailyGoalActivityCount, 0)
        XCTAssertEqual(harness.engine.accumulatedEligibleSeconds, 0)
    }

    func testRestartRestoresAccumulatorButDoesNotCountOfflineTime() {
        let defaults = makeDefaults()
        let directory = temporaryDirectory()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let first = makeHarness(storageDirectory: directory, defaults: defaults, date: start)
        first.start()
        first.advance(by: 4 * 60)
        XCTAssertEqual(first.engine.accumulatedEligibleSeconds, 4 * 60)

        let restartDate = first.clock.now.addingTimeInterval(60 * 60)
        let restarted = makeHarness(storageDirectory: directory, defaults: defaults, date: restartDate)
        restarted.start()

        XCTAssertEqual(restarted.engine.accumulatedEligibleSeconds, 4 * 60)
        XCTAssertEqual(restarted.engine.remainingInterval, 60)
        restarted.cleanup()
    }

    func testRestartCancelsInProgressGuideWithoutScoring() throws {
        let defaults = makeDefaults()
        let directory = temporaryDirectory()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let first = makeHarness(storageDirectory: directory, defaults: defaults, date: start)
        try first.triggerReminder()
        first.engine.startActivity()
        first.advance(by: 20)

        let restarted = makeHarness(
            storageDirectory: directory,
            defaults: defaults,
            date: first.clock.now.addingTimeInterval(2)
        )
        restarted.start()

        XCTAssertNotEqual(restarted.engine.phase, .guiding)
        XCTAssertEqual(restarted.statsStore.today.dailyGoalActivityCount, 0)
        XCTAssertEqual(restarted.statsStore.today.reminderCompletedCount, 0)
        XCTAssertEqual(restarted.engine.accumulatedEligibleSeconds, 5 * 60)
        restarted.cleanup()
    }

    func testRestartDuringProactiveGuideRestoresAdvancedCadenceWithoutScoringOfflineTime() {
        let defaults = makeDefaults()
        let directory = temporaryDirectory()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let first = makeHarness(
            storageDirectory: directory,
            defaults: defaults,
            date: start
        ) { $0.intervalMinutes = 45 }
        first.start()
        first.advance(by: 5 * 60)
        first.engine.startActivity()
        first.advance(by: 30)

        let restarted = makeHarness(
            storageDirectory: directory,
            defaults: defaults,
            date: first.clock.now.addingTimeInterval(2)
        ) { $0.intervalMinutes = 45 }
        restarted.start()

        XCTAssertNotEqual(restarted.engine.phase, .guiding)
        XCTAssertEqual(restarted.statsStore.today.dailyGoalActivityCount, 0)
        XCTAssertEqual(restarted.engine.accumulatedEligibleSeconds, 5 * 60 + 30)
        XCTAssertEqual(restarted.engine.remainingInterval, 39 * 60 + 30)
        restarted.cleanup()
    }

    func testLegacyPendingCycleGetsOnlyItsRemainingResponseWindow() throws {
        let defaults = makeDefaults()
        let directory = temporaryDirectory()
        let triggeredAt = Date(timeIntervalSince1970: 1_800_000_000)
        let first = makeHarness(storageDirectory: directory, defaults: defaults, date: triggeredAt)
        let cycleID = UUID()
        XCTAssertTrue(first.statsStore.beginReminderCycle(id: cycleID, at: triggeredAt))

        let restartedAt = triggeredAt.addingTimeInterval(5 * 60)
        let restarted = makeHarness(storageDirectory: directory, defaults: defaults, date: restartedAt)
        restarted.start()

        XCTAssertEqual(restarted.engine.activeReminderCycle?.id, cycleID)
        XCTAssertEqual(
            restarted.engine.activeReminderCycle?.responseDeadline,
            triggeredAt.addingTimeInterval(ReminderTiming.responseWindow)
        )
        restarted.cleanup()
    }

    func testDailyTargetUpdateChangesTodaySnapshotWithoutStoppingCadence() {
        let harness = makeHarness()
        defer { harness.cleanup() }
        harness.start()

        harness.settingsStore.update { $0.dailyTarget = 12 }

        XCTAssertEqual(harness.statsStore.today.dailyTargetSnapshot, 12)
        XCTAssertEqual(harness.engine.phase, .accumulating)
    }

    func testNearEndOfScheduleDoesNotCreateOpportunityWithoutFullResponseWindow() throws {
        let base = try makeLocalDate(hour: 17, minute: 54)
        let harness = makeHarness(date: base) { settings in
            settings.intervalMinutes = 5
            settings.workStartMinutes = 9 * 60
            settings.workEndMinutes = 18 * 60
        }
        defer { harness.cleanup() }
        harness.start()
        harness.advance(by: 5 * 60)

        XCTAssertEqual(harness.statsStore.today.reminderOpportunityCount, 0)
        XCTAssertEqual(harness.presenter.presentedCount, 0)
    }

    func testDSTWorkBoundariesUseWallClockTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        var settings = AppSettings()
        settings.workdaysOnly = false
        settings.workStartMinutes = 9 * 60
        settings.workEndMinutes = 18 * 60
        settings.lunchPauseEnabled = false

        for (month, day) in [(3, 8), (11, 1)] {
            let before = try XCTUnwrap(calendar.date(from: DateComponents(
                year: 2026, month: month, day: day, hour: 8, minute: 30
            )))
            let start = try XCTUnwrap(SchedulePolicy.nextAllowedDate(
                onOrAfter: before,
                settings: settings,
                calendar: calendar
            ))
            XCTAssertEqual(calendar.component(.hour, from: start), 9)
            XCTAssertEqual(calendar.component(.minute, from: start), 0)
        }
    }

    private func makeHarness(
        storageDirectory: URL? = nil,
        defaults: UserDefaults? = nil,
        date: Date = Date(timeIntervalSince1970: 1_800_000_000),
        notificationManager: StubNotificationManager? = nil,
        configure: (inout AppSettings) -> Void = { _ in }
    ) -> Harness {
        let directory = storageDirectory ?? temporaryDirectory()
        let defaults = defaults ?? makeDefaults()
        let clock = TestClock(now: date)
        let settingsStore = SettingsStore(defaults: defaults)
        settingsStore.update { settings in
            settings.workdaysOnly = false
            settings.workStartMinutes = 0
            settings.workEndMinutes = 24 * 60
            settings.lunchPauseEnabled = false
            settings.intervalMinutes = 5
            settings.popupEnabled = true
            settings.notificationsEnabled = false
            configure(&settings)
        }
        let statsStore = StatsStore(
            defaults: defaults,
            historyStorageDirectory: directory,
            date: date
        )
        let notifier = notificationManager ?? StubNotificationManager()
        let presenter = StubReminderPresenter()
        let sessionStore = ReminderSessionStateStore(defaults: defaults)
        let engine = ReminderEngine(
            settingsStore: settingsStore,
            statsStore: statsStore,
            notificationManager: notifier,
            reminderPresenter: presenter,
            widgetSyncController: WidgetSyncController(
                storageDirectory: directory,
                reloadTimelines: false
            ),
            sessionStateStore: sessionStore,
            nowProvider: { clock.now }
        )
        return Harness(
            storageDirectory: directory,
            clock: clock,
            settingsStore: settingsStore,
            statsStore: statsStore,
            engine: engine,
            notificationManager: notifier,
            presenter: presenter
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SitRightReminderEngineTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeDefaults() -> UserDefaults {
        let name = "SitRightReminderEngineTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func makeLocalDate(
        year: Int = 2026,
        month: Int = 7,
        day: Int = 1,
        hour: Int,
        minute: Int
    ) throws -> Date {
        try XCTUnwrap(Calendar.current.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )))
    }

    private final class TestClock {
        var now: Date
        init(now: Date) { self.now = now }
    }

    private final class StubNotificationManager: ReminderNotificationManaging {
        private(set) var deliveredCount = 0
        private(set) var cancelledCycleIDs: [UUID] = []
        private var results: [Bool]
        private var actionHandler: ((ReminderNotificationAction) -> Void)?

        init(results: [Bool] = []) {
            self.results = results
        }

        func requestAuthorizationIfNeeded() {}

        func deliverReminder(
            body: String,
            soundEnabled: Bool,
            completion: @escaping (Bool) -> Void
        ) {
            deliverReminder(
                cycleID: UUID(),
                body: body,
                soundEnabled: soundEnabled,
                completion: completion
            )
        }

        func deliverReminder(
            cycleID: UUID,
            body: String,
            soundEnabled: Bool,
            completion: @escaping (Bool) -> Void
        ) {
            deliveredCount += 1
            completion(results.isEmpty ? true : results.removeFirst())
        }

        func cancelReminder(cycleID: UUID) {
            cancelledCycleIDs.append(cycleID)
        }

        func setReminderActionHandler(_ handler: @escaping (ReminderNotificationAction) -> Void) {
            actionHandler = handler
        }

        func send(_ action: ReminderNotificationAction) {
            actionHandler?(action)
        }
    }

    private final class StubReminderPresenter: ReminderPresenting {
        private(set) var presentedCount = 0
        private(set) var dismissedCount = 0
        private(set) var completionMessages: [String] = []
        private(set) var guideDeadlines: [Date] = []
        private var handler: ((ReminderAction) -> Void)?

        func present(message: String, completion: @escaping (ReminderAction) -> Void) {
            presentedCount += 1
            handler = completion
        }

        func presentGuide(endsAt: Date, completion: @escaping (ReminderAction) -> Void) {
            presentedCount += 1
            guideDeadlines.append(endsAt)
            handler = completion
        }

        func updateGuide(endsAt: Date) {
            guideDeadlines.append(endsAt)
        }

        func dismiss() {
            dismissedCount += 1
        }

        func presentGuideCompletion(message: String) {
            completionMessages.append(message)
        }

        func send(_ action: ReminderAction) {
            handler?(action)
        }
    }

    @MainActor
    private struct Harness {
        let storageDirectory: URL
        let clock: TestClock
        let settingsStore: SettingsStore
        let statsStore: StatsStore
        let engine: ReminderEngine
        let notificationManager: StubNotificationManager
        let presenter: StubReminderPresenter

        func start() {
            engine.start(at: clock.now, schedulesTimer: false)
        }

        func advance(by interval: TimeInterval) {
            move(to: clock.now.addingTimeInterval(interval))
        }

        func move(to date: Date) {
            clock.now = date
            engine.tick()
        }

        func triggerReminder() throws {
            start()
            let due = try XCTUnwrap(engine.nextReminderAt)
            move(to: due)
        }

        func cleanup() {
            try? FileManager.default.removeItem(at: storageDirectory)
        }
    }
}
