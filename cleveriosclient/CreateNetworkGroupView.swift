import SwiftUI
import Combine

/// Creation form for a network group, mirroring CreateAddonView's structure.
struct CreateNetworkGroupView: View {
    let organizationId: String?
    let cleverCloudSDK: CleverCloudSDK
    var onNetworkGroupCreated: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var description = ""
    @State private var cidr = ""
    @State private var region = "par"

    @State private var isCreating = false
    @State private var showingConfirmation = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var cancellables = Set<AnyCancellable>()

    /// Common Clever Cloud regions. Validated against the live API.
    private let regions = ["par", "rbx", "scw", "mtl", "sgp", "syd", "wsw"]

    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && organizationId != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .autocorrectionDisabled(true)
                    TextField("Description (optional)", text: $description)
                } header: {
                    Text("Network group")
                }

                Section {
                    TextField("CIDR (optional, e.g. 10.0.0.0/16)", text: $cidr)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                    Picker("Region", selection: $region) {
                        ForEach(regions, id: \.self) { Text($0.uppercased()).tag($0) }
                    }
                } header: {
                    Text("Network")
                } footer: {
                    Text("Leave the CIDR empty to let Clever Cloud assign one automatically.")
                }

                if organizationId == nil {
                    Section {
                        Label("Select an organization first — network groups are owned by an organization.", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
            .navigationTitle("Create Network Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isCreating ? "Creating…" : "Create") {
                        showingConfirmation = true
                    }
                    .disabled(!isFormValid || isCreating)
                }
            }
            .alert("Create network group?", isPresented: $showingConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Create") { create() }
            } message: {
                Text("Create the network group “\(name)”\(region.isEmpty ? "" : " in \(region.uppercased())")?")
            }
            .alert("Creation failed", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }

    private func create() {
        guard let organizationId else { return }
        let trimmedCidr = cidr.trimmingCharacters(in: .whitespaces)
        let trimmedDescription = description.trimmingCharacters(in: .whitespaces)

        let request = CCNetworkGroupCreate(
            name: name.trimmingCharacters(in: .whitespaces),
            description: trimmedDescription.isEmpty ? nil : trimmedDescription,
            cidr: trimmedCidr.isEmpty ? nil : trimmedCidr,
            region: region.isEmpty ? nil : region
        )

        isCreating = true
        cleverCloudSDK.networkGroups
            .createNetworkGroup(organizationId: organizationId, networkGroup: request)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    isCreating = false
                    if case .failure(let error) = completion {
                        errorMessage = error.localizedDescription
                        showingError = true
                    }
                },
                receiveValue: { _ in
                    onNetworkGroupCreated?()
                    dismiss()
                }
            )
            .store(in: &cancellables)
    }
}
