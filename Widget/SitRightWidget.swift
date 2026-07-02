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
        let nextRefresh = Calendar.current.date(
            byAdding: .minute,
            value: 5,
            to: Calendar.current.startOfDay(for: now.addingTimeInterval(24 * 60 * 60))
        ) ?? now.addingTimeInterval(60 * 60)

        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func loadEntry(date: Date) -> SitRightWidgetEntry {
        SitRightWidgetEntry(
            date: date,
            snapshot: WidgetSnapshotStore.load(),
            history: ActivityHistoryStore.load()
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
                Text("\(today.completedCount)/\(dailyTarget)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HeatmapView(history: entry.history, endDate: entry.date, dayCount: 365)
                .frame(maxHeight: .infinity)

            HStack(spacing: 14) {
                summaryPill(title: "本周", value: "\(weekCompletedCount)")
                summaryPill(title: "连续", value: "\(streakDays) 天")
                Spacer(minLength: 0)
                completionButton
            }
        }
        .padding(4)
    }

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                header
                Spacer()
                Text(todayStatusText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                statCard(title: "今日", value: "\(today.completedCount)/\(dailyTarget)", systemImage: "figure.stand")
                statCard(title: "本周", value: "\(weekCompletedCount)", systemImage: "calendar")
                statCard(title: "连续", value: "\(streakDays) 天", systemImage: "flame.fill")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("最近一年")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HeatmapView(history: entry.history, endDate: entry.date, dayCount: 365)
                    .frame(maxHeight: .infinity)
            }

            HStack {
                Spacer(minLength: 0)
                completionButton
            }
        }
        .padding(4)
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "figure.stand")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.green)
            Text("SitRight 坐正")
                .font(.headline)
                .lineLimit(1)
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

    private var completionButton: some View {
        Button(intent: MarkActivityCompleteIntent()) {
            Label("完成", systemImage: "checkmark")
                .font(.caption.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .tint(.green)
        .disabled(!entry.snapshot.allowsWidgetCompletion)
        .opacity(entry.snapshot.allowsWidgetCompletion ? 1 : 0.45)
    }

    private var today: ActivityDay {
        entry.history.day(for: entry.date)
    }

    private var dailyTarget: Int {
        max(entry.snapshot.dailyTarget, 1)
    }

    private var remainingToday: Int {
        max(dailyTarget - today.completedCount, 0)
    }

    private var todayStatusText: String {
        remainingToday == 0 ? "今日目标已完成" : "还差 \(remainingToday) 次"
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
    }

    private func color(for day: ActivityDay?) -> Color {
        guard let day, day.completedCount > 0 else {
            return Color.secondary.opacity(0.14)
        }

        switch day.completedCount {
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
        .description("查看今日完成、年度活动热力图，并快速标记一次活动。")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

@main
struct SitRightWidgetBundle: WidgetBundle {
    var body: some Widget {
        SitRightWidget()
    }
}
