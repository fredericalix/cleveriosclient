import SwiftUI
import Combine

@MainActor
struct CreateAddonView: View {
    
    // MARK: - Input Properties
    let selectedOrganization: CCOrganization?
    let onAddonCreated: (() -> Void)?
    
    // MARK: - Environment & State
    
    @State private var addonProviders: [CCAddonProvider] = []
    @State private var isLoadingProviders = false
    @Environment(\.dismiss) private var dismiss
    @Environment(AppCoordinator.self) private var coordinator
    @EnvironmentObject var cleverCloudVM: CleverCloudViewModel
    
    // MARK: - Form State
    
    @State private var addonName = ""
    @State private var selectedProvider: CCAddonProvider?
    @State private var selectedPlan: CCAddonPlan?
    @State private var selectedRegion = "par"
    
    // MARK: - UI State
    
    @State private var isCreating = false
    @State private var showingProviderPicker = false
    @State private var showingPlanPicker = false
    @State private var showingRegionPicker = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var showingConfirmation = false
    @State private var cancellables = Set<AnyCancellable>()
    
    var body: some View {
        NavigationView {
            Form {
                basicInformationSection
                providerConfigurationSection
                planAndRegionSection
            }
            .navigationTitle("Create Add-on")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isCreating ? "Creating..." : "Create") {
                        print("🔥 Create button clicked")
                        showingConfirmation = true
                    }
                    .disabled(!isFormValid || isCreating)
                }
            }
            .onAppear {
                loadAddonProviders()
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage ?? "Unknown error occurred")
            }
            .alert("Confirm Creation", isPresented: $showingConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Create", role: .destructive) {
                    print("🔥 User confirmed - calling createAddon()")
                    createAddon()
                }
            } message: {
                if let provider = selectedProvider, let plan = selectedPlan {
                    Text("Create \(provider.displayNameWithIcon) add-on '\(addonName)' with \(plan.name) plan (\(plan.displayPrice))?")
                } else {
                    Text("Create this add-on?")
                }
            }
        }
    }
    
    // MARK: - Form Sections
    
    private var basicInformationSection: some View {
        Section("Basic Information") {
            TextField("Add-on Name", text: $addonName)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
        }
    }
    
    private var providerConfigurationSection: some View {
        Section("Provider") {
            Button {
                showingProviderPicker = true
            } label: {
                HStack {
                    if let provider = selectedProvider {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(provider.displayNameWithIcon)
                                .foregroundColor(.primary)
                                .font(.headline)
                            
                            Text(provider.shortDesc ?? "Add-on service")
                                .foregroundColor(.secondary)
                                .font(.caption)
                                .multilineTextAlignment(.leading)
                        }
                    } else {
                        Text("Select Provider")
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
            .sheet(isPresented: $showingProviderPicker) {
                AddonProviderPickerView(
                    providers: addonProviders,
                    selectedProvider: $selectedProvider,
                    onProviderSelected: { provider in
                        selectedProvider = provider
                        selectedPlan = nil // Reset plan when provider changes
                    }
                )
            }
        }
    }
    
    private var planAndRegionSection: some View {
        Section("Configuration") {
            // Plan Selection
            Button {
                if selectedProvider != nil {
                    showingPlanPicker = true
                }
            } label: {
                HStack {
                    Text("Plan")
                    Spacer()
                    if let plan = selectedPlan {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(plan.name)
                                .foregroundColor(.primary)
                            Text(plan.displayPrice)
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    } else {
                        Text("Select Plan")
                            .foregroundColor(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .disabled(selectedProvider == nil)
            .sheet(isPresented: $showingPlanPicker) {
                if let provider = selectedProvider {
                    AddonPlanPickerView(
                        plans: provider.plansForRegion(selectedRegion),
                        selectedPlan: $selectedPlan,
                        onPlanSelected: { plan in
                            selectedPlan = plan
                        }
                    )
                }
            }
            
            // Region Selection
            Button {
                showingRegionPicker = true
            } label: {
                HStack {
                    Text("Region")
                    Spacer()
                    Text(selectedRegion.uppercased())
                        .foregroundColor(.primary)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .sheet(isPresented: $showingRegionPicker) {
                AddonRegionPickerView(
                    regions: selectedProvider?.regions ?? [],
                    selectedRegion: $selectedRegion,
                    onRegionSelected: { region in
                        selectedRegion = region
                        selectedPlan = nil // Reset plan when region changes
                    }
                )
            }
        }
    }
    
    
    // MARK: - Form Validation
    
    private var isFormValid: Bool {
        !addonName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        selectedProvider != nil &&
        selectedPlan != nil
    }
    
    // MARK: - Actions
    
    private func loadAddonProviders() {
        isLoadingProviders = true
        
        coordinator.cleverCloudSDK.addons.getAddonProviders()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    isLoadingProviders = false
                    if case .failure(let error) = completion {
                        errorMessage = error.localizedDescription
                        showingError = true
                    }
                },
                receiveValue: { providers in
                    self.addonProviders = providers
                }
            )
            .store(in: &cancellables)
    }
    
    
    private func createAddon() {
        print("🔥 CreateAddonView.createAddon() called")
        guard let provider = selectedProvider,
              let plan = selectedPlan else { 
            print("🔥 CreateAddon FAILED - provider or plan is nil")
            return 
        }
        
        isCreating = true
        
        let request = CCAddonCreationRequest(
            name: addonName.trimmingCharacters(in: .whitespacesAndNewlines),
            plan: plan.id,
            providerId: provider.id,
            region: selectedRegion
        )
        
        print("🔥 Plan ID being used: '\(plan.id)'")
        print("🔥 Available plans for \(provider.name):")
        for availablePlan in provider.plansForRegion(selectedRegion) {
            print("🔥   - \(availablePlan.name) (id: '\(availablePlan.id)', slug: '\(availablePlan.slug)', price: \(availablePlan.price))")
        }
        
        let organizationId = selectedOrganization?.id
        
        coordinator.cleverCloudSDK.addons
            .createAddon(request: request, organizationId: organizationId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    isCreating = false
                    if case .failure(let error) = completion {
                        errorMessage = error.localizedDescription
                        showingError = true
                    }
                },
                receiveValue: { _ in
                    print("✅ Add-on created successfully!")
                    // Trigger refresh in parent view
                    onAddonCreated?()
                    dismiss()
                }
            )
            .store(in: &cancellables)
    }
}

// MARK: - Provider Picker

struct AddonProviderPickerView: View {
    let providers: [CCAddonProvider]
    @Binding var selectedProvider: CCAddonProvider?
    let onProviderSelected: (CCAddonProvider) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                ForEach(providers.filter { $0.comingSoon != true }) { provider in
                    Button {
                        onProviderSelected(provider)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(provider.displayNameWithIcon)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                if selectedProvider?.id == provider.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                            
                            Text(provider.safeShortDesc)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.leading)
                            
                            if let plans = provider.plans, !plans.isEmpty {
                                Text("\(plans.count) plans available")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Add-on Provider")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Plan Picker

struct AddonPlanPickerView: View {
    let plans: [CCAddonPlan]
    @Binding var selectedPlan: CCAddonPlan?
    let onPlanSelected: (CCAddonPlan) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                ForEach(plans) { plan in
                    Button {
                        onPlanSelected(plan)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(plan.name)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(plan.displayPrice)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                    
                                    if selectedPlan?.id == plan.id {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                            
                            if let memory = plan.displayMemory {
                                Text(memory)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            if let disk = plan.displayDisk {
                                Text(disk)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            let featuresStrings = plan.featuresStrings
                            if !featuresStrings.isEmpty {
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(featuresStrings.prefix(3), id: \.self) { feature in
                                        HStack {
                                            Text("•")
                                            Text(feature)
                                        }
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    }
                                    
                                    if featuresStrings.count > 3 {
                                        Text("and \(featuresStrings.count - 3) more...")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Region Picker

struct AddonRegionPickerView: View {
    let regions: [String]
    @Binding var selectedRegion: String
    let onRegionSelected: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                ForEach(regions, id: \.self) { region in
                    Button {
                        onRegionSelected(region)
                        dismiss()
                    } label: {
                        HStack {
                            Text(region.uppercased())
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            if selectedRegion == region {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Region")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Helpers

extension CreateAddonView {
    func loadData() {
        loadAddonProviders()
    }
}

#Preview {
    let coordinator = AppCoordinator()
    let cleverCloudVM = CleverCloudViewModel(cleverCloudSDK: coordinator.cleverCloudSDK)
    
    return CreateAddonView(selectedOrganization: nil, onAddonCreated: nil)
        .environment(coordinator)
        .environmentObject(cleverCloudVM)
}