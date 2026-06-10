import Foundation
import Combine

/// Response body of `POST .../external-peers`: `{"peerId":"…"}`.
fileprivate struct CCCreatedExternalPeer: Codable {
    let peerId: String
}

// MARK: - CCNetworkGroupService
/// Service for managing Clever Cloud Network Groups (v4 API).
/// Driven live from the app UI since 2026-06; endpoints/models are validated against the real API
/// and decoding is kept tolerant (optionals + `.unknown` fallbacks) to survive shape drift.
public class CCNetworkGroupService {

    // MARK: - Properties
    private let httpClient: CCHTTPClient

    // MARK: - Initialization
    public init(httpClient: CCHTTPClient) {
        self.httpClient = httpClient
    }
    
    // MARK: - Network Groups Management
    
    /// List all network groups for an organization
    /// - Parameter organizationId: Organization ID
    /// - Returns: Publisher emitting array of network groups or error
    public func getNetworkGroups(organizationId: String) -> AnyPublisher<[CCNetworkGroup], CCError> {
        return httpClient.get("/networkgroups/organisations/\(organizationId)/networkgroups", apiVersion: .v4)
    }
    
    /// Get a specific network group by ID
    /// - Parameters:
    ///   - organizationId: Organization ID
    ///   - networkGroupId: Network group ID
    /// - Returns: Publisher emitting network group or error
    public func getNetworkGroup(organizationId: String, networkGroupId: String) -> AnyPublisher<CCNetworkGroup, CCError> {
        return httpClient.get("/networkgroups/organisations/\(organizationId)/networkgroups/\(networkGroupId)", apiVersion: .v4)
    }
    
    /// Create a new network group
    /// - Parameters:
    ///   - organizationId: Organization ID
    ///   - networkGroup: Network group creation data
    /// - Returns: Publisher emitting created network group or error
    public func createNetworkGroup(organizationId: String, networkGroup: CCNetworkGroupCreate) -> AnyPublisher<CCNetworkGroup, CCError> {
        // The v4 NG payload has no createdAt/timestamp, so we can't pick "the newest" by date.
        // Snapshot the existing ids first, then after creating, return the id that wasn't there before.
        let priorIds = getNetworkGroups(organizationId: organizationId)
            .map { Set($0.map { $0.id }) }
            .catch { _ in Just(Set<String>()).setFailureType(to: CCError.self) }
            .eraseToAnyPublisher()

        return priorIds
            .flatMap { existingIds -> AnyPublisher<CCNetworkGroup, CCError> in
                self.httpClient.postRaw("/networkgroups/organisations/\(organizationId)/networkgroups", body: networkGroup, apiVersion: .v4)
                    .flatMap { _ -> AnyPublisher<[CCNetworkGroup], CCError> in
                        // Small delay to allow the API to process the creation.
                        Just(())
                            .delay(for: .milliseconds(500), scheduler: DispatchQueue.main)
                            .setFailureType(to: CCError.self)
                            .flatMap { _ in self.getNetworkGroups(organizationId: organizationId) }
                            .eraseToAnyPublisher()
                    }
                    .tryMap { networkGroups -> CCNetworkGroup in
                        // Prefer the id that did not exist before the create; fall back to a name match.
                        if let created = networkGroups.first(where: { !existingIds.contains($0.id) && $0.name == networkGroup.name }) {
                            return created
                        }
                        if let byName = networkGroups.first(where: { $0.name == networkGroup.name }) {
                            return byName
                        }
                        throw CCError.invalidParameters("Failed to retrieve created network group")
                    }
                    .mapError { ($0 as? CCError) ?? CCError.unknown($0) }
                    .eraseToAnyPublisher()
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
        return httpClient.put("/networkgroups/organisations/\(organizationId)/networkgroups/\(networkGroupId)", body: networkGroupUpdate, apiVersion: .v4)
    }
    
    /// Delete a network group
    /// - Parameters:
    ///   - organizationId: Organization ID
    ///   - networkGroupId: Network group ID to delete
    /// - Returns: Publisher emitting void response or error
    public func deleteNetworkGroup(organizationId: String, networkGroupId: String) -> AnyPublisher<Void, CCError> {
        return httpClient.deleteRaw("/networkgroups/organisations/\(organizationId)/networkgroups/\(networkGroupId)", apiVersion: .v4)
    }
    
    // MARK: - Network Group Members Management
    
    /// List all members of a network group
    /// - Parameters:
    ///   - organizationId: Organization ID
    ///   - networkGroupId: Network group ID
    /// - Returns: Publisher emitting array of members or error
    public func getNetworkGroupMembers(organizationId: String, networkGroupId: String) -> AnyPublisher<[CCNetworkGroupMember], CCError> {
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
    public func addNetworkGroupMember(organizationId: String, networkGroupId: String, member: CCNetworkGroupMemberCreate) -> AnyPublisher<Void, CCError> {
        // The members endpoint returns an empty/202 body, so use the raw path (any 2xx = success)
        // rather than trying to decode a member object.
        return httpClient.postRaw("/networkgroups/organisations/\(organizationId)/networkgroups/\(networkGroupId)/members", body: member, apiVersion: .v4)
    }

    /// `<memberId>.m.<networkGroupId>.cc-ng.cloud` — the member domain name the API expects.
    static func memberDomainName(memberId: String, networkGroupId: String) -> String {
        "\(memberId).m.\(networkGroupId).cc-ng.cloud"
    }
    
    /// Remove a member from a network group
    /// - Parameters:
    ///   - organizationId: Organization ID
    ///   - networkGroupId: Network group ID
    ///   - memberId: Member ID to remove
    /// - Returns: Publisher emitting void response or error
    public func removeNetworkGroupMember(organizationId: String, networkGroupId: String, memberId: String) -> AnyPublisher<Void, CCError> {
        return httpClient.deleteRaw("/networkgroups/organisations/\(organizationId)/networkgroups/\(networkGroupId)/members/\(memberId)", apiVersion: .v4)
    }
    
    // MARK: - Network Group Peers Management
    
    /// List all peers of a network group
    /// - Parameters:
    ///   - organizationId: Organization ID
    ///   - networkGroupId: Network group ID
    /// - Returns: Publisher emitting array of peers or error
    public func getNetworkGroupPeers(organizationId: String, networkGroupId: String) -> AnyPublisher<[CCNetworkGroupPeer], CCError> {
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
        return httpClient.get("/networkgroups/organisations/\(organizationId)/networkgroups/\(networkGroupId)/peers/\(peerId)/wireguard/configuration", apiVersion: .v4)
    }
    
    /// Get WireGuard configuration as a downloadable stream
    /// - Parameters:
    ///   - organizationId: Organization ID
    ///   - networkGroupId: Network group ID
    ///   - peerId: Peer ID
    /// - Returns: Publisher emitting configuration file content or error
    public func getWireGuardConfigurationStream(organizationId: String, networkGroupId: String, peerId: String) -> AnyPublisher<String, CCError> {
        return httpClient.get("/networkgroups/organisations/\(organizationId)/networkgroups/\(networkGroupId)/peers/\(peerId)/wireguard/configuration/stream", apiVersion: .v4)
    }

    /// Get the WireGuard configuration for a peer as raw text (the API returns a `.conf` as
    /// text/plain, per clever-client.js — not JSON, so this avoids the JSON-decoding path).
    /// The returned `[Interface] PrivateKey` is typically empty/placeholder for an externally-keyed
    /// peer; the caller injects the locally-generated private key before presenting/importing.
    public func getWireGuardConfigurationText(organizationId: String, networkGroupId: String, peerId: String) -> AnyPublisher<String, CCError> {
        // The endpoint serves text/plain — a JSON `Accept` header makes it 406. Ask for text/plain.
        return httpClient.getRawString("/networkgroups/organisations/\(organizationId)/networkgroups/\(networkGroupId)/peers/\(peerId)/wireguard/configuration", apiVersion: .v4, accept: "text/plain")
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
    public func addApplicationToNetworkGroup(organizationId: String, networkGroupId: String, applicationId: String) -> AnyPublisher<Void, CCError> {
        let member = CCNetworkGroupMemberCreate(
            id: applicationId,
            label: applicationId,
            domainName: Self.memberDomainName(memberId: applicationId, networkGroupId: networkGroupId),
            kind: "APPLICATION"
        )
        return addNetworkGroupMember(organizationId: organizationId, networkGroupId: networkGroupId, member: member)
    }

    /// Create an external WireGuard peer (e.g. a laptop/phone). Two-step, mirroring clever-tools:
    /// (1) create an EXTERNAL parent member, (2) create the peer with `peerRole=CLIENT` + that parent.
    ///
    /// The external-peers POST returns `{"peerId":"…"}` — the authoritative id of the new peer — so we
    /// resolve the peer by that id (not by matching on publicKey, which could collide). A short retry
    /// absorbs the v4 eventual-consistency window before the peer is listable. If the peer POST fails,
    /// the already-created EXTERNAL parent member is rolled back (best-effort) so no orphan is left.
    public func createExternalPeer(organizationId: String, networkGroupId: String, publicKey: String, label: String) -> AnyPublisher<CCNetworkGroupPeer, CCError> {
        let parentId = "external_\(UUID().uuidString)"
        let parentMember = CCNetworkGroupMemberCreate(
            id: parentId,
            label: "Parent of \(label)",
            domainName: Self.memberDomainName(memberId: parentId, networkGroupId: networkGroupId),
            kind: "EXTERNAL"
        )
        let peerBody = CCNetworkGroupExternalPeerCreate(publicKey: publicKey, label: label, parentMember: parentId)
        let client = httpClient

        return addNetworkGroupMember(organizationId: organizationId, networkGroupId: networkGroupId, member: parentMember)
            .flatMap { _ -> AnyPublisher<CCCreatedExternalPeer, CCError> in
                // Capture the authoritative peerId from the POST body; roll back the parent member on failure.
                client.post("/networkgroups/organisations/\(organizationId)/networkgroups/\(networkGroupId)/external-peers", body: peerBody, apiVersion: .v4)
                    .catch { error -> AnyPublisher<CCCreatedExternalPeer, CCError> in
                        client.deleteRaw("/networkgroups/organisations/\(organizationId)/networkgroups/\(networkGroupId)/members/\(parentId)", apiVersion: .v4)
                            .catch { _ in Just(()).setFailureType(to: CCError.self) } // ignore cleanup failure
                            .flatMap { _ in Fail<CCCreatedExternalPeer, CCError>(error: error) }
                            .eraseToAnyPublisher()
                    }
                    .eraseToAnyPublisher()
            }
            .flatMap { [weak self] created -> AnyPublisher<CCNetworkGroupPeer, CCError> in
                guard let self else {
                    return Fail(error: CCError.invalidParameters("Service deallocated")).eraseToAnyPublisher()
                }
                // Resolve by the authoritative id; retry to absorb the eventual-consistency window.
                return Just(())
                    .delay(for: .milliseconds(500), scheduler: DispatchQueue.main)
                    .setFailureType(to: CCError.self)
                    .flatMap { _ in self.getNetworkGroupPeers(organizationId: organizationId, networkGroupId: networkGroupId) }
                    .tryMap { peers -> CCNetworkGroupPeer in
                        guard let peer = peers.first(where: { $0.id == created.peerId }) else {
                            throw CCError.resourceNotFound
                        }
                        return peer
                    }
                    .mapError { ($0 as? CCError) ?? CCError.unknown($0) }
                    .retry(2)
                    .eraseToAnyPublisher()
            }
            .mapError { ($0 as? CCError) ?? CCError.unknown($0) }
            .eraseToAnyPublisher()
    }
    
    /// Add an add-on to a network group
    /// - Parameters:
    ///   - organizationId: Organization ID
    ///   - networkGroupId: Network group ID
    ///   - addonId: Add-on ID to add
    /// - Returns: Publisher emitting added member or error
    public func addAddonToNetworkGroup(organizationId: String, networkGroupId: String, addonId: String) -> AnyPublisher<Void, CCError> {
        let member = CCNetworkGroupMemberCreate(
            id: addonId,
            label: addonId,
            domainName: Self.memberDomainName(memberId: addonId, networkGroupId: networkGroupId),
            kind: "ADDON"
        )
        return addNetworkGroupMember(organizationId: organizationId, networkGroupId: networkGroupId, member: member)
    }
    
    /// Get comprehensive network group data (group + members + peers)
    /// - Parameters:
    ///   - organizationId: Organization ID
    ///   - networkGroupId: Network group ID
    /// - Returns: Publisher emitting tuple with all network group data or error
    public func getCompleteNetworkGroupData(organizationId: String, networkGroupId: String) -> AnyPublisher<(CCNetworkGroup, [CCNetworkGroupMember], [CCNetworkGroupPeer]), CCError> {
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
                // Peers returned by the API are active; there is no per-peer status field.
                let activePeers = peers.count
                
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