import XCTest
@testable import SitRight

final class TimeFormattingTests: XCTestCase {
    func testMenuBarCountdownUsesSecondsBelowOneHour() {
        XCTAssertEqual(TimeFormatting.menuBarCountdown(275), "04:35")
        XCTAssertEqual(TimeFormatting.menuBarCountdown(59), "00:59")
        XCTAssertEqual(TimeFormatting.menuBarCountdown(0), "00:00")
    }

    func testMenuBarCountdownUsesHoursAboveOneHour() {
        XCTAssertEqual(TimeFormatting.menuBarCountdown(3_905), "1:05:05")
    }

    func testMenuBarTitleLayoutUsesMinuteTemplateBelowOneHour() {
        XCTAssertEqual(
            MenuBarTitleLayout.measurementText(for: .running, remainingInterval: 59),
            "88:88"
        )
        XCTAssertEqual(
            MenuBarTitleLayout.measurementText(for: .running, remainingInterval: 3_599),
            "88:88"
        )
    }

    func testMenuBarTitleLayoutUsesHourTemplateAboveOneHour() {
        XCTAssertEqual(
            MenuBarTitleLayout.measurementText(for: .running, remainingInterval: 3_600),
            "8:88:88"
        )
        XCTAssertEqual(
            MenuBarTitleLayout.measurementText(for: .running, remainingInterval: 36_000),
            "88:88:88"
        )
    }

    func testMenuBarTitleLayoutUsesStatusTemplatesOutsideCountdown() {
        XCTAssertEqual(MenuBarTitleLayout.measurementText(for: .due, remainingInterval: 0), "Move")
        XCTAssertEqual(MenuBarTitleLayout.measurementText(for: .paused(until: nil), remainingInterval: 0), "Paused")
        XCTAssertEqual(MenuBarTitleLayout.measurementText(for: .outsideHours, remainingInterval: 0), "Rest")
        XCTAssertEqual(MenuBarTitleLayout.measurementText(for: .disabled, remainingInterval: 0), "Off")
    }

    func testMenuBarTitleLayoutUsesFixedWidthsByDisplayFormat() {
        XCTAssertEqual(MenuBarTitleLayout.fixedWidth(for: .running, remainingInterval: 59), 44)
        XCTAssertEqual(MenuBarTitleLayout.fixedWidth(for: .running, remainingInterval: 3_599), 44)
        XCTAssertEqual(MenuBarTitleLayout.fixedWidth(for: .running, remainingInterval: 3_600), 62)
        XCTAssertEqual(MenuBarTitleLayout.fixedWidth(for: .running, remainingInterval: 36_000), 70)
        XCTAssertEqual(MenuBarTitleLayout.fixedWidth(for: .paused(until: nil), remainingInterval: 0), 52)
        XCTAssertEqual(MenuBarTitleLayout.fixedWidth(for: .due, remainingInterval: 0), 36)
        XCTAssertEqual(MenuBarTitleLayout.fixedWidth(for: .outsideHours, remainingInterval: 0), 36)
        XCTAssertEqual(MenuBarTitleLayout.fixedWidth(for: .disabled, remainingInterval: 0), 28)
    }
}
