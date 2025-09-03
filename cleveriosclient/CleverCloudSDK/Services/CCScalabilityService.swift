import Foundation

/// Service for managing application scalability following clever-tools patterns
public class CCScalabilityService {
    
    // MARK: - Core mergeScalabilityParameters Implementation
    
    /// Merge scalability parameters with existing instance configuration
    /// Exact implementation of clever-tools mergeScalabilityParameters function
    /// - Parameters:
    ///   - scalabilityParameters: The new parameters to apply
    ///   - instance: The existing instance configuration
    /// - Returns: Updated instance configuration with merged parameters
    public static func mergeScalabilityParameters(_ scalabilityParameters: CCScalabilityParams, instance: CCInstanceConfig) -> CCInstanceConfig {
        let flavors = CCFlavor.availableFlavorNames
        var updatedInstance = instance
        
        // Handle minFlavor
        if let minFlavor = scalabilityParameters.minFlavor {
            updatedInstance.minFlavor = minFlavor
            // If minFlavor index > maxFlavor index, adjust maxFlavor
            if let minIndex = flavors.firstIndex(of: updatedInstance.minFlavor),
               let maxIndex = flavors.firstIndex(of: updatedInstance.maxFlavor),
               minIndex > maxIndex {
                updatedInstance.maxFlavor = updatedInstance.minFlavor
            }
        }
        
        // Handle maxFlavor  
        if let maxFlavor = scalabilityParameters.maxFlavor {
            updatedInstance.maxFlavor = maxFlavor
            // If minFlavor index > maxFlavor index AND minFlavor was not set, adjust minFlavor
            if let minIndex = flavors.firstIndex(of: updatedInstance.minFlavor),
               let maxIndex = flavors.firstIndex(of: updatedInstance.maxFlavor),
               minIndex > maxIndex,
               scalabilityParameters.minFlavor == nil {
                updatedInstance.minFlavor = updatedInstance.maxFlavor
            }
        }
        
        // Handle minInstances
        if let minInstances = scalabilityParameters.minInstances {
            updatedInstance.minInstances = minInstances
            // If minInstances > maxInstances, adjust maxInstances
            if updatedInstance.minInstances > updatedInstance.maxInstances {
                updatedInstance.maxInstances = updatedInstance.minInstances
            }
        }
        
        // Handle maxInstances
        if let maxInstances = scalabilityParameters.maxInstances {
            updatedInstance.maxInstances = maxInstances
            // If minInstances > maxInstances AND minInstances was not set, adjust minInstances
            if updatedInstance.minInstances > updatedInstance.maxInstances,
               scalabilityParameters.minInstances == nil {
                updatedInstance.minInstances = updatedInstance.maxInstances
            }
        }
        
        return updatedInstance
    }
    
    // MARK: - Validation Logic
    
    /// Validate scalability configuration following clever-tools validation rules
    /// - Parameter config: The scalability configuration to validate
    /// - Returns: Validation result with errors and warnings
    public static func validateScalabilityConfig(_ config: CCScalabilityConfig) -> CCValidationResult {
        var errors: [String] = []
        var warnings: [String] = []
        
        // Validate flavor relationships
        if let minFlavor = config.flavorScaling.minFlavor,
           let maxFlavor = config.flavorScaling.maxFlavor {
            let flavors = CCFlavor.availableFlavorNames
            if let minIndex = flavors.firstIndex(of: minFlavor),
               let maxIndex = flavors.firstIndex(of: maxFlavor),
               minIndex > maxIndex {
                errors.append("min-flavor can't be a greater flavor than max-flavor")
            }
        }
        
        // Validate instance relationships
        if let minInstances = config.instanceScaling.minInstances,
           let maxInstances = config.instanceScaling.maxInstances {
            if minInstances > maxInstances {
                errors.append("min-instances can't be greater than max-instances")
            }
        }
        
        // Validate constraints
        if let maxInstances = config.instanceScaling.maxInstances {
            if maxInstances > config.constraints.maxAllowedInstances {
                errors.append("max-instances can't be greater than \(config.constraints.maxAllowedInstances)")
            }
        }
        
        // Check for strategy conflicts
        switch config.strategy {
        case .fixed:
            if config.flavorScaling.enabled && config.instanceScaling.enabled {
                warnings.append("Fixed strategy with both flavor and instance scaling enabled")
            }
        case .horizontal:
            if config.flavorScaling.enabled {
                warnings.append("Horizontal strategy with flavor scaling enabled")
            }
        case .vertical:
            if config.instanceScaling.enabled {
                warnings.append("Vertical strategy with instance scaling enabled")
            }
        case .fullAuto:
            if !config.flavorScaling.enabled && !config.instanceScaling.enabled {
                warnings.append("Full-auto strategy with no scaling enabled")
            }
        }
        
        return CCValidationResult(isValid: errors.isEmpty, errors: errors, warnings: warnings)
    }
    
    // MARK: - Scalability Parameters Validation (matching clever-tools validateOptions)
    
    /// Validate scalability parameters following clever-tools validateOptions logic
    /// - Parameter params: The scalability parameters to validate
    /// - Returns: Validation result
    public static func validateScalabilityParams(_ params: CCScalabilityParams) -> CCValidationResult {
        var errors: [String] = []
        var warnings: [String] = []
        
        // Check if at least one option is provided
        if params.minFlavor == nil && params.maxFlavor == nil && 
           params.minInstances == nil && params.maxInstances == nil {
            errors.append("You should provide at least 1 option")
        }
        
        // Validate flavor relationships
        if let minFlavor = params.minFlavor,
           let maxFlavor = params.maxFlavor {
            let flavors = CCFlavor.availableFlavorNames
            if let minIndex = flavors.firstIndex(of: minFlavor),
               let maxIndex = flavors.firstIndex(of: maxFlavor),
               minIndex > maxIndex {
                errors.append("min-flavor can't be a greater flavor than max-flavor")
            }
        }
        
        // Validate instance relationships
        if let minInstances = params.minInstances,
           let maxInstances = params.maxInstances {
            if minInstances > maxInstances {
                errors.append("min-instances can't be greater than max-instances")
            }
        }
        
        // Validate individual flavors
        if let minFlavor = params.minFlavor,
           !CCFlavor.availableFlavorNames.contains(minFlavor) {
            errors.append("Invalid min-flavor: \(minFlavor)")
        }
        
        if let maxFlavor = params.maxFlavor,
           !CCFlavor.availableFlavorNames.contains(maxFlavor) {
            errors.append("Invalid max-flavor: \(maxFlavor)")
        }
        
        // Validate instance counts
        if let minInstances = params.minInstances,
           minInstances < 1 {
            errors.append("min-instances must be at least 1")
        }
        
        if let maxInstances = params.maxInstances,
           maxInstances < 1 {
            errors.append("max-instances must be at least 1")
        }
        
        return CCValidationResult(isValid: errors.isEmpty, errors: errors, warnings: warnings)
    }
    
    // MARK: - Preset Management
    
    /// Get default scalability presets
    /// - Returns: Array of predefined scalability presets
    public static func getDefaultPresets() -> [CCScalabilityPreset] {
        return [
            // Development preset
            CCScalabilityPreset(
                id: "dev-fixed",
                name: "Development Fixed",
                description: "Fixed single instance for development",
                category: .development,
                configuration: CCScalabilityConfig(
                    strategy: .fixed,
                    flavorScaling: CCFlavorScaling(minFlavor: "S", maxFlavor: "S", enabled: false),
                    instanceScaling: CCInstanceScaling(minInstances: 1, maxInstances: 1, enabled: false)
                ),
                applicableTypes: ["node", "php", "python", "ruby"],
                tags: ["development", "single-instance"]
            ),
            
            // Staging preset
            CCScalabilityPreset(
                id: "staging-horizontal",
                name: "Staging Horizontal",
                description: "Horizontal scaling for staging environment",
                category: .staging,
                configuration: CCScalabilityConfig(
                    strategy: .horizontal,
                    flavorScaling: CCFlavorScaling(minFlavor: "S", maxFlavor: "S", enabled: false),
                    instanceScaling: CCInstanceScaling(minInstances: 1, maxInstances: 3, enabled: true)
                ),
                applicableTypes: ["node", "php", "python", "ruby", "java"],
                tags: ["staging", "horizontal-scaling"]
            ),
            
            // Production preset
            CCScalabilityPreset(
                id: "prod-full-auto",
                name: "Production Full Auto",
                description: "Full auto-scaling for production workloads",
                category: .production,
                configuration: CCScalabilityConfig(
                    strategy: .fullAuto,
                    flavorScaling: CCFlavorScaling(minFlavor: "S", maxFlavor: "L", enabled: true),
                    instanceScaling: CCInstanceScaling(minInstances: 2, maxInstances: 10, enabled: true)
                ),
                applicableTypes: ["node", "php", "python", "ruby", "java", "go"],
                tags: ["production", "auto-scaling", "high-availability"]
            ),
            
            // High Traffic preset
            CCScalabilityPreset(
                id: "high-traffic",
                name: "High Traffic",
                description: "Optimized for high traffic applications",
                category: .highTraffic,
                configuration: CCScalabilityConfig(
                    strategy: .fullAuto,
                    flavorScaling: CCFlavorScaling(minFlavor: "M", maxFlavor: "2XL", enabled: true),
                    instanceScaling: CCInstanceScaling(minInstances: 3, maxInstances: 20, enabled: true)
                ),
                applicableTypes: ["node", "php", "python", "ruby", "java", "go"],
                tags: ["high-traffic", "performance", "auto-scaling"]
            ),
            
            // Cost Optimized preset
            CCScalabilityPreset(
                id: "cost-optimized",
                name: "Cost Optimized",
                description: "Optimized for cost efficiency",
                category: .costOptimized,
                configuration: CCScalabilityConfig(
                    strategy: .horizontal,
                    flavorScaling: CCFlavorScaling(minFlavor: "XS", maxFlavor: "S", enabled: false),
                    instanceScaling: CCInstanceScaling(minInstances: 1, maxInstances: 5, enabled: true)
                ),
                applicableTypes: ["node", "php", "python", "ruby", "static"],
                tags: ["cost-optimized", "small-instances"]
            )
        ]
    }
    
    // MARK: - Cost Estimation
    
    /// Calculate estimated costs for scaling configuration
    /// - Parameter config: The scalability configuration
    /// - Returns: Cost estimation
    public static func calculateScalingCost(_ config: CCScalabilityConfig) -> CCCostEstimate {
        // Simple cost calculation based on flavor pricing
        let flavorPricing: [String: Double] = [
            "pico": 0.0,
            "nano": 0.0,
            "XS": 0.3,
            "S": 0.6,
            "M": 1.7,
            "L": 3.4,
            "XL": 6.9,
            "2XL": 13.8,
            "3XL": 27.5
        ]
        
        let minFlavorCost = flavorPricing[config.flavorScaling.minFlavor ?? "S"] ?? 0.6
        let maxFlavorCost = flavorPricing[config.flavorScaling.maxFlavor ?? "S"] ?? 0.6
        
        let minInstances = config.instanceScaling.minInstances ?? 1
        let maxInstances = config.instanceScaling.maxInstances ?? 1
        
        let monthlyMin = minFlavorCost * Double(minInstances) * 24 * 30
        let monthlyMax = maxFlavorCost * Double(maxInstances) * 24 * 30
        
        let breakdown = [
            "min_cost": monthlyMin,
            "max_cost": monthlyMax,
            "min_instances": Double(minInstances),
            "max_instances": Double(maxInstances)
        ]
        
        return CCCostEstimate(
            monthlyMin: monthlyMin,
            monthlyMax: monthlyMax,
            currency: "EUR",
            breakdown: breakdown
        )
    }
    
    // MARK: - Scaling Strategy Detection
    
    /// Detect scaling strategy from configuration
    /// - Parameter config: The scalability configuration
    /// - Returns: Detected scaling strategy
    public static func detectScalingStrategy(_ config: CCScalabilityConfig) -> ScalingStrategy {
        let flavorScaling = config.flavorScaling.enabled
        let instanceScaling = config.instanceScaling.enabled
        
        switch (flavorScaling, instanceScaling) {
        case (false, false):
            return .fixed
        case (false, true):
            return .horizontal
        case (true, false):
            return .vertical
        case (true, true):
            return .fullAuto
        }
    }
} 