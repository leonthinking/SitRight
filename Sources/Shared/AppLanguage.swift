import Foundation

enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case systemDefault = "system_default"
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    static var preferredSystemLanguageLocale: Locale {
        Locale(
            identifier: Locale.preferredLanguages.first
                ?? Locale.current.identifier
        )
    }

    var locale: Locale {
        locale(
            resolvingSystemLocale: .current,
            preferredLanguageLocale: Self.preferredSystemLanguageLocale
        )
    }

    func resolvedLanguage(
        for systemLocale: Locale = Self.preferredSystemLanguageLocale
    ) -> AppLanguage {
        guard self == .systemDefault else { return self }
        return systemLocale.language.languageCode?.identifier == "zh"
            ? .simplifiedChinese
            : .english
    }

    func locale(
        resolvingSystemLocale systemLocale: Locale,
        preferredLanguageLocale: Locale? = nil
    ) -> Locale {
        let resolvedLanguage = resolvedLanguage(
            for: preferredLanguageLocale ?? systemLocale
        )
        var components = Locale.Components(locale: systemLocale)
        switch resolvedLanguage {
        case .systemDefault:
            return systemLocale
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
        components.hourCycle = systemLocale.hourCycle
        components.firstDayOfWeek = systemLocale.firstDayOfWeek
        return Locale(components: components)
    }

    var displayName: String {
        displayName(resolvingSystemLocale: .current)
    }

    func displayName(resolvingSystemLocale systemLocale: Locale) -> String {
        switch self {
        case .systemDefault:
            return resolvedLanguage(for: systemLocale) == .simplifiedChinese
                ? "自动（跟随系统）"
                : "Automatic (System Default)"
        case .simplifiedChinese:
            return "简体中文"
        case .english:
            return "English"
        }
    }

    func displayName(presentationLanguage: AppLanguage) -> String {
        guard self == .systemDefault else { return displayName }
        return presentationLanguage.text(
            "自动（跟随系统）",
            "Automatic (System Default)"
        )
    }

    func text(_ simplifiedChinese: String, _ english: String) -> String {
        switch resolvedLanguage() {
        case .systemDefault:
            return english
        case .simplifiedChinese:
            return simplifiedChinese
        case .english:
            return english
        }
    }

    func quantity(
        _ value: Int,
        simplifiedChineseUnit: String,
        englishSingular: String,
        englishPlural: String
    ) -> String {
        text(
            "\(value) \(simplifiedChineseUnit)",
            "\(value) \(value == 1 ? englishSingular : englishPlural)"
        )
    }

    func formattedTime(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle(date: .omitted, time: .shortened)
                .locale(locale)
        )
    }

    func localizedRuntimeMessage(_ message: String) -> String {
        let resolvedLanguage = resolvedLanguage()
        let combinedMessages = message.components(separatedBy: "；")
        if combinedMessages.count > 1 {
            return combinedMessages
                .map(localizedRuntimeMessage)
                .joined(separator: resolvedLanguage == .english ? "; " : "；")
        }

        guard resolvedLanguage == .english else {
            return Self.isSystemDetailCompatible(message, with: resolvedLanguage)
                ? message
                : "SitRight 遇到意外错误，请重试"
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
                let detail = String(message.dropFirst(storagePrefix.count))
                guard Self.isSystemDetailCompatible(detail, with: resolvedLanguage) else {
                    return "Unable to access SitRight local storage."
                }
                return "Unable to access SitRight local storage: \(detail)"
            }
            return Self.isSystemDetailCompatible(message, with: resolvedLanguage)
                ? message
                : "SitRight encountered an unexpected error. Please try again."
        }
    }

    func sanitizedSystemErrorDetail(
        _ detail: String,
        simplifiedChineseFallback: String,
        englishFallback: String
    ) -> String {
        Self.isSystemDetailCompatible(detail, with: resolvedLanguage())
            ? detail
            : text(simplifiedChineseFallback, englishFallback)
    }

    private static func isSystemDetailCompatible(
        _ detail: String,
        with language: AppLanguage
    ) -> Bool {
        let allowedScripts: String
        switch language {
        case .systemDefault:
            return isSystemDetailCompatible(
                detail,
                with: language.resolvedLanguage()
            )
        case .simplifiedChinese:
            guard detail.range(of: #"\p{Han}"#, options: .regularExpression) != nil else {
                return false
            }
            allowedScripts = #"^[\p{Han}\p{Latin}\p{N}\p{P}\p{S}\p{Z}\p{M}]*$"#
        case .english:
            allowedScripts = #"^[\p{Latin}\p{N}\p{P}\p{S}\p{Z}\p{M}]*$"#
        }
        return detail.range(of: allowedScripts, options: .regularExpression) != nil
    }
}
