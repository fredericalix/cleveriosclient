import Foundation
import Security

/// Structure pour les credentials OAuth
public struct OAuthCredentials: Codable {
    public let token: String
    public let secret: String
    
    public init(token: String, secret: String) {
        self.token = token
        self.secret = secret
    }
}

/// Gestionnaire sécurisé pour les tokens OAuth dans le Keychain iOS
/// Adapté pour le système CLI Token de Clever Cloud
final class CCKeychainManager: @unchecked Sendable {
    
    // MARK: - Constants
    
    private struct Keys {
        static let credentials = "cc_cli_credentials"
        static let service = "com.fredalix.cctoolkit.clevercloud"
    }
    
    // MARK: - Initialization
    
    init() {}
    
    // MARK: - Credentials Management
    
    /// Sauvegarde les credentials OAuth dans le Keychain
    func saveCredentials(_ credentials: OAuthCredentials) -> Bool {
        do {
            let data = try JSONEncoder().encode(credentials)
            
            let saveQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: Keys.service,
                kSecAttrAccount as String: Keys.credentials,
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]
            
            // Delete any existing item first
            SecItemDelete(saveQuery as CFDictionary)
            
            // Add new item
            let status = SecItemAdd(saveQuery as CFDictionary, nil)
            if status == errSecSuccess {
                debugLog("ℹ️ ✅ CCKeychainManager: CLI credentials stored successfully")
            } else {
                debugLog("❌ ❌ CCKeychainManager: Failed to store CLI credentials")
            }
            return status == errSecSuccess
        } catch {
            debugLog("❌ ❌ CCKeychainManager: Failed to encode credentials: \(error)")
            return false
        }
    }
    
    /// Récupère les credentials OAuth depuis le Keychain
    func loadCredentials() -> OAuthCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Keys.service,
            kSecAttrAccount as String: Keys.credentials,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        
        do {
            return try JSONDecoder().decode(OAuthCredentials.self, from: data)
        } catch {
            debugLog("❌ ❌ CCKeychainManager: Failed to decode credentials: \(error)")
            return nil
        }
    }
    
    /// Supprime les credentials OAuth (logout)
    func deleteCredentials() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Keys.service,
            kSecAttrAccount as String: Keys.credentials
        ]
        
        SecItemDelete(query as CFDictionary)
        debugLog("ℹ️ 🗑️ CCKeychainManager: CLI credentials deleted")
    }
    
    // MARK: - Status Check
    
    /// Vérifie si des credentials valides sont stockés
    var hasStoredCredentials: Bool {
        return loadCredentials() != nil
    }
    
    // MARK: - Private Keychain Operations
    
    private func save(key: String, data: Data) -> Bool {
        // Configuration de la requête Keychain
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Keys.service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        // Supprime l'ancienne entrée si elle existe
        SecItemDelete(query as CFDictionary)
        
        // Ajoute la nouvelle entrée
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    private func get(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Keys.service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        
        return data
    }
    
    private func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Keys.service,
            kSecAttrAccount as String: key
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Debug Extensions

extension CCKeychainManager {
    
    /// Affiche l'état des credentials pour debug
    func debugCredentialsStatus() {
        let hasStoredCredentials = hasStoredCredentials
        
        if let credentials = loadCredentials() {
            debugLog("🔍 🔐 KEYCHAIN STATUS:")
            debugLog("🔍    CLI Token: \(credentials.token.prefix(10))...")
            debugLog("🔍    Token Secret: \(credentials.secret.prefix(10))...")
            debugLog("🔍    Has Valid Credentials: \(hasStoredCredentials)")
        } else {
            debugLog("🔍 🔐 KEYCHAIN STATUS: No credentials stored")
        }
    }
} 