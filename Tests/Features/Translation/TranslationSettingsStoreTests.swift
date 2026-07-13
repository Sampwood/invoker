import XCTest
@testable import Invoker

@MainActor
final class TranslationSettingsStoreTests: XCTestCase {
    func testSecretsAreStoredInKeychainAndNeverInUserDefaults() throws {
        let suiteName = "TranslationSettingsStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let keychain = InMemoryKeychainStore()
        let store = TranslationSettingsStore(userDefaults: defaults, keychain: keychain)

        store.aiAPIKey = "ai-secret"
        store.deepLAuthKey = "deepl-secret"
        store.activeProvider = .deepL

        XCTAssertEqual(try keychain.string(for: TranslationSecretAccount.aiAPIKey), "ai-secret")
        XCTAssertEqual(try keychain.string(for: TranslationSecretAccount.deepLAuthKey), "deepl-secret")
        XCTAssertEqual(defaults.string(forKey: TranslationDefaultsKey.activeProvider), TranslationProviderID.deepL.rawValue)
        XCTAssertFalse(defaults.dictionaryRepresentation().values.contains { value in
            let string = value as? String
            return string == "ai-secret" || string == "deepl-secret"
        })

        let reloadedStore = TranslationSettingsStore(userDefaults: defaults, keychain: keychain)
        XCTAssertEqual(reloadedStore.aiAPIKey, "ai-secret")
    }

    func testMatchingPreferredLanguagesAreRepairedToDistinctDefaults() throws {
        let suiteName = "TranslationSettingsStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(TranslationLanguage.english.rawValue, forKey: TranslationDefaultsKey.preferredLanguage)
        defaults.set(TranslationLanguage.english.rawValue, forKey: TranslationDefaultsKey.secondaryLanguage)

        let store = TranslationSettingsStore(userDefaults: defaults, keychain: InMemoryKeychainStore())

        XCTAssertEqual(store.preferredLanguage, .english)
        XCTAssertEqual(store.secondaryLanguage, .simplifiedChinese)
    }
}

private final class InMemoryKeychainStore: KeychainStoring {
    private var values: [String: String] = [:]

    func string(for account: String) throws -> String? {
        values[account]
    }

    func set(_ value: String, for account: String) throws {
        values[account] = value
    }
}
