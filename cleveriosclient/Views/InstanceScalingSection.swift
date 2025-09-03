import SwiftUI

/// Instance Scaling Section - Horizontal Scaling Configuration
/// Manages min/max instance count selection with intelligent validation
struct InstanceScalingSection: View {
    @Binding var instanceScaling: CCInstanceScaling
    let application: CCApplication
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "arrow.left.and.right")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading) {
                    Text("Horizontal Scaling")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("Scale number of instances")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Enable/Disable toggle
                Toggle("", isOn: $instanceScaling.enabled)
                    .labelsHidden()
            }
            
            if instanceScaling.enabled {
                VStack(spacing: 16) {
                    // Min Instances Slider
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Minimum Instances")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Spacer()
                            
                            Text("\(instanceScaling.minInstances ?? 1)")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.green)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(8)
                        }
                        
                        Slider(
                            value: Binding(
                                get: { Double(instanceScaling.minInstances ?? 1) },
                                set: { newValue in
                                    let intValue = Int(newValue)
                                    instanceScaling.minInstances = intValue
                                    
                                    // Auto-adjust max if needed
                                    if let maxInstances = instanceScaling.maxInstances,
                                       intValue > maxInstances {
                                        instanceScaling.maxInstances = intValue
                                    }
                                }
                            ),
                            in: 1...Double(application.instance.maxAllowedInstances),
                            step: 1
                        )
                        .accentColor(.green)
                    }
                    .padding()
                    .background(Color(red: 0.95, green: 0.98, blue: 0.95))
                    .cornerRadius(8)
                    
                    // Max Instances Slider
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Maximum Instances")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Spacer()
                            
                            Text("\(instanceScaling.maxInstances ?? 1)")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.orange)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(8)
                        }
                        
                        Slider(
                            value: Binding(
                                get: { Double(instanceScaling.maxInstances ?? 1) },
                                set: { newValue in
                                    let intValue = Int(newValue)
                                    instanceScaling.maxInstances = intValue
                                    
                                    // Auto-adjust min if needed
                                    if let minInstances = instanceScaling.minInstances,
                                       intValue < minInstances {
                                        instanceScaling.minInstances = intValue
                                    }
                                }
                            ),
                            in: Double(instanceScaling.minInstances ?? 1)...Double(application.instance.maxAllowedInstances),
                            step: 1
                        )
                        .accentColor(.orange)
                    }
                    .padding()
                    .background(Color(red: 0.98, green: 0.95, blue: 0.90))
                    .cornerRadius(8)
                    
                    // Instance Range Display
                    if let minInstances = instanceScaling.minInstances,
                       let maxInstances = instanceScaling.maxInstances {
                        InstanceRangeView(minInstances: minInstances, maxInstances: maxInstances)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .background(Color(red: 0.95, green: 0.95, blue: 0.97))
        .cornerRadius(12)
        .animation(.easeInOut(duration: 0.3), value: instanceScaling.enabled)
    }
}

struct InstanceRangeView: View {
    let minInstances: Int
    let maxInstances: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scaling Range")
                .font(.subheadline)
                .fontWeight(.medium)
            
            HStack {
                // Min Instances
                VStack(spacing: 4) {
                    Text("\(minInstances)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                    
                    Text("MIN")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                
                // Arrow
                Image(systemName: "arrow.right")
                    .foregroundColor(.blue)
                
                // Max Instances
                VStack(spacing: 4) {
                    Text("\(maxInstances)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                    
                    Text("MAX")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
            
            // Cost Information
            HStack {
                Text("Estimated Cost:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("€\(String(format: "%.2f", calculateEstimatedCost()))/month")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.green)
            }
        }
    }
    
    private func calculateEstimatedCost() -> Double {
        // Simple cost calculation based on instance count
        // Assuming average S flavor cost of €0.6/hour
        let avgHourlyCost = 0.6
        let avgInstances = Double(minInstances + maxInstances) / 2.0
        return avgHourlyCost * avgInstances * 24 * 30 // Monthly estimate
    }
}

#Preview {
    VStack {
        InstanceScalingSection(
            instanceScaling: .constant(CCInstanceScaling(minInstances: 1, maxInstances: 3, enabled: true)),
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
            )
        )
    }
    .padding()
} 