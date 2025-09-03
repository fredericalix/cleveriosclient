import Foundation
import Combine

/// Service for managing Clever Cloud application deployments
public class CCDeploymentService: ObservableObject {
    
    // MARK: - Properties
    
    private let httpClient: CCHTTPClient
    
    // MARK: - Initialization
    
    init(httpClient: CCHTTPClient) {
        self.httpClient = httpClient
    }
    
    // MARK: - Deployment Management
    
    /// Get deployment history for an application
    /// - Parameters:
    ///   - applicationId: The application ID
    ///   - organizationId: Optional organization ID (nil for user applications)
    ///   - filter: Optional deployment filter parameters
    /// - Returns: Publisher with array of CCDeployment objects
    public func getDeployments(
        applicationId: String,
        organizationId: String? = nil,
        filter: CCDeploymentFilter? = nil
    ) -> AnyPublisher<[CCDeployment], CCError> {
        print("🚀 CCDeploymentService.getDeployments() called for app: \(applicationId)")
        
        let endpoint: String
        if let orgId = organizationId {
            endpoint = "/organisations/\(orgId)/applications/\(applicationId)/deployments"
        } else {
            endpoint = "/self/applications/\(applicationId)/deployments"
        }
        
        var queryItems: [String] = []
        
        // Add filter parameters if provided
        if let filter = filter {
            if let states = filter.states, !states.isEmpty {
                queryItems.append("state=\(states.joined(separator: ","))")
            }
            if let actions = filter.actions, !actions.isEmpty {
                queryItems.append("action=\(actions.joined(separator: ","))")
            }
            if let since = filter.since {
                queryItems.append("since=\(ISO8601DateFormatter().string(from: since))")
            }
            if let until = filter.until {
                queryItems.append("until=\(ISO8601DateFormatter().string(from: until))")
            }
            if let commit = filter.commit {
                queryItems.append("commit=\(commit)")
            }
            if let branch = filter.branch {
                queryItems.append("branch=\(branch)")
            }
            if let triggeredBy = filter.triggeredBy {
                queryItems.append("triggered_by=\(triggeredBy)")
            }
            if let limit = filter.limit {
                queryItems.append("limit=\(String(limit))")
            }
            if let offset = filter.offset {
                queryItems.append("offset=\(String(offset))")
            }
        }
        
        let finalEndpoint = queryItems.isEmpty ? endpoint : "\(endpoint)?\(queryItems.joined(separator: "&"))"
        return httpClient.get(finalEndpoint, apiVersion: .v2)
    }
    
    /// Get a specific deployment
    /// - Parameters:
    ///   - deploymentId: The deployment ID
    ///   - applicationId: The application ID
    ///   - organizationId: Optional organization ID (nil for user applications)
    /// - Returns: Publisher with CCDeployment object
    public func getDeployment(
        deploymentId: String,
        applicationId: String,
        organizationId: String? = nil
    ) -> AnyPublisher<CCDeployment, CCError> {
        print("🔍 CCDeploymentService.getDeployment() called for deployment: \(deploymentId)")
        
        let endpoint: String
        if let orgId = organizationId {
            endpoint = "/organisations/\(orgId)/applications/\(applicationId)/deployments/\(deploymentId)"
        } else {
            endpoint = "/self/applications/\(applicationId)/deployments/\(deploymentId)"
        }
        
        return httpClient.get(endpoint, apiVersion: .v2)
    }
    
    /// Create a new deployment
    /// - Parameters:
    ///   - applicationId: The application ID
    ///   - deployment: CCDeploymentCreate object with deployment details
    ///   - organizationId: Optional organization ID (nil for user applications)
    /// - Returns: Publisher with created CCDeployment object
    public func createDeployment(
        applicationId: String,
        deployment: CCDeploymentCreate,
        organizationId: String? = nil
    ) -> AnyPublisher<CCDeployment, CCError> {
        print("🚀 CCDeploymentService.createDeployment() called for app: \(applicationId)")
        
        let endpoint: String
        if let orgId = organizationId {
            endpoint = "/organisations/\(orgId)/applications/\(applicationId)/deployments"
        } else {
            endpoint = "/self/applications/\(applicationId)/deployments"
        }
        
        return httpClient.post(endpoint, body: deployment, apiVersion: .v2)
    }
    
    /// Cancel a running deployment
    /// - Parameters:
    ///   - deploymentId: The deployment ID
    ///   - applicationId: The application ID
    ///   - organizationId: Optional organization ID (nil for user applications)
    ///   - cancellation: Optional cancellation details
    /// - Returns: Publisher indicating completion
    public func cancelDeployment(
        deploymentId: String,
        applicationId: String,
        organizationId: String? = nil,
        cancellation: CCDeploymentCancel? = nil
    ) -> AnyPublisher<EmptyResponse, CCError> {
        print("🛑 CCDeploymentService.cancelDeployment() called for deployment: \(deploymentId)")
        
        let endpoint: String
        if let orgId = organizationId {
            endpoint = "/organisations/\(orgId)/applications/\(applicationId)/deployments/\(deploymentId)/cancel"
        } else {
            endpoint = "/self/applications/\(applicationId)/deployments/\(deploymentId)/cancel"
        }
        
        let body = cancellation ?? CCDeploymentCancel()
        return httpClient.post(endpoint, body: body, apiVersion: .v2)
    }
    
    // MARK: - Deployment Logs
    
    /// Get deployment logs
    /// - Parameters:
    ///   - deploymentId: The deployment ID
    ///   - applicationId: The application ID
    ///   - organizationId: Optional organization ID (nil for user applications)
    ///   - since: Optional timestamp to get logs since
    ///   - limit: Optional limit for number of log entries
    /// - Returns: Publisher with array of CCDeploymentLog objects
    public func getDeploymentLogs(
        deploymentId: String,
        applicationId: String,
        organizationId: String? = nil,
        since: Date? = nil,
        limit: Int? = nil
    ) -> AnyPublisher<[CCDeploymentLog], CCError> {
        print("📄 CCDeploymentService.getDeploymentLogs() called for deployment: \(deploymentId)")
        
        let endpoint: String
        if let orgId = organizationId {
            endpoint = "/organisations/\(orgId)/applications/\(applicationId)/deployments/\(deploymentId)/logs"
        } else {
            endpoint = "/self/applications/\(applicationId)/deployments/\(deploymentId)/logs"
        }
        
        var queryItems: [String] = []
        if let since = since {
            queryItems.append("since=\(ISO8601DateFormatter().string(from: since))")
        }
        if let limit = limit {
            queryItems.append("limit=\(String(limit))")
        }
        
        let finalEndpoint = queryItems.isEmpty ? endpoint : "\(endpoint)?\(queryItems.joined(separator: "&"))"
        return httpClient.get(finalEndpoint, apiVersion: .v2)
    }
    
    /// Stream deployment logs in real-time
    /// - Parameters:
    ///   - deploymentId: The deployment ID
    ///   - applicationId: The application ID
    ///   - organizationId: Optional organization ID (nil for user applications)
    /// - Returns: Publisher with streaming CCDeploymentLog objects
    public func streamDeploymentLogs(
        deploymentId: String,
        applicationId: String,
        organizationId: String? = nil
    ) -> AnyPublisher<CCDeploymentLog, CCError> {
        print("📡 CCDeploymentService.streamDeploymentLogs() called for deployment: \(deploymentId)")
        
        // Note: This would typically use Server-Sent Events (SSE) or WebSocket
        // For now, we'll use polling as a fallback implementation
        return Timer.publish(every: 2.0, on: .main, in: .common)
            .autoconnect()
            .flatMap { _ in
                self.getDeploymentLogs(
                    deploymentId: deploymentId,
                    applicationId: applicationId,
                    organizationId: organizationId,
                    since: Date().addingTimeInterval(-10) // Last 10 seconds
                )
            }
            .flatMap { logs in
                Publishers.Sequence(sequence: logs)
                    .setFailureType(to: CCError.self)
            }
            .eraseToAnyPublisher()
    }
    
    // MARK: - Quick Actions
    
    /// Restart an application (create a restart deployment)
    /// - Parameters:
    ///   - applicationId: The application ID
    ///   - organizationId: Optional organization ID (nil for user applications)
    /// - Returns: Publisher with created CCDeployment object
    public func restartApplication(
        applicationId: String,
        organizationId: String? = nil
    ) -> AnyPublisher<CCDeployment, CCError> {
        print("🔄 CCDeploymentService.restartApplication() called for app: \(applicationId)")
        
        let endpoint: String
        if let orgId = organizationId {
            endpoint = "/organisations/\(orgId)/applications/\(applicationId)/restart"
        } else {
            endpoint = "/self/applications/\(applicationId)/restart"
        }
        
        return httpClient.post(endpoint, body: EmptyRequest(), apiVersion: .v2)
    }
    
    /// Redeploy an application with the same configuration
    /// - Parameters:
    ///   - applicationId: The application ID
    ///   - organizationId: Optional organization ID (nil for user applications)
    /// - Returns: Publisher with created CCDeployment object
    public func redeployApplication(
        applicationId: String,
        organizationId: String? = nil
    ) -> AnyPublisher<CCDeployment, CCError> {
        print("🔁 CCDeploymentService.redeployApplication() called for app: \(applicationId)")
        
        let endpoint: String
        if let orgId = organizationId {
            endpoint = "/organisations/\(orgId)/applications/\(applicationId)/redeploy"
        } else {
            endpoint = "/self/applications/\(applicationId)/redeploy"
        }
        
        return httpClient.post(endpoint, body: EmptyRequest(), apiVersion: .v2)
    }
    
    /// Stop an application (undeploy)
    /// - Parameters:
    ///   - applicationId: The application ID
    ///   - organizationId: Optional organization ID (nil for user applications)
    /// - Returns: Publisher with created CCDeployment object
    public func stopApplication(
        applicationId: String,
        organizationId: String? = nil
    ) -> AnyPublisher<CCDeployment, CCError> {
        print("⏹️ CCDeploymentService.stopApplication() called for app: \(applicationId)")
        
        let endpoint: String
        if let orgId = organizationId {
            endpoint = "/organisations/\(orgId)/applications/\(applicationId)/stop"
        } else {
            endpoint = "/self/applications/\(applicationId)/stop"
        }
        
        return httpClient.post(endpoint, body: EmptyRequest(), apiVersion: .v2)
    }
    
    // MARK: - Git Integration
    
    /// Deploy from a specific Git commit
    /// - Parameters:
    ///   - applicationId: The application ID
    ///   - commit: Git commit SHA
    ///   - branch: Optional branch name
    ///   - organizationId: Optional organization ID (nil for user applications)
    /// - Returns: Publisher with created CCDeployment object
    public func deployFromCommit(
        applicationId: String,
        commit: String,
        branch: String? = nil,
        organizationId: String? = nil
    ) -> AnyPublisher<CCDeployment, CCError> {
        print("📦 CCDeploymentService.deployFromCommit() called for app: \(applicationId), commit: \(commit)")
        
        let deployment = CCDeploymentCreate(
            commit: commit,
            branch: branch
        )
        
        return createDeployment(
            applicationId: applicationId,
            deployment: deployment,
            organizationId: organizationId
        )
    }
    
    /// Deploy from a specific Git branch
    /// - Parameters:
    ///   - applicationId: The application ID
    ///   - branch: Git branch name
    ///   - organizationId: Optional organization ID (nil for user applications)
    /// - Returns: Publisher with created CCDeployment object
    public func deployFromBranch(
        applicationId: String,
        branch: String,
        organizationId: String? = nil
    ) -> AnyPublisher<CCDeployment, CCError> {
        print("🌿 CCDeploymentService.deployFromBranch() called for app: \(applicationId), branch: \(branch)")
        
        let deployment = CCDeploymentCreate(branch: branch)
        
        return createDeployment(
            applicationId: applicationId,
            deployment: deployment,
            organizationId: organizationId
        )
    }
    
    // MARK: - Deployment Analytics
    
    /// Get deployment statistics for an application
    /// - Parameters:
    ///   - applicationId: The application ID
    ///   - period: Time period for statistics (e.g., "7d", "30d", "90d")
    ///   - organizationId: Optional organization ID (nil for user applications)
    /// - Returns: Publisher with CCDeploymentStats object
    public func getDeploymentStats(
        applicationId: String,
        period: String = "30d",
        organizationId: String? = nil
    ) -> AnyPublisher<CCDeploymentStats, CCError> {
        print("📊 CCDeploymentService.getDeploymentStats() called for app: \(applicationId), period: \(period)")
        
        let endpoint: String
        if let orgId = organizationId {
            endpoint = "/organisations/\(orgId)/applications/\(applicationId)/deployments/stats"
        } else {
            endpoint = "/self/applications/\(applicationId)/deployments/stats"
        }
        
        let endpointWithParams = "\(endpoint)?period=\(period)"
        return httpClient.get(endpointWithParams, apiVersion: .v2)
    }
    
    // MARK: - Deployment Monitoring
    
    /// Get active deployments across all applications
    /// - Parameter organizationId: Optional organization ID (nil for user applications)
    /// - Returns: Publisher with array of active CCDeployment objects
    public func getActiveDeployments(
        organizationId: String? = nil
    ) -> AnyPublisher<[CCDeployment], CCError> {
        print("⚡ CCDeploymentService.getActiveDeployments() called")
        
        let endpoint: String
        if let orgId = organizationId {
            endpoint = "/organisations/\(orgId)/deployments/active"
        } else {
            endpoint = "/self/deployments/active"
        }
        
        return httpClient.get(endpoint, apiVersion: .v2)
    }
    
    /// Get recent deployments across all applications
    /// - Parameters:
    ///   - limit: Maximum number of deployments to return
    ///   - organizationId: Optional organization ID (nil for user applications)
    /// - Returns: Publisher with array of recent CCDeployment objects
    public func getRecentDeployments(
        limit: Int = 20,
        organizationId: String? = nil
    ) -> AnyPublisher<[CCDeployment], CCError> {
        print("🕐 CCDeploymentService.getRecentDeployments() called with limit: \(limit)")
        
        let endpoint: String
        if let orgId = organizationId {
            endpoint = "/organisations/\(orgId)/deployments/recent"
        } else {
            endpoint = "/self/deployments/recent"
        }
        
        let endpointWithParams = "\(endpoint)?limit=\(limit)"
        return httpClient.get(endpointWithParams, apiVersion: .v2)
    }
    
    // MARK: - Convenience Methods
    
    /// Get deployment status with automatic refresh
    /// - Parameters:
    ///   - deploymentId: The deployment ID
    ///   - applicationId: The application ID
    ///   - organizationId: Optional organization ID (nil for user applications)
    ///   - refreshInterval: Refresh interval in seconds (default: 5)
    /// - Returns: Publisher with CCDeployment objects that updates automatically
    public func monitorDeployment(
        deploymentId: String,
        applicationId: String,
        organizationId: String? = nil,
        refreshInterval: TimeInterval = 5.0
    ) -> AnyPublisher<CCDeployment, CCError> {
        print("👀 CCDeploymentService.monitorDeployment() called for deployment: \(deploymentId)")
        
        return Timer.publish(every: refreshInterval, on: .main, in: .common)
            .autoconnect()
            .prepend(Date()) // Emit immediately
            .flatMap { _ in
                self.getDeployment(
                    deploymentId: deploymentId,
                    applicationId: applicationId,
                    organizationId: organizationId
                )
            }
            .removeDuplicates() // Only emit when deployment actually changes
            .eraseToAnyPublisher()
    }
    
    /// Get deployments with enhanced data (includes application info)
    /// - Parameters:
    ///   - applicationId: The application ID
    ///   - organizationId: Optional organization ID (nil for user applications)
    ///   - filter: Optional deployment filter parameters
    /// - Returns: Publisher with array of deployments with enhanced information
    public func getDeploymentsWithApplicationInfo(
        applicationId: String,
        organizationId: String? = nil,
        filter: CCDeploymentFilter? = nil
    ) -> AnyPublisher<[CCDeploymentWithApp], CCError> {
        print("🔗 CCDeploymentService.getDeploymentsWithApplicationInfo() called for app: \(applicationId)")
        
        return getDeployments(
            applicationId: applicationId,
            organizationId: organizationId,
            filter: filter
        )
        .flatMap { deployments -> AnyPublisher<[CCDeploymentWithApp], CCError> in
            guard deployments.count >= 0 else {
                return Fail(error: CCError.invalidParameters("Invalid deployments data"))
                    .eraseToAnyPublisher()
            }
            
            // For now, we'll create enhanced objects without fetching app info
            // In a real implementation, you might want to fetch application details
            let enhancedDeployments = deployments.map { deployment in
                CCDeploymentWithApp(deployment: deployment, applicationName: "App \(applicationId)")
            }
            
            return Just(enhancedDeployments)
                .setFailureType(to: CCError.self)
                .eraseToAnyPublisher()
        }
        .eraseToAnyPublisher()
    }
}

// MARK: - Supporting Models

/// Enhanced deployment model with application information
public struct CCDeploymentWithApp: Identifiable {
    public let id: String
    public let deployment: CCDeployment
    public let applicationName: String
    
    public init(deployment: CCDeployment, applicationName: String) {
        self.id = deployment.id
        self.deployment = deployment
        self.applicationName = applicationName
    }
    
    /// Combined display title
    public var displayTitle: String {
        return "\(applicationName): \(deployment.displayAction)"
    }
}

// EmptyRequest and EmptyResponse are now defined in CCCommon.swift 