import XCTest
@testable import SitRight

final class HeatmapPresentationTests: XCTestCase {
    func testRollingRangesContainExactlyRequestedDaysAndEndOnToday() throws {
        let calendar = Self.calendar(firstWeekday: 2)
        let end = try Self.date(2026, 8, 3, calendar: calendar)

        let presentation = HeatmapPresentation(
            history: ActivityHistory(),
            endDate: end,
            dayCount: 90,
            calendar: calendar
        )
        let datedCells = presentation.weeks.flatMap(\.cells).compactMap(\.date)

        XCTAssertEqual(datedCells.count, 90)
        XCTAssertEqual(datedCells.last, end)
        XCTAssertEqual(
            datedCells.first,
            calendar.date(byAdding: .day, value: -89, to: end)
        )
        XCTAssertEqual(
            presentation.weeks.flatMap(\.cells).filter(\.isToday).count,
            1
        )
    }

    func testLeapDayIsIncludedWithoutChangingQuarterDayCount() throws {
        let calendar = Self.calendar(firstWeekday: 2)
        let end = try Self.date(2024, 3, 1, calendar: calendar)
        let presentation = HeatmapPresentation(
            history: ActivityHistory(),
            endDate: end,
            dayCount: 90,
            calendar: calendar
        )
        let dates = presentation.weeks.flatMap(\.cells).compactMap(\.date)

        XCTAssertEqual(dates.count, 90)
        XCTAssertTrue(dates.contains(try Self.date(2024, 2, 29, calendar: calendar)))
    }

    func testWeekAlignmentFollowsCalendarFirstWeekday() throws {
        let monday = try Self.date(2026, 8, 3, calendar: Self.calendar(firstWeekday: 2))
        let mondayFirst = HeatmapPresentation(
            history: ActivityHistory(),
            endDate: monday,
            dayCount: 1,
            calendar: Self.calendar(firstWeekday: 2)
        )
        let sundayFirst = HeatmapPresentation(
            history: ActivityHistory(),
            endDate: monday,
            dayCount: 1,
            calendar: Self.calendar(firstWeekday: 1)
        )

        XCTAssertNotNil(mondayFirst.weeks[0].cells[0].date)
        XCTAssertEqual(sundayFirst.weeks[0].cells[0].state, .padding)
        XCTAssertNotNil(sundayFirst.weeks[0].cells[1].date)
    }

    func testPaddingCellsAreTransparentPresentationState() throws {
        let calendar = Self.calendar(firstWeekday: 2)
        let end = try Self.date(2026, 8, 3, calendar: calendar)
        let presentation = HeatmapPresentation(
            history: ActivityHistory(),
            endDate: end,
            dayCount: 90,
            calendar: calendar
        )
        let padding = presentation.weeks.flatMap(\.cells).filter { $0.date == nil }

        XCTAssertFalse(padding.isEmpty)
        XCTAssertTrue(padding.allSatisfy { $0.state == .padding && !$0.isToday })
    }

    func testMonthMarkersFollowVisibleMonthBoundaries() throws {
        let calendar = Self.calendar(firstWeekday: 2)
        let end = try Self.date(2026, 8, 3, calendar: calendar)
        let presentation = HeatmapPresentation(
            history: ActivityHistory(),
            endDate: end,
            dayCount: 90,
            calendar: calendar
        )

        XCTAssertEqual(presentation.monthMarkers.count, 4)
        XCTAssertEqual(presentation.monthMarkers.map(\.columnIndex), [0, 4, 8, 12])
        XCTAssertTrue(presentation.monthMarkers.allSatisfy { !$0.title.isEmpty })

        let placements = HeatmapPresentation.monthLabelPlacements(
            for: presentation.monthMarkers,
            originX: 0,
            step: 40,
            availableWidth: 520,
            labelWidth: 24
        )
        XCTAssertTrue(placements.allSatisfy { $0.xOffset >= 0 && $0.xOffset + 24 <= 520 })
        for (current, next) in zip(placements, placements.dropFirst()) {
            XCTAssertGreaterThanOrEqual(next.xOffset - current.xOffset, 24)
        }
    }

    func testMonthMarkersRemainOrderedAcrossYearBoundary() throws {
        let calendar = Self.calendar(firstWeekday: 2)
        let end = try Self.date(2026, 2, 15, calendar: calendar)
        let presentation = HeatmapPresentation(
            history: ActivityHistory(),
            endDate: end,
            dayCount: 90,
            calendar: calendar
        )

        XCTAssertEqual(presentation.monthMarkers.count, 4)
        XCTAssertEqual(presentation.monthMarkers.first?.columnIndex, 0)
        XCTAssertEqual(
            presentation.monthMarkers.map(\.columnIndex),
            presentation.monthMarkers.map(\.columnIndex).sorted()
        )
        XCTAssertTrue(presentation.monthMarkers.allSatisfy { !$0.title.isEmpty })
    }

    func testQuarterDropsTinyLeadingMonthWhenNextMonthSharesItsWeekColumn() throws {
        let calendar = Self.calendar(firstWeekday: 2)
        let presentation = HeatmapPresentation(
            history: ActivityHistory(),
            endDate: try Self.date(2025, 8, 28, calendar: calendar),
            dayCount: 90,
            calendar: calendar
        )

        XCTAssertEqual(presentation.monthMarkers.count, 3)
        XCTAssertEqual(presentation.monthMarkers.map(\.columnIndex), [0, 5, 9])
        XCTAssertEqual(Set(presentation.monthMarkers.map(\.columnIndex)).count, 3)
    }

    func testRollingDatesRemainUniqueAcrossDaylightSavingTransitions() throws {
        let calendar = Self.calendar(
            firstWeekday: 1,
            timeZoneIdentifier: "America/Los_Angeles"
        )

        for end in [
            try Self.date(2026, 3, 15, calendar: calendar),
            try Self.date(2026, 11, 15, calendar: calendar)
        ] {
            let dayCount = 90
            let dates = HeatmapPresentation(
                history: ActivityHistory(),
                endDate: end,
                dayCount: dayCount,
                calendar: calendar
            ).weeks.flatMap(\.cells).compactMap(\.date)
            let dateKeys = dates.map { ActivityDay.makeDateKey(for: $0, calendar: calendar) }

            XCTAssertEqual(dates.count, dayCount)
            XCTAssertEqual(Set(dateKeys).count, dayCount)
            XCTAssertEqual(dates.last, calendar.startOfDay(for: end))
        }
    }

    func testGoalCompletionIntensityBoundaries() {
        XCTAssertEqual(Self.state(count: 0, target: 100), .inactive)
        XCTAssertEqual(Self.state(count: 24, target: 100), .activity(.low))
        XCTAssertEqual(Self.state(count: 25, target: 100), .activity(.medium))
        XCTAssertEqual(Self.state(count: 49, target: 100), .activity(.medium))
        XCTAssertEqual(Self.state(count: 50, target: 100), .activity(.high))
        XCTAssertEqual(Self.state(count: 99, target: 100), .activity(.high))
        XCTAssertEqual(Self.state(count: 100, target: 100), .activity(.complete))
        XCTAssertEqual(Self.state(count: 125, target: 100), .activity(.complete))
    }

    func testMissingHistoricalTargetUsesConservativeActivityLevel() {
        XCTAssertEqual(Self.state(count: 12, target: nil), .activity(.low))
    }

    func testInactiveNeutralAndActiveNeutralDaysRemainDistinct() {
        var paused = ActivityDay(dateKey: "2026-08-01")
        paused.eligibilitySnapshot = .paused
        XCTAssertEqual(HeatmapPresentation.cellState(for: paused), .neutral)

        var nonWorkday = ActivityDay(dateKey: "2026-08-02")
        nonWorkday.eligibilitySnapshot = .nonWorkday
        XCTAssertEqual(HeatmapPresentation.cellState(for: nonWorkday), .neutral)

        let unknown = ActivityDay(dateKey: "2026-08-03")
        XCTAssertEqual(HeatmapPresentation.cellState(for: unknown), .inactive)

        paused.completedCount = 1
        paused.dailyTargetSnapshot = 1
        XCTAssertEqual(HeatmapPresentation.cellState(for: paused), .activity(.complete))
    }

    func testSummaryCountsActivitiesActiveDaysAndKnownTargetCompletions() throws {
        let calendar = Self.calendar(firstWeekday: 2)
        let end = try Self.date(2026, 8, 3, calendar: calendar)
        var history = ActivityHistory()
        history.upsert(Self.day(dateKey: "2026-08-01", count: 3, target: 8))
        history.upsert(Self.day(dateKey: "2026-08-02", count: 8, target: 8))
        history.upsert(Self.day(dateKey: "2026-08-03", count: 9, target: nil))

        let summary = HeatmapPresentation(
            history: history,
            endDate: end,
            dayCount: 3,
            calendar: calendar
        ).summary

        XCTAssertEqual(summary.activityTotal, 20)
        XCTAssertEqual(summary.activeDays, 3)
        XCTAssertEqual(summary.completedDays, 1)
    }

    private static func state(count: Int, target: Int?) -> HeatmapCellState {
        HeatmapPresentation.cellState(for: day(dateKey: "2026-08-03", count: count, target: target))
    }

    private static func day(dateKey: String, count: Int, target: Int?) -> ActivityDay {
        var day = ActivityDay(dateKey: dateKey)
        day.completedCount = count
        day.dailyTargetSnapshot = target
        day.eligibilitySnapshot = .scheduled
        return day
    }

    private static func calendar(
        firstWeekday: Int,
        timeZoneIdentifier: String = "GMT"
    ) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier)!
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private static func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        calendar: Calendar
    ) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }
}
