//
//  PacketTunnelProvider.swift
//  PacketTunnelExtension
//
//  Packet Tunnel Provider for Clever Cloud Network Groups.
//
//  Runs inside the PacketTunnelExtension target — NOT the main app. It owns the WireGuard tunnel
//  through WireGuardKit's `WireGuardAdapter`. The main app drives it via `NETunnelProviderManager`
//  (see `CCTunnelManager`).
//
//  Config delivery: the wg-quick `.conf` text (which contains the private key) arrives either in
//  the transient start options (manual connect, keyed by `confKey`) or — for system-initiated
//  starts — through `protocolConfiguration.passwordReference`, a keychain persistent reference to
//  an item the app stored in the shared App Group access group. The conf is never persisted in
//  `providerConfiguration` (that store is written to disk in cleartext). On `startTunnel` we parse
//  it with WireGuardKit's wg-quick parser and hand it to the adapter, which derives the
//  NEPacketTunnelNetworkSettings — including, for split tunnel, the included routes from each
//  peer's AllowedIPs (so only the network group CIDR is routed).
//

import NetworkExtension
import Security
import WireGuardKit
import os

final class PacketTunnelProvider: NEPacketTunnelProvider {

    /// Key under which the wg-quick `.conf` string is passed in the start options.
    /// Must match `CCTunnelManager.confKey` in the main app (separate module → duplicated on purpose).
    static let confKey = "wgQuickConfig"

    private lazy var adapter: WireGuardAdapter = {
        WireGuardAdapter(with: self) { logLevel, message in
            // DEBUG builds only: adapter messages include peer endpoints/handshake details, which
            // must not reach the unified log in Release (repo rule: no log output in Release).
            #if DEBUG
            os_log("%{public}s", log: .default, type: logLevel == .error ? .error : .info, message)
            #endif
        }
    }()

    override func startTunnel(options: [String: NSObject]?,
                              completionHandler: @escaping (Error?) -> Void) {
        guard let confString = resolveConfString(options: options) else {
            completionHandler(PacketTunnelError.missingConfiguration)
            return
        }

        let tunnelConfiguration: TunnelConfiguration
        do {
            tunnelConfiguration = try TunnelConfiguration(fromWgQuickConfig: confString,
                                                          called: "clevercloud-ng")
        } catch {
            // Do NOT embed the parse error in the returned error: WireGuardKit's ParseError cases
            // carry the offending config text (potentially the private key), and errors returned
            // here are recorded in the unified log / sysdiagnose by the system.
            #if DEBUG
            os_log("wg-quick parse failed: %{public}s", log: .default, type: .error,
                   String(describing: error))
            #endif
            completionHandler(PacketTunnelError.invalidConfiguration)
            return
        }

        adapter.start(tunnelConfiguration: tunnelConfiguration) { adapterError in
            completionHandler(adapterError)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        adapter.stop { _ in
            completionHandler()
        }
    }

    /// Lets the main app query live status (handshake / transfer counters) over the session channel.
    /// `CCTunnelManager` sends "stats"; we reply with WireGuard's runtime configuration text.
    override func handleAppMessage(_ messageData: Data,
                                   completionHandler: ((Data?) -> Void)?) {
        guard let request = String(data: messageData, encoding: .utf8) else {
            completionHandler?(nil)
            return
        }
        switch request {
        case "stats":
            adapter.getRuntimeConfiguration { settings in
                completionHandler?(settings?.data(using: .utf8))
            }
        default:
            completionHandler?(nil)
        }
    }

    // MARK: - Config resolution

    /// Start options first (manual connect — transient IPC, never persisted), then the keychain
    /// item referenced by the profile (system-initiated starts: reboot, on-demand).
    private func resolveConfString(options: [String: NSObject]?) -> String? {
        if let conf = options?[Self.confKey] as? String {
            return conf
        }
        guard let reference = protocolConfiguration.passwordReference else { return nil }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecValuePersistentRef: reference,
            kSecReturnData: true,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

enum PacketTunnelError: Error, LocalizedError {
    case missingConfiguration
    case invalidConfiguration

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "No WireGuard configuration was provided to the tunnel."
        case .invalidConfiguration:
            return "The WireGuard configuration could not be parsed."
        }
    }
}
