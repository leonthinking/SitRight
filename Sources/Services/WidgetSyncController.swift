import Foundation
import WidgetKit

@MainActor
final class WidgetSyncController {
    private var lastSnapshot: WidgetSnapshot?
    private let storageDirectory: URL?
    private let reloadTimelines: Bool

    init(storageDirectory: URL? = nil, reloadTimelines: Bool = true) {
        self.storageDirectory = storageDirectory
        self.reloadTimelines = reloadTimelines
    }

    func publish(
        settings: AppSettings,
        stats: DailyStats,
        nextReminderAt: Date?,
        state: ReminderRunState,
        phase: ReminderPhase = .accumulating,
        accumulatedEligibleSeconds: TimeInterval? = nil,
        responseDeadline: Date? = nil,
        snoozedUntil: Date? = nil,
        guideStartedAt: Date? = nil,
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
            reminderCompletedCount: stats.reminderCompletedCount,
            reminderOpportunityCount: stats.reminderOpportunityCount,
            manualActivityCount: stats.manualActivityCount,
            legacyUnclassifiedCount: stats.legacyUnclassifiedCount,
            qualifiedActivityCount: stats.qualifiedActivityCount,
            qualifiedProactiveCount: stats.qualifiedProactiveCount,
            dailyGoalActivityCount: stats.dailyGoalActivityCount,
            dailyTarget: settings.dailyTarget,
            dateKey: stats.dateKey,
            phase: WidgetSnapshot.ActivityPhase(phase),
            accumulatedEligibleSeconds: accumulatedEligibleSeconds,
            responseDeadline: responseDeadline,
            snoozedUntil: snoozedUntil,
            guideStartedAt: guideStartedAt,
            guideEndsAt: guideStartedAt?.addingTimeInterval(ReminderTiming.guidedActivityDuration)
        )

        guard lastSnapshot?.reloadRelevantFields != snapshot.reloadRelevantFields else {
            return
        }

        guard WidgetSnapshotStore.save(snapshot, storageDirectory: storageDirectory) else {
            return
        }
        lastSnapshot = snapshot

        if reloadTimelines {
            WidgetCenter.shared.reloadTimelines(ofKind: SitRightWidgetKind.activity)
        }
    }
}

private extension WidgetSnapshot {
    var reloadRelevantFields: String {
        var fields = [
            state.rawValue,
            statusText,
            "\(completedCount)",
            "\(reminderCompletedCount)",
            "\(reminderOpportunityCount)",
            "\(manualActivityCount)",
            "\(legacyUnclassifiedCount)",
            "\(qualifiedActivityCount)",
            "\(qualifiedProactiveCount)",
            "\(dailyGoalActivityCount)",
            "\(dailyTarget)",
            dateKey,
            "\(intervalMinutes)",
            nextReminderAt.map { String(Int($0.timeIntervalSince1970 / 60)) } ?? "nil"
        ]
        fields.append(phase?.rawValue ?? "legacy")
        fields.append(accumulatedEligibleSeconds.map { String(Int($0)) } ?? "nil")
        fields.append(responseDeadline.map { String(Int($0.timeIntervalSince1970)) } ?? "nil")
        fields.append(snoozedUntil.map { String(Int($0.timeIntervalSince1970)) } ?? "nil")
        fields.append(guideStartedAt.map { String(Int($0.timeIntervalSince1970)) } ?? "nil")
        return fields.joined(separator: "|")
    }
}

private extension WidgetSnapshot.ActivityPhase {
    init(_ phase: ReminderPhase) {
        self = WidgetSnapshot.ActivityPhase(rawValue: phase.rawValue) ?? .accumulating
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
