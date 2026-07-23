import Foundation

struct TranslationProviderResolution {
    let provider: any TranslationProvider
    let displayModel: String?
    let configurationWarning: String?
}

@MainActor
protocol TranslationProviderResolving: AnyObject {
    func resolveProvider(for id: TranslationProviderID) throws -> TranslationProviderResolution
}

@MainActor
final class TranslationProviderRegistry: TranslationProviderResolving {
    private let settings: TranslationSettingsStore
    private let session: URLSession

    init(
        settings: TranslationSettingsStore,
        session: URLSession = TranslationNetworkSupport.makeEphemeralSession()
    ) {
        self.settings = settings
        self.session = session
    }

    func resolveProvider(for id: TranslationProviderID) throws -> TranslationProviderResolution {
        switch id {
        case .openAICompatible:
            let configuration = try settings.resolveAIConfiguration()
            return TranslationProviderResolution(
                provider: OpenAICompatibleTranslationProvider(
                    configuration: OpenAICompatibleConfiguration(
                        baseURL: configuration.baseURL,
                        model: configuration.model,
                        apiKey: configuration.apiKey
                    ),
                    session: session
                ),
                displayModel: configuration.model,
                configurationWarning: configuration.warning
            )
        case .deepL:
            guard !settings.deepLAuthKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw TranslationError.missingConfiguration("请先在设置中填写 DeepL Auth Key。")
            }
            return TranslationProviderResolution(
                provider: DeepLTranslationProvider(
                    configuration: DeepLConfiguration(authKey: settings.deepLAuthKey),
                    session: session
                ),
                displayModel: nil,
                configurationWarning: nil
            )
        }
    }
}
