import Foundation
import Combine

// MARK: - Monitoring Models

/// Represents application metrics and monitoring data
public struct CCApplicationMetrics: Codable, Identifiable {
    public let id: String
    public let applicationId: String
    public let timestamp: Date
    public let cpuUsage: Double
    public let memoryUsage: Double
    public let networkIn: Int64
    public let networkOut: Int64
    public let requestCount: Int
    public let errorCount: Int
    public let responseTime: Double
    public let activeConnections: Int
    
    /// CPU usage percentage as formatted string
    public var cpuUsageFormatted: String {
        return String(format: "%.1f%%", cpuUsage)
    }
    
    /// Memory usage in MB as formatted string
    public var memoryUsageFormatted: String {
        return String(format: "%.1f MB", memoryUsage / 1024 / 1024)
    }
    
    /// Network in formatted as MB
    public var networkInFormatted: String {
        return String(format: "%.1f MB", Double(networkIn) / 1024 / 1024)
    }
    
    /// Network out formatted as MB
    public var networkOutFormatted: String {
        return String(format: "%.1f MB", Double(networkOut) / 1024 / 1024)
    }
    
    /// Response time formatted as ms
    public var responseTimeFormatted: String {
        return String(format: "%.0f ms", responseTime)
    }
    
    /// Error rate percentage
    public var errorRate: Double {
        guard requestCount > 0 else { return 0.0 }
        return (Double(errorCount) / Double(requestCount)) * 100.0
    }
    
    /// Error rate formatted as percentage
    public var errorRateFormatted: String {
        return String(format: "%.2f%%", errorRate)
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case applicationId = "application_id"
        case timestamp
        case cpuUsage = "cpu_usage"
        case memoryUsage = "memory_usage"
        case networkIn = "network_in"
        case networkOut = "network_out"
        case requestCount = "request_count"
        case errorCount = "error_count"
        case responseTime = "response_time"
        case activeConnections = "active_connections"
    }
    
    public init(
        id: String,
        applicationId: String,
        timestamp: Date,
        cpuUsage: Double,
        memoryUsage: Double,
        networkIn: Int64,
        networkOut: Int64,
        requestCount: Int,
        errorCount: Int,
        responseTime: Double,
        activeConnections: Int
    ) {
        self.id = id
        self.applicationId = applicationId
        self.timestamp = timestamp
        self.cpuUsage = cpuUsage
        self.memoryUsage = memoryUsage
        self.networkIn = networkIn
        self.networkOut = networkOut
        self.requestCount = requestCount
        self.errorCount = errorCount
        self.responseTime = responseTime
        self.activeConnections = activeConnections
    }
}

/// Represents application health status
public struct CCApplicationHealth: Codable, Identifiable {
    public let id: String
    public let applicationId: String
    public let status: String
    public let lastCheck: Date
    public let uptime: Int64
    public let instancesStatus: [CCInstanceStatus]
    public let healthScore: Double
    public let issues: [CCHealthIssue]
    
    /// Overall health status
    public var overallStatus: HealthStatus {
        switch status.lowercased() {
        case "healthy": return .healthy
        case "warning": return .warning
        case "critical": return .critical
        case "down": return .down
        default: return .unknown
        }
    }
    
    /// Health status emoji
    public var statusEmoji: String {
        switch overallStatus {
        case .healthy: return "✅"
        case .warning: return "⚠️"
        case .critical: return "🔴"
        case .down: return "💀"
        case .unknown: return "❓"
        }
    }
    
    /// Uptime formatted as human readable string
    public var uptimeFormatted: String {
        let days = uptime / (24 * 60 * 60)
        let hours = (uptime % (24 * 60 * 60)) / (60 * 60)
        let minutes = (uptime % (60 * 60)) / 60
        
        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    /// Health score formatted as percentage
    public var healthScoreFormatted: String {
        return String(format: "%.1f%%", healthScore)
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case applicationId = "application_id"
        case status
        case lastCheck = "last_check"
        case uptime
        case instancesStatus = "instances_status"
        case healthScore = "health_score"
        case issues
    }
    
    public init(
        id: String,
        applicationId: String,
        status: String,
        lastCheck: Date,
        uptime: Int64,
        instancesStatus: [CCInstanceStatus],
        healthScore: Double,
        issues: [CCHealthIssue]
    ) {
        self.id = id
        self.applicationId = applicationId
        self.status = status
        self.lastCheck = lastCheck
        self.uptime = uptime
        self.instancesStatus = instancesStatus
        self.healthScore = healthScore
        self.issues = issues
    }
}

/// Health status enum
public enum HealthStatus: String, CaseIterable {
    case healthy = "healthy"
    case warning = "warning"
    case critical = "critical"
    case down = "down"
    case unknown = "unknown"
}

/// Instance status in health check
public struct CCInstanceStatus: Codable, Identifiable {
    public let id: String
    public let instanceId: String
    public let status: String
    public let cpuUsage: Double
    public let memoryUsage: Double
    public let lastHeartbeat: Date?
    
    /// Instance status emoji
    public var statusEmoji: String {
        switch status.lowercased() {
        case "running": return "🟢"
        case "starting": return "🟡"
        case "stopping": return "🟠"
        case "stopped": return "🔴"
        default: return "❓"
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case instanceId = "instance_id"
        case status
        case cpuUsage = "cpu_usage"
        case memoryUsage = "memory_usage"
        case lastHeartbeat = "last_heartbeat"
    }
    
    public init(
        id: String,
        instanceId: String,
        status: String,
        cpuUsage: Double,
        memoryUsage: Double,
        lastHeartbeat: Date?
    ) {
        self.id = id
        self.instanceId = instanceId
        self.status = status
        self.cpuUsage = cpuUsage
        self.memoryUsage = memoryUsage
        self.lastHeartbeat = lastHeartbeat
    }
}

/// Health issue detected
public struct CCHealthIssue: Codable, Identifiable {
    public let id: String
    public let severity: String
    public let message: String
    public let detectedAt: Date
    public let resolvedAt: Date?
    public let type: String
    
    /// Severity emoji
    public var severityEmoji: String {
        switch severity.lowercased() {
        case "info": return "ℹ️"
        case "warning": return "⚠️"
        case "error": return "❌"
        case "critical": return "🚨"
        default: return "❓"
        }
    }
    
    /// Is resolved
    public var isResolved: Bool {
        return resolvedAt != nil
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case severity
        case message
        case detectedAt = "detected_at"
        case resolvedAt = "resolved_at"
        case type
    }
    
    public init(
        id: String,
        severity: String,
        message: String,
        detectedAt: Date,
        resolvedAt: Date? = nil,
        type: String
    ) {
        self.id = id
        self.severity = severity
        self.message = message
        self.detectedAt = detectedAt
        self.resolvedAt = resolvedAt
        self.type = type
    }
}

// MARK: - Log Models

/// Represents application logs
public struct CCApplicationLog: Codable, Identifiable {
    public let id: String
    public let applicationId: String
    public let timestamp: Date
    public let level: String
    public let message: String
    public let source: String
    public let instanceId: String?
    public let metadata: [String: String]?
    
    /// Log level emoji
    public var levelEmoji: String {
        switch level.lowercased() {
        case "debug": return "🐛"
        case "info": return "ℹ️"
        case "warn", "warning": return "⚠️"
        case "error": return "❌"
        case "fatal", "critical": return "💥"
        default: return "📝"
        }
    }
    
    /// Formatted timestamp
    public var timestampFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter.string(from: timestamp)
    }
    
    /// Log level color (for UI)
    public var levelColor: String {
        switch level.lowercased() {
        case "debug": return "gray"
        case "info": return "blue"
        case "warn", "warning": return "orange"
        case "error": return "red"
        case "fatal", "critical": return "purple"
        default: return "black"
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case applicationId = "application_id"
        case timestamp
        case level
        case message
        case source
        case instanceId = "instance_id"
        case metadata
    }
    
    public init(
        id: String,
        applicationId: String,
        timestamp: Date,
        level: String,
        message: String,
        source: String,
        instanceId: String? = nil,
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.applicationId = applicationId
        self.timestamp = timestamp
        self.level = level
        self.message = message
        self.source = source
        self.instanceId = instanceId
        self.metadata = metadata
    }
}

/// Log query filter
public struct CCLogFilter: Codable {
    public let level: String?
    public let source: String?
    public let since: Date?
    public let until: Date?
    public let search: String?
    public let limit: Int?
    
    public init(
        level: String? = nil,
        source: String? = nil,
        since: Date? = nil,
        until: Date? = nil,
        search: String? = nil,
        limit: Int? = nil
    ) {
        self.level = level
        self.source = source
        self.since = since
        self.until = until
        self.search = search
        self.limit = limit
    }
}

// MARK: - Performance Models

/// Application performance statistics
public struct CCPerformanceStats: Codable, Identifiable {
    public let id: String
    public let applicationId: String
    public let period: String
    public let averageResponseTime: Double
    public let p95ResponseTime: Double
    public let p99ResponseTime: Double
    public let throughput: Double
    public let errorRate: Double
    public let availabilityPercentage: Double
    public let totalRequests: Int64
    public let totalErrors: Int64
    public let peakConcurrentUsers: Int
    
    /// Average response time formatted
    public var averageResponseTimeFormatted: String {
        return String(format: "%.0f ms", averageResponseTime)
    }
    
    /// P95 response time formatted
    public var p95ResponseTimeFormatted: String {
        return String(format: "%.0f ms", p95ResponseTime)
    }
    
    /// P99 response time formatted
    public var p99ResponseTimeFormatted: String {
        return String(format: "%.0f ms", p99ResponseTime)
    }
    
    /// Throughput formatted
    public var throughputFormatted: String {
        return String(format: "%.1f req/s", throughput)
    }
    
    /// Error rate formatted
    public var errorRateFormatted: String {
        return String(format: "%.2f%%", errorRate)
    }
    
    /// Availability formatted
    public var availabilityFormatted: String {
        return String(format: "%.3f%%", availabilityPercentage)
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case applicationId = "application_id"
        case period
        case averageResponseTime = "average_response_time"
        case p95ResponseTime = "p95_response_time"
        case p99ResponseTime = "p99_response_time"
        case throughput
        case errorRate = "error_rate"
        case availabilityPercentage = "availability_percentage"
        case totalRequests = "total_requests"
        case totalErrors = "total_errors"
        case peakConcurrentUsers = "peak_concurrent_users"
    }
    
    public init(
        id: String,
        applicationId: String,
        period: String,
        averageResponseTime: Double,
        p95ResponseTime: Double,
        p99ResponseTime: Double,
        throughput: Double,
        errorRate: Double,
        availabilityPercentage: Double,
        totalRequests: Int64,
        totalErrors: Int64,
        peakConcurrentUsers: Int
    ) {
        self.id = id
        self.applicationId = applicationId
        self.period = period
        self.averageResponseTime = averageResponseTime
        self.p95ResponseTime = p95ResponseTime
        self.p99ResponseTime = p99ResponseTime
        self.throughput = throughput
        self.errorRate = errorRate
        self.availabilityPercentage = availabilityPercentage
        self.totalRequests = totalRequests
        self.totalErrors = totalErrors
        self.peakConcurrentUsers = peakConcurrentUsers
    }
}

// MARK: - Alert Models

/// Alert rule configuration
public struct CCAlertRule: Codable, Identifiable {
    public let id: String
    public let name: String
    public let metric: String
    public let threshold: Double
    public let operatorType: String
    public let duration: Int
    public let severity: String
    public let enabled: Bool
    public let notificationChannels: [String]
    public let createdAt: Date
    public let updatedAt: Date?
    
    /// Severity emoji
    public var severityEmoji: String {
        switch severity.lowercased() {
        case "info": return "ℹ️"
        case "warning": return "⚠️"
        case "error": return "❌"
        case "critical": return "🚨"
        default: return "📊"
        }
    }
    
    /// Operator symbol
    public var operatorSymbol: String {
        switch operatorType.lowercased() {
        case "gt", "greater_than": return ">"
        case "gte", "greater_than_equal": return "≥"
        case "lt", "less_than": return "<"
        case "lte", "less_than_equal": return "≤"
        case "eq", "equal": return "="
        case "ne", "not_equal": return "≠"
        default: return operatorType
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case metric
        case threshold
        case operatorType = "operator"
        case duration
        case severity
        case enabled
        case notificationChannels = "notification_channels"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    public init(
        id: String,
        name: String,
        metric: String,
        threshold: Double,
        operatorValue: String,
        duration: Int,
        severity: String,
        enabled: Bool,
        notificationChannels: [String],
        createdAt: Date,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.metric = metric
        self.threshold = threshold
        self.operatorType = operatorValue
        self.duration = duration
        self.severity = severity
        self.enabled = enabled
        self.notificationChannels = notificationChannels
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Active alert
public struct CCAlert: Codable, Identifiable {
    public let id: String
    public let ruleId: String
    public let applicationId: String
    public let status: String
    public let triggeredAt: Date
    public let resolvedAt: Date?
    public let currentValue: Double
    public let threshold: Double
    public let message: String
    public let metadata: [String: String]?
    
    /// Is active
    public var isActive: Bool {
        return resolvedAt == nil
    }
    
    /// Duration since triggered
    public var duration: TimeInterval {
        if let resolvedAt = resolvedAt {
            return resolvedAt.timeIntervalSince(triggeredAt)
        }
        return Date().timeIntervalSince(triggeredAt)
    }
    
    /// Duration formatted
    public var durationFormatted: String {
        let minutes = Int(duration / 60)
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        
        if hours > 0 {
            return "\(hours)h \(remainingMinutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case ruleId = "rule_id"
        case applicationId = "application_id"
        case status
        case triggeredAt = "triggered_at"
        case resolvedAt = "resolved_at"
        case currentValue = "current_value"
        case threshold
        case message
        case metadata
    }
    
    public init(
        id: String,
        ruleId: String,
        applicationId: String,
        status: String,
        triggeredAt: Date,
        resolvedAt: Date? = nil,
        currentValue: Double,
        threshold: Double,
        message: String,
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.ruleId = ruleId
        self.applicationId = applicationId
        self.status = status
        self.triggeredAt = triggeredAt
        self.resolvedAt = resolvedAt
        self.currentValue = currentValue
        self.threshold = threshold
        self.message = message
        self.metadata = metadata
    }
} 