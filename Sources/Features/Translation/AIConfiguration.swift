import Foundation
import SQLite3

enum AIConfigurationSource: String, CaseIterable, Identifiable, Sendable {
    case ccSwitch
    case manual

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ccSwitch:
            return "CC Switch"
        case .manual:
            return "手动"
        }
    }
}

enum AIAuthenticationStatus: Equatable, Sendable {
    case configured
    case notRequired
    case missing

    var displayName: String {
        switch self {
        case .configured:
            return "已配置"
        case .notRequired:
            return "不需要认证"
        case .missing:
            return "缺少 API Key"
        }
    }
}

struct CCSwitchConfigurationPreview: Equatable, Sendable {
    let providerName: String
    let baseURL: String
    let model: String
    let authenticationStatus: AIAuthenticationStatus
}

struct ResolvedAIConfiguration: Equatable, Sendable {
    let baseURL: String
    let model: String
    let apiKey: String
    let source: AIConfigurationSource
    let providerName: String?
    let warning: String?
}

struct ManualAIConfiguration: Equatable, Sendable {
    let baseURL: String
    let model: String
    let apiKey: String

    func resolvedConfiguration(warning: String? = nil) throws -> ResolvedAIConfiguration {
        guard AIConfigurationValidation.isValidBaseURL(baseURL) else {
            throw AIConfigurationError.invalidManualBaseURL
        }
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIConfigurationError.missingManualModel
        }

        return ResolvedAIConfiguration(
            baseURL: baseURL,
            model: model,
            apiKey: apiKey,
            source: .manual,
            providerName: nil,
            warning: warning
        )
    }
}

struct CCSwitchAIConfiguration: Equatable, Sendable {
    let providerName: String
    let baseURL: String
    let model: String
    let wireAPI: String?
    let requiresOpenAIAuth: Bool
    let apiKey: String?

    var preview: CCSwitchConfigurationPreview {
        let authenticationStatus: AIAuthenticationStatus
        if !requiresOpenAIAuth {
            authenticationStatus = .notRequired
        } else if apiKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            authenticationStatus = .configured
        } else {
            authenticationStatus = .missing
        }

        return CCSwitchConfigurationPreview(
            providerName: providerName,
            baseURL: baseURL,
            model: model,
            authenticationStatus: authenticationStatus
        )
    }

    func resolvedConfiguration() throws -> ResolvedAIConfiguration {
        guard AIConfigurationValidation.isValidBaseURL(baseURL) else {
            throw AIConfigurationError.invalidCCSwitchBaseURL
        }
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIConfigurationError.missingCCSwitchModel
        }
        if let wireAPI,
           !wireAPI.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           wireAPI.caseInsensitiveCompare("responses") != .orderedSame {
            throw AIConfigurationError.unsupportedWireAPI
        }

        let resolvedAPIKey: String
        if requiresOpenAIAuth {
            guard let apiKey,
                  !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AIConfigurationError.missingCCSwitchAPIKey
            }
            resolvedAPIKey = apiKey
        } else {
            resolvedAPIKey = ""
        }

        return ResolvedAIConfiguration(
            baseURL: baseURL,
            model: model,
            apiKey: resolvedAPIKey,
            source: .ccSwitch,
            providerName: providerName,
            warning: nil
        )
    }
}

protocol CCSwitchAIConfigurationReading {
    func currentConfiguration() throws -> CCSwitchAIConfiguration
}

protocol AIConfigurationResolving {
    func resolve(
        source: AIConfigurationSource,
        manualConfiguration: ManualAIConfiguration
    ) throws -> ResolvedAIConfiguration
}

struct AIConfigurationResolver: AIConfigurationResolving {
    let ccSwitchReader: any CCSwitchAIConfigurationReading

    func resolve(
        source: AIConfigurationSource,
        manualConfiguration: ManualAIConfiguration
    ) throws -> ResolvedAIConfiguration {
        switch source {
        case .manual:
            return try manualConfiguration.resolvedConfiguration()
        case .ccSwitch:
            do {
                return try ccSwitchReader.currentConfiguration().resolvedConfiguration()
            } catch {
                let warning = "无法读取有效的 CC Switch 配置，当前使用手动回退。\(error.localizedDescription)"
                do {
                    return try manualConfiguration.resolvedConfiguration(warning: warning)
                } catch {
                    throw AIConfigurationError.ccSwitchAndManualUnavailable(
                        "\(warning) 手动回退也不可用：\(error.localizedDescription)"
                    )
                }
            }
        }
    }
}

struct CCSwitchAIConfigurationReader: CCSwitchAIConfigurationReading {
    let databaseURL: URL

    init(
        databaseURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cc-switch", isDirectory: true)
            .appendingPathComponent("cc-switch.db", isDirectory: false)
    ) {
        self.databaseURL = databaseURL
    }

    func currentConfiguration() throws -> CCSwitchAIConfiguration {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &database, flags, nil) == SQLITE_OK,
              let database else {
            if let database {
                sqlite3_close(database)
            }
            throw AIConfigurationError.ccSwitchDatabaseUnavailable
        }
        defer {
            sqlite3_close(database)
        }
        sqlite3_busy_timeout(database, 150)

        let query = """
        SELECT name, settings_config
        FROM providers
        WHERE app_type = 'codex' AND is_current = 1
        ORDER BY sort_index
        LIMIT 1
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw AIConfigurationError.ccSwitchQueryFailed
        }
        defer {
            sqlite3_finalize(statement)
        }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw AIConfigurationError.noCurrentCCSwitchProvider
        }
        guard let providerNameText = sqlite3_column_text(statement, 0),
              let settingsText = sqlite3_column_text(statement, 1) else {
            throw AIConfigurationError.invalidCCSwitchProvider
        }

        let providerName = String(decodingCString: providerNameText, as: UTF8.self)
        let settingsJSON = String(decodingCString: settingsText, as: UTF8.self)
        guard let data = settingsJSON.data(using: .utf8) else {
            throw AIConfigurationError.invalidCCSwitchProvider
        }

        let payload: CCSwitchProviderPayload
        do {
            payload = try JSONDecoder().decode(CCSwitchProviderPayload.self, from: data)
        } catch {
            throw AIConfigurationError.invalidCCSwitchProvider
        }
        let codexConfiguration = try CodexProviderTOMLParser().parse(payload.config)

        return CCSwitchAIConfiguration(
            providerName: providerName,
            baseURL: codexConfiguration.baseURL,
            model: codexConfiguration.model,
            wireAPI: codexConfiguration.wireAPI,
            requiresOpenAIAuth: codexConfiguration.requiresOpenAIAuth,
            apiKey: payload.auth?.apiKey
        )
    }
}

struct CodexProviderTOMLConfiguration: Equatable, Sendable {
    let modelProvider: String
    let model: String
    let baseURL: String
    let wireAPI: String?
    let requiresOpenAIAuth: Bool
}

struct CodexProviderTOMLParser {
    func parse(_ source: String) throws -> CodexProviderTOMLConfiguration {
        var currentTable: [String] = []
        var topLevel: [String: TOMLSubsetValue] = [:]
        var modelProviders: [String: [String: TOMLSubsetValue]] = [:]

        source.enumerateLines { rawLine, _ in
            let line = stripTOMLComment(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                return
            }

            if line.first == "[", line.last == "]" {
                let tableText = String(line.dropFirst().dropLast())
                currentTable = (try? parseTOMLDottedKey(tableText)) ?? []
                return
            }

            guard let separatorIndex = firstUnquotedCharacter("=", in: line) else {
                return
            }
            let rawKey = String(line[..<separatorIndex])
            let rawValue = String(line[line.index(after: separatorIndex)...])
            guard let key = try? parseTOMLKey(rawKey),
                  let value = try? parseTOMLValue(rawValue) else {
                return
            }

            if currentTable.isEmpty {
                topLevel[key] = value
            } else if currentTable.count == 2, currentTable[0] == "model_providers" {
                modelProviders[currentTable[1], default: [:]][key] = value
            }
        }

        guard let modelProvider = topLevel["model_provider"]?.stringValue,
              !modelProvider.isEmpty,
              let model = topLevel["model"]?.stringValue,
              !model.isEmpty,
              let provider = modelProviders[modelProvider],
              let baseURL = provider["base_url"]?.stringValue,
              !baseURL.isEmpty else {
            throw AIConfigurationError.invalidCCSwitchCodexConfiguration
        }

        return CodexProviderTOMLConfiguration(
            modelProvider: modelProvider,
            model: model,
            baseURL: baseURL,
            wireAPI: provider["wire_api"]?.stringValue,
            requiresOpenAIAuth: provider["requires_openai_auth"]?.boolValue ?? false
        )
    }
}

enum AIConfigurationError: LocalizedError {
    case ccSwitchDatabaseUnavailable
    case ccSwitchQueryFailed
    case noCurrentCCSwitchProvider
    case invalidCCSwitchProvider
    case invalidCCSwitchCodexConfiguration
    case invalidCCSwitchBaseURL
    case missingCCSwitchModel
    case unsupportedWireAPI
    case missingCCSwitchAPIKey
    case invalidManualBaseURL
    case missingManualModel
    case ccSwitchAndManualUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .ccSwitchDatabaseUnavailable:
            return "找不到或无法只读打开 ~/.cc-switch/cc-switch.db。"
        case .ccSwitchQueryFailed:
            return "CC Switch 数据库结构不可用。"
        case .noCurrentCCSwitchProvider:
            return "CC Switch 没有当前启用的 Codex Provider。"
        case .invalidCCSwitchProvider:
            return "CC Switch 当前 Provider 配置无法解析。"
        case .invalidCCSwitchCodexConfiguration:
            return "CC Switch 当前 Provider 缺少 Codex 模型或服务地址。"
        case .invalidCCSwitchBaseURL:
            return "CC Switch 当前 Provider 的 Base URL 无效。"
        case .missingCCSwitchModel:
            return "CC Switch 当前 Provider 缺少模型。"
        case .unsupportedWireAPI:
            return "CC Switch 当前 Provider 不是 Responses API。"
        case .missingCCSwitchAPIKey:
            return "CC Switch 当前 Provider 需要认证，但没有 API Key。"
        case .invalidManualBaseURL:
            return "手动 AI Base URL 无效。"
        case .missingManualModel:
            return "手动 AI 配置缺少模型。"
        case let .ccSwitchAndManualUnavailable(message):
            return message
        }
    }
}

private struct CCSwitchProviderPayload: Decodable {
    let auth: Authentication?
    let config: String

    struct Authentication: Decodable {
        let apiKey: String?

        enum CodingKeys: String, CodingKey {
            case apiKey = "OPENAI_API_KEY"
        }
    }
}

private enum AIConfigurationValidation {
    static func isValidBaseURL(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return false
        }
        return true
    }
}

private enum TOMLSubsetValue {
    case string(String)
    case bool(Bool)

    var stringValue: String? {
        guard case let .string(value) = self else {
            return nil
        }
        return value
    }

    var boolValue: Bool? {
        guard case let .bool(value) = self else {
            return nil
        }
        return value
    }
}

private func stripTOMLComment(_ text: String) -> String {
    let characters = Array(text)
    var quote: Character?
    var isEscaped = false

    for (index, character) in characters.enumerated() {
        if let activeQuote = quote {
            if activeQuote == "\"", character == "\\", !isEscaped {
                isEscaped = true
                continue
            }
            if character == activeQuote, !isEscaped {
                quote = nil
            }
            isEscaped = false
            continue
        }
        if character == "\"" || character == "'" {
            quote = character
        } else if character == "#" {
            return String(characters[..<index])
        }
    }
    return text
}

private func firstUnquotedCharacter(_ target: Character, in text: String) -> String.Index? {
    var quote: Character?
    var isEscaped = false

    for index in text.indices {
        let character = text[index]
        if let activeQuote = quote {
            if activeQuote == "\"", character == "\\", !isEscaped {
                isEscaped = true
                continue
            }
            if character == activeQuote, !isEscaped {
                quote = nil
            }
            isEscaped = false
            continue
        }
        if character == "\"" || character == "'" {
            quote = character
        } else if character == target {
            return index
        }
    }
    return nil
}

private func parseTOMLDottedKey(_ text: String) throws -> [String] {
    var segments: [String] = []
    var current = ""
    var quote: Character?
    var isEscaped = false

    for character in text {
        if let activeQuote = quote {
            current.append(character)
            if activeQuote == "\"", character == "\\", !isEscaped {
                isEscaped = true
                continue
            }
            if character == activeQuote, !isEscaped {
                quote = nil
            }
            isEscaped = false
            continue
        }
        if character == "\"" || character == "'" {
            quote = character
            current.append(character)
        } else if character == "." {
            segments.append(try parseTOMLKey(current))
            current = ""
        } else {
            current.append(character)
        }
    }
    guard quote == nil else {
        throw AIConfigurationError.invalidCCSwitchCodexConfiguration
    }
    segments.append(try parseTOMLKey(current))
    return segments
}

private func parseTOMLKey(_ text: String) throws -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        throw AIConfigurationError.invalidCCSwitchCodexConfiguration
    }
    return try decodeTOMLString(trimmed)
}

private func parseTOMLValue(_ text: String) throws -> TOMLSubsetValue {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed == "true" {
        return .bool(true)
    }
    if trimmed == "false" {
        return .bool(false)
    }
    return .string(try decodeTOMLString(trimmed))
}

private func decodeTOMLString(_ text: String) throws -> String {
    guard let first = text.first else {
        throw AIConfigurationError.invalidCCSwitchCodexConfiguration
    }
    if first == "\"" {
        guard text.last == "\"",
              let data = text.data(using: .utf8),
              let value = try? JSONDecoder().decode(String.self, from: data) else {
            throw AIConfigurationError.invalidCCSwitchCodexConfiguration
        }
        return value
    }
    if first == "'" {
        guard text.last == "'", text.count >= 2 else {
            throw AIConfigurationError.invalidCCSwitchCodexConfiguration
        }
        return String(text.dropFirst().dropLast())
    }
    return text
}
