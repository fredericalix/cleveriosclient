import Foundation
import CryptoKit

/// OAuth 1.0a signer for Clever Cloud API authentication
public final class CCOAuthSigner: @unchecked Sendable {
    
    // MARK: - Properties
    
    /// SDK configuration with OAuth tokens
    private let configuration: CCConfiguration

    /// OAuth nonce/timestamp generators. Injectable so tests can pin a deterministic signature;
    /// the defaults reproduce the exact production behavior.
    private let nonceProvider: () -> String
    private let timestampProvider: () -> String

    // MARK: - Initialization

    /// Initialize OAuth signer with configuration
    /// - Parameters:
    ///   - configuration: SDK configuration containing OAuth tokens
    ///   - nonceProvider: test seam for a fixed nonce (default: random 32-char hex)
    ///   - timestampProvider: test seam for a fixed timestamp (default: current unix time)
    public init(configuration: CCConfiguration,
                nonceProvider: (() -> String)? = nil,
                timestampProvider: (() -> String)? = nil) {
        self.configuration = configuration
        self.nonceProvider = nonceProvider ?? {
            String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(32))
        }
        self.timestampProvider = timestampProvider ?? {
            String(Int(Date().timeIntervalSince1970))
        }
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
        
        // Generate OAuth parameters (injectable for deterministic tests)
        let timestamp = timestampProvider()
        let nonce = nonceProvider()
        
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
    
    // MARK: - Internal (test seams)

    /// Create OAuth signature base string. `internal` so tests can pin it against a known vector.
    func createSignatureBaseString(
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

        // Get base URL (without query parameters).
        // CRITICAL: use the ENCODED path as actually sent in the HTTP request — requestURL.path
        // auto-decodes, so we slice it out of absoluteString to preserve encoding.
        let absoluteString = requestURL.absoluteString
        let baseURL: String
        if let host = requestURL.host, let scheme = requestURL.scheme,
           let hostEndIndex = absoluteString.range(of: host)?.upperBound {
            let pathWithQuery = String(absoluteString[hostEndIndex...])
            let path = pathWithQuery.components(separatedBy: "?").first ?? pathWithQuery
            baseURL = "\(scheme)://\(host)\(path)"
        } else {
            // Defensive fallback (URLs originate from our own buildURL, so host/scheme are normally
            // present). Strip any query and sign the remaining absolute string.
            baseURL = absoluteString.components(separatedBy: "?").first ?? absoluteString
        }

        // Create signature base string
        let baseString = [
            httpMethod.uppercased(),
            baseURL.oauthPercentEncoded(),
            parameterString.oauthPercentEncoded()
        ].joined(separator: "&")
        
        // OAuth signature details available via enableDebugLogging if needed
        
        return baseString
    }
    
    /// Create OAuth signing key
    private func createSigningKey() -> String {
        let consumerSecret = configuration.consumerSecret.oauthPercentEncoded()
        let tokenSecret = configuration.accessTokenSecret.oauthPercentEncoded()
        return "\(consumerSecret)&\(tokenSecret)"
    }
    
    /// Generate HMAC-SHA512 signature. `internal` so tests can pin it against a precomputed value.
    func generateHMACSHA512Signature(
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