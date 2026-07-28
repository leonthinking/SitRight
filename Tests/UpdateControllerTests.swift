import Foundation
import Sparkle
import XCTest
@testable import SitRight

final class UpdateControllerTests: XCTestCase {
    private let validPublicKey =
        Data(repeating: 0x2A, count: 32).base64EncodedString()

    func testConfigurationRequiresExactFeedAndEdDSAPublicKey() {
        let valid = configuration()
        XCTAssertTrue(valid.hasValidPublicEDKey)
        XCTAssertTrue(valid.isUpdaterConfigured)
        XCTAssertEqual(
            UpdateConfiguration.scheduledCheckInterval,
            24 * 60 * 60
        )

        XCTAssertFalse(
            configuration(
                feedURL: URL(string: "https://example.com/appcast.xml")
            ).isUpdaterConfigured
        )
        XCTAssertFalse(
            configuration(
                publicKey: UpdateConfiguration.publicKeyPlaceholder
            ).isUpdaterConfigured
        )
        XCTAssertFalse(
            configuration(publicKey: "not-base64").isUpdaterConfigured
        )
        XCTAssertFalse(
            configuration(
                publicKey: Data(repeating: 0, count: 31).base64EncodedString()
            ).isUpdaterConfigured
        )
    }

    @MainActor
    func testControllerStartsOnlyAfterExplicitApplicationLifecycleStart() {
        let controller = UpdateController(
            configuration: configuration(),
            startsUpdater: false
        )

        XCTAssertEqual(controller.state, .idle)
        XCTAssertFalse(controller.canCheckForUpdates)
        XCTAssertTrue(controller.automaticallyChecksForUpdates)
        XCTAssertEqual(controller.currentVersionText, "版本 1.2.3（45）")

        controller.setAutomaticallyChecksForUpdates(false)
        XCTAssertEqual(controller.statusText, "自动检查已关闭")
    }

    @MainActor
    func testControllerTracksUpdateSessionAndGentleReminderStates() {
        let checkDate = Date(timeIntervalSince1970: 1_700_000_000)
        let controller = UpdateController(
            configuration: configuration(),
            startsUpdater: false,
            now: { checkDate }
        )

        controller.recordFoundUpdate(
            version: "1.3.0",
            showsGentleReminder: true
        )
        XCTAssertEqual(controller.state, .available(version: "1.3.0"))
        XCTAssertEqual(controller.availableVersion, "1.3.0")
        XCTAssertEqual(controller.lastCheckDate, checkDate)

        controller.recordUserAttention()
        XCTAssertNil(controller.availableVersion)
        XCTAssertEqual(controller.state, .available(version: "1.3.0"))

        controller.recordDownloadStarted(version: "1.3.0")
        XCTAssertEqual(controller.state, .downloading(version: "1.3.0"))
        XCTAssertNil(controller.availableVersion)

        controller.recordInstallationStarted(version: "1.3.0")
        XCTAssertEqual(controller.state, .installing(version: "1.3.0"))

        controller.recordUpdateFailure()
        XCTAssertEqual(controller.state, .failed)
        XCTAssertEqual(
            controller.state.statusText,
            "更新失败，请稍后重试"
        )

        controller.recordNoUpdateFound()
        XCTAssertEqual(controller.state, .current)
        XCTAssertEqual(controller.state.statusText, "当前已是最新版")
        XCTAssertEqual(
            controller.statusText,
            "当前已是最新版：1.2.3（45）"
        )
        XCTAssertNotNil(controller.lastCheckText)
    }

    @MainActor
    func testPresentingGentleUpdateDoesNotPretendToStartAnotherCheck() {
        let controller = UpdateController(
            configuration: configuration(),
            startsUpdater: false
        )

        controller.recordFoundUpdate(
            version: "1.3.0",
            showsGentleReminder: true
        )
        controller.prepareForUserInitiatedUpdatePresentation()

        XCTAssertEqual(controller.state, .available(version: "1.3.0"))
        XCTAssertEqual(controller.availableVersion, "1.3.0")

        controller.recordUserAttention()
        controller.prepareForUserInitiatedUpdatePresentation()

        XCTAssertEqual(controller.state, .available(version: "1.3.0"))
        XCTAssertNil(controller.availableVersion)

        controller.standardUserDriverWillFinishUpdateSession()

        XCTAssertEqual(controller.state, .idle)
        XCTAssertNil(controller.availableVersion)
    }

    @MainActor
    func testControllerDistinguishesNoUpdateCancellationAndFailure() {
        let checkDate = Date(timeIntervalSince1970: 1_700_000_100)
        let controller = UpdateController(
            configuration: configuration(),
            startsUpdater: false,
            now: { checkDate }
        )

        controller.recordUpdateAbort(
            NSError(
                domain: SUSparkleErrorDomain,
                code: Int(SUError.noUpdateError.rawValue)
            )
        )
        XCTAssertEqual(controller.state, .noCompatibleUpdate)
        XCTAssertEqual(controller.lastCheckDate, checkDate)

        controller.recordFoundUpdate(
            version: "1.3.0",
            showsGentleReminder: true
        )
        controller.recordUpdateAbort(
            NSError(
                domain: SUSparkleErrorDomain,
                code: Int(SUError.installationCanceledError.rawValue)
            )
        )
        XCTAssertEqual(controller.state, .idle)
        XCTAssertNil(controller.availableVersion)

        controller.recordUpdateAbort(
            NSError(
                domain: NSURLErrorDomain,
                code: NSURLErrorNotConnectedToInternet
            )
        )
        XCTAssertEqual(controller.state, .failed)
        XCTAssertEqual(controller.lastCheckDate, checkDate)
    }

    @MainActor
    func testNoUpdateReasonsDistinguishCurrentFromIncompatibleSystem() {
        let controller = UpdateController(
            configuration: configuration(),
            startsUpdater: false
        )

        for reason in [
            SPUNoUpdateFoundReason.onLatestVersion,
            .onNewerThanLatestVersion,
        ] {
            controller.recordNoUpdateFound(
                error: noUpdateError(reason: reason)
            )
            XCTAssertEqual(controller.state, .current)
            XCTAssertTrue(controller.statusText.contains("1.2.3（45）"))
        }

        for reason in [
            SPUNoUpdateFoundReason.systemIsTooOld,
            .systemIsTooNew,
            .hardwareDoesNotSupportARM64,
            .unknown,
        ] {
            controller.recordNoUpdateFound(
                error: noUpdateError(reason: reason)
            )
            XCTAssertEqual(controller.state, .noCompatibleUpdate)
            XCTAssertEqual(
                controller.statusText,
                "未发现适用于此 Mac 的更新"
            )
        }

        controller.prepareForUserInitiatedUpdatePresentation()
        XCTAssertEqual(controller.state, .checking)
    }

    @MainActor
    func testNoUpdateAbortPreservesTheReasonFromSparklesCallbackSequence() {
        let controller = UpdateController(
            configuration: configuration(),
            startsUpdater: false
        )

        let incompatibleError = noUpdateError(reason: .systemIsTooOld)
        controller.recordNoUpdateFound(error: incompatibleError)
        controller.recordUpdateAbort(incompatibleError)
        XCTAssertEqual(controller.state, .noCompatibleUpdate)

        let currentError = noUpdateError(reason: .onLatestVersion)
        controller.recordNoUpdateFound(error: currentError)
        controller.recordUpdateAbort(currentError)
        XCTAssertEqual(controller.state, .current)
    }

    @MainActor
    func testUnavailableControllerDoesNotPretendUpdateCheckingWorks() {
        let controller = UpdateController(
            configuration: configuration(
                publicKey: UpdateConfiguration.publicKeyPlaceholder
            ),
            startsUpdater: false
        )

        XCTAssertFalse(controller.isConfigured)
        XCTAssertEqual(controller.state, .unavailable)
        XCTAssertFalse(controller.canCheckForUpdates)

        controller.checkForUpdates()
        controller.setAutomaticallyChecksForUpdates(false)

        XCTAssertEqual(controller.state, .unavailable)
        XCTAssertTrue(controller.automaticallyChecksForUpdates)
    }

    private func configuration(
        feedURL: URL? = UpdateConfiguration.expectedFeedURL,
        publicKey: String? = nil
    ) -> UpdateConfiguration {
        UpdateConfiguration(
            currentVersion: "1.2.3",
            currentBuild: "45",
            feedURL: feedURL,
            publicEDKey: publicKey ?? validPublicKey
        )
    }

    private func noUpdateError(
        reason: SPUNoUpdateFoundReason
    ) -> NSError {
        NSError(
            domain: SUSparkleErrorDomain,
            code: Int(SUError.noUpdateError.rawValue),
            userInfo: [
                SPUNoUpdateFoundReasonKey: NSNumber(value: reason.rawValue)
            ]
        )
    }
}
