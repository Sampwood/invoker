import Combine
import Foundation

enum TranslationDefaultsKey {
    static let activeProvider = "translation.activeProvider"
    static let aiBaseURL = "translation.ai.endpoint"
    static let aiModel = "translation.ai.model"
    static let aiConfigurationSource = "translation.ai.configurationSource"
    static let preferredLanguage = "translation.preferredLanguage"
    static let secondaryLanguage = "translation.secondaryLanguage"
    static let secretFileMigrationVersion = "translation.secretFileMigrationVersion"
}

enum TranslationSecretAccount {
    static let aiAPIKey = "openai-compatible-api-key"
    static let deepLAuthKey = "deepl-auth-key"
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
            if aiConfigurationSource == .manual {
                effectiveAIModel = aiModel
            }
        }
    }

    @Published var aiModel: String {
        didSet {
            userDefaults.set(aiModel, forKey: TranslationDefaultsKey.aiModel)
            if aiConfigurationSource == .manual {
                effectiveAIModel = aiModel
            }
        }
    }

    @Published var aiConfigurationSource: AIConfigurationSource {
        didSet {
            userDefaults.set(
                aiConfigurationSource.rawValue,
                forKey: TranslationDefaultsKey.aiConfigurationSource
            )
            aiConfigurationWarning = nil
            if aiConfigurationSource == .manual {
                effectiveAIModel = aiModel
            } else {
                refreshCCSwitchConfiguration()
            }
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
            persistSecrets()
        }
    }

    @Published var deepLAuthKey: String {
        didSet {
            persistSecrets()
        }
    }

    @Published private(set) var persistenceErrorMessage: String?
    @Published private(set) var ccSwitchPreview: CCSwitchConfigurationPreview?
    @Published private(set) var ccSwitchErrorMessage: String?
    @Published private(set) var aiConfigurationWarning: String?
    @Published private(set) var effectiveAIModel: String

    private let userDefaults: UserDefaults
    private let secretStore: any TranslationSecretStoring
    private let ccSwitchReader: any CCSwitchAIConfigurationReading
    private let aiConfigurationResolver: any AIConfigurationResolving
    private var canPersistSecrets: Bool
    private var isRepairingLanguages = false

    init(
        userDefaults: UserDefaults = .standard,
        secretStore: any TranslationSecretStoring = TranslationSecretFileStore(),
        legacyKeychain: (any LegacyKeychainStoring)? = LegacyKeychainStore(),
        ccSwitchReader: any CCSwitchAIConfigurationReading = CCSwitchAIConfigurationReader()
    ) {
        self.userDefaults = userDefaults
        self.secretStore = secretStore
        self.ccSwitchReader = ccSwitchReader
        aiConfigurationResolver = AIConfigurationResolver(ccSwitchReader: ccSwitchReader)

        activeProvider = TranslationProviderID(
            rawValue: userDefaults.string(forKey: TranslationDefaultsKey.activeProvider) ?? ""
        ) ?? .openAICompatible
        let initialAIBaseURL = userDefaults.string(forKey: TranslationDefaultsKey.aiBaseURL)
            ?? Self.defaultAIBaseURL
        let initialAIModel = userDefaults.string(forKey: TranslationDefaultsKey.aiModel)
            ?? Self.defaultAIModel
        aiBaseURL = initialAIBaseURL
        aiModel = initialAIModel

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

        let secretLoad = Self.loadAndMigrateSecrets(
            userDefaults: userDefaults,
            secretStore: secretStore,
            legacyKeychain: legacyKeychain
        )
        aiAPIKey = secretLoad.secrets.aiAPIKey
        deepLAuthKey = secretLoad.secrets.deepLAuthKey
        persistenceErrorMessage = secretLoad.errorMessage
        canPersistSecrets = secretLoad.canPersist

        let initialCCSwitchConfiguration: CCSwitchAIConfiguration?
        let initialCCSwitchError: String?
        do {
            let configuration = try ccSwitchReader.currentConfiguration()
            initialCCSwitchConfiguration = configuration
            do {
                _ = try configuration.resolvedConfiguration()
                initialCCSwitchError = nil
            } catch {
                initialCCSwitchError = error.localizedDescription
            }
        } catch {
            initialCCSwitchConfiguration = nil
            initialCCSwitchError = error.localizedDescription
        }

        let storedSource = AIConfigurationSource(
            rawValue: userDefaults.string(forKey: TranslationDefaultsKey.aiConfigurationSource) ?? ""
        )
        let initialSource: AIConfigurationSource
        if let storedSource {
            initialSource = storedSource
        } else if initialCCSwitchConfiguration != nil, initialCCSwitchError == nil {
            initialSource = .ccSwitch
        } else {
            initialSource = .manual
        }
        aiConfigurationSource = initialSource
        ccSwitchPreview = initialCCSwitchConfiguration?.preview
        ccSwitchErrorMessage = initialCCSwitchError
        aiConfigurationWarning = nil
        effectiveAIModel = initialSource == .ccSwitch
            ? initialCCSwitchConfiguration?.model ?? initialAIModel
            : initialAIModel

        if storedSource == nil {
            userDefaults.set(
                initialSource.rawValue,
                forKey: TranslationDefaultsKey.aiConfigurationSource
            )
        }

        persistLanguages()
    }

    func resolveAIConfiguration() throws -> ResolvedAIConfiguration {
        let manualConfiguration = ManualAIConfiguration(
            baseURL: aiBaseURL,
            model: aiModel,
            apiKey: aiAPIKey
        )

        do {
            let resolved = try aiConfigurationResolver.resolve(
                source: aiConfigurationSource,
                manualConfiguration: manualConfiguration
            )
            effectiveAIModel = resolved.model
            aiConfigurationWarning = resolved.warning

            if resolved.source == .ccSwitch {
                ccSwitchPreview = CCSwitchConfigurationPreview(
                    providerName: resolved.providerName ?? "CC Switch",
                    baseURL: resolved.baseURL,
                    model: resolved.model,
                    authenticationStatus: resolved.apiKey.isEmpty ? .notRequired : .configured
                )
                ccSwitchErrorMessage = nil
            } else if aiConfigurationSource == .ccSwitch {
                ccSwitchErrorMessage = resolved.warning
            }
            return resolved
        } catch {
            aiConfigurationWarning = nil
            if aiConfigurationSource == .ccSwitch {
                ccSwitchErrorMessage = error.localizedDescription
            }
            throw error
        }
    }

    func refreshCCSwitchConfiguration() {
        do {
            let configuration = try ccSwitchReader.currentConfiguration()
            ccSwitchPreview = configuration.preview
            do {
                let resolved = try configuration.resolvedConfiguration()
                ccSwitchErrorMessage = nil
                if aiConfigurationSource == .ccSwitch {
                    effectiveAIModel = resolved.model
                }
            } catch {
                ccSwitchErrorMessage = error.localizedDescription
            }
        } catch {
            ccSwitchPreview = nil
            ccSwitchErrorMessage = error.localizedDescription
        }
    }

    private func persistSecrets() {
        if !canPersistSecrets {
            do {
                _ = try secretStore.load()
                canPersistSecrets = true
            } catch {
                persistenceErrorMessage = "无法读取密钥配置 \(secretStore.fileURL.path)：\(error.localizedDescription)"
                return
            }
        }

        do {
            try secretStore.save(
                TranslationSecrets(aiAPIKey: aiAPIKey, deepLAuthKey: deepLAuthKey)
            )
            persistenceErrorMessage = nil
        } catch {
            persistenceErrorMessage = "无法保存密钥配置 \(secretStore.fileURL.path)：\(error.localizedDescription)"
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

    private static func loadAndMigrateSecrets(
        userDefaults: UserDefaults,
        secretStore: any TranslationSecretStoring,
        legacyKeychain: (any LegacyKeychainStoring)?
    ) -> SecretLoadResult {
        let fileExists = secretStore.fileExists()
        let loadedSecrets: TranslationSecrets
        do {
            loadedSecrets = try secretStore.load()
        } catch {
            return SecretLoadResult(
                secrets: .empty,
                errorMessage: "无法读取密钥配置 \(secretStore.fileURL.path)：\(error.localizedDescription)",
                canPersist: false
            )
        }

        let currentMigrationVersion = userDefaults.integer(
            forKey: TranslationDefaultsKey.secretFileMigrationVersion
        )
        guard currentMigrationVersion < 1, let legacyKeychain else {
            return SecretLoadResult(secrets: loadedSecrets, errorMessage: nil, canPersist: true)
        }

        var migratedSecrets = loadedSecrets
        do {
            if !fileExists {
                migratedSecrets = TranslationSecrets(
                    aiAPIKey: try legacyKeychain.string(for: TranslationSecretAccount.aiAPIKey) ?? "",
                    deepLAuthKey: try legacyKeychain.string(for: TranslationSecretAccount.deepLAuthKey) ?? ""
                )
                if migratedSecrets != .empty {
                    try secretStore.save(migratedSecrets)
                }
            }

            try legacyKeychain.deleteValue(for: TranslationSecretAccount.aiAPIKey)
            try legacyKeychain.deleteValue(for: TranslationSecretAccount.deepLAuthKey)
            userDefaults.set(1, forKey: TranslationDefaultsKey.secretFileMigrationVersion)
            return SecretLoadResult(secrets: migratedSecrets, errorMessage: nil, canPersist: true)
        } catch {
            return SecretLoadResult(
                secrets: migratedSecrets,
                errorMessage: "无法完成旧 Keychain 密钥迁移：\(error.localizedDescription)",
                canPersist: true
            )
        }
    }
}

private struct SecretLoadResult {
    let secrets: TranslationSecrets
    let errorMessage: String?
    let canPersist: Bool
}
