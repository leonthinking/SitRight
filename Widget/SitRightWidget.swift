import SwiftUI
import WidgetKit

struct SitRightWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> SitRightWidgetEntry {
        SitRightWidgetEntry(date: Date(), snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (SitRightWidgetEntry) -> Void) {
        completion(SitRightWidgetEntry(date: Date(), snapshot: WidgetSnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SitRightWidgetEntry>) -> Void) {
        let snapshot = WidgetSnapshotStore.load()
        let now = Date()
        let entries = makeEntries(from: now, snapshot: snapshot)
        let nextRefresh = snapshot.nextReminderAt.map { max($0, now.addingTimeInterval(60)) }
            ?? now.addingTimeInterval(15 * 60)

        completion(Timeline(entries: entries, policy: .after(nextRefresh)))
    }

    private func makeEntries(from now: Date, snapshot: WidgetSnapshot) -> [SitRightWidgetEntry] {
        guard snapshot.state == .running,
              let nextReminderAt = snapshot.nextReminderAt,
              nextReminderAt > now else {
            return [SitRightWidgetEntry(date: now, snapshot: snapshot)]
        }

        let maxEntries = 12
        let minuteCount = min(max(Int(nextReminderAt.timeIntervalSince(now) / 60), 1), maxEntries)
        return (0...minuteCount).compactMap { minuteOffset in
            Calendar.current.date(byAdding: .minute, value: minuteOffset, to: now).map {
                SitRightWidgetEntry(date: $0, snapshot: snapshot)
            }
        }
    }
}

struct SitRightWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct SitRightWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family

    let entry: SitRightWidgetEntry

    var body: some View {
        switch family {
        case .systemMedium:
            mediumView
                .containerBackground(.background, for: .widget)
        default:
            smallView
                .containerBackground(.background, for: .widget)
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Spacer(minLength: 0)

            Text(countdownText)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.72)
                .lineLimit(1)

            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: entry.snapshot.completionProgress)
                    .tint(.green)
                Text("今日 \(entry.snapshot.completedCount)/\(entry.snapshot.dailyTarget)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(4)
    }

    private var mediumView: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(.secondary.opacity(0.18), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: entry.snapshot.progress(at: entry.date))
                    .stroke(ringColor.gradient, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 4) {
                    Image(systemName: iconName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(ringColor)
                    Text(countdownText)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
                .padding(12)
            }
            .frame(width: 110, height: 110)

            VStack(alignment: .leading, spacing: 10) {
                header

                Text(entry.snapshot.statusText)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("今日活动")
                        Spacer()
                        Text("\(entry.snapshot.completedCount)/\(entry.snapshot.dailyTarget)")
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    ProgressView(value: entry.snapshot.completionProgress)
                        .tint(.green)
                }

                Spacer(minLength: 0)
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

    private var countdownText: String {
        switch entry.snapshot.state {
        case .running:
            guard let nextReminderAt = entry.snapshot.nextReminderAt else { return "--" }
            let remaining = max(Int(nextReminderAt.timeIntervalSince(entry.date)), 0)
            let minutes = Int(ceil(Double(remaining) / 60.0))
            if minutes < 60 { return "\(minutes)m" }
            return "\(minutes / 60)h \(minutes % 60)m"
        case .paused:
            return "暂停"
        case .outsideHours:
            return "休息"
        case .disabled:
            return "关闭"
        case .due:
            return "活动"
        }
    }

    private var ringColor: Color {
        switch entry.snapshot.state {
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

    private var iconName: String {
        switch entry.snapshot.state {
        case .running:
            return "timer"
        case .paused:
            return "pause.circle.fill"
        case .outsideHours:
            return "moon.fill"
        case .disabled:
            return "power.circle.fill"
        case .due:
            return "figure.walk.circle.fill"
        }
    }
}

struct SitRightWidget: Widget {
    let kind = "SitRightWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SitRightWidgetProvider()) { entry in
            SitRightWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("SitRight 坐正")
        .description("查看下次久坐提醒和今日活动进度。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct SitRightWidgetBundle: WidgetBundle {
    var body: some Widget {
        SitRightWidget()
    }
}
