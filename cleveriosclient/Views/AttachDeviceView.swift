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
    @State private var cancellables = Set<AnyCancellable>()

    private var tunnel: CCTunnelManager { appState.tunnel }

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

            Section {
                Button {
                    start()
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
                        networkGroupId: networkGroupId,
                        peerId: peerId
                    )
                }
            }
        )
        .store(in: &cancellables)
    }
}
