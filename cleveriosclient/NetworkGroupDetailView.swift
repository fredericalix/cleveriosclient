import SwiftUI
import Combine

/// Detail screen for a network group: overview, members (apps/add-ons) and peers (incl. attaching
/// this device as an external WireGuard peer). Mirrors ApplicationDetailView/AddonDetailView.
struct NetworkGroupDetailView: View {
    let networkGroup: CCNetworkGroup
    let organizationId: String?
    let cleverCloudSDK: CleverCloudSDK

    @Environment(\.dismiss) private var dismiss

    @State private var members: [CCNetworkGroupMember] = []
    @State private var peers: [CCNetworkGroupPeer] = []
    @State private var loadError: String?
    @State private var didRunInitialLoad = false
    @State private var selectedTab = 0

    @State private var showingAddMember = false
    @State private var showingAttachDevice = false
    @State private var showingDeleteConfirmation = false
    @State private var deleteConfirmationText = ""
    @State private var isDeleting = false
    @State private var actionError: String?
    @State private var isLoadingData = false
    @State private var pendingLoads = 0
    /// Member/peer staged for removal — set by the row button, confirmed via alert. Removing a
    /// member breaks its private connectivity; removing a peer invalidates an installed WireGuard
    /// config. Neither should fire on a single (easily mis-tapped) row-button tap.
    @State private var pendingMemberRemoval: CCNetworkGroupMember?
    @State private var pendingPeerRemoval: CCNetworkGroupPeer?

    @State private var cancellables = Set<AnyCancellable>()

    var body: some View {
        VStack(spacing: 0) {
            header
            TabView(selection: $selectedTab) {
                overviewTab
                    .tabItem { Label("Overview", systemImage: "info.circle") }
                    .tag(0)
                membersTab
                    .tabItem { Label("Members", systemImage: "square.stack.3d.up.fill") }
                    .tag(1)
                peersTab
                    .tabItem { Label("Peers", systemImage: "laptopcomputer.and.iphone") }
                    .tag(2)
            }
        }
        .navigationTitle(networkGroup.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !didRunInitialLoad else { return }
            didRunInitialLoad = true
            reload()
        }
        .sheet(isPresented: $showingAddMember) {
            AddNetworkGroupMemberSheet(
                networkGroupId: networkGroup.id,
                organizationId: organizationId,
                cleverCloudSDK: cleverCloudSDK,
                existingResourceIds: Set(members.map { $0.resourceId }),
                onMemberAdded: { reload() }
            )
        }
        .sheet(isPresented: $showingAttachDevice) {
            WireGuardConfigView(
                networkGroupId: networkGroup.id,
                organizationId: organizationId,
                cleverCloudSDK: cleverCloudSDK,
                onPeerCreated: { reload() }
            )
        }
        .alert(
            "Remove member?",
            isPresented: Binding(
                get: { pendingMemberRemoval != nil },
                set: { if !$0 { pendingMemberRemoval = nil } }
            ),
            presenting: pendingMemberRemoval
        ) { member in
            Button("Cancel", role: .cancel) { pendingMemberRemoval = nil }
            Button("Remove", role: .destructive) {
                removeMember(member)
                pendingMemberRemoval = nil
            }
        } message: { member in
            Text("“\(member.name)” will lose its private connectivity to the other members of this network group.")
        }
        .alert(
            "Remove peer?",
            isPresented: Binding(
                get: { pendingPeerRemoval != nil },
                set: { if !$0 { pendingPeerRemoval = nil } }
            ),
            presenting: pendingPeerRemoval
        ) { peer in
            Button("Cancel", role: .cancel) { pendingPeerRemoval = nil }
            Button("Remove", role: .destructive) {
                removeExternalPeer(peer)
                pendingPeerRemoval = nil
            }
        } message: { peer in
            Text("The WireGuard configuration installed for “\(peer.name)” will stop working permanently.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.title)
                    .foregroundColor(.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text(networkGroup.name)
                        .font(.title3).fontWeight(.bold)
                    if let cidr = networkGroup.cidr {
                        Text(cidr).font(.caption).foregroundColor(.secondary)
                    }
                }
                Spacer()
                statusBadge(networkGroup.status, fallbackActive: networkGroup.isActive)
            }
            if let actionError {
                Text(actionError).font(.caption).foregroundColor(.red)
            }
        }
        .padding()
        .background(Color(.systemGray6))
    }

    // MARK: - Overview tab

    private var overviewTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                infoCard
                dangerZone
            }
            .padding()
        }
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Information").font(.headline)
            infoRow("Name", networkGroup.name)
            infoRow("ID", networkGroup.id, monospaced: true)
            if let cidr = networkGroup.cidr { infoRow("Network", cidr, monospaced: true) }
            if let region = networkGroup.region { infoRow("Region", region.uppercased()) }
            if let status = networkGroup.status { infoRow("Status", status.capitalized) }
            infoRow("Members", "\(appAndAddonMembers.count)")
            infoRow("Peers", "\(peers.count)")
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var dangerZone: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("⚠️ Danger Zone").font(.headline).foregroundColor(.red)
            Text("Permanently delete this network group. Members lose their private connectivity. This cannot be undone.")
                .font(.subheadline).foregroundColor(.secondary)
            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "trash.fill")
                    Text(isDeleting ? "Deleting…" : "Delete Network Group")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(isDeleting)
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(12)
        .alert("Delete network group", isPresented: $showingDeleteConfirmation) {
            TextField("Type the name to confirm", text: $deleteConfirmationText)
                .autocorrectionDisabled(true)
            Button("Cancel", role: .cancel) { deleteConfirmationText = "" }
            Button("Delete", role: .destructive) { deleteNetworkGroup() }
                .disabled(deleteConfirmationText != networkGroup.name)
        } message: {
            Text("This permanently deletes “\(networkGroup.name)”.\n\nType “\(networkGroup.name)” to confirm.")
        }
    }

    // MARK: - Members tab

    /// App/add-on members only. EXTERNAL members are the parent constructs auto-created for external
    /// WireGuard devices — the device itself is shown under the Peers tab, so we hide its parent here
    /// to avoid a confusing duplicate row (and a destructive button that would orphan the peer).
    private var appAndAddonMembers: [CCNetworkGroupMember] {
        members.filter { $0.type != .external }
    }

    private var membersTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Members").font(.title2).fontWeight(.bold)
                    Spacer()
                    Button {
                        showingAddMember = true
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.title2)
                    }
                    .accessibilityLabel("Add member")
                }

                // A fetch failure must not render as "no members" — that empty state invites the
                // user to mutate a group whose real state couldn't even be read.
                if let loadError {
                    loadErrorView(loadError)
                } else if isLoadingData && appAndAddonMembers.isEmpty {
                    ProgressView("Loading members…")
                        .frame(maxWidth: .infinity).padding(.vertical, 24)
                } else if appAndAddonMembers.isEmpty {
                    ContentUnavailableView(
                        "No members",
                        systemImage: "square.stack.3d.up",
                        description: Text("Add applications or add-ons to connect them over the private network.")
                    )
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
                } else {
                    ForEach(appAndAddonMembers) { member in
                        memberRow(member)
                    }
                }
            }
            .padding()
        }
    }

    private func memberRow(_ member: CCNetworkGroupMember) -> some View {
        HStack {
            Image(systemName: member.type.icon).foregroundColor(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.name).font(.subheadline).fontWeight(.medium)
                Text("\(member.type.displayName) • \(member.resourceId)")
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            if let ip = member.ipAddress {
                Text(ip).font(.system(.caption2, design: .monospaced)).foregroundColor(.secondary)
            }
            Button(role: .destructive) {
                pendingMemberRemoval = member
            } label: {
                Image(systemName: "minus.circle").foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove member \(member.name)")
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    // MARK: - Peers tab

    private var peersTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Peers").font(.title2).fontWeight(.bold)
                    Spacer()
                    Button {
                        showingAttachDevice = true
                    } label: {
                        Label("Attach this device", systemImage: "qrcode")
                    }
                    .buttonStyle(.borderedProminent)
                }

                if let loadError {
                    loadErrorView(loadError)
                } else if isLoadingData && peers.isEmpty {
                    ProgressView("Loading peers…")
                        .frame(maxWidth: .infinity).padding(.vertical, 24)
                } else if peers.isEmpty {
                    ContentUnavailableView(
                        "No peers",
                        systemImage: "laptopcomputer.and.iphone",
                        description: Text("Attach this device (or another machine) as an external WireGuard peer.")
                    )
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
                } else {
                    ForEach(peers) { peer in
                        peerRow(peer)
                    }
                }
            }
            .padding()
        }
    }

    private func peerRow(_ peer: CCNetworkGroupPeer) -> some View {
        HStack {
            Image(systemName: peer.isExternal ? "globe" : "house").foregroundColor(peer.isExternal ? .blue : .green)
            VStack(alignment: .leading, spacing: 2) {
                Text(peer.name).font(.subheadline).fontWeight(.medium)
                Text(peer.isExternal ? "External peer" : (peer.parentMember.map { "Linked to \($0)" } ?? "Internal peer"))
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            if peer.isExternal {
                Button(role: .destructive) {
                    pendingPeerRemoval = peer
                } label: {
                    Image(systemName: "minus.circle").foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove peer \(peer.name)")
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    // MARK: - Helpers

    private func loadErrorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            ContentUnavailableView(
                "Failed to load",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
            Button("Retry") { reload() }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func infoRow(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(monospaced ? .system(.caption, design: .monospaced) : .subheadline)
                .multilineTextAlignment(.trailing)
        }
    }

    @ViewBuilder
    private func statusBadge(_ status: String?, fallbackActive: Bool) -> some View {
        let isActive = (status?.lowercased() == "active") || (status == nil && fallbackActive)
        HStack(spacing: 4) {
            Circle().fill(isActive ? .green : .gray).frame(width: 8, height: 8)
            Text((status ?? (fallbackActive ? "active" : "unknown")).capitalized)
                .font(.caption).fontWeight(.medium)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background((isActive ? Color.green : Color.gray).opacity(0.15))
        .cornerRadius(10)
    }

    // MARK: - Data

    private func reload() {
        guard let orgId = organizationId else { return }
        actionError = nil
        loadError = nil
        isLoadingData = true
        pendingLoads = 2

        cleverCloudSDK.networkGroups
            .getNetworkGroupMembers(organizationId: orgId, networkGroupId: networkGroup.id)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    pendingLoads -= 1
                    if pendingLoads <= 0 { isLoadingData = false }
                    if case .failure(let error) = completion { loadError = error.localizedDescription }
                },
                receiveValue: { members = $0 }
            )
            .store(in: &cancellables)

        cleverCloudSDK.networkGroups
            .getNetworkGroupPeers(organizationId: orgId, networkGroupId: networkGroup.id)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    pendingLoads -= 1
                    if pendingLoads <= 0 { isLoadingData = false }
                    if case .failure(let error) = completion { loadError = error.localizedDescription }
                },
                receiveValue: { peers = $0 }
            )
            .store(in: &cancellables)
    }

    private func removeMember(_ member: CCNetworkGroupMember) {
        guard let orgId = organizationId else { return }
        cleverCloudSDK.networkGroups
            .removeNetworkGroupMember(organizationId: orgId, networkGroupId: networkGroup.id, memberId: member.resourceId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion { actionError = error.localizedDescription }
                    else { reload() }
                },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)
    }

    private func removeExternalPeer(_ peer: CCNetworkGroupPeer) {
        guard let orgId = organizationId else { return }
        let sdk = cleverCloudSDK.networkGroups
        let ngId = networkGroup.id
        // An external peer is paired with an `external_<uuid>` parent member (created together in
        // createExternalPeer). Delete the peer, then best-effort delete that parent so no orphan is left.
        sdk.removeNetworkGroupExternalPeer(organizationId: orgId, networkGroupId: ngId, peerId: peer.id)
            .flatMap { _ -> AnyPublisher<Void, CCError> in
                if let parent = peer.parentMember, parent.hasPrefix("external_") {
                    return sdk.removeNetworkGroupMember(organizationId: orgId, networkGroupId: ngId, memberId: parent)
                        .catch { _ in Just(()).setFailureType(to: CCError.self) } // parent may be gone / cascaded
                        .eraseToAnyPublisher()
                }
                return Just(()).setFailureType(to: CCError.self).eraseToAnyPublisher()
            }
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion { actionError = error.localizedDescription }
                    else { reload() }
                },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)
    }

    private func deleteNetworkGroup() {
        // In-action backstop: `.disabled` on alert buttons isn't reliably re-evaluated while the
        // alert is presented, so the type-to-confirm gate must also be enforced here.
        guard deleteConfirmationText == networkGroup.name else {
            actionError = "Name did not match — network group not deleted."
            deleteConfirmationText = ""
            return
        }
        deleteConfirmationText = ""
        guard let orgId = organizationId else { return }
        isDeleting = true
        cleverCloudSDK.networkGroups
            .deleteNetworkGroup(organizationId: orgId, networkGroupId: networkGroup.id)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    isDeleting = false
                    if case .failure(let error) = completion {
                        actionError = error.localizedDescription
                    } else {
                        // Both ContentView layouts observe this to drop the group from their lists
                        // and reset any selection; dismissing pops the pushed detail on iPhone.
                        NotificationCenter.default.post(name: .networkGroupDestroyed, object: networkGroup.id)
                        dismiss()
                    }
                },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)
    }
}

// MARK: - Add Member Sheet

/// Lets the user pick one of the organization's applications or add-ons to add as a network-group member.
private struct AddNetworkGroupMemberSheet: View {
    let networkGroupId: String
    let organizationId: String?
    let cleverCloudSDK: CleverCloudSDK
    let existingResourceIds: Set<String>
    var onMemberAdded: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var applications: [CCApplication] = []
    @State private var addons: [CCAddon] = []
    @State private var isLoading = true
    @State private var addingResourceId: String?
    @State private var errorMessage: String?
    @State private var cancellables = Set<AnyCancellable>()

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading resources…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        if let errorMessage {
                            Text(errorMessage).font(.caption).foregroundColor(.red)
                        }
                        Section("Applications") {
                            ForEach(applications.filter { !existingResourceIds.contains($0.id) }) { app in
                                resourceRow(name: app.name, subtitle: app.id, icon: "app.badge",
                                            isAdding: addingResourceId == app.id) {
                                    add(.application, resourceId: app.id)
                                }
                            }
                        }
                        Section("Add-ons") {
                            ForEach(addons.filter { !existingResourceIds.contains($0.id) }) { addon in
                                resourceRow(name: addon.name, subtitle: addon.provider.name, icon: "puzzlepiece.extension",
                                            isAdding: addingResourceId == addon.id) {
                                    add(.addon, resourceId: addon.id)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
            }
            .onAppear(perform: loadResources)
        }
    }

    private func resourceRow(name: String, subtitle: String, icon: String, isAdding: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                VStack(alignment: .leading) {
                    Text(name).foregroundColor(.primary)
                    Text(subtitle).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                if isAdding { ProgressView() } else { Image(systemName: "plus.circle").foregroundColor(.blue) }
            }
        }
        .disabled(addingResourceId != nil)
    }

    private func loadResources() {
        let appsPublisher: AnyPublisher<[CCApplication], CCError>
        let addonsPublisher: AnyPublisher<[CCAddon], CCError>
        if let orgId = organizationId, CCOrganization.isOrganizationId(orgId) {
            appsPublisher = cleverCloudSDK.applications.getApplicationsWithStates(forOrganization: orgId)
            addonsPublisher = cleverCloudSDK.getOrganizationAddons(organizationId: orgId)
        } else {
            appsPublisher = cleverCloudSDK.applications.getApplicationsWithStates()
            addonsPublisher = cleverCloudSDK.getUserAddons()
        }

        Publishers.Zip(appsPublisher, addonsPublisher)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    isLoading = false
                    if case .failure(let error) = completion { errorMessage = error.localizedDescription }
                },
                receiveValue: { apps, loadedAddons in
                    applications = apps.sortedByName()
                    addons = loadedAddons.sortedByName()
                }
            )
            .store(in: &cancellables)
    }

    private func add(_ type: CCNetworkGroupMemberType, resourceId: String) {
        guard let orgId = organizationId else { return }
        addingResourceId = resourceId
        let publisher = type == .application
            ? cleverCloudSDK.networkGroups.addApplicationToNetworkGroup(organizationId: orgId, networkGroupId: networkGroupId, applicationId: resourceId)
            : cleverCloudSDK.networkGroups.addAddonToNetworkGroup(organizationId: orgId, networkGroupId: networkGroupId, addonId: resourceId)

        publisher
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    addingResourceId = nil
                    if case .failure(let error) = completion {
                        errorMessage = error.localizedDescription
                    } else {
                        onMemberAdded?()
                        dismiss()
                    }
                },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)
    }
}
