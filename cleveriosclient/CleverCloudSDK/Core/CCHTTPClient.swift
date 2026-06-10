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
            debugLog("🔍 🌐 [CCHTTPClient] Initialized with OAuth 1.0a authentication")
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
        // Use the raw path: any 2xx is success regardless of body, and real HTTP errors (401/404/…)
        // still propagate. The old approach decoded EmptyResponse and swallowed ALL .parsingError,
        // which would also mask a 2xx carrying an unexpected (non-empty) body.
        return requestRaw(method: .DELETE, endpoint: endpoint, apiVersion: apiVersion)
            .map { _ in () }
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
        // See deleteRaw: raw path treats any 2xx as success and propagates real HTTP errors, instead
        // of decoding EmptyResponse and swallowing every .parsingError.
        return requestRawWithBody(method: .POST, endpoint: endpoint, body: body, apiVersion: apiVersion)
            .map { _ in () }
            .eraseToAnyPublisher()
    }
    
    // MARK: - Raw Request Methods
    
    /// Perform GET request and return raw string (no JSON decoding)
    /// - Parameters:
    ///   - endpoint: API endpoint
    ///   - apiVersion: API version
    ///   - accept: Value for the `Accept` header. Defaults to `application/json`; pass `text/plain`
    ///     for plain-text endpoints (e.g. WireGuard `.conf`) that 406 on a JSON Accept.
    /// - Returns: Publisher with raw string response
    public func getRawString(
        _ endpoint: String,
        apiVersion: APIVersion = .v2,
        accept: String = "application/json"
    ) -> AnyPublisher<String, CCError> {
        return requestRaw(method: .GET, endpoint: endpoint, apiVersion: apiVersion, accept: accept)
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
    ///   - accept: Value for the `Accept` header. Defaults to `application/json`; pass `text/plain`
    ///     for endpoints that serve plain text (e.g. WireGuard `.conf`), which 406 on a JSON Accept.
    /// - Returns: Publisher with raw data response
    public func requestRaw(
        method: HTTPMethod,
        endpoint: String,
        apiVersion: APIVersion,
        accept: String = "application/json"
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
        request.setValue(accept, forHTTPHeaderField: "Accept")

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
            debugLog("🔍 🚀 [CCHTTPClient] \(method.rawValue) \(requestURL)")
            if let authHeader = request.value(forHTTPHeaderField: "Authorization") {
                debugLog("🔍 🔐 [CCHTTPClient] OAuth: \(String(authHeader.prefix(50)))...")
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
                    debugLog("🔍 📡 HTTP Response [statusCode=\(httpResponse.statusCode), url=\(httpResponse.url?.absoluteString ?? "unknown")]")

                    debugLog("🔍 📦 Raw response: \(redactedBodyPreview(data))")

                }
                
                switch httpResponse.statusCode {
                case 200...299:
                    return data
                case 401:
                    let errorBody = String(data: data, encoding: .utf8) ?? "No error body"
                    debugLog("❌ 🔒 401 Unauthorized: \(errorBody)")
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
                        debugLog("📦 [DEBUG] JSON Payload being sent:")
                        debugLog("📦 [DEBUG] \(jsonString)")
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
            debugLog("🔍 🚀 [CCHTTPClient] \(method.rawValue) \(url)")
        }
        
        // Perform request
        return urlSession.dataTaskPublisher(for: request)
            .tryMap { data, response in
                guard let httpResponse = response as? HTTPURLResponse else {
                    debugLog("❌ Invalid response type")
                    throw CCError.invalidResponse
                }
                
                // Log response details (missing from original requestRawWithBody implementation)
                debugLog("🔍 📡 HTTP Response [statusCode=\(httpResponse.statusCode), url=\(httpResponse.url?.absoluteString ?? "unknown"), headers=\(httpResponse.allHeaderFields.description)]")
                
                // Log raw response data (secrets redacted)
                debugLog("🔍 📦 Raw response data [size=\(data.count) bytes, preview=\(redactedBodyPreview(data))]")
                
                switch httpResponse.statusCode {
                case 200...299:
                    return data
                case 401:
                    debugLog("❌ 🔒 Unauthorized - OAuth token may be invalid")
                    throw CCError.authenticationFailed
                case 404:
                    debugLog("❌ 🔍 Not Found - Resource doesn't exist")
                    debugLog("❌ ❌ 404 ERROR DETAILS [url=\(httpResponse.url?.absoluteString ?? "unknown"), method=\(method.rawValue), endpoint=\(endpoint), fullURL=\(url.absoluteString)]")
                    let errorBody = String(data: data, encoding: .utf8) ?? "No error body"
                    debugLog("❌ ❌ 404 ERROR BODY: \(errorBody)")
                    throw CCError.resourceNotFound
                default:
                    let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                    debugLog("❌ HTTP Error \(httpResponse.statusCode) [endpoint=\(endpoint), errorBody=\(errorMessage)]")
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
                        debugLog("📦 [DEBUG] JSON Payload being sent:")
                        debugLog("📦 [DEBUG] \(jsonString)")
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
            debugLog("🔍 🚀 [CCHTTPClient] \(method.rawValue) \(requestURLString)")
            if let authHeader = request.value(forHTTPHeaderField: "Authorization") {
                debugLog("🔍 🔐 [CCHTTPClient] OAuth: \(String(authHeader.prefix(50)))...")
            }
        }
        
        // Perform request
        return urlSession.dataTaskPublisher(for: request)
            .tryMap { [weak self] data, response in
                guard let httpResponse = response as? HTTPURLResponse else {
                    debugLog("❌ Invalid response type")
                    throw CCError.invalidResponse
                }
                
                // Log metrics response details
                if endpoint.contains("metrics") || endpoint.contains("stats") {
                    let responseBody = String(data: data, encoding: .utf8) ?? "Unable to decode response"
                    debugLog("🔍 [CleverMetrics] HTTP Response [statusCode=\(httpResponse.statusCode), endpoint=\(endpoint), responseBody=\(responseBody.prefix(500).description), headers=\(httpResponse.allHeaderFields.description)]")
                }
                
                // Log response details
                debugLog("🔍 📡 HTTP Response [statusCode=\(httpResponse.statusCode), url=\(httpResponse.url?.absoluteString ?? "unknown"), headers=\(httpResponse.allHeaderFields.description)]")
                
                // Check status code
                switch httpResponse.statusCode {
                case 200...299:
                    // Success - decode response
                    debugLog("🔍 📦 Raw response data [size=\(data.count) bytes, preview=\(redactedBodyPreview(data))]")

                    do {
                        let decoder = JSONDecoder()
                        decoder.dateDecodingStrategy = .iso8601
                        let decodedResponse = try decoder.decode(T.self, from: data)
                        return decodedResponse
                    } catch {
                        debugLog("❌ ❌ JSON Decoding Error [error=\(error.localizedDescription), type=\(T.self), size=\(data.count) bytes, rawData=\(redactedBodyPreview(data)), decodingError=\(error)]")
                        throw CCError.parsingError(error)
                    }
                    
                case 401:
                    debugLog("❌ 🔒 Unauthorized - OAuth token may be invalid")
                    throw CCError.authenticationFailed
                    
                case 404:
                    debugLog("❌ 🔍 Not Found - Resource doesn't exist")
                    // Add detailed error logging for debugging
                    debugLog("❌ ❌ 404 ERROR DETAILS [url=\(httpResponse.url?.absoluteString ?? "unknown"), method=\(method.rawValue), endpoint=\(endpoint), fullURL=\(url.absoluteString)]")
                    let errorBody = String(data: data, encoding: .utf8) ?? "No error body"
                    debugLog("❌ ❌ 404 ERROR BODY: \(errorBody)")
                    throw CCError.resourceNotFound
                    
                default:
                    let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                    debugLog("❌ [CleverMetrics] HTTP Error \(httpResponse.statusCode) [endpoint=\(endpoint), errorBody=\(errorMessage)]")
                    
                    // Enhanced logging for application creation errors
                    if endpoint.contains("applications") && method.rawValue == "POST" {
                        debugLog("❌ [APPLICATION CREATION ERROR] Status: \(httpResponse.statusCode)")
                        debugLog("❌ [APPLICATION CREATION ERROR] Endpoint: \(endpoint)")
                        debugLog("❌ [APPLICATION CREATION ERROR] Error Body: \(errorMessage)")
                        debugLog("❌ [APPLICATION CREATION ERROR] Headers: \(httpResponse.allHeaderFields)")
                    }
                    
                    throw CCError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
                }
            }
            .receive(on: DispatchQueue.main)
            .mapError { error in
                if let ccError = error as? CCError {
                    return ccError
                } else if error is DecodingError {
                    debugLog("❌ ❌ DECODING ERROR: \(error.localizedDescription)")
                    if let decodingError = error as? DecodingError {
                        debugLog("❌ ❌ DECODING ERROR DETAILS: \(String(describing: decodingError))")
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
            debugLog("🔍 🚀 [CCHTTPClient] \(method.rawValue) \(url) with Bearer token")
        }
        
        // Perform request
        return urlSession.dataTaskPublisher(for: request)
            .tryMap { [weak self] data, response in
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw CCError.invalidResponse
                }
                
                // Log response for debugging
                debugLog("🔍 📡 Bearer Token Response [statusCode=\(httpResponse.statusCode), endpoint=\(endpoint), url=\(url.absoluteString)]")
                
                switch httpResponse.statusCode {
                case 200...299:
                    // Success - decode response
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    let decodedResponse = try decoder.decode(T.self, from: data)
                    return decodedResponse
                    
                case 401:
                    debugLog("❌ 🔒 Unauthorized - Bearer token may be invalid")
                    throw CCError.authenticationFailed
                    
                case 404:
                    throw CCError.resourceNotFound
                    
                default:
                    let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                    debugLog("❌ HTTP Error \(httpResponse.statusCode) [endpoint=\(endpoint), errorBody=\(errorMessage)]")
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
            debugLog("🔍 [CCHTTPClient] Building URL [baseURL=\(baseURL), endpoint=\(endpoint), cleanEndpoint=\(cleanEndpoint), finalURL=\(urlString), apiVersion=\(apiVersion == .v2 ? "v2" : "v4")]")
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
            debugLog("🔍 📡 [CCHTTPClient] Response: \(httpResponse.statusCode) (\(data.count) bytes)")
            
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

        debugLog("🌐 [CCHTTPClient] SSE GET \(url.absoluteString)")

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

    /// Open a persistent SSE connection and push each parsed event as it arrives.
    ///
    /// Unlike `getSSEData`, this does not accumulate or close after a heartbeat — the data task
    /// stays alive until the subscriber cancels the returned publisher or the server closes the
    /// connection. Each event is delivered as a `CCSSEEvent` on the main queue.
    public func streamSSE(
        _ endpoint: String,
        apiVersion: APIVersion = .v4
    ) -> AnyPublisher<CCSSEEvent, CCError> {
        guard let url = buildURL(endpoint: endpoint, apiVersion: apiVersion) else {
            return Fail(error: CCError.invalidURL).eraseToAnyPublisher()
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = TimeInterval.infinity

        do {
            request = try oauthSigner.signRequest(request)
        } catch {
            return Fail(error: CCError.authenticationFailed).eraseToAnyPublisher()
        }

        debugLog("🌐 [CCHTTPClient] SSE stream GET \(url.absoluteString)")

        let subject = PassthroughSubject<CCSSEEvent, CCError>()
        let collector = SSEStreamCollector(subject: subject)
        let session = URLSession(configuration: .default, delegate: collector, delegateQueue: nil)
        let task = session.dataTask(with: request)
        collector.session = session
        collector.task = task
        task.resume()

        return subject
            .handleEvents(receiveCancel: {
                debugLog("🧹 [CCHTTPClient] SSE stream cancelled by subscriber")
                collector.cancel()
            })
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

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse {
            debugLog("🌐 [SSE] HTTP \(http.statusCode) for \(http.url?.absoluteString ?? "?")")
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        accumulatedData.append(data)

        // Check if we received log events followed by a heartbeat
        if let text = String(data: data, encoding: .utf8) {
            if text.contains("APPLICATION_LOG") || text.contains("RESOURCE_LOG") {
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
            debugLog("🌐 [SSE] task completed with \(accumulatedData.count) bytes accumulated (error=\(error?.localizedDescription ?? "nil"))")
            promise(.success(accumulatedData))
        } else if let error = error {
            debugLog("❌ [SSE] task failed: \(error.localizedDescription)")
            promise(.failure(CCError.networkError(error)))
        } else {
            debugLog("⚠️ [SSE] task completed with 0 bytes and no error")
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

// MARK: - SSE Stream Collector

/// A single SSE event, parsed from a `data:` / `event:` / `id:` block.
public struct CCSSEEvent: Sendable {
    public let name: String   // Value of the `event:` line, or "message" by default
    public let data: String   // Concatenated `data:` lines (sans trailing newline)
    public let id: String?    // Optional `id:` line value
}

/// Delegate that parses an SSE stream chunk-by-chunk and pushes each complete event to a Combine
/// subject. Unlike `SSEDataCollector`, it does not accumulate the full body and does not close
/// after a heartbeat — the connection stays open until cancelled or the server hangs up.
private final class SSEStreamCollector: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let subject: PassthroughSubject<CCSSEEvent, CCError>
    private var buffer = ""
    private let lock = NSLock()
    private var finished = false
    var session: URLSession?
    var task: URLSessionTask?

    init(subject: PassthroughSubject<CCSSEEvent, CCError>) {
        self.subject = subject
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse {
            debugLog("🌐 [SSE-stream] HTTP \(http.statusCode) for \(http.url?.absoluteString ?? "?")")
            if http.statusCode >= 400 {
                completeWithError(CCError.httpError(statusCode: http.statusCode, message: HTTPURLResponse.localizedString(forStatusCode: http.statusCode)))
                completionHandler(.cancel)
                return
            }
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        buffer += chunk
        // Each SSE event is terminated by a blank line (\n\n). Pull every complete event off the
        // front of the buffer and emit it; keep the partial trailing fragment for the next chunk.
        while let separator = buffer.range(of: "\n\n") {
            let rawEvent = String(buffer[..<separator.lowerBound])
            buffer.removeSubrange(buffer.startIndex..<separator.upperBound)
            if let event = Self.parseEvent(rawEvent) {
                subject.send(event)
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        finished = true
        self.session?.invalidateAndCancel()
        if let nsErr = error as NSError?, nsErr.domain == NSURLErrorDomain && nsErr.code == NSURLErrorCancelled {
            debugLog("ℹ️ [SSE-stream] task cancelled")
            subject.send(completion: .finished)
            return
        }
        if let error {
            debugLog("❌ [SSE-stream] task failed: \(error.localizedDescription)")
            subject.send(completion: .failure(.networkError(error)))
        } else {
            debugLog("ℹ️ [SSE-stream] task completed normally (server closed)")
            subject.send(completion: .finished)
        }
    }

    func cancel() {
        lock.lock()
        let alreadyFinished = finished
        finished = true
        lock.unlock()
        guard !alreadyFinished else { return }
        task?.cancel()
        session?.invalidateAndCancel()
    }

    private func completeWithError(_ error: CCError) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        lock.unlock()
        session?.invalidateAndCancel()
        subject.send(completion: .failure(error))
    }

    /// Parse a raw SSE event block (lines separated by `\n`) into a `CCSSEEvent`.
    private static func parseEvent(_ raw: String) -> CCSSEEvent? {
        var name = "message"
        var dataParts: [String] = []
        var id: String?
        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.isEmpty || line.hasPrefix(":") { continue } // comments and blanks
            guard let colon = line.firstIndex(of: ":") else { continue }
            let field = String(line[..<colon])
            var value = String(line[line.index(after: colon)...])
            if value.hasPrefix(" ") { value.removeFirst() }
            switch field {
            case "event": name = value
            case "data": dataParts.append(value)
            case "id": id = value
            default: break
            }
        }
        guard !dataParts.isEmpty else { return nil }
        return CCSSEEvent(name: name, data: dataParts.joined(separator: "\n"), id: id)
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

// MARK: - Log redaction

/// Best-effort masking of secrets before a response/request body is logged, so that flipping
/// `kForceConsoleLogs` for a diagnostic build can't dump credentials (OAuth tokens, add-on
/// connection strings in env vars, etc.). Only ever runs behind `debugLog` (no-op in Release).
fileprivate func redactSecretsForLog(_ text: String) -> String {
    var result = text
    // 1. Mask the value of any JSON key whose name looks sensitive: "...token...": "value" -> "***".
    let sensitiveKey = "(\"[^\"]*(?:token|secret|password|passwd|authorization|api[_-]?key|access[_-]?key|private[_-]?key)[^\"]*\"\\s*:\\s*\")[^\"]*(\")"
    result = result.replacingOccurrences(
        of: sensitiveKey,
        with: "$1***$2",
        options: [.regularExpression, .caseInsensitive]
    )
    // 2. Mask credentials embedded in connection-string URIs: scheme://user:pass@host -> scheme://***:***@host.
    let uriCreds = "([a-zA-Z][a-zA-Z0-9+.-]*://)[^/@:\\s\"]+:[^/@\\s\"]+@"
    result = result.replacingOccurrences(
        of: uriCreds,
        with: "$1***:***@",
        options: [.regularExpression]
    )
    // 3. Mask INI/key=value secret assignments (e.g. a WireGuard .conf): "PrivateKey = <base64>" -> "PrivateKey = ***".
    let iniSecret = "(?im)^(\\s*(?:private[_-]?key|preshared[_-]?key|password|secret|token)\\s*=\\s*).+$"
    result = result.replacingOccurrences(
        of: iniSecret,
        with: "$1***",
        options: [.regularExpression]
    )
    return result
}

/// Redacted, size-capped preview of a body for logging.
fileprivate func redactedBodyPreview(_ data: Data, limit: Int = 500) -> String {
    guard let text = String(data: data, encoding: .utf8) else { return "<\(data.count) bytes, non-UTF8>" }
    return String(redactSecretsForLog(text).prefix(limit))
}

 