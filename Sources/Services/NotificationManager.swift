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
    nonisolated static let englishReminderCategoryIdentifier = "SITRIGHT_ACTIVITY_REMINDER_EN"
    nonisolated static let startActionIdentifier = "SITRIGHT_START_ACTIVITY"
    nonisolated static let snoozeActionIdentifier = "SITRIGHT_SNOOZE"
    nonisolated static let cycleIDUserInfoKey = "sitright.cycleID"
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var lastErrorMessage: String?

    private let client: any NotificationCenterClient
    private let activationNotificationCenter: NotificationCenter
    private let didBecomeActiveNotification: Notification.Name
    private var language: AppLanguage
    private var statusRevision = 0
    private var reminderActionHandler: ((ReminderNotificationAction) -> Void)?
    private var pendingReminderActions: [ReminderNotificationAction] = []

    private enum PresentationError {
        case authorizationFailed(String)
        case permissionUnavailable
        case permissionDenied
        case deliveryFailed(String)
        case unknownPermission

        func message(language: AppLanguage) -> String {
            switch self {
            case .authorizationFailed(let detail):
                let presentedDetail = language.sanitizedSystemErrorDetail(
                    detail,
                    simplifiedChineseFallback: "请重试",
                    englishFallback: "Please try again"
                )
                return language.text(
                    "通知授权失败：\(presentedDetail)",
                    "Notification authorization failed: \(presentedDetail)"
                )
            case .permissionUnavailable:
                return language.text(
                    "系统通知权限未开启",
                    "System notification permission is not enabled"
                )
            case .permissionDenied:
                return language.text(
                    "系统通知权限已关闭",
                    "System notification permission is off"
                )
            case .deliveryFailed(let detail):
                let presentedDetail = language.sanitizedSystemErrorDetail(
                    detail,
                    simplifiedChineseFallback: "请重试",
                    englishFallback: "Please try again"
                )
                return language.text(
                    "通知发送失败：\(presentedDetail)",
                    "Notification delivery failed: \(presentedDetail)"
                )
            case .unknownPermission:
                return language.text(
                    "无法确认系统通知权限",
                    "Unable to determine notification permission"
                )
            }
        }
    }

    private var presentationError: PresentationError?

    init(
        client: any NotificationCenterClient = SystemNotificationCenterClient(),
        language: AppLanguage = .simplifiedChinese,
        activationNotificationCenter: NotificationCenter = .default,
        didBecomeActiveNotification: Notification.Name = NSApplication.didBecomeActiveNotification
    ) {
        self.client = client
        self.language = language
        self.activationNotificationCenter = activationNotificationCenter
        self.didBecomeActiveNotification = didBecomeActiveNotification
        super.init()

        client.setDelegate(self)
        client.setNotificationCategories(Self.reminderCategories)
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
                    .authorizationFailed(error.localizedDescription),
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
        // Keep one localization context for the whole asynchronous delivery.
        // The body was produced in this same language by ReminderEngine, so a
        // settings change while permission is being queried must not create a
        // mixed-language notification.
        let deliveryLanguage = language
        Task { @MainActor [weak self, client] in
            let status = await client.authorizationStatus()
            self?.applyAuthorizationStatus(status, revision: revision)

            guard status == .authorized || status == .provisional else {
                self?.applyError(.permissionUnavailable, revision: revision)
                completion(false)
                return
            }

            let content = UNMutableNotificationContent()
            content.title = deliveryLanguage.text("SitRight 坐正", "SitRight")
            content.subtitle = deliveryLanguage.text("活动提醒", "Activity reminder")
            content.body = body
            content.categoryIdentifier = Self.reminderCategoryIdentifier(for: deliveryLanguage)
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
                    .deliveryFailed(error.localizedDescription),
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

    func setLanguage(_ language: AppLanguage) {
        guard self.language != language else { return }
        self.language = language
        client.setNotificationCategories(Self.reminderCategories)

        // A language-only change must not supersede an authorization or
        // delivery operation that is already awaiting the system. Existing
        // errors are structured so their app-owned copy can be re-rendered.
        if let presentationError {
            lastErrorMessage = presentationError.message(language: language)
        }
    }

    private static var reminderCategories: Set<UNNotificationCategory> {
        [
            reminderCategory(language: .simplifiedChinese),
            reminderCategory(language: .english)
        ]
    }

    private static func reminderCategory(language: AppLanguage) -> UNNotificationCategory {
        let startAction = UNNotificationAction(
            identifier: startActionIdentifier,
            title: language.text("开始 1 分钟活动", "Start a 1-minute break"),
            options: [.foreground]
        )
        let snoozeAction = UNNotificationAction(
            identifier: snoozeActionIdentifier,
            title: language.text("延后 5 分钟", "Remind me in 5 minutes"),
            options: []
        )
        return UNNotificationCategory(
            identifier: reminderCategoryIdentifier(for: language),
            actions: [startAction, snoozeAction],
            intentIdentifiers: [],
            options: []
        )
    }

    private static func reminderCategoryIdentifier(for language: AppLanguage) -> String {
        switch language.resolvedLanguage() {
        case .systemDefault:
            englishReminderCategoryIdentifier
        case .simplifiedChinese:
            reminderCategoryIdentifier
        case .english:
            englishReminderCategoryIdentifier
        }
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
            presentationError = .permissionDenied
            lastErrorMessage = presentationError?.message(language: language)
        case .authorized, .provisional, .ephemeral:
            presentationError = nil
            lastErrorMessage = nil
        case .notDetermined:
            break
        @unknown default:
            presentationError = .unknownPermission
            lastErrorMessage = presentationError?.message(language: language)
        }
    }

    private func applyError(_ error: PresentationError, revision: Int) {
        guard revision == statusRevision else { return }
        presentationError = error
        lastErrorMessage = error.message(language: language)
    }

    private func clearError(revision: Int) {
        guard revision == statusRevision else { return }
        presentationError = nil
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
