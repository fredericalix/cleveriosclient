import Foundation
import Combine

/// Configuration for Clever Cloud SDK with OAuth 1.0a authentication
public class CCConfiguration: ObservableObject {
    
    // MARK: - OAuth 1.0a Properties
    
    /// OAuth consumer key (identifies the application)
    public let consumerKey: String
    
    /// OAuth consumer secret (authenticates the application)
    public let consumerSecret: String
    
    /// OAuth access token (identifies the user)
    @Published public private(set) var accessToken: String
    
    /// OAuth access token secret (authenticates the user)
    @Published public private(set) var accessTokenSecret: String
    
    // MARK: - Additional Configuration
    
    /// Enable debug logging
    public let enableDebugLogging: Bool
    
    /// Base URL for Clever Cloud API v2
    public static let apiV2BaseURL = "https://api.clever-cloud.com/v2"
    
    /// Base URL for Clever Cloud API v4
    public static let apiV4BaseURL = "https://api.clever-cloud.com/v4"
    
    // MARK: - Initialization
    
    /// Initialize with OAuth 1.0a tokens
    /// - Parameters:
    ///   - consumerKey: OAuth consumer key
    ///   - consumerSecret: OAuth consumer secret
    ///   - accessToken: OAuth access token
    ///   - accessTokenSecret: OAuth access token secret
    ///   - enableDebugLogging: Enable debug logging (default: false)
    public init(
        consumerKey: String,
        consumerSecret: String,
        accessToken: String,
        accessTokenSecret: String,
        enableDebugLogging: Bool = false
    ) {
        self.consumerKey = consumerKey
        self.consumerSecret = consumerSecret
        self.accessToken = accessToken
        self.accessTokenSecret = accessTokenSecret
        self.enableDebugLogging = enableDebugLogging
        self.legacyApiToken = nil
    }
    
    /// Initialize with consumer keys only (for OAuth flow)
    /// - Parameters:
    ///   - consumerKey: OAuth consumer key
    ///   - consumerSecret: OAuth consumer secret
    ///   - enableDebugLogging: Enable debug logging (default: false)
    public init(
        consumerKey: String,
        consumerSecret: String,
        enableDebugLogging: Bool = false
    ) {
        self.consumerKey = consumerKey
        self.consumerSecret = consumerSecret
        self.accessToken = ""
        self.accessTokenSecret = ""
        self.enableDebugLogging = enableDebugLogging
        self.legacyApiToken = nil
    }
    
    // MARK: - Legacy Bearer Token Support
    
    /// Legacy API token (for backward compatibility)
    @available(*, deprecated, message: "Use OAuth 1.0a tokens instead")
    public let legacyApiToken: String?
    
    /// Initialize with legacy Bearer token (deprecated)
    /// - Parameters:
    ///   - apiToken: Legacy API token
    ///   - enableDebugLogging: Enable debug logging
    @available(*, deprecated, message: "Use OAuth 1.0a initializer instead")
    public init(apiToken: String, enableDebugLogging: Bool = false) {
        self.legacyApiToken = apiToken
        self.consumerKey = ""
        self.consumerSecret = ""
        self.accessToken = ""
        self.accessTokenSecret = ""
        self.enableDebugLogging = enableDebugLogging
    }
    
    // MARK: - Computed Properties
    
    /// Check if OAuth 1.0a tokens are configured
    public var hasOAuthTokens: Bool {
        return !consumerKey.isEmpty && !consumerSecret.isEmpty && 
               !accessToken.isEmpty && !accessTokenSecret.isEmpty
    }
    
    /// Check if legacy token is configured
    public var hasLegacyToken: Bool {
        return legacyApiToken != nil && !legacyApiToken!.isEmpty
    }
    
    /// Check if any authentication is configured
    public var isAuthenticated: Bool {
        return hasOAuthTokens || hasLegacyToken
    }
    
    // MARK: - Dynamic Token Management
    
    /// Updates the OAuth access tokens (for OAuth flow completion)
    /// - Parameters:
    ///   - accessToken: New OAuth access token
    ///   - accessTokenSecret: New OAuth access token secret
    public func updateTokens(accessToken: String, accessTokenSecret: String) {
        self.accessToken = accessToken
        self.accessTokenSecret = accessTokenSecret
        
        if enableDebugLogging {
            RemoteLogger.shared.info("✅ CCConfiguration: Tokens updated")
            RemoteLogger.shared.debug("   Access Token: \(accessToken.prefix(10))...")
            RemoteLogger.shared.debug("   Token Secret: \(accessTokenSecret.prefix(10))...")
        }
        
        objectWillChange.send()
    }
    
    /// Clears the OAuth access tokens (for logout)
    public func clearTokens() {
        self.accessToken = ""
        self.accessTokenSecret = ""
        
        if enableDebugLogging {
            RemoteLogger.shared.info("🗑️ CCConfiguration: Tokens cleared")
        }
        
        objectWillChange.send()
    }
} 