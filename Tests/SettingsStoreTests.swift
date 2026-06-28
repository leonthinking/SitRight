import XCTest
@testable import SitRight

@MainActor
final class SettingsStoreTests: XCTestCase {
    func testIntervalShortcutUpdatesDoNotReenterPublishedSetter() {
        let suiteName = "SitRightTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = SettingsStore(defaults: defaults)

        var changeCount = 0
        store.onSettingsChanged = {
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
        store.onSettingsChanged = {
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
}
