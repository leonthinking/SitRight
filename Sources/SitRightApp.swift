import AppKit
import SwiftUI

@main
struct SitRightApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsPanelView()
                .environmentObject(appDelegate.container.settingsStore)
                .environmentObject(appDelegate.container.notificationManager)
                .environmentObject(appDelegate.container.launchAtLoginController)
                .environmentObject(appDelegate.container.updateController)
        }
        .defaultSize(SettingsWindowSizingPolicy.defaultContentSize)
        .windowResizability(.contentMinSize)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let container = AppContainer()
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        container.updateController.start()
        self.statusBarController = StatusBarController(container: container)
    }
}
