import Foundation
import NaturalLanguage

enum TranslationProviderID: String, CaseIterable, Identifiable, Sendable {
    case openAICompatible
    case deepL

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAICompatible:
            return "AI"
        case .deepL:
            return "DeepL"
        }
    }
}

enum TranslationLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
    case automatic = "auto"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case english = "en"
    case japanese = "ja"
    case korean = "ko"
    case french = "fr"
    case german = "de"
    case spanish = "es"
    case portuguese = "pt"
    case italian = "it"
    case russian = "ru"

    static let targetLanguages = allCases.filter { $0 != .automatic }

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic:
            return "自动识别"
        case .simplifiedChinese:
            return "简体中文"
        case .traditionalChinese:
            return "繁体中文"
        case .english:
            return "英语"
        case .japanese:
            return "日语"
        case .korean:
            return "韩语"
        case .french:
            return "法语"
        case .german:
            return "德语"
        case .spanish:
            return "西班牙语"
        case .portuguese:
            return "葡萄牙语"
        case .italian:
            return "意大利语"
        case .russian:
            return "俄语"
        }
    }

    var promptName: String {
        switch self {
        case .automatic:
            return "the automatically detected source language"
        case .simplifiedChinese:
            return "Simplified Chinese"
        case .traditionalChinese:
            return "Traditional Chinese"
        case .english:
            return "English"
        case .japanese:
            return "Japanese"
        case .korean:
            return "Korean"
        case .french:
            return "French"
        case .german:
            return "German"
        case .spanish:
            return "Spanish"
        case .portuguese:
            return "Portuguese"
        case .italian:
            return "Italian"
        case .russian:
            return "Russian"
        }
    }

    var deepLSourceCode: String? {
        switch self {
        case .automatic:
            return nil
        case .simplifiedChinese, .traditionalChinese:
            return "ZH"
        case .english:
            return "EN"
        case .japanese:
            return "JA"
        case .korean:
            return "KO"
        case .french:
            return "FR"
        case .german:
            return "DE"
        case .spanish:
            return "ES"
        case .portuguese:
            return "PT"
        case .italian:
            return "IT"
        case .russian:
            return "RU"
        }
    }

    var deepLTargetCode: String? {
        switch self {
        case .automatic:
            return nil
        case .simplifiedChinese:
            return "ZH-HANS"
        case .traditionalChinese:
            return "ZH-HANT"
        case .english:
            return "EN-US"
        default:
            return deepLSourceCode
        }
    }

    init?(deepLDetectedCode: String) {
        switch deepLDetectedCode.uppercased() {
        case "ZH", "ZH-HANS":
            self = .simplifiedChinese
        case "ZH-HANT":
            self = .traditionalChinese
        case "EN", "EN-US", "EN-GB":
            self = .english
        case "JA":
            self = .japanese
        case "KO":
            self = .korean
        case "FR":
            self = .french
        case "DE":
            self = .german
        case "ES":
            self = .spanish
        case "PT", "PT-PT", "PT-BR":
            self = .portuguese
        case "IT":
            self = .italian
        case "RU":
            self = .russian
        default:
            return nil
        }
    }
}

enum TranslationTargetSelection: Hashable, Sendable {
    case preferred
    case language(TranslationLanguage)

    var displayName: String {
        switch self {
        case .preferred:
            return "智能目标语言"
        case let .language(language):
            return language.displayName
        }
    }
}

struct ResolvedTranslationLanguages: Equatable, Sendable {
    let source: TranslationLanguage
    let target: TranslationLanguage
}

struct TranslationLanguageResolver: Sendable {
    typealias Detector = @Sendable (String) -> TranslationLanguage?

    private let detector: Detector

    init(detector: @escaping Detector = TranslationLanguageResolver.detectLanguage) {
        self.detector = detector
    }

    func resolve(
        text: String,
        sourceSelection: TranslationLanguage,
        targetSelection: TranslationTargetSelection,
        preferredLanguage: TranslationLanguage,
        secondaryLanguage: TranslationLanguage
    ) -> ResolvedTranslationLanguages {
        let source = sourceSelection == .automatic
            ? detector(text) ?? .automatic
            : sourceSelection

        let target: TranslationLanguage
        switch targetSelection {
        case .preferred:
            target = source == preferredLanguage ? secondaryLanguage : preferredLanguage
        case let .language(language):
            target = language == .automatic ? preferredLanguage : language
        }

        return ResolvedTranslationLanguages(source: source, target: target)
    }

    private static func detectLanguage(_ text: String) -> TranslationLanguage? {
        guard let language = NLLanguageRecognizer.dominantLanguage(for: text) else {
            return nil
        }

        switch language {
        case .simplifiedChinese:
            return .simplifiedChinese
        case .traditionalChinese:
            return .traditionalChinese
        case .english:
            return .english
        case .japanese:
            return .japanese
        case .korean:
            return .korean
        case .french:
            return .french
        case .german:
            return .german
        case .spanish:
            return .spanish
        case .portuguese:
            return .portuguese
        case .italian:
            return .italian
        case .russian:
            return .russian
        default:
            return nil
        }
    }
}

struct TranslationRequest: Equatable, Sendable {
    let text: String
    let sourceLanguage: TranslationLanguage
    let targetLanguage: TranslationLanguage
}

enum TranslationEvent: Equatable, Sendable {
    case textDelta(String)
    case completed(detectedSourceLanguage: TranslationLanguage?)
}

protocol TranslationProvider: Sendable {
    var id: TranslationProviderID { get }

    func translate(
        _ request: TranslationRequest
    ) -> AsyncThrowingStream<TranslationEvent, Error>
}

enum TranslationError: LocalizedError, Equatable, Sendable {
    case emptyInput
    case identicalLanguages
    case missingConfiguration(String)
    case invalidEndpoint
    case endpointRejected(statusCode: Int)
    case unsupportedLanguage(TranslationProviderID, TranslationLanguage)
    case accessibilityPermissionRequired
    case noSelectedText
    case authenticationFailed
    case rateLimited
    case quotaExceeded
    case timedOut
    case http(statusCode: Int, message: String?)
    case responseDecodingFailed
    case emptyResponse
    case network(String)

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "请输入需要翻译的文本。"
        case .identicalLanguages:
            return "来源语言和目标语言不能相同。"
        case let .missingConfiguration(message):
            return message
        case .invalidEndpoint:
            return "翻译服务地址无效，请在设置中检查。"
        case let .endpointRejected(statusCode):
            return "当前 AI Base URL 无法接收 Responses API 请求（HTTP \(statusCode)），请检查服务商配置。"
        case let .unsupportedLanguage(provider, language):
            return "\(provider.displayName) 暂不支持\(language.displayName)。"
        case .accessibilityPermissionRequired:
            return "需要辅助功能权限才能读取当前选中的文本。"
        case .noSelectedText:
            return "未读取到选中文字，请粘贴或输入文本。"
        case .authenticationFailed:
            return "服务鉴权失败，请检查 API Key 和服务配置。"
        case .rateLimited:
            return "请求过于频繁，请稍后重试。"
        case .quotaExceeded:
            return "翻译服务额度不足。"
        case .timedOut:
            return "翻译请求超时，请重试。"
        case let .http(statusCode, message):
            if let message, !message.isEmpty {
                return "翻译服务返回错误（\(statusCode)）：\(message)"
            }
            return "翻译服务返回错误（\(statusCode)）。"
        case .responseDecodingFailed:
            return "无法解析翻译服务的响应。"
        case .emptyResponse:
            return "翻译服务没有返回内容。"
        case let .network(message):
            return "网络请求失败：\(message)"
        }
    }

    var suggestsOpeningSettings: Bool {
        switch self {
        case .missingConfiguration, .invalidEndpoint, .endpointRejected, .authenticationFailed:
            return true
        default:
            return false
        }
    }

    static func map(_ error: Error) -> TranslationError {
        if let translationError = error as? TranslationError {
            return translationError
        }
        if let urlError = error as? URLError {
            if urlError.code == .timedOut {
                return .timedOut
            }
            return .network(urlError.localizedDescription)
        }
        return .network(error.localizedDescription)
    }
}

enum TranslationViewState: Equatable {
    case idle
    case translating
    case succeeded
    case failed
}

enum TranslationInlineNotice: Equatable {
    case accessibilityPermissionRequired
    case noSelectedText

    var message: String {
        switch self {
        case .accessibilityPermissionRequired:
            return "请在系统设置中允许 Invoker 使用辅助功能，然后重试划词翻译。"
        case .noSelectedText:
            return "未读取到选中文字，请在上方粘贴或输入文本。"
        }
    }
}
