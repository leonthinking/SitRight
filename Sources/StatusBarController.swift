import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let container: AppContainer
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

    init(container: AppContainer) {
        self.container = container
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
            refreshController: menuPanelRefreshController
        ) { [weak self] in
            self?.schedulePopoverResize(for: .tabChange)
        }
            .environmentObject(container.settingsStore)
            .environmentObject(container.statsStore)
            .environmentObject(container.notificationManager)
            .environmentObject(container.launchAtLoginController)

        let hostingController = NSHostingController(rootView: AnyView(rootView))
        hostingController.sizingOptions = StatusBarPopoverSizingPolicy.hostingSizingOptions

        popoverHostingController = hostingController
        popover.contentViewController = hostingController
        popover.delegate = self
        popover.behavior = .transient
        popover.animates = false
        resizePopoverContent(for: .initialization)
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }

        button.imagePosition = .imageLeading
        button.imageScaling = .scaleProportionallyDown
        button.target = self
        button.action = #selector(togglePopover)
        button.toolTip = "SitRight 坐正"
        button.setAccessibilityLabel("SitRight 坐正")
    }

    private func observeStatusChanges() {
        container.engine.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.menuPanelRefreshController.engineDidChange()
                    self?.scheduleStatusButtonRefresh()
                }
            }
            .store(in: &cancellables)

        container.settingsStore.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.scheduleStatusButtonRefresh()
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

        let showsCountdown = container.settingsStore.settings.menuBarCountdownEnabled
        let labelWidth: CGFloat
        if showsCountdown {
            labelWidth = MenuBarTitleLayout.fixedWidth(
                for: container.engine.state,
                remainingInterval: container.engine.remainingInterval
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
            showsCountdown: showsCountdown
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

    private func resizePopoverContent(for trigger: StatusBarPopoverResizeTrigger) {
        guard StatusBarPopoverSizingPolicy.requestsMeasurement(for: trigger) else { return }
        guard let hostingController = popoverHostingController else { return }

        let measuredSize = hostingController.sizeThatFits(
            in: StatusBarPopoverSizingPolicy.fittingConstraint
        )
        let fittedSize = StatusBarPopoverSizingPolicy.normalized(measuredSize)
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
    }
}

struct StatusBarButtonPresentation: Equatable {
    let systemImageName: String
    let title: String
    let isAttentionState: Bool
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
}

enum StatusBarPopoverSizingPolicy {
    static let fittingConstraint = NSSize(width: 370, height: 900)
    static let hostingSizingOptions: NSHostingSizingOptions = []

    static func requestsMeasurement(for trigger: StatusBarPopoverResizeTrigger) -> Bool {
        switch trigger {
        case .initialization, .opening, .tabChange:
            return true
        case .engineTick:
            return false
        }
    }

    static func normalized(_ measuredSize: NSSize) -> NSSize {
        NSSize(
            width: fittingConstraint.width,
            height: min(max(ceil(measuredSize.height), 1), fittingConstraint.height)
        )
    }
}

enum StatusBarPopoverResizeTrigger {
    case initialization
    case opening
    case tabChange
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
