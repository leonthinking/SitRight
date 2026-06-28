import AppKit
import SwiftUI

@main
struct SitRightApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var container = AppContainer()

    var body: some Scene {
        MenuBarExtra {
            MenuPanelView()
                .environmentObject(container.settingsStore)
                .environmentObject(container.statsStore)
                .environmentObject(container.engine)
        } label: {
            MenuBarStatusLabel()
                .environmentObject(container.settingsStore)
                .environmentObject(container.engine)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}
