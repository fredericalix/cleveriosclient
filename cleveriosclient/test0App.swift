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
        debugLog("ℹ️ Application initialized [version=\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"), build=\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown")]")
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
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
    @Environment(\.scenePhase) private var scenePhase

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
        .onChange(of: coordinator.isAuthenticated) { _, isAuth in
            // On logout, stop polling immediately rather than waiting for ContentView.onDisappear
            // — the view-tree teardown can be slightly deferred and we don't want a stray tick to
            // fire against a torn-down SDK.
            if !isAuth {
                debugLog("ℹ️ 🛑 Auth dropped → stopping polling")
                appState?.stopPolling()
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            guard let appState else { return }
            switch newPhase {
            case .background, .inactive:
                if oldPhase == .active {
                    debugLog("ℹ️ 🛑 Scene → \(newPhase) — stopping polling")
                    appState.stopPolling()
                }
            case .active:
                if oldPhase != .active && coordinator.isAuthenticated {
                    debugLog("ℹ️ 🔄 Scene → active — requesting foreground refresh")
                    // Ask ContentView to re-arm polling + immediate refresh. ContentView owns the
                    // org-aware refresh path, so route through the existing notification channel.
                    NotificationCenter.default.post(name: .appRefreshRequested, object: nil)
                }
            @unknown default:
                break
            }
        }
    }
}
