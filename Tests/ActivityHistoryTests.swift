import XCTest
@testable import SitRight

final class ActivityHistoryTests: XCTestCase {
    func testRecordCompletedStoresCountsByDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 30, hour: 9)))

        var history = ActivityHistory()
        _ = history.recordCompleted(at: date, calendar: calendar)
        let day = history.recordCompleted(at: date, calendar: calendar)

        XCTAssertEqual(day.dateKey, "2026-06-30")
        XCTAssertEqual(day.completedCount, 2)
        XCTAssertEqual(history.day(for: date, calendar: calendar).completedCount, 2)
    }

    func testDaysReturnsZeroFilledDateRange() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let endDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 30)))
        let completedDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 28)))

        var history = ActivityHistory()
        _ = history.recordCompleted(at: completedDate, calendar: calendar)

        let days = history.days(endingAt: endDate, count: 4, calendar: calendar)

        XCTAssertEqual(days.map(\.dateKey), ["2026-06-27", "2026-06-28", "2026-06-29", "2026-06-30"])
        XCTAssertEqual(days.map(\.completedCount), [0, 1, 0, 0])
    }

    func testCurrentWeekAndStreakStats() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2

        let monday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 29)))
        let tuesday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 30)))
        let sunday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 28)))

        var history = ActivityHistory()
        _ = history.recordCompleted(at: sunday, calendar: calendar)
        _ = history.recordCompleted(at: monday, calendar: calendar)
        _ = history.recordCompleted(at: tuesday, calendar: calendar)
        _ = history.recordCompleted(at: tuesday, calendar: calendar)

        XCTAssertEqual(history.completedCountInCurrentWeek(endingAt: tuesday, calendar: calendar), 3)
        XCTAssertEqual(history.currentStreak(endingAt: tuesday, calendar: calendar), 3)
    }

    func testActivityHistoryStorePersistsLocally() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SitRightTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 30, hour: 9)))

        var history = ActivityHistory()
        _ = history.recordCompleted(at: date, calendar: calendar)
        ActivityHistoryStore.save(history, storageDirectory: directory)

        let loaded = ActivityHistoryStore.load(storageDirectory: directory)

        XCTAssertEqual(loaded.day(for: date, calendar: calendar).completedCount, 1)
    }
}
