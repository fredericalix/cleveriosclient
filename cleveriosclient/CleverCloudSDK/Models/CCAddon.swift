import Foundation
import Combine

// MARK: - CCAddon Models

/// Represents a Clever Cloud add-on (database, cache, etc.)
public struct CCAddon: Codable, Identifiable, Equatable {
    
    // MARK: - Core Properties
    
    /// Unique add-on identifier
    public let id: String
    
    /// Add-on display name
    public let name: String
    
    /// Add-on description
    public let description: String?
    
    /// Add-on provider information
    public let provider: CCAddonProvider
    
    /// Add-on plan information
    public let plan: CCAddonPlan
    
    /// Add-on region/zone
    public let region: String
    
    /// Creation timestamp
    public let createdAt: Date?
    
    /// Add-on status (e.g., "running", "creating", "error")
    public let status: String?
    
    /// Add-on configuration URL
    public let configUrl: String?
    
    /// Add-on real ID (internal Clever Cloud ID)
    public let realId: String?
    
    /// Zone ID where the add-on is deployed
    public let zoneId: String?
    
    /// Environment variables provided by this add-on
    public let env: [String: String]?
    
    // MARK: - Computed Properties
    
    /// Display name for the add-on
    public var displayName: String {
        return name.isEmpty ? "Unnamed Add-on" : name
    }
    
    /// Provider display name with icon
    public var providerDisplayName: String {
        switch provider.id.lowercased() {
        case "postgresql-addon", "postgres":
            return "🐘 PostgreSQL"
        case "mysql-addon":
            return "🐬 MySQL"
        case "redis-addon":
            return "🔴 Redis"
        case "mongodb-addon", "mongo":
            return "🍃 MongoDB"
        case "elasticsearch-addon":
            return "🔍 Elasticsearch"
        case "jenkins-addon":
            return "⚙️ Jenkins"
        case "pulsar-addon":
            return "📡 Pulsar"
        case "materia-addon":
            return "🔧 Materia KV"
        default:
            return "📦 \(provider.name)"
        }
    }
    
    /// Status color for UI display
    public var statusColor: String {
        switch status?.lowercased() ?? "unknown" {
        case "running":
            return "green"
        case "creating", "starting":
            return "orange"
        case "error", "failed":
            return "red"
        case "stopped":
            return "gray"
        default:
            return "blue"
        }
    }
    
    // MARK: - Coding Keys
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case provider
        case plan
        case region
        case createdAt = "creation_date"
        case status
        case configUrl = "config_url"
        case realId = "real_id"
        case zoneId
        case env
    }
    
    // MARK: - Initialization
    
    public init(
        id: String,
        name: String,
        description: String? = nil,
        provider: CCAddonProvider,
        plan: CCAddonPlan,
        region: String,
        createdAt: Date? = nil,
        status: String? = nil,
        configUrl: String? = nil,
        realId: String? = nil,
        zoneId: String? = nil,
        env: [String: String]? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.provider = provider
        self.plan = plan
        self.region = region
        self.createdAt = createdAt
        self.status = status
        self.configUrl = configUrl
        self.realId = realId
        self.zoneId = zoneId
        self.env = env
    }
}

// MARK: - CCAddon CRUD Models

/// Model for creating a new add-on
public struct CCAddonCreate: Codable {
    public let providerId: String
    public let name: String
    public let planId: String
    public let region: String
    public let options: [String: String]?
    
    enum CodingKeys: String, CodingKey {
        case providerId = "provider_id"
        case name
        case planId = "plan"
        case region
        case options
    }
    
    public init(
        providerId: String,
        name: String,
        planId: String,
        region: String,
        options: [String: String]? = nil
    ) {
        self.providerId = providerId
        self.name = name
        self.planId = planId
        self.region = region
        self.options = options
    }
}

/// Model for updating an add-on
public struct CCAddonUpdate: Codable {
    public let name: String?
    public let plan: String?
    
    public init(name: String? = nil, plan: String? = nil) {
        self.name = name
        self.plan = plan
    }
}

// MARK: - CCAddonProvider Models

/// Model for add-on provider information
public struct CCAddonProvider: Codable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let shortDesc: String?
    public let longDesc: String?
    public let logoUrl: String?
    public let website: String?
    public let analyticsId: String?
    public let supportEmail: String?
    public let googlePlusName: String?
    public let twitterName: String?
    public let status: String?
    public let openInNewTab: Bool?
    public let canUpgrade: Bool?
    public let comingSoon: Bool?
    public let regions: [String]?
    public let plans: [CCAddonPlan]?
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case shortDesc = "short_desc"
        case longDesc = "long_desc"
        case logoUrl = "logo_url"
        case website
        case analyticsId = "analytics_id"
        case supportEmail = "support_email"
        case googlePlusName = "google_plus_name"
        case twitterName = "twitter_name"
        case status
        case openInNewTab = "open_in_new_tab"
        case canUpgrade = "can_upgrade"
        case comingSoon = "coming_soon"
        case regions
        case plans
    }
    
    public init(
        id: String,
        name: String,
        shortDesc: String? = nil,
        longDesc: String? = nil,
        logoUrl: String? = nil,
        website: String? = nil,
        analyticsId: String? = nil,
        supportEmail: String? = nil,
        googlePlusName: String? = nil,
        twitterName: String? = nil,
        status: String? = nil,
        openInNewTab: Bool? = nil,
        canUpgrade: Bool? = nil,
        comingSoon: Bool? = nil,
        regions: [String]? = nil,
        plans: [CCAddonPlan]? = nil
    ) {
        self.id = id
        self.name = name
        self.shortDesc = shortDesc
        self.longDesc = longDesc
        self.logoUrl = logoUrl
        self.website = website
        self.analyticsId = analyticsId
        self.supportEmail = supportEmail
        self.googlePlusName = googlePlusName
        self.twitterName = twitterName
        self.status = status
        self.openInNewTab = openInNewTab
        self.canUpgrade = canUpgrade
        self.comingSoon = comingSoon
        self.regions = regions
        self.plans = plans
    }
}

// MARK: - CCAddonPlan Models

/// Model for add-on plan information
public struct CCAddonPlan: Codable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let slug: String
    public let price: Double
    public let features: [CCAddonFeature]?
    
    public init(id: String, name: String, slug: String, price: Double, features: [CCAddonFeature]? = nil) {
        self.id = id
        self.name = name
        self.slug = slug
        self.price = price
        self.features = features
    }
}

/// Model for add-on plan feature
public struct CCAddonFeature: Codable, Identifiable, Equatable {
    public let name: String
    public let value: String?
    
    /// Generate a unique ID from the name for Identifiable conformance
    public var id: String {
        return name
    }
    
    public init(name: String, value: String? = nil) {
        self.name = name
        self.value = value
    }
}

// MARK: - CCAddon Service Helper Models
// Note: CCAddonApplicationLink, CCAddonSSOData, and CCAddonWithProvider are defined in CCAddonService.swift

// MARK: - CCAddon Migration Models

/// Model for migrating add-ons between organizations
public struct CCAddonMigration: Codable {
    public let addonId: String
    public let targetOrganizationId: String
    public let targetRegion: String?
    public let preserveData: Bool
    
    enum CodingKeys: String, CodingKey {
        case addonId = "addon_id"
        case targetOrganizationId = "target_organization_id"
        case targetRegion = "target_region"
        case preserveData = "preserve_data"
    }
    
    public init(
        addonId: String,
        targetOrganizationId: String,
        targetRegion: String? = nil,
        preserveData: Bool = true
    ) {
        self.addonId = addonId
        self.targetOrganizationId = targetOrganizationId
        self.targetRegion = targetRegion
        self.preserveData = preserveData
    }
}

// MARK: - CCAddon Analytics Models

/// Model for add-on usage analytics
public struct CCAddonAnalytics: Codable, Identifiable {
    public let id: String
    public let addonId: String
    public let period: String
    public let metrics: CCAddonMetrics
    public let costs: CCAddonCosts?
    
    enum CodingKeys: String, CodingKey {
        case id
        case addonId = "addon_id"
        case period
        case metrics
        case costs
    }
    
    public init(
        id: String,
        addonId: String,
        period: String,
        metrics: CCAddonMetrics,
        costs: CCAddonCosts? = nil
    ) {
        self.id = id
        self.addonId = addonId
        self.period = period
        self.metrics = metrics
        self.costs = costs
    }
}

/// Model for add-on performance metrics
public struct CCAddonMetrics: Codable {
    public let connections: Int?
    public let queries: Int?
    public let dataSize: Int?
    public let memoryUsage: Double?
    public let cpuUsage: Double?
    public let networkIn: Int?
    public let networkOut: Int?
    
    enum CodingKeys: String, CodingKey {
        case connections
        case queries
        case dataSize = "data_size"
        case memoryUsage = "memory_usage"
        case cpuUsage = "cpu_usage"
        case networkIn = "network_in"
        case networkOut = "network_out"
    }
    
    public init(
        connections: Int? = nil,
        queries: Int? = nil,
        dataSize: Int? = nil,
        memoryUsage: Double? = nil,
        cpuUsage: Double? = nil,
        networkIn: Int? = nil,
        networkOut: Int? = nil
    ) {
        self.connections = connections
        self.queries = queries
        self.dataSize = dataSize
        self.memoryUsage = memoryUsage
        self.cpuUsage = cpuUsage
        self.networkIn = networkIn
        self.networkOut = networkOut
    }
}

/// Model for add-on cost information
public struct CCAddonCosts: Codable {
    public let totalCost: Double
    public let currency: String
    public let breakdown: [CCAddonCostItem]?
    
    enum CodingKeys: String, CodingKey {
        case totalCost = "total_cost"
        case currency
        case breakdown
    }
    
    public init(totalCost: Double, currency: String, breakdown: [CCAddonCostItem]? = nil) {
        self.totalCost = totalCost
        self.currency = currency
        self.breakdown = breakdown
    }
}

/// Model for individual add-on cost items
public struct CCAddonCostItem: Codable, Identifiable {
    public let id: String
    public let name: String
    public let cost: Double
    public let unit: String?
    
    public init(id: String, name: String, cost: Double, unit: String? = nil) {
        self.id = id
        self.name = name
        self.cost = cost
        self.unit = unit
    }
}

// MARK: - Add-on Consumption Models

/// Model for add-on consumption data
public struct CCAddonConsumption: Codable, Identifiable {
    public let id: String
    public let addonId: String
    public let period: String
    public let totalCost: Double
    public let currency: String
    public let usage: CCAddonUsage
    
    enum CodingKeys: String, CodingKey {
        case id
        case addonId = "addon_id"
        case period
        case totalCost = "total_cost"
        case currency
        case usage
    }
    
    public init(
        id: String,
        addonId: String,
        period: String,
        totalCost: Double,
        currency: String,
        usage: CCAddonUsage
    ) {
        self.id = id
        self.addonId = addonId
        self.period = period
        self.totalCost = totalCost
        self.currency = currency
        self.usage = usage
    }
}

/// Model for add-on usage details
public struct CCAddonUsage: Codable {
    public let storageGB: Double?
    public let dataTransferGB: Double?
    public let queries: Int?
    public let connections: Int?
    public let uptime: Double?
    
    enum CodingKeys: String, CodingKey {
        case storageGB = "storage_gb"
        case dataTransferGB = "data_transfer_gb"
        case queries
        case connections
        case uptime
    }
    
    public init(
        storageGB: Double? = nil,
        dataTransferGB: Double? = nil,
        queries: Int? = nil,
        connections: Int? = nil,
        uptime: Double? = nil
    ) {
        self.storageGB = storageGB
        self.dataTransferGB = dataTransferGB
        self.queries = queries
        self.connections = connections
        self.uptime = uptime
    }
}

// MARK: - Add-on Metric Time Series Models

/// Model for add-on metric data point
public struct CCAddonMetricPoint: Codable, Identifiable {
    public let id = UUID()
    public let timestamp: Date
    public let value: Double
    public let unit: String?
    
    enum CodingKeys: String, CodingKey {
        case timestamp
        case value
        case unit
    }
    
    public init(timestamp: Date, value: Double, unit: String? = nil) {
        self.timestamp = timestamp
        self.value = value
        self.unit = unit
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Handle timestamp
        if let timestampString = try? container.decode(String.self, forKey: .timestamp) {
            if let date = ISO8601DateFormatter().date(from: timestampString) {
                self.timestamp = date
            } else {
                self.timestamp = Date()
            }
        } else if let timestampDouble = try? container.decode(Double.self, forKey: .timestamp) {
            self.timestamp = Date(timeIntervalSince1970: timestampDouble)
        } else {
            self.timestamp = Date()
        }
        
        self.value = try container.decode(Double.self, forKey: .value)
        self.unit = try? container.decode(String.self, forKey: .unit)
    }
}

// MARK: - Add-on Real-time Metrics

/// Enhanced add-on metrics with real-time data
public struct CCAddonRealtimeMetrics: Codable {
    public let cpu: MetricSnapshot?
    public let memory: MetricSnapshot?
    public let connections: MetricSnapshot?
    public let queries: MetricSnapshot?
    public let storage: MetricSnapshot?
    public let networkIn: MetricSnapshot?
    public let networkOut: MetricSnapshot?
    
    public struct MetricSnapshot: Codable {
        public let current: Double
        public let average: Double
        public let peak: Double
        public let unit: String
        
        /// Formatted current value
        public var formattedCurrent: String {
            formatValue(current)
        }
        
        /// Formatted average value
        public var formattedAverage: String {
            formatValue(average)
        }
        
        /// Formatted peak value
        public var formattedPeak: String {
            formatValue(peak)
        }
        
        private func formatValue(_ value: Double) -> String {
            switch unit.lowercased() {
            case "percent", "%":
                return String(format: "%.1f%%", value)
            case "mb":
                return String(format: "%.1f MB", value)
            case "gb":
                return String(format: "%.2f GB", value)
            case "connections", "queries":
                return String(format: "%.0f", value)
            default:
                return String(format: "%.2f \(unit)", value)
            }
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case cpu
        case memory
        case connections
        case queries
        case storage
        case networkIn = "network_in"
        case networkOut = "network_out"
    }
} 