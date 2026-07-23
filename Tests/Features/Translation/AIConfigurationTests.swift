import XCTest
import SQLite3
@testable import Invoker

final class AIConfigurationTests: XCTestCase {
    func testCodexProviderTOMLParserReadsCurrentProviderFields() throws {
        let configuration = try CodexProviderTOMLParser().parse(
            """
            model_provider = "custom" # active provider
            model = "gpt-test"

            [model_providers."custom"]
            name = "Custom"
            base_url = "https://example.test/v1"
            wire_api = "responses"
            requires_openai_auth = true
            """
        )

        XCTAssertEqual(configuration.modelProvider, "custom")
        XCTAssertEqual(configuration.model, "gpt-test")
        XCTAssertEqual(configuration.baseURL, "https://example.test/v1")
        XCTAssertEqual(configuration.wireAPI, "responses")
        XCTAssertTrue(configuration.requiresOpenAIAuth)
    }

    func testUnsupportedWireAPIIsRejected() throws {
        let configuration = CCSwitchAIConfiguration(
            providerName: "custom",
            baseURL: "https://example.test/v1",
            model: "gpt-test",
            wireAPI: "chat",
            requiresOpenAIAuth: false,
            apiKey: nil
        )

        XCTAssertThrowsError(try configuration.resolvedConfiguration()) { error in
            XCTAssertEqual((error as? AIConfigurationError)?.localizedDescription, AIConfigurationError.unsupportedWireAPI.localizedDescription)
        }
    }

    func testNoAuthProviderDoesNotRequireAPIKey() throws {
        let configuration = CCSwitchAIConfiguration(
            providerName: "local",
            baseURL: "http://127.0.0.1:8080/v1",
            model: "local-model",
            wireAPI: nil,
            requiresOpenAIAuth: false,
            apiKey: nil
        )

        let resolved = try configuration.resolvedConfiguration()

        XCTAssertEqual(resolved.apiKey, "")
        XCTAssertEqual(resolved.source, .ccSwitch)
    }

    func testCCSwitchFailureUsesManualFallbackWithoutPersistingProviderSecret() throws {
        let resolver = AIConfigurationResolver(ccSwitchReader: FailingCCSwitchReader())

        let resolved = try resolver.resolve(
            source: .ccSwitch,
            manualConfiguration: ManualAIConfiguration(
                baseURL: "https://manual.example/v1",
                model: "manual-model",
                apiKey: "manual-key"
            )
        )

        XCTAssertEqual(resolved.source, .manual)
        XCTAssertEqual(resolved.apiKey, "manual-key")
        XCTAssertNotNil(resolved.warning)
    }

    func testManualSourceDoesNotReadCCSwitch() throws {
        let reader = CountingCCSwitchReader()
        let resolver = AIConfigurationResolver(ccSwitchReader: reader)

        _ = try resolver.resolve(
            source: .manual,
            manualConfiguration: ManualAIConfiguration(
                baseURL: "https://manual.example/v1",
                model: "manual-model",
                apiKey: "manual-key"
            )
        )

        XCTAssertEqual(reader.readCount, 0)
    }

    func testCCSwitchReaderFollowsCurrentCodexProvider() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("InvokerCCSwitchTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let databaseURL = directoryURL.appendingPathComponent("cc-switch.db")
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        let openedDatabase = try XCTUnwrap(database)
        defer { sqlite3_close(openedDatabase) }

        try executeSQL(
            """
            CREATE TABLE providers (
                id TEXT NOT NULL,
                app_type TEXT NOT NULL,
                name TEXT NOT NULL,
                settings_config TEXT NOT NULL,
                sort_index INTEGER,
                is_current INTEGER NOT NULL
            );
            """,
            database: openedDatabase
        )
        try insertProvider(
            id: "first",
            name: "First",
            model: "first-model",
            baseURL: "https://first.example/v1",
            apiKey: "first-key",
            isCurrent: true,
            database: openedDatabase
        )
        try insertProvider(
            id: "second",
            name: "Second",
            model: "second-model",
            baseURL: "https://second.example/v1",
            apiKey: "second-key",
            isCurrent: false,
            database: openedDatabase
        )

        let reader = CCSwitchAIConfigurationReader(databaseURL: databaseURL)
        XCTAssertEqual(try reader.currentConfiguration().model, "first-model")

        try executeSQL(
            "UPDATE providers SET is_current = CASE id WHEN 'second' THEN 1 ELSE 0 END;",
            database: openedDatabase
        )

        let switched = try reader.currentConfiguration()
        XCTAssertEqual(switched.providerName, "Second")
        XCTAssertEqual(switched.model, "second-model")
        XCTAssertEqual(switched.apiKey, "second-key")
    }
}

private struct FailingCCSwitchReader: CCSwitchAIConfigurationReading {
    func currentConfiguration() throws -> CCSwitchAIConfiguration {
        throw AIConfigurationError.ccSwitchDatabaseUnavailable
    }
}

private final class CountingCCSwitchReader: CCSwitchAIConfigurationReading {
    private(set) var readCount = 0

    func currentConfiguration() throws -> CCSwitchAIConfiguration {
        readCount += 1
        throw AIConfigurationError.ccSwitchDatabaseUnavailable
    }
}

private func insertProvider(
    id: String,
    name: String,
    model: String,
    baseURL: String,
    apiKey: String,
    isCurrent: Bool,
    database: OpaquePointer
) throws {
    let config = """
    model_provider = "custom"
    model = "\(model)"
    [model_providers.custom]
    base_url = "\(baseURL)"
    wire_api = "responses"
    requires_openai_auth = true
    """
    let data = try JSONSerialization.data(
        withJSONObject: [
            "auth": ["OPENAI_API_KEY": apiKey],
            "config": config,
        ]
    )
    let settingsJSON = try XCTUnwrap(String(data: data, encoding: .utf8))
    let escapedSettings = settingsJSON.replacingOccurrences(of: "'", with: "''")
    let escapedName = name.replacingOccurrences(of: "'", with: "''")
    try executeSQL(
        """
        INSERT INTO providers (id, app_type, name, settings_config, sort_index, is_current)
        VALUES ('\(id)', 'codex', '\(escapedName)', '\(escapedSettings)', 0, \(isCurrent ? 1 : 0));
        """,
        database: database
    )
}

private func executeSQL(_ sql: String, database: OpaquePointer) throws {
    var errorMessage: UnsafeMutablePointer<CChar>?
    let status = sqlite3_exec(database, sql, nil, nil, &errorMessage)
    defer { sqlite3_free(errorMessage) }
    guard status == SQLITE_OK else {
        let message = errorMessage.map { String(cString: $0) } ?? "SQLite error \(status)"
        throw NSError(domain: "AIConfigurationTests", code: Int(status), userInfo: [NSLocalizedDescriptionKey: message])
    }
}
