import Testing
@testable import cleveriosclient

/// Unit tests for CCScalabilityService to verify clever-tools compatibility
@Suite("CCScalabilityService Tests")
struct CCScalabilityServiceTests {
    
    // MARK: - Test Cases from clever-tools scale.spec.js
    
    /// Test: should scale up max scalability
    /// From clever-tools: setting minFlavor to "M" should adjust maxFlavor to "M" if current maxFlavor is smaller
    @Test("Scale up max scalability")
    func scaleUpMaxScalability() {
        // Default instance configuration (S/S/5/5)
        let instance = CCInstanceConfig(
            minFlavor: "S",
            maxFlavor: "S", 
            minInstances: 5,
            maxInstances: 5
        )
        
        // Set minFlavor to M (which is higher than current maxFlavor S)
        let params = CCScalabilityParams(minFlavor: "M")
        
        let result = CCScalabilityService.mergeScalabilityParameters(params, instance: instance)
        
        // Should adjust maxFlavor to match minFlavor
        #expect(result.minFlavor == "M", "minFlavor should be set to M")
        #expect(result.maxFlavor == "M", "maxFlavor should be adjusted to M")
        #expect(result.minInstances == 5, "minInstances should remain unchanged")
        #expect(result.maxInstances == 5, "maxInstances should remain unchanged")
    }
    
    /// Test: should scale down min scalability 
    /// From clever-tools: setting maxFlavor to "XS" should adjust minFlavor to "XS" if current minFlavor is larger and minFlavor wasn't explicitly set
    @Test("Scale down min scalability")
    func scaleDownMinScalability() {
        // Default instance configuration (S/S/5/5)
        let instance = CCInstanceConfig(
            minFlavor: "S",
            maxFlavor: "S",
            minInstances: 5,
            maxInstances: 5
        )
        
        // Set maxFlavor to XS (which is lower than current minFlavor S)
        let params = CCScalabilityParams(maxFlavor: "XS")
        
        let result = CCScalabilityService.mergeScalabilityParameters(params, instance: instance)
        
        // Should adjust minFlavor to match maxFlavor since minFlavor was not explicitly set
        #expect(result.minFlavor == "XS", "minFlavor should be adjusted to XS")
        #expect(result.maxFlavor == "XS", "maxFlavor should be set to XS")
        #expect(result.minInstances == 5, "minInstances should remain unchanged")
        #expect(result.maxInstances == 5, "maxInstances should remain unchanged")
    }
    
    /// Test: should augment max instances
    /// From clever-tools: setting minInstances to 6 should adjust maxInstances to 6 if current maxInstances is smaller
    @Test("Augment max instances")
    func augmentMaxInstances() {
        // Default instance configuration (S/S/5/5)
        let instance = CCInstanceConfig(
            minFlavor: "S",
            maxFlavor: "S",
            minInstances: 5,
            maxInstances: 5
        )
        
        // Set minInstances to 6 (which is higher than current maxInstances 5)
        let params = CCScalabilityParams(minInstances: 6)
        
        let result = CCScalabilityService.mergeScalabilityParameters(params, instance: instance)
        
        // Should adjust maxInstances to match minInstances
        #expect(result.minFlavor == "S", "minFlavor should remain unchanged")
        #expect(result.maxFlavor == "S", "maxFlavor should remain unchanged")
        #expect(result.minInstances == 6, "minInstances should be set to 6")
        #expect(result.maxInstances == 6, "maxInstances should be adjusted to 6")
    }
    
    /// Test: should diminish min instances
    /// From clever-tools: setting maxInstances to 4 should adjust minInstances to 4 if current minInstances is larger and minInstances wasn't explicitly set
    @Test("Diminish min instances")
    func diminishMinInstances() {
        // Default instance configuration (S/S/5/5)
        let instance = CCInstanceConfig(
            minFlavor: "S",
            maxFlavor: "S",
            minInstances: 5,
            maxInstances: 5
        )
        
        // Set maxInstances to 4 (which is lower than current minInstances 5)
        let params = CCScalabilityParams(maxInstances: 4)
        
        let result = CCScalabilityService.mergeScalabilityParameters(params, instance: instance)
        
        // Should adjust minInstances to match maxInstances since minInstances was not explicitly set
        #expect(result.minFlavor == "S", "minFlavor should remain unchanged")
        #expect(result.maxFlavor == "S", "maxFlavor should remain unchanged")
        #expect(result.minInstances == 4, "minInstances should be adjusted to 4")
        #expect(result.maxInstances == 4, "maxInstances should be set to 4")
    }
    
    // MARK: - Additional Edge Cases
    
    /// Test: Both min and max flavor set explicitly - no automatic adjustment
    @Test("Both min and max flavor set explicitly")
    func bothMinMaxFlavorSet() {
        let instance = CCInstanceConfig(
            minFlavor: "S",
            maxFlavor: "S",
            minInstances: 1,
            maxInstances: 1
        )
        
        // Set both minFlavor and maxFlavor explicitly
        let params = CCScalabilityParams(minFlavor: "M", maxFlavor: "L")
        
        let result = CCScalabilityService.mergeScalabilityParameters(params, instance: instance)
        
        // Both should be set as specified, no automatic adjustment
        #expect(result.minFlavor == "M", "minFlavor should be set to M")
        #expect(result.maxFlavor == "L", "maxFlavor should be set to L")
    }
    
    /// Test: Both min and max instances set explicitly - no automatic adjustment
    @Test("Both min and max instances set explicitly")
    func bothMinMaxInstancesSet() {
        let instance = CCInstanceConfig(
            minFlavor: "S",
            maxFlavor: "S",
            minInstances: 1,
            maxInstances: 1
        )
        
        // Set both minInstances and maxInstances explicitly
        let params = CCScalabilityParams(minInstances: 2, maxInstances: 5)
        
        let result = CCScalabilityService.mergeScalabilityParameters(params, instance: instance)
        
        // Both should be set as specified, no automatic adjustment
        #expect(result.minInstances == 2, "minInstances should be set to 2")
        #expect(result.maxInstances == 5, "maxInstances should be set to 5")
    }
    
    /// Test: Complex scenario with all parameters
    @Test("Complex scenario with all parameters")
    func complexScenario() {
        let instance = CCInstanceConfig(
            minFlavor: "XS",
            maxFlavor: "M",
            minInstances: 2,
            maxInstances: 8
        )
        
        // Set all parameters
        let params = CCScalabilityParams(
            minFlavor: "S",
            maxFlavor: "L", 
            minInstances: 3,
            maxInstances: 10
        )
        
        let result = CCScalabilityService.mergeScalabilityParameters(params, instance: instance)
        
        // All should be set as specified
        #expect(result.minFlavor == "S", "minFlavor should be set to S")
        #expect(result.maxFlavor == "L", "maxFlavor should be set to L")
        #expect(result.minInstances == 3, "minInstances should be set to 3")
        #expect(result.maxInstances == 10, "maxInstances should be set to 10")
    }
    
    // MARK: - Validation Tests
    
    /// Test validation of scalability parameters
    @Test("Validate scalability parameters")
    func validateScalabilityParams() {
        // Valid params
        let validParams = CCScalabilityParams(minFlavor: "S", maxFlavor: "M", minInstances: 1, maxInstances: 3)
        let validResult = CCScalabilityService.validateScalabilityParams(validParams)
        #expect(validResult.isValid, "Valid params should pass validation")
        #expect(validResult.errors.isEmpty, "Valid params should have no errors")
        
        // Invalid flavor relationship
        let invalidFlavorParams = CCScalabilityParams(minFlavor: "M", maxFlavor: "S")
        let flavorResult = CCScalabilityService.validateScalabilityParams(invalidFlavorParams)
        #expect(!flavorResult.isValid, "Invalid flavor relationship should fail validation")
        #expect(flavorResult.errors.contains("min-flavor can't be a greater flavor than max-flavor"))
        
        // Invalid instance relationship
        let invalidInstanceParams = CCScalabilityParams(minInstances: 5, maxInstances: 3)
        let instanceResult = CCScalabilityService.validateScalabilityParams(invalidInstanceParams)
        #expect(!instanceResult.isValid, "Invalid instance relationship should fail validation")
        #expect(instanceResult.errors.contains("min-instances can't be greater than max-instances"))
        
        // No parameters provided
        let emptyParams = CCScalabilityParams()
        let emptyResult = CCScalabilityService.validateScalabilityParams(emptyParams)
        #expect(!emptyResult.isValid, "Empty params should fail validation")
        #expect(emptyResult.errors.contains("You should provide at least 1 option"))
    }
    
    /// Test flavor comparison helpers
    @Test("Flavor comparison helpers")
    func flavorComparison() {
        // Test flavor index ordering
        #expect(CCFlavor.flavorIndex("pico") == 0)
        #expect(CCFlavor.flavorIndex("nano") == 1)
        #expect(CCFlavor.flavorIndex("XS") == 2)
        #expect(CCFlavor.flavorIndex("S") == 3)
        #expect(CCFlavor.flavorIndex("M") == 4)
        #expect(CCFlavor.flavorIndex("L") == 5)
        #expect(CCFlavor.flavorIndex("XL") == 6)
        #expect(CCFlavor.flavorIndex("2XL") == 7)
        #expect(CCFlavor.flavorIndex("3XL") == 8)
        
        // Test flavor comparison
        #expect(CCFlavor.isFlavorGreater("M", than: "S"))
        #expect(!CCFlavor.isFlavorGreater("S", than: "M"))
        #expect(!CCFlavor.isFlavorGreater("S", than: "S"))
        
        // Test flavor validation
        #expect(CCFlavor.isValidFlavor("S"))
        #expect(CCFlavor.isValidFlavor("3XL"))
        #expect(!CCFlavor.isValidFlavor("Invalid"))
        #expect(!CCFlavor.isValidFlavor(""))
    }
    
    /// Test preset functionality
    @Test("Preset functionality")
    func presets() {
        let presets = CCScalabilityService.getDefaultPresets()
        
        // Should have multiple presets
        #expect(presets.count > 0, "Should have default presets")
        
        // Check for expected preset categories
        let categories = Set(presets.map { $0.category })
        #expect(categories.contains(.development))
        #expect(categories.contains(.production))
        #expect(categories.contains(.costOptimized))
        
        // Verify preset structure
        let devPreset = presets.first { $0.category == .development }
        #expect(devPreset != nil)
        #expect(devPreset?.configuration.strategy == .fixed)
    }
    
    /// Test cost calculation
    @Test("Cost calculation")
    func costCalculation() {
        let config = CCScalabilityConfig(
            strategy: .horizontal,
            flavorScaling: CCFlavorScaling(minFlavor: "S", maxFlavor: "M", enabled: false),
            instanceScaling: CCInstanceScaling(minInstances: 1, maxInstances: 3, enabled: true)
        )
        
        let cost = CCScalabilityService.calculateScalingCost(config)
        
        #expect(cost.monthlyMin > 0, "Should calculate minimum cost")
        #expect(cost.monthlyMax > cost.monthlyMin, "Max cost should be greater than min")
        #expect(cost.currency == "EUR", "Should use EUR currency")
        #expect(cost.breakdown.keys.contains("min_cost"))
        #expect(cost.breakdown.keys.contains("max_cost"))
    }
    
    /// Test scaling strategy detection
    @Test("Scaling strategy detection")
    func scalingStrategyDetection() {
        // Fixed scaling (no scaling enabled)
        let fixedConfig = CCScalabilityConfig(
            strategy: .fixed,
            flavorScaling: CCFlavorScaling(enabled: false),
            instanceScaling: CCInstanceScaling(enabled: false)
        )
        #expect(CCScalabilityService.detectScalingStrategy(fixedConfig) == .fixed)
        
        // Horizontal scaling (only instance scaling)
        let horizontalConfig = CCScalabilityConfig(
            strategy: .horizontal,
            flavorScaling: CCFlavorScaling(enabled: false),
            instanceScaling: CCInstanceScaling(enabled: true)
        )
        #expect(CCScalabilityService.detectScalingStrategy(horizontalConfig) == .horizontal)
        
        // Vertical scaling (only flavor scaling)
        let verticalConfig = CCScalabilityConfig(
            strategy: .vertical,
            flavorScaling: CCFlavorScaling(enabled: true),
            instanceScaling: CCInstanceScaling(enabled: false)
        )
        #expect(CCScalabilityService.detectScalingStrategy(verticalConfig) == .vertical)
        
        // Full auto scaling (both enabled)
        let fullAutoConfig = CCScalabilityConfig(
            strategy: .fullAuto,
            flavorScaling: CCFlavorScaling(enabled: true),
            instanceScaling: CCInstanceScaling(enabled: true)
        )
        #expect(CCScalabilityService.detectScalingStrategy(fullAutoConfig) == .fullAuto)
    }
} 