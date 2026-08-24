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

    func testChangingLanguageReRegistersNotificationActionsWithoutStartingStatusRefresh() async {
        let client = NotificationCenterClientStub(status: .authorized)
        let manager = NotificationManager(client: client)
        let observedInitialStatus = await waitUntil {
            manager.authorizationStatus == .authorized
        }
        XCTAssertTrue(observedInitialStatus)
        let authorizationQueryCount = client.authorizationStatusCallCount

        manager.setLanguage(.english)
        await Task.yield()

        let actions = client.categories.first {
            $0.identifier == NotificationManager.englishReminderCategoryIdentifier
        }?.actions ?? []
        XCTAssertEqual(actions.map(\.title), [
            "Start a 1-minute break",
            "Remind me in 5 minutes"
        ])
        XCTAssertEqual(client.categories.count, 2)
        XCTAssertEqual(client.authorizationStatusCallCount, authorizationQueryCount)
    }

    func testLanguageChangeDoesNotInvalidatePendingAuthorizationResult() async {
        let client = NotificationCenterClientStub(status: .notDetermined)
        let manager = NotificationManager(client: client)
        let observedInitialStatus = await waitUntil {
            client.authorizationStatusCallCount > 0
        }
        XCTAssertTrue(observedInitialStatus)

        manager.requestAuthorizationIfNeeded()
        let observedRequest = await waitUntil { client.hasPendingAuthorizationRequest }
        XCTAssertTrue(observedRequest)

        manager.setLanguage(.english)
        client.completeAuthorizationRequest(granted: true)

        let observedAuthorized = await waitUntil {
            manager.authorizationStatus == .authorized
        }
        XCTAssertTrue(observedAuthorized)
        XCTAssertNil(manager.lastErrorMessage)
    }

    func testDeliveryUsesOneLanguageWhenPreferenceChangesDuringStatusQuery() async throws {
        let client = NotificationCenterClientStub(status: .authorized)
        let manager = NotificationManager(client: client)
        let observedInitialStatus = await waitUntil {
            manager.authorizationStatus == .authorized
        }
        XCTAssertTrue(observedInitialStatus)

        client.suspendNextAuthorizationStatusQuery()
        var deliveryResult: Bool?
        manager.deliverReminder(
            body: "到活动时间了。",
            soundEnabled: false
        ) { deliveryResult = $0 }
        let observedPendingQuery = await waitUntil { client.hasPendingStatusQuery }
        XCTAssertTrue(observedPendingQuery)

        manager.setLanguage(.english)
        client.completeStatusQuery()

        let observedDelivery = await waitUntil { deliveryResult != nil }
        XCTAssertTrue(observedDelivery)
        XCTAssertEqual(deliveryResult, true)
        let request = try XCTUnwrap(client.addedRequests.last)
        XCTAssertEqual(request.content.title, "SitRight 坐正")
        XCTAssertEqual(request.content.subtitle, "活动提醒")
        XCTAssertEqual(request.content.body, "到活动时间了。")
        XCTAssertEqual(
            request.content.categoryIdentifier,
            NotificationManager.reminderCategoryIdentifier
        )
        let actions = try XCTUnwrap(client.categories.first {
            $0.identifier == request.content.categoryIdentifier
        }?.actions)
        XCTAssertEqual(actions.map(\.title), [
            "开始 1 分钟活动",
            "延后 5 分钟"
        ])
    }

    func testChangingLanguageRendersExistingPermissionErrorInNewLanguage() async {
        let client = NotificationCenterClientStub(status: .denied)
        let manager = NotificationManager(client: client)
        let observedDenied = await waitUntil {
            manager.authorizationStatus == .denied
        }
        XCTAssertTrue(observedDenied)
        XCTAssertEqual(manager.lastErrorMessage, "系统通知权限已关闭")
        let authorizationQueryCount = client.authorizationStatusCallCount

        manager.setLanguage(.english)

        XCTAssertEqual(
            manager.lastErrorMessage,
            "System notification permission is off"
        )
        XCTAssertEqual(client.authorizationStatusCallCount, authorizationQueryCount)
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
    private(set) var categories: Set<UNNotificationCategory> = []
    private(set) var authorizationStatusCallCount = 0
    private var authorizationContinuation: CheckedContinuation<Bool, Never>?
    private var statusContinuation: CheckedContinuation<UNAuthorizationStatus, Never>?
    private var shouldSuspendNextStatusQuery = false
    private(set) var addedRequests: [UNNotificationRequest] = []

    var hasPendingAuthorizationRequest: Bool {
        authorizationContinuation != nil
    }

    var hasPendingStatusQuery: Bool {
        statusContinuation != nil
    }

    init(status: UNAuthorizationStatus) {
        self.status = status
    }

    func setDelegate(_ delegate: (any UNUserNotificationCenterDelegate)?) {
        didSetDelegate = delegate != nil
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        authorizationStatusCallCount += 1
        if shouldSuspendNextStatusQuery {
            shouldSuspendNextStatusQuery = false
            return await withCheckedContinuation { continuation in
                statusContinuation = continuation
            }
        }
        return status
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        let granted = await withCheckedContinuation { continuation in
            authorizationContinuation = continuation
        }
        status = granted ? .authorized : .denied
        return granted
    }

    func completeAuthorizationRequest(granted: Bool) {
        let continuation = authorizationContinuation
        authorizationContinuation = nil
        continuation?.resume(returning: granted)
    }

    func add(_ request: UNNotificationRequest) async throws {
        addedRequests.append(request)
    }

    func suspendNextAuthorizationStatusQuery() {
        shouldSuspendNextStatusQuery = true
    }

    func completeStatusQuery() {
        let continuation = statusContinuation
        statusContinuation = nil
        continuation?.resume(returning: status)
    }

    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        self.categories = categories
    }
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
