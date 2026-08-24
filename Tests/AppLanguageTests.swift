import Foundation
import XCTest
@testable import SitRight

final class AppLanguageTests: XCTestCase {
    func testLanguageNamesAndCorePresentationCopy() {
        XCTAssertEqual(AppLanguage.simplifiedChinese.displayName, "简体中文")
        XCTAssertEqual(AppLanguage.english.displayName, "English")
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
            AppLanguage.english.localizedRuntimeMessage(
                "活动记录已从备份恢复；无法访问 SitRight App Group，共享统计已暂停"
            ),
            "Activity history was restored from backup; Unable to access the SitRight App Group. Shared statistics are paused."
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
