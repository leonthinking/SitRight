import AppKit
import SwiftUI

@MainActor
protocol ApplicationActivationClient: AnyObject {
    var activationPolicy: NSApplication.ActivationPolicy { get }

    @discardableResult
    func setActivationPolicy(_ policy: NSApplication.ActivationPolicy) -> Bool
    func unhide()
    func activate()
    func makeKeyAndOrderFront(_ window: NSWindow)
    func isStandardWindow(_ window: NSWindow) -> Bool
    func visibleStandardWindows() -> [NSWindow]
    func hasVisibleStandardWindow(excluding window: NSWindow?) -> Bool
}

@MainActor
final class SystemApplicationActivationClient: ApplicationActivationClient {
    private let application: NSApplication

    init(application: NSApplication = .shared) {
        self.application = application
    }

    var activationPolicy: NSApplication.ActivationPolicy {
        application.activationPolicy()
    }

    @discardableResult
    func setActivationPolicy(_ policy: NSApplication.ActivationPolicy) -> Bool {
        application.setActivationPolicy(policy)
    }

    func unhide() {
        application.unhide(nil)
    }

    func activate() {
        application.activate(ignoringOtherApps: true)
    }

    func makeKeyAndOrderFront(_ window: NSWindow) {
        window.makeKeyAndOrderFront(nil)
    }

    func isStandardWindow(_ window: NSWindow) -> Bool {
        if window is NSPanel {
            return application.modalWindow === window
        }
        return window.canBecomeMain
    }

    func visibleStandardWindows() -> [NSWindow] {
        application.windows.filter { window in
            window.isVisible && isStandardWindow(window)
        }
    }

    func hasVisibleStandardWindow(excluding excludedWindow: NSWindow?) -> Bool {
        visibleStandardWindows().contains { window in
            window !== excludedWindow
        }
    }
}

private struct WeakWindow {
    weak var value: NSWindow?
}

@MainActor
final class SettingsWindowActivationController: NSObject {
    private let applicationClient: any ApplicationActivationClient
    private let notificationCenter: NotificationCenter
    private var settingsWindows: [ObjectIdentifier: WeakWindow] = [:]
    private var standardWindows: [ObjectIdentifier: WeakWindow] = [:]
    private var presentationRequested = false
    private var focusScheduled = false
    private var focusRequestGeneration = 0
    private var demotionCheckScheduled = false
    private var modalPresentationLeaseCount = 0
    private var pendingActivationPolicy: NSApplication.ActivationPolicy?
    private var activationPolicyRetryScheduled = false

    init(
        applicationClient: any ApplicationActivationClient =
            SystemApplicationActivationClient(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.applicationClient = applicationClient
        self.notificationCenter = notificationCenter
        super.init()

        notificationCenter.addObserver(
            self,
            selector: #selector(applicationWillHide(_:)),
            name: NSApplication.willHideNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(applicationDidHide(_:)),
            name: NSApplication.didHideNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    deinit {
        notificationCenter.removeObserver(self)
    }

    func prepareForSettingsPresentation() {
        presentationRequested = true
        promoteToRegularApplication()
        applicationClient.unhide()
        applicationClient.activate()
        focusRegisteredSettingsWindowOnNextRunLoop()
    }

    func registerSettingsWindow(_ window: NSWindow) {
        removeReleasedWindows()
        let identifier = ObjectIdentifier(window)
        let wasAlreadyRegistered = settingsWindows[identifier]?.value != nil
        let weakWindow = WeakWindow(value: window)
        settingsWindows[identifier] = weakWindow
        standardWindows[identifier] = weakWindow

        guard presentationRequested || window.isVisible else { return }
        promoteToRegularApplication()
        guard presentationRequested || !wasAlreadyRegistered else { return }
        if !presentationRequested {
            applicationClient.unhide()
            applicationClient.activate()
        }
        focusRegisteredSettingsWindowOnNextRunLoop()
    }

    func handleApplicationWillHide() {
        applicationClient.visibleStandardWindows().forEach(trackStandardWindow)
    }

    func handleApplicationDidHide() {
        presentationRequested = false
        cancelScheduledFocus()
    }

    func beginModalWindowPresentation() {
        modalPresentationLeaseCount += 1
        promoteToRegularApplication()
    }

    func endModalWindowPresentation() {
        guard modalPresentationLeaseCount > 0 else { return }
        modalPresentationLeaseCount -= 1
        guard modalPresentationLeaseCount == 0 else { return }
        scheduleAccessoryDemotionCheck(excluding: nil)
    }

    func handleWindowWillClose(_ window: NSWindow) {
        let identifier = ObjectIdentifier(window)
        let wasRegisteredSettingsWindow =
            settingsWindows.removeValue(forKey: identifier) != nil
        let wasTrackedStandardWindow =
            standardWindows.removeValue(forKey: identifier) != nil
        let isStandardWindow = applicationClient.isStandardWindow(window)
        guard wasRegisteredSettingsWindow ||
            wasTrackedStandardWindow ||
            isStandardWindow else {
            return
        }

        if wasRegisteredSettingsWindow {
            presentationRequested = false
            cancelScheduledFocus()
        }

        guard !presentationRequested else { return }
        scheduleAccessoryDemotionIfNeeded(excluding: window)
    }

    private func promoteToRegularApplication() {
        requestActivationPolicy(.regular)
    }

    private func demoteToAccessoryApplication() {
        requestActivationPolicy(.accessory)
    }

    private func requestActivationPolicy(
        _ policy: NSApplication.ActivationPolicy
    ) {
        if pendingActivationPolicy == policy &&
            activationPolicyRetryScheduled
        {
            return
        }
        pendingActivationPolicy = policy
        applyPendingActivationPolicy(allowsRetry: true)
    }

    private func applyPendingActivationPolicy(allowsRetry: Bool) {
        guard let policy = pendingActivationPolicy else { return }
        guard applicationClient.activationPolicy != policy else {
            pendingActivationPolicy = nil
            return
        }

        let accepted = applicationClient.setActivationPolicy(policy)
        if accepted && applicationClient.activationPolicy == policy {
            pendingActivationPolicy = nil
            return
        }

        guard allowsRetry, !activationPolicyRetryScheduled else { return }
        activationPolicyRetryScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.activationPolicyRetryScheduled = false
            self.applyPendingActivationPolicy(allowsRetry: false)
        }
    }

    private func focusRegisteredSettingsWindowOnNextRunLoop() {
        guard !focusScheduled else { return }
        focusScheduled = true
        let generation = focusRequestGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.focusRequestGeneration == generation else { return }
            self.focusScheduled = false
            self.removeReleasedWindows()
            self.settingsWindows.values
                .compactMap(\.value)
                .forEach(self.applicationClient.makeKeyAndOrderFront)
            self.applicationClient.activate()
        }
    }

    private func cancelScheduledFocus() {
        focusRequestGeneration &+= 1
        focusScheduled = false
    }

    private func removeReleasedWindows() {
        settingsWindows = settingsWindows.filter { $0.value.value != nil }
        standardWindows = standardWindows.filter { $0.value.value != nil }
    }

    private func removeInactiveTransientPanels() {
        standardWindows = standardWindows.filter { identifier, trackedWindow in
            guard let window = trackedWindow.value else { return false }
            if settingsWindows[identifier] != nil {
                return true
            }
            if window is NSPanel {
                return window.isVisible ||
                    applicationClient.isStandardWindow(window)
            }
            return true
        }
    }

    private func trackStandardWindow(_ window: NSWindow) {
        standardWindows[ObjectIdentifier(window)] = WeakWindow(value: window)
    }

    private func hasOpenStandardWindow(excluding window: NSWindow?) -> Bool {
        removeReleasedWindows()
        if standardWindows.values.contains(where: { trackedWindow in
            guard let trackedWindow = trackedWindow.value else { return false }
            return trackedWindow !== window
        }) {
            return true
        }
        return applicationClient.hasVisibleStandardWindow(excluding: window)
    }

    private func scheduleAccessoryDemotionIfNeeded(excluding window: NSWindow) {
        guard modalPresentationLeaseCount == 0 else { return }
        guard !hasOpenStandardWindow(excluding: window) else { return }
        if pendingActivationPolicy == .regular {
            pendingActivationPolicy = nil
        }
        scheduleAccessoryDemotionCheck(excluding: window)
    }

    private func scheduleAccessoryDemotionCheck(excluding window: NSWindow?) {
        guard !demotionCheckScheduled else { return }
        demotionCheckScheduled = true
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self else { return }
            self.demotionCheckScheduled = false
            guard !self.presentationRequested else { return }
            guard self.modalPresentationLeaseCount == 0 else { return }
            self.removeInactiveTransientPanels()
            guard !self.hasOpenStandardWindow(excluding: window) else { return }
            if self.pendingActivationPolicy == .regular {
                self.pendingActivationPolicy = nil
            }
            self.demoteToAccessoryApplication()
        }
    }

    private func isRegisteredSettingsWindow(_ window: NSWindow?) -> Bool {
        guard let window else { return false }
        removeReleasedWindows()
        return settingsWindows[ObjectIdentifier(window)] != nil
    }

    @objc
    private func applicationWillHide(_ notification: Notification) {
        handleApplicationWillHide()
    }

    @objc
    private func applicationDidHide(_ notification: Notification) {
        handleApplicationDidHide()
    }

    @objc
    private func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        let isSettingsWindow = isRegisteredSettingsWindow(window)
        guard isSettingsWindow || applicationClient.isStandardWindow(window) else {
            return
        }
        trackStandardWindow(window)
        if isSettingsWindow {
            presentationRequested = false
        }
        promoteToRegularApplication()
    }

    @objc
    private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        handleWindowWillClose(window)
    }
}

private struct SettingsWindowActivationControllerKey: EnvironmentKey {
    static let defaultValue: SettingsWindowActivationController? = nil
}

extension EnvironmentValues {
    var settingsWindowActivationController: SettingsWindowActivationController? {
        get { self[SettingsWindowActivationControllerKey.self] }
        set { self[SettingsWindowActivationControllerKey.self] = newValue }
    }
}
