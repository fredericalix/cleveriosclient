import Foundation
import Combine

/// Single source of truth for all shared app data.
/// Replaces the scattered @State arrays in ContentView and the underutilized CleverCloudViewModel.
/// Uses @Observable (iOS 17+) for fine-grained SwiftUI updates.
///
/// Also owns the intelligent polling system (status polling every 15s + data refresh every 10s).
/// Polling state MUST live here rather than in ContentView's @State because SwiftUI can recreate
/// the ContentView struct during NavigationSplitView layout on iPad — this would reset @State and
/// make any idempotence guard at the ContentView level useless.
@MainActor
@Observable
final class AppState {

    // MARK: - Shared Data

    var organizations: [CCOrganization] = []
    var selectedOrganization: CCOrganization?
    var applications: [CCApplication] = []
    var addons: [CCAddon] = []
    var addonProviders: [CCAddonProvider] = []
    var applicationStatuses: [String: String] = [:]

    // MARK: - UI State

    var isLoading = false
    var errorMessage: String?
    var organizationError: String?
    var addonError: String?

    // MARK: - Polling UI State

    var isPollingActive = false
    var lastEventReceived: String = "None"
    var eventSystemMode: String = "Disconnected"
    let pollingInterval: TimeInterval = 15.0

    // MARK: - SDK Access

    let cleverCloudSDK: CleverCloudSDK

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()
    private var eventsCancellables = Set<AnyCancellable>()
    private var pollingTimer: Timer?
    private var dataRefreshTimer: Timer?

    // Closures provided by ContentView so the polling loop can read the current app list and
    // trigger list refreshes without AppState taking ownership of all data state.
    private var applicationsProvider: (() -> [CCApplication])?
    private var organizationIdProvider: (() -> String?)?
    private var dataRefreshTick: (() -> Void)?

    // MARK: - Init

    init(cleverCloudSDK: CleverCloudSDK) {
        self.cleverCloudSDK = cleverCloudSDK
    }

    // MARK: - Data Loading

    func loadOrganizations() {
        organizationError = nil
        isLoading = true

        cleverCloudSDK.getUserOrganizations()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.organizationError = error.localizedDescription
                    }
                },
                receiveValue: { [weak self] orgs in
                    self?.organizations = orgs
                    if self?.selectedOrganization == nil, let first = orgs.first {
                        self?.selectedOrganization = first
                    }
                }
            )
            .store(in: &cancellables)
    }

    func loadApplications() {
        guard let org = selectedOrganization else { return }
        isLoading = true

        let publisher: AnyPublisher<[CCApplication], CCError>
        if org.id.hasPrefix("orga_") {
            publisher = cleverCloudSDK.applications.getApplicationsWithStates(forOrganization: org.id)
        } else {
            publisher = cleverCloudSDK.applications.getApplicationsWithStates()
        }

        publisher
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.errorMessage = error.localizedDescription
                    }
                },
                receiveValue: { [weak self] apps in
                    self?.applications = apps
                }
            )
            .store(in: &cancellables)
    }

    func loadAddons() {
        guard let org = selectedOrganization else { return }
        addonError = nil

        let publisher: AnyPublisher<[CCAddon], CCError>
        if org.id.hasPrefix("orga_") {
            publisher = cleverCloudSDK.getOrganizationAddons(organizationId: org.id)
        } else {
            publisher = cleverCloudSDK.getUserAddons()
        }

        publisher
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.addonError = error.localizedDescription
                    }
                },
                receiveValue: { [weak self] loadedAddons in
                    self?.addons = loadedAddons
                }
            )
            .store(in: &cancellables)
    }

    /// Refresh apps and addons for the currently selected organization
    func refreshOrganizationData() {
        loadApplications()
        loadAddons()
    }

    // MARK: - Polling

    /// Start the intelligent polling system. Idempotent: safe to call from multiple onAppear fires.
    /// - Parameters:
    ///   - applicationsProvider: closure returning the current applications list (owned by ContentView)
    ///   - organizationIdProvider: closure returning the current selected organization ID
    ///   - dataRefreshTick: closure fired every 10s to refresh the apps/addons lists
    func startPolling(
        applicationsProvider: @escaping () -> [CCApplication],
        organizationIdProvider: @escaping () -> String?,
        dataRefreshTick: @escaping () -> Void
    ) {
        // Always refresh closures so they point at the latest backing state (view identity changes
        // on iPad NavigationSplitView layout can invalidate older captures).
        self.applicationsProvider = applicationsProvider
        self.organizationIdProvider = organizationIdProvider
        self.dataRefreshTick = dataRefreshTick

        // Idempotent: timers already running, don't rebuild subscriptions or timers.
        guard pollingTimer == nil else {
            return
        }

        debugLog("🔄 Setting up intelligent polling system...")

        cleverCloudSDK.events.connectionStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handleConnectionStateChange(state)
            }
            .store(in: &eventsCancellables)

        cleverCloudSDK.events.eventPublisher
            .receive(on: DispatchQueue.main)
            .sink { completion in
                if case .failure(let error) = completion {
                    debugLog("❌ Events stream error: \(error)")
                }
            } receiveValue: { [weak self] event in
                self?.handlePlatformEvent(event)
            }
            .store(in: &eventsCancellables)

        debugLog("🔄 Starting intelligent status polling every \(pollingInterval) seconds")

        refreshApplicationStatuses()
        cleverCloudSDK.events.connect()

        pollingTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshApplicationStatuses()
            }
        }

        dataRefreshTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.dataRefreshTick?()
            }
        }
    }

    /// Stop the polling system. Safe to call multiple times.
    func stopPolling() {
        guard pollingTimer != nil || dataRefreshTimer != nil else {
            return
        }
        debugLog("🛑 Stopping polling system...")
        cleverCloudSDK.events.disconnect()
        eventsCancellables.removeAll()
        pollingTimer?.invalidate()
        pollingTimer = nil
        dataRefreshTimer?.invalidate()
        dataRefreshTimer = nil
        debugLog("⏹️ Stopped intelligent polling")
        isPollingActive = false
        eventSystemMode = "Disconnected"
    }

    /// Trigger an immediate status refresh. Used after an explicit data reload (e.g. org change).
    func refreshApplicationStatuses() {
        let apps = applicationsProvider?() ?? applications
        guard !apps.isEmpty else { return }
        debugLog("🔄 Refreshing application statuses...")
        loadApplicationStatuses(for: apps)
    }

    private func loadApplicationStatuses(for apps: [CCApplication]) {
        for app in apps where applicationStatuses[app.id] == nil {
            applicationStatuses[app.id] = "Loading..."
        }

        let currentOrgId = organizationIdProvider?() ?? selectedOrganization?.id
        let sdk = cleverCloudSDK

        for (index, app) in apps.enumerated() {
            let appId = app.id
            let instancesPublisher: AnyPublisher<[CCApplicationInstance], CCError>
            if let orgId = currentOrgId, orgId.hasPrefix("orga_") {
                instancesPublisher = sdk.applications.getApplicationInstances(applicationId: appId, organizationId: orgId)
            } else {
                instancesPublisher = sdk.applications.getApplicationInstances(applicationId: appId)
            }

            let delay = Double(index) * 0.2
            instancesPublisher
                .delay(for: .milliseconds(Int(delay * 1000)), scheduler: DispatchQueue.main)
                .timeout(.seconds(10), scheduler: DispatchQueue.main)
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { [weak self] completion in
                        if case .failure = completion {
                            self?.applicationStatuses[appId] = "Error"
                        }
                    },
                    receiveValue: { [weak self] instances in
                        self?.applicationStatuses[appId] = Self.computeApplicationStatus(from: instances)
                    }
                )
                .store(in: &eventsCancellables)
        }
    }

    private func handleConnectionStateChange(_ state: CCConnectionState) {
        switch state {
        case .disconnected:
            isPollingActive = false
            eventSystemMode = "Disconnected"
        case .polling:
            isPollingActive = true
            eventSystemMode = "Polling Active"
        case .failed:
            isPollingActive = false
            eventSystemMode = "Error"
        }
    }

    private func handlePlatformEvent(_ event: CCPlatformEvent) {
        lastEventReceived = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    }

    /// Compute application status from instances (follows clever-tools computeStatus pattern)
    private static func computeApplicationStatus(from instances: [CCApplicationInstance]) -> String {
        guard !instances.isEmpty else { return "Stopped" }
        let states = instances.map { $0.state.uppercased() }
        if states.contains("FAILED") { return "Failed" }
        if states.contains("DEPLOYING") { return "Deploying" }
        if states.contains("UP") { return "Running" }
        if states.contains("DOWN") || states.contains("SHOULD_BE_DOWN") { return "Stopped" }
        return "Unknown"
    }
}
