import AppKit

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popoverController: CalendarPopoverPanelController
    private let screenshotController: ScreenshotController
    private let updateChecker = UpdateChecker()
    private lazy var screenshotHotKeyController = GlobalHotKeyController { [weak self] in
        self?.captureSelectionToClipboard()
    }
    private lazy var menuController = StatusBarMenuPanelController(
        screenshotAction: { [weak self] in
            self?.captureSelectionToClipboard()
        },
        checkForUpdatesAction: { [weak self] in
            self?.updateChecker.checkForUpdates()
        }
    )

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: CalendarStatusIconMetrics.statusItemLength)
        popoverController = CalendarPopoverPanelController()
        screenshotController = ScreenshotController()
        super.init()

        configureStatusItem()
        registerScreenshotHotKey()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        statusItem.menu = nil
        button.image = CalendarStatusIconRenderer.image(for: Date())
        button.image?.isTemplate = false
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "Invoker Calendar"
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        let eventType = NSApp.currentEvent?.type ?? .leftMouseUp

        switch StatusBarInteractionRouter.action(for: eventType) {
        case .toggleCalendar:
            toggleCalendar(from: sender)
        case .showMenu:
            showContextMenu(from: sender)
        case .ignore:
            break
        }
    }

    private func toggleCalendar(from button: NSStatusBarButton) {
        menuController.close()
        popoverController.toggle(relativeTo: button)
    }

    private func showContextMenu(from button: NSStatusBarButton) {
        popoverController.close()
        menuController.toggle(relativeTo: button)
    }

    private func captureSelectionToClipboard() {
        popoverController.close()
        menuController.close()

        Task { @MainActor in
            await screenshotController.captureSelectionToClipboard()
        }
    }

    private func registerScreenshotHotKey() {
        do {
            try screenshotHotKeyController.register()
        } catch {
            presentHotKeyRegistrationFailure(error)
        }
    }

    private func presentHotKeyRegistrationFailure(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "截图快捷键注册失败"
        alert.informativeText = "Shift + Command + X 可能已被系统或其他应用占用。\n\n\(error.localizedDescription)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")

        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
