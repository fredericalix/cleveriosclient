import Foundation
import CryptoKit

/// OAuth 1.0a signer for Clever Cloud API authentication
public final class CCOAuthSigner: @unchecked Sendable {
    
    // MARK: - Properties
    
    /// SDK configuration with OAuth tokens
    private let configuration: CCConfiguration
    
    // MARK: - Initialization
    
    /// Initialize OAuth signer with configuration
    /// - Parameter configuration: SDK configuration containing OAuth tokens
    public init(configuration: CCConfiguration) {
        self.configuration = configuration
    }
    
    // MARK: - OAuth Request Signing
    
    /// Sign HTTP request with OAuth 1.0a
    /// - Parameter request: HTTP request to sign
    /// - Returns: Signed request with Authorization header
    /// - Throws: Error if signing fails
    public func signRequest(_ request: URLRequest) throws -> URLRequest {
        // Check if we have OAuth tokens
        guard configuration.hasOAuthTokens else {
            // Fall back to legacy Bearer token if available
            if configuration.hasLegacyToken {
                var signedRequest = request
                signedRequest.setValue("Bearer \(configuration.legacyApiToken!)", forHTTPHeaderField: "Authorization")
                return signedRequest
            }
            throw CCError.authenticationFailed
        }
        
        guard let url = request.url else {
            throw CCError.invalidURL
        }
        
        // Extract query parameters from URL
        var queryParams: [String: String] = [:]
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItems = components.queryItems {
            for item in queryItems {
                if let value = item.value {
                    queryParams[item.name] = value
                }
            }
        }
        
        let authHeader = generateOAuthHeader(
            httpMethod: request.httpMethod ?? "GET",
            requestURL: url,
            parameters: queryParams
        )
        
        var signedRequest = request
        signedRequest.setValue(authHeader, forHTTPHeaderField: "Authorization")
        
        return signedRequest
    }
    
    /// Generate OAuth 1.0a signature for request
    /// - Parameters:
    ///   - httpMethod: HTTP method (GET, POST, etc.)
    ///   - requestURL: Complete request URL
    ///   - parameters: Query parameters (optional)
    /// - Returns: Authorization header value
    private func generateOAuthHeader(
        httpMethod: String,
        requestURL: URL,
        parameters: [String: String] = [:]
    ) -> String {
        
        // Generate OAuth parameters
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let nonce = generateNonce()
        
        // Create OAuth parameters
        var oauthParams: [String: String] = [
            "oauth_consumer_key": configuration.consumerKey,
            "oauth_token": configuration.accessToken,
            "oauth_signature_method": "HMAC-SHA512",
            "oauth_timestamp": timestamp,
            "oauth_nonce": nonce,
            "oauth_version": "1.0"
        ]
        
        // Combine OAuth params with request parameters
        var allParams = parameters
        allParams.merge(oauthParams) { _, new in new }
        
        // Generate signature base string
        let signatureBaseString = createSignatureBaseString(
            httpMethod: httpMethod,
            requestURL: requestURL,
            parameters: allParams
        )
        
        // Generate signing key
        let signingKey = createSigningKey()
        
        // Generate signature
        let signature = generateHMACSHA512Signature(
            baseString: signatureBaseString,
            signingKey: signingKey
        )
        
        // Add signature to OAuth parameters
        oauthParams["oauth_signature"] = signature
        
        // Build Authorization header
        return buildAuthorizationHeader(oauthParams: oauthParams)
    }
    
    // MARK: - Private Methods
    
    /// Generate random nonce
    private func generateNonce() -> String {
        let uuid = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        return String(uuid.prefix(32))
    }
    
    /// Create OAuth signature base string
    private func createSignatureBaseString(
        httpMethod: String,
        requestURL: URL,
        parameters: [String: String]
    ) -> String {
        
        // Sort parameters by key
        let sortedParams = parameters.sorted { $0.key < $1.key }
        
        // Create parameter string
        let parameterString = sortedParams
            .map { "\($0.key.oauthPercentEncoded())=\($0.value.oauthPercentEncoded())" }
            .joined(separator: "&")
        
        // Get base URL (without query parameters)
        let baseURL = "\(requestURL.scheme!)://\(requestURL.host!)\(requestURL.path)"
        
        // Create signature base string
        let baseString = [
            httpMethod.uppercased(),
            baseURL.oauthPercentEncoded(),
            parameterString.oauthPercentEncoded()
        ].joined(separator: "&")
        
        if configuration.enableDebugLogging {
            print("🔐 [OAuth] Signature Base String: \(baseString)")
            print("🔐 [OAuth] HTTP Method: \(httpMethod.uppercased())")
            print("🔐 [OAuth] Base URL: \(baseURL)")
            print("🔐 [OAuth] Parameter String: \(parameterString)")
            print("🔐 [OAuth] Sorted Parameters: \(sortedParams)")
        }
        
        return baseString
    }
    
    /// Create OAuth signing key
    private func createSigningKey() -> String {
        let consumerSecret = configuration.consumerSecret.oauthPercentEncoded()
        let tokenSecret = configuration.accessTokenSecret.oauthPercentEncoded()
        return "\(consumerSecret)&\(tokenSecret)"
    }
    
    /// Generate HMAC-SHA512 signature
    private func generateHMACSHA512Signature(
        baseString: String,
        signingKey: String
    ) -> String {
        
        let keyData = Data(signingKey.utf8)
        let messageData = Data(baseString.utf8)
        
        let signature = HMAC<SHA512>.authenticationCode(
            for: messageData,
            using: SymmetricKey(data: keyData)
        )
        
        let signatureString = Data(signature).base64EncodedString()
        
        if configuration.enableDebugLogging {
            print("🔐 [OAuth] Generated signature: \(signatureString.prefix(20))...")
        }
        
        return signatureString
    }
    
    /// Build OAuth Authorization header
    private func buildAuthorizationHeader(oauthParams: [String: String]) -> String {
        let headerParams = oauthParams
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\"\($0.value.oauthPercentEncoded())\"" }
            .joined(separator: ", ")
        
        return "OAuth \(headerParams)"
    }
}

// MARK: - String OAuth Extensions

extension String {
    
    /// OAuth percent encoding (RFC 3986)
    func oauthPercentEncoded() -> String {
        let unreservedCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")
        return self.addingPercentEncoding(withAllowedCharacters: unreservedCharacters) ?? self
    }
} 