import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    @Published private(set) var settings: AppSettings

    @Published var lastErrorMessage: String?

    var onSettingsChanged: (() -> Void)?

    private let defaults: UserDefaults
    private let storageKey = "sitright.settings.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.settings = decoded.normalized()
        } else {
            self.settings = AppSettings()
        }
    }

    func update(_ mutate: (inout AppSettings) -> Void) {
        var copy = settings
        mutate(&copy)
        apply(copy)
    }

    func setError(_ message: String?) {
        lastErrorMessage = message
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func apply(_ newSettings: AppSettings) {
        let normalized = newSettings.normalized()
        guard normalized != settings else { return }

        settings = normalized
        save()
        onSettingsChanged?()
    }
}
