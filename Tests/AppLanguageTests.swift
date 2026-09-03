import Foundation
import XCTest
@testable import SitRight

final class AppLanguageTests: XCTestCase {
    func testLanguageNamesAndCorePresentationCopy() {
        XCTAssertEqual(AppLanguage.systemDefault.rawValue, "system_default")
        XCTAssertEqual(
            AppLanguage.systemDefault.displayName(
                resolvingSystemLocale: Locale(identifier: "zh-Hans-CN")
            ),
            "自动（跟随系统）"
        )
        XCTAssertEqual(
            AppLanguage.systemDefault.displayName(
                resolvingSystemLocale: Locale(identifier: "en-US")
            ),
            "Automatic (System Default)"
        )
        XCTAssertEqual(AppLanguage.simplifiedChinese.displayName, "简体中文")
        XCTAssertEqual(AppLanguage.english.displayName, "English")
        XCTAssertEqual(
            AppLanguage.systemDefault.displayName(
                presentationLanguage: .simplifiedChinese
            ),
            "自动（跟随系统）"
        )
        XCTAssertEqual(
            AppLanguage.systemDefault.displayName(
                presentationLanguage: .english
            ),
            "Automatic (System Default)"
        )
        XCTAssertEqual(
            SettingsPanePresentation.title(for: .general, language: .english),
            "General"
        )
        XCTAssertEqual(
            UpdatePresentationState.current.statusText(language: .english),
            "SitRight is up to date"
        )
        XCTAssertEqual(
            ReminderAccessibility.statusText(
                statusText: "Reminders are active",
                countdownText: "04:32",
                state: .running,
                showsCountdown: true,
                language: .english
            ),
            "Reminders are active, 04:32 remaining"
        )
    }

    func testSystemDefaultResolvesChineseSystemsToChineseAndOthersToEnglish() {
        for identifier in ["zh-Hans-CN", "zh-Hant-TW", "zh-HK"] {
            XCTAssertEqual(
                AppLanguage.systemDefault.resolvedLanguage(
                    for: Locale(identifier: identifier)
                ),
                .simplifiedChinese
            )
        }

        for identifier in ["en-US", "ja-JP", "fr-FR"] {
            XCTAssertEqual(
                AppLanguage.systemDefault.resolvedLanguage(
                    for: Locale(identifier: identifier)
                ),
                .english
            )
        }
    }

    func testSystemDefaultLocaleUsesResolvedCopyLanguageAndKeepsRegionPreferences() {
        let systemLocale = Locale(identifier: "ja-JP")
        let locale = AppLanguage.systemDefault.locale(
            resolvingSystemLocale: systemLocale,
            preferredLanguageLocale: Locale(identifier: "en-US")
        )

        XCTAssertEqual(
            locale.language.languageCode?.identifier,
            "en"
        )
        XCTAssertEqual(locale.hourCycle, systemLocale.hourCycle)
        XCTAssertEqual(locale.firstDayOfWeek, systemLocale.firstDayOfWeek)

        let month = Date(timeIntervalSince1970: 1_785_456_000).formatted(
            Date.FormatStyle().month(.abbreviated).locale(locale)
        )
        XCTAssertTrue(
            month.range(of: #"^[A-Za-z]+$"#, options: .regularExpression) != nil
        )
    }

    func testEnglishMonthMarkersUseTheSelectedLanguageLocale() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = AppLanguage.english.locale
        let endDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 24
        )))

        let presentation = HeatmapPresentation(
            history: ActivityHistory(),
            endDate: endDate,
            dayCount: 90,
            calendar: calendar
        )

        XCTAssertEqual(presentation.monthMarkers.last?.title, "Aug")
        XCTAssertTrue(presentation.monthMarkers.allSatisfy { marker in
            marker.title.range(of: #"^[A-Za-z]+$"#, options: .regularExpression) != nil
        })
    }

    func testEnglishLocalizationResourcesCoverPrimaryAppAndWidgetSurfaces() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: repositoryRoot.appendingPathComponent(
            "Sources/Resources/en.lproj/Localizable.strings"
        ))
        let strings = try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: String]
        )

        for key in [
            "通用",
            "语言",
            "提醒方式",
            "版本更新",
            "主动活动 1 分钟",
            "活动完成",
            "今日活动",
            "最近 3 个月",
            "活动热力图"
        ] {
            XCTAssertNotNil(strings[key], "Missing English localization for \(key)")
        }

        let project = try String(
            contentsOf: repositoryRoot.appendingPathComponent("project.yml"),
            encoding: .utf8
        )
        XCTAssertTrue(project.contains("path: Sources/Resources"))
        XCTAssertTrue(project.contains("en.lproj/Localizable.strings"))
        XCTAssertTrue(project.contains("zh-Hans.lproj/Localizable.strings"))
        XCTAssertTrue(project.contains("buildPhase: resources"))
    }

    func testKnownRuntimeStorageMessagesTranslateWithoutChangingUnknownErrors() {
        XCTAssertEqual(
            AppLanguage.english.localizedRuntimeMessage("活动记录已从备份恢复"),
            "Activity history was restored from backup"
        )
        XCTAssertEqual(
            AppLanguage.english.localizedRuntimeMessage("custom system error"),
            "custom system error"
        )
        XCTAssertEqual(
            AppLanguage.english.localizedRuntimeMessage("未知系统错误"),
            "SitRight encountered an unexpected error. Please try again."
        )
        XCTAssertEqual(
            AppLanguage.english.localizedRuntimeMessage("予期しないエラー"),
            "SitRight encountered an unexpected error. Please try again."
        )
        XCTAssertEqual(
            AppLanguage.simplifiedChinese.localizedRuntimeMessage(
                "Unexpected system error"
            ),
            "SitRight 遇到意外错误，请重试"
        )
        XCTAssertEqual(
            AppLanguage.english.localizedRuntimeMessage(
                "无法访问 SitRight 本地存储：目录不可用"
            ),
            "Unable to access SitRight local storage."
        )
        XCTAssertEqual(
            AppLanguage.english.localizedRuntimeMessage(
                "活动记录已从备份恢复；无法访问 SitRight App Group，共享统计已暂停"
            ),
            "Activity history was restored from backup; Unable to access the SitRight App Group. Shared statistics are paused."
        )
    }

    func testEnglishQuantitiesUseSingularAndPluralForms() {
        XCTAssertEqual(
            AppLanguage.english.quantity(
                1,
                simplifiedChineseUnit: "秒",
                englishSingular: "second",
                englishPlural: "seconds"
            ),
            "1 second"
        )
        XCTAssertEqual(
            AppLanguage.english.quantity(
                0,
                simplifiedChineseUnit: "秒",
                englishSingular: "second",
                englishPlural: "seconds"
            ),
            "0 seconds"
        )
        XCTAssertEqual(
            AppLanguage.english.quantity(
                2,
                simplifiedChineseUnit: "秒",
                englishSingular: "second",
                englishPlural: "seconds"
            ),
            "2 seconds"
        )
        XCTAssertEqual(
            AppLanguage.simplifiedChinese.quantity(
                1,
                simplifiedChineseUnit: "秒",
                englishSingular: "second",
                englishPlural: "seconds"
            ),
            "1 秒"
        )
    }

    func testEnglishSystemErrorDetailsDoNotLeakChineseCopy() {
        XCTAssertEqual(
            AppLanguage.english.sanitizedSystemErrorDetail(
                "系统拒绝了请求",
                simplifiedChineseFallback: "请重试",
                englishFallback: "Please try again"
            ),
            "Please try again"
        )
        XCTAssertEqual(
            AppLanguage.english.sanitizedSystemErrorDetail(
                "The request was denied",
                simplifiedChineseFallback: "请重试",
                englishFallback: "Please try again"
            ),
            "The request was denied"
        )
        XCTAssertEqual(
            AppLanguage.simplifiedChinese.sanitizedSystemErrorDetail(
                "系统拒绝了请求",
                simplifiedChineseFallback: "请重试",
                englishFallback: "Please try again"
            ),
            "系统拒绝了请求"
        )
        XCTAssertEqual(
            AppLanguage.english.sanitizedSystemErrorDetail(
                "リクエストが拒否されました",
                simplifiedChineseFallback: "请重试",
                englishFallback: "Please try again"
            ),
            "Please try again"
        )
        XCTAssertEqual(
            AppLanguage.english.sanitizedSystemErrorDetail(
                "Запрос отклонен",
                simplifiedChineseFallback: "请重试",
                englishFallback: "Please try again"
            ),
            "Please try again"
        )
        XCTAssertEqual(
            AppLanguage.simplifiedChinese.sanitizedSystemErrorDetail(
                "The request was denied",
                simplifiedChineseFallback: "请重试",
                englishFallback: "Please try again"
            ),
            "请重试"
        )
    }

    func testSelectedLanguagePreservesCurrentHourCycleAndWeekStart() {
        for language in AppLanguage.allCases {
            XCTAssertEqual(language.locale.hourCycle, Locale.current.hourCycle)

            var calendar = Calendar.current
            let originalFirstWeekday = calendar.firstWeekday
            calendar.locale = language.locale
            XCTAssertEqual(calendar.firstWeekday, originalFirstWeekday)
        }
    }
}
