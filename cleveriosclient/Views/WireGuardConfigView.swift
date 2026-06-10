import SwiftUI
import UIKit
import Combine
import CryptoKit
import CoreImage.CIFilterBuiltins

// MARK: - WireGuard key generation

/// Generates a WireGuard-compatible Curve25519 key pair locally. The private key never leaves the
/// device — only the public key is sent to the API when creating the external peer.
enum WireGuardKey {
    struct Pair {
        let privateKeyBase64: String
        let publicKeyBase64: String
    }

    static func generate() -> Pair {
        let priv = Curve25519.KeyAgreement.PrivateKey()
        return Pair(
            privateKeyBase64: priv.rawRepresentation.base64EncodedString(),
            publicKeyBase64: priv.publicKey.rawRepresentation.base64EncodedString()
        )
    }
}

// MARK: - QR generation

enum QRCode {
    static func image(from string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - WireGuardConfigView
//
// Attaches "this device" to a network group as an external WireGuard peer:
//   1. generate a Curve25519 key pair locally (private key stays on device);
//   2. create the external peer with the public key;
//   3. fetch the peer's WireGuard config (text) and inject the local private key;
//   4. present the .conf as text + QR + copy, to import into a WireGuard client.
struct WireGuardConfigView: View {
    let networkGroupId: String
    let organizationId: String?
    let cleverCloudSDK: CleverCloudSDK
    /// Called after the peer is created so the parent can refresh its peer list.
    var onPeerCreated: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var deviceName: String = "My device"
    @State private var phase: Phase = .idle
    @State private var configText: String = ""
    /// Whether the assembled config contains a `[Peer]` block. A freshly-created peer in a network
    /// group with no gateway yet comes back as `[Interface]`-only, which imports but routes nowhere.
    @State private var configHasPeer: Bool = false
    @State private var errorMessage: String?
    @State private var cancellables = Set<AnyCancellable>()

    private enum Phase: Equatable {
        case idle          // waiting for the user to name the device and tap Generate
        case working       // generating key + creating peer + fetching config
        case ready         // config assembled
        case failed
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .idle: idleView
                case .working: workingView
                case .ready: readyView
                case .failed: failedView
                }
            }
            .navigationTitle("Attach this device")
            .navigationBarTitleDisplayMode(.inline)
            // The ready view shows the WireGuard private key (text + QR). Cover it while the scene
            // is not active so the key doesn't land in the app-switcher snapshot.
            .overlay {
                if phase == .ready && scenePhase != .active {
                    ZStack {
                        Rectangle().fill(.regularMaterial).ignoresSafeArea()
                        Label("Hidden while in background", systemImage: "eye.slash")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
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
                Text("A WireGuard key pair will be generated on this device. The private key never leaves it and is shown only once.")
            }

            Section {
                Button {
                    start()
                } label: {
                    Label("Generate configuration", systemImage: "key.fill")
                }
                .disabled(deviceName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var workingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Generating key & creating peer…")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var failedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundColor(.orange)
            Text("Failed to create the peer")
                .font(.headline)
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            Button("Retry") { phase = .idle }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var readyView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !configHasPeer {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("No gateway peer yet", systemImage: "info.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.blue)
                        Text("This network group has no gateway peer yet, so the configuration below has no “[Peer]” section and will not route traffic until one exists. You can still save this private key now (it is shown only once); re-create the peer once a gateway is available to get a complete, connectable configuration.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                }

                Label("Private key shown once", systemImage: "exclamationmark.shield.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.orange)
                Text(configHasPeer
                     ? "This configuration contains a private key that is not stored anywhere else. Import it now (scan the QR from the WireGuard app, or copy the text). If you lose it, delete this peer and create a new one."
                     : "This configuration contains a private key that is not stored anywhere else. Save it now (scan the QR or copy the text) — it cannot be shown again. If you lose it, delete this peer and create a new one.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let qr = QRCode.image(from: configText) {
                    HStack {
                        Spacer()
                        Image(uiImage: qr)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 240, maxHeight: 240)
                            .accessibilityLabel("WireGuard configuration QR code")
                        Spacer()
                    }
                }

                Text(configText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)

                Button {
                    // The config contains a private key — auto-expire it from the clipboard and keep
                    // it off Universal Clipboard (it would otherwise sync to the user's other devices).
                    UIPasteboard.general.setItems(
                        [["public.utf8-plain-text": configText]],
                        options: [
                            .expirationDate: Date().addingTimeInterval(120),
                            .localOnly: true
                        ]
                    )
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                } label: {
                    Label("Copy configuration", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
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

        let keys = WireGuardKey.generate()

        cleverCloudSDK.networkGroups
            .createExternalPeer(
                organizationId: orgId,
                networkGroupId: networkGroupId,
                publicKey: keys.publicKeyBase64,
                label: deviceName.trimmingCharacters(in: .whitespaces)
            )
            .flatMap { peer -> AnyPublisher<String, CCError> in
                cleverCloudSDK.networkGroups.getWireGuardConfigurationText(
                    organizationId: orgId,
                    networkGroupId: networkGroupId,
                    peerId: peer.id
                )
            }
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        errorMessage = error.localizedDescription
                        phase = .failed
                    }
                },
                receiveValue: { rawConfig in
                    let assembled = Self.injectingPrivateKey(keys.privateKeyBase64, into: rawConfig)
                    configText = assembled
                    configHasPeer = assembled.range(of: "[Peer]", options: .caseInsensitive) != nil
                    phase = .ready
                    onPeerCreated?()
                }
            )
            .store(in: &cancellables)
    }

    /// Inserts/overwrites the `[Interface] PrivateKey` line with the locally-generated key, since the
    /// API never receives (and therefore can't return) the external peer's private key.
    /// `nonisolated` because it's a pure string transform — callable off the main actor (e.g. tests)
    /// even though `View` is `@MainActor`.
    nonisolated static func injectingPrivateKey(_ privateKey: String, into config: String) -> String {
        var lines = config.components(separatedBy: .newlines)
        if let idx = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("privatekey") }) {
            lines[idx] = "PrivateKey = \(privateKey)"
            return lines.joined(separator: "\n")
        }
        // No PrivateKey line — insert one right after [Interface].
        if let idx = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "[Interface]" }) {
            lines.insert("PrivateKey = \(privateKey)", at: idx + 1)
            return lines.joined(separator: "\n")
        }
        // No [Interface] section at all — prepend a minimal one.
        return "[Interface]\nPrivateKey = \(privateKey)\n\n" + config
    }
}
