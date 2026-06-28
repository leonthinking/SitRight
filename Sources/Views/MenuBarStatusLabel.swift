import SwiftUI

struct MenuBarStatusLabel: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var engine: ReminderEngine

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "figure.stand")
                .opacity(settingsStore.settings.menuBarCountdownEnabled ? 1 : 0.45)

            if settingsStore.settings.menuBarCountdownEnabled {
                Text(engine.menuBarTitle)
            }
        }
        .accessibilityLabel("SitRight 坐正")
    }
}
