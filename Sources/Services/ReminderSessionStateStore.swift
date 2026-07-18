import AppKit
import Foundation

enum ReminderPauseState: Equatable {
    case none
    case indefinite
    case until(Date)
}

struct ReminderRuntimeCheckpoint: Codable, Equatable {
    var accumulatedEligibleSeconds: TimeInterval
    var opportunityCooldownSeconds: TimeInterval

    static let empty = ReminderRuntimeCheckpoint(
        accumulatedEligibleSeconds: 0,
        opportunityCooldownSeconds: 0
    )
}

struct ReminderSuspensionState: Equatable {
    var startedAt: Date
    var isSleep: Bool
}

@MainActor
final class ReminderSessionStateStore {
    private struct PersistedState: Codable {
        enum Mode: String, Codable {
            case indefinite
            case until
        }

        var mode: Mode?
        var pauseUntil: Date?
        var accumulatedEligibleSeconds: TimeInterval?
        var opportunityCooldownSeconds: TimeInterval?
        var suspensionStartedAt: Date?
        var suspensionIsSleep: Bool?
    }

    private let defaults: UserDefaults
    private let storageKey = "sitright.reminderSession.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(at date: Date = Date()) -> ReminderPauseState {
        guard let data = defaults.data(forKey: storageKey),
              let persisted = try? JSONDecoder().decode(PersistedState.self, from: data) else {
            return .none
        }

        switch persisted.mode {
        case .indefinite:
            return .indefinite
        case .until:
            guard let pauseUntil = persisted.pauseUntil, pauseUntil > date else {
                save(.none)
                return .none
            }
            return .until(pauseUntil)
        case nil:
            return .none
        }
    }

    func save(_ state: ReminderPauseState) {
        var persisted = decodedState() ?? PersistedState(
            mode: nil,
            pauseUntil: nil,
            accumulatedEligibleSeconds: nil,
            opportunityCooldownSeconds: nil,
            suspensionStartedAt: nil,
            suspensionIsSleep: nil
        )

        switch state {
        case .none:
            persisted.mode = nil
            persisted.pauseUntil = nil
            if (persisted.accumulatedEligibleSeconds ?? 0) == 0,
               (persisted.opportunityCooldownSeconds ?? 0) == 0,
               persisted.suspensionStartedAt == nil {
                clear()
                return
            }
        case .indefinite:
            persisted.mode = .indefinite
            persisted.pauseUntil = nil
        case .until(let date):
            persisted.mode = .until
            persisted.pauseUntil = date
        }

        persist(persisted)
    }

    func loadCheckpoint() -> ReminderRuntimeCheckpoint {
        guard let persisted = decodedState() else { return .empty }
        return ReminderRuntimeCheckpoint(
            accumulatedEligibleSeconds: max(persisted.accumulatedEligibleSeconds ?? 0, 0),
            opportunityCooldownSeconds: max(persisted.opportunityCooldownSeconds ?? 0, 0)
        )
    }

    func saveCheckpoint(_ checkpoint: ReminderRuntimeCheckpoint) {
        var persisted = decodedState() ?? PersistedState(
            mode: nil,
            pauseUntil: nil,
            accumulatedEligibleSeconds: nil,
            opportunityCooldownSeconds: nil,
            suspensionStartedAt: nil,
            suspensionIsSleep: nil
        )
        persisted.accumulatedEligibleSeconds = max(checkpoint.accumulatedEligibleSeconds, 0)
        persisted.opportunityCooldownSeconds = max(checkpoint.opportunityCooldownSeconds, 0)
        persist(persisted)
    }

    func resetCheckpoint() {
        saveCheckpoint(.empty)
    }

    func loadSuspension() -> ReminderSuspensionState? {
        guard let persisted = decodedState(),
              let startedAt = persisted.suspensionStartedAt else {
            return nil
        }
        return ReminderSuspensionState(
            startedAt: startedAt,
            isSleep: persisted.suspensionIsSleep ?? false
        )
    }

    func saveSuspension(startedAt: Date, isSleep: Bool) {
        var persisted = decodedState() ?? PersistedState(
            mode: nil,
            pauseUntil: nil,
            accumulatedEligibleSeconds: nil,
            opportunityCooldownSeconds: nil,
            suspensionStartedAt: nil,
            suspensionIsSleep: nil
        )
        persisted.suspensionStartedAt = startedAt
        persisted.suspensionIsSleep = isSleep
        persist(persisted)
    }

    func clearSuspension() {
        guard var persisted = decodedState() else { return }
        persisted.suspensionStartedAt = nil
        persisted.suspensionIsSleep = nil
        if persisted.mode == nil,
           (persisted.accumulatedEligibleSeconds ?? 0) == 0,
           (persisted.opportunityCooldownSeconds ?? 0) == 0 {
            clear()
        } else {
            persist(persisted)
        }
    }

    private func decodedState() -> PersistedState? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(PersistedState.self, from: data)
    }

    private func persist(_ persisted: PersistedState) {
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        defaults.set(data, forKey: storageKey)
    }

    func clear() {
        defaults.removeObject(forKey: storageKey)
    }
}

@MainActor
final class ReminderSystemActivityMonitor {
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []

    init(engine: ReminderEngine) {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor [weak engine] in engine?.systemWillSleep() }
        })
        workspaceObservers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor [weak engine] in engine?.suspensionDidEnd() }
        })
        workspaceObservers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor [weak engine] in engine?.sessionDidBecomeInactive() }
        })
        workspaceObservers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor [weak engine] in engine?.suspensionDidEnd() }
        })

        let distributedCenter = DistributedNotificationCenter.default()
        distributedObservers.append(distributedCenter.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor [weak engine] in engine?.sessionDidBecomeInactive() }
        })
        distributedObservers.append(distributedCenter.addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor [weak engine] in engine?.suspensionDidEnd() }
        })
    }

}
