import SwiftUI
import Combine

// MARK: - NetworkGroupsIntegratedView
/// Interface intégrée révolutionnaire pour les Network Groups - Sans sheets, optimisée iPad
struct NetworkGroupsIntegratedView: View {
    
    // MARK: - Environment
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(AppCoordinator.self) private var coordinator: AppCoordinator
    
    // MARK: - Properties
    let organizationId: String
    
    // MARK: - State
    @State private var networkGroups: [CCNetworkGroup] = []
    @State private var selectedNetworkGroup: CCNetworkGroup?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var cancellables = Set<AnyCancellable>()
    
    // Navigation state
    @State private var navigationPath = NavigationPath()
    @State private var selectedDetailType: DetailType = .list
    @State private var showingCreateNetworkGroup = false
    
    enum DetailType {
        case list
        case networkGroupDetail(CCNetworkGroup)
        case createNetworkGroup
        case editNetworkGroup(CCNetworkGroup)
    }
    
    // iPad optimization
    private var isIpad: Bool {
        horizontalSizeClass == .regular && verticalSizeClass == .regular
    }
    
    var filteredNetworkGroups: [CCNetworkGroup] {
        if searchText.isEmpty {
            return networkGroups
        } else {
            return networkGroups.filter { ng in
                ng.name.localizedCaseInsensitiveContains(searchText) ||
                ng.description?.localizedCaseInsensitiveContains(searchText) ?? false
            }
        }
    }
    
    var body: some View {
        Group {
            if isIpad {
                iPadLayout
            } else {
                iPhoneLayout
            }
        }
        .sheet(isPresented: $showingCreateNetworkGroup) {
            CreateNetworkGroupView(
                organizationId: organizationId,
                onNetworkGroupCreated: { newNetworkGroup in
                    // Add the new network group to the list
                    networkGroups.append(newNetworkGroup)
                    
                    // On iPad, select the new network group
                    if isIpad {
                        selectedNetworkGroup = newNetworkGroup
                    }
                    
                    print("✅ Successfully created network group: \(newNetworkGroup.name)")
                }
            )
            .environment(coordinator)
        }
    }
    
    // MARK: - iPad Layout avec NavigationSplitView
    
    private var iPadLayout: some View {
        NavigationSplitView {
            // Sidebar - Liste des Network Groups
            networkGroupsSidebar
                .navigationSplitViewColumnWidth(min: 300, ideal: 350, max: 400)
        } detail: {
            // Detail - Vue détaillée du Network Group sélectionné
            networkGroupDetailView
        }
        .onAppear {
            loadNetworkGroups()
        }
    }
    
    // MARK: - iPhone Layout avec NavigationStack
    
    private var iPhoneLayout: some View {
        NavigationStack(path: $navigationPath) {
            networkGroupsListView
                .navigationTitle("Network Groups")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { createNetworkGroup() }) {
                            Image(systemName: "plus")
                        }
                    }
                }
                .navigationDestination(for: CCNetworkGroup.self) { networkGroup in
                    NetworkGroupDetailView(
                        networkGroup: networkGroup,
                        organizationId: organizationId
                    )
                    .environment(coordinator)
                }
        }
        .onAppear {
            loadNetworkGroups()
        }
    }
    
    // MARK: - Network Groups Sidebar (iPad)
    
    private var networkGroupsSidebar: some View {
        VStack(spacing: 0) {
            // Header avec search et actions
            VStack(spacing: 16) {
                HStack {
                    Text("Network Groups")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Spacer()
                    
                    Button(action: { createNetworkGroup() }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Search network groups...", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                
                // Stats
                if !networkGroups.isEmpty {
                    HStack(spacing: 16) {
                        statPill(title: "Total", count: networkGroups.count, color: .blue)
                        statPill(title: "Active", count: networkGroups.filter { $0.status?.lowercased() == "active" }.count, color: .green)
                    }
                }
            }
            .padding()
            
            Divider()
            
            // Liste des Network Groups
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Loading Network Groups...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredNetworkGroups.isEmpty {
                emptyStateView
            } else {
                List(filteredNetworkGroups, selection: $selectedNetworkGroup) { networkGroup in
                    networkGroupRowForSidebar(networkGroup)
                        .tag(networkGroup)
                }
                .listStyle(SidebarListStyle())
            }
        }
    }
    
    // MARK: - Network Groups List (iPhone)
    
    private var networkGroupsListView: some View {
        VStack(spacing: 0) {
            // Search bar
            if !networkGroups.isEmpty {
                searchBar
                    .padding(.horizontal)
                    .padding(.bottom)
            }
            
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Loading Network Groups...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredNetworkGroups.isEmpty {
                emptyStateView
            } else {
                List(filteredNetworkGroups) { networkGroup in
                    Button(action: {
                        navigationPath.append(networkGroup)
                    }) {
                        networkGroupRowForList(networkGroup)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .listStyle(PlainListStyle())
            }
        }
    }
    
    // MARK: - Detail View (iPad)
    
    private var networkGroupDetailView: some View {
        Group {
            if let selectedNG = selectedNetworkGroup {
                NetworkGroupDetailView(
                    networkGroup: selectedNG,
                    organizationId: organizationId
                )
                .environment(coordinator)
                .navigationTitle(selectedNG.name)
            } else {
                // État par défaut quand aucun Network Group n'est sélectionné
                VStack(spacing: 20) {
                    Image(systemName: "network")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    Text("Select a Network Group")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Choose a network group from the sidebar to view its details and manage connections.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    if networkGroups.isEmpty && !isLoading {
                        Button(action: { createNetworkGroup() }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Create First Network Group")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(10)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("Network Groups")
            }
        }
    }
    
    // MARK: - Helper Views
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Search network groups...", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "network")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            
            Text("No Network Groups")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(searchText.isEmpty ?
                "Create your first network group to start connecting applications and services securely." :
                "No network groups match '\(searchText)'. Try a different search term.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            if searchText.isEmpty {
                Button(action: { createNetworkGroup() }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Create Network Group")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func statPill(title: String, count: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
    
    private func networkGroupRowForSidebar(_ networkGroup: CCNetworkGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Icône avec couleur de status
                Image(systemName: "network")
                    .foregroundColor(colorFromString(networkGroup.statusColor))
                    .font(.title3)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(networkGroup.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    if let description = networkGroup.description {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                
                Spacer()
            }
            
            // CIDR et région
            HStack {
                if let cidr = networkGroup.cidr {
                    Text(cidr)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.systemGray5))
                        .cornerRadius(4)
                }
                
                Spacer()
                
                if let region = networkGroup.region {
                    Text(region.uppercased())
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func networkGroupRowForList(_ networkGroup: CCNetworkGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // Icône avec couleur de status
                Image(systemName: "network")
                    .foregroundColor(colorFromString(networkGroup.statusColor))
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(networkGroup.name)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    if let description = networkGroup.description {
                        Text(description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Informations supplémentaires
            HStack(spacing: 16) {
                if let cidr = networkGroup.cidr {
                    Label(cidr, systemImage: "network.badge.shield.half.filled")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let region = networkGroup.region {
                    Label(region.uppercased(), systemImage: "globe")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Status
                HStack(spacing: 4) {
                    Circle()
                        .fill(colorFromString(networkGroup.statusColor))
                        .frame(width: 6, height: 6)
                    
                    Text(networkGroup.status?.capitalized ?? "Unknown")
                        .font(.caption)
                        .foregroundColor(colorFromString(networkGroup.statusColor))
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Actions
    
    private func createNetworkGroup() {
        showingCreateNetworkGroup = true
    }
    
    private func loadNetworkGroups() {
        isLoading = true
        errorMessage = nil
        
        coordinator.cleverCloudSDK.networkGroups.getNetworkGroups(organizationId: organizationId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    isLoading = false
                    if case .failure(let error) = completion {
                        errorMessage = "Failed to load network groups: \(error.localizedDescription)"
                    }
                },
                receiveValue: { groups in
                    networkGroups = groups
                    
                    // Sur iPad, sélectionner automatiquement le premier si aucune sélection
                    if isIpad && selectedNetworkGroup == nil && !groups.isEmpty {
                        selectedNetworkGroup = groups.first
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    /// Convert system color name to SwiftUI Color
    private func colorFromString(_ colorName: String) -> Color {
        switch colorName {
        case "systemGreen":
            return .green
        case "systemOrange":
            return .orange
        case "systemRed":
            return .red
        case "systemGray":
            return .gray
        default:
            return .blue
        }
    }
}

// MARK: - Preview
#Preview {
    NavigationView {
        NetworkGroupsIntegratedView(organizationId: "orga_example")
            .environment(AppCoordinator())
    }
} 