import AppKit
import XCTest

@MainActor
final class LauncherUITests: XCTestCase {
    func testLaunchSearchScreenshotAndTerminate() throws {
        let (app, dataDirectory) = try launchHost()
        let openLauncher = app.buttons["uitest.open-launcher"]
        XCTAssertTrue(openLauncher.waitForExistence(timeout: 10))
        openLauncher.click()

        let searchPredicate = NSPredicate(format: "placeholderValue == %@", "搜索命令或应用")
        let search = app.descendants(matching: .any).matching(searchPredicate).firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        // Wait for the injected scan, rather than a machine-dependent application index.
        XCTAssertTrue(app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Fixture Notes")
        ).firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(app.state, .runningForeground)
        // Numeric fixture keywords stay literal with the user's active IME.
        try pressKeys([25, 29, 29, 29, 18], in: app) // 90001
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertEqual(search.value as? String, "90001")
        let match = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Fixture Calendar")
        )
        XCTAssertTrue(match.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(match.count, 1)
        XCTAssertFalse(app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Fixture Clipboard")
        ).firstMatch.exists)
        XCTAssertFalse(app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Fixture Notes")
        ).firstMatch.exists)
        XCTAssertEqual(search.value as? String, "90001")

        let window = app.dialogs.containing(searchPredicate).firstMatch
        XCTAssertTrue(window.exists)
        let screenshot = window.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "launcher-search-calendar"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: dataDirectory.appendingPathComponent("last-action.txt").path
        ), "Searching must not execute a command or application.")
    }

    func testHoverStaysStillAndKeyboardRevealsOffscreenSelection() throws {
        let (app, dataDirectory) = try launchHost(query: "90004")
        let openLauncher = app.buttons["uitest.open-launcher"]
        XCTAssertTrue(openLauncher.waitForExistence(timeout: 10))
        openLauncher.click()
        let search = app.descendants(matching: .any).matching(
            NSPredicate(format: "placeholderValue == %@", "搜索命令或应用")
        ).firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertEqual(search.value as? String, "90004")
        let hovered = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Fixture Row 04")
        ).firstMatch
        XCTAssertTrue(hovered.waitForExistence(timeout: 10))
        XCTAssertTrue(hovered.isHittable)
        search.hover()
        let originalFrame = hovered.frame
        hovered.hover()
        let hoverSelected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "selected == true"), object: hovered
        )
        wait(for: [hoverSelected], timeout: 3)

        let unwantedScroll = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                !hovered.isSelected || abs(hovered.frame.minY - originalFrame.minY) > 1
            }, object: nil
        )
        unwantedScroll.isInverted = true
        wait(for: [unwantedScroll], timeout: 1)

        // Keep the pointer over the list while keyboard navigation scrolls underneath it.
        try pressKeys(Array(repeating: 125, count: 5), in: app) // Down
        let keyboardTarget = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Fixture Row 09")
        ).firstMatch
        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "selected == true AND hittable == true"),
            object: keyboardTarget
        )
        wait(for: [selected], timeout: 5)
        XCTAssertEqual(search.value as? String, "90004")
        let window = app.dialogs.containing(
            NSPredicate(format: "placeholderValue == %@", "搜索命令或应用")
        ).firstMatch
        XCTAssertTrue(window.exists)
        let screenshot = window.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "launcher-hover-keyboard-regression"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: dataDirectory.appendingPathComponent("last-action.txt").path
        ))
    }

    func testLongTextKeycapAndExecutionUsingDoubles() throws {
        let (app, dataDirectory) = try launchHost()
        let openLauncher = app.buttons["uitest.open-launcher"]
        XCTAssertTrue(openLauncher.waitForExistence(timeout: 10))
        openLauncher.click()
        let searchPredicate = NSPredicate(format: "placeholderValue == %@", "搜索命令或应用")
        let search = app.descendants(matching: .any).matching(searchPredicate).firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        XCTAssertEqual(app.state, .runningForeground)
        try pressKeys([25, 29, 29, 29, 20], in: app) // 90003
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertEqual(search.value as? String, "90003")
        let longResult = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Fixture Long")
        ).firstMatch
        XCTAssertTrue(longResult.waitForExistence(timeout: 10))
        XCTAssertTrue(longResult.isSelected)
        XCTAssertTrue(longResult.label.contains("⇧⌘V"))
        let window = app.dialogs.containing(searchPredicate).firstMatch
        XCTAssertTrue(window.frame.contains(longResult.frame))
        let screenshot = window.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "launcher-long-text-keycap"
        attachment.lifetime = .keepAlways
        add(attachment)

        let receipt = dataDirectory.appendingPathComponent("last-action.txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: receipt.path))
        longResult.click()
        let clicked = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (try? String(contentsOf: receipt, encoding: .utf8)) == "command:fixture-long"
        }, object: nil)
        wait(for: [clicked], timeout: 5)
        XCTAssertFalse(search.exists)

        openLauncher.click()
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertEqual(search.value as? String, "")
        try pressKeys([25, 29, 29, 29, 18], in: app) // 90001
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertEqual(search.value as? String, "90001")
        XCTAssertTrue(app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Fixture Calendar")
        ).firstMatch.waitForExistence(timeout: 5))
        try pressKeys([36], in: app) // Return
        let entered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (try? String(contentsOf: receipt, encoding: .utf8)) == "command:fixture-calendar"
        }, object: nil)
        wait(for: [entered], timeout: 5)
        XCTAssertFalse(search.exists)
    }

    func testApplicationExecutionUsingDouble() throws {
        let (app, dataDirectory) = try launchHost()
        let openLauncher = app.buttons["uitest.open-launcher"]
        XCTAssertTrue(openLauncher.waitForExistence(timeout: 10))
        openLauncher.click()
        let searchPredicate = NSPredicate(format: "placeholderValue == %@", "搜索命令或应用")
        let search = app.descendants(matching: .any).matching(searchPredicate).firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        let application = app.dialogs.containing(searchPredicate).firstMatch.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Fixture Notes")
        ).firstMatch
        XCTAssertTrue(application.waitForExistence(timeout: 10))
        let receipt = dataDirectory.appendingPathComponent("last-action.txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: receipt.path))
        application.click()
        let applicationID = "app:/InvokerUITestFixtures/Fixture Notes.app"
        let executed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (try? String(contentsOf: receipt, encoding: .utf8)) == applicationID
        }, object: nil)
        wait(for: [executed], timeout: 5)
        XCTAssertFalse(search.exists)
        let usageData = try Data(contentsOf: dataDirectory.appendingPathComponent("launcher-usage.json"))
        let usage = try XCTUnwrap(JSONSerialization.jsonObject(with: usageData) as? [String: [Double]])
        XCTAssertEqual(usage.keys.sorted(), [applicationID])
        XCTAssertEqual(usage[applicationID]?.count, 1)
    }

    func testScanningPreservesTypedQuery() throws {
        let (app, dataDirectory) = try launchHost(holdScan: true)
        let openLauncher = app.buttons["uitest.open-launcher"]
        XCTAssertTrue(openLauncher.waitForExistence(timeout: 10))
        openLauncher.click()
        let searchPredicate = NSPredicate(format: "placeholderValue == %@", "搜索命令或应用")
        let search = app.descendants(matching: .any).matching(searchPredicate).firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        let window = app.dialogs.containing(searchPredicate).firstMatch
        let scanning = window.staticTexts["正在查找应用…"]
        XCTAssertTrue(scanning.waitForExistence(timeout: 5))
        XCTAssertEqual(window.buttons.count, 5)
        for row in window.buttons.allElementsBoundByIndex {
            XCTAssertTrue(window.frame.contains(row.frame))
        }
        let capacity = XCTAttachment(screenshot: window.screenshot())
        capacity.name = "launcher-scanning-five-rows"
        capacity.lifetime = .keepAlways
        add(capacity)

        try pressKeys([25, 29, 29, 29, 18], in: app) // 90001
        XCTAssertEqual(search.value as? String, "90001")
        XCTAssertTrue(scanning.exists)
        let calendar = window.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Fixture Calendar")
        ).firstMatch
        XCTAssertTrue(calendar.isSelected)
        let rowTopWhileScanning = calendar.frame.minY
        let typed = XCTAttachment(screenshot: window.screenshot())
        typed.name = "launcher-scanning-typed-query"
        typed.lifetime = .keepAlways
        add(typed)

        try Data().write(to: try inputDirectory().appendingPathComponent("scan-release"), options: .atomic)
        let finished = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: scanning
        )
        wait(for: [finished], timeout: 5)
        XCTAssertEqual(search.value as? String, "90001")
        XCTAssertTrue(calendar.isSelected)
        XCTAssertEqual(calendar.frame.minY, rowTopWhileScanning, accuracy: 1)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: dataDirectory.appendingPathComponent("last-action.txt").path
        ))
    }

    private func inputDirectory() throws -> URL {
        let root = try XCTUnwrap(ProcessInfo.processInfo.environment["INVOKER_UI_TEST_RUN_ROOT"])
        let directory = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(
            "tmp/\(URL(fileURLWithPath: root).lastPathComponent)", isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    // XCTest keyboard synthesis can trigger input-source consent and steal launcher focus.
    private func pressKeys(_ keyCodes: [CGKeyCode], in app: XCUIApplication) throws {
        XCTAssertEqual(app.state, .runningForeground)
        let hosts = NSRunningApplication.runningApplications(withBundleIdentifier: "com.sampwood.invoker.uitesthost")
        XCTAssertEqual(hosts.count, 1)
        let host = try XCTUnwrap(hosts.first)
        let input = try inputDirectory()
        let id = UUID().uuidString
        let request: [String: Any] = [
            "id": id, "pid": host.processIdentifier,
            "launchTime": try XCTUnwrap(host.launchDate).timeIntervalSince1970, "keys": keyCodes
        ]
        try JSONSerialization.data(withJSONObject: request).write(
            to: input.appendingPathComponent("request.json"), options: .atomic
        )
        let responseURL = input.appendingPathComponent("response.json")
        let delivered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let data = try? Data(contentsOf: responseURL),
                  let response = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return false }
            return response["id"] == id
        }, object: nil)
        wait(for: [delivered], timeout: 5)
        let response = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: responseURL)) as? [String: String])
        XCTAssertEqual(response["error"], "")
    }

    private func launchHost(query: String = "", holdScan: Bool = false) throws -> (XCUIApplication, URL) {
        continueAfterFailure = false
        let hostID = "com.sampwood.invoker.uitesthost"
        let runRoot = try XCTUnwrap(ProcessInfo.processInfo.environment["INVOKER_UI_TEST_RUN_ROOT"])
        XCTAssertTrue(runRoot.hasPrefix("/"), "Run with scripts/ui-test.sh.")
        let dataDirectory = URL(fileURLWithPath: runRoot)
            .appendingPathComponent("Data/\(UUID().uuidString)/\(hostID)", isDirectory: true)
        let developerInstances = Self.developmentInstances()
        let app = XCUIApplication(bundleIdentifier: hostID)
        app.launchEnvironment["INVOKER_UI_TEST_DATA_DIR"] = dataDirectory.path
        app.launchEnvironment["INVOKER_UI_TEST_QUERY"] = query
        if holdScan {
            app.launchEnvironment["INVOKER_UI_TEST_SCAN_GATE"] = try inputDirectory()
                .appendingPathComponent("scan-release").path
        }
        addTeardownBlock { @MainActor in
            app.terminate()
            XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
            XCTAssertEqual(Self.developmentInstances(), developerInstances,
                           "The existing development processes must stay running.")
        }
        app.launch()
        return (app, dataDirectory)
    }

    private static func developmentInstances() -> [String] {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.sampwood.invoker")
            .map { "\($0.processIdentifier):\($0.launchDate?.timeIntervalSince1970 ?? 0)" }
            .sorted()
    }
}
