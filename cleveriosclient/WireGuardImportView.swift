import SwiftUI
import UniformTypeIdentifiers
import Combine

// MARK: - WireGuardImportView
/// View for importing WireGuard configurations as external peers
struct WireGuardImportView: View {
    
    // MARK: - Environment
    @Environment(\.dismiss) private var dismiss
    @Environment(AppCoordinator.self) private var coordinator
    
    // MARK: - Properties
    let networkGroup: CCNetworkGroup
    let organizationId: String
    let onImportComplete: (CCNetworkGroupPeer) -> Void
    
    // MARK: - State
    @State private var peerName = ""
    @State private var peerDescription = ""
    @State private var configText = ""
    @State private var showingFilePicker = false
    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var cancellables = Set<AnyCancellable>()
    
    // Parsed config values
    @State private var parsedPublicKey = ""
    @State private var parsedEndpoint = ""
    @State private var parsedAllowedIPs = ""
    
    // MARK: - Body
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerView
                    
                    // Peer Information
                    peerInfoSection
                    
                    // Configuration Input
                    configInputSection
                    
                    // Parsed Configuration Preview
                    if !parsedPublicKey.isEmpty {
                        parsedConfigPreview
                    }
                    
                    // Import Button
                    importButton
                }
                .padding()
            }
            .navigationTitle("Import WireGuard Config")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Import Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "")
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.plainText, .data],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "square.and.arrow.down")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Import External Peer")
                        .font(.headline)
                    Text("Add an external WireGuard peer to \(networkGroup.name)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.orange)
                Text("The peer's public key and endpoint will be extracted from the configuration")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
        }
    }
    
    // MARK: - Peer Info Section
    
    private var peerInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Peer Information")
                .font(.headline)
            
            VStack(spacing: 12) {
                // Name Field
                VStack(alignment: .leading, spacing: 6) {
                    Label("Name", systemImage: "tag")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextField("External VPN Server", text: $peerName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                // Description Field
                VStack(alignment: .leading, spacing: 6) {
                    Label("Description (optional)", systemImage: "text.alignleft")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextField("Office network connection", text: $peerDescription)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Config Input Section
    
    private var configInputSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("WireGuard Configuration")
                    .font(.headline)
                
                Spacer()
                
                Button("Choose File") {
                    showingFilePicker = true
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Paste your WireGuard configuration or select a .conf file")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                TextEditor(text: $configText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 200)
                    .padding(8)
                    .background(Color(.systemGray5))
                    .cornerRadius(8)
                    .onChange(of: configText) { _, newValue in
                        parseConfiguration(newValue)
                    }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Parsed Config Preview
    
    private var parsedConfigPreview: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Configuration Parsed")
                    .font(.headline)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                // Public Key
                if !parsedPublicKey.isEmpty {
                    configValueRow(
                        label: "Public Key",
                        value: parsedPublicKey,
                        icon: "key"
                    )
                }
                
                // Endpoint
                if !parsedEndpoint.isEmpty {
                    configValueRow(
                        label: "Endpoint",
                        value: parsedEndpoint,
                        icon: "link"
                    )
                }
                
                // Allowed IPs
                if !parsedAllowedIPs.isEmpty {
                    configValueRow(
                        label: "Allowed IPs",
                        value: parsedAllowedIPs,
                        icon: "network"
                    )
                }
            }
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
    }
    
    private func configValueRow(label: String, value: String, icon: String) -> some View {
        HStack(alignment: .top) {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(value)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Import Button
    
    private var importButton: some View {
        Button(action: importPeer) {
            HStack {
                if isImporting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "plus.circle.fill")
                }
                
                Text(isImporting ? "Importing..." : "Import as External Peer")
                    .fontWeight(.medium)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                canImport() ? Color.blue : Color.gray
            )
            .cornerRadius(12)
        }
        .disabled(!canImport() || isImporting)
    }
    
    // MARK: - Methods
    
    private func canImport() -> Bool {
        !peerName.isEmpty && !parsedPublicKey.isEmpty
    }
    
    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                configText = content
                
                // Try to extract name from filename
                let filename = url.lastPathComponent
                if peerName.isEmpty && filename.hasSuffix(".conf") {
                    peerName = String(filename.dropLast(5))
                        .replacingOccurrences(of: "_", with: " ")
                        .replacingOccurrences(of: "-", with: " ")
                }
            } catch {
                errorMessage = "Failed to read file: \(error.localizedDescription)"
            }
            
        case .failure(let error):
            errorMessage = "Failed to import file: \(error.localizedDescription)"
        }
    }
    
    private func parseConfiguration(_ config: String) {
        // Reset parsed values
        parsedPublicKey = ""
        parsedEndpoint = ""
        parsedAllowedIPs = ""
        
        let lines = config.components(separatedBy: .newlines)
        var inInterfaceSection = false
        var inPeerSection = false
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            // Section detection
            if trimmedLine == "[Interface]" {
                inInterfaceSection = true
                inPeerSection = false
                continue
            } else if trimmedLine == "[Peer]" {
                inInterfaceSection = false
                inPeerSection = true
                continue
            }
            
            // Skip comments and empty lines
            if trimmedLine.isEmpty || trimmedLine.hasPrefix("#") {
                continue
            }
            
            // Parse key-value pairs
            let parts = trimmedLine.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            
            let key = parts[0].lowercased()
            let value = parts[1]
            
            if inInterfaceSection {
                // In a client config, the Interface section contains the private key
                // We need the public key from the Peer section
            } else if inPeerSection {
                switch key {
                case "publickey":
                    parsedPublicKey = value
                case "endpoint":
                    parsedEndpoint = value
                case "allowedips":
                    parsedAllowedIPs = value
                default:
                    break
                }
            }
        }
        
        // If this is a server config (has PrivateKey in Interface), we need to derive the public key
        // For now, we'll just check if we found a public key in a peer section
    }
    
    private func importPeer() {
        guard canImport() else { return }
        
        isImporting = true
        
        // Create external peer data
        let allowedIPs = parsedAllowedIPs.isEmpty ? [networkGroup.cidr ?? "10.0.0.0/24"] : parsedAllowedIPs.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        
        let externalPeer = CCNetworkGroupExternalPeerCreate(
            name: peerName,
            description: peerDescription.isEmpty ? nil : peerDescription,
            publicKey: parsedPublicKey,
            allowedIps: allowedIPs,
            endpoint: parsedEndpoint.isEmpty ? nil : parsedEndpoint
        )
        
        // Add external peer via API
        coordinator.cleverCloudSDK.networkGroups.addNetworkGroupExternalPeer(
            organizationId: organizationId,
            networkGroupId: networkGroup.id,
            externalPeer: externalPeer
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { completion in
                isImporting = false
                if case .failure(let error) = completion {
                    errorMessage = "Failed to add external peer: \(error.localizedDescription)"
                }
            },
            receiveValue: { peer in
                onImportComplete(peer)
                dismiss()
            }
        )
        .store(in: &cancellables)
    }
} 