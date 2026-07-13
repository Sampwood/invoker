import AppKit
import SwiftUI

struct TranslationSettingsView: View {
    @ObservedObject var settings: TranslationSettingsStore

    var body: some View {
        TabView {
            generalSettings
                .tabItem {
                    Label("通用", systemImage: "gearshape")
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
        .frame(width: 520, height: 390)
    }

    private var generalSettings: some View {
        Form {
            Picker("默认翻译服务", selection: $settings.activeProvider) {
                ForEach(TranslationProviderID.allCases) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }

            Picker("首选语言", selection: $settings.preferredLanguage) {
                ForEach(TranslationLanguage.targetLanguages) { language in
                    Text(language.displayName).tag(language)
                }
            }

            Picker("第二语言", selection: $settings.secondaryLanguage) {
                ForEach(TranslationLanguage.targetLanguages) { language in
                    Text(language.displayName).tag(language)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var aiSettings: some View {
        Form {
            TextField("Base URL", text: $settings.aiBaseURL)
            TextField("Model", text: $settings.aiModel)
            SecureField("API Key", text: $settings.aiAPIKey)

            if let error = settings.persistenceErrorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
    }

    private var deepLSettings: some View {
        Form {
            SecureField("Auth Key", text: $settings.deepLAuthKey)

            if let error = settings.persistenceErrorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
    }
}

@MainActor
final class TranslationSettingsWindowController: NSObject, NSWindowDelegate {
    private let settings: TranslationSettingsStore
    private var window: NSWindow?

    init(settings: TranslationSettingsStore) {
        self.settings = settings
    }

    func show() {
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
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 390),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Invoker 设置"
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: TranslationSettingsView(settings: settings))
        return window
    }
}
