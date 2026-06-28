import Foundation
import UserNotifications

@MainActor
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        refreshAuthorizationStatus()
    }

    func refreshAuthorizationStatus() {
        Task { @MainActor [weak self] in
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            self?.authorizationStatus = settings.authorizationStatus
        }
    }

    func requestAuthorizationIfNeeded() {
        Task { @MainActor [weak self] in
            let center = UNUserNotificationCenter.current()
            let current = await center.notificationSettings()

            if current.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }

            let refreshed = await center.notificationSettings()
            self?.authorizationStatus = refreshed.authorizationStatus
        }
    }

    func deliverReminder(body: String, soundEnabled: Bool) {
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()

            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                return
            }

            let content = UNMutableNotificationContent()
            content.title = "SitRight 坐正"
            content.subtitle = "久坐提醒"
            content.body = body
            if soundEnabled {
                content.sound = .default
            }

            let request = UNNotificationRequest(
                identifier: "sitright-reminder-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
