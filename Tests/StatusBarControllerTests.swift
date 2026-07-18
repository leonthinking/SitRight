import AppKit
import Combine
import SwiftUI
import XCTest
@testable import SitRight

final class StatusBarControllerTests: XCTestCase {
    func testPopoverSizingDisablesAutomaticPreferredContentSizing() {
        XCTAssertEqual(StatusBarPopoverSizingPolicy.hostingSizingOptions, [])
    }

    func testPopoverSizingUsesFixedWidthAndClampsMeasuredHeight() {
        XCTAssertEqual(
            StatusBarPopoverSizingPolicy.normalized(NSSize(width: 120, height: 622.2)),
            NSSize(width: 370, height: 623)
        )
        XCTAssertEqual(
            StatusBarPopoverSizingPolicy.normalized(NSSize(width: 800, height: 1_200)),
            NSSize(width: 370, height: 900)
        )
        XCTAssertEqual(
            StatusBarPopoverSizingPolicy.normalized(NSSize(width: 0, height: 0)),
            NSSize(width: 370, height: 1)
        )
    }

    func testPopoverMeasurementTriggersExcludeOrdinaryEngineTicks() {
        XCTAssertTrue(StatusBarPopoverSizingPolicy.requestsMeasurement(for: .initialization))
        XCTAssertTrue(StatusBarPopoverSizingPolicy.requestsMeasurement(for: .opening))
        XCTAssertTrue(StatusBarPopoverSizingPolicy.requestsMeasurement(for: .tabChange))
        XCTAssertFalse(StatusBarPopoverSizingPolicy.requestsMeasurement(for: .engineTick))
    }

    func testUpdateGateCoalescesUntilCompleted() {
        var gate = UpdateCoalescingGate()

        XCTAssertTrue(gate.schedule())
        XCTAssertTrue(gate.isScheduled)
        XCTAssertFalse(gate.schedule())

        gate.complete()

        XCTAssertFalse(gate.isScheduled)
        XCTAssertTrue(gate.schedule())
    }

    @MainActor
    func testMenuPanelEngineUpdatesAreForwardedOnlyWhilePopoverIsActive() {
        let controller = MenuPanelRefreshController()
        var updateCount = 0
        let cancellable = controller.objectWillChange.sink {
            updateCount += 1
        }

        controller.engineDidChange()
        XCTAssertEqual(updateCount, 0)

        controller.setActive(true)
        XCTAssertEqual(updateCount, 1)
        XCTAssertTrue(controller.isActive)

        controller.engineDidChange()
        XCTAssertEqual(updateCount, 2)

        controller.setActive(false)
        controller.engineDidChange()
        XCTAssertEqual(updateCount, 2)
        XCTAssertFalse(controller.isActive)

        withExtendedLifetime(cancellable) {}
    }
}
