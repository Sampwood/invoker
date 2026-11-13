import AppKit
import XCTest
@testable import Invoker

@MainActor
final class LauncherTests: XCTestCase {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "Invoker.LauncherTests." + UUID().uuidString)!
    }
    private func command(_ name: String) -> LauncherCommand {
        LauncherCommand(id: name, title: name, subtitle: "description", keywords: ["keyword"],
                        systemImage: "gear", shortcut: nil, action: {})
    }
    private func app(_ name: String, path: String? = nil) -> LauncherApplication {
        LauncherApplication(url: URL(fileURLWithPath: path ?? "/Applications/\(name).app"), title: name)
    }

    func testUsageWindowPersistenceAndCorruptFallback() {
        let storage = defaults()
        var date = Date(timeIntervalSince1970: 10_000_000)
        let store = LauncherUsageStore(defaults: storage, now: { date })
        store.record("app:a")
        date = date.addingTimeInterval(LauncherUsageStore.window)
        XCTAssertEqual(store.snapshot()["app:a"]?.count, 1)
        store.record("command:b")
        let restored = LauncherUsageStore(defaults: storage, now: { date })
        XCTAssertEqual(restored.snapshot()["command:b"]?.count, 1)
        date = date.addingTimeInterval(1)
        XCTAssertNil(store.snapshot()["app:a"])
        storage.set(Data("bad".utf8), forKey: LauncherUsageStore.key)
        XCTAssertTrue(LauncherUsageStore(defaults: storage).snapshot().isEmpty)
    }

    func testRecommendationsAndFrequencyBeforeMatchQuality() async {
        let usage = LauncherUsageStore(defaults: defaults())
        let chrome = app("Google Chrome")
        let exact = app("Chrome")
        usage.record(chrome.id)
        usage.record(chrome.id)
        usage.record(exact.id)
        let model = LauncherSearchViewModel(
            registry: LauncherCommandRegistry(commands: (0..<8).map { command("Command\($0)") }),
            usage: usage, scan: { [chrome, exact] })
        model.prepare()
        await model.waitForRefresh()
        XCTAssertEqual(model.results.count, 5)
        XCTAssertEqual(model.results.first?.id, chrome.id)
        model.query = " CHROME "
        XCTAssertEqual(model.results.map(\.id), [chrome.id, exact.id])
        model.query = "Command"
        XCTAssertEqual(model.results.count, 8)
        model.query = "unknown"
        XCTAssertTrue(model.results.isEmpty)
        XCTAssertNil(model.selectedCommand())
        model.query = "keyword"
        XCTAssertEqual(model.results.count, 8)
    }

    func testAliasesSelectionAndNoPathSearch() async {
        let application = app("日历", path: "/Applications/Calendar.app")
        let model = LauncherSearchViewModel(registry: LauncherCommandRegistry(),
                                           usage: LauncherUsageStore(defaults: defaults()), scan: { [application] })
        model.prepare()
        await model.waitForRefresh()
        XCTAssertEqual(model.results.count, 1)
        model.query = "cal"
        XCTAssertEqual(model.results.first?.id, application.id)
        XCTAssertEqual(model.results.first?.subtitle, "")
        model.query = "/Applications"
        XCTAssertTrue(model.results.isEmpty)
        model.query = "日历"
        model.moveSelection(by: 10)
        XCTAssertEqual(model.selectedCommand()?.id, application.id)
    }

    func testRefreshKeepsCacheAndUsesLatestQuery() async throws {
        let gate = ScanGate()
        let launcher = LaunchStub()
        let application = app("Alpha")
        let model = LauncherSearchViewModel(registry: LauncherCommandRegistry(),
                                           usage: LauncherUsageStore(defaults: defaults()), launcher: launcher, scan: { await gate.scan() })
        model.prepare()
        await gate.finish([application])
        await model.waitForRefresh()
        model.refresh()
        model.refresh()
        XCTAssertTrue(model.isScanning)
        model.query = "Al"
        XCTAssertEqual(model.results.first?.id, application.id)
        try await model.execute(.application(application))
        XCTAssertEqual(launcher.urls, [application.url])
        let focus = model.focusRequestID
        await gate.finish([application, app("Beta")])
        await model.waitForRefresh()
        XCTAssertEqual(model.query, "Al")
        XCTAssertEqual(model.selectedCommand()?.id, application.id)
        XCTAssertEqual(model.focusRequestID, focus)
        let count = await gate.count
        XCTAssertEqual(count, 2)
        model.refresh()
        await gate.finish([])
        await model.waitForRefresh()
        XCTAssertTrue(model.results.isEmpty)
        XCTAssertNil(model.selectedCommand())
    }

    func testRecentUseTieAndStableColdStart() async {
        var date = Date(timeIntervalSince1970: 10_000_000)
        let usage = LauncherUsageStore(defaults: defaults(), now: { date })
        let a = app("Alpha"), b = app("Beta")
        let model = LauncherSearchViewModel(registry: LauncherCommandRegistry(), usage: usage, scan: { [b, a] })
        model.prepare()
        await model.waitForRefresh()
        XCTAssertEqual(model.results.map(\.title), ["Alpha", "Beta"])
        usage.record(a.id)
        date = date.addingTimeInterval(1)
        usage.record(b.id)
        XCTAssertEqual(model.results.first?.id, b.id)
        model.query = "a"
        XCTAssertEqual(model.results.first?.id, b.id)
        model.moveSelection(by: 1)
        XCTAssertEqual(model.selectedCommand()?.id, a.id)
        model.query = "zzz"
        model.moveSelection(by: 1)
        XCTAssertNil(model.selectedCommand())
    }

    func testExecutionRecordsOnlySuccessAndBeforeCommandAction() async throws {
        let usage = LauncherUsageStore(defaults: defaults())
        let launcher = LaunchStub()
        var commandCount = 0
        let cmd = LauncherCommand(id: "quit", title: "Quit", subtitle: "", keywords: [], systemImage: "power", shortcut: nil) {
            XCTAssertEqual(usage.snapshot()["command:quit"]?.count, 1)
            commandCount += 1
        }
        let model = LauncherSearchViewModel(registry: LauncherCommandRegistry(commands: [cmd]),
                                           usage: usage, launcher: launcher, scan: { [] })
        try await model.execute(.command(cmd))
        XCTAssertEqual(commandCount, 1)
        let first = app("Same", path: "/Applications/One.app")
        let second = app("Same", path: "/Applications/Two.app")
        try await model.execute(.application(first))
        XCTAssertEqual(launcher.urls, [first.url])
        XCTAssertEqual(usage.snapshot()[first.id]?.count, 1)
        launcher.fail = true
        do {
            try await model.execute(.application(second))
            XCTFail("Failed launch should throw")
        } catch {}
        XCTAssertEqual(launcher.urls, [first.url, second.url])
        XCTAssertNil(usage.snapshot()[second.id])
    }

    func testScannerBoundariesLinksAndNames() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        func makeApp(_ relative: String, displayName: String? = nil) throws -> URL {
            let url = root.appendingPathComponent(relative)
            let contents = url.appendingPathComponent("Contents")
            try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
            var info = ["CFBundlePackageType": "APPL", "CFBundleExecutable": "run"]
            if let displayName { info["CFBundleDisplayName"] = displayName }
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: contents.appendingPathComponent("Info.plist"))
            FileManager.default.createFile(atPath: contents.appendingPathComponent("MacOS/run").path, contents: Data())
            return url
        }
        let first = try makeApp("Tools/First.app", displayName: "Display")
        _ = try makeApp("Other.app")
        _ = try makeApp("Copy.app", displayName: "Display")
        _ = try makeApp("Tools/First.app/Contents/Helper.app")
        _ = try makeApp(".Hidden.app")
        _ = try makeApp("Archive.bundle/Nested.app")
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Alias.app"), withDestinationURL: first)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Loop"), withDestinationURL: root)
        let scanner = LauncherApplicationScanner(roots: [root, root.appendingPathComponent("Missing")])
        let apps = scanner.scan()
        XCTAssertEqual(apps.count, 3)
        XCTAssertEqual(Set(apps.map(\.title)), Set(["Display", "Other"]))
    }
}

private actor ScanGate {
    var count = 0
    private var continuation: CheckedContinuation<[LauncherApplication], Never>?
    private var buffered: [LauncherApplication]?
    func scan() async -> [LauncherApplication] {
        count += 1
        if let buffered { self.buffered = nil; return buffered }
        return await withCheckedContinuation { continuation = $0 }
    }
    func finish(_ apps: [LauncherApplication]) {
        if let continuation { self.continuation = nil; continuation.resume(returning: apps) }
        else { buffered = apps }
    }
}

@MainActor
private final class LaunchStub: LauncherApplicationLaunching {
    var urls: [URL] = []
    var fail = false
    func open(_ application: LauncherApplication) async throws {
        urls.append(application.url)
        if fail { throw NSError(domain: "test", code: 1) }
    }
}
