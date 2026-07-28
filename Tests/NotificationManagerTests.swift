import Foundation
import UserNotifications
import XCTest
@testable import SitRight

@MainActor
final class NotificationManagerTests: XCTestCase {
    func testApplicationActivationRefreshesDeniedAuthorizationToAuthorized() async {
        let client = NotificationCenterClientStub(status: .denied)
        let activationCenter = NotificationCenter()
        let activationName = Notification.Name("NotificationManagerTests.didBecomeActive")
        let manager = NotificationManager(
            client: client,
            activationNotificationCenter: activationCenter,
            didBecomeActiveNotification: activationName
        )

        let observedDenied = await waitUntil { manager.authorizationStatus == .denied }
        XCTAssertTrue(observedDenied)
        XCTAssertEqual(manager.lastErrorMessage, "系统通知权限已关闭")
        XCTAssertTrue(client.didSetDelegate)

        client.status = .authorized
        activationCenter.post(name: activationName, object: nil)

        let observedAuthorized = await waitUntil { manager.authorizationStatus == .authorized }
        XCTAssertTrue(observedAuthorized)
        XCTAssertNil(manager.lastErrorMessage)
    }

    private func waitUntil(_ predicate: () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return predicate()
    }
}

@MainActor
private final class NotificationCenterClientStub: NotificationCenterClient {
    var status: UNAuthorizationStatus
    private(set) var didSetDelegate = false

    init(status: UNAuthorizationStatus) {
        self.status = status
    }

    func setDelegate(_ delegate: (any UNUserNotificationCenterDelegate)?) {
        didSetDelegate = delegate != nil
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        status
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        status = .authorized
        return true
    }

    func add(_ request: UNNotificationRequest) async throws {}
}

final class ReminderAccessibilityTests: XCTestCase {
    func testRunningCountdownIsIncludedWhenVisible() {
        XCTAssertEqual(
            ReminderAccessibility.statusText(
                statusText: "坐姿提醒中",
                countdownText: "04:32",
                state: .running,
                showsCountdown: true
            ),
            "坐姿提醒中，剩余 04:32"
        )
    }

    func testHiddenCountdownIsNotIncluded() {
        XCTAssertEqual(
            ReminderAccessibility.statusText(
                statusText: "坐姿提醒中",
                countdownText: "04:32",
                state: .running,
                showsCountdown: false
            ),
            "坐姿提醒中"
        )
    }

    func testPausedStateDoesNotIncludeCountdown() {
        XCTAssertEqual(
            ReminderAccessibility.statusText(
                statusText: "已暂停",
                countdownText: "04:32",
                state: .paused(until: nil),
                showsCountdown: true
            ),
            "已暂停"
        )
    }
}
