import Foundation
import Combine

/// Main SDK class for Clever Cloud API integration with OAuth 1.0a authentication
public final class CleverCloudSDK: ObservableObject {
    
    // MARK: - Properties
    
    /// HTTP client for API communication
    public let httpClient: CCHTTPClient
    
    /// Application service for app management
    public let applications: CCApplicationService
    
    /// Organization service for organization management
    public let organizations: CCOrganizationService
    
    /// Add-on service for database and cache management
    public let addons: CCAddonService
    
    /// Deployment service for application deployment management
    public let deployments: CCDeploymentService
    
    /// Environment service for managing variables and configuration
    public let environment: CCEnvironmentService
    
    /// Network Groups service for revolutionary networking features
    public let networkGroups: CCNetworkGroupService
    
    /// Events service for real-time updates and notifications
    public let events: CCEventsService
    
    /// SDK configuration
    public let configuration: CCConfiguration
    
    // MARK: - Published Properties
    
    /// Current authentication state
    @Published public private(set) var isAuthenticated: Bool = false
    
    /// SDK initialization state
    @Published public private(set) var isInitialized: Bool = false
    
    /// Last error that occurred
    @Published public private(set) var lastError: CCError?
    
    /// Debug logging enabled state
    public var isDebugLoggingEnabled: Bool {
        return configuration.enableDebugLogging
    }
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Static Properties
    
    /// SDK version
    public static let version = "2.0.0"
    
    // MARK: - Initialization
    
    /// Initialize Clever Cloud SDK with OAuth 1.0a
    /// - Parameter configuration: SDK configuration with OAuth tokens
    public init(configuration: CCConfiguration) {
        self.configuration = configuration
        self.httpClient = CCHTTPClient(configuration: configuration)
        self.applications = CCApplicationService(httpClient: httpClient)
        self.organizations = CCOrganizationService(httpClient: httpClient)
        self.addons = CCAddonService(httpClient: httpClient)
        self.deployments = CCDeploymentService(httpClient: httpClient)
        self.environment = CCEnvironmentService(httpClient: httpClient)
        self.networkGroups = CCNetworkGroupService(httpClient: httpClient)
        self.events = CCEventsService(baseURL: CCConfiguration.apiV2BaseURL, oauthSigner: CCOAuthSigner(configuration: configuration))
        
        // Set initial authentication state
        self.isAuthenticated = configuration.isAuthenticated
        self.isInitialized = true
        
        if configuration.enableDebugLogging {
            let authType = configuration.hasOAuthTokens ? "OAuth 1.0a" : "Bearer Token (legacy)"
            RemoteLogger.shared.info("🚀 [CleverCloudSDK] v\(Self.version) Initialized with \(authType)")
            if configuration.hasOAuthTokens {
                RemoteLogger.shared.debug("🔑 [CleverCloudSDK] Consumer: \(configuration.consumerKey)")
                RemoteLogger.shared.debug("🎫 [CleverCloudSDK] Token: \(String(configuration.accessToken.prefix(8)))...")
            }
        }
    }
    
    // MARK: - Error Management
    
    /// Clear the last error
    public func clearLastError() {
        lastError = nil
    }
    
    /// Set error and update authentication state if needed
    /// - Parameter error: Error to set
    private func setError(_ error: CCError) {
        lastError = error
        
        // Update authentication state for auth errors
        if error.isAuthenticationError {
            isAuthenticated = false
        }
        
        if configuration.enableDebugLogging {
            RemoteLogger.shared.error("❌ [CleverCloudSDK] Error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Utility Methods
    
    /// Get current SDK configuration
    public var currentConfiguration: CCConfiguration {
        return configuration
    }
    
    // MARK: - Quick Access Methods
    
    /// Quick method to get all user applications
    /// - Returns: Publisher with applications array
    public func getUserApplications() -> AnyPublisher<[CCApplication], CCError> {
        return applications.getApplications()
            .handleEvents(receiveCompletion: { [weak self] completion in
                if case .failure(let error) = completion {
                    self?.setError(error)
                }
            })
            .eraseToAnyPublisher()
    }
    
    /// Quick method to get applications for a specific organization
    /// - Parameter organizationId: Organization identifier
    /// - Returns: Publisher with applications array
    public func getOrganizationApplications(organizationId: String) -> AnyPublisher<[CCApplication], CCError> {
        return applications.getApplications(forOrganization: organizationId)
            .handleEvents(receiveCompletion: { [weak self] completion in
                if case .failure(let error) = completion {
                    self?.setError(error)
                }
            })
            .eraseToAnyPublisher()
    }
    
    /// Quick method to get application details
    /// - Parameter applicationId: Application identifier
    /// - Returns: Publisher with application details
    public func getApplication(id applicationId: String) -> AnyPublisher<CCApplication, CCError> {
        return applications.getApplication(applicationId: applicationId)
            .handleEvents(receiveCompletion: { [weak self] completion in
                if case .failure(let error) = completion {
                    self?.setError(error)
                }
            })
            .eraseToAnyPublisher()
    }
    
    
    /// Quick method to get all organizations
    /// - Returns: Publisher with organizations array
    public func getUserOrganizations() -> AnyPublisher<[CCOrganization], CCError> {
        return organizations.getAllOrganizations()
            .handleEvents(receiveCompletion: { [weak self] completion in
                if case .failure(let error) = completion {
                    self?.setError(error)
                }
            })
            .eraseToAnyPublisher()
    }
    
    /// Quick method to get user profile (personal space)
    /// - Returns: Publisher with user organization data
    public func getUserProfile() -> AnyPublisher<CCOrganization, CCError> {
        return organizations.getUserProfile()
            .handleEvents(receiveCompletion: { [weak self] completion in
                if case .failure(let error) = completion {
                    self?.setError(error)
                }
            })
            .eraseToAnyPublisher()
    }
    
    /// Quick method to get specific organization
    /// - Parameter organizationId: Organization identifier
    /// - Returns: Publisher with organization details
    public func getOrganization(id organizationId: String) -> AnyPublisher<CCOrganization, CCError> {
        return organizations.getOrganization(id: organizationId)
            .handleEvents(receiveCompletion: { [weak self] completion in
                if case .failure(let error) = completion {
                    self?.setError(error)
                }
            })
            .eraseToAnyPublisher()
    }
    
    /// Quick method to get all user add-ons
    /// - Returns: Publisher with add-ons array
    public func getUserAddons() -> AnyPublisher<[CCAddon], CCError> {
        return addons.getUserAddons()
            .handleEvents(receiveCompletion: { [weak self] completion in
                if case .failure(let error) = completion {
                    self?.setError(error)
                }
            })
            .eraseToAnyPublisher()
    }
    
    /// Quick method to get add-ons for a specific organization
    /// - Parameter organizationId: Organization identifier
    /// - Returns: Publisher with add-ons array
    public func getOrganizationAddons(organizationId: String) -> AnyPublisher<[CCAddon], CCError> {
        return addons.getAddons(forOrganization: organizationId)
            .handleEvents(receiveCompletion: { [weak self] completion in
                if case .failure(let error) = completion {
                    self?.setError(error)
                }
            })
            .eraseToAnyPublisher()
    }
    
    /// Quick method to get add-on details
    /// - Parameter addonId: Add-on identifier
    /// - Returns: Publisher with add-on details
    public func getAddon(id addonId: String) -> AnyPublisher<CCAddon, CCError> {
        return addons.getAddon(addonId: addonId)
            .handleEvents(receiveCompletion: { [weak self] completion in
                if case .failure(let error) = completion {
                    self?.setError(error)
                }
            })
            .eraseToAnyPublisher()
    }
    
    /// Quick method to create a new add-on
    /// - Parameters:
    ///   - name: Add-on name
    ///   - providerId: Provider ID (e.g., "postgresql", "redis")
    ///   - planId: Plan ID (e.g., "dev", "s", "m", "l")
    ///   - region: Region where to deploy (default: "par")
    /// - Returns: Publisher with created add-on
    public func createAddon(
        name: String,
        providerId: String,
        planId: String,
        region: String = "par"
    ) -> AnyPublisher<CCAddon, CCError> {
        let addonCreate = CCAddonCreate(
            providerId: providerId,
            name: name,
            planId: planId,
            region: region
        )
        
        return addons.createAddon(addonCreate)
            .handleEvents(receiveCompletion: { [weak self] completion in
                if case .failure(let error) = completion {
                    self?.setError(error)
                }
            })
            .eraseToAnyPublisher()
    }
    
    /// Quick method to get all available add-on providers
    /// - Returns: Publisher with providers array
    public func getAddonProviders() -> AnyPublisher<[CCAddonProvider], CCError> {
        return addons.getAddonProviders()
            .handleEvents(receiveCompletion: { [weak self] completion in
                if case .failure(let error) = completion {
                    self?.setError(error)
                }
            })
            .eraseToAnyPublisher()
    }
    
    // MARK: - Deployment Quick Access Methods
    
    /// Quick method to get deployments for an application
    /// - Parameters:
    ///   - applicationId: Application identifier
    ///   - organizationId: Optional organization identifier
    /// - Returns: Publisher with deployments array
    public func getApplicationDeployments(
        applicationId: String,
        organizationId: String? = nil
    ) -> AnyPublisher<[CCDeployment], CCError> {
        return deployments.getDeployments(applicationId: applicationId, organizationId: organizationId)
            .handleEvents(receiveCompletion: { [weak self] completion in
                if case .failure(let error) = completion {
                    self?.setError(error)
                }
            })
            .eraseToAnyPublisher()
    }
    
    /// Quick method to restart an application
    /// - Parameters:
    ///   - applicationId: Application identifier
    ///   - organizationId: Optional organization identifier
    /// - Returns: Publisher with deployment object
    public func restartApplication(
        applicationId: String,
        organizationId: String? = nil
    ) -> AnyPublisher<CCDeployment, CCError> {
        return deployments.restartApplication(applicationId: applicationId, organizationId: organizationId)
            .handleEvents(receiveCompletion: { [weak self] completion in
                if case .failure(let error) = completion {
                    self?.setError(error)
                }
            })
            .eraseToAnyPublisher()
    }
    
    /// Quick method to get active deployments
    /// - Parameter organizationId: Optional organization identifier
    /// - Returns: Publisher with active deployments array
    public func getActiveDeployments(organizationId: String? = nil) -> AnyPublisher<[CCDeployment], CCError> {
        return deployments.getActiveDeployments(organizationId: organizationId)
            .handleEvents(receiveCompletion: { [weak self] completion in
                if case .failure(let error) = completion {
                    self?.setError(error)
                }
            })
            .eraseToAnyPublisher()
    }
    
    // MARK: - Environment Quick Access Methods
    
    /// Quick method to get environment variables for an application
    /// - Parameter applicationId: Application identifier
    /// - Returns: Publisher with environment variables response
    public func getEnvironmentVariables(for applicationId: String) -> AnyPublisher<CCEnvironmentVariablesResponse, CCError> {
        return environment.getEnvironmentVariables(for: applicationId)
            .handleEvents(receiveCompletion: { [weak self] completion in
                if case .failure(let error) = completion {
                    self?.setError(error)
                }
            })
            .eraseToAnyPublisher()
    }
    
    /// Quick method to set an environment variable
    /// - Parameters:
    ///   - applicationId: Application identifier
    ///   - name: Variable name
    ///   - value: Variable value
    ///   - isSecret: Whether the variable should be treated as secret
    /// - Returns: Publisher with success response
    public func setEnvironmentVariable(
        for applicationId: String,
        name: String,
        value: String,
        isSecret: Bool = false
    ) -> AnyPublisher<CCConfigurationUpdateResponse, CCError> {
        let variable = CCEnvironmentVariableUpdate(name: name, value: value, isSecret: isSecret)
        return environment.setEnvironmentVariable(for: applicationId, variable: variable)
            .handleEvents(receiveCompletion: { [weak self] completion in
                if case .failure(let error) = completion {
                    self?.setError(error)
                }
            })
            .eraseToAnyPublisher()
    }
    
    /// Quick method to get application domains
    /// - Parameter applicationId: Application identifier
    /// - Returns: Publisher with domains array
    public func getApplicationDomains(for applicationId: String) -> AnyPublisher<[String], CCError> {
        return environment.getApplicationDomains(for: applicationId)
            .handleEvents(receiveCompletion: { [weak self] completion in
                if case .failure(let error) = completion {
                    self?.setError(error)
                }
            })
            .eraseToAnyPublisher()
    }
    
    /// Quick method to get environment templates
    /// - Returns: Publisher with environment templates
    public func getEnvironmentTemplates() -> AnyPublisher<[CCEnvironmentVariableUpdate], CCError> {
        return environment.getEnvironmentTemplates()
            .handleEvents(receiveCompletion: { [weak self] completion in
                if case .failure(let error) = completion {
                    self?.setError(error)
                }
            })
            .eraseToAnyPublisher()
    }
    
    // MARK: - Network Groups Quick Access Methods - DISABLED until Clever Cloud stabilizes Network Groups

    /// Quick method to get all network groups for an organization - DISABLED
    /// - Parameter organizationId: Organization identifier
    /// - Returns: Publisher with network groups array
    public func getNetworkGroups(for organizationId: String) -> AnyPublisher<[CCNetworkGroup], CCError> {
        return networkGroups.getNetworkGroups(organizationId: organizationId)
            .handleEvents(receiveCompletion: { [weak self] completion in
                if case .failure(let error) = completion {
                    self?.setError(error)
                }
            })
            .eraseToAnyPublisher()
    }

    /// Quick method to create a new network group - DISABLED
    /// - Parameters:
    ///   - organizationId: Organization identifier
    ///   - name: Network group name
    ///   - description: Network group description (optional)
    ///   - cidr: Network CIDR block (optional, auto-assigned if not provided)
    ///   - region: Region where to create the network group (optional)
    /// - Returns: Publisher with created network group
    public func createNetworkGroup(
        for organizationId: String,
        name: String,
        description: String? = nil,
        cidr: String? = nil,
        region: String? = nil
    ) -> AnyPublisher<CCNetworkGroup, CCError> {
        let networkGroupCreate = CCNetworkGroupCreate(
            name: name,
            description: description,
            cidr: cidr,
            region: region
        )

        return networkGroups.createNetworkGroup(organizationId: organizationId, networkGroup: networkGroupCreate)
            .handleEvents(receiveCompletion: { [weak self] completion in
                if case .failure(let error) = completion {
                    self?.setError(error)
                }
            })
            .eraseToAnyPublisher()
    }

    /// Quick method to get comprehensive network group data - DISABLED
    /// - Parameters:
    ///   - organizationId: Organization identifier
    ///   - networkGroupId: Network group identifier
    /// - Returns: Publisher with complete network group data (group + members + peers)
    public func getCompleteNetworkGroupData(
        organizationId: String,
        networkGroupId: String
    ) -> AnyPublisher<(CCNetworkGroup, [CCNetworkGroupMember], [CCNetworkGroupPeer]), CCError> {
        return networkGroups.getCompleteNetworkGroupData(organizationId: organizationId, networkGroupId: networkGroupId)
            .handleEvents(receiveCompletion: { [weak self] completion in
                if case .failure(let error) = completion {
                    self?.setError(error)
                }
            })
            .eraseToAnyPublisher()
    }

    /// Quick method to add an application to a network group - DISABLED
    /// - Parameters:
    ///   - organizationId: Organization identifier
    ///   - networkGroupId: Network group identifier
    ///   - applicationId: Application identifier to add
    /// - Returns: Publisher with added member
    public func addApplicationToNetworkGroup(
        organizationId: String,
        networkGroupId: String,
        applicationId: String
    ) -> AnyPublisher<CCNetworkGroupMember, CCError> {
        return networkGroups.addApplicationToNetworkGroup(
            organizationId: organizationId,
            networkGroupId: networkGroupId,
            applicationId: applicationId
        )
        .handleEvents(receiveCompletion: { [weak self] completion in
            if case .failure(let error) = completion {
                self?.setError(error)
            }
        })
        .eraseToAnyPublisher()
    }

    /// Quick method to get WireGuard configuration for a peer - DISABLED
    /// - Parameters:
    ///   - organizationId: Organization identifier
    ///   - networkGroupId: Network group identifier
    ///   - peerId: Peer identifier
    /// - Returns: Publisher with WireGuard configuration
    public func getWireGuardConfiguration(
        organizationId: String,
        networkGroupId: String,
        peerId: String
    ) -> AnyPublisher<CCWireGuardConfiguration, CCError> {
        return networkGroups.getWireGuardConfiguration(
            organizationId: organizationId,
            networkGroupId: networkGroupId,
            peerId: peerId
        )
        .handleEvents(receiveCompletion: { [weak self] completion in
            if case .failure(let error) = completion {
                self?.setError(error)
            }
        })
        .eraseToAnyPublisher()
    }
    
    // MARK: - Authentication Testing
    
    /// Test authentication by making a simple API call
    /// - Returns: Publisher indicating authentication success
    public func testAuthentication() -> AnyPublisher<Bool, CCError> {
        return getUserProfile()
            .map { _ in true }
            .handleEvents(receiveCompletion: { [weak self] completion in
                if case .failure(let error) = completion {
                    self?.setError(error)
                }
            })
            .eraseToAnyPublisher()
    }
    
    // MARK: - Authentication Status
    
    /// Réinitialise l'authentification (supprime les credentials stockés)
    public func resetAuthentication() {
        RemoteLogger.shared.info("🔄 CleverCloudSDK: Resetting authentication...")
        
        // Clear configuration tokens
        configuration.clearTokens()
        
        // Clear keychain
        let keychain = CCKeychainManager()
        keychain.deleteCredentials()
        
        // Reset state
        isAuthenticated = false
        lastError = nil
        
        RemoteLogger.shared.info("✅ CleverCloudSDK: Authentication reset complete")
    }
}

// MARK: - SDK Factory

/// Factory for creating CleverCloudSDK instances
public enum CleverCloudSDKFactory {
    
    /// Create SDK instance with OAuth 1.0a tokens
    /// - Parameters:
    ///   - consumerKey: OAuth consumer key
    ///   - consumerSecret: OAuth consumer secret  
    ///   - accessToken: OAuth access token
    ///   - accessTokenSecret: OAuth access token secret
    ///   - enableDebugLogging: Enable debug logging
    /// - Returns: Configured SDK instance
    public static func create(
        consumerKey: String,
        consumerSecret: String,
        accessToken: String,
        accessTokenSecret: String,
        enableDebugLogging: Bool = false
    ) -> CleverCloudSDK {
        let configuration = CCConfiguration(
            consumerKey: consumerKey,
            consumerSecret: consumerSecret,
            accessToken: accessToken,
            accessTokenSecret: accessTokenSecret,
            enableDebugLogging: enableDebugLogging
        )
        
        return CleverCloudSDK(configuration: configuration)
    }
    
    /// Create SDK for development/testing with legacy Bearer token
    /// - Parameters:
    ///   - apiToken: Legacy API token
    ///   - enableDebugLogging: Enable debug logging
    /// - Returns: Configured SDK instance
    @available(*, deprecated, message: "Use OAuth 1.0a create method instead")
    public static func createForDevelopment(
        apiToken: String,
        enableDebugLogging: Bool = true
    ) -> CleverCloudSDK {
        let configuration = CCConfiguration(
            apiToken: apiToken,
            enableDebugLogging: enableDebugLogging
        )
        
        return CleverCloudSDK(configuration: configuration)
    }
    
    /// Create SDK for production with OAuth 1.0a tokens and optimized settings
    /// - Parameters:
    ///   - consumerKey: OAuth consumer key
    ///   - consumerSecret: OAuth consumer secret
    ///   - accessToken: OAuth access token
    ///   - accessTokenSecret: OAuth access token secret
    /// - Returns: Configured SDK instance for production
    public static func createForProduction(
        consumerKey: String,
        consumerSecret: String,
        accessToken: String,
        accessTokenSecret: String
    ) -> CleverCloudSDK {
        let configuration = CCConfiguration(
            consumerKey: consumerKey,
            consumerSecret: consumerSecret,
            accessToken: accessToken,
            accessTokenSecret: accessTokenSecret,
            enableDebugLogging: false
        )
        
        return CleverCloudSDK(configuration: configuration)
    }
} 