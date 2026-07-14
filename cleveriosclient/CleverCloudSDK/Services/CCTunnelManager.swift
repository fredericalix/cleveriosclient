import Foundation
@preconcurrency import NetworkExtension
import Security

/// Drives the Clever Cloud Network Group WireGuard tunnel from the main app, via
/// `NETunnelProviderManager`.
///
/// iOS allows only ONE active packet tunnel, so this manages a single reusable VPN profile and
/// swaps its configuration when connecting to a different network group.
///
/// Config delivery: the wg-quick `.conf` (which contains the WireGuard private key) is stored in
/// the keychain — shared with the extension through the `group.com.fredalix.cciosclient` access
/// group — and the VPN profile only carries a keychain *persistent reference*
/// (`NEVPNProtocol.passwordReference`), never the key itself. The conf is additionally passed in
/// the transient `startVPNTunnel(options:)` dictionary (IPC only, not persisted) so manual
/// connects work even if the keychain access group is unavailable.
///
/// Phase 0 (spike): `connect(confString:label:)` takes a ready wg-quick `.conf` — produced by the
/// existing `WireGuardConfigView` pipeline — and starts the tunnel. Later phases add live stats
/// and on-demand auto-reconnect.
@MainActor
@Observable
final class CCTunnelManager {

    /// Must match the extension target's bundle id and the shared App Group exactly.
    static let tunnelBundleId = "com.fredalix.cciosclient.PacketTunnelExtension"
    static let appGroup = "group.com.fredalix.cciosclient"
    /// Must match `PacketTunnelProvider.confKey` in the extension (separate module → duplicated).
    private static let confKey = "wgQuickConfig"
    /// `providerConfiguration` keys persisting which org/NG/peer the profile belongs to.
    private static let organizationIdKey = "organizationId"
    private static let networkGroupIdKey = "networkGroupId"
    private static let peerIdKey = "peerId"

    enum Status: Equatable {
        case disconnected
        case connecting
        case connected
        case disconnecting
        case failed(String)

        var label: String {
            switch self {
            case .disconnected: return "Disconnected"
            case .connecting: return "Connecting…"
            case .connected: return "Connected"
            case .disconnecting: return "Disconnecting…"
            case .failed(let msg): return "Failed: \(msg)"
            }
        }
    }

    private(set) var status: Status = .disconnected
    /// Label of the network group whose tunnel is currently loaded.
    private(set) var activeLabel: String?
    /// Network group the persisted VPN profile belongs to (from `providerConfiguration`).
    /// The association lives in the NE profile itself so it disappears with the profile if the
    /// user deletes the VPN in iOS Settings — it can't desynchronize.
    private(set) var configuredNetworkGroupId: String?
    /// External peer the persisted VPN profile was created for (from `providerConfiguration`).
    private(set) var configuredPeerId: String?
    /// Owner (org or user_…) of the configured network group — needed to clean the previous
    /// peer up when the device is re-attached to a different group. Nil on profiles created
    /// before this key existed.
    private(set) var configuredOrganizationId: String?

    private var manager: NETunnelProviderManager?
    /// Not observable state; `nonisolated(unsafe)` so `deinit` (nonisolated) can cancel it.
    /// Written only on the MainActor, and `Task.cancel()` is thread-safe.
    @ObservationIgnored nonisolated(unsafe) private var observerTask: Task<Void, Never>?
    /// Whether `load()` has completed at least once — `connect()` awaits it before deciding to
    /// create a fresh profile, so a connect racing the initial load can't install a duplicate.
    private var loaded = false

    deinit {
        observerTask?.cancel()
    }

    /// Load the existing VPN profile (if any) and start observing its status.
    func load() async {
        let managers = (try? await NETunnelProviderManager.loadAllFromPreferences()) ?? []
        manager = managers.first
        loaded = true
        syncConfiguredIds()
        startObserving()
        syncStatus()
    }

    /// Install/refresh the single VPN profile with `confString` and start the tunnel.
    /// `organizationId`/`networkGroupId`/`peerId` are persisted in the profile's
    /// `providerConfiguration` so the on/off toggle can be scoped to the right network group,
    /// the profile torn down when its peer is deleted, and the previous peer cleaned up when
    /// the device is re-attached elsewhere.
    func connect(confString: String, label: String, organizationId: String, networkGroupId: String, peerId: String) async {
        if !loaded { await load() }
        status = .connecting
        let mgr = manager ?? NETunnelProviderManager()

        // The conf contains the private key: keychain only, referenced from the profile.
        guard let passwordReference = Self.storeConfInKeychain(confString) else {
            status = .failed("Could not store the configuration in the keychain.")
            return
        }

        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = Self.tunnelBundleId
        proto.serverAddress = label // display-only in Settings > VPN
        proto.passwordReference = passwordReference
        proto.providerConfiguration = [
            Self.organizationIdKey: organizationId,
            Self.networkGroupIdKey: networkGroupId,
            Self.peerIdKey: peerId,
        ]

        mgr.protocolConfiguration = proto
        mgr.localizedDescription = "Clever Cloud — \(label)"
        mgr.isEnabled = true

        do {
            try await mgr.saveToPreferences()
            try await mgr.loadFromPreferences() // reload so the connection handle is valid
            manager = mgr
            syncConfiguredIds()
            startObserving()
            try mgr.connection.startVPNTunnel(options: [Self.confKey: confString as NSObject])
            activeLabel = label
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Start the tunnel from the persisted profile, without re-generating a peer. No start
    /// options: the extension reads the conf from the keychain via `passwordReference`.
    func startSaved() async {
        if !loaded { await load() }
        guard let mgr = manager else {
            status = .failed("No saved VPN configuration.")
            return
        }
        status = .connecting
        do {
            // Re-enable in case the user toggled the profile off in iOS Settings.
            if !mgr.isEnabled {
                mgr.isEnabled = true
                try await mgr.saveToPreferences()
                try await mgr.loadFromPreferences()
                startObserving()
            }
            try mgr.connection.startVPNTunnel()
            activeLabel = mgr.localizedDescription
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Full removal of the device's VPN: stops the tunnel, deletes the profile from iOS
    /// Settings, and wipes the wg-quick conf (private key) from the keychain. Called when the
    /// peer this profile was created for is deleted — the config is permanently dead server-side
    /// and must not survive as a zombie VPN on the device.
    func tearDown() async {
        observerTask?.cancel()
        if let connection = manager?.connection,
           connection.status != .disconnected && connection.status != .invalid {
            connection.stopVPNTunnel()
        }
        if let mgr = manager {
            do {
                try await mgr.removeFromPreferences()
            } catch {
                debugLog("⚠️ [CCTunnelManager] removeFromPreferences failed: \(error.localizedDescription)")
            }
        }
        Self.deleteConfFromKeychain()
        manager = nil
        status = .disconnected
        activeLabel = nil
        configuredOrganizationId = nil
        configuredNetworkGroupId = nil
        configuredPeerId = nil
    }

    private func syncConfiguredIds() {
        let providerConfig = (manager?.protocolConfiguration as? NETunnelProviderProtocol)?
            .providerConfiguration
        configuredOrganizationId = providerConfig?[Self.organizationIdKey] as? String
        configuredNetworkGroupId = providerConfig?[Self.networkGroupIdKey] as? String
        configuredPeerId = providerConfig?[Self.peerIdKey] as? String
    }

    func disconnect() {
        guard let connection = manager?.connection,
              connection.status == .connected
                || connection.status == .connecting
                || connection.status == .reasserting else {
            // Nothing to stop (failed/never-started connect): just reset the UI state.
            status = .disconnected
            activeLabel = nil
            return
        }
        status = .disconnecting
        connection.stopVPNTunnel()
    }

    // MARK: - Status observation

    private func startObserving() {
        observerTask?.cancel()
        guard let connection = manager?.connection else { return }
        observerTask = Task { [weak self] in
            let notifications = NotificationCenter.default.notifications(
                named: .NEVPNStatusDidChange, object: connection
            )
            for await _ in notifications {
                self?.syncStatus()
            }
        }
    }

    private func syncStatus() {
        guard let connection = manager?.connection else {
            status = .disconnected
            activeLabel = nil
            return
        }
        let newStatus: Status
        switch connection.status {
        case .connected: newStatus = .connected
        case .connecting, .reasserting: newStatus = .connecting
        case .disconnecting: newStatus = .disconnecting
        case .disconnected, .invalid: newStatus = .disconnected
        @unknown default: newStatus = .disconnected
        }

        if newStatus == .disconnected {
            activeLabel = nil
            // Keep an explicit failure visible until the next connect attempt instead of letting
            // the trailing status notification repaint it as a plain "Disconnected".
            if case .failed = status { return }
            // connecting/connected → disconnected without the user asking: surface the tunnel's
            // real error (e.g. PacketTunnelError from the extension) instead of dropping it.
            if status == .connecting || status == .connected {
                fetchDisconnectError(from: connection)
            }
        }
        status = newStatus
    }

    /// Asynchronously replaces a bare `.disconnected` with `.failed(reason)` when the system has
    /// recorded a disconnect error for the last session.
    private func fetchDisconnectError(from connection: NEVPNConnection) {
        connection.fetchLastDisconnectError { [weak self] error in
            guard let error else { return }
            Task { @MainActor [weak self] in
                guard let self, self.status == .disconnected else { return }
                self.status = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Keychain

    private static let keychainService = "com.fredalix.cciosclient.ng-tunnel"
    private static let keychainAccount = "wg-quick-config"

    /// Stores the wg-quick conf as a generic-password item and returns its persistent reference.
    ///
    /// Tries the shared App Group access group first (on iOS, app groups double as keychain access
    /// groups) so the extension can read the item on system-initiated starts. Falls back to the
    /// app's default access group if the entitlement isn't provisioned yet — manual connects still
    /// work then, because the conf also travels in the start options.
    private static func storeConfInKeychain(_ conf: String) -> Data? {
        for accessGroup in [appGroup, nil] {
            var base: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: keychainService,
                kSecAttrAccount: keychainAccount,
            ]
            if let accessGroup { base[kSecAttrAccessGroup] = accessGroup }

            SecItemDelete(base as CFDictionary) // replace any previous conf

            var add = base
            add[kSecValueData] = Data(conf.utf8)
            add[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
            add[kSecReturnPersistentRef] = true
            var result: CFTypeRef?
            let osStatus = SecItemAdd(add as CFDictionary, &result)
            if osStatus == errSecSuccess, let ref = result as? Data {
                return ref
            }
            debugLog("⚠️ [CCTunnelManager] Keychain store failed (status \(osStatus), accessGroup: \(accessGroup ?? "default"))")
        }
        return nil
    }

    /// Best-effort removal of the stored conf from both access groups (the item may live in
    /// either, depending on which one `storeConfInKeychain` succeeded with).
    private static func deleteConfFromKeychain() {
        for accessGroup in [appGroup, nil] {
            var query: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: keychainService,
                kSecAttrAccount: keychainAccount,
            ]
            if let accessGroup { query[kSecAttrAccessGroup] = accessGroup }
            SecItemDelete(query as CFDictionary)
        }
    }
}
