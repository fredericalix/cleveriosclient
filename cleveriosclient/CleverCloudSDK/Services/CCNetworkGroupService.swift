import Foundation
import Combine

/// Response body of `POST .../external-peers`: `{"peerId":"…"}`.
fileprivate struct CCCreatedExternalPeer: Codable {
    let peerId: String
}

/// Wire body of `POST .../networkgroups`, mirroring clever-tools: the client generates the
/// `ng_<uuid>` id and sends it (with `ownerId`) so the creation is idempotent — replaying the
/// same id is safe, which makes the POST retryable on the intermittent v4 5xx — and the created
/// group can be resolved by id instead of a fragile list-diff/name match.
fileprivate struct CCNetworkGroupCreateBody: Codable {
    let ownerId: String
    let id: String
    let label: String
    let description: String?
    let networkIp: String?
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
        // Client-generated lowercase id, like clever-tools' crypto.randomUUID(): the POST becomes
        // idempotent (retryable on 5xx) and the created group is resolved by its known id — the
        // creation POST answers 202 with an empty body, so a poll absorbs the async window.
        let ngId = "ng_\(UUID().uuidString.lowercased())"
        let body = CCNetworkGroupCreateBody(
            ownerId: organizationId,
            id: ngId,
            label: networkGroup.name,
            description: networkGroup.description,
            networkIp: networkGroup.cidr
        )
        let client = httpClient

        return Self.retryingOnServerError { client.postRaw("/networkgroups/organisations/\(organizationId)/networkgroups", body: body, apiVersion: .v4) }
            .flatMap { [weak self] _ -> AnyPublisher<CCNetworkGroup, CCError> in
                guard let self else {
                    return Fail(error: CCError.invalidParameters("Service deallocated")).eraseToAnyPublisher()
                }
                return self.waitForNetworkGroup(organizationId: organizationId, networkGroupId: ngId)
            }
            .eraseToAnyPublisher()
    }

    /// Poll the network-groups list until `networkGroupId` is visible and return it — same
    /// pattern as `waitForNetworkGroupMember` (creation answers 202 Accepted, async).
    private func waitForNetworkGroup(organizationId: String, networkGroupId: String) -> AnyPublisher<CCNetworkGroup, CCError> {
        return Just(())
            .delay(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .setFailureType(to: CCError.self)
            .flatMap { [weak self] _ -> AnyPublisher<[CCNetworkGroup], CCError> in
                guard let self else {
                    return Fail(error: CCError.invalidParameters("Service deallocated")).eraseToAnyPublisher()
                }
                return self.getNetworkGroups(organizationId: organizationId)
            }
            .tryMap { networkGroups -> CCNetworkGroup in
                guard let created = networkGroups.first(where: { $0.id == networkGroupId }) else {
                    debugLog("🔍 [CCNetworkGroupService] Network group \(networkGroupId) not listable yet, retrying…")
                    throw CCError.resourceNotFound
                }
                return created
            }
            .mapError { ($0 as? CCError) ?? CCError.unknown($0) }
            .retry(29)
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
        //
        // Retried on 5xx: the v4 backend intermittently answers 500 to this POST while accepting
        // the byte-identical body seconds later (observed 2026-07-13, looks like one bad replica
        // behind Sozu). Replaying the same member id is safe — the server upserts duplicates.
        let client = httpClient
        let endpoint = "/networkgroups/organisations/\(organizationId)/networkgroups/\(networkGroupId)/members"
        return Self.retryingOnServerError { client.postRaw(endpoint, body: member, apiVersion: .v4) }
    }

    /// Pauses between successive 5xx retries: two quick 2s retries, a 5s breather (field logs
    /// showed up to 3 consecutive 500s — the bad-replica ratio behind the v4 LB fluctuates, so
    /// give it a moment), then a second burst of two. 6 attempts total, ~13s worst case.
    static let serverErrorRetryDelays: [TimeInterval] = [2, 2, 5, 2, 2]

    /// Re-subscribes `makePublisher` when it fails with an HTTP 5xx, pausing per the `delays`
    /// schedule (one entry consumed per retry). Only use for calls that are safe to replay
    /// (idempotent/upsert).
    private static func retryingOnServerError<T>(
        delays: [TimeInterval] = serverErrorRetryDelays,
        _ makePublisher: @escaping () -> AnyPublisher<T, CCError>
    ) -> AnyPublisher<T, CCError> {
        makePublisher()
            .catch { error -> AnyPublisher<T, CCError> in
                guard let delay = delays.first,
                      case .httpError(let statusCode, _) = error,
                      (500...599).contains(statusCode) else {
                    return Fail(error: error).eraseToAnyPublisher()
                }
                debugLog("⚠️ [CCNetworkGroupService] Server error \(statusCode), retrying in \(Int(delay))s (\(delays.count) attempts left)…")
                return Just(())
                    .delay(for: .seconds(delay), scheduler: DispatchQueue.main)
                    .setFailureType(to: CCError.self)
                    .flatMap { _ in retryingOnServerError(delays: Array(delays.dropFirst()), makePublisher) }
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
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
    /// The members POST returns 202 Accepted — creation is asynchronous — so before referencing the
    /// parent from the peer POST we poll the members list until it appears (clever-tools does the
    /// same in `checkResource`, 1s interval / 30s timeout). POSTing the peer earlier makes the API
    /// answer 500 because the parent member doesn't exist yet.
    ///
    /// The external-peers POST returns `{"peerId":"…"}` — the authoritative id of the new peer — so we
    /// resolve the peer by that id (not by matching on publicKey, which could collide). A short retry
    /// absorbs the v4 eventual-consistency window before the peer is listable. If the wait or the peer
    /// POST fails, the already-created EXTERNAL parent member is rolled back (best-effort) so no
    /// orphan is left.
    public func createExternalPeer(organizationId: String, networkGroupId: String, publicKey: String, label: String) -> AnyPublisher<CCNetworkGroupPeer, CCError> {
        // Lowercased to match clever-tools' crypto.randomUUID(): the id is embedded in a DNS
        // domainName, and the v4 API strictly validates the `external_<uuid>` format.
        let parentId = "external_\(UUID().uuidString.lowercased())"
        let parentMember = CCNetworkGroupMemberCreate(
            id: parentId,
            label: "Parent of \(label)",
            domainName: Self.memberDomainName(memberId: parentId, networkGroupId: networkGroupId),
            kind: "EXTERNAL"
        )
        let peerBody = CCNetworkGroupExternalPeerCreate(publicKey: publicKey, label: label, parentMember: parentId)
        let client = httpClient

        return addNetworkGroupMember(organizationId: organizationId, networkGroupId: networkGroupId, member: parentMember)
            .flatMap { [weak self] _ -> AnyPublisher<CCCreatedExternalPeer, CCError> in
                guard let self else {
                    return Fail(error: CCError.invalidParameters("Service deallocated")).eraseToAnyPublisher()
                }
                // Wait for the async member creation, then capture the authoritative peerId from
                // the POST body; roll back the parent member on failure.
                return self.waitForNetworkGroupMember(organizationId: organizationId, networkGroupId: networkGroupId, memberId: parentId)
                    .flatMap { _ -> AnyPublisher<CCCreatedExternalPeer, CCError> in
                        self.createExternalPeerRecovering(
                            organizationId: organizationId,
                            networkGroupId: networkGroupId,
                            body: peerBody,
                            publicKey: publicKey
                        )
                    }
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
    
    /// POST the external peer, absorbing the intermittent v4 5xx. Unlike members/groups the peer
    /// id is server-generated, so a blind replay could create a duplicate: after a 5xx we first
    /// look the peer up by its public key (unique — freshly generated per attach) and adopt it if
    /// the POST actually went through server-side; only when it truly didn't do we replay, up to
    /// `attempts` extra times.
    private func createExternalPeerRecovering(
        organizationId: String,
        networkGroupId: String,
        body: CCNetworkGroupExternalPeerCreate,
        publicKey: String,
        delays: [TimeInterval] = CCNetworkGroupService.serverErrorRetryDelays
    ) -> AnyPublisher<CCCreatedExternalPeer, CCError> {
        let client = httpClient
        return client.post("/networkgroups/organisations/\(organizationId)/networkgroups/\(networkGroupId)/external-peers", body: body, apiVersion: .v4)
            .catch { [weak self] error -> AnyPublisher<CCCreatedExternalPeer, CCError> in
                guard let self,
                      case .httpError(let statusCode, _) = error,
                      (500...599).contains(statusCode) else {
                    return Fail(error: error).eraseToAnyPublisher()
                }
                let delay = delays.first ?? 2
                return Just(())
                    .delay(for: .seconds(delay), scheduler: DispatchQueue.main)
                    .setFailureType(to: CCError.self)
                    .flatMap { _ in
                        self.getNetworkGroupPeers(organizationId: organizationId, networkGroupId: networkGroupId)
                            .catch { _ in Just([]).setFailureType(to: CCError.self) }
                    }
                    .flatMap { peers -> AnyPublisher<CCCreatedExternalPeer, CCError> in
                        if let existing = peers.first(where: { $0.publicKey == publicKey }) {
                            debugLog("⚠️ [CCNetworkGroupService] external-peers POST answered \(statusCode) but the peer exists — adopting \(existing.id)")
                            return Just(CCCreatedExternalPeer(peerId: existing.id))
                                .setFailureType(to: CCError.self)
                                .eraseToAnyPublisher()
                        }
                        guard !delays.isEmpty else {
                            return Fail(error: error).eraseToAnyPublisher()
                        }
                        debugLog("⚠️ [CCNetworkGroupService] Server error \(statusCode) on external-peers POST, retrying (\(delays.count) attempts left)…")
                        return self.createExternalPeerRecovering(
                            organizationId: organizationId,
                            networkGroupId: networkGroupId,
                            body: body,
                            publicKey: publicKey,
                            delays: Array(delays.dropFirst())
                        )
                    }
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }

    /// Delete an external peer and (best-effort) its `external_<uuid>` parent member.
    /// Used when re-attaching this device to a different network group: the previous peer's
    /// private key has been overwritten in the keychain (single slot, never leaves the device),
    /// so that peer can never work again — clean it up instead of leaving a zombie server-side.
    public func deleteExternalPeerCascading(organizationId: String, networkGroupId: String, peerId: String) -> AnyPublisher<Void, CCError> {
        return getNetworkGroupPeer(organizationId: organizationId, networkGroupId: networkGroupId, peerId: peerId)
            .map { $0.parentMember }
            .catch { _ in Just(String?.none).setFailureType(to: CCError.self) } // peer lookup is best-effort
            .flatMap { [weak self] parentMember -> AnyPublisher<Void, CCError> in
                guard let self else {
                    return Fail(error: CCError.invalidParameters("Service deallocated")).eraseToAnyPublisher()
                }
                return self.removeNetworkGroupExternalPeer(organizationId: organizationId, networkGroupId: networkGroupId, peerId: peerId)
                    .flatMap { _ -> AnyPublisher<Void, CCError> in
                        guard let parentMember, parentMember.hasPrefix("external_") else {
                            return Just(()).setFailureType(to: CCError.self).eraseToAnyPublisher()
                        }
                        return self.removeNetworkGroupMember(organizationId: organizationId, networkGroupId: networkGroupId, memberId: parentMember)
                            .catch { _ in Just(()).setFailureType(to: CCError.self) } // parent may be gone / cascaded
                            .eraseToAnyPublisher()
                    }
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }

    /// Poll the members list until `memberId` is visible, 1s between attempts, ~30 attempts
    /// (mirrors clever-tools' `checkResource` polling: 1s interval, 30s timeout). The members
    /// POST returns 202 Accepted, so the member only becomes referenceable after an
    /// eventual-consistency window.
    private func waitForNetworkGroupMember(organizationId: String, networkGroupId: String, memberId: String) -> AnyPublisher<Void, CCError> {
        return Just(())
            .delay(for: .seconds(1), scheduler: DispatchQueue.main)
            .setFailureType(to: CCError.self)
            .flatMap { [weak self] _ -> AnyPublisher<[CCNetworkGroupMember], CCError> in
                guard let self else {
                    return Fail(error: CCError.invalidParameters("Service deallocated")).eraseToAnyPublisher()
                }
                return self.getNetworkGroupMembers(organizationId: organizationId, networkGroupId: networkGroupId)
            }
            .tryMap { members -> Void in
                // CCNetworkGroupMember's decoder remaps the API id: `resourceId` holds the raw
                // API id, `id` is prefixed with "member_" — so match on resourceId.
                guard members.contains(where: { $0.resourceId == memberId }) else {
                    debugLog("🔍 [CCNetworkGroupService] Member \(memberId) not listable yet, retrying…")
                    throw CCError.resourceNotFound
                }
            }
            .mapError { ($0 as? CCError) ?? CCError.unknown($0) }
            .retry(29)
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