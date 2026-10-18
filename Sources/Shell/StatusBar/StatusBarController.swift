import AppKit

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popoverController: CalendarPopoverPanelController
    private let clipboardHistoryStore: ClipboardHistoryStore
    private let clipboardHistorySettings: ClipboardHistorySettingsStore
    private let clipboardPasteExecutor: ClipboardPasteExecutor
    private let translationSettings: TranslationSettingsStore
    private let translationViewModel: TranslationViewModel
    private let selectedTextReader: SelectedTextReading
    private let updateChecker = UpdateChecker()
    private lazy var launcherRegistry = LauncherCommandRegistry(commands: [
        LauncherCommand(
            id: "translation.manual",
            title: "翻译输入内容",
            subtitle: "打开翻译面板，输入要翻译的文字",
            keywords: ["翻译", "translate", "translation", "AI", "DeepL"],
            systemImage: "character.bubble",
            shortcut: nil,
            action: { [weak self] in
                self?.showManualTranslation()
            }
        ),
        LauncherCommand(
            id: "translation.selection",
            title: "翻译选中文本",
            subtitle: "读取当前应用中的选中文本并翻译",
            keywords: ["翻译", "selected text", "selection"],
            systemImage: "text.viewfinder",
            shortcut: "⌥F",
            action: { [weak self] in
                self?.translateSelectedText()
            }
        ),
        LauncherCommand(
            id: "clipboard.history",
            title: "剪贴板历史",
            subtitle: "搜索并粘贴最近复制的内容",
            keywords: ["剪贴板", "clipboard", "paste", "复制"],
            systemImage: "clipboard",
            shortcut: "⇧⌘V",
            action: { [weak self] in
                self?.showClipboardHistory()
            }
        ),
        LauncherCommand(
            id: "system.monitor",
            title: "系统监控",
            subtitle: "查看 CPU、内存、磁盘和运行时间",
            keywords: ["系统", "监控", "system", "monitor", "CPU", "memory", "disk"],
            systemImage: "waveform.path.ecg",
            shortcut: nil,
            action: { [weak self] in
                self?.showSystemMonitor()
            }
        ),
        LauncherCommand(
            id: "calendar.open",
            title: "打开日历",
            subtitle: "查看当前月份和日期",
            keywords: ["日历", "calendar", "date", "日期"],
            systemImage: "calendar",
            shortcut: nil,
            action: { [weak self] in
                self?.showCalendarFromLauncher()
            }
        ),
        LauncherCommand(
            id: "settings.open",
            title: "Invoker 设置",
            subtitle: "配置翻译、剪贴板和应用选项",
            keywords: ["设置", "settings", "preferences", "配置"],
            systemImage: "gearshape",
            shortcut: nil,
            action: { [weak self] in
                self?.showTranslationSettings()
            }
        ),
        LauncherCommand(
            id: "updates.check",
            title: "检查更新",
            subtitle: "检查 Invoker 是否有新版本",
            keywords: ["更新", "update", "version"],
            systemImage: "arrow.clockwise",
            shortcut: nil,
            action: { [weak self] in
                self?.updateChecker.checkForUpdates()
            }
        ),
        LauncherCommand(
            id: "app.quit",
            title: "退出 Invoker",
            subtitle: "关闭菜单栏应用",
            keywords: ["退出", "quit", "close"],
            systemImage: "power",
            shortcut: "⌘Q",
            action: {
                NSApp.terminate(nil)
            }
        )
    ])
    private lazy var launcherPanelController = LauncherPanelController(
        registry: launcherRegistry
    )
    private lazy var settingsWindowController = SettingsWindowController(
        translationSettings: translationSettings,
        clipboardSettings: clipboardHistorySettings,
        clipboardHistoryStore: clipboardHistoryStore
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
    private lazy var launcherHotKeyController = GlobalHotKeyController(
        configuration: .launcher
    ) { [weak self] in
        self?.showLauncher()
    }
    private lazy var clipboardHistoryPanelController = ClipboardHistoryPanelController(
        store: clipboardHistoryStore
    ) { [weak self] item in
        self?.pasteClipboardHistoryItem(item)
    }
    private lazy var systemMonitorPanelController = SystemMonitorPanelController()
    private lazy var menuController = StatusBarMenuPanelController(
        translationAction: { [weak self] in
            self?.showManualTranslation()
        },
        clipboardHistoryAction: { [weak self] in
            self?.showClipboardHistory()
        },
        systemMonitorAction: { [weak self] in
            self?.showSystemMonitor()
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
        let clipboardHistorySettings = ClipboardHistorySettingsStore()
        self.clipboardHistorySettings = clipboardHistorySettings
        clipboardHistoryStore = ClipboardHistoryStore(settings: clipboardHistorySettings)
        clipboardPasteExecutor = ClipboardPasteExecutor()
        self.translationSettings = translationSettings
        translationViewModel = TranslationViewModel(
            settings: translationSettings,
            providerRegistry: translationProviderRegistry
        )
        self.selectedTextReader = selectedTextReader
        super.init()

        configureStatusItem()
        monitorStatusIconDateChanges()
        registerHotKey(translationHotKeyController, configuration: .selectionTranslation)
        registerHotKey(clipboardHistoryHotKeyController, configuration: .clipboardHistory)
        registerHotKey(launcherHotKeyController, configuration: .launcher)
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
        updateStatusIcon()
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "Invoker Calendar"
    }

    private func monitorStatusIconDateChanges() {
        let notificationCenter = NotificationCenter.default
        let selector = #selector(systemDateDidChange(_:))

        notificationCenter.addObserver(
            self,
            selector: selector,
            name: .NSCalendarDayChanged,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: selector,
            name: .NSSystemClockDidChange,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: selector,
            name: .NSSystemTimeZoneDidChange,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: selector,
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private nonisolated func systemDateDidChange(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.updateStatusIcon()
        }
    }

    private func updateStatusIcon() {
        statusItem.button?.image = CalendarStatusIconRenderer.image(
            for: Date(),
            calendar: .autoupdatingCurrent
        )
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
        launcherPanelController.close()
        systemMonitorPanelController.close()
        menuController.close()
        clipboardHistoryPanelController.close()
        popoverController.toggle(relativeTo: button)
    }

    private func showContextMenu(from button: NSStatusBarButton) {
        launcherPanelController.close()
        systemMonitorPanelController.close()
        popoverController.close()
        clipboardHistoryPanelController.close()
        menuController.toggle(relativeTo: button)
    }

    private func showManualTranslation() {
        launcherPanelController.close()
        systemMonitorPanelController.close()
        popoverController.close()
        menuController.close()
        clipboardHistoryPanelController.close()
        translationViewModel.prepareManualInput()
        translationPanelController.show()
    }

    private func translateSelectedText() {
        launcherPanelController.close()
        systemMonitorPanelController.close()
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
        launcherPanelController.close()
        systemMonitorPanelController.close()
        popoverController.close()
        menuController.close()
        clipboardHistoryPanelController.close()
        settingsWindowController.show()
    }

    private func showClipboardHistory() {
        launcherPanelController.close()
        systemMonitorPanelController.close()
        clipboardPasteExecutor.rememberFrontmostApplication()
        popoverController.close()
        menuController.close()
        translationPanelController.close()
        clipboardHistoryPanelController.toggle()
    }

    private func showLauncher() {
        systemMonitorPanelController.close()
        popoverController.close()
        menuController.close()
        clipboardHistoryPanelController.close()
        translationPanelController.close()
        launcherPanelController.toggle()
    }

    private func showSystemMonitor() {
        launcherPanelController.close()
        popoverController.close()
        menuController.close()
        clipboardHistoryPanelController.close()
        translationPanelController.close()
        systemMonitorPanelController.toggle()
    }

    private func showCalendarFromLauncher() {
        guard let button = statusItem.button else {
            return
        }
        toggleCalendar(from: button)
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
