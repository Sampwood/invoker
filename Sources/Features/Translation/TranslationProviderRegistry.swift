import Foundation

@MainActor
protocol TranslationProviderResolving: AnyObject {
    func provider(for id: TranslationProviderID) -> any TranslationProvider
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

    func provider(for id: TranslationProviderID) -> any TranslationProvider {
        switch id {
        case .openAICompatible:
            return OpenAICompatibleTranslationProvider(
                configuration: OpenAICompatibleConfiguration(
                    baseURL: settings.aiBaseURL,
                    model: settings.aiModel,
                    apiKey: settings.aiAPIKey
                ),
                session: session
            )
        case .deepL:
            return DeepLTranslationProvider(
                configuration: DeepLConfiguration(authKey: settings.deepLAuthKey),
                session: session
            )
        }
    }
}
