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

enum LaunchAtLoginIssue: Equatable {
    case serviceNotFound
    case operationFailed

    func userMessage(language: AppLanguage = .simplifiedChinese) -> String {
        switch self {
        case .serviceNotFound:
            return language.text(
                "macOS 暂时未能识别 SitRight 登录项",
                "macOS cannot currently recognize the SitRight login item"
            )
        case .operationFailed:
            return language.text(
                "macOS 未能更改登录项，请在系统设置中检查后重试",
                "macOS could not change the login item. Check System Settings and try again."
            )
        }
    }

    var userMessage: String {
        userMessage()
    }
}

enum LaunchAtLoginRecovery: Equatable {
    case none
    case approvalRequired
    case serviceNotFound
    case operationFailed
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
    @Published private(set) var issue: LaunchAtLoginIssue?

    private let service: any LaunchAtLoginService

    init(service: any LaunchAtLoginService = SystemLaunchAtLoginService()) {
        self.service = service
        self.status = service.status
        self.issue = status == .notFound ? .serviceNotFound : nil
    }

    var isRegistered: Bool {
        status == .enabled || status == .requiresApproval
    }

    var recovery: LaunchAtLoginRecovery {
        if issue == .operationFailed {
            return .operationFailed
        }
        switch status {
        case .requiresApproval:
            return .approvalRequired
        case .notFound:
            return .serviceNotFound
        case .notRegistered, .enabled:
            return .none
        }
    }

    func refreshStatus() {
        status = service.status
        if status == .notFound {
            issue = .serviceNotFound
        } else {
            issue = nil
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        do {
            switch (enabled, status) {
            case (true, .notRegistered), (true, .notFound):
                try service.register()
            case (false, .enabled), (false, .requiresApproval):
                try service.unregister()
            case (true, .enabled), (true, .requiresApproval),
                 (false, .notRegistered), (false, .notFound):
                break
            }
        } catch {
            status = service.status
            issue = .operationFailed
            throw error
        }
        refreshStatus()
    }

    func retryStatusDetection() {
        refreshStatus()
    }

    func openSystemSettingsLoginItems() {
        service.openSystemSettingsLoginItems()
    }
}
