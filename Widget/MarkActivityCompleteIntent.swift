import AppIntents
import Foundation
import WidgetKit

struct MarkActivityCompleteIntent: AppIntent {
    static let title: LocalizedStringResource = "标记完成"
    static let description = IntentDescription("记录一次坐姿/活动完成，并刷新 SitRight 小组件。")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        let now = Date()
        let day = ActivityHistoryStore.recordCompleted(at: now)
        var snapshot = WidgetSnapshotStore.load()
        snapshot.updatedAt = now
        snapshot.completedCount = day.completedCount
        snapshot.dateKey = day.dateKey
        WidgetSnapshotStore.save(snapshot)

        WidgetCenter.shared.reloadTimelines(ofKind: SitRightWidgetKind.activity)
        return .result()
    }
}
