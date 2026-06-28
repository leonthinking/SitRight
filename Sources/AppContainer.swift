import Foundation

@MainActor
final class AppContainer: ObservableObject {
    let settingsStore: SettingsStore
    let statsStore: StatsStore
    let notificationManager: NotificationManager
    let reminderPresenter: ReminderPresenter
    let widgetSyncController: WidgetSyncController
    let engine: ReminderEngine

    init() {
        let settingsStore = SettingsStore()
        let statsStore = StatsStore()
        let notificationManager = NotificationManager()
        let reminderPresenter = ReminderPresenter()
        let widgetSyncController = WidgetSyncController()

        self.settingsStore = settingsStore
        self.statsStore = statsStore
        self.notificationManager = notificationManager
        self.reminderPresenter = reminderPresenter
        self.widgetSyncController = widgetSyncController
        self.engine = ReminderEngine(
            settingsStore: settingsStore,
            statsStore: statsStore,
            notificationManager: notificationManager,
            reminderPresenter: reminderPresenter,
            widgetSyncController: widgetSyncController
        )

        self.engine.start()
    }
}
