import SwiftUI
import UIKit
import Combine

// MARK: - AttachDeviceView
//
// Attaches THIS device to a network group and turns the in-app VPN on:
//   1. run the shared provisioning pipeline (local keygen → external peer → .conf with the
//      private key injected — see `WireGuardProvisioning`);
//   2. install the VPN profile and start the tunnel (`CCTunnelManager.connect`). Saving the
//      profile is what triggers the iOS "Allow VPN configurations" prompt, so the user always
//      authorizes the VPN as part of this flow — the per-NG toggle then works from the
//      persisted profile.
// The private key goes straight to the keychain and is never displayed; exporting a conf/QR
// for another device is `WireGuardConfigView`'s job.
struct AttachDeviceView: View {
    let networkGroupId: String
    let organizationId: String?
    let cleverCloudSDK: CleverCloudSDK
    /// Called after the peer is created so the parent can refresh its peer list.
    var onPeerCreated: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    /// Tunnel state lives in AppState (not sheet-local @State) so the connection and its status
    /// observer survive dismissing this sheet — see `AppState.tunnel`.
    @Environment(AppState.self) private var appState

    @State private var deviceName: String = UIDevice.current.name
    @State private var phase: Phase = .idle
    @State private var errorMessage: String?
    @State private var showingReplaceConfirmation = false
    @State private var cancellables = Set<AnyCancellable>()

    private var tunnel: CCTunnelManager { appState.tunnel }

    /// The single VPN profile currently belongs to ANOTHER network group: attaching here
    /// overwrites its keychain private key, permanently invalidating that peer.
    private var replacesOtherGroup: Bool {
        tunnel.configuredNetworkGroupId != nil && tunnel.configuredNetworkGroupId != networkGroupId
    }

    private enum Phase: Equatable {
        case idle       // waiting for the user to confirm the device name
        case working    // creating the peer + fetching the config
        case tunnel     // profile installed / installing — the tunnel status drives the UI
        case failed     // API failure before the tunnel step
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .idle: idleView
                case .working: workingView
                case .tunnel: tunnelView
                case .failed: failedView
                }
            }
            .navigationTitle("Attach this device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await tunnel.load() }
            .alert("Replace the current VPN?", isPresented: $showingReplaceConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Replace & Connect", role: .destructive) { start() }
            } message: {
                Text("This device is already attached to another network group. Attaching it here replaces the VPN configuration, and the previous peer — permanently unusable without its key — will be deleted from that group.")
            }
        }
    }

    // MARK: - Sub-views

    private var idleView: some View {
        Form {
            Section {
                TextField("Device name", text: $deviceName)
                    .autocorrectionDisabled(true)
            } header: {
                Text("Name")
            } footer: {
                Text("A WireGuard key pair is generated on this device and stored in the keychain — the private key never leaves it. iOS will ask you to allow adding a VPN configuration.")
            }

            if replacesOtherGroup {
                Section {
                    Label {
                        Text("This device is already attached to another network group. Attaching it here replaces that VPN configuration and permanently invalidates the previous peer (it will be deleted).")
                            .font(.caption)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .foregroundColor(.orange)
                }
            }

            Section {
                Button {
                    if replacesOtherGroup {
                        showingReplaceConfirmation = true
                    } else {
                        start()
                    }
                } label: {
                    Label("Attach & Connect", systemImage: "personalhotspot")
                }
                .disabled(deviceName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var workingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Creating peer & fetching configuration…")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tunnelView: some View {
        VStack(spacing: 16) {
            Image(systemName: tunnel.status == .connected ? "checkmark.shield.fill" : "bolt.horizontal.circle")
                .font(.system(size: 44))
                .foregroundColor(statusColor)
            Text(tunnel.status.label)
                .font(.headline)
                .foregroundColor(statusColor)
            if case .failed(let message) = tunnel.status {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            Text("The peer is attached to the network group. You can turn the VPN on and off anytime from the group's Overview tab.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var failedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundColor(.orange)
            Text("Failed to attach this device")
                .font(.headline)
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            Button("Try again") { phase = .idle }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var statusColor: Color {
        switch tunnel.status {
        case .connected: return .green
        case .connecting, .disconnecting: return .orange
        case .failed: return .red
        case .disconnected: return .secondary
        }
    }

    // MARK: - Flow

    private func start() {
        guard let orgId = organizationId else {
            errorMessage = "No organization selected."
            phase = .failed
            return
        }
        phase = .working
        errorMessage = nil
        let label = deviceName.trimmingCharacters(in: .whitespaces)

        // Capture the previous attachment now — connect() overwrites the configured ids.
        // Its private key is about to be replaced in the keychain, so that peer is dead;
        // it gets cleaned up server-side after the new attach succeeds. Profiles created
        // before organizationId was persisted can't be cleaned automatically (nil orgId).
        let previousPeer: (organizationId: String, networkGroupId: String, peerId: String)?
        if replacesOtherGroup,
           let previousOrgId = tunnel.configuredOrganizationId,
           let previousNgId = tunnel.configuredNetworkGroupId,
           let previousPeerId = tunnel.configuredPeerId {
            previousPeer = (previousOrgId, previousNgId, previousPeerId)
        } else {
            previousPeer = nil
        }

        WireGuardProvisioning.provision(
            sdk: cleverCloudSDK,
            organizationId: orgId,
            networkGroupId: networkGroupId,
            label: label
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    errorMessage = error.localizedDescription
                    phase = .failed
                }
            },
            receiveValue: { peerId, config in
                onPeerCreated?()
                phase = .tunnel
                Task {
                    await tunnel.connect(
                        confString: config,
                        label: label,
                        organizationId: orgId,
                        networkGroupId: networkGroupId,
                        peerId: peerId
                    )
                }
                if let previousPeer {
                    cleanUpPreviousPeer(previousPeer)
                }
            }
        )
        .store(in: &cancellables)
    }

    /// Best-effort removal of the now-unusable peer left in the previously attached network
    /// group (its private key was just overwritten). Failures are only logged: the peer is a
    /// zombie either way and can still be removed manually from that group's Peers tab.
    private func cleanUpPreviousPeer(_ previous: (organizationId: String, networkGroupId: String, peerId: String)) {
        cleverCloudSDK.networkGroups
            .deleteExternalPeerCascading(
                organizationId: previous.organizationId,
                networkGroupId: previous.networkGroupId,
                peerId: previous.peerId
            )
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        debugLog("⚠️ [AttachDeviceView] Could not clean up previous peer \(previous.peerId) in \(previous.networkGroupId): \(error.localizedDescription)")
                    } else {
                        debugLog("ℹ️ [AttachDeviceView] Cleaned up previous peer \(previous.peerId) in \(previous.networkGroupId)")
                    }
                },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)
    }
}
