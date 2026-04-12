import Foundation
import Combine

/// Single source of truth for all shared app data.
/// Replaces the scattered @State arrays in ContentView and the underutilized CleverCloudViewModel.
/// Uses @Observable (iOS 17+) for fine-grained SwiftUI updates.
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

    // MARK: - SDK Access

    let cleverCloudSDK: CleverCloudSDK

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()

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

    func loadApplicationStatuses() {
        for app in applications {
            applicationStatuses[app.id] = "Loading..."
        }

        guard let org = selectedOrganization else { return }

        for app in applications {
            cleverCloudSDK.applications.getApplicationInstances(
                applicationId: app.id,
                organizationId: org.id
            )
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure = completion {
                        self?.applicationStatuses[app.id] = "Unknown"
                    }
                },
                receiveValue: { [weak self] instances in
                    if instances.isEmpty {
                        self?.applicationStatuses[app.id] = "Stopped"
                    } else {
                        self?.applicationStatuses[app.id] = "Running"
                    }
                }
            )
            .store(in: &cancellables)
        }
    }

    /// Refresh apps and addons for the currently selected organization
    func refreshOrganizationData() {
        loadApplications()
        loadAddons()
    }
}
