import AppKit
import SwiftUI

@MainActor
final class StatusBarMenuPanelController {
    private let screenshotAction: () -> Void
    private let checkForUpdatesAction: () -> Void
    private var panel: NSPanel?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var resignActiveObserver: NSObjectProtocol?

    init(
        screenshotAction: @escaping () -> Void,
        checkForUpdatesAction: @escaping () -> Void
    ) {
        self.screenshotAction = screenshotAction
        self.checkForUpdatesAction = checkForUpdatesAction
    }

    var isShown: Bool {
        panel?.isVisible == true
    }

    func toggle(relativeTo button: NSStatusBarButton) {
        if isShown {
            close()
        } else {
            show(relativeTo: button)
        }
    }

    private func show(relativeTo button: NSStatusBarButton) {
        let panel = panel ?? makePanel()
        self.panel = panel

        let origin = presentationOrigin(relativeTo: button)
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        installDismissHandlers()
    }

    func close() {
        panel?.orderOut(nil)
        removeDismissHandlers()
    }

    private func makePanel() -> NSPanel {
        let size = NSSize(
            width: StatusBarMenuMetrics.windowWidth,
            height: StatusBarMenuMetrics.windowHeight
        )
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = NSHostingView(
            rootView: StatusBarMenuView(
                screenshotAction: { [weak self] in
                    self?.close()
                    self?.screenshotAction()
                },
                checkForUpdatesAction: { [weak self] in
                    self?.close()
                    self?.checkForUpdatesAction()
                },
                quitAction: { [weak self] in
                    self?.close()
                    NSApp.terminate(nil)
                }
            )
        )
        return panel
    }

    private func presentationOrigin(relativeTo button: NSStatusBarButton) -> CGPoint {
        guard let window = button.window else {
            return .zero
        }

        let buttonRectInWindow = button.convert(button.bounds, to: nil)
        let buttonRectOnScreen = window.convertToScreen(buttonRectInWindow)
        let screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        let preferredBodyX = buttonRectOnScreen.minX
        let minX = screenFrame.minX + CalendarPopoverPresentationGeometry.horizontalMargin
        let maxX = max(
            minX,
            screenFrame.maxX - StatusBarMenuMetrics.bodyWidth - CalendarPopoverPresentationGeometry.horizontalMargin
        )
        let bodyX = min(max(preferredBodyX, minX), maxX)
        let x = bodyX - StatusBarMenuMetrics.shadowPadding
        let y = buttonRectOnScreen.minY
            - StatusBarMenuMetrics.bodyHeight
            - CalendarPopoverPresentationGeometry.verticalOffset
            - StatusBarMenuMetrics.shadowPadding

        return CGPoint(x: x, y: y)
    }

    private func installDismissHandlers() {
        removeDismissHandlers()

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, event.window !== self.panel else {
                return event
            }

            self.close()
            return event
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.close()
            }
        }

        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.close()
            }
        }
    }

    private func removeDismissHandlers() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }

        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }

        if let resignActiveObserver {
            NotificationCenter.default.removeObserver(resignActiveObserver)
            self.resignActiveObserver = nil
        }
    }
}
