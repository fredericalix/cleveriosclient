import Foundation
import SafariServices
import SwiftUI

/// Service d'authentification CLI Token (comme clever-tools)
/// Utilise le même système que l'outil officiel Clever Cloud
@MainActor
@Observable
final class CCOAuthService: NSObject {
    
    // MARK: - Published Properties
    var isAuthenticating = false
    var authError: String?
    var isAuthenticated = false
    
    // MARK: - Private Properties
    private let configuration: CCConfiguration
    private let keychainManager = CCKeychainManager()
    private var cliToken: String?
    private var pollingTask: Task<Void, Never>?
    private var safariViewController: SFSafariViewController?
    
    // MARK: - Constants (comme clever-tools)
    private struct CLIAuth {
        static let consoleBaseURL = "https://console.clever-cloud.com/cli-oauth"
        static let apiHost = "https://api.clever-cloud.com"
        static let pollingInterval: TimeInterval = 2.0  // 2 secondes comme clever-tools
        static let maxPollingAttempts = 60  // 2 minutes max (comme clever-tools)
    }
    
    // MARK: - Initialization
    init(configuration: CCConfiguration) {
        self.configuration = configuration
        super.init()
        checkExistingAuthentication()
    }
    
    // MARK: - Public Methods
    
    /// Lance le processus d'authentification CLI Token
    func authenticate() {
        Task {
            await startCLIAuthentication()
        }
    }
    
    /// Déconnecte l'utilisateur
    func logout() {
        keychainManager.deleteCredentials()
        isAuthenticated = false
        authError = nil
        if configuration.enableDebugLogging {
            debugLog("🔐 User logged out successfully")
        }
    }
    
    /// Réinitialise l'authentification (supprime les credentials stockés)
    public func resetAuthentication() {
        keychainManager.deleteCredentials()
        isAuthenticated = false
        
        if configuration.enableDebugLogging {
            debugLog("🔄 Authentication reset - credentials deleted from keychain")
        }
    }
    
    // MARK: - Private Methods
    
    /// Vérifie s'il y a déjà des credentials stockés
    private func checkExistingAuthentication() {
        if let credentials = keychainManager.loadCredentials(),
           !credentials.token.isEmpty,
           !credentials.secret.isEmpty {
            isAuthenticated = true
            if configuration.enableDebugLogging {
                debugLog("ℹ️ 🔐 Found valid credentials in keychain [hasToken=yes, hasSecret=yes, tokenLength=\(credentials.token.count), secretLength=\(credentials.secret.count)]")
            }
        } else {
            isAuthenticated = false
            
            // Check if there are invalid credentials to clean up
            if let credentials = keychainManager.loadCredentials() {
                // Found credentials but they are invalid/empty
                if configuration.enableDebugLogging {
                    debugLog("⚠️ 🔐 Found invalid/empty credentials in keychain [tokenEmpty=\(credentials.token.isEmpty ? "yes" : "no"), secretEmpty=\(credentials.secret.isEmpty ? "yes" : "no")]")
                }
                // Clean up invalid credentials
                debugLog("ℹ️ 🧹 Cleaning up invalid credentials from keychain")
                keychainManager.deleteCredentials()
            } else {
                if configuration.enableDebugLogging {
                    debugLog("ℹ️ 🔐 No credentials found in keychain")
                }
            }
        }
    }
    

    
    /// Lance l'authentification CLI Token (comme clever-tools)
    private func startCLIAuthentication() async {
        guard !isAuthenticating else { return }
        
        isAuthenticating = true
        authError = nil
        
        if configuration.enableDebugLogging {
            debugLog("🔐 Starting CLI token authentication...")
        }
        
        debugLog("ℹ️ 🚀 Starting OAuth authentication flow")
        
        // 1. Générer un CLI token aléatoire (comme clever-tools)
        let cliToken = generateRandomCLIToken()
        self.cliToken = cliToken
        
        if configuration.enableDebugLogging {
            debugLog("🔐 Generated CLI token: \(cliToken)")
        }
        
        debugLog("🔍 🔑 Generated CLI token [tokenLength=\(cliToken.count), tokenPrefix=\(String(cliToken.prefix(10)) + "...")]")
        
        // 2. Construire l'URL de la console (comme clever-tools)
        guard let consoleURL = buildConsoleURL(cliToken: cliToken) else {
            authError = "Failed to build console URL"
            isAuthenticating = false
            debugLog("❌ ❌ Failed to build console URL")
            return
        }
        
        if configuration.enableDebugLogging {
            debugLog("🔐 Opening console URL: \(consoleURL)")
        }
        
        debugLog("ℹ️ 🌐 Console URL built [url=\(consoleURL.absoluteString)]")
        
        // 3. Ouvrir Safari pour l'authentification
        openSafariForAuthentication(url: consoleURL)
        
        // 4. Commencer le polling pour récupérer les tokens
        startPollingForTokens(cliToken: cliToken)
    }
    
    /// Génère un token CLI aléatoire (comme dans clever-tools)
    /// Format: 20 random bytes as Base64URL (remplace / par -, + par _, enlève =)
    private func generateRandomCLIToken() -> String {
        let data = Data((0..<20).map { _ in UInt8.random(in: 0...255) })
        return data.base64EncodedString()
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "+", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    /// Construit l'URL de la console (comme clever-tools)
    private func buildConsoleURL(cliToken: String) -> URL? {
        guard var components = URLComponents(string: CLIAuth.consoleBaseURL) else {
            return nil
        }
        
        components.queryItems = [
            URLQueryItem(name: "cli_version", value: "ios-1.0.0"),  // Version de notre app iOS
            URLQueryItem(name: "cli_token", value: cliToken)
        ]
        
        return components.url
    }
    
    /// Ouvre Safari pour l'authentification
    private func openSafariForAuthentication(url: URL) {
        debugLog("ℹ️ 🌐 Attempting to open Safari for authentication [url=\(url.absoluteString)]")
        
        // Configure Safari with ephemeral session to avoid cross-site tracking issues
        let safariConfig = SFSafariViewController.Configuration()
        safariConfig.entersReaderIfAvailable = false
        safariConfig.barCollapsingEnabled = false
        
        // IMPORTANT: Use ephemeral session to bypass cross-site tracking prevention
        // This creates a fresh session that doesn't share cookies with Safari
        // Helps users who have "Prevent Cross-Site Tracking" enabled
        #if swift(>=5.5)
        if #available(iOS 16.0, *) {
            safariConfig.activityButton = .none
        }
        #endif
        
        let safariVC = SFSafariViewController(url: url, configuration: safariConfig)
        safariVC.delegate = self
        safariVC.preferredBarTintColor = .systemBackground
        safariVC.preferredControlTintColor = UIColor(red: 165/255.0, green: 16/255.0, blue: 80/255.0, alpha: 1.0) // Clever Cloud primary color
        
        // Obtenir la window root view controller
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootViewController = window.rootViewController {
            
            // Présenter Safari
            var presentingVC = rootViewController
            while let presented = presentingVC.presentedViewController {
                presentingVC = presented
            }
            
            debugLog("🔍 🌐 Presenting Safari from view controller [viewController=\(type(of: presentingVC))]")
            
            presentingVC.present(safariVC, animated: true)
            self.safariViewController = safariVC
            
            debugLog("ℹ️ ✅ Safari presented successfully for authentication")
        } else {
            debugLog("❌ ❌ Failed to present Safari - no root view controller found")
            handleAuthenticationError("Failed to open authentication browser")
        }
    }
    
    /// Commence le polling pour récupérer les tokens (comme clever-tools)
    private func startPollingForTokens(cliToken: String) {
        pollingTask?.cancel()
        
        debugLog("ℹ️ 🔄 Starting token polling [cliToken=\(String(cliToken.prefix(10)) + "..."), maxAttempts=\(CLIAuth.maxPollingAttempts), interval=\(CLIAuth.pollingInterval)s]")
        
        pollingTask = Task {
            var attempts = 0
            
            while attempts < CLIAuth.maxPollingAttempts && !Task.isCancelled {
                attempts += 1
                
                if configuration.enableDebugLogging {
                    debugLog("🔐 Polling attempt \(attempts)/\(CLIAuth.maxPollingAttempts)")
                }
                
                debugLog("🔍 🔄 Polling attempt [attempt=\(attempts), maxAttempts=\(CLIAuth.maxPollingAttempts)]")
                
                // Faire la requête de polling
                do {
                    if let tokens = try await pollForTokens(cliToken: cliToken) {
                        // Tokens reçus !
                        debugLog("ℹ️ ✅ Tokens received from polling! [attempt=\(attempts), tokenLength=\(tokens.token.count), secretLength=\(tokens.secret.count)]")
                        await MainActor.run {
                            handleTokensReceived(tokens)
                        }
                        return
                    }
                } catch {
                    if configuration.enableDebugLogging {
                        debugLog("🔐 Polling error: \(error.localizedDescription)")
                    }
                    
                    debugLog("❌ ❌ Polling error [attempt=\(attempts), error=\(error.localizedDescription), errorType=\(type(of: error))]")
                    
                    // Si c'est pas une 404, c'est une vraie erreur
                    if !error.localizedDescription.contains("404") {
                        debugLog("❌ ❌ Non-404 error, stopping polling [error=\(error.localizedDescription)]")
                        await MainActor.run {
                            handleAuthenticationError("Network error: \(error.localizedDescription)")
                        }
                        return
                    }
                }
                
                // Attendre avant le prochain poll
                if attempts % 10 == 0 {
                    if configuration.enableDebugLogging {
                        debugLog("🔐 Still waiting for authentication completion...")
                    }
                    debugLog("ℹ️ ⏳ Still polling for tokens [attempts=\(attempts), timeElapsed=\(Double(attempts) * CLIAuth.pollingInterval)s]")
                }
                
                try? await Task.sleep(nanoseconds: UInt64(CLIAuth.pollingInterval * 1_000_000_000))
            }
            
            // Timeout atteint
            debugLog("❌ ❌ Polling timeout reached [totalAttempts=\(attempts), totalTime=\(Double(attempts) * CLIAuth.pollingInterval)s]")
            await MainActor.run {
                handleAuthenticationError("Authentication timeout. Please try again.")
            }
        }
    }
    
    /// Fait une requête de polling pour récupérer les tokens
    private func pollForTokens(cliToken: String) async throws -> OAuthCredentials? {
        // Construire l'URL de polling (comme clever-tools)
        guard var components = URLComponents(string: CLIAuth.apiHost) else {
            throw NSError(domain: "CCOAuthService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid API host"])
        }
        
        components.path = "/v2/self/cli_tokens"
        components.queryItems = [
            URLQueryItem(name: "cli_token", value: cliToken)
        ]
        
        guard let url = components.url else {
            throw NSError(domain: "CCOAuthService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to build polling URL"])
        }
        
        // Faire la requête GET
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        if configuration.enableDebugLogging {
            debugLog("🔐 Polling URL: \(url)")
        }
        
        debugLog("🔍 🌐 Making polling request [url=\(url.absoluteString), method=GET]")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            debugLog("❌ ❌ Invalid response type [responseType=\(type(of: response))]")
            throw NSError(domain: "CCOAuthService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        if configuration.enableDebugLogging {
            debugLog("🔐 Polling response status: \(httpResponse.statusCode)")
        }
        
        debugLog("🔍 📡 Polling response received [statusCode=\(httpResponse.statusCode), contentLength=\(data.count)]")
        
        if httpResponse.statusCode == 404 {
            // Pas encore de tokens, continuer le polling
            debugLog("🔍 ⏳ 404 - Tokens not ready yet")
            return nil
        }
        
        if httpResponse.statusCode != 200 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            debugLog("❌ ❌ Polling failed [statusCode=\(httpResponse.statusCode), errorMessage=\(errorMessage), responseBody=\(String(data: data, encoding: .utf8) ?? "Unable to decode")]")
            throw NSError(domain: "CCOAuthService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }
        
        // Parser la réponse JSON
        do {
            let tokenResponse = try JSONDecoder().decode(CLITokenResponse.self, from: data)
            
            if configuration.enableDebugLogging {
                debugLog("🔐 Tokens received successfully!")
            }
            
            debugLog("ℹ️ ✅ Successfully decoded token response [hasToken=yes, hasSecret=yes]")
            
            return OAuthCredentials(
                token: tokenResponse.token,
                secret: tokenResponse.secret
            )
        } catch {
            if configuration.enableDebugLogging {
                debugLog("🔐 JSON parsing error: \(error)")
                debugLog("🔐 Response data: \(String(data: data, encoding: .utf8) ?? "nil")")
            }
            debugLog("❌ ❌ Failed to decode token response [error=\(error.localizedDescription), responseBody=\(String(data: data, encoding: .utf8) ?? "Unable to decode"), dataSize=\(data.count)]")
            throw error
        }
    }
    
    /// Gère la réception des tokens
    @MainActor
    private func handleTokensReceived(_ credentials: OAuthCredentials) {
        if configuration.enableDebugLogging {
            debugLog("🎉 AUTHENTICATION SUCCESS! Tokens received and saving to keychain...")
        }
        
        // Sauvegarder dans le keychain
        _ = keychainManager.saveCredentials(credentials)
        
        // Mettre à jour l'état
        isAuthenticated = true
        isAuthenticating = false
        authError = nil
        
        if configuration.enableDebugLogging {
            debugLog("🎉 Authentication completed successfully! User is now logged in.")
            debugLog("🔐 isAuthenticated: \(isAuthenticated)")
        }
        
        // Petite pause pour s'assurer que tout est bien sauvegardé
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconde
            
            // Fermer Safari
            safariViewController?.dismiss(animated: true)
            safariViewController = nil
        }
        
        // Annuler le polling
        pollingTask?.cancel()
        pollingTask = nil
    }
    
    /// Gère les erreurs d'authentification
    @MainActor
    private func handleAuthenticationError(_ message: String) {
        authError = message
        isAuthenticating = false
        
        debugLog("❌ ❌ Authentication failed [error=\(message), hadSafariOpen=\(safariViewController != nil ? "yes" : "no"), wasPolling=\(pollingTask != nil ? "yes" : "no")]")
        
        // Fermer Safari
        safariViewController?.dismiss(animated: true)
        safariViewController = nil
        
        // Annuler le polling
        pollingTask?.cancel()
        pollingTask = nil
        
        if configuration.enableDebugLogging {
            debugLog("🔐 Authentication error: \(message)")
        }
    }
}

// MARK: - SFSafariViewControllerDelegate
extension CCOAuthService: SFSafariViewControllerDelegate {
    nonisolated func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        // Safari closed (either by user or automatically after auth)
        Task {
            await MainActor.run {
                debugLog("⚠️ ⚠️ Safari dismissed [wasAuthenticating=\(isAuthenticating ? "yes" : "no")]")
                
                // IMPORTANT: Don't cancel polling immediately!
                // Safari might close automatically after successful authentication
                // Let the polling continue to check if tokens were generated
                
                if isAuthenticating {
                    debugLog("ℹ️ 🔄 Safari closed but continuing to poll for tokens... [reason=Safari might close automatically after successful auth]")
                    
                    // Just clear the Safari reference, but don't stop polling
                    safariViewController = nil
                    
                    // Note: The polling will timeout on its own after 2 minutes if no tokens are found
                    // This gives time for the authentication to complete even if Safari closes
                }
            }
        }
    }
}

// MARK: - Supporting Types

/// Réponse du CLI token endpoint
private struct CLITokenResponse: Codable {
    let token: String
    let secret: String
} 