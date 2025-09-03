import SwiftUI
import Combine

// MARK: - NetworkGroupsView
/// Revolutionary Network Groups management interface with interactive graph visualization
struct NetworkGroupsView: View {
    
    // MARK: - Environment
    @Environment(\.dismiss) private var dismiss
    @Environment(AppCoordinator.self) private var coordinator: AppCoordinator
    
    // MARK: - State
    @State private var networkGroups: [CCNetworkGroup] = []
    @State private var selectedNetworkGroup: CCNetworkGroup?
    @State private var networkGroupMembers: [CCNetworkGroupMember] = []
    @State private var networkGroupPeers: [CCNetworkGroupPeer] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingCreateNetworkGroup = false
    @State private var searchText = ""
    @State private var selectedOrganization: CCOrganization?
    @State private var cancellables = Set<AnyCancellable>()
    @State private var showing3DVisualization = false
    
    // MARK: - Graph Visualization State
    @State private var graphNodes: [GraphNode] = []
    @State private var graphConnections: [GraphConnection] = []
    @State private var selectedNode: GraphNode?
    @State private var isDraggingNode = false
    @State private var dragOffset: CGSize = .zero
    @State private var graphScale: CGFloat = 1.0
    @State private var graphOffset: CGSize = .zero
    
    // MARK: - Properties
    let organizationId: String
    
    // MARK: - Body
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header with search and actions
                headerView
                
                if isLoading {
                    loadingView
                } else if networkGroups.isEmpty {
                    emptyStateView
                } else {
                    // Main content with vertical layout
                    VStack(spacing: 0) {
                        // Top: Network Groups horizontal list
                        networkGroupsHorizontalList
                            .frame(height: 120)
                            .background(Color(.systemGroupedBackground))
                        
                        Divider()
                        
                        // Center: Interactive 2D graph visualization
                        networkGraphVisualizationView
                            .frame(maxHeight: .infinity)
                        
                        // Bottom: Selected node details (when applicable)
                        if selectedNode != nil {
                            Divider()
                            selectedNodeDetailsView
                                .frame(height: 200)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                }
            }
            .navigationTitle("🌐 Network Groups")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        // 3D Visualization Button
                        Button(action: {
                            showing3DVisualization = true
                        }) {
                            Image(systemName: "cube.transparent")
                                .foregroundColor(.purple)
                                .font(.title2)
                        }
                        .help("3D Network Topology")
                        
                        // Create Network Group Button
                        Button("Create Network Group") {
                            showingCreateNetworkGroup = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search network groups...")
            .onAppear {
                loadNetworkGroups()
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "")
            }
            .sheet(isPresented: $showingCreateNetworkGroup) {
                CreateNetworkGroupView(
                    organizationId: organizationId,
                    onNetworkGroupCreated: { newNetworkGroup in
                        networkGroups.append(newNetworkGroup)
                        selectedNetworkGroup = newNetworkGroup
                        loadNetworkGroupDetails(newNetworkGroup)
                    }
                )
                .environment(coordinator)
            }
            .sheet(isPresented: $showing3DVisualization) {
                NetworkGroups3DView(organizationId: organizationId)
                    .environment(coordinator)
            }
        }
    }
    
    // MARK: - Header View
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Network Groups Management")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Create secure private networks between applications, add-ons, and external services")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(spacing: 8) {
                Image(systemName: "cube.transparent")
                    .foregroundColor(.purple)
                Text("Click the cube for 3D topology view")
                    .font(.caption2)
                    .foregroundColor(.purple)
            }
        }
        .padding()
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
    }
    
    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "network.slash")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("No Network Groups")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Create your first network group to connect applications and services securely")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button("Create First Network Group") {
                showingCreateNetworkGroup = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Network Groups Horizontal List
    private var networkGroupsHorizontalList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Network Groups")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, 8)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(filteredNetworkGroups) { networkGroup in
                        NetworkGroupCard(
                            networkGroup: networkGroup,
                            isSelected: selectedNetworkGroup?.id == networkGroup.id
                        ) {
                            withAnimation(.spring()) {
                                selectedNetworkGroup = networkGroup
                                selectedNode = nil // Clear selected node when changing network group
                                loadNetworkGroupDetails(networkGroup)
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
        }
    }
    
    // MARK: - Network Group Card
    struct NetworkGroupCard: View {
        let networkGroup: CCNetworkGroup
        let isSelected: Bool
        let action: () -> Void
        
        var body: some View {
            Button(action: action) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Circle()
                            .fill(Color(networkGroup.statusColor))
                            .frame(width: 8, height: 8)
                        
                        Text(networkGroup.name)
                            .font(.subheadline)
                            .fontWeight(isSelected ? .semibold : .medium)
                            .lineLimit(1)
                    }
                    
                    if let description = networkGroup.description {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    
                    if let cidr = networkGroup.cidr {
                        Label(cidr, systemImage: "network")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(minWidth: 150)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isSelected ? Color.blue : Color(.secondarySystemGroupedBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                        )
                )
                .foregroundColor(isSelected ? .white : .primary)
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Network Graph Visualization View
    private var networkGraphVisualizationView: some View {
        VStack(spacing: 0) {
            // Graph header
            HStack {
                if let selectedGroup = selectedNetworkGroup {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedGroup.displayName)
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        if let description = selectedGroup.description {
                            Text(description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    Text("Select a Network Group")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if selectedNetworkGroup != nil {
                    // Graph controls
                    HStack(spacing: 12) {
                        Button(action: resetGraphView) {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(.secondary)
                        }
                        .help("Reset view")
                        
                        Button(action: zoomToFit) {
                            Image(systemName: "viewfinder")
                                .foregroundColor(.secondary)
                        }
                        .help("Zoom to fit")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .background(Color(.systemGroupedBackground))
            
            // Interactive graph canvas
            if selectedNetworkGroup != nil {
                InteractiveNetworkGraphView(
                    networkGroup: selectedNetworkGroup!,
                    members: networkGroupMembers,
                    peers: networkGroupPeers,
                    nodes: $graphNodes,
                    connections: $graphConnections,
                    selectedNode: $selectedNode,
                    scale: $graphScale,
                    offset: $graphOffset
                )
                .background(
                    LinearGradient(
                        colors: [Color(.systemBackground), Color.blue.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipped()
            } else {
                // Empty state
                ContentUnavailableView(
                    "Network Visualization",
                    systemImage: "network",
                    description: Text("Select a network group to view its interactive topology")
                )
            }
        }
    }
    
    // MARK: - Selected Node Details View
    private var selectedNodeDetailsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedNode?.title ?? "")
                        .font(.headline)
                    
                    HStack {
                        Image(systemName: selectedNode?.type.icon ?? "")
                            .foregroundColor(selectedNode?.type.color)
                        Text(nodeTypeDescription)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Button(action: {
                    withAnimation(.spring()) {
                        selectedNode = nil
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title2)
                }
            }
            
            if let subtitle = selectedNode?.subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // Node-specific details
            nodeSpecificDetails
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(radius: 5)
        )
        .padding()
    }
    
    private var nodeTypeDescription: String {
        switch selectedNode?.type {
        case .networkGroup:
            return "Network Group"
        case .application:
            return "Application"
        case .addon:
            return "Add-on"
        case .externalPeer:
            return "External Peer"
        case .internalPeer:
            return "Internal Peer"
        case .none:
            return ""
        }
    }
    
    private var nodeSpecificDetails: some View {
        Group {
            if let node = selectedNode {
                switch node.type {
                case .networkGroup:
                    if let networkGroup = selectedNetworkGroup {
                        VStack(alignment: .leading, spacing: 8) {
                            detailRow("Members", value: "\(networkGroupMembers.count)")
                            detailRow("Peers", value: "\(networkGroupPeers.count)")
                            if let region = networkGroup.region {
                                detailRow("Region", value: region.uppercased())
                            }
                            detailRow("Status", value: networkGroup.status ?? "Unknown", color: colorFromString(networkGroup.statusColor))
                        }
                    }
                    
                case .application, .addon:
                    if let member = networkGroupMembers.first(where: { $0.id == node.id }) {
                        VStack(alignment: .leading, spacing: 8) {
                            detailRow("Type", value: member.type.displayName)
                            if let ip = member.ipAddress {
                                detailRow("IP Address", value: ip)
                            }
                            detailRow("Status", value: member.status ?? "Unknown", color: colorFromString(member.statusColor))
                        }
                    }
                    
                case .externalPeer, .internalPeer:
                    if let peer = networkGroupPeers.first(where: { $0.id == node.id }) {
                        VStack(alignment: .leading, spacing: 8) {
                            detailRow("Type", value: peer.isExternal ? "External" : "Internal")
                            if let endpoint = peer.endpoint {
                                detailRow("Endpoint", value: endpoint)
                            }
                            detailRow("Status", value: peer.status ?? "Unknown", color: colorFromString(peer.statusColor))
                        }
                    }
                }
            }
        }
    }
    
    private func detailRow(_ label: String, value: String, color: Color? = nil) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            if let color = color {
                HStack(spacing: 4) {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                    Text(value)
                        .font(.caption)
                        .fontWeight(.medium)
                }
            } else {
                Text(value)
                    .font(.caption)
                    .fontWeight(.medium)
            }
        }
    }
    
    // MARK: - Computed Properties
    private var filteredNetworkGroups: [CCNetworkGroup] {
        if searchText.isEmpty {
            return networkGroups
        }
        return networkGroups.filter { networkGroup in
            networkGroup.name.localizedCaseInsensitiveContains(searchText) ||
            networkGroup.description?.localizedCaseInsensitiveContains(searchText) == true
        }
    }
    
    // MARK: - Methods
    private func loadNetworkGroups() {
        isLoading = true
        errorMessage = nil
        
        coordinator.cleverCloudSDK.getNetworkGroups(for: organizationId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    isLoading = false
                    if case .failure(let error) = completion {
                        errorMessage = error.localizedDescription
                    }
                },
                receiveValue: { groups in
                    networkGroups = groups
                    
                    // Auto-select first network group if available
                    if !groups.isEmpty && selectedNetworkGroup == nil {
                        selectedNetworkGroup = groups.first
                        loadNetworkGroupDetails(groups.first!)
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    private func loadNetworkGroupDetails(_ networkGroup: CCNetworkGroup) {
        coordinator.cleverCloudSDK.getCompleteNetworkGroupData(
            organizationId: organizationId,
            networkGroupId: networkGroup.id
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    errorMessage = error.localizedDescription
                }
            },
            receiveValue: { (group, members, peers) in
                networkGroupMembers = members
                networkGroupPeers = peers
                updateGraphVisualization()
            }
        )
        .store(in: &cancellables)
    }
    
    private func updateGraphVisualization() {
        // Convert network group data to graph nodes and connections
        var nodes: [GraphNode] = []
        var connections: [GraphConnection] = []
        
        // Add network group center node
        if let networkGroup = selectedNetworkGroup {
            nodes.append(GraphNode(
                id: networkGroup.id,
                type: .networkGroup,
                title: networkGroup.displayName,
                subtitle: networkGroup.description,
                status: networkGroup.status ?? "unknown",
                position: CGPoint(x: 0, y: 0) // Center position
            ))
        }
        
        // Add member nodes
        for member in networkGroupMembers {
            let randomX = Double.random(in: -200...200)
            let randomY = Double.random(in: -200...200)
            
            let node = GraphNode(
                id: member.id,
                type: member.type == .application ? .application : .addon,
                title: member.name,
                subtitle: member.ipAddress,
                status: member.status ?? "unknown",
                position: CGPoint(
                    x: randomX.isNaN ? 0 : randomX,
                    y: randomY.isNaN ? 0 : randomY
                )
            )
            nodes.append(node)
            
            // Connect to network group
            if let networkGroup = selectedNetworkGroup {
                connections.append(GraphConnection(
                    from: networkGroup.id,
                    to: member.id,
                    type: .membership
                ))
            }
        }
        
        // Add peer nodes
        for peer in networkGroupPeers {
            let randomX = Double.random(in: -300...300)
            let randomY = Double.random(in: -300...300)
            
            let node = GraphNode(
                id: peer.id,
                type: peer.isExternal ? .externalPeer : .internalPeer,
                title: peer.name,
                subtitle: peer.endpoint,
                status: peer.status ?? "unknown",
                position: CGPoint(
                    x: randomX.isNaN ? 0 : randomX,
                    y: randomY.isNaN ? 0 : randomY
                )
            )
            nodes.append(node)
            
            // Connect to network group
            if let networkGroup = selectedNetworkGroup {
                connections.append(GraphConnection(
                    from: networkGroup.id,
                    to: peer.id,
                    type: .peering
                ))
            }
        }
        
        graphNodes = nodes
        graphConnections = connections
    }
    
    private func resetGraphView() {
        graphScale = 1.0
        graphOffset = .zero
        updateGraphVisualization()
    }
    
    private func zoomToFit() {
        // Calculate bounds of all nodes
        guard !graphNodes.isEmpty else { return }
        
        let minX = graphNodes.map(\.position.x).min() ?? 0
        let maxX = graphNodes.map(\.position.x).max() ?? 0
        let minY = graphNodes.map(\.position.y).min() ?? 0
        let maxY = graphNodes.map(\.position.y).max() ?? 0
        
        let width = maxX - minX
        let height = maxY - minY
        
        // Calculate scale to fit
        let maxDimension = max(width, height)
        if maxDimension > 0 {
            graphScale = min(400 / maxDimension, 2.0)
        }
        
        // Center the graph
        graphOffset = CGSize(
            width: -(minX + width / 2) * graphScale,
            height: -(minY + height / 2) * graphScale
        )
    }
    
    private func exportGraph() {
        // TODO: Implement graph export functionality
        print("Export graph functionality to be implemented")
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
            return .gray
        }
    }
}

// MARK: - Graph Models
struct GraphNode: Identifiable, Equatable {
    let id: String
    let type: NodeType
    let title: String
    let subtitle: String?
    let status: String
    var position: CGPoint
    
    enum NodeType {
        case networkGroup
        case application
        case addon
        case externalPeer
        case internalPeer
        
        var color: Color {
            switch self {
            case .networkGroup:
                return .blue
            case .application:
                return .green
            case .addon:
                return .orange
            case .externalPeer:
                return .red
            case .internalPeer:
                return .purple
            }
        }
        
        var icon: String {
            switch self {
            case .networkGroup:
                return "network"
            case .application:
                return "app.badge"
            case .addon:
                return "gear.badge"
            case .externalPeer:
                return "globe"
            case .internalPeer:
                return "house"
            }
        }
        
        var size: CGFloat {
            switch self {
            case .networkGroup:
                return 60
            case .application, .addon:
                return 45
            case .externalPeer, .internalPeer:
                return 40
            }
        }
    }
}

struct GraphConnection: Identifiable {
    let id = UUID()
    let from: String
    let to: String
    let type: ConnectionType
    
    enum ConnectionType {
        case membership
        case peering
        
        var color: Color {
            switch self {
            case .membership:
                return .blue
            case .peering:
                return .orange
            }
        }
        
        var strokeWidth: CGFloat {
            switch self {
            case .membership:
                return 2.0
            case .peering:
                return 1.5
            }
        }
    }
}

// MARK: - Interactive Network Graph View (Placeholder)
struct InteractiveNetworkGraphView: View {
    let networkGroup: CCNetworkGroup
    let members: [CCNetworkGroupMember]
    let peers: [CCNetworkGroupPeer]
    
    @Binding var nodes: [GraphNode]
    @Binding var connections: [GraphConnection]
    @Binding var selectedNode: GraphNode?
    @Binding var scale: CGFloat
    @Binding var offset: CGSize
    
    @State private var draggedNode: GraphNode?
    @State private var dragOffset: CGSize = .zero
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Graph content
                ForEach(connections) { connection in
                    drawConnection(connection, in: geometry.size)
                }
                
                ForEach(nodes) { node in
                    drawNode(node)
                        .position(
                            x: geometry.size.width / 2 + (node.position.x + (draggedNode?.id == node.id ? dragOffset.width : 0)) * scale + offset.width,
                            y: geometry.size.height / 2 + (node.position.y + (draggedNode?.id == node.id ? dragOffset.height : 0)) * scale + offset.height
                        )
                        .scaleEffect(scale)
                        .scaleEffect(selectedNode?.id == node.id ? 1.1 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedNode?.id)
                        .zIndex(selectedNode?.id == node.id ? 2 : (node.type == .networkGroup ? 1 : 0))
                }
            }
        }
        .background(Color.clear)
        .gesture(
            MagnificationGesture()
                .onChanged { value in
                    scale = max(0.5, min(3.0, value))
                }
                .simultaneously(with:
                    DragGesture()
                        .onChanged { value in
                            if draggedNode == nil {
                                offset = CGSize(
                                    width: value.translation.width,
                                    height: value.translation.height
                                )
                            }
                        }
                )
        )
    }
    
    private func drawNode(_ node: GraphNode) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(node.type.color.opacity(0.2))
                    .overlay(
                        Circle()
                            .stroke(node.type.color, lineWidth: selectedNode?.id == node.id ? 3 : 2)
                    )
                    .frame(width: node.type.size, height: node.type.size)
                    .shadow(color: selectedNode?.id == node.id ? node.type.color.opacity(0.4) : Color.black.opacity(0.1), 
                           radius: selectedNode?.id == node.id ? 8 : 2)
                
                Image(systemName: node.type.icon)
                    .font(.system(size: node.type.size * 0.4, weight: .medium))
                    .foregroundColor(node.type.color)
            }
            
            Text(node.title)
                .font(.caption2)
                .fontWeight(selectedNode?.id == node.id ? .semibold : .medium)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 80)
                .foregroundColor(selectedNode?.id == node.id ? node.type.color : .primary)
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(UIColor.systemBackground).opacity(0.9))
                .shadow(color: selectedNode?.id == node.id ? node.type.color.opacity(0.2) : Color.black.opacity(0.05), 
                       radius: selectedNode?.id == node.id ? 8 : 2)
        )
        .padding(4)
        .onTapGesture {
            withAnimation(.spring()) {
                selectedNode = selectedNode?.id == node.id ? nil : node
            }
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    if draggedNode == nil || draggedNode?.id == node.id {
                        draggedNode = node
                        dragOffset = CGSize(
                            width: value.translation.width / scale,
                            height: value.translation.height / scale
                        )
                    }
                }
                .onEnded { _ in
                    if let index = nodes.firstIndex(where: { $0.id == node.id }) {
                        nodes[index].position.x += dragOffset.width
                        nodes[index].position.y += dragOffset.height
                    }
                    draggedNode = nil
                    dragOffset = .zero
                }
        )
    }
    
    private func drawConnection(_ connection: GraphConnection, in size: CGSize) -> some View {
        // Find nodes for connection
        guard let fromNode = nodes.first(where: { $0.id == connection.from }),
              let toNode = nodes.first(where: { $0.id == connection.to }) else {
            return AnyView(EmptyView())
        }
        
        let fromX = fromNode.position.x + (draggedNode?.id == fromNode.id ? dragOffset.width : 0)
        let fromY = fromNode.position.y + (draggedNode?.id == fromNode.id ? dragOffset.height : 0)
        let toX = toNode.position.x + (draggedNode?.id == toNode.id ? dragOffset.width : 0)
        let toY = toNode.position.y + (draggedNode?.id == toNode.id ? dragOffset.height : 0)
        
        let fromPoint = CGPoint(
            x: size.width / 2 + fromX * scale + offset.width,
            y: size.height / 2 + fromY * scale + offset.height
        )
        
        let toPoint = CGPoint(
            x: size.width / 2 + toX * scale + offset.width,
            y: size.height / 2 + toY * scale + offset.height
        )
        
        let isHighlighted = selectedNode?.id == fromNode.id || selectedNode?.id == toNode.id
        
        return AnyView(
            Path { path in
                path.move(to: fromPoint)
                path.addLine(to: toPoint)
            }
            .stroke(
                connection.type.color.opacity(isHighlighted ? 0.8 : 0.3),
                style: StrokeStyle(
                    lineWidth: isHighlighted ? 3 : connection.type.strokeWidth,
                    lineCap: .round,
                    dash: connection.type == .peering ? [5, 5] : []
                )
            )
            .animation(.easeInOut(duration: 0.3), value: isHighlighted)
        )
    }
}

// MARK: - The CreateNetworkGroupView is now imported from CreateNetworkGroupView.swift
// This placeholder has been replaced with the complete implementation

// MARK: - Preview
#Preview {
    NetworkGroupsView(organizationId: "org_example")
        .environment(AppCoordinator())
} 