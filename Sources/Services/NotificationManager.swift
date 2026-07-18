import AppKit
import Foundation
import UserNotifications

@MainActor
protocol NotificationCenterClient: AnyObject {
    func setDelegate(_ delegate: (any UNUserNotificationCenterDelegate)?)
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>)
    func removeDeliveredNotifications(withIdentifiers identifiers: [String])
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
}

extension NotificationCenterClient {
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {}
    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {}
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {}
}

@MainActor
final class SystemNotificationCenterClient: NotificationCenterClient {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func setDelegate(_ delegate: (any UNUserNotificationCenterDelegate)?) {
        center.delegate = delegate
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await center.requestAuthorization(options: options)
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        center.setNotificationCategories(categories)
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

enum ReminderNotificationAction: Equatable, Sendable {
    case startActivity(cycleID: UUID)
    case snooze(cycleID: UUID)
}

@MainActor
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    nonisolated static let reminderCategoryIdentifier = "SITRIGHT_ACTIVITY_REMINDER"
    nonisolated static let startActionIdentifier = "SITRIGHT_START_ACTIVITY"
    nonisolated static let snoozeActionIdentifier = "SITRIGHT_SNOOZE"
    nonisolated static let cycleIDUserInfoKey = "sitright.cycleID"
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var lastErrorMessage: String?

    private let client: any NotificationCenterClient
    private let activationNotificationCenter: NotificationCenter
    private let didBecomeActiveNotification: Notification.Name
    private var statusRevision = 0
    private var reminderActionHandler: ((ReminderNotificationAction) -> Void)?
    private var pendingReminderActions: [ReminderNotificationAction] = []

    init(
        client: any NotificationCenterClient = SystemNotificationCenterClient(),
        activationNotificationCenter: NotificationCenter = .default,
        didBecomeActiveNotification: Notification.Name = NSApplication.didBecomeActiveNotification
    ) {
        self.client = client
        self.activationNotificationCenter = activationNotificationCenter
        self.didBecomeActiveNotification = didBecomeActiveNotification
        super.init()

        client.setDelegate(self)
        client.setNotificationCategories([Self.reminderCategory])
        activationNotificationCenter.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: didBecomeActiveNotification,
            object: nil
        )
        refreshAuthorizationStatus()
    }

    deinit {
        activationNotificationCenter.removeObserver(
            self,
            name: didBecomeActiveNotification,
            object: nil
        )
    }

    func refreshAuthorizationStatus() {
        let revision = beginStatusOperation()
        Task { @MainActor [weak self, client] in
            let status = await client.authorizationStatus()
            self?.applyAuthorizationStatus(status, revision: revision)
        }
    }

    func requestAuthorizationIfNeeded() {
        let revision = beginStatusOperation()
        Task { @MainActor [weak self, client] in
            let currentStatus = await client.authorizationStatus()

            do {
                if currentStatus == .notDetermined {
                    _ = try await client.requestAuthorization(options: [.alert, .sound])
                }

                let refreshedStatus = await client.authorizationStatus()
                self?.applyAuthorizationStatus(refreshedStatus, revision: revision)
            } catch {
                self?.applyError(
                    "通知授权失败：\(error.localizedDescription)",
                    revision: revision
                )
            }
        }
    }

    func deliverReminder(
        body: String,
        soundEnabled: Bool,
        completion: @escaping (Bool) -> Void
    ) {
        deliverReminder(
            cycleID: UUID(),
            body: body,
            soundEnabled: soundEnabled,
            completion: completion
        )
    }

    func deliverReminder(
        cycleID: UUID,
        body: String,
        soundEnabled: Bool,
        completion: @escaping (Bool) -> Void
    ) {
        let revision = beginStatusOperation()
        Task { @MainActor [weak self, client] in
            let status = await client.authorizationStatus()
            self?.applyAuthorizationStatus(status, revision: revision)

            guard status == .authorized || status == .provisional else {
                self?.applyError("系统通知权限未开启", revision: revision)
                completion(false)
                return
            }

            let content = UNMutableNotificationContent()
            content.title = "SitRight 坐正"
            content.subtitle = "活动提醒"
            content.body = body
            content.categoryIdentifier = Self.reminderCategoryIdentifier
            content.userInfo = [Self.cycleIDUserInfoKey: cycleID.uuidString]
            if soundEnabled {
                content.sound = .default
            }

            let request = UNNotificationRequest(
                identifier: Self.notificationIdentifier(for: cycleID),
                content: content,
                trigger: nil
            )
            do {
                try await client.add(request)
                self?.clearError(revision: revision)
                completion(true)
            } catch {
                self?.applyError(
                    "通知发送失败：\(error.localizedDescription)",
                    revision: revision
                )
                completion(false)
            }
        }
    }

    func cancelReminder(cycleID: UUID) {
        let identifiers = [Self.notificationIdentifier(for: cycleID)]
        client.removePendingNotificationRequests(withIdentifiers: identifiers)
        client.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func setReminderActionHandler(_ handler: @escaping (ReminderNotificationAction) -> Void) {
        reminderActionHandler = handler
        let queuedActions = pendingReminderActions
        pendingReminderActions.removeAll()
        queuedActions.forEach(handler)
    }

    private static var reminderCategory: UNNotificationCategory {
        let startAction = UNNotificationAction(
            identifier: startActionIdentifier,
            title: "开始 1 分钟活动",
            options: [.foreground]
        )
        let snoozeAction = UNNotificationAction(
            identifier: snoozeActionIdentifier,
            title: "延后 5 分钟",
            options: []
        )
        return UNNotificationCategory(
            identifier: reminderCategoryIdentifier,
            actions: [startAction, snoozeAction],
            intentIdentifiers: [],
            options: []
        )
    }

    private static func notificationIdentifier(for cycleID: UUID) -> String {
        "sitright-reminder-\(cycleID.uuidString.lowercased())"
    }

    private func beginStatusOperation() -> Int {
        statusRevision += 1
        return statusRevision
    }

    private func applyAuthorizationStatus(_ status: UNAuthorizationStatus, revision: Int) {
        guard revision == statusRevision else { return }
        authorizationStatus = status

        switch status {
        case .denied:
            lastErrorMessage = "系统通知权限已关闭"
        case .authorized, .provisional, .ephemeral:
            lastErrorMessage = nil
        case .notDetermined:
            break
        @unknown default:
            lastErrorMessage = "无法确认系统通知权限"
        }
    }

    private func applyError(_ message: String, revision: Int) {
        guard revision == statusRevision else { return }
        lastErrorMessage = message
    }

    private func clearError(revision: Int) {
        guard revision == statusRevision else { return }
        lastErrorMessage = nil
    }

    @objc
    private func applicationDidBecomeActive() {
        refreshAuthorizationStatus()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let content = response.notification.request.content
        guard let rawCycleID = content.userInfo[Self.cycleIDUserInfoKey] as? String,
              let cycleID = UUID(uuidString: rawCycleID) else {
            return
        }

        let action: ReminderNotificationAction?
        switch response.actionIdentifier {
        case Self.startActionIdentifier:
            action = .startActivity(cycleID: cycleID)
        case Self.snoozeActionIdentifier:
            action = .snooze(cycleID: cycleID)
        default:
            action = nil
        }
        guard let action else { return }
        await MainActor.run { [weak self] in
            guard let self else { return }
            if let reminderActionHandler {
                reminderActionHandler(action)
            } else {
                pendingReminderActions.append(action)
            }
        }
    }
}
