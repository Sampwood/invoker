import XCTest
@testable import Invoker

@MainActor
final class TranslationSettingsStoreTests: XCTestCase {
    func testFileStoreWritesExpectedJSONAndPermissions() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("InvokerSecretStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let fileURL = rootURL
            .appendingPathComponent(".invoker", isDirectory: true)
            .appendingPathComponent("config.json")
        let store = TranslationSecretFileStore(fileURL: fileURL)
        let secrets = TranslationSecrets(aiAPIKey: "ai-secret", deepLAuthKey: "deepl-secret")

        try store.save(secrets)

        XCTAssertEqual(try store.load(), secrets)
        let directoryAttributes = try FileManager.default.attributesOfItem(
            atPath: fileURL.deletingLastPathComponent().path
        )
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        XCTAssertEqual((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        XCTAssertEqual((fileAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: String]
        )
        XCTAssertEqual(object["ai_api_key"], "ai-secret")
        XCTAssertEqual(object["deepl_auth_key"], "deepl-secret")
    }

    func testFileStoreDoesNotSilentlyAcceptMalformedJSON() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("InvokerSecretStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let fileURL = rootURL.appendingPathComponent("config.json")
        try Data("{".utf8).write(to: fileURL)
        let store = TranslationSecretFileStore(fileURL: fileURL)

        XCTAssertThrowsError(try store.load())
    }

    func testSecretsAreStoredInConfigFileAndNeverInUserDefaults() throws {
        let suiteName = "TranslationSettingsStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let secretStore = InMemorySecretStore()
        let store = TranslationSettingsStore(
            userDefaults: defaults,
            secretStore: secretStore,
            ccSwitchReader: UnavailableCCSwitchReader()
        )

        store.aiAPIKey = "ai-secret"
        store.deepLAuthKey = "deepl-secret"
        store.activeProvider = .deepL

        XCTAssertEqual(secretStore.secrets, TranslationSecrets(aiAPIKey: "ai-secret", deepLAuthKey: "deepl-secret"))
        XCTAssertEqual(defaults.string(forKey: TranslationDefaultsKey.activeProvider), TranslationProviderID.deepL.rawValue)
        XCTAssertFalse(defaults.dictionaryRepresentation().values.contains { value in
            let string = value as? String
            return string == "ai-secret" || string == "deepl-secret"
        })
    }

    func testMatchingPreferredLanguagesAreRepairedToDistinctDefaults() throws {
        let suiteName = "TranslationSettingsStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(TranslationLanguage.english.rawValue, forKey: TranslationDefaultsKey.preferredLanguage)
        defaults.set(TranslationLanguage.english.rawValue, forKey: TranslationDefaultsKey.secondaryLanguage)

        let store = TranslationSettingsStore(
            userDefaults: defaults,
            secretStore: InMemorySecretStore(),
            ccSwitchReader: UnavailableCCSwitchReader()
        )

        XCTAssertEqual(store.preferredLanguage, .english)
        XCTAssertEqual(store.secondaryLanguage, .simplifiedChinese)
        XCTAssertEqual(store.aiConfigurationSource, .manual)
    }

    func testFirstLaunchDefaultsToValidCCSwitchSourceAndPersistsChoice() throws {
        let suiteName = "TranslationSettingsStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = TranslationSettingsStore(
            userDefaults: defaults,
            secretStore: InMemorySecretStore(),
            ccSwitchReader: ValidCCSwitchReader()
        )

        XCTAssertEqual(store.aiConfigurationSource, .ccSwitch)
        XCTAssertEqual(
            defaults.string(forKey: TranslationDefaultsKey.aiConfigurationSource),
            AIConfigurationSource.ccSwitch.rawValue
        )
        XCTAssertEqual(store.effectiveAIModel, "cc-switch-model")
    }
}

private final class InMemorySecretStore: TranslationSecretStoring {
    let fileURL = URL(fileURLWithPath: "/tmp/invoker-settings-test-config.json")
    private(set) var secrets: TranslationSecrets
    private(set) var hasFile: Bool

    init(secrets: TranslationSecrets = .empty, hasFile: Bool = false) {
        self.secrets = secrets
        self.hasFile = hasFile
    }

    func fileExists() -> Bool {
        hasFile
    }

    func load() throws -> TranslationSecrets {
        secrets
    }

    func save(_ secrets: TranslationSecrets) throws {
        self.secrets = secrets
        hasFile = true
    }
}

private struct UnavailableCCSwitchReader: CCSwitchAIConfigurationReading {
    func currentConfiguration() throws -> CCSwitchAIConfiguration {
        throw AIConfigurationError.ccSwitchDatabaseUnavailable
    }
}

private struct ValidCCSwitchReader: CCSwitchAIConfigurationReading {
    func currentConfiguration() throws -> CCSwitchAIConfiguration {
        CCSwitchAIConfiguration(
            providerName: "Test Provider",
            baseURL: "https://example.test/v1",
            model: "cc-switch-model",
            wireAPI: "responses",
            requiresOpenAIAuth: true,
            apiKey: "cc-switch-key"
        )
    }
}
