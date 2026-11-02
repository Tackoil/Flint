import Foundation
import Security

struct TranslationAPIKeyStore {
    private static let cache = TranslationAPIKeyCache()
    private let service = "com.flint.translation.deepseek"
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: "api-key"]
    }

    func containsKey() throws -> Bool {
        var attributes = query
        attributes[kSecReturnAttributes as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(attributes as CFDictionary, nil)
        if status == errSecItemNotFound { return false }
        try check(status)
        return true
    }

    func read() throws -> String? {
        try Self.cache.read { try readFromKeychain() }
    }

    private func readFromKeychain() throws -> String? {
        var attributes = query
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(_ value: String) throws {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw TranslationError.missingAPIKey }
        try Self.cache.replace(with: key) { try writeToKeychain(key) }
    }

    private func writeToKeychain(_ key: String) throws {
        let data = Data(key.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = query
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            try check(SecItemAdd(attributes as CFDictionary, nil))
        } else {
            try check(status)
        }
    }

    func delete() throws {
        try Self.cache.replace(with: nil) {
            let status = SecItemDelete(query as CFDictionary)
            if status != errSecItemNotFound { try check(status) }
        }
    }

    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "Couldn’t access the API key in Keychain. \(SecCopyErrorMessageString(status, nil) as String? ?? "Try again.")"
            ])
        }
    }
}

// All store instances share one process-only cache. Serialize reads and mutations so
// a delayed Keychain read cannot restore a key after it was replaced or removed.
final class TranslationAPIKeyCache: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    func read(load: () throws -> String?) throws -> String? {
        try lock.withLock {
            if let value { return value }
            let loaded = try load()
            value = loaded
            return loaded
        }
    }

    func replace(with key: String?, after operation: () throws -> Void) throws {
        try lock.withLock {
            try operation()
            value = key
        }
    }
}
