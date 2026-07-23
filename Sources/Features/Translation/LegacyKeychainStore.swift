import Foundation
import Security

protocol LegacyKeychainStoring {
    func string(for account: String) throws -> String?
    func deleteValue(for account: String) throws
}

struct LegacyKeychainStore: LegacyKeychainStoring {
    private let service = "com.sampwood.invoker.translation"

    func string(for account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw LegacyKeychainStoreError(status: status)
        }
        guard let data = item as? Data,
              let value = String(data: data, encoding: .utf8)
        else {
            throw LegacyKeychainStoreError(status: errSecDecode)
        }
        return value
    }

    func deleteValue(for account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw LegacyKeychainStoreError(status: status)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

private struct LegacyKeychainStoreError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        if let message = SecCopyErrorMessageString(status, nil) {
            return message as String
        }
        return "Keychain 错误码：\(status)"
    }
}
