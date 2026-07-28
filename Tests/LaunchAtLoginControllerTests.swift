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
        XCTAssertEqual(controller.recovery, .approvalRequired)

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

    func testNotFoundServiceRetriesRegistrationWhenEnabled() throws {
        let service = LaunchAtLoginServiceStub(status: .notFound)
        let controller = LaunchAtLoginController(service: service)

        try controller.setEnabled(true)

        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(controller.status, .enabled)
        XCTAssertNil(controller.issue)
        XCTAssertTrue(controller.isRegistered)
    }

    func testNotFoundRegistrationFailureKeepsRecoverableIssue() {
        let service = LaunchAtLoginServiceStub(
            status: .notFound,
            registerError: TestError.registrationFailed
        )
        let controller = LaunchAtLoginController(service: service)

        XCTAssertThrowsError(try controller.setEnabled(true))

        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(controller.status, .notFound)
        XCTAssertEqual(controller.issue, .operationFailed)
        XCTAssertEqual(controller.recovery, .operationFailed)
        XCTAssertFalse(controller.isRegistered)
    }

    func testRegistrationFailureRemainsRecoverableWhenStatusIsNotRegistered() {
        let service = LaunchAtLoginServiceStub(
            status: .notRegistered,
            registerError: TestError.registrationFailed
        )
        let controller = LaunchAtLoginController(service: service)

        XCTAssertThrowsError(try controller.setEnabled(true))

        XCTAssertEqual(controller.status, .notRegistered)
        XCTAssertEqual(controller.issue, .operationFailed)
        XCTAssertEqual(controller.recovery, .operationFailed)
    }

    func testUnregisterFailureRemainsRecoverableWhenStatusIsEnabled() {
        let service = LaunchAtLoginServiceStub(
            status: .enabled,
            unregisterError: TestError.registrationFailed
        )
        let controller = LaunchAtLoginController(service: service)

        XCTAssertThrowsError(try controller.setEnabled(false))

        XCTAssertEqual(controller.status, .enabled)
        XCTAssertEqual(controller.issue, .operationFailed)
        XCTAssertEqual(controller.recovery, .operationFailed)
    }

    func testRetryStatusDetectionClearsNotFoundIssueAfterSystemRecovers() {
        let service = LaunchAtLoginServiceStub(status: .notFound)
        let controller = LaunchAtLoginController(service: service)
        XCTAssertEqual(controller.issue, .serviceNotFound)

        service.status = .notRegistered
        controller.retryStatusDetection()

        XCTAssertEqual(controller.status, .notRegistered)
        XCTAssertNil(controller.issue)
        XCTAssertEqual(controller.recovery, .none)
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
    private let registerError: Error?
    private let unregisterError: Error?

    init(
        status: LaunchAtLoginStatus,
        registerError: Error? = nil,
        unregisterError: Error? = nil
    ) {
        self.status = status
        self.registerError = registerError
        self.unregisterError = unregisterError
    }

    func register() throws {
        registerCallCount += 1
        if let registerError {
            throw registerError
        }
        status = .enabled
    }

    func unregister() throws {
        unregisterCallCount += 1
        if let unregisterError {
            throw unregisterError
        }
        status = .notRegistered
    }

    func openSystemSettingsLoginItems() {
        openSettingsCallCount += 1
    }
}

private enum TestError: Error {
    case registrationFailed
}
