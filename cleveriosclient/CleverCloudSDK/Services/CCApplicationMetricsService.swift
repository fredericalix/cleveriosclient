import Foundation
import Combine

/// Service for managing Clever Cloud application metrics and monitoring
/// 
/// ## Implementation Details
/// This service now uses Warp10 time series database directly for real metrics data,
/// following the official Clever Cloud documentation at:
/// https://www.clever-cloud.com/developers/doc/metrics/warp10/
/// 
/// ## Supported Metrics
/// - CPU Usage: `cpu.percent` - Percentage of CPU utilization
/// - Memory Usage: `mem.available` - Available memory in bytes  
/// - Network In: `net.in.bytes` - Incoming network traffic in bytes/second
/// - Network Out: `net.out.bytes` - Outgoing network traffic in bytes/second
/// 
/// ## Authentication Flow
/// 1. Uses existing v2 API `/metrics/read/{orgaId}` to obtain Warp10 read tokens
/// 2. Tokens are cached for ~4.5 days (valid for 5 days per documentation)
/// 3. Executes WarpScript queries on Warp10 endpoint directly
/// 4. Fallback to mock data if Warp10 requests fail
/// 
/// ## Period Conversion
/// Converts ISO 8601 durations (PT1H, P7D, etc.) to Warp10 format (1 h, 7 d, etc.)
/// 
/// ## Data Format
/// Warp10 returns GeoTime Series in format: [timestamp, longitude, latitude, altitude, value]
/// We extract timestamp (microseconds) and value for our metric points.
public class CCApplicationMetricsService: ObservableObject {
    
    // MARK: - Properties
    
    private let httpClient: CCHTTPClient
    private let warp10Client: CCWarp10Client
    
    // MARK: - Initialization
    
    public init(httpClient: CCHTTPClient) {
        self.httpClient = httpClient
        self.warp10Client = CCWarp10Client(httpClient: httpClient)
    }
    
    // MARK: - Application Metrics
    
    /// Get comprehensive metrics for an application
    /// - Parameters:
    ///   - applicationId: The application ID
    ///   - organizationId: The organization ID (required for metrics)
    ///   - period: Time period for metrics (e.g., "PT1H", "PT24H", "P7D", "P30D")
    /// - Returns: Publisher with application metrics
    public func getApplicationMetrics(
        applicationId: String,
        organizationId: String,
        period: String = "PT1H"
    ) -> AnyPublisher<CCApplicationMetrics, CCError> {
        
        print("📊 [CCApplicationMetricsService] Getting metrics for application: \(applicationId)")
        print("📊 [CCApplicationMetricsService] Organization: \(organizationId), Period: \(period)")
        print("📊 [CCApplicationMetricsService] ✅ FIXED: Using OAuth 1.0a directly on v4 API (same as official JS SDK)")
        
        // Build endpoint with query parameters - Use OAuth 1.0a directly like official JS SDK
        let endpoint = "/stats/organisations/\(organizationId)/resources/\(applicationId)/metrics"
        let queryItems = [
            URLQueryItem(name: "interval", value: "PT5M"),
            URLQueryItem(name: "span", value: period)
        ]
        var urlComponents = URLComponents()
        urlComponents.queryItems = queryItems
        let queryString = urlComponents.query ?? ""
        let fullEndpoint = queryString.isEmpty ? endpoint : "\(endpoint)?\(queryString)"
        
        print("📊 [CCApplicationMetricsService] OAuth 1.0a request to: \(fullEndpoint)")
        
        // Use OAuth 1.0a directly (same as JS SDK) instead of Bearer token
        return httpClient.getRawData(fullEndpoint, apiVersion: .v4)
        .tryMap { data in
            RemoteLogger.shared.debug("[CleverMetrics] getApplicationMetrics response", metadata: [
                "dataSize": "\(data.count) bytes",
                "endpoint": fullEndpoint
            ])
            
            // Log the raw response to understand the format
            if let jsonString = String(data: data, encoding: .utf8) {
                RemoteLogger.shared.debug("[CleverMetrics] Raw metrics API response", metadata: [
                    "response": jsonString.prefix(1000).description
                ])
            }
            
            // Parse the actual metrics response format
            // The API likely returns time series data, not a single metrics object
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                RemoteLogger.shared.debug("[CleverMetrics] Successfully parsed JSON", metadata: [
                    "keys": json.keys.joined(separator: ", ")
                ])
                
                // Create metrics from the actual response
                return self.parseMetricsResponse(json: json, applicationId: applicationId)
            } else {
                RemoteLogger.shared.error("[CleverMetrics] Invalid JSON format", metadata: [
                    "error": "Response is not a dictionary"
                ])
                throw CCError.parsingError(NSError(domain: "CCApplicationMetricsService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid metrics response format"]))
            }
        }
        .mapError { error in
            if let ccError = error as? CCError {
                return ccError
            }
            return CCError.parsingError(error)
        }
        .handleEvents(
            receiveOutput: { metrics in
                print("✅ [CCApplicationMetricsService] SUCCESS! Received comprehensive metrics with OAuth 1.0a")
                print("📊 [CCApplicationMetricsService] CPU: \(metrics.cpuUsageFormatted), Memory: \(metrics.memoryUsageFormatted)")
            },
            receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    print("❌ [CCApplicationMetricsService] OAuth 1.0a request failed: \(error)")
                }
            }
        )
        .catch { error -> AnyPublisher<CCApplicationMetrics, CCError> in
            // Return error instead of mock data
            print("⚠️ [CCApplicationMetricsService] OAuth 1.0a request failed: \(error)")
            return Fail(error: error)
                .eraseToAnyPublisher()
        }
        .eraseToAnyPublisher()
    }
    
    /// Get time series data for specific metric using Warp10
    /// - Parameters:
    ///   - applicationId: The application ID
    ///   - organizationId: The organization ID (required for metrics)
    ///   - metric: Metric type to retrieve
    ///   - interval: Data point interval (default: "PT5M")
    ///   - span: Time span (default: "PT1H")
    /// - Returns: Publisher with time series data points
    public func getApplicationTimeSeries(
        applicationId: String,
        organizationId: String,
        metric: MetricType,
        interval: String = "PT5M",
        span: String = "PT1H"
    ) -> AnyPublisher<[CCApplicationMetricPoint], CCError> {
        
        print("📈 [CCApplicationMetricsService] Getting time series for metric '\(metric.rawValue)'")
        print("📈 [CCApplicationMetricsService] App: \(applicationId), Interval: \(interval), Span: \(span)")
        print("📈 [CCApplicationMetricsService] ✅ Using v4 API directly like getApplicationMetrics")
        
        // Build endpoint with query parameters - Use same endpoint as getApplicationMetrics
        let endpoint = "/stats/organisations/\(organizationId)/resources/\(applicationId)/metrics"
        
        // For network metrics, try without "only" parameter to see what metrics are available
        var queryItems: [URLQueryItem]
        if metric == .networkIn || metric == .networkOut {
            // Don't use "only" for network metrics - we'll filter client-side
            queryItems = [
                URLQueryItem(name: "interval", value: interval),
                URLQueryItem(name: "span", value: span)
            ]
        } else {
            queryItems = [
                URLQueryItem(name: "interval", value: interval),
                URLQueryItem(name: "span", value: span),
                URLQueryItem(name: "only", value: metric.rawValue) // Filter to specific metric
            ]
        }
        var urlComponents = URLComponents()
        urlComponents.queryItems = queryItems
        let queryString = urlComponents.query ?? ""
        let fullEndpoint = queryString.isEmpty ? endpoint : "\(endpoint)?\(queryString)"
        
        print("📈 [CCApplicationMetricsService] OAuth 1.0a request to: \(fullEndpoint)")
        
        return httpClient.getRawData(fullEndpoint, apiVersion: .v4)
            .tryMap { data in
                RemoteLogger.shared.debug("[CleverMetrics] getApplicationTimeSeries response", metadata: [
                    "dataSize": "\(data.count) bytes",
                    "endpoint": fullEndpoint,
                    "metric": metric.rawValue
                ])
                
                // Log the raw response to understand the format
                if let jsonString = String(data: data, encoding: .utf8) {
                    RemoteLogger.shared.debug("[CleverMetrics] Raw time series response", metadata: [
                        "metric": metric.rawValue,
                        "response": jsonString.prefix(1000).description
                    ])
                }
                
                // Parse the time series response
                return try self.parseTimeSeriesResponse(data: data, metricType: metric)
            }
            .mapError { error in
                if let ccError = error as? CCError {
                    return ccError
                }
                return CCError.parsingError(error)
            }
            .handleEvents(
                receiveOutput: { dataPoints in
                    print("✅ [CCApplicationMetricsService] SUCCESS! Received \(dataPoints.count) data points for metric \(metric.rawValue) from Warp10")
                },
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("❌ [CCApplicationMetricsService] Warp10 request failed: \(error)")
                    }
                }
            )
            .catch { error -> AnyPublisher<[CCApplicationMetricPoint], CCError> in
                // Return empty array instead of mock data
                print("⚠️ [CCApplicationMetricsService] Time series request failed: \(error)")
                return Just([])
                    .setFailureType(to: CCError.self)
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }
    
    /// Start real-time metrics polling
    /// - Parameters:
    ///   - applicationId: The application ID
    ///   - organizationId: The organization ID
    ///   - interval: Polling interval in seconds (default: 30)
    /// - Returns: Publisher that emits metrics at regular intervals
    public func startRealtimeMetrics(
        applicationId: String,
        organizationId: String,
        interval: TimeInterval = 30.0
    ) -> AnyPublisher<CCApplicationMetrics, CCError> {
        
        print("⏱️ [CCApplicationMetricsService] Starting real-time metrics polling (interval: \(interval)s)")
        
        return Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .prepend(Date()) // Emit immediately
            .flatMap { _ in
                self.getApplicationMetrics(
                    applicationId: applicationId,
                    organizationId: organizationId,
                    period: "PT1H" // Use shorter period for real-time
                )
            }
            .removeDuplicates { lhs, rhs in
                // Only emit if metrics actually changed
                return lhs.timestamp == rhs.timestamp &&
                       lhs.cpuUsage == rhs.cpuUsage &&
                       lhs.memoryUsage == rhs.memoryUsage
            }
            .eraseToAnyPublisher()
    }
    
    // MARK: - Warp10 Integration
    
    /// Convert ISO 8601 duration to Warp10 time format
    /// - Parameter iso8601Period: ISO 8601 period (e.g., "PT1H", "PT24H", "P7D", "P30D")
    /// - Returns: Warp10 time format (e.g., "1 h", "24 h", "7 d", "30 d")
    private func convertToWarp10Period(_ iso8601Period: String) -> String {
        switch iso8601Period {
        case "PT1H":
            return "1 h"
        case "PT24H":
            return "24 h"
        case "P7D":
            return "7 d"
        case "P30D":
            return "30 d"
        case "PT5M":
            return "5 m"
        case "PT15M":
            return "15 m"
        case "PT30M":
            return "30 m"
        case "PT6H":
            return "6 h"
        case "PT12H":
            return "12 h"
        case "P1D":
            return "1 d"
        case "P3D":
            return "3 d"
        case "P14D":
            return "14 d"
        default:
            // Default to 1 hour if unknown format
            print("⚠️ [CCApplicationMetricsService] Unknown period format: \(iso8601Period), defaulting to 1 h")
            return "1 h"
        }
    }
    
    
    /// Parse the actual metrics API response
    private func parseMetricsResponse(json: [String: Any], applicationId: String) -> CCApplicationMetrics {
        // Extract the latest values from time series data
        var cpuUsage: Double = 0.0
        var memoryUsage: Double = 0.0
        var networkIn: Int64 = 0
        var networkOut: Int64 = 0
        
        RemoteLogger.shared.debug("[CleverMetrics] parseMetricsResponse JSON keys", metadata: [
            "keys": json.keys.joined(separator: ", ")
        ])
        
        // The API returns time series data with different metric types
        // We need to find the latest value for each metric
        if let metrics = json["metrics"] as? [[String: Any]] {
            RemoteLogger.shared.debug("[CleverMetrics] Found metrics array", metadata: [
                "count": "\(metrics.count)"
            ])
            
            for (index, metric) in metrics.enumerated() {
                if let metricName = metric["name"] as? String {
                    RemoteLogger.shared.debug("[CleverMetrics] Metric \(index)", metadata: [
                        "name": metricName,
                        "hasValues": "\(metric["values"] != nil)"
                    ])
                    
                    if let values = metric["values"] as? [[Any]] {
                        RemoteLogger.shared.debug("[CleverMetrics] Metric '\(metricName)' values", metadata: [
                            "count": "\(values.count)",
                            "firstValue": values.first.map { String(describing: $0) } ?? "none",
                            "lastValue": values.last.map { String(describing: $0) } ?? "none"
                        ])
                        
                        if let lastValue = values.last,
                           lastValue.count >= 2,
                           let value = lastValue[1] as? Double {
                            
                            switch metricName {
                            case "cpu", "cpu.percent", "cpu_usage":
                                cpuUsage = value
                                RemoteLogger.shared.debug("[CleverMetrics] Set CPU usage", metadata: ["value": "\(value)"])
                            case "mem", "memory", "mem.available", "memory_usage":
                                memoryUsage = value
                                RemoteLogger.shared.debug("[CleverMetrics] Set memory usage", metadata: ["value": "\(value)"])
                            case "net_in", "net.in.bytes", "network_in":
                                networkIn = Int64(value)
                                RemoteLogger.shared.debug("[CleverMetrics] Set network in", metadata: ["value": "\(value)"])
                            case "net_out", "net.out.bytes", "network_out":
                                networkOut = Int64(value)
                                RemoteLogger.shared.debug("[CleverMetrics] Set network out", metadata: ["value": "\(value)"])
                            default:
                                RemoteLogger.shared.debug("[CleverMetrics] Unknown metric", metadata: ["name": metricName])
                                break
                            }
                        }
                    }
                }
            }
        } else {
            RemoteLogger.shared.debug("[CleverMetrics] No metrics array found in response")
        }
        
        // Alternative format: direct time series arrays
        if let cpuData = json["cpu"] as? [[Any]] {
            RemoteLogger.shared.debug("[CleverMetrics] Found direct CPU data", metadata: [
                "count": "\(cpuData.count)",
                "lastValue": cpuData.last.map { String(describing: $0) } ?? "none"
            ])
            if let lastCpu = cpuData.last, lastCpu.count >= 2 {
                cpuUsage = (lastCpu[1] as? Double) ?? 0.0
            }
        }
        if let memData = json["memory"] as? [[Any]] {
            RemoteLogger.shared.debug("[CleverMetrics] Found direct memory data", metadata: [
                "count": "\(memData.count)",
                "lastValue": memData.last.map { String(describing: $0) } ?? "none"
            ])
            if let lastMem = memData.last, lastMem.count >= 2 {
                memoryUsage = (lastMem[1] as? Double) ?? 0.0
            }
        }
        
        // Also check for "mem" key
        if let memData = json["mem"] as? [[Any]] {
            RemoteLogger.shared.debug("[CleverMetrics] Found direct mem data", metadata: [
                "count": "\(memData.count)",
                "lastValue": memData.last.map { String(describing: $0) } ?? "none"
            ])
            if let lastMem = memData.last, lastMem.count >= 2 {
                memoryUsage = (lastMem[1] as? Double) ?? 0.0
            }
        }
        
        RemoteLogger.shared.debug("[CleverMetrics] Final parsed values", metadata: [
            "cpuUsage": "\(cpuUsage)",
            "memoryUsage": "\(memoryUsage)",
            "networkIn": "\(networkIn)",
            "networkOut": "\(networkOut)"
        ])
        
        return CCApplicationMetrics(
            id: UUID().uuidString,
            applicationId: applicationId,
            timestamp: Date(),
            cpuUsage: cpuUsage,
            memoryUsage: memoryUsage,
            networkIn: networkIn,
            networkOut: networkOut,
            requestCount: 0,
            errorCount: 0,
            responseTime: 0.0,
            activeConnections: 0
        )
    }
    
    /// Parse time series response from the v4 API
    private func parseTimeSeriesResponse(data: Data, metricType: MetricType) throws -> [CCApplicationMetricPoint] {
        var points: [CCApplicationMetricPoint] = []
        
        // Log raw data size and preview
        RemoteLogger.shared.debug("[CleverMetrics] parseTimeSeriesResponse", metadata: [
            "dataSize": "\(data.count) bytes",
            "metricType": metricType.rawValue
        ])
        
        // Log raw response as string for debugging
        if let rawString = String(data: data, encoding: .utf8) {
            RemoteLogger.shared.debug("[CleverMetrics] Raw response string", metadata: [
                "response": rawString.prefix(1000).description
            ])
        }
        
        // The v4 API returns an array of metric objects
        guard let metricsArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            RemoteLogger.shared.error("[CleverMetrics] Failed to parse JSON", metadata: [
                "error": "Response is not an array"
            ])
            return []
        }
        
        RemoteLogger.shared.debug("[CleverMetrics] Parsed metrics array", metadata: [
            "count": "\(metricsArray.count)"
        ])
        
        // Log all available metric names for debugging
        let availableMetrics = metricsArray.compactMap { $0["name"] as? String }
        RemoteLogger.shared.debug("[CleverMetrics] Available metrics", metadata: [
            "metrics": availableMetrics.joined(separator: ", ")
        ])
        
        // The v4 API returns: [{"name":"cpu","data":[{"timestamp":...,"value":"..."}],"unit":"...","resource":"..."}]
        for metric in metricsArray {
            if let name = metric["name"] as? String {
                RemoteLogger.shared.debug("[CleverMetrics] Found metric", metadata: [
                    "name": name,
                    "hasData": "\(metric["data"] != nil)",
                    "unit": metric["unit"] as? String ?? "unknown"
                ])
                
                // Check if this is the metric we're looking for
                // For network metrics, we need to find the actual metric names
                let isMatchingMetric: Bool
                switch metricType {
                case .networkIn:
                    // Try various possible network in metric names
                    isMatchingMetric = name.lowercased().contains("net") && 
                                      (name.lowercased().contains("in") || name.lowercased().contains("rx") || name.lowercased().contains("recv"))
                case .networkOut:
                    // Try various possible network out metric names
                    isMatchingMetric = name.lowercased().contains("net") && 
                                      (name.lowercased().contains("out") || name.lowercased().contains("tx") || name.lowercased().contains("send"))
                default:
                    isMatchingMetric = name == metricType.rawValue
                }
                
                if isMatchingMetric,
                   let dataArray = metric["data"] as? [[String: Any]] {
                    
                    RemoteLogger.shared.debug("[CleverMetrics] Processing metric data", metadata: [
                        "name": name,
                        "dataCount": "\(dataArray.count)"
                    ])
                    
                    // Parse each data point
                    for (index, dataPoint) in dataArray.enumerated() {
                        if index < 3 || index >= dataArray.count - 3 {
                            RemoteLogger.shared.debug("[CleverMetrics] Data point \(index)", metadata: [
                                "data": String(describing: dataPoint)
                            ])
                        }
                        
                        if let timestampMicros = dataPoint["timestamp"] as? Double,
                           let valueString = dataPoint["value"] as? String,
                           let value = Double(valueString) {
                            
                            // Adjust value based on metric type
                            var adjustedValue = value
                            
                            // If memory is returned as percentage, convert to bytes (assuming 512MB total for nano)
                            if metricType == .memoryUsage && name == "mem" {
                                // Memory is returned as percentage, convert to bytes
                                // Assuming 512MB total for nano instance
                                let totalMemoryMB = 512.0
                                adjustedValue = (value / 100.0) * totalMemoryMB * 1024 * 1024 // Convert to bytes
                                RemoteLogger.shared.debug("[CleverMetrics] Converting memory percentage to bytes", metadata: [
                                    "percentage": "\(value)%",
                                    "bytes": "\(adjustedValue)"
                                ])
                            }
                            
                            // Convert microseconds to seconds for Date
                            let point = CCApplicationMetricPoint(
                                timestamp: Date(timeIntervalSince1970: timestampMicros / 1_000_000),
                                value: adjustedValue,
                                metricType: metricType.rawValue,
                                unit: metricType.unit
                            )
                            points.append(point)
                            
                            if index < 3 {
                                RemoteLogger.shared.debug("[CleverMetrics] Parsed point", metadata: [
                                    "timestamp": point.timestamp.description,
                                    "value": "\(value)"
                                ])
                            }
                        }
                    }
                }
            }
        }
        
        // If no points were parsed, log detailed error
        if points.isEmpty {
            RemoteLogger.shared.error("[CleverMetrics] No data points parsed", metadata: [
                "metricType": metricType.rawValue,
                "availableMetrics": availableMetrics.joined(separator: ", "),
                "rawDataSize": "\(data.count) bytes"
            ])
        } else {
            RemoteLogger.shared.debug("[CleverMetrics] Successfully parsed data points", metadata: [
                "count": "\(points.count)",
                "firstTimestamp": points.first?.timestamp.description ?? "none",
                "lastTimestamp": points.last?.timestamp.description ?? "none",
                "firstValue": points.first?.value.description ?? "none",
                "lastValue": points.last?.value.description ?? "none"
            ])
        }
        
        // Sort points by timestamp
        points.sort { $0.timestamp < $1.timestamp }
        
        return points
    }
}

// MARK: - Metric Types

/// Available metric types for application monitoring
public enum MetricType: String, CaseIterable {
    case cpuUsage = "cpu"
    case memoryUsage = "mem"
    case networkIn = "net_in"
    case networkOut = "net_out"
    case requestCount = "requests"
    case responseTime = "response_time"
    
    /// Display name for the metric
    public var displayName: String {
        switch self {
        case .cpuUsage: return "CPU Usage"
        case .memoryUsage: return "Memory Usage"
        case .networkIn: return "Network In"
        case .networkOut: return "Network Out"
        case .requestCount: return "Request Count"
        case .responseTime: return "Response Time"
        }
    }
    
    /// Unit for the metric
    public var unit: String {
        switch self {
        case .cpuUsage: return "%"
        case .memoryUsage: return "bytes"
        case .networkIn: return "bytes/s"
        case .networkOut: return "bytes/s"
        case .requestCount: return "requests"
        case .responseTime: return "ms"
        }
    }
    
    /// Color for graph display
    public var color: String {
        switch self {
        case .cpuUsage: return "blue"
        case .memoryUsage: return "green"
        case .networkIn: return "orange"
        case .networkOut: return "red"
        case .requestCount: return "purple"
        case .responseTime: return "yellow"
        }
    }
}

// MARK: - Application Metric Point Model

/// Represents a single data point in application metrics time series
public struct CCApplicationMetricPoint: Identifiable, Codable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let value: Double
    public let metricType: String
    public let unit: String
    
    public init(timestamp: Date, value: Double, metricType: String, unit: String) {
        self.id = UUID()
        self.timestamp = timestamp
        self.value = value
        self.metricType = metricType
        self.unit = unit
    }
    
    /// Formatted value with appropriate unit
    public var formattedValue: String {
        switch metricType {
        case "cpu", "cpu.percent":
            return String(format: "%.1f%%", value)
        case "mem", "memory", "mem.available":
            let mbValue = value / 1024 / 1024
            if mbValue >= 1024 {
                return String(format: "%.1f GB", mbValue / 1024)
            } else if mbValue >= 1 {
                return String(format: "%.0f MB", mbValue)
            } else {
                return String(format: "%.0f KB", value / 1024)
            }
        case "net_in", "net.in.bytes", "network_in":
            return String(format: "%.2f KB/s", value / 1024)
        case "net_out", "net.out.bytes", "network_out":
            return String(format: "%.2f KB/s", value / 1024)
        case "requests", "http.request.count":
            return String(format: "%.0f req", value)
        case "response_time", "http.response.time":
            return String(format: "%.0f ms", value)
        default:
            return String(format: "%.2f %@", value, unit)
        }
    }
} 