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

        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
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
    @Environment(\.widgetFamily) private var family

    let entry: SitRightWidgetEntry

    var body: some View {
        switch family {
        case .systemMedium:
            mediumView
                .containerBackground(.background, for: .widget)
        case .systemLarge:
            largeView
                .containerBackground(.background, for: .widget)
        default:
            mediumView
                .containerBackground(.background, for: .widget)
        }
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                header
                Spacer()
                Text("\(today.dailyGoalActivityCount)/\(dailyTarget)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            statusSummary

            HeatmapView(history: entry.history, endDate: entry.date, dayCount: 365)
                .frame(maxHeight: .infinity)

            HStack(spacing: 12) {
                summaryPill(title: "提醒后", value: "\(today.reminderCompletedCount)")
                summaryPill(title: "主动", value: "\(today.qualifiedProactiveCount)")
                summaryPill(title: "本周", value: "\(weekCompletedCount)")
                summaryPill(title: "连续", value: "\(streakDays) 天")
                Spacer(minLength: 0)
            }
        }
        .padding(4)
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
                Text("最近一年")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HeatmapView(history: entry.history, endDate: entry.date, dayCount: 365)
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
            if let guideEndsAt = entry.snapshot.guideEndsAt {
                return "活动进行中，还剩 \(max(Int(ceil(guideEndsAt.timeIntervalSince(entry.date))), 0)) 秒"
            }
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

    private func summaryPill(title: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .font(.caption)
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

    private var responsePercentageText: String {
        guard let responseRate = today.responseRate else { return "暂无" }
        return "\(Int((responseRate * 100).rounded()))%"
    }

    private var responseOpportunityText: String {
        guard today.reminderOpportunityCount > 0 else { return "暂无提醒" }
        return "响应 \(today.reminderCompletedCount)/\(today.reminderOpportunityCount)"
    }

    private var weekCompletedCount: Int {
        entry.history.completedCountInCurrentWeek(endingAt: entry.date)
    }

    private var streakDays: Int {
        entry.history.currentStreak(endingAt: entry.date)
    }
}

struct HeatmapView: View {
    let history: ActivityHistory
    let endDate: Date
    let dayCount: Int

    private let gap: CGFloat = 2
    private let calendar = Calendar.current

    var body: some View {
        GeometryReader { proxy in
            let weeks = heatmapWeeks
            let cellSize = max(
                min(
                    (proxy.size.width - CGFloat(max(weeks.count - 1, 0)) * gap) / CGFloat(max(weeks.count, 1)),
                    (proxy.size.height - 6 * gap) / 7
                ),
                2
            )
            let totalWidth = CGFloat(weeks.count) * cellSize + CGFloat(max(weeks.count - 1, 0)) * gap
            let totalHeight = 7 * cellSize + 6 * gap

            Canvas { context, size in
                let originX = max((size.width - totalWidth) / 2, 0)
                let originY = max((size.height - totalHeight) / 2, 0)
                let cornerRadius = min(cellSize / 2, 2)

                for weekIndex in weeks.indices {
                    for dayIndex in 0..<7 {
                        let rect = CGRect(
                            x: originX + CGFloat(weekIndex) * (cellSize + gap),
                            y: originY + CGFloat(dayIndex) * (cellSize + gap),
                            width: cellSize,
                            height: cellSize
                        )
                        let path = Path(roundedRect: rect, cornerRadius: cornerRadius)
                        context.fill(path, with: .color(color(for: weeks[weekIndex][dayIndex])))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("活动热力图")
        .accessibilityValue("最近 \(dayCount) 天完成 \(completedTotal) 次活动")
    }

    private func color(for day: ActivityDay?) -> Color {
        guard let day, day.qualifiedActivityCount > 0 else {
            return Color.secondary.opacity(0.14)
        }

        switch day.qualifiedActivityCount {
        case 1:
            return Color.green.opacity(0.35)
        case 2...3:
            return Color.green.opacity(0.55)
        case 4...5:
            return Color.green.opacity(0.76)
        default:
            return Color.green
        }
    }

    private var heatmapWeeks: [[ActivityDay?]] {
        let end = calendar.startOfDay(for: endDate)
        guard let start = calendar.date(byAdding: .day, value: -(dayCount - 1), to: end) else {
            return []
        }

        let leadingEmptyCount = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        var cells = Array<ActivityDay?>(repeating: nil, count: leadingEmptyCount)
        cells.append(contentsOf: history.days(endingAt: end, count: dayCount, calendar: calendar).map(Optional.some))

        let trailingEmptyCount = (7 - cells.count % 7) % 7
        cells.append(contentsOf: Array<ActivityDay?>(repeating: nil, count: trailingEmptyCount))

        return stride(from: 0, to: cells.count, by: 7).map { startIndex in
            var week = Array(cells[startIndex..<min(startIndex + 7, cells.count)])
            if week.count < 7 {
                week.append(contentsOf: Array<ActivityDay?>(repeating: nil, count: 7 - week.count))
            }
            return week
        }
    }

    private var completedTotal: Int {
        history.days(endingAt: endDate, count: dayCount, calendar: calendar)
            .reduce(0) { $0 + $1.qualifiedActivityCount }
    }
}

private extension ActivityHistory {
    static var preview: ActivityHistory {
        var history = ActivityHistory()
        let calendar = Calendar.current
        let today = Date()

        for offset in 0..<365 {
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
            history.upsert(day)
        }

        return history
    }
}

struct SitRightWidget: Widget {
    let kind = SitRightWidgetKind.activity

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SitRightWidgetProvider()) { entry in
            SitRightWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("SitRight 坐正")
        .description("查看今日活动目标、提醒后活动、主动活动、本周统计和年度活动热力图。")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

@main
struct SitRightWidgetBundle: WidgetBundle {
    var body: some Widget {
        SitRightWidget()
    }
}
