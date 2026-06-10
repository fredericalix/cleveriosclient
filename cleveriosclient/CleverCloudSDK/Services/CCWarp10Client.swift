import Foundation
import Combine

/// Client for interacting with Clever Cloud's Warp10 time series database
/// Based on official documentation: https://www.clever-cloud.com/developers/doc/metrics/warp10/
public class CCWarp10Client: ObservableObject {
    
    // MARK: - Properties
    
    private let httpClient: CCHTTPClient
    
    /// Warp10 endpoint as per official documentation
    private let warp10Endpoint = "https://c2-warp10-clevercloud-customers.services.clever-cloud.com/api/v0"
    
    // Token cache to avoid fetching tokens too frequently (tokens are valid for 5 days)
    private var tokenCache: [String: (token: String, expiry: Date)] = [:]
    
    // MARK: - Initialization
    
    public init(httpClient: CCHTTPClient) {
        self.httpClient = httpClient
    }
    
    // MARK: - Token Management
    
    /// Get Warp10 read token for an organization using v2 API
    /// Tokens are valid for 5 days according to documentation
    /// - Parameter organizationId: The organization ID
    /// - Returns: Publisher with Warp10 read token
    public func getWarp10Token(organizationId: String) -> AnyPublisher<String, CCError> {
        
        // Check cache first (tokens valid for 5 days)
        if let cached = tokenCache[organizationId],
           cached.expiry > Date() {
            debugLog("🎫 [CCWarp10Client] Using cached token for org: \(organizationId)")
            return Just(cached.token)
                .setFailureType(to: CCError.self)
                .eraseToAnyPublisher()
        }
        
        debugLog("🎫 [CCWarp10Client] Fetching new Warp10 token for org: \(organizationId)")
        debugLog("🔍 [CCWarp10Client] Using endpoint discovered in SDK JS: /v2/metrics/read/{orgaId}")
        
        // Use existing v2 API endpoint for metrics token (same as JS SDK)
        // Note: Don't include /v2 prefix since apiVersion: .v2 adds it automatically
        let endpoint = "/metrics/read/\(organizationId)"
        
        // The endpoint returns raw token string, not JSON
        return httpClient.getRawString(endpoint, apiVersion: .v2)
            .map { (tokenString: String) in
                // Clean up the token (remove any whitespace/newlines)
                let cleanToken = tokenString.trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Cache token for ~4.5 days (a bit less than 5 days for safety)
                let expiryDate = Date().addingTimeInterval(4.5 * 24 * 60 * 60)
                self.tokenCache[organizationId] = (token: cleanToken, expiry: expiryDate)
                
                debugLog("✅ [CCWarp10Client] Cached new Warp10 token for org: \(organizationId) (\(cleanToken.prefix(8))...[\(cleanToken.count) chars])")
                return cleanToken
            }
            .handleEvents(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        debugLog("❌ [CCWarp10Client] Failed to get Warp10 token from \(endpoint): \(error)")
                    }
                }
            )
            .eraseToAnyPublisher()
    }
    
    /// Drop all cached Warp10 tokens (called on logout so a ~5-day token doesn't outlive the session).
    public func clearTokenCache() {
        tokenCache.removeAll()
        debugLog("ℹ️ 🧹 [CCWarp10Client] Token cache cleared")
    }

    // MARK: - WarpScript Execution

    /// Execute a WarpScript query on Warp10
    /// - Parameters:
    ///   - script: The WarpScript to execute
    ///   - organizationId: When set, an auth failure (401/403) evicts this org's cached token so
    ///     the next query re-fetches a fresh one instead of replaying a dead token for 4.5 days.
    /// - Returns: Publisher with raw Warp10 response data
    public func executeWarpScript(_ script: String, organizationId: String? = nil) -> AnyPublisher<Data, CCError> {

        debugLog("📝 [CCWarp10Client] Executing WarpScript (\(script.count) chars)")

        let url = URL(string: "\(warp10Endpoint)/exec")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/text", forHTTPHeaderField: "Content-Type")
        request.httpBody = script.data(using: .utf8)

        return URLSession.shared.dataTaskPublisher(for: request)
            .tryMap { [weak self] data, response in
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw CCError.invalidResponse
                }
                guard (200...299).contains(httpResponse.statusCode) else {
                    // A Warp10 error body would otherwise parse as "no data points" and render as
                    // silently empty charts.
                    if httpResponse.statusCode == 401 || httpResponse.statusCode == 403,
                       let organizationId {
                        self?.tokenCache[organizationId] = nil
                        debugLog("⚠️ [CCWarp10Client] Evicted cached token for org \(organizationId) after \(httpResponse.statusCode)")
                    }
                    throw CCError.httpError(
                        statusCode: httpResponse.statusCode,
                        message: String(data: data.prefix(200), encoding: .utf8)
                    )
                }
                return data
            }
            .mapError { error in
                (error as? CCError) ?? CCError.networkError(error)
            }
            .handleEvents(
                receiveOutput: { data in
                    debugLog("✅ [CCWarp10Client] WarpScript executed successfully, received \(data.count) bytes")
                },
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        debugLog("❌ [CCWarp10Client] WarpScript execution failed: \(error)")
                    }
                }
            )
            .eraseToAnyPublisher()
    }
    
    // MARK: - Application Metrics Queries
    
    /// Get CPU usage metrics for an application using WarpScript
    /// - Parameters:
    ///   - applicationId: The application ID
    ///   - organizationId: The organization ID
    ///   - span: Time span (e.g., "1 h", "24 h", "7 d")
    /// - Returns: Publisher with CPU metric data points
    public func getCPUMetrics(
        applicationId: String,
        organizationId: String,
        span: String = "1 h"
    ) -> AnyPublisher<[CCApplicationMetricPoint], CCError> {
        
        return getWarp10Token(organizationId: organizationId)
            .flatMap { token in
                let warpScript = self.createCPUWarpScript(
                    token: token,
                    applicationId: applicationId,
                    span: span
                )
                
                return self.executeWarpScript(warpScript, organizationId: organizationId)
                    .tryMap { data in
                        return try self.parseWarp10Response(
                            data: data,
                            metricType: .cpuUsage
                        )
                    }
                    .mapError { error in
                        if let ccError = error as? CCError {
                            return ccError
                        }
                        return CCError.parsingError(error)
                    }
            }
            .eraseToAnyPublisher()
    }
    
    /// Get Memory usage metrics for an application using WarpScript
    /// - Parameters:
    ///   - applicationId: The application ID
    ///   - organizationId: The organization ID
    ///   - span: Time span (e.g., "1 h", "24 h", "7 d")
    /// - Returns: Publisher with Memory metric data points
    public func getMemoryMetrics(
        applicationId: String,
        organizationId: String,
        span: String = "1 h"
    ) -> AnyPublisher<[CCApplicationMetricPoint], CCError> {
        
        return getWarp10Token(organizationId: organizationId)
            .flatMap { token in
                let warpScript = self.createMemoryWarpScript(
                    token: token,
                    applicationId: applicationId,
                    span: span
                )
                
                return self.executeWarpScript(warpScript, organizationId: organizationId)
                    .tryMap { data in
                        return try self.parseWarp10Response(
                            data: data,
                            metricType: .memoryUsage
                        )
                    }
                    .mapError { error in
                        if let ccError = error as? CCError {
                            return ccError
                        }
                        return CCError.parsingError(error)
                    }
            }
            .eraseToAnyPublisher()
    }
    
    /// Get Network I/O metrics for an application using WarpScript
    /// - Parameters:
    ///   - applicationId: The application ID
    ///   - organizationId: The organization ID
    ///   - span: Time span (e.g., "1 h", "24 h", "7 d")
    /// - Returns: Publisher with Network metric data points (both in and out)
    public func getNetworkMetrics(
        applicationId: String,
        organizationId: String,
        span: String = "1 h"
    ) -> AnyPublisher<[CCApplicationMetricPoint], CCError> {
        
        return getWarp10Token(organizationId: organizationId)
            .flatMap { token in
                let warpScript = self.createNetworkWarpScript(
                    token: token,
                    applicationId: applicationId,
                    span: span
                )
                
                return self.executeWarpScript(warpScript, organizationId: organizationId)
                    .tryMap { data in
                        return try self.parseWarp10NetworkResponse(data: data)
                    }
                    .mapError { error in
                        if let ccError = error as? CCError {
                            return ccError
                        }
                        return CCError.parsingError(error)
                    }
            }
            .eraseToAnyPublisher()
    }
    
    // MARK: - WarpScript Generation
    
    /// Create WarpScript for CPU metrics
    /// Real CPU metrics are: cpu.usage_user, cpu.usage_system, cpu.usage_idle, etc.
    private func createCPUWarpScript(token: String, applicationId: String, span: String) -> String {
        debugLog("🧪 [CCWarp10Client] Creating CPU WarpScript for app: \(applicationId), span: \(span)")
        return """
        [ '\(token)' 'cpu.usage_user' { 'app_id' '\(applicationId)' } NOW \(span) ] FETCH
        """
    }
    
    /// Create WarpScript for Memory metrics  
    /// Real memory metrics may be different - we'll need to check what's available
    private func createMemoryWarpScript(token: String, applicationId: String, span: String) -> String {
        debugLog("🧪 [CCWarp10Client] Creating Memory WarpScript for app: \(applicationId), span: \(span)")
        return """
        [ '\(token)' 'mem.used_percent' { 'app_id' '\(applicationId)' } NOW \(span) ] FETCH
        """
    }
    
    /// Create WarpScript for Network metrics (both in and out)
    /// Real network metrics may be different - we'll test what works
    private func createNetworkWarpScript(token: String, applicationId: String, span: String) -> String {
        debugLog("🧪 [CCWarp10Client] Creating Network WarpScript for app: \(applicationId), span: \(span)")
        return """
        [ '\(token)' 'net.bytes_recv' { 'app_id' '\(applicationId)' } NOW \(span) ] FETCH
        [ '\(token)' 'net.bytes_sent' { 'app_id' '\(applicationId)' } NOW \(span) ] FETCH
        """
    }
    
    // MARK: - Response Parsing
    
    /// Parse Warp10 GeoTime Series response into metric points
    /// Warp10 returns GTS format: [[{"c":"metric","l":{labels},"v":[[timestamp,value],...]}]]
    private func parseWarp10Response(
        data: Data,
        metricType: MetricType
    ) throws -> [CCApplicationMetricPoint] {
        
        debugLog("🔍 [CCWarp10Client] Parsing Warp10 response for metric: \(metricType.rawValue)")
        
        // Parse JSON response - Warp10 format: [[{"c":...,"l":...,"v":...}]]
        guard let outerArray = try JSONSerialization.jsonObject(with: data) as? [Any],
              let gtsArray = outerArray.first as? [Any] else {
            throw CCError.parsingError(NSError(domain: "CCWarp10Client", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid Warp10 response format"]))
        }
        
        var points: [CCApplicationMetricPoint] = []
        
        // Process each GTS (GeoTime Series) object
        for gtsElement in gtsArray {
            guard let gts = gtsElement as? [String: Any],
                  let className = gts["c"] as? String,
                  let values = gts["v"] as? [[Any]] else {
                debugLog("⚠️ [CCWarp10Client] Skipping malformed GTS")
                continue
            }
            
            debugLog("✅ [CCWarp10Client] Processing GTS '\(className)' with \(values.count) data points")
            
            // Parse value arrays: [[timestamp, value], ...]
            for valueArray in values {
                guard valueArray.count >= 2,
                      let timestamp = valueArray[0] as? Double,
                      let value = valueArray[1] as? Double else {
                    continue
                }
                
                // Convert microsecond timestamp to Date
                let date = Date(timeIntervalSince1970: timestamp / 1_000_000)
                
                let point = CCApplicationMetricPoint(
                    timestamp: date,
                    value: value,
                    metricType: metricType.rawValue,
                    unit: metricType.unit
                )
                
                points.append(point)
            }
        }
        
        // Sort by timestamp (oldest first)
        points.sort { $0.timestamp < $1.timestamp }
        
        debugLog("✅ [CCWarp10Client] Successfully parsed \(points.count) data points for \(metricType.rawValue)")
        return points
    }
    
    /// Parse Network metrics response (handles both in and out)
    /// Network query returns format: [[{"c":"net.bytes_recv",...},{"c":"net.bytes_sent",...}]]
    private func parseWarp10NetworkResponse(data: Data) throws -> [CCApplicationMetricPoint] {
        
        debugLog("🔍 [CCWarp10Client] Parsing Warp10 network response")
        
        // Parse JSON response - same format as other metrics
        guard let outerArray = try JSONSerialization.jsonObject(with: data) as? [Any],
              let gtsArray = outerArray.first as? [Any] else {
            throw CCError.parsingError(NSError(domain: "CCWarp10Client", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid Warp10 network response format"]))
        }
        
        var points: [CCApplicationMetricPoint] = []
        
        // Process each GTS - we expect both net.bytes_recv and net.bytes_sent
        for gtsElement in gtsArray {
            guard let gts = gtsElement as? [String: Any],
                  let className = gts["c"] as? String,
                  let values = gts["v"] as? [[Any]] else {
                debugLog("⚠️ [CCWarp10Client] Skipping malformed network GTS")
                continue
            }
            
            // Determine metric type based on class name
            let metricType: String
            let unit: String
            
            if className.contains("recv") {
                metricType = "net.in.bytes"
                unit = "bytes/s"
            } else if className.contains("sent") {
                metricType = "net.out.bytes" 
                unit = "bytes/s"
            } else {
                debugLog("⚠️ [CCWarp10Client] Unknown network metric: \(className)")
                continue
            }
            
            debugLog("✅ [CCWarp10Client] Processing network GTS '\(className)' -> \(metricType) with \(values.count) data points")
            
            // Parse value arrays: [[timestamp, value], ...]
            for valueArray in values {
                guard valueArray.count >= 2,
                      let timestamp = valueArray[0] as? Double,
                      let value = valueArray[1] as? Double else {
                    continue
                }
                
                // Convert microsecond timestamp to Date
                let date = Date(timeIntervalSince1970: timestamp / 1_000_000)
                
                let point = CCApplicationMetricPoint(
                    timestamp: date,
                    value: value,
                    metricType: metricType,
                    unit: unit
                )
                
                points.append(point)
            }
        }
        
        // Sort by timestamp
        points.sort { $0.timestamp < $1.timestamp }
        
        debugLog("✅ [CCWarp10Client] Successfully parsed \(points.count) network data points")
        return points
    }
}

// MARK: - Supporting Models

/// Response model for Warp10 token API
public struct CCWarp10TokenResponse: Codable {
    public let token: String
    
    public init(token: String) {
        self.token = token
    }
} 