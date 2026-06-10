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
    /// An application's computed status changed; `object` carries the application id.
    static let applicationStateChanged = Notification.Name("ApplicationStateChanged")
    /// An application was destroyed; `object` carries the application id.
    static let applicationDestroyed = Notification.Name("ApplicationDestroyed")
    /// An add-on was destroyed; `object` carries the add-on id.
    static let addonDestroyed = Notification.Name("AddonDestroyed")
    /// A network group was destroyed; `object` carries the network group id.
    static let networkGroupDestroyed = Notification.Name("NetworkGroupDestroyed")
}

/// Vue racine de l'application
struct AppRootView: View {
    @State private var coordinator = AppCoordinator()
    @State private var appState: AppState?
    @Environment(\.scenePhase) private var scenePhase
    /// Set on the first `.active` so the launch-time `.inactive → .active` transition doesn't stack
    /// a redundant refresh on top of ContentView.onAppear — while every later return to `.active`
    /// (including from `.inactive`: Control Center, system dialogs, app-switcher peek) re-arms polling.
    @State private var hasBecomeActiveOnce = false

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
                // Re-arm on EVERY return to .active after launch. stopPolling() fires on .inactive
                // too (Control Center, system dialogs, app-switcher peek, incoming call), and those
                // round-trips never pass through .background — gating the restart on
                // `oldPhase == .background` left polling and the events WebSocket dead for the rest
                // of the session. The one-shot flag (not oldPhase) filters the launch transition.
                defer { hasBecomeActiveOnce = true }
                if hasBecomeActiveOnce && coordinator.isAuthenticated {
                    debugLog("ℹ️ 🔄 Scene → active (from \(String(describing: oldPhase))) — requesting foreground refresh")
                    NotificationCenter.default.post(name: .appRefreshRequested, object: nil)
                }
            @unknown default:
                break
            }
        }
    }
}
