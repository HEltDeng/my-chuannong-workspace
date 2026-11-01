import Foundation
import Security

/// Device-only items. School sessions and platform tokens use separate service namespaces.
enum SecureStore {
    static func read(_ key: String, realm: String) throws -> Data? {
        var query = base(key, realm)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw StorageError.keychain(status) }
        return result as? Data
    }
    static func write(_ data: Data?, key: String, realm: String) throws {
        let query = base(key, realm)
        guard let data else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw StorageError.keychain(status) }; return
        }
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound { status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil) }
        guard status == errSecSuccess else { throw StorageError.keychain(status) }
    }
    private static func base(_ key: String, _ realm: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.mychuannong.ios.\(realm)", kSecAttrAccount as String: key, kSecAttrSynchronizable as String: false]
    }
    enum StorageError: Error, LocalizedError {
        case keychain(OSStatus)
        var errorDescription: String? {
            guard case .keychain(let status) = self else { return nil }
            let message: String
            switch status {
            case errSecInteractionNotAllowed, errSecNotAvailable:
                message = "本机安全存储暂不可用，请解锁设备后重试"
            case errSecMissingEntitlement:
                message = "应用安全存储权限配置不完整，请更新或重新安装此版本"
            default:
                message = "本机安全存储操作失败，请稍后重试"
            }
            #if DEBUG
            return message + "（Keychain \(status)）"
            #else
            return message
            #endif
        }
    }
}
