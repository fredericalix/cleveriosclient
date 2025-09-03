import SwiftUI
import Combine

// MARK: - DeleteNetworkGroupView
/// Revolutionary Network Group deletion interface with comprehensive warnings and confirmation steps
struct DeleteNetworkGroupView: View {
    
    // MARK: - Environment
    @Environment(\.dismiss) private var dismiss
    @Environment(AppCoordinator.self) private var coordinator: AppCoordinator
    
    // MARK: - Properties
    let organizationId: String
    let networkGroup: CCNetworkGroup
    let onNetworkGroupDeleted: () -> Void
    
    // MARK: - State
    @State private var confirmationText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingDangerConfirmation = false
    @State private var showingFinalConfirmation = false
    @State private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Constants
    private let requiredConfirmationText: String
    
    init(organizationId: String, networkGroup: CCNetworkGroup, onNetworkGroupDeleted: @escaping () -> Void) {
        self.organizationId = organizationId
        self.networkGroup = networkGroup
        self.onNetworkGroupDeleted = onNetworkGroupDeleted
        self.requiredConfirmationText = networkGroup.name
    }
    
    // MARK: - Body
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header with danger icon
                    headerSection
                    
                    // Network Group summary
                    networkGroupSummarySection
                    
                    // Critical warnings
                    criticalWarningsSection
                    
                    // Impact analysis
                    impactAnalysisSection
                    
                    // Confirmation input
                    confirmationInputSection
                    
                    // Action buttons
                    actionButtonsSection
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .navigationTitle("Delete Network Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Network Deletion Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "Unknown error occurred")
            }
            .confirmationDialog(
                "⚠️ FINAL CONFIRMATION",
                isPresented: $showingFinalConfirmation,
                titleVisibility: .visible
            ) {
                Button("YES, DELETE PERMANENTLY", role: .destructive) {
                    performDeletion()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This action CANNOT be undone. The Network Group '\(networkGroup.name)' and all its connections will be permanently destroyed. Are you absolutely certain?")
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 16) {
            // Danger icon with animation
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.red.opacity(0.1), Color.red.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 50, weight: .medium))
                    .foregroundColor(.red)
                    .scaleEffect(showingDangerConfirmation ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.3).repeatForever(autoreverses: true), value: showingDangerConfirmation)
            }
            
            VStack(spacing: 8) {
                Text("⚠️ DANGER ZONE ⚠️")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.red)
                
                Text("You are about to permanently delete a Network Group")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            showingDangerConfirmation = true
        }
    }
    
    // MARK: - Network Group Summary Section
    private var networkGroupSummarySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Network Group Details")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 0) {
                summaryRow("Name", value: networkGroup.name, highlighted: true)
                summaryRow("Organization ID", value: organizationId)
                summaryRow("Status", value: networkGroup.status ?? "Unknown")
                if let region = networkGroup.region {
                    summaryRow("Region", value: region.uppercased())
                }
                if let cidr = networkGroup.cidr {
                    summaryRow("CIDR Block", value: cidr)
                }
                if let created = networkGroup.createdAt {
                    summaryRow("Created", value: DateFormatter.shortDate.string(from: created))
                }
                if let description = networkGroup.description, !description.isEmpty {
                    summaryRow("Description", value: description)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
            )
        }
    }
    
    // MARK: - Critical Warnings Section
    private var criticalWarningsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("⚠️ Critical Warnings")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.red)
            
            VStack(spacing: 12) {
                warningCard(
                    icon: "wifi.slash",
                    title: "Network Connectivity Loss",
                    description: "All applications and services in this network group will immediately lose their private network connectivity.",
                    severity: .critical
                )
                
                warningCard(
                    icon: "link.circle",
                    title: "Service Disruption",
                    description: "Applications relying on internal network communication may experience immediate service disruption or failure.",
                    severity: .critical
                )
                
                warningCard(
                    icon: "trash.fill",
                    title: "Permanent Data Loss",
                    description: "This action is irreversible. All network group configurations, member associations, and peer connections will be permanently lost.",
                    severity: .critical
                )
                
                warningCard(
                    icon: "clock.arrow.circlepath",
                    title: "No Recovery Option",
                    description: "Once deleted, this network group cannot be restored. You would need to manually recreate all configurations.",
                    severity: .warning
                )
            }
        }
    }
    
    // MARK: - Impact Analysis Section
    private var impactAnalysisSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("📊 Impact Analysis")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                impactCard(
                    icon: "app.badge",
                    title: "Connected Applications",
                    impact: "All applications will lose network group membership and internal connectivity",
                    color: .orange
                )
                
                impactCard(
                    icon: "gear.badge",
                    title: "Connected Add-ons",
                    impact: "All add-ons will lose network group access and may require reconfiguration",
                    color: .orange
                )
                
                impactCard(
                    icon: "globe",
                    title: "External Peers",
                    impact: "All WireGuard peers will lose connectivity and configurations will be invalidated",
                    color: .red
                )
                
                impactCard(
                    icon: "network",
                    title: "Internal Network",
                    impact: "Private IP allocations and routing rules will be permanently removed",
                    color: .red
                )
            }
        }
    }
    
    // MARK: - Confirmation Input Section
    private var confirmationInputSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("🔒 Confirmation Required")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("To confirm deletion, type the Network Group name:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text("**\(requiredConfirmationText)**")
                    .font(.subheadline)
                    .fontDesign(.monospaced)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(.systemGray5))
                    .cornerRadius(6)
                
                TextField("Enter network group name here", text: $confirmationText)
                    .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: confirmationText) { _, _ in
                        // Auto-validate on change
                    }
                
                if !confirmationText.isEmpty && confirmationText != requiredConfirmationText {
                    HStack(spacing: 8) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                        Text("Network Group name doesn't match")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                
                if confirmationText == requiredConfirmationText {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Confirmation text matches")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }
        }
    }
    
    // MARK: - Action Buttons Section
    private var actionButtonsSection: some View {
        VStack(spacing: 16) {
            Button(action: {
                showingFinalConfirmation = true
            }) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "trash.fill")
                    }
                    
                    Text("DELETE NETWORK GROUP PERMANENTLY")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .foregroundColor(.white)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isConfirmationValid ? Color.red : Color.gray)
                )
            }
            .disabled(!isConfirmationValid || isLoading)
            
            Button("Cancel") {
                dismiss()
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .foregroundColor(.blue)
        }
    }
    
    // MARK: - Helper Views
    private func summaryRow(_ label: String, value: String, highlighted: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .fontWeight(highlighted ? .semibold : .medium)
                .foregroundColor(highlighted ? .primary : .secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            highlighted ?
            Color.blue.opacity(0.05) :
            Color.clear
        )
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(.systemGray4)),
            alignment: .bottom
        )
    }
    
    private func warningCard(icon: String, title: String, description: String, severity: WarningLevel) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(severity.iconColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(severity.titleColor)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(severity.backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(severity.borderColor, lineWidth: 1)
        )
    }
    
    private func impactCard(icon: String, title: String, impact: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(impact)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }
    
    // MARK: - Computed Properties
    private var isConfirmationValid: Bool {
        confirmationText == requiredConfirmationText
    }
    
    // MARK: - Methods
    private func performDeletion() {
        isLoading = true
        errorMessage = nil
        
        coordinator.cleverCloudSDK.networkGroups.deleteNetworkGroup(
            organizationId: organizationId,
            networkGroupId: networkGroup.id
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { completion in
                isLoading = false
                
                switch completion {
                case .finished:
                    // Success - notify parent and dismiss
                    onNetworkGroupDeleted()
                    dismiss()
                    
                case .failure(let error):
                    errorMessage = "Failed to delete network group: \(error.localizedDescription)"
                }
            },
            receiveValue: { _ in
                // Deletion completed successfully (void response)
            }
        )
        .store(in: &cancellables)
    }
}

// MARK: - Supporting Types
enum WarningLevel {
    case critical
    case warning
    
    var iconColor: Color {
        switch self {
        case .critical: return .red
        case .warning: return .orange
        }
    }
    
    var titleColor: Color {
        switch self {
        case .critical: return .red
        case .warning: return .orange
        }
    }
    
    var backgroundColor: Color {
        switch self {
        case .critical: return Color.red.opacity(0.05)
        case .warning: return Color.orange.opacity(0.05)
        }
    }
    
    var borderColor: Color {
        switch self {
        case .critical: return Color.red.opacity(0.2)
        case .warning: return Color.orange.opacity(0.2)
        }
    }
}

// MARK: - Extensions
extension DateFormatter {
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

// MARK: - Preview
#Preview {
    DeleteNetworkGroupView(
        organizationId: "orga_example",
        networkGroup: CCNetworkGroup(
            id: "ng_example",
            name: "Production Network",
            description: "Main production environment",
            organizationId: "orga_example",
            cidr: "10.0.0.0/24",
            createdAt: Date(),
            updatedAt: Date(),
            status: "active",
            wireGuardEndpoint: nil,
            region: "par"
        ),
        onNetworkGroupDeleted: {}
    )
    .environment(AppCoordinator())
} 