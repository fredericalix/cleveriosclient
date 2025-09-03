import SwiftUI
import Combine

// MARK: - EditNetworkGroupView
/// Revolutionary Network Group editing interface with pre-filled data and real-time validation
struct EditNetworkGroupView: View {
    
    // MARK: - Environment
    @Environment(\.dismiss) private var dismiss
    @Environment(AppCoordinator.self) private var coordinator: AppCoordinator
    
    // MARK: - Properties
    let organizationId: String
    let networkGroup: CCNetworkGroup
    let onNetworkGroupUpdated: (CCNetworkGroup) -> Void
    
    // MARK: - State
    @State private var networkGroupName = ""
    @State private var networkGroupDescription = ""
    @State private var selectedCIDR = ""
    @State private var customCIDR = ""
    @State private var selectedRegion = ""
    @State private var isUpdating = false
    @State private var validationErrors: [String] = []
    @State private var errorMessage: String?
    @State private var showingCIDRWarning = false
    @State private var cancellables = Set<AnyCancellable>()
    
    // Validation state
    @State private var isNameValid = false
    @State private var isCIDRValid = false
    @State private var cidrValidationMessage = ""
    @State private var hasChanges = false
    
    // Original values for comparison
    private var originalName: String
    private var originalDescription: String?
    private var originalCIDR: String?
    private var originalRegion: String?
    
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
    
    // MARK: - Initializer
    init(
        organizationId: String, 
        networkGroup: CCNetworkGroup, 
        onNetworkGroupUpdated: @escaping (CCNetworkGroup) -> Void
    ) {
        self.organizationId = organizationId
        self.networkGroup = networkGroup
        self.onNetworkGroupUpdated = onNetworkGroupUpdated
        
        // Store original values
        self.originalName = networkGroup.name
        self.originalDescription = networkGroup.description
        self.originalCIDR = networkGroup.cidr
        self.originalRegion = networkGroup.region
    }
    
    // MARK: - Body
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerView
                    
                    // Network Group Information
                    networkGroupInfoSection
                    
                    // Network Configuration
                    networkConfigurationSection
                    
                    // Region Selection
                    regionSelectionSection
                    
                    // CIDR Warning if changes detected
                    if showingCIDRWarning {
                        cidrWarningSection
                    }
                    
                    // Validation Summary
                    if !validationErrors.isEmpty {
                        validationSummarySection
                    }
                    
                    // Action Buttons
                    actionButtons
                }
                .padding()
            }
            .navigationTitle("Edit Network Group")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if hasChanges {
                        Button("Reset") {
                            resetToOriginalValues()
                        }
                        .foregroundColor(.orange)
                    }
                }
            }
            .alert("Update Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("CIDR Change Warning", isPresented: $showingCIDRWarning) {
                Button("Cancel", role: .cancel) {
                    // Reset CIDR to original value
                    if let originalCIDR = originalCIDR {
                        if predefinedCIDRs.contains(originalCIDR) {
                            selectedCIDR = originalCIDR
                            customCIDR = ""
                        } else {
                            selectedCIDR = "Custom"
                            customCIDR = originalCIDR
                        }
                    }
                }
                Button("Continue", role: .destructive) {
                    // Allow CIDR change
                }
            } message: {
                Text("Changing the CIDR of an existing network group may disrupt connected applications and services. This action cannot be undone easily.")
            }
            .onAppear {
                setupInitialValues()
                setupValidation()
            }
            .onChange(of: networkGroupName) { _, newValue in
                validateName(newValue)
                updateHasChanges()
            }
            .onChange(of: networkGroupDescription) { _, _ in
                updateHasChanges()
            }
            .onChange(of: selectedCIDR) { _, _ in
                let cidr = selectedCIDR == "Custom" ? customCIDR : selectedCIDR
                validateCIDR(cidr)
                checkCIDRChange()
                updateHasChanges()
            }
            .onChange(of: customCIDR) { _, _ in
                if selectedCIDR == "Custom" {
                    validateCIDR(customCIDR)
                    checkCIDRChange()
                    updateHasChanges()
                }
            }
            .onChange(of: selectedRegion) { _, _ in
                updateHasChanges()
            }
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "network")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Edit Network Group")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("Modify network configuration and settings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Status indicator
                HStack {
                    Circle()
                        .fill(Color(networkGroup.statusColor))
                        .frame(width: 8, height: 8)
                    Text(networkGroup.status ?? "Unknown")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if isUpdating {
                VStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(LinearProgressViewStyle())
                    
                    Text("Updating network group...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
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
                                    isNameValid ? (hasNameChanged ? Color.orange : Color.green) : Color.red,
                                    lineWidth: 1
                                )
                        )
                    
                    if !networkGroupName.isEmpty && !isNameValid {
                        Text("Name must be at least 3 characters")
                            .font(.caption)
                            .foregroundColor(.red)
                    } else if hasNameChanged && isNameValid {
                        Text("Name has been modified")
                            .font(.caption)
                            .foregroundColor(.orange)
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
                .textInputAutocapitalization(.never)
                        .lineLimit(3)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    hasDescriptionChanged ? Color.orange : Color.clear,
                                    lineWidth: 1
                                )
                        )
                    
                    if hasDescriptionChanged {
                        Text("Description has been modified")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
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
            HStack {
                Text("Network Configuration")
                    .font(.headline)
                
                Spacer()
                
                if hasCIDRChanged {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                }
            }
            
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
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.systemGray6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(hasCIDRChanged ? Color.orange : Color.clear, lineWidth: 1)
                            )
                    )
                    
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
                                            isCIDRValid ? (hasCIDRChanged ? Color.orange : Color.green) : Color.red,
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
                    
                    if hasCIDRChanged {
                        Text("⚠️ CIDR change may affect connected services")
                            .font(.caption)
                            .foregroundColor(.orange)
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
            HStack {
                Text("Region")
                    .font(.headline)
                
                Spacer()
                
                if hasRegionChanged {
                    Text("Modified")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(availableRegions) { region in
                        RegionCard(
                            region: region,
                            isSelected: selectedRegion == region.code,
                            isChanged: hasRegionChanged && selectedRegion == region.code
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
    
    // MARK: - CIDR Warning Section
    
    private var cidrWarningSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("CIDR Change Warning")
                    .font(.headline)
                    .foregroundColor(.orange)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Changing the network CIDR may:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                VStack(alignment: .leading, spacing: 4) {
                    Label("Disconnect existing applications", systemImage: "app.badge")
                        .font(.caption)
                    Label("Affect external peers", systemImage: "globe")
                        .font(.caption)
                    Label("Require WireGuard config updates", systemImage: "gear")
                        .font(.caption)
                    Label("Cause service interruption", systemImage: "exclamationmark.circle")
                        .font(.caption)
                }
                .foregroundColor(.orange)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }
    
    // MARK: - Validation Summary Section
    
    private var validationSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text("Validation Issues")
                    .font(.headline)
                    .foregroundColor(.red)
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
        .background(Color.red.opacity(0.1))
        .cornerRadius(12)
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Update Button
            Button(action: updateNetworkGroup) {
                HStack {
                    if isUpdating {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    
                    Text(isUpdating ? "Updating..." : "Update Network Group")
                        .fontWeight(.medium)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    canUpdateNetworkGroup ? Color.blue : Color.gray
                )
                .cornerRadius(12)
            }
            .disabled(!canUpdateNetworkGroup || isUpdating)
            
            // Reset Button
            if hasChanges {
                Button(action: resetToOriginalValues) {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset Changes")
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.orange)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.orange, lineWidth: 1)
                    )
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var canUpdateNetworkGroup: Bool {
        return isNameValid && isCIDRValid && validationErrors.isEmpty && hasChanges
    }
    
    private var effectiveCIDR: String {
        return selectedCIDR == "Custom" ? customCIDR : selectedCIDR
    }
    
    private var hasNameChanged: Bool {
        return networkGroupName != originalName
    }
    
    private var hasDescriptionChanged: Bool {
        return networkGroupDescription != (originalDescription ?? "")
    }
    
    private var hasCIDRChanged: Bool {
        return effectiveCIDR != (originalCIDR ?? "")
    }
    
    private var hasRegionChanged: Bool {
        return selectedRegion != (originalRegion ?? "")
    }
    
    // MARK: - Methods
    
    private func setupInitialValues() {
        // Set initial values from network group
        networkGroupName = networkGroup.name
        networkGroupDescription = networkGroup.description ?? ""
        
        // Set CIDR
        if let cidr = networkGroup.cidr {
            if predefinedCIDRs.contains(cidr) {
                selectedCIDR = cidr
                customCIDR = ""
            } else {
                selectedCIDR = "Custom"
                customCIDR = cidr
            }
        } else {
            selectedCIDR = "10.0.0.0/24"
            customCIDR = ""
        }
        
        // Set region
        selectedRegion = networkGroup.region ?? "par"
    }
    
    private func setupValidation() {
        // Initial validation
        validateName(networkGroupName)
        let cidr = selectedCIDR == "Custom" ? customCIDR : selectedCIDR
        validateCIDR(cidr)
        updateHasChanges()
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
    
    private func updateHasChanges() {
        hasChanges = hasNameChanged || hasDescriptionChanged || hasCIDRChanged || hasRegionChanged
    }
    
    private func checkCIDRChange() {
        if hasCIDRChanged && originalCIDR != nil {
            showingCIDRWarning = true
        }
    }
    
    private func resetToOriginalValues() {
        networkGroupName = originalName
        networkGroupDescription = originalDescription ?? ""
        
        if let originalCIDR = originalCIDR {
            if predefinedCIDRs.contains(originalCIDR) {
                selectedCIDR = originalCIDR
                customCIDR = ""
            } else {
                selectedCIDR = "Custom"
                customCIDR = originalCIDR
            }
        } else {
            selectedCIDR = "10.0.0.0/24"
            customCIDR = ""
        }
        
        selectedRegion = originalRegion ?? "par"
        
        // Reset validation
        setupValidation()
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
    
    private func updateNetworkGroup() {
        guard canUpdateNetworkGroup else { return }
        
        isUpdating = true
        errorMessage = nil
        
        let networkGroupUpdate = CCNetworkGroupUpdate(
            name: networkGroupName,
            description: networkGroupDescription.isEmpty ? nil : networkGroupDescription,
            cidr: hasCIDRChanged ? effectiveCIDR : nil, // Only send CIDR if changed
            region: hasRegionChanged ? selectedRegion : nil // Only send region if changed
        )
        
        coordinator.cleverCloudSDK.networkGroups.updateNetworkGroup(
            organizationId: organizationId,
            networkGroupId: networkGroup.id,
            networkGroupUpdate: networkGroupUpdate
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { completion in
                isUpdating = false
                if case .failure(let error) = completion {
                    errorMessage = "Failed to update network group: \(error.localizedDescription)"
                }
            },
            receiveValue: { updatedNetworkGroup in
                print("✅ Network group updated successfully: \(updatedNetworkGroup.name)")
                onNetworkGroupUpdated(updatedNetworkGroup)
                dismiss()
            }
        )
        .store(in: &cancellables)
    }
}

// MARK: - RegionCard is defined in CreateNetworkGroupView.swift with extended functionality

// MARK: - CCNetworkGroupUpdate is now defined in CCNetworkGroup.swift

// MARK: - Preview

#Preview {
    EditNetworkGroupView(
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
        onNetworkGroupUpdated: { _ in }
    )
    .environment(AppCoordinator())
} 