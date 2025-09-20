import SwiftUI
import Combine
import os.log

struct ApplicationDetailView: View {
    @State var application: CCApplication // 🎯 CRITICAL FIX: Changed from 'let' to '@State var' so we can update it!
    @ObservedObject var cleverCloudSDK: CleverCloudSDK
    let organizationId: String?
    
    // MARK: - iPad Detection
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(\.presentationMode) var presentationMode
    
    // Computed property to determine if we're on iPad
    private var isIpad: Bool {
        horizontalSizeClass == .regular && verticalSizeClass == .regular
    }
    
    // MARK: - State
    
    @State private var environmentVariables: [CCEnvironmentVariable] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingAddVariable = false
    @State private var selectedTab = 0
    
    // New variable form
    @State private var newVariableName = ""
    @State private var newVariableValue = ""
    @State private var isSecret = false
    
    @State private var cancellables = Set<AnyCancellable>()
    
    // Application actions state
    @State private var isStarting = false
    @State private var isStopping = false
    @State private var isRestarting = false
    @State private var isRedeploying = false
    @State private var actionMessage: String?
    @State private var showingDeleteConfirmation = false
    
    // Real status tracking
    @State private var applicationStatus = "Loading..."
    @State private var applicationInstances: [CCApplicationInstance] = []
    @State private var lastStatusUpdate = Date()
    
    // Logs-related state
    @State private var selectedDeploymentSection = 0 // 0: Deployments, 1: Logs
    @State private var logs: [CCLogEntry] = []
    @State private var isLoadingLogs = false
    @State private var logsError: String?
    @State private var searchText = ""
    @State private var selectedLogLevel: CCLogLevel? = nil
    @State private var isPaused = false
    @State private var autoScroll = true
    @State private var logsTimer: Timer?

    // Deployment-related state
    @State private var deployments: [CCDeployment] = []
    @State private var isLoadingDeployments = false
    @State private var deploymentsError: String?
    
    // Configuration state
    @State private var availableFlavors: [CCFlavor] = []
    @State private var isLoadingFlavors = false
    @State private var selectedFlavor: CCFlavor?
    @State private var currentApplicationFlavor: CCFlavor?
    @State private var tempMinInstances: Double
    @State private var tempMaxInstances: Double
    @State private var showingInstanceTypePicker = false
    @State private var isApplyingConfiguration = false
    @State private var configurationMessage: String?
    
    // Destroy application state
    @State private var showingDestroyConfirmation = false
    @State private var isDestroying = false
    @State private var destroyConfirmationText = ""

    // MARK: - Domains State
    @State private var domains: [CCDomain] = []
    @State private var isLoadingDomains = false
    @State private var domainsError: String?
    @State private var showingAddDomain = false
    @State private var newDomainName = ""
    @State private var isAddingDomain = false
    @State private var isDeletingDomain = false
    @State private var domainToDelete: String?
    @State private var showingDeleteDomainConfirmation = false

    // MARK: - Metrics State
    @State private var selectedMetricsPeriod = "PT1H"
    @State private var isLoadingMetrics = false
    @State private var cpuMetricsData: [CCApplicationMetricPoint] = []
    @State private var memoryMetricsData: [CCApplicationMetricPoint] = []
    @State private var networkInMetricsData: [CCApplicationMetricPoint] = []
    @State private var networkOutMetricsData: [CCApplicationMetricPoint] = []
    @State private var metricsTimer: Timer?
    @State private var metricsService: CCApplicationMetricsService?
    
    // Initialize temp instances values
    init(application: CCApplication, cleverCloudSDK: CleverCloudSDK, organizationId: String?) {
        self._application = State(initialValue: application) // 🎯 CRITICAL FIX: Initialize @State var properly
        self.cleverCloudSDK = cleverCloudSDK
        self.organizationId = organizationId
        
        // Initialize temp scaling values from current application configuration
        self._tempMinInstances = State(initialValue: Double(application.instance.minInstances))
        self._tempMaxInstances = State(initialValue: Double(application.instance.maxInstances))
    }
    
    var body: some View {
        Group {
            if isIpad {
                // iPad: No NavigationView needed (we're inside NavigationSplitView detail)
                applicationContent
            } else {
                // iPhone: Use NavigationView for traditional navigation
                NavigationView {
                    applicationContent
                        .navigationBarHidden(true)
                }
                .navigationTitle(application.name)
                .navigationBarTitleDisplayMode(.large)
            }
        }
        .sheet(isPresented: $showingAddVariable) {
            addVariableSheet
        }
    }
    
    // MARK: - Shared Application Content
    
    private var applicationContent: some View {
        VStack(spacing: 0) {
            // Header with application info
            applicationHeader
            
            // TabView with beautiful bottom tabs
            TabView(selection: $selectedTab) {
                // Tab 1: Environment Variables (Priority 1)
                environmentVariablesTab
                    .tabItem {
                        Image(systemName: "lock.fill")
                        Text("Environment")
                    }
                    .tag(0)
                
                // Tab 2: Configuration (Priority 2)
                configurationTabContent
                    .tabItem {
                        Image(systemName: "gear")
                        Text("Configuration")
                    }
                    .tag(1)
                
                // Tab 3: Overview & Billing (Priority 3)
                overviewTab
                    .tabItem {
                        Image(systemName: "chart.bar")
                        Text("Metrics")
                    }
                    .tag(2)
                
                // Tab 4: Deployments & Logs (Priority 4)
                deploymentsTab
                    .tabItem {
                        Image(systemName: "arrow.up.circle")
                        Text("Deployments")
                    }
                    .tag(3)
                
                // Tab 5: Domains & Networking (Priority 5)
                domainsTab
                    .tabItem {
                        Image(systemName: "globe")
                        Text("Domains")
                    }
                    .tag(4)
                
                // Tab 6: Advanced Settings (Priority 6)
                advancedTab
                    .tabItem {
                        Image(systemName: "slider.horizontal.3")
                        Text("Advanced")
                    }
                    .tag(5)
            }
        }
        .onAppear {
            // 🔄 CRITICAL: Always force refresh data from API when appearing
            Task {
                await forceRefreshFromAPI()
            }
            
            // Initialize view state
            selectedFlavor = application.instance.minFlavor
            currentApplicationFlavor = application.instance.minFlavor
            loadEnvironmentVariables()
            refreshApplicationState()
            
            // 🔄 Listen for scaling configuration updates
            setupNotificationListeners()
        }
        .onDisappear {
            // Clean up notification listeners
            NotificationCenter.default.removeObserver(self)
        }
    }
    
    // MARK: - Header Section
    
    private var applicationHeader: some View {
        VStack(spacing: 16) {
            // App Status Row
            HStack(spacing: 16) {
                // App Icon & Basic Info
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "app.badge.fill")
                            .foregroundColor(.purple)
                            .font(.title)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(application.name)
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Text("ID: \(application.id)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        // Status Badge
                        statusBadge
                    }
                }
            }
            
            // Instance Info Row
            HStack(spacing: 20) {
                InfoCard(
                    icon: "cpu",
                    title: "Instance",
                    value: instanceDisplayName,
                    subtitle: instanceSpecs
                )
                
                InfoCard(
                    icon: "location",
                    title: "Zone",
                    value: application.zone.uppercased(),
                    subtitle: "Region"
                )
                
                InfoCard(
                    icon: "clock",
                    title: "Created",
                    value: formatDate(Date()),
                    subtitle: "Date"
                )
            }
            
            // Quick Actions - Organized in two rows
            VStack(spacing: 8) {
                // Row 1: State Controls
                HStack(spacing: 12) {
                    ActionButton(
                        title: isStarting ? "Starting..." : "Start",
                        icon: isStarting ? "hourglass" : "play.fill",
                        color: .green,
                        isLoading: isStarting
                    ) {
                        startApplication()
                    }

                    ActionButton(
                        title: isStopping ? "Stopping..." : "Stop",
                        icon: isStopping ? "hourglass" : "stop.fill",
                        color: .red,
                        isLoading: isStopping
                    ) {
                        stopApplication()
                    }

                    ActionButton(
                        title: isRestarting ? "Restarting..." : "Restart",
                        icon: isRestarting ? "hourglass" : "arrow.clockwise",
                        color: .orange,
                        isLoading: isRestarting
                    ) {
                        restartApplication()
                    }

                    Spacer()
                }

                // Row 2: Deployment & Refresh
                HStack(spacing: 12) {
                    ActionButton(
                        title: isRedeploying ? "Redeploying..." : "Redeploy",
                        icon: isRedeploying ? "hourglass" : "arrow.up.doc",
                        color: .purple,
                        isLoading: isRedeploying
                    ) {
                        redeployApplication()
                    }

                    ActionButton(
                        title: isLoading ? "Refreshing..." : "Refresh",
                        icon: isLoading ? "hourglass" : "arrow.clockwise",
                        color: .blue,
                        isLoading: isLoading
                    ) {
                        refreshApplicationData()
                    }

                    Spacer()
                }
            }
            
            // Action message display
            if let actionMessage = actionMessage {
                Text(actionMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }
        }
        .padding()
        .background(Color(.systemGray6))
    }
    
    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(colorForStatus(applicationStatus))
                .frame(width: 8, height: 8)
            Text(applicationStatus)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(colorForStatus(applicationStatus).opacity(0.1))
        .cornerRadius(12)
    }
    
    private func colorForStatus(_ status: String) -> Color {
        switch status.lowercased() {
        case "running", "up":
            return .green
        case "deploying", "starting", "restarting":
            return .orange
        case "sleeping":
            return .blue
        case "stopped", "down":
            return .gray
        case "failed":
            return .red
        case "loading...", "loading":
            return .blue
        default:
            return .gray
        }
    }
    
    /// Get instance specifications based on the actual flavor
    private var instanceSpecs: String {
        let flavorName = application.instance.minFlavor.name.lowercased()
        
        switch flavorName {
        case "pico": return "0.125 vCPU, 128MB"
        case "nano": return "0.25 vCPU, 256MB"
        case "xs": return "0.5 vCPU, 512MB"
        case "s": return "1 vCPU, 1GB"
        case "m": return "2 vCPU, 2GB"
        case "l": return "4 vCPU, 4GB"
        case "xl": return "8 vCPU, 8GB"
        case "2xl": return "16 vCPU, 16GB"
        case "3xl": return "32 vCPU, 32GB"
        default: 
            // Fallback to flavor data if available
            let cpu = application.instance.minFlavor.cpus
            let memGB = application.instance.minFlavor.mem / 1024
            return "\(cpu) vCPU, \(memGB)GB"
        }
    }
    
    /// Display name combining runtime and flavor size
    private var instanceDisplayName: String {
        let runtime = application.instance.type.capitalized
        let flavor = application.instance.minFlavor.name.uppercased()
        return "\(runtime) \(flavor)"
    }
    

    
    // MARK: - Configuration Tab Content
    
    private var configurationTabContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Configuration")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.horizontal)
                
                // Instance Type Section
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Instance Type")
                            .font(.headline)
                        
                        Spacer()
                        
                        if isLoadingFlavors {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                    
                    // Current Configuration Display
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Runtime:")
                                .fontWeight(.medium)
                            Text(application.instance.type.capitalized)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Size:")
                                .fontWeight(.medium)
                            Text("\((currentApplicationFlavor ?? application.instance.minFlavor).name.uppercased()) (\(instanceSpecs))")
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Price:")
                                .fontWeight(.medium)
                            Text("€\(String(format: "%.3f", (currentApplicationFlavor ?? application.instance.minFlavor).price))/hour")
                                .foregroundColor(.green)
                        }
                    }
                    .padding(.vertical, 8)
                    
                    // Change Instance Type Button
                    Button(action: {
                        configurationMessage = "✅ Change Instance Type button clicked!"
                        loadAvailableFlavors()
                        showingInstanceTypePicker = true
                    }) {
                        HStack {
                            Image(systemName: "gear")
                            Text("Change Instance Type")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLoadingFlavors)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)
                
                // Revolutionary Scaling Configuration
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("🚀 Revolutionary Autoscaling")
                            .font(.headline)
                            .fontWeight(.bold)
                        
                        Spacer()
                        
                        NavigationLink(destination: ScalabilityConfigurationView(
                            application: application,
                            cleverCloudSDK: cleverCloudSDK,
                            organizationId: organizationId
                        )) {
                            HStack {
                                Image(systemName: "wand.and.stars")
                                Text("Open Autoscaling")
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [.blue, .purple]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(20)
                        }
                    }
                    
                    Text("Complete autoscaling management with clever-tools compatibility")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    // Features overview
                    VStack(alignment: .leading, spacing: 8) {
                        FeatureBadge(icon: "gear.2", text: "4 Scaling Strategies")
                        FeatureBadge(icon: "rectangle.stack", text: "Preset Management")
                        FeatureBadge(icon: "chart.line.uptrend.xyaxis", text: "Real-time Validation")
                        FeatureBadge(icon: "eurosign.circle", text: "Cost Estimation")
                    }
                }
                .padding()
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [.blue.opacity(0.1), .purple.opacity(0.1)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(12)
                .padding(.horizontal)
                
                // Legacy Auto-scaling Section (Simplified)
                VStack(alignment: .leading, spacing: 16) {
                    Text("Basic Auto-scaling (Legacy)")
                        .font(.headline)
                    
                    Text("Simple instance scaling configuration")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    VStack(alignment: .leading, spacing: 16) {
                        // Min Instances Slider
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Min Instances:")
                                    .fontWeight(.medium)
                                Spacer()
                                Text("\(Int(tempMinInstances))")
                                    .foregroundColor(.blue)
                                    .fontWeight(.semibold)
                            }
                            
                            Slider(value: $tempMinInstances, in: 1...Double(application.instance.maxAllowedInstances), step: 1)
                                .onChange(of: tempMinInstances) { _, newValue in
                                    // Ensure min <= max
                                    if newValue > tempMaxInstances {
                                        tempMaxInstances = newValue
                                    }
                                }
                        }
                        
                        // Max Instances Slider
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Max Instances:")
                                    .fontWeight(.medium)
                                Spacer()
                                Text("\(Int(tempMaxInstances))")
                                    .foregroundColor(.orange)
                                    .fontWeight(.semibold)
                            }
                            
                            Slider(value: $tempMaxInstances, in: tempMinInstances...Double(application.instance.maxAllowedInstances), step: 1)
                                .onChange(of: tempMaxInstances) { _, newValue in
                                    // Ensure max >= min
                                    if newValue < tempMinInstances {
                                        tempMinInstances = newValue
                                    }
                                }
                        }
                        
                        // Current vs New Values
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Current: \(application.instance.minInstances)-\(application.instance.maxInstances)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing) {
                                Text("New: \(Int(tempMinInstances))-\(Int(tempMaxInstances))")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                        
                        // Apply Scaling Button
                        if tempMinInstances != Double(application.instance.minInstances) || 
                           tempMaxInstances != Double(application.instance.maxInstances) {
                            
                            Button(action: {
                                applyScalingConfiguration()
                            }) {
                                HStack {
                                    if isApplyingConfiguration {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "checkmark.circle")
                                    }
                                    Text(isApplyingConfiguration ? "Applying..." : "Apply Scaling Changes")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isApplyingConfiguration)
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)
                
                // Deployment Settings (Coming Soon)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Deployment Settings")
                        .font(.headline)
                    
                    Text("Advanced deployment configuration coming soon")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .italic()
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)
                
                // Danger Zone - Destroy Application
                VStack(alignment: .leading, spacing: 16) {
                    Text("⚠️ Danger Zone")
                        .font(.headline)
                        .foregroundColor(.red)
                    
                    Text("Permanently delete this application and all its data. This action cannot be undone.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Button(action: {
                        showingDestroyConfirmation = true
                    }) {
                        HStack {
                            Image(systemName: "trash.fill")
                            Text(isDestroying ? "Destroying..." : "Destroy Application")
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
                
                // Configuration Messages
                if let configurationMessage = configurationMessage {
                    Text(configurationMessage)
                        .font(.caption)
                        .foregroundColor(.blue)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                        .padding(.horizontal)
                }
            }
        }
        .sheet(isPresented: $showingInstanceTypePicker) {
            instanceTypePickerSheet
        }
        .alert("Destroy Application", isPresented: $showingDestroyConfirmation) {
            TextField("Type application name to confirm", text: $destroyConfirmationText)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
            Button("Cancel", role: .cancel) {
                destroyConfirmationText = ""
            }
            Button("Destroy", role: .destructive) {
                destroyApplication()
            }
            .disabled(destroyConfirmationText != application.name)
        } message: {
            Text("This will permanently delete '\(application.name)' and all its data.\n\nType the application name '\(application.name)' to confirm.")
        }
        .onAppear {
            // Initialize selected flavor
            selectedFlavor = application.instance.minFlavor
        }
    }
    
    // MARK: - Tab 1: Environment Variables (Priority 1)
    
    private var environmentVariablesTab: some View {
        VStack(spacing: 0) {
            // Header with Add Button
            HStack {
                Text("Environment Variables")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(action: {
                    showingAddVariable = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Variable")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            
            if isLoading {
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
                    
                    Text("Add environment variables to configure your application")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button("Add First Variable") {
                        showingAddVariable = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Variables List
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(environmentVariables, id: \.name) { variable in
                            EnvironmentVariableRow(
                                variable: variable,
                                onEdit: { editVariable(variable) },
                                onDelete: { deleteVariable(variable) }
                            )
                        }
                    }
                    .padding()
                }
            }
            
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Placeholder Tabs (To be implemented)
    
    private var overviewTab: some View {
        GeometryReader { geometry in
            ScrollView {
                LazyVStack(spacing: 16) {
                    
                    // MARK: - Application Status Section
                    applicationStatusSection
                    
                    // MARK: - Metrics Dashboard  
                    metricsDashboardSection
                    
                    // MARK: - Cost & Billing Section
                    costBillingSection
                }
                .padding()
            }
        }
        .onAppear {
            startMetricsUpdates()
        }
        .onDisappear {
            stopMetricsUpdates()
        }
    }
    
    // MARK: - Overview Tab Sections
    
    private var applicationStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Application Status")
                .font(.title2)
                .fontWeight(.semibold)
            
            HStack(spacing: 16) {
                // Status Indicator
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 12, height: 12)
                    
                    Text(applicationStatus)
                        .font(.headline)
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                // Instance count
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(applicationInstances.count)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    Text("Instances")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Additional status details
            Text("Last updated: \(formatTimeAgo(lastStatusUpdate))")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    private var metricsDashboardSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Performance Metrics")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                // Time period selector
                Picker("Period", selection: $selectedMetricsPeriod) {
                    Text("1H").tag("PT1H")
                    Text("6H").tag("PT6H")
                    Text("24H").tag("PT24H")
                    Text("7D").tag("P7D")
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 200)
            }
            
            // CPU Usage Graph
            MetricsGraphView(
                title: "CPU Usage",
                dataPoints: cpuMetricsData,
                metricType: .cpuUsage,
                isLoading: isLoadingMetrics,
                period: formatPeriodDisplay(selectedMetricsPeriod)
            )
            
            // Memory Usage Graph
            MetricsGraphView(
                title: "Memory Usage",
                dataPoints: memoryMetricsData,
                metricType: .memoryUsage,
                isLoading: isLoadingMetrics,
                period: formatPeriodDisplay(selectedMetricsPeriod)
            )
            
            // Network I/O Graphs in vertical layout
            MetricsGraphView(
                title: "Network In",
                dataPoints: networkInMetricsData,
                metricType: .networkIn,
                isLoading: isLoadingMetrics,
                period: formatPeriodDisplay(selectedMetricsPeriod)
            )

            MetricsGraphView(
                title: "Network Out",
                dataPoints: networkOutMetricsData,
                metricType: .networkOut,
                isLoading: isLoadingMetrics,
                period: formatPeriodDisplay(selectedMetricsPeriod)
            )
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    private var costBillingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cost & Billing")
                .font(.title2)
                .fontWeight(.semibold)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Estimated Monthly Cost")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    if currentApplicationFlavor != nil {
                        Text("€\(String(format: "%.2f", estimatedMonthlyCost))")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                    } else {
                        Text("Calculating...")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Current Flavor")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text(currentApplicationFlavor?.name ?? "Unknown")
                        .font(.headline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                }
            }
            
            // Cost breakdown details
            if let flavor = currentApplicationFlavor {
                VStack(alignment: .leading, spacing: 6) {
                    Divider()
                    
                    HStack {
                        Text("Per instance/hour:")
                        Spacer()
                        Text("€\(String(format: "%.4f", Double(flavor.price) / 3600.0))")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    
                    HStack {
                        Text("Running instances:")
                        Spacer() 
                        Text("\(application.instance.minInstances) - \(application.instance.maxInstances)")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    

    
    private var deploymentHistoryView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isLoadingDeployments {
                ProgressView("Loading deployments...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = deploymentsError {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text("Failed to load deployments")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Retry") {
                        loadDeployments()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if deployments.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No deployments yet")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(deployments) { deployment in
                            DeploymentRow(deployment: deployment)
                        }
                    }
                    .padding()
                }
            }
        }
        .onAppear {
            if deployments.isEmpty && !isLoadingDeployments {
                loadDeployments()
            }
        }
    }

    private var deploymentsTab: some View {
        VStack(spacing: 0) {
            // Segmented Control
            Picker("Section", selection: $selectedDeploymentSection) {
                Text("Deployments").tag(0)
                Text("Logs").tag(1)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()

            // Content based on selection
            if selectedDeploymentSection == 0 {
                // Deployments view
                deploymentHistoryView
            } else {
                // Logs view
                ApplicationLogsView(
                    application: application,
                    cleverCloudSDK: cleverCloudSDK,
                    organizationId: organizationId,
                    logs: $logs,
                    isLoadingLogs: $isLoadingLogs,
                    logsError: $logsError,
                    searchText: $searchText,
                    selectedLogLevel: $selectedLogLevel,
                    isPaused: $isPaused,
                    autoScroll: $autoScroll,
                    logsTimer: $logsTimer
                )
            }
        }
    }
    
    private var domainsTab: some View {
        VStack(spacing: 0) {
            // Header with Add Button
            HStack {
                Text("Domains")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                Button(action: {
                    showingAddDomain = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Domain")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()

            if isLoadingDomains {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Loading domains...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Default Clever Cloud domain section
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "star.fill")
                                    .foregroundColor(.orange)
                                Text("Default Domain")
                                    .font(.headline)
                            }

                            HStack {
                                Image(systemName: "globe")
                                    .foregroundColor(.blue)
                                    .font(.title3)

                                Text(cleverAppDomain)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.primary)

                                Spacer()

                                Button(action: {
                                    UIPasteboard.general.string = cleverAppDomain
                                }) {
                                    Image(systemName: "doc.on.doc")
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(10)

                            Text("This is your default Clever Cloud domain. It cannot be removed.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        // Custom domains section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Custom Domains")
                                .font(.headline)

                            if domains.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "link.badge.plus")
                                        .font(.largeTitle)
                                        .foregroundColor(.secondary)

                                    Text("No custom domains yet")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)

                                    Text("Add a custom domain to make your app accessible via your own domain name.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 30)
                            } else {
                                ForEach(domains) { domain in
                                    HStack {
                                        Image(systemName: "globe")
                                            .foregroundColor(.green)
                                            .font(.title3)

                                        Text(domain.fqdn)
                                            .font(.system(.body, design: .monospaced))
                                            .foregroundColor(.primary)

                                        Spacer()

                                        Button(action: {
                                            UIPasteboard.general.string = domain.fqdn
                                        }) {
                                            Image(systemName: "doc.on.doc")
                                                .foregroundColor(.blue)
                                        }

                                        Button(action: {
                                            domainToDelete = domain.fqdn
                                            showingDeleteDomainConfirmation = true
                                        }) {
                                            Image(systemName: "trash")
                                                .foregroundColor(.red)
                                        }
                                        .disabled(isDeletingDomain)
                                    }
                                    .padding()
                                    .background(Color(.systemBackground))
                                    .cornerRadius(10)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color(.systemGray4), lineWidth: 1)
                                    )
                                }
                            }
                        }

                        // DNS Configuration Help
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "network")
                                    .foregroundColor(.blue)
                                Text("Configure your DNS")
                                    .font(.headline)
                            }

                            Text("To associate a domain managed by a third-party provider, configure its DNS zone:")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            // CNAME Record (Recommended)
                            VStack(alignment: .leading, spacing: 6) {
                                Label("CNAME Record (Recommended)", systemImage: "star.fill")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.orange)

                                HStack {
                                    Text("domain.par.clever-cloud.com.")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.blue)

                                    Button(action: {
                                        UIPasteboard.general.string = "domain.par.clever-cloud.com."
                                    }) {
                                        Image(systemName: "doc.on.doc")
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                    }
                                }
                                .padding(8)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(6)
                            }

                            Divider()

                            // A Records (Alternative)
                            VStack(alignment: .leading, spacing: 6) {
                                Label("A Records (For APEX domains)", systemImage: "number")
                                    .font(.caption)
                                    .fontWeight(.semibold)

                                Text("91.208.207.214-218, 220-223")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }

                            Divider()

                            // SSL/TLS info
                            HStack(spacing: 6) {
                                Image(systemName: "lock.shield.fill")
                                    .font(.caption)
                                    .foregroundColor(.green)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Automatic HTTPS")
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                    Text("Let's Encrypt certificates are automatically issued and renewed")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                    }
                    .padding()
                }
            }

            // Error message display
            if let error = domainsError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding()
            }
        }
        .sheet(isPresented: $showingAddDomain) {
            addDomainSheet
        }
        .alert("Remove Domain", isPresented: $showingDeleteDomainConfirmation) {
            Button("Cancel", role: .cancel) {
                domainToDelete = nil
            }
            Button("Remove", role: .destructive) {
                if let domain = domainToDelete {
                    removeDomain(domain)
                    domainToDelete = nil
                }
            }
        } message: {
            Text("Are you sure you want to remove '\(domainToDelete ?? "")'? This action cannot be undone.")
        }
        .onAppear {
            if domains.isEmpty && !isLoadingDomains {
                loadDomains()
            }
        }
    }
    
    private var advancedTab: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Advanced Settings")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Dangerous operations")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                // Danger Zone
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text("Danger Zone")
                            .font(.headline)
                            .foregroundColor(.red)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Delete Application")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        Text("Once you delete an application, there is no going back. Please be certain.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button(action: {
                            showingDeleteConfirmation = true
                        }) {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete Application")
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.red)
                            .cornerRadius(8)
                        }
                        .alert("Delete Application", isPresented: $showingDeleteConfirmation) {
                            Button("Cancel", role: .cancel) { }
                            Button("Delete", role: .destructive) {
                                deleteApplication()
                            }
                        } message: {
                            Text("Are you sure you want to delete \"\(application.name)\"? This action cannot be undone.")
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                .padding()

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Add Variable Sheet
    
    private var addVariableSheet: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Add Environment Variable")
                    .font(.title2)
                    .fontWeight(.bold)
                
                VStack(alignment: .leading, spacing: 16) {
                    // Variable Name
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Variable Name")
                            .font(.headline)
                        TextField("e.g. NODE_ENV", text: $newVariableName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocorrectionDisabled(true)
                            .textInputAutocapitalization(.never)
                    }
                    
                    // Variable Value
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Variable Value")
                            .font(.headline)
                        TextField("e.g. production", text: $newVariableValue)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocorrectionDisabled(true)
                            .textInputAutocapitalization(.never)
                    }
                    
                    // Secret Toggle
                    Toggle("Mark as Secret", isOn: $isSecret)
                }
                .padding()
                
                Spacer()
                
                // Action Buttons
                HStack(spacing: 16) {
                    Button("Cancel") {
                        showingAddVariable = false
                        clearForm()
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.bordered)
                    
                    Button("Add Variable") {
                        addEnvironmentVariable()
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.borderedProminent)
                    .disabled(newVariableName.isEmpty || newVariableValue.isEmpty)
                }
                .padding()
            }
            .navigationBarHidden(true)
        }
        .presentationDetents([.medium, .large])
    }
    
    // MARK: - Helper Methods
    
    private func loadEnvironmentVariables() {
        isLoading = true
        errorMessage = nil
        
        cleverCloudSDK.applications.getEnvironmentVariables(applicationId: application.id, organizationId: organizationId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    isLoading = false
                    if case .failure(let error) = completion {
                        errorMessage = "Failed to load environment variables: \(error.localizedDescription)"
                    }
                },
                receiveValue: { variables in
                    environmentVariables = variables
                }
            )
            .store(in: &cancellables)
    }
    
    private func addEnvironmentVariable() {
        let newVariable = CCEnvironmentVariable(name: newVariableName, value: newVariableValue)
        cleverCloudSDK.applications.setEnvironmentVariable(
            applicationId: application.id,
            variable: newVariable,
            organizationId: organizationId
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    errorMessage = "Failed to add variable: \(error.localizedDescription)"
                } else {
                    showingAddVariable = false
                    clearForm()
                    loadEnvironmentVariables() // Reload the list
                }
            },
            receiveValue: { _ in }
        )
        .store(in: &cancellables)
    }
    
    private func editVariable(_ variable: CCEnvironmentVariable) {
        // TODO: Implement edit functionality
        print("Edit variable: \(variable.name)")
    }
    
    private func deleteVariable(_ variable: CCEnvironmentVariable) {
        // Use the applications service to delete the environment variable
        cleverCloudSDK.applications.removeEnvironmentVariable(
            applicationId: application.id,
            name: variable.name,
            organizationId: organizationId
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    errorMessage = "Failed to delete variable: \(error.localizedDescription)"
                } else {
                    loadEnvironmentVariables() // Reload the list
                }
            },
            receiveValue: { _ in }
        )
        .store(in: &cancellables)
    }
    
    private func clearForm() {
        newVariableName = ""
        newVariableValue = ""
        isSecret = false
    }
    
    private func startApplication() {
        isStarting = true
        actionMessage = "Starting application..."
        
        cleverCloudSDK.applications.startApplication(applicationId: application.id, organizationId: organizationId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    isStarting = false
                    
                    switch completion {
                    case .finished:
                        actionMessage = "✅ Start request sent successfully"
                        
                        // Refresh application state after 2 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            refreshApplicationState()
                        }
                        
                        // Clear message after 3 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            actionMessage = nil
                        }
                        
                    case .failure(let error):
                        actionMessage = "❌ Failed to start: \(error.localizedDescription)"
                        
                        // Clear error message after 5 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                            actionMessage = nil
                        }
                    }
                },
                receiveValue: { _ in
                    // Request completed successfully
                }
            )
            .store(in: &cancellables)
    }
    
    private func stopApplication() {
        isStopping = true
        actionMessage = "Stopping application..."
        
        cleverCloudSDK.applications.stopApplication(applicationId: application.id, organizationId: organizationId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    isStopping = false
                    
                    switch completion {
                    case .finished:
                        actionMessage = "✅ Stop request sent successfully"
                        
                        // Refresh application state after 2 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            refreshApplicationState()
                        }
                        
                        // Clear message after 3 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            actionMessage = nil
                        }
                        
                    case .failure(let error):
                        actionMessage = "❌ Failed to stop: \(error.localizedDescription)"
                        
                        // Clear error message after 5 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                            actionMessage = nil
                        }
                    }
                },
                receiveValue: { _ in
                    // Request completed successfully
                }
            )
            .store(in: &cancellables)
    }
    
    private func restartApplication() {
        isRestarting = true
        actionMessage = "Restarting application..."
        
        cleverCloudSDK.applications.restartApplication(applicationId: application.id, organizationId: organizationId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    isRestarting = false
                    
                    switch completion {
                    case .finished:
                        actionMessage = "✅ Restart request sent successfully"
                        
                        // Refresh application state after 2 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            refreshApplicationState()
                        }
                        
                        // Clear message after 3 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            actionMessage = nil
                        }
                        
                    case .failure(let error):
                        actionMessage = "❌ Failed to restart: \(error.localizedDescription)"
                        
                        // Clear error message after 5 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                            actionMessage = nil
                        }
                    }
                },
                receiveValue: { _ in
                    // Request completed successfully
                }
            )
            .store(in: &cancellables)
    }

    private func redeployApplication() {
        isRedeploying = true
        actionMessage = "Redeploying application..."

        cleverCloudSDK.applications.deploy(applicationId: application.id)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    isRedeploying = false

                    switch completion {
                    case .finished:
                        actionMessage = "✅ Redeploy request sent successfully"

                        // Refresh application state after 2 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            refreshApplicationState()
                        }

                        // Clear message after 3 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            actionMessage = nil
                        }

                    case .failure(let error):
                        actionMessage = "❌ Failed to redeploy: \(error.localizedDescription)"

                        // Clear error message after 5 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                            actionMessage = nil
                        }
                    }
                },
                receiveValue: { _ in
                    // Request completed successfully
                }
            )
            .store(in: &cancellables)
    }

    private func deleteApplication() {
        cleverCloudSDK.applications.deleteApplication(applicationId: application.id, organizationId: organizationId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    switch completion {
                    case .finished:
                        // Navigate back to the main screen
                        presentationMode.wrappedValue.dismiss()

                        // Post notification to refresh the application list
                        NotificationCenter.default.post(name: NSNotification.Name("RefreshApplicationList"), object: nil)

                    case .failure(let error):
                        actionMessage = "❌ Failed to delete application: \(error.localizedDescription)"

                        // Clear error message after 5 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                            actionMessage = nil
                        }
                    }
                },
                receiveValue: { _ in
                    // Request completed successfully
                }
            )
            .store(in: &cancellables)
    }

    private func refreshApplicationData() {
        loadEnvironmentVariables()
        refreshApplicationState()
    }
    
    /// Setup notification listeners for refresh events
    private func setupNotificationListeners() {
        // Listen for scaling configuration updates from ScalabilityConfigurationView
        let applicationId = application.id // Capture the ID to avoid concurrency issues
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("RefreshApplicationData"),
            object: nil,
            queue: .main
        ) { notification in
            // Check if this notification is for our application
            if let appId = notification.object as? String,
               appId == applicationId {
                print("🔄 [ApplicationDetailView] Received refresh notification for application: \(appId)")
                
                // Use Task to handle the async call properly
                Task { @MainActor in
                    self.forceCompleteRefresh()
                }
            }
        }
        
        // Also listen for global refresh requests
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("RefreshApplicationList"),
            object: nil,
            queue: .main
        ) { _ in
            print("🔄 [ApplicationDetailView] Received global refresh notification")
            Task { @MainActor in
                self.forceCompleteRefresh()
            }
        }
    }
    
    /// Force complete refresh of all application data 
    @MainActor private func forceCompleteRefresh() {
        print("🔄 [ApplicationDetailView] Starting force complete refresh...")
        
        // Reset loading states
        isLoading = true
        isLoadingLogs = true
        
        // 🎯 CRITICAL FIX: Update ALL local state properties with fresh application data
        print("🔄 [ApplicationDetailView] BEFORE refresh - Current flavor: \(currentApplicationFlavor?.name ?? "nil"), App flavor: \(application.instance.minFlavor.name)")
        
        selectedFlavor = application.instance.minFlavor
        currentApplicationFlavor = application.instance.minFlavor
        tempMinInstances = Double(application.instance.minInstances)
        tempMaxInstances = Double(application.instance.maxInstances)
        
        print("🔄 [ApplicationDetailView] AFTER local update - New flavor: \(currentApplicationFlavor?.name ?? "nil")")
        
        // Force reload application data first from API
        self.reloadApplicationFromAPI()
        
        // Then reload everything else
        Task {
            // Load environment variables
            loadEnvironmentVariables()
            
            // Refresh application state multiple times to ensure fresh data
            refreshApplicationState()
            
            // Wait and try again to catch any delayed updates
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            refreshApplicationState()
            
            await MainActor.run {
                // 🎯 FINAL UPDATE: Ensure we have the absolute latest data
                selectedFlavor = application.instance.minFlavor
                currentApplicationFlavor = application.instance.minFlavor
                tempMinInstances = Double(application.instance.minInstances)
                tempMaxInstances = Double(application.instance.maxInstances)
                
                print("🔄 [ApplicationDetailView] Force complete refresh completed! Final flavor: \(currentApplicationFlavor?.name ?? "nil")")
                isLoading = false
                isLoadingLogs = false
            }
        }
    }
    
    private func refreshApplicationState() {
        // Use organization context if available
        let instancesPublisher: AnyPublisher<[CCApplicationInstance], CCError>
        if let orgId = organizationId {
            instancesPublisher = cleverCloudSDK.applications.getApplicationInstances(
                applicationId: application.id, 
                organizationId: orgId
            )
        } else {
            instancesPublisher = cleverCloudSDK.applications.getApplicationInstances(applicationId: application.id)
        }
        
        instancesPublisher
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(_) = completion {
                        applicationStatus = "Unknown"
                    }
                },
                receiveValue: { instances in
                    applicationInstances = instances
                    let computedStatus = computeApplicationStatus(from: instances)
                    applicationStatus = computedStatus
                    lastStatusUpdate = Date()
                    
                    // Post notification for other views
                    NotificationCenter.default.post(
                        name: NSNotification.Name("ApplicationStateChanged"),
                        object: application.id,
                        userInfo: ["status": computedStatus]
                    )
                }
            )
            .store(in: &cancellables)
    }
    
    /// Compute application status from instances (following clever-tools computeStatus pattern)
    private func computeApplicationStatus(from instances: [CCApplicationInstance]) -> String {
        guard !instances.isEmpty else {
            return "Stopped"
        }
        
        let instanceStates = instances.map { $0.state.uppercased() }
        
        // Priority order based on clever-tools logic
        if instanceStates.contains("FAILED") {
            return "Failed"
        }
        
        if instanceStates.contains("DEPLOYING") {
            return "Deploying"
        }
        
        if instanceStates.contains("UP") {
            return "Running"
        }
        
        if instanceStates.contains("DOWN") || instanceStates.contains("SHOULD_BE_DOWN") {
            return "Stopped"
        }
        
        // Default case
        return "Unknown"
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }
    
    // MARK: - Configuration Methods
    
    /// Load available flavors from the API
    private func loadAvailableFlavors() {
        isLoadingFlavors = true
        configurationMessage = "Loading available flavors..."
        
        cleverCloudSDK.applications.getAvailableFlavors()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    isLoadingFlavors = false
                    
                    if case .failure(let error) = completion {
                        configurationMessage = "❌ Failed to load flavors: \(error.localizedDescription)"
                        
                        // Clear message after 5 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                            configurationMessage = nil
                        }
                    } else {
                        configurationMessage = nil
                    }
                },
                receiveValue: { flavors in
                    let availableFlavorsList = flavors.filter { $0.available }
                    availableFlavors = availableFlavorsList
                    
                    selectedFlavor = availableFlavorsList.first { $0.name.lowercased() == application.instance.minFlavor.name.lowercased() }
                }
            )
            .store(in: &cancellables)
    }
    
    /// Apply scaling configuration changes
    private func applyScalingConfiguration() {
        isApplyingConfiguration = true
        configurationMessage = "Applying scaling configuration..."
        
        let instanceConfig = CCAppInstanceConfiguration(
            minInstances: Int(tempMinInstances),
            maxInstances: Int(tempMaxInstances),
            flavor: application.instance.minFlavor.name
        )
        
        cleverCloudSDK.environment.updateInstanceConfiguration(
            for: application.id,
            instanceConfig: instanceConfig,
            organizationId: organizationId
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { completion in
                isApplyingConfiguration = false
                
                if case .failure(let error) = completion {
                    configurationMessage = "❌ Failed to apply scaling: \(error.localizedDescription)"
                } else {
                    configurationMessage = "✅ Scaling configuration applied successfully!"
                }
                
                // Clear message after 5 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    configurationMessage = nil
                }
            },
            receiveValue: { response in
                if !response.success {
                    configurationMessage = "⚠️ \(response.message)"
                }
            }
        )
        .store(in: &cancellables)
    }
    
    /// Instance type picker sheet
    private var instanceTypePickerSheet: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 16) {
                    Text("Choose Instance Type")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Select the size and performance level for your application")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                
                if isLoadingFlavors {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Loading available instance types...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if availableFlavors.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 50))
                            .foregroundColor(.orange)
                        
                        Text("No Flavors Available")
                            .font(.title2)
                            .fontWeight(.medium)
                        
                        Text("Unable to load instance types. Please try again.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Flavors list
                    List(availableFlavors, id: \.name) { flavor in
                        FlavorRow(
                            flavor: flavor,
                            isSelected: selectedFlavor?.name == flavor.name,
                            isCurrentFlavor: flavor.name.lowercased() == (currentApplicationFlavor ?? application.instance.minFlavor).name.lowercased()
                        ) {
                            selectedFlavor = flavor
                            configurationMessage = "🎯 FLAVOR SÉLECTIONNÉE: \(flavor.name)"
                        }
                    }
                }
                
                // Action buttons
                VStack(spacing: 12) {
                    if let selectedFlavor = selectedFlavor,
                       selectedFlavor.name != (currentApplicationFlavor ?? application.instance.minFlavor).name {
                        
                        VStack(spacing: 8) {
                            HStack {
                                Text("Change from:")
                                Text("\((currentApplicationFlavor ?? application.instance.minFlavor).name.uppercased()) (€\(String(format: "%.3f", (currentApplicationFlavor ?? application.instance.minFlavor).price))/hour)")
                                    .fontWeight(.medium)
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                            
                            HStack {
                                Text("Change to:")
                                Text("\(selectedFlavor.name.uppercased()) (€\(String(format: "%.3f", selectedFlavor.price))/hour)")
                                    .fontWeight(.medium)
                                    .foregroundColor(.blue)
                            }
                            .font(.caption)
                        }
                        .padding(.vertical, 8)
                        
                        Button(action: {
                            configurationMessage = "🚀 Apply Instance Type clicked!"
                            applyInstanceTypeChange()
                        }) {
                            HStack {
                                if isApplyingConfiguration {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "checkmark.circle")
                                }
                                Text(isApplyingConfiguration ? "Applying..." : "Apply Instance Type")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isApplyingConfiguration)
                    }
                    
                    Button("Cancel") {
                        showingInstanceTypePicker = false
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.bordered)
                }
                .padding()
            }
            .navigationBarHidden(true)
        }
        .presentationDetents([.medium, .large])
    }
    
    /// Apply instance type change using clever-tools approach (simple and direct)
    private func applyInstanceTypeChange() {
        guard let newFlavor = selectedFlavor else { 
            configurationMessage = "❌ No flavor selected!"
            return 
        }
        
        isApplyingConfiguration = true
        configurationMessage = "🔧 Changing instance type to \(newFlavor.name.uppercased())..."
        
        let instanceConfig = CCAppInstanceConfiguration(
            minInstances: Int(tempMinInstances),
            maxInstances: Int(tempMaxInstances),
            flavor: newFlavor.name
        )
        
        cleverCloudSDK.environment.updateInstanceConfiguration(
            for: application.id,
            instanceConfig: instanceConfig,
            organizationId: organizationId
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { completion in
                isApplyingConfiguration = false
                if case .failure(let error) = completion {
                    // 🔄 IMPORTANT: Even if there's a parsing error, the API might have succeeded!
                    // Force refresh to check if the change was applied on Clever Cloud
                    configurationMessage = "🔄 Configuration may have succeeded - checking updates..."
                    reloadApplicationFromAPI()
                    
                    // Also log the error for debugging
                    print("⚠️ API call had error (but may have succeeded): \(error.localizedDescription)")
                } else {
                    configurationMessage = "✅ Instance type changed to \(newFlavor.name.uppercased()) successfully!"
                    showingInstanceTypePicker = false
                    // Force reload of application data from API to show updated flavor
                    reloadApplicationFromAPI()
                }
                
                // Clear message after 5 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    configurationMessage = nil
                }
            },
            receiveValue: { response in
                if !response.success {
                    // 🔄 Even if response indicates failure, try to refresh to be sure
                    configurationMessage = "🔄 Checking if configuration was applied..."
                    reloadApplicationFromAPI()
                    print("⚠️ Response success=false but forcing refresh: \(response.message)")
                } else {
                    configurationMessage = "✅ Configuration applied successfully!"
                }
            }
        )
        .store(in: &cancellables)
    }
    
    /// Load deployment history for the application
    private func loadDeployments() {
        isLoadingDeployments = true
        deploymentsError = nil

        cleverCloudSDK.deployments.getDeployments(
            applicationId: application.id,
            organizationId: organizationId
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { completion in
                self.isLoadingDeployments = false
                if case .failure(let error) = completion {
                    self.deploymentsError = error.localizedDescription
                    print("❌ Failed to load deployments: \(error)")
                }
            },
            receiveValue: { deployments in
                self.deployments = deployments
                self.isLoadingDeployments = false
                print("✅ Loaded \(deployments.count) deployments")
            }
        )
        .store(in: &cancellables)
    }

    // MARK: - Domains Management

    /// Load domains for the application
    private func loadDomains() {
        guard let orgId = organizationId else {
            domainsError = "Organization ID not available"
            print("❌ Cannot load domains: organizationId is nil")
            return
        }

        isLoadingDomains = true
        domainsError = nil

        cleverCloudSDK.applications.getDomainsForOrganization(
            applicationId: application.id,
            organizationId: orgId
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { completion in
                isLoadingDomains = false
                if case .failure(let error) = completion {
                    domainsError = error.localizedDescription
                    print("❌ Failed to load domains: \(error)")
                }
            },
            receiveValue: { loadedDomains in
                domains = loadedDomains
                print("✅ Loaded \(domains.count) domains")
                if !loadedDomains.isEmpty {
                    print("🏷️ Domain list: \(loadedDomains.map { $0.fqdn }.joined(separator: ", "))")
                }
            }
        )
        .store(in: &cancellables)
    }

    /// Add a new custom domain
    private func addDomain() {
        guard !newDomainName.isEmpty else { return }

        guard let orgId = organizationId else {
            domainsError = "Organization ID not available"
            print("❌ Cannot add domain: organizationId is nil")
            return
        }

        // Validate domain format
        guard isValidDomain(newDomainName) else {
            domainsError = "Invalid domain format. Please enter a valid domain name."
            return
        }

        isAddingDomain = true
        domainsError = nil

        cleverCloudSDK.applications.addDomain(
            applicationId: application.id,
            organizationId: orgId,
            domain: newDomainName
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { completion in
                isAddingDomain = false
                if case .failure(let error) = completion {
                    domainsError = "Failed to add domain: \(error.localizedDescription)"
                    print("❌ Failed to add domain: \(error)")
                }
            },
            receiveValue: { _ in
                print("✅ Domain added successfully")
                newDomainName = ""
                showingAddDomain = false
                // Reload domains to show the new one
                loadDomains()
            }
        )
        .store(in: &cancellables)
    }

    /// Remove a custom domain
    private func removeDomain(_ domain: String) {
        guard let orgId = organizationId else {
            domainsError = "Organization ID not available"
            print("❌ Cannot remove domain: organizationId is nil")
            return
        }

        // CRITICAL: Try deleting with the slash if the domain has one
        // The API might expect the exact FQDN as returned, including trailing slash
        let cleanDomain = domain // DON'T remove trailing slash
        print("🗑️ Attempting to remove domain: '\(domain)' (cleaned: '\(cleanDomain)') from app \(application.id)")
        print("🔗 DELETE URL will be: https://api.clever-cloud.com/v2/organisations/\(orgId)/applications/\(application.id)/vhosts/\(cleanDomain)")

        // Log current domains before deletion
        print("📋 Current domains before deletion: \(domains.map { $0.fqdn }.joined(separator: ", "))")

        isDeletingDomain = true
        domainsError = nil

        cleverCloudSDK.applications.removeDomain(
            applicationId: application.id,
            organizationId: orgId,
            domain: cleanDomain
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { completion in
                isDeletingDomain = false
                if case .failure(let error) = completion {
                    domainsError = "Failed to remove domain: \(error.localizedDescription)"
                    print("❌ Failed to remove domain: \(error)")
                    print("🔍 Error details: \(error)")
                }
            },
            receiveValue: { response in
                print("✅ Domain deletion API returned success")
                print("🔍 Response type: \(type(of: response))")

                // Wait longer before reloading to ensure server-side consistency
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    print("🔄 Reloading domains after deletion (2s delay)...")
                    loadDomains()

                    // Check again after additional delay to see if it's a consistency issue
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        print("🔄 Second check - reloading domains after 5s total...")
                        loadDomains()
                    }
                }
            }
        )
        .store(in: &cancellables)
    }

    /// Validate domain format
    private func isValidDomain(_ domain: String) -> Bool {
        // Basic domain validation regex
        let domainRegex = #"^([a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]\.)+[a-zA-Z]{2,}$"#
        let domainPredicate = NSPredicate(format: "SELF MATCHES %@", domainRegex)

        // Also allow simple domain without subdomain (e.g., "example.com")
        let simpleDomainRegex = #"^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$"#
        let simpleDomainPredicate = NSPredicate(format: "SELF MATCHES %@", simpleDomainRegex)

        return domainPredicate.evaluate(with: domain) || simpleDomainPredicate.evaluate(with: domain)
    }

    /// Get the default Clever Cloud domain for the application
    private var cleverAppDomain: String {
        return "app-\(application.id).cleverapps.io"
    }

    /// Reload application data from API after successful configuration change
    /// This ensures the UI displays the updated flavor information
    private func reloadApplicationFromAPI() {
        print("🔄 Reloading application data from API to check for changes...")
        
        // Use the applications service to get fresh data from the API
        cleverCloudSDK.applications.getApplication(applicationId: application.id)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        configurationMessage = "⚠️ Configuration may have succeeded but failed to refresh UI: \(error.localizedDescription)"
                        print("❌ Failed to reload application data: \(error)")
                    }
                },
                receiveValue: { (updatedApplication: CCApplication) in
                    // Check if the configuration actually changed
                    let oldFlavor = self.currentApplicationFlavor?.name ?? self.application.instance.minFlavor.name
                    let newFlavor = updatedApplication.instance.minFlavor.name
                    
                    print("🔄 API refresh complete - Old flavor: \(oldFlavor), New flavor: \(newFlavor)")
                    
                    // 🎯 CRITICAL: Update the APPLICATION OBJECT itself with fresh data
                    // This is the key fix that was missing!
                    self.application = updatedApplication
                    
                    // Update ALL local state properties with fresh data from API
                    self.selectedFlavor = updatedApplication.instance.minFlavor
                    self.currentApplicationFlavor = updatedApplication.instance.minFlavor
                    self.tempMinInstances = Double(updatedApplication.instance.minInstances)
                    self.tempMaxInstances = Double(updatedApplication.instance.maxInstances)
                    
                    print("🎯 [CRITICAL FIX] Updated application object AND all local state - New flavor: \(self.currentApplicationFlavor?.name ?? "nil")")
                    
                    // Refresh the application state with the new data
                    self.refreshApplicationState()
                    
                    if oldFlavor != newFlavor {
                        // Configuration was successfully applied!
                        configurationMessage = "✅ Instance type updated! Now showing \(newFlavor.uppercased())"
                        showingInstanceTypePicker = false
                        print("✅ Configuration change confirmed: \(oldFlavor) → \(newFlavor)")
                    } else {
                        // Configuration might still be processing
                        configurationMessage = "⏳ Configuration change may still be processing..."
                        print("⏳ No change detected yet - may still be processing")
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    /// Force refresh from API every time the view appears - NO MORE CACHE ISSUES!
    @MainActor private func forceRefreshFromAPI() async {
        print("🔄 [ApplicationDetailView] FORCE REFRESH from API - Getting fresh data...")
        
        // Reset loading states
        isLoading = true
        
        // Use the existing working method that properly handles Combine publishers
        reloadApplicationFromAPI()
        
        // Reset loading state after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.isLoading = false
        }
        
        // Reload everything else with fresh data
        loadEnvironmentVariables()
        refreshApplicationState()
    }
    
    // MARK: - Destroy Application
    
    /// Destroy the application permanently
    private func destroyApplication() {
        guard destroyConfirmationText == application.name else { return }
        
        isDestroying = true
        configurationMessage = "🗑️ Destroying application '\(application.name)'..."
        
        cleverCloudSDK.applications.deleteApplication(applicationId: application.id, organizationId: organizationId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    isDestroying = false
                    
                    if case .failure(let error) = completion {
                        configurationMessage = "❌ Failed to destroy application: \(error.localizedDescription)"
                        
                        // Clear message after 5 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                            configurationMessage = nil
                        }
                    } else {
                        configurationMessage = "✅ Application '\(application.name)' destroyed successfully!"
                        
                        // Navigate back after successful destruction
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            // The parent view should handle navigation back
                            // Could send a notification or use a callback
                        }
                    }
                },
                receiveValue: { _ in
                    print("✅ Application '\(application.name)' destroyed successfully")
                    
                    // Send notification to parent to refresh and dismiss
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("ApplicationDestroyed"), 
                            object: application.id
                        )
                    }
                }
            )
            .store(in: &cancellables)
        
        // Clear confirmation text
        destroyConfirmationText = ""
    }
    
    // MARK: - Metrics Methods
    
    /// Start updating metrics automatically
    private func startMetricsUpdates() {
        // Initialize metrics service if needed
        if metricsService == nil {
            metricsService = CCApplicationMetricsService(httpClient: cleverCloudSDK.httpClient)
        }
        
        // Load initial metrics
        loadMetricsData()
        
        // Set up auto-refresh timer (every 30 seconds)
        metricsTimer?.invalidate()
        metricsTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
            Task { @MainActor in
                self.loadMetricsData()
            }
        }
    }
    
    /// Stop metrics updates
    private func stopMetricsUpdates() {
        metricsTimer?.invalidate()
        metricsTimer = nil
    }
    
    /// Load metrics data for all metric types
    private func loadMetricsData() {
        guard let organizationId = organizationId else { return }
        
        isLoadingMetrics = true
        
        // Load metrics for all types
        let metrics: [MetricType] = [.cpuUsage, .memoryUsage, .networkIn, .networkOut]
        
        for metric in metrics {
            loadMetricsForType(metric, organizationId: organizationId)
        }
    }
    
    /// Load metrics for a specific type
    private func loadMetricsForType(_ metricType: MetricType, organizationId: String) {
        guard let metricsService = metricsService else { return }
        
        metricsService.getApplicationTimeSeries(
            applicationId: application.id,
            organizationId: organizationId,
            metric: metricType,
            interval: intervalForPeriod(selectedMetricsPeriod),
            span: selectedMetricsPeriod
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    print("Failed to load \(metricType) metrics: \(error)")
                }
                // Only stop loading when all metrics are done
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.isLoadingMetrics = false
                }
            },
            receiveValue: { dataPoints in
                // Update the appropriate data array
                switch metricType {
                case .cpuUsage:
                    self.cpuMetricsData = dataPoints
                case .memoryUsage:
                    self.memoryMetricsData = dataPoints
                case .networkIn:
                    self.networkInMetricsData = dataPoints
                case .networkOut:
                    self.networkOutMetricsData = dataPoints
                default:
                    break
                }
            }
        )
        .store(in: &cancellables)
    }
    
    /// Get appropriate interval for a given period
    private func intervalForPeriod(_ period: String) -> String {
        switch period {
        case "PT1H": return "PT5M"  // 5 minutes for 1 hour
        case "PT6H": return "PT15M" // 15 minutes for 6 hours
        case "PT24H": return "PT1H"  // 1 hour for 24 hours
        case "P7D": return "PT6H"   // 6 hours for 7 days
        default: return "PT5M"
        }
    }
    
    /// Format period for display
    private func formatPeriodDisplay(_ period: String) -> String {
        switch period {
        case "PT1H": return "Last Hour"
        case "PT6H": return "Last 6 Hours"
        case "PT24H": return "Last 24 Hours"
        case "P7D": return "Last 7 Days"
        default: return "Last Hour"
        }
    }
    
    /// Computed property for status color
    private var statusColor: Color {
        return colorForStatus(applicationStatus)
    }
    
    /// Computed property for estimated monthly cost
    private var estimatedMonthlyCost: Double {
        guard let flavor = currentApplicationFlavor else { return 0.0 }
        
        let hourlyRate = flavor.price
        let avgInstances = Double(application.instance.minInstances + application.instance.maxInstances) / 2.0
        let hoursPerMonth = 24.0 * 30.0 // Approximate
        
        return hourlyRate * avgInstances * hoursPerMonth
    }
    
    /// Format time ago for status updates
    private func formatTimeAgo(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

}

// MARK: - Helper Components

struct InfoCard: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.headline)
                .fontWeight(.semibold)
            
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
}

struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    var isLoading: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.6)
                } else {
                    Image(systemName: icon)
                        .font(.caption)
                }
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isLoading ? color.opacity(0.7) : color)
            .foregroundColor(.white)
            .cornerRadius(8)
        }
        .disabled(isLoading)
    }
}

struct EnvironmentVariableRow: View {
    let variable: CCEnvironmentVariable
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    @State private var showValue = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: isSecret ? "lock.fill" : "textformat")
                            .foregroundColor(isSecret ? .orange : .blue)
                        
                        Text(variable.name)
                            .font(.headline)
                            .fontWeight(.medium)
                        
                        if isSecret {
                            Text("SECRET")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.2))
                                .foregroundColor(.orange)
                                .cornerRadius(4)
                        }
                    }
                    
                    HStack {
                        Text(displayValue)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        if isSecret {
                            Button(showValue ? "Hide" : "Show") {
                                showValue.toggle()
                            }
                            .font(.caption)
                            .buttonStyle(.borderless)
                        }
                    }
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    Button("Edit") {
                        onEdit()
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    
                    Button("Delete") {
                        onDelete()
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
    
    private var isSecret: Bool {
        variable.name.lowercased().contains("secret") ||
        variable.name.lowercased().contains("key") ||
        variable.name.lowercased().contains("password") ||
        variable.name.lowercased().contains("token")
    }
    
    private var displayValue: String {
        if isSecret && !showValue {
            return "••••••••"
        }
        return variable.value
    }
}

struct ToggleRow: View {
    let title: String
    @Binding var value: Bool
    
    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
            
            Spacer()
            
            Toggle("", isOn: $value)
                .labelsHidden()
        }
    }
}

struct FlavorRow: View {
    let flavor: CCFlavor
    let isSelected: Bool
    let isCurrentFlavor: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Flavor icon and name
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(flavor.name.uppercased())
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        if isCurrentFlavor {
                            Text("CURRENT")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.2))
                                .foregroundColor(.green)
                                .cornerRadius(4)
                        }
                        
                        Spacer()
                        
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.blue)
                                .font(.title3)
                        }
                    }
                    
                    HStack(spacing: 8) {
                        Label("\(flavor.cpus) vCPU", systemImage: "cpu")
                        Label("\(flavor.mem)MB", systemImage: "memorychip")
                        if flavor.gpus > 0 {
                            Label("\(flavor.gpus) GPU", systemImage: "display")
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Price
                VStack(alignment: .trailing, spacing: 2) {
                    Text("€\(String(format: "%.3f", flavor.price))")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                    
                    Text("per hour")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isCurrentFlavor)
        .opacity(isCurrentFlavor ? 0.6 : 1.0)
    }
}

/// Feature Badge Component for the Revolutionary Scaling Section
struct FeatureBadge: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.blue)
            
            Text(text)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

// MARK: - Preview

#Preview {
    NavigationView {
        ApplicationDetailView(
            application: CCApplication(
                id: "app_123",
                name: "My Test App",
                description: "A sample application",
                zone: "par",
                zoneId: "par_01",
                instance: CCInstance(
                    type: "node",
                    version: "1.0",
                    variant: nil,
                    minInstances: 1,
                    maxInstances: 3,
                    maxAllowedInstances: 5,
                    minFlavor: CCFlavor(
                        name: "nano",
                        mem: 256,
                        cpus: 1,
                        gpus: 0,
                        disk: 1024,
                        price: 0.02,
                        available: true,
                        microservice: false,
                        machine_learning: false,
                        nice: 0,
                        price_id: "nano_price",
                        memory: nil,
                        cpuFactor: 1.0,
                        memFactor: 1.0
                    ),
                    maxFlavor: CCFlavor(
                        name: "s",
                        mem: 1024,
                        cpus: 1,
                        gpus: 0,
                        disk: 1024,
                        price: 0.08,
                        available: true,
                        microservice: false,
                        machine_learning: false,
                        nice: 0,
                        price_id: "s_price",
                        memory: nil,
                        cpuFactor: 1.0,
                        memFactor: 1.0
                    ),
                    flavors: nil
                )
            ),
            cleverCloudSDK: CleverCloudSDKFactory.create(
                consumerKey: "demo_key",
                consumerSecret: "demo_secret",
                accessToken: "demo_token",
                accessTokenSecret: "demo_token_secret",
                enableDebugLogging: true
            ),
            organizationId: nil
        )
    }
}

// MARK: - Add Domain Sheet

extension ApplicationDetailView {
    private var addDomainSheet: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Instructions
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                        Text("Add Custom Domain")
                            .font(.headline)
                    }

                    Text("Enter your domain name without http:// or https://")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text("Examples: example.com, app.example.com, subdomain.example.org")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))
                .cornerRadius(10)

                // Domain input field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Domain Name")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    TextField("example.com", text: $newDomainName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }

                // DNS Configuration reminder
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("DNS Configuration Required")
                            .font(.headline)
                    }

                    Text("After adding this domain, configure your DNS provider:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        // CNAME option
                        HStack(alignment: .top) {
                            Text("CNAME:")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .frame(width: 50, alignment: .leading)

                            HStack {
                                Text("domain.par.clever-cloud.com.")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.blue)

                                Button(action: {
                                    UIPasteboard.general.string = "domain.par.clever-cloud.com."
                                }) {
                                    Image(systemName: "doc.on.doc")
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                }
                            }
                        }

                        Text("OR")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 2)

                        // A Records option
                        HStack(alignment: .top) {
                            Text("A Records:")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .frame(width: 50, alignment: .leading)

                            Text("91.208.207.214-218, 220-223")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(6)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)

                Spacer()
            }
            .padding()
            .navigationTitle("Add Domain")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        newDomainName = ""
                        showingAddDomain = false
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        addDomain()
                    }
                    .disabled(newDomainName.isEmpty || isAddingDomain)
                }
            }
        }
    }
}

// MARK: - Deployment Row View

struct DeploymentRow: View {
    let deployment: CCDeployment

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Status icon
            VStack {
                statusIcon
                    .font(.title2)
            }
            .frame(width: 40)

            // Deployment details
            VStack(alignment: .leading, spacing: 4) {
                // First row: action and state
                HStack {
                    Text(deployment.displayAction)
                        .font(.headline)
                    Spacer()
                    Text(deployment.displayState)
                        .font(.caption)
                        .fontWeight(.semibold)
                }

                // Second row: commit and branch
                if let commit = deployment.shortCommit, let branch = deployment.branch {
                    HStack {
                        Label(commit, systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("•")
                            .foregroundColor(.secondary)
                        Label(branch, systemImage: "arrow.branch")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if let branch = deployment.branch {
                    Label(branch, systemImage: "arrow.branch")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Third row: timestamp and duration
                HStack {
                    Label(deployment.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if let duration = deployment.humanDuration {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text("Duration: \(duration)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // Triggered by info
                if let triggeredBy = deployment.triggeredBy {
                    Label("Triggered by \(triggeredBy)", systemImage: "person.circle")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }

    private var statusIcon: some View {
        Group {
            switch deployment.state.uppercased() {
            case "WIP", "QUEUED":
                ProgressView()
                    .scaleEffect(0.8)
            case "SUCCESS":
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            case "FAIL", "FAILED":
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
            case "CANCELLED":
                Image(systemName: "stop.circle.fill")
                    .foregroundColor(.gray)
            default:
                Image(systemName: "circle.fill")
                    .foregroundColor(.blue)
            }
        }
    }
}
