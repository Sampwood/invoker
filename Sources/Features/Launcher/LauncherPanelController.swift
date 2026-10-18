import AppKit
import Carbon
import SwiftUI

@MainActor
final class LauncherPanelController: NSObject, NSWindowDelegate {
    private let viewModel: LauncherSearchViewModel
    private var panel: LauncherPanel?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var resignActiveObserver: NSObjectProtocol?
    private var isClosing = false

    init(registry: LauncherCommandRegistry) {
        viewModel = LauncherSearchViewModel(registry: registry)
        super.init()
    }

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

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel

        viewModel.prepare()
        panel.setFrameOrigin(centeredPresentationOrigin())
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        installDismissHandlers()
    }

    func close() {
        guard !isClosing else {
            return
        }

        isClosing = true
        defer { isClosing = false }
        removeDismissHandlers()
        panel?.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard notification.object as? NSWindow === panel, panel?.isVisible == true else {
            return
        }

        close()
    }

    private func makePanel() -> LauncherPanel {
        let size = NSSize(width: LauncherMetrics.width, height: LauncherMetrics.height)
        let panel = LauncherPanel(
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
        panel.delegate = self
        panel.keyDownHandler = { [weak self] event in
            self?.handleKeyDown(event) ?? false
        }
        panel.contentView = NSHostingView(
            rootView: LauncherView(
                viewModel: viewModel,
                executeAction: { [weak self] command in
                    self?.execute(command)
                }
            )
        )
        return panel
    }

    private func execute(_ command: LauncherCommand) {
        close()
        command.action()
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        switch Int(event.keyCode) {
        case Int(kVK_UpArrow):
            viewModel.moveSelection(by: -1)
            return true
        case Int(kVK_DownArrow):
            viewModel.moveSelection(by: 1)
            return true
        case Int(kVK_Return), Int(kVK_ANSI_KeypadEnter):
            guard let command = viewModel.selectedCommand() else {
                return true
            }
            execute(command)
            return true
        case Int(kVK_Escape):
            close()
            return true
        default:
            return false
        }
    }

    private func centeredPresentationOrigin() -> CGPoint {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first {
            NSMouseInRect(mouseLocation, $0.frame, false)
        } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? .zero

        return CGPoint(
            x: visibleFrame.midX - LauncherMetrics.width / 2,
            y: visibleFrame.midY - LauncherMetrics.height / 2
        )
    }

    private func installDismissHandlers() {
        removeDismissHandlers()

        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self, event.window !== self.panel else {
                return event
            }

            self.close()
            return event
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
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

@MainActor
private final class LauncherPanel: NSPanel {
    var keyDownHandler: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool {
        true
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, keyDownHandler?(event) == true {
            return
        }
        super.sendEvent(event)
    }
}
