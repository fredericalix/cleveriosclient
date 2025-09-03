import Foundation
import Combine

/// Service for managing application environment variables and configuration
public class CCEnvironmentService {
    
    // MARK: - Properties
    
    private let httpClient: CCHTTPClient
    private let enableLogging: Bool = true
    
    // MARK: - Supporting Types
    
    /// Application update request structure for clever-tools method
    private struct ApplicationUpdateRequest: Codable {
        let instance: InstanceConfiguration
        
        struct InstanceConfiguration: Codable {
            let minFlavor: FlavorRequest
            let maxFlavor: FlavorRequest
            let minInstances: Int
            let maxInstances: Int
        }
        
        // Create a flavor object similar to what Clever Cloud expects
        struct FlavorRequest: Codable {
            let name: String
            let mem: Int
            let cpus: Int
            let gpus: Int
            let disk: Int
            let price: Double
            let available: Bool
            let microservice: Bool
            let machine_learning: Bool
            let nice: Int
            let price_id: String
            let memory: MemoryInfo
            let cpuFactor: Double
            let memFactor: Double
            
            struct MemoryInfo: Codable {
                let unit: String
                let value: Int
                let formatted: String
            }
        }
    }
    
    // MARK: - Initialization
    
    public init(httpClient: CCHTTPClient) {
        self.httpClient = httpClient
    }
    
    // MARK: - Environment Variables Management
    
    /// Get all environment variables for an application
    /// - Parameter applicationId: The application identifier
    /// - Returns: Publisher with environment variables response
    public func getEnvironmentVariables(for applicationId: String) -> AnyPublisher<CCEnvironmentVariablesResponse, CCError> {
        if enableLogging { print("🔧 Getting environment variables for application: \(applicationId)") }
        
        let endpoint = "/self/applications/\(applicationId)/env"
        return httpClient.get(endpoint, apiVersion: .v2)
            .tryMap { (data: Data) -> CCEnvironmentVariablesResponse in
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                
                // Try to decode as dictionary first (Clever Cloud format)
                if let envDict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                    let variables = envDict.map { key, value in
                        CCEnvironmentVariable(
                            name: key,
                            value: value,
                            isSecret: self.isSecretVariable(name: key)
                        )
                    }
                    return CCEnvironmentVariablesResponse(variables: variables, count: variables.count)
                }
                
                // Fallback to direct decoding
                return try decoder.decode(CCEnvironmentVariablesResponse.self, from: data)
            }
            .mapError { error in
                if self.enableLogging { print("❌ Failed to get environment variables: \(error)") }
                return CCError.parsingError(error)
            }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
    
    /// Set an environment variable for an application
    /// - Parameters:
    ///   - applicationId: The application identifier
    ///   - variable: The environment variable to set
    /// - Returns: Publisher with success response
    public func setEnvironmentVariable(
        for applicationId: String,
        variable: CCEnvironmentVariableUpdate
    ) -> AnyPublisher<CCConfigurationUpdateResponse, CCError> {
        if enableLogging { print("🔧 Setting environment variable \(variable.name) for application: \(applicationId)") }
        
        let endpoint = "/self/applications/\(applicationId)/env"
        let body = [variable.name: variable.value]
        
        return httpClient.put(endpoint, body: body, apiVersion: .v2)
            .map { (_: Data) in
                CCConfigurationUpdateResponse(
                    success: true,
                    message: "Environment variable '\(variable.name)' updated successfully"
                )
            }
            .catch { error in
                if self.enableLogging { print("❌ Failed to set environment variable: \(error)") }
                return Just(CCConfigurationUpdateResponse(
                    success: false,
                    message: "Failed to update environment variable: \(error.localizedDescription)"
                ))
                .setFailureType(to: CCError.self)
            }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
    
    /// Update multiple environment variables at once
    /// - Parameters:
    ///   - applicationId: The application identifier
    ///   - batch: Batch update with variables to set/delete
    /// - Returns: Publisher with success response
    public func updateEnvironmentVariables(
        for applicationId: String,
        batch: CCEnvironmentVariablesBatch
    ) -> AnyPublisher<CCConfigurationUpdateResponse, CCError> {
        if enableLogging { print("🔧 Batch updating environment variables for application: \(applicationId)") }
        
        var updateDict: [String: String] = [:]
        
        // Add/update variables
        for variable in batch.variables {
            updateDict[variable.name] = variable.value
        }
        
        // Handle deletions (set to empty string or use DELETE endpoint)
        if let deleteVars = batch.deleteVariables {
            for varName in deleteVars {
                updateDict[varName] = ""
            }
        }
        
        let endpoint = "/self/applications/\(applicationId)/env"
        
        return httpClient.put(endpoint, body: updateDict, apiVersion: .v2)
            .map { (_: Data) in
                CCConfigurationUpdateResponse(
                    success: true,
                    message: "Environment variables updated successfully (\(batch.variables.count) updated, \(batch.deleteVariables?.count ?? 0) deleted)"
                )
            }
            .catch { error in
                if self.enableLogging { print("❌ Failed to batch update environment variables: \(error)") }
                return Just(CCConfigurationUpdateResponse(
                    success: false,
                    message: "Failed to update environment variables: \(error.localizedDescription)"
                ))
                .setFailureType(to: CCError.self)
            }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
    
    /// Delete an environment variable
    /// - Parameters:
    ///   - applicationId: The application identifier
    ///   - variableName: Name of the variable to delete
    /// - Returns: Publisher with success response
    public func deleteEnvironmentVariable(
        for applicationId: String,
        variableName: String
    ) -> AnyPublisher<CCConfigurationUpdateResponse, CCError> {
        if enableLogging { print("🔧 Deleting environment variable \(variableName) for application: \(applicationId)") }
        
        let endpoint = "/self/applications/\(applicationId)/env/\(variableName)"
        
        return httpClient.delete(endpoint, apiVersion: .v2)
            .map { (_: Data) in
                CCConfigurationUpdateResponse(
                    success: true,
                    message: "Environment variable '\(variableName)' deleted successfully"
                )
            }
            .catch { error in
                if self.enableLogging { print("❌ Failed to delete environment variable: \(error)") }
                return Just(CCConfigurationUpdateResponse(
                    success: false,
                    message: "Failed to delete environment variable: \(error.localizedDescription)"
                ))
                .setFailureType(to: CCError.self)
            }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
    
    // MARK: - Application Configuration Management
    
    /// Get application configuration
    /// - Parameter applicationId: The application identifier
    /// - Returns: Publisher with application configuration
    public func getApplicationConfiguration(for applicationId: String) -> AnyPublisher<CCApplicationConfig, CCError> {
        if enableLogging { print("🔧 Getting configuration for application: \(applicationId)") }
        
        let endpoint = "/applications/\(applicationId)"
        return httpClient.get(endpoint, apiVersion: .v2)
            .tryMap { (data: Data) -> CCApplicationConfig in
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                
                // Parse application data and extract configuration
                if let appData = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    return try self.parseApplicationConfiguration(from: appData, applicationId: applicationId)
                }
                
                return try decoder.decode(CCApplicationConfig.self, from: data)
            }
            .mapError { error in
                if self.enableLogging { print("❌ Failed to get application configuration: \(error)") }
                return CCError.parsingError(error)
            }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
    
    /// Update application scaling configuration following official clever-tools pattern
    /// Based on clever-tools setScalability function:
    /// 1. Get current application config
    /// 2. Convert flavor objects to strings  
    /// 3. Merge with new parameters
    /// 4. Use updateApplication endpoint
    /// - Parameters:
    ///   - applicationId: The application identifier
    ///   - instanceConfig: New instance configuration
    ///   - organizationId: Optional organization ID (required for organization apps)
    /// - Returns: Publisher with success response
    public func updateInstanceConfiguration(
        for applicationId: String,
        instanceConfig: CCAppInstanceConfiguration,
        organizationId: String? = nil
    ) -> AnyPublisher<CCConfigurationUpdateResponse, CCError> {
        if enableLogging { print("🔧 Scaling app following clever-tools pattern: \(applicationId)") }
        
        // Step 1: Get current application (following clever-tools setScalability)
        let getAppEndpoint: String
        if let orgId = organizationId {
            getAppEndpoint = "/organisations/\(orgId)/applications/\(applicationId)"
        } else {
            getAppEndpoint = "/self/applications/\(applicationId)"
        }
        
        return httpClient.get(getAppEndpoint, apiVersion: .v2)
            .flatMap { [weak self] (currentApp: CCApplication) -> AnyPublisher<CCConfigurationUpdateResponse, CCError> in
                guard let self = self else {
                    return Fail(error: CCError.unknown("Service deallocated" as! Error))
                        .eraseToAnyPublisher()
                }
                
                if self.enableLogging { 
                    print("📋 Current app instance config:")
                    print("   minFlavor: \(currentApp.instance.minFlavor.name)")
                    print("   maxFlavor: \(currentApp.instance.maxFlavor.name)")
                    print("   minInstances: \(currentApp.instance.minInstances)")
                    print("   maxInstances: \(currentApp.instance.maxInstances)")
                }
                
                // Step 2: Convert current flavor objects to string names (clever-tools pattern)
                let currentMinFlavorName = currentApp.instance.minFlavor.name
                let currentMaxFlavorName = currentApp.instance.maxFlavor.name
                
                // Step 3: Merge scalability parameters (following mergeScalabilityParameters logic)
                let minFlavor: String
                let maxFlavor: String
                
                // Use new flavor if provided, otherwise keep current flavors
                let newFlavor = instanceConfig.flavor
                minFlavor = newFlavor
                maxFlavor = newFlavor
                if self.enableLogging { print("📋 Setting both flavors to: \(newFlavor)") }
                
                // Handle instances with auto-adjustment (clever-tools pattern)
                let minInstances: Int
                let maxInstances: Int
                
                let configMinInstances = instanceConfig.minInstances
                let configMaxInstances = instanceConfig.maxInstances
                
                // Auto-adjust if needed
                if configMinInstances > configMaxInstances {
                    // If minInstances > maxInstances, set both to the higher value
                    minInstances = configMinInstances
                    maxInstances = configMinInstances
                } else if configMaxInstances < configMinInstances {
                    // If maxInstances < minInstances, set both to the lower value
                    minInstances = configMaxInstances
                    maxInstances = configMaxInstances
                } else {
                    // Normal case - use provided values
                    minInstances = configMinInstances
                    maxInstances = configMaxInstances
                }
                
                // Step 3: Merge scalability parameters (following mergeScalabilityParameters)
                let scalabilityParams = CCScalabilityParameters(
                    minFlavor: newFlavor,
                    maxFlavor: newFlavor,
                    minInstances: configMinInstances,
                    maxInstances: configMaxInstances
                )
                
                // Apply clever-tools mergeScalabilityParameters logic
                let mergedConfig = self.mergeScalabilityParameters(scalabilityParams, with: currentApp.instance)
                
                if self.enableLogging {
                    print("🔧 Merged instance configuration (clever-tools pattern):")
                    print("   minFlavor: \(mergedConfig.minFlavor)")
                    print("   maxFlavor: \(mergedConfig.maxFlavor)")
                    print("   minInstances: \(mergedConfig.minInstances)")
                    print("   maxInstances: \(mergedConfig.maxInstances)")
                }
                
                // Step 4: Use updateApplication endpoint (not /instances!)
                let endpoint: String
                if let orgId = organizationId {
                    endpoint = "/organisations/\(orgId)/applications/\(applicationId)"
                } else {
                    endpoint = "/self/applications/\(applicationId)"
                }
                
                // 🔧 FIX: Use requestRawWithBody to avoid JSON parsing issues
                // The API returns the complete updated application, but we don't need to parse it
                return self.httpClient.requestRawWithBody(
                    method: .PUT,
                    endpoint: endpoint,
                    body: mergedConfig,
                    apiVersion: .v2
                )
                .map { (data: Data) -> CCConfigurationUpdateResponse in
                    if self.enableLogging { 
                        print("✅ Application updated successfully using clever-tools method") 
                        
                        // Optional: Log the response for debugging
                        if let responseString = String(data: data, encoding: .utf8) {
                            print("📦 API Response: \(responseString.prefix(200))...")
                        }
                    }
                    
                    // The API call succeeded - return success response
                    return CCConfigurationUpdateResponse(
                        success: true,
                        message: "Application configuration updated successfully"
                    )
                }
                .catch { error in
                    if self.enableLogging { print("❌ Failed to update application configuration: \(error)") }
                    
                    return Just(CCConfigurationUpdateResponse(
                        success: false,
                        message: "Failed to update application configuration: \(error.localizedDescription)"
                    ))
                    .setFailureType(to: CCError.self)
                }
                .receive(on: DispatchQueue.main)
                .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }
    
    /// Get application domains configuration
    /// - Parameter applicationId: The application identifier
    /// - Returns: Publisher with domains list
    public func getApplicationDomains(for applicationId: String) -> AnyPublisher<[String], CCError> {
                if enableLogging { print("🔧 Getting domains for application: \(applicationId)") }

        let endpoint = "/applications/\(applicationId)/vhosts"
        return httpClient.get(endpoint, apiVersion: .v2)
            .tryMap { (data: Data) -> [String] in
                if let domains = try? JSONSerialization.jsonObject(with: data) as? [String] {
                    return domains
                }
                
                // Fallback for more complex domain structure
                if let domainsData = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    return domainsData.compactMap { $0["fqdn"] as? String }
                }
                
                return []
            }
            .mapError { error in
                if self.enableLogging { print("❌ Failed to get application domains: \(error)") }
                return CCError.parsingError(error)
            }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
    
    /// Add a custom domain to an application
    /// - Parameters:
    ///   - applicationId: The application identifier
    ///   - domain: Domain to add
    /// - Returns: Publisher with success response
    public func addCustomDomain(
        for applicationId: String,
        domain: String
    ) -> AnyPublisher<CCConfigurationUpdateResponse, CCError> {
        if enableLogging { print("🔧 Adding custom domain \(domain) for application: \(applicationId)") }
        
        let endpoint = "/applications/\(applicationId)/vhosts"
        let body = ["fqdn": domain]
        
        return httpClient.post(endpoint, body: body, apiVersion: .v2)
            .map { (_: Data) in
                CCConfigurationUpdateResponse(
                    success: true,
                    message: "Custom domain '\(domain)' added successfully"
                )
            }
            .catch { error in
                if self.enableLogging { print("❌ Failed to add custom domain: \(error)") }
                return Just(CCConfigurationUpdateResponse(
                    success: false,
                    message: "Failed to add custom domain: \(error.localizedDescription)"
                ))
                .setFailureType(to: CCError.self)
            }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
    
    /// Remove a custom domain from an application
    /// - Parameters:
    ///   - applicationId: The application identifier
    ///   - domain: Domain to remove
    /// - Returns: Publisher with success response
    public func removeCustomDomain(
        for applicationId: String,
        domain: String
    ) -> AnyPublisher<CCConfigurationUpdateResponse, CCError> {
        if enableLogging { print("🔧 Removing custom domain \(domain) for application: \(applicationId)") }
        
        let endpoint = "/applications/\(applicationId)/vhosts/\(domain)"
        
        return httpClient.delete(endpoint, apiVersion: .v2)
            .map { (_: Data) in
                CCConfigurationUpdateResponse(
                    success: true,
                    message: "Custom domain '\(domain)' removed successfully"
                )
            }
            .catch { error in
                if self.enableLogging { print("❌ Failed to remove custom domain: \(error)") }
                return Just(CCConfigurationUpdateResponse(
                    success: false,
                    message: "Failed to remove custom domain: \(error.localizedDescription)"
                ))
                .setFailureType(to: CCError.self)
            }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
    
    // MARK: - Application Lifecycle Management
    
    /// Start an application
    /// - Parameters:
    ///   - applicationId: The application identifier
    ///   - organizationId: Optional organization ID (required for organization apps)
    /// - Returns: Publisher with success response
    public func startApplication(
        for applicationId: String,
        organizationId: String? = nil
    ) -> AnyPublisher<CCConfigurationUpdateResponse, CCError> {
        if enableLogging { print("🔧 Starting application: \(applicationId)") }
        
        let endpoint: String
        if let orgId = organizationId {
            endpoint = "/organisations/\(orgId)/applications/\(applicationId)/instances"
        } else {
            endpoint = "/self/applications/\(applicationId)/instances"
        }
        
        return httpClient.post(endpoint, body: [String: String](), apiVersion: .v2)
            .map { (_: Data) in
                CCConfigurationUpdateResponse(
                    success: true,
                    message: "Application start command sent successfully"
                )
            }
            .catch { error in
                if self.enableLogging { print("❌ Failed to start application: \(error)") }
                return Just(CCConfigurationUpdateResponse(
                    success: false,
                    message: "Failed to start application: \(error.localizedDescription)"
                ))
                .setFailureType(to: CCError.self)
            }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
    
    /// Restart an application
    /// - Parameters:
    ///   - applicationId: The application identifier
    ///   - organizationId: Optional organization ID (required for organization apps)
    /// - Returns: Publisher with success response
    public func restartApplication(
        for applicationId: String,
        organizationId: String? = nil
    ) -> AnyPublisher<CCConfigurationUpdateResponse, CCError> {
        if enableLogging { print("🔧 Restarting application: \(applicationId)") }
        
        let endpoint: String
        if let orgId = organizationId {
            endpoint = "/organisations/\(orgId)/applications/\(applicationId)/instances"
        } else {
            endpoint = "/self/applications/\(applicationId)/instances"
        }
        
        return httpClient.put(endpoint, body: [String: String](), apiVersion: .v2)
            .map { (_: Data) in
                CCConfigurationUpdateResponse(
                    success: true,
                    message: "Application restart command sent successfully"
                )
            }
            .catch { error in
                if self.enableLogging { print("❌ Failed to restart application: \(error)") }
                return Just(CCConfigurationUpdateResponse(
                    success: false,
                    message: "Failed to restart application: \(error.localizedDescription)"
                ))
                .setFailureType(to: CCError.self)
            }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
    
    /// Stop an application
    /// - Parameters:
    ///   - applicationId: The application identifier
    ///   - organizationId: Optional organization ID (required for organization apps)
    /// - Returns: Publisher with success response
    public func stopApplication(
        for applicationId: String,
        organizationId: String? = nil
    ) -> AnyPublisher<CCConfigurationUpdateResponse, CCError> {
        if enableLogging { print("🔧 Stopping application: \(applicationId)") }
        
        let endpoint: String
        if let orgId = organizationId {
            endpoint = "/organisations/\(orgId)/applications/\(applicationId)/instances"
        } else {
            endpoint = "/self/applications/\(applicationId)/instances"
        }
        
        return httpClient.delete(endpoint, apiVersion: .v2)
            .map { (_: Data) in
                CCConfigurationUpdateResponse(
                    success: true,
                    message: "Application stop command sent successfully"
                )
            }
            .catch { error in
                if self.enableLogging { print("❌ Failed to stop application: \(error)") }
                return Just(CCConfigurationUpdateResponse(
                    success: false,
                    message: "Failed to stop application: \(error.localizedDescription)"
                ))
                .setFailureType(to: CCError.self)
            }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
    
    // MARK: - Environment Template Management
    
    /// Get predefined environment templates
    /// - Returns: Publisher with environment templates
    public func getEnvironmentTemplates() -> AnyPublisher<[CCEnvironmentVariableUpdate], CCError> {
        if enableLogging { print("🔧 Getting environment templates") }
        
        return Just([
            // Node.js templates
            CCEnvironmentVariableUpdate(name: "NODE_ENV", value: "production"),
            CCEnvironmentVariableUpdate(name: "PORT", value: "8080"),
            CCEnvironmentVariableUpdate(name: "NPM_CONFIG_PRODUCTION", value: "true"),
            
            // PHP templates
            CCEnvironmentVariableUpdate(name: "PHP_VERSION", value: "8.1"),
            CCEnvironmentVariableUpdate(name: "DOCUMENT_ROOT", value: "/app"),
            
            // Python templates
            CCEnvironmentVariableUpdate(name: "PYTHON_VERSION", value: "3.9"),
            CCEnvironmentVariableUpdate(name: "PYTHONPATH", value: "/app"),
            
            // Database templates
            CCEnvironmentVariableUpdate(name: "DATABASE_URL", value: "", isSecret: true),
            CCEnvironmentVariableUpdate(name: "REDIS_URL", value: "", isSecret: true),
            
            // Common security templates
            CCEnvironmentVariableUpdate(name: "JWT_SECRET", value: "", isSecret: true),
            CCEnvironmentVariableUpdate(name: "API_KEY", value: "", isSecret: true),
            CCEnvironmentVariableUpdate(name: "SESSION_SECRET", value: "", isSecret: true)
        ])
        .setFailureType(to: CCError.self)
        .receive(on: DispatchQueue.main)
        .eraseToAnyPublisher()
    }
    
    // MARK: - Helper Methods
    
    /// Merge scalability parameters following clever-tools mergeScalabilityParameters logic
    /// This exactly replicates the logic from clever-tools/src/models/application.js
    /// - Parameters:
    ///   - scalabilityParameters: New scaling parameters
    ///   - instance: Current instance configuration
    /// - Returns: Merged instance configuration
    private func mergeScalabilityParameters(
        _ scalabilityParameters: CCScalabilityParameters,
        with instance: CCInstance
    ) -> CCInstanceUpdateRequest {
        let flavors = ["pico", "nano", "XS", "S", "M", "L", "XL", "2XL", "3XL"]
        
        // Start with current values converted to strings
        var minFlavor = instance.minFlavor.name
        var maxFlavor = instance.maxFlavor.name
        var minInstances = instance.minInstances
        var maxInstances = instance.maxInstances
        
        // Apply clever-tools mergeScalabilityParameters logic
        if let newMinFlavor = scalabilityParameters.minFlavor {
            minFlavor = newMinFlavor
            // Auto-adjust maxFlavor if needed
            if let minIndex = flavors.firstIndex(of: minFlavor),
               let maxIndex = flavors.firstIndex(of: maxFlavor),
               minIndex > maxIndex {
                maxFlavor = minFlavor
            }
        }
        
        if let newMaxFlavor = scalabilityParameters.maxFlavor {
            maxFlavor = newMaxFlavor
            // Auto-adjust minFlavor if needed
            if let minIndex = flavors.firstIndex(of: minFlavor),
               let maxIndex = flavors.firstIndex(of: maxFlavor),
               minIndex > maxIndex && scalabilityParameters.minFlavor == nil {
                minFlavor = maxFlavor
            }
        }
        
        if let newMinInstances = scalabilityParameters.minInstances {
            minInstances = newMinInstances
            // Auto-adjust maxInstances if needed
            if minInstances > maxInstances {
                maxInstances = minInstances
            }
        }
        
        if let newMaxInstances = scalabilityParameters.maxInstances {
            maxInstances = newMaxInstances
            // Auto-adjust minInstances if needed
            if minInstances > maxInstances && scalabilityParameters.minInstances == nil {
                minInstances = maxInstances
            }
        }
        
        return CCInstanceUpdateRequest(
            minFlavor: minFlavor,
            maxFlavor: maxFlavor,
            minInstances: minInstances,
            maxInstances: maxInstances
        )
    }
    
    /// Determine if a variable should be treated as secret based on its name
    /// - Parameter name: Variable name
    /// - Returns: True if the variable should be treated as secret
    private func isSecretVariable(name: String) -> Bool {
        let secretPatterns = [
            "password", "secret", "key", "token", "auth", "credential",
            "private", "api_key", "database_url", "redis_url", "mongodb_uri",
            "jwt", "session", "oauth", "webhook_secret"
        ]
        
        let lowercaseName = name.lowercased()
        return secretPatterns.contains { lowercaseName.contains($0) }
    }
    
    /// Parse application configuration from API response
    /// - Parameters:
    ///   - data: Raw application data
    ///   - applicationId: Application identifier
    /// - Returns: Parsed application configuration
    private func parseApplicationConfiguration(
        from data: [String: Any],
        applicationId: String
    ) throws -> CCApplicationConfig {
        // Extract instance configuration
        let instance = data["instance"] as? [String: Any] ?? [:]
        let instanceConfig = CCAppInstanceConfiguration(
            minInstances: instance["minInstances"] as? Int ?? 1,
            maxInstances: instance["maxInstances"] as? Int ?? 1,
            flavor: (instance["minFlavor"] as? [String: Any])?["name"] as? String ?? "nano"
        )
        
        // Extract deployment configuration
        let deploymentConfig = CCDeploymentConfiguration(
            autoDeployment: data["autoDeployment"] as? Bool ?? false,
            deploymentStrategy: "rolling",
            buildTimeout: 900
        )
        
        return CCApplicationConfig(
            id: UUID().uuidString,
            applicationId: applicationId,
            instanceConfiguration: instanceConfig,
            deploymentConfiguration: deploymentConfig
        )
    }
    

} 