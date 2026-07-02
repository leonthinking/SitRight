import XCTest
@testable import SitRight

final class WidgetSnapshotTests: XCTestCase {
    func testAllowsWidgetCompletionOnlyWhenDue() {
        XCTAssertTrue(snapshot(state: .due).allowsWidgetCompletion)
        XCTAssertFalse(snapshot(state: .running).allowsWidgetCompletion)
        XCTAssertFalse(snapshot(state: .paused).allowsWidgetCompletion)
        XCTAssertFalse(snapshot(state: .outsideHours).allowsWidgetCompletion)
        XCTAssertFalse(snapshot(state: .disabled).allowsWidgetCompletion)
    }

    func testEmptySnapshotDoesNotAllowWidgetCompletion() {
        XCTAssertFalse(WidgetSnapshot.empty.allowsWidgetCompletion)
    }

    private func snapshot(state: WidgetSnapshot.RunState) -> WidgetSnapshot {
        WidgetSnapshot(
            updatedAt: Date(timeIntervalSince1970: 0),
            nextReminderAt: nil,
            intervalMinutes: 45,
            state: state,
            statusText: "",
            completedCount: 0,
            dailyTarget: 8,
            dateKey: "2026-07-02"
        )
    }
}
