//
//  NetworkGroupDetailView.swift
//  test0
//
//  Created by Assistant on 18/06/2025.
//

import SwiftUI
import Combine

struct NetworkGroupDetailView: View {
    let networkGroup: CCNetworkGroup
    let organizationId: String
    
    // MARK: - Environment
    @Environment(\.dismiss) private var dismiss
    @Environment(AppCoordinator.self) private var coordinator: AppCoordinator
    
    // MARK: - State
    @State private var members: [CCNetworkGroupMember] = []
    @State private var peers: [CCNetworkGroupPeer] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingAddPeer = false
    @State private var showingAddMember = false
    @State private var selectedTab = 0
    @State private var showingWireGuardConfig = false
    @State private var showingExportSheet = false
    @State private var showingImportSheet = false
    @State private var showing3DVisualization = false
    @State private var showingDeleteSheet = false
    @State private var showingBulkOperations = false
    @State private var selectedBulkOperation: BulkOperationType?
    
    // WireGuard configuration state
    @State private var wireGuardConfig: String = ""
    @State private var selectedPeerId: String?
    @State private var selectedPeerForConfig: CCNetworkGroupPeer?
    @State private var cancellables = Set<AnyCancellable>()
    
    // Graph visualization state
    @State private var selectedNode: NetworkNode?
    @State private var dragOffset = CGSize.zero
    @State private var scale: CGFloat = 1.0
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header Information
                    networkGroupInfoCard
                    
                    // Interactive Graph Visualization
                    networkGraphCard
                    
                    // Members Management
                    membersCard
                    
                    // Peers Management
                    peersCard
                }
                .padding()
            }
        }
        .navigationTitle(networkGroup.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    // 3D Visualization Button
                    Button(action: {
                        showing3DVisualization = true
                    }) {
                        Image(systemName: "cube.transparent")
                            .foregroundColor(.purple)
                    }
                    
                    // Main Menu
                    Menu {
                        // Network Management
                        Section("Network Management") {
                            Button(action: { showingAddMember = true }) {
                                Label("Add Member", systemImage: "plus.circle")
                            }
                            Button(action: { showingAddPeer = true }) {
                                Label("Add External Peer", systemImage: "network.badge.shield.half.filled")
                            }
                        }
                        
                        // Bulk Operations
                        Section("Bulk Operations") {
                            Button(action: { 
                                selectedBulkOperation = .removeMembers
                                showingBulkOperations = true
                            }) {
                                Label("Remove Multiple Members", systemImage: "person.3.fill")
                            }
                            .foregroundColor(.red)
                            
                            Button(action: { 
                                selectedBulkOperation = .removePeers
                                showingBulkOperations = true
                            }) {
                                Label("Remove Multiple Peers", systemImage: "network.badge.shield.half.filled")
                            }
                            .foregroundColor(.red)
                        }
                        
                        // WireGuard Configuration
                        Section("WireGuard Configuration") {
                            Button(action: { exportWireGuardConfigs() }) {
                                Label("Export All Configurations", systemImage: "square.and.arrow.up")
                            }
                            Button(action: { showingImportSheet = true }) {
                                Label("Import Configuration", systemImage: "square.and.arrow.down")
                            }
                        }
                        
                        Divider()
                        
                        Button(action: { loadNetworkGroupDetails() }) {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        
                        Divider()
                        
                        Button(role: .destructive, action: { showingDeleteSheet = true }) {
                            Label("Delete Network Group", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .onAppear {
            loadNetworkGroupDetails()
        }
        .sheet(isPresented: $showing3DVisualization) {
            NetworkGroups3DView(organizationId: organizationId)
                .environment(coordinator)
        }
        .sheet(isPresented: $showingExportSheet) {
            WireGuardExportView(
                networkGroup: networkGroup,
                members: members,
                peers: peers,
                organizationId: organizationId
            )
            .environment(coordinator)
        }
        .sheet(isPresented: $showingImportSheet) {
            WireGuardImportView(
                networkGroup: networkGroup,
                organizationId: organizationId,
                onImportComplete: { newPeer in
                    // Refresh peers after import
                    loadNetworkGroupDetails()
                }
            )
            .environment(coordinator)
        }
        .sheet(isPresented: $showingDeleteSheet) {
            DeleteNetworkGroupView(
                organizationId: organizationId,
                networkGroup: networkGroup,
                onNetworkGroupDeleted: {
                    // Return to network groups list after deletion
                    dismiss()
                }
            )
            .environment(coordinator)
        }
        .sheet(isPresented: $showingAddMember) {
            AddMemberToNetworkGroupView(
                networkGroup: networkGroup,
                organizationId: organizationId,
                onMemberAdded: { newMember in
                    // Add new member to local array
                    members.append(newMember)
                    print("✅ Successfully added member: \(newMember.name)")
                }
            )
            .environment(coordinator)
        }
        .sheet(isPresented: $showingAddPeer) {
            AddExternalPeerView(
                networkGroup: networkGroup,
                organizationId: organizationId,
                onPeerAdded: { newPeer in
                    // Add new peer to local array
                    peers.append(newPeer)
                    print("✅ Successfully added external peer: \(newPeer.name)")
                }
            )
            .environment(coordinator)
        }
        .sheet(isPresented: $showingWireGuardConfig) {
            if let selectedPeer = selectedPeerForConfig {
                WireGuardConfigurationView(
                    networkGroup: networkGroup,
                    peer: selectedPeer,
                    organizationId: organizationId
                )
                .environment(coordinator)
            }
        }
        .sheet(isPresented: $showingBulkOperations) {
            if let operation = selectedBulkOperation {
                BulkOperationsView(
                    networkGroup: networkGroup,
                    organizationId: organizationId,
                    operationType: operation,
                    onOperationCompleted: { removedItemIds in
                        // Refresh the data after bulk operations
                        loadNetworkGroupDetails()
                        print("✅ Bulk operation completed. Removed \(removedItemIds.count) items")
                    }
                )
                .environment(coordinator)
            }
        }
    }
    
    // MARK: - Network Group Info Card
    
    private var networkGroupInfoCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "network")
                    .foregroundColor(.purple)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(networkGroup.name)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text(networkGroup.description ?? "No description")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                        Text("Active")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text("ID: \(networkGroup.id)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            // Statistics
            HStack(spacing: 20) {
                StatisticView(title: "Members", value: "\(members.count)", color: .blue)
                StatisticView(title: "Peers", value: "\(peers.count)", color: .orange)
                StatisticView(title: "Status", value: "Connected", color: .green)
            }
            
            // Danger Zone
            HStack {
                Spacer()
                Button(action: { showingDeleteSheet = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "trash")
                        Text("Delete Network Group")
                    }
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.red)
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    // MARK: - Network Graph Card
    
    private var networkGraphCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Network Topology")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Export") {
                    // TODO: Export functionality
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            
            // Interactive Graph
            GeometryReader { geometry in
                ZStack {
                    // Background
                    Rectangle()
                        .fill(Color(.systemGray6))
                        .cornerRadius(8)
                    
                    // Network nodes and connections
                    networkGraphView(in: geometry.size)
                }
            }
            .frame(height: 300)
            .scaleEffect(scale)
            .offset(dragOffset)
            .gesture(
                SimultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = max(0.5, min(2.0, value))
                        },
                    DragGesture()
                        .onChanged { value in
                            dragOffset = value.translation
                        }
                        .onEnded { _ in
                            withAnimation {
                                dragOffset = .zero
                            }
                        }
                )
            )
            
            // Graph controls
            HStack {
                Button("Reset View") {
                    withAnimation {
                        scale = 1.0
                        dragOffset = .zero
                    }
                }
                .font(.caption)
                
                Spacer()
                
                Text("Pinch to zoom • Drag to pan")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    // MARK: - Members Card
    
    private var membersCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Members")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Add Member") {
                    showingAddMember = true
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            
            if members.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.3")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    
                    Text("No Members")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("Add applications or add-ons to this network group")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 24)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(members, id: \.id) { member in
                        memberRow(member)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    // MARK: - Peers Card
    
    private var peersCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("External Peers")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Add Peer") {
                    showingAddPeer = true
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            
            if peers.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "network.badge.shield.half.filled")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    
                    Text("No External Peers")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("Add external connections to expand your network")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 24)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(peers, id: \.id) { peer in
                        peerRow(peer)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    // MARK: - Helper Views
    
    private func networkGraphView(in size: CGSize) -> some View {
        // Simplified graph view to fix compilation time
        VStack {
            Text("Network Graph")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(spacing: 20) {
                // Central node
                VStack {
                    Circle()
                        .fill(Color.purple.opacity(0.3))
                        .frame(width: 60, height: 60)
                        .overlay(
                            Image(systemName: "network")
                                .foregroundColor(.purple)
                                .font(.title2)
                        )
                    Text(networkGroup.name)
                        .font(.caption)
                        .lineLimit(1)
                }
                
                // Members
                if !members.isEmpty {
                    ForEach(members.prefix(3), id: \.id) { member in
                        VStack {
                            Circle()
                                .fill((member.type == .application ? Color.green : Color.orange).opacity(0.3))
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Image(systemName: member.type == .application ? "app.fill" : "puzzlepiece.extension.fill")
                                        .foregroundColor(member.type == .application ? .green : .orange)
                                )
                            Text(member.name)
                                .font(.caption2)
                                .lineLimit(1)
                        }
                    }
                    
                    if members.count > 3 {
                        Text("+\(members.count - 3)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func memberRow(_ member: CCNetworkGroupMember) -> some View {
        HStack {
            Image(systemName: member.type == .application ? "app.fill" : "puzzlepiece.extension.fill")
                .foregroundColor(member.type == .application ? .green : .orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(member.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(member.type.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("Remove") {
                removeMember(member)
            }
            .font(.caption)
            .foregroundColor(.red)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
    
    private func peerRow(_ peer: CCNetworkGroupPeer) -> some View {
        HStack {
            Image(systemName: "network.badge.shield.half.filled")
                .foregroundColor(.red)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(peer.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("External Peer")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                Button("WireGuard") {
                    selectedPeerForConfig = peer
                    showingWireGuardConfig = true
                }
                .font(.caption)
                .foregroundColor(.blue)
                
                Button("Remove") {
                    removePeer(peer)
                }
                .font(.caption)
                .foregroundColor(.red)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
    
    // MARK: - Methods
    
    private func loadNetworkGroupDetails() {
        isLoading = true
        errorMessage = nil
        
        // Load members
        coordinator.cleverCloudSDK.networkGroups.getNetworkGroupMembers(
            organizationId: organizationId,
            networkGroupId: networkGroup.id
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    errorMessage = "Failed to load members: \(error.localizedDescription)"
                }
            },
            receiveValue: { loadedMembers in
                members = loadedMembers
                print("✅ Loaded \(loadedMembers.count) members for network group \(networkGroup.name)")
            }
        )
        .store(in: &cancellables)
        
        // Load peers
        coordinator.cleverCloudSDK.networkGroups.getNetworkGroupPeers(
            organizationId: organizationId,
            networkGroupId: networkGroup.id
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { completion in
                isLoading = false
                if case .failure(let error) = completion {
                    errorMessage = "Failed to load peers: \(error.localizedDescription)"
                }
            },
            receiveValue: { loadedPeers in
                peers = loadedPeers
                print("✅ Loaded \(loadedPeers.count) peers for network group \(networkGroup.name)")
            }
        )
        .store(in: &cancellables)
    }
    
    private func removeMember(_ member: CCNetworkGroupMember) {
        print("🗑️ Removing member: \(member.name)")
        
        coordinator.cleverCloudSDK.networkGroups.removeNetworkGroupMember(
            organizationId: organizationId,
            networkGroupId: networkGroup.id,
            memberId: member.resourceId
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    errorMessage = "Failed to remove member: \(error.localizedDescription)"
                }
            },
            receiveValue: { _ in
                // Remove member from local array
                members.removeAll { $0.id == member.id }
                print("✅ Successfully removed member: \(member.name)")
            }
        )
        .store(in: &cancellables)
    }
    
    private func removePeer(_ peer: CCNetworkGroupPeer) {
        print("🗑️ Removing peer: \(peer.name)")
        
        if peer.isExternal {
            // Remove external peer
            coordinator.cleverCloudSDK.networkGroups.removeNetworkGroupExternalPeer(
                organizationId: organizationId,
                networkGroupId: networkGroup.id,
                peerId: peer.id
            )
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        errorMessage = "Failed to remove external peer: \(error.localizedDescription)"
                    }
                },
                receiveValue: { _ in
                    // Remove peer from local array
                    peers.removeAll { $0.id == peer.id }
                    print("✅ Successfully removed external peer: \(peer.name)")
                }
            )
            .store(in: &cancellables)
        } else {
            // Remove internal peer
            coordinator.cleverCloudSDK.networkGroups.removeNetworkGroupPeer(
                organizationId: organizationId,
                networkGroupId: networkGroup.id,
                peerId: peer.id
            )
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        errorMessage = "Failed to remove peer: \(error.localizedDescription)"
                    }
                },
                receiveValue: { _ in
                    // Remove peer from local array
                    peers.removeAll { $0.id == peer.id }
                    print("✅ Successfully removed peer: \(peer.name)")
                }
            )
            .store(in: &cancellables)
        }
    }
    
    private func exportWireGuardConfigs() {
        showingExportSheet = true
    }
}

// MARK: - Supporting Types

struct NetworkNode {
    let id: String
    let name: String
    let type: NodeType
    let position: CGPoint
    
    enum NodeType {
        case networkGroup
        case application
        case addon
        case peer
        
        var color: Color {
            switch self {
            case .networkGroup: return .purple
            case .application: return .green
            case .addon: return .orange
            case .peer: return .red
            }
        }
        
        var icon: String {
            switch self {
            case .networkGroup: return "network"
            case .application: return "app.fill"
            case .addon: return "puzzlepiece.extension.fill"
            case .peer: return "network.badge.shield.half.filled"
            }
        }
    }
}

struct NetworkNodeView: View {
    let node: NetworkNode
    let isSelected: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(node.type.color.opacity(0.2))
                    .frame(width: 40, height: 40)
                
                Circle()
                    .stroke(node.type.color, lineWidth: isSelected ? 3 : 2)
                    .frame(width: 40, height: 40)
                
                Image(systemName: node.type.icon)
                    .foregroundColor(node.type.color)
                    .font(.system(size: 16, weight: .medium))
            }
            
            Text(node.name)
                .font(.caption2)
                .foregroundColor(.primary)
                .lineLimit(1)
                .frame(maxWidth: 60)
        }
        .position(node.position)
    }
}

struct StatisticView: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Preview

#Preview {
    NetworkGroupDetailView(
        networkGroup: CCNetworkGroup.example(),
        organizationId: "org_example"
    )
    .environment(AppCoordinator())
} 