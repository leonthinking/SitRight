import AppKit
import SwiftUI

struct MenuPanelView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var statsStore: StatsStore
    @ObservedObject private var refreshController: MenuPanelRefreshController

    private let engine: ReminderEngine
    private let onSelectedTabChanged: () -> Void
    @State private var selectedTab: PanelTab = .today

    init(
        engine: ReminderEngine,
        refreshController: MenuPanelRefreshController,
        onSelectedTabChanged: @escaping () -> Void = {}
    ) {
        self.engine = engine
        self.refreshController = refreshController
        self.onSelectedTabChanged = onSelectedTabChanged
    }

    var body: some View {
        VStack(spacing: 14) {
            header

            Picker("视图", selection: $selectedTab) {
                Label("今日", systemImage: "checkmark.circle").tag(PanelTab.today)
                Label("设置", systemImage: "slider.horizontal.3").tag(PanelTab.settings)
            }
            .pickerStyle(.segmented)
            .controlSize(.regular)

            switch selectedTab {
            case .today:
                TodayPanelView(engine: engine)
            case .settings:
                SettingsPanelView(engine: engine)
            }

            Divider()

            footer
        }
        .padding(16)
        .frame(width: 370)
        .onChange(of: selectedTab) { _, _ in
            onSelectedTabChanged()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.green.opacity(0.14))
                    .frame(width: 42, height: 42)
                Image(systemName: engine.celebrationText == nil ? engine.statusSystemImage : "sparkles")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(engine.celebrationText == nil ? .green : .orange)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("SitRight 坐正")
                    .font(.headline)
                Text(engine.celebrationText ?? engine.statusText)
                    .font(.caption)
                    .foregroundStyle(engine.celebrationText == nil ? Color.secondary : Color.orange)
                    .lineLimit(1)
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
