import Foundation
import UserNotifications
import Combine
import UIKit

// MARK: - NetworkGroupNotificationService
/// Service for managing push notifications related to network groups
@MainActor
class NetworkGroupNotificationService: ObservableObject {
    
    // MARK: - Singleton
    static let shared = NetworkGroupNotificationService()
    
    // MARK: - Properties
    @Published var isNotificationsEnabled = false
    @Published var monitoredNetworkGroups: Set<String> = []
    
    private var cancellables = Set<AnyCancellable>()
    private let notificationCenter = UNUserNotificationCenter.current()
    
    // MARK: - Initialization
    private init() {
        loadSettings()
        checkNotificationPermissions()
    }
    
    // MARK: - Public Methods
    
    /// Request notification permissions
    func requestNotificationPermissions() {
        notificationCenter.requestAuthorization(options: [.alert, .badge, .sound]) { [weak self] granted, error in
            DispatchQueue.main.async {
                self?.isNotificationsEnabled = granted
                if granted {
                    self?.registerForPushNotifications()
                }
            }
        }
    }
    
    /// Enable monitoring for a network group
    func enableMonitoring(for networkGroupId: String) {
        monitoredNetworkGroups.insert(networkGroupId)
        saveSettings()
    }
    
    /// Disable monitoring for a network group
    func disableMonitoring(for networkGroupId: String) {
        monitoredNetworkGroups.remove(networkGroupId)
        saveSettings()
    }
    
    /// Check if monitoring is enabled for a network group
    func isMonitoringEnabled(for networkGroupId: String) -> Bool {
        monitoredNetworkGroups.contains(networkGroupId)
    }
    
    /// Handle incoming network group state change
    func handleStateChange(
        networkGroup: CCNetworkGroup,
        previousState: NetworkGroupState,
        newState: NetworkGroupState
    ) {
        guard isNotificationsEnabled,
              isMonitoringEnabled(for: networkGroup.id) else { return }
        
        // Create notification based on state change
        let notification = createNotification(
            for: networkGroup,
            previousState: previousState,
            newState: newState
        )
        
        // Schedule notification
        scheduleNotification(notification)
    }
    
    /// Handle member state change
    func handleMemberStateChange(
        networkGroup: CCNetworkGroup,
        member: CCNetworkGroupMember,
        previousStatus: String?,
        newStatus: String?
    ) {
        guard isNotificationsEnabled,
              isMonitoringEnabled(for: networkGroup.id),
              previousStatus != newStatus else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Network Group: \(networkGroup.name)"
        
        switch (previousStatus?.lowercased(), newStatus?.lowercased()) {
        case (_, "connected"):
            content.subtitle = "Member Connected"
            content.body = "\(member.name) is now connected to the network"
            content.sound = .default
            
        case ("connected", _):
            content.subtitle = "Member Disconnected"
            content.body = "\(member.name) has disconnected from the network"
            content.sound = UNNotificationSound(named: UNNotificationSoundName("disconnect.caf"))
            
        default:
            content.subtitle = "Member Status Changed"
            content.body = "\(member.name) status: \(newStatus ?? "Unknown")"
        }
        
        content.badge = 1
        content.categoryIdentifier = "NETWORK_GROUP_MEMBER"
        content.userInfo = [
            "networkGroupId": networkGroup.id,
            "memberId": member.id,
            "memberName": member.name
        ]
        
        scheduleNotification(content, identifier: "member_\(member.id)_\(Date().timeIntervalSince1970)")
    }
    
    /// Handle peer state change
    func handlePeerStateChange(
        networkGroup: CCNetworkGroup,
        peer: CCNetworkGroupPeer,
        previousStatus: String?,
        newStatus: String?
    ) {
        guard isNotificationsEnabled,
              isMonitoringEnabled(for: networkGroup.id),
              previousStatus != newStatus else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Network Group: \(networkGroup.name)"
        
        switch (previousStatus?.lowercased(), newStatus?.lowercased()) {
        case (_, "connected"):
            content.subtitle = "Peer Connected"
            content.body = "\(peer.name) has established connection"
            content.sound = .default
            
        case ("connected", _):
            content.subtitle = "Peer Disconnected"
            content.body = "\(peer.name) connection lost"
            content.sound = UNNotificationSound(named: UNNotificationSoundName("disconnect.caf"))
            
        default:
            content.subtitle = "Peer Status Changed"
            content.body = "\(peer.name) status: \(newStatus ?? "Unknown")"
        }
        
        content.badge = 1
        content.categoryIdentifier = "NETWORK_GROUP_PEER"
        content.userInfo = [
            "networkGroupId": networkGroup.id,
            "peerId": peer.id,
            "peerName": peer.name
        ]
        
        scheduleNotification(content, identifier: "peer_\(peer.id)_\(Date().timeIntervalSince1970)")
    }
    
    // MARK: - Private Methods
    
    private func loadSettings() {
        if let data = UserDefaults.standard.data(forKey: "NetworkGroupNotificationSettings"),
           let settings = try? JSONDecoder().decode(NotificationSettings.self, from: data) {
            monitoredNetworkGroups = Set(settings.monitoredNetworkGroups)
        }
    }
    
    private func saveSettings() {
        let settings = NotificationSettings(
            monitoredNetworkGroups: Array(monitoredNetworkGroups)
        )
        
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: "NetworkGroupNotificationSettings")
        }
    }
    
    private func checkNotificationPermissions() {
        notificationCenter.getNotificationSettings { [weak self] settings in
            let isAuthorized = settings.authorizationStatus == .authorized
            DispatchQueue.main.async {
                self?.isNotificationsEnabled = isAuthorized
            }
        }
    }
    
    private func registerForPushNotifications() {
        // Register notification categories
        registerNotificationCategories()
        
        // Register for remote notifications
        DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }
    
    private func registerNotificationCategories() {
        // Network Group Category
        let viewAction = UNNotificationAction(
            identifier: "VIEW_NETWORK_GROUP",
            title: "View",
            options: .foreground
        )
        
        let dismissAction = UNNotificationAction(
            identifier: "DISMISS",
            title: "Dismiss",
            options: .destructive
        )
        
        let networkGroupCategory = UNNotificationCategory(
            identifier: "NETWORK_GROUP",
            actions: [viewAction, dismissAction],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "Network Group Update",
            options: .customDismissAction
        )
        
        // Member Category
        let memberCategory = UNNotificationCategory(
            identifier: "NETWORK_GROUP_MEMBER",
            actions: [viewAction, dismissAction],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "Member Status Update",
            options: .customDismissAction
        )
        
        // Peer Category
        let peerCategory = UNNotificationCategory(
            identifier: "NETWORK_GROUP_PEER",
            actions: [viewAction, dismissAction],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "Peer Status Update",
            options: .customDismissAction
        )
        
        notificationCenter.setNotificationCategories([
            networkGroupCategory,
            memberCategory,
            peerCategory
        ])
    }
    
    private func createNotification(
        for networkGroup: CCNetworkGroup,
        previousState: NetworkGroupState,
        newState: NetworkGroupState
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Network Group Update"
        content.subtitle = networkGroup.name
        
        switch (previousState, newState) {
        case (.inactive, .active):
            content.body = "Network group is now active and ready"
            content.sound = .default
            
        case (.active, .inactive):
            content.body = "Network group has become inactive"
            content.sound = UNNotificationSound(named: UNNotificationSoundName("alert.caf"))
            
        case (.active, .error):
            content.body = "Network group encountered an error"
            content.sound = UNNotificationSound(named: UNNotificationSoundName("error.caf"))
            
        case (.error, .active):
            content.body = "Network group recovered from error"
            content.sound = .default
            
        default:
            content.body = "Network group status changed to \(newState.rawValue)"
        }
        
        content.badge = 1
        content.categoryIdentifier = "NETWORK_GROUP"
        content.userInfo = [
            "networkGroupId": networkGroup.id,
            "networkGroupName": networkGroup.name,
            "previousState": previousState.rawValue,
            "newState": newState.rawValue
        ]
        
        return content
    }
    
    private func scheduleNotification(_ content: UNMutableNotificationContent, identifier: String? = nil) {
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let notificationId = identifier ?? UUID().uuidString
        let request = UNNotificationRequest(
            identifier: notificationId,
            content: content,
            trigger: trigger
        )
        
        notificationCenter.add(request) { error in
            if let error = error {
                print("❌ Failed to schedule notification: \(error)")
            }
        }
    }
}

// MARK: - Supporting Types

/// Network group state for notifications
enum NetworkGroupState: String, Codable {
    case active
    case inactive
    case error
    case creating
    case deleting
    
    init(from status: String?) {
        switch status?.lowercased() {
        case "active":
            self = .active
        case "creating":
            self = .creating
        case "deleting":
            self = .deleting
        case "error", "failed":
            self = .error
        default:
            self = .inactive
        }
    }
}

/// Notification settings model
struct NotificationSettings: Codable {
    let monitoredNetworkGroups: [String]
}

// MARK: - NetworkGroupMonitor
/// Monitor for tracking network group state changes
@MainActor
class NetworkGroupMonitor: ObservableObject {
    
    // MARK: - Properties
    private let organizationId: String
    private let networkGroupId: String
    private let cleverCloudSDK: CleverCloudSDK
    private let notificationService = NetworkGroupNotificationService.shared
    
    @Published private(set) var networkGroup: CCNetworkGroup?
    @Published private(set) var members: [CCNetworkGroupMember] = []
    @Published private(set) var peers: [CCNetworkGroupPeer] = []
    
    private var previousMemberStates: [String: String] = [:]
    private var previousPeerStates: [String: String] = [:]
    private var previousGroupState: NetworkGroupState?
    
    private var monitoringTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init(organizationId: String, networkGroupId: String, cleverCloudSDK: CleverCloudSDK) {
        self.organizationId = organizationId
        self.networkGroupId = networkGroupId
        self.cleverCloudSDK = cleverCloudSDK
    }
    
    // MARK: - Public Methods
    
    /// Start monitoring the network group
    func startMonitoring(interval: TimeInterval = 30) {
        // Initial fetch
        fetchNetworkGroupData()
        
        // Set up periodic monitoring
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.fetchNetworkGroupData()
            }
        }
    }
    
    /// Stop monitoring
    func stopMonitoring() {
        monitoringTimer?.invalidate()
        monitoringTimer = nil
    }
    
    // MARK: - Private Methods
    
    private func fetchNetworkGroupData() {
        cleverCloudSDK.networkGroups.getCompleteNetworkGroupData(
            organizationId: organizationId,
            networkGroupId: networkGroupId
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    print("❌ Failed to fetch network group data: \(error)")
                }
            },
            receiveValue: { [weak self] (group, members, peers) in
                self?.handleNetworkGroupUpdate(group: group, members: members, peers: peers)
            }
        )
        .store(in: &cancellables)
    }
    
    private func handleNetworkGroupUpdate(
        group: CCNetworkGroup,
        members: [CCNetworkGroupMember],
        peers: [CCNetworkGroupPeer]
    ) {
        // Check for network group state change
        let newGroupState = NetworkGroupState(from: group.status)
        if let previousState = previousGroupState, previousState != newGroupState {
            notificationService.handleStateChange(
                networkGroup: group,
                previousState: previousState,
                newState: newGroupState
            )
        }
        previousGroupState = newGroupState
        
        // Check for member state changes
        for member in members {
            let previousStatus = previousMemberStates[member.id]
            if previousStatus != member.status {
                notificationService.handleMemberStateChange(
                    networkGroup: group,
                    member: member,
                    previousStatus: previousStatus,
                    newStatus: member.status
                )
                previousMemberStates[member.id] = member.status
            }
        }
        
        // Check for peer state changes
        for peer in peers {
            let previousStatus = previousPeerStates[peer.id]
            if previousStatus != peer.status {
                notificationService.handlePeerStateChange(
                    networkGroup: group,
                    peer: peer,
                    previousStatus: previousStatus,
                    newStatus: peer.status
                )
                previousPeerStates[peer.id] = peer.status
            }
        }
        
        // Update published properties
        self.networkGroup = group
        self.members = members
        self.peers = peers
    }
} 