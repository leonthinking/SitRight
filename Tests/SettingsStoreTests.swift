import XCTest
@testable import SitRight

@MainActor
final class SettingsStoreTests: XCTestCase {
    func testFreshInstallUsesAppleInspiredDeliveryDefaults() {
        let suiteName = "SitRightTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = SettingsStore(defaults: defaults)

        XCTAssertEqual(store.settings.intervalMinutes, 50)
        XCTAssertTrue(store.settings.notificationsEnabled)
        XCTAssertFalse(store.settings.soundEnabled)
        XCTAssertFalse(store.settings.popupEnabled)
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

    func testLunchNormalizationMaintainsThirtyMinuteWindowInsideWorkHours() {
        let suiteName = "SitRightTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = SettingsStore(defaults: defaults)

        store.update { settings in
            settings.workStartMinutes = 23 * 60
            settings.workEndMinutes = 24 * 60
            settings.lunchStartMinutes = 24 * 60
            settings.lunchEndMinutes = 0
        }

        XCTAssertEqual(store.settings.lunchStartMinutes, 23 * 60 + 30)
        XCTAssertEqual(store.settings.lunchEndMinutes, 24 * 60)
    }

    func testEmptyLegacySettingsUseAllCurrentDefaults() throws {
        let suiteName = "SitRightTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(try XCTUnwrap("{}".data(using: .utf8)), forKey: "sitright.settings.v1")

        XCTAssertEqual(SettingsStore(defaults: defaults).settings, AppSettings())
    }

    func testCorruptSettingsFallBackToDefaults() {
        let suiteName = "SitRightTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(Data("not-json".utf8), forKey: "sitright.settings.v1")

        XCTAssertEqual(SettingsStore(defaults: defaults).settings, AppSettings())
    }

    func testPersistedOutOfRangeValuesAreNormalizedOnLoad() throws {
        let suiteName = "SitRightTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        var persisted = AppSettings()
        persisted.intervalMinutes = 999
        persisted.dailyTarget = 0
        persisted.workStartMinutes = 2_000
        persisted.workEndMinutes = -50
        defaults.set(try JSONEncoder().encode(persisted), forKey: "sitright.settings.v1")

        let settings = SettingsStore(defaults: defaults).settings

        XCTAssertEqual(settings.intervalMinutes, 240)
        XCTAssertEqual(settings.dailyTarget, 1)
        XCTAssertEqual(settings.workStartMinutes, 23 * 60)
        XCTAssertEqual(settings.workEndMinutes, 24 * 60)
        XCTAssertGreaterThanOrEqual(settings.lunchStartMinutes, settings.workStartMinutes)
        XCTAssertLessThanOrEqual(settings.lunchEndMinutes, settings.workEndMinutes)
        XCTAssertGreaterThanOrEqual(settings.lunchEndMinutes - settings.lunchStartMinutes, 30)
    }

    func testNoOpUpdateDoesNotPersistOrNotify() {
        let suiteName = "SitRightTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = SettingsStore(defaults: defaults)
        var changeCount = 0
        store.onSettingsChanged = { _, _ in changeCount += 1 }

        store.update { $0.intervalMinutes = 50 }

        XCTAssertEqual(changeCount, 0)
        XCTAssertNil(defaults.data(forKey: "sitright.settings.v1"))
    }
}
