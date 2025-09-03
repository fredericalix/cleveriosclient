import SwiftUI
import Combine

// MARK: - BulkOperationsView
/// Modern interface for performing bulk operations on Network Group members and peers
struct BulkOperationsView: View {
    
    // MARK: - Environment
    @Environment(\.dismiss) private var dismiss
    @Environment(AppCoordinator.self) private var coordinator: AppCoordinator
    
    // MARK: - Properties
    let networkGroup: CCNetworkGroup
    let organizationId: String
    let operationType: BulkOperationType
    let onOperationCompleted: ([String]) -> Void
    
    // MARK: - State
    @State private var members: [CCNetworkGroupMember] = []
    @State private var peers: [CCNetworkGroupPeer] = []
    @State private var selectedItems = Set<String>()
    @State private var isLoading = false
    @State private var isOperating = false
    @State private var errorMessage: String?
    @State private var operationResults: [BulkOperationResult] = []
    @State private var showingResults = false
    @State private var operationProgress: Float = 0.0
    @State private var currentOperationItem = ""
    @State private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Computed Properties
    private var selectedItemsCount: Int {
        selectedItems.count
    }
    
    private var availableItems: [BulkOperationItem] {
        switch operationType {
        case .removeMembers:
            return members.map { BulkOperationItem(id: $0.id, name: $0.name, type: $0.type.displayName, subtitle: $0.resourceId) }
        case .removePeers:
            return peers.map { BulkOperationItem(id: $0.id, name: $0.name, type: $0.isExternal ? "External Peer" : "Internal Peer", subtitle: $0.endpoint ?? "No endpoint") }
        case .addMembers, .addPeers:
            return [] // These will be handled by existing specialized views
        }
    }
    
    // MARK: - Body
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header Section
                headerSection
                    .background(Color(.systemGray6))
                
                Divider()
                
                // Content Area
                Group {
                    if isLoading {
                        loadingView
                    } else if availableItems.isEmpty {
                        emptyStateView
                    } else {
                        VStack(spacing: 0) {
                            // Selection Controls
                            selectionControlsSection
                                .padding()
                                .background(Color(.systemBackground))
                            
                            Divider()
                            
                            // Items List
                            itemsList
                        }
                    }
                }
                
                Spacer()
                
                // Action Section
                actionSection
                    .padding()
                    .background(Color(.systemBackground))
            }
            .navigationTitle(operationType.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadData()
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "Unknown error occurred")
            }
            .sheet(isPresented: $showingResults) {
                BulkOperationResultsView(
                    operation: operationType,
                    results: operationResults,
                    onDismiss: {
                        showingResults = false
                        onOperationCompleted(operationResults.compactMap { $0.success ? $0.itemId : nil })
                        dismiss()
                    }
                )
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: operationType.icon)
                    .font(.title2)
                    .foregroundColor(operationType.color)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(operationType.title)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("on \(networkGroup.name)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Selection Counter
                if !selectedItems.isEmpty {
                    VStack {
                        Text("\(selectedItemsCount)")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(operationType.color)
                        Text("selected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Warning Banner for Destructive Operations
            if operationType.isDestructive {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    
                    Text("This operation cannot be undone. Selected items will be permanently removed.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
    }
    
    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
                .scaleEffect(1.5)
            
            Text("Loading \(operationType.dataType)...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: operationType.emptyStateIcon)
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No \(operationType.dataType) Available")
                .font(.headline)
                .fontWeight(.semibold)
            
            Text("There are no \(operationType.dataType.lowercased()) in this network group to perform bulk operations on.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Selection Controls Section
    private var selectionControlsSection: some View {
        HStack {
            // Select All/None Button
            Button(action: toggleSelectAll) {
                HStack {
                    Image(systemName: selectedItems.count == availableItems.count ? "checkmark.square.fill" : (selectedItems.isEmpty ? "square" : "minus.square.fill"))
                        .foregroundColor(.blue)
                    
                    Text(selectedItems.count == availableItems.count ? "Deselect All" : "Select All")
                        .fontWeight(.medium)
                }
            }
            .disabled(availableItems.isEmpty)
            
            Spacer()
            
            // Selection Summary
            Text("\(selectedItemsCount) of \(availableItems.count) selected")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Items List
    private var itemsList: some View {
        List(availableItems) { item in
            itemRow(item)
                .onTapGesture {
                    toggleSelection(item.id)
                }
        }
        .listStyle(PlainListStyle())
    }
    
    // MARK: - Item Row
    private func itemRow(_ item: BulkOperationItem) -> some View {
        let isSelected = selectedItems.contains(item.id)
        
        return HStack(spacing: 12) {
            // Selection Indicator
            Button(action: { toggleSelection(item.id) }) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .secondary)
                    .font(.title3)
            }
            
            // Item Icon
            Image(systemName: getIconForItemType(item.type))
                .foregroundColor(getColorForItemType(item.type))
                .font(.title3)
                .frame(width: 30)
            
            // Item Info
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text(item.type)
                    .font(.caption)
                    .foregroundColor(.blue)
                
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Status Indicator (for operation progress)
            if isOperating && selectedItems.contains(item.id) {
                if operationResults.contains(where: { $0.itemId == item.id }) {
                    let result = operationResults.first { $0.itemId == item.id }!
                    Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(result.success ? .green : .red)
                } else if currentOperationItem == item.id {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "clock")
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? operationType.color.opacity(0.1) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? operationType.color : Color.clear, lineWidth: 2)
                )
        )
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
    
    // MARK: - Action Section
    private var actionSection: some View {
        VStack(spacing: 12) {
            // Operation Progress (if running)
            if isOperating {
                VStack(spacing: 8) {
                    HStack {
                        Text("Operation Progress")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        Text("\(Int(operationProgress * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    ProgressView(value: operationProgress)
                        .progressViewStyle(LinearProgressViewStyle())
                    
                    if !currentOperationItem.isEmpty {
                        Text("Processing: \(currentOperationItem)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
            
            // Action Button
            Button(action: performBulkOperation) {
                HStack {
                    if isOperating {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: operationType.actionIcon)
                    }
                    
                    Text(isOperating ? "Processing..." : "\(operationType.actionTitle) \(selectedItemsCount) Item\(selectedItemsCount == 1 ? "" : "s")")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .foregroundColor(.white)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(selectedItems.isEmpty ? Color.gray : operationType.color)
                )
            }
            .disabled(selectedItems.isEmpty || isOperating)
        }
    }
    
    // MARK: - Helper Methods
    private func loadData() {
        isLoading = true
        errorMessage = nil
        
        let membersPublisher = coordinator.cleverCloudSDK.networkGroups.getNetworkGroupMembers(
            organizationId: organizationId,
            networkGroupId: networkGroup.id
        )
        
        let peersPublisher = coordinator.cleverCloudSDK.networkGroups.getNetworkGroupPeers(
            organizationId: organizationId,
            networkGroupId: networkGroup.id
        )
        
        Publishers.CombineLatest(membersPublisher, peersPublisher)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    isLoading = false
                    if case .failure(let error) = completion {
                        errorMessage = "Failed to load data: \(error.localizedDescription)"
                    }
                },
                receiveValue: { (loadedMembers, loadedPeers) in
                    members = loadedMembers
                    peers = loadedPeers
                }
            )
            .store(in: &cancellables)
    }
    
    private func toggleSelection(_ itemId: String) {
        if selectedItems.contains(itemId) {
            selectedItems.remove(itemId)
        } else {
            selectedItems.insert(itemId)
        }
    }
    
    private func toggleSelectAll() {
        if selectedItems.count == availableItems.count {
            selectedItems.removeAll()
        } else {
            selectedItems = Set(availableItems.map(\.id))
        }
    }
    
    private func performBulkOperation() {
        guard !selectedItems.isEmpty else { return }
        
        isOperating = true
        operationResults.removeAll()
        operationProgress = 0.0
        
        let selectedItemsList = Array(selectedItems)
        let totalItems = selectedItemsList.count
        
        // Create a sequence of operations
        let operations = selectedItemsList.enumerated().map { (index, itemId) -> AnyPublisher<BulkOperationResult, Never> in
            
            // Update progress
            DispatchQueue.main.async {
                operationProgress = Float(index) / Float(totalItems)
                currentOperationItem = availableItems.first { $0.id == itemId }?.name ?? itemId
            }
            
            // Perform the appropriate operation
            let operationPublisher: AnyPublisher<Void, CCError>
            
            switch operationType {
            case .removeMembers:
                if let member = members.first(where: { $0.id == itemId }) {
                    operationPublisher = coordinator.cleverCloudSDK.networkGroups.removeNetworkGroupMember(
                        organizationId: organizationId,
                        networkGroupId: networkGroup.id,
                        memberId: member.resourceId
                    )
                } else {
                    operationPublisher = Fail(error: CCError.resourceNotFound).eraseToAnyPublisher()
                }
                
            case .removePeers:
                if let peer = peers.first(where: { $0.id == itemId }) {
                    if peer.isExternal {
                        operationPublisher = coordinator.cleverCloudSDK.networkGroups.removeNetworkGroupExternalPeer(
                            organizationId: organizationId,
                            networkGroupId: networkGroup.id,
                            peerId: peer.id
                        )
                    } else {
                        operationPublisher = coordinator.cleverCloudSDK.networkGroups.removeNetworkGroupPeer(
                            organizationId: organizationId,
                            networkGroupId: networkGroup.id,
                            peerId: peer.id
                        )
                    }
                } else {
                    operationPublisher = Fail(error: CCError.resourceNotFound).eraseToAnyPublisher()
                }
                
            case .addMembers, .addPeers:
                // These should be handled by specialized views
                operationPublisher = Fail(error: CCError.invalidParameters("Operation not supported in bulk view")).eraseToAnyPublisher()
            }
            
            return operationPublisher
                .map { BulkOperationResult(itemId: itemId, success: true, error: nil) }
                .catch { error in
                    Just(BulkOperationResult(itemId: itemId, success: false, error: error.localizedDescription))
                }
                .eraseToAnyPublisher()
        }
        
        // Execute operations sequentially
        Publishers.Sequence(sequence: operations)
            .flatMap(maxPublishers: .max(1)) { $0 }
            .collect()
            .receive(on: DispatchQueue.main)
            .sink { results in
                operationResults = results
                operationProgress = 1.0
                currentOperationItem = ""
                isOperating = false
                showingResults = true
            }
            .store(in: &cancellables)
    }
    
    private func getIconForItemType(_ type: String) -> String {
        switch type.lowercased() {
        case "application":
            return "app.fill"
        case "add-on":
            return "puzzlepiece.extension.fill"
        case "external peer":
            return "globe"
        case "internal peer":
            return "house"
        default:
            return "questionmark.circle"
        }
    }
    
    private func getColorForItemType(_ type: String) -> Color {
        switch type.lowercased() {
        case "application":
            return .green
        case "add-on":
            return .orange
        case "external peer":
            return .blue
        case "internal peer":
            return .purple
        default:
            return .secondary
        }
    }
}

// MARK: - Supporting Types

enum BulkOperationType {
    case addMembers
    case removeMembers
    case addPeers
    case removePeers
    
    var title: String {
        switch self {
        case .addMembers: return "Add Multiple Members"
        case .removeMembers: return "Remove Multiple Members"
        case .addPeers: return "Add Multiple Peers"
        case .removePeers: return "Remove Multiple Peers"
        }
    }
    
    var icon: String {
        switch self {
        case .addMembers: return "person.3.fill"
        case .removeMembers: return "person.3.fill"
        case .addPeers: return "network.badge.shield.half.filled"
        case .removePeers: return "network.badge.shield.half.filled"
        }
    }
    
    var color: Color {
        switch self {
        case .addMembers, .addPeers: return .blue
        case .removeMembers, .removePeers: return .red
        }
    }
    
    var actionTitle: String {
        switch self {
        case .addMembers: return "Add"
        case .removeMembers: return "Remove"
        case .addPeers: return "Add"
        case .removePeers: return "Remove"
        }
    }
    
    var actionIcon: String {
        switch self {
        case .addMembers, .addPeers: return "plus.circle.fill"
        case .removeMembers, .removePeers: return "minus.circle.fill"
        }
    }
    
    var dataType: String {
        switch self {
        case .addMembers, .removeMembers: return "Members"
        case .addPeers, .removePeers: return "Peers"
        }
    }
    
    var emptyStateIcon: String {
        switch self {
        case .addMembers, .removeMembers: return "person.3"
        case .addPeers, .removePeers: return "network"
        }
    }
    
    var isDestructive: Bool {
        switch self {
        case .addMembers, .addPeers: return false
        case .removeMembers, .removePeers: return true
        }
    }
}

struct BulkOperationItem: Identifiable {
    let id: String
    let name: String
    let type: String
    let subtitle: String?
}

struct BulkOperationResult {
    let itemId: String
    let success: Bool
    let error: String?
}



// MARK: - Results View
struct BulkOperationResultsView: View {
    let operation: BulkOperationType
    let results: [BulkOperationResult]
    let onDismiss: () -> Void
    
    private var successCount: Int {
        results.filter(\.success).count
    }
    
    private var failureCount: Int {
        results.filter { !$0.success }.count
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Summary Section
                    VStack(spacing: 16) {
                        Image(systemName: successCount == results.count ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(successCount == results.count ? .green : .orange)
                        
                        Text("Operation Complete")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        VStack(spacing: 4) {
                            Text("\(successCount) successful, \(failureCount) failed")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            if successCount > 0 {
                                Text("✅ \(successCount) items processed successfully")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                            
                            if failureCount > 0 {
                                Text("❌ \(failureCount) items failed to process")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(16)
                    
                    // Detailed Results
                    if failureCount > 0 {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Failed Operations")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            ForEach(results.filter { !$0.success }, id: \.itemId) { result in
                                HStack {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                    
                                    VStack(alignment: .leading) {
                                        Text(result.itemId)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        
                                        if let error = result.error {
                                            Text(error)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    
                                    Spacer()
                                }
                                .padding()
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(12)
                            }
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(16)
                    }
                }
                .padding()
            }
            .navigationTitle("Operation Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        onDismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Preview
#Preview {
    BulkOperationsView(
        networkGroup: CCNetworkGroup.example(),
        organizationId: "orga_example",
        operationType: .removeMembers,
        onOperationCompleted: { _ in }
    )
    .environment(AppCoordinator())
} 