import Foundation
import Combine
import CryptoKit

// Internal imports for CleverCloudSDK components
// These types are defined in other files within the same SDK

/// HTTP client for Clever Cloud API with OAuth 1.0a authentication
public final class CCHTTPClient: ObservableObject {
    
    // MARK: - Properties
    
    /// SDK configuration
    private let configuration: CCConfiguration
    
    /// URL session for HTTP requests
    private let urlSession: URLSession
    
    /// OAuth 1.0a signer
    private let oauthSigner: CCOAuthSigner
    
    // MARK: - Initialization
    
    /// Initialize HTTP client with configuration
    /// - Parameter configuration: SDK configuration
    public init(configuration: CCConfiguration) {
        self.configuration = configuration
        self.oauthSigner = CCOAuthSigner(configuration: configuration)
        
        // Configure URL session
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 30.0
        sessionConfig.timeoutIntervalForResource = 60.0
        
        self.urlSession = URLSession(configuration: sessionConfig)
        
        if configuration.enableDebugLogging {
            RemoteLogger.shared.debug("🌐 [CCHTTPClient] Initialized with OAuth 1.0a authentication")
        }
    }
    
    // MARK: - HTTP Methods
    
    /// Perform GET request
    /// - Parameters:
    ///   - endpoint: API endpoint
    ///   - apiVersion: API version (.v2 or .v4)
    /// - Returns: Publisher with decoded response
    public func get<T: Codable>(
        _ endpoint: String,
        apiVersion: APIVersion = .v2
    ) -> AnyPublisher<T, CCError> {
        return request(method: .GET, endpoint: endpoint, body: nil as String?, apiVersion: apiVersion)
    }
    
    /// Perform POST request
    /// - Parameters:
    ///   - endpoint: API endpoint
    ///   - body: Request body
    ///   - apiVersion: API version
    /// - Returns: Publisher with decoded response
    public func post<T: Codable, U: Codable>(
        _ endpoint: String,
        body: U?,
        apiVersion: APIVersion = .v2
    ) -> AnyPublisher<T, CCError> {
        return request(method: .POST, endpoint: endpoint, body: body, apiVersion: apiVersion)
    }
    
    /// Perform PUT request
    /// - Parameters:
    ///   - endpoint: API endpoint
    ///   - body: Request body
    ///   - apiVersion: API version
    /// - Returns: Publisher with decoded response
    public func put<T: Codable, U: Codable>(
        _ endpoint: String,
        body: U?,
        apiVersion: APIVersion = .v2
    ) -> AnyPublisher<T, CCError> {
        return request(method: .PUT, endpoint: endpoint, body: body, apiVersion: apiVersion)
    }
    
    /// Perform DELETE request
    /// - Parameters:
    ///   - endpoint: API endpoint
    ///   - apiVersion: API version
    /// - Returns: Publisher with decoded response
    public func delete<T: Codable>(
        _ endpoint: String,
        apiVersion: APIVersion = .v2
    ) -> AnyPublisher<T, CCError> {
        // Use standard request method - OAuth signer now handles URL normalization correctly
        return request(method: .DELETE, endpoint: endpoint, body: nil as String?, apiVersion: apiVersion)
    }
    
    /// Perform POST request without body
    /// - Parameters:
    ///   - endpoint: API endpoint
    ///   - apiVersion: API version
    /// - Returns: Publisher with decoded response
    public func postWithoutBody<T: Codable>(
        _ endpoint: String,
        apiVersion: APIVersion = .v2
    ) -> AnyPublisher<T, CCError> {
        return request(method: .POST, endpoint: endpoint, body: nil as String?, apiVersion: apiVersion)
    }
    
    /// Perform DELETE request without body (alias for delete method)
    /// - Parameters:
    ///   - endpoint: API endpoint
    ///   - apiVersion: API version
    /// - Returns: Publisher with decoded response
    public func deleteWithoutBody<T: Codable>(
        _ endpoint: String,
        apiVersion: APIVersion = .v2
    ) -> AnyPublisher<T, CCError> {
        return request(method: .DELETE, endpoint: endpoint, body: nil as String?, apiVersion: apiVersion)
    }
    
    /// Perform DELETE request for endpoints that return empty responses
    /// - Parameters:
    ///   - endpoint: API endpoint
    ///   - apiVersion: API version
    /// - Returns: Publisher with void response (success only)
    public func deleteRaw(
        _ endpoint: String,
        apiVersion: APIVersion = .v2
    ) -> AnyPublisher<Void, CCError> {
        return request(method: .DELETE, endpoint: endpoint, body: nil as String?, apiVersion: apiVersion)
            .map { (_: EmptyResponse) in () }
            .catch { error -> AnyPublisher<Void, CCError> in
                // If decoding fails, assume success for empty response
                if case .parsingError = error {
                    return Just(()).setFailureType(to: CCError.self).eraseToAnyPublisher()
                } else {
                    return Fail(error: error).eraseToAnyPublisher()
                }
            }
            .eraseToAnyPublisher()
    }
    
    /// Perform POST request for endpoints that return empty responses
    /// - Parameters:
    ///   - endpoint: API endpoint
    ///   - body: Request body
    ///   - apiVersion: API version
    /// - Returns: Publisher with void response (success only)
    public func postRaw<T: Codable>(
        _ endpoint: String,
        body: T,
        apiVersion: APIVersion = .v2
    ) -> AnyPublisher<Void, CCError> {
        return request(method: .POST, endpoint: endpoint, body: body, apiVersion: apiVersion)
            .map { (_: EmptyResponse) in () }
            .catch { error -> AnyPublisher<Void, CCError> in
                // If decoding fails, assume success for empty response
                if case .parsingError = error {
                    return Just(()).setFailureType(to: CCError.self).eraseToAnyPublisher()
                } else {
                    return Fail(error: error).eraseToAnyPublisher()
                }
            }
            .eraseToAnyPublisher()
    }
    
    // MARK: - Raw Request Methods
    
    /// Perform GET request and return raw string (no JSON decoding)
    /// - Parameters:
    ///   - endpoint: API endpoint
    ///   - apiVersion: API version
    /// - Returns: Publisher with raw string response
    public func getRawString(
        _ endpoint: String,
        apiVersion: APIVersion = .v2
    ) -> AnyPublisher<String, CCError> {
        return requestRaw(method: .GET, endpoint: endpoint, apiVersion: apiVersion)
            .tryMap { data in
                guard let string = String(data: data, encoding: .utf8) else {
                    throw CCError.parsingError(NSError(domain: "StringConversion", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to convert data to UTF-8 string"]))
                }
                return string
            }
            .mapError { error in
                if let ccError = error as? CCError {
                    return ccError
                }
                return CCError.unknown(error)
            }
            .eraseToAnyPublisher()
    }
    
    /// GET request with raw data response
    /// - Parameters:
    ///   - endpoint: API endpoint
    ///   - apiVersion: API version
    /// - Returns: Publisher with raw data response
    public func getRawData(
        _ endpoint: String,
        apiVersion: APIVersion = .v4
    ) -> AnyPublisher<Data, CCError> {
        return requestRaw(method: .GET, endpoint: endpoint, apiVersion: apiVersion)
    }
    
    /// Perform HTTP request and return raw data (no JSON decoding)
    /// - Parameters:
    ///   - method: HTTP method
    ///   - endpoint: API endpoint
    ///   - apiVersion: API version
    /// - Returns: Publisher with raw data response
    public func requestRaw(
        method: HTTPMethod,
        endpoint: String,
        apiVersion: APIVersion
    ) -> AnyPublisher<Data, CCError> {
        
        // Build URL
        guard let url = buildURL(endpoint: endpoint, apiVersion: apiVersion) else {
            return Fail(error: CCError.invalidURL)
                .eraseToAnyPublisher()
        }
        
        // Create request - URLRequest may normalize the URL and add trailing slashes
        // We need to handle this carefully for OAuth signature matching
        var request = URLRequest(url: url)

        // CRITICAL FIX: If URLRequest added a trailing slash that wasn't in the original URL,
        // we need to recreate it without the slash
        if let requestPath = request.url?.path,
           requestPath.hasSuffix("/") && !url.path.hasSuffix("/") {
            // Create a new URL without the trailing slash
            if var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                components.path = url.path  // Use the original path without modifications
                if let fixedURL = components.url {
                    request = URLRequest(url: fixedURL)
                }
            }
        }

        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Add OAuth 1.0a authentication headers
        do {
            request = try oauthSigner.signRequest(request)
        } catch {
            return Fail(error: CCError.authenticationFailed)
                .eraseToAnyPublisher()
        }

        if configuration.enableDebugLogging {
            // Log the actual URL being used in the request after OAuth signing
            let requestURL = request.url?.absoluteString ?? "No URL"
            RemoteLogger.shared.debug("🚀 [CCHTTPClient] \(method.rawValue) \(requestURL)")
            if let authHeader = request.value(forHTTPHeaderField: "Authorization") {
                RemoteLogger.shared.debug("🔐 [CCHTTPClient] OAuth: \(String(authHeader.prefix(50)))...")
            }
        }
        
        // Perform request
        return urlSession.dataTaskPublisher(for: request)
            .tryMap { data, response in
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw CCError.invalidResponse
                }
                
                // Log response for debugging
                if self.configuration.enableDebugLogging {
                    RemoteLogger.shared.debug("📡 HTTP Response", metadata: [
                        "statusCode": "\(httpResponse.statusCode)",
                        "url": httpResponse.url?.absoluteString ?? "unknown"
                    ])

                    if let responseString = String(data: data, encoding: .utf8) {
                        RemoteLogger.shared.debug("📦 Raw response: \(responseString.prefix(500))")
                    }

                    // EMERGENCY DEBUG: Log ALL HTTP responses to find the DELETE
                    if let url = httpResponse.url?.absoluteString {
                        RemoteLogger.shared.debug("🚨 [ALL HTTP DEBUG] URL: \(url)")
                        RemoteLogger.shared.debug("🚨 [ALL HTTP DEBUG] Status: \(httpResponse.statusCode)")

                        // Special focus on vhosts operations
                        if url.contains("vhosts") {
                            RemoteLogger.shared.debug("🗑️ [VHOSTS DEBUG] FOUND VHOSTS URL: \(url)")
                            RemoteLogger.shared.debug("🗑️ [VHOSTS DEBUG] Status: \(httpResponse.statusCode)")
                            RemoteLogger.shared.debug("🗑️ [VHOSTS DEBUG] Headers: \(httpResponse.allHeaderFields)")
                            if let responseString = String(data: data, encoding: .utf8) {
                                RemoteLogger.shared.debug("🗑️ [VHOSTS DEBUG] Response body: '\(responseString)'")
                            } else {
                                RemoteLogger.shared.debug("🗑️ [VHOSTS DEBUG] Response body: (binary data, \(data.count) bytes)")
                            }
                        }
                    }
                }
                
                switch httpResponse.statusCode {
                case 200...299:
                    return data
                case 401:
                    let errorBody = String(data: data, encoding: .utf8) ?? "No error body"
                    RemoteLogger.shared.error("🔒 401 Unauthorized: \(errorBody)")
                    throw CCError.authenticationFailed
                case 404:
                    throw CCError.resourceNotFound
                default:
                    let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                    throw CCError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
                }
            }
            .receive(on: DispatchQueue.main)
            .mapError { error in
                if let ccError = error as? CCError {
                    return ccError
                }
                return CCError.unknown(error)
            }
            .eraseToAnyPublisher()
    }
    
    /// Perform HTTP request with body and return raw data (no JSON decoding)
    /// - Parameters:
    ///   - method: HTTP method
    ///   - endpoint: API endpoint
    ///   - body: Request body
    ///   - apiVersion: API version
    /// - Returns: Publisher with raw data response
    public func requestRawWithBody<U: Codable>(
        method: HTTPMethod,
        endpoint: String,
        body: U?,
        apiVersion: APIVersion
    ) -> AnyPublisher<Data, CCError> {
        
        // Build URL
        guard let url = buildURL(endpoint: endpoint, apiVersion: apiVersion) else {
            return Fail(error: CCError.invalidURL)
                .eraseToAnyPublisher()
        }
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        // Add body if present
        if let body = body {
            do {
                // Use a custom encoder that respects field ordering for API compatibility
                let encoder = JSONEncoder()
                encoder.outputFormatting = [] // No pretty printing to match API expectations
                let bodyData = try encoder.encode(body)
                request.httpBody = bodyData
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                
                // Debug: Log the JSON payload being sent
                if configuration.enableDebugLogging {
                    if let jsonString = String(data: bodyData, encoding: .utf8) {
                        print("📦 [DEBUG] JSON Payload being sent:")
                        print("📦 [DEBUG] \(jsonString)")
                    }
                }
            } catch {
                return Fail(error: CCError.invalidParameters("Failed to encode request body"))
                    .eraseToAnyPublisher()
            }
        }
        
        // Add OAuth 1.0a authentication headers
        do {
            request = try oauthSigner.signRequest(request)
        } catch {
            return Fail(error: CCError.authenticationFailed)
                .eraseToAnyPublisher()
        }
        
        if configuration.enableDebugLogging {
            RemoteLogger.shared.debug("🚀 [CCHTTPClient] \(method.rawValue) \(url)")
        }
        
        // Perform request
        return urlSession.dataTaskPublisher(for: request)
            .tryMap { data, response in
                guard let httpResponse = response as? HTTPURLResponse else {
                    RemoteLogger.shared.error("Invalid response type")
                    throw CCError.invalidResponse
                }
                
                // Log response details (missing from original requestRawWithBody implementation)
                RemoteLogger.shared.debug("📡 HTTP Response", metadata: [
                    "statusCode": "\(httpResponse.statusCode)",
                    "url": httpResponse.url?.absoluteString ?? "unknown",
                    "headers": httpResponse.allHeaderFields.description
                ])
                
                // Log raw response data
                let rawResponse = String(data: data, encoding: .utf8) ?? "Unable to decode as UTF-8"
                RemoteLogger.shared.debug("📦 Raw response data", metadata: [
                    "size": "\(data.count) bytes",
                    "preview": String(rawResponse.prefix(500))
                ])
                
                switch httpResponse.statusCode {
                case 200...299:
                    return data
                case 401:
                    RemoteLogger.shared.error("🔒 Unauthorized - OAuth token may be invalid")
                    throw CCError.authenticationFailed
                case 404:
                    RemoteLogger.shared.error("🔍 Not Found - Resource doesn't exist")
                    RemoteLogger.shared.error("❌ 404 ERROR DETAILS", metadata: [
                        "url": httpResponse.url?.absoluteString ?? "unknown",
                        "method": method.rawValue,
                        "endpoint": endpoint,
                        "fullURL": url.absoluteString
                    ])
                    let errorBody = String(data: data, encoding: .utf8) ?? "No error body"
                    RemoteLogger.shared.error("❌ 404 ERROR BODY: \(errorBody)")
                    throw CCError.resourceNotFound
                default:
                    let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                    RemoteLogger.shared.error("HTTP Error \(httpResponse.statusCode)", metadata: [
                        "endpoint": endpoint,
                        "errorBody": errorMessage
                    ])
                    throw CCError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
                }
            }
            .receive(on: DispatchQueue.main)
            .mapError { error in
                if let ccError = error as? CCError {
                    return ccError
                }
                return CCError.unknown(error)
            }
            .eraseToAnyPublisher()
    }
    
    // MARK: - Core Request Method
    
    /// Perform HTTP request with OAuth 1.0a authentication
    /// - Parameters:
    ///   - method: HTTP method
    ///   - endpoint: API endpoint
    ///   - body: Request body
    ///   - apiVersion: API version
    /// - Returns: Publisher with decoded response
    private func request<T: Codable, U: Codable>(
        method: HTTPMethod,
        endpoint: String,
        body: U?,
        apiVersion: APIVersion
    ) -> AnyPublisher<T, CCError> {

        // Build URL
        guard let url = buildURL(endpoint: endpoint, apiVersion: apiVersion) else {
            return Fail(error: CCError.invalidURL)
                .eraseToAnyPublisher()
        }

        // Create request - URLRequest may normalize the URL and add trailing slashes
        // We need to handle this carefully for OAuth signature matching
        var request = URLRequest(url: url)

        // CRITICAL FIX: If URLRequest added a trailing slash that wasn't in the original URL,
        // we need to recreate it without the slash
        if let requestPath = request.url?.path,
           requestPath.hasSuffix("/") && !url.path.hasSuffix("/") {
            // Create a new URL without the trailing slash
            if var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                components.path = url.path  // Use the original path without modifications
                if let fixedURL = components.url {
                    request = URLRequest(url: fixedURL)
                }
            }
        }

        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        // Add body if present
        if let body = body {
            do {
                // Use a custom encoder that respects field ordering for API compatibility
                let encoder = JSONEncoder()
                encoder.outputFormatting = [] // No pretty printing to match API expectations
                let bodyData = try encoder.encode(body)
                request.httpBody = bodyData
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                
                // Debug: Log the JSON payload being sent
                if configuration.enableDebugLogging {
                    if let jsonString = String(data: bodyData, encoding: .utf8) {
                        print("📦 [DEBUG] JSON Payload being sent:")
                        print("📦 [DEBUG] \(jsonString)")
                    }
                }
            } catch {
                return Fail(error: CCError.invalidParameters("Failed to encode request body"))
                    .eraseToAnyPublisher()
            }
        }
        
        // Add OAuth 1.0a authentication headers
        do {
            request = try oauthSigner.signRequest(request)
        } catch {
            return Fail(error: CCError.authenticationFailed)
                .eraseToAnyPublisher()
        }
        
        if configuration.enableDebugLogging {
            // Log the actual URL being used in the request, not the original URL
            // This helps us debug OAuth signature issues
            let requestURLString = request.url?.absoluteString ?? "No URL"
            RemoteLogger.shared.debug("🚀 [CCHTTPClient] \(method.rawValue) \(requestURLString)")
            if let authHeader = request.value(forHTTPHeaderField: "Authorization") {
                RemoteLogger.shared.debug("🔐 [CCHTTPClient] OAuth: \(String(authHeader.prefix(50)))...")
            }
        }
        
        // Perform request
        return urlSession.dataTaskPublisher(for: request)
            .tryMap { [weak self] data, response in
                guard let httpResponse = response as? HTTPURLResponse else {
                    RemoteLogger.shared.error("Invalid response type")
                    throw CCError.invalidResponse
                }
                
                // Log metrics response details
                if endpoint.contains("metrics") || endpoint.contains("stats") {
                    let responseBody = String(data: data, encoding: .utf8) ?? "Unable to decode response"
                    RemoteLogger.shared.debug("[CleverMetrics] HTTP Response", metadata: [
                        "statusCode": "\(httpResponse.statusCode)",
                        "endpoint": endpoint,
                        "responseBody": responseBody.prefix(500).description,
                        "headers": httpResponse.allHeaderFields.description
                    ])
                }
                
                // Log response details
                RemoteLogger.shared.debug("📡 HTTP Response", metadata: [
                    "statusCode": "\(httpResponse.statusCode)",
                    "url": httpResponse.url?.absoluteString ?? "unknown",
                    "headers": httpResponse.allHeaderFields.description
                ])
                
                // Check status code
                switch httpResponse.statusCode {
                case 200...299:
                    // Success - decode response
                    let rawResponse = String(data: data, encoding: .utf8) ?? "Unable to decode as UTF-8"
                    RemoteLogger.shared.debug("📦 Raw response data", metadata: [
                        "size": "\(data.count) bytes",
                        "preview": String(rawResponse.prefix(500))
                    ])

                    // EMERGENCY DEBUG: Log ALL HTTP responses to find the DELETE
                    if let url = httpResponse.url?.absoluteString {
                        RemoteLogger.shared.debug("🚨 [ALL HTTP DEBUG] URL: \(url)")
                        RemoteLogger.shared.debug("🚨 [ALL HTTP DEBUG] Status: \(httpResponse.statusCode)")

                        // Special focus on vhosts operations
                        if url.contains("vhosts") {
                            RemoteLogger.shared.debug("🗑️ [VHOSTS DEBUG] FOUND VHOSTS URL: \(url)")
                            RemoteLogger.shared.debug("🗑️ [VHOSTS DEBUG] Status: \(httpResponse.statusCode)")
                            RemoteLogger.shared.debug("🗑️ [VHOSTS DEBUG] Headers: \(httpResponse.allHeaderFields)")
                            RemoteLogger.shared.debug("🗑️ [VHOSTS DEBUG] Response body: '\(rawResponse)'")
                        }
                    }
                    
                    do {
                        let decoder = JSONDecoder()
                        decoder.dateDecodingStrategy = .iso8601
                        let decodedResponse = try decoder.decode(T.self, from: data)
                        return decodedResponse
                    } catch {
                        RemoteLogger.shared.error("❌ JSON Decoding Error", metadata: [
                            "error": error.localizedDescription,
                            "type": String(describing: T.self),
                            "rawData": rawResponse,
                            "decodingError": String(describing: error)
                        ])
                        throw CCError.parsingError(error)
                    }
                    
                case 401:
                    RemoteLogger.shared.error("🔒 Unauthorized - OAuth token may be invalid")
                    throw CCError.authenticationFailed
                    
                case 404:
                    RemoteLogger.shared.error("🔍 Not Found - Resource doesn't exist")
                    // Add detailed error logging for debugging
                    RemoteLogger.shared.error("❌ 404 ERROR DETAILS", metadata: [
                        "url": httpResponse.url?.absoluteString ?? "unknown",
                        "method": method.rawValue,
                        "endpoint": endpoint,
                        "fullURL": url.absoluteString
                    ])
                    let errorBody = String(data: data, encoding: .utf8) ?? "No error body"
                    RemoteLogger.shared.error("❌ 404 ERROR BODY: \(errorBody)")
                    throw CCError.resourceNotFound
                    
                default:
                    let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                    RemoteLogger.shared.error("[CleverMetrics] HTTP Error \(httpResponse.statusCode)", metadata: [
                        "endpoint": endpoint,
                        "errorBody": errorMessage
                    ])
                    
                    // Enhanced logging for application creation errors
                    if endpoint.contains("applications") && method.rawValue == "POST" {
                        print("❌ [APPLICATION CREATION ERROR] Status: \(httpResponse.statusCode)")
                        print("❌ [APPLICATION CREATION ERROR] Endpoint: \(endpoint)")
                        print("❌ [APPLICATION CREATION ERROR] Error Body: \(errorMessage)")
                        print("❌ [APPLICATION CREATION ERROR] Headers: \(httpResponse.allHeaderFields)")
                    }
                    
                    throw CCError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
                }
            }
            .receive(on: DispatchQueue.main)
            .mapError { error in
                if let ccError = error as? CCError {
                    return ccError
                } else if error is DecodingError {
                    RemoteLogger.shared.error("❌ DECODING ERROR: \(error.localizedDescription)")
                    if let decodingError = error as? DecodingError {
                        RemoteLogger.shared.error("❌ DECODING ERROR DETAILS: \(String(describing: decodingError))")
                    }
                    return CCError.invalidResponse
                } else {
                    return CCError.unknown(error)
                }
            }
            .eraseToAnyPublisher()
    }
    
    // MARK: - Bearer Token Request Method
    
    /// Perform HTTP request with Bearer token authentication (for v4 metrics API)
    /// - Parameters:
    ///   - method: HTTP method
    ///   - endpoint: API endpoint
    ///   - token: Bearer token
    ///   - apiVersion: API version
    /// - Returns: Publisher with decoded response
    public func requestWithBearerToken<T: Codable>(
        method: HTTPMethod,
        endpoint: String,
        token: String,
        apiVersion: APIVersion
    ) -> AnyPublisher<T, CCError> {
        
        // Build URL
        guard let url = buildURL(endpoint: endpoint, apiVersion: apiVersion) else {
            return Fail(error: CCError.invalidURL)
                .eraseToAnyPublisher()
        }
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        if configuration.enableDebugLogging {
            RemoteLogger.shared.debug("🚀 [CCHTTPClient] \(method.rawValue) \(url) with Bearer token")
        }
        
        // Perform request
        return urlSession.dataTaskPublisher(for: request)
            .tryMap { [weak self] data, response in
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw CCError.invalidResponse
                }
                
                // Log response for debugging
                RemoteLogger.shared.debug("📡 Bearer Token Response", metadata: [
                    "statusCode": "\(httpResponse.statusCode)",
                    "endpoint": endpoint,
                    "url": url.absoluteString
                ])
                
                switch httpResponse.statusCode {
                case 200...299:
                    // Success - decode response
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    let decodedResponse = try decoder.decode(T.self, from: data)
                    return decodedResponse
                    
                case 401:
                    RemoteLogger.shared.error("🔒 Unauthorized - Bearer token may be invalid")
                    throw CCError.authenticationFailed
                    
                case 404:
                    throw CCError.resourceNotFound
                    
                default:
                    let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                    RemoteLogger.shared.error("HTTP Error \(httpResponse.statusCode)", metadata: [
                        "endpoint": endpoint,
                        "errorBody": errorMessage
                    ])
                    throw CCError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
                }
            }
            .receive(on: DispatchQueue.main)
            .mapError { error in
                if let ccError = error as? CCError {
                    return ccError
                }
                return CCError.unknown(error)
            }
            .eraseToAnyPublisher()
    }
    
    // MARK: - Helper Methods
    
    /// Build complete URL from endpoint and API version
    ///   - endpoint: API endpoint path
    ///   - apiVersion: API version
    private func buildURL(endpoint: String, apiVersion: APIVersion) -> URL? {
        let baseURL = apiVersion == .v2 ? CCConfiguration.apiV2BaseURL : CCConfiguration.apiV4BaseURL
        let cleanEndpoint = endpoint.hasPrefix("/") ? endpoint : "/\(endpoint)"
        var urlString = baseURL + cleanEndpoint

        // Critical: Remove any trailing slash from the URL string before creating URL object
        // This prevents URL normalization issues that cause OAuth signature mismatch
        if urlString.hasSuffix("/") && !urlString.hasSuffix("://") {
            urlString = String(urlString.dropLast())
        }

        // Log URL construction for debugging
        if configuration.enableDebugLogging {
            RemoteLogger.shared.debug("[CCHTTPClient] Building URL", metadata: [
                "baseURL": baseURL,
                "endpoint": endpoint,
                "cleanEndpoint": cleanEndpoint,
                "finalURL": urlString,
                "apiVersion": apiVersion == .v2 ? "v2" : "v4"
            ])
        }

        return URL(string: urlString)
    }
    
    /// Handle HTTP response and extract data
    /// - Parameters:
    ///   - data: Response data
    ///   - response: HTTP response
    /// - Returns: Response data
    /// - Throws: CCError for HTTP errors
    private func handleResponse(data: Data, response: URLResponse) throws -> Data {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CCError.invalidResponse
        }
        
        if configuration.enableDebugLogging {
            RemoteLogger.shared.debug("📡 [CCHTTPClient] Response: \(httpResponse.statusCode) (\(data.count) bytes)")
            
                    // Raw JSON response available for debugging if needed
        }
        
        switch httpResponse.statusCode {
        case 200...299:
            return data
        case 400:
            throw CCError.invalidParameters("Bad request")
        case 401:
            throw CCError.authenticationFailed
        case 403:
            throw CCError.accessDenied
        case 404:
            throw CCError.resourceNotFound
        case 409:
            throw CCError.resourceExists
        case 429:
            throw CCError.rateLimitExceeded
        case 500...599:
            throw CCError.httpError(statusCode: httpResponse.statusCode, message: "Server error")
        default:
            throw CCError.httpError(statusCode: httpResponse.statusCode, message: "HTTP error")
        }
    }

    // MARK: - SSE Request Method

    /// Perform GET request to an SSE (Server-Sent Events) endpoint.
    /// Collects streamed log events until a HEARTBEAT arrives after log data,
    /// or until `timeout` seconds elapse (whichever comes first).
    public func getSSEData(
        _ endpoint: String,
        apiVersion: APIVersion = .v4,
        timeout: TimeInterval = 10.0
    ) -> AnyPublisher<Data, CCError> {
        guard let url = buildURL(endpoint: endpoint, apiVersion: apiVersion) else {
            return Fail(error: CCError.invalidURL).eraseToAnyPublisher()
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        do {
            request = try oauthSigner.signRequest(request)
        } catch {
            return Fail(error: CCError.authenticationFailed).eraseToAnyPublisher()
        }

        return Future<Data, CCError> { promise in
            let collector = SSEDataCollector(promise: promise)
            let session = URLSession(configuration: .default, delegate: collector, delegateQueue: nil)
            let task = session.dataTask(with: request)
            collector.session = session
            task.resume()

            // Hard timeout as safety net
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                collector.finish(task: task)
            }
        }
        .receive(on: DispatchQueue.main)
        .eraseToAnyPublisher()
    }
}

// MARK: - SSE Data Collector

/// Delegate that accumulates SSE data. Finishes when it detects a HEARTBEAT
/// after having received at least one APPLICATION_LOG event (meaning the
/// historical log burst is over and we're now in live-tail mode).
private final class SSEDataCollector: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private var accumulatedData = Data()
    private let promise: (Result<Data, CCError>) -> Void
    private var completed = false
    private var hasReceivedLogEvents = false
    var session: URLSession?

    init(promise: @escaping (Result<Data, CCError>) -> Void) {
        self.promise = promise
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        accumulatedData.append(data)

        // Check if we received log events followed by a heartbeat
        if let text = String(data: data, encoding: .utf8) {
            if text.contains("APPLICATION_LOG") {
                hasReceivedLogEvents = true
            }
            // If we already got log events and now see a heartbeat,
            // the historical burst is done - finish collecting
            if hasReceivedLogEvents && text.contains("HEARTBEAT") {
                finish(task: dataTask)
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !completed else { return }
        completed = true
        self.session?.invalidateAndCancel()

        if !accumulatedData.isEmpty {
            promise(.success(accumulatedData))
        } else if let error = error {
            promise(.failure(CCError.networkError(error)))
        } else {
            promise(.success(Data()))
        }
    }

    func finish(task: URLSessionTask) {
        guard !completed else { return }
        completed = true
        task.cancel()
        self.session?.invalidateAndCancel()
        promise(.success(accumulatedData))
    }
}

// MARK: - Supporting Types

/// HTTP methods
public enum HTTPMethod: String {
    case GET = "GET"
    case POST = "POST"
    case PUT = "PUT"
    case DELETE = "DELETE"
}

/// API versions
public enum APIVersion {
    case v2
    case v4
}

 