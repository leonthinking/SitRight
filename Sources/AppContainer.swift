import Foundation

@MainActor
final class AppContainer: ObservableObject {
    let settingsStore: SettingsStore
    let statsStore: StatsStore
    let notificationManager: NotificationManager
    let launchAtLoginController: LaunchAtLoginController
    let reminderPresenter: ReminderPresenter
    let widgetSyncController: WidgetSyncController
    let reminderSessionStateStore: ReminderSessionStateStore
    let engine: ReminderEngine
    let systemActivityMonitor: ReminderSystemActivityMonitor

    init() {
        var storagePreparationErrors: [String] = []
        do {
            try ActivityHistoryStore.migrateDevelopmentDatasetToAppGroupIfNeeded()
        } catch {
            storagePreparationErrors.append(error.localizedDescription)
        }

        do {
            try SharedStorage.migrateDevelopmentFilesToAppGroupIfNeeded(named: [
                WidgetSnapshotStore.fileName
            ])
        } catch {
            storagePreparationErrors.append(error.localizedDescription)
        }
        let storagePreparationError = storagePreparationErrors.isEmpty
            ? nil
            : storagePreparationErrors.joined(separator: "；")

        let settingsStore = SettingsStore()
        let statsStore = StatsStore(initialErrorMessage: storagePreparationError)
        let notificationManager = NotificationManager()
        let launchAtLoginController = LaunchAtLoginController()
        let reminderPresenter = ReminderPresenter()
        let widgetSyncController = WidgetSyncController()
        let reminderSessionStateStore = ReminderSessionStateStore()

        self.settingsStore = settingsStore
        self.statsStore = statsStore
        self.notificationManager = notificationManager
        self.launchAtLoginController = launchAtLoginController
        self.reminderPresenter = reminderPresenter
        self.widgetSyncController = widgetSyncController
        self.reminderSessionStateStore = reminderSessionStateStore
        let engine = ReminderEngine(
            settingsStore: settingsStore,
            statsStore: statsStore,
            notificationManager: notificationManager,
            reminderPresenter: reminderPresenter,
            widgetSyncController: widgetSyncController,
            sessionStateStore: reminderSessionStateStore
        )
        self.engine = engine
        self.systemActivityMonitor = ReminderSystemActivityMonitor(engine: engine)

        engine.start()
    }
}
