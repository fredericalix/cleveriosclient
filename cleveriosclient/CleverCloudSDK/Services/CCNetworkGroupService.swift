import Foundation
import Combine

// MARK: - CCNetworkGroupService
/// Service for managing Clever Cloud Network Groups - the revolutionary networking feature
/// TEMPORARILY DISABLED: All methods return "feature disabled" errors until Clever Cloud stabilizes this feature
public class CCNetworkGroupService {

    // MARK: - Properties
    private let httpClient: CCHTTPClient

    /// Flag to disable Network Groups functionality temporarily
    private let isNetworkGroupsEnabled = false

    /// Error returned when Network Groups are disabled
    private let featureDisabledError = CCError.invalidParameters("Network Groups feature is temporarily disabled. Please wait for Clever Cloud to stabilize this feature.")

    // MARK: - Initialization
    public init(httpClient: CCHTTPClient) {
        self.httpClient = httpClient
    }
    
    // MARK: - Network Groups Management
    
    /// List all network groups for an organization
    /// - Parameter organizationId: Organization ID
    /// - Returns: Publisher emitting array of network groups or error
    public func getNetworkGroups(organizationId: String) -> AnyPublisher<[CCNetworkGroup], CCError> {
        guard isNetworkGroupsEnabled else {
            return Fail(error: featureDisabledError).eraseToAnyPublisher()
        }
        return httpClient.get("/networkgroups/organisations/\(organizationId)/networkgroups", apiVersion: .v4)
    }
    
    /// Get a specific network group by ID
    /// - Parameters:
    ///   - organizationId: Organization ID
    ///   - networkGroupId: Network group ID
    /// - Returns: Publisher emitting network group or error
    public func getNetworkGroup(organizationId: String, networkGroupId: String) -> AnyPublisher<CCNetworkGroup, CCError> {
        guard isNetworkGroupsEnabled else {
            return Fail(error: featureDisabledError).eraseToAnyPublisher()
        }
        return httpClient.get("/networkgroups/organisations/\(organizationId)/networkgroups/\(networkGroupId)", apiVersion: .v4)
    }
    
    /// Create a new network group
    /// - Parameters:
    ///   - organizationId: Organization ID
    ///   - networkGroup: Network group creation data
    /// - Returns: Publisher emitting created network group or error
    public func createNetworkGroup(organizationId: String, networkGroup: CCNetworkGroupCreate) -> AnyPublisher<CCNetworkGroup, CCError> {
        guard isNetworkGroupsEnabled else {
            return Fail(error: featureDisabledError).eraseToAnyPublisher()
        }
        // First create the network group (expects empty response)
        let createRequest = httpClient.postRaw("/networkgroups/organisations/\(organizationId)/networkgroups", body: networkGroup, apiVersion: .v4)
        
        // Then fetch all network groups to find the newly created one
        return createRequest
            .flatMap { _ -> AnyPublisher<[CCNetworkGroup], CCError> in
                // Small delay to allow the API to process the creation
                return Just(())
                    .delay(for: .milliseconds(500), scheduler: DispatchQueue.main)
                    .setFailureType(to: CCError.self)
                    .flatMap { _ in
                        self.getNetworkGroups(organizationId: organizationId)
                    }
                    .eraseToAnyPublisher()
            }
            .map { networkGroups in
                // Find the network group by name (most recent with matching name)
                return networkGroups
                    .filter { $0.name == networkGroup.name }
                    .max { $0.createdAt ?? Date.distantPast < $1.createdAt ?? Date.distantPast }
            }
            .tryMap { optionalNetworkGroup in
                guard let createdNetworkGroup = optionalNetworkGroup else {
                    throw CCError.invalidParameters("Failed to retrieve created network group")
                }
                return createdNetworkGroup
            }
            .mapError { error in
                if let ccError = error as? CCError {
                    return ccError
                } else {
                    return CCError.unknown(error)
                }
            }
            .eraseToAnyPublisher()
    }
    
    /// Update an existing network group
    /// - Parameters:
    ///   - organizationId: Organization ID
    ///   - networkGroupId: Network group ID to update
    ///   - networkGroupUpdate: Network group update data
    /// - Returns: Publisher emitting updated network group or error
    public func updateNetworkGroup(organizationId: String, networkGroupId: String, networkGroupUpdate: CCNetworkGroupUpdate) -> AnyPublisher<CCNetworkGroup, CCError> {
        guard isNetworkGroupsEnabled else {
            return Fail(error: featureDisabledError).eraseToAnyPublisher()
        }
        return httpClient.put("/networkgroups/organisations/\(organizationId)/networkgroups/\(networkGroupId)", body: networkGroupUpdate, apiVersion: .v4)
    }
    
    /// Delete a network group
    /// - Parameters:
    ///   - organizationId: Organization ID
    ///   - networkGroupId: Network group ID to delete
    /// - Returns: Publisher emitting void response or error
    public func deleteNetworkGroup(organizationId: String, networkGroupId: String) -> AnyPublisher<Void, CCError> {
        guard isNetworkGroupsEnabled else {
            return Fail(error: featureDisabledError).eraseToAnyPublisher()
        }
        return httpClient.deleteRaw("/networkgroups/organisations/\(organizationId)/networkgroups/\(networkGroupId)", apiVersion: .v4)
    }
    
    // MARK: - Network Group Members Management
    
    /// List all members of a network group
    /// - Parameters:
    ///   - organizationId: Organization ID
    ///   - networkGroupId: Network group ID
    /// - Returns: Publisher emitting array of members or error
    public func getNetworkGroupMembers(organizationId: String, networkGroupId: String) -> AnyPublisher<[CCNetworkGroupMember], CCError> {
        guard isNetworkGroupsEnabled else {
            return Fail(error: featureDisabledError).eraseToAnyPublisher()
        }
        return httpClient.get("/networkgroups/organisations/\(organizationId)/networkgroups/\(networkGroupId)/members", apiVersion: .v4)
    }
    
    /// Get a specific member of a network group
    /// - Parameters:
    ///   - organizationId: Organization ID
    ///   - networkGroupId: Network group ID
    ///   - memberId: Member ID
    /// - Returns: Publisher emitting member or error
    public func getNetworkGroupMember(organizationId: String, networkGroupId: String, memberId: String) -> AnyPublisher<CCNetworkGroupMember, CCError> {
        return httpClient.get("/networkgroups/organisations/\(organizationId)/networkgroups/\(networkGroupId)/members/\(memberId)", apiVersion: .v4)
    }
    
    /// Add a member to a network group
    /// - Parameters:
    ///   - organizationId: Organization ID
    ///   - networkGroupId: Network group ID
    ///   - member: Member creation data
    /// - Returns: Publisher emitting added member or error
    public func addNetworkGroupMember(organizationId: String, networkGroupId: String, member: CCNetworkGroupMemberCreate) -> AnyPublisher<CCNetworkGroupMember, CCError> {
        guard isNetworkGroupsEnabled else {
            return Fail(error: featureDisabledError).eraseToAnyPublisher()
        }
        return httpClient.post("/networkgroups/organisations/\(organizationId)/networkgroups/\(networkGroupId)/members", body: member, apiVersion: .v4)
    }
    
    /// Remove a member from a network group
    /// - Parameters:
    ///   - organizationId: Organization ID
    ///   - networkGroupId: Network group ID
    ///   - memberId: Member ID to remove
    /// - Returns: Publisher emitting void response or error
    public func removeNetworkGroupMember(organizationId: String, networkGroupId: String, memberId: String) -> AnyPublisher<Void, CCError> {
        guard isNetworkGroupsEnabled else {
            return Fail(error: featureDisabledError).eraseToAnyPublisher()
        }
        return httpClient.deleteRaw("/networkgroups/organisations/\(organizationId)/networkgroups/\(networkGroupId)/members/\(memberId)", apiVersion: .v4)
    }
    
    // MARK: - Network Group Peers Management
    
    /// List all peers of a network group
    /// - Parameters:
    ///   - organizationId: Organization ID
    ///   - networkGroupId: Network group ID
    /// - Returns: Publisher emitting array of peers or error
    public func getNetworkGroupPeers(organizationId: String, networkGroupId: String) -> AnyPublisher<[CCNetworkGroupPeer], CCError> {
        guard isNetworkGroupsEnabled else {
            return Fail(error: featureDisabledError).eraseToAnyPublisher()
        }
        return httpClient.get("/networkgroups/organisations/\(organizationId)/networkgroups/\(networkGroupId)/peers", apiVersion: .v4)
    }
    
    /// Get a specific peer of a network group
    /// - Parameters:
    ///   - organizationId: Organization ID
    ///   - networkGroupId: Network group ID
    ///   - peerId: Peer ID
    /// - Returns: Publisher emitting peer or error
    public func getNetworkGroupPeer(organizationId: String, networkGroupId: String, peerId: String) -> AnyPublisher<CCNetworkGroupPeer, CCError> {
        return httpClient.get("/networkgroups/organisations/\(organizationId)/networkgroups/\(networkGroupId)/peers/\(peerId)", apiVersion: .v4)
    }
    
    /// Remove a peer from a network group
    /// - Parameters:
    ///   - organizationId: Organization ID
    ///   - networkGroupId: Network group ID
    ///   - peerId: Peer ID to remove
    /// - Returns: Publisher emitting void response or error
    public func removeNetworkGroupPeer(organizationId: String, networkGroupId: String, peerId: String) -> AnyPublisher<Void, CCError> {
        return httpClient.deleteRaw("/networkgroups/organisations/\(organizationId)/networkgroups/\(networkGroupId)/peers/\(peerId)", apiVersion: .v4)
    }
    
    // MARK: - External Peers Management
    
    /// Add an external peer to a network group
    /// - Parameters:
    ///   - organizationId: Organization ID
    ///   - networkGroupId: Network group ID
    ///   - externalPeer: External peer creation data
    /// - Returns: Publisher emitting added external peer or error
    public func addNetworkGroupExternalPeer(organizationId: String, networkGroupId: String, externalPeer: CCNetworkGroupExternalPeerCreate) -> AnyPublisher<CCNetworkGroupPeer, CCError> {
        return httpClient.post("/networkgroups/organisations/\(organizationId)/networkgroups/\(networkGroupId)/external-peers", body: externalPeer, apiVersion: .v4)
    }
    
    /// Remove an external peer from a network group
    /// - Parameters:
    ///   - organizationId: Organization ID
    ///   - networkGroupId: Network group ID
    ///   - peerId: External peer ID to remove
    /// - Returns: Publisher emitting void response or error
    public func removeNetworkGroupExternalPeer(organizationId: String, networkGroupId: String, peerId: String) -> AnyPublisher<Void, CCError> {
        return httpClient.deleteRaw("/networkgroups/organisations/\(organizationId)/networkgroups/\(networkGroupId)/external-peers/\(peerId)", apiVersion: .v4)
    }
    
    // MARK: - WireGuard Configuration Management
    
    /// Get WireGuard configuration for a peer
    /// - Parameters:
    ///   - organizationId: Organization ID
    ///   - networkGroupId: Network group ID
    ///   - peerId: Peer ID
    /// - Returns: Publisher emitting WireGuard configuration or error
    public func getWireGuardConfiguration(organizationId: String, networkGroupId: String, peerId: String) -> AnyPublisher<CCWireGuardConfiguration, CCError> {
        guard isNetworkGroupsEnabled else {
            return Fail(error: featureDisabledError).eraseToAnyPublisher()
        }
        return httpClient.get("/networkgroups/organisations/\(organizationId)/networkgroups/\(networkGroupId)/peers/\(peerId)/wireguard/configuration", apiVersion: .v4)
    }
    
    /// Get WireGuard configuration as a downloadable stream
    /// - Parameters:
    ///   - organizationId: Organization ID
    ///   - networkGroupId: Network group ID
    ///   - peerId: Peer ID
    /// - Returns: Publisher emitting configuration file content or error
    public func getWireGuardConfigurationStream(organizationId: String, networkGroupId: String, peerId: String) -> AnyPublisher<String, CCError> {
        guard isNetworkGroupsEnabled else {
            return Fail(error: featureDisabledError).eraseToAnyPublisher()
        }
        return httpClient.get("/networkgroups/organisations/\(organizationId)/networkgroups/\(networkGroupId)/peers/\(peerId)/wireguard/configuration/stream", apiVersion: .v4)
    }
    
    // MARK: - Real-time Network Group Monitoring
    
    /// Get real-time updates for a network group (SSE stream)
    /// - Parameters:
    ///   - organizationId: Organization ID
    ///   - networkGroupId: Network group ID
    /// - Returns: Publisher emitting real-time events or error
    public func getNetworkGroupStream(organizationId: String, networkGroupId: String) -> AnyPublisher<String, CCError> {
        return httpClient.get("/networkgroups/organisations/\(organizationId)/networkgroups/\(networkGroupId)/stream", apiVersion: .v4)
    }
    
    // MARK: - Convenience Methods
    
    /// Add an application to a network group
    /// - Parameters:
    ///   - organizationId: Organization ID
    ///   - networkGroupId: Network group ID
    ///   - applicationId: Application ID to add
    /// - Returns: Publisher emitting added member or error
    public func addApplicationToNetworkGroup(organizationId: String, networkGroupId: String, applicationId: String) -> AnyPublisher<CCNetworkGroupMember, CCError> {
        guard isNetworkGroupsEnabled else {
            return Fail(error: featureDisabledError).eraseToAnyPublisher()
        }
        let member = CCNetworkGroupMemberCreate(type: .application, resourceId: applicationId)
        return addNetworkGroupMember(organizationId: organizationId, networkGroupId: networkGroupId, member: member)
    }
    
    /// Add an add-on to a network group
    /// - Parameters:
    ///   - organizationId: Organization ID
    ///   - networkGroupId: Network group ID
    ///   - addonId: Add-on ID to add
    /// - Returns: Publisher emitting added member or error
    public func addAddonToNetworkGroup(organizationId: String, networkGroupId: String, addonId: String) -> AnyPublisher<CCNetworkGroupMember, CCError> {
        let member = CCNetworkGroupMemberCreate(type: .addon, resourceId: addonId)
        return addNetworkGroupMember(organizationId: organizationId, networkGroupId: networkGroupId, member: member)
    }
    
    /// Get comprehensive network group data (group + members + peers)
    /// - Parameters:
    ///   - organizationId: Organization ID
    ///   - networkGroupId: Network group ID
    /// - Returns: Publisher emitting tuple with all network group data or error
    public func getCompleteNetworkGroupData(organizationId: String, networkGroupId: String) -> AnyPublisher<(CCNetworkGroup, [CCNetworkGroupMember], [CCNetworkGroupPeer]), CCError> {
        guard isNetworkGroupsEnabled else {
            return Fail(error: featureDisabledError).eraseToAnyPublisher()
        }
        let networkGroupPublisher = getNetworkGroup(organizationId: organizationId, networkGroupId: networkGroupId)
        let membersPublisher = getNetworkGroupMembers(organizationId: organizationId, networkGroupId: networkGroupId)
        let peersPublisher = getNetworkGroupPeers(organizationId: organizationId, networkGroupId: networkGroupId)
        
        return Publishers.CombineLatest3(networkGroupPublisher, membersPublisher, peersPublisher)
            .eraseToAnyPublisher()
    }
    
    /// Search network groups by name
    /// - Parameters:
    ///   - organizationId: Organization ID
    ///   - searchTerm: Search term for network group names
    /// - Returns: Publisher emitting filtered array of network groups or error
    public func searchNetworkGroups(organizationId: String, searchTerm: String) -> AnyPublisher<[CCNetworkGroup], CCError> {
        return getNetworkGroups(organizationId: organizationId)
            .map { networkGroups in
                networkGroups.filter { networkGroup in
                    networkGroup.name.localizedCaseInsensitiveContains(searchTerm) ||
                    networkGroup.description?.localizedCaseInsensitiveContains(searchTerm) == true
                }
            }
            .eraseToAnyPublisher()
    }
    
    /// Generate network group statistics
    /// - Parameters:
    ///   - organizationId: Organization ID
    ///   - networkGroupId: Network group ID
    /// - Returns: Publisher emitting network group statistics or error
    public func getNetworkGroupStatistics(organizationId: String, networkGroupId: String) -> AnyPublisher<CCNetworkGroupStats, CCError> {
        return getCompleteNetworkGroupData(organizationId: organizationId, networkGroupId: networkGroupId)
            .map { (networkGroup, members, peers) in
                let connectedMembers = members.filter { $0.status?.lowercased() == "connected" }.count
                let activePeers = peers.filter { $0.status?.lowercased() == "connected" }.count
                
                return CCNetworkGroupStats(
                    connectedMembers: connectedMembers,
                    totalMembers: members.count,
                    activePeers: activePeers,
                    dataTransferred: nil, // Would need additional API data
                    lastActivity: Date() // Would need additional API data
                )
            }
            .eraseToAnyPublisher()
    }
} 