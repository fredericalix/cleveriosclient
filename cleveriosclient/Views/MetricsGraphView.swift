import SwiftUI
import Charts
import Combine
import Foundation

// Note: Types CCApplicationMetricPoint and MetricType are defined in CCApplicationMetricsService

/// Reusable metrics graph component with SwiftUI Charts
public struct MetricsGraphView: View {
    
    // MARK: - Properties
    
    let title: String
    let dataPoints: [CCApplicationMetricPoint]
    let metricType: MetricType
    let isLoading: Bool
    let period: String
    
    @State private var selectedDataPoint: CCApplicationMetricPoint?
    @State private var showDetails = false
    
    // MARK: - Initialization
    
    public init(
        title: String,
        dataPoints: [CCApplicationMetricPoint],
        metricType: MetricType,
        isLoading: Bool = false,
        period: String = "Last 24h"
    ) {
        self.title = title
        self.dataPoints = dataPoints
        self.metricType = metricType
        self.isLoading = isLoading
        self.period = period
    }
    
    // MARK: - Body
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            headerView
            
            // Chart or Loading State
            chartContentView
                .frame(height: 200)
            
            // Footer with stats
            if !dataPoints.isEmpty && !isLoading {
                footerView
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(colorForMetric)
                        .frame(width: 8, height: 8)
                    
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                
                Text(period)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Current value
            if let latestPoint = dataPoints.last, !isLoading {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(latestPoint.formattedValue)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(colorForMetric)
                    
                    Text("Current")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    // MARK: - Chart Content
    
    @ViewBuilder
    private var chartContentView: some View {
        if isLoading {
            loadingView
        } else if dataPoints.isEmpty {
            emptyStateView
        } else {
            chartView
        }
    }
    
    private var loadingView: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(1.2)
                Text("Loading metrics...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }
    
    private var emptyStateView: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text("No data available")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }
    
    private var chartView: some View {
        Chart(dataPoints, id: \.id) { dataPoint in
            LineMark(
                x: .value("Time", dataPoint.timestamp),
                y: .value("Value", dataPoint.value)
            )
            .foregroundStyle(colorForMetric.gradient)
            .lineStyle(StrokeStyle(lineWidth: 2.5))
            
            AreaMark(
                x: .value("Time", dataPoint.timestamp),
                y: .value("Value", dataPoint.value)
            )
            .foregroundStyle(
                colorForMetric.opacity(0.1).gradient
            )
            
            if let selectedPoint = selectedDataPoint,
               selectedPoint.id == dataPoint.id {
                PointMark(
                    x: .value("Time", dataPoint.timestamp),
                    y: .value("Value", dataPoint.value)
                )
                .foregroundStyle(colorForMetric)
                .symbolSize(80)
                
                RuleMark(x: .value("Time", dataPoint.timestamp))
                    .foregroundStyle(colorForMetric.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                    .annotation(position: .top, alignment: .center) {
                        VStack(alignment: .center, spacing: 2) {
                            Text(dataPoint.formattedValue)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            
                            Text(formatTimestamp(dataPoint.timestamp))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white)
                        .cornerRadius(6)
                        .shadow(radius: 2)
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 4)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted)))
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let doubleValue = value.as(Double.self) {
                        Text(formatAxisValue(doubleValue))
                    }
                }
            }
        }
        .chartBackground { chartProxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        handleChartTap(at: location, geometry: geometry, proxy: chartProxy)
                    }
            }
        }
    }
    
    // MARK: - Footer
    
    private var footerView: some View {
        HStack(spacing: 20) {
            // Min Value
            StatView(
                title: "Min",
                value: formatValue(minValue),
                color: .secondary
            )
            
            // Average Value
            StatView(
                title: "Avg",
                value: formatValue(averageValue),
                color: colorForMetric
            )
            
            // Max Value
            StatView(
                title: "Max",
                value: formatValue(maxValue),
                color: .secondary
            )
            
            Spacer()
            
            // Trend indicator
            trendIndicator
        }
        .padding(.top, 8)
    }
    
    // MARK: - Helper Views
    
    private struct StatView: View {
        let title: String
        let value: String
        let color: Color
        
        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(color)
            }
        }
    }
    
    private var trendIndicator: some View {
        HStack(spacing: 4) {
            Image(systemName: trendIcon)
                .font(.caption)
                .foregroundColor(trendColor)
            
            Text(trendText)
                .font(.caption2)
                .foregroundColor(trendColor)
        }
    }
    
    // MARK: - Computed Properties
    
    private var colorForMetric: Color {
        switch metricType {
        case .cpuUsage: return .blue
        case .memoryUsage: return .green
        case .networkIn: return .orange
        case .networkOut: return .red
        case .requestCount: return .purple
        case .responseTime: return .yellow
        }
    }
    
    private var minValue: Double {
        dataPoints.map(\.value).min() ?? 0
    }
    
    private var maxValue: Double {
        dataPoints.map(\.value).max() ?? 0
    }
    
    private var averageValue: Double {
        guard !dataPoints.isEmpty else { return 0 }
        return dataPoints.map(\.value).reduce(0, +) / Double(dataPoints.count)
    }
    
    private var trendIcon: String {
        guard dataPoints.count >= 2 else { return "minus" }
        
        let firstHalf = dataPoints.prefix(dataPoints.count / 2).map(\.value).reduce(0, +)
        let secondHalf = dataPoints.suffix(dataPoints.count / 2).map(\.value).reduce(0, +)
        
        if secondHalf > firstHalf * 1.1 {
            return "arrow.up"
        } else if secondHalf < firstHalf * 0.9 {
            return "arrow.down"
        } else {
            return "minus"
        }
    }
    
    private var trendColor: Color {
        switch trendIcon {
        case "arrow.up": return metricType == .responseTime ? .red : .green
        case "arrow.down": return metricType == .responseTime ? .green : .red
        default: return .secondary
        }
    }
    
    private var trendText: String {
        switch trendIcon {
        case "arrow.up": return metricType == .responseTime ? "Slower" : "Rising"
        case "arrow.down": return metricType == .responseTime ? "Faster" : "Falling"
        default: return "Stable"
        }
    }
    
    // MARK: - Helper Methods
    
    private func handleChartTap(at location: CGPoint, geometry: GeometryProxy, proxy: ChartProxy) {
        guard let timestamp = proxy.value(atX: location.x, as: Date.self) else { return }
        
        // Find closest data point
        let closestPoint = dataPoints.min { point1, point2 in
            abs(point1.timestamp.timeIntervalSince(timestamp)) < abs(point2.timestamp.timeIntervalSince(timestamp))
        }
        
        selectedDataPoint = closestPoint
        
        // Auto-hide selection after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if selectedDataPoint?.id == closestPoint?.id {
                selectedDataPoint = nil
            }
        }
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatValue(_ value: Double) -> String {
        switch metricType {
        case .cpuUsage:
            return String(format: "%.1f%%", value)
        case .memoryUsage:
            let mbValue = value / 1024 / 1024
            if mbValue >= 1024 {
                return String(format: "%.1f GB", mbValue / 1024)
            } else if mbValue >= 1 {
                return String(format: "%.0f MB", mbValue)
            } else {
                return String(format: "%.0f KB", value / 1024)
            }
        case .networkIn, .networkOut:
            return String(format: "%.1f KB/s", value / 1024)
        case .requestCount:
            return String(format: "%.0f", value)
        case .responseTime:
            return String(format: "%.0f ms", value)
        }
    }
    
    private func formatAxisValue(_ value: Double) -> String {
        switch metricType {
        case .cpuUsage:
            return "\(Int(value))%"
        case .memoryUsage:
            let mbValue = value / 1024 / 1024
            if mbValue >= 1024 {
                return String(format: "%.1fG", mbValue / 1024)
            } else if mbValue >= 1 {
                return "\(Int(mbValue))M"
            } else {
                return "\(Int(value / 1024))K"
            }
        case .networkIn, .networkOut:
            return "\(Int(value / 1024))K"
        case .requestCount:
            return "\(Int(value))"
        case .responseTime:
            return "\(Int(value))ms"
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            // CPU Usage Chart - No data
            MetricsGraphView(
                title: "CPU Usage",
                dataPoints: [],
                metricType: .cpuUsage,
                period: "Last 24 hours"
            )
            
            // Memory Usage Chart - No data
            MetricsGraphView(
                title: "Memory Usage", 
                dataPoints: [],
                metricType: .memoryUsage,
                period: "Last 24 hours"
            )
            
            // Loading State
            MetricsGraphView(
                title: "Network In",
                dataPoints: [],
                metricType: .networkIn,
                isLoading: true
            )
        }
        .padding()
    }
} 