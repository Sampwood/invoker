import Foundation

struct TranslationSecrets: Codable, Equatable, Sendable {
    var aiAPIKey: String
    var deepLAuthKey: String

    static let empty = TranslationSecrets(aiAPIKey: "", deepLAuthKey: "")

    enum CodingKeys: String, CodingKey {
        case aiAPIKey = "ai_api_key"
        case deepLAuthKey = "deepl_auth_key"
    }

    init(aiAPIKey: String, deepLAuthKey: String) {
        self.aiAPIKey = aiAPIKey
        self.deepLAuthKey = deepLAuthKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        aiAPIKey = try container.decodeIfPresent(String.self, forKey: .aiAPIKey) ?? ""
        deepLAuthKey = try container.decodeIfPresent(String.self, forKey: .deepLAuthKey) ?? ""
    }
}

protocol TranslationSecretStoring {
    var fileURL: URL { get }

    func fileExists() -> Bool
    func load() throws -> TranslationSecrets
    func save(_ secrets: TranslationSecrets) throws
}

struct TranslationSecretFileStore: TranslationSecretStoring {
    let fileURL: URL

    private let fileManager: FileManager

    init(
        fileURL: URL = TranslationSecretFileStore.defaultFileURL,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    static var defaultFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".invoker", isDirectory: true)
            .appendingPathComponent("config.json", isDirectory: false)
    }

    func fileExists() -> Bool {
        fileManager.fileExists(atPath: fileURL.path)
    }

    func load() throws -> TranslationSecrets {
        guard fileExists() else {
            return .empty
        }

        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(TranslationSecrets.self, from: data)
    }

    func save(_ secrets: TranslationSecrets) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directoryURL.path
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var data = try encoder.encode(secrets)
        data.append(0x0A)
        try data.write(to: fileURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }
}
