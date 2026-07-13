import AppKit

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popoverController: CalendarPopoverPanelController
    private let screenshotController: ScreenshotController
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
    private lazy var menuController = StatusBarMenuPanelController(
        translationAction: { [weak self] in
            self?.showManualTranslation()
        },
        screenshotAction: { [weak self] in
            self?.captureSelectionToClipboard()
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

    private func showManualTranslation() {
        popoverController.close()
        menuController.close()
        translationViewModel.prepareManualInput()
        translationPanelController.show()
    }

    private func translateSelectedText() {
        popoverController.close()
        menuController.close()

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
        translationSettingsWindowController.show()
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
