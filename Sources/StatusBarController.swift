import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let container: AppContainer
    private let settingsWindowActivationController:
        SettingsWindowActivationController
    private let statusItem: NSStatusItem
    private let menuPanelRefreshController: MenuPanelRefreshController
    private let popover = NSPopover()
    private var popoverHostingController: NSHostingController<AnyView>?
    private var cancellables = Set<AnyCancellable>()
    private var popoverResizeGate = UpdateCoalescingGate()
    private var statusRefreshGate = UpdateCoalescingGate()
    private var lastStatusItemLength: CGFloat?
    private var lastStatusButtonPresentation: StatusBarButtonPresentation?
    private var lastAccessibilityValue: String?
    private var popoverLayoutMeasurementState: PopoverLayoutMeasurementState?

    init(
        container: AppContainer,
        settingsWindowActivationController: SettingsWindowActivationController
    ) {
        self.container = container
        self.settingsWindowActivationController =
            settingsWindowActivationController
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.menuPanelRefreshController = MenuPanelRefreshController()
        super.init()

        configurePopover()
        configureStatusButton()
        observeStatusChanges()
        refreshStatusButton()
    }

    private func configurePopover() {
        let rootView = MenuPanelView(
            engine: container.engine,
            refreshController: menuPanelRefreshController,
            onRequestClose: { [weak self] in
                self?.popover.performClose(nil)
            }
        )
            .environmentObject(container.settingsStore)
            .environmentObject(container.statsStore)
            .environmentObject(container.updateController)
            .environment(
                \.settingsWindowActivationController,
                settingsWindowActivationController
            )

        let hostingController = NSHostingController(rootView: AnyView(rootView))
        hostingController.sizingOptions = StatusBarPopoverSizingPolicy.hostingSizingOptions

        popoverHostingController = hostingController
        popover.contentViewController = hostingController
        popover.delegate = self
        popover.behavior = .transient
        popover.animates = false
        popoverLayoutMeasurementState = PopoverLayoutMeasurementState(
            signature: currentPopoverLayoutSignature()
        )
        resizePopoverContent(for: .initialization)
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }

        button.imagePosition = .imageLeading
        button.imageScaling = .scaleProportionallyDown
        button.target = self
        button.action = #selector(togglePopover)
        let language = container.settingsStore.settings.language
        let appName = language.text("SitRight 坐正", "SitRight")
        button.toolTip = appName
        button.setAccessibilityLabel(appName)
    }

    private func observeStatusChanges() {
        // The projected @Published stream delivers the incoming phase before
        // ReminderEngine requests the guide panel. Arm the presentation gate
        // first so an asynchronous popover close cannot overlap or compete
        // with the guide panel for focus.
        container.engine.$phase
            .removeDuplicates()
            .sink { [weak self] phase in
                guard let self,
                      MenuPopoverVisibilityPolicy.shouldWaitForClose(
                        for: phase,
                        popoverLifecycleIsActive: self.menuPanelRefreshController.isActive
                      ) else {
                    return
                }
                self.container.reminderPresenter
                    .waitForPopoverToCloseBeforePresentingGuide()
                if self.popover.isShown {
                    self.popover.performClose(nil)
                }
            }
            .store(in: &cancellables)

        container.engine.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.menuPanelRefreshController.engineDidChange()
                    self?.scheduleStatusButtonRefresh()
                    self?.schedulePopoverResizeIfLayoutChanged()
                }
            }
            .store(in: &cancellables)

        container.settingsStore.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.scheduleStatusButtonRefresh()
                    self?.schedulePopoverResizeIfLayoutChanged()
                }
            }
            .store(in: &cancellables)

        container.statsStore.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.schedulePopoverResizeIfLayoutChanged()
                }
            }
            .store(in: &cancellables)

        container.updateController.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.menuPanelRefreshController.externalContentDidChange()
                    self?.schedulePopoverResizeIfLayoutChanged()
                }
            }
            .store(in: &cancellables)
    }

    private func scheduleStatusButtonRefresh() {
        guard statusRefreshGate.schedule() else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.statusRefreshGate.complete()
            self.refreshStatusButton()
        }
    }

    private func refreshStatusButton() {
        guard let button = statusItem.button else { return }

        let settings = container.settingsStore.settings
        let language = settings.language
        let appName = language.text("SitRight 坐正", "SitRight")
        button.toolTip = appName
        button.setAccessibilityLabel(appName)

        let showsCountdown = settings.menuBarCountdownEnabled
        let labelWidth: CGFloat
        if showsCountdown {
            labelWidth = MenuBarTitleLayout.fixedWidth(
                for: container.engine.state,
                remainingInterval: container.engine.remainingInterval,
                language: language
            )
        } else {
            labelWidth = 0
        }

        let itemLength = 25 + labelWidth
        if itemLength != lastStatusItemLength {
            statusItem.length = itemLength
            lastStatusItemLength = itemLength
        }

        let presentation = StatusBarButtonPresentation(
            systemImageName: container.engine.statusSystemImage,
            title: showsCountdown ? container.engine.menuBarTitle : "",
            isAttentionState: showsCountdown && (
                container.engine.canCompleteReminder || container.engine.state == .due
            )
        )
        applyStatusButtonPresentation(presentation, to: button)

        let accessibilityValue = ReminderAccessibility.statusText(
            statusText: container.engine.statusText,
            countdownText: container.engine.countdownText,
            state: container.engine.state,
            showsCountdown: showsCountdown,
            language: language
        )
        if accessibilityValue != lastAccessibilityValue {
            button.setAccessibilityValue(accessibilityValue)
            lastAccessibilityValue = accessibilityValue
        }
    }

    private func applyStatusButtonPresentation(
        _ presentation: StatusBarButtonPresentation,
        to button: NSStatusBarButton
    ) {
        let previous = lastStatusButtonPresentation

        if previous?.systemImageName != presentation.systemImageName {
            let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            button.image = NSImage(
                systemSymbolName: presentation.systemImageName,
                accessibilityDescription: nil
            )?.withSymbolConfiguration(configuration)
            button.image?.isTemplate = true
        }

        if previous?.title != presentation.title ||
            previous?.isAttentionState != presentation.isAttentionState {
            let color = presentation.isAttentionState
                ? NSColor.labelColor
                : NSColor.labelColor.withSystemEffect(.disabled)
            button.attributedTitle = NSAttributedString(
                string: presentation.title,
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold),
                    .foregroundColor: color
                ]
            )
            button.contentTintColor = color
        }

        lastStatusButtonPresentation = presentation
    }

    private func schedulePopoverResize(for trigger: StatusBarPopoverResizeTrigger) {
        guard StatusBarPopoverSizingPolicy.requestsMeasurement(for: trigger) else { return }
        guard popoverResizeGate.schedule() else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.popoverResizeGate.complete()
            self.resizePopoverContent(for: trigger)
        }
    }

    private func schedulePopoverResizeIfLayoutChanged() {
        let signature = currentPopoverLayoutSignature()
        guard popoverLayoutMeasurementState?.shouldRequestMeasurement(
            for: signature,
            whilePopoverIsShown: popover.isShown
        ) == true else {
            return
        }
        schedulePopoverResize(for: .layoutChange)
    }

    private func currentPopoverLayoutSignature() -> MenuPanelLayoutSignature {
        MenuPanelLayoutSignature(
            engine: container.engine,
            statsStore: container.statsStore,
            showsAvailableUpdate:
                container.updateController.availableVersion != nil
        )
    }

    private func resizePopoverContent(for trigger: StatusBarPopoverResizeTrigger) {
        guard StatusBarPopoverSizingPolicy.requestsMeasurement(for: trigger) else { return }
        guard let hostingController = popoverHostingController else { return }

        let maximumHeight = StatusBarPopoverSizingPolicy.maximumHeight(
            for: statusItem.button?.window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        )
        let measuredSize = hostingController.sizeThatFits(
            in: StatusBarPopoverSizingPolicy.fittingConstraint(maximumHeight: maximumHeight)
        )
        let fittedSize = StatusBarPopoverSizingPolicy.normalized(
            measuredSize,
            maximumHeight: maximumHeight
        )
        popoverLayoutMeasurementState?.synchronize(
            with: currentPopoverLayoutSignature()
        )
        guard popover.contentSize != fittedSize else { return }
        popover.contentSize = fittedSize
    }

    @objc
    private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            menuPanelRefreshController.setActive(true)
            container.launchAtLoginController.refreshStatus()
            resizePopoverContent(for: .opening)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        menuPanelRefreshController.setActive(false)
        container.reminderPresenter.popoverDidCloseBeforeGuidePresentation()
    }
}

struct StatusBarButtonPresentation: Equatable {
    let systemImageName: String
    let title: String
    let isAttentionState: Bool
}

enum MenuPopoverVisibilityPolicy {
    static func shouldClose(for phase: ReminderPhase) -> Bool {
        phase == .guiding
    }

    static func shouldWaitForClose(
        for phase: ReminderPhase,
        popoverLifecycleIsActive: Bool
    ) -> Bool {
        shouldClose(for: phase) && popoverLifecycleIsActive
    }
}

@MainActor
final class MenuPanelRefreshController: ObservableObject {
    private(set) var isActive = false

    func setActive(_ isActive: Bool) {
        guard self.isActive != isActive else { return }
        self.isActive = isActive

        if isActive {
            objectWillChange.send()
        }
    }

    func engineDidChange() {
        guard isActive else { return }
        objectWillChange.send()
    }

    func externalContentDidChange() {
        guard isActive else { return }
        objectWillChange.send()
    }
}

enum StatusBarPopoverSizingPolicy {
    static let width: CGFloat = 370
    static let maximumContentHeight: CGFloat = 900
    static let screenEdgeMargin: CGFloat = 24
    static let hostingSizingOptions: NSHostingSizingOptions = []

    static func requestsMeasurement(for trigger: StatusBarPopoverResizeTrigger) -> Bool {
        switch trigger {
        case .initialization, .opening, .layoutChange:
            return true
        case .engineTick:
            return false
        }
    }

    static func maximumHeight(for visibleFrame: NSRect?) -> CGFloat {
        guard let visibleFrame else { return maximumContentHeight }
        return min(
            maximumContentHeight,
            max(floor(visibleFrame.height - screenEdgeMargin), 1)
        )
    }

    static func fittingConstraint(maximumHeight: CGFloat) -> NSSize {
        NSSize(
            width: width,
            height: min(max(maximumHeight, 1), maximumContentHeight)
        )
    }

    static func normalized(
        _ measuredSize: NSSize,
        maximumHeight: CGFloat = maximumContentHeight
    ) -> NSSize {
        let clampedMaximumHeight = min(max(maximumHeight, 1), maximumContentHeight)
        return NSSize(
            width: width,
            height: min(max(ceil(measuredSize.height), 1), clampedMaximumHeight)
        )
    }
}

enum StatusBarPopoverResizeTrigger {
    case initialization
    case opening
    case layoutChange
    case engineTick
}

struct UpdateCoalescingGate {
    private(set) var isScheduled = false

    mutating func schedule() -> Bool {
        guard !isScheduled else { return false }
        isScheduled = true
        return true
    }

    mutating func complete() {
        isScheduled = false
    }
}

struct PopoverLayoutMeasurementState {
    private(set) var signature: MenuPanelLayoutSignature

    mutating func shouldRequestMeasurement(
        for newSignature: MenuPanelLayoutSignature,
        whilePopoverIsShown: Bool
    ) -> Bool {
        guard newSignature != signature else { return false }
        signature = newSignature
        return whilePopoverIsShown
    }

    mutating func synchronize(with newSignature: MenuPanelLayoutSignature) {
        signature = newSignature
    }
}
