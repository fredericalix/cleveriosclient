import SwiftUI
import Combine

struct ApplicationLogsView: View {
    let application: CCApplication
    @ObservedObject var cleverCloudSDK: CleverCloudSDK
    let organizationId: String?
    
    // Bindings from parent
    @Binding var logs: [CCLogEntry]
    @Binding var isLoadingLogs: Bool
    @Binding var logsError: String?
    @Binding var searchText: String
    @Binding var selectedLogLevel: CCLogLevel?
    @Binding var isPaused: Bool
    @Binding var autoScroll: Bool
    @Binding var logsTimer: Timer?
    
    @State private var cancellables = Set<AnyCancellable>()
    @State private var scrollViewProxy: ScrollViewProxy?
    
    // Computed filtered logs
    private var filteredLogs: [CCLogEntry] {
        logs.filter { log in
            // Filter by search text
            let matchesSearch = searchText.isEmpty || 
                log.message.localizedCaseInsensitiveContains(searchText)
            
            // Filter by log level
            let matchesLevel = selectedLogLevel == nil || log.level == selectedLogLevel
            
            return matchesSearch && matchesLevel
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            logsToolbar
            
            Divider()
            
            // Logs content
            if isLoadingLogs && logs.isEmpty {
                // Initial loading
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Loading logs...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = logsError {
                // Error state
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 50))
                        .foregroundColor(.orange)
                    Text("Failed to load logs")
                        .font(.title3)
                        .fontWeight(.medium)
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button("Retry") {
                        loadLogs()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredLogs.isEmpty {
                // Empty state
                VStack(spacing: 16) {
                    Image(systemName: logs.isEmpty ? "doc.text" : "magnifyingglass")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                    Text(logs.isEmpty ? "No logs available" : "No logs match your filters")
                        .font(.title3)
                        .fontWeight(.medium)
                    Text(logs.isEmpty ? 
                         "Logs will appear here when your application generates them" : 
                         "Try adjusting your search or filter criteria")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Logs list
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(filteredLogs) { log in
                                LogEntryRow(log: log)
                                    .id(log.id)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .onAppear {
                        scrollViewProxy = proxy
                        if autoScroll && !filteredLogs.isEmpty {
                            proxy.scrollTo(filteredLogs.last?.id, anchor: .bottom)
                        }
                    }
                    .onChange(of: filteredLogs.count) {
                        if autoScroll && !filteredLogs.isEmpty {
                            withAnimation {
                                proxy.scrollTo(filteredLogs.last?.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            
            // Status bar
            statusBar
        }
        .onAppear {
            startLogStreaming()
        }
        .onDisappear {
            stopLogStreaming()
        }
    }
    
    // MARK: - Toolbar
    
    private var logsToolbar: some View {
        VStack(spacing: 12) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search logs...", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Controls row
            HStack {
                // Log level filter
                Menu {
                    Button("All Levels") {
                        selectedLogLevel = nil
                    }
                    Divider()
                    ForEach(CCLogLevel.allCases, id: \.self) { level in
                        Button(action: { selectedLogLevel = level }) {
                            Label(level.rawValue.capitalized, systemImage: level.icon)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: selectedLogLevel?.icon ?? "line.3.horizontal.decrease.circle")
                        Text(selectedLogLevel?.rawValue.capitalized ?? "All Levels")
                        Image(systemName: "chevron.down")
                            .font(.caption)
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(.systemGray5))
                    .cornerRadius(8)
                }
                
                Spacer()
                
                // Auto-scroll toggle
                Toggle("", isOn: $autoScroll)
                    .labelsHidden()
                    .toggleStyle(AutoScrollToggleStyle())
                
                // Pause/Resume button
                Button(action: togglePause) {
                    HStack(spacing: 4) {
                        Image(systemName: isPaused ? "play.fill" : "pause.fill")
                        Text(isPaused ? "Resume" : "Pause")
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(isPaused ? Color.green : Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                
                // Clear logs button
                Button(action: clearLogs) {
                    Image(systemName: "trash")
                        .font(.subheadline)
                        .padding(6)
                        .background(Color(.systemGray5))
                        .cornerRadius(8)
                }
                .disabled(logs.isEmpty)
            }
        }
        .padding()
    }
    
    // MARK: - Status Bar
    
    private var statusBar: some View {
        HStack {
            // Log count
            Label("\(filteredLogs.count) logs", systemImage: "doc.text")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            // Loading indicator
            if isLoadingLogs {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Loading...")
                        .font(.caption)
                }
            }
            
            // Last update time
            if !logs.isEmpty {
                Text("Last update: \(formatTime(Date()))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
    }
    
    // MARK: - Helper Methods
    
    private func loadLogs() {
        isLoadingLogs = true
        logsError = nil
        
        cleverCloudSDK.applications.getApplicationLogs(
            applicationId: application.id,
            organizationId: organizationId,
            limit: 1000
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { completion in
                isLoadingLogs = false
                if case .failure(let error) = completion {
                    logsError = error.localizedDescription
                    print("❌ Failed to load application logs: \(error)")
                }
            },
            receiveValue: { newLogs in
                logs = newLogs
                print("✅ Loaded \(newLogs.count) application logs")
            }
        )
        .store(in: &cancellables)
    }
    
    private func startLogStreaming() {
        // Initial load
        loadLogs()
        
        // Start periodic updates if not paused
        if !isPaused {
            logsTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                Task { @MainActor in
                    if !isPaused {
                        loadLogs()
                    }
                }
            }
        }
    }
    
    private func stopLogStreaming() {
        logsTimer?.invalidate()
        logsTimer = nil
    }
    
    private func togglePause() {
        isPaused.toggle()
        
        if isPaused {
            stopLogStreaming()
        } else {
            startLogStreaming()
        }
    }
    
    private func clearLogs() {
        logs.removeAll()
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Log Entry Row

struct LogEntryRow: View {
    let log: CCLogEntry
    @State private var showFullMessage = false
    @State private var showCopiedToast = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header row
            HStack(alignment: .top) {
                // Level icon and color
                Image(systemName: log.level.icon)
                    .foregroundColor(colorForLogLevel(log.level))
                    .font(.caption)
                
                // Timestamp
                Text(formatTimestamp(log.timestamp))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Source
                if let source = log.source {
                    Text("[\(source)]")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Copy button
                Button(action: copyLog) {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Message
            Text(log.message)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(showFullMessage ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showFullMessage.toggle()
                    }
                }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
        .overlay(
            // Copied toast
            showCopiedToast ? 
            Text("Copied!")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(4)
                .transition(.scale.combined(with: .opacity))
                .offset(y: -20)
            : nil,
            alignment: .top
        )
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

    private func copyLog() {
        let fullLog = "[\(formatTimestamp(log.timestamp))] [\(log.level.rawValue.uppercased())] \(log.message)"
        UIPasteboard.general.string = fullLog
        
        withAnimation {
            showCopiedToast = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showCopiedToast = false
            }
        }
    }
}

// MARK: - Custom Toggle Style

struct AutoScrollToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(action: { configuration.isOn.toggle() }) {
            HStack(spacing: 4) {
                Image(systemName: configuration.isOn ? "arrow.down.circle.fill" : "arrow.down.circle")
                Text("Auto-scroll")
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(configuration.isOn ? Color.blue : Color(.systemGray5))
            .foregroundColor(configuration.isOn ? .white : .primary)
            .cornerRadius(8)
        }
    }
}

// MARK: - Preview

#Preview {
    ApplicationLogsView(
        application: CCApplication(
            id: "app_123",
            name: "My Test App",
            description: "A sample application",
            zone: "par",
            zoneId: "par_01",
            instance: CCInstance(
                type: "nano",
                version: "1.0",
                variant: nil,
                minInstances: 1,
                maxInstances: 3,
                maxAllowedInstances: 5,
                minFlavor: CCFlavor(
                    name: "nano",
                    mem: 512,
                    cpus: 1,
                    gpus: 0,
                    disk: 10,
                    price: 0.0,
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
                    name: "nano",
                    mem: 512,
                    cpus: 1,
                    gpus: 0,
                    disk: 10,
                    price: 0.0,
                    available: true,
                    microservice: false,
                    machine_learning: false,
                    nice: 0,
                    price_id: "nano_price",
                    memory: nil,
                    cpuFactor: 1.0,
                    memFactor: 1.0
                ),
                flavors: nil
            )
        ),
        cleverCloudSDK: CleverCloudSDK(configuration: CCConfiguration(apiToken: "preview-token")),
        organizationId: nil,
        logs: .constant([]),
        isLoadingLogs: .constant(false),
        logsError: .constant(nil),
        searchText: .constant(""),
        selectedLogLevel: .constant(nil),
        isPaused: .constant(false),
        autoScroll: .constant(true),
        logsTimer: .constant(nil)
    )
} 