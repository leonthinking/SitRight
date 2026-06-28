import Foundation

@MainActor
final class StatsStore: ObservableObject {
    @Published private(set) var today: DailyStats

    private let defaults: UserDefaults
    private let storageKey = "sitright.dailyStats.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(DailyStats.self, from: data),
           decoded.dateKey == DailyStats.makeDateKey(for: Date()) {
            self.today = decoded
        } else {
            self.today = DailyStats()
        }
    }

    func refreshForCurrentDay() {
        let currentKey = DailyStats.makeDateKey(for: Date())
        guard today.dateKey != currentKey else { return }
        today = DailyStats(dateKey: currentKey)
        save()
    }

    func markCompleted() {
        refreshForCurrentDay()
        today.completedCount += 1
        today.lastCompletedAt = Date()
        save()
    }

    func markPostponed() {
        refreshForCurrentDay()
        today.postponedCount += 1
        save()
    }

    func markSkipped() {
        refreshForCurrentDay()
        today.skippedCount += 1
        save()
    }

    var lastCompletedText: String {
        guard let date = today.lastCompletedAt else { return "今天还没有完成活动" }
        return "上次完成 \(date.formatted(date: .omitted, time: .shortened))"
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(today) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
