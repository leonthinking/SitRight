import AppKit
import SwiftUI

struct MenuPanelView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var statsStore: StatsStore
    @EnvironmentObject private var engine: ReminderEngine

    @State private var selectedTab: PanelTab = .today

    var body: some View {
        VStack(spacing: 14) {
            header

            if let celebration = engine.celebrationText {
                CelebrationBanner(text: celebration)
                    .transition(.scale.combined(with: .opacity))
            }

            Picker("视图", selection: $selectedTab) {
                Label("今日", systemImage: "checkmark.circle").tag(PanelTab.today)
                Label("设置", systemImage: "slider.horizontal.3").tag(PanelTab.settings)
            }
            .pickerStyle(.segmented)
            .controlSize(.regular)

            switch selectedTab {
            case .today:
                TodayPanelView()
            case .settings:
                SettingsPanelView()
            }

            Divider()

            footer
        }
        .padding(16)
        .frame(width: 370)
        .background(.regularMaterial)
        .animation(.snappy(duration: 0.22), value: engine.celebrationText)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.green.opacity(0.14))
                    .frame(width: 42, height: 42)
                Image(systemName: "figure.stand")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.green)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("SitRight 坐正")
                    .font(.headline)
                Text(engine.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            statusBarPill
        }
    }

    private var statusBarPill: some View {
        StatusPill(
            text: settingsStore.settings.menuBarCountdownEnabled ? engine.menuBarTitle : "已隐藏",
            state: settingsStore.settings.menuBarCountdownEnabled ? engine.state : .disabled
        )
    }

    private var footer: some View {
        HStack {
            Text("轻提醒，不打扰")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("退出", systemImage: "power")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }
}

private enum PanelTab {
    case today
    case settings
}

private struct StatusPill: View {
    let text: String
    let state: ReminderRunState

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.thinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(foreground.opacity(0.22), lineWidth: 0.5)
            }
    }

    private var foreground: Color {
        switch state {
        case .running:
            return .green
        case .paused:
            return .orange
        case .outsideHours:
            return .indigo
        case .disabled:
            return .secondary
        case .due:
            return .blue
        }
    }

}

private struct CelebrationBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(.orange)
            Text(text)
                .font(.subheadline.weight(.medium))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
