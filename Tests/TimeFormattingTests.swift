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
}
