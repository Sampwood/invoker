import AppKit

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popoverController: CalendarPopoverPanelController
    private let menuController: StatusBarMenuPanelController

    override init() {
        let checker = UpdateChecker()

        statusItem = NSStatusBar.system.statusItem(withLength: CalendarStatusIconMetrics.statusItemLength)
        popoverController = CalendarPopoverPanelController()
        menuController = StatusBarMenuPanelController {
            Task { @MainActor in
                checker.checkForUpdates()
            }
        }
        super.init()

        configureStatusItem()
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
}
