import Foundation
import os
import Security

/// SecItem 轻封装：存放 VPM 会话凭证（accessToken）。
public enum VPMKeychain {
    enum Accounts {
        static let accessToken = "vpm.accessToken"
    }

    private static let service = "io.nekohasekai.sfa.vpm"
    private static let logger = Logger(category: "VPMKeychain")

    private static func baseQuery(account: String) -> [String: Any] {
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account]
    }

    public static func set(value: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query = baseQuery(account: account)
        let update: [String: Any] = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }
        if status != errSecSuccess {
            logger.error("VPMKeychain set \(account, privacy: .public) failed: \(status)")
        }
    }

    public static func get(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func remove(account: String) {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            logger.error("VPMKeychain remove \(account, privacy: .public) failed: \(status)")
        }
    }
}
