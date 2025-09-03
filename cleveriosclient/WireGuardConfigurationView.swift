import SwiftUI
import Combine
import CoreImage.CIFilterBuiltins

// MARK: - WireGuardConfigurationView
/// Modern interface for managing WireGuard configurations with QR code generation
struct WireGuardConfigurationView: View {
    
    // MARK: - Environment
    @Environment(\.dismiss) private var dismiss
    @Environment(AppCoordinator.self) private var coordinator: AppCoordinator
    
    // MARK: - Properties
    let networkGroup: CCNetworkGroup
    let peer: CCNetworkGroupPeer
    let organizationId: String
    
    // MARK: - State
    @State private var wireGuardConfig: CCWireGuardConfiguration?
    @State private var configurationText: String = ""
    @State private var qrCodeImage: UIImage?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingShareSheet = false
    @State private var showingCopyAlert = false
    @State private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Body
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header Section
                    headerSection
                    
                    // Configuration Status
                    if isLoading {
                        loadingSection
                    } else if wireGuardConfig != nil {
                        // QR Code Section
                        qrCodeSection
                        
                        // Configuration Text
                        configurationSection
                        
                        // Actions Section
                        actionsSection
                        
                        // Instructions Section
                        instructionsSection
                    } else {
                        // Error or Empty State
                        emptyStateSection
                    }
                }
                .padding()
            }
            .navigationTitle("WireGuard Config")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Refresh") {
                        loadWireGuardConfiguration()
                    }
                    .disabled(isLoading)
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let configText = configurationText.isEmpty ? nil : configurationText {
                    ShareSheet(items: [configText])
                }
            }
            .alert("Configuration Copied", isPresented: $showingCopyAlert) {
                Button("OK") { }
            } message: {
                Text("WireGuard configuration has been copied to clipboard")
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "Unknown error occurred")
            }
        }
        .onAppear {
            loadWireGuardConfiguration()
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "qrcode.viewfinder")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("WireGuard Configuration")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("For peer: \(peer.name)")
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
                    Text("Network: \(networkGroup.name)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("CIDR: \(networkGroup.cidr ?? "Auto-assigned")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Peer Type Indicator
                Label(peer.isExternal ? "External" : "Internal", systemImage: peer.isExternal ? "globe" : "house")
                    .font(.caption)
                    .foregroundColor(peer.isExternal ? .blue : .green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(peer.isExternal ? .blue : .green).opacity(0.1))
                    .cornerRadius(6)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Loading Section
    private var loadingSection: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
                .scaleEffect(1.5)
            
            Text("Generating WireGuard configuration...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    // MARK: - QR Code Section
    private var qrCodeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("QR Code")
                .font(.headline)
                .fontWeight(.semibold)
            
            HStack {
                Spacer()
                
                VStack(spacing: 12) {
                    if let qrImage = qrCodeImage {
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 200, height: 200)
                            .background(Color.white)
                            .cornerRadius(12)
                            .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemGray5))
                            .frame(width: 200, height: 200)
                            .overlay(
                                VStack {
                                    Image(systemName: "qrcode")
                                        .font(.system(size: 40))
                                        .foregroundColor(.secondary)
                                    Text("No QR Code")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            )
                    }
                    
                    Text("Scan with WireGuard app")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    // MARK: - Configuration Section
    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Configuration File")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("WireGuard Configuration (.conf)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                ScrollView {
                    Text(configurationText)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                }
                .frame(maxHeight: 200)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    // MARK: - Actions Section
    private var actionsSection: some View {
        VStack(spacing: 12) {
            // Primary Actions
            HStack(spacing: 12) {
                Button(action: copyConfiguration) {
                    HStack {
                        Image(systemName: "doc.on.clipboard")
                        Text("Copy Config")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                
                Button(action: shareConfiguration) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share Config")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            }
            
            // Save QR Code Action
            if qrCodeImage != nil {
                Button(action: saveQRCode) {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                        Text("Save QR Code to Photos")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.purple)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            }
        }
    }
    
    // MARK: - Instructions Section
    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Setup Instructions")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 12) {
                InstructionRow(
                    number: "1",
                    icon: "qrcode.viewfinder",
                    title: "Scan QR Code",
                    description: "Open WireGuard app and tap + → Scan QR Code"
                )
                
                InstructionRow(
                    number: "2",
                    icon: "doc.text",
                    title: "Or Import File",
                    description: "Save config as .conf file and import in WireGuard app"
                )
                
                InstructionRow(
                    number: "3",
                    icon: "play.circle",
                    title: "Activate Connection",
                    description: "Toggle the connection in WireGuard app to connect"
                )
                
                InstructionRow(
                    number: "4",
                    icon: "checkmark.shield",
                    title: "Verify Connection",
                    description: "Check that you can reach other network members"
                )
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Empty State Section
    private var emptyStateSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text("Configuration Unavailable")
                .font(.headline)
                .fontWeight(.semibold)
            
            Text("Unable to load WireGuard configuration for this peer. Please try refreshing or contact support if the issue persists.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Retry") {
                loadWireGuardConfiguration()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    // MARK: - Helper Methods
    private func loadWireGuardConfiguration() {
        isLoading = true
        errorMessage = nil
        
        coordinator.cleverCloudSDK.networkGroups.getWireGuardConfiguration(
            organizationId: organizationId,
            networkGroupId: networkGroup.id,
            peerId: peer.id
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { completion in
                isLoading = false
                
                if case .failure(let error) = completion {
                    errorMessage = "Failed to load WireGuard configuration: \(error.localizedDescription)"
                }
            },
            receiveValue: { config in
                wireGuardConfig = config
                configurationText = config.configContent ?? generateConfigurationText(from: config)
                generateQRCode()
                print("✅ Successfully loaded WireGuard configuration")
            }
        )
        .store(in: &cancellables)
    }
    
    private func generateConfigurationText(from config: CCWireGuardConfiguration) -> String {
        var configText = "[Interface]\n"
        configText += "PrivateKey = \(config.interface.privateKey)\n"
        configText += "Address = \(config.interface.address)\n"
        
        if let dns = config.interface.dns, !dns.isEmpty {
            configText += "DNS = \(dns.joined(separator: ", "))\n"
        }
        
        for peer in config.peers {
            configText += "\n[Peer]\n"
            configText += "PublicKey = \(peer.publicKey)\n"
            configText += "AllowedIPs = \(peer.allowedIPs)\n"
            
            if let endpoint = peer.endpoint {
                configText += "Endpoint = \(endpoint)\n"
            }
            
            if let keepalive = peer.persistentKeepalive {
                configText += "PersistentKeepalive = \(keepalive)\n"
            }
        }
        
        return configText
    }
    
    private func generateQRCode() {
        guard !configurationText.isEmpty else { return }
        
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        
        filter.message = Data(configurationText.utf8)
        filter.correctionLevel = "M"
        
        if let outputImage = filter.outputImage {
            let transform = CGAffineTransform(scaleX: 10, y: 10)
            let scaledImage = outputImage.transformed(by: transform)
            
            if let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) {
                qrCodeImage = UIImage(cgImage: cgImage)
            }
        }
    }
    
    private func copyConfiguration() {
        UIPasteboard.general.string = configurationText
        showingCopyAlert = true
    }
    
    private func shareConfiguration() {
        showingShareSheet = true
    }
    
    private func saveQRCode() {
        guard let image = qrCodeImage else { return }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
    }
}

// MARK: - InstructionRow
private struct InstructionRow: View {
    let number: String
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Step Number
            Text(number)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Color.blue)
                .clipShape(Circle())
            
            // Icon
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 24, height: 24)
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}



// MARK: - Preview
#Preview {
    WireGuardConfigurationView(
        networkGroup: CCNetworkGroup.example(),
        peer: CCNetworkGroupPeer(
            id: "peer_example",
            name: "My Laptop",
            description: "Personal laptop",
            type: "external",
            publicKey: "dQw4w9WgXcQ=",
            allowedIps: ["0.0.0.0/0"],
            endpoint: "example.com:51820",
            createdAt: Date(),
            status: "connected"
        ),
        organizationId: "orga_example"
    )
    .environment(AppCoordinator())
} 