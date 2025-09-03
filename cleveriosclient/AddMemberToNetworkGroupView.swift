import SwiftUI
import Combine

// MARK: - AddMemberToNetworkGroupView
/// Modern interface for adding applications and add-ons to Network Groups
struct AddMemberToNetworkGroupView: View {
    
    // MARK: - Environment
    @Environment(\.dismiss) private var dismiss
    @Environment(AppCoordinator.self) private var coordinator: AppCoordinator
    
    // MARK: - Properties
    let networkGroup: CCNetworkGroup
    let organizationId: String
    let onMemberAdded: (CCNetworkGroupMember) -> Void
    
    // MARK: - State
    @State private var selectedMemberType: CCNetworkGroupMemberType = .application
    @State private var searchText = ""
    @State private var applications: [CCApplication] = []
    @State private var addons: [CCAddon] = []
    @State private var existingMembers: [CCNetworkGroupMember] = []
    @State private var selectedResourceIds = Set<String>()
    @State private var isLoading = false
    @State private var isAdding = false
    @State private var errorMessage: String?
    @State private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Body
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header Section
                headerSection
                
                // Member Type Selector
                memberTypeSelector
                
                // Search Bar
                searchSection
                
                // Content
                if isLoading {
                    loadingView
                } else {
                    contentView
                }
                
                Spacer()
                
                // Action Buttons
                actionButtonsSection
            }
            .navigationTitle("Add Members")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadData()
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "Unknown error occurred")
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "person.badge.plus")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Add to Network Group")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text(networkGroup.name)
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
                
                Spacer()
                
                // Selection counter
                if !selectedResourceIds.isEmpty {
                    VStack {
                        Text("\(selectedResourceIds.count)")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                        Text("selected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Network Group Info
            HStack {
                Image(systemName: "network")
                    .foregroundColor(.purple)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("CIDR: \(networkGroup.cidr ?? "Auto-assigned")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Region: \(networkGroup.region?.uppercased() ?? "Global")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
        }
        .padding()
        .background(Color(.systemGray6))
    }
    
    // MARK: - Member Type Selector
    private var memberTypeSelector: some View {
        HStack(spacing: 0) {
            ForEach(CCNetworkGroupMemberType.allCases, id: \.self) { type in
                Button(action: {
                    selectedMemberType = type
                    selectedResourceIds.removeAll() // Clear selection when changing type
                }) {
                    HStack {
                        Image(systemName: type.icon)
                            .foregroundColor(selectedMemberType == type ? .white : .primary)
                        
                        Text(type.displayName + "s")
                            .fontWeight(.medium)
                            .foregroundColor(selectedMemberType == type ? .white : .primary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        selectedMemberType == type
                        ? Color.blue
                        : Color.clear
                    )
                }
            }
        }
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding(.horizontal)
    }
    
    // MARK: - Search Section
    private var searchSection: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search \(selectedMemberType.displayName.lowercased())s...", text: $searchText)
                    .textFieldStyle(.plain)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .cornerRadius(8)
            
            // Filter info
            if !filteredResources.isEmpty {
                HStack {
                    Text("\(filteredResources.count) \(selectedMemberType.displayName.lowercased())\(filteredResources.count == 1 ? "" : "s") available")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if filteredExistingMembers.count > 0 {
                        Text("\(filteredExistingMembers.count) already added")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.top)
    }
    
    // MARK: - Content View
    private var contentView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(filteredResources, id: \.id) { resource in
                    resourceRow(resource)
                }
                
                if filteredResources.isEmpty {
                    emptyStateView
                }
            }
            .padding(.horizontal)
            .padding(.top)
        }
    }
    
    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("Loading \(selectedMemberType.displayName.lowercased())s...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
    
    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: selectedMemberType == .application ? "app.badge" : "gear.badge")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            
            Text("No \(selectedMemberType.displayName)s Found")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text(searchText.isEmpty 
                ? "No \(selectedMemberType.displayName.lowercased())s are available in this organization"
                : "No \(selectedMemberType.displayName.lowercased())s match your search criteria")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .padding(.vertical, 40)
    }
    
    // MARK: - Resource Row
    private func resourceRow(_ resource: ResourceItem) -> some View {
        let isSelected = selectedResourceIds.contains(resource.id)
        let isAlreadyMember = existingMembers.contains { $0.resourceId == resource.id && $0.type == selectedMemberType }
        
        return HStack(spacing: 12) {
            // Selection indicator
            Button(action: {
                if isAlreadyMember {
                    return // Can't select already added members
                }
                
                if isSelected {
                    selectedResourceIds.remove(resource.id)
                } else {
                    selectedResourceIds.insert(resource.id)
                }
            }) {
                Image(systemName: isAlreadyMember ? "checkmark.circle.fill" : (isSelected ? "checkmark.circle.fill" : "circle"))
                    .foregroundColor(isAlreadyMember ? .orange : (isSelected ? .blue : .secondary))
                    .font(.title3)
            }
            .disabled(isAlreadyMember)
            
            // Resource icon
            Image(systemName: selectedMemberType.icon)
                .foregroundColor(selectedMemberType == .application ? .green : .orange)
                .font(.title3)
                .frame(width: 30)
            
            // Resource info
            VStack(alignment: .leading, spacing: 4) {
                Text(resource.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(isAlreadyMember ? .secondary : .primary)
                
                if let description = resource.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                // Status and additional info
                HStack {
                    Label(resource.status, systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundColor(statusColor(resource.status))
                    
                    if isAlreadyMember {
                        Spacer()
                        Text("Already in network")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
            
            Spacer()
            
            // Resource type badge
            Text(selectedMemberType.displayName)
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.systemGray5))
                .cornerRadius(4)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.blue.opacity(0.1) : Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isAlreadyMember ? Color.orange : (isSelected ? Color.blue : Color(.systemGray4)),
                            lineWidth: isSelected || isAlreadyMember ? 2 : 1
                        )
                )
        )
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
    
    // MARK: - Action Buttons Section
    private var actionButtonsSection: some View {
        VStack(spacing: 12) {
            // Add selected members button
            Button(action: addSelectedMembers) {
                HStack {
                    if isAdding {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "person.badge.plus")
                    }
                    
                    Text(isAdding ? "Adding Members..." : "Add \(selectedResourceIds.count) Member\(selectedResourceIds.count == 1 ? "" : "s")")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .foregroundColor(.white)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(selectedResourceIds.isEmpty ? Color.gray : Color.blue)
                )
            }
            .disabled(selectedResourceIds.isEmpty || isAdding)
            
            // Cancel button
            Button("Cancel") {
                dismiss()
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .foregroundColor(.blue)
        }
        .padding()
        .background(Color(.systemBackground))
    }
    
    // MARK: - Computed Properties
    private var filteredResources: [ResourceItem] {
        let resources = selectedMemberType == .application ? 
            applications.map { ResourceItem(from: $0) } :
            addons.map { ResourceItem(from: $0) }
        
        if searchText.isEmpty {
            return resources
        }
        
        return resources.filter { resource in
            resource.name.localizedCaseInsensitiveContains(searchText) ||
            resource.description?.localizedCaseInsensitiveContains(searchText) == true
        }
    }
    
    private var filteredExistingMembers: [CCNetworkGroupMember] {
        return existingMembers.filter { $0.type == selectedMemberType }
    }
    
    // MARK: - Helper Methods
    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "running", "active":
            return .green
        case "stopped", "inactive":
            return .red
        case "starting", "stopping":
            return .orange
        default:
            return .secondary
        }
    }
    
    private func loadData() {
        isLoading = true
        errorMessage = nil
        
        // Load existing members first
        coordinator.cleverCloudSDK.networkGroups.getNetworkGroupMembers(
            organizationId: organizationId,
            networkGroupId: networkGroup.id
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    errorMessage = "Failed to load existing members: \(error.localizedDescription)"
                }
            },
            receiveValue: { members in
                existingMembers = members
            }
        )
        .store(in: &cancellables)
        
        // Load applications
        coordinator.cleverCloudSDK.applications.getApplications(forOrganization: organizationId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        errorMessage = "Failed to load applications: \(error.localizedDescription)"
                    }
                },
                receiveValue: { apps in
                    applications = apps
                }
            )
            .store(in: &cancellables)
        
        // Load add-ons
        coordinator.cleverCloudSDK.addons.getAddons(forOrganization: organizationId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    isLoading = false
                    if case .failure(let error) = completion {
                        errorMessage = "Failed to load add-ons: \(error.localizedDescription)"
                    }
                },
                receiveValue: { addonsResult in
                    addons = addonsResult
                }
            )
            .store(in: &cancellables)
    }
    
    private func addSelectedMembers() {
        guard !selectedResourceIds.isEmpty else { return }
        
        isAdding = true
        
        let publishers = selectedResourceIds.map { resourceId in
            coordinator.cleverCloudSDK.networkGroups.addNetworkGroupMember(
                organizationId: organizationId,
                networkGroupId: networkGroup.id,
                member: CCNetworkGroupMemberCreate(type: selectedMemberType, resourceId: resourceId)
            )
        }
        
        Publishers.MergeMany(publishers)
            .collect()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    isAdding = false
                    
                    switch completion {
                    case .finished:
                        // Success - dismiss and notify parent
                        dismiss()
                        
                    case .failure(let error):
                        errorMessage = "Failed to add members: \(error.localizedDescription)"
                    }
                },
                receiveValue: { addedMembers in
                    // Notify parent about each added member
                    addedMembers.forEach { member in
                        onMemberAdded(member)
                    }
                }
            )
            .store(in: &cancellables)
    }
}

// MARK: - Supporting Types

/// Unified resource item for display
private struct ResourceItem: Identifiable {
    let id: String
    let name: String
    let description: String?
    let status: String
    
    init(from application: CCApplication) {
        self.id = application.id
        self.name = application.name
        self.description = application.description
        self.status = "running" // Applications don't have a direct status field in the model
    }
    
    init(from addon: CCAddon) {
        self.id = addon.id
        self.name = addon.name
        self.description = addon.description
        self.status = addon.status ?? "active"
    }
}

// MARK: - Preview
#Preview {
    AddMemberToNetworkGroupView(
        networkGroup: CCNetworkGroup.example(),
        organizationId: "orga_example",
        onMemberAdded: { _ in }
    )
    .environment(AppCoordinator())
} 