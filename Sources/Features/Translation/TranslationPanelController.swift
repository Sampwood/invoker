import AppKit
import Combine
import SwiftUI

@MainActor
private final class TranslationPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

@MainActor
final class TranslationPanelController: NSObject, NSWindowDelegate {
    private enum PanelMetrics {
        static let width = TranslationPanelContentSizing.defaultWidth
        static let minimumWidth: CGFloat = 380
    }

    private let viewModel: TranslationViewModel
    private let openSettingsAction: () -> Void
    private let openAccessibilitySettingsAction: () -> Void
    private var panel: NSPanel?
    private var contentSizingCancellable: AnyCancellable?
    private var contentSizingTask: Task<Void, Never>?
    private var localEventMonitor: Any?
    private var localKeyDownMonitor: Any?
    private var globalEventMonitor: Any?
    private var lastObservedPanelWidth = PanelMetrics.width
    private var lastAppliedExpansionState = false
    private var isClosing = false

    init(
        viewModel: TranslationViewModel,
        openSettingsAction: @escaping () -> Void,
        openAccessibilitySettingsAction: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.openSettingsAction = openSettingsAction
        self.openAccessibilitySettingsAction = openAccessibilitySettingsAction
        lastAppliedExpansionState = viewModel.state != .idle || viewModel.inlineNotice != nil
        super.init()
        observeContentSizingState()
    }

    var isShown: Bool {
        panel?.isVisible == true
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        synchronizePanelHeight()
        panel.setFrameOrigin(presentationOrigin(for: panel.frame.size))
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        installDismissHandlers()
        viewModel.requestInputFocus()
    }

    func close() {
        guard !isClosing else {
            return
        }

        isClosing = true
        defer { isClosing = false }
        removeDismissHandlers()
        panel?.close()
    }

    func windowWillClose(_ notification: Notification) {
        removeDismissHandlers()
        viewModel.cancelTranslation()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard notification.object as? NSWindow === panel, panel?.isVisible == true else {
            return
        }

        close()
    }

    private func makePanel() -> NSPanel {
        let initialHeight = targetPanelHeight(panelWidth: PanelMetrics.width)
        let panel = TranslationPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: PanelMetrics.width,
                height: initialHeight
            ),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "翻译"
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.minSize = NSSize(
            width: PanelMetrics.minimumWidth,
            height: minimumPanelHeight
        )
        panel.maxSize = NSSize(
            width: panel.maxSize.width,
            height: TranslationPanelContentSizing.maximumPanelHeight
        )
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentView = NSHostingView(
            rootView: TranslationView(
                viewModel: viewModel,
                openSettingsAction: openSettingsAction,
                openAccessibilitySettingsAction: openAccessibilitySettingsAction
            )
        )
        return panel
    }

    private func observeContentSizingState() {
        contentSizingCancellable = viewModel.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.schedulePanelHeightSynchronization()
                }
            }
    }

    private func schedulePanelHeightSynchronization() {
        contentSizingTask?.cancel()
        contentSizingTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled else {
                return
            }
            self?.synchronizePanelHeight()
        }
    }

    private var shouldExpand: Bool {
        viewModel.state != .idle || viewModel.inlineNotice != nil
    }

    private var minimumPanelHeight: CGFloat {
        shouldExpand
            ? TranslationPanelContentSizing.expandedMinimumPanelHeight
            : TranslationPanelContentSizing.minimumPanelHeight
    }

    private func targetPanelHeight(panelWidth: CGFloat) -> CGFloat {
        TranslationPanelContentSizing.panelHeight(
            state: viewModel.state,
            inlineNotice: viewModel.inlineNotice,
            errorMessage: viewModel.errorMessage,
            inputText: viewModel.inputText,
            resultText: viewModel.resultText,
            panelWidth: panelWidth
        )
    }

    private func synchronizePanelHeight() {
        guard let panel else {
            return
        }

        let currentFrame = panel.frame
        let targetHeight = targetPanelHeight(panelWidth: currentFrame.width)
        let isExpansionTransition = shouldExpand != lastAppliedExpansionState
        lastAppliedExpansionState = shouldExpand
        lastObservedPanelWidth = currentFrame.width
        panel.minSize = NSSize(
            width: PanelMetrics.minimumWidth,
            height: minimumPanelHeight
        )
        panel.maxSize = NSSize(
            width: panel.maxSize.width,
            height: TranslationPanelContentSizing.maximumPanelHeight
        )

        let visibleFrame = panel.screen?.visibleFrame
        let anchoredMaximumX = visibleFrame?.maxX ?? currentFrame.maxX
        let anchoredMaximumY = visibleFrame?.maxY ?? currentFrame.maxY
        let targetFrame = NSRect(
            x: anchoredMaximumX - currentFrame.width,
            y: anchoredMaximumY - targetHeight,
            width: currentFrame.width,
            height: targetHeight
        )
        guard
            abs(targetFrame.minX - currentFrame.minX) > 0.5
                || abs(targetFrame.minY - currentFrame.minY) > 0.5
                || abs(targetFrame.height - currentFrame.height) > 0.5
        else {
            return
        }

        let shouldAnimate = panel.isVisible
            && !isClosing
            && !panel.inLiveResize
            && isExpansionTransition
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        panel.setFrame(
            targetFrame,
            display: panel.isVisible,
            animate: shouldAnimate
        )
    }

    func windowDidResize(_ notification: Notification) {
        guard
            let resizedPanel = notification.object as? NSPanel,
            resizedPanel === panel,
            abs(resizedPanel.frame.width - lastObservedPanelWidth) > 0.5
        else {
            return
        }

        lastObservedPanelWidth = resizedPanel.frame.width
        synchronizePanelHeight()
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard sender === panel else {
            return frameSize
        }

        return NSSize(
            width: frameSize.width,
            height: targetPanelHeight(panelWidth: frameSize.width)
        )
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard notification.object as? NSWindow === panel else {
            return
        }

        synchronizePanelHeight()
    }

    private func presentationOrigin(for panelSize: NSSize) -> NSPoint {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first {
            NSMouseInRect(mouseLocation, $0.frame, false)
        } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? .zero

        return NSPoint(
            x: max(visibleFrame.minX, visibleFrame.maxX - panelSize.width),
            y: max(visibleFrame.minY, visibleFrame.maxY - panelSize.height)
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

        localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) {
            [weak self] event in
            guard
                let self,
                let panel = self.panel,
                event.window === panel,
                let textView = panel.firstResponder as? NSTextView,
                textView.isEditable,
                event.keyCode == 36 || event.keyCode == 76,
                event.modifierFlags.intersection([.shift, .command, .option, .control]).isEmpty,
                !textView.hasMarkedText()
            else {
                return event
            }

            guard !event.isARepeat else {
                return nil
            }

            if viewModel.state == .translating {
                viewModel.cancelTranslation()
            } else if viewModel.canTranslate {
                viewModel.startTranslation()
            }
            return nil
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
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

        if let localKeyDownMonitor {
            NSEvent.removeMonitor(localKeyDownMonitor)
            self.localKeyDownMonitor = nil
        }

        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
    }
}
