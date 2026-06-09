import SwiftUI
import Combine
import Charts

struct AddonDetailView: View {
    let addon: CCAddon
    let organizationId: String?
    let cleverCloudSDK: CleverCloudSDK
    
    // MARK: - iPad Detection
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    
    // Computed property to determine if we're on iPad
    private var isIpad: Bool {
        horizontalSizeClass == .regular && verticalSizeClass == .regular
    }
    
    // MARK: - State
    
    @State private var environmentVariables: [String: String] = [:]
    @State private var linkedApplications: [CCAddonApplicationLink] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedTab = 0
    @State private var isLoadingEnvironment = false
    @State private var envError: String?

    // Logs-related states
    @State private var logs: [CCLogEntry] = []
    @State private var isLoadingLogs = false
    @State private var logsError: String?
    @State private var searchText = ""
    @State private var selectedLogLevel: CCLogLevel? = nil
    @State private var isPaused = false
    @State private var autoScroll = true
    @State private var logsTimer: Timer?  // legacy, no longer used (replaced by `logStream`)
    /// Persistent SSE subscription for the add-on logs. Cancelled on disappear / pause.
    @State private var logStream: AnyCancellable?
    /// Wire-id dedup set — keeps entries unique across reconnects.
    @State private var knownLogIds: Set<String> = []

    /// Hard cap on the rolling buffer; live-tail keeps appending up to this size, oldest drop off.
    private let maxLogsBufferSize = 250
    
    @State private var cancellables = Set<AnyCancellable>()

    // Metrics-related states
    @State private var selectedMetricsPeriod = "PT1H"
    @State private var isLoadingMetrics = false
    @State private var pendingAddonMetricsLoads = 0
    @State private var addonMetricsError: String?
    @State private var addonCpuData: [CCApplicationMetricPoint] = []
    @State private var addonMemData: [CCApplicationMetricPoint] = []

    // Destroy addon state
    @State private var showingDestroyConfirmation = false
    @State private var isDestroying = false
    @State private var destroyConfirmationText = ""
    
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            // Header Section
            addonHeader
            
            // TabView with 4 tabs
            TabView(selection: $selectedTab) {
                // Tab 1: Environment Variables
                environmentVariablesTab
                    .tabItem {
                        Image(systemName: "lock.fill")
                        Text("Environment")
                    }
                    .tag(0)
                
                // Tab 2: Logs (opens full screen)
                logsLauncherTab
                    .tabItem {
                        Image(systemName: "doc.text")
                        Text("Logs")
                    }
                    .tag(1)

                // Tab 3: Configuration
                configurationTab
                    .tabItem {
                        Image(systemName: "gear")
                        Text("Configuration")
                    }
                    .tag(2)

                // Tab 4: Metrics (PostgreSQL, MySQL, Redis only)
                metricsTab
                    .tabItem {
                        Image(systemName: "chart.xyaxis.line")
                        Text("Metrics")
                    }
                    .tag(3)
            }
        }
        .navigationTitle(isIpad ? "" : addon.name)
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            loadAddonData()
        }
        .onDisappear {
            // Belt-and-suspenders: ensure the SSE log stream is torn down when the whole add-on
            // detail leaves the screen (e.g. switching add-ons on iPad), not only when the
            // full-screen logs view is dismissed.
            stopLogsPolling()
        }
    }
    
    // MARK: - Header Section
    
    private var addonHeader: some View {
        VStack(spacing: 16) {
            // Addon Info Row
            HStack(spacing: 16) {
                // Provider Icon & Basic Info
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        // Provider-specific icon
                        Text(providerIcon)
                            .font(.largeTitle)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(addon.name)
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Text(addon.provider.name)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        // Status Badge
                        statusBadge
                    }
                }
            }
            
            // Info Cards Row
            HStack(spacing: 12) {
                AddonInfoCard(
                    icon: "server.rack",
                    title: "Type",
                    value: addon.provider.name,
                    subtitle: addon.plan.name
                )
                
                AddonInfoCard(
                    icon: "location",
                    title: "Region",
                    value: addon.region.uppercased(),
                    subtitle: "Zone"
                )
                
                AddonInfoCard(
                    icon: "dollarsign.circle",
                    title: "Plan",
                    value: addon.plan.name,
                    subtitle: formatPrice(addon.plan.price)
                )
            }
            
            // Quick Actions
            HStack(spacing: 12) {
                Spacer()
                
                AddonActionButton(
                    title: isLoading ? "Refreshing..." : "Refresh",
                    icon: isLoading ? "hourglass" : "arrow.clockwise",
                    color: .blue,
                    isLoading: isLoading
                ) {
                    refreshAddonData()
                }
            }
            
            // Error display
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }
        }
        .padding()
        .background(Color(.systemGray6))
    }
    
    private var providerIcon: String {
        switch addon.provider.id.lowercased() {
        case "postgresql-addon", "postgres":
            return "🐘"
        case "mysql-addon":
            return "🐬"
        case "redis-addon":
            return "🔴"
        case "mongodb-addon", "mongo":
            return "🍃"
        case "elasticsearch-addon":
            return "🔍"
        case "jenkins-addon":
            return "⚙️"
        case "pulsar-addon":
            return "📡"
        case "materia-addon":
            return "🔧"
        default:
            return "📦"
        }
    }
    
    @ViewBuilder
    private var statusBadge: some View {
        if let status = addon.status {
            HStack(spacing: 4) {
                Circle()
                    .fill(colorForStatus(status))
                    .frame(width: 8, height: 8)
                Text(status.capitalized)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(colorForStatus(status).opacity(0.1))
            .cornerRadius(12)
        }
    }
    
    private func colorForStatus(_ status: String) -> Color {
        switch status.lowercased() {
        case "running", "up":
            return .green
        case "creating", "starting":
            return .orange
        case "stopped", "down":
            return .gray
        case "error", "failed":
            return .red
        default:
            return .blue
        }
    }
    
    private func formatPrice(_ price: Double) -> String {
        if price == 0 {
            return "Free"
        }
        return String(format: "€%.2f/mo", price)
    }
    
    // MARK: - Tab 1: Environment Variables
    
    private var environmentVariablesTab: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Environment Variables")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                if !environmentVariables.isEmpty {
                    Button(action: copyAllVariables) {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.on.doc")
                            Text("Copy All")
                        }
                        .font(.subheadline)
                        .fontWeight(.medium)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            
            if isLoadingEnvironment {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Loading environment variables...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if environmentVariables.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "lock.doc")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                    
                    Text("No Environment Variables")
                        .font(.title2)
                        .fontWeight(.medium)
                    
                    Text("This add-on doesn't provide any environment variables")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Variables List
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(environmentVariables.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                            EnvironmentVariableCard(key: key, value: value)
                        }
                        
                        // Usage instructions based on provider
                        usageInstructionsCard
                    }
                    .padding()
                }
            }
        }
    }
    
    private var usageInstructionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Usage Instructions")
                .font(.headline)
                .padding(.top, 8)
            
            Text(usageInstructions)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
                .padding()
                .background(Color(.systemGray5))
                .cornerRadius(8)
        }
    }
    
    private var usageInstructions: String {
        switch addon.provider.id.lowercased() {
        case "postgresql-addon", "postgres":
            return """
            // Node.js example
            const { Client } = require('pg');
            const client = new Client({
              connectionString: process.env.POSTGRESQL_ADDON_URI
            });
            """
        case "mysql-addon":
            return """
            // Node.js example
            const mysql = require('mysql2');
            const connection = mysql.createConnection(
              process.env.MYSQL_ADDON_URI
            );
            """
        case "redis-addon":
            return """
            // Node.js example
            const redis = require('redis');
            const client = redis.createClient({
              url: process.env.REDIS_URL
            });
            """
        case "mongodb-addon", "mongo":
            return """
            // Node.js example
            const { MongoClient } = require('mongodb');
            const client = new MongoClient(
              process.env.MONGODB_ADDON_URI
            );
            """
        default:
            return "Check the add-on documentation for usage instructions."
        }
    }
    
    // MARK: - Tab 2: Logs Launcher

    @State private var showingAddonLogsFullScreen = false

    private var logsLauncherTab: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 50))
                .foregroundColor(.blue)
            Text("View Add-on Logs")
                .font(.title3)
                .fontWeight(.medium)
            Text("\(logs.count) logs loaded")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Button(action: { showingAddonLogsFullScreen = true }) {
                Label("Open Logs", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fullScreenCover(isPresented: $showingAddonLogsFullScreen) {
            addonLogsFullScreen
        }
        // The SSE stream is started/stopped by the full-screen logsTab's onAppear/onDisappear, so it
        // only runs while logs are actually on screen — not merely because this trampoline tab showed.
    }

    private var addonLogsFullScreen: some View {
        NavigationStack {
            logsTab
                .navigationTitle(addon.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { showingAddonLogsFullScreen = false }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
        }
    }

    // MARK: - Logs Content

    private var logsTab: some View {
        VStack(spacing: 0) {
            // Header with controls
            logsHeader
            
            // Logs content
            if isLoadingLogs && logs.isEmpty {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Loading logs...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else if let error = logsError {
                VStack(spacing: 16) {
                    Image(systemName: error.contains("400") || error.contains("404") ? "exclamationmark.octagon" : "exclamationmark.triangle")
                        .font(.system(size: 50))
                        .foregroundColor(error.contains("400") || error.contains("404") ? .red : .orange)
                    
                    Text(error.contains("400") || error.contains("404") ? "Logs Not Available" : "Failed to load logs")
                        .font(.title2)
                        .fontWeight(.medium)
                    
                    if error.contains("400") || error.contains("404") {
                        Text("Unable to fetch logs for this add-on")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Text("The add-on might not support logs via API or has no logs yet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    } else {
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Button("Retry") {
                            startLogsPolling()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredLogs.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: searchText.isEmpty && selectedLogLevel == nil ? "doc.text" : "magnifyingglass")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                    
                    Text(searchText.isEmpty && selectedLogLevel == nil ? "No logs available" : "No matching logs")
                        .font(.title2)
                        .fontWeight(.medium)
                    
                    Text(searchText.isEmpty && selectedLogLevel == nil ? 
                         "Logs will appear here when available" : 
                         "Try adjusting your search or filters")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(filteredLogs) { log in
                                LogEntryView(log: log)
                                    .id(log.id)
                            }
                        }
                        .padding()
                    }
                    .onAppear {
                        if autoScroll, let lastLog = filteredLogs.last {
                            proxy.scrollTo(lastLog.id, anchor: .bottom)
                        }
                    }
                    .onChange(of: logs.count) { oldCount, newCount in
                        if autoScroll, let lastLog = filteredLogs.last {
                            withAnimation {
                                proxy.scrollTo(lastLog.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            startLogsPolling()
        }
        .onDisappear {
            stopLogsPolling()
        }
    }
    
    private var logsHeader: some View {
        VStack(spacing: 12) {
            // Title and controls
            HStack {
                Text("Logs")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                HStack(spacing: 12) {
                    // Auto-scroll toggle
                    Button(action: { autoScroll.toggle() }) {
                        HStack(spacing: 4) {
                            Image(systemName: autoScroll ? "arrow.down.circle.fill" : "arrow.down.circle")
                            Text("Auto-scroll")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(autoScroll ? .blue : .gray)
                    
                    // Pause/Resume button
                    Button(action: togglePause) {
                        HStack(spacing: 4) {
                            Image(systemName: isPaused ? "play.circle.fill" : "pause.circle.fill")
                            Text(isPaused ? "Resume" : "Pause")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(isPaused ? .green : .orange)
                    
                    // Clear logs
                    Button(action: clearLogs) {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(logs.isEmpty)
                    .accessibilityLabel("Clear logs")
                }
            }
            
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search logs...", text: $searchText)
                    .textFieldStyle(.plain)
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(8)
            .background(Color(.systemGray5))
            .cornerRadius(8)
            
            // Filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(
                        title: "All",
                        isSelected: selectedLogLevel == nil,
                        action: { selectedLogLevel = nil }
                    )
                    
                    ForEach(CCLogLevel.allCases, id: \.self) { level in
                        FilterChip(
                            title: level.rawValue.capitalized,
                            isSelected: selectedLogLevel == level,
                            color: colorForLogLevel(level),
                            action: { 
                                selectedLogLevel = selectedLogLevel == level ? nil : level 
                            }
                        )
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
    }
    
    private var filteredLogs: [CCLogEntry] {
        logs.filter { log in
            let matchesSearch = searchText.isEmpty ||
                log.message.localizedCaseInsensitiveContains(searchText)
            let matchesLevel = selectedLogLevel == nil || log.level == selectedLogLevel
            return matchesSearch && matchesLevel
        }
        .sorted { $0.timestamp < $1.timestamp }
    }
    
    private func colorForLogLevel(_ level: CCLogLevel) -> Color {
        switch level {
        case .debug:
            return .gray
        case .info:
            return .blue
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
    
    
    

    // MARK: - Tab 3: Configuration
    
    private var configurationTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Configuration")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.horizontal)
                
                // Plan Information
                VStack(alignment: .leading, spacing: 12) {
                    Text("Plan Details")
                        .font(.headline)
                    
                    HStack {
                        Text("Current Plan:")
                        Spacer()
                        Text(addon.plan.name)
                            .fontWeight(.medium)
                    }
                    
                    HStack {
                        Text("Price:")
                        Spacer()
                        Text(formatPrice(addon.plan.price))
                            .fontWeight(.medium)
                    }
                    
                    if let features = addon.plan.features, !features.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Features:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            ForEach(features, id: \.id) { feature in
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.caption)
                                    Text(feature.name)
                                        .font(.subheadline)
                                    if let value = feature.value {
                                        Spacer()
                                        Text(value)
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)
                
                // SSO Access section removed
                
                // Add-on Info
                VStack(alignment: .leading, spacing: 12) {
                    Text("Add-on Information")
                        .font(.headline)
                    
                    if let description = addon.description {
                        Text(description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Add-on ID:")
                        Spacer()
                        Text(addon.id)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    
                    if let realId = addon.realId {
                        HStack {
                            Text("Real ID:")
                            Spacer()
                            Text(realId)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if let createdAt = addon.createdAt {
                        HStack {
                            Text("Created:")
                            Spacer()
                            Text(formatDate(createdAt))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)
                
                // Danger Zone - Destroy Add-on
                VStack(alignment: .leading, spacing: 16) {
                    Text("⚠️ Danger Zone")
                        .font(.headline)
                        .foregroundColor(.red)
                    
                    Text("Permanently delete this add-on and all its data. This action cannot be undone.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Button(action: {
                        showingDestroyConfirmation = true
                    }) {
                        HStack {
                            Image(systemName: "trash.fill")
                            Text(isDestroying ? "Destroying..." : "Destroy Add-on")
                        }
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.white)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(isDestroying)
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal)
            }
        }
        .alert("Destroy Add-on", isPresented: $showingDestroyConfirmation) {
            TextField("Type add-on name to confirm", text: $destroyConfirmationText)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
            Button("Cancel", role: .cancel) {
                destroyConfirmationText = ""
            }
            Button("Destroy", role: .destructive) {
                destroyAddon()
            }
            .disabled(destroyConfirmationText != addon.name)
        } message: {
            Text("This will permanently delete '\(addon.name)' and all its data.\n\nType the add-on name '\(addon.name)' to confirm.")
        }
    }
    
    // MARK: - Tab 4: Metrics

    private var addonSupportsMetrics: Bool {
        let pid = addon.provider.id.lowercased()
        return pid.contains("postgresql") || pid.contains("mysql") || pid.contains("redis")
    }

    private var metricsTab: some View {
        Group {
            if !addonSupportsMetrics {
                VStack(spacing: 16) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                    Text("Metrics not available")
                        .font(.title3)
                        .fontWeight(.medium)
                    Text("Metrics are available for PostgreSQL, MySQL, and Redis add-ons")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Performance Metrics")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Spacer()

                    Picker("Period", selection: $selectedMetricsPeriod) {
                        Text("1H").tag("PT1H")
                        Text("6H").tag("PT6H")
                        Text("24H").tag("PT24H")
                        Text("7D").tag("P7D")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .frame(width: 200)
                }

                if let error = addonMetricsError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                HStack(spacing: 16) {
                    MetricValueCard(
                        title: "CPU Usage",
                        dataPoint: addonCpuData.last,
                        color: .blue,
                        isLoading: isLoadingMetrics
                    )
                    MetricValueCard(
                        title: "Memory",
                        dataPoint: addonMemData.last,
                        color: .green,
                        isLoading: isLoadingMetrics
                    )
                }
            }
            .padding()
        }
        .onAppear {
            loadAddonMetrics()
        }
        .onChange(of: selectedMetricsPeriod) { _, _ in
            loadAddonMetrics()
        }
            } // else
        } // Group
    }

    private func intervalForAddonPeriod(_ period: String) -> String {
        switch period {
        case "PT1H": return "PT5M"
        case "PT6H": return "PT15M"
        case "PT24H": return "PT1H"
        case "P7D": return "PT6H"
        default: return "PT5M"
        }
    }

    // MARK: - Addon Metrics Loading

    private func loadAddonMetrics() {
        guard let orgId = organizationId else { return }
        let resourceId = addon.realId ?? addon.id

        addonMetricsError = nil
        let metrics: [MetricType] = [.cpuUsage, .memoryUsage]
        pendingAddonMetricsLoads = metrics.count
        isLoadingMetrics = true

        let metricsService = CCApplicationMetricsService(
            httpClient: cleverCloudSDK.httpClient
        )

        for metric in metrics {
            metricsService.getApplicationTimeSeries(
                applicationId: resourceId,
                organizationId: orgId,
                metric: metric,
                interval: intervalForAddonPeriod(selectedMetricsPeriod),
                span: selectedMetricsPeriod,
                totalMemoryMB: 0 // Keep memory as percentage for addons
            )
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        self.addonMetricsError = "Failed to load \(metric.displayName): \(error.localizedDescription)"
                    }
                    self.pendingAddonMetricsLoads -= 1
                    if self.pendingAddonMetricsLoads <= 0 {
                        self.isLoadingMetrics = false
                    }
                },
                receiveValue: { dataPoints in
                    switch metric {
                    case .cpuUsage:
                        self.addonCpuData = dataPoints
                    case .memoryUsage:
                        self.addonMemData = dataPoints
                    default:
                        break
                    }
                }
            )
            .store(in: &cancellables)
        }
    }

    // MARK: - Data Loading

    private func loadAddonData() {
        errorMessage = nil
        
        // Load environment variables
        isLoadingEnvironment = true
        loadEnvironmentVariables()

        // Metrics token will be fetched when metrics tab is accessed
    }
    
    private func loadEnvironmentVariables() {
        // First check if env vars are already in the addon object
        if let envVars = addon.env, !envVars.isEmpty {
            debugLog("✅ Using environment variables from addon object: \(envVars.count) variables")
            self.environmentVariables = envVars
            self.isLoadingEnvironment = false
            return
        }
        
        // If not, try to load from API
        // Try using realId if available, otherwise use regular id
        let addonIdToUse = addon.realId ?? addon.id
        debugLog("🔍 Loading env vars for addon: \(addon.name)")
        debugLog("🔍 Using addon ID: \(addonIdToUse) (realId: \(addon.realId ?? "nil"), id: \(addon.id))")
        
        cleverCloudSDK.addons.getAddonEnvironmentVariables(
            addonId: addonIdToUse,
            organizationId: organizationId
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    debugLog("❌ Failed to load environment variables: \(error)")
                    debugLog("❌ Error details: \(error.localizedDescription)")
                    debugLog("❌ Addon ID: \(self.addon.id)")
                    debugLog("❌ Organization ID: \(self.organizationId ?? "nil")")
                    self.errorMessage = "Failed to load environment variables: \(error.localizedDescription)"
                }
                self.isLoadingEnvironment = false
            },
            receiveValue: { variables in
                debugLog("✅ Loaded \(variables.count) environment variables for addon")
                self.environmentVariables = variables
            }
        )
        .store(in: &cancellables)
    }
    
    private func refreshAddonData() {
        loadAddonData()
    }
    
    // MARK: - Logs Functions

    /// Open the persistent SSE stream of add-on logs. Replaces the "Timer + getAddonLogs" pattern;
    /// the server pushes a short replay on connect then live entries thereafter.
    private func startLogsPolling() {
        guard logStream == nil else { return }
        isLoadingLogs = logs.isEmpty
        logsError = nil

        logStream = cleverCloudSDK.addons.streamAddonLogs(
            addon: addon,
            ownerId: organizationId
        )
        .sink(
            receiveCompletion: { completion in
                self.isLoadingLogs = false
                self.logStream = nil
                if case .failure(let error) = completion {
                    debugLog("❌ Add-on logs stream failed: \(error)")
                    self.logsError = error.localizedDescription
                } else {
                    debugLog("ℹ️ Add-on logs stream closed by server")
                }
            },
            receiveValue: { entry in
                self.isLoadingLogs = false
                self.appendLog(entry)
            }
        )
    }

    private func stopLogsPolling() {
        logStream?.cancel()
        logStream = nil
    }

    private func togglePause() {
        isPaused.toggle()
        if isPaused {
            stopLogsPolling()
        } else {
            startLogsPolling()
        }
    }

    private func clearLogs() {
        logs.removeAll()
        knownLogIds.removeAll()
    }

    private func appendLog(_ entry: CCLogEntry) {
        guard !isPaused else { return }
        guard knownLogIds.insert(entry.id).inserted else { return }
        // Existing UI sorts newest-first via prepend; keep that ordering for source-compat.
        logs.insert(entry, at: 0)
        if logs.count > maxLogsBufferSize {
            let drop = logs.count - maxLogsBufferSize
            for stale in logs.suffix(drop) {
                knownLogIds.remove(stale.id)
            }
            logs.removeLast(drop)
        }
    }
    
    // MARK: - Actions
    
    private func copyAllVariables() {
        let envString = environmentVariables
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "\n")
        
        UIPasteboard.general.string = envString
        
        // Show feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    // MARK: - Destroy Add-on
    
    /// Destroy the add-on permanently
    private func destroyAddon() {
        guard destroyConfirmationText == addon.name else { return }
        
        isDestroying = true
        
        cleverCloudSDK.addons.deleteAddon(addonId: addon.id, organizationId: organizationId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    isDestroying = false
                    
                    if case .failure(let error) = completion {
                        errorMessage = "❌ Failed to destroy add-on: \(error.localizedDescription)"
                        
                        // Clear message after 5 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                            errorMessage = nil
                        }
                    } else {
                        // Navigate back after successful destruction
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            // Send notification to parent to refresh and dismiss
                            NotificationCenter.default.post(
                                name: .addonDestroyed,
                                object: addon.id
                            )
                        }
                    }
                },
                receiveValue: { _ in
                    debugLog("✅ Add-on '\(addon.name)' destroyed successfully")
                }
            )
            .store(in: &cancellables)
        
        // Clear confirmation text
        destroyConfirmationText = ""
    }
    
    

}

// MARK: - Supporting Views

struct EnvironmentVariableCard: View {
    let key: String
    let value: String
    @State private var isCopied = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(key)
                    .font(.system(.subheadline, design: .monospaced))
                    .fontWeight(.medium)
                
                Spacer()
                
                Button(action: copyVariable) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .foregroundColor(isCopied ? .green : .blue)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy \(key)")
            }
            
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(3)
                .truncationMode(.tail)
        }
        .padding()
        .background(Color(.systemGray5))
        .cornerRadius(8)
    }
    
    private func copyVariable() {
        UIPasteboard.general.string = "\(key)=\(value)"
        
        withAnimation {
            isCopied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                isCopied = false
            }
        }
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
}


struct AddonInfoCard: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
            
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.systemGray5))
        .cornerRadius(8)
    }
}

struct AddonActionButton: View {
    let title: String
    let icon: String
    let color: Color
    var isLoading: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: icon)
                }
                Text(title)
                    .fontWeight(.medium)
            }
            .font(.subheadline)
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(color)
            .cornerRadius(8)
        }
        .disabled(isLoading)
    }
}

// MARK: - Log Entry View

struct LogEntryView: View {
    let log: CCLogEntry
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Level icon and color
            Image(systemName: log.level.icon)
                .font(.caption)
                .foregroundColor(colorForLogLevel(log.level))
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 4) {
                // Timestamp and source
                HStack {
                    Text(formatTimestamp(log.timestamp))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if let source = log.source {
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(source)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                
                // Message
                Text(log.message)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray5).opacity(0.5))
        .cornerRadius(8)
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
    
    private func colorForLogLevel(_ level: CCLogLevel) -> Color {
        switch level {
        case .debug:
            return .gray
        case .info:
            return .blue
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
}

// MARK: - Filter Chip View

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    var color: Color = .blue
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption2)
                }
                Text(title)
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? color.opacity(0.2) : Color(.systemGray5))
            .foregroundColor(isSelected ? color : .primary)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? color : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AddonDetailView(
            addon: CCAddon(
                id: "addon_123",
                name: "Production Database",
                description: "PostgreSQL database for production",
                provider: CCAddonProvider(
                    id: "postgresql-addon",
                    name: "PostgreSQL"
                ),
                plan: CCAddonPlan(
                    id: "plan_123",
                    name: "Small",
                    slug: "small",
                    price: 7.0,
                    features: [
                        CCAddonFeature(name: "Storage", value: "10 GB"),
                        CCAddonFeature(name: "RAM", value: "512 MB"),
                        CCAddonFeature(name: "Connections", value: "20")
                    ]
                ),
                region: "par",
                createdAt: Date(),
                status: "running"
            ),
            organizationId: "org_123",
            cleverCloudSDK: CleverCloudSDK(
                configuration: CCConfiguration(
                    consumerKey: "test",
                    consumerSecret: "test"
                )
            )
        )
    }
}
