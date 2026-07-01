import Foundation
import WidgetKit

@MainActor
final class WidgetSyncController {
    private var lastReloadAt = Date.distantPast
    private var lastSnapshot: WidgetSnapshot?

    func publish(
        settings: AppSettings,
        stats: DailyStats,
        nextReminderAt: Date?,
        state: ReminderRunState,
        statusText: String,
        now: Date
    ) {
        let snapshot = WidgetSnapshot(
            updatedAt: now,
            nextReminderAt: nextReminderAt,
            intervalMinutes: settings.intervalMinutes,
            state: WidgetSnapshot.RunState(state),
            statusText: statusText,
            completedCount: stats.completedCount,
            dailyTarget: settings.dailyTarget,
            dateKey: stats.dateKey
        )

        WidgetSnapshotStore.save(snapshot)

        let shouldReload = lastSnapshot?.reloadRelevantFields != snapshot.reloadRelevantFields
            || now.timeIntervalSince(lastReloadAt) > 60

        lastSnapshot = snapshot

        if shouldReload {
            WidgetCenter.shared.reloadTimelines(ofKind: SitRightWidgetKind.activity)
            lastReloadAt = now
        }
    }
}

private extension WidgetSnapshot {
    var reloadRelevantFields: String {
        [
            state.rawValue,
            statusText,
            "\(completedCount)",
            "\(dailyTarget)",
            dateKey,
            "\(intervalMinutes)",
            nextReminderAt.map { String(Int($0.timeIntervalSince1970 / 60)) } ?? "nil"
        ].joined(separator: "|")
    }
}

private extension WidgetSnapshot.RunState {
    init(_ state: ReminderRunState) {
        switch state {
        case .running:
            self = .running
        case .paused:
            self = .paused
        case .outsideHours:
            self = .outsideHours
        case .disabled:
            self = .disabled
        case .due:
            self = .due
        }
    }
}
