import SwiftUI
import WidgetKit

struct SitRightWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> SitRightWidgetEntry {
        SitRightWidgetEntry(date: Date(), snapshot: .empty, history: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (SitRightWidgetEntry) -> Void) {
        completion(loadEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SitRightWidgetEntry>) -> Void) {
        let now = Date()
        let entry = loadEntry(date: now)
        let calendar = Calendar.current
        let tomorrow = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: now)
        ) ?? now.addingTimeInterval(24 * 60 * 60)
        let defaultRefresh = calendar.date(
            byAdding: .minute,
            value: 5,
            to: tomorrow
        ) ?? now.addingTimeInterval(60 * 60)
        let deadlineRefreshes = [
            entry.snapshot.nextReminderAt,
            entry.snapshot.responseDeadline,
            entry.snapshot.snoozedUntil,
            entry.snapshot.guideEndsAt
        ].compactMap { $0 }
            .filter { $0 > now }
        let nextRefresh = min(
            defaultRefresh,
            deadlineRefreshes.min() ?? defaultRefresh
        )
        let rolloverEntry = SitRightWidgetEntry(
            date: tomorrow,
            snapshot: entry.snapshot,
            history: entry.history
        )

        completion(Timeline(entries: [entry, rolloverEntry], policy: .after(nextRefresh)))
    }

    private func loadEntry(date: Date) -> SitRightWidgetEntry {
        SitRightWidgetEntry(
            date: date,
            snapshot: WidgetSnapshotStore.load(),
            history: ActivityHistoryStore.loadForDisplay()
        )
    }
}

struct SitRightWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let history: ActivityHistory
}

struct SitRightWidgetEntryView: View {
    let entry: SitRightWidgetEntry

    var body: some View {
        largeView
            .containerBackground(.background, for: .widget)
    }

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                header
                Spacer()
                Text("本周 \(weekCompletedCount) · 连续 \(streakDays) 天")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            statusSummary

            HStack(spacing: 8) {
                statCard(
                    title: "今日活动",
                    value: "\(today.dailyGoalActivityCount)/\(dailyTarget)",
                    systemImage: "checkmark.circle.fill"
                )
                statCard(
                    title: "提醒后活动",
                    value: "\(today.reminderCompletedCount) 次",
                    systemImage: "bell.badge.fill"
                )
                statCard(
                    title: "主动活动",
                    value: "\(today.qualifiedProactiveCount) 次",
                    systemImage: "arrow.triangle.2.circlepath"
                )
            }

            if today.legacyUnclassifiedCount > 0 {
                Label(
                    "未分类记录 \(today.legacyUnclassifiedCount) 次",
                    systemImage: "archivebox"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("最近 3 个月")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HeatmapView(
                    history: entry.history,
                    endDate: entry.date,
                    dayCount: 90
                )
                    .frame(maxHeight: .infinity)
            }
        }
        .padding(4)
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "timer")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.green)
            Text("SitRight 坐正")
                .font(.headline)
                .lineLimit(1)
        }
    }

    private var statusSummary: some View {
        HStack(spacing: 6) {
            Image(systemName: statusSymbol)
                .foregroundStyle(.green)
            Text(statusText)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("提醒状态")
        .accessibilityValue(statusText)
    }

    private var statusText: String {
        switch entry.snapshot.phase {
        case .accumulating:
            return entry.snapshot.nextReminderAt.map {
                "下次提醒 \($0.formatted(date: .omitted, time: .shortened))"
            } ?? "正在累计活动间隔"
        case .delivering:
            return "正在发送活动提醒"
        case .awaitingResponse:
            return "等待开始 1 分钟活动"
        case .snoozed:
            return "已延后 5 分钟"
        case .guiding:
            return "活动进行中"
        case .overdue:
            return "活动时间已到"
        case .paused:
            return "已暂停"
        case .outsideSchedule:
            return "非提醒时段"
        case .disabled:
            return "提醒已关闭"
        case nil:
            return entry.snapshot.statusText
        }
    }

    private var statusSymbol: String {
        switch entry.snapshot.phase {
        case .guiding: return "timer"
        case .paused: return "pause.circle"
        case .disabled: return "power"
        case .outsideSchedule: return "moon"
        case .snoozed: return "clock.arrow.circlepath"
        default: return "bell"
        }
    }

    private func statCard(title: String, value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
            Text(value)
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var today: ActivityDay {
        entry.history.day(for: entry.date)
    }

    private var dailyTarget: Int {
        max(today.dailyTargetSnapshot ?? entry.snapshot.dailyTarget, 1)
    }

    private var weekCompletedCount: Int {
        entry.history.completedCountInCurrentWeek(endingAt: entry.date)
    }

    private var streakDays: Int {
        entry.history.currentStreak(endingAt: entry.date)
    }
}

private struct HeatmapView: View {
    let history: ActivityHistory
    let endDate: Date
    let dayCount: Int

    private let calendar = Calendar.current
    private let gap: CGFloat = 4
    private let maximumCornerRadius: CGFloat = 4

    var body: some View {
        let presentation = HeatmapPresentation(
            history: history,
            endDate: endDate,
            dayCount: dayCount,
            calendar: calendar
        )

        VStack(spacing: 4) {
            GeometryReader { proxy in
                heatmap(in: proxy.size, presentation: presentation)
            }

            heatmapLegend
                .frame(height: 12)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("活动热力图")
        .accessibilityValue(accessibilitySummary(for: presentation))
    }

    private func heatmap(
        in size: CGSize,
        presentation: HeatmapPresentation
    ) -> some View {
        let monthLabelHeight: CGFloat = 14
        let weekdayLabelWidth: CGFloat = 0
        let plotWidth = max(size.width - weekdayLabelWidth, 0)
        let plotHeight = max(size.height - monthLabelHeight, 0)
        let cellSize = max(
            min(
                (plotWidth - CGFloat(max(presentation.weeks.count - 1, 0)) * gap)
                    / CGFloat(max(presentation.weeks.count, 1)),
                (plotHeight - 6 * gap) / 7
            ),
            2
        )
        let totalWidth = CGFloat(presentation.weeks.count) * cellSize
            + CGFloat(max(presentation.weeks.count - 1, 0)) * gap
        let totalHeight = 7 * cellSize + 6 * gap
        let originX = weekdayLabelWidth + max((plotWidth - totalWidth) / 2, 0)
        let originY = monthLabelHeight + max((plotHeight - totalHeight) / 2, 0)
        let step = cellSize + gap

        return ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for weekIndex in presentation.weeks.indices {
                    for dayIndex in 0..<7 {
                        let cell = presentation.weeks[weekIndex].cells[dayIndex]
                        guard cell.state != .padding else { continue }

                        let rect = CGRect(
                            x: originX + CGFloat(weekIndex) * step,
                            y: originY + CGFloat(dayIndex) * step,
                            width: cellSize,
                            height: cellSize
                        )
                        let path = Path(
                            roundedRect: rect,
                            cornerRadius: min(cellSize * 0.22, maximumCornerRadius)
                        )

                        if let fill = fillColor(for: cell.state) {
                            context.fill(path, with: .color(fill))
                        }
                        if cell.state == .neutral {
                            context.stroke(
                                path,
                                with: .color(Color.secondary.opacity(0.28)),
                                lineWidth: min(max(cellSize * 0.08, 0.6), 1)
                            )
                        }
                        if cell.isToday {
                            context.stroke(
                                path,
                                with: .color(todayStrokeColor(for: cell.state)),
                                lineWidth: min(max(cellSize * 0.1, 1), 1.5)
                            )
                        }
                    }
                }
            }

            let placements = HeatmapPresentation.monthLabelPlacements(
                for: presentation.monthMarkers,
                originX: originX,
                step: step,
                availableWidth: size.width,
                labelWidth: 24
            )
            ForEach(
                Array(placements.enumerated()),
                id: \.offset
            ) { _, placement in
                Text(placement.title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(width: 24, alignment: .leading)
                    .offset(
                        x: placement.xOffset,
                        y: 0
                    )
            }
        }
    }

    private var heatmapLegend: some View {
        HStack(spacing: 4) {
            Text("少")
            ForEach(HeatmapIntensity.allCases, id: \.rawValue) { intensity in
                RoundedRectangle(cornerRadius: 2)
                    .fill(color(for: intensity))
                    .frame(width: 9, height: 9)
            }
            Text("达标")
        }
        .font(.system(size: 8, weight: .medium))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func fillColor(for state: HeatmapCellState) -> Color? {
        switch state {
        case .padding, .neutral:
            nil
        case .inactive:
            Color.secondary.opacity(0.14)
        case let .activity(intensity):
            color(for: intensity)
        }
    }

    private func todayStrokeColor(for state: HeatmapCellState) -> Color {
        switch state {
        case .activity:
            Color.primary.opacity(0.82)
        case .padding, .inactive, .neutral:
            Color.green
        }
    }

    private func color(for intensity: HeatmapIntensity) -> Color {
        switch intensity {
        case .low:
            Color.green.opacity(0.28)
        case .medium:
            Color.green.opacity(0.48)
        case .high:
            Color.green.opacity(0.72)
        case .complete:
            Color.green
        }
    }

    private func accessibilitySummary(for presentation: HeatmapPresentation) -> String {
        let summary = presentation.summary
        return "最近 \(dayCount) 天，活动 \(summary.activityTotal) 次，活跃 \(summary.activeDays) 天，达标 \(summary.completedDays) 天"
    }
}

private extension ActivityHistory {
    static var preview: ActivityHistory {
        var history = ActivityHistory()
        let calendar = Calendar.current
        let today = Date()

        for offset in 0..<90 {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let weekday = calendar.component(.weekday, from: date)
            let count = (offset + weekday) % 6 == 0 ? 4 : (offset + weekday) % 3 == 0 ? 2 : 0
            guard count > 0 else { continue }

            var day = ActivityDay(dateKey: ActivityDay.makeDateKey(for: date, calendar: calendar))
            day.reminderCycles = (0..<count).map { _ in
                ReminderCycleRecord(
                    id: UUID(),
                    firstTriggeredAt: date,
                    outcome: .completed,
                    resolvedAt: date,
                    completedAt: date
                )
            }
            day.completedCount = count
            day.lastCompletedAt = date
            day.dailyTargetSnapshot = 4
            day.eligibilitySnapshot = .scheduled
            history.upsert(day)
        }

        return history
    }
}

struct SitRightQuarterWidget: Widget {
    let kind = SitRightWidgetKind.quarterActivity

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SitRightWidgetProvider()) { entry in
            SitRightWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("SitRight 坐正 · 最近 3 个月")
        .description("查看今日活动、本周统计和最近 3 个月活动热力图。")
        .supportedFamilies([.systemLarge])
    }
}

@main
struct SitRightWidgetBundle: WidgetBundle {
    var body: some Widget {
        SitRightQuarterWidget()
    }
}
