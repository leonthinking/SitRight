import Combine
import Foundation
@preconcurrency import Sparkle

struct UpdateConfiguration: Equatable {
    static let expectedFeedURL = URL(
        string: "https://github.com/leonthinking/SitRight/releases/latest/download/appcast.xml"
    )!
    static let releasesURL = CommunityLinks.releasesURL
    static let publicKeyPlaceholder =
        "REPLACE_WITH_SPARKLE_ED25519_PUBLIC_KEY"
    static let scheduledCheckInterval: TimeInterval = 24 * 60 * 60

    let currentVersion: String
    let currentBuild: String
    let feedURL: URL?
    let publicEDKey: String

    init(infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
        currentVersion =
            infoDictionary["CFBundleShortVersionString"] as? String ??
            "开发版"
        currentBuild =
            infoDictionary["CFBundleVersion"] as? String ??
            "—"
        if let rawFeedURL = infoDictionary["SUFeedURL"] as? String {
            feedURL = URL(string: rawFeedURL)
        } else {
            feedURL = nil
        }
        publicEDKey = infoDictionary["SUPublicEDKey"] as? String ?? ""
    }

    init(
        currentVersion: String,
        currentBuild: String,
        feedURL: URL?,
        publicEDKey: String
    ) {
        self.currentVersion = currentVersion
        self.currentBuild = currentBuild
        self.feedURL = feedURL
        self.publicEDKey = publicEDKey
    }

    var hasValidPublicEDKey: Bool {
        guard publicEDKey != Self.publicKeyPlaceholder,
              let decodedKey = Data(base64Encoded: publicEDKey) else {
            return false
        }
        return decodedKey.count == 32
    }

    var isUpdaterConfigured: Bool {
        feedURL == Self.expectedFeedURL && hasValidPublicEDKey
    }
}

enum UpdatePresentationState: Equatable {
    case unavailable
    case idle
    case checking
    case current
    case noCompatibleUpdate
    case available(version: String)
    case downloading(version: String)
    case installing(version: String)
    case failed

    var statusText: String {
        switch self {
        case .unavailable:
            return "发布密钥尚未配置"
        case .idle:
            return "每天自动检查一次"
        case .checking:
            return "正在检查更新…"
        case .current:
            return "当前已是最新版"
        case .noCompatibleUpdate:
            return "未发现适用于此 Mac 的更新"
        case .available(let version):
            return "发现 SitRight v\(version)"
        case .downloading(let version):
            return "正在下载 SitRight v\(version)…"
        case .installing(let version):
            return "正在安装 SitRight v\(version)…"
        case .failed:
            return "更新失败，请稍后重试"
        }
    }

    var systemImage: String {
        switch self {
        case .unavailable:
            return "exclamationmark.shield"
        case .idle:
            return "clock.arrow.circlepath"
        case .checking, .downloading:
            return "arrow.triangle.2.circlepath"
        case .current:
            return "checkmark.circle.fill"
        case .noCompatibleUpdate:
            return "desktopcomputer.trianglebadge.exclamationmark"
        case .available:
            return "arrow.down.circle.fill"
        case .installing:
            return "shippingbox.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }
}

@MainActor
final class UpdateController: NSObject, ObservableObject {
    let configuration: UpdateConfiguration

    @Published private(set) var state: UpdatePresentationState
    @Published private(set) var availableVersion: String?
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = true
    @Published private(set) var lastCheckDate: Date?

    var onModalAlertWillPresent: (() -> Void)?
    var onModalAlertDidFinish: (() -> Void)?

    private var standardUpdaterController: SPUStandardUpdaterController?
    private var cancellables = Set<AnyCancellable>()
    private let now: () -> Date

    init(
        configuration: UpdateConfiguration = UpdateConfiguration(),
        startsUpdater: Bool = true,
        now: @escaping () -> Date = Date.init
    ) {
        self.configuration = configuration
        self.state = configuration.isUpdaterConfigured ? .idle : .unavailable
        self.now = now
        super.init()

        guard configuration.isUpdaterConfigured else { return }
        if startsUpdater {
            start()
        }
    }

    func start() {
        guard configuration.isUpdaterConfigured,
              standardUpdaterController == nil else {
            return
        }

        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )
        standardUpdaterController = controller
        canCheckForUpdates = controller.updater.canCheckForUpdates
        automaticallyChecksForUpdates =
            controller.updater.automaticallyChecksForUpdates
        lastCheckDate = controller.updater.lastUpdateCheckDate

        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.canCheckForUpdates = value
            }
            .store(in: &cancellables)
    }

    var currentVersionText: String {
        "版本 \(configuration.currentVersion)（\(configuration.currentBuild)）"
    }

    var statusText: String {
        if state == .idle && !automaticallyChecksForUpdates {
            return "自动检查已关闭"
        }
        if state == .current {
            return "当前已是最新版：\(configuration.currentVersion)（\(configuration.currentBuild)）"
        }
        return state.statusText
    }

    var lastCheckText: String? {
        guard let lastCheckDate else { return nil }
        return "最近检查：\(lastCheckDate.formatted(date: .omitted, time: .shortened))"
    }

    var isConfigured: Bool {
        configuration.isUpdaterConfigured
    }

    func setAutomaticallyChecksForUpdates(_ isEnabled: Bool) {
        guard configuration.isUpdaterConfigured else { return }
        automaticallyChecksForUpdates = isEnabled
        standardUpdaterController?.updater.automaticallyChecksForUpdates =
            isEnabled
    }

    func checkForUpdates() {
        guard configuration.isUpdaterConfigured,
              canCheckForUpdates else {
            return
        }
        prepareForUserInitiatedUpdatePresentation()
        standardUpdaterController?.checkForUpdates(nil)
    }

    func prepareForUserInitiatedUpdatePresentation() {
        switch state {
        case .idle, .current, .noCompatibleUpdate, .failed:
            state = .checking
        case .unavailable, .checking, .available, .downloading, .installing:
            break
        }
    }

    func recordFoundUpdate(version: String, showsGentleReminder: Bool) {
        lastCheckDate = now()
        state = .available(version: version)
        availableVersion = showsGentleReminder ? version : nil
    }

    func recordNoUpdateFound() {
        lastCheckDate = now()
        state = .current
        availableVersion = nil
    }

    func recordNoUpdateFound(error: NSError) {
        lastCheckDate = now()
        availableVersion = nil

        let rawReason = (error.userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber)?
            .intValue
        switch rawReason {
        case Int(SPUNoUpdateFoundReason.onLatestVersion.rawValue),
             Int(SPUNoUpdateFoundReason.onNewerThanLatestVersion.rawValue):
            state = .current
        case Int(SPUNoUpdateFoundReason.systemIsTooOld.rawValue),
             Int(SPUNoUpdateFoundReason.systemIsTooNew.rawValue),
             Int(SPUNoUpdateFoundReason.hardwareDoesNotSupportARM64.rawValue),
             Int(SPUNoUpdateFoundReason.unknown.rawValue),
             .none:
            state = .noCompatibleUpdate
        default:
            state = .noCompatibleUpdate
        }
    }

    func recordDownloadStarted(version: String) {
        state = .downloading(version: version)
        availableVersion = nil
    }

    func recordInstallationStarted(version: String) {
        state = .installing(version: version)
        availableVersion = nil
    }

    func recordUpdateFailure() {
        lastCheckDate = now()
        state = .failed
        availableVersion = nil
    }

    func recordUpdateAbort(_ error: NSError) {
        if error.domain == SUSparkleErrorDomain {
            switch error.code {
            case Int(SUError.noUpdateError.rawValue):
                recordNoUpdateFound(error: error)
                return
            case Int(SUError.installationCanceledError.rawValue),
                 Int(SUError.installationAuthorizeLaterError.rawValue):
                state = .idle
                availableVersion = nil
                return
            default:
                break
            }
        }
        recordUpdateFailure()
    }

    func recordUserAttention() {
        availableVersion = nil
    }
}

extension UpdateController: SPUUpdaterDelegate {
    func updater(
        _ updater: SPUUpdater,
        didFindValidUpdate item: SUAppcastItem
    ) {
        recordFoundUpdate(
            version: item.displayVersionString,
            showsGentleReminder: false
        )
    }

    func updaterDidNotFindUpdate(
        _ updater: SPUUpdater,
        error: any Error
    ) {
        recordNoUpdateFound(error: error as NSError)
    }

    func updater(
        _ updater: SPUUpdater,
        willDownloadUpdate item: SUAppcastItem,
        with request: NSMutableURLRequest
    ) {
        recordDownloadStarted(version: item.displayVersionString)
    }

    func updater(
        _ updater: SPUUpdater,
        failedToDownloadUpdate item: SUAppcastItem,
        error: any Error
    ) {
        recordUpdateFailure()
    }

    func userDidCancelDownload(_ updater: SPUUpdater) {
        state = .idle
        availableVersion = nil
    }

    func updater(
        _ updater: SPUUpdater,
        willInstallUpdate item: SUAppcastItem
    ) {
        recordInstallationStarted(version: item.displayVersionString)
    }

    func updater(
        _ updater: SPUUpdater,
        didAbortWithError error: any Error
    ) {
        recordUpdateAbort(error as NSError)
    }
}

extension UpdateController: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state updateState: SPUUserUpdateState
    ) {
        recordFoundUpdate(
            version: update.displayVersionString,
            showsGentleReminder:
                !handleShowingUpdate && !updateState.userInitiated
        )
    }

    func standardUserDriverDidReceiveUserAttention(
        forUpdate update: SUAppcastItem
    ) {
        recordUserAttention()
    }

    func standardUserDriverWillShowModalAlert() {
        onModalAlertWillPresent?()
    }

    func standardUserDriverDidShowModalAlert() {
        onModalAlertDidFinish?()
    }

    func standardUserDriverWillFinishUpdateSession() {
        availableVersion = nil
        if case .available = state {
            state = .idle
        }
    }
}
