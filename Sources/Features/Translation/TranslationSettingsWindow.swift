import AppKit
import SwiftUI

struct InvokerSettingsView: View {
    @ObservedObject var translationSettings: TranslationSettingsStore
    @ObservedObject var clipboardSettings: ClipboardHistorySettingsStore
    @ObservedObject var clipboardHistoryStore: ClipboardHistoryStore

    var body: some View {
        TabView {
            generalSettings
                .tabItem {
                    Label("通用", systemImage: "gearshape")
                }

            clipboardSettingsView
                .tabItem {
                    Label("剪贴板", systemImage: "clipboard")
                }

            aiSettings
                .tabItem {
                    Label("AI", systemImage: "sparkles")
                }

            deepLSettings
                .tabItem {
                    Label("DeepL", systemImage: "character.book.closed")
                }
        }
        .padding(18)
        .frame(width: 560, height: 520)
    }

    private var generalSettings: some View {
        Form {
            Picker("首选语言", selection: $translationSettings.preferredLanguage) {
                ForEach(TranslationLanguage.targetLanguages) { language in
                    Text(language.displayName).tag(language)
                }
            }

            Picker("第二语言", selection: $translationSettings.secondaryLanguage) {
                ForEach(TranslationLanguage.targetLanguages) { language in
                    Text(language.displayName).tag(language)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var clipboardSettingsView: some View {
        ClipboardHistorySettingsView(
            settings: clipboardSettings,
            store: clipboardHistoryStore
        )
    }

    private var aiSettings: some View {
        Form {
            Picker("AI 配置来源", selection: $translationSettings.aiConfigurationSource) {
                ForEach(AIConfigurationSource.allCases) { source in
                    Text(source.displayName).tag(source)
                }
            }
            .pickerStyle(.segmented)

            if translationSettings.aiConfigurationSource == .ccSwitch {
                if let preview = translationSettings.ccSwitchPreview {
                    LabeledContent("Provider") {
                        compactValue(preview.providerName)
                    }
                    LabeledContent("Base URL") {
                        compactValue(preview.baseURL)
                    }
                    LabeledContent("Model") {
                        compactValue(preview.model)
                    }
                    LabeledContent("认证", value: preview.authenticationStatus.displayName)
                }

                if let error = translationSettings.ccSwitchErrorMessage {
                    Text(error)
                        .foregroundStyle(.orange)
                        .font(.caption)
                }

                DisclosureGroup("手动回退") {
                    manualAIFields
                }
            } else {
                manualAIFields
            }

            if let error = translationSettings.persistenceErrorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var manualAIFields: some View {
        TextField("Base URL", text: $translationSettings.aiBaseURL)
        TextField("Model", text: $translationSettings.aiModel)
        SecureField("API Key", text: $translationSettings.aiAPIKey)
    }

    private func compactValue(_ value: String) -> some View {
        Text(value)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
    }

    private var deepLSettings: some View {
        Form {
            SecureField("Auth Key", text: $translationSettings.deepLAuthKey)

            if let error = translationSettings.persistenceErrorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ClipboardHistorySettingsView: View {
    @ObservedObject var settings: ClipboardHistorySettingsStore
    @ObservedObject var store: ClipboardHistoryStore

    private let storageOptions = [50, 100, 250, 500]

    var body: some View {
        Form {
            Section("记录") {
                Toggle("记录通用剪贴板", isOn: $settings.capturesUniversalClipboard)

                Stepper(
                    "普通记录：\(settings.maxHistoryItems) 条",
                    value: $settings.maxHistoryItems,
                    in: 50...1_000,
                    step: 50
                )

                Picker("存储上限", selection: $settings.maxStorageMegabytes) {
                    ForEach(storageOptions, id: \.self) { megabytes in
                        Text("\(megabytes) MB").tag(megabytes)
                    }
                }
            }

            Section("密码管理器") {
                ForEach(PasswordManagerCatalog.entries) { entry in
                    Toggle(
                        entry.displayName,
                        isOn: Binding(
                            get: { settings.isPasswordManagerEnabled(entry) },
                            set: { settings.setPasswordManager(entry, enabled: $0) }
                        )
                    )
                }
            }

            Section("忽略应用") {
                ForEach(settings.ignoredApplications) { application in
                    HStack(spacing: 8) {
                        applicationIcon(for: application)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(application.name)
                                .lineLimit(1)
                            Text(application.bundleIdentifier)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 8)

                        Button {
                            settings.removeIgnoredApplication(application)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                        .help("移除忽略规则")
                        .accessibilityLabel("不再忽略 \(application.name)")
                    }
                }

                Button {
                    settings.addIgnoredApplication()
                } label: {
                    Label("添加应用", systemImage: "plus")
                }
            }

            if !store.statusErrorMessages.isEmpty {
                Section("状态") {
                    ForEach(store.statusErrorMessages, id: \.self) { message in
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func applicationIcon(for application: IgnoredClipboardApplication) -> some View {
        if let bundlePath = application.bundlePath {
            Image(nsImage: NSWorkspace.shared.icon(forFile: bundlePath))
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
        } else {
            Image(systemName: "app")
                .frame(width: 24, height: 24)
        }
    }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let translationSettings: TranslationSettingsStore
    private let clipboardSettings: ClipboardHistorySettingsStore
    private let clipboardHistoryStore: ClipboardHistoryStore
    private var window: NSWindow?

    init(
        translationSettings: TranslationSettingsStore,
        clipboardSettings: ClipboardHistorySettingsStore,
        clipboardHistoryStore: ClipboardHistoryStore
    ) {
        self.translationSettings = translationSettings
        self.clipboardSettings = clipboardSettings
        self.clipboardHistoryStore = clipboardHistoryStore
    }

    func show() {
        translationSettings.refreshCCSwitchConfiguration()
        let window = window ?? makeWindow()
        self.window = window
        if !window.isVisible {
            window.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Invoker 设置"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(
            rootView: InvokerSettingsView(
                translationSettings: translationSettings,
                clipboardSettings: clipboardSettings,
                clipboardHistoryStore: clipboardHistoryStore
            )
        )
        return window
    }
}
