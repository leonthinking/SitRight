import Foundation

@MainActor
final class StatsStore: ObservableObject {
    @Published private(set) var today: DailyStats

    private let defaults: UserDefaults
    private let storageKey = "sitright.dailyStats.v1"
    private let historyStorageDirectory: URL?
    private var history: ActivityHistory

    init(defaults: UserDefaults = .standard, historyStorageDirectory: URL? = nil) {
        self.defaults = defaults
        self.historyStorageDirectory = historyStorageDirectory

        var history = ActivityHistoryStore.load(storageDirectory: historyStorageDirectory)
        if history.isEmpty,
           let legacyToday = Self.loadLegacyToday(from: defaults) {
            history.upsert(legacyToday)
            ActivityHistoryStore.save(history, storageDirectory: historyStorageDirectory)
        }

        self.history = history
        let currentDay = history.day(for: Date())
        if currentDay.dateKey == DailyStats.makeDateKey(for: Date()) {
            self.today = currentDay
        } else {
            self.today = DailyStats()
        }
    }

    func refreshForCurrentDay() {
        history = ActivityHistoryStore.load(storageDirectory: historyStorageDirectory)
        let currentKey = DailyStats.makeDateKey(for: Date())
        let currentDay = history.day(for: Date())
        guard today != currentDay || today.dateKey != currentKey else { return }
        today = currentDay
        saveLegacyToday()
    }

    func markCompleted() {
        refreshForCurrentDay()
        today = history.recordCompleted()
        save()
    }

    func markPostponed() {
        refreshForCurrentDay()
        today = history.recordPostponed()
        save()
    }

    func markSkipped() {
        refreshForCurrentDay()
        today = history.recordSkipped()
        save()
    }

    var lastCompletedText: String {
        guard let date = today.lastCompletedAt else { return "今天还没有完成活动" }
        return "上次完成 \(date.formatted(date: .omitted, time: .shortened))"
    }

    private func save() {
        ActivityHistoryStore.save(history, storageDirectory: historyStorageDirectory)
        saveLegacyToday()
    }

    private func saveLegacyToday() {
        guard let data = try? JSONEncoder().encode(today) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private static func loadLegacyToday(from defaults: UserDefaults) -> DailyStats? {
        guard let data = defaults.data(forKey: "sitright.dailyStats.v1"),
              let decoded = try? JSONDecoder().decode(DailyStats.self, from: data),
              decoded.dateKey == DailyStats.makeDateKey(for: Date()) else {
            return nil
        }

        return decoded
    }
}
