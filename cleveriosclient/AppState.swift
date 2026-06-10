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
    /// Long-lived subscriptions to the events service streams. Cleared only by stopPolling().
    private var eventsCancellables = Set<AnyCancellable>()
    /// In-flight status fetch pipelines, keyed by UUID and removed when each pipeline completes —
    /// a plain Set would accumulate thousands of finished sinks per hour from the periodic refresh.
    /// Cleared by cancelInFlight() on org switch.
    private var statusRequestCancellables: [UUID: AnyCancellable] = [:]
    private var pollingTimer: Timer?
    private var dataRefreshTimer: Timer?

    // Debounce: skip the auto tick when a manual refresh fired within this window.
    private let minRefreshInterval: TimeInterval = 3.0
    private var lastDataRefreshAt: Date = .distantPast
    private var lastStatusRefreshAt: Date = .distantPast

    #if DEBUG
    // In-memory counter for observability — measures how many per-app status fetches we issue.
    // Dumped on stopPolling so the before/after impact of the SSE migration is visible.
    private var statusRequestsIssued: Int = 0
    private var counterWindowStartedAt: Date = Date()
    #endif

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
        if org.isOrganization {
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
        if org.isOrganization {
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
        #if DEBUG
        counterWindowStartedAt = Date()
        statusRequestsIssued = 0
        #endif

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
                guard let self else { return }
                // The WebSocket event stream is the primary source of status changes; this poll is
                // only a reconciliation fallback. While the stream is live, stretch the N-requests-
                // per-app fan-out from every 15s to every 60s (~4× fewer API calls when idle).
                let effectiveInterval = self.isPollingActive ? 60.0 : self.pollingInterval
                guard Date().timeIntervalSince(self.lastStatusRefreshAt) >= effectiveInterval - 0.5 else {
                    return
                }
                self.refreshApplicationStatuses(forced: false)
            }
        }

        dataRefreshTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if Date().timeIntervalSince(self.lastDataRefreshAt) < self.minRefreshInterval {
                    debugLog("ℹ️ ⏭️ Skipping data refresh tick (debounced, manual refresh <\(Int(self.minRefreshInterval))s ago)")
                    return
                }
                self.lastDataRefreshAt = Date()
                self.dataRefreshTick?()
            }
        }
    }

    /// Stop the polling system. Safe to call multiple times.
    func stopPolling() {
        guard pollingTimer != nil || dataRefreshTimer != nil else {
            return
        }
        #if DEBUG
        let windowSeconds = Date().timeIntervalSince(counterWindowStartedAt)
        debugLog("ℹ️ 📊 Status requests since polling start: \(statusRequestsIssued) over \(Int(windowSeconds))s")
        statusRequestsIssued = 0
        counterWindowStartedAt = Date()
        #endif
        debugLog("🛑 Stopping polling system...")
        cleverCloudSDK.events.disconnect()
        eventsCancellables.removeAll()
        statusRequestCancellables.removeAll()
        pollingTimer?.invalidate()
        pollingTimer = nil
        dataRefreshTimer?.invalidate()
        dataRefreshTimer = nil
        debugLog("⏹️ Stopped intelligent polling")
        isPollingActive = false
        eventSystemMode = "Disconnected"
    }

    /// Cancel all in-flight per-app status fetches. The long-lived events-service subscriptions are
    /// kept intact. Used by the org-switch path so responses from the previous org cannot land in
    /// `applicationStatuses` after the user has moved on.
    func cancelInFlight() {
        guard !statusRequestCancellables.isEmpty else { return }
        debugLog("ℹ️ 🧹 Cancelling \(statusRequestCancellables.count) in-flight status batches")
        statusRequestCancellables.removeAll()
        applicationStatuses.removeAll()
    }

    /// Stamp `lastDataRefreshAt` so the next auto tick is debounced. ContentView calls this from
    /// the manual refresh paths (pull-to-refresh, Cmd+R, org switch) so the 10s timer doesn't pile
    /// a second request on top of the one we just issued.
    func markDataRefreshed() {
        lastDataRefreshAt = Date()
    }

    /// Trigger an immediate status refresh. Used after an explicit data reload (e.g. org change).
    /// Call with `forced: false` from the polling timer so a recent manual refresh debounces it.
    func refreshApplicationStatuses(forced: Bool = true) {
        if !forced, Date().timeIntervalSince(lastStatusRefreshAt) < minRefreshInterval {
            debugLog("ℹ️ ⏭️ Skipping status refresh (debounced, manual <\(Int(minRefreshInterval))s ago)")
            return
        }
        let apps = applicationsProvider?() ?? applications
        guard !apps.isEmpty else { return }
        lastStatusRefreshAt = Date()
        debugLog("🔄 Refreshing application statuses...")
        loadApplicationStatuses(for: apps)
    }

    private func loadApplicationStatuses(for apps: [CCApplication]) {
        for app in apps where applicationStatuses[app.id] == nil {
            applicationStatuses[app.id] = "Loading..."
        }

        // Capture the org context this batch was issued under. Any response that lands after the
        // user has switched orgs is dropped on the floor — see the orgId guard in the sink below.
        let requestOrgId = organizationIdProvider?() ?? selectedOrganization?.id
        let sdk = cleverCloudSDK

        #if DEBUG
        statusRequestsIssued += apps.count
        #endif

        // One pipeline per batch, bounded to 4 concurrent /instances requests. The previous
        // per-app `.delay(index * 0.2s)` was a no-op stagger (Combine's delay postpones output
        // delivery, not the request) that silently ate into the 10s `.timeout` budget — apps past
        // index ~49 could never receive a status.
        let key = UUID()
        statusRequestCancellables[key] = Publishers.Sequence(sequence: apps)
            .flatMap(maxPublishers: .max(4)) { (app: CCApplication) -> AnyPublisher<(String, String), Never> in
                let instancesPublisher: AnyPublisher<[CCApplicationInstance], CCError>
                if let orgId = requestOrgId, CCOrganization.isOrganizationId(orgId) {
                    instancesPublisher = sdk.applications.getApplicationInstances(applicationId: app.id, organizationId: orgId)
                } else {
                    instancesPublisher = sdk.applications.getApplicationInstances(applicationId: app.id)
                }
                return instancesPublisher
                    .retry(1)
                    .timeout(.seconds(10), scheduler: DispatchQueue.main)
                    .map { instances in (app.id, ApplicationStatus.compute(from: instances).description) }
                    .catch { _ in Just((app.id, "Error")) }
                    .eraseToAnyPublisher()
            }
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] _ in
                    // Prune the finished pipeline so the dictionary doesn't grow with every tick.
                    self?.statusRequestCancellables[key] = nil
                },
                receiveValue: { [weak self] appId, status in
                    guard let self else { return }
                    let liveOrgId = self.organizationIdProvider?() ?? self.selectedOrganization?.id
                    guard liveOrgId == requestOrgId else { return }
                    self.applicationStatuses[appId] = status
                }
            )
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

        // DEPLOYMENT_ACTION_BEGIN/_END carry an application id in data.id (or data.appId on some
        // event variants). Map the deployment `state` directly into our display string so the badge
        // updates in real time without waiting for the next /instances poll.
        guard event.type == "DEPLOYMENT_ACTION_BEGIN" || event.type == "DEPLOYMENT_ACTION_END" else {
            return
        }
        guard let appId = event.appId, !appId.isEmpty else { return }

        // Org guard: only apply events for apps in the currently displayed (org-scoped) list, so an
        // event for another org — or a stale org right after cancelInFlight() — cannot pollute
        // applicationStatuses and inflate the dashboard counts. Mirrors the polled path's org guard.
        let currentApps = applicationsProvider?() ?? applications
        guard currentApps.contains(where: { $0.id == appId }) else { return }

        let state = event.state?.uppercased() ?? ""
        let mapped: String
        switch state {
        case "WIP": mapped = "Deploying"
        case "OK": mapped = "Running"
        case "FAIL": mapped = "Failed"
        case "CANCELLED": mapped = "Stopped"
        default:
            // Unknown state → refresh only the affected app instead of trusting the event or
            // fanning out to every app.
            loadApplicationStatuses(for: currentApps.filter { $0.id == appId })
            return
        }
        debugLog("ℹ️ 📨 Event \(event.type) \(state) → \(appId) = \(mapped)")
        applicationStatuses[appId] = mapped
    }
}
