import Foundation

enum HeatmapIntensity: Int, CaseIterable, Equatable {
    case low
    case medium
    case high
    case complete
}

enum HeatmapCellState: Equatable {
    case padding
    case inactive
    case neutral
    case activity(HeatmapIntensity)
}

struct HeatmapCell: Equatable {
    let date: Date?
    let state: HeatmapCellState
    let isToday: Bool
}

struct HeatmapWeek: Equatable {
    let cells: [HeatmapCell]
}

struct HeatmapMonthMarker: Equatable {
    let columnIndex: Int
    let title: String
}

struct HeatmapMonthLabelPlacement: Equatable {
    let columnIndex: Int
    let title: String
    let xOffset: CGFloat
}

struct HeatmapSummary: Equatable {
    let activityTotal: Int
    let activeDays: Int
    let completedDays: Int
}

struct HeatmapPresentation: Equatable {
    let weeks: [HeatmapWeek]
    let monthMarkers: [HeatmapMonthMarker]
    let summary: HeatmapSummary

    init(
        history: ActivityHistory,
        endDate: Date,
        dayCount: Int,
        calendar: Calendar = .current
    ) {
        guard dayCount > 0 else {
            weeks = []
            monthMarkers = []
            summary = HeatmapSummary(activityTotal: 0, activeDays: 0, completedDays: 0)
            return
        }

        let end = calendar.startOfDay(for: endDate)
        guard let start = calendar.date(byAdding: .day, value: -(dayCount - 1), to: end) else {
            weeks = []
            monthMarkers = []
            summary = HeatmapSummary(activityTotal: 0, activeDays: 0, completedDays: 0)
            return
        }

        let leadingPadding = Self.weekdayOffset(for: start, calendar: calendar)
        var cells = Array(
            repeating: HeatmapCell(date: nil, state: .padding, isToday: false),
            count: leadingPadding
        )
        var activityTotal = 0
        var activeDays = 0
        var completedDays = 0
        var markerCandidates: [(marker: HeatmapMonthMarker, visibleDays: Int)] = [(
            marker: HeatmapMonthMarker(
                columnIndex: 0,
                title: Self.monthTitle(for: start, calendar: calendar)
            ),
            visibleDays: min(Self.visibleDaysInStartMonth(start, calendar: calendar), dayCount)
        )]
        var lastMarkedMonth = calendar.dateComponents([.year, .month], from: start)

        for offset in 0..<dayCount {
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let day = history.day(for: date, calendar: calendar)
            let activityCount = max(day.qualifiedActivityCount, 0)
            let state = Self.cellState(for: day)
            cells.append(HeatmapCell(
                date: date,
                state: state,
                isToday: calendar.isDate(date, inSameDayAs: end)
            ))

            activityTotal += activityCount
            if activityCount > 0 {
                activeDays += 1
                if let target = day.dailyTargetSnapshot,
                   target > 0,
                   activityCount >= target {
                    completedDays += 1
                }
            }

            let components = calendar.dateComponents([.year, .month, .day], from: date)
            if components.day == 1,
               components.year != lastMarkedMonth.year || components.month != lastMarkedMonth.month {
                let candidate = (
                    marker: HeatmapMonthMarker(
                        columnIndex: (leadingPadding + offset) / 7,
                        title: Self.monthTitle(for: date, calendar: calendar)
                    ),
                    visibleDays: min(Self.daysInMonth(date, calendar: calendar), dayCount - offset)
                )
                if let last = markerCandidates.last,
                   last.marker.columnIndex == candidate.marker.columnIndex {
                    if candidate.visibleDays > last.visibleDays {
                        markerCandidates[markerCandidates.count - 1] = candidate
                    }
                } else {
                    markerCandidates.append(candidate)
                }
                lastMarkedMonth = components
            }
        }

        let markers = markerCandidates.map(\.marker)

        let trailingPadding = (7 - cells.count % 7) % 7
        cells.append(contentsOf: Array(
            repeating: HeatmapCell(date: nil, state: .padding, isToday: false),
            count: trailingPadding
        ))

        weeks = stride(from: 0, to: cells.count, by: 7).map { startIndex in
            HeatmapWeek(cells: Array(cells[startIndex..<(startIndex + 7)]))
        }
        monthMarkers = markers
        summary = HeatmapSummary(
            activityTotal: activityTotal,
            activeDays: activeDays,
            completedDays: completedDays
        )
    }

    static func monthLabelPlacements(
        for markers: [HeatmapMonthMarker],
        originX: CGFloat,
        step: CGFloat,
        availableWidth: CGFloat,
        labelWidth: CGFloat
    ) -> [HeatmapMonthLabelPlacement] {
        guard !markers.isEmpty else { return [] }

        let maximumX = max(availableWidth - labelWidth, 0)
        var offsets = markers.map { marker in
            min(max(originX + CGFloat(marker.columnIndex) * step, 0), maximumX)
        }

        // Month anchors near the trailing edge can be closer than the label width.
        // Resolve collisions from right to left so the final label remains visible,
        // then translate the group back on-screen when there is enough total room.
        if offsets.count > 1, labelWidth > 0 {
            for index in stride(from: offsets.count - 2, through: 0, by: -1) {
                offsets[index] = min(offsets[index], offsets[index + 1] - labelWidth)
            }

            if let first = offsets.first, first < 0,
               CGFloat(offsets.count) * labelWidth <= availableWidth {
                let translation = -first
                offsets = offsets.map { $0 + translation }
            }
        }

        return zip(markers, offsets).map { marker, xOffset in
            HeatmapMonthLabelPlacement(
                columnIndex: marker.columnIndex,
                title: marker.title,
                xOffset: xOffset
            )
        }
    }

    static func cellState(for day: ActivityDay) -> HeatmapCellState {
        let count = max(day.qualifiedActivityCount, 0)
        guard count > 0 else {
            switch day.eligibilitySnapshot {
            case .paused, .nonWorkday:
                return .neutral
            case .scheduled, .none:
                return .inactive
            }
        }

        guard let target = day.dailyTargetSnapshot, target > 0 else {
            return .activity(.low)
        }

        switch Double(count) / Double(target) {
        case 1...:
            return .activity(.complete)
        case 0.5...:
            return .activity(.high)
        case 0.25...:
            return .activity(.medium)
        default:
            return .activity(.low)
        }
    }

    private static func weekdayOffset(for date: Date, calendar: Calendar) -> Int {
        (calendar.component(.weekday, from: date) - calendar.firstWeekday + 7) % 7
    }

    private static func visibleDaysInStartMonth(_ date: Date, calendar: Calendar) -> Int {
        guard let dayRange = calendar.range(of: .day, in: .month, for: date) else { return 1 }
        return max(dayRange.count - calendar.component(.day, from: date) + 1, 1)
    }

    private static func daysInMonth(_ date: Date, calendar: Calendar) -> Int {
        calendar.range(of: .day, in: .month, for: date)?.count ?? 1
    }

    private static func monthTitle(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return formatter.string(from: date)
    }
}
