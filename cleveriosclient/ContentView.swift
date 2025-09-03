//
//  ContentView.swift
//  test0
//
//  Created by Frédéric Alix on 17/06/2025.
//

import SwiftUI
import SwiftData
import Combine

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Query private var items: [Item]
    
    // MARK: - AppCoordinator from Environment 
    @Environment(AppCoordinator.self) private var coordinator
    
    // Computed property pour accéder au SDK depuis l'AppCoordinator
    private var cleverCloudSDK: CleverCloudSDK {
        coordinator.cleverCloudSDK
    }
    
    @State private var applications: [CCApplication] = []
    @State private var organizations: [CCOrganization] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var organizationError: String?
    
    // Add-ons state
    @State private var addons: [CCAddon] = []
    @State private var addonProviders: [CCAddonProvider] = []
    @State private var addonError: String?
    
    // Organization selection
    @State private var selectedOrganization: CCOrganization?
    
    @State private var cancellables = Set<AnyCancellable>()
    @State private var refreshTimer: Timer?
    
    // Simple application status tracking
    @State private var applicationStatuses: [String: String] = [:]
    
    // Event system tracking
    @State private var eventsCancellables = Set<AnyCancellable>()
    
    // MARK: - Properties
    @State private var showingAlert = false
    @State private var authButtonText = "🔑 Login with Clever Cloud"
    @State private var authButtonColor = Color.blue
    @State private var showingPreventDisappear = false
    @State private var navigateToMain = false
    @State private var pollingTimer: Timer?
    
    @State private var lastEventReceived: String = "None"
    
    // MARK: - Event System State
    @State private var isPollingActive = false
    @State private var pollingInterval: TimeInterval = 15.0
    @State private var eventSystemMode: String = "Disconnected"
    
    // MARK: - Network Groups State
    @State private var showingNetworkGroups = false
    
    // MARK: - Creation Views State
    @State private var showingCreateAddon = false
    
    // MARK: - Favorites and Filtering
    @State private var favoriteOrgIds: [String] = []
    
    @State private var orgFilterMode: OrgFilterMode = .all
    @State private var appSearchText = ""
    @State private var appFilterStatus: AppStatus? = nil

    // MARK: - iPad Support State
    @State private var selectedDetailView: DetailViewType = .dashboard
    @State private var selectedApplicationForDetail: CCApplication?
    @State private var selectedAddonForDetail: CCAddon?
    
    enum DetailViewType {
        case dashboard
        case applicationDetail
        case addonDetail
        case networkGroups
    }
    
    // Computed property to determine if we're on iPad - Using Apple recommended method
    private var isIpad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }
    
    // MARK: - Enums for Filtering
    enum OrgFilterMode: String, CaseIterable {
        case all = "All"
        case favorites = "Favorites ⭐"
        case personal = "Personal"
        case teams = "Teams"
    }
    
    enum AppStatus: String, CaseIterable {
        case all = "All"
        case running = "Running"
        case stopped = "Stopped"
        case deploying = "Deploying"
        case failed = "Failed"
        
        var icon: String {
            switch self {
            case .all: return "circle.grid.3x3"
            case .running: return "play.circle.fill"
            case .stopped: return "stop.circle.fill"
            case .deploying: return "arrow.clockwise.circle.fill"
            case .failed: return "exclamationmark.circle.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .all: return .gray
            case .running: return .green
            case .stopped: return .red
            case .deploying: return .orange
            case .failed: return .red
            }
        }
    }
    
    // MARK: - Computed Properties for Filtering
    
    var filteredOrganizations: [CCOrganization] {
        switch orgFilterMode {
        case .all:
            return organizations
        case .favorites:
            return organizations.filter { favoriteOrgIds.contains($0.id) }
        case .personal:
            return organizations.filter { $0.isPersonalSpace }
        case .teams:
            return organizations.filter { $0.isOrganization }
        }
    }
    
    var filteredApplications: [CCApplication] {
        var filtered = applications
        
        // Filter by search text
        if !appSearchText.isEmpty {
            filtered = filtered.filter { app in
                app.name.localizedCaseInsensitiveContains(appSearchText) ||
                app.description?.localizedCaseInsensitiveContains(appSearchText) ?? false ||
                app.id.localizedCaseInsensitiveContains(appSearchText)
            }
        }
        
        // Filter by status
        if let statusFilter = appFilterStatus, statusFilter != .all {
            filtered = filtered.filter { app in
                let status = applicationStatuses[app.id]?.lowercased() ?? "unknown"
                switch statusFilter {
                case .running: return status == "running"
                case .stopped: return status == "stopped"
                case .deploying: return status == "deploying"
                case .failed: return status == "failed"
                default: return true
                }
            }
        }
        
                return filtered
    }
    
    var filteredAddons: [CCAddon] {
        return addons // For now, no filtering on add-ons
    }

    var body: some View {
        if isIpad {
            iPadLayout
        } else {
            iPhoneLayout
        }
    }
    
    // MARK: - iPad Optimized Layout
    
    private var iPadLayout: some View {
        NavigationSplitView {
            // Sidebar content - same as iPhone but optimized
            sidebarContent
                .navigationTitle("Clever Cloud")
        } detail: {
            // Intelligent detail view based on selection
            detailContent
        }
        .onAppear {
            loadData()
            setupPollingSystem()
            loadFavorites()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ApplicationDestroyed"))) { notification in
            // Handle application destruction
            if let destroyedAppId = notification.object as? String {
                // Remove from applications list
                applications.removeAll { $0.id == destroyedAppId }
                
                // Clear selected detail if it was the destroyed app
                if selectedApplicationForDetail?.id == destroyedAppId {
                    selectedDetailView = .dashboard
                    selectedApplicationForDetail = nil
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AddonDestroyed"))) { notification in
            // Handle addon destruction
            if let destroyedAddonId = notification.object as? String {
                // Remove from addons list
                addons.removeAll { $0.id == destroyedAddonId }
                
                // Clear selected detail if it was the destroyed addon
                if selectedAddonForDetail?.id == destroyedAddonId {
                    selectedDetailView = .dashboard
                    selectedAddonForDetail = nil
                }
            }
        }
        .onDisappear {
            teardownPollingSystem()
        }
        .onChange(of: selectedOrganization) { oldValue, newValue in
            if let newOrg = newValue {
                RemoteLogger.shared.info("🔄 Organization changed to: \(newOrg.name) - Auto-refreshing data...")
                autoRefreshOrganizationData(for: newOrg)
                
                // On iPad, maintain current selection if possible
                // Only reset to dashboard if explicitly changing organizations (not data refresh)
                if oldValue?.id != newValue?.id {
                    // This is a real organization change, not just a data refresh
                    // Keep current selection unless it's no longer valid
                    if selectedDetailView == .applicationDetail && selectedApplicationForDetail != nil {
                        // Keep application detail view if we have a selected app
                    } else if selectedDetailView == .addonDetail && selectedAddonForDetail != nil {
                        // Keep addon detail view if we have a selected addon
                    } else if selectedDetailView == .networkGroups {
                        // Keep network groups view (it will reload for the new organization)
                    } else {
                        // Default to dashboard only if no valid selection
                        selectedDetailView = .dashboard
                        selectedApplicationForDetail = nil
                        selectedAddonForDetail = nil
                    }
                }
            }
        }
    }
    
    // MARK: - iPhone Layout (unchanged)
    
    private var iPhoneLayout: some View {
        NavigationView {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 20) {
                    // Main Content Sections
                    VStack(spacing: 16) {
                        organizationsCard
                        applicationsCard
                        addonsCard
                        networkGroupsCard
                    }
                    .padding(.horizontal)
                    
                    // Footer spacing
                    Spacer(minLength: 50)
                }
                .padding(.top)
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .navigationBarItems(leading: cleverCloudTitleLogo, trailing: logoutButton)
        }
        .onAppear {
            loadData()
            setupPollingSystem()
            loadFavorites()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ApplicationDestroyed"))) { notification in
            // Handle application destruction
            if let destroyedAppId = notification.object as? String {
                // Remove from applications list
                applications.removeAll { $0.id == destroyedAppId }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AddonDestroyed"))) { notification in
            // Handle addon destruction
            if let destroyedAddonId = notification.object as? String {
                // Remove from addons list
                addons.removeAll { $0.id == destroyedAddonId }
            }
        }
        .onDisappear {
            teardownPollingSystem()
        }
        .onChange(of: selectedOrganization) { oldValue, newValue in
            if let newOrg = newValue {
                RemoteLogger.shared.info("🔄 Organization changed to: \(newOrg.name) - Auto-refreshing data...")
                autoRefreshOrganizationData(for: newOrg)
            }
        }
        .sheet(isPresented: $showingCreateAddon) {
            CreateAddonView(selectedOrganization: selectedOrganization, onAddonCreated: {
                // Refresh the addons list when a new addon is created
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    testGetAddons()
                }
            })
                .environment(coordinator)
                .environmentObject(CleverCloudViewModel(cleverCloudSDK: cleverCloudSDK))
        }
    }
    
    // MARK: - Sidebar Content (for iPad)
    
    private var sidebarContent: some View {
        List {
            // Organizations Section
            Section(header: Text("Organizations")) {
                ForEach(filteredOrganizations) { org in
                    organizationRowForSidebar(org)
                }
            }
            
            // Applications Section
            if !filteredApplications.isEmpty {
                Section(header: Text("Applications")) {
                    ForEach(filteredApplications) { app in
                        applicationRowForSidebar(app)
                    }
                }
            }
            
            // Add-ons Section
            if !filteredAddons.isEmpty {
                Section(header: Text("Add-ons")) {
                    ForEach(filteredAddons) { addon in
                        addonRowForSidebar(addon)
                    }
                }
            }
            
            // Network Groups Section - Intégré directement
            if selectedOrganization?.id != nil {
                Section(header: Text("Network Groups")) {
                    Button(action: {
                        selectNetworkGroups()
                    }) {
                        HStack {
                            Image(systemName: "network")
                                .foregroundColor(.blue)
                                .font(.title3)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Network Groups")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                Text("Manage network connections")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if selectedDetailView == .networkGroups {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .listStyle(SidebarListStyle())
    }
    
    // MARK: - Detail Content (for iPad)
    
    private var detailContent: some View {
        Group {
            switch selectedDetailView {
            case .dashboard:
                iPadDashboardView
                    .navigationTitle("Dashboard")
            case .applicationDetail:
                if let app = selectedApplicationForDetail {
                    ApplicationDetailView(
                        application: app,
                        cleverCloudSDK: cleverCloudSDK,
                        organizationId: selectedOrganization?.id
                    )
                } else {
                    iPadDashboardView
                        .navigationTitle("Dashboard")
                }
            case .addonDetail:
                if let addon = selectedAddonForDetail {
                    AddonDetailView(
                        addon: addon,
                        organizationId: selectedOrganization?.id,
                        viewModel: CleverCloudViewModel(cleverCloudSDK: cleverCloudSDK)
                    )
                } else {
                    iPadDashboardView
                        .navigationTitle("Dashboard")
                }
            case .networkGroups:
                if let organizationId = selectedOrganization?.id {
                    NetworkGroupsModernView(organizationId: organizationId, isEmbeddedInNavigationSplitView: true)
                        .navigationTitle("Network Groups")
                } else {
                    iPadDashboardView
                        .navigationTitle("Dashboard")
                }
            }
        }
    }
    
    // MARK: - iPad Dashboard View
    
    private var iPadDashboardView: some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 20) {
                    // Welcome section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            cleverCloudTitleLogo
                            Spacer()
                            logoutButton
                        }
                        
                        if let selectedOrg = selectedOrganization {
                            Text("Welcome to \(selectedOrg.name)")
                                .font(.title2)
                                .fontWeight(.semibold)
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
                    
                    // Quick stats in 2x2 grid for iPad
                    let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 2)
                    LazyVGrid(columns: columns, spacing: 16) {
                        // Applications stat
                        quickStatCard(
                            title: "Applications",
                            count: applications.count,
                            icon: "app.fill",
                            color: .purple
                        ) {
                            if let firstApp = applications.first {
                                selectApplicationDetail(firstApp)
                            }
                        }
                        
                        // Add-ons stat
                        quickStatCard(
                            title: "Add-ons",
                            count: addons.count,
                            icon: "puzzlepiece.extension",
                            color: .orange
                        ) {
                            if let firstAddon = addons.first {
                                selectAddonDetail(firstAddon)
                            }
                        }
                        
                        // Running apps stat
                        quickStatCard(
                            title: "Running",
                            count: applicationStatuses.values.filter { $0.lowercased() == "running" }.count,
                            icon: "play.circle.fill",
                            color: .green
                        ) {
                            // Find first running app and select it
                            if let runningApp = applications.first(where: { applicationStatuses[$0.id]?.lowercased() == "running" }) {
                                selectApplicationDetail(runningApp)
                            }
                        }
                        
                        // Organizations stat
                        quickStatCard(
                            title: "Organizations",
                            count: organizations.count,
                            icon: "building.2",
                            color: .blue
                        ) {
                            // No action for organizations
                        }
                    }
                    
                    // Recent applications
                    if !applications.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Recent Applications")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            ForEach(Array(applications.prefix(5))) { app in
                                Button(action: {
                                    selectApplicationDetail(app)
                                }) {
                                    applicationRowForDashboard(app)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
                    }
                }
                .padding()
            }
        }
    }
    
    // MARK: - Helper Views for iPad
    
    private func quickStatCard(title: String, count: Int, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundColor(color)
                    Spacer()
                    Text("\(count)")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(color)
                }
                
                HStack {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    Spacer()
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func applicationRowForDashboard(_ app: CCApplication) -> some View {
        HStack {
            Image(systemName: "app.badge")
                .foregroundColor(.purple)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                if let description = app.description {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            let status = applicationStatuses[app.id] ?? "Loading..."
            HStack(spacing: 4) {
                Circle()
                    .fill(colorForState(status))
                    .frame(width: 8, height: 8)
                
                Text(status.capitalized)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(colorForState(status))
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
    
    // MARK: - Sidebar Row Views
    
    private func organizationRowForSidebar(_ org: CCOrganization) -> some View {
        Button(action: {
            selectedOrganization = org
        }) {
            HStack {
                Image(systemName: org.name.lowercased().contains("personal") ? "person.circle" : "building.2")
                    .foregroundColor(selectedOrganization?.id == org.id ? .blue : .secondary)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(org.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    if let description = org.description {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                if selectedOrganization?.id == org.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func applicationRowForSidebar(_ app: CCApplication) -> some View {
        Button(action: {
            selectApplicationDetail(app)
        }) {
            HStack {
                Image(systemName: "app.badge")
                    .foregroundColor(.purple)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text(app.instance.type.capitalized)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                let status = applicationStatuses[app.id] ?? "Loading..."
                Circle()
                    .fill(colorForState(status))
                    .frame(width: 8, height: 8)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func addonRowForSidebar(_ addon: CCAddon) -> some View {
        Button(action: {
            selectAddonDetail(addon)
        }) {
            HStack {
                Image(systemName: "puzzlepiece.extension")
                    .foregroundColor(.orange)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(addon.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text(addon.provider.name)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Selection Methods
    
    private func selectApplicationDetail(_ app: CCApplication) {
        print("🎯 [iPad Navigation] Selecting application: \(app.name)")
        RemoteLogger.shared.info("🎯 [iPad Navigation] Selecting application: \(app.name)")
        
        // Check if we're doing an app-to-app transition
        let isAppToAppTransition = selectedDetailView == .applicationDetail && selectedApplicationForDetail != nil
        
        if isAppToAppTransition {
            print("🔄 [iPad Navigation] App-to-App transition detected - forcing UI refresh")
            // Force UI refresh by temporarily resetting state
            selectedDetailView = .dashboard
            selectedApplicationForDetail = nil
            selectedAddonForDetail = nil
            
            // Short delay to ensure state change is processed by SwiftUI
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.selectedApplicationForDetail = app
                    self.selectedDetailView = .applicationDetail
                }
                print("🔄 [iPad Navigation] App-to-App transition complete - App: \(app.name)")
            }
        } else {
            // Normal transition from dashboard/addon to app
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedApplicationForDetail = app
                selectedAddonForDetail = nil
                selectedDetailView = .applicationDetail
            }
            print("🔄 [iPad Navigation] Normal transition - App: \(app.name)")
        }
    }
    
    private func selectAddonDetail(_ addon: CCAddon) {
        print("🎯 [iPad Navigation] Selecting addon: \(addon.name)")
        RemoteLogger.shared.info("🎯 [iPad Navigation] Selecting addon: \(addon.name)")
        
        // Update state atomically to avoid conflicts
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedAddonForDetail = addon
            selectedApplicationForDetail = nil
            selectedDetailView = .addonDetail
        }
        
        // On iPad, force a UI refresh to ensure the detail view updates
        if isIpad {
            DispatchQueue.main.async {
                // This ensures the UI refresh happens after the state change
                print("🔄 [iPad Navigation] State updated - DetailView: \(selectedDetailView), Addon: \(selectedAddonForDetail?.name ?? "nil")")
            }
        }
    }
    
    private func selectNetworkGroups() {
        print("🎯 [iPad Navigation] Selecting Network Groups")
        RemoteLogger.shared.info("🎯 [iPad Navigation] Selecting Network Groups")
        
        // Update state atomically to avoid conflicts
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedDetailView = .networkGroups
            selectedApplicationForDetail = nil
            selectedAddonForDetail = nil
        }
        
        // On iPad, force a UI refresh to ensure the detail view updates
        if isIpad {
            DispatchQueue.main.async {
                // This ensures the UI refresh happens after the state change
                print("🔄 [iPad Navigation] State updated - DetailView: \(selectedDetailView)")
            }
        }
    }
    
    private func autoSelectFirstApplicationOnIpad() {
        if isIpad && !applications.isEmpty {
            if let firstApp = applications.first {
                selectApplicationDetail(firstApp)
            }
        }
    }

    // MARK: - Clever Cloud Title Logo
    
    private var cleverCloudTitleLogo: some View {
        Image("CleverCloudLogo")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(height: 32)
            .accessibility(label: Text("Clever Cloud"))
    }
    
    // MARK: - Logout Button
    
    private var logoutButton: some View {
        Button(action: {
            coordinator.logout()
        }) {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 14, weight: .medium))
                Text("Logout")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(.red)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.red.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - SDK Status Header
    
    private var sdkStatusHeader: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "cloud.circle.fill")
                    .font(.title2)
                    .foregroundColor(cleverCloudSDK.isAuthenticated ? .green : .red)
                
                VStack(alignment: .leading) {
                    Text("CleverCloud SDK")
                        .font(.headline)
                        .fontWeight(.semibold)
                    Text("Version \(CleverCloudSDK.version) • Debug: \(cleverCloudSDK.isDebugLoggingEnabled ? "ON" : "OFF")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(cleverCloudSDK.isAuthenticated ? "Connected" : "Disconnected")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(cleverCloudSDK.isAuthenticated ? .green : .red)
                    
                    // Polling status indicator
                    VStack(alignment: .trailing, spacing: 2) {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(isPollingActive ? Color.green : Color.red)
                                    .frame(width: 6, height: 6)
                                Text(eventSystemMode)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            
                            if isPollingActive {
                                Text("Polling every \(Int(pollingInterval))s")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            
                            if lastEventReceived != "None" {
                                Text("Last: \(lastEventReceived)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal)
                }
            }
            
            if let error = cleverCloudSDK.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundColor(.primary)
                    Spacer()
                }
                .padding(.top, 8)
                .onTapGesture {
                    cleverCloudSDK.clearLastError()
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    // MARK: - Organizations Card
    
    private var organizationsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "building.2.fill")
                    .foregroundColor(.blue)
                Text("Organizations")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(organizations.count)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(8)
            }
            
            if let selectedOrg = selectedOrganization {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Selected: \(selectedOrg.name)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        if isLoading && errorMessage?.contains("Switching to") == true {
                            Text("Auto-refreshing data...")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                    
                    Spacer()
                    
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background((isLoading ? Color.blue : Color.green).opacity(0.1))
                .cornerRadius(8)
                .animation(.easeInOut(duration: 0.3), value: isLoading)
            }
            
            if let orgError = organizationError {
                Text(orgError)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
            }
            
            // Filter Picker
            Picker("Filter", selection: $orgFilterMode) {
                ForEach(OrgFilterMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.vertical, 8)
            
            // Organizations List - Clickable for selection
            if !filteredOrganizations.isEmpty {
                LazyVStack(spacing: 12) {
                    ForEach(filteredOrganizations) { org in
                        organizationRowClickable(org)
                    }
                }
            } else if organizationError == nil && !organizations.isEmpty {
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "No Results",
                    subtitle: "No organizations match your filter"
                )
            } else if organizationError == nil {
                if isLoading {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading organizations...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical)
                } else {
                    EmptyStateView(
                        icon: "building.2",
                        title: "No Organizations",
                        subtitle: "Organizations will load automatically on app start"
                    )
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    // MARK: - Applications Card
    
    private var applicationsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "app.fill")
                    .foregroundColor(.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Applications")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    if let selectedOrg = selectedOrganization {
                        Text("for \(selectedOrg.name)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                
                Text("\(applications.count)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.purple.opacity(0.2))
                    .cornerRadius(8)
            }
            
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search applications...", text: $appSearchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                
                if !appSearchText.isEmpty {
                    Button(action: { appSearchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.vertical, 8)
            
            // Status Filters
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AppStatus.allCases, id: \.self) { status in
                        FilterChip(
                            title: status.rawValue,
                            icon: status.icon,
                            color: status.color,
                            isSelected: appFilterStatus == status
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                appFilterStatus = (appFilterStatus == status) ? nil : status
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 8)
            
            if isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading applications...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical)
            }
            
            // Applications List
            if !filteredApplications.isEmpty {
                LazyVStack(spacing: 12) {
                    ForEach(filteredApplications) { app in
                        applicationRow(app)
                    }
                }
            } else if !applications.isEmpty {
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "No Results",
                    subtitle: "No applications match your search or filters"
                )
            } else if !isLoading {
                EmptyStateView(
                    icon: "app",
                    title: "No Applications",
                    subtitle: "Load applications to view your Clever Cloud apps"
                )
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    // MARK: - Add-ons Card
    
    private var addonsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "puzzlepiece.extension.fill")
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add-ons")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    if let selectedOrg = selectedOrganization {
                        Text("for \(selectedOrg.name)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                
                // Create Add-on Button
                Button {
                    showingCreateAddon = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.orange)
                        .font(.title2)
                }
                
                Text("\(addons.count)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.2))
                    .cornerRadius(8)
            }
            
            if let addonError = addonError {
                Text(addonError)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
            }
            
            // Add-ons List
            if !addons.isEmpty {
                LazyVStack(spacing: 12) {
                    ForEach(addons) { addon in
                        addonRow(addon)
                    }
                }
            } else if addonError == nil {
                EmptyStateView(
                    icon: "puzzlepiece.extension",
                    title: "No Add-ons",
                    subtitle: "Test add-ons to view available services"
                )
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    // MARK: - Network Groups Card
    
    private var networkGroupsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "network")
                    .foregroundColor(.blue)
                    .font(.title)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Network Groups")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("Revolutionary networking visualization")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Navigate button pour iPhone, intégration pour iPad
                if isIpad {
                    // Sur iPad, déjà intégré dans la sidebar
                    Text("Integrated")
                        .font(.caption)
                        .foregroundColor(.green)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(15)
                } else {
                    // Sur iPhone, navigation vers la vue intégrée
                    NavigationLink(destination: networkGroupsModernView) {
                        HStack(spacing: 6) {
                            Text("Open")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(selectedOrganization != nil ? Color.blue : Color.gray)
                        .cornerRadius(20)
                    }
                    .disabled(selectedOrganization == nil)
                }
            }
            
            // Feature highlights
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .foregroundColor(.blue)
                        .font(.title2)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Interactive Graph Visualization")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Drag & drop network topology with real-time updates")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack(spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundColor(.green)
                        .font(.title2)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("WireGuard VPN Configuration")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Secure connections between applications and services")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack(spacing: 12) {
                    Image(systemName: "cube.transparent")
                        .foregroundColor(.purple)
                        .font(.title2)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("3D Visualization Coming Soon")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Experience your network topology in stunning 3D")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            if selectedOrganization == nil {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text("Select an organization to access Network Groups")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.blue.opacity(0.05),
                    Color.purple.opacity(0.05)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.blue.opacity(0.3),
                            Color.purple.opacity(0.3)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
    
    // MARK: - Network Groups View
    private var networkGroupsModernView: some View {
        Group {
            if let organizationId = selectedOrganization?.id {
                NetworkGroupsModernView(organizationId: organizationId, isEmbeddedInNavigationSplitView: false).environment(coordinator)
            } else {
                Text("Select an organization first")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    // MARK: - Testing Actions Card

    
    // MARK: - Helper Components
    
    struct EmptyStateView: View {
        let icon: String
        let title: String
        let subtitle: String
        
        var body: some View {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 40))
                    .foregroundColor(.secondary)
                
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 24)
        }
    }
    

    
    struct FilterChip: View {
        let title: String
        let icon: String
        let color: Color
        let isSelected: Bool
        let action: () -> Void
        
        var body: some View {
            Button(action: action) {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.caption)
                    Text(title)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? color : Color(.systemGray5))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(15)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    private func organizationRowClickable(_ org: CCOrganization) -> some View {
        Button(action: {
            selectOrganization(org)
        }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    // Favorite star icon
                    Button(action: {
                        toggleFavorite(org)
                    }) {
                        Image(systemName: favoriteOrgIds.contains(org.id) ? "star.fill" : "star")
                            .foregroundColor(favoriteOrgIds.contains(org.id) ? .yellow : .gray)
                            .font(.title2)
                            .animation(.easeInOut(duration: 0.2), value: favoriteOrgIds.contains(org.id))
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Image(systemName: org.organizationType.icon)
                        .foregroundColor(org.organizationType.color)
                        .font(.title2)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(org.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        Text(org.description ?? "No description")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(org.organizationType.description)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(org.organizationType.color.opacity(0.2))
                            .cornerRadius(6)
                        
                        // Selection indicator
                        if selectedOrganization?.id == org.id {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                                Text("Selected")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                                    .fontWeight(.medium)
                            }
                        }
                    }
                }
                
                if !org.fullAddress.isEmpty {
                    HStack {
                        Image(systemName: "location.fill")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text(org.fullAddress)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(
                selectedOrganization?.id == org.id 
                    ? Color.green.opacity(0.1)
                    : Color(.systemGray6)
            )
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        selectedOrganization?.id == org.id 
                            ? Color.green.opacity(0.5)
                            : Color.clear,
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func applicationRow(_ app: CCApplication) -> some View {
        NavigationLink(destination: ApplicationDetailView(application: app, cleverCloudSDK: cleverCloudSDK, organizationId: selectedOrganization?.id)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "app.badge")
                        .foregroundColor(.purple)
                        .font(.title2)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        if let description = app.description {
                            Text(description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        // Use real status from applicationStatuses dictionary or fallback to "Loading..."
                        let status = applicationStatuses[app.id] ?? "Loading..."
                        applicationStatusBadge(status)
                        
                        // Navigation indicator
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack {
                    Label(app.instance.type.capitalized, systemImage: "gear")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text(app.zone.uppercased())
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray5))
                        .cornerRadius(6)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func addonRow(_ addon: CCAddon) -> some View {
        NavigationLink(destination: AddonDetailView(addon: addon, organizationId: selectedOrganization?.id, viewModel: CleverCloudViewModel(cleverCloudSDK: cleverCloudSDK))) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "puzzlepiece.extension")
                        .foregroundColor(.orange)
                        .font(.title2)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(addon.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Text("Provider: \(addon.provider.name)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        // Status badge
                        addonStatusBadge(addon.status ?? "active")
                        
                        // Navigation indicator
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func addonStatusBadge(_ status: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(addonStatusColor(status))
                .frame(width: 8, height: 8)
            
            Text(status.capitalized)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(addonStatusColor(status).opacity(0.15))
        .foregroundColor(addonStatusColor(status))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(addonStatusColor(status).opacity(0.3), lineWidth: 0.5)
        )
    }
    
    private func addonStatusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "running", "up", "active":
            return .green
        case "creating", "starting":
            return .orange
        case "stopped", "down":
            return .gray
        case "error", "failed":
            return .red
        default:
            return .blue
        }
    }
    
    private func applicationStatusBadge(_ state: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(colorForState(state))
                .frame(width: 8, height: 8)
            
            Text(state.capitalized)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(colorForState(state).opacity(0.15))
        .foregroundColor(colorForState(state))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(colorForState(state).opacity(0.3), lineWidth: 0.5)
        )
    }
    
    private func colorForState(_ state: String) -> Color {
        switch state.lowercased() {
        case "running", "up":
            return .green
        case "deploying", "starting", "restarting":
            return .orange
        case "sleeping":
            return .blue
        case "stopped", "down", "should be down":
            return .gray
        case "failed":
            return .red
        case "loading...", "loading":
            return .blue
        default:
            return .gray
        }
    }
    
    // MARK: - Helper Methods
    
    private func toggleFavorite(_ org: CCOrganization) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if favoriteOrgIds.contains(org.id) {
                favoriteOrgIds.removeAll { $0 == org.id }
                RemoteLogger.shared.info("⭐ Removed \(org.name) from favorites")
            } else {
                favoriteOrgIds.append(org.id)
                RemoteLogger.shared.info("⭐ Added \(org.name) to favorites")
            }
            saveFavorites()
        }
    }
    
    private func loadFavorites() {
        if let savedFavorites = UserDefaults.standard.array(forKey: "com.cleveriosclient.favoriteOrganizations") as? [String] {
            favoriteOrgIds = savedFavorites
            RemoteLogger.shared.info("📱 Loaded \(savedFavorites.count) favorite organizations")
        }
    }
    
    private func saveFavorites() {
        UserDefaults.standard.set(favoriteOrgIds, forKey: "com.cleveriosclient.favoriteOrganizations")
        RemoteLogger.shared.info("💾 Saved \(favoriteOrgIds.count) favorite organizations")
    }
    
    // MARK: - Methods
    
    private func loadApplications() {
        isLoading = true
        errorMessage = nil
        
        // Load applications using SDK
        cleverCloudSDK.getUserApplications()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    isLoading = false
                    if case .failure(let error) = completion {
                        errorMessage = error.localizedDescription
                        print("❌ REAL API ERROR: \(error)")
                        print("📋 Error Type: \(error)")
                        print("📋 Localized: \(error.localizedDescription)")
                    }
                },
                receiveValue: { apps in
                    applications = apps
                    print("✅ REAL API SUCCESS: Loaded \(apps.count) applications from Clever Cloud!")
                    for app in apps {
                        print("📱 App: \(app.name) - \(app.instance.type)")
                    }
                    
                    // Load real status for each application
                    Task {
                        loadApplicationStatuses(for: apps)
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    private func testOrganizations() {
        organizationError = nil
        organizations = []
        errorMessage = "🔄 Loading all organizations..."
        isLoading = true
        
        // Use only getUserOrganizations since it already returns everything (personal space + organizations)
        cleverCloudSDK.getUserOrganizations()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    isLoading = false
                    if case .failure(let error) = completion {
                        organizationError = "Error: \(error.localizedDescription)"
                        errorMessage = "❌ Organizations load failed: \(error.localizedDescription)"
                    } else {
                        errorMessage = "✅ All organizations loaded successfully!"
                    }
                },
                receiveValue: { allOrganizations in
                    organizations = allOrganizations
                    
                    // Auto-select the first organization (usually personal space)
                    if let firstOrg = allOrganizations.first {
                        selectedOrganization = firstOrg
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: - Data Loading
    @MainActor
    private func loadData() {
        testOrganizations()
        // Load applications and statuses after organizations are loaded
        if !applications.isEmpty {
            loadApplicationStatuses(for: applications)
        }
    }
    
    @MainActor
    private func loadApplicationStatuses(for apps: [CCApplication]) {
        // Initialize apps with Loading status
        for app in apps {
            applicationStatuses[app.id] = "Loading..."
        }
        
        // Load real application statuses using instance API calls (with concurrency safety)
        let group = DispatchGroup()
        
        // Capture main actor values before entering background context
        let currentOrgId = selectedOrganization?.id
        let sdk = cleverCloudSDK
        
        // Process apps sequentially to be conservative
        for (index, app) in apps.enumerated() {
            group.enter()
            
            let appId = app.id
            _ = app.name
            
            // Make the API call on main queue to avoid concurrency issues
            let instancesPublisher: AnyPublisher<[CCApplicationInstance], CCError>
            if let orgId = currentOrgId, orgId.hasPrefix("orga_") {
                // Organization context
                instancesPublisher = sdk.applications.getApplicationInstances(applicationId: appId, organizationId: orgId)
            } else {
                // Personal space context
                instancesPublisher = sdk.applications.getApplicationInstances(applicationId: appId)
            }
            
            // Add small delay between requests to be conservative
            let delay = Double(index) * 0.2 // 200ms delay between each request
            
            instancesPublisher
                .delay(for: .milliseconds(Int(delay * 1000)), scheduler: DispatchQueue.main)
                .timeout(.seconds(10), scheduler: DispatchQueue.main)
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { completion in
                        if case .failure(_) = completion {
                            applicationStatuses[appId] = "Error"
                        }
                        group.leave()
                    },
                    receiveValue: { instances in
                        let computedStatus = computeApplicationStatus(from: instances)
                        applicationStatuses[appId] = computedStatus
                    }
                )
                .store(in: &cancellables)
        }
    }
    
    /// Compute application status from instances (following clever-tools computeStatus pattern)
    private func computeApplicationStatus(from instances: [CCApplicationInstance]) -> String {
        guard !instances.isEmpty else {
            return "Stopped"
        }
        
        let instanceStates = instances.map { $0.state.uppercased() }
        
        // Priority order based on clever-tools logic
        if instanceStates.contains("FAILED") {
            return "Failed"
        }
        
        if instanceStates.contains("DEPLOYING") {
            return "Deploying"
        }
        
        if instanceStates.contains("UP") {
            return "Running"
        }
        
        if instanceStates.contains("DOWN") || instanceStates.contains("SHOULD_BE_DOWN") {
            return "Stopped"
        }
        
        // Default case
        return "Unknown"
    }
    
    // MARK: - CCApplicationService Test Methods
    
    private func testGetApplications() {
        // Determine which organization to use
        let targetOrganization = selectedOrganization ?? organizations.first
        let orgName = targetOrganization?.name ?? "Default"
        let orgId = targetOrganization?.id
        
        errorMessage = "Loading applications for \(orgName)..."
        isLoading = true
        
        // Use organization-specific method if organization is selected
        let applicationsPublisher: AnyPublisher<[CCApplication], CCError>
        
        if let orgId = orgId, orgId.hasPrefix("orga_") {
            // Real organization - use organization applications endpoint WITH STATES
            applicationsPublisher = cleverCloudSDK.applications.getApplicationsWithStates(forOrganization: orgId)
        } else {
            // Personal space - use user applications endpoint WITH STATES
            applicationsPublisher = cleverCloudSDK.applications.getApplicationsWithStates()
        }
        
        applicationsPublisher
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    isLoading = false
                    if case .failure(let error) = completion {
                        errorMessage = "getApplications failed for \(orgName): \(error.localizedDescription)"
                    } else {
                        errorMessage = "✅ Applications loaded for \(orgName)!"
                    }
                },
                receiveValue: { apps in
                    applications = apps
                    
                    // Load real status for each application  
                    Task { @MainActor in
                        loadApplicationStatuses(for: apps)
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    private func testGetApplicationById() {
        isLoading = true
        errorMessage = nil
        
        // Use the first application's ID if available
        guard let firstApp = applications.first else {
            errorMessage = "No applications available. Run 'Test Get Apps' first."
            isLoading = false
            return
        }
        
        print("🧪 Testing: getApplication(id: \(firstApp.id))")
        
        cleverCloudSDK.getApplication(id: firstApp.id)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    isLoading = false
                    if case .failure(let error) = completion {
                        errorMessage = "getApplication failed: \(error.localizedDescription)"
                        print("❌ Test Failed: getApplication - \(error)")
                    } else {
                        print("✅ Test Passed: getApplication")
                    }
                },
                receiveValue: { app in
                    print("✅ Test Result: Retrieved app '\(app.name)' with ID \(app.id)")
                }
            )
            .store(in: &cancellables)
    }
    
    private func testGetOrgApplications() {
        errorMessage = "Organization apps: This feature will be implemented in Phase 2"
        print("🧪 Testing: Organization Applications - Feature not yet implemented")
    }
    
    private func testCreateApplication() {
        errorMessage = "Create app: This feature will be implemented in Phase 2"
        print("🧪 Testing: Create Application - Feature not yet implemented")
    }
    
    private func testUpdateApplication() {
        errorMessage = "Update app: This feature will be implemented in Phase 2"
        print("🧪 Testing: Update Application - Feature not yet implemented")
    }
    
    private func testDeleteApplication() {
        errorMessage = "Delete app: This feature will be implemented in Phase 2"
        print("🧪 Testing: Delete Application - Feature not yet implemented")
    }
    
    private func testDeployApplication() {
        errorMessage = "Deploy app: This feature will be implemented in Phase 2"
        print("🧪 Testing: Deploy Application - Feature not yet implemented")
    }
    
    private func testApplicationEnvVars() {
        errorMessage = "Env vars: This feature will be implemented in Phase 2"
        print("🧪 Testing: Environment Variables - Feature not yet implemented")
    }
    
    private func testApplicationInstances() {
        errorMessage = "Instances: This feature will be implemented in Phase 2"
        print("🧪 Testing: Application Instances - Feature not yet implemented")
    }
    
    // MARK: - CCAddonService Test Methods
    
    private func testGetAddons() {
        // Determine which organization to use
        let targetOrganization = selectedOrganization ?? organizations.first
        let orgName = targetOrganization?.name ?? "Default"
        let orgId = targetOrganization?.id
        
        // Clear previous state
        addonError = nil
        addons = []
        errorMessage = "Loading add-ons for \(orgName)..."
        isLoading = true
        
        // Use organization-specific method if organization is selected
        let addonsPublisher: AnyPublisher<[CCAddon], CCError>
        
        if let orgId = orgId, orgId.hasPrefix("orga_") {
            // Real organization - use organization addons endpoint
            addonsPublisher = cleverCloudSDK.getOrganizationAddons(organizationId: orgId)
        } else {
            // Personal space - use user addons endpoint
            addonsPublisher = cleverCloudSDK.getUserAddons()
        }
        
        addonsPublisher
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    isLoading = false
                    if case .failure(let error) = completion {
                        addonError = error.localizedDescription
                        errorMessage = "getAddons failed for \(orgName): \(error.localizedDescription)"
                    } else {
                        errorMessage = "✅ Add-ons loaded successfully for \(orgName)!"
                    }
                },
                receiveValue: { loadedAddons in
                    addons = loadedAddons
                }
            )
            .store(in: &cancellables)
    }
    
    private func testGetAddonProviders() {
        // Clear previous state
        addonError = nil
        addonProviders = []
        errorMessage = "Loading add-on providers..."
        isLoading = true
        
        cleverCloudSDK.getAddonProviders()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    isLoading = false
                    if case .failure(let error) = completion {
                        addonError = error.localizedDescription
                        errorMessage = "getAddonProviders failed: \(error.localizedDescription)"
                    } else {
                        errorMessage = "✅ Add-on providers loaded successfully!"
                    }
                },
                receiveValue: { providers in
                    addonProviders = providers
                }
            )
            .store(in: &cancellables)
    }
    
    private func testCreateAddon() {
        errorMessage = "Create addon: This feature will be implemented next"
        print("🧪 Testing: Create Add-on - Feature implementation in progress")
    }
    
    private func testGetAddonsForOrganization(_ organization: CCOrganization) {
        // Clear previous state
        addonError = nil
        addons = []
        errorMessage = "Loading add-ons for \(organization.name)..."
        isLoading = true
        
        // Note: This method doesn't exist yet in CCAddonService, so we'll simulate it
        // In the real implementation, we would call:
        // cleverCloudSDK.getOrganizationAddons(organizationId: organization.id)
        
        // For now, test with user addons but show it's for the organization
        cleverCloudSDK.getUserAddons()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    isLoading = false
                    if case .failure(let error) = completion {
                        addonError = "Failed to load \(organization.name) add-ons: \(error.localizedDescription)"
                        errorMessage = "Organization add-ons failed: \(error.localizedDescription)"
                    } else {
                        errorMessage = "✅ Add-ons for \(organization.name) loaded!"
                    }
                },
                receiveValue: { loadedAddons in
                    addons = loadedAddons
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: - Auto-Refresh Methods
    
    /// Select an organization and trigger auto-refresh
    private func selectOrganization(_ organization: CCOrganization) {
        selectedOrganization = organization
        // The onChange modifier will automatically trigger autoRefreshOrganizationData
    }
    
    /// Automatically refresh applications and add-ons when organization changes
    private func autoRefreshOrganizationData(for organization: CCOrganization) {
        // Clear error states
        errorMessage = nil
        addonError = nil
        
        // Set loading state with organization context
        isLoading = true
        errorMessage = "🔄 Switching to \(organization.name)..."
        
        // Store current selection for iPad to maintain after reload
        let currentAppSelection = selectedApplicationForDetail
        let currentAddonSelection = selectedAddonForDetail
        let currentDetailView = selectedDetailView
        
        // Small delay for better UX (visual feedback)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // Auto-load applications for the new organization
            testGetApplications()
            
            // Auto-load add-ons for the new organization (after applications)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                testGetAddons()
                
                // On iPad, try to maintain the previous selection after data reload
                if isIpad {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        maintainSelectionAfterDataReload(
                            previousApp: currentAppSelection,
                            previousAddon: currentAddonSelection,
                            previousDetailView: currentDetailView
                        )
                    }
                }
            }
        }
    }
    
    /// Maintain selection after data reload on iPad
    private func maintainSelectionAfterDataReload(
        previousApp: CCApplication?,
        previousAddon: CCAddon?,
        previousDetailView: DetailViewType
    ) {
        guard isIpad else { return }
        
        switch previousDetailView {
        case .applicationDetail:
            if let prevApp = previousApp {
                // Try to find the same application in the new data
                if let newApp = applications.first(where: { $0.id == prevApp.id }) {
                    print("🔄 [iPad Navigation] Maintaining application selection: \(newApp.name)")
                    selectApplicationDetail(newApp)
                } else {
                    print("🔄 [iPad Navigation] Previous app not found, staying on dashboard")
                }
            }
        case .addonDetail:
            if let prevAddon = previousAddon {
                // Try to find the same addon in the new data
                if let newAddon = addons.first(where: { $0.id == prevAddon.id }) {
                    print("🔄 [iPad Navigation] Maintaining addon selection: \(newAddon.name)")
                    selectAddonDetail(newAddon)
                } else {
                    print("🔄 [iPad Navigation] Previous addon not found, staying on dashboard")
                }
            }
        case .networkGroups:
            // Maintain network groups selection (it will reload with new organization data)
            print("🔄 [iPad Navigation] Maintaining Network Groups selection")
            selectNetworkGroups()
        case .dashboard:
            // Already on dashboard, nothing to do
            break
        }
    }
    
    // MARK: - SwiftData Methods (Original)
    
    private func addItem() {
        withAnimation {
            let newItem = Item(timestamp: Date())
            modelContext.insert(newItem)
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(items[index])
            }
        }
    }
    
    // MARK: - Reset Authentication
    
    private func resetAuthentication() {
        print("🎯 Reset Authentication")
        cleverCloudSDK.resetAuthentication()
        errorMessage = "Authentication reset. Please log in again."
        isLoading = false
        applications = []
        organizations = []
        addons = []
        addonProviders = []
        selectedOrganization = nil
    }
    
    // MARK: - Event System Management
    private func setupPollingSystem() {
        let message = "🔄 Setting up intelligent polling system..."
        print(message)
        writeToDebugLog(message)
        
        // Listen to connection state changes
        cleverCloudSDK.events.connectionStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { state in
                handleConnectionStateChange(state)
            }
            .store(in: &eventsCancellables)
        
        // Listen to platform events
        cleverCloudSDK.events.eventPublisher
            .receive(on: DispatchQueue.main)
            .sink { completion in
                if case .failure(let error) = completion {
                    print("❌ Events stream error: \(error)")
                }
            } receiveValue: { event in
                handlePlatformEvent(event)
            }
            .store(in: &eventsCancellables)
        
        // Start polling
        startIntelligentPolling()
    }
    
    private func teardownPollingSystem() {
        print("🛑 Stopping polling system...")
        writeToDebugLog("🛑 Stopping polling system...")
        
        cleverCloudSDK.events.disconnect()
        eventsCancellables.removeAll()
        stopIntelligentPolling()
        
        isPollingActive = false
        eventSystemMode = "Disconnected"
    }
    
    private func handleConnectionStateChange(_ state: CCConnectionState) {
        switch state {
        case .disconnected:
            isPollingActive = false
            eventSystemMode = "Disconnected"
            print("⚪ Event system disconnected")
            
        case .polling:
            isPollingActive = true
            eventSystemMode = "Polling Active"
            print("🟢 Polling system active")
            
        case .failed(let error):
            isPollingActive = false
            eventSystemMode = "Error"
            print("🔴 Event system error: \(error)")
        }
    }
    
    private func handlePlatformEvent(_ event: CCPlatformEvent) {
        print("📡 Platform event: \(event.type)")
        lastEventReceived = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        
        // Handle specific event types here
        // For example: refresh application statuses on status change events
    }
    
    // MARK: - Intelligent Polling System
    private func startIntelligentPolling() {
        // Stop any existing timer
        stopIntelligentPolling()
        
        print("🔄 Starting intelligent status polling every \(pollingInterval) seconds")
        writeToDebugLog("🔄 Starting intelligent status polling every \(pollingInterval) seconds")
        
        // Initial poll immediately
        refreshApplicationStatuses()
        
        // Connect to events service
        cleverCloudSDK.events.connect()
        
        pollingTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { _ in
            Task { @MainActor in
                refreshApplicationStatuses()
            }
        }
    }
    
    private func stopIntelligentPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        print("⏹️ Stopped intelligent polling")
        writeToDebugLog("⏹️ Stopped intelligent polling")
    }
    
    private func refreshApplicationStatuses() {
        guard !applications.isEmpty else { return }
        
        print("🔄 Refreshing application statuses...")
        writeToDebugLog("🔄 Refreshing application statuses...")
        Task { @MainActor in
            loadApplicationStatuses(for: applications)
        }
    }
    

    
    private func writeToDebugLog(_ message: String) {
        let timestamp = DateFormatter().string(from: Date())
        let logMessage = "[\(timestamp)] \(message)\n"
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let logFile = documentsPath.appendingPathComponent("debug.log")
        
        if let data = logMessage.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFile.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logFile) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: logFile)
            }
        }
    }
    
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}

