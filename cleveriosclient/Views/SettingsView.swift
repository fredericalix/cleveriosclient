import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tabs: [ApplicationTab] = ApplicationTabOrder.load()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(tabs) { tab in
                        Label(tab.title, systemImage: tab.icon)
                    }
                    .onMove(perform: move)
                } header: {
                    Text("Application tabs")
                } footer: {
                    Text("Drag to reorder how tabs appear in an application's detail screen.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.editMode, .constant(.active))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Reset") {
                        ApplicationTabOrder.reset()
                        tabs = ApplicationTabOrder.load()
                    }
                    .disabled(tabs == ApplicationTabOrder.defaultOrder)
                }
            }
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        tabs.move(fromOffsets: source, toOffset: destination)
        ApplicationTabOrder.save(tabs)
    }
}
