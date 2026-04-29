import Foundation
import Security

public enum ProKeychain {
    private static let service = "com.dyad-itss.anchor.pro"
    private static let account = "entitlement"

    /// Returns true if a Pro entitlement token is stored in Keychain.
    public static func isProUnlocked() -> Bool {
        readToken() != nil
    }

    /// Stores the Pro entitlement token in Keychain. Overwrites any existing token.
    public static func unlock(token: String) {
        let data = Data(token.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemDelete(query as CFDictionary) // delete any existing item first
        SecItemAdd(query as CFDictionary, nil)
    }

    /// Removes the Pro entitlement token from Keychain.
    public static func lock() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func readToken() -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// For tests only — clears the Keychain entry.
    public static func clearForTesting() {
        lock()
    }
}
