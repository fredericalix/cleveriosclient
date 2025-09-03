import Foundation
import SwiftUI
import Combine

@MainActor
class CleverCloudViewModel: ObservableObject {
    
    // MARK: - CleverCloud SDK
    private let _cleverCloudSDK: CleverCloudSDK
    
    /// Access to the CleverCloud SDK
    public var cleverCloudSDK: CleverCloudSDK {
        return _cleverCloudSDK
    }
    
    // MARK: - Published Properties
    @Published var applications: [CCApplication] = []
    @Published var organizations: [CCOrganization] = []
    @Published var addons: [CCAddon] = []
    @Published var addonProviders: [CCAddonProvider] = []
    
    // MARK: - UI State
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var loadingMessage: String = ""
    
    // MARK: - Organization Selection
    @Published var selectedOrganization: String = ""
    
    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Computed Properties
    var selectedOrganizationObject: CCOrganization? {
        return organizations.first { $0.id == selectedOrganization }
    }
    
    // MARK: - Initialization
    
    init(cleverCloudSDK: CleverCloudSDK) {
        self._cleverCloudSDK = cleverCloudSDK
        // Load organizations after initialization
        DispatchQueue.main.async {
            self.loadOrganizations()
        }
    }
    
    // MARK: - Organization Methods
    
    func loadOrganizations() {
        RemoteLogger.shared.info("🎯 Loading ALL organizations (using organizations endpoint)")
        isLoading = true
        loadingMessage = "Loading organizations..."
        errorMessage = nil
        
        // Load organizations directly (the personal space is included in the organizations list)
        cleverCloudSDK.getUserOrganizations()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    guard let self = self else { return }
                    self.isLoading = false
                    
                    switch completion {
                    case .finished:
                        RemoteLogger.shared.info("✅ Organizations loaded successfully: \(self.organizations.count) total")
                        
                        // Auto-select first organization if only one exists
                        if self.organizations.count == 1,
                           let firstOrg = self.organizations.first {
                            self.selectedOrganization = firstOrg.id
                            RemoteLogger.shared.info("🔄 Auto-selected single organization: \(firstOrg.name)")
                            // Automatically load applications for the single organization
                            self.autoRefreshOrganizationData()
                        }
                        
                    case .failure(let error):
                        RemoteLogger.shared.error("❌ Failed to load organizations", metadata: [
                            "error": error.localizedDescription,
                            "errorType": String(describing: type(of: error)),
                            "underlyingError": (error as NSError).debugDescription
                        ])
                        self.errorMessage = "Failed to load organizations: \(error.localizedDescription)"
                        
                        // Log more details about the error
                        if let ccError = error as? CCError {
                            RemoteLogger.shared.error("CCError details", metadata: [
                                "code": "\(ccError)",
                                "description": ccError.localizedDescription
                            ])
                        }
                    }
                },
                receiveValue: { [weak self] organizations in
                    guard let self = self else { return }
                    
                    RemoteLogger.shared.info("📦 Received \(organizations.count) organizations from API")
                    for (index, org) in organizations.enumerated() {
                        RemoteLogger.shared.debug("Organization \(index + 1): \(org.name) (ID: \(org.id))")
                    }
                    
                    self.organizations = organizations
                    
                    if organizations.isEmpty {
                        RemoteLogger.shared.warn("⚠️ No organizations found for this user")
                        self.errorMessage = "No organizations found"
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    func autoRefreshOrganizationData() {
        guard let selectedOrg = selectedOrganizationObject else { return }
        
        print("🔄 Auto-refreshing data for organization: \(selectedOrg.name)")
        
        // Clear error states
        errorMessage = nil
        
        // Set loading state with organization context
        isLoading = true
        loadingMessage = "🔄 Switching to \(selectedOrg.name)..."
        
        // Small delay for better UX (visual feedback)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            // Auto-load applications for the new organization
            self?.testGetApplications()
            
            // Auto-load add-ons for the new organization (after applications)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.testGetAddons()
            }
        }
    }
    
    // MARK: - Application Methods
    
    func testGetApplications() {
        print("🔥 Testing: getApplications")
        
        guard let targetOrganization = selectedOrganizationObject else {
            errorMessage = "No organization selected"
            return
        }
        
        let orgName = targetOrganization.name
        let orgId = targetOrganization.id
        
        // Update UI state
        errorMessage = nil
        isLoading = true
        loadingMessage = "Loading apps for \(orgName)..."
        
        print("🧪 Testing: getApplications for organization: \(orgName)")
        print("🏢 Organization ID: \(orgId)")
        
        // Use organization-specific method if organization is selected
        let applicationsPublisher: AnyPublisher<[CCApplication], CCError>
        
        if orgId.hasPrefix("orga_") {
            // Real organization - use organization applications endpoint
            print("🏢 Loading applications for organization: \(orgName) (ID: \(orgId))")
            applicationsPublisher = cleverCloudSDK.getOrganizationApplications(organizationId: orgId)
        } else {
            // Personal space - use user applications endpoint
            print("👤 Loading applications for personal space: \(orgName)")
            applicationsPublisher = cleverCloudSDK.getUserApplications()
        }
        
        applicationsPublisher
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    self?.loadingMessage = ""
                    if case .failure(let error) = completion {
                        self?.errorMessage = "getApplications failed for \(orgName): \(error.localizedDescription)"
                        print("❌ Test Failed: getApplications for \(orgName) - \(error)")
                    } else {
                        print("✅ Test Passed: getApplications for \(orgName)")
                    }
                },
                receiveValue: { [weak self] apps in
                    self?.applications = apps
                    print("✅ SUCCESS: Loaded \(apps.count) applications for \(orgName)")
                    for app in apps {
                        print("📱 App: \(app.name) (ID: \(app.id))")
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    func testApplicationDetails() {
        guard let firstApp = applications.first else {
            errorMessage = "No applications available. Load apps first."
            return
        }
        
        isLoading = true
        loadingMessage = "Getting app details..."
        errorMessage = nil
        
        print("🧪 Testing: getApplication(id: \(firstApp.id))")
        
        cleverCloudSDK.getApplication(id: firstApp.id)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    self?.loadingMessage = ""
                    if case .failure(let error) = completion {
                        self?.errorMessage = "getApplication failed: \(error.localizedDescription)"
                        print("❌ Test Failed: getApplication - \(error)")
                    } else {
                        self?.errorMessage = "✅ App details loaded successfully!"
                        print("✅ Test Passed: getApplication")
                    }
                },
                receiveValue: { app in
                    print("✅ Test Result: Retrieved app '\(app.name)' with ID \(app.id)")
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: - Add-on Methods
    
    func testGetAddons() {
        print("🎯 Testing: getAddons")
        
        guard let targetOrganization = selectedOrganizationObject else {
            errorMessage = "No organization selected"
            return
        }
        
        let orgName = targetOrganization.name
        let orgId = targetOrganization.id
        
        // Update UI state
        errorMessage = nil
        isLoading = true
        loadingMessage = "Loading add-ons for \(orgName)..."
        
        print("🧪 Testing: getAddons for organization: \(orgName)")
        print("🏢 Organization ID: \(orgId)")
        
        // Use organization-specific method if organization is selected
        let addonsPublisher: AnyPublisher<[CCAddon], CCError>
        
        if orgId.hasPrefix("orga_") {
            // Real organization - use organization addons endpoint
            print("🏢 Loading add-ons for organization: \(orgName) (ID: \(orgId))")
            addonsPublisher = cleverCloudSDK.getOrganizationAddons(organizationId: orgId)
        } else {
            // Personal space - use user addons endpoint
            print("👤 Loading add-ons for personal space: \(orgName)")
            addonsPublisher = cleverCloudSDK.getUserAddons()
        }
        
        addonsPublisher
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    self?.loadingMessage = ""
                    if case .failure(let error) = completion {
                        self?.errorMessage = "getAddons failed for \(orgName): \(error.localizedDescription)"
                        print("❌ Test Failed: getAddons for \(orgName) - \(error)")
                    } else {
                        print("✅ Test Passed: getAddons for \(orgName)")
                    }
                },
                receiveValue: { [weak self] loadedAddons in
                    self?.addons = loadedAddons
                    print("✅ SUCCESS: Loaded \(loadedAddons.count) add-ons for \(orgName)")
                    for addon in loadedAddons {
                        print("🎯 Add-on: \(addon.displayName) (\(addon.providerDisplayName))")
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    func testAddonProviders() {
        print("🎯 Testing: getAddonProviders()")
        
        isLoading = true
        loadingMessage = "Loading add-on providers..."
        errorMessage = nil
        
        cleverCloudSDK.getAddonProviders()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    self?.loadingMessage = ""
                    if case .failure(let error) = completion {
                        self?.errorMessage = "getAddonProviders failed: \(error.localizedDescription)"
                        print("❌ Test Failed: getAddonProviders - \(error)")
                    } else {
                        self?.errorMessage = "✅ Add-on providers loaded successfully!"
                        print("✅ Test Passed: getAddonProviders")
                    }
                },
                receiveValue: { [weak self] providers in
                    self?.addonProviders = providers
                    print("✅ SUCCESS: Loaded \(providers.count) add-on providers!")
                    for provider in providers {
                        print("🎯 Provider: \(provider.name) (ID: \(provider.id))")
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: - Deployment Methods
    
    func testGetDeployments(appId: String) {
        guard !appId.isEmpty else {
            errorMessage = "No application selected"
            return
        }
        
        isLoading = true
        loadingMessage = "Loading deployments..."
        errorMessage = nil
        
        print("🚀 Testing: getDeployments for app: \(appId)")
        
        cleverCloudSDK.deployments.getDeployments(applicationId: appId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    self?.loadingMessage = ""
                    if case .failure(let error) = completion {
                        self?.errorMessage = "getDeployments failed: \(error.localizedDescription)"
                        print("❌ Test Failed: getDeployments - \(error)")
                    } else {
                        self?.errorMessage = "✅ Deployments loaded successfully!"
                        print("✅ Test Passed: getDeployments")
                    }
                },
                receiveValue: { deployments in
                    print("✅ SUCCESS: Loaded \(deployments.count) deployments!")
                    for deployment in deployments {
                        print("🚀 Deployment: \(deployment.id) - \(deployment.state)")
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    func testRestartApp(appId: String) {
        guard !appId.isEmpty else {
            errorMessage = "No application selected"
            return
        }
        
        isLoading = true
        loadingMessage = "Restarting application..."
        errorMessage = nil
        
        print("🔄 Testing: restartApplication for app: \(appId)")
        
        cleverCloudSDK.deployments.restartApplication(applicationId: appId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    self?.loadingMessage = ""
                    if case .failure(let error) = completion {
                        self?.errorMessage = "Restart failed: \(error.localizedDescription)"
                        print("❌ Test Failed: restartApplication - \(error)")
                    } else {
                        self?.errorMessage = "✅ Application restart initiated!"
                        print("✅ Test Passed: restartApplication")
                    }
                },
                receiveValue: { response in
                    print("✅ SUCCESS: Application restart response received")
                }
            )
            .store(in: &cancellables)
    }
    
    func testCreateDeployment(appId: String) {
        guard !appId.isEmpty else {
            errorMessage = "No application selected"
            return
        }
        
        isLoading = true
        loadingMessage = "Creating deployment..."
        errorMessage = nil
        
        print("🚀 Testing: createDeployment for app: \(appId)")
        
        // Create deployment from default branch
        let deploymentRequest = CCDeploymentCreate(
            commit: nil,
            repository: nil,
            branch: "main",
            environment: [:]
        )
        
        cleverCloudSDK.deployments.createDeployment(applicationId: appId, deployment: deploymentRequest)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    self?.loadingMessage = ""
                    if case .failure(let error) = completion {
                        self?.errorMessage = "Create deployment failed: \(error.localizedDescription)"
                        print("❌ Test Failed: createDeployment - \(error)")
                    } else {
                        self?.errorMessage = "✅ Deployment created successfully!"
                        print("✅ Test Passed: createDeployment")
                    }
                },
                receiveValue: { deployment in
                    print("✅ SUCCESS: Deployment created with ID: \(deployment.id)")
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: - Environment Methods
    
    func testGetEnvironmentVariables(appId: String) {
        guard !appId.isEmpty else {
            errorMessage = "No application selected"
            return
        }
        
        isLoading = true
        loadingMessage = "Loading environment variables..."
        errorMessage = nil
        
        print("🔧 Testing: getEnvironmentVariables for app: \(appId)")
        
        cleverCloudSDK.environment.getEnvironmentVariables(for: appId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    self?.loadingMessage = ""
                    if case .failure(let error) = completion {
                        self?.errorMessage = "Get env vars failed: \(error.localizedDescription)"
                        print("❌ Test Failed: getEnvironmentVariables - \(error)")
                    } else {
                        self?.errorMessage = "✅ Environment variables loaded successfully!"
                        print("✅ Test Passed: getEnvironmentVariables")
                    }
                },
                receiveValue: { response in
                    print("✅ SUCCESS: Loaded \(response.variables.count) environment variables!")
                    for variable in response.variables {
                        print("🔧 Env Var: \(variable.name) = \(variable.displayValue)")
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    func testSetEnvironmentVariable(appId: String, name: String, value: String) {
        guard !appId.isEmpty else {
            errorMessage = "No application selected"
            return
        }
        
        isLoading = true
        loadingMessage = "Setting environment variable..."
        errorMessage = nil
        
        print("🔧 Testing: setEnvironmentVariable \(name) for app: \(appId)")
        
        let variable = CCEnvironmentVariableUpdate(
            name: name,
            value: value
        )
        
        cleverCloudSDK.environment.setEnvironmentVariable(for: appId, variable: variable)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    self?.loadingMessage = ""
                    if case .failure(let error) = completion {
                        self?.errorMessage = "Set env var failed: \(error.localizedDescription)"
                        print("❌ Test Failed: setEnvironmentVariable - \(error)")
                    } else {
                        self?.errorMessage = "✅ Environment variable \(name) set successfully!"
                        print("✅ Test Passed: setEnvironmentVariable")
                    }
                },
                receiveValue: { response in
                    print("✅ SUCCESS: Environment variable \(name) set!")
                }
            )
            .store(in: &cancellables)
    }
    
    func testGetAppConfig(appId: String) {
        guard !appId.isEmpty else {
            errorMessage = "No application selected"
            return
        }
        
        isLoading = true
        loadingMessage = "Loading app configuration..."
        errorMessage = nil
        
        print("🔧 Testing: getApplicationConfiguration for app: \(appId)")
        
        cleverCloudSDK.environment.getApplicationConfiguration(for: appId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    self?.loadingMessage = ""
                    if case .failure(let error) = completion {
                        self?.errorMessage = "Get app config failed: \(error.localizedDescription)"
                        print("❌ Test Failed: getApplicationConfiguration - \(error)")
                    } else {
                        self?.errorMessage = "✅ App configuration loaded successfully!"
                        print("✅ Test Passed: getApplicationConfiguration")
                    }
                },
                receiveValue: { config in
                    print("✅ SUCCESS: App configuration loaded!")
                    print("🔧 Config: Min: \(config.instanceConfiguration.minInstances), Max: \(config.instanceConfiguration.maxInstances)")
                }
            )
            .store(in: &cancellables)
    }
    
    func testGetDomains(appId: String) {
        guard !appId.isEmpty else {
            errorMessage = "No application selected"
            return
        }
        
        isLoading = true
        loadingMessage = "Loading domains..."
        errorMessage = nil
        
        print("🌐 Testing: getApplicationDomains for app: \(appId)")
        
        cleverCloudSDK.environment.getApplicationDomains(for: appId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    self?.loadingMessage = ""
                    if case .failure(let error) = completion {
                        self?.errorMessage = "Get domains failed: \(error.localizedDescription)"
                        print("❌ Test Failed: getApplicationDomains - \(error)")
                    } else {
                        self?.errorMessage = "✅ App domains loaded successfully!"
                        print("✅ Test Passed: getApplicationDomains")
                    }
                },
                receiveValue: { domains in
                    print("✅ SUCCESS: Loaded \(domains.count) domains!")
                    for domain in domains {
                        print("🌐 Domain: \(domain)")
                    }
                }
            )
            .store(in: &cancellables)
    }
}

// MARK: - Organization Extensions
extension CCOrganization {
    var displayName: String {
        return "\(name) (\(organizationType.description))"
    }
} 