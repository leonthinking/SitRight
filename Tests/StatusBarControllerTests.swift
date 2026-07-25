import AppKit
import Combine
import SwiftUI
import XCTest
@testable import SitRight

final class StatusBarControllerTests: XCTestCase {
    func testMenuPopoverClosesOnlyWhenActivityGuideBegins() {
        for phase in [
            ReminderPhase.accumulating,
            .delivering,
            .awaitingResponse,
            .snoozed,
            .overdue,
            .paused,
            .outsideSchedule,
            .disabled
        ] {
            XCTAssertFalse(MenuPopoverVisibilityPolicy.shouldClose(for: phase))
        }

        XCTAssertTrue(MenuPopoverVisibilityPolicy.shouldClose(for: .guiding))
    }

    func testGuideWaitsThroughPopoverClosingLifecycle() {
        XCTAssertFalse(
            MenuPopoverVisibilityPolicy.shouldWaitForClose(
                for: .guiding,
                popoverLifecycleIsActive: false
            )
        )
        XCTAssertTrue(
            MenuPopoverVisibilityPolicy.shouldWaitForClose(
                for: .guiding,
                popoverLifecycleIsActive: true
            )
        )
        XCTAssertFalse(
            MenuPopoverVisibilityPolicy.shouldWaitForClose(
                for: .accumulating,
                popoverLifecycleIsActive: true
            )
        )
    }

    @MainActor
    func testGuidePresentationWaitsUntilPopoverDidClose() {
        let gate = GuidePresentationGate()
        var events: [String] = []

        gate.waitForPopoverToClose()
        gate.submit {
            events.append("guidePresented")
        }

        XCTAssertTrue(events.isEmpty)
        events.append("popoverDidClose")
        gate.popoverDidClose()
        XCTAssertEqual(events, ["popoverDidClose", "guidePresented"])
    }

    @MainActor
    func testGuidePresentationStillRunsWhenPopoverClosedSynchronously() {
        let gate = GuidePresentationGate()
        var presentationCount = 0

        gate.waitForPopoverToClose()
        gate.popoverDidClose()
        gate.submit {
            presentationCount += 1
        }

        XCTAssertEqual(presentationCount, 1)
    }

    @MainActor
    func testDismissCancelsDeferredGuidePresentation() {
        let gate = GuidePresentationGate()
        var presentationCount = 0

        gate.waitForPopoverToClose()
        gate.submit {
            presentationCount += 1
        }
        gate.cancel()
        gate.popoverDidClose()

        XCTAssertEqual(presentationCount, 0)
    }

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
        XCTAssertEqual(
            StatusBarPopoverSizingPolicy.normalized(
                NSSize(width: 370, height: 800),
                maximumHeight: 600
            ),
            NSSize(width: 370, height: 600)
        )
    }

    func testPopoverSizingRespectsVisibleScreenHeight() {
        XCTAssertEqual(StatusBarPopoverSizingPolicy.maximumHeight(for: nil), 900)
        XCTAssertEqual(
            StatusBarPopoverSizingPolicy.maximumHeight(
                for: NSRect(x: 0, y: 0, width: 1_200, height: 700)
            ),
            676
        )
        XCTAssertEqual(
            StatusBarPopoverSizingPolicy.maximumHeight(
                for: NSRect(x: 0, y: 0, width: 1_200, height: 1_200)
            ),
            900
        )
        XCTAssertEqual(
            StatusBarPopoverSizingPolicy.fittingConstraint(maximumHeight: 676),
            NSSize(width: 370, height: 676)
        )
    }

    func testPopoverMeasurementTriggersExcludeOrdinaryEngineTicks() {
        XCTAssertTrue(StatusBarPopoverSizingPolicy.requestsMeasurement(for: .initialization))
        XCTAssertTrue(StatusBarPopoverSizingPolicy.requestsMeasurement(for: .opening))
        XCTAssertTrue(StatusBarPopoverSizingPolicy.requestsMeasurement(for: .layoutChange))
        XCTAssertFalse(StatusBarPopoverSizingPolicy.requestsMeasurement(for: .engineTick))
    }

    func testPopoverLayoutSignatureTracksOnlyDiscreteLayoutChanges() {
        let baseline = MenuPanelLayoutSignature(
            actionKind: .running,
            hasCurrentReminder: false,
            hasStatsError: false,
            showsActivityBreakdown: false,
            showsLegacyRecords: false,
            showsResponseRate: false
        )
        let sameLayoutOnNextTick = MenuPanelLayoutSignature(
            actionKind: .running,
            hasCurrentReminder: false,
            hasStatsError: false,
            showsActivityBreakdown: false,
            showsLegacyRecords: false,
            showsResponseRate: false
        )
        let reminderLayout = MenuPanelLayoutSignature(
            actionKind: .awaitingResponse,
            hasCurrentReminder: true,
            hasStatsError: false,
            showsActivityBreakdown: false,
            showsLegacyRecords: false,
            showsResponseRate: true
        )

        XCTAssertEqual(baseline, sameLayoutOnNextTick)
        XCTAssertNotEqual(baseline, reminderLayout)
    }

    func testRepeatedEngineTicksDoNotRequestMeasurementUntilLayoutChanges() {
        let running = MenuPanelLayoutSignature(
            actionKind: .running,
            hasCurrentReminder: false,
            hasStatsError: false,
            showsActivityBreakdown: false,
            showsLegacyRecords: false,
            showsResponseRate: false
        )
        let awaitingResponse = MenuPanelLayoutSignature(
            actionKind: .awaitingResponse,
            hasCurrentReminder: true,
            hasStatsError: false,
            showsActivityBreakdown: false,
            showsLegacyRecords: false,
            showsResponseRate: true
        )
        var state = PopoverLayoutMeasurementState(signature: running)

        for _ in 0..<1_000 {
            XCTAssertFalse(
                state.shouldRequestMeasurement(
                    for: running,
                    whilePopoverIsShown: true
                )
            )
        }

        XCTAssertTrue(
            state.shouldRequestMeasurement(
                for: awaitingResponse,
                whilePopoverIsShown: true
            )
        )
        XCTAssertFalse(
            state.shouldRequestMeasurement(
                for: awaitingResponse,
                whilePopoverIsShown: true
            )
        )
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
