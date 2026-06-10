import Foundation
import Combine

// MARK: - CCNetworkGroup Models

/// Represents a Clever Cloud Network Group for secure networking between applications
public struct CCNetworkGroup: Codable, Identifiable, Equatable, Hashable {
    
    // MARK: - Core Properties
    
    /// Unique network group identifier
    public let id: String
    
    /// Network group display name
    public let name: String
    
    /// Network group description
    public let description: String?
    
    /// Organization ID that owns this network group
    public let organizationId: String
    
    /// Network CIDR block (e.g., "10.0.0.0/16")
    public let cidr: String?
    
    /// Creation timestamp
    public let createdAt: Date?
    
    /// Last modification timestamp
    public let updatedAt: Date?
    
    /// Network group status (e.g., "active", "creating", "error")
    public let status: String?
    
    /// WireGuard configuration endpoint
    public let wireGuardEndpoint: String?
    
    /// Network group region
    public let region: String?
    
    // MARK: - Computed Properties
    
    /// Display name for the network group
    public var displayName: String {
        return name.isEmpty ? "Unnamed Network Group" : name
    }
    
    /// Status color for UI
    public var statusColor: String {
        switch status?.lowercased() {
        case "active":
            return "systemGreen"
        case "creating", "updating":
            return "systemOrange"
        case "error", "failed":
            return "systemRed"
        default:
            return "systemGray"
        }
    }
    
    /// Is network group operational. The v4 API does not return a `status` field for network groups
    /// (unlike applications), so a group that exists is considered active; only an explicit
    /// non-"active" status marks it otherwise.
    public var isActive: Bool {
        guard let status = status else { return true }
        return status.lowercased() == "active"
    }
    
    // MARK: - CodingKeys
    enum CodingKeys: String, CodingKey {
        case id
        case name = "label"
        case description
        case organizationId = "ownerId"
        case cidr = "networkIp"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case status
        case wireGuardEndpoint = "wireguard_endpoint"
        case region
    }
}

// MARK: - CCNetworkGroupMember

/// Represents a member of a network group (application or add-on)
public struct CCNetworkGroupMember: Codable, Identifiable, Equatable {
    
    /// Unique member identifier
    public let id: String
    
    /// Member type ("application" or "addon")
    public let type: CCNetworkGroupMemberType
    
    /// Member name (application or add-on name)
    public let name: String
    
    /// Member description
    public let description: String?
    
    /// Application or add-on ID
    public let resourceId: String
    
    /// IP address assigned in the network group
    public let ipAddress: String?
    
    /// Join timestamp
    public let joinedAt: Date?
    
    /// Member status in the network group
    public let status: String?
    
    // MARK: - Computed Properties
    
    /// Display name with type icon
    public var displayNameWithIcon: String {
        let icon: String
        switch type {
        case .application: icon = "📱"
        case .addon: icon = "🔧"
        case .external: icon = "💻"
        case .unknown: icon = "❔"
        }
        return "\(icon) \(name)"
    }
    
    /// Status color for UI
    public var statusColor: String {
        switch status?.lowercased() {
        case "connected":
            return "systemGreen"
        case "connecting":
            return "systemOrange"
        case "disconnected", "error":
            return "systemRed"
        default:
            return "systemGray"
        }
    }
    
    // MARK: - CodingKeys
    enum CodingKeys: String, CodingKey {
        case type = "kind"
        case name = "label"
        case description
        case resourceId = "id"
        case ipAddress = "ip_address"
        case joinedAt = "joined_at"
        case status
    }
    
    // Custom init pour gérer le fait que l'API retourne resourceId comme id
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        let apiId = try container.decode(String.self, forKey: .resourceId)
        self.id = "member_\(apiId)" // Créer un ID unique pour le member
        self.resourceId = apiId // L'ID de l'API devient resourceId
        self.type = try container.decode(CCNetworkGroupMemberType.self, forKey: .type)
        self.name = try container.decode(String.self, forKey: .name)
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
        self.ipAddress = try container.decodeIfPresent(String.self, forKey: .ipAddress)
        self.joinedAt = try container.decodeIfPresent(Date.self, forKey: .joinedAt)
        self.status = try container.decodeIfPresent(String.self, forKey: .status) ?? "connected"
    }
    
    // Custom encoder pour symétrie
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(resourceId, forKey: .resourceId)
        try container.encode(type, forKey: .type)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(ipAddress, forKey: .ipAddress)
        try container.encodeIfPresent(joinedAt, forKey: .joinedAt)
        try container.encodeIfPresent(status, forKey: .status)
    }
}

// MARK: - CCNetworkGroupMemberType

/// Type of network group member.
///
/// The API uses `kind`, which can be `APPLICATION`, `ADDON`, or `EXTERNAL` (the parent member
/// auto-created for an external WireGuard peer / "device"). Decoding is tolerant: any unrecognised
/// value maps to `.unknown` instead of throwing, so a single unexpected `kind` can never break the
/// whole members list.
public enum CCNetworkGroupMemberType: String, Codable, CaseIterable {
    case application = "APPLICATION"
    case addon = "ADDON"
    case external = "EXTERNAL"
    case unknown = "UNKNOWN"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CCNetworkGroupMemberType(rawValue: raw.uppercased()) ?? .unknown
    }

    public var displayName: String {
        switch self {
        case .application:
            return "Application"
        case .addon:
            return "Add-on"
        case .external:
            return "External device"
        case .unknown:
            return "Member"
        }
    }

    public var icon: String {
        switch self {
        case .application:
            return "app.badge"
        case .addon:
            return "gear.badge"
        case .external:
            return "laptopcomputer"
        case .unknown:
            return "questionmark.circle"
        }
    }
}

// MARK: - CCNetworkGroupPeer

/// Represents a peer in a network group. Shape validated against the live v4 API, e.g.:
/// `{"id":"…","label":"Spoiled camerupt","publicKey":"…","endpoint":{…},"hostname":"…",
///   "parentMember":"postgresql_…","type":"CleverPeer"}`
/// `CleverPeer` peers are created automatically for members (apps/add-ons); external peers carry an
/// "external"-flavored type. Decoding is tolerant so unexpected/missing fields never crash the list.
public struct CCNetworkGroupPeer: Codable, Identifiable, Equatable {

    /// Unique peer identifier
    public let id: String

    /// Peer name (API field `label`)
    public let name: String

    /// Peer type, e.g. "CleverPeer" / "ExternalPeer"
    public let type: String

    /// WireGuard public key (API field `publicKey`)
    public let publicKey: String?

    /// For CleverPeers, the member (app/add-on id) this peer was created for
    public let parentMember: String?

    /// Internal hostname
    public let hostname: String?

    // MARK: - Computed Properties

    /// Is this an external (user-added) peer rather than an auto-created member peer
    public var isExternal: Bool {
        return type.lowercased().contains("external")
    }

    /// Display name with type indicator
    public var displayNameWithType: String {
        return "\(isExternal ? "🌐" : "🏠") \(name)"
    }

    // MARK: - CodingKeys
    enum CodingKeys: String, CodingKey {
        case id
        case name = "label"
        case type
        case publicKey
        case parentMember
        case hostname
    }

    /// Tolerant decoding: only `id` is required; everything else falls back so a payload-shape change
    /// (or the nested `endpoint` object, which is intentionally not decoded) can't break the peers list.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        self.name = (try? c.decode(String.self, forKey: .name)) ?? "Peer"
        self.type = (try? c.decode(String.self, forKey: .type)) ?? "peer"
        self.publicKey = try? c.decode(String.self, forKey: .publicKey)
        self.parentMember = try? c.decode(String.self, forKey: .parentMember)
        self.hostname = try? c.decode(String.self, forKey: .hostname)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(type, forKey: .type)
        try c.encodeIfPresent(publicKey, forKey: .publicKey)
        try c.encodeIfPresent(parentMember, forKey: .parentMember)
        try c.encodeIfPresent(hostname, forKey: .hostname)
    }
}

// MARK: - CCNetworkGroupCreate

/// Model for creating a new network group. Network groups are NOT region-scoped (the web console
/// offers no geographic choice), so there is no `region` field — only `label`, optional description,
/// and an optional CIDR (`networkIp`, auto-assigned when omitted).
public struct CCNetworkGroupCreate: Codable {

    /// Network group name
    public let name: String

    /// Network group description
    public let description: String?

    /// Network CIDR block (optional, auto-assigned if not provided)
    public let cidr: String?

    public init(
        name: String,
        description: String? = nil,
        cidr: String? = nil
    ) {
        self.name = name
        self.description = description
        self.cidr = cidr
    }

    // MARK: - CodingKeys
    /// Map fields to match API expectations
    enum CodingKeys: String, CodingKey {
        case name = "label"
        case description
        case cidr = "networkIp"
    }
}

// MARK: - CCNetworkGroupUpdate

/// Model for updating an existing network group
public struct CCNetworkGroupUpdate: Codable {
    
    /// Network group name (optional - only sent if changed)
    public let name: String?
    
    /// Network group description (optional - only sent if changed)
    public let description: String?
    
    /// Network CIDR block (optional - only sent if changed, WARNING: may disrupt services)
    public let cidr: String?
    
    /// Region (optional - only sent if changed)
    public let region: String?
    
    public init(
        name: String? = nil,
        description: String? = nil,
        cidr: String? = nil,
        region: String? = nil
    ) {
        self.name = name
        self.description = description
        self.cidr = cidr
        self.region = region
    }
    
    // MARK: - CodingKeys
    /// Map fields to match API expectations
    enum CodingKeys: String, CodingKey {
        case name = "label"
        case description = "description"
        case cidr = "networkIp"
        case region = "region"
    }
}

// MARK: - CCNetworkGroupMemberCreate

/// Model for adding a member to a network group. Body shape matches the live API / clever-tools:
/// `{ id, label, domainName, kind }` where kind is "APPLICATION" | "ADDON" | "EXTERNAL" and
/// `domainName` is `<id>.m.<networkGroupId>.cc-ng.cloud`.
public struct CCNetworkGroupMemberCreate: Codable {

    /// Resource id (app/add-on id, or `external_<uuid>` for an external parent member)
    public let id: String

    /// Member label (for app/add-on members the API uses the id; for external, "Parent of …")
    public let label: String

    /// `<id>.m.<networkGroupId>.cc-ng.cloud`
    public let domainName: String

    /// "APPLICATION" | "ADDON" | "EXTERNAL"
    public let kind: String

    public init(id: String, label: String, domainName: String, kind: String) {
        self.id = id
        self.label = label
        self.domainName = domainName
        self.kind = kind
    }
}

// MARK: - CCNetworkGroupExternalPeerCreate

/// Model for creating an external peer. Body shape validated against the live v4 API:
/// it expects camelCase `label` + `publicKey` (NOT `name`/`public_key`/`allowed_ips`, which produced
/// a 400 "A form field was malformed / Missing required field"). The peer's IP is assigned by the API.
/// Mirrors clever-tools `clever ng create external <label> <ng> <publicKey>`.
public struct CCNetworkGroupExternalPeerCreate: Codable {

    /// Peer role — currently only "CLIENT" is supported (per clever-tools).
    public let peerRole: String

    /// WireGuard public key (API field `publicKey`, camelCase)
    public let publicKey: String

    /// Peer name (API field `label`)
    public let label: String

    /// Id of the EXTERNAL parent member this peer attaches to (`external_<uuid>`).
    public let parentMember: String

    public init(peerRole: String = "CLIENT", publicKey: String, label: String, parentMember: String) {
        self.peerRole = peerRole
        self.publicKey = publicKey
        self.label = label
        self.parentMember = parentMember
    }

    // MARK: - CodingKeys
    enum CodingKeys: String, CodingKey {
        case peerRole
        case publicKey
        case label
        case parentMember
    }
}

// MARK: - CCWireGuardConfiguration

/// WireGuard configuration for a peer
public struct CCWireGuardConfiguration: Codable {
    
    /// Interface configuration
    public let interface: WireGuardInterface
    
    /// Peer configurations
    public let peers: [WireGuardPeer]
    
    /// Generated configuration file content
    public let configContent: String?
    
    // MARK: - CodingKeys
    enum CodingKeys: String, CodingKey {
        case interface = "Interface"
        case peers = "Peer"
        case configContent = "config_content"
    }
}

// MARK: - WireGuardInterface

/// WireGuard interface configuration
public struct WireGuardInterface: Codable {
    
    /// Private key
    public let privateKey: String
    
    /// Address (IP and subnet)
    public let address: String
    
    /// DNS servers
    public let dns: [String]?
    
    // MARK: - CodingKeys
    enum CodingKeys: String, CodingKey {
        case privateKey = "PrivateKey"
        case address = "Address"
        case dns = "DNS"
    }
}

// MARK: - WireGuardPeer

/// WireGuard peer configuration
public struct WireGuardPeer: Codable {
    
    /// Public key
    public let publicKey: String
    
    /// Allowed IPs
    public let allowedIPs: String
    
    /// Endpoint
    public let endpoint: String?
    
    /// Keep alive interval
    public let persistentKeepalive: Int?
    
    // MARK: - CodingKeys
    enum CodingKeys: String, CodingKey {
        case publicKey = "PublicKey"
        case allowedIPs = "AllowedIPs"
        case endpoint = "Endpoint"
        case persistentKeepalive = "PersistentKeepalive"
    }
}

// MARK: - CCNetworkGroupStats

/// Network group statistics and metrics
public struct CCNetworkGroupStats: Codable {
    
    /// Number of connected members
    public let connectedMembers: Int
    
    /// Total number of members
    public let totalMembers: Int
    
    /// Number of active peers
    public let activePeers: Int
    
    /// Total data transferred (bytes)
    public let dataTransferred: Int64?
    
    /// Last activity timestamp
    public let lastActivity: Date?
    
    /// Computed connection rate
    public var connectionRate: Double {
        guard totalMembers > 0 else { return 0.0 }
        return Double(connectedMembers) / Double(totalMembers)
    }
    
    // MARK: - CodingKeys
    enum CodingKeys: String, CodingKey {
        case connectedMembers = "connected_members"
        case totalMembers = "total_members"
        case activePeers = "active_peers"
        case dataTransferred = "data_transferred"
        case lastActivity = "last_activity"
    }
}

// MARK: - Example Data

extension CCNetworkGroup {
    /// Creates an example network group for previews and testing
    public static func example() -> CCNetworkGroup {
        return CCNetworkGroup(
            id: "ng_example_123",
            name: "Example Network Group",
            description: "A sample network group for demonstration purposes",
            organizationId: "orga_example",
            cidr: "10.0.0.0/24",
            createdAt: Date(),
            updatedAt: Date(),
            status: "active",
            wireGuardEndpoint: "vpn.clever-cloud.com:51820",
            region: "par"
        )
    }
}