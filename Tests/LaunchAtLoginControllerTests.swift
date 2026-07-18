import ServiceManagement
import XCTest
@testable import SitRight

@MainActor
final class LaunchAtLoginControllerTests: XCTestCase {
    func testSystemStatusesMapToFourStateModel() {
        XCTAssertEqual(LaunchAtLoginStatus(.notRegistered), .notRegistered)
        XCTAssertEqual(LaunchAtLoginStatus(.enabled), .enabled)
        XCTAssertEqual(LaunchAtLoginStatus(.requiresApproval), .requiresApproval)
        XCTAssertEqual(LaunchAtLoginStatus(.notFound), .notFound)
    }

    func testRequiresApprovalCountsAsRegisteredAndCanBeDisabled() throws {
        let service = LaunchAtLoginServiceStub(status: .requiresApproval)
        let controller = LaunchAtLoginController(service: service)

        XCTAssertTrue(controller.isRegistered)

        try controller.setEnabled(false)

        XCTAssertEqual(service.unregisterCallCount, 1)
        XCTAssertEqual(controller.status, .notRegistered)
        XCTAssertFalse(controller.isRegistered)
    }

    func testEnablingNotRegisteredServiceRegistersOnce() throws {
        let service = LaunchAtLoginServiceStub(status: .notRegistered)
        let controller = LaunchAtLoginController(service: service)

        try controller.setEnabled(true)
        try controller.setEnabled(true)

        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(controller.status, .enabled)
        XCTAssertTrue(controller.isRegistered)
    }

    func testEnabledServiceCanBeDisabled() throws {
        let service = LaunchAtLoginServiceStub(status: .enabled)
        let controller = LaunchAtLoginController(service: service)

        try controller.setEnabled(false)

        XCTAssertEqual(service.unregisterCallCount, 1)
        XCTAssertEqual(controller.status, .notRegistered)
        XCTAssertFalse(controller.isRegistered)
    }

    func testNotFoundServiceCannotBeEnabledOrDisabled() throws {
        let service = LaunchAtLoginServiceStub(status: .notFound)
        let controller = LaunchAtLoginController(service: service)

        try controller.setEnabled(true)
        try controller.setEnabled(false)

        XCTAssertEqual(service.registerCallCount, 0)
        XCTAssertEqual(service.unregisterCallCount, 0)
        XCTAssertEqual(controller.status, .notFound)
        XCTAssertFalse(controller.isRegistered)
    }

    func testOpenSystemSettingsDelegatesToService() {
        let service = LaunchAtLoginServiceStub(status: .requiresApproval)
        let controller = LaunchAtLoginController(service: service)

        controller.openSystemSettingsLoginItems()

        XCTAssertEqual(service.openSettingsCallCount, 1)
    }
}

@MainActor
private final class LaunchAtLoginServiceStub: LaunchAtLoginService {
    var status: LaunchAtLoginStatus
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0
    private(set) var openSettingsCallCount = 0

    init(status: LaunchAtLoginStatus) {
        self.status = status
    }

    func register() throws {
        registerCallCount += 1
        status = .enabled
    }

    func unregister() throws {
        unregisterCallCount += 1
        status = .notRegistered
    }

    func openSystemSettingsLoginItems() {
        openSettingsCallCount += 1
    }
}
