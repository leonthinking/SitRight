import AppKit
import XCTest
@testable import SitRight

@MainActor
final class SettingsWindowActivationControllerTests: XCTestCase {
    func testPreparingSettingsPromotesUnhidesAndActivatesApplication() {
        let client = ApplicationActivationClientSpy()
        let controller = SettingsWindowActivationController(
            applicationClient: client,
            notificationCenter: NotificationCenter()
        )

        controller.prepareForSettingsPresentation()

        XCTAssertEqual(client.activationPolicy, .regular)
        XCTAssertEqual(client.requestedPolicies, [.regular])
        XCTAssertEqual(client.unhideCallCount, 1)
        XCTAssertEqual(client.activateCallCount, 1)
    }

    func testRegisteredSettingsWindowReceivesFocusAndHideKeepsRegularMode() {
        let client = ApplicationActivationClientSpy()
        let controller = SettingsWindowActivationController(
            applicationClient: client,
            notificationCenter: NotificationCenter()
        )
        let window = makeWindow()

        controller.prepareForSettingsPresentation()
        controller.registerSettingsWindow(window)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(client.focusedWindows.map(ObjectIdentifier.init), [
            ObjectIdentifier(window)
        ])
        XCTAssertEqual(client.activationPolicy, .regular)

        controller.handleApplicationDidHide()

        XCTAssertEqual(client.activationPolicy, .regular)
        XCTAssertEqual(client.requestedPolicies, [.regular])
        window.close()
    }

    func testOpeningSettingsFromStatusItemAfterHideUnhidesAndRefocusesWindow() {
        let client = ApplicationActivationClientSpy()
        let controller = SettingsWindowActivationController(
            applicationClient: client,
            notificationCenter: NotificationCenter()
        )
        let window = makeWindow()

        controller.prepareForSettingsPresentation()
        controller.registerSettingsWindow(window)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        controller.handleApplicationDidHide()

        controller.prepareForSettingsPresentation()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(client.activationPolicy, .regular)
        XCTAssertEqual(client.unhideCallCount, 2)
        XCTAssertGreaterThanOrEqual(client.activateCallCount, 3)
        XCTAssertEqual(
            client.focusedWindows.map(ObjectIdentifier.init),
            [ObjectIdentifier(window), ObjectIdentifier(window)]
        )
        window.close()
    }

    func testHideCancelsFocusThatWasQueuedBeforeApplicationHid() {
        let client = ApplicationActivationClientSpy()
        let controller = SettingsWindowActivationController(
            applicationClient: client,
            notificationCenter: NotificationCenter()
        )
        let window = makeWindow()

        controller.prepareForSettingsPresentation()
        controller.registerSettingsWindow(window)
        controller.handleApplicationDidHide()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertTrue(client.focusedWindows.isEmpty)
        XCTAssertEqual(
            client.activateCallCount,
            1,
            "隐藏后不能由旧的异步聚焦任务再次激活应用"
        )
        XCTAssertEqual(client.activationPolicy, .regular)
        window.close()
    }

    func testRepeatedWindowRegistrationWithoutPresentationDoesNotStealFocus() {
        let client = ApplicationActivationClientSpy()
        let controller = SettingsWindowActivationController(
            applicationClient: client,
            notificationCenter: NotificationCenter()
        )
        let window = makeWindow()

        controller.prepareForSettingsPresentation()
        controller.registerSettingsWindow(window)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        controller.handleApplicationDidHide()
        window.orderFront(nil)

        let unhideCount = client.unhideCallCount
        let activateCount = client.activateCallCount
        let focusCount = client.focusedWindows.count
        controller.registerSettingsWindow(window)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(client.unhideCallCount, unhideCount)
        XCTAssertEqual(client.activateCallCount, activateCount)
        XCTAssertEqual(client.focusedWindows.count, focusCount)
        XCTAssertEqual(client.activationPolicy, .regular)
        window.close()
    }

    func testClosingHiddenSettingsWindowRestoresAccessoryMode() {
        let client = ApplicationActivationClientSpy()
        let controller = SettingsWindowActivationController(
            applicationClient: client,
            notificationCenter: NotificationCenter()
        )
        let window = makeWindow()

        controller.prepareForSettingsPresentation()
        controller.registerSettingsWindow(window)
        client.visibleStandardWindowList = [window]
        controller.handleApplicationWillHide()
        controller.handleApplicationDidHide()
        controller.handleWindowWillClose(window)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(client.activationPolicy, .accessory)
        XCTAssertEqual(client.requestedPolicies, [.regular, .accessory])
        window.close()
    }

    func testClosingSettingsThenUpdateWindowEventuallyDemotesApplication() {
        let client = ApplicationActivationClientSpy()
        let controller = SettingsWindowActivationController(
            applicationClient: client,
            notificationCenter: NotificationCenter()
        )
        let settingsWindow = makeWindow()
        let updateWindow = makeWindow()

        controller.prepareForSettingsPresentation()
        controller.registerSettingsWindow(settingsWindow)

        client.hasOtherVisibleStandardWindow = true
        controller.handleWindowWillClose(settingsWindow)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(client.activationPolicy, .regular)

        client.hasOtherVisibleStandardWindow = false
        controller.handleWindowWillClose(updateWindow)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(client.activationPolicy, .accessory)

        settingsWindow.close()
        updateWindow.close()
    }

    func testHiddenSettingsAndUpdateWindowsRemainRecoverableUntilBothClose() {
        for closesSettingsFirst in [true, false] {
            let client = ApplicationActivationClientSpy()
            let controller = SettingsWindowActivationController(
                applicationClient: client,
                notificationCenter: NotificationCenter()
            )
            let settingsWindow = makeWindow()
            let updateWindow = makeWindow()

            controller.prepareForSettingsPresentation()
            controller.registerSettingsWindow(settingsWindow)
            client.visibleStandardWindowList = [settingsWindow, updateWindow]
            controller.handleApplicationWillHide()
            client.visibleStandardWindowList = []
            controller.handleApplicationDidHide()

            let firstWindow = closesSettingsFirst
                ? settingsWindow
                : updateWindow
            let secondWindow = closesSettingsFirst
                ? updateWindow
                : settingsWindow
            controller.handleWindowWillClose(firstWindow)
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            XCTAssertEqual(
                client.activationPolicy,
                .regular,
                "隐藏期间关闭一个窗口后，另一个窗口仍须保留 Command-Tab"
            )

            controller.handleWindowWillClose(secondWindow)
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            XCTAssertEqual(client.activationPolicy, .accessory)

            settingsWindow.close()
            updateWindow.close()
        }
    }

    func testDelayedDemotionAllowsSparkleWindowHandoff() {
        let client = ApplicationActivationClientSpy()
        let controller = SettingsWindowActivationController(
            applicationClient: client,
            notificationCenter: NotificationCenter()
        )
        let checkingWindow = makeWindow()
        let updateWindow = makeWindow()

        client.activationPolicy = .regular
        controller.handleWindowWillClose(checkingWindow)
        client.hasOtherVisibleStandardWindow = true
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(
            client.activationPolicy,
            .regular,
            "关闭旧窗口与显示 Sparkle 新窗口之间不能同步降级"
        )

        client.hasOtherVisibleStandardWindow = false
        controller.handleWindowWillClose(updateWindow)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(client.activationPolicy, .accessory)
        checkingWindow.close()
        updateWindow.close()
    }

    func testModalPresentationLeasePreventsDemotionUntilAlertFinishes() {
        let client = ApplicationActivationClientSpy()
        let controller = SettingsWindowActivationController(
            applicationClient: client,
            notificationCenter: NotificationCenter()
        )
        let checkingWindow = makeWindow()

        client.activationPolicy = .regular
        controller.handleWindowWillClose(checkingWindow)
        controller.beginModalWindowPresentation()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(client.activationPolicy, .regular)

        controller.endModalWindowPresentation()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(client.activationPolicy, .accessory)
        checkingWindow.close()
    }

    func testFinishedModalAlertDemotesWithoutWillCloseNotification() {
        let client = ApplicationActivationClientSpy()
        let controller = SettingsWindowActivationController(
            applicationClient: client,
            notificationCenter: NotificationCenter()
        )
        let alertPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 180),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )

        client.activationPolicy = .regular
        client.visibleStandardWindowList = [alertPanel]
        controller.handleApplicationWillHide()
        controller.beginModalWindowPresentation()
        client.visibleStandardWindowList = []
        client.treatsWindowAsStandard = false

        controller.endModalWindowPresentation()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(
            client.activationPolicy,
            .accessory,
            "Sparkle 模态提示移出屏幕后不应依赖 willClose 才能降级"
        )
        alertPanel.close()
    }

    func testActivationPolicyTransitionRetriesOnceAfterFailure() {
        let client = ApplicationActivationClientSpy()
        client.setPolicyResults = [false, true]
        let controller = SettingsWindowActivationController(
            applicationClient: client,
            notificationCenter: NotificationCenter()
        )

        controller.prepareForSettingsPresentation()
        XCTAssertEqual(client.activationPolicy, .accessory)
        XCTAssertEqual(client.requestedPolicies, [.regular])

        controller.prepareForSettingsPresentation()
        XCTAssertEqual(
            client.requestedPolicies,
            [.regular],
            "同策略请求应与已排队的单次重试合并"
        )

        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(client.activationPolicy, .regular)
        XCTAssertEqual(client.requestedPolicies, [.regular, .regular])
    }

    func testOppositePolicyRequestCancelsStaleRetry() {
        let client = ApplicationActivationClientSpy()
        client.setPolicyResults = [false]
        let controller = SettingsWindowActivationController(
            applicationClient: client,
            notificationCenter: NotificationCenter()
        )
        let window = makeWindow()

        controller.prepareForSettingsPresentation()
        controller.registerSettingsWindow(window)
        controller.handleWindowWillClose(window)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(client.activationPolicy, .accessory)
        XCTAssertEqual(client.requestedPolicies, [.regular])
        XCTAssertTrue(
            client.focusedWindows.isEmpty,
            "关闭窗口应使尚未执行的异步聚焦任务失效"
        )
        window.close()
    }

    func testClosingStatusPanelDoesNotChangeActivationPolicy() {
        let client = ApplicationActivationClientSpy()
        client.activationPolicy = .regular
        client.treatsWindowAsStandard = false
        let controller = SettingsWindowActivationController(
            applicationClient: client,
            notificationCenter: NotificationCenter()
        )
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )

        controller.handleWindowWillClose(panel)

        XCTAssertEqual(client.activationPolicy, .regular)
        XCTAssertTrue(client.requestedPolicies.isEmpty)
        panel.close()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 900),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        return window
    }
}

@MainActor
private final class ApplicationActivationClientSpy:
    ApplicationActivationClient
{
    var activationPolicy: NSApplication.ActivationPolicy = .accessory
    var requestedPolicies: [NSApplication.ActivationPolicy] = []
    var unhideCallCount = 0
    var activateCallCount = 0
    var focusedWindows: [NSWindow] = []
    var hasOtherVisibleStandardWindow = false
    var visibleStandardWindowList: [NSWindow] = []
    var treatsWindowAsStandard = true
    var setPolicyResults: [Bool] = []

    @discardableResult
    func setActivationPolicy(
        _ policy: NSApplication.ActivationPolicy
    ) -> Bool {
        requestedPolicies.append(policy)
        let result = setPolicyResults.isEmpty
            ? true
            : setPolicyResults.removeFirst()
        if result {
            activationPolicy = policy
        }
        return result
    }

    func unhide() {
        unhideCallCount += 1
    }

    func activate() {
        activateCallCount += 1
    }

    func makeKeyAndOrderFront(_ window: NSWindow) {
        focusedWindows.append(window)
    }

    func isStandardWindow(_ window: NSWindow) -> Bool {
        treatsWindowAsStandard
    }

    func visibleStandardWindows() -> [NSWindow] {
        visibleStandardWindowList
    }

    func hasVisibleStandardWindow(excluding window: NSWindow?) -> Bool {
        hasOtherVisibleStandardWindow
    }
}
