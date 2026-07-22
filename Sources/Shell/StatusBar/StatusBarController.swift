import AppKit

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popoverController: CalendarPopoverPanelController
    private let screenshotController: ScreenshotController
    private let clipboardHistoryStore: ClipboardHistoryStore
    private let clipboardPasteExecutor: ClipboardPasteExecutor
    private let translationSettings: TranslationSettingsStore
    private let translationViewModel: TranslationViewModel
    private let selectedTextReader: SelectedTextReading
    private let updateChecker = UpdateChecker()
    private lazy var translationSettingsWindowController = TranslationSettingsWindowController(
        settings: translationSettings
    )
    private lazy var translationPanelController = TranslationPanelController(
        viewModel: translationViewModel,
        openSettingsAction: { [weak self] in
            self?.showTranslationSettings()
        },
        openAccessibilitySettingsAction: { [weak self] in
            self?.selectedTextReader.openAccessibilitySettings()
        }
    )
    private lazy var screenshotHotKeyController = GlobalHotKeyController(
        configuration: .screenshot
    ) { [weak self] in
        self?.captureSelectionToClipboard()
    }
    private lazy var translationHotKeyController = GlobalHotKeyController(
        configuration: .selectionTranslation
    ) { [weak self] in
        self?.translateSelectedText()
    }
    private lazy var clipboardHistoryHotKeyController = GlobalHotKeyController(
        configuration: .clipboardHistory
    ) { [weak self] in
        self?.showClipboardHistory()
    }
    private lazy var clipboardHistoryPanelController = ClipboardHistoryPanelController(
        store: clipboardHistoryStore
    ) { [weak self] item in
        self?.pasteClipboardHistoryItem(item)
    }
    private lazy var menuController = StatusBarMenuPanelController(
        translationAction: { [weak self] in
            self?.showManualTranslation()
        },
        screenshotAction: { [weak self] in
            self?.captureSelectionToClipboard()
        },
        clipboardHistoryAction: { [weak self] in
            self?.showClipboardHistory()
        },
        settingsAction: { [weak self] in
            self?.showTranslationSettings()
        },
        checkForUpdatesAction: { [weak self] in
            self?.updateChecker.checkForUpdates()
        }
    )

    override convenience init() {
        let translationSettings = TranslationSettingsStore()
        self.init(
            translationSettings: translationSettings,
            translationProviderRegistry: TranslationProviderRegistry(settings: translationSettings),
            selectedTextReader: AccessibilitySelectedTextReader()
        )
    }

    init(
        translationSettings: TranslationSettingsStore,
        translationProviderRegistry: TranslationProviderResolving,
        selectedTextReader: SelectedTextReading
    ) {
        statusItem = NSStatusBar.system.statusItem(withLength: CalendarStatusIconMetrics.statusItemLength)
        popoverController = CalendarPopoverPanelController()
        screenshotController = ScreenshotController()
        clipboardHistoryStore = ClipboardHistoryStore()
        clipboardPasteExecutor = ClipboardPasteExecutor()
        self.translationSettings = translationSettings
        translationViewModel = TranslationViewModel(
            settings: translationSettings,
            providerRegistry: translationProviderRegistry
        )
        self.selectedTextReader = selectedTextReader
        super.init()

        configureStatusItem()
        registerHotKey(screenshotHotKeyController, configuration: .screenshot)
        registerHotKey(translationHotKeyController, configuration: .selectionTranslation)
        registerHotKey(clipboardHistoryHotKeyController, configuration: .clipboardHistory)
        clipboardHistoryStore.startMonitoring()
    }

    func stopClipboardHistoryMonitoring() {
        clipboardHistoryStore.stopMonitoring()
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
        clipboardHistoryPanelController.close()
        popoverController.toggle(relativeTo: button)
    }

    private func showContextMenu(from button: NSStatusBarButton) {
        popoverController.close()
        clipboardHistoryPanelController.close()
        menuController.toggle(relativeTo: button)
    }

    private func captureSelectionToClipboard() {
        popoverController.close()
        menuController.close()
        clipboardHistoryPanelController.close()

        Task { @MainActor in
            await screenshotController.captureSelectionToClipboard()
        }
    }

    private func showManualTranslation() {
        popoverController.close()
        menuController.close()
        clipboardHistoryPanelController.close()
        translationViewModel.prepareManualInput()
        translationPanelController.show()
    }

    private func translateSelectedText() {
        popoverController.close()
        menuController.close()
        clipboardHistoryPanelController.close()

        do {
            let text = try selectedTextReader.selectedText(promptForPermission: true)
            translationViewModel.prepareSelectedText(text)
            translationPanelController.show()
            translationViewModel.startTranslation()
        } catch TranslationError.accessibilityPermissionRequired {
            translationViewModel.prepareManualInput(notice: .accessibilityPermissionRequired)
            translationPanelController.show()
        } catch {
            translationViewModel.prepareManualInput(notice: .noSelectedText)
            translationPanelController.show()
        }
    }

    private func showTranslationSettings() {
        popoverController.close()
        menuController.close()
        clipboardHistoryPanelController.close()
        translationSettingsWindowController.show()
    }

    private func showClipboardHistory() {
        clipboardPasteExecutor.rememberFrontmostApplication()
        popoverController.close()
        menuController.close()
        translationPanelController.close()
        clipboardHistoryPanelController.toggle()
    }

    private func pasteClipboardHistoryItem(_ item: ClipboardHistoryItem) {
        guard clipboardHistoryStore.copyToPasteboard(item) else {
            presentClipboardHistoryFailure(
                message: "无法写回剪贴板",
                informativeText: "请稍后重试，或重新复制这项内容。"
            )
            return
        }

        switch clipboardPasteExecutor.pasteToRememberedApplication() {
        case .pasted:
            break
        case .accessibilityPermissionRequired:
            presentClipboardPastePermissionRequired()
        case .failed:
            presentClipboardHistoryFailure(
                message: "无法自动粘贴",
                informativeText: "内容已复制到剪贴板，你可以手动粘贴。"
            )
        }
    }

    private func presentClipboardPastePermissionRequired() {
        let alert = NSAlert()
        alert.messageText = "需要辅助功能权限"
        alert.informativeText = "内容已复制到剪贴板。授予 Invoker 辅助功能权限后，剪贴板历史可以自动粘贴到前台应用。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "好")

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            selectedTextReader.openAccessibilitySettings()
        }
    }

    private func presentClipboardHistoryFailure(message: String, informativeText: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = informativeText
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")

        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func registerHotKey(
        _ controller: GlobalHotKeyController,
        configuration: GlobalHotKeyConfiguration
    ) {
        do {
            try controller.register()
        } catch {
            presentHotKeyRegistrationFailure(error, configuration: configuration)
        }
    }

    private func presentHotKeyRegistrationFailure(
        _ error: Error,
        configuration: GlobalHotKeyConfiguration
    ) {
        let alert = NSAlert()
        alert.messageText = "\(configuration.displayName)快捷键注册失败"
        alert.informativeText = "\(configuration.shortcutDescription) 可能已被系统或其他应用占用。\n\n\(error.localizedDescription)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")

        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
