import Foundation

struct AppSettings: Codable, Equatable {
    var remindersEnabled: Bool = true
    var intervalMinutes: Int = 30
    var dailyTarget: Int = 8
    var menuBarCountdownEnabled: Bool = true

    var workdaysOnly: Bool = true
    var workStartMinutes: Int = 9 * 60
    var workEndMinutes: Int = 18 * 60
    var lunchPauseEnabled: Bool = true
    var lunchStartMinutes: Int = 12 * 60
    var lunchEndMinutes: Int = 13 * 60 + 30

    var popupEnabled: Bool = true
    var notificationsEnabled: Bool = true
    var soundEnabled: Bool = true
    var launchAtLogin: Bool = false

    enum CodingKeys: String, CodingKey {
        case remindersEnabled
        case intervalMinutes
        case dailyTarget
        case menuBarCountdownEnabled
        case workdaysOnly
        case workStartMinutes
        case workEndMinutes
        case lunchPauseEnabled
        case lunchStartMinutes
        case lunchEndMinutes
        case popupEnabled
        case notificationsEnabled
        case soundEnabled
        case launchAtLogin
    }

    init() {}

    init(from decoder: Decoder) throws {
        let defaults = AppSettings()
        let container = try decoder.container(keyedBy: CodingKeys.self)

        remindersEnabled = try container.decodeIfPresent(Bool.self, forKey: .remindersEnabled) ?? defaults.remindersEnabled
        intervalMinutes = try container.decodeIfPresent(Int.self, forKey: .intervalMinutes) ?? defaults.intervalMinutes
        dailyTarget = try container.decodeIfPresent(Int.self, forKey: .dailyTarget) ?? defaults.dailyTarget
        menuBarCountdownEnabled = try container.decodeIfPresent(Bool.self, forKey: .menuBarCountdownEnabled) ?? defaults.menuBarCountdownEnabled

        workdaysOnly = try container.decodeIfPresent(Bool.self, forKey: .workdaysOnly) ?? defaults.workdaysOnly
        workStartMinutes = try container.decodeIfPresent(Int.self, forKey: .workStartMinutes) ?? defaults.workStartMinutes
        workEndMinutes = try container.decodeIfPresent(Int.self, forKey: .workEndMinutes) ?? defaults.workEndMinutes
        lunchPauseEnabled = try container.decodeIfPresent(Bool.self, forKey: .lunchPauseEnabled) ?? defaults.lunchPauseEnabled
        lunchStartMinutes = try container.decodeIfPresent(Int.self, forKey: .lunchStartMinutes) ?? defaults.lunchStartMinutes
        lunchEndMinutes = try container.decodeIfPresent(Int.self, forKey: .lunchEndMinutes) ?? defaults.lunchEndMinutes

        popupEnabled = try container.decodeIfPresent(Bool.self, forKey: .popupEnabled) ?? defaults.popupEnabled
        notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? defaults.notificationsEnabled
        soundEnabled = try container.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? defaults.soundEnabled
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? defaults.launchAtLogin
    }

    func normalized() -> AppSettings {
        var copy = self
        copy.intervalMinutes = min(max(copy.intervalMinutes, 5), 240)
        copy.dailyTarget = min(max(copy.dailyTarget, 1), 24)

        copy.workStartMinutes = copy.workStartMinutes.clamped(to: 0...(23 * 60))
        copy.workEndMinutes = copy.workEndMinutes.clamped(to: 60...(24 * 60))
        if copy.workStartMinutes >= copy.workEndMinutes {
            copy.workEndMinutes = min(copy.workStartMinutes + 60, 24 * 60)
        }

        copy.lunchStartMinutes = copy.lunchStartMinutes.clamped(to: copy.workStartMinutes...copy.workEndMinutes)
        copy.lunchEndMinutes = copy.lunchEndMinutes.clamped(to: copy.workStartMinutes...copy.workEndMinutes)
        if copy.lunchStartMinutes >= copy.lunchEndMinutes {
            copy.lunchEndMinutes = min(copy.lunchStartMinutes + 30, copy.workEndMinutes)
        }

        return copy
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
