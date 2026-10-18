import AppKit
import SwiftUI

@MainActor
final class SystemMonitorPanelController {
    private let viewModel = SystemMonitorViewModel()
    private var panel: NSPanel?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var resignActiveObserver: NSObjectProtocol?

    var isShown: Bool {
        panel?.isVisible == true
    }

    func toggle() {
        if isShown {
            close()
        } else {
            show()
        }
    }

    func close() {
        panel?.orderOut(nil)
        removeDismissHandlers()
    }

    private func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        viewModel.refresh()
        panel.setFrameOrigin(centeredPresentationOrigin())
        panel.orderFrontRegardless()
        installDismissHandlers()
    }

    private func makePanel() -> NSPanel {
        let size = NSSize(width: 560, height: 388)
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
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = NSHostingView(
            rootView: SystemMonitorView(
                viewModel: viewModel,
                openCachesAction: { [weak self] in
                    self?.openCachesDirectory()
                }
            )
        )
        return panel
    }

    private func openCachesDirectory() {
        guard let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func centeredPresentationOrigin() -> CGPoint {
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        return CGPoint(
            x: screenFrame.midX - 280,
            y: screenFrame.midY - 194
        )
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
