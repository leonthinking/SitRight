import AppKit
import SwiftUI

struct MenuBarStatusLabel: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var engine: ReminderEngine

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: engine.statusSystemImage)
                .foregroundStyle(statusLabelColor)

            if settingsStore.settings.menuBarCountdownEnabled {
                ZStack(alignment: .trailing) {
                    Text(MenuBarTitleLayout.measurementText(
                        for: engine.state,
                        remainingInterval: engine.remainingInterval
                    ))
                    .hidden()
                    .accessibilityHidden(true)

                    Text(engine.menuBarTitle)
                }
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(statusLabelColor)
                .lineLimit(1)
                .frame(
                    width: MenuBarTitleLayout.fixedWidth(
                        for: engine.state,
                        remainingInterval: engine.remainingInterval
                    ),
                    alignment: .trailing
                )
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .accessibilityLabel("SitRight 坐正")
        .accessibilityValue(ReminderAccessibility.statusText(
            statusText: engine.statusText,
            countdownText: engine.countdownText,
            state: engine.state,
            showsCountdown: settingsStore.settings.menuBarCountdownEnabled
        ))
    }

    private var statusLabelColor: Color {
        Color(nsColor: isAttentionState ? .labelColor : .labelColor.withSystemEffect(.disabled))
    }

    private var isAttentionState: Bool {
        guard settingsStore.settings.menuBarCountdownEnabled else { return false }
        if engine.canCompleteReminder { return true }

        switch engine.state {
        case .due:
            return true
        case .running, .paused, .outsideHours, .disabled:
            return false
        }
    }

}
