import Foundation
import Combine

/// Service for managing Clever Cloud applications
public class CCApplicationService: ObservableObject {
    
    // MARK: - Properties

    private let httpClient: CCHTTPClient

    /// JavaScript encodeURIComponent-compatible character set for domain encoding
    private static let jsEncodeURIComponentAllowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()"
    )
    
    // MARK: - Initialization
    
    public init(httpClient: CCHTTPClient) {
        self.httpClient = httpClient
    }
    
    // MARK: - CRUD Operations
    
    /// Get all applications for the current user
    /// - Returns: Publisher with array of CCApplication objects
    public func getApplications() -> AnyPublisher<[CCApplication], CCError> {
        debugLog("🚀 CCApplicationService.getApplications() called")
        return httpClient.get("/self/applications", apiVersion: .v2)
    }
    
    /// Get all applications (status computation will be done separately when needed)
    /// - Returns: Publisher with array of CCApplication objects 
    public func getApplicationsWithStates() -> AnyPublisher<[CCApplication], CCError> {
        debugLog("🚀 CCApplicationService.getApplicationsWithStates() called")
        debugLog("📝 Note: Application status should be computed separately using getApplicationStatus()")
        
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
        debugLog("🚀 CCApplicationService.getApplicationsWithStates(forOrganization: \(organizationId)) called")
        debugLog("📝 Note: Application status should be computed separately using getApplicationStatus()")
        
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
        debugLog("🚀 CCApplicationService.getApplicationInstances(\(applicationId)) called")
        
        return httpClient.get("/self/applications/\(applicationId)/instances", apiVersion: .v2)
            .eraseToAnyPublisher()
    }
    
    /// Get all instances for a specific application in an organization
    /// - Parameters:
    ///   - applicationId: The application ID
    ///   - organizationId: The organization ID
    /// - Returns: Publisher with array of application instances
    public func getApplicationInstances(applicationId: String, organizationId: String) -> AnyPublisher<[CCApplicationInstance], CCError> {
        debugLog("🚀 CCApplicationService.getApplicationInstances(\(applicationId), org: \(organizationId)) called")
        
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
    ///   - organizationId: Optional organization ID (nil for user applications)
    public func setEnvironmentVariables(
        applicationId: String,
        variables: [CCEnvironmentVariable],
        organizationId: String? = nil
    ) -> AnyPublisher<EmptyResponse, CCError> {
        let endpoint: String
        if let orgId = organizationId {
            endpoint = "/organisations/\(orgId)/applications/\(applicationId)/env"
        } else {
            endpoint = "/self/applications/\(applicationId)/env"
        }
        return httpClient.put(endpoint, body: variables, apiVersion: .v2)
    }
    
    /// Add or update a single environment variable
    /// - Parameters:
    ///   - applicationId: The application ID
    ///   - variable: Environment variable to set
    ///   - organizationId: Optional organization ID (nil for user applications)
    public func setEnvironmentVariable(
        applicationId: String,
        variable: CCEnvironmentVariable,
        organizationId: String? = nil
    ) -> AnyPublisher<EmptyResponse, CCError> {
        let endpoint: String
        if let orgId = organizationId {
            endpoint = "/organisations/\(orgId)/applications/\(applicationId)/env/\(variable.name)"
        } else {
            endpoint = "/self/applications/\(applicationId)/env/\(variable.name)"
        }
        return httpClient.put(endpoint, body: variable, apiVersion: .v2)
    }
    
    /// Remove an environment variable
    /// - Parameters:
    ///   - applicationId: The application ID
    ///   - name: Variable name to remove
    ///   - organizationId: Optional organization ID (nil for user applications)
    public func removeEnvironmentVariable(
        applicationId: String,
        name: String,
        organizationId: String? = nil
    ) -> AnyPublisher<EmptyResponse, CCError> {
        let endpoint: String
        if let orgId = organizationId {
            endpoint = "/organisations/\(orgId)/applications/\(applicationId)/env/\(name)"
        } else {
            endpoint = "/self/applications/\(applicationId)/env/\(name)"
        }
        return httpClient.delete(endpoint, apiVersion: .v2)
    }
    
    // MARK: - Scaling
    
    /// Get available flavors for applications
    /// - Returns: Publisher with array of available instance flavors
    public func getAvailableFlavors() -> AnyPublisher<[CCFlavor], CCError> {
        // Clever Cloud flavor specs from /v2/products/instances API
        let availableFlavors = [
            CCFlavor(
                name: "pico",
                mem: 337,
                cpus: 1,
                gpus: 0,
                disk: 0,
                price: 0.0,
                available: true,
                microservice: false,
                machine_learning: false,
                nice: 0,
                price_id: "pico",
                memory: CCMemoryInfo(unit: "MB", value: 337, formatted: "337 MB"),
                cpuFactor: 1.0,
                memFactor: 1.0
            ),
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
                mem: 2048,
                cpus: 2,
                gpus: 0,
                disk: 0,
                price: 0.0444444444,
                available: true,
                microservice: false,
                machine_learning: false,
                nice: 0,
                price_id: "S",
                memory: CCMemoryInfo(unit: "MB", value: 2048, formatted: "2 GB"),
                cpuFactor: 2.0,
                memFactor: 2.0
            ),
            CCFlavor(
                name: "M",
                mem: 4096,
                cpus: 4,
                gpus: 0,
                disk: 0,
                price: 0.0888888889,
                available: true,
                microservice: false,
                machine_learning: false,
                nice: 0,
                price_id: "M",
                memory: CCMemoryInfo(unit: "MB", value: 4096, formatted: "4 GB"),
                cpuFactor: 4.0,
                memFactor: 4.0
            ),
            CCFlavor(
                name: "L",
                mem: 8192,
                cpus: 6,
                gpus: 0,
                disk: 0,
                price: 0.1777777778,
                available: true,
                microservice: false,
                machine_learning: false,
                nice: 0,
                price_id: "L",
                memory: CCMemoryInfo(unit: "MB", value: 8192, formatted: "8 GB"),
                cpuFactor: 6.0,
                memFactor: 6.0
            ),
            CCFlavor(
                name: "XL",
                mem: 16384,
                cpus: 8,
                gpus: 0,
                disk: 0,
                price: 0.3555555556,
                available: true,
                microservice: false,
                machine_learning: false,
                nice: 0,
                price_id: "XL",
                memory: CCMemoryInfo(unit: "MB", value: 16384, formatted: "16 GB"),
                cpuFactor: 8.0,
                memFactor: 8.0
            ),
            CCFlavor(
                name: "2XL",
                mem: 24576,
                cpus: 12,
                gpus: 0,
                disk: 0,
                price: 0.5333333334,
                available: true,
                microservice: false,
                machine_learning: false,
                nice: 0,
                price_id: "2XL",
                memory: CCMemoryInfo(unit: "MB", value: 24576, formatted: "24 GB"),
                cpuFactor: 12.0,
                memFactor: 12.0
            ),
            CCFlavor(
                name: "3XL",
                mem: 32768,
                cpus: 16,
                gpus: 0,
                disk: 0,
                price: 0.7111111112,
                available: true,
                microservice: false,
                machine_learning: false,
                nice: 0,
                price_id: "3XL",
                memory: CCMemoryInfo(unit: "MB", value: 32768, formatted: "32 GB"),
                cpuFactor: 16.0,
                memFactor: 16.0
            )
        ]
        
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
        guard let encodedDomain = domain.addingPercentEncoding(withAllowedCharacters: Self.jsEncodeURIComponentAllowed) else {
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
        guard let encodedDomain = domain.addingPercentEncoding(withAllowedCharacters: Self.jsEncodeURIComponentAllowed) else {
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
        order: String = "desc",
        since: Date? = nil
    ) -> AnyPublisher<[CCLogEntry], CCError> {
        // Use provided since date, or default to 24h ago for initial load
        let sinceDate = since ?? Date().addingTimeInterval(-24 * 3600)
        let sinceStr = ISO8601DateFormatter().string(from: sinceDate)

        guard let orgId = organizationId else {
            let endpoint = "/logs/self/applications/\(applicationId)/logs?limit=\(limit)&since=\(sinceStr)"
            return fetchSSELogs(endpoint: endpoint, apiVersion: .v4)
        }

        let endpoint = "/logs/organisations/\(orgId)/applications/\(applicationId)/logs?limit=\(limit)&since=\(sinceStr)"
        return fetchSSELogs(endpoint: endpoint, apiVersion: .v4)
    }

    /// Fetch logs from SSE endpoint and parse into CCLogEntry array
    private func fetchSSELogs(endpoint: String, apiVersion: APIVersion) -> AnyPublisher<[CCLogEntry], CCError> {
        return httpClient.getSSEData(endpoint, apiVersion: apiVersion, timeout: 10.0)
            .map { data -> [CCLogEntry] in
                let sseText = String(data: data, encoding: .utf8) ?? ""
                return self.parseSSELogEvents(sseText)
            }
            .eraseToAnyPublisher()
    }

    /// Parse SSE text into log entries
    /// SSE format: "data:{json}\nevent:APPLICATION_LOG\nid:...\n\n"
    private func parseSSELogEvents(_ sseText: String) -> [CCLogEntry] {
        var entries: [CCLogEntry] = []
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // Split by double newline (SSE event boundary)
        let events = sseText.components(separatedBy: "\n\n")

        for event in events {
            let lines = event.components(separatedBy: "\n")

            // Find the data line
            var dataLine: String?
            var eventType: String?

            for line in lines {
                if line.hasPrefix("data:") {
                    dataLine = String(line.dropFirst(5))
                } else if line.hasPrefix("event:") {
                    eventType = String(line.dropFirst(6))
                }
            }

            // Only parse APPLICATION_LOG events with data
            guard let jsonString = dataLine, !jsonString.isEmpty,
                  eventType == "APPLICATION_LOG" else {
                continue
            }

            guard let jsonData = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let message = json["message"] as? String else {
                continue
            }

            // Parse date
            let timestamp: Date
            if let dateStr = json["date"] as? String {
                timestamp = isoFormatter.date(from: dateStr)
                    ?? ISO8601DateFormatter().date(from: dateStr)
                    ?? Date()
            } else {
                timestamp = Date()
            }

            // Parse severity
            let level: CCLogLevel
            if let severity = json["severity"] as? String {
                switch severity.lowercased() {
                case "debug": level = .debug
                case "info", "informational": level = .info
                case "warning", "warn": level = .warning
                case "error", "err", "critical", "alert", "emergency": level = .error
                default: level = .info
                }
            } else {
                level = .info
            }

            let entry = CCLogEntry(
                timestamp: timestamp,
                message: message,
                level: level,
                source: json["service"] as? String,
                instanceId: json["instanceId"] as? String
            )
            entries.append(entry)
        }

        // Sort newest first
        entries.sort { $0.timestamp > $1.timestamp }
        return entries
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