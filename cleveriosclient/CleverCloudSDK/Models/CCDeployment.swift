import Foundation
import Combine

// MARK: - CCDeployment Models

/// Represents a Clever Cloud deployment
public struct CCDeployment: Codable, Identifiable, Equatable {
    
    // MARK: - Core Properties
    
    /// Unique deployment identifier
    public let id: String
    
    /// Deployment UUID (Clever Cloud internal ID)
    public let uuid: String
    
    /// Application ID this deployment belongs to
    public let applicationId: String
    
    /// Deployment action type (e.g., "DEPLOY", "RESTART", "CANCEL")
    public let action: String
    
    /// Deployment state (e.g., "WIP", "SUCCESS", "FAIL", "CANCELLED")
    public let state: String
    
    /// Deployment type (e.g., "GIT_PUSH", "MANUAL", "API")
    public let type: String?
    
    /// Git commit SHA if deployment is from Git
    public let commit: String?
    
    /// Git repository URL
    public let repository: String?
    
    /// Git branch name
    public let branch: String?
    
    /// Deployment creation timestamp
    public let createdAt: Date
    
    /// Deployment start timestamp
    public let startedAt: Date?
    
    /// Deployment end timestamp  
    public let endedAt: Date?
    
    /// Duration in seconds
    public let duration: Int?
    
    /// Deployment result message
    public let result: String?
    
    /// Error message if deployment failed
    public let error: String?
    
    /// User who triggered the deployment
    public let triggeredBy: String?
    
    /// Deployment environment variables
    public let environment: [String: String]?
    
    /// Instance configuration at deployment time
    public let instanceConfiguration: CCInstanceConfiguration?
    
    // MARK: - Computed Properties
    
    /// Display-friendly deployment state
    public var displayState: String {
        switch state.uppercased() {
        case "WIP":
            return "🟡 In Progress"
        case "SUCCESS":
            return "✅ Success"
        case "FAIL", "FAILED":
            return "❌ Failed"
        case "CANCELLED":
            return "⚪ Cancelled"
        case "QUEUED":
            return "🟦 Queued"
        default:
            return "🔵 \(state)"
        }
    }
    
    /// Display-friendly deployment action
    public var displayAction: String {
        switch action.uppercased() {
        case "DEPLOY":
            return "🚀 Deploy"
        case "RESTART":
            return "🔄 Restart"
        case "CANCEL":
            return "⏹️ Cancel"
        case "UNDEPLOY":
            return "🗑️ Undeploy"
        default:
            return "⚙️ \(action)"
        }
    }
    
    /// Short commit SHA for display
    public var shortCommit: String? {
        guard let commit = commit else { return nil }
        return String(commit.prefix(8))
    }
    
    /// Duration in human-readable format
    public var humanDuration: String? {
        guard let duration = duration else { return nil }
        
        if duration < 60 {
            return "\(duration)s"
        } else if duration < 3600 {
            let minutes = duration / 60
            let seconds = duration % 60
            return "\(minutes)m \(seconds)s"
        } else {
            let hours = duration / 3600
            let minutes = (duration % 3600) / 60
            return "\(hours)h \(minutes)m"
        }
    }
    
    /// Is deployment currently active
    public var isActive: Bool {
        return state.uppercased() == "WIP" || state.uppercased() == "QUEUED"
    }
    
    /// Is deployment successful
    public var isSuccessful: Bool {
        return state.uppercased() == "SUCCESS"
    }
    
    /// Is deployment failed
    public var isFailed: Bool {
        return state.uppercased() == "FAIL" || state.uppercased() == "FAILED"
    }
    
    // MARK: - Coding Keys
    
    enum CodingKeys: String, CodingKey {
        case id
        case uuid
        case applicationId = "app_id"
        case action
        case state
        case type
        case commit
        case repository
        case branch
        case createdAt = "date"
        case startedAt = "started_date"
        case endedAt = "ended_date"
        case duration
        case result
        case error
        case triggeredBy = "triggered_by"
        case environment
        case instanceConfiguration = "instance_configuration"
    }
    
    // MARK: - Initialization
    
    public init(
        id: String,
        uuid: String,
        applicationId: String,
        action: String,
        state: String,
        type: String? = nil,
        commit: String? = nil,
        repository: String? = nil,
        branch: String? = nil,
        createdAt: Date,
        startedAt: Date? = nil,
        endedAt: Date? = nil,
        duration: Int? = nil,
        result: String? = nil,
        error: String? = nil,
        triggeredBy: String? = nil,
        environment: [String: String]? = nil,
        instanceConfiguration: CCInstanceConfiguration? = nil
    ) {
        self.id = id
        self.uuid = uuid
        self.applicationId = applicationId
        self.action = action
        self.state = state
        self.type = type
        self.commit = commit
        self.repository = repository
        self.branch = branch
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.duration = duration
        self.result = result
        self.error = error
        self.triggeredBy = triggeredBy
        self.environment = environment
        self.instanceConfiguration = instanceConfiguration
    }
}

// MARK: - CCDeployment CRUD Models

/// Model for creating a new deployment
public struct CCDeploymentCreate: Codable {
    public let commit: String?
    public let repository: String?
    public let branch: String?
    public let environment: [String: String]?
    
    public init(
        commit: String? = nil,
        repository: String? = nil,
        branch: String? = nil,
        environment: [String: String]? = nil
    ) {
        self.commit = commit
        self.repository = repository
        self.branch = branch
        self.environment = environment
    }
}

/// Model for cancelling a deployment
public struct CCDeploymentCancel: Codable {
    public let reason: String?
    
    public init(reason: String? = nil) {
        self.reason = reason
    }
}

// MARK: - CCDeployment Log Models

/// Represents a deployment log entry
public struct CCDeploymentLog: Codable, Identifiable {
    public let id: String
    public let deploymentId: String
    public let timestamp: Date
    public let level: String
    public let message: String
    public let source: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case deploymentId = "deployment_id"
        case timestamp
        case level
        case message
        case source
    }
    
    /// Display-friendly log level with icon
    public var displayLevel: String {
        switch level.uppercased() {
        case "ERROR":
            return "❌ ERROR"
        case "WARN", "WARNING":
            return "⚠️ WARN"
        case "INFO":
            return "ℹ️ INFO"
        case "DEBUG":
            return "🐛 DEBUG"
        default:
            return "📝 \(level)"
        }
    }
    
    public init(
        id: String,
        deploymentId: String,
        timestamp: Date,
        level: String,
        message: String,
        source: String? = nil
    ) {
        self.id = id
        self.deploymentId = deploymentId
        self.timestamp = timestamp
        self.level = level
        self.message = message
        self.source = source
    }
}

// MARK: - CCInstance Configuration Models

/// Instance configuration for deployments
public struct CCInstanceConfiguration: Codable, Equatable {
    public let instanceType: String
    public let instanceVariant: String?
    public let instanceCount: Int
    public let minInstances: Int?
    public let maxInstances: Int?
    public let flavor: String?
    
    enum CodingKeys: String, CodingKey {
        case instanceType = "instance_type"
        case instanceVariant = "instance_variant"
        case instanceCount = "instance_count"
        case minInstances = "min_instances"
        case maxInstances = "max_instances"
        case flavor
    }
    
    /// Display-friendly instance configuration
    public var displayConfiguration: String {
        if let variant = instanceVariant {
            return "\(instanceType)-\(variant) x\(instanceCount)"
        } else {
            return "\(instanceType) x\(instanceCount)"
        }
    }
    
    public init(
        instanceType: String,
        instanceVariant: String? = nil,
        instanceCount: Int,
        minInstances: Int? = nil,
        maxInstances: Int? = nil,
        flavor: String? = nil
    ) {
        self.instanceType = instanceType
        self.instanceVariant = instanceVariant
        self.instanceCount = instanceCount
        self.minInstances = minInstances
        self.maxInstances = maxInstances
        self.flavor = flavor
    }
}

// MARK: - CCDeployment Analytics Models

/// Deployment statistics for analytics
public struct CCDeploymentStats: Codable, Identifiable {
    public let id: String
    public let applicationId: String
    public let period: String
    public let totalDeployments: Int
    public let successfulDeployments: Int
    public let failedDeployments: Int
    public let cancelledDeployments: Int
    public let averageDuration: Double?
    public let successRate: Double
    
    enum CodingKeys: String, CodingKey {
        case id
        case applicationId = "app_id"
        case period
        case totalDeployments = "total_deployments"
        case successfulDeployments = "successful_deployments"
        case failedDeployments = "failed_deployments"
        case cancelledDeployments = "cancelled_deployments"
        case averageDuration = "average_duration"
        case successRate = "success_rate"
    }
    
    /// Display-friendly success rate
    public var displaySuccessRate: String {
        return String(format: "%.1f%%", successRate * 100)
    }
    
    /// Display-friendly average duration
    public var displayAverageDuration: String? {
        guard let duration = averageDuration else { return nil }
        
        if duration < 60 {
            return String(format: "%.0fs", duration)
        } else if duration < 3600 {
            let minutes = duration / 60
            return String(format: "%.1fm", minutes)
        } else {
            let hours = duration / 3600
            return String(format: "%.1fh", hours)
        }
    }
    
    public init(
        id: String,
        applicationId: String,
        period: String,
        totalDeployments: Int,
        successfulDeployments: Int,
        failedDeployments: Int,
        cancelledDeployments: Int,
        averageDuration: Double? = nil,
        successRate: Double
    ) {
        self.id = id
        self.applicationId = applicationId
        self.period = period
        self.totalDeployments = totalDeployments
        self.successfulDeployments = successfulDeployments
        self.failedDeployments = failedDeployments
        self.cancelledDeployments = cancelledDeployments
        self.averageDuration = averageDuration
        self.successRate = successRate
    }
}

// MARK: - CCDeployment Webhook Models

/// Webhook payload for deployment events
public struct CCDeploymentWebhook: Codable {
    public let event: String
    public let deployment: CCDeployment
    public let application: CCApplication
    public let timestamp: Date
    
    /// Event type with icon
    public var displayEvent: String {
        switch event.uppercased() {
        case "DEPLOYMENT_STARTED":
            return "🚀 Deployment Started"
        case "DEPLOYMENT_SUCCESS":
            return "✅ Deployment Success"
        case "DEPLOYMENT_FAILED":
            return "❌ Deployment Failed"
        case "DEPLOYMENT_CANCELLED":
            return "⚪ Deployment Cancelled"
        default:
            return "📡 \(event)"
        }
    }
    
    public init(
        event: String,
        deployment: CCDeployment,
        application: CCApplication,
        timestamp: Date
    ) {
        self.event = event
        self.deployment = deployment
        self.application = application
        self.timestamp = timestamp
    }
}

// MARK: - CCDeployment Filter Models

/// Filters for deployment queries
public struct CCDeploymentFilter: Codable {
    public let states: [String]?
    public let actions: [String]?
    public let since: Date?
    public let until: Date?
    public let commit: String?
    public let branch: String?
    public let triggeredBy: String?
    public let limit: Int?
    public let offset: Int?
    
    enum CodingKeys: String, CodingKey {
        case states
        case actions
        case since
        case until
        case commit
        case branch
        case triggeredBy = "triggered_by"
        case limit
        case offset
    }
    
    public init(
        states: [String]? = nil,
        actions: [String]? = nil,
        since: Date? = nil,
        until: Date? = nil,
        commit: String? = nil,
        branch: String? = nil,
        triggeredBy: String? = nil,
        limit: Int? = nil,
        offset: Int? = nil
    ) {
        self.states = states
        self.actions = actions
        self.since = since
        self.until = until
        self.commit = commit
        self.branch = branch
        self.triggeredBy = triggeredBy
        self.limit = limit
        self.offset = offset
    }
} 