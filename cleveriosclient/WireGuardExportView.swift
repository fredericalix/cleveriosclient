import SwiftUI
import Combine
import UniformTypeIdentifiers

// MARK: - WireGuardExportView
/// View for exporting WireGuard configurations for network group members and peers
struct WireGuardExportView: View {
    
    // MARK: - Environment
    @Environment(\.dismiss) private var dismiss
    @Environment(AppCoordinator.self) private var coordinator
    
    // MARK: - Properties
    let networkGroup: CCNetworkGroup
    let members: [CCNetworkGroupMember]
    let peers: [CCNetworkGroupPeer]
    let organizationId: String
    
    // MARK: - State
    @State private var selectedItems: Set<String> = []
    @State private var isExporting = false
    @State private var exportProgress: Double = 0
    @State private var exportedConfigs: [ExportedConfig] = []
    @State private var showingShareSheet = false
    @State private var errorMessage: String?
    @State private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Body
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                headerView
                
                // Selection List
                ScrollView {
                    VStack(spacing: 16) {
                        // Members Section
                        if !members.isEmpty {
                            sectionView(
                                title: "Applications & Add-ons",
                                items: members.map { member in
                                    SelectableItem(
                                        id: member.id,
                                        name: member.name,
                                        subtitle: member.ipAddress ?? "No IP",
                                        type: member.type == .application ? .application : .addon
                                    )
                                }
                            )
                        }
                        
                        // Peers Section
                        if !peers.isEmpty {
                            sectionView(
                                title: "External Peers",
                                items: peers.map { peer in
                                    SelectableItem(
                                        id: peer.id,
                                        name: peer.name,
                                        subtitle: peer.endpoint ?? "No endpoint",
                                        type: .peer
                                    )
                                }
                            )
                        }
                    }
                    .padding()
                }
                
                // Export Button
                exportButton
            }
            .navigationTitle("Export WireGuard Configs")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(selectedItems.isEmpty ? "Select All" : "Deselect All") {
                        if selectedItems.isEmpty {
                            selectAll()
                        } else {
                            selectedItems.removeAll()
                        }
                    }
                }
            }
            .alert("Export Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "")
            }
            .sheet(isPresented: $showingShareSheet) {
                ShareSheet(items: exportedConfigs.map { $0.url })
            }
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "lock.shield.fill")
                    .font(.title2)
                    .foregroundColor(.green)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("WireGuard Configuration Export")
                        .font(.headline)
                    Text("Select items to export their VPN configurations")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            if isExporting {
                VStack(spacing: 8) {
                    ProgressView(value: exportProgress)
                        .progressViewStyle(LinearProgressViewStyle())
                    
                    Text("Exporting \(Int(exportProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
    }
    
    // MARK: - Section View
    
    private func sectionView(title: String, items: [SelectableItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                ForEach(items) { item in
                    itemRow(item)
                }
            }
        }
    }
    
    private func itemRow(_ item: SelectableItem) -> some View {
        HStack {
            // Selection checkbox
            Image(systemName: selectedItems.contains(item.id) ? "checkmark.square.fill" : "square")
                .foregroundColor(selectedItems.contains(item.id) ? .blue : .secondary)
                .font(.title2)
            
            // Icon
            Image(systemName: item.type.icon)
                .foregroundColor(item.type.color)
                .font(.title2)
            
            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    selectedItems.contains(item.id) ? Color.blue : Color.clear,
                    lineWidth: 2
                )
        )
        .onTapGesture {
            toggleSelection(item.id)
        }
    }
    
    // MARK: - Export Button
    
    private var exportButton: some View {
        Button(action: exportSelectedConfigs) {
            HStack {
                Image(systemName: "square.and.arrow.up")
                Text("Export \(selectedItems.count) Configuration\(selectedItems.count == 1 ? "" : "s")")
                    .fontWeight(.medium)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                selectedItems.isEmpty ? Color.gray : Color.blue
            )
            .cornerRadius(12)
        }
        .disabled(selectedItems.isEmpty || isExporting)
        .padding()
    }
    
    // MARK: - Methods
    
    private func toggleSelection(_ id: String) {
        if selectedItems.contains(id) {
            selectedItems.remove(id)
        } else {
            selectedItems.insert(id)
        }
    }
    
    private func selectAll() {
        selectedItems = Set(members.map(\.id) + peers.map(\.id))
    }
    
    private func exportSelectedConfigs() {
        guard !selectedItems.isEmpty else { return }
        
        isExporting = true
        exportProgress = 0
        exportedConfigs = []
        
        let totalItems = Double(selectedItems.count)
        var processedItems = 0.0
        
        // Process each selected item
        for (index, itemId) in selectedItems.enumerated() {
            // Check if it's a member or peer
            if let member = members.first(where: { $0.id == itemId }) {
                exportMemberConfig(member) { config in
                    if let config = config {
                        exportedConfigs.append(config)
                    }
                    processedItems += 1
                    exportProgress = processedItems / totalItems
                    
                    if processedItems == totalItems {
                        finishExport()
                    }
                }
            } else if let peer = peers.first(where: { $0.id == itemId }) {
                exportPeerConfig(peer) { config in
                    if let config = config {
                        exportedConfigs.append(config)
                    }
                    processedItems += 1
                    exportProgress = processedItems / totalItems
                    
                    if processedItems == totalItems {
                        finishExport()
                    }
                }
            }
        }
    }
    
    private func exportMemberConfig(_ member: CCNetworkGroupMember, completion: @escaping (ExportedConfig?) -> Void) {
        // Simulate API call to get WireGuard config
        coordinator.cleverCloudSDK.networkGroups.getWireGuardConfiguration(
            organizationId: organizationId,
            networkGroupId: networkGroup.id,
            peerId: member.resourceId
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { result in
                if case .failure(let error) = result {
                    print("❌ Failed to export config for \(member.name): \(error)")
                    completion(nil)
                }
            },
            receiveValue: { config in
                // Create config file
                let configContent = generateWireGuardConfig(for: member, config: config)
                let fileName = "\(member.name.replacingOccurrences(of: " ", with: "_")).conf"
                
                if let url = saveConfigToFile(content: configContent, fileName: fileName) {
                    completion(ExportedConfig(
                        id: member.id,
                        name: member.name,
                        fileName: fileName,
                        url: url
                    ))
                } else {
                    completion(nil)
                }
            }
        )
        .store(in: &cancellables)
    }
    
    private func exportPeerConfig(_ peer: CCNetworkGroupPeer, completion: @escaping (ExportedConfig?) -> Void) {
        // For external peers, we generate a template config
        let configContent = generatePeerConfigTemplate(for: peer)
        let fileName = "\(peer.name.replacingOccurrences(of: " ", with: "_")).conf"
        
        if let url = saveConfigToFile(content: configContent, fileName: fileName) {
            completion(ExportedConfig(
                id: peer.id,
                name: peer.name,
                fileName: fileName,
                url: url
            ))
        } else {
            completion(nil)
        }
    }
    
    private func generateWireGuardConfig(for member: CCNetworkGroupMember, config: CCWireGuardConfiguration) -> String {
        var content = "[Interface]\n"
        content += "# Network Group: \(networkGroup.name)\n"
        content += "# Member: \(member.name)\n"
        content += "# Generated: \(Date().formatted())\n\n"
        
        content += "PrivateKey = \(config.interface.privateKey)\n"
        content += "Address = \(config.interface.address)\n"
        
        if let dns = config.interface.dns, !dns.isEmpty {
            content += "DNS = \(dns.joined(separator: ", "))\n"
        }
        
        content += "\n"
        
        // Add peers
        for peer in config.peers {
            content += "[Peer]\n"
            content += "PublicKey = \(peer.publicKey)\n"
            content += "AllowedIPs = \(peer.allowedIPs)\n"
            
            if let endpoint = peer.endpoint {
                content += "Endpoint = \(endpoint)\n"
            }
            
            if let keepalive = peer.persistentKeepalive {
                content += "PersistentKeepalive = \(keepalive)\n"
            }
            
            content += "\n"
        }
        
        return content
    }
    
    private func generatePeerConfigTemplate(for peer: CCNetworkGroupPeer) -> String {
        var content = "[Interface]\n"
        content += "# Network Group: \(networkGroup.name)\n"
        content += "# External Peer: \(peer.name)\n"
        content += "# Generated: \(Date().formatted())\n\n"
        
        content += "# Replace with your private key\n"
        content += "PrivateKey = YOUR_PRIVATE_KEY_HERE\n"
        content += "# Configure your IP address in the network\n"
        content += "Address = 10.0.0.X/24\n"
        content += "# Optional: DNS servers\n"
        content += "# DNS = 1.1.1.1, 8.8.8.8\n\n"
        
        content += "[Peer]\n"
        content += "# Clever Cloud Network Group endpoint\n"
        
        if let publicKey = peer.publicKey {
            content += "PublicKey = \(publicKey)\n"
        } else {
            content += "# Request public key from administrator\n"
            content += "PublicKey = NETWORK_GROUP_PUBLIC_KEY\n"
        }
        
        if let allowedIps = peer.allowedIps {
            content += "AllowedIPs = \(allowedIps.joined(separator: ", "))\n"
        } else {
            content += "AllowedIPs = \(networkGroup.cidr ?? "10.0.0.0/24")\n"
        }
        
        if let endpoint = peer.endpoint {
            content += "Endpoint = \(endpoint)\n"
        } else if let wgEndpoint = networkGroup.wireGuardEndpoint {
            content += "Endpoint = \(wgEndpoint)\n"
        }
        
        content += "PersistentKeepalive = 25\n"
        
        return content
    }
    
    private func saveConfigToFile(content: String, fileName: String) -> URL? {
        let documentsPath = FileManager.default.temporaryDirectory
        let fileURL = documentsPath.appendingPathComponent(fileName)
        
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            print("❌ Failed to save config file: \(error)")
            return nil
        }
    }
    
    private func finishExport() {
        isExporting = false
        
        if exportedConfigs.isEmpty {
            errorMessage = "Failed to export configurations"
        } else {
            showingShareSheet = true
        }
    }
}

// MARK: - Supporting Types

struct SelectableItem: Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let type: ItemType
    
    enum ItemType {
        case application
        case addon
        case peer
        
        var icon: String {
            switch self {
            case .application: return "app.badge"
            case .addon: return "puzzlepiece.extension"
            case .peer: return "network.badge.shield.half.filled"
            }
        }
        
        var color: Color {
            switch self {
            case .application: return .green
            case .addon: return .orange
            case .peer: return .purple
            }
        }
    }
}

struct ExportedConfig {
    let id: String
    let name: String
    let fileName: String
    let url: URL
}

// MARK: - ShareSheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
} 