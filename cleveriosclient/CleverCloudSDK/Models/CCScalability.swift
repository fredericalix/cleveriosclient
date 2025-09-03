import Foundation

// MARK: - Scalability Models Following Clever-Tools Implementation

/// Scaling strategy options following clever-tools patterns
public enum ScalingStrategy: String, CaseIterable {
    case fixed = "fixed"
    case horizontal = "horizontal"
    case vertical = "vertical"
    case fullAuto = "full-auto"
}

/// Preset categories for common scaling configurations
public enum PresetCategory: String, CaseIterable {
    case development = "Development"
    case staging = "Staging"
    case production = "Production"
    case highTraffic = "High Traffic"
    case costOptimized = "Cost Optimized"
}

// MARK: - Flavor Management Extension

/// Extension to CCFlavor for scalability management
extension CCFlavor {
    /// Get all available flavors as strings (matching clever-tools listAvailableFlavors)
    public static var availableFlavorNames: [String] {
        return ["pico", "nano", "XS", "S", "M", "L", "XL", "2XL", "3XL"]
    }
    
    /// Get the index of a flavor name for comparison (higher index = more powerful)
    public static func flavorIndex(_ flavorName: String) -> Int {
        return availableFlavorNames.firstIndex(of: flavorName) ?? 0
    }
    
    /// Compare two flavor names by power level
    public static func isFlavorGreater(_ flavor1: String, than flavor2: String) -> Bool {
        return flavorIndex(flavor1) > flavorIndex(flavor2)
    }
    
    /// Check if a flavor name is valid
    public static func isValidFlavor(_ flavorName: String) -> Bool {
        return availableFlavorNames.contains(flavorName)
    }
}

/// Scalability parameters for merging (matching clever-tools scalabilityParameters)
public struct CCScalabilityParams {
    public let minFlavor: String?
    public let maxFlavor: String?
    public let minInstances: Int?
    public let maxInstances: Int?
    
    public init(minFlavor: String? = nil, maxFlavor: String? = nil, minInstances: Int? = nil, maxInstances: Int? = nil) {
        self.minFlavor = minFlavor
        self.maxFlavor = maxFlavor
        self.minInstances = minInstances
        self.maxInstances = maxInstances
    }
}

/// Instance configuration (matching clever-tools instance object)
public struct CCInstanceConfig {
    public var minFlavor: String
    public var maxFlavor: String
    public var minInstances: Int
    public var maxInstances: Int
    
    public init(minFlavor: String, maxFlavor: String, minInstances: Int, maxInstances: Int) {
        self.minFlavor = minFlavor
        self.maxFlavor = maxFlavor
        self.minInstances = minInstances
        self.maxInstances = maxInstances
    }
}

/// Flavor scaling configuration
public struct CCFlavorScaling: Equatable {
    public var minFlavor: String?
    public var maxFlavor: String?
    public var enabled: Bool
    
    public init(minFlavor: String? = nil, maxFlavor: String? = nil, enabled: Bool = false) {
        self.minFlavor = minFlavor
        self.maxFlavor = maxFlavor
        self.enabled = enabled
    }
}

/// Instance scaling configuration
public struct CCInstanceScaling: Equatable {
    public var minInstances: Int?
    public var maxInstances: Int?
    public var enabled: Bool
    
    public init(minInstances: Int? = nil, maxInstances: Int? = nil, enabled: Bool = false) {
        self.minInstances = minInstances
        self.maxInstances = maxInstances
        self.enabled = enabled
    }
}

/// Build flavor configuration
public struct CCBuildFlavorConfig: Equatable {
    public let flavor: String
    public let enabled: Bool
    
    public init(flavor: String, enabled: Bool = false) {
        self.flavor = flavor
        self.enabled = enabled
    }
}

/// Scaling constraints and validation
public struct CCScalingConstraints: Equatable {
    public let maxAllowedInstances: Int
    public let allowedFlavors: [String]
    public let minFlavorIndex: Int
    public let maxFlavorIndex: Int
    
    public init(maxAllowedInstances: Int = 40, allowedFlavors: [String] = ["pico", "nano", "XS", "S", "M", "L", "XL", "2XL", "3XL"], minFlavorIndex: Int = 0, maxFlavorIndex: Int = 8) {
        self.maxAllowedInstances = maxAllowedInstances
        self.allowedFlavors = allowedFlavors
        self.minFlavorIndex = minFlavorIndex
        self.maxFlavorIndex = maxFlavorIndex
    }
}

/// Validation result for scalability configuration
public struct CCValidationResult {
    public let isValid: Bool
    public let errors: [String]
    public let warnings: [String]
    
    public init(isValid: Bool, errors: [String] = [], warnings: [String] = []) {
        self.isValid = isValid
        self.errors = errors
        self.warnings = warnings
    }
}

/// Cost estimation for scaling configuration
public struct CCCostEstimate {
    public let monthlyMin: Double
    public let monthlyMax: Double
    public let currency: String
    public let breakdown: [String: Double]
    
    public init(monthlyMin: Double, monthlyMax: Double, currency: String = "EUR", breakdown: [String: Double] = [:]) {
        self.monthlyMin = monthlyMin
        self.monthlyMax = monthlyMax
        self.currency = currency
        self.breakdown = breakdown
    }
}

/// Scalability preset for common configurations
public struct CCScalabilityPreset {
    public let id: String
    public let name: String
    public let description: String
    public let category: PresetCategory
    public let configuration: CCScalabilityConfig
    public let applicableTypes: [String]
    public let tags: [String]
    
    public init(id: String, name: String, description: String, category: PresetCategory, configuration: CCScalabilityConfig, applicableTypes: [String] = [], tags: [String] = []) {
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.configuration = configuration
        self.applicableTypes = applicableTypes
        self.tags = tags
    }
}

/// Complete scalability configuration
public struct CCScalabilityConfig: Equatable {
    public var strategy: ScalingStrategy
    public var flavorScaling: CCFlavorScaling
    public var instanceScaling: CCInstanceScaling
    public var buildFlavors: [String: CCBuildFlavorConfig]
    public var constraints: CCScalingConstraints
    public var separateBuild: Bool
    public var buildFlavor: String?
    
    public init(strategy: ScalingStrategy, flavorScaling: CCFlavorScaling, instanceScaling: CCInstanceScaling, buildFlavors: [String: CCBuildFlavorConfig] = [:], constraints: CCScalingConstraints = CCScalingConstraints(), separateBuild: Bool = false, buildFlavor: String? = nil) {
        self.strategy = strategy
        self.flavorScaling = flavorScaling
        self.instanceScaling = instanceScaling
        self.buildFlavors = buildFlavors
        self.constraints = constraints
        self.separateBuild = separateBuild
        self.buildFlavor = buildFlavor
    }
} 