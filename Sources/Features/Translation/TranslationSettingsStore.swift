import Combine
import Foundation

enum TranslationDefaultsKey {
    static let activeProvider = "translation.activeProvider"
    static let aiBaseURL = "translation.ai.endpoint"
    static let aiModel = "translation.ai.model"
    static let preferredLanguage = "translation.preferredLanguage"
    static let secondaryLanguage = "translation.secondaryLanguage"
}

enum TranslationSecretAccount {
    static let aiAPIKey = "openai-compatible-api-key"
    static let deepLAuthKey = "deepl-auth-key"
}

protocol KeychainStoring {
    func string(for account: String) throws -> String?
    func set(_ value: String, for account: String) throws
}

@MainActor
final class TranslationSettingsStore: ObservableObject {
    static let defaultAIBaseURL = "https://api.openai.com/v1"
    static let defaultAIModel = "gpt-5-mini"

    @Published var activeProvider: TranslationProviderID {
        didSet {
            userDefaults.set(activeProvider.rawValue, forKey: TranslationDefaultsKey.activeProvider)
        }
    }

    @Published var aiBaseURL: String {
        didSet {
            userDefaults.set(aiBaseURL, forKey: TranslationDefaultsKey.aiBaseURL)
        }
    }

    @Published var aiModel: String {
        didSet {
            userDefaults.set(aiModel, forKey: TranslationDefaultsKey.aiModel)
        }
    }

    @Published var preferredLanguage: TranslationLanguage {
        didSet {
            repairLanguagePair(changedPreferredLanguage: true)
            persistLanguages()
        }
    }

    @Published var secondaryLanguage: TranslationLanguage {
        didSet {
            repairLanguagePair(changedPreferredLanguage: false)
            persistLanguages()
        }
    }

    @Published var aiAPIKey: String {
        didSet {
            persistSecret(aiAPIKey, account: TranslationSecretAccount.aiAPIKey)
        }
    }

    @Published var deepLAuthKey: String {
        didSet {
            persistSecret(deepLAuthKey, account: TranslationSecretAccount.deepLAuthKey)
        }
    }

    @Published private(set) var persistenceErrorMessage: String?

    private let userDefaults: UserDefaults
    private let keychain: KeychainStoring
    private var isRepairingLanguages = false

    init(
        userDefaults: UserDefaults = .standard,
        keychain: KeychainStoring = KeychainStore()
    ) {
        self.userDefaults = userDefaults
        self.keychain = keychain

        activeProvider = TranslationProviderID(
            rawValue: userDefaults.string(forKey: TranslationDefaultsKey.activeProvider) ?? ""
        ) ?? .openAICompatible
        aiBaseURL = userDefaults.string(forKey: TranslationDefaultsKey.aiBaseURL)
            ?? Self.defaultAIBaseURL
        aiModel = userDefaults.string(forKey: TranslationDefaultsKey.aiModel)
            ?? Self.defaultAIModel

        let preferred = TranslationLanguage(
            rawValue: userDefaults.string(forKey: TranslationDefaultsKey.preferredLanguage) ?? ""
        ) ?? .simplifiedChinese
        let secondary = TranslationLanguage(
            rawValue: userDefaults.string(forKey: TranslationDefaultsKey.secondaryLanguage) ?? ""
        ) ?? .english
        let normalizedPreferred = preferred == .automatic ? .simplifiedChinese : preferred
        preferredLanguage = normalizedPreferred
        if secondary == .automatic || secondary == normalizedPreferred {
            secondaryLanguage = normalizedPreferred == .english ? .simplifiedChinese : .english
        } else {
            secondaryLanguage = secondary
        }

        aiAPIKey = (try? keychain.string(for: TranslationSecretAccount.aiAPIKey)) ?? ""
        deepLAuthKey = (try? keychain.string(for: TranslationSecretAccount.deepLAuthKey)) ?? ""
        persistenceErrorMessage = nil
        persistLanguages()
    }

    func isConfigured(_ provider: TranslationProviderID) -> Bool {
        switch provider {
        case .openAICompatible:
            let baseURL = aiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: baseURL),
                  let scheme = url.scheme?.lowercased(),
                  ["http", "https"].contains(scheme),
                  url.host != nil
            else {
                return false
            }
            return !aiModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .deepL:
            return !deepLAuthKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func persistSecret(_ value: String, account: String) {
        do {
            try keychain.set(value, for: account)
            persistenceErrorMessage = nil
        } catch {
            persistenceErrorMessage = "无法保存密钥：\(error.localizedDescription)"
        }
    }

    private func repairLanguagePair(changedPreferredLanguage: Bool) {
        guard !isRepairingLanguages else {
            return
        }

        isRepairingLanguages = true
        defer { isRepairingLanguages = false }

        if preferredLanguage == .automatic {
            preferredLanguage = .simplifiedChinese
        }
        if secondaryLanguage == .automatic {
            secondaryLanguage = .english
        }
        if preferredLanguage == secondaryLanguage {
            if changedPreferredLanguage {
                secondaryLanguage = preferredLanguage == .english ? .simplifiedChinese : .english
            } else {
                preferredLanguage = secondaryLanguage == .simplifiedChinese ? .english : .simplifiedChinese
            }
        }
    }

    private func persistLanguages() {
        userDefaults.set(preferredLanguage.rawValue, forKey: TranslationDefaultsKey.preferredLanguage)
        userDefaults.set(secondaryLanguage.rawValue, forKey: TranslationDefaultsKey.secondaryLanguage)
    }
}
