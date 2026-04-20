//
//  test0App.swift
//  test0
//
//  Created by Frédéric Alix on 17/06/2025.
//

import SwiftUI
import SwiftData

@main
struct test0App: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    init() {
        // Configure RemoteLogger for TestFlight debugging
        RemoteLogger.shared.configure()
        RemoteLogger.shared.startNewSession()
        RemoteLogger.shared.info("Application initialized", metadata: [
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown",
            "build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        ])
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                    // Flush logs when app goes to background
                    RemoteLogger.shared.flush()
                }
        }
        .modelContainer(sharedModelContainer)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .toolbar) {
                Button("Refresh") {
                    NotificationCenter.default.post(name: .appRefreshRequested, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            SidebarCommands()
        }
    }
}

extension Notification.Name {
    static let appRefreshRequested = Notification.Name("appRefreshRequested")
}

/// Vue racine de l'application
struct AppRootView: View {
    @State private var coordinator = AppCoordinator()
    @State private var appState: AppState?

    var body: some View {
        Group {
            if let appState = appState {
                coordinator.rootView()
                    .environment(coordinator)
                    .environment(appState)
            } else {
                coordinator.rootView()
                    .environment(coordinator)
            }
        }
        .onAppear {
            if appState == nil {
                appState = AppState(cleverCloudSDK: coordinator.cleverCloudSDK)
            }
        }
    }
}
