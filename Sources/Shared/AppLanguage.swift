import Foundation

enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    var locale: Locale {
        var components = Locale.Components(locale: .current)
        switch self {
        case .simplifiedChinese:
            components.languageComponents.languageCode = Locale.LanguageCode("zh")
            components.languageComponents.script = Locale.Script("Hans")
        case .english:
            components.languageComponents.languageCode = Locale.LanguageCode("en")
            components.languageComponents.script = nil
        }
        // Language is an app-copy preference. Preserve the user's regional
        // hour-cycle and week-start choices rather than silently changing
        // them with a bare `en` or `zh-Hans` locale.
        components.hourCycle = Locale.current.hourCycle
        components.firstDayOfWeek = Locale.current.firstDayOfWeek
        return Locale(components: components)
    }

    var displayName: String {
        switch self {
        case .simplifiedChinese:
            return "简体中文"
        case .english:
            return "English"
        }
    }

    func text(_ simplifiedChinese: String, _ english: String) -> String {
        switch self {
        case .simplifiedChinese:
            return simplifiedChinese
        case .english:
            return english
        }
    }

    func formattedTime(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle(date: .omitted, time: .shortened)
                .locale(locale)
        )
    }

    func localizedRuntimeMessage(_ message: String) -> String {
        guard self == .english else { return message }

        let combinedMessages = message.components(separatedBy: "；")
        if combinedMessages.count > 1 {
            return combinedMessages
                .map(localizedRuntimeMessage)
                .joined(separator: "; ")
        }

        switch message {
        case "活动记录已从备份恢复":
            return "Activity history was restored from backup"
        case "无法访问 SitRight App Group，共享统计已暂停":
            return "Unable to access the SitRight App Group. Shared statistics are paused."
        case "活动历史文件和备份均无法读取，原文件已保留":
            return "Neither the activity history nor its backup could be read. The original files were preserved."
        default:
            let storagePrefix = "无法访问 SitRight 本地存储："
            if message.hasPrefix(storagePrefix) {
                return "Unable to access SitRight local storage: "
                    + message.dropFirst(storagePrefix.count)
            }
            return message
        }
    }
}
