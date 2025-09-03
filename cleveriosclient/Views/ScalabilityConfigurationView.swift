import SwiftUI
import Combine

/// Revolutionary Scalability Configuration View
/// Transforms basic instance configuration into a complete autoscaling management system
/// following clever-tools patterns with modern SwiftUI interface
struct ScalabilityConfigurationView: View {
    let application: CCApplication
    @ObservedObject var cleverCloudSDK: CleverCloudSDK
    let organizationId: String?
    
    // MARK: - State Management
    
    @State private var scalingStrategy: ScalingStrategy = .fixed
    @State private var selectedPreset: CCScalabilityPreset?
    @State private var validationResult: CCValidationResult?
    @State private var costEstimate: CCCostEstimate?
    @State private var currentConfig: CCScalabilityConfig
    @State private var tempConfig: CCScalabilityConfig
    
    // UI State
    @State private var showingPresets = false
    @State private var showingAdvanced = false
    @State private var isApplying = false
    @State private var applyMessage: String?
    @State private var showingCostDetails = false
    @State private var showingRestartConfirmation = false
    @State private var cancellables = Set<AnyCancellable>()
    
    // Animation State
    @State private var animateValidation = false
    @State private var animateCost = false
    
    // MARK: - Initialization
    
    init(application: CCApplication, cleverCloudSDK: CleverCloudSDK, organizationId: String?) {
        self.application = application
        self.cleverCloudSDK = cleverCloudSDK
        self.organizationId = organizationId
        
        // Initialize configuration from current application state
        let config = CCScalabilityConfig(
            strategy: .fixed,
            flavorScaling: CCFlavorScaling(
                minFlavor: application.instance.minFlavor.name,
                maxFlavor: application.instance.maxFlavor.name,
                enabled: false
            ),
            instanceScaling: CCInstanceScaling(
                minInstances: application.instance.minInstances,
                maxInstances: application.instance.maxInstances,
                enabled: application.instance.minInstances != application.instance.maxInstances
            )
        )
        
        self._currentConfig = State(initialValue: config)
        self._tempConfig = State(initialValue: config)
        self._scalingStrategy = State(initialValue: CCScalabilityService.detectScalingStrategy(config))
    }
    
    // MARK: - Main View
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerSection
                
                // Preset Management
                presetSection
                
                // Scaling Strategy Selector
                strategySection
                
                // Configuration Sections
                configurationSections
                
                // Validation & Cost
                validationSection
                
                // Actions
                actionsSection
                
                Spacer(minLength: 100)
            }
            .padding()
        }
        .navigationTitle("Scalability Configuration")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            validateAndEstimate()
        }
        .sheet(isPresented: $showingPresets) {
            PresetSelectorView(
                application: application,
                selectedPreset: $selectedPreset,
                tempConfig: $tempConfig,
                scalingStrategy: $scalingStrategy
            )
        }
        .sheet(isPresented: $showingCostDetails) {
            CostDetailsView(costEstimate: costEstimate)
        }
        .alert("⚠️ Application Restart Required", isPresented: $showingRestartConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Restart & Apply", role: .destructive) {
                applyConfiguration()
            }
        } message: {
            Text("Changing the flavor/instances requires restarting the application to take effect.\n\nThe application will be unavailable for a few minutes during restart.\n\nProceed?")
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "speedometer")
                    .font(.title)
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading) {
                    Text("Autoscaling Configuration")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Configure intelligent scaling for \(application.name)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            // Current vs New Status
            HStack {
                VStack(alignment: .leading) {
                    Text("Current")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(currentStatusText)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                Image(systemName: "arrow.right")
                    .foregroundColor(.blue)
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("New")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(newStatusText)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                }
            }
            .padding(.vertical, 8)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Preset Section
    
    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Scaling Presets")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Browse Presets") {
                    showingPresets = true
                }
                .font(.subheadline)
                .buttonStyle(.borderedProminent)
            }
            
            if let preset = selectedPreset {
                PresetCardView(preset: preset) {
                    selectedPreset = nil
                    resetToCurrentConfig()
                }
            } else {
                VStack(spacing: 8) {
                    Text("No preset selected")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("Choose a preset for quick configuration or configure manually below")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Strategy Section
    
    private var strategySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Scaling Strategy")
                .font(.headline)
                .fontWeight(.semibold)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                ForEach(ScalingStrategy.allCases, id: \.self) { strategy in
                    StrategyCard(
                        strategy: strategy,
                        isSelected: scalingStrategy == strategy
                    ) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            scalingStrategy = strategy
                            updateConfigurationForStrategy(strategy)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Configuration Sections
    
    private var configurationSections: some View {
        VStack(spacing: 16) {
            // Flavor Scaling Section
            if tempConfig.flavorScaling.enabled {
                FlavorScalingSection(
                    flavorScaling: $tempConfig.flavorScaling,
                    application: application
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            // Instance Scaling Section
            if tempConfig.instanceScaling.enabled {
                InstanceScalingSection(
                    instanceScaling: $tempConfig.instanceScaling,
                    application: application
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: tempConfig.flavorScaling.enabled)
        .animation(.easeInOut(duration: 0.3), value: tempConfig.instanceScaling.enabled)
    }
    
    // MARK: - Validation Section
    
    private var validationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Validation & Cost")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                if let costEstimate = costEstimate {
                    Button(action: {
                        showingCostDetails = true
                    }) {
                        HStack {
                            Text("€\(String(format: "%.2f", costEstimate.monthlyMin))-€\(String(format: "%.2f", costEstimate.monthlyMax))/month")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.green)
                            
                            Image(systemName: "info.circle")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                    .scaleEffect(animateCost ? 1.05 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: animateCost)
                }
            }
            
            if let validation = validationResult {
                ValidationResultView(result: validation)
                    .scaleEffect(animateValidation ? 1.02 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: animateValidation)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .onChange(of: tempConfig) { _, _ in
            validateAndEstimate()
        }
    }
    
    // MARK: - Actions Section
    
    private var actionsSection: some View {
        VStack(spacing: 12) {
            if hasChanges {
                Button(action: {
                    showingRestartConfirmation = true
                }) {
                    HStack {
                        if isApplying {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.white)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                        }
                        
                        Text(isApplying ? "Applying Configuration..." : "Apply Configuration")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isApplying || validationResult?.isValid == false)
            }
            
            if let message = applyMessage {
                Text(message)
                    .font(.caption)
                    .foregroundColor(message.hasPrefix("✅") ? .green : .red)
                    .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private var currentStatusText: String {
        let flavorRange = currentConfig.flavorScaling.minFlavor == currentConfig.flavorScaling.maxFlavor
        ? currentConfig.flavorScaling.minFlavor ?? "S"
        : "\(currentConfig.flavorScaling.minFlavor ?? "S")-\(currentConfig.flavorScaling.maxFlavor ?? "S")"
        
        let instanceRange = currentConfig.instanceScaling.minInstances == currentConfig.instanceScaling.maxInstances
        ? "\(currentConfig.instanceScaling.minInstances ?? 1)"
        : "\(currentConfig.instanceScaling.minInstances ?? 1)-\(currentConfig.instanceScaling.maxInstances ?? 1)"
        
        return "\(flavorRange) × \(instanceRange)"
    }
    
    private var newStatusText: String {
        let flavorRange = tempConfig.flavorScaling.minFlavor == tempConfig.flavorScaling.maxFlavor
        ? tempConfig.flavorScaling.minFlavor ?? "S"
        : "\(tempConfig.flavorScaling.minFlavor ?? "S")-\(tempConfig.flavorScaling.maxFlavor ?? "S")"
        
        let instanceRange = tempConfig.instanceScaling.minInstances == tempConfig.instanceScaling.maxInstances
        ? "\(tempConfig.instanceScaling.minInstances ?? 1)"
        : "\(tempConfig.instanceScaling.minInstances ?? 1)-\(tempConfig.instanceScaling.maxInstances ?? 1)"
        
        return "\(flavorRange) × \(instanceRange)"
    }
    
    private var hasChanges: Bool {
        return tempConfig.flavorScaling.minFlavor != currentConfig.flavorScaling.minFlavor ||
               tempConfig.flavorScaling.maxFlavor != currentConfig.flavorScaling.maxFlavor ||
               tempConfig.instanceScaling.minInstances != currentConfig.instanceScaling.minInstances ||
               tempConfig.instanceScaling.maxInstances != currentConfig.instanceScaling.maxInstances
    }
    
    private func updateConfigurationForStrategy(_ strategy: ScalingStrategy) {
        tempConfig.strategy = strategy
        
        switch strategy {
        case .fixed:
            tempConfig.flavorScaling.enabled = false
            tempConfig.instanceScaling.enabled = false
            
        case .horizontal:
            tempConfig.flavorScaling.enabled = false
            tempConfig.instanceScaling.enabled = true
            
        case .vertical:
            tempConfig.flavorScaling.enabled = true
            tempConfig.instanceScaling.enabled = false
            
        case .fullAuto:
            tempConfig.flavorScaling.enabled = true
            tempConfig.instanceScaling.enabled = true
        }
        
        validateAndEstimate()
    }
    
    private func validateAndEstimate() {
        // Validate configuration
        validationResult = CCScalabilityService.validateScalabilityConfig(tempConfig)
        
        // Estimate costs
        costEstimate = CCScalabilityService.calculateScalingCost(tempConfig)
        
        // Trigger animations
        withAnimation(.easeInOut(duration: 0.3)) {
            animateValidation.toggle()
            animateCost.toggle()
        }
    }
    
    private func resetToCurrentConfig() {
        tempConfig = currentConfig
        scalingStrategy = CCScalabilityService.detectScalingStrategy(currentConfig)
        validateAndEstimate()
    }
    
    private func applyConfiguration() {
        isApplying = true
        applyMessage = nil
        
        Task {
            do {
                // Use the merged parameters from clever-tools logic
                let params = CCScalabilityParams(
                    minFlavor: tempConfig.flavorScaling.minFlavor,
                    maxFlavor: tempConfig.flavorScaling.maxFlavor,
                    minInstances: tempConfig.instanceScaling.minInstances,
                    maxInstances: tempConfig.instanceScaling.maxInstances
                )
                
                // Create instance config from current application data
                let sourceInstanceConfig = CCInstanceConfig(
                    minFlavor: tempConfig.flavorScaling.minFlavor ?? application.instance.minFlavor.name,
                    maxFlavor: tempConfig.flavorScaling.maxFlavor ?? application.instance.maxFlavor.name,
                    minInstances: tempConfig.instanceScaling.minInstances ?? application.instance.minInstances,
                    maxInstances: tempConfig.instanceScaling.maxInstances ?? application.instance.maxInstances
                )
                
                let mergedInstanceConfig = CCScalabilityService.mergeScalabilityParameters(params, instance: sourceInstanceConfig)
                
                // Apply configuration using CCEnvironmentService
                let targetInstanceConfig = CCAppInstanceConfiguration(
                    minInstances: mergedInstanceConfig.minInstances,
                    maxInstances: mergedInstanceConfig.maxInstances,
                    flavor: mergedInstanceConfig.minFlavor
                )
                
                // 🚀 REAL API CALL: Apply configuration using CCEnvironmentService
                let _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CCConfigurationUpdateResponse, Error>) in
                    cleverCloudSDK.environment.updateInstanceConfiguration(
                        for: application.id,
                        instanceConfig: targetInstanceConfig,
                        organizationId: organizationId
                    )
                                            .sink(
                            receiveCompletion: { completion in
                                if case .failure(let error) = completion {
                                    continuation.resume(throwing: error)
                                }
                            },
                            receiveValue: { response in
                                Task { @MainActor in
                                    continuation.resume(returning: response)
                                }
                            }
                        )
                    .store(in: &cancellables)
                }
                
                await MainActor.run {
                    applyMessage = "🚀 Configuration applied! Starting application redeploy..."
                }
                
                // 🔄 AUTO-REDEPLOY: Like clever-tools, automatically redeploy after scaling change
                do {
                    let _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CCDeployment, Error>) in
                        cleverCloudSDK.deployments.redeployApplication(
                            applicationId: application.id,
                            organizationId: organizationId
                        )
                        .sink(
                            receiveCompletion: { completion in
                                if case .failure(let error) = completion {
                                    continuation.resume(throwing: error)
                                }
                            },
                            receiveValue: { deployment in
                                Task { @MainActor in
                                    continuation.resume(returning: deployment)
                                }
                            }
                        )
                        .store(in: &cancellables)
                    }
                    
                    await MainActor.run {
                        // Update configuration
                        currentConfig = tempConfig
                        isApplying = false
                        applyMessage = "✅ Configuration applied and application redeployed successfully!"
                        
                        // Clear message after 5 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                            applyMessage = nil
                        }
                    }
                    
                    // 🔄 FORCE UI REFRESH AFTER REDEPLOY
                    await refreshApplicationData()
                    
                } catch {
                    await MainActor.run {
                        // Even if redeploy fails, the config was applied
                        currentConfig = tempConfig
                        isApplying = false
                        applyMessage = "⚠️ Configuration applied but redeploy failed: \(error.localizedDescription)"
                        
                        // Clear message after 8 seconds for error
                        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
                            applyMessage = nil
                        }
                    }
                    
                    // Still refresh UI even if redeploy failed
                    await refreshApplicationData()
                }
                
            } catch {
                await MainActor.run {
                    isApplying = false
                    applyMessage = "❌ Failed to apply configuration: \(error.localizedDescription)"
                    
                    // Clear error message after 10 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                        applyMessage = nil
                    }
                }
            }
        }
    }
    
    private func refreshApplicationData() async {
        // 🔄 FORCE REFRESH: Reload application data from API to reflect the new scaling configuration
        do {
            // Small delay to allow server to process the update
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            // 🚀 FORCE RELOAD from API
            await MainActor.run {
                // Send multiple refresh notifications to ensure UI updates
                NotificationCenter.default.post(
                    name: NSNotification.Name("RefreshApplicationData"),
                    object: application.id
                )
                
                // Also send global refresh to update application list
                NotificationCenter.default.post(
                    name: NSNotification.Name("RefreshApplicationList"),
                    object: nil
                )
                
                print("🔄 Sent refresh notifications for application: \(application.id)")
            }
            
            // Additional delay and second refresh to ensure data is updated
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 more second
            
            await MainActor.run {
                // Send another round of refresh notifications
                NotificationCenter.default.post(
                    name: NSNotification.Name("RefreshApplicationData"),
                    object: application.id
                )
                
                print("🔄 Sent second refresh notification for application: \(application.id)")
            }
            
        } catch {
            print("🔄 Error during refresh delay: \(error)")
        }
    }
}

// MARK: - Supporting Views

struct StrategyCard: View {
    let strategy: ScalingStrategy
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: strategy.icon)
                        .font(.title2)
                        .foregroundColor(isSelected ? .white : .blue)
                    
                    Spacer()
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.white)
                    }
                }
                
                Text(strategy.displayName)
                    .font(.headline)
                    .foregroundColor(isSelected ? .white : .primary)
                
                Text(strategy.description)
                    .font(.caption)
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                    .multilineTextAlignment(.leading)
            }
            .padding()
            .background(isSelected ? Color.blue : Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

struct PresetCardView: View {
    let preset: CCScalabilityPreset
    let onRemove: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(preset.name)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text(preset.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    Text(preset.category.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(4)
                    
                    Spacer()
                }
            }
            
            Spacer()
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
    }
}

struct ValidationResultView: View {
    let result: CCValidationResult
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if result.isValid {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Configuration is valid")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                }
            } else {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text("Configuration has errors")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.red)
                }
            }
            
            // Show errors
            ForEach(result.errors, id: \.self) { error in
                HStack {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            
            // Show warnings
            ForEach(result.warnings, id: \.self) { warning in
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text(warning)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding()
        .background(result.isValid ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Extensions

extension ScalingStrategy {
    var displayName: String {
        switch self {
        case .fixed: return "Fixed"
        case .horizontal: return "Horizontal"
        case .vertical: return "Vertical"
        case .fullAuto: return "Full Auto"
        }
    }
    
    var description: String {
        switch self {
        case .fixed: return "Fixed configuration, no scaling"
        case .horizontal: return "Scale instances only"
        case .vertical: return "Scale flavor only"
        case .fullAuto: return "Scale both instances and flavor"
        }
    }
    
    var icon: String {
        switch self {
        case .fixed: return "pin.fill"
        case .horizontal: return "arrow.left.and.right"
        case .vertical: return "arrow.up.and.down"
        case .fullAuto: return "arrow.up.and.down.and.arrow.left.and.right"
        }
    }
}

#Preview {
    NavigationView {
        ScalabilityConfigurationView(
            application: CCApplication.sampleApplication,
            cleverCloudSDK: CleverCloudSDK(configuration: CCConfiguration(apiToken: "preview-token")),
            organizationId: "org_123"
        )
    }
} 