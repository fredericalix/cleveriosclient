import Foundation
import SwiftUI
// Import nécessaire pour CleverCloudSDK
import Combine

/// Coordinateur global pour gérer l'état d'authentification de l'application
@MainActor
@Observable
final class AppCoordinator {
    
    // MARK: - Properties
    var isAuthenticated = false
    var currentUser: String?
    var authError: String?
    var isCheckingAuth = true
    
    // Services
    private var _oauthService: CCOAuthService?
    private var authCheckTimer: Timer?
    private var _configuration: CCConfiguration
    
    /// Service OAuth partagé - accessible pour LoginView
    var oauthService: CCOAuthService {
        if _oauthService == nil {
            _oauthService = createOAuthService()
        }
        return _oauthService!
    }
    
    // MARK: - SDK Access
    private var _cleverCloudSDK: CleverCloudSDK?
    
    /// CleverCloud SDK accessible publiquement pour les vues (singleton pattern)
    var cleverCloudSDK: CleverCloudSDK {
        if _cleverCloudSDK == nil {
            _cleverCloudSDK = CleverCloudSDK(configuration: _configuration)
        }
        return _cleverCloudSDK!
    }
    
    // Configuration initiale - sera mise à jour avec les tokens du Keychain
    private var configuration: CCConfiguration {
        return _configuration
    }
    
    // MARK: - Initialization

    init() {
        self.isAuthenticated = false
        self.isCheckingAuth = true
        
        debugLog("ℹ️ 🚀 AppCoordinator initialized [timestamp=\(Date().description)]")
        
        // Initialize configuration first
        let keychain = CCKeychainManager()
        let credentials = keychain.loadCredentials()
        
        // Create configuration with hardcoded consumer keys (from clever-tools)
        _configuration = CCConfiguration(
            consumerKey: "T5nFjKeHH4AIlEveuGhB5S3xg8T19e",      // Credentials officielles
            consumerSecret: "MgVMqTr6fWlf2M0tkC2MXOnhfqBWDT",    // de clever-tools
            enableDebugLogging: {
                #if DEBUG
                return true
                #else
                return false
                #endif
            }()
        )
        
        debugLog("🔍 Configuration initialized [hasToken=\((credentials?.token != nil && !credentials!.token.isEmpty) ? "yes" : "no"), hasTokenSecret=\((credentials?.secret != nil && !credentials!.secret.isEmpty) ? "yes" : "no")]")
        
        // Update tokens if available
        if let credentials = credentials,
           !credentials.token.isEmpty,
           !credentials.secret.isEmpty {
            debugLog("ℹ️ 🔑 Found stored OAuth tokens, updating configuration")
            _configuration.updateTokens(accessToken: credentials.token, accessTokenSecret: credentials.secret)
            self.isAuthenticated = true
            debugLog("ℹ️ ✅ User authenticated from stored credentials")
        } else {
            debugLog("ℹ️ 📱 No valid OAuth tokens found, user needs to login")
        }
        
        isCheckingAuth = false
        
        setupAuthentication()
        startAuthenticationMonitoring()
    }
    
    // MARK: - Public Methods
    
    /// Configuration initiale de l'authentification
    func setupAuthentication() {
        // Créer le service OAuth CLI (via la propriété calculée)
        _ = oauthService
        
        // Vérifier immédiatement s'il y a des credentials existants
        checkAuthenticationState()
    }
    
    /// Démarre le processus d'authentification CLI
    func startAuthentication() {
        oauthService.authenticate()
    }
    
    /// Déconnecte l'utilisateur et nettoie tous les états
    func logout() {
        if configuration.enableDebugLogging {
            debugLog("🔐 Starting user logout process...")
        }
        
        // Déconnexion via le service OAuth (supprime les credentials du Keychain)
        oauthService.logout()
        
        // Nettoyer tous les états d'authentification
        isAuthenticated = false
        currentUser = nil
        authError = nil
        
        // Effacer les tokens de la configuration
        _configuration.clearTokens()
        
        if configuration.enableDebugLogging {
            debugLog("✅ User logout completed successfully")
        }
    }
    
    /// Retourne la vue appropriée selon l'état d'authentification
    @ViewBuilder
    func rootView() -> some View {
        if isAuthenticated {
            ContentView()
        } else {
            LoginView()
        }
    }
    
    /// Force la vérification de l'état d'authentification
    func refreshAuthenticationState() {
        checkAuthenticationState()
    }
    
    /// Force une vérification immédiate de l'état d'authentification (appelé après login)
    func forceAuthenticationCheck() {
        if configuration.enableDebugLogging {
            debugLog("🔍 Forcing immediate authentication check...")
        }
        
        // Recharger les tokens depuis le Keychain
        loadTokensFromKeychain()
        
        checkAuthenticationState()
    }
    
    // MARK: - Private Methods
    
    /// Charge les tokens OAuth depuis le Keychain
    private func loadTokensFromKeychain() {
        let keychain = CCKeychainManager()
        
        if let credentials = keychain.loadCredentials() {
            // Mettre à jour la configuration avec les tokens chargés
            _configuration.updateTokens(accessToken: credentials.token, accessTokenSecret: credentials.secret)
            
            if _configuration.enableDebugLogging {
                debugLog("🔑 Tokens loaded from Keychain")
                debugLog("   Access Token: \(credentials.token.prefix(10))...")
                debugLog("   Token Secret: \(credentials.secret.prefix(10))...")
                debugLog("   isAuthenticated: \(_configuration.isAuthenticated)")
            }
        } else {
            if _configuration.enableDebugLogging {
                debugLog("📱 No tokens found in Keychain")
            }
        }
    }
    
    /// Crée et retourne un service OAuth configuré
    private func createOAuthService() -> CCOAuthService {
        return CCOAuthService(configuration: _configuration)
    }
    
    /// Démarre la surveillance continue de l'état d'authentification
    private func startAuthenticationMonitoring() {
        // Vérification moins fréquente pour éviter la surcharge (toutes les 2 secondes au lieu de 0.1s)
        authCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkAuthenticationState()
            }
        }
    }
    
    /// Vérifie l'état d'authentification actuel
    private func checkAuthenticationState() {
        let previousAuthState = isAuthenticated
        let currentAuthState = oauthService.isAuthenticated
        
        // Seulement mettre à jour si l'état a vraiment changé
        if previousAuthState != currentAuthState {
            // Mettre à jour l'état local
            isAuthenticated = currentAuthState
            authError = oauthService.authError
            
            if currentAuthState {
                // Nouvellement authentifié - recharger les tokens
                loadTokensFromKeychain()
                onAuthenticationSuccess()
            } else {
                // Nouvellement déconnecté
                onAuthenticationFailure()
            }
            
            if configuration.enableDebugLogging {
                debugLog("🔄 Authentication state changed: \(previousAuthState) -> \(currentAuthState)")
            }
        }
        // Sinon, ne rien faire - évite les vérifications inutiles du keychain
    }
    
    /// Appelé quand l'authentification réussit
    private func onAuthenticationSuccess() {
        Task {
            await fetchUserInfo()
        }
        
        if configuration.enableDebugLogging {
            debugLog("🎉 Authentication successful - user now logged in!")
        }
    }
    
    /// Appelé quand l'authentification échoue ou que l'utilisateur se déconnecte
    private func onAuthenticationFailure() {
        currentUser = nil
        
        if configuration.enableDebugLogging {
            debugLog("🔐 User logged out or authentication failed")
        }
    }
    
    /// Récupère les informations de l'utilisateur actuel (optionnel)
    private func fetchUserInfo() async {
        // Pour l'instant, on met un placeholder
        // TODO: Utiliser l'API Clever Cloud pour récupérer les vraies infos utilisateur
        currentUser = "Clever Cloud User"
        
        if configuration.enableDebugLogging {
            debugLog("✅ User info loaded: \(currentUser ?? "Unknown")")
        }
    }
} 