import AppKit
import SwiftUI
import UserNotifications
import XCTest
@testable import SitRight

final class MenuPanelPresentationTests: XCTestCase {
    func testSettingsSelectionMapsLegacyScheduleToVisibleGeneralPane() {
        XCTAssertEqual(
            SettingsSelection.visiblePane(for: .general),
            .general
        )
        XCTAssertEqual(
            SettingsSelection.visiblePane(for: .schedule),
            .general
        )
        XCTAssertEqual(
            SettingsSelection.visiblePane(for: .notifications),
            .notifications
        )
        XCTAssertEqual(
            SettingsSelection.visiblePane(for: .about),
            .about
        )
        XCTAssertEqual(
            Set(
                [
                    SettingsPane.general,
                    .schedule,
                    .notifications,
                    .about
                ].map(SettingsSelection.visiblePane(for:))
            ),
            Set([.general, .notifications, .about])
        )
    }

    func testSettingsPresentationKeepsStableIdentifiersAndUsesGeneralTitle() {
        XCTAssertEqual(SettingsPane.general.rawValue, "general")
        XCTAssertEqual(SettingsPane.schedule.rawValue, "schedule")
        XCTAssertEqual(SettingsPane.notifications.rawValue, "notifications")
        XCTAssertEqual(SettingsPane.about.rawValue, "about")
        XCTAssertEqual(
            SettingsSelection.defaultsKey,
            "sitright.settings.selectedPane"
        )
        XCTAssertEqual(
            SettingsSelection.requestedSectionDefaultsKey,
            "sitright.settings.requestedSection"
        )
        XCTAssertEqual(SettingsPanePresentation.title(for: .general), "通用")
        XCTAssertEqual(SettingsPanePresentation.title(for: .schedule), "通用")
        XCTAssertEqual(SettingsPanePresentation.title(for: .notifications), "通知")
        XCTAssertEqual(SettingsPanePresentation.title(for: .about), "关于")
    }

    func testSettingsWindowSizingProvidesRoomAndVerticalExpansion() {
        XCTAssertEqual(
            SettingsWindowSizingPolicy.defaultContentSize,
            NSSize(width: 520, height: 900)
        )
        XCTAssertEqual(
            SettingsWindowSizingPolicy.minimumContentSize,
            NSSize(width: 520, height: 520)
        )
        XCTAssertEqual(
            SettingsWindowSizingPolicy.defaultContentSize.width,
            SettingsWindowSizingPolicy.minimumContentSize.width
        )
        XCTAssertGreaterThan(
            SettingsWindowSizingPolicy.defaultContentSize.height,
            SettingsWindowSizingPolicy.minimumContentSize.height
        )
        XCTAssertEqual(
            SettingsWindowSizingPolicy.migrationTarget(
                currentContentSize: NSSize(width: 460, height: 380),
                maximumContentSize: NSSize(width: 1_440, height: 900)
            ),
            SettingsWindowSizingPolicy.defaultContentSize
        )
        XCTAssertEqual(
            SettingsWindowSizingPolicy.migrationTarget(
                currentContentSize: NSSize(width: 460, height: 380),
                maximumContentSize: NSSize(width: 1_000, height: 700)
            ),
            NSSize(width: 520, height: 700)
        )
        XCTAssertEqual(
            SettingsWindowSizingPolicy.migrationTarget(
                currentContentSize: NSSize(width: 600, height: 800),
                maximumContentSize: NSSize(width: 1_440, height: 1_000)
            ),
            NSSize(width: 520, height: 900)
        )
        XCTAssertEqual(
            SettingsWindowSizingPolicy.migrationTarget(
                currentContentSize: NSSize(width: 600, height: 640),
                maximumContentSize: NSSize(width: 1_440, height: 1_000)
            ),
            NSSize(width: 520, height: 640),
            "迁移标志缺失也不应覆盖用户主动调整的高度"
        )
        XCTAssertEqual(
            SettingsWindowSizingPolicy.restorationTarget(
                currentContentSize: NSSize(width: 520, height: 380),
                maximumContentSize: NSSize(width: 1_440, height: 1_000)
            ),
            NSSize(width: 520, height: 520)
        )
        XCTAssertEqual(
            SettingsWindowSizingPolicy.restorationTarget(
                currentContentSize: NSSize(width: 520, height: 900),
                maximumContentSize: NSSize(width: 1_440, height: 700)
            ),
            NSSize(width: 520, height: 700)
        )
        XCTAssertEqual(
            SettingsWindowSizingPolicy.restorationTarget(
                currentContentSize: NSSize(width: 520, height: 1_000),
                maximumContentSize: NSSize(width: 1_440, height: 1_200)
            ),
            NSSize(width: 520, height: 1_000)
        )
        XCTAssertEqual(
            SettingsWindowSizingPolicy.v2MigrationDefaultsKey,
            "sitright.settings.windowSizingV2Migrated"
        )
        XCTAssertEqual(
            SettingsWindowSizingPolicy.migrationDefaultsKey,
            "sitright.settings.windowSizingV3Migrated"
        )
    }

    func testSettingsSceneDeclaresDefaultSizeAndContentMinResizability() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sources/SitRightApp.swift"
            ),
            encoding: .utf8
        )
        let settingsSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sources/Views/SettingsPanelView.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(
            appSource.contains(
                ".defaultSize(SettingsWindowSizingPolicy.defaultContentSize)"
            )
        )
        XCTAssertTrue(
            appSource.contains(".windowResizability(.contentMinSize)")
        )
        XCTAssertFalse(settingsSource.contains(".frame(width: 460, height: 380)"))
        XCTAssertTrue(
            settingsSource.contains(
                "maxWidth: SettingsWindowSizingPolicy.fixedContentWidth"
            )
        )
        XCTAssertTrue(
            settingsSource.contains("NSWindow.didChangeScreenNotification")
        )
        XCTAssertTrue(settingsSource.contains(".frame(width: 1, height: 1)"))
        XCTAssertFalse(settingsSource.contains(".frame(width: 0, height: 0)"))
    }

    @MainActor
    func testProductionSettingsViewFillsDefaultAndExpandedWindows() throws {
        let suiteName = "MenuPanelPresentationTests.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            true,
            forKey: SettingsWindowSizingPolicy.migrationDefaultsKey
        )

        let settingsStore = SettingsStore(defaults: defaults)
        let notificationManager = NotificationManager(
            client: SettingsNotificationCenterClientStub()
        )
        let launchAtLoginController = LaunchAtLoginController(
            service: SettingsLaunchAtLoginServiceStub()
        )
        let view = SettingsPanelView()
            .defaultAppStorage(defaults)
            .environmentObject(settingsStore)
            .environmentObject(notificationManager)
            .environmentObject(launchAtLoginController)
            .environmentObject(UpdateController(startsUpdater: false))
        let hostingController = NSHostingController(rootView: view)
        hostingController.sizingOptions = []
        let window = NSWindow(
            contentRect: NSRect(
                origin: .zero,
                size: SettingsWindowSizingPolicy.defaultContentSize
            ),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = hostingController
        SettingsWindowConfigurator.configure(
            window,
            shouldMigrateLegacySize: false
        )

        let sizeCases: [(contentSize: NSSize, expectsOverflow: Bool)] = [
            (SettingsWindowSizingPolicy.minimumContentSize, true),
            (SettingsWindowSizingPolicy.defaultContentSize, false)
        ]

        for sizeCase in sizeCases {
            let contentSize = sizeCase.contentSize
            window.setContentSize(contentSize)
            window.contentView?.layoutSubtreeIfNeeded()

            XCTAssertEqual(
                window.contentRect(forFrameRect: window.frame).size,
                contentSize
            )
            XCTAssertEqual(hostingController.view.frame.size, contentSize)

            let formScrollView = try XCTUnwrap(
                hostingController.view.descendants(ofType: NSScrollView.self).first
            )
            let documentHeight = formScrollView.documentView?.bounds.height ?? 0
            let viewportHeight = formScrollView.contentView.bounds.height

            if sizeCase.expectsOverflow {
                XCTAssertGreaterThan(documentHeight, viewportHeight)
            } else {
                XCTAssertLessThanOrEqual(documentHeight, viewportHeight)
            }
        }

        settingsStore.update { $0.language = .english }
        window.setContentSize(SettingsWindowSizingPolicy.defaultContentSize)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        window.contentView?.layoutSubtreeIfNeeded()
        let englishScrollView = try XCTUnwrap(
            hostingController.view.descendants(ofType: NSScrollView.self).first
        )
        XCTAssertLessThanOrEqual(
            englishScrollView.documentView?.bounds.height ?? 0,
            englishScrollView.contentView.bounds.height
        )

        let sharedTabSize = NSSize(width: 520, height: 700)
        window.setContentSize(sharedTabSize)
        defaults.set(
            SettingsPane.notifications.rawValue,
            forKey: SettingsSelection.defaultsKey
        )
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(window.contentLayoutRect.size, sharedTabSize)
        defaults.set(
            SettingsPane.general.rawValue,
            forKey: SettingsSelection.defaultsKey
        )
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(window.contentLayoutRect.size, sharedTabSize)
        defaults.set(
            SettingsPane.about.rawValue,
            forKey: SettingsSelection.defaultsKey
        )
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(window.contentLayoutRect.size, sharedTabSize)

        window.setContentSize(NSSize(width: 720, height: 760))
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(
            window.contentLayoutRect.size,
            NSSize(width: 520, height: 760),
            "生产窗口观察器应纠正横向变化并保留纵向调整"
        )
        XCTAssertTrue(window.styleMask.contains(.resizable))
        window.contentViewController = nil
        window.close()
    }

    func testAboutSettingsDeclaresUpdateAndCommunityControls() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let settingsSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sources/Views/SettingsPanelView.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(settingsSource.contains("language.text(\"版本更新\", \"Software updates\")"))
        XCTAssertTrue(settingsSource.contains("\"自动检查更新\""))
        XCTAssertTrue(settingsSource.contains("language.text(\"检查更新…\", \"Check for Updates…\")"))
        XCTAssertTrue(settingsSource.contains("\"查看 GitHub Releases\""))
        XCTAssertTrue(settingsSource.contains("GitHub 社区预览版未经 Developer ID 公证"))
        XCTAssertTrue(settingsSource.contains("language.text(\"开源与社区\", \"Open source and community\")"))
        XCTAssertTrue(settingsSource.contains("title: language.text(\"开源协议\""))
        XCTAssertTrue(settingsSource.contains("detail: \"MIT\""))
        XCTAssertTrue(settingsSource.contains("CommunityLinks.repositoryURL"))
        XCTAssertTrue(settingsSource.contains("\"给 SitRight 点个 Star 🌟\""))
        XCTAssertTrue(settingsSource.contains("CommunityLinks.featureRequestURL"))
        XCTAssertTrue(settingsSource.contains("title: language.text(\"功能建议\""))
        XCTAssertTrue(settingsSource.contains("CommunityLinks.bugReportURL"))
        XCTAssertTrue(settingsSource.contains("title: language.text(\"报告问题\""))
        XCTAssertTrue(settingsSource.contains("CommunityLinks.supportRequestURL"))
        XCTAssertTrue(settingsSource.contains("title: language.text(\"使用帮助\""))
        XCTAssertTrue(settingsSource.contains("CommunityLinks.privacyURL"))
        XCTAssertTrue(settingsSource.contains("title: language.text(\"隐私说明\""))
        XCTAssertTrue(settingsSource.contains("CommunityLinks.securityReportURL"))
        XCTAssertTrue(settingsSource.contains("title: language.text(\"安全问题\""))
        XCTAssertTrue(settingsSource.contains("isExternal: true"))
        XCTAssertTrue(settingsSource.contains("arrow.up.right.square"))
        XCTAssertEqual(
            settingsSource.components(
                separatedBy: "SettingsExternalLink("
            ).count - 1,
            9
        )
        XCTAssertFalse(
            settingsSource.contains("Link(destination: CommunityLinks")
        )
        XCTAssertTrue(settingsSource.contains("需要 GitHub 账号"))
        XCTAssertTrue(settingsSource.contains("title: language.text(\"第三方许可\""))
        XCTAssertTrue(settingsSource.contains("LegalNoticeSheet(notice: notice, language: language)"))
        XCTAssertTrue(settingsSource.contains("\"在线查看\\(notice.title(language: language))\""))
        XCTAssertTrue(settingsSource.contains(".keyboardShortcut(.cancelAction)"))
        XCTAssertFalse(settingsSource.contains("错误日志"))
        XCTAssertFalse(settingsSource.contains("请从打包后的 .app 启动后设置"))
        XCTAssertTrue(settingsSource.contains("language.text(\"重新检测\", \"Check Again\")"))
        XCTAssertTrue(settingsSource.contains("language.text(\"打开登录项…\", \"Open Login Items…\")"))
        XCTAssertTrue(
            settingsSource.contains(
                "switch launchAtLoginController.recovery"
            )
        )
        XCTAssertTrue(
            settingsSource.contains(
                "case .serviceNotFound, .operationFailed"
            )
        )
        XCTAssertFalse(
            settingsSource.contains("settingsStore.setError("),
            "登录项错误应只由 LaunchAtLoginController 的结构化状态展示"
        )

        let accountNotice = try XCTUnwrap(
            settingsSource.range(of: "需要 GitHub 账号")
        )
        let firstCommunityDestination = try XCTUnwrap(
            settingsSource.range(of: "CommunityLinks.repositoryURL")
        )
        XCTAssertLessThan(
            accountNotice.lowerBound,
            firstCommunityDestination.lowerBound
        )
    }

    @MainActor
    func testAboutSettingsFitsDefaultWindowWithoutScrolling() throws {
        let suiteName = "MenuPanelPresentationTests.about.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            SettingsPane.about.rawValue,
            forKey: SettingsSelection.defaultsKey
        )
        defaults.set(
            true,
            forKey: SettingsWindowSizingPolicy.migrationDefaultsKey
        )

        let settingsStore = SettingsStore(defaults: defaults)
        let view = SettingsPanelView()
            .defaultAppStorage(defaults)
            .environmentObject(settingsStore)
            .environmentObject(
                NotificationManager(
                    client: SettingsNotificationCenterClientStub()
                )
            )
            .environmentObject(
                LaunchAtLoginController(
                    service: SettingsLaunchAtLoginServiceStub()
                )
            )
            .environmentObject(UpdateController(startsUpdater: false))
        let hostingController = NSHostingController(rootView: view)
        hostingController.sizingOptions = []
        let window = NSWindow(
            contentRect: NSRect(
                origin: .zero,
                size: SettingsWindowSizingPolicy.defaultContentSize
            ),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = hostingController
        window.setContentSize(SettingsWindowSizingPolicy.defaultContentSize)
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        window.contentView?.layoutSubtreeIfNeeded()

        let visibleScrollView = try XCTUnwrap(
            hostingController.view
                .descendants(ofType: NSScrollView.self)
                .first(where: { !$0.isHidden })
        )
        let documentHeight = visibleScrollView.documentView?.bounds.height ?? 0
        XCTAssertLessThanOrEqual(
            documentHeight,
            visibleScrollView.contentView.bounds.height
        )

        settingsStore.update { $0.language = .english }
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        window.contentView?.layoutSubtreeIfNeeded()
        let englishVisibleScrollView = try XCTUnwrap(
            hostingController.view
                .descendants(ofType: NSScrollView.self)
                .first(where: { !$0.isHidden })
        )
        XCTAssertLessThanOrEqual(
            englishVisibleScrollView.documentView?.bounds.height ?? 0,
            englishVisibleScrollView.contentView.bounds.height
        )

        window.contentViewController = nil
        window.close()
    }

    @MainActor
    func testProductionSettingsWindowConfiguratorMigratesLegacySizeOnce() {
        let legacyWindow = NSWindow(
            contentRect: NSRect(
                origin: .zero,
                size: SettingsWindowSizingPolicy.priorDefaultContentSize
            ),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        legacyWindow.isReleasedWhenClosed = false

        let didMigrate = SettingsWindowConfigurator.configure(
            legacyWindow,
            shouldMigrateLegacySize: true
        )
        XCTAssertTrue(didMigrate)

        let maximumContentSize = (legacyWindow.screen ?? NSScreen.main).map {
            legacyWindow.contentRect(forFrameRect: $0.visibleFrame).size
        } ?? SettingsWindowSizingPolicy.defaultContentSize
        let expectedMigratedSize = SettingsWindowSizingPolicy.migrationTarget(
            currentContentSize: SettingsWindowSizingPolicy.priorDefaultContentSize,
            maximumContentSize: maximumContentSize
        )
        XCTAssertEqual(legacyWindow.contentLayoutRect.size, expectedMigratedSize)
        XCTAssertEqual(legacyWindow.contentMinSize, NSSize(width: 520, height: 520))
        XCTAssertEqual(legacyWindow.contentMaxSize.width, 520)

        legacyWindow.setContentSize(NSSize(width: 520, height: 640))
        let didMigrateAgain = SettingsWindowConfigurator.configure(
            legacyWindow,
            shouldMigrateLegacySize: false
        )
        XCTAssertFalse(didMigrateAgain)
        XCTAssertEqual(
            legacyWindow.contentLayoutRect.size,
            NSSize(width: 520, height: 640)
        )

        let customWindow = NSWindow(
            contentRect: NSRect(
                origin: .zero,
                size: NSSize(width: 640, height: 680)
            ),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        customWindow.isReleasedWhenClosed = false
        XCTAssertTrue(
            SettingsWindowConfigurator.configure(
                customWindow,
                shouldMigrateLegacySize: true
            )
        )
        XCTAssertEqual(
            customWindow.contentLayoutRect.size,
            NSSize(width: 520, height: 680)
        )

        let tooShortWindow = NSWindow(
            contentRect: NSRect(
                origin: .zero,
                size: NSSize(width: 520, height: 380)
            ),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        tooShortWindow.isReleasedWhenClosed = false
        XCTAssertFalse(
            SettingsWindowConfigurator.configure(
                tooShortWindow,
                shouldMigrateLegacySize: false,
                maximumContentSize: NSSize(width: 1_440, height: 1_000)
            )
        )
        XCTAssertEqual(
            tooShortWindow.contentLayoutRect.size,
            NSSize(width: 520, height: 520)
        )

        let restoredOnSmallerScreenWindow = NSWindow(
            contentRect: NSRect(
                origin: .zero,
                size: NSSize(width: 520, height: 900)
            ),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        restoredOnSmallerScreenWindow.isReleasedWhenClosed = false
        XCTAssertFalse(
            SettingsWindowConfigurator.configure(
                restoredOnSmallerScreenWindow,
                shouldMigrateLegacySize: false,
                maximumContentSize: NSSize(width: 1_440, height: 700)
            )
        )
        XCTAssertEqual(
            restoredOnSmallerScreenWindow.contentLayoutRect.size,
            NSSize(width: 520, height: 700)
        )

        legacyWindow.close()
        customWindow.close()
        tooShortWindow.close()
        restoredOnSmallerScreenWindow.close()
    }

    @MainActor
    func testProductionSettingsViewMigratesLegacyScheduleRequest() throws {
        let suiteName = "MenuPanelPresentationTests.legacySchedule.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            SettingsPane.schedule.rawValue,
            forKey: SettingsSelection.defaultsKey
        )
        defaults.set(
            true,
            forKey: SettingsWindowSizingPolicy.migrationDefaultsKey
        )

        let settingsStore = SettingsStore(defaults: defaults)
        let notificationManager = NotificationManager(
            client: SettingsNotificationCenterClientStub()
        )
        let launchAtLoginController = LaunchAtLoginController(
            service: SettingsLaunchAtLoginServiceStub()
        )
        let view = SettingsPanelView()
            .defaultAppStorage(defaults)
            .environmentObject(settingsStore)
            .environmentObject(notificationManager)
            .environmentObject(launchAtLoginController)
            .environmentObject(UpdateController(startsUpdater: false))
        let hostingController = NSHostingController(rootView: view)
        hostingController.sizingOptions = []
        let window = NSWindow(
            contentRect: NSRect(
                origin: .zero,
                size: SettingsWindowSizingPolicy.minimumContentSize
            ),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = hostingController
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        window.contentView?.layoutSubtreeIfNeeded()

        XCTAssertEqual(
            defaults.string(forKey: SettingsSelection.defaultsKey),
            SettingsPane.general.rawValue
        )
        XCTAssertEqual(
            defaults.string(
                forKey: SettingsSelection.requestedSectionDefaultsKey
            ),
            ""
        )
        let formScrollView = try XCTUnwrap(
            hostingController.view.descendants(ofType: NSScrollView.self).first
        )
        XCTAssertGreaterThan(formScrollView.contentView.bounds.origin.y, 0)

        window.contentViewController = nil
        window.close()
    }

    @MainActor
    func testSettingsDynamicContentScrollsAtAccessibilitySize() throws {
        let suiteName = "MenuPanelPresentationTests.dynamicSettings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            true,
            forKey: SettingsWindowSizingPolicy.migrationDefaultsKey
        )

        let settingsStore = SettingsStore(defaults: defaults)
        settingsStore.update {
            $0.intervalMinutes = 35
            $0.dailyTarget = 24
            $0.lunchPauseEnabled = true
        }
        settingsStore.setError("测试错误提示仍应保留在可滚动内容中")
        let notificationManager = NotificationManager(
            client: SettingsNotificationCenterClientStub()
        )
        let launchAtLoginController = LaunchAtLoginController(
            service: SettingsLaunchAtLoginServiceStub()
        )
        let view = SettingsPanelView()
            .dynamicTypeSize(.accessibility5)
            .defaultAppStorage(defaults)
            .environmentObject(settingsStore)
            .environmentObject(notificationManager)
            .environmentObject(launchAtLoginController)
            .environmentObject(UpdateController(startsUpdater: false))
        let hostingController = NSHostingController(rootView: view)
        hostingController.sizingOptions = []
        let window = NSWindow(
            contentRect: NSRect(
                origin: .zero,
                size: SettingsWindowSizingPolicy.minimumContentSize
            ),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = hostingController
        window.contentView?.layoutSubtreeIfNeeded()

        let formScrollView = try XCTUnwrap(
            hostingController.view.descendants(ofType: NSScrollView.self).first
        )
        let documentHeight = formScrollView.documentView?.bounds.height ?? 0
        XCTAssertGreaterThan(
            documentHeight,
            formScrollView.contentView.bounds.height
        )
        let bottomOrigin = NSPoint(
            x: 0,
            y: max(
                documentHeight - formScrollView.contentView.bounds.height,
                0
            )
        )
        formScrollView.contentView.scroll(to: bottomOrigin)
        formScrollView.reflectScrolledClipView(formScrollView.contentView)
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertGreaterThan(
            documentHeight,
            SettingsWindowSizingPolicy.defaultContentSize.height
        )
        XCTAssertEqual(
            formScrollView.contentView.bounds.maxY,
            documentHeight,
            accuracy: 1
        )
        XCTAssertEqual(settingsStore.settings.intervalMinutes, 35)
        XCTAssertEqual(settingsStore.settings.dailyTarget, 24)
        XCTAssertTrue(settingsStore.settings.lunchPauseEnabled)
        XCTAssertEqual(
            settingsStore.lastErrorMessage,
            "测试错误提示仍应保留在可滚动内容中"
        )

        window.contentViewController = nil
        window.close()
    }

    func testScheduleSettingsRouteKeepsSectionIntentSeparateFromVisiblePane() {
        XCTAssertEqual(
            SettingsSelection.route(for: .general),
            SettingsRoute(visiblePane: .general, requestedSection: nil)
        )
        XCTAssertEqual(
            SettingsSelection.route(for: .schedule),
            SettingsRoute(
                visiblePane: .general,
                requestedSection: .workSchedule
            )
        )
        XCTAssertEqual(
            SettingsSelection.route(for: .notifications),
            SettingsRoute(visiblePane: .notifications, requestedSection: nil)
        )
        XCTAssertEqual(
            SettingsSelection.route(for: .about),
            SettingsRoute(visiblePane: .about, requestedSection: nil)
        )
    }

    func testSettingsSectionRequestIsConsumedExactlyOnce() {
        var request = SettingsSectionRequestState(
            rawValue: SettingsSectionDestination.workSchedule.rawValue
        )

        XCTAssertEqual(request.consume(), .workSchedule)
        XCTAssertEqual(request.rawValue, "")
        XCTAssertNil(request.consume())
    }

    func testReminderPopupUsesPlatformActionOrderForRowsAndStacks() {
        XCTAssertEqual(
            ReminderPopupActionLayout.actions(for: .horizontal),
            [.pausedToday, .snoozed, .completed]
        )
        XCTAssertEqual(
            ReminderPopupActionLayout.actions(for: .vertical),
            [.completed, .snoozed, .pausedToday]
        )
    }

    func testReminderPanelSizingIsControlledAndIgnoresCountdownTicks() {
        XCTAssertEqual(ReminderPanelSizingPolicy.hostingSizingOptions, [])
        XCTAssertTrue(
            ReminderPanelSizingPolicy.requestsMeasurement(for: .presentation)
        )
        XCTAssertFalse(
            ReminderPanelSizingPolicy.requestsMeasurement(for: .countdownTick)
        )
        XCTAssertEqual(
            ReminderPanelSizingPolicy.maximumHeight(for: nil),
            720
        )
        XCTAssertEqual(
            ReminderPanelSizingPolicy.maximumHeight(
                for: NSRect(x: 0, y: 0, width: 1_200, height: 600)
            ),
            552
        )
        XCTAssertEqual(
            ReminderPanelSizingPolicy.fittingConstraint(maximumHeight: 552),
            NSSize(width: 420, height: 552)
        )
        XCTAssertEqual(
            ReminderPanelSizingPolicy.normalized(
                NSSize(width: 300, height: 250),
                maximumHeight: 552
            ),
            NSSize(width: 420, height: 360)
        )
        XCTAssertEqual(
            ReminderPanelSizingPolicy.normalized(
                NSSize(width: 500, height: 800),
                maximumHeight: 552
            ),
            NSSize(width: 420, height: 552)
        )
        XCTAssertEqual(
            ReminderPanelSizingPolicy.normalized(
                NSSize(width: 420, height: 300),
                maximumHeight: 200
            ),
            NSSize(width: 420, height: 200)
        )
    }

    @MainActor
    func testReminderPanelRetainsMeasuredSizeAfterHostingControllerAttachment() {
        var cases: [(AppLanguage, Bool, Bool, String)] = [
            (
                .simplifiedChinese,
                false,
                false,
                ReminderMessages.reminder(language: .simplifiedChinese)
            ),
            (
                .simplifiedChinese,
                true,
                false,
                ReminderMessages.guide(language: .simplifiedChinese)
            ),
            (
                .english,
                false,
                false,
                ReminderMessages.reminder(language: .english)
            ),
            (
                .english,
                true,
                false,
                ReminderMessages.guide(language: .english)
            )
        ]
        let completionOutcomes: [ActivityGuideCompletionOutcome] = [
            .reminderResponse,
            .proactivePreservingCadence,
            .proactiveSatisfyingUpcomingReminder,
            .proactiveFollowingSchedule
        ]
        for language in AppLanguage.allCases {
            cases.append(contentsOf: completionOutcomes.map { outcome in
                (
                    language,
                    false,
                    true,
                    outcome.celebrationText(language: language)
                )
            })
        }

        for (language, isGuiding, isCompletion, message) in cases {
            var layoutFrames: [ReminderPopupLayoutElement: CGRect] = [:]
            let guideEndsAt = isGuiding ? Date().addingTimeInterval(60) : nil
            let view = ReminderPopupView(
                message: message,
                language: language,
                isGuiding: isGuiding,
                isCompletion: isCompletion,
                guideEndsAt: guideEndsAt,
                onAction: { _ in },
                layoutObserver: { element, frame in
                    layoutFrames[element] = frame
                }
            )
            let hostingController = NSHostingController(rootView: view)
            hostingController.sizingOptions = ReminderPanelSizingPolicy.hostingSizingOptions
            let measuredSize = hostingController.sizeThatFits(
                in: ReminderPanelSizingPolicy.fittingConstraint(
                    maximumHeight: ReminderPanelSizingPolicy.maximumContentHeight
                )
            )
            let contentSize = ReminderPanelSizingPolicy.normalized(measuredSize)
            let panel = ReminderPanelFactory.make(
                contentViewController: hostingController,
                contentSize: contentSize,
                language: language
            )

            panel.contentView?.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            panel.contentView?.layoutSubtreeIfNeeded()

            XCTAssertEqual(
                panel.contentRect(forFrameRect: panel.frame).size,
                contentSize
            )
            XCTAssertEqual(hostingController.view.frame.size, contentSize)
            XCTAssertGreaterThan(contentSize.width, 0)
            XCTAssertGreaterThanOrEqual(
                contentSize.height,
                ReminderPanelSizingPolicy.minimumHeight
            )
            let expectedElements: [ReminderPopupLayoutElement]
            if isCompletion {
                expectedElements = [.message, .done]
            } else if isGuiding {
                expectedElements = [.message, .countdown, .cancel]
            } else {
                expectedElements = [
                    .message,
                    .completed,
                    .snoozed,
                    .pausedToday
                ]
            }
            for element in expectedElements {
                guard let frame = layoutFrames[element] else {
                    XCTFail("Missing layout frame for \(element)")
                    continue
                }
                XCTAssertGreaterThanOrEqual(
                    frame.minX,
                    -1,
                    "\(element) must not be clipped at the leading edge"
                )
                XCTAssertLessThanOrEqual(
                    frame.maxX,
                    contentSize.width + 1,
                    "\(element) must not be clipped at the trailing edge"
                )
            }
            let visibleScrollViews = hostingController.view
                .descendants(ofType: NSScrollView.self)
                .filter { scrollView in
                    sequence(first: scrollView as NSView?, next: { $0?.superview })
                        .compactMap { $0 }
                        .allSatisfy { !$0.isHidden }
                        && scrollView.frame.height > 0
                }
            for scrollView in visibleScrollViews {
                let documentHeight = scrollView.documentView?.bounds.height ?? 0
                let viewportHeight = scrollView.contentView.bounds.height
                let documentWidth = scrollView.documentView?.bounds.width ?? 0
                let viewportWidth = scrollView.contentView.bounds.width
                XCTAssertLessThanOrEqual(
                    documentHeight,
                    viewportHeight + 1,
                    "Regular-size \(language.rawValue) popup "
                        + "(guiding: \(isGuiding), completion: \(isCompletion)) "
                        + "should not need scrolling; document \(documentHeight), "
                        + "viewport \(viewportHeight)"
                )
                XCTAssertLessThanOrEqual(
                    documentWidth,
                    viewportWidth + 1,
                    "Regular-size \(language.rawValue) popup content must not "
                        + "be clipped horizontally; document \(documentWidth), "
                        + "viewport \(viewportWidth)"
                )
            }

            if isGuiding {
                RunLoop.main.run(until: Date().addingTimeInterval(1.1))
                panel.contentView?.layoutSubtreeIfNeeded()

                XCTAssertEqual(
                    panel.contentRect(forFrameRect: panel.frame).size,
                    contentSize
                )
                XCTAssertEqual(hostingController.view.frame.size, contentSize)
            }

            panel.close()
        }
    }

    @MainActor
    func testReminderPresenterConsumesPresentedActionOnlyOnce() {
        let presenter = ReminderPresenter()
        var receivedActions: [ReminderAction] = []

        presenter.presentGuide(endsAt: Date().addingTimeInterval(60)) {
            receivedActions.append($0)
        }

        XCTAssertNotNil(presenter.panel)

        presenter.handlePresentedAction(.dismissed)
        presenter.handlePresentedAction(.dismissed)

        XCTAssertEqual(receivedActions, [.dismissed])
        XCTAssertNil(presenter.panel)
    }

    @MainActor
    func testReminderPresenterRefreshesGuideDeadlineWithoutResizingPanel() throws {
        let presenter = ReminderPresenter()
        let originalDeadline = Date().addingTimeInterval(60)
        let resumedDeadline = originalDeadline.addingTimeInterval(30)

        presenter.presentGuide(endsAt: originalDeadline) { _ in }
        let panel = try XCTUnwrap(presenter.panel)
        let contentSize = panel.contentRect(forFrameRect: panel.frame).size

        presenter.updateGuide(endsAt: resumedDeadline)

        XCTAssertTrue(presenter.panel === panel)
        XCTAssertEqual(
            panel.contentRect(forFrameRect: panel.frame).size,
            contentSize
        )
        let hostingController = try XCTUnwrap(
            panel.contentViewController as? NSHostingController<ReminderPopupView>
        )
        XCTAssertTrue(hostingController.rootView.isGuiding)
        XCTAssertEqual(hostingController.rootView.guideEndsAt, resumedDeadline)

        presenter.dismiss()
    }

    @MainActor
    func testReminderPresenterAppliesLanguageToVisibleGuideWithoutResizingPanel() throws {
        let presenter = ReminderPresenter()
        let deadline = Date().addingTimeInterval(60)

        presenter.presentGuide(endsAt: deadline) { _ in }
        let panel = try XCTUnwrap(presenter.panel)
        let contentSize = panel.contentRect(forFrameRect: panel.frame).size

        presenter.setLanguage(.english)

        let hostingController = try XCTUnwrap(
            panel.contentViewController as? NSHostingController<ReminderPopupView>
        )
        XCTAssertEqual(hostingController.rootView.language, .english)
        XCTAssertEqual(
            hostingController.rootView.message,
            ReminderMessages.guide(language: .english)
        )
        XCTAssertEqual(hostingController.rootView.guideEndsAt, deadline)
        XCTAssertEqual(
            panel.contentRect(forFrameRect: panel.frame).size,
            contentSize
        )

        presenter.dismiss()
    }

    @MainActor
    func testReminderPresenterRefreshesDeadlineWhileWaitingForPopoverToClose() throws {
        let presenter = ReminderPresenter()
        let originalDeadline = Date().addingTimeInterval(60)
        let resumedDeadline = originalDeadline.addingTimeInterval(30)

        presenter.waitForPopoverToCloseBeforePresentingGuide()
        presenter.presentGuide(endsAt: originalDeadline) { _ in }
        XCTAssertNil(presenter.panel)

        presenter.updateGuide(endsAt: resumedDeadline)
        presenter.popoverDidCloseBeforeGuidePresentation()

        let panel = try XCTUnwrap(presenter.panel)
        let hostingController = try XCTUnwrap(
            panel.contentViewController as? NSHostingController<ReminderPopupView>
        )
        XCTAssertTrue(hostingController.rootView.isGuiding)
        XCTAssertEqual(hostingController.rootView.guideEndsAt, resumedDeadline)

        presenter.dismiss()
    }

    @MainActor
    func testReminderPresenterWindowCloseCompletesOnceAndClearsPanel() throws {
        let presenter = ReminderPresenter()
        var receivedActions: [ReminderAction] = []

        presenter.presentGuide(endsAt: Date().addingTimeInterval(60)) {
            receivedActions.append($0)
        }
        let panel = try XCTUnwrap(presenter.panel)

        XCTAssertTrue(presenter.windowShouldClose(panel))
        presenter.windowWillClose(
            Notification(name: NSWindow.willCloseNotification, object: panel)
        )
        XCTAssertTrue(presenter.windowShouldClose(panel))

        XCTAssertEqual(receivedActions, [.dismissed])
        XCTAssertNil(presenter.panel)
        panel.close()
    }

    @MainActor
    func testReminderPresenterShowsCompletionInStableGuidePanelWithoutRepeatingAction() throws {
        let presenter = ReminderPresenter()
        var receivedActions: [ReminderAction] = []

        presenter.presentGuide(endsAt: Date().addingTimeInterval(60)) {
            receivedActions.append($0)
        }
        let panel = try XCTUnwrap(presenter.panel)
        let contentSize = panel.contentRect(forFrameRect: panel.frame).size

        presenter.presentGuideCompletion(
            outcome: .proactivePreservingCadence,
            language: .simplifiedChinese
        )
        panel.contentView?.layoutSubtreeIfNeeded()

        XCTAssertTrue(presenter.panel === panel)
        XCTAssertEqual(
            panel.contentRect(forFrameRect: panel.frame).size,
            contentSize
        )
        XCTAssertEqual(panel.contentViewController?.view.frame.size, contentSize)
        let completionController = try XCTUnwrap(
            panel.contentViewController as? NSHostingController<ReminderPopupView>
        )
        XCTAssertTrue(completionController.rootView.isCompletion)
        XCTAssertEqual(
            completionController.rootView.message,
            ActivityGuideCompletionOutcome
                .proactivePreservingCadence
                .celebrationText
        )

        presenter.setLanguage(.english)
        let englishCompletionController = try XCTUnwrap(
            panel.contentViewController as? NSHostingController<ReminderPopupView>
        )
        XCTAssertEqual(englishCompletionController.rootView.language, .english)
        XCTAssertEqual(
            englishCompletionController.rootView.message,
            ActivityGuideCompletionOutcome
                .proactivePreservingCadence
                .celebrationText(language: .english)
        )
        XCTAssertEqual(
            panel.contentRect(forFrameRect: panel.frame).size,
            contentSize
        )

        englishCompletionController.rootView.onAction(.dismissed)

        XCTAssertTrue(receivedActions.isEmpty)
        XCTAssertNil(presenter.panel)
        panel.close()
    }

    @MainActor
    func testEnglishReminderPopupUsesUsableInternalScrollAtAccessibilitySize() throws {
        var layoutFrames: [ReminderPopupLayoutElement: CGRect] = [:]
        let view = ReminderPopupView(
            message: ReminderMessages.guide(language: .english),
            language: .english,
            isGuiding: true,
            guideEndsAt: Date().addingTimeInterval(60),
            onAction: { _ in },
            layoutObserver: { element, frame in
                layoutFrames[element] = frame
            }
        )
        .environment(\.dynamicTypeSize, .accessibility5)
        let hostingController = NSHostingController(rootView: view)
        hostingController.sizingOptions = ReminderPanelSizingPolicy.hostingSizingOptions
        let maximumHeight: CGFloat = 240
        let measuredSize = hostingController.sizeThatFits(
            in: ReminderPanelSizingPolicy.fittingConstraint(
                maximumHeight: maximumHeight
            )
        )
        let contentSize = ReminderPanelSizingPolicy.normalized(
            measuredSize,
            maximumHeight: maximumHeight
        )
        let panel = ReminderPanelFactory.make(
            contentViewController: hostingController,
            contentSize: contentSize,
            language: .english
        )
        defer { panel.close() }

        panel.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        panel.contentView?.layoutSubtreeIfNeeded()

        XCTAssertEqual(contentSize, NSSize(width: 420, height: maximumHeight))
        let scrollView = try XCTUnwrap(
            hostingController.view
                .descendants(ofType: NSScrollView.self)
                .first(where: { scrollView in
                    sequence(first: scrollView as NSView?, next: { $0?.superview })
                        .compactMap { $0 }
                        .allSatisfy { !$0.isHidden }
                        && scrollView.frame.height > 0
                })
        )
        let documentHeight = scrollView.documentView?.bounds.height ?? 0
        let viewportHeight = scrollView.contentView.bounds.height
        let documentWidth = scrollView.documentView?.bounds.width ?? 0
        let viewportWidth = scrollView.contentView.bounds.width
        XCTAssertGreaterThan(documentHeight, viewportHeight)
        XCTAssertLessThanOrEqual(documentWidth, viewportWidth + 1)

        let maximumScrollY = max(documentHeight - viewportHeight, 0)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: maximumScrollY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        panel.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        panel.contentView?.layoutSubtreeIfNeeded()
        XCTAssertEqual(
            scrollView.contentView.bounds.origin.y,
            maximumScrollY,
            accuracy: 1
        )
        let cancelFrame = try XCTUnwrap(layoutFrames[.cancel])
        let viewport = try XCTUnwrap(layoutFrames[.scrollViewport])
        XCTAssertTrue(
            viewport.intersects(cancelFrame),
            "Cancel break must be visible after scrolling to the bottom; "
                + "button \(cancelFrame), viewport \(viewport)"
        )
        XCTAssertGreaterThan(cancelFrame.width, 0)
        XCTAssertGreaterThan(cancelFrame.height, 0)
    }

    func testSettingsValuePickerOptionsPreserveLegacyNonStepSelection() {
        let options = SettingsValuePickerOptions.values(
            in: 0...(23 * 60),
            step: 30,
            including: 9 * 60 + 15
        )

        XCTAssertTrue(options.contains(9 * 60 + 15))
        XCTAssertTrue(options.contains(0))
        XCTAssertTrue(options.contains(23 * 60))
        XCTAssertEqual(options, Array(Set(options)).sorted())
        XCTAssertFalse(
            SettingsValuePickerOptions.values(
                in: 60...120,
                step: 30,
                including: 30
            ).contains(30)
        )
    }

    func testSettingsValuePickerOptionsCoverDailyTargetAndCustomIntervalRanges() {
        XCTAssertEqual(
            SettingsValuePickerOptions.values(
                in: 1...24,
                step: 1,
                including: 10
            ),
            Array(1...24)
        )

        let customIntervals = SettingsValuePickerOptions.values(
            in: 5...240,
            step: 5,
            including: 37
        )
        XCTAssertTrue(customIntervals.contains(37))
        XCTAssertEqual(customIntervals.first, 5)
        XCTAssertEqual(customIntervals.last, 240)
        XCTAssertEqual(customIntervals, Array(Set(customIntervals)).sorted())
    }

    func testSettingsValuePresentationLocalizesCompleteTrailingValues() {
        XCTAssertEqual(
            SettingsValuePresentation.dailyTarget(10, language: .simplifiedChinese),
            "10 次"
        )
        XCTAssertEqual(
            SettingsValuePresentation.dailyTarget(1, language: .english),
            "1 time"
        )
        XCTAssertEqual(
            SettingsValuePresentation.dailyTarget(10, language: .english),
            "10 times"
        )
        XCTAssertEqual(
            SettingsValuePresentation.intervalMinutes(35, language: .english),
            "35 minutes"
        )
    }

    @MainActor
    func testProductionGeneralSettingsKeepsTrailingPickersRightAlignedInBothLanguages() throws {
        let suiteName = "MenuPanelPresentationTests.valuePickerAlignment.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            true,
            forKey: SettingsWindowSizingPolicy.migrationDefaultsKey
        )

        let settingsStore = SettingsStore(defaults: defaults)
        settingsStore.update {
            $0.intervalMinutes = 45
            $0.dailyTarget = 10
            $0.lunchPauseEnabled = true
            $0.workStartMinutes = 9 * 60
            $0.workEndMinutes = 19 * 60 + 30
            $0.lunchStartMinutes = 11 * 60 + 30
            $0.lunchEndMinutes = 13 * 60 + 30
        }
        let view = SettingsPanelView()
            .defaultAppStorage(defaults)
            .environmentObject(settingsStore)
            .environmentObject(
                NotificationManager(
                    client: SettingsNotificationCenterClientStub()
                )
            )
            .environmentObject(
                LaunchAtLoginController(
                    service: SettingsLaunchAtLoginServiceStub()
                )
            )
            .environmentObject(UpdateController(startsUpdater: false))
        let hostingController = NSHostingController(rootView: view)
        hostingController.sizingOptions = []
        let window = NSWindow(
            contentRect: NSRect(
                origin: .zero,
                size: SettingsWindowSizingPolicy.defaultContentSize
            ),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = hostingController
        window.setContentSize(SettingsWindowSizingPolicy.defaultContentSize)

        func assertAligned(language: AppLanguage) throws {
            settingsStore.update { $0.language = language }
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            window.contentView?.layoutSubtreeIfNeeded()

            let visiblePopUpButtons = hostingController.view
                .descendants(ofType: NSPopUpButton.self)
                .filter { button in
                    sequence(first: button as NSView?, next: { $0?.superview })
                        .compactMap { $0 }
                        .allSatisfy { !$0.isHidden }
                }
            XCTAssertGreaterThanOrEqual(visiblePopUpButtons.count, 7)
            let trailingEdges = visiblePopUpButtons.map {
                $0.convert($0.bounds, to: hostingController.view).maxX
            }
            let minimumTrailingEdge = try XCTUnwrap(trailingEdges.min())
            let maximumTrailingEdge = try XCTUnwrap(trailingEdges.max())
            XCTAssertEqual(minimumTrailingEdge, maximumTrailingEdge, accuracy: 1)

            let selectedTitles = Set(visiblePopUpButtons.map(\.title))
            let expectedLocalizedTitles: Set<String>
            switch language {
            case .systemDefault:
                expectedLocalizedTitles = language.resolvedLanguage() == .simplifiedChinese
                    ? ["45 分钟", "10 次", "自动（跟随系统）"]
                    : ["45 minutes", "10 times", "Automatic (System Default)"]
            case .simplifiedChinese:
                expectedLocalizedTitles = ["45 分钟", "10 次", "简体中文"]
            case .english:
                expectedLocalizedTitles = ["45 minutes", "10 times", "English"]
            }
            XCTAssertTrue(expectedLocalizedTitles.isSubset(of: selectedTitles))
            let expectedTimes = Set([9 * 60, 19 * 60 + 30, 11 * 60 + 30, 13 * 60 + 30].map {
                TimeFormatting.clockText(for: $0, locale: language.locale)
            })
            XCTAssertTrue(expectedTimes.isSubset(of: selectedTitles))
            for button in visiblePopUpButtons {
                let frameInHostingView = button.convert(
                    button.bounds,
                    to: hostingController.view
                )
                XCTAssertTrue(
                    hostingController.view.bounds.contains(frameInHostingView),
                    "The complete popup must remain inside the visible Form area"
                )
                let titleWidth = (button.title as NSString).size(
                    withAttributes: [
                        .font: button.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
                    ]
                ).width
                XCTAssertGreaterThanOrEqual(
                    button.bounds.width,
                    titleWidth + 18,
                    "Popup should display its complete selected value without truncation"
                )
            }
        }

        try assertAligned(language: .systemDefault)
        try assertAligned(language: .simplifiedChinese)
        try assertAligned(language: .english)

        window.contentViewController = nil
        window.close()
    }

    func testActionModeUsesContextualRunningAndReminderActions() {
        XCTAssertEqual(
            TodayActionMode.resolve(
                phase: .accumulating,
                state: .running,
                canRecordManualActivity: true,
                canSnooze: false,
                snoozedStatusText: ""
            ),
            .running(canRecordManualActivity: true)
        )
        XCTAssertEqual(
            TodayActionMode.resolve(
                phase: .awaitingResponse,
                state: .due,
                canRecordManualActivity: false,
                canSnooze: true,
                snoozedStatusText: ""
            ),
            .awaitingResponse(canSnooze: true)
        )
    }

    func testActionModeUsesExplicitSnoozedAndGuidingStates() {
        XCTAssertEqual(
            TodayActionMode.resolve(
                phase: .snoozed,
                state: .running,
                canRecordManualActivity: false,
                canSnooze: false,
                snoozedStatusText: "已延后 04:59"
            ),
            .snoozed(statusText: "已延后 04:59")
        )
        XCTAssertEqual(
            TodayActionMode.resolve(
                phase: .guiding,
                state: .due,
                canRecordManualActivity: false,
                canSnooze: false,
                snoozedStatusText: ""
            ),
            .guiding
        )
    }

    func testRunStateOverridesTransientPhaseForUnavailableActions() {
        XCTAssertEqual(
            TodayActionMode.resolve(
                phase: .awaitingResponse,
                state: .paused(until: nil),
                canRecordManualActivity: false,
                canSnooze: true,
                snoozedStatusText: ""
            ),
            .paused
        )
        XCTAssertEqual(
            TodayActionMode.resolve(
                phase: .accumulating,
                state: .outsideHours,
                canRecordManualActivity: false,
                canSnooze: false,
                snoozedStatusText: ""
            ),
            .outsideHours
        )
        XCTAssertEqual(
            TodayActionMode.resolve(
                phase: .accumulating,
                state: .disabled,
                canRecordManualActivity: false,
                canSnooze: false,
                snoozedStatusText: ""
            ),
            .disabled
        )
    }

    func testIntervalChoiceRecognizesPresetsAndCustomValues() {
        XCTAssertEqual(ReminderIntervalChoice.selection(for: 30), .preset(30))
        XCTAssertEqual(ReminderIntervalChoice.selection(for: 45), .preset(45))
        XCTAssertEqual(ReminderIntervalChoice.selection(for: 5), .custom)
        XCTAssertEqual(ReminderIntervalChoice.selection(for: 55), .custom)
        XCTAssertEqual(ReminderIntervalChoice.selection(for: 240), .custom)
        XCTAssertEqual(ReminderIntervalChoice.preset(50).minuteValue, 50)
        XCTAssertNil(ReminderIntervalChoice.custom.minuteValue)
    }

    func testTimerRingTextUsesPhaseSpecificDeadlineLanguage() {
        let deadline = Date(timeIntervalSince1970: 1_700_000_000)
        let timeText = deadline.formatted(date: .omitted, time: .shortened)

        XCTAssertEqual(
            TimerRingPresentationText.subtitle(
                phase: .awaitingResponse,
                nextReminderAt: deadline
            ),
            "请在 \(timeText) 前开始"
        )
        XCTAssertEqual(
            TimerRingPresentationText.subtitle(
                phase: .snoozed,
                nextReminderAt: deadline
            ),
            "延后至 \(timeText)"
        )
        XCTAssertEqual(
            TimerRingPresentationText.subtitle(
                phase: .guiding,
                nextReminderAt: deadline
            ),
            "完成后开始下一轮"
        )
        XCTAssertEqual(
            TimerRingPresentationText.subtitle(
                phase: .guiding,
                nextReminderAt: deadline,
                isProactiveGuide: true
            ),
            "主动活动，提醒节奏继续"
        )
        XCTAssertEqual(
            TimerRingPresentationText.contextLabel(
                phase: .awaitingResponse,
                state: .due
            ),
            "活动提醒"
        )
    }

    func testActivityGuideCompletionFeedbackExplainsCadenceOutcome() {
        XCTAssertGreaterThanOrEqual(
            ReminderTiming.completionFeedbackDuration,
            6
        )
        XCTAssertEqual(
            ActivityGuideCompletionOutcome.reminderResponse.celebrationText,
            "做得好，已完成 1 分钟活动。下一轮提醒已开始。"
        )
        XCTAssertEqual(
            ActivityGuideCompletionOutcome.proactivePreservingCadence.celebrationText,
            "做得好，已完成 1 分钟主动活动。原提醒时间不变。"
        )
        XCTAssertEqual(
            ActivityGuideCompletionOutcome.proactiveSatisfyingUpcomingReminder.celebrationText,
            "做得好，已完成 1 分钟主动活动。本轮提醒已满足。"
        )
        XCTAssertEqual(
            ActivityGuideCompletionOutcome.proactiveFollowingSchedule.celebrationText,
            "做得好，已完成 1 分钟主动活动。提醒将按工作时段继续。"
        )
        XCTAssertEqual(
            ActivityGuideCompletionOutcome.proactivePreservingCadence.accessibilityAnnouncement,
            ActivityGuideCompletionOutcome.proactivePreservingCadence.celebrationText
        )
    }

    func testTimerRingStrokeFitsInsideDeclaredDiameter() {
        for diameter in [
            TimerRingLayout.diameter,
            TimerRingLayout.accessibilityDiameter
        ] {
            let pathDiameter = diameter - (2 * TimerRingLayout.strokeInset)
            let paintedDiameter = pathDiameter + TimerRingLayout.lineWidth

            XCTAssertEqual(
                TimerRingLayout.strokeInset,
                TimerRingLayout.lineWidth / 2
            )
            XCTAssertEqual(paintedDiameter, diameter)
        }
    }

    func testTimerRingPartialArcUsesNonOverlappingLineCap() {
        XCTAssertEqual(TimerRingLayout.partialLineCap, .butt)
    }

    func testTimerRingProgressRemainsAccurateThroughFinalPercent() {
        let checkpoints = [0.0, 0.02, 0.5, 0.98, 0.99]

        for progress in checkpoints {
            XCTAssertEqual(
                TimerRingProgress.resolve(
                    progress: progress,
                    state: .running,
                    phase: .accumulating
                ),
                progress
            )
        }

        XCTAssertEqual(
            TimerRingProgress.resolve(
                progress: 0.99,
                state: .due,
                phase: .awaitingResponse
            ),
            1
        )
        XCTAssertEqual(
            TimerRingProgress.resolve(
                progress: 0.99,
                state: .paused(until: nil),
                phase: .paused
            ),
            0
        )
    }

    func testTimerRingGuidingDueStateUsesLiveActivityProgress() {
        XCTAssertEqual(
            TimerRingProgress.resolve(
                progress: 0,
                state: .due,
                phase: .guiding
            ),
            0
        )
        XCTAssertEqual(
            TimerRingProgress.resolve(
                progress: 0.5,
                state: .due,
                phase: .guiding
            ),
            0.5
        )
        XCTAssertEqual(
            TimerRingProgress.resolve(
                progress: 1,
                state: .due,
                phase: .guiding
            ),
            1
        )
    }

    func testTimerRingAccessibilityLayoutAddsRoomWithoutExceedingPanel() {
        XCTAssertEqual(
            TimerRingLayout.diameter(usesAccessibilityLayout: false),
            168
        )
        XCTAssertEqual(
            TimerRingLayout.diameter(usesAccessibilityLayout: true),
            200
        )
        XCTAssertLessThan(TimerRingLayout.accessibilityDiameter, 370 - 32)
        XCTAssertEqual(TimerRingLayout.compactSubtitleLineLimit, 2)
        XCTAssertLessThan(
            TimerRingLayout.compactSubtitleWidth,
            TimerRingLayout.diameter - 2 * TimerRingLayout.strokeInset
        )
    }

    func testTimerRingEnglishSubtitlesFitConfiguredTwoLineArea() {
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let lineHeight = ceil(font.boundingRectForFont.height)
        let longestSubtitles = [
            "The next cycle starts when you finish",
            "Original reminder unchanged",
            "Waiting for next reminder",
            "Waiting for reminder hours",
            "Timer restarts when resumed"
        ]

        for subtitle in longestSubtitles {
            let bounds = (subtitle as NSString).boundingRect(
                with: NSSize(
                    width: TimerRingLayout.compactSubtitleWidth,
                    height: .greatestFiniteMagnitude
                ),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font]
            )
            XCTAssertLessThanOrEqual(
                ceil(bounds.height),
                lineHeight * CGFloat(TimerRingLayout.compactSubtitleLineLimit),
                "English timer subtitle should fit without truncation: \(subtitle)"
            )
        }
    }

    func testTimerRingEnglishTitlesFitAtConfiguredMinimumScale() {
        let font = NSFont.systemFont(ofSize: 28, weight: .bold)
        let titles = [
            "Time to move",
            "Snoozed 05:00",
            "Waiting",
            "Off hours",
            "Paused",
            "Off"
        ]

        for title in titles {
            let width = (title as NSString).size(withAttributes: [.font: font]).width
            XCTAssertLessThanOrEqual(
                width * TimerRingLayout.compactTitleMinimumScale,
                TimerRingLayout.compactTitleWidth,
                "English timer title should fit inside the ring: \(title)"
            )
        }
    }

    func testTimerRingAccessibilityValueUsesSelectedLanguagePunctuation() {
        XCTAssertEqual(
            TimerRingAccessibility.value(
                title: "04:32",
                subtitle: "Next at 10:30 AM",
                language: .english
            ),
            "04:32, Next at 10:30 AM"
        )
        XCTAssertEqual(
            TimerRingAccessibility.value(
                title: "04:32",
                subtitle: "下次 10:30",
                language: .simplifiedChinese
            ),
            "04:32，下次 10:30"
        )
    }

    func testTodayProgressPresentationCollapsesEmptyBreakdown() {
        let empty = TodayProgressPresentation(
            dailyGoalCompleted: 0,
            reminderCompleted: 0,
            target: 12,
            reminderOpportunities: 0,
            responseRate: nil,
            proactiveActivities: 0,
            legacyUnclassified: 0,
            subtitle: "今天还没有完成活动"
        )

        XCTAssertEqual(empty.progress, 0)
        XCTAssertFalse(empty.showsActivityBreakdown)
        XCTAssertNil(empty.responseText)
    }

    func testTodayProgressPresentationKeepsTrustedMetricsSeparate() {
        let progress = TodayProgressPresentation(
            dailyGoalCompleted: 3,
            reminderCompleted: 2,
            target: 12,
            reminderOpportunities: 4,
            responseRate: 0.5,
            proactiveActivities: 1,
            legacyUnclassified: 0,
            subtitle: "上次完成于 10:30"
        )

        XCTAssertEqual(progress.progress, 0.25)
        XCTAssertTrue(progress.showsActivityBreakdown)
        XCTAssertEqual(progress.responseText, "50% · 2/4 次提醒")
    }

    func testTodayProgressPresentationShowsZeroResponseWhenOnlyOpportunityExists() {
        let progress = TodayProgressPresentation(
            dailyGoalCompleted: 0,
            reminderCompleted: 0,
            target: 12,
            reminderOpportunities: 1,
            responseRate: 0,
            proactiveActivities: 0,
            legacyUnclassified: 0,
            subtitle: "今天还没有完成活动"
        )

        XCTAssertTrue(progress.showsActivityBreakdown)
        XCTAssertEqual(progress.responseText, "0% · 0/1 次提醒")
    }
}

@MainActor
private final class SettingsNotificationCenterClientStub: NotificationCenterClient {
    func setDelegate(_ delegate: (any UNUserNotificationCenterDelegate)?) {}

    func authorizationStatus() async -> UNAuthorizationStatus {
        .authorized
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        true
    }

    func add(_ request: UNNotificationRequest) async throws {}
}

@MainActor
private final class SettingsLaunchAtLoginServiceStub: LaunchAtLoginService {
    var status: LaunchAtLoginStatus = .notFound

    func register() throws {
        status = .enabled
    }

    func unregister() throws {
        status = .notRegistered
    }

    func openSystemSettingsLoginItems() {}
}

private extension NSView {
    func descendants<ViewType: NSView>(ofType type: ViewType.Type) -> [ViewType] {
        subviews.flatMap { subview in
            (subview as? ViewType).map { [$0] } ?? []
                + subview.descendants(ofType: type)
        }
    }
}
