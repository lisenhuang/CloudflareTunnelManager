import Foundation
import Security

/// Thin wrapper over Keychain Services for storing the Cloudflare API token and
/// per-tunnel connector tokens as generic passwords. Nothing secret is ever
/// written to disk in the clear.
struct KeychainStore {
    let service: String

    init(service: String = "com.cloudflaretunnelmanager.tokens") {
        self.service = service
    }

    // Well-known account keys.
    static let apiTokenAccount = "cloudflare-api-token"
    static func connectorTokenAccount(for tunnelID: UUID) -> String {
        "tunnel-token-\(tunnelID.uuidString)"
    }

    @discardableResult
    func set(_ value: String, account: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        // Delete any existing item first so we always upsert cleanly.
        delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    @discardableResult
    func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    func has(account: String) -> Bool {
        get(account: account) != nil
    }
}
