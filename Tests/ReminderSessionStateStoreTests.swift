import XCTest
@testable import SitRight

@MainActor
final class ReminderSessionStateStoreTests: XCTestCase {
    func testIndefinitePauseRoundTripsAndCanBeCleared() {
        let harness = makeHarness()

        harness.store.save(.indefinite)
        XCTAssertEqual(harness.store.load(), .indefinite)

        harness.store.clear()
        XCTAssertEqual(harness.store.load(), .none)
    }

    func testFutureTimedPauseRoundTrips() {
        let harness = makeHarness()
        let now = Date(timeIntervalSince1970: 1_000)
        let pauseUntil = now.addingTimeInterval(300)

        harness.store.save(.until(pauseUntil))

        XCTAssertEqual(harness.store.load(at: now), .until(pauseUntil))
    }

    func testExpiredTimedPauseIsReturnedAsNoneAndRemoved() {
        let harness = makeHarness()
        let now = Date(timeIntervalSince1970: 1_000)

        harness.store.save(.until(now))

        XCTAssertEqual(harness.store.load(at: now), .none)
        XCTAssertNil(harness.defaults.data(forKey: "sitright.reminderSession.v1"))
    }

    func testMalformedPersistedPauseFallsBackToNone() {
        let harness = makeHarness()
        harness.defaults.set(Data("not-json".utf8), forKey: "sitright.reminderSession.v1")

        XCTAssertEqual(harness.store.load(), .none)
    }

    func testSuspensionRoundTripsAlongsideCheckpoint() {
        let harness = makeHarness()
        let startedAt = Date(timeIntervalSince1970: 1_000)

        harness.store.saveCheckpoint(.init(
            accumulatedEligibleSeconds: 49 * 60,
            opportunityCooldownSeconds: 0
        ))
        harness.store.saveSuspension(startedAt: startedAt, isSleep: true)

        XCTAssertEqual(
            harness.store.loadSuspension(),
            ReminderSuspensionState(startedAt: startedAt, isSleep: true)
        )
        XCTAssertEqual(harness.store.loadCheckpoint().accumulatedEligibleSeconds, 49 * 60)

        harness.store.clearSuspension()
        XCTAssertNil(harness.store.loadSuspension())
        XCTAssertEqual(harness.store.loadCheckpoint().accumulatedEligibleSeconds, 49 * 60)
    }

    private func makeHarness() -> (store: ReminderSessionStateStore, defaults: UserDefaults) {
        let suiteName = "SitRightReminderSessionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (ReminderSessionStateStore(defaults: defaults), defaults)
    }
}
