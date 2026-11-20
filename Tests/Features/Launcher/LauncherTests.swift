import AppKit
import Carbon
import Combine
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

    func testArithmeticAppearsBeforeMatchesAndInvalidInputSearchesNormally() {
        let model = LauncherSearchViewModel(
            registry: LauncherCommandRegistry(commands: [command("100*2"), command("1Password")]),
            usage: LauncherUsageStore(defaults: defaults()), scan: { [] }
        )
        model.query = "100*2"
        XCTAssertEqual(model.results.map(\.title), ["200", "100*2"])
        XCTAssertEqual(model.selectedCommand()?.title, "200")

        for (query, result) in [("2+3*4", "14"), ("(2+3)*0.5", "2.5"), (" -2 * 3 ", "-6")] {
            model.query = query
            XCTAssertEqual(model.results.map(\.title), [result])
        }

        for query in ["100*", "100"] {
            model.query = query
            XCTAssertEqual(model.results.map(\.title), ["100*2"])
        }
        model.query = "1/0"
        XCTAssertTrue(model.results.isEmpty)
        model.query = "1Password"
        XCTAssertEqual(model.results.map(\.title), ["1Password"])
    }

    func testCalculationCopiesThroughKeyboardAndResultAction() throws {
        let usage = LauncherUsageStore(defaults: defaults())
        let model = LauncherSearchViewModel(registry: LauncherCommandRegistry(), usage: usage, scan: { [] })
        var copies: [String] = []
        let controller = LauncherPanelController(viewModel: model, copyCalculation: { value in
            copies.append(value)
            return true
        })

        for keyCode in [kVK_Return, kVK_ANSI_KeypadEnter] {
            model.query = "100*2"
            let event = try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, characters: "\r",
                charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: UInt16(keyCode)
            ))
            XCTAssertTrue(controller.handleKeyDown(event))
            XCTAssertTrue(model.query.isEmpty)
        }

        controller.execute(.calculation(value: "6.68", quoteTime: Date()))
        XCTAssertEqual(copies, ["200", "200", "6.68"])
        XCTAssertTrue(usage.snapshot().isEmpty)
    }

    func testExchangeRateRequestAndCacheAreScopedToTheKey() async throws {
        var now = ContinuousClock.now
        var requests: [URLRequest] = []
        let client = TwelveDataExchangeRates(load: { request in
            requests.append(request)
            return try rateResponse(request, body: #"{"symbol":"USD/CNY","rate":6.6789,"timestamp":1760000000}"#)
        }, now: { now })

        let quote = try await client.quote(for: "rate-fixture")
        XCTAssertEqual(quote.rate, Decimal(string: "6.6789"))
        XCTAssertEqual(quote.timestamp, 1_760_000_000)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.twelvedata.com/exchange_rate?symbol=USD%2FCNY")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "apikey rate-fixture")

        now += .seconds(59)
        _ = try await client.quote(for: "rate-fixture")
        XCTAssertEqual(requests.count, 1)
        now += .seconds(1)
        _ = try await client.quote(for: "rate-fixture")
        _ = try await client.quote(for: "replacement-fixture")
        XCTAssertEqual(requests.count, 3)
        XCTAssertNil(client.cachedQuote(for: "rate-fixture"))
        XCTAssertEqual(requests.last?.value(forHTTPHeaderField: "Authorization"), "apikey replacement-fixture")
    }

    func testExchangeRateRejectsErrorsAndInvalidQuotes() async {
        let cases: [(Int, String, TwelveDataExchangeRates.LookupError)] = [
            (401, "", .invalidKey), (403, "", .accessDenied), (429, "", .rateLimited),
            (200, #"{"code":429,"status":"error"}"#, .rateLimited),
            (200, #"{"symbol":"USD/CNH","rate":6.67,"timestamp":1760000000}"#, .unavailable),
            (200, #"{"symbol":"USD/CNY","rate":0,"timestamp":1760000000}"#, .unavailable),
            (200, #"{"symbol":"USD/CNY","rate":6.67,"timestamp":0}"#, .unavailable),
        ]
        for (status, body, expected) in cases {
            let client = TwelveDataExchangeRates(load: { try rateResponse($0, status: status, body: body) })
            do {
                _ = try await client.quote(for: "rate-fixture")
                XCTFail("Invalid responses must not produce a quote")
            } catch {
                XCTAssertEqual(error as? TwelveDataExchangeRates.LookupError, expected)
            }
            XCTAssertNil(client.cachedQuote(for: "rate-fixture"))
        }
    }

    func testDollarConversionUsesLatestAmountAndIgnoresLateResponse() async throws {
        let key = RateKeyFixture()
        let requests = AsyncStream<URLRequest>.makeStream()
        var iterator = requests.stream.makeAsyncIterator()
        var finish: CheckedContinuation<(Data, URLResponse), Error>?
        let client = TwelveDataExchangeRates(load: { request in
            try await withCheckedThrowingContinuation { continuation in
                finish = continuation
                requests.continuation.yield(request)
            }
        })
        let model = LauncherSearchViewModel(
            registry: LauncherCommandRegistry(commands: [command("1Password")]),
            usage: LauncherUsageStore(defaults: defaults()), exchangeRateKeys: key.$value,
            exchangeRates: client, scan: { [] }
        )

        model.query = "$1"
        await model.waitForExchangeRateLookup()
        XCTAssertNotNil(model.exchangeRateStatus)
        XCTAssertNil(model.selectedCommand())
        XCTAssertNil(finish)

        key.value = "rate-fixture"
        let firstRequest = await iterator.next()
        let request = try XCTUnwrap(firstRequest)
        XCTAssertNotNil(model.exchangeRateStatus)
        XCTAssertNil(model.selectedCommand())
        model.query = "$12.50"
        let firstResponse = try rateResponse(request, body: #"{"symbol":"USD/CNY","rate":6.6789,"timestamp":1760000000}"#)
        try XCTUnwrap(finish).resume(returning: firstResponse)
        await model.waitForExchangeRateLookup()
        XCTAssertEqual(model.selectedCommand()?.title, "¥83.49")
        XCTAssertFalse(try XCTUnwrap(model.selectedCommand()).subtitle.isEmpty)
        XCTAssertNil(model.exchangeRateStatus)

        model.query = "$1"
        XCTAssertEqual(model.selectedCommand()?.title, "¥6.68")
        key.value = "replacement-fixture"
        let nextRequest = await iterator.next()
        let replacement = try XCTUnwrap(nextRequest)
        XCTAssertEqual(replacement.value(forHTTPHeaderField: "Authorization"), "apikey replacement-fixture")
        XCTAssertNil(model.selectedCommand())

        model.query = "1Password"
        let nextResponse = try rateResponse(replacement, body: #"{"symbol":"USD/CNY","rate":6.5,"timestamp":1760000001}"#)
        try XCTUnwrap(finish).resume(returning: nextResponse)
        await model.waitForExchangeRateLookup()
        XCTAssertEqual(model.results.map(\.title), ["1Password"])
        XCTAssertEqual(model.selectedCommand()?.title, "1Password")
        XCTAssertNil(model.exchangeRateStatus)

        key.value = ""
        model.query = "$1"
        XCTAssertNotNil(model.exchangeRateStatus)
        XCTAssertNil(model.selectedCommand())
    }

    func testFiveRecommendationsFitWhileScanning() {
        let listHeight = LauncherMetrics.rowHeight * 5
            + LauncherMetrics.rowSpacing * 4
            + LauncherMetrics.listVerticalPadding * 2
        XCTAssertGreaterThanOrEqual(
            LauncherMetrics.resultsHeight,
            listHeight + LauncherMetrics.scanStatusHeight
        )
    }

    func testLauncherDoesNotInterceptReturnWhileInputIsMarked() throws {
        let frame = NSRect(x: 0, y: 0, width: 200, height: 40)
        let panel = LauncherPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                  backing: .buffered, defer: false)
        let editor = NSTextView(frame: frame)
        panel.contentView = editor
        XCTAssertTrue(panel.makeFirstResponder(editor))
        editor.setMarkedText("ji", selectedRange: NSRange(location: 2, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(editor.hasMarkedText())

        var interceptedKeys = 0
        panel.keyDownHandler = { _ in
            interceptedKeys += 1
            return true
        }
        let enter = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: panel.windowNumber, context: nil, characters: "\r",
            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: UInt16(kVK_Return)
        ))

        panel.sendEvent(enter)
        XCTAssertEqual(interceptedKeys, 0)

        editor.unmarkText()
        panel.sendEvent(enter)
        XCTAssertEqual(interceptedKeys, 1)
    }

    func testHoverSelectionDoesNotRequestScrolling() {
        let model = LauncherSearchViewModel(
            registry: LauncherCommandRegistry(commands: (0..<12).map { command("Item\($0)") }),
            usage: LauncherUsageStore(defaults: defaults()), scan: { [] }
        )
        model.query = "Item"
        let items = model.results
        let initialScroll = model.scrollRequestID

        model.select(items[4])
        XCTAssertEqual(model.selectedCommand()?.id, items[4].id)
        XCTAssertEqual(model.scrollRequestID, initialScroll,
                       "Hover must not cause the list to move under the pointer.")

        model.moveSelection(by: 1)
        XCTAssertEqual(model.selectedCommand()?.id, items[5].id)
        XCTAssertNotEqual(model.scrollRequestID, initialScroll)
        let keyboardScroll = model.scrollRequestID

        model.select(items[8])
        XCTAssertEqual(model.scrollRequestID, keyboardScroll)
        model.moveSelection(by: -3)
        XCTAssertEqual(model.selectedCommand()?.id, items[5].id)
        XCTAssertNotEqual(model.scrollRequestID, keyboardScroll,
                          "Returning to an earlier keyboard target must still reveal it.")

        model.select(items[0])
        let beforeQuery = model.scrollRequestID
        model.query = " Item "
        XCTAssertEqual(model.selectedCommand()?.id, items[0].id)
        XCTAssertNotEqual(model.scrollRequestID, beforeQuery,
                          "A new query must reveal the first result even when its ID is unchanged.")

        let beforeBoundary = model.scrollRequestID
        model.moveSelection(by: -1)
        XCTAssertEqual(model.selectedCommand()?.id, items[0].id)
        XCTAssertNotEqual(model.scrollRequestID, beforeBoundary,
                          "A boundary key must reveal a selection scrolled away manually.")
        model.query = "no matching fixture"
        model.moveSelection(by: 1)
        XCTAssertNil(model.selectedCommand())
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

    func testSearchFindsSystemAppsByChineseNameAndFilename() async throws {
        let languages = [Locale.Language(identifier: "zh-Hans-CN")]
        let urls = [
            URL(fileURLWithPath: "/System/Applications/Calculator.app"),
            URL(fileURLWithPath: "/System/Applications/Utilities/Screen Sharing.app")
        ]
        let applications = try urls.map { url in
            try XCTUnwrap(LauncherApplicationScanner.application(at: url, preferredLanguages: languages))
        }
        let model = LauncherSearchViewModel(
            registry: LauncherCommandRegistry(),
            usage: LauncherUsageStore(defaults: defaults()),
            scan: { applications }
        )
        model.prepare()
        await model.waitForRefresh()

        for (application, title) in zip(applications, ["计算器", "屏幕共享"]) {
            model.query = title
            XCTAssertEqual(model.results.map(\.id), [application.id])
            XCTAssertEqual(model.results.first?.title, title)
            model.query = application.fileName
            XCTAssertEqual(model.results.map(\.id), [application.id])
        }
    }

    func testSearchMatchesPinyinForAppsAndCommands() async {
        let calculator = app("计算器", path: "/Applications/Calculator.app")
        let screenSharing = app("屏幕共享", path: "/Applications/Screen Sharing.app")
        let literalMatch = app("Jisuanqi")
        let model = LauncherSearchViewModel(
            registry: LauncherCommandRegistry(commands: [command("打开日历")]),
            usage: LauncherUsageStore(defaults: defaults()),
            scan: { [calculator, screenSharing, literalMatch] }
        )
        model.prepare()
        await model.waitForRefresh()

        model.query = "jisuanqi"
        XCTAssertEqual(model.results.map(\.id), [literalMatch.id, calculator.id])
        model.query = " PING MU "
        XCTAssertEqual(model.results.map(\.id), [screenSharing.id])
        model.query = "dakai ri li"
        XCTAssertEqual(model.selectedCommand()?.title, "打开日历")
        model.query = "jqq"
        XCTAssertTrue(model.results.isEmpty)
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

private func rateResponse(_ request: URLRequest, status: Int = 200, body: String) throws -> (Data, URLResponse) {
    let url = try XCTUnwrap(request.url)
    let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil))
    return (Data(body.utf8), response)
}

private final class RateKeyFixture {
    @Published var value = ""
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
