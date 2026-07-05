import AppKit
import SwiftUI

@MainActor
final class CalendarPopoverPanelController {
    private let presentationState = CalendarPopoverPresentationState()
    private var panel: NSPanel?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var resignActiveObserver: NSObjectProtocol?
    private weak var statusButton: NSStatusBarButton?

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
        statusButton = button

        let layout = presentationLayout(relativeTo: button, for: panel.frame.size)
        presentationState.arrowCenterX = layout.arrowCenterX
        panel.setFrameOrigin(layout.origin)
        panel.orderFrontRegardless()
        installDismissHandlers()
    }

    func close() {
        panel?.orderOut(nil)
        removeDismissHandlers()
    }

    private func makePanel() -> NSPanel {
        let size = NSSize(
            width: CalendarPopoverMetrics.windowWidth,
            height: CalendarPopoverMetrics.windowHeight
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
        panel.contentView = NSHostingView(rootView: CalendarPopoverView(presentationState: presentationState))
        return panel
    }

    private func presentationLayout(relativeTo button: NSStatusBarButton, for size: NSSize) -> CalendarPopoverPresentationLayout {
        guard let window = button.window else {
            return CalendarPopoverPresentationLayout(
                origin: .zero,
                arrowCenterX: CalendarPopoverMetrics.panelWidth / 2
            )
        }

        let buttonRectInWindow = button.convert(button.bounds, to: nil)
        let buttonRectOnScreen = window.convertToScreen(buttonRectInWindow)
        let screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        return CalendarPopoverPresentationGeometry.layout(
            buttonRectOnScreen: buttonRectOnScreen,
            screenFrame: screenFrame,
            panelSize: size
        )
    }

    private func installDismissHandlers() {
        removeDismissHandlers()

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.shouldDismiss(for: event) else {
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

    private func shouldDismiss(for event: NSEvent) -> Bool {
        if event.window === panel {
            return false
        }

        if let statusButton, event.window === statusButton.window {
            let pointInButton = statusButton.convert(event.locationInWindow, from: nil)
            if statusButton.bounds.contains(pointInButton) {
                return false
            }
        }

        return true
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
