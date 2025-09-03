import SwiftUI
import Combine
import Network

// MARK: - CreateNetworkGroupView
/// Revolutionary Network Group creation interface with real-time validation
struct CreateNetworkGroupView: View {
    
    // MARK: - Environment
    @Environment(\.dismiss) private var dismiss
    @Environment(AppCoordinator.self) private var coordinator: AppCoordinator
    
    // MARK: - Properties
    let organizationId: String
    let onNetworkGroupCreated: (CCNetworkGroup) -> Void
    
    // MARK: - State
    @State private var networkGroupName = ""
    @State private var networkGroupDescription = ""
    @State private var selectedCIDR = "10.0.0.0/24"
    @State private var customCIDR = ""
    @State private var selectedRegion = "par"
    @State private var selectedTemplate: NetworkGroupTemplate?
    @State private var useTemplate = false
    @State private var isCreating = false
    @State private var validationErrors: [String] = []
    @State private var errorMessage: String?
    @State private var cancellables = Set<AnyCancellable>()
    
    // Validation state
    @State private var isNameValid = false
    @State private var isCIDRValid = false
    @State private var cidrValidationMessage = ""
    
    // MARK: - Predefined Options
    private let predefinedCIDRs = [
        "10.0.0.0/24",
        "10.0.0.0/16", 
        "192.168.0.0/24",
        "192.168.1.0/24",
        "172.16.0.0/24",
        "Custom"
    ]
    
    private let availableRegions = [
        Region(code: "par", name: "Paris", flag: "🇫🇷"),
        Region(code: "mtl", name: "Montreal", flag: "🇨🇦"),
        Region(code: "sgp", name: "Singapore", flag: "🇸🇬"),
        Region(code: "syd", name: "Sydney", flag: "🇦🇺"),
        Region(code: "wsw", name: "Warsaw", flag: "🇵🇱")
    ]
    
    // MARK: - Body
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerView
                    
                    // Template Selection (if available)
                    if !availableTemplates.isEmpty {
                        templateSelectionSection
                    }
                    
                    // Network Group Information
                    networkGroupInfoSection
                    
                    // Network Configuration
                    networkConfigurationSection
                    
                    // Region Selection
                    regionSelectionSection
                    
                    // Validation Summary
                    if !validationErrors.isEmpty {
                        validationSummarySection
                    }
                    
                    // Create Button
                    createButton
                }
                .padding()
            }
            .navigationTitle("Create Network Group")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Creation Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "")
            }
            .onAppear {
                setupValidation()
            }
            .onChange(of: networkGroupName) { _, newValue in
                validateName(newValue)
            }
            .onChange(of: selectedCIDR) { _, _ in
                let cidr = selectedCIDR == "Custom" ? customCIDR : selectedCIDR
                validateCIDR(cidr)
            }
            .onChange(of: customCIDR) { _, _ in
                if selectedCIDR == "Custom" {
                    validateCIDR(customCIDR)
                }
            }
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "network")
                    .font(.title2)
                    .foregroundColor(.purple)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Create Network Group")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("Secure private network for applications and services")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            if isCreating {
                VStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(LinearProgressViewStyle())
                    
                    Text("Creating network group...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Template Selection Section
    
    private var templateSelectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Templates")
                    .font(.headline)
                
                Spacer()
                
                Toggle("Use Template", isOn: $useTemplate)
                    .toggleStyle(SwitchToggleStyle())
            }
            
            if useTemplate {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(availableTemplates) { template in
                            TemplateCard(
                                template: template,
                                isSelected: selectedTemplate?.id == template.id
                            ) {
                                selectedTemplate = template
                                applyTemplate(template)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - Network Group Info Section
    
    private var networkGroupInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Network Group Information")
                .font(.headline)
            
            VStack(spacing: 16) {
                // Name Field
                VStack(alignment: .leading, spacing: 6) {
                    Label("Name", systemImage: "tag")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextField("Production Network", text: $networkGroupName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    networkGroupName.isEmpty ? Color.clear : 
                                    isNameValid ? Color.green : Color.red,
                                    lineWidth: 1
                                )
                        )
                    
                    if !networkGroupName.isEmpty && !isNameValid {
                        Text("Name must be at least 3 characters")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                
                // Description Field
                VStack(alignment: .leading, spacing: 6) {
                    Label("Description (optional)", systemImage: "text.alignleft")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextField("Secure network for production applications", text: $networkGroupDescription, axis: .vertical)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocorrectionDisabled(true)
                        .lineLimit(3)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - Network Configuration Section
    
    private var networkConfigurationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Network Configuration")
                .font(.headline)
            
            VStack(spacing: 16) {
                // CIDR Selection
                VStack(alignment: .leading, spacing: 6) {
                    Label("Network CIDR", systemImage: "network")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Picker("CIDR", selection: $selectedCIDR) {
                        ForEach(predefinedCIDRs, id: \.self) { cidr in
                            Text(cidr).tag(cidr)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    
                    // Custom CIDR Input
                    if selectedCIDR == "Custom" {
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("10.0.0.0/24", text: $customCIDR)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .autocorrectionDisabled(true)
                                .textInputAutocapitalization(.never)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(
                                            customCIDR.isEmpty ? Color.clear :
                                            isCIDRValid ? Color.green : Color.red,
                                            lineWidth: 1
                                        )
                                )
                            
                            if !cidrValidationMessage.isEmpty {
                                Text(cidrValidationMessage)
                                    .font(.caption)
                                    .foregroundColor(isCIDRValid ? .green : .red)
                            }
                        }
                    }
                    
                    // CIDR Info
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Network Information")
                            .font(.caption)
                            .fontWeight(.medium)
                        
                        let cidr = selectedCIDR == "Custom" ? customCIDR : selectedCIDR
                        if let info = getCIDRInfo(cidr) {
                            HStack {
                                Text("Available IPs:")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("\(info.availableIPs)")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                            }
                            
                            HStack {
                                Text("Subnet Mask:")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(info.subnetMask)
                                    .font(.caption2)
                                    .fontWeight(.medium)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - Region Selection Section
    
    private var regionSelectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Region")
                .font(.headline)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(availableRegions) { region in
                        RegionCard(
                            region: region,
                            isSelected: selectedRegion == region.code
                        ) {
                            selectedRegion = region.code
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - Validation Summary Section
    
    private var validationSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Validation Issues")
                    .font(.headline)
                    .foregroundColor(.orange)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                ForEach(validationErrors, id: \.self) { error in
                    HStack(alignment: .top) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                        
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }
    
    // MARK: - Create Button
    
    private var createButton: some View {
        Button(action: createNetworkGroup) {
            HStack {
                if isCreating {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "plus.circle.fill")
                }
                
                Text(isCreating ? "Creating..." : "Create Network Group")
                    .fontWeight(.medium)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                canCreateNetworkGroup ? Color.blue : Color.gray
            )
            .cornerRadius(12)
        }
        .disabled(!canCreateNetworkGroup || isCreating)
    }
    
    // MARK: - Computed Properties
    
    private var canCreateNetworkGroup: Bool {
        return isNameValid && isCIDRValid && validationErrors.isEmpty
    }
    
    private var effectiveCIDR: String {
        return selectedCIDR == "Custom" ? customCIDR : selectedCIDR
    }
    
    private var availableTemplates: [NetworkGroupTemplate] {
        // For now, return hardcoded templates
        // TODO: Load from CCNetworkGroupService when implemented
        return [
            NetworkGroupTemplate(
                id: "dev-template",
                name: "Development",
                description: "Standard development environment",
                category: .development,
                defaultCIDR: "10.0.0.0/24",
                recommendedMembers: [],
                securityRules: []
            ),
            NetworkGroupTemplate(
                id: "prod-template", 
                name: "Production",
                description: "Production environment with high security",
                category: .production,
                defaultCIDR: "10.1.0.0/24",
                recommendedMembers: [],
                securityRules: []
            )
        ]
    }
    
    // MARK: - Methods
    
    private func setupValidation() {
        // Initial validation
        validateName(networkGroupName)
        let cidr = selectedCIDR == "Custom" ? customCIDR : selectedCIDR
        validateCIDR(cidr)
    }
    
    private func validateName(_ name: String) {
        isNameValid = name.count >= 3
        updateValidationErrors()
    }
    
    private func validateCIDR(_ cidr: String) {
        if cidr.isEmpty {
            isCIDRValid = false
            cidrValidationMessage = "CIDR is required"
            updateValidationErrors()
            return
        }
        
        // Basic CIDR validation
        let cidrRegex = #"^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\/(?:[0-9]|[1-2][0-9]|3[0-2])$"#
        
        let isValidFormat = cidr.range(of: cidrRegex, options: .regularExpression) != nil
        
        if isValidFormat {
            // Additional validation for sensible CIDR ranges
            let parts = cidr.split(separator: "/")
            if parts.count == 2, let subnet = Int(parts[1]) {
                if subnet >= 8 && subnet <= 30 {
                    isCIDRValid = true
                    cidrValidationMessage = "✓ Valid CIDR format"
                } else {
                    isCIDRValid = false
                    cidrValidationMessage = "Subnet mask should be between /8 and /30"
                }
            } else {
                isCIDRValid = false
                cidrValidationMessage = "Invalid subnet mask"
            }
        } else {
            isCIDRValid = false
            cidrValidationMessage = "Invalid CIDR format (e.g., 10.0.0.0/24)"
        }
        
        updateValidationErrors()
    }
    
    private func updateValidationErrors() {
        var errors: [String] = []
        
        if !isNameValid && !networkGroupName.isEmpty {
            errors.append("Network group name must be at least 3 characters")
        }
        
        if !isCIDRValid && !effectiveCIDR.isEmpty {
            errors.append("Invalid CIDR format")
        }
        
        validationErrors = errors
    }
    
    private func applyTemplate(_ template: NetworkGroupTemplate) {
        networkGroupName = template.name + " Network"
        networkGroupDescription = template.description
        selectedCIDR = template.defaultCIDR
    }
    
    private func getCIDRInfo(_ cidr: String) -> CIDRInfo? {
        guard !cidr.isEmpty else { return nil }
        
        let parts = cidr.split(separator: "/")
        guard parts.count == 2, let subnet = Int(parts[1]) else { return nil }
        
        let availableIPs = Int(pow(2.0, Double(32 - subnet))) - 2 // -2 for network and broadcast
        let subnetMask = cidrToSubnetMask(subnet)
        
        return CIDRInfo(availableIPs: availableIPs, subnetMask: subnetMask)
    }
    
    private func cidrToSubnetMask(_ cidr: Int) -> String {
        let mask = (0xFFFFFFFF << (32 - cidr)) & 0xFFFFFFFF
        let a = (mask >> 24) & 0xFF
        let b = (mask >> 16) & 0xFF
        let c = (mask >> 8) & 0xFF
        let d = mask & 0xFF
        return "\(a).\(b).\(c).\(d)"
    }
    
    private func createNetworkGroup() {
        guard canCreateNetworkGroup else { return }
        
        isCreating = true
        errorMessage = nil
        
        let networkGroupCreate = CCNetworkGroupCreate(
            name: networkGroupName,
            description: networkGroupDescription.isEmpty ? nil : networkGroupDescription,
            cidr: effectiveCIDR,
            region: selectedRegion
        )
        
        coordinator.cleverCloudSDK.networkGroups.createNetworkGroup(
            organizationId: organizationId,
            networkGroup: networkGroupCreate
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { completion in
                isCreating = false
                if case .failure(let error) = completion {
                    errorMessage = "Failed to create network group: \(error.localizedDescription)"
                }
            },
            receiveValue: { networkGroup in
                print("✅ Network group created successfully: \(networkGroup.name)")
                onNetworkGroupCreated(networkGroup)
                dismiss()
            }
        )
        .store(in: &cancellables)
    }
}

// MARK: - Supporting Types

struct NetworkGroupTemplate: Identifiable, Codable {
    let id: String
    let name: String
    let description: String
    let category: TemplateCategory
    let defaultCIDR: String
    let recommendedMembers: [String]
    let securityRules: [String] // Simplified for now
    
    enum TemplateCategory: String, CaseIterable, Codable {
        case development = "Development"
        case staging = "Staging"
        case production = "Production"
        case microservices = "Microservices"
        case database = "Database"
    }
}

struct Region: Identifiable {
    let id = UUID()
    let code: String
    let name: String
    let flag: String
}

struct CIDRInfo {
    let availableIPs: Int
    let subnetMask: String
}

// MARK: - Template Card

struct TemplateCard: View {
    let template: NetworkGroupTemplate
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: template.category.icon)
                        .foregroundColor(template.category.color)
                    
                    Text(template.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.blue)
                    }
                }
                
                Text(template.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                Text(template.defaultCIDR)
                    .font(.caption2)
                    .fontDesign(.monospaced)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray5))
                    .cornerRadius(4)
            }
            .padding()
            .frame(width: 200)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Region Card

struct RegionCard: View {
    let region: Region
    let isSelected: Bool
    let isChanged: Bool
    let action: () -> Void
    
    init(region: Region, isSelected: Bool, isChanged: Bool = false, action: @escaping () -> Void) {
        self.region = region
        self.isSelected = isSelected
        self.isChanged = isChanged
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Text(region.flag)
                        .font(.title)
                    
                    // Change indicator
                    if isChanged {
                        VStack {
                            HStack {
                                Spacer()
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 12, height: 12)
                                    .overlay(
                                        Text("!")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundColor(.white)
                                    )
                            }
                            Spacer()
                        }
                    }
                }
                
                Text(region.name)
                    .font(.caption)
                    .fontWeight(.medium)
                
                Text(region.code.uppercased())
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color(.systemGray6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                isSelected ? Color.blue : (isChanged ? Color.orange : Color.clear), 
                                lineWidth: 2
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Template Category Extension

extension NetworkGroupTemplate.TemplateCategory {
    var icon: String {
        switch self {
        case .development:
            return "hammer.fill"
        case .staging:
            return "testtube.2"
        case .production:
            return "server.rack"
        case .microservices:
            return "cube.transparent"
        case .database:
            return "cylinder.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .development:
            return .orange
        case .staging:
            return .yellow
        case .production:
            return .red
        case .microservices:
            return .purple
        case .database:
            return .green
        }
    }
}

// MARK: - Preview

#Preview {
    CreateNetworkGroupView(
        organizationId: "orga_example",
        onNetworkGroupCreated: { _ in }
    )
    .environment(AppCoordinator())
} 