import SwiftUI

/// Flavor Scaling Section - Vertical Scaling Configuration
struct FlavorScalingSection: View {
    @Binding var flavorScaling: CCFlavorScaling
    let application: CCApplication
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "arrow.up.and.down")
                    .font(.title2)
                    .foregroundColor(.green)
                
                VStack(alignment: .leading) {
                    Text("Vertical Scaling")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("Scale CPU and memory resources")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Enable/Disable toggle
                Toggle("", isOn: $flavorScaling.enabled)
                    .labelsHidden()
            }
            
            if flavorScaling.enabled {
                VStack(spacing: 16) {
                    // Min Flavor Selection
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Minimum Flavor")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        HStack {
                            Text(flavorScaling.minFlavor ?? "S")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.green)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(8)
                            
                            Spacer()
                            
                            Text("Click to change")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color(red: 0.95, green: 0.98, blue: 0.95))
                    .cornerRadius(8)
                    
                    // Max Flavor Selection
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Maximum Flavor")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        HStack {
                            Text(flavorScaling.maxFlavor ?? "S")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.orange)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(8)
                            
                            Spacer()
                            
                            Text("Click to change")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color(red: 0.98, green: 0.95, blue: 0.90))
                    .cornerRadius(8)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .background(Color(red: 0.95, green: 0.95, blue: 0.97))
        .cornerRadius(12)
        .animation(.easeInOut(duration: 0.3), value: flavorScaling.enabled)
    }
}

//#Preview {
//    VStack {
//        FlavorScalingSection(
//            flavorScaling: .constant(CCFlavorScaling(minFlavor: "S", maxFlavor: "L", enabled: true)),
//            application: CCApplication.sampleApplication
//        )
//    }
//    .padding()
//} 