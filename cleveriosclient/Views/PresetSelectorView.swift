import SwiftUI

/// Preset Selector View for Scalability Configuration
/// Provides preset management with categories and quick configuration
struct PresetSelectorView: View {
    let application: CCApplication
    @Binding var selectedPreset: CCScalabilityPreset?
    @Binding var tempConfig: CCScalabilityConfig
    @Binding var scalingStrategy: ScalingStrategy
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: PresetCategory?
    @State private var presets: [CCScalabilityPreset] = []
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Category Filter
                categoryFilterSection
                
                // Presets List
                presetsListSection
            }
            .navigationTitle("Scaling Presets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Clear") {
                        selectedPreset = nil
                        dismiss()
                    }
                    .disabled(selectedPreset == nil)
                }
            }
            .onAppear {
                loadPresets()
            }
        }
    }
    
    // MARK: - Category Filter Section
    
    private var categoryFilterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // All categories
                CategoryChip(
                    title: "All",
                    isSelected: selectedCategory == nil
                ) {
                    selectedCategory = nil
                }
                
                // Individual categories
                ForEach(PresetCategory.allCases, id: \.self) { category in
                    CategoryChip(
                        title: category.rawValue,
                        isSelected: selectedCategory == category
                    ) {
                        selectedCategory = category
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 12)
        .background(Color(red: 0.98, green: 0.98, blue: 1.0))
    }
    
    // MARK: - Presets List Section
    
    private var presetsListSection: some View {
        List {
            ForEach(filteredPresets, id: \.id) { preset in
                PresetRow(
                    preset: preset,
                    isSelected: selectedPreset?.id == preset.id,
                    isApplicable: isPresetApplicable(preset)
                ) {
                    selectPreset(preset)
                }
            }
        }
        .listStyle(.plain)
    }
    
    // MARK: - Helper Methods
    
    private var filteredPresets: [CCScalabilityPreset] {
        if let category = selectedCategory {
            return presets.filter { $0.category == category }
        }
        return presets
    }
    
    private func loadPresets() {
        presets = CCScalabilityService.getDefaultPresets()
    }
    
    private func isPresetApplicable(_ preset: CCScalabilityPreset) -> Bool {
        let appType = application.instance.type.lowercased()
        return preset.applicableTypes.contains(appType) || preset.applicableTypes.isEmpty
    }
    
    private func selectPreset(_ preset: CCScalabilityPreset) {
        selectedPreset = preset
        tempConfig = preset.configuration
        scalingStrategy = preset.configuration.strategy
        dismiss()
    }
}

// MARK: - Supporting Views

struct CategoryChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(isSelected ? .white : .blue)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.blue : Color.blue.opacity(0.1))
                .cornerRadius(20)
        }
        .buttonStyle(.plain)
    }
}

struct PresetRow: View {
    let preset: CCScalabilityPreset
    let isSelected: Bool
    let isApplicable: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(preset.name)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        Text(preset.description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    
                    Spacer()
                    
                    VStack(spacing: 4) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.blue)
                                .font(.title2)
                        }
                        
                        if !isApplicable {
                            Text("N/A")
                                .font(.caption)
                                .foregroundColor(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                }
                
                // Configuration Preview
                PresetConfigurationPreview(configuration: preset.configuration)
                
                // Tags
                if !preset.tags.isEmpty {
                    HStack {
                        ForEach(preset.tags.prefix(3), id: \.self) { tag in
                            Text(tag)
                                .font(.caption)
                                .foregroundColor(.blue)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(4)
                        }
                        
                        if preset.tags.count > 3 {
                            Text("+\(preset.tags.count - 3)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        // Category badge
                        Text(preset.category.rawValue)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(categoryColor(preset.category))
                            .cornerRadius(4)
                    }
                }
            }
            .padding()
            .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
            .cornerRadius(8)
            .opacity(isApplicable ? 1.0 : 0.6)
        }
        .buttonStyle(.plain)
        .disabled(!isApplicable)
    }
    
    private func categoryColor(_ category: PresetCategory) -> Color {
        switch category {
        case .development: return .green
        case .staging: return .orange
        case .production: return .red
        case .highTraffic: return .purple
        case .costOptimized: return .blue
        }
    }
}

struct PresetConfigurationPreview: View {
    let configuration: CCScalabilityConfig
    
    var body: some View {
        HStack(spacing: 16) {
            // Strategy
            HStack(spacing: 4) {
                Image(systemName: configuration.strategy.icon)
                    .font(.caption)
                    .foregroundColor(.blue)
                
                Text(configuration.strategy.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            
            Spacer()
            
            // Flavor Range
            if configuration.flavorScaling.enabled {
                HStack(spacing: 2) {
                    Text("Flavor:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("\(configuration.flavorScaling.minFlavor ?? "S")-\(configuration.flavorScaling.maxFlavor ?? "S")")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                }
            }
            
            // Instance Range
            if configuration.instanceScaling.enabled {
                HStack(spacing: 2) {
                    Text("Instances:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("\(configuration.instanceScaling.minInstances ?? 1)-\(configuration.instanceScaling.maxInstances ?? 1)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color(red: 0.98, green: 0.98, blue: 0.98))
        .cornerRadius(6)
    }
}

#Preview {
    PresetSelectorView(
        application: CCApplication(
            id: "app_123",
            name: "Sample App",
            description: "Sample application",
            zone: "par",
            zoneId: "par_01",
            instance: CCInstance(
                type: "node",
                version: "18",
                variant: nil,
                minInstances: 1,
                maxInstances: 3,
                maxAllowedInstances: 40,
                minFlavor: CCFlavor(
                    name: "S",
                    mem: 1024,
                    cpus: 1,
                    gpus: 0,
                    disk: 1024,
                    price: 0.6,
                    available: true,
                    microservice: false,
                    machine_learning: false,
                    nice: 0,
                    price_id: "s_flavor",
                    memory: nil,
                    cpuFactor: 1.0,
                    memFactor: 1.0
                ),
                maxFlavor: CCFlavor(
                    name: "S",
                    mem: 1024,
                    cpus: 1,
                    gpus: 0,
                    disk: 1024,
                    price: 0.6,
                    available: true,
                    microservice: false,
                    machine_learning: false,
                    nice: 0,
                    price_id: "s_flavor",
                    memory: nil,
                    cpuFactor: 1.0,
                    memFactor: 1.0
                ),
                flavors: nil
            )
        ),
        selectedPreset: .constant(nil),
        tempConfig: .constant(CCScalabilityConfig(
            strategy: .fixed,
            flavorScaling: CCFlavorScaling(),
            instanceScaling: CCInstanceScaling()
        )),
        scalingStrategy: .constant(.fixed)
    )
} 