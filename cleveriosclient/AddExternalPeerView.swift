import SwiftUI
import Combine

// MARK: - AddExternalPeerView
/// Modern interface for adding external peers to Network Groups with WireGuard support
struct AddExternalPeerView: View {
    
    // MARK: - Environment
    @Environment(\.dismiss) private var dismiss
    @Environment(AppCoordinator.self) private var coordinator: AppCoordinator
    
    // MARK: - Properties
    let networkGroup: CCNetworkGroup
    let organizationId: String
    let onPeerAdded: (CCNetworkGroupPeer) -> Void
    
    // MARK: - State
    @State private var peerName = ""
    @State private var peerDescription = ""
    @State private var publicKey = ""
    @State private var allowedIPs: [String] = ["0.0.0.0/0"]
    @State private var endpoint = ""
    @State private var newAllowedIP = ""
    @State private var isAdding = false
    @State private var errorMessage: String?
    @State private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Validation
    private var isValidForm: Bool {
        !peerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !publicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !allowedIPs.isEmpty &&
        isValidWireGuardKey(publicKey.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    
    // MARK: - Body
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header Section
                    headerSection
                    
                    // Peer Configuration
                    peerConfigurationSection
                    
                    // WireGuard Settings
                    wireGuardSection
                    
                    // Network Settings
                    networkSettingsSection
                    
                    // Help Section
                    helpSection
                }
                .padding()
            }
            .navigationTitle("Add External Peer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add Peer") {
                        addExternalPeer()
                    }
                    .disabled(!isValidForm || isAdding)
                    .fontWeight(.semibold)
                }
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
                Image(systemName: "network.badge.shield.half.filled")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Add External Peer")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("Connect external device to \(networkGroup.name)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
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
                
                Label("WireGuard", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundColor(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(6)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Peer Configuration Section
    private var peerConfigurationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Peer Information")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                // Peer Name
                VStack(alignment: .leading, spacing: 6) {
                    Text("Peer Name *")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    TextField("e.g., My Laptop, Office Desktop", text: $peerName)
                        .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                        .autocapitalization(.words)
                        .disableAutocorrection(true)
                }
                
                // Peer Description
                VStack(alignment: .leading, spacing: 6) {
                    Text("Description")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    TextField("Optional description", text: $peerDescription)
                        .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                        .autocapitalization(.sentences)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    // MARK: - WireGuard Section
    private var wireGuardSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("WireGuard Configuration")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Image(systemName: "shield.checkered")
                    .foregroundColor(.green)
            }
            
            VStack(spacing: 12) {
                // Public Key
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Public Key *")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        // Key validation indicator
                        if !publicKey.isEmpty {
                            Image(systemName: isValidWireGuardKey(publicKey.trimmingCharacters(in: .whitespacesAndNewlines)) ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(isValidWireGuardKey(publicKey.trimmingCharacters(in: .whitespacesAndNewlines)) ? .green : .red)
                        }
                    }
                    
                    TextField("Paste WireGuard public key here", text: $publicKey, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                        .lineLimit(2...4)
                        .font(.system(.caption, design: .monospaced))
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    Text("44-character base64 encoded key from your WireGuard client")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Endpoint (Optional)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Endpoint (Optional)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    TextField("e.g., example.com:51820", text: $endpoint)
                        .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .keyboardType(.URL)
                    
                    Text("Leave empty for dynamic IP or client-initiated connections")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    // MARK: - Network Settings Section
    private var networkSettingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Network Settings")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 12) {
                // Allowed IPs Header
                HStack {
                    Text("Allowed IPs")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Text("\(allowedIPs.count) rule\(allowedIPs.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Allowed IPs List
                ForEach(allowedIPs.indices, id: \.self) { index in
                    HStack {
                        Text(allowedIPs[index])
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        
                        Spacer()
                        
                        Button(action: {
                            removeAllowedIP(at: index)
                        }) {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.red)
                        }
                        .disabled(allowedIPs.count <= 1)
                    }
                }
                
                // Add new Allowed IP
                HStack {
                    TextField("e.g., 192.168.1.0/24", text: $newAllowedIP)
                        .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .keyboardType(.numbersAndPunctuation)
                    
                    Button("Add") {
                        addAllowedIP()
                    }
                    .disabled(newAllowedIP.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .buttonStyle(.borderless)
                    .foregroundColor(.blue)
                    .fontWeight(.medium)
                }
                
                // Quick options
                HStack {
                    Text("Quick options:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button("All Traffic") {
                        if !allowedIPs.contains("0.0.0.0/0") {
                            allowedIPs.append("0.0.0.0/0")
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                    .foregroundColor(.blue)
                    
                    Button("LAN Only") {
                        let lanRanges = ["192.168.0.0/16", "10.0.0.0/8", "172.16.0.0/12"]
                        for range in lanRanges {
                            if !allowedIPs.contains(range) {
                                allowedIPs.append(range)
                            }
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                    .foregroundColor(.blue)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    // MARK: - Help Section
    private var helpSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How to get WireGuard public key")
                .font(.subheadline)
                .fontWeight(.medium)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "desktopcomputer")
                        .foregroundColor(.blue)
                        .frame(width: 20)
                    Text("Desktop: Open WireGuard app → Generate key pair → Copy public key")
                        .font(.caption)
                }
                
                HStack {
                    Image(systemName: "iphone")
                        .foregroundColor(.blue)
                        .frame(width: 20)
                    Text("Mobile: WireGuard app → + → Create from scratch → Copy public key")
                        .font(.caption)
                }
                
                HStack {
                    Image(systemName: "terminal")
                        .foregroundColor(.blue)
                        .frame(width: 20)
                    Text("CLI: wg genkey | tee private.key | wg pubkey > public.key")
                        .font(.system(.caption, design: .monospaced))
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Helper Methods
    private func isValidWireGuardKey(_ key: String) -> Bool {
        // WireGuard public keys are 44 characters base64 encoded
        let cleanKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanKey.count == 44 else { return false }
        
        // Check if it's valid base64
        let base64Regex = "^[A-Za-z0-9+/]*={0,2}$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", base64Regex)
        return predicate.evaluate(with: cleanKey)
    }
    
    private func addAllowedIP() {
        let trimmedIP = newAllowedIP.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedIP.isEmpty && !allowedIPs.contains(trimmedIP) else { return }
        
        allowedIPs.append(trimmedIP)
        newAllowedIP = ""
    }
    
    private func removeAllowedIP(at index: Int) {
        guard index >= 0 && index < allowedIPs.count && allowedIPs.count > 1 else { return }
        allowedIPs.remove(at: index)
    }
    
    private func addExternalPeer() {
        guard isValidForm else { return }
        
        isAdding = true
        errorMessage = nil
        
        let trimmedName = peerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = peerDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPublicKey = publicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let externalPeer = CCNetworkGroupExternalPeerCreate(
            name: trimmedName,
            description: trimmedDescription.isEmpty ? nil : trimmedDescription,
            publicKey: trimmedPublicKey,
            allowedIps: allowedIPs,
            endpoint: trimmedEndpoint.isEmpty ? nil : trimmedEndpoint
        )
        
        coordinator.cleverCloudSDK.networkGroups.addNetworkGroupExternalPeer(
            organizationId: organizationId,
            networkGroupId: networkGroup.id,
            externalPeer: externalPeer
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { completion in
                isAdding = false
                
                switch completion {
                case .finished:
                    // Success - dismiss and notify parent
                    dismiss()
                    
                case .failure(let error):
                    errorMessage = "Failed to add external peer: \(error.localizedDescription)"
                }
            },
            receiveValue: { addedPeer in
                // Notify parent about the added peer
                onPeerAdded(addedPeer)
                print("✅ Successfully added external peer: \(addedPeer.name)")
            }
        )
        .store(in: &cancellables)
    }
}

// MARK: - Preview
#Preview {
    AddExternalPeerView(
        networkGroup: CCNetworkGroup.example(),
        organizationId: "orga_example",
        onPeerAdded: { _ in }
    )
    .environment(AppCoordinator())
} 