import AppKit
import Carbon
import SwiftUI

@MainActor
final class ClipboardHistoryPanelController {
    private let store: ClipboardHistoryStore
    private let applyAction: (ClipboardHistoryItem) -> Void
    private let presentationState = ClipboardHistoryPresentationState()
    private var panel: ClipboardHistoryPanel?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var resignActiveObserver: NSObjectProtocol?

    init(
        store: ClipboardHistoryStore,
        applyAction: @escaping (ClipboardHistoryItem) -> Void
    ) {
        self.store = store
        self.applyAction = applyAction
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

        presentationState.prepare(for: store.items)
        panel.setFrameOrigin(centeredPresentationOrigin())
        panel.orderFrontRegardless()
        panel.makeKey()
        presentationState.requestSearchFocus()
        installDismissHandlers()
    }

    func close() {
        panel?.orderOut(nil)
        removeDismissHandlers()
    }

    private func makePanel() -> ClipboardHistoryPanel {
        let size = NSSize(
            width: ClipboardHistoryMetrics.windowWidth,
            height: ClipboardHistoryMetrics.windowHeight
        )
        let panel = ClipboardHistoryPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.keyDownHandler = { [weak self] event in
            self?.handleKeyDown(event) ?? false
        }
        panel.contentView = NSHostingView(
            rootView: ClipboardHistoryView(
                store: store,
                presentationState: presentationState,
                applyAction: { [weak self] item in
                    self?.close()
                    self?.applyAction(item)
                },
                clearAction: { [weak self] in
                    self?.store.clear()
                }
            )
        )
        return panel
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        switch Int(event.keyCode) {
        case Int(kVK_UpArrow):
            presentationState.moveSelection(by: -1, in: store.items)
            return true
        case Int(kVK_DownArrow):
            presentationState.moveSelection(by: 1, in: store.items)
            return true
        case Int(kVK_Return), Int(kVK_ANSI_KeypadEnter):
            guard let item = presentationState.selectedItem(from: store.items) else {
                return true
            }
            close()
            applyAction(item)
            return true
        case Int(kVK_Escape):
            close()
            return true
        default:
            return false
        }
    }

    private func centeredPresentationOrigin() -> CGPoint {
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        return CGPoint(
            x: screenFrame.midX - ClipboardHistoryMetrics.windowWidth / 2,
            y: screenFrame.midY - ClipboardHistoryMetrics.windowHeight / 2
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

private final class ClipboardHistoryPanel: NSPanel {
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
