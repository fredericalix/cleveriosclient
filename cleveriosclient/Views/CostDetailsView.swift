import SwiftUI

/// Cost Details View for Scalability Configuration
/// Provides detailed cost breakdown and estimation
struct CostDetailsView: View {
    let costEstimate: CCCostEstimate?
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    if let cost = costEstimate {
                        // Header
                        costHeaderSection(cost)
                        
                        // Monthly Breakdown
                        monthlyBreakdownSection(cost)
                        
                        // Cost Breakdown
                        costBreakdownSection(cost)
                        
                        // Cost Comparison
                        costComparisonSection(cost)
                        
                        // Tips and Recommendations
                        tipsSection
                    } else {
                        // No cost data
                        noCostDataSection
                    }
                }
                .padding()
            }
            .navigationTitle("Cost Details")
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
    
    // MARK: - Cost Header Section
    
    private func costHeaderSection(_ cost: CCCostEstimate) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "eurosign.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)
            
            VStack(spacing: 8) {
                Text("Estimated Monthly Cost")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("€\(String(format: "%.2f", cost.monthlyMin))")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                    
                    Text("-")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    
                    Text("€\(String(format: "%.2f", cost.monthlyMax))")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                    
                    Text("/month")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Text("Actual cost depends on usage and scaling activity")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .background(Color(red: 0.95, green: 0.98, blue: 0.95))
        .cornerRadius(12)
    }
    
    // MARK: - Monthly Breakdown Section
    
    private func monthlyBreakdownSection(_ cost: CCCostEstimate) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Monthly Breakdown")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                CostBreakdownRow(
                    title: "Minimum Cost",
                    subtitle: "When running at minimum scale",
                    amount: cost.monthlyMin,
                    color: .green
                )
                
                CostBreakdownRow(
                    title: "Maximum Cost",
                    subtitle: "When running at maximum scale",
                    amount: cost.monthlyMax,
                    color: .orange
                )
                
                CostBreakdownRow(
                    title: "Average Cost (estimated)",
                    subtitle: "Typical usage between min and max",
                    amount: (cost.monthlyMin + cost.monthlyMax) / 2.0,
                    color: .blue
                )
            }
        }
        .padding()
        .background(Color(red: 0.98, green: 0.98, blue: 1.0))
        .cornerRadius(12)
    }
    
    // MARK: - Cost Breakdown Section
    
    private func costBreakdownSection(_ cost: CCCostEstimate) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Cost Breakdown")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 8) {
                if let minInstances = cost.breakdown["min_instances"],
                   let maxInstances = cost.breakdown["max_instances"] {
                    
                    HStack {
                        Text("Instance Count:")
                            .font(.subheadline)
                        Spacer()
                        Text("\(Int(minInstances)) - \(Int(maxInstances))")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }
                
                HStack {
                    Text("Billing Model:")
                        .font(.subheadline)
                    Spacer()
                    Text("Pay-per-hour")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                HStack {
                    Text("Currency:")
                        .font(.subheadline)
                    Spacer()
                    Text(cost.currency)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                HStack {
                    Text("Hours per month:")
                        .font(.subheadline)
                    Spacer()
                    Text("720")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
        }
        .padding()
        .background(Color(red: 0.98, green: 0.95, blue: 0.98))
        .cornerRadius(12)
    }
    
    // MARK: - Cost Comparison Section
    
    private func costComparisonSection(_ cost: CCCostEstimate) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Cost Comparison")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                ComparisonRow(
                    title: "Fixed S Instance",
                    subtitle: "1 instance, always running",
                    amount: 0.6 * 24 * 30, // S flavor at €0.6/hour
                    isRecommended: false
                )
                
                ComparisonRow(
                    title: "Your Configuration",
                    subtitle: "Optimized scaling",
                    amount: (cost.monthlyMin + cost.monthlyMax) / 2.0,
                    isRecommended: true
                )
                
                ComparisonRow(
                    title: "Fixed L Instance",
                    subtitle: "1 large instance, always running",
                    amount: 3.4 * 24 * 30, // L flavor at €3.4/hour
                    isRecommended: false
                )
            }
        }
        .padding()
        .background(Color(red: 0.95, green: 0.95, blue: 0.98))
        .cornerRadius(12)
    }
    
    // MARK: - Tips Section
    
    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                
                Text("Cost Optimization Tips")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                TipRow(
                    icon: "arrow.down.circle.fill",
                    title: "Start Small",
                    description: "Begin with minimum configuration and scale up as needed"
                )
                
                TipRow(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Monitor Usage",
                    description: "Review metrics regularly to optimize your scaling configuration"
                )
                
                TipRow(
                    icon: "clock.fill",
                    title: "Development Hours",
                    description: "Scale down during non-business hours for development environments"
                )
                
                TipRow(
                    icon: "cpu.fill",
                    title: "Right-size Flavors",
                    description: "Choose the smallest flavor that meets your performance requirements"
                )
            }
        }
        .padding()
        .background(Color(red: 1.0, green: 0.98, blue: 0.95))
        .cornerRadius(12)
    }
    
    // MARK: - No Cost Data Section
    
    private var noCostDataSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text("No Cost Data Available")
                .font(.headline)
                .fontWeight(.semibold)
            
            Text("Cost estimation is not available for the current configuration. Please ensure your scaling parameters are properly configured.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - Supporting Views

struct CostBreakdownRow: View {
    let title: String
    let subtitle: String
    let amount: Double
    let color: Color
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text("€\(String(format: "%.2f", amount))")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(color)
        }
        .padding()
        .background(Color.white)
        .cornerRadius(8)
    }
}

struct ComparisonRow: View {
    let title: String
    let subtitle: String
    let amount: Double
    let isRecommended: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    if isRecommended {
                        Text("RECOMMENDED")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green)
                            .cornerRadius(4)
                    }
                }
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text("€\(String(format: "%.2f", amount))")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(isRecommended ? .green : .primary)
        }
        .padding()
        .background(isRecommended ? Color.green.opacity(0.1) : Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isRecommended ? Color.green : Color.clear, lineWidth: 2)
        )
        .cornerRadius(8)
    }
}

struct TipRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    CostDetailsView(
        costEstimate: CCCostEstimate(
            monthlyMin: 43.2,
            monthlyMax: 129.6,
            currency: "EUR",
            breakdown: [
                "min_instances": 1,
                "max_instances": 3,
                "min_cost": 43.2,
                "max_cost": 129.6
            ]
        )
    )
} 