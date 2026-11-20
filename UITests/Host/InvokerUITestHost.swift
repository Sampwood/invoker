import AppKit
import SwiftUI

@main
@MainActor
struct InvokerUITestHost {
    static func main() {
        let application = NSApplication.shared
        let delegate = UITestAppDelegate()
        application.delegate = delegate
        application.run()
    }
}

@MainActor
private final class UITestAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var launcher: LauncherPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        precondition(Bundle.main.bundleIdentifier == "com.sampwood.invoker.uitesthost")
        guard let path = ProcessInfo.processInfo.environment["INVOKER_UI_TEST_DATA_DIR"],
              path.hasPrefix("/"),
              URL(fileURLWithPath: path).lastPathComponent == "com.sampwood.invoker.uitesthost" else {
            fatalError("An isolated UI test data directory is required.")
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: directory.appendingPathComponent("launcher-usage.json"), options: .atomic)
        } catch {
            fatalError("Cannot initialize UI test data: \(error)")
        }

        let actions = UITestActions(directory: directory)
        let registry = LauncherCommandRegistry(commands: [
            LauncherCommand(
                id: "fixture-calendar", title: "Fixture Calendar",
                subtitle: "Deterministic UI test command", keywords: ["calendar", "90001"],
                systemImage: "calendar", shortcut: nil,
                action: { actions.record("command:fixture-calendar") }
            ),
            LauncherCommand(
                id: "fixture-clipboard", title: "Fixture Clipboard",
                subtitle: "Another fixed command", keywords: ["clipboard"],
                systemImage: "clipboard", shortcut: nil,
                action: { actions.record("command:fixture-clipboard") }
            ),
            LauncherCommand(
                id: "fixture-long", title: "Fixture Long " + String(repeating: "长名称 Long name ", count: 12),
                subtitle: String(repeating: "长描述 Long description ", count: 16), keywords: ["long", "90003"],
                systemImage: "text.alignleft", shortcut: "⇧⌘V",
                action: { actions.record("command:fixture-long") }
            )
        ] + (0..<12).map { index in
            let suffix = String(format: "%02d", index)
            return LauncherCommand(
                id: "fixture-row-\(suffix)", title: "Fixture Row \(suffix)",
                subtitle: "Fixed long-list fixture", keywords: ["row", "90004"],
                systemImage: "list.bullet", shortcut: nil,
                action: { actions.record("command:fixture-row-\(suffix)") }
            )
        })
        let scanGate = ProcessInfo.processInfo.environment["INVOKER_UI_TEST_SCAN_GATE"]
        let model = LauncherSearchViewModel(
            registry: registry,
            usage: LauncherUsageStore(defaults: UITestUsageDefaults(
                directory: directory, key: LauncherUsageStore.key
            )),
            launcher: actions,
            scan: {
                if let scanGate {
                    while !FileManager.default.fileExists(atPath: scanGate) {
                        try? await Task.sleep(for: .milliseconds(50))
                    }
                }
                return [LauncherApplication(
                    url: URL(fileURLWithPath: "/InvokerUITestFixtures/Fixture Notes.app"),
                    title: "Fixture Notes"
                )]
            }
        )
        let launcher = LauncherPanelController(viewModel: model)
        self.launcher = launcher

        NSApp.setActivationPolicy(.regular)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.title = "Invoker UI Test Host"
        window.contentView = NSHostingView(rootView:
            Button("Open Launcher") {
                launcher.show()
                // Hover tests inject their list; the smoke test separately covers real typing.
                model.query = ProcessInfo.processInfo.environment["INVOKER_UI_TEST_QUERY"] ?? ""
            }
                .accessibilityIdentifier("uitest.open-launcher")
                .frame(width: 320, height: 120)
        )
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }
}

// The existing usage-store injection stays entirely inside the per-run test directory.
private final class UITestUsageDefaults: UserDefaults, @unchecked Sendable {
    private var fileURL: URL?
    private var usageKey: String?

    convenience init(directory: URL, key: String) {
        self.init()
        fileURL = directory.appendingPathComponent("launcher-usage.json")
        usageKey = key
    }

    override func data(forKey defaultName: String) -> Data? {
        precondition(defaultName == usageKey)
        guard let fileURL else { fatalError("UI test storage must be configured.") }
        do { return try Data(contentsOf: fileURL) }
        catch { fatalError("Cannot read UI test usage: \(error)") }
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        precondition(defaultName == usageKey)
        guard let fileURL else { fatalError("UI test storage must be configured.") }
        guard let data = value as? Data else { fatalError("Expected encoded launcher usage.") }
        do { try data.write(to: fileURL, options: .atomic) }
        catch { fatalError("Cannot write UI test usage: \(error)") }
    }
}

@MainActor
private struct UITestActions: LauncherApplicationLaunching {
    let directory: URL

    func open(_ application: LauncherApplication) async throws {
        record(application.id)
    }

    func record(_ action: String) {
        do {
            try Data(action.utf8).write(
                to: directory.appendingPathComponent("last-action.txt"), options: .atomic
            )
        } catch {
            fatalError("Cannot record UI test action: \(error)")
        }
    }
}
