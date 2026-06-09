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
    /// Refresh a single application's data; `object` carries the application id.
    static let refreshApplicationData = Notification.Name("RefreshApplicationData")
    /// Refresh the whole application list (e.g. after a deletion).
    static let refreshApplicationList = Notification.Name("RefreshApplicationList")
    /// An application's computed status changed; `object` carries the application id.
    static let applicationStateChanged = Notification.Name("ApplicationStateChanged")
    /// An application was destroyed; `object` carries the application id.
    static let applicationDestroyed = Notification.Name("ApplicationDestroyed")
    /// An add-on was destroyed; `object` carries the add-on id.
    static let addonDestroyed = Notification.Name("AddonDestroyed")
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
                // Only refresh when truly coming back from background. SwiftUI emits an
                // `.inactive → .active` transition at launch which would otherwise stack a
                // redundant refresh on top of ContentView's onAppear loadData().
                if oldPhase == .background && coordinator.isAuthenticated {
                    debugLog("ℹ️ 🔄 Scene → active (from background) — requesting foreground refresh")
                    NotificationCenter.default.post(name: .appRefreshRequested, object: nil)
                }
            @unknown default:
                break
            }
        }
    }
}
