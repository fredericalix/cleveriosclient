import Foundation
import Combine

/// Service for managing Clever Cloud applications
public class CCApplicationService: ObservableObject {
    
    // MARK: - Properties
    
    private let httpClient: CCHTTPClient
    
    // MARK: - Initialization
    
    public init(httpClient: CCHTTPClient) {
        self.httpClient = httpClient
    }
    
    // MARK: - CRUD Operations
    
    /// Get all applications for the current user
    /// - Returns: Publisher with array of CCApplication objects
    public func getApplications() -> AnyPublisher<[CCApplication], CCError> {
        print("🚀 CCApplicationService.getApplications() called")
        return httpClient.get("/self/applications", apiVersion: .v2)
    }
    
    /// Get all applications (status computation will be done separately when needed)
    /// - Returns: Publisher with array of CCApplication objects 
    public func getApplicationsWithStates() -> AnyPublisher<[CCApplication], CCError> {
        print("🚀 CCApplicationService.getApplicationsWithStates() called")
        print("📝 Note: Application status should be computed separately using getApplicationStatus()")
        
        return getApplications()
    }
    
    /// Get applications for a specific organization
    /// - Parameter organizationId: The organization ID
    /// - Returns: Publisher with array of CCApplication objects
    public func getApplications(forOrganization organizationId: String) -> AnyPublisher<[CCApplication], CCError> {
        return httpClient.get("/organisations/\(organizationId)/applications", apiVersion: .v2)
    }
    
    /// Get applications for a specific organization (status computation will be done separately when needed)
    /// - Parameter organizationId: The organization ID
    /// - Returns: Publisher with array of CCApplication objects
    public func getApplicationsWithStates(forOrganization organizationId: String) -> AnyPublisher<[CCApplication], CCError> {
        print("🚀 CCApplicationService.getApplicationsWithStates(forOrganization: \(organizationId)) called")
        print("📝 Note: Application status should be computed separately using getApplicationStatus()")
        
        return getApplications(forOrganization: organizationId)
    }
    
    /// Get a specific application by ID
    /// - Parameter applicationId: The application ID
    /// - Returns: Publisher with CCApplication object
    public func getApplication(applicationId: String) -> AnyPublisher<CCApplication, CCError> {
        return httpClient.get("/self/applications/\(applicationId)", apiVersion: .v2)
    }
    
    
    /// Update an existing application
    /// - Parameters:
    ///   - applicationId: The application ID to update
    ///   - update: CCApplicationUpdate object with changes
    /// - Returns: Publisher with updated CCApplication object
    public func updateApplication(
        applicationId: String,
        update: CCApplicationUpdate
    ) -> AnyPublisher<CCApplication, CCError> {
        return httpClient.put("/self/applications/\(applicationId)", body: update, apiVersion: .v2)
    }
    
    /// Delete an application
    /// - Parameters:
    ///   - applicationId: The application ID to delete
    ///   - organizationId: Optional organization ID. If nil, uses personal space (/self)
    public func deleteApplication(applicationId: String, organizationId: String? = nil) -> AnyPublisher<EmptyResponse, CCError> {
        let endpoint = buildApplicationEndpoint(applicationId: applicationId, organizationId: organizationId)
        return httpClient.delete(endpoint, apiVersion: .v2)
    }
    
    // MARK: - Application State Management
    
    /// Start an application (redeploy) - same as restart
    /// - Parameters:
    ///   - applicationId: The application ID to start
    ///   - organizationId: Optional organization ID. If nil, uses personal space (/self)
    public func startApplication(applicationId: String, organizationId: String? = nil) -> AnyPublisher<EmptyResponse, CCError> {
        let endpoint = buildApplicationEndpoint(applicationId: applicationId, organizationId: organizationId, path: "/instances")
        return httpClient.postWithoutBody(endpoint, apiVersion: .v2)
    }
    
    /// Stop an application (undeploy)
    /// - Parameters:
    ///   - applicationId: The application ID to stop
    ///   - organizationId: Optional organization ID. If nil, uses personal space (/self)
    public func stopApplication(applicationId: String, organizationId: String? = nil) -> AnyPublisher<EmptyResponse, CCError> {
        let endpoint = buildApplicationEndpoint(applicationId: applicationId, organizationId: organizationId, path: "/instances")
        return httpClient.deleteWithoutBody(endpoint, apiVersion: .v2)
    }
    
    /// Restart an application (redeploy) - same as start
    /// - Parameters:
    ///   - applicationId: The application ID to restart
    ///   - organizationId: Optional organization ID. If nil, uses personal space (/self)
    public func restartApplication(applicationId: String, organizationId: String? = nil) -> AnyPublisher<EmptyResponse, CCError> {
        let endpoint = buildApplicationEndpoint(applicationId: applicationId, organizationId: organizationId, path: "/instances")
        return httpClient.postWithoutBody(endpoint, apiVersion: .v2)
    }
    
    
    // MARK: - Helper Methods
    
    /// Build the correct endpoint based on organization context
    /// - Parameters:
    ///   - applicationId: The application ID
    ///   - organizationId: Optional organization ID
    ///   - path: The additional path (e.g., "/instances", "/env")
    /// - Returns: The correct endpoint string
    private func buildApplicationEndpoint(applicationId: String, organizationId: String?, path: String = "") -> String {
        if let orgId = organizationId, orgId.hasPrefix("orga_") {
            // Organization context
            return "/organisations/\(orgId)/applications/\(applicationId)\(path)"
        } else {
            // Personal space context
            return "/self/applications/\(applicationId)\(path)"
        }
    }
    
    // MARK: - Application Instance Management
    
    /// Get all instances for a specific application
    /// - Parameter applicationId: The application ID
    /// - Returns: Publisher with array of application instances
    public func getApplicationInstances(applicationId: String) -> AnyPublisher<[CCApplicationInstance], CCError> {
        print("🚀 CCApplicationService.getApplicationInstances(\(applicationId)) called")
        
        return httpClient.get("/self/applications/\(applicationId)/instances", apiVersion: .v2)
            .eraseToAnyPublisher()
    }
    
    /// Get all instances for a specific application in an organization
    /// - Parameters:
    ///   - applicationId: The application ID
    ///   - organizationId: The organization ID
    /// - Returns: Publisher with array of application instances
    public func getApplicationInstances(applicationId: String, organizationId: String) -> AnyPublisher<[CCApplicationInstance], CCError> {
        print("🚀 CCApplicationService.getApplicationInstances(\(applicationId), org: \(organizationId)) called")
        
        return httpClient.get("/organisations/\(organizationId)/applications/\(applicationId)/instances", apiVersion: .v2)
            .eraseToAnyPublisher()
    }
    
    // MARK: - Environment Variables
    
    /// Get environment variables for an application
    /// - Parameters:
    ///   - applicationId: The application ID
    ///   - organizationId: Optional organization ID (nil for user applications)
    /// - Returns: Publisher with array of environment variables
    public func getEnvironmentVariables(applicationId: String, organizationId: String? = nil) -> AnyPublisher<[CCEnvironmentVariable], CCError> {
        let endpoint: String
        if let orgId = organizationId {
            endpoint = "/organisations/\(orgId)/applications/\(applicationId)/env"
        } else {
            endpoint = "/self/applications/\(applicationId)/env"
        }
        return httpClient.get(endpoint, apiVersion: .v2)
    }
    
    /// Set environment variables for an application
    /// - Parameters:
    ///   - applicationId: The application ID
    ///   - variables: Array of environment variables to set
    public func setEnvironmentVariables(
        applicationId: String,
        variables: [CCEnvironmentVariable]
    ) -> AnyPublisher<[CCEnvironmentVariable], CCError> {
        return httpClient.put("/self/applications/\(applicationId)/env", body: variables, apiVersion: .v2)
    }
    
    /// Add or update a single environment variable
    /// - Parameters:
    ///   - applicationId: The application ID
    ///   - variable: Environment variable to set
    public func setEnvironmentVariable(
        applicationId: String,
        variable: CCEnvironmentVariable
    ) -> AnyPublisher<CCEnvironmentVariable, CCError> {
        return httpClient.put("/self/applications/\(applicationId)/env/\(variable.name)", body: variable, apiVersion: .v2)
    }
    
    /// Remove an environment variable
    /// - Parameters:
    ///   - applicationId: The application ID
    ///   - name: Variable name to remove
    public func removeEnvironmentVariable(
        applicationId: String,
        name: String
    ) -> AnyPublisher<EmptyResponse, CCError> {
        return httpClient.delete("/self/applications/\(applicationId)/env/\(name)", apiVersion: .v2)
    }
    
    // MARK: - Scaling
    
    /// Get available flavors for applications
    /// - Returns: Publisher with array of available instance flavors
    public func getAvailableFlavors() -> AnyPublisher<[CCFlavor], CCError> {
        // Since the /products/instances endpoint doesn't exist (returns 404),
        // we provide the standard Clever Cloud flavors based on actual instances we see in the API
        let availableFlavors = [
            CCFlavor(
                name: "nano",
                mem: 582,
                cpus: 1,
                gpus: 0,
                disk: 0,
                price: 0.0083333333,
                available: true,
                microservice: false,
                machine_learning: false,
                nice: 0,
                price_id: "nano",
                memory: CCMemoryInfo(unit: "MB", value: 582, formatted: "582 MB"),
                cpuFactor: 1.0,
                memFactor: 1.0
            ),
            CCFlavor(
                name: "XS",
                mem: 1152,
                cpus: 1,
                gpus: 0,
                disk: 0,
                price: 0.0222222222,
                available: true,
                microservice: false,
                machine_learning: false,
                nice: 0,
                price_id: "XS",
                memory: CCMemoryInfo(unit: "MB", value: 1152, formatted: "1152 MB"),
                cpuFactor: 1.0,
                memFactor: 1.0
            ),
            CCFlavor(
                name: "S",
                mem: 2304,
                cpus: 2,
                gpus: 0,
                disk: 0,
                price: 0.0444444444,
                available: true,
                microservice: false,
                machine_learning: false,
                nice: 0,
                price_id: "S",
                memory: CCMemoryInfo(unit: "MB", value: 2304, formatted: "2304 MB"),
                cpuFactor: 2.0,
                memFactor: 2.0
            ),
            CCFlavor(
                name: "M",
                mem: 4608,
                cpus: 4,
                gpus: 0,
                disk: 0,
                price: 0.0888888889,
                available: true,
                microservice: false,
                machine_learning: false,
                nice: 0,
                price_id: "M",
                memory: CCMemoryInfo(unit: "MB", value: 4608, formatted: "4608 MB"),
                cpuFactor: 4.0,
                memFactor: 4.0
            ),
            CCFlavor(
                name: "L",
                mem: 9216,
                cpus: 8,
                gpus: 0,
                disk: 0,
                price: 0.1777777778,
                available: true,
                microservice: false,
                machine_learning: false,
                nice: 0,
                price_id: "L",
                memory: CCMemoryInfo(unit: "MB", value: 9216, formatted: "9216 MB"),
                cpuFactor: 8.0,
                memFactor: 8.0
            ),
            CCFlavor(
                name: "XL",
                mem: 18432,
                cpus: 16,
                gpus: 0,
                disk: 0,
                price: 0.3555555556,
                available: true,
                microservice: false,
                machine_learning: false,
                nice: 0,
                price_id: "XL",
                memory: CCMemoryInfo(unit: "MB", value: 18432, formatted: "18432 MB"),
                cpuFactor: 16.0,
                memFactor: 16.0
            )
        ]
        
        print("📋 Available flavors loaded: \(availableFlavors.map { $0.name }.joined(separator: ", "))")
        
        return Just(availableFlavors)
            .setFailureType(to: CCError.self)
            .eraseToAnyPublisher()
    }
    
    // MARK: - Domains

    /// Get domains for an application (using self endpoint)
    /// - Parameter applicationId: The application ID
    /// - Returns: Publisher with array of domains
    public func getDomains(applicationId: String) -> AnyPublisher<[CCDomain], CCError> {
        return httpClient.get("/self/applications/\(applicationId)/vhosts", apiVersion: .v2)
    }

    /// Get domains for an application with organization context
    /// - Parameters:
    ///   - applicationId: The application ID
    ///   - organizationId: The organization ID
    /// - Returns: Publisher with array of domains
    public func getDomainsForOrganization(applicationId: String, organizationId: String) -> AnyPublisher<[CCDomain], CCError> {
        return httpClient.get("/organisations/\(organizationId)/applications/\(applicationId)/vhosts", apiVersion: .v2)
    }

    /// Add a domain to an application
    /// - Parameters:
    ///   - applicationId: The application ID
    ///   - organizationId: The organization ID
    ///   - domain: Domain name to add
    public func addDomain(applicationId: String, organizationId: String, domain: String) -> AnyPublisher<EmptyResponse, CCError> {
        // Encode domain name like clever-tools does
        guard let encodedDomain = domain.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) else {
            return Fail(error: CCError.invalidParameters("Invalid domain name"))
                .eraseToAnyPublisher()
        }
        return httpClient.put("/organisations/\(organizationId)/applications/\(applicationId)/vhosts/\(encodedDomain)", body: EmptyRequest(), apiVersion: .v2)
    }

    /// Remove a domain from an application
    /// - Parameters:
    ///   - applicationId: The application ID
    ///   - organizationId: The organization ID
    ///   - domain: Domain name to remove
    public func removeDomain(applicationId: String, organizationId: String, domain: String) -> AnyPublisher<EmptyResponse, CCError> {
        // CRITICAL: We MUST encode the domain EXACTLY like clever-tools does with encodeURIComponent
        // JavaScript encodeURIComponent encodes everything EXCEPT: A-Z a-z 0-9 - _ . ! ~ * ' ( )
        // This means dots (.) should NOT be encoded in encodeURIComponent
        let jsEncodeURIComponentAllowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
        guard let encodedDomain = domain.addingPercentEncoding(withAllowedCharacters: jsEncodeURIComponentAllowed) else {
            return Fail(error: CCError.invalidParameters("Failed to encode domain name"))
                .eraseToAnyPublisher()
        }

        return httpClient.delete("/organisations/\(organizationId)/applications/\(applicationId)/vhosts/\(encodedDomain)", apiVersion: .v2)
    }

    /// Set favorite domain for an application
    /// - Parameters:
    ///   - applicationId: The application ID
    ///   - organizationId: The organization ID
    ///   - domain: Domain to set as favorite
    public func setFavoriteDomain(applicationId: String, organizationId: String, domain: String) -> AnyPublisher<EmptyResponse, CCError> {
        let body = FavoriteDomainRequest(fqdn: domain)
        return httpClient.put("/organisations/\(organizationId)/applications/\(applicationId)/vhosts/favourite", body: body, apiVersion: .v2)
    }
    
    // MARK: - Deployment Management
    
    /// Get deployment information
    /// - Parameter applicationId: The application ID
    /// - Returns: Publisher with array of deployment information
    public func getDeployments(applicationId: String) -> AnyPublisher<[CCDeployment], CCError> {
        return httpClient.get("/self/applications/\(applicationId)/deployments", apiVersion: .v2)
    }
    
    /// Trigger a new deployment
    /// - Parameter applicationId: The application ID
    /// - Returns: Publisher with deployment information
    public func deploy(applicationId: String) -> AnyPublisher<CCDeployment, CCError> {
        return httpClient.post("/self/applications/\(applicationId)/deployments", body: EmptyRequest(), apiVersion: .v2)
    }
    
    /// Cancel a deployment
    /// - Parameters:
    ///   - applicationId: The application ID
    ///   - deploymentId: The deployment ID to cancel
    public func cancelDeployment(applicationId: String, deploymentId: String) -> AnyPublisher<EmptyResponse, CCError> {
        return httpClient.delete("/self/applications/\(applicationId)/deployments/\(deploymentId)", apiVersion: .v2)
    }
    
    // MARK: - Add-ons
    
    /// Get linked add-ons for an application
    /// - Parameter applicationId: The application ID
    /// - Returns: Publisher with array of linked add-on information
    public func getLinkedAddons(applicationId: String) -> AnyPublisher<[CCAddonLink], CCError> {
        return httpClient.get("/self/applications/\(applicationId)/addons", apiVersion: .v2)
    }
    
    /// Link an add-on to an application
    /// - Parameters:
    ///   - applicationId: The application ID
    ///   - addonId: The add-on ID to link
    public func linkAddon(applicationId: String, addonId: String) -> AnyPublisher<EmptyResponse, CCError> {
        let body = AddonLinkRequest(addon_id: addonId)
        return httpClient.post("/self/applications/\(applicationId)/addons", body: body, apiVersion: .v2)
    }
    
    /// Unlink an add-on from an application
    /// - Parameters:
    ///   - applicationId: The application ID
    ///   - addonId: The add-on ID to unlink
    public func unlinkAddon(applicationId: String, addonId: String) -> AnyPublisher<EmptyResponse, CCError> {
        return httpClient.delete("/self/applications/\(applicationId)/addons/\(addonId)", apiVersion: .v2)
    }
    
    // MARK: - Application Logs
    
    /// Get logs for an application
    /// - Parameters:
    ///   - applicationId: The application ID
    ///   - organizationId: Optional organization ID (nil for user applications)
    ///   - limit: Maximum number of logs to retrieve (default: 100)
    ///   - order: Log order (asc or desc, default: desc)
    /// - Returns: Publisher with array of log entries
    public func getApplicationLogs(
        applicationId: String,
        organizationId: String? = nil,
        limit: Int = 100,
        order: String = "desc"
    ) -> AnyPublisher<[CCLogEntry], CCError> {
        // Use the same logs endpoint as add-ons
        let endpoint = "/logs/\(applicationId)?limit=\(limit)&order=\(order)"
        
        print("📝 [CCApplicationService] Getting logs from endpoint: \(endpoint)")
        print("📝 [CCApplicationService] Application ID: \(applicationId)")
        print("📝 [CCApplicationService] Using v2 logs endpoint")
        
        // Decode as array of ElasticsearchLogEntry first, then map to CCLogEntry
        return httpClient.get(endpoint, apiVersion: .v2)
            .handleEvents(
                receiveOutput: { (entries: [ElasticsearchLogEntry]) in
                    print("📝 [CCApplicationService] Received \(entries.count) Elasticsearch log entries")
                },
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("❌ [CCApplicationService] Failed to decode Elasticsearch logs: \(error)")
                    }
                }
            )
            .tryMap { (entries: [ElasticsearchLogEntry]) -> [CCLogEntry] in
                // Convert Elasticsearch entries to CCLogEntry
                return entries.compactMap { elasticEntry in
                    let source = elasticEntry.source
                    
                    // Parse timestamp
                    let timestamp: Date
                    if let date = ISO8601DateFormatter().date(from: source.timestamp) {
                        timestamp = date
                    } else {
                        timestamp = Date()
                    }
                    
                    // Determine log level from message or metadata
                    let level: CCLogLevel
                    if let severity = source.syslogSeverity {
                        switch severity.lowercased() {
                        case "debug": level = .debug
                        case "info", "informational": level = .info
                        case "warning", "warn": level = .warning
                        case "error", "err": level = .error
                        default: level = .info
                        }
                    } else {
                        // Try to infer from message
                        let lowercasedMessage = source.message.lowercased()
                        if lowercasedMessage.contains("error") || lowercasedMessage.contains("fail") {
                            level = .error
                        } else if lowercasedMessage.contains("warn") {
                            level = .warning
                        } else if lowercasedMessage.contains("debug") {
                            level = .debug
                        } else {
                            level = .info
                        }
                    }
                    
                    return CCLogEntry(
                        timestamp: timestamp,
                        message: source.message,
                        level: level,
                        source: source.syslogProgram ?? source.type,
                        instanceId: source.sourceHost
                    )
                }
            }
            .mapError { error -> CCError in
                if let ccError = error as? CCError {
                    return ccError
                }
                return CCError.parsingError(error)
            }
            .eraseToAnyPublisher()
    }
}

// MARK: - Supporting Models
// EmptyRequest and EmptyResponse are now defined in CCCommon.swift

// CCEnvironmentVariable is now defined in CCEnvironment.swift

/// Domain model
public struct CCDomain: Codable, Identifiable {
    public var id: UUID { UUID() }
    public let fqdn: String
    public let isCanonical: Bool?
    
    enum CodingKeys: String, CodingKey {
        case fqdn
        case isCanonical = "is_canonical"
    }
}

// CCDeployment is now defined in CCDeployment.swift

/// Add-on link model
public struct CCAddonLink: Codable, Identifiable {
    public var id: UUID { UUID() }
    public let addon_id: String
    public let application_id: String
}

/// Application instance flavor model
public struct CCInstanceFlavor: Codable {
    public let name: String
    public let mem: Int?
    public let cpus: Int?
    public let price: Double?
}

/// Application instance model
public struct CCApplicationInstance: Codable, Identifiable {
    public let id: String
    public let appId: String
    public let ip: String?
    public let appPort: Int?
    public let state: String
    public let flavor: CCInstanceFlavor
    public let commit: String?
    public let deployNumber: Int?
    public let deployId: String?
    public let instanceNumber: Int?
    public let displayName: String?
    public let creationDate: Int64?
    
    enum CodingKeys: String, CodingKey {
        case id
        case appId
        case ip
        case appPort
        case state
        case flavor
        case commit
        case deployNumber
        case deployId
        case instanceNumber
        case displayName
        case creationDate
    }
}

/// Request model for linking add-ons
private struct AddonLinkRequest: Codable {
    let addon_id: String
}

/// Request model for setting favorite domain
private struct FavoriteDomainRequest: Codable {
    let fqdn: String
} 