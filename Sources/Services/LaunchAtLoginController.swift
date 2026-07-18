import Foundation
import ServiceManagement

enum LaunchAtLoginStatus: Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound

    init(_ status: SMAppService.Status) {
        switch status {
        case .notRegistered:
            self = .notRegistered
        case .enabled:
            self = .enabled
        case .requiresApproval:
            self = .requiresApproval
        case .notFound:
            self = .notFound
        @unknown default:
            self = .notFound
        }
    }
}

@MainActor
protocol LaunchAtLoginService: AnyObject {
    var status: LaunchAtLoginStatus { get }
    func register() throws
    func unregister() throws
    func openSystemSettingsLoginItems()
}

@MainActor
final class SystemLaunchAtLoginService: LaunchAtLoginService {
    var status: LaunchAtLoginStatus {
        LaunchAtLoginStatus(SMAppService.mainApp.status)
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }

    func openSystemSettingsLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

@MainActor
final class LaunchAtLoginController: ObservableObject {
    @Published private(set) var status: LaunchAtLoginStatus

    private let service: any LaunchAtLoginService

    init(service: any LaunchAtLoginService = SystemLaunchAtLoginService()) {
        self.service = service
        self.status = service.status
    }

    var isRegistered: Bool {
        status == .enabled || status == .requiresApproval
    }

    func refreshStatus() {
        status = service.status
    }

    func setEnabled(_ enabled: Bool) throws {
        defer { refreshStatus() }

        switch (enabled, status) {
        case (true, .notRegistered):
            try service.register()
        case (false, .enabled), (false, .requiresApproval):
            try service.unregister()
        case (true, .enabled), (true, .requiresApproval),
             (true, .notFound), (false, .notRegistered), (false, .notFound):
            break
        }
    }

    func openSystemSettingsLoginItems() {
        service.openSystemSettingsLoginItems()
    }
}
