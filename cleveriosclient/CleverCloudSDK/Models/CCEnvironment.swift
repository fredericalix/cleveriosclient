import Foundation
import Combine

// MARK: - Environment Variable Models

/// Represents an environment variable for a Clever Cloud application
public struct CCEnvironmentVariable: Codable, Identifiable, Equatable {
    public let name: String
    public let value: String
    public let isSecret: Bool
    public let createdAt: Date?
    public let updatedAt: Date?
    
    /// Unique identifier generated from name
    public var id: String {
        return name
    }
    
    /// Display value (masked if secret)
    public var displayValue: String {
        return isSecret ? "••••••••" : value
    }
    
    /// Security level indicator
    public var securityLevel: String {
        return isSecret ? "🔒 Secret" : "📝 Public"
    }
    
    enum CodingKeys: String, CodingKey {
        case name
        case value
        case isSecret = "is_secret"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        value = try container.decode(String.self, forKey: .value)
        // Make isSecret optional with default value false (API doesn't always return it)
        isSecret = try container.decodeIfPresent(Bool.self, forKey: .isSecret) ?? false
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(value, forKey: .value)
        try container.encode(isSecret, forKey: .isSecret)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }
    
    public init(
        name: String,
        value: String,
        isSecret: Bool = false,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.name = name
        self.value = value
        self.isSecret = isSecret
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Model for creating/updating environment variables
public struct CCEnvironmentVariableUpdate: Codable {
    public let name: String
    public let value: String
    public let isSecret: Bool?
    
    enum CodingKeys: String, CodingKey {
        case name
        case value
        case isSecret = "is_secret"
    }
    
    public init(name: String, value: String, isSecret: Bool? = nil) {
        self.name = name
        self.value = value
        self.isSecret = isSecret
    }
}

/// Batch environment variables update
public struct CCEnvironmentVariablesBatch: Codable {
    public let variables: [CCEnvironmentVariableUpdate]
    public let deleteVariables: [String]?
    
    enum CodingKeys: String, CodingKey {
        case variables
        case deleteVariables = "delete_variables"
    }
    
    public init(variables: [CCEnvironmentVariableUpdate], deleteVariables: [String]? = nil) {
        self.variables = variables
        self.deleteVariables = deleteVariables
    }
}

// MARK: - Application Configuration Models

/// Represents application configuration settings
public struct CCApplicationConfig: Codable, Identifiable {
    public let id: String
    public let applicationId: String
    public let instanceConfiguration: CCAppInstanceConfiguration
    public let deploymentConfiguration: CCDeploymentConfiguration
    public let networkConfiguration: CCNetworkConfiguration?
    public let monitoringConfiguration: CCMonitoringConfiguration?
    public let backupConfiguration: CCBackupConfiguration?
    public let updatedAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id
        case applicationId = "application_id"
        case instanceConfiguration = "instance_configuration"
        case deploymentConfiguration = "deployment_configuration"
        case networkConfiguration = "network_configuration"
        case monitoringConfiguration = "monitoring_configuration"
        case backupConfiguration = "backup_configuration"
        case updatedAt = "updated_at"
    }
    
    public init(
        id: String,
        applicationId: String,
        instanceConfiguration: CCAppInstanceConfiguration,
        deploymentConfiguration: CCDeploymentConfiguration,
        networkConfiguration: CCNetworkConfiguration? = nil,
        monitoringConfiguration: CCMonitoringConfiguration? = nil,
        backupConfiguration: CCBackupConfiguration? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.applicationId = applicationId
        self.instanceConfiguration = instanceConfiguration
        self.deploymentConfiguration = deploymentConfiguration
        self.networkConfiguration = networkConfiguration
        self.monitoringConfiguration = monitoringConfiguration
        self.backupConfiguration = backupConfiguration
        self.updatedAt = updatedAt
    }
}

/// Application instance configuration settings  
public struct CCAppInstanceConfiguration: Codable {
    public let minInstances: Int
    public let maxInstances: Int
    public let flavor: String
    public let autoScaling: Bool
    public let autoScalingConfig: CCAutoScalingConfig?
    
    enum CodingKeys: String, CodingKey {
        case minInstances = "min_instances"
        case maxInstances = "max_instances"
        case flavor
        case autoScaling = "auto_scaling"
        case autoScalingConfig = "auto_scaling_config"
    }
    
    public init(
        minInstances: Int,
        maxInstances: Int,
        flavor: String,
        autoScaling: Bool = false,
        autoScalingConfig: CCAutoScalingConfig? = nil
    ) {
        self.minInstances = minInstances
        self.maxInstances = maxInstances
        self.flavor = flavor
        self.autoScaling = autoScaling
        self.autoScalingConfig = autoScalingConfig
    }
}

/// Auto-scaling configuration
public struct CCAutoScalingConfig: Codable {
    public let cpuThreshold: Double
    public let memoryThreshold: Double
    public let scaleUpCooldown: Int
    public let scaleDownCooldown: Int
    
    enum CodingKeys: String, CodingKey {
        case cpuThreshold = "cpu_threshold"
        case memoryThreshold = "memory_threshold"
        case scaleUpCooldown = "scale_up_cooldown"
        case scaleDownCooldown = "scale_down_cooldown"
    }
    
    public init(
        cpuThreshold: Double,
        memoryThreshold: Double,
        scaleUpCooldown: Int,
        scaleDownCooldown: Int
    ) {
        self.cpuThreshold = cpuThreshold
        self.memoryThreshold = memoryThreshold
        self.scaleUpCooldown = scaleUpCooldown
        self.scaleDownCooldown = scaleDownCooldown
    }
}

/// Deployment configuration settings
public struct CCDeploymentConfiguration: Codable {
    public let autoDeployment: Bool
    public let deploymentStrategy: String
    public let buildTimeout: Int
    public let healthCheckConfiguration: CCHealthCheckConfiguration?
    
    enum CodingKeys: String, CodingKey {
        case autoDeployment = "auto_deployment"
        case deploymentStrategy = "deployment_strategy"
        case buildTimeout = "build_timeout"
        case healthCheckConfiguration = "health_check_configuration"
    }
    
    public init(
        autoDeployment: Bool,
        deploymentStrategy: String,
        buildTimeout: Int,
        healthCheckConfiguration: CCHealthCheckConfiguration? = nil
    ) {
        self.autoDeployment = autoDeployment
        self.deploymentStrategy = deploymentStrategy
        self.buildTimeout = buildTimeout
        self.healthCheckConfiguration = healthCheckConfiguration
    }
}

/// Health check configuration
public struct CCHealthCheckConfiguration: Codable {
    public let enabled: Bool
    public let path: String?
    public let port: Int?
    public let interval: Int
    public let timeout: Int
    public let retries: Int
    
    public init(
        enabled: Bool,
        path: String? = nil,
        port: Int? = nil,
        interval: Int = 30,
        timeout: Int = 10,
        retries: Int = 3
    ) {
        self.enabled = enabled
        self.path = path
        self.port = port
        self.interval = interval
        self.timeout = timeout
        self.retries = retries
    }
}

/// Network configuration settings
public struct CCNetworkConfiguration: Codable {
    public let customDomains: [String]?
    public let sslConfiguration: CCSSLConfiguration?
    public let redirectHttpToHttps: Bool
    public let stickySession: Bool
    
    enum CodingKeys: String, CodingKey {
        case customDomains = "custom_domains"
        case sslConfiguration = "ssl_configuration"
        case redirectHttpToHttps = "redirect_http_to_https"
        case stickySession = "sticky_session"
    }
    
    public init(
        customDomains: [String]? = nil,
        sslConfiguration: CCSSLConfiguration? = nil,
        redirectHttpToHttps: Bool = true,
        stickySession: Bool = false
    ) {
        self.customDomains = customDomains
        self.sslConfiguration = sslConfiguration
        self.redirectHttpToHttps = redirectHttpToHttps
        self.stickySession = stickySession
    }
}

/// SSL configuration
public struct CCSSLConfiguration: Codable {
    public let enabled: Bool
    public let certificateId: String?
    public let autoRenewal: Bool
    
    enum CodingKeys: String, CodingKey {
        case enabled
        case certificateId = "certificate_id"
        case autoRenewal = "auto_renewal"
    }
    
    public init(enabled: Bool, certificateId: String? = nil, autoRenewal: Bool = true) {
        self.enabled = enabled
        self.certificateId = certificateId
        self.autoRenewal = autoRenewal
    }
}

/// Monitoring configuration
public struct CCMonitoringConfiguration: Codable {
    public let enabled: Bool
    public let alertsEnabled: Bool
    public let alertThresholds: CCAlertThresholds?
    public let notificationChannels: [String]?
    
    enum CodingKeys: String, CodingKey {
        case enabled
        case alertsEnabled = "alerts_enabled"
        case alertThresholds = "alert_thresholds"
        case notificationChannels = "notification_channels"
    }
    
    public init(
        enabled: Bool,
        alertsEnabled: Bool = false,
        alertThresholds: CCAlertThresholds? = nil,
        notificationChannels: [String]? = nil
    ) {
        self.enabled = enabled
        self.alertsEnabled = alertsEnabled
        self.alertThresholds = alertThresholds
        self.notificationChannels = notificationChannels
    }
}

/// Alert thresholds configuration
public struct CCAlertThresholds: Codable {
    public let cpuThreshold: Double
    public let memoryThreshold: Double
    public let errorRateThreshold: Double
    public let responseTimeThreshold: Double
    
    enum CodingKeys: String, CodingKey {
        case cpuThreshold = "cpu_threshold"
        case memoryThreshold = "memory_threshold"
        case errorRateThreshold = "error_rate_threshold"
        case responseTimeThreshold = "response_time_threshold"
    }
    
    public init(
        cpuThreshold: Double = 80.0,
        memoryThreshold: Double = 85.0,
        errorRateThreshold: Double = 5.0,
        responseTimeThreshold: Double = 1000.0
    ) {
        self.cpuThreshold = cpuThreshold
        self.memoryThreshold = memoryThreshold
        self.errorRateThreshold = errorRateThreshold
        self.responseTimeThreshold = responseTimeThreshold
    }
}

/// Backup configuration
public struct CCBackupConfiguration: Codable {
    public let enabled: Bool
    public let frequency: String
    public let retention: Int
    public let compressionEnabled: Bool
    
    enum CodingKeys: String, CodingKey {
        case enabled
        case frequency
        case retention
        case compressionEnabled = "compression_enabled"
    }
    
    public init(
        enabled: Bool,
        frequency: String = "daily",
        retention: Int = 7,
        compressionEnabled: Bool = true
    ) {
        self.enabled = enabled
        self.frequency = frequency
        self.retention = retention
        self.compressionEnabled = compressionEnabled
    }
}

// MARK: - Environment Management Response Models

/// Response for environment variables list
public struct CCEnvironmentVariablesResponse: Codable {
    public let variables: [CCEnvironmentVariable]
    public let count: Int
    
    public init(variables: [CCEnvironmentVariable], count: Int) {
        self.variables = variables
        self.count = count
    }
}

/// Response for configuration update
public struct CCConfigurationUpdateResponse: Codable {
    public let success: Bool
    public let message: String
    public let updatedConfig: CCApplicationConfig?
    
    enum CodingKeys: String, CodingKey {
        case success
        case message
        case updatedConfig = "updated_config"
    }
    
    public init(success: Bool, message: String, updatedConfig: CCApplicationConfig? = nil) {
        self.success = success
        self.message = message
        self.updatedConfig = updatedConfig
    }
}

/// Response from Clever Cloud API when scaling instances (redeploy)
public struct CCRedeployResponse: Codable {
    public let id: Int
    public let message: String
    public let type: String
    public let deploymentId: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case message
        case type
        case deploymentId
    }
    
    public init(id: Int, message: String, type: String, deploymentId: String) {
        self.id = id
        self.message = message
        self.type = type
        self.deploymentId = deploymentId
    }
}

/// Instance update request structure (follows clever-tools pattern)
/// Request structure for updating application configuration (following clever-tools pattern)
/// This matches exactly what clever-tools sends to updateApplication
public struct CCInstanceUpdateRequest: Codable {
    public let minFlavor: String
    public let maxFlavor: String
    public let minInstances: Int
    public let maxInstances: Int
    
    public init(minFlavor: String, maxFlavor: String, minInstances: Int, maxInstances: Int) {
        self.minFlavor = minFlavor
        self.maxFlavor = maxFlavor
        self.minInstances = minInstances
        self.maxInstances = maxInstances
    }
}

/// Scalability parameters for merging (following clever-tools mergeScalabilityParameters)
public struct CCScalabilityParameters {
    public let minFlavor: String?
    public let maxFlavor: String?
    public let minInstances: Int?
    public let maxInstances: Int?
    
    public init(minFlavor: String?, maxFlavor: String?, minInstances: Int?, maxInstances: Int?) {
        self.minFlavor = minFlavor
        self.maxFlavor = maxFlavor
        self.minInstances = minInstances
        self.maxInstances = maxInstances
    }
} 