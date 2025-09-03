import SwiftUI
import Combine

// MARK: - NetworkGroupsModernView
/// STUNNING PREMIUM interface for Network Groups - iPad Masterpiece
struct NetworkGroupsModernView: View {
    
    // MARK: - Environment
    @Environment(AppCoordinator.self) private var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - Properties
    let organizationId: String
    let isEmbeddedInNavigationSplitView: Bool // New parameter to avoid nested NavigationSplitViews
    
    // MARK: - Initializers
    init(organizationId: String, isEmbeddedInNavigationSplitView: Bool = false) {
        self.organizationId = organizationId
        self.isEmbeddedInNavigationSplitView = isEmbeddedInNavigationSplitView
    }
    
    // MARK: - State
    @State private var networkGroups: [CCNetworkGroup] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var selectedNetworkGroup: CCNetworkGroup?
    @State private var showingCreateNetworkGroup = false
    @State private var viewMode: ViewMode = .grid
    @State private var selectedFilter: NetworkGroupFilter = .all
    @State private var cancellables = Set<AnyCancellable>()
    @State private var hoveredCard: CCNetworkGroup?
    @State private var showingDetailAnimation = false
    
    // MARK: - Computed Properties

    /// Check if we're on iPad - Using Apple recommended method
    private var isIpad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }
    
    /// Filtered network groups based on search and filter
    private var filteredNetworkGroups: [CCNetworkGroup] {
        var groups = networkGroups
        
        // Apply search filter
        if !searchText.isEmpty {
            groups = groups.filter { group in
                group.name.localizedCaseInsensitiveContains(searchText) ||
                group.description?.localizedCaseInsensitiveContains(searchText) == true ||
                group.cidr?.contains(searchText) == true
            }
        }
        
        // Apply status filter
        switch selectedFilter {
        case .all:
            break
        case .active:
            groups = groups.filter { $0.isActive }
        case .inactive:
            groups = groups.filter { !$0.isActive }
        case .recent:
            // Sort by creation date and take recent ones
            groups = groups.sorted { 
                ($0.createdAt ?? Date.distantPast) > ($1.createdAt ?? Date.distantPast) 
            }.prefix(10).map { $0 }
        }
        
        return groups
    }
    
    // MARK: - Body
    var body: some View {
        Group {
            if isIpad && !isEmbeddedInNavigationSplitView {
                // Full-screen iPad layout with own NavigationSplitView
                stunningIPadLayout
                    .onAppear {
                        print("🔴 [NetworkGroupsModernView] USING stunningIPadLayout - isIpad: \(isIpad), isEmbeddedInNavigationSplitView: \(isEmbeddedInNavigationSplitView)")
                        RemoteLogger.shared.error("🔴 [NetworkGroupsModernView] USING stunningIPadLayout - isIpad: \(isIpad), isEmbeddedInNavigationSplitView: \(isEmbeddedInNavigationSplitView)")
                    }
            } else if isIpad && isEmbeddedInNavigationSplitView {
                // Embedded iPad layout without NavigationSplitView (optimized for ContentView)
                embeddedIPadLayout
                    .onAppear {
                        print("🟢 [NetworkGroupsModernView] USING embeddedIPadLayout - isIpad: \(isIpad), isEmbeddedInNavigationSplitView: \(isEmbeddedInNavigationSplitView)")
                        RemoteLogger.shared.info("🟢 [NetworkGroupsModernView] USING embeddedIPadLayout - isIpad: \(isIpad), isEmbeddedInNavigationSplitView: \(isEmbeddedInNavigationSplitView)")
                    }
            } else {
                // iPhone layout
                iPhoneLayout
                    .onAppear {
                        print("🟡 [NetworkGroupsModernView] USING iPhoneLayout - isIpad: \(isIpad), isEmbeddedInNavigationSplitView: \(isEmbeddedInNavigationSplitView)")
                        RemoteLogger.shared.info("🟡 [NetworkGroupsModernView] USING iPhoneLayout - isIpad: \(isIpad), isEmbeddedInNavigationSplitView: \(isEmbeddedInNavigationSplitView)")
                    }
            }
        }
        .onAppear {
            print("🔍 [NetworkGroupsModernView] INIT CHECK - UIDevice.userInterfaceIdiom: \(UIDevice.current.userInterfaceIdiom), isIpad computed: \(isIpad)")
            RemoteLogger.shared.info("🔍 [NetworkGroupsModernView] INIT CHECK - UIDevice.userInterfaceIdiom: \(UIDevice.current.userInterfaceIdiom), isIpad computed: \(isIpad)")
            
            loadNetworkGroups()
            withAnimation(.easeInOut(duration: 0.6)) {
                showingDetailAnimation = true
            }
        }
        .navigationTitle("Network Groups")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingCreateNetworkGroup = true }) {
                    Image(systemName: "plus")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
            }
            
            if !isIpad {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Back") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingCreateNetworkGroup) {
            CreateNetworkGroupView(
                organizationId: organizationId,
                onNetworkGroupCreated: { newNetworkGroup in
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                        networkGroups.append(newNetworkGroup)
                        if isIpad {
                            selectedNetworkGroup = newNetworkGroup
                        }
                    }
                }
            )
            .environment(coordinator)
        }
    }
    
    // MARK: - STUNNING iPad Layout ✨
    private var stunningIPadLayout: some View {
        NavigationSplitView {
            // GORGEOUS PREMIUM SIDEBAR 🎨
            VStack(spacing: 0) {
                // PREMIUM HEADER with gradient
                premiumSidebarHeader
                
                // STUNNING NETWORK GROUPS DISPLAY
                if isLoading {
                    stunningLoadingView
                } else if networkGroups.isEmpty {
                    gorgeousEmptyStateView
                } else {
                    stunningNetworkGroupsList
                }
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(.systemBackground),
                        Color(.systemBackground).opacity(0.95),
                        Color(.systemGroupedBackground)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .navigationTitle("Network Groups")
            .navigationBarTitleDisplayMode(.large)
            .navigationSplitViewColumnWidth(min: 380, ideal: 420, max: 480)
        } detail: {
            // PREMIUM DETAIL VIEW ✨
            if let selectedGroup = selectedNetworkGroup {
                VStack(spacing: 0) {
                    // GORGEOUS STATISTICS DASHBOARD
                    premiumStatsDashboard
                    
                    // MAIN DETAIL CONTENT with animation
                    NetworkGroupDetailView(
                        networkGroup: selectedGroup,
                        organizationId: organizationId
                    )
                    .environment(coordinator)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                }
            } else {
                magnificentWelcomeView
            }
        }
        .onAppear {
            // Auto-select first network group with smooth animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if selectedNetworkGroup == nil && !networkGroups.isEmpty {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        selectedNetworkGroup = networkGroups.first
                    }
                }
            }
        }
    }
    
    // MARK: - EMBEDDED iPad Layout ✨ (for use inside ContentView)
    private var embeddedIPadLayout: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // GORGEOUS PREMIUM SIDEBAR 🎨 - Now as a regular HStack component
                VStack(spacing: 0) {
                    // PREMIUM HEADER with gradient
                    premiumSidebarHeader
                    
                    // STUNNING NETWORK GROUPS DISPLAY
                    if isLoading {
                        stunningLoadingView
                    } else if networkGroups.isEmpty {
                        gorgeousEmptyStateView
                    } else {
                        stunningNetworkGroupsList
                    }
                }
                .frame(width: min(geometry.size.width * 0.6, 600)) // Increased from 0.4 to 0.6 and max from 480 to 600
                .background(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                
                // DETAIL PANEL 🎨 - Clean implementation
                VStack(spacing: 0) {
                    if let selectedNetworkGroup = selectedNetworkGroup {
                        // Network group details in the panel
                        NetworkGroupDetailView(
                            networkGroup: selectedNetworkGroup,
                            organizationId: organizationId
                        )
                        .environment(coordinator)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        // Welcome view when no network group selected
                        VStack(spacing: 24) {
                            Image(systemName: "network")
                                .font(.system(size: 48, weight: .light))
                                .foregroundColor(.secondary)
                            
                            Text("Select a Network Group")
                                .font(.title2)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            
                            Text("Choose a network group from the sidebar to view its details and manage connections.")
                                .font(.body)
                                .multilineTextAlignment(.center)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 32)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .background(Color(UIColor.systemBackground))
            }
        }
        .onAppear {
            loadNetworkGroups()
            withAnimation(.easeInOut(duration: 0.6)) {
                showingDetailAnimation = true
            }
        }
    }
    
    // MARK: - Premium Sidebar Header ✨
    private var premiumSidebarHeader: some View {
        VStack(spacing: 20) {
            // ELEGANT SEARCH with premium styling
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.blue)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 20, height: 20)
                
                TextField("Search network groups...", text: $searchText)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .textFieldStyle(PlainTextFieldStyle())
                
                if !searchText.isEmpty {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            searchText = ""
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                            .font(.system(size: 16))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.tertiarySystemFill))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 20)
            
            // PREMIUM FILTER CHIPS with animations
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(NetworkGroupFilter.allCases, id: \.self) { filter in
                        premiumFilterChip(filter: filter)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.vertical, 24)
        .background(
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    Color(.systemBackground).opacity(0.98)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .overlay(
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.05)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1),
                alignment: .bottom
            )
        )
    }
    
    // MARK: - Premium Filter Chip ✨
    private func premiumFilterChip(filter: NetworkGroupFilter) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                selectedFilter = filter
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: filter.icon)
                    .font(.system(size: 14, weight: .semibold))
                
                Text(filter.displayName)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Group {
                    if selectedFilter == filter {
                        LinearGradient(
                            colors: [Color.blue, Color.blue.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    } else {
                        Color(.tertiarySystemFill)
                    }
                }
            )
            .foregroundColor(selectedFilter == filter ? .white : .primary)
            .cornerRadius(20)
            .shadow(
                color: selectedFilter == filter ? Color.blue.opacity(0.3) : Color.clear,
                radius: selectedFilter == filter ? 4 : 0,
                x: 0,
                y: selectedFilter == filter ? 2 : 0
            )
        }
        .scaleEffect(selectedFilter == filter ? 1.05 : 1.0)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: selectedFilter)
    }
    
    // MARK: - Stunning Network Groups List ✨
    private var stunningNetworkGroupsList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(Array(filteredNetworkGroups.enumerated()), id: \.element.id) { index, group in
                    magnificentNetworkGroupCard(group: group, index: index)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                selectedNetworkGroup = group
                            }
                        }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }
    
    // MARK: - Magnificent Network Group Card ✨
    private func magnificentNetworkGroupCard(group: CCNetworkGroup, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // PREMIUM HEADER with status and region
            HStack {
                // ANIMATED STATUS INDICATOR
                HStack(spacing: 8) {
                    Circle()
                        .fill(group.isActive ? Color.green : Color.orange)
                        .frame(width: 10, height: 10)
                        .shadow(
                            color: group.isActive ? Color.green.opacity(0.4) : Color.orange.opacity(0.4),
                            radius: 4,
                            x: 0,
                            y: 2
                        )
                        .scaleEffect(group.isActive ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: group.isActive)
                    
                    Text(group.isActive ? "Active" : "Inactive")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(group.isActive ? .green : .orange)
                }
                
                Spacer()
                
                // PREMIUM REGION BADGE
                if let region = group.region {
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                            .font(.system(size: 10, weight: .bold))
                        
                        Text(region.uppercased())
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        LinearGradient(
                            colors: [Color.blue, Color.blue.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .shadow(color: Color.blue.opacity(0.3), radius: 2, x: 0, y: 1)
                }
            }
            
            // NETWORK GROUP NAME with premium typography
            Text(group.name)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(2)
            
            // DESCRIPTION if available
            if let description = group.description, !description.isEmpty {
                Text(description)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            
            // CIDR NETWORK INFO with premium styling
            if let cidr = group.cidr {
                HStack(spacing: 8) {
                    Image(systemName: "network")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.blue)
                    
                    Text(cidr)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(.blue)
                    
                    Spacer()
                    
                    // SELECTION INDICATOR
                    if selectedNetworkGroup?.id == group.id {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.blue)
                            .scaleEffect(1.1)
                            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: selectedNetworkGroup?.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.08))
                .cornerRadius(8)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(
                    color: selectedNetworkGroup?.id == group.id ? Color.blue.opacity(0.2) : Color.black.opacity(0.08),
                    radius: selectedNetworkGroup?.id == group.id ? 8 : 4,
                    x: 0,
                    y: selectedNetworkGroup?.id == group.id ? 4 : 2
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            selectedNetworkGroup?.id == group.id ? 
                            LinearGradient(colors: [Color.blue, Color.blue.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing) :
                            LinearGradient(colors: [Color.clear], startPoint: .top, endPoint: .bottom),
                            lineWidth: selectedNetworkGroup?.id == group.id ? 2 : 0
                        )
                )
        )
        .scaleEffect(selectedNetworkGroup?.id == group.id ? 1.02 : 1.0)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: selectedNetworkGroup?.id)
        .transition(.asymmetric(
            insertion: .scale(scale: 0.8).combined(with: .opacity).animation(.spring(response: 0.6, dampingFraction: 0.8).delay(Double(index) * 0.1)),
            removal: .scale(scale: 0.8).combined(with: .opacity)
        ))
    }
    
    // MARK: - Premium Stats Dashboard ✨
    private var premiumStatsDashboard: some View {
        HStack(spacing: 24) {
            // PREMIUM STATISTICS with gorgeous cards
            HStack(spacing: 20) {
                premiumStatCard(
                    title: "Total",
                    value: "\(networkGroups.count)",
                    icon: "network",
                    color: .blue,
                    gradient: [Color.blue, Color.blue.opacity(0.7)]
                )
                
                premiumStatCard(
                    title: "Active",
                    value: "\(networkGroups.filter { $0.isActive }.count)",
                    icon: "checkmark.circle.fill",
                    color: .green,
                    gradient: [Color.green, Color.green.opacity(0.7)]
                )
                
                premiumStatCard(
                    title: "Inactive",
                    value: "\(networkGroups.filter { !$0.isActive }.count)",
                    icon: "xmark.circle.fill",
                    color: .orange,
                    gradient: [Color.orange, Color.orange.opacity(0.7)]
                )
            }
            
            Spacer()
            
            // PREMIUM ACTION BUTTONS
            HStack(spacing: 12) {
                // Refresh Button
                Button(action: loadNetworkGroups) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.blue)
                        .frame(width: 36, height: 36)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(18)
                }
                .buttonStyle(PlainButtonStyle())
                
                // Create Button
                Button(action: { showingCreateNetworkGroup = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                        
                        Text("Create")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(
                            colors: [Color.blue, Color.blue.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(18)
                    .shadow(color: Color.blue.opacity(0.3), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .background(
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    Color(.systemGroupedBackground).opacity(0.3)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .overlay(
                Rectangle()
                    .fill(Color(.separator).opacity(0.3))
                    .frame(height: 0.5),
                alignment: .bottom
            )
        )
    }
    
    // MARK: - Premium Stat Card ✨
    private func premiumStatCard(title: String, value: String, icon: String, color: Color, gradient: [Color]) -> some View {
        HStack(spacing: 12) {
            // ICON with gradient background
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(
                    LinearGradient(
                        colors: gradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(18)
                .shadow(color: color.opacity(0.4), radius: 4, x: 0, y: 2)
            
            // VALUE AND TITLE
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(color)
                
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Stunning Loading View ✨
    private var stunningLoadingView: some View {
        VStack(spacing: 24) {
            // ANIMATED LOADING INDICATOR
            ZStack {
                Circle()
                    .stroke(Color.blue.opacity(0.2), lineWidth: 4)
                    .frame(width: 60, height: 60)
                
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(
                        LinearGradient(
                            colors: [Color.blue, Color.blue.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false), value: showingDetailAnimation)
            }
            
            VStack(spacing: 8) {
                Text("Loading Network Groups")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text("Please wait while we fetch your network configuration...")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color(.systemBackground).opacity(0.8),
                    Color(.systemGroupedBackground).opacity(0.6)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
    
    // MARK: - Gorgeous Empty State View ✨
    private var gorgeousEmptyStateView: some View {
        VStack(spacing: 32) {
            // PREMIUM ILLUSTRATION
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                
                Image(systemName: "network.slash")
                    .font(.system(size: 48, weight: .thin))
                    .foregroundColor(.blue)
                    .scaleEffect(showingDetailAnimation ? 1.0 : 0.8)
                    .animation(.spring(response: 0.8, dampingFraction: 0.6).delay(0.2), value: showingDetailAnimation)
            }
            
            VStack(spacing: 16) {
                Text("No Network Groups Yet")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text("Create your first network group to securely connect your applications and services with advanced networking capabilities.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
                    .lineSpacing(4)
                
                // PREMIUM CREATE BUTTON
                Button(action: { showingCreateNetworkGroup = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                        
                        Text("Create Network Group")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [Color.blue, Color.blue.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(22)
                    .shadow(color: Color.blue.opacity(0.4), radius: 8, x: 0, y: 4)
                }
                .scaleEffect(showingDetailAnimation ? 1.0 : 0.9)
                .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.4), value: showingDetailAnimation)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    Color(.systemGroupedBackground).opacity(0.5)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
    
    // MARK: - Magnificent Welcome View ✨
    private var magnificentWelcomeView: some View {
        VStack(spacing: 40) {
            // SPECTACULAR WELCOME ILLUSTRATION
            ZStack {
                // Background glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.blue.opacity(0.15),
                                Color.blue.opacity(0.05),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 100
                        )
                    )
                    .frame(width: 200, height: 200)
                    .scaleEffect(showingDetailAnimation ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: showingDetailAnimation)
                
                // Main icon
                Image(systemName: "network")
                    .font(.system(size: 64, weight: .ultraLight))
                    .foregroundColor(.blue)
                    .scaleEffect(showingDetailAnimation ? 1.0 : 0.8)
                    .animation(.spring(response: 1.0, dampingFraction: 0.6).delay(0.3), value: showingDetailAnimation)
            }
            
            VStack(spacing: 20) {
                Text("Select a Network Group")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .opacity(showingDetailAnimation ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.8).delay(0.5), value: showingDetailAnimation)
                
                Text("Choose a network group from the sidebar to view comprehensive details, manage members, configure security settings, and monitor real-time performance.")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
                    .lineSpacing(6)
                    .opacity(showingDetailAnimation ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.8).delay(0.7), value: showingDetailAnimation)
                
                // PREMIUM ACTION BUTTONS
                VStack(spacing: 16) {
                    Button(action: { showingCreateNetworkGroup = true }) {
                        HStack(spacing: 10) {
                            Image(systemName: "plus.diamond.fill")
                                .font(.system(size: 20, weight: .semibold))
                            
                            Text("Create Network Group")
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [Color.blue, Color.blue.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .cornerRadius(25)
                        .shadow(color: Color.blue.opacity(0.4), radius: 12, x: 0, y: 6)
                    }
                    .scaleEffect(showingDetailAnimation ? 1.0 : 0.8)
                    .opacity(showingDetailAnimation ? 1.0 : 0.0)
                    .animation(.spring(response: 0.8, dampingFraction: 0.6).delay(0.9), value: showingDetailAnimation)
                    
                    // SECONDARY ACTIONS
                    HStack(spacing: 20) {
                        Button(action: loadNetworkGroups) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 14, weight: .semibold))
                                
                                Text("Refresh")
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                            }
                            .foregroundColor(.blue)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(15)
                        }
                        
                        Button(action: {}) {
                            HStack(spacing: 6) {
                                Image(systemName: "questionmark.circle")
                                    .font(.system(size: 14, weight: .semibold))
                                
                                Text("Help")
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                            }
                            .foregroundColor(.gray)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(15)
                        }
                    }
                    .opacity(showingDetailAnimation ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.6).delay(1.1), value: showingDetailAnimation)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    Color(.systemGroupedBackground).opacity(0.8),
                    Color(.systemGroupedBackground)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
    
    // MARK: - iPhone Layout (UNCHANGED BUT IMPROVED)
    private var iPhoneLayout: some View {
        VStack(spacing: 0) {
            modernHeader
            
            if isLoading {
                loadingView
            } else if networkGroups.isEmpty {
                emptyStateView
            } else {
                modernListView
            }
        }
    }
    
    // MARK: - Modern Header
    private var modernHeader: some View {
        VStack(spacing: 16) {
            // Statistics Cards
            HStack(spacing: 12) {
                StatCard(
                    title: "Total",
                    value: "\(networkGroups.count)",
                    icon: "network",
                    color: .blue
                )
                
                StatCard(
                    title: "Active",
                    value: "\(networkGroups.filter { $0.isActive }.count)",
                    icon: "checkmark.circle.fill",
                    color: .green
                )
                
                StatCard(
                    title: "Inactive",
                    value: "\(networkGroups.filter { !$0.isActive }.count)",
                    icon: "xmark.circle.fill",
                    color: .orange
                )
            }
            .padding(.horizontal)
            
            // Search and Filters
            VStack(spacing: 8) {
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Search network groups...", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                    
                    if !searchText.isEmpty {
                        Button("Clear") {
                            searchText = ""
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal)
                
                // Filter Chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(NetworkGroupFilter.allCases, id: \.self) { filter in
                            NetworkGroupFilterChip(
                                title: filter.displayName,
                                icon: filter.icon,
                                isSelected: selectedFilter == filter
                            ) {
                                selectedFilter = filter
                            }
                        }
                        
                        // View Mode Toggle (iPad only)
                        if isIpad {
                            Divider()
                                .frame(height: 20)
                            
                            ViewModeToggle(viewMode: $viewMode)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(.vertical)
        .background(Color(.systemBackground))
        .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 1)
    }
    
    // MARK: - Modern Grid View (iPad)
    private var modernGridView: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 16) {
                ForEach(filteredNetworkGroups) { group in
                    ModernNetworkGroupCard(
                        networkGroup: group,
                        isSelected: selectedNetworkGroup?.id == group.id
                    ) {
                        selectedNetworkGroup = group
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Modern List View (iPhone)
    private var modernListView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(filteredNetworkGroups) { group in
                    if isEmbeddedInNavigationSplitView {
                        // When embedded, use tap gesture instead of NavigationLink
                        ModernNetworkGroupListCard(networkGroup: group)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                    selectedNetworkGroup = group
                                }
                            }
                    } else {
                        // Normal NavigationLink for standalone usage
                        NavigationLink(destination: NetworkGroupDetailView(
                            networkGroup: group,
                            organizationId: organizationId
                        ).environment(coordinator)) {
                            ModernNetworkGroupListCard(networkGroup: group)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Grid Columns
    private var gridColumns: [GridItem] {
        let columnCount = isIpad ? (viewMode == .grid ? 2 : 1) : 1
        return Array(repeating: GridItem(.flexible(), spacing: 16), count: columnCount)
    }
    
    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("Loading network groups...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
    
    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "network.slash")
                .font(.system(size: 64))
                .foregroundColor(.orange)
            
            VStack(spacing: 8) {
                Text("No Network Groups")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Create your first network group to securely connect your applications and services.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button(action: { showingCreateNetworkGroup = true }) {
                Label("Create Your First Network Group", systemImage: "plus")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
    
    // MARK: - Methods
    
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
                    
                    // Auto-select first group on iPad if none selected
                    if isIpad && selectedNetworkGroup == nil && !groups.isEmpty {
                        selectedNetworkGroup = groups.first
                    }
                }
            )
            .store(in: &cancellables)
    }
}

// MARK: - Supporting Views

/// Statistics card for header
struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.caption)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

/// Filter chip component
struct NetworkGroupFilterChip: View {
    let title: String
    let icon: String
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
            .background(isSelected ? Color.blue : Color(.systemGray6))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(16)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

/// View mode toggle for iPad
struct ViewModeToggle: View {
    @Binding var viewMode: ViewMode
    
    var body: some View {
        HStack(spacing: 4) {
            Button(action: { viewMode = .grid }) {
                Image(systemName: "grid")
                    .foregroundColor(viewMode == .grid ? .blue : .secondary)
            }
            
            Button(action: { viewMode = .list }) {
                Image(systemName: "list.bullet")
                    .foregroundColor(viewMode == .list ? .blue : .secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

/// Modern network group card for grid view
struct ModernNetworkGroupCard: View {
    let networkGroup: CCNetworkGroup
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with status
            HStack {
                // Status indicator
                Circle()
                    .fill(networkGroup.isActive ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                
                Text(networkGroup.isActive ? "Active" : "Inactive")
                    .font(.caption)
                    .foregroundColor(networkGroup.isActive ? .green : .orange)
                    .fontWeight(.medium)
                
                Spacer()
                
                // Region badge (compact)
                if let region = networkGroup.region {
                    Text(region.uppercased())
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(3)
                }
            }
            
            // Network group info
            VStack(alignment: .leading, spacing: 4) {
                Text(networkGroup.name)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                
                if let description = networkGroup.description, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                if let cidr = networkGroup.cidr {
                    HStack {
                        Image(systemName: "network")
                            .foregroundColor(.blue)
                            .font(.caption)
                        
                        Text(cidr)
                            .font(.caption)
                            .fontDesign(.monospaced)
                            .foregroundColor(Color.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Quick stats
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("0") // TODO: Get real member count
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    Text("Members")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("0") // TODO: Get real peer count
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    Text("Peers")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
        )
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .onTapGesture {
            onTap()
        }
    }
}

/// Modern network group card for list view
struct ModernNetworkGroupListCard: View {
    let networkGroup: CCNetworkGroup
    
    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            VStack {
                Circle()
                    .fill(networkGroup.isActive ? Color.green : Color.orange)
                    .frame(width: 12, height: 12)
                
                Spacer()
            }
            
            // Main content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(networkGroup.name)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    if let region = networkGroup.region {
                        Text(region.uppercased())
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                    }
                }
                
                if let description = networkGroup.description, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                HStack {
                    if let cidr = networkGroup.cidr {
                        HStack(spacing: 4) {
                            Image(systemName: "network")
                                .foregroundColor(.blue)
                                .font(.caption)
                            
                            Text(cidr)
                                .font(.caption)
                                .fontDesign(.monospaced)
                                .foregroundColor(Color.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Text(networkGroup.isActive ? "Active" : "Inactive")
                        .font(.caption)
                        .foregroundColor(networkGroup.isActive ? .green : .orange)
                        .fontWeight(.medium)
                }
            }
            
            // Chevron
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 1)
    }
}

// MARK: - Supporting Types

enum ViewMode: CaseIterable {
    case grid
    case list
    
    var icon: String {
        switch self {
        case .grid:
            return "grid"
        case .list:
            return "list.bullet"
        }
    }
}

enum NetworkGroupFilter: CaseIterable {
    case all
    case active
    case inactive
    case recent
    
    var displayName: String {
        switch self {
        case .all:
            return "All"
        case .active:
            return "Active"
        case .inactive:
            return "Inactive"
        case .recent:
            return "Recent"
        }
    }
    
    var icon: String {
        switch self {
        case .all:
            return "circle.grid.3x3"
        case .active:
            return "checkmark.circle"
        case .inactive:
            return "xmark.circle"
        case .recent:
            return "clock"
        }
    }
} 