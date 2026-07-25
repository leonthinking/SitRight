import AppKit
import SwiftUI
import XCTest
@testable import SitRight

final class MenuPanelPresentationTests: XCTestCase {
    func testSettingsSelectionMapsLegacyScheduleToVisibleGeneralPane() {
        XCTAssertEqual(
            SettingsSelection.visiblePane(for: .general),
            .general
        )
        XCTAssertEqual(
            SettingsSelection.visiblePane(for: .schedule),
            .general
        )
        XCTAssertEqual(
            SettingsSelection.visiblePane(for: .notifications),
            .notifications
        )
        XCTAssertEqual(
            Set(
                [
                    SettingsPane.general,
                    .schedule,
                    .notifications
                ].map(SettingsSelection.visiblePane(for:))
            ),
            Set([.general, .notifications])
        )
    }

    func testScheduleSettingsRouteKeepsSectionIntentSeparateFromVisiblePane() {
        XCTAssertEqual(
            SettingsSelection.route(for: .general),
            SettingsRoute(visiblePane: .general, requestedSection: nil)
        )
        XCTAssertEqual(
            SettingsSelection.route(for: .schedule),
            SettingsRoute(
                visiblePane: .general,
                requestedSection: .workSchedule
            )
        )
        XCTAssertEqual(
            SettingsSelection.route(for: .notifications),
            SettingsRoute(visiblePane: .notifications, requestedSection: nil)
        )
    }

    func testSettingsSectionRequestIsConsumedExactlyOnce() {
        var request = SettingsSectionRequestState(
            rawValue: SettingsSectionDestination.workSchedule.rawValue
        )

        XCTAssertEqual(request.consume(), .workSchedule)
        XCTAssertEqual(request.rawValue, "")
        XCTAssertNil(request.consume())
    }

    func testReminderPopupUsesPlatformActionOrderForRowsAndStacks() {
        XCTAssertEqual(
            ReminderPopupActionLayout.actions(for: .horizontal),
            [.pausedToday, .snoozed, .completed]
        )
        XCTAssertEqual(
            ReminderPopupActionLayout.actions(for: .vertical),
            [.completed, .snoozed, .pausedToday]
        )
    }

    func testReminderPanelSizingIsControlledAndIgnoresCountdownTicks() {
        XCTAssertEqual(ReminderPanelSizingPolicy.hostingSizingOptions, [])
        XCTAssertTrue(
            ReminderPanelSizingPolicy.requestsMeasurement(for: .presentation)
        )
        XCTAssertFalse(
            ReminderPanelSizingPolicy.requestsMeasurement(for: .countdownTick)
        )
        XCTAssertEqual(
            ReminderPanelSizingPolicy.maximumHeight(for: nil),
            720
        )
        XCTAssertEqual(
            ReminderPanelSizingPolicy.maximumHeight(
                for: NSRect(x: 0, y: 0, width: 1_200, height: 600)
            ),
            552
        )
        XCTAssertEqual(
            ReminderPanelSizingPolicy.fittingConstraint(maximumHeight: 552),
            NSSize(width: 420, height: 552)
        )
        XCTAssertEqual(
            ReminderPanelSizingPolicy.normalized(
                NSSize(width: 300, height: 250),
                maximumHeight: 552
            ),
            NSSize(width: 420, height: 300)
        )
        XCTAssertEqual(
            ReminderPanelSizingPolicy.normalized(
                NSSize(width: 500, height: 800),
                maximumHeight: 552
            ),
            NSSize(width: 420, height: 552)
        )
        XCTAssertEqual(
            ReminderPanelSizingPolicy.normalized(
                NSSize(width: 420, height: 300),
                maximumHeight: 200
            ),
            NSSize(width: 420, height: 200)
        )
    }

    @MainActor
    func testReminderPopupUsesInternalScrollAtAccessibilitySize() {
        let view = ReminderPopupView(
            message: "按你的身体状况，换个姿势或活动 60 秒。",
            onAction: { _ in }
        )
        .environment(\.dynamicTypeSize, .accessibility5)
        let hostingController = NSHostingController(rootView: view)
        hostingController.sizingOptions = ReminderPanelSizingPolicy.hostingSizingOptions

        let constrainedSize = hostingController.sizeThatFits(
            in: NSSize(width: 420, height: 240)
        )

        XCTAssertEqual(constrainedSize.width, 420)
        XCTAssertLessThanOrEqual(constrainedSize.height, 240)
    }

    func testTimePickerOptionsPreserveLegacyNonStepSelection() {
        let options = TimePickerOptions.values(
            in: 0...(23 * 60),
            step: 30,
            including: 9 * 60 + 15
        )

        XCTAssertTrue(options.contains(9 * 60 + 15))
        XCTAssertTrue(options.contains(0))
        XCTAssertTrue(options.contains(23 * 60))
        XCTAssertEqual(options, Array(Set(options)).sorted())
        XCTAssertFalse(
            TimePickerOptions.values(
                in: 60...120,
                step: 30,
                including: 30
            ).contains(30)
        )
    }

    func testActionModeUsesContextualRunningAndReminderActions() {
        XCTAssertEqual(
            TodayActionMode.resolve(
                phase: .accumulating,
                state: .running,
                canRecordManualActivity: true,
                canSnooze: false,
                snoozedStatusText: ""
            ),
            .running(canRecordManualActivity: true)
        )
        XCTAssertEqual(
            TodayActionMode.resolve(
                phase: .awaitingResponse,
                state: .due,
                canRecordManualActivity: false,
                canSnooze: true,
                snoozedStatusText: ""
            ),
            .awaitingResponse(canSnooze: true)
        )
    }

    func testActionModeUsesExplicitSnoozedAndGuidingStates() {
        XCTAssertEqual(
            TodayActionMode.resolve(
                phase: .snoozed,
                state: .running,
                canRecordManualActivity: false,
                canSnooze: false,
                snoozedStatusText: "已延后 04:59"
            ),
            .snoozed(statusText: "已延后 04:59")
        )
        XCTAssertEqual(
            TodayActionMode.resolve(
                phase: .guiding,
                state: .due,
                canRecordManualActivity: false,
                canSnooze: false,
                snoozedStatusText: ""
            ),
            .guiding
        )
    }

    func testRunStateOverridesTransientPhaseForUnavailableActions() {
        XCTAssertEqual(
            TodayActionMode.resolve(
                phase: .awaitingResponse,
                state: .paused(until: nil),
                canRecordManualActivity: false,
                canSnooze: true,
                snoozedStatusText: ""
            ),
            .paused
        )
        XCTAssertEqual(
            TodayActionMode.resolve(
                phase: .accumulating,
                state: .outsideHours,
                canRecordManualActivity: false,
                canSnooze: false,
                snoozedStatusText: ""
            ),
            .outsideHours
        )
        XCTAssertEqual(
            TodayActionMode.resolve(
                phase: .accumulating,
                state: .disabled,
                canRecordManualActivity: false,
                canSnooze: false,
                snoozedStatusText: ""
            ),
            .disabled
        )
    }

    func testIntervalChoiceRecognizesPresetsAndCustomValues() {
        XCTAssertEqual(ReminderIntervalChoice.selection(for: 30), .preset(30))
        XCTAssertEqual(ReminderIntervalChoice.selection(for: 45), .preset(45))
        XCTAssertEqual(ReminderIntervalChoice.selection(for: 5), .custom)
        XCTAssertEqual(ReminderIntervalChoice.selection(for: 55), .custom)
        XCTAssertEqual(ReminderIntervalChoice.selection(for: 240), .custom)
        XCTAssertEqual(ReminderIntervalChoice.preset(50).minuteValue, 50)
        XCTAssertNil(ReminderIntervalChoice.custom.minuteValue)
    }

    func testTimerRingTextUsesPhaseSpecificDeadlineLanguage() {
        let deadline = Date(timeIntervalSince1970: 1_700_000_000)
        let timeText = deadline.formatted(date: .omitted, time: .shortened)

        XCTAssertEqual(
            TimerRingPresentationText.subtitle(
                phase: .awaitingResponse,
                nextReminderAt: deadline
            ),
            "请在 \(timeText) 前开始"
        )
        XCTAssertEqual(
            TimerRingPresentationText.subtitle(
                phase: .snoozed,
                nextReminderAt: deadline
            ),
            "延后至 \(timeText)"
        )
        XCTAssertEqual(
            TimerRingPresentationText.subtitle(
                phase: .guiding,
                nextReminderAt: deadline
            ),
            "完成后重新计时"
        )
        XCTAssertEqual(
            TimerRingPresentationText.contextLabel(
                phase: .awaitingResponse,
                state: .due
            ),
            "活动提醒"
        )
    }

    func testTimerRingStrokeFitsInsideDeclaredDiameter() {
        for diameter in [
            TimerRingLayout.diameter,
            TimerRingLayout.accessibilityDiameter
        ] {
            let pathDiameter = diameter - (2 * TimerRingLayout.strokeInset)
            let paintedDiameter = pathDiameter + TimerRingLayout.lineWidth

            XCTAssertEqual(
                TimerRingLayout.strokeInset,
                TimerRingLayout.lineWidth / 2
            )
            XCTAssertEqual(paintedDiameter, diameter)
        }
    }

    func testTimerRingPartialArcUsesNonOverlappingLineCap() {
        XCTAssertEqual(TimerRingLayout.partialLineCap, .butt)
    }

    func testTimerRingProgressRemainsAccurateThroughFinalPercent() {
        let checkpoints = [0.0, 0.02, 0.5, 0.98, 0.99]

        for progress in checkpoints {
            XCTAssertEqual(
                TimerRingProgress.resolve(
                    progress: progress,
                    state: .running,
                    phase: .accumulating
                ),
                progress
            )
        }

        XCTAssertEqual(
            TimerRingProgress.resolve(
                progress: 0.99,
                state: .due,
                phase: .awaitingResponse
            ),
            1
        )
        XCTAssertEqual(
            TimerRingProgress.resolve(
                progress: 0.99,
                state: .paused(until: nil),
                phase: .paused
            ),
            0
        )
    }

    func testTimerRingGuidingDueStateUsesLiveActivityProgress() {
        XCTAssertEqual(
            TimerRingProgress.resolve(
                progress: 0,
                state: .due,
                phase: .guiding
            ),
            0
        )
        XCTAssertEqual(
            TimerRingProgress.resolve(
                progress: 0.5,
                state: .due,
                phase: .guiding
            ),
            0.5
        )
        XCTAssertEqual(
            TimerRingProgress.resolve(
                progress: 1,
                state: .due,
                phase: .guiding
            ),
            1
        )
    }

    func testTimerRingAccessibilityLayoutAddsRoomWithoutExceedingPanel() {
        XCTAssertEqual(
            TimerRingLayout.diameter(usesAccessibilityLayout: false),
            168
        )
        XCTAssertEqual(
            TimerRingLayout.diameter(usesAccessibilityLayout: true),
            200
        )
        XCTAssertLessThan(TimerRingLayout.accessibilityDiameter, 370 - 32)
    }

    func testTodayProgressPresentationCollapsesEmptyBreakdown() {
        let empty = TodayProgressPresentation(
            dailyGoalCompleted: 0,
            reminderCompleted: 0,
            target: 12,
            reminderOpportunities: 0,
            responseRate: nil,
            proactiveActivities: 0,
            legacyUnclassified: 0,
            subtitle: "今天还没有完成活动"
        )

        XCTAssertEqual(empty.progress, 0)
        XCTAssertFalse(empty.showsActivityBreakdown)
        XCTAssertNil(empty.responseText)
    }

    func testTodayProgressPresentationKeepsTrustedMetricsSeparate() {
        let progress = TodayProgressPresentation(
            dailyGoalCompleted: 3,
            reminderCompleted: 2,
            target: 12,
            reminderOpportunities: 4,
            responseRate: 0.5,
            proactiveActivities: 1,
            legacyUnclassified: 0,
            subtitle: "上次完成于 10:30"
        )

        XCTAssertEqual(progress.progress, 0.25)
        XCTAssertTrue(progress.showsActivityBreakdown)
        XCTAssertEqual(progress.responseText, "50% · 2/4 次提醒")
    }

    func testTodayProgressPresentationShowsZeroResponseWhenOnlyOpportunityExists() {
        let progress = TodayProgressPresentation(
            dailyGoalCompleted: 0,
            reminderCompleted: 0,
            target: 12,
            reminderOpportunities: 1,
            responseRate: 0,
            proactiveActivities: 0,
            legacyUnclassified: 0,
            subtitle: "今天还没有完成活动"
        )

        XCTAssertTrue(progress.showsActivityBreakdown)
        XCTAssertEqual(progress.responseText, "0% · 0/1 次提醒")
    }
}
