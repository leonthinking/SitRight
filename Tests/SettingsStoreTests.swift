import XCTest
@testable import SitRight

@MainActor
final class SettingsStoreTests: XCTestCase {
    func testDefaultIntervalIsFortyFiveMinutes() {
        let suiteName = "SitRightTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = SettingsStore(defaults: defaults)

        XCTAssertEqual(store.settings.intervalMinutes, 45)
    }

    func testIntervalShortcutUpdatesDoNotReenterPublishedSetter() {
        let suiteName = "SitRightTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = SettingsStore(defaults: defaults)

        var changeCount = 0
        store.onSettingsChanged = { _, _ in
            changeCount += 1
        }

        for interval in [15, 30, 45, 60] {
            store.update { $0.intervalMinutes = interval }
            XCTAssertEqual(store.settings.intervalMinutes, interval)
        }

        XCTAssertEqual(changeCount, 4)
    }

    func testOutOfRangeIntervalIsClampedOnce() {
        let suiteName = "SitRightTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = SettingsStore(defaults: defaults)

        var changeCount = 0
        store.onSettingsChanged = { _, _ in
            changeCount += 1
        }

        store.update { $0.intervalMinutes = 999 }

        XCTAssertEqual(store.settings.intervalMinutes, 240)
        XCTAssertEqual(changeCount, 1)
    }

    func testLegacySettingsDecodeWithMenuBarCountdownDefaultEnabled() {
        let suiteName = "SitRightTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(
            """
            {
              "remindersEnabled": false,
              "intervalMinutes": 45,
              "dailyTarget": 6
            }
            """.data(using: .utf8),
            forKey: "sitright.settings.v1"
        )

        let store = SettingsStore(defaults: defaults)

        XCTAssertFalse(store.settings.remindersEnabled)
        XCTAssertEqual(store.settings.intervalMinutes, 45)
        XCTAssertEqual(store.settings.dailyTarget, 6)
        XCTAssertTrue(store.settings.menuBarCountdownEnabled)
    }

    func testMenuBarCountdownSettingPersists() {
        let suiteName = "SitRightTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = SettingsStore(defaults: defaults)

        store.update { $0.menuBarCountdownEnabled = false }

        XCTAssertFalse(store.settings.menuBarCountdownEnabled)

        let reloadedStore = SettingsStore(defaults: defaults)
        XCTAssertFalse(reloadedStore.settings.menuBarCountdownEnabled)
    }

    func testSettingsChangeCallbackIncludesOldAndNewValues() {
        let suiteName = "SitRightTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = SettingsStore(defaults: defaults)

        var observedOld: AppSettings?
        var observedNew: AppSettings?
        store.onSettingsChanged = { oldSettings, newSettings in
            observedOld = oldSettings
            observedNew = newSettings
        }

        store.update { $0.dailyTarget = 10 }

        XCTAssertEqual(observedOld?.dailyTarget, 8)
        XCTAssertEqual(observedNew?.dailyTarget, 10)
    }

    func testNonScheduleSettingsDoNotRequireReminderScheduleChange() {
        let baseline = AppSettings()
        var updated = baseline

        updated.dailyTarget = 12
        XCTAssertFalse(updated.hasReminderScheduleChange(comparedTo: baseline))

        updated = baseline
        updated.menuBarCountdownEnabled = false
        XCTAssertFalse(updated.hasReminderScheduleChange(comparedTo: baseline))

        updated = baseline
        updated.popupEnabled = false
        XCTAssertFalse(updated.hasReminderScheduleChange(comparedTo: baseline))

        updated = baseline
        updated.notificationsEnabled = false
        XCTAssertFalse(updated.hasReminderScheduleChange(comparedTo: baseline))

        updated = baseline
        updated.soundEnabled = false
        XCTAssertFalse(updated.hasReminderScheduleChange(comparedTo: baseline))

        updated = baseline
        updated.launchAtLogin = true
        XCTAssertFalse(updated.hasReminderScheduleChange(comparedTo: baseline))
    }

    func testScheduleSettingsRequireReminderScheduleChange() {
        let baseline = AppSettings()
        let scheduleMutations: [(inout AppSettings) -> Void] = [
            { $0.remindersEnabled = false },
            { $0.intervalMinutes = 60 },
            { $0.workdaysOnly = false },
            { $0.workStartMinutes = 10 * 60 },
            { $0.workEndMinutes = 19 * 60 },
            { $0.lunchPauseEnabled = false },
            { $0.lunchStartMinutes = 12 * 60 + 30 },
            { $0.lunchEndMinutes = 14 * 60 }
        ]

        for mutate in scheduleMutations {
            var updated = baseline
            mutate(&updated)
            XCTAssertTrue(updated.hasReminderScheduleChange(comparedTo: baseline))
        }
    }
}
