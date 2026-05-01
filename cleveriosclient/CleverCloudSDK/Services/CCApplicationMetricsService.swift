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
        
        debugLog("📊 [CCApplicationMetricsService] Getting metrics for application: \(applicationId)")
        debugLog("📊 [CCApplicationMetricsService] Organization: \(organizationId), Period: \(period)")
        debugLog("📊 [CCApplicationMetricsService] ✅ FIXED: Using OAuth 1.0a directly on v4 API (same as official JS SDK)")
        
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
        
        debugLog("📊 [CCApplicationMetricsService] OAuth 1.0a request to: \(fullEndpoint)")
        
        // Use OAuth 1.0a directly (same as JS SDK) instead of Bearer token
        return httpClient.getRawData(fullEndpoint, apiVersion: .v4)
        .tryMap { data in
            debugLog("🔍 [CleverMetrics] getApplicationMetrics response [dataSize=\(data.count) bytes, endpoint=\(fullEndpoint)]")
            
            // Log the raw response to understand the format
            if let jsonString = String(data: data, encoding: .utf8) {
                debugLog("🔍 [CleverMetrics] Raw metrics API response [response=\(jsonString.prefix(1000).description)]")
            }
            
            // Parse the actual metrics response format
            // The API likely returns time series data, not a single metrics object
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                debugLog("🔍 [CleverMetrics] Successfully parsed JSON [keys=\(json.keys.joined(separator: ", "))]")
                
                // Create metrics from the actual response
                return self.parseMetricsResponse(json: json, applicationId: applicationId)
            } else {
                debugLog("❌ [CleverMetrics] Invalid JSON format [error=Response is not a dictionary]")
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
                debugLog("✅ [CCApplicationMetricsService] SUCCESS! Received comprehensive metrics with OAuth 1.0a")
                debugLog("📊 [CCApplicationMetricsService] CPU: \(metrics.cpuUsageFormatted), Memory: \(metrics.memoryUsageFormatted)")
            },
            receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    debugLog("❌ [CCApplicationMetricsService] OAuth 1.0a request failed: \(error)")
                }
            }
        )
        .catch { error -> AnyPublisher<CCApplicationMetrics, CCError> in
            // Return error instead of mock data
            debugLog("⚠️ [CCApplicationMetricsService] OAuth 1.0a request failed: \(error)")
            return Fail(error: error)
                .eraseToAnyPublisher()
        }
        .eraseToAnyPublisher()
    }
    
    /// Get time series data for specific metric using v4 API or Warp10
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
        span: String = "PT1H",
        totalMemoryMB: Double = 512.0
    ) -> AnyPublisher<[CCApplicationMetricPoint], CCError> {

        debugLog("📈 [CCApplicationMetricsService] Getting time series for metric '\(metric.rawValue)'")
        debugLog("📈 [CCApplicationMetricsService] App: \(applicationId), Interval: \(interval), Span: \(span)")

        // For network metrics, use Warp10 directly as v4 API doesn't provide them
        if metric == .networkIn || metric == .networkOut {
            debugLog("📈 [CCApplicationMetricsService] 🔄 Using Warp10 for network metrics")
            return getNetworkMetricsFromWarp10(
                applicationId: applicationId,
                organizationId: organizationId,
                metric: metric,
                span: span
            )
        }

        // For CPU and Memory, continue using v4 API which works well
        debugLog("📈 [CCApplicationMetricsService] ✅ Using v4 API for CPU/Memory metrics")

        // Build endpoint with query parameters - Use same endpoint as getApplicationMetrics
        let endpoint = "/stats/organisations/\(organizationId)/resources/\(applicationId)/metrics"

        let queryItems = [
            URLQueryItem(name: "interval", value: interval),
            URLQueryItem(name: "span", value: span),
            URLQueryItem(name: "only", value: metric.rawValue) // Filter to specific metric
        ]

        var urlComponents = URLComponents()
        urlComponents.queryItems = queryItems
        let queryString = urlComponents.query ?? ""
        let fullEndpoint = queryString.isEmpty ? endpoint : "\(endpoint)?\(queryString)"

        debugLog("📈 [CCApplicationMetricsService] OAuth 1.0a request to: \(fullEndpoint)")

        return httpClient.getRawData(fullEndpoint, apiVersion: .v4)
            .tryMap { data in
                debugLog("🔍 [CleverMetrics] getApplicationTimeSeries response [dataSize=\(data.count) bytes, endpoint=\(fullEndpoint), metric=\(metric.rawValue)]")

                // Log the raw response to understand the format
                if let jsonString = String(data: data, encoding: .utf8) {
                    debugLog("🔍 [CleverMetrics] Raw time series response [metric=\(metric.rawValue), response=\(jsonString.prefix(1000).description)]")
                }

                // Parse the time series response
                return try self.parseTimeSeriesResponse(data: data, metricType: metric, totalMemoryMB: totalMemoryMB)
            }
            .mapError { error in
                if let ccError = error as? CCError {
                    return ccError
                }
                return CCError.parsingError(error)
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
        
        debugLog("⏱️ [CCApplicationMetricsService] Starting real-time metrics polling (interval: \(interval)s)")
        
        return Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .prepend(Date()) // Emit immediately
            .flatMap { [weak self] _ -> AnyPublisher<CCApplicationMetrics, CCError> in
                guard let self = self else {
                    return Empty().eraseToAnyPublisher()
                }
                return self.getApplicationMetrics(
                    applicationId: applicationId,
                    organizationId: organizationId,
                    period: "PT1H"
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

    /// Get network metrics from Warp10 directly
    /// - Parameters:
    ///   - applicationId: The application ID
    ///   - organizationId: The organization ID
    ///   - metric: The network metric type (networkIn or networkOut)
    ///   - span: Time span in ISO8601 format
    /// - Returns: Publisher with network metric data points
    private func getNetworkMetricsFromWarp10(
        applicationId: String,
        organizationId: String,
        metric: MetricType,
        span: String
    ) -> AnyPublisher<[CCApplicationMetricPoint], CCError> {

        debugLog("🌐 [CCApplicationMetricsService] Fetching network metrics from Warp10")
        debugLog("🌐 [CCApplicationMetricsService] Metric: \(metric.rawValue), App: \(applicationId)")

        // Convert ISO8601 to Warp10 format
        let warp10Span = convertToWarp10Period(span)

        return warp10Client.getWarp10Token(organizationId: organizationId)
            .flatMap { token -> AnyPublisher<[CCApplicationMetricPoint], CCError> in
                // Create WarpScript for the specific network metric
                let metricName = metric == .networkIn ? "net.bytes_recv" : "net.bytes_sent"

                let warpScript = """
                [ '\(token)' '\(metricName)' { 'app_id' '\(applicationId)' } NOW \(warp10Span) ] FETCH
                """

                debugLog("🌐 [CCApplicationMetricsService] Executing WarpScript for metric: \(metricName)")

                return self.warp10Client.executeWarpScript(warpScript)
                    .tryMap { data in
                        return try self.parseWarp10NetworkResponse(
                            data: data,
                            metricType: metric
                        )
                    }
                    .mapError { error in
                        if let ccError = error as? CCError {
                            return ccError
                        }
                        return CCError.parsingError(error)
                    }
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }

    /// Parse Warp10 network metrics response
    /// - Parameters:
    ///   - data: Raw response data from Warp10
    ///   - metricType: The metric type being parsed
    /// - Returns: Array of metric points
    private func parseWarp10NetworkResponse(
        data: Data,
        metricType: MetricType
    ) throws -> [CCApplicationMetricPoint] {

        debugLog("📊 [CCApplicationMetricsService] Parsing Warp10 network response")

        // Log raw response for debugging
        if let jsonString = String(data: data, encoding: .utf8) {
            debugLog("📊 [CCApplicationMetricsService] Warp10 response: \(jsonString.prefix(500))")
        }

        // Warp10 returns nested arrays: [[{...}]]
        guard let outerArray = try JSONSerialization.jsonObject(with: data) as? [Any] else {
            debugLog("❌ [CCApplicationMetricsService] Invalid Warp10 response format - not an array")
            return []
        }

        var points: [CCApplicationMetricPoint] = []

        // Process each GTS (GeoTime Series)
        for element in outerArray {
            guard let gtsArray = element as? [[String: Any]] else {
                debugLog("⚠️ [CCApplicationMetricsService] Skipping non-GTS element")
                continue
            }

            for gts in gtsArray {
                guard let className = gts["c"] as? String,
                      let values = gts["v"] as? [[Any]] else {
                    debugLog("⚠️ [CCApplicationMetricsService] Skipping malformed GTS")
                    continue
                }

                debugLog("📊 [CCApplicationMetricsService] Processing GTS '\(className)' with \(values.count) data points")

                // Sort values by timestamp ascending (Warp10 may return descending)
                let sortedValues = values.sorted { a, b in
                    let tsA = (a[0] as? Double) ?? 0
                    let tsB = (b[0] as? Double) ?? 0
                    return tsA < tsB
                }

                // Parse each value: [timestamp, latitude, longitude, elevation, value]
                var previousTimestamp: Double?
                var previousValue: Double?

                for valueArray in sortedValues {
                    // Warp10 format: [timestamp, lat, lon, elev, value] or just [timestamp, value]
                    let timestamp: Double
                    let value: Double

                    if valueArray.count >= 5 {
                        // Full GeoTime format
                        guard let ts = valueArray[0] as? Double,
                              let val = valueArray[4] as? Double else {
                            continue
                        }
                        timestamp = ts
                        value = val
                    } else if valueArray.count >= 2 {
                        // Simple format
                        guard let ts = valueArray[0] as? Double,
                              let val = valueArray[1] as? Double else {
                            continue
                        }
                        timestamp = ts
                        value = val
                    } else {
                        continue
                    }

                    // For network metrics, calculate rate (bytes/sec) from cumulative values
                    if let prevTs = previousTimestamp, let prevVal = previousValue {
                        let timeDiffSeconds = (timestamp - prevTs) / 1_000_000
                        let valueDiff = value - prevVal

                        // Skip counter resets (negative diff = new instance started)
                        // and same-timestamp duplicates
                        if valueDiff >= 0 && timeDiffSeconds > 0 {
                            let rate = valueDiff / timeDiffSeconds
                            let date = Date(timeIntervalSince1970: timestamp / 1_000_000)

                            let point = CCApplicationMetricPoint(
                                timestamp: date,
                                value: rate,
                                metricType: metricType.rawValue,
                                unit: metricType.unit
                            )
                            points.append(point)
                        }
                    }

                    // Store current values for next iteration
                    previousTimestamp = timestamp
                    previousValue = value
                }
            }
        }

        // Sort by timestamp
        points.sort { $0.timestamp < $1.timestamp }

        debugLog("✅ [CCApplicationMetricsService] Parsed \(points.count) network data points")
        return points
    }

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
            debugLog("⚠️ [CCApplicationMetricsService] Unknown period format: \(iso8601Period), defaulting to 1 h")
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
        
        debugLog("🔍 [CleverMetrics] parseMetricsResponse JSON keys [keys=\(json.keys.joined(separator: ", "))]")
        
        // The API returns time series data with different metric types
        // We need to find the latest value for each metric
        if let metrics = json["metrics"] as? [[String: Any]] {
            debugLog("🔍 [CleverMetrics] Found metrics array [count=\(metrics.count)]")
            
            for (index, metric) in metrics.enumerated() {
                if let metricName = metric["name"] as? String {
                    debugLog("🔍 [CleverMetrics] Metric \(index) [name=\(metricName), hasValues=\("\(metric["values"] != nil)")]")
                    
                    if let values = metric["values"] as? [[Any]] {
                        debugLog("🔍 [CleverMetrics] Metric '\(metricName)' values [count=\(values.count), firstValue=\(values.first.map { String(describing: $0) } ?? "none"), lastValue=\(values.last.map { String(describing: $0) } ?? "none")]")
                        
                        if let lastValue = values.last,
                           lastValue.count >= 2,
                           let value = lastValue[1] as? Double {
                            
                            switch metricName {
                            case "cpu", "cpu.percent", "cpu_usage":
                                cpuUsage = value
                                debugLog("🔍 [CleverMetrics] Set CPU usage [value=\(value)]")
                            case "mem", "memory", "mem.available", "memory_usage":
                                memoryUsage = value
                                debugLog("🔍 [CleverMetrics] Set memory usage [value=\(value)]")
                            case "net_in", "net.in.bytes", "network_in":
                                networkIn = Int64(value)
                                debugLog("🔍 [CleverMetrics] Set network in [value=\(value)]")
                            case "net_out", "net.out.bytes", "network_out":
                                networkOut = Int64(value)
                                debugLog("🔍 [CleverMetrics] Set network out [value=\(value)]")
                            default:
                                debugLog("🔍 [CleverMetrics] Unknown metric [name=\(metricName)]")
                                break
                            }
                        }
                    }
                }
            }
        } else {
            debugLog("🔍 [CleverMetrics] No metrics array found in response")
        }
        
        // Alternative format: direct time series arrays
        if let cpuData = json["cpu"] as? [[Any]] {
            debugLog("🔍 [CleverMetrics] Found direct CPU data [count=\(cpuData.count), lastValue=\(cpuData.last.map { String(describing: $0) } ?? "none")]")
            if let lastCpu = cpuData.last, lastCpu.count >= 2 {
                cpuUsage = (lastCpu[1] as? Double) ?? 0.0
            }
        }
        if let memData = json["memory"] as? [[Any]] {
            debugLog("🔍 [CleverMetrics] Found direct memory data [count=\(memData.count), lastValue=\(memData.last.map { String(describing: $0) } ?? "none")]")
            if let lastMem = memData.last, lastMem.count >= 2 {
                memoryUsage = (lastMem[1] as? Double) ?? 0.0
            }
        }
        
        // Also check for "mem" key
        if let memData = json["mem"] as? [[Any]] {
            debugLog("🔍 [CleverMetrics] Found direct mem data [count=\(memData.count), lastValue=\(memData.last.map { String(describing: $0) } ?? "none")]")
            if let lastMem = memData.last, lastMem.count >= 2 {
                memoryUsage = (lastMem[1] as? Double) ?? 0.0
            }
        }
        
        debugLog("🔍 [CleverMetrics] Final parsed values [cpuUsage=\(cpuUsage), memoryUsage=\(memoryUsage), networkIn=\(networkIn), networkOut=\(networkOut)]")
        
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
    private func parseTimeSeriesResponse(data: Data, metricType: MetricType, totalMemoryMB: Double = 512.0) throws -> [CCApplicationMetricPoint] {
        var points: [CCApplicationMetricPoint] = []

        debugLog("🔍 [CleverMetrics] parseTimeSeriesResponse [dataSize=\(data.count) bytes, metricType=\(metricType.rawValue)]")

        if let rawString = String(data: data, encoding: .utf8) {
            debugLog("🔍 [CleverMetrics] Raw response string [response=\(rawString.prefix(1000).description)]")
        }

        // Parse top-level JSON - handle both array and dictionary formats
        let jsonObject = try JSONSerialization.jsonObject(with: data)
        let metricsArray: [[String: Any]]
        if let array = jsonObject as? [[String: Any]] {
            metricsArray = array
        } else if let dict = jsonObject as? [String: Any] {
            // Single metric object wrapped in a dictionary
            metricsArray = [dict]
        } else {
            debugLog("❌ [CleverMetrics] Failed to parse JSON [error=Response is not an array or dictionary, type=\(type(of: jsonObject))]")
            return []
        }
        
        debugLog("🔍 [CleverMetrics] Parsed metrics array [count=\(metricsArray.count)]")
        
        // Log all available metric names for debugging
        let availableMetrics = metricsArray.compactMap { $0["name"] as? String }
        debugLog("🔍 [CleverMetrics] Available metrics [metrics=\(availableMetrics.joined(separator: ", ")), searchingFor=\(metricType.rawValue)]")

        // Special logging for network metrics to understand what's available
        if metricType == .networkIn || metricType == .networkOut {
            let networkMetrics = availableMetrics.filter { name in
                let lowercaseName = name.lowercased()
                return lowercaseName.contains("net") || lowercaseName.contains("network") ||
                       lowercaseName.contains("rx") || lowercaseName.contains("tx") ||
                       lowercaseName.contains("in") || lowercaseName.contains("out")
            }
            debugLog("🔍 [CleverMetrics] Network-related metrics found [networkMetrics=\(networkMetrics.joined(separator: ", ")), count=\(networkMetrics.count)]")
        }
        
        // The v4 API returns: [{"name":"cpu","data":[{"timestamp":...,"value":"..."}],"unit":"...","resource":"..."}]
        for metric in metricsArray {
            if let name = metric["name"] as? String {
                debugLog("🔍 [CleverMetrics] Found metric [name=\(name), hasData=\("\(metric["data"] != nil)"), unit=\(metric["unit"] as? String ?? "unknown")]")
                
                // Check if this is the metric we're looking for
                // For network metrics, we need to find the actual metric names
                let isMatchingMetric: Bool
                switch metricType {
                case .networkIn:
                    // Extended list of possible network in metric names based on Clever Cloud API
                    let lowercaseName = name.lowercased()
                    isMatchingMetric = lowercaseName == "net_in" ||
                                      lowercaseName == "network_in" ||
                                      lowercaseName == "net.in" ||
                                      lowercaseName == "net.in.bytes" ||
                                      lowercaseName == "network.in" ||
                                      lowercaseName == "network.incoming" ||
                                      lowercaseName == "net_rx" ||
                                      lowercaseName == "rx_bytes" ||
                                      lowercaseName == "network_received" ||
                                      (lowercaseName.contains("net") && (lowercaseName.contains("in") || lowercaseName.contains("rx") || lowercaseName.contains("recv")))
                case .networkOut:
                    // Extended list of possible network out metric names based on Clever Cloud API
                    let lowercaseName = name.lowercased()
                    isMatchingMetric = lowercaseName == "net_out" ||
                                      lowercaseName == "network_out" ||
                                      lowercaseName == "net.out" ||
                                      lowercaseName == "net.out.bytes" ||
                                      lowercaseName == "network.out" ||
                                      lowercaseName == "network.outgoing" ||
                                      lowercaseName == "net_tx" ||
                                      lowercaseName == "tx_bytes" ||
                                      lowercaseName == "network_sent" ||
                                      (lowercaseName.contains("net") && (lowercaseName.contains("out") || lowercaseName.contains("tx") || lowercaseName.contains("send")))
                default:
                    isMatchingMetric = name == metricType.rawValue
                }
                
                if isMatchingMetric,
                   let dataArray = metric["data"] as? [[String: Any]] {
                    
                    debugLog("🔍 [CleverMetrics] Processing metric data [name=\(name), dataCount=\(dataArray.count)]")
                    
                    // Parse each data point
                    for (index, dataPoint) in dataArray.enumerated() {
                        if index < 3 {
                            debugLog("🔍 [CleverMetrics] Data point \(index) [data=\(dataPoint)]")
                        }

                        // Parse timestamp - handle Double, Int, and String types
                        let timestampMicros: Double
                        if let tsDouble = dataPoint["timestamp"] as? Double {
                            timestampMicros = tsDouble
                        } else if let tsInt = dataPoint["timestamp"] as? Int {
                            timestampMicros = Double(tsInt)
                        } else if let tsString = dataPoint["timestamp"] as? String,
                                  let tsParsed = Double(tsString) {
                            timestampMicros = tsParsed
                        } else {
                            continue
                        }

                        // Parse value - handle Double, Int, and String types
                        let value: Double
                        if let numValue = dataPoint["value"] as? Double {
                            value = numValue
                        } else if let intValue = dataPoint["value"] as? Int {
                            value = Double(intValue)
                        } else if let valueString = dataPoint["value"] as? String,
                                  let parsedValue = Double(valueString) {
                            value = parsedValue
                        } else {
                            continue
                        }

                        var adjustedValue = value

                        // Convert memory percentage to bytes using actual flavor memory
                        // When totalMemoryMB is 0 (addons), keep raw percentage
                        if metricType == .memoryUsage && name == "mem" && value <= 100.0 && totalMemoryMB > 0 {
                            adjustedValue = (value / 100.0) * totalMemoryMB * 1024 * 1024
                        }

                        // For addon memory (totalMemoryMB == 0), store as "cpu" type
                        // so formattedValue displays as percentage, not bytes
                        let pointMetricType = (metricType == .memoryUsage && totalMemoryMB == 0)
                            ? MetricType.cpuUsage.rawValue : metricType.rawValue
                        let pointUnit = (metricType == .memoryUsage && totalMemoryMB == 0)
                            ? "%" : metricType.unit

                        let point = CCApplicationMetricPoint(
                            timestamp: Date(timeIntervalSince1970: timestampMicros / 1_000_000),
                            value: adjustedValue,
                            metricType: pointMetricType,
                            unit: pointUnit
                        )
                        points.append(point)
                    }
                }
            }
        }
        
        // If no points were parsed, log detailed error
        if points.isEmpty {
            debugLog("❌ [CleverMetrics] No data points parsed [metricType=\(metricType.rawValue), availableMetrics=\(availableMetrics.joined(separator: ", ")), rawDataSize=\(data.count) bytes]")
        } else {
            debugLog("🔍 [CleverMetrics] Successfully parsed data points [count=\(points.count), firstTimestamp=\(points.first?.timestamp.description ?? "none"), lastTimestamp=\(points.last?.timestamp.description ?? "none"), firstValue=\(points.first?.value.description ?? "none"), lastValue=\(points.last?.value.description ?? "none")]")
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