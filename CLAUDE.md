# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Native iOS application for managing Clever Cloud infrastructure (applications, add-ons, organizations, network groups, environment variables, deployments, logs, metrics). Uses OAuth 1.0a authentication against the Clever Cloud API. Built with SwiftUI targeting iOS 17+, Swift 6.0.

## Build and Development Commands

```bash
# Build from command line
xcodebuild -project cleveriosclient.xcodeproj -scheme cleveriosclient build

# Run unit tests
xcodebuild test -scheme cleveriosclient

# Run UI tests
xcodebuild test -scheme cleveriosclientUITests

# Clean build cache (required when JSON decoding errors appear after model changes)
xcodebuild clean -project cleveriosclient.xcodeproj && rm -rf DerivedData/

# Open in Xcode
open cleveriosclient.xcodeproj
```

## Architecture

### App Entry Point and Auth Flow

`test0App.swift` is the `@main` entry point. It creates `AppRootView`, which holds an `AppCoordinator` as `@State`. The coordinator:
- Loads OAuth tokens from Keychain on init via `CCKeychainManager`
- Routes to `LoginView` or `ContentView` based on `isAuthenticated`
- Polls authentication state every 2 seconds via a timer
- Is injected into the SwiftUI environment so all views can access it

The SDK is accessed through `coordinator.cleverCloudSDK` (lazy singleton). Consumer credentials are hardcoded in `AppCoordinator.init()` (from clever-tools).

### App State Layer

`AppState` (`cleveriosclient/AppState.swift`) is an `@Observable final class` that serves as the single source of truth for shared data (`organizations`, `applications`, `addons`, `applicationStatuses`) and owns the intelligent polling system. It lives in the SwiftUI environment (`@Environment(AppState.self)`) and survives view recreations — critical on iPad where SwiftUI rebuilds the `ContentView` struct during `NavigationSplitView` layout, which would reset any `@State` polling guard.

The polling system runs two timers:
- **Status polling** (every 15s) — refreshes `applicationStatuses` via `CCApplicationService.getApplicationInstances` per app
- **Data refresh** (every 10s) — refreshes the apps + addons lists via the `dataRefreshTick` closure

`AppState.startPolling(applicationsProvider:organizationIdProvider:dataRefreshTick:)` is idempotent (guard on `pollingTimer == nil`). ContentView passes closures that read its current `@State` arrays so AppState doesn't need to own all data state.

### SDK Layer (`CleverCloudSDK/`)

`CleverCloudSDK` is an `ObservableObject` that owns all service objects. Each service takes `CCHTTPClient` as a dependency.

**Core** (`Core/`):
- `CCHTTPClient` - All HTTP requests with OAuth 1.0a signing. Has a critical trailing-slash fix for URL normalization that affects OAuth signature matching. Supports both typed JSON decoding and raw data/string responses.
- `CCOAuthSigner` - OAuth 1.0a signature generation (HMAC-SHA512 via CryptoKit)
- `CCConfiguration` - Holds OAuth tokens (mutable via `updateTokens`/`clearTokens`), API base URLs
- `CCKeychainManager` - Keychain read/write for persisting OAuth credentials
- `CCError` - Typed error enum with `isAuthenticationError` and `isRetryable` helpers

**Services** (`Services/`): Each service maps to a Clever Cloud API domain:
- `CCApplicationService` - CRUD, instances, domains (vhosts), deployments, logs, scaling
- `CCOrganizationService` - Organizations and user profile
- `CCAddonService` - Add-on CRUD, providers, plans
- `CCDeploymentService` - Deployment history, restart, redeploy
- `CCEnvironmentService` - Environment variables, app config, domains
- `CCNetworkGroupService` - Network groups, members, peers, WireGuard configs
- `CCEventsService` - Polling-based status updates (WebSocket removed, polling every 15s). The lifecycle (`connect()`/`disconnect()`) is driven by `AppState.startPolling()` / `stopPolling()`, not by Views directly.
- `CCScalabilityService` - Instance/flavor scaling configuration
- `CCApplicationMetricsService` - Application metrics via Warp10
- `CCWarp10Client` - Direct Warp10 time-series queries (tokens cached for 5 days)
- `CCOAuthService` - OAuth 1.0a flow (request token, authorization, access token)

**Models** (`Models/`): All `Codable` structs with `CC` prefix (e.g., `CCApplication`, `CCOrganization`, `CCAddon`, `CCDeployment`, `CCNetworkGroup`, `CCEnvironment`, `CCScalability`, `CCMonitoring`, `CCLogs`).

### API Versions

Two Clever Cloud API versions are used:
- **v2** (`https://api.clever-cloud.com/v2`) - Most endpoints: apps, orgs, addons, env, deployments, logs
- **v4** (`https://api.clever-cloud.com/v4`) - Network groups, some newer endpoints

Warp10 metrics use a separate endpoint: `https://c2-warp10-clevercloud-customers.services.clever-cloud.com/api/v0`

### Organization Context Pattern

API calls differ based on whether targeting personal space or an organization:
- Personal space: `/self/applications/...`
- Organization: `/organisations/{orgId}/applications/...`
- Organization IDs start with `orga_` prefix; this is used to select the correct endpoint

### View Layer

Most views live directly in `cleveriosclient/` (not in a `Views/` subdirectory):
- `ContentView` - Main dashboard after login. Layout is **device-conditional**:
  - **iPad/Mac**: 3-column `NavigationSplitView` (orgs sidebar | apps+addons content | detail) with `columnVisibility` state
  - **iPhone**: `NavigationStack(path:)` with an `AppDestination` enum
- `ApplicationDetailView` - 7 top-level tabs in a SwiftUI `TabView`:
  `Environment | Configuration | Metrics | Deployments | Logs | Domains | Advanced`
  The Logs tab is a **trampoline** showing a "Display Logs" button that opens `ApplicationLogsView` in a `fullScreenCover`. The other 6 tabs render their content inline.
- `AddonDetailView` - Add-on details, including an embedded logs viewer using the same buffer policy as `ApplicationLogsView`
- `LoginView` - OAuth login flow
- Scalability/metrics views are in `Views/` subdirectory

**macOS support** = "Designed for iPad" on Apple Silicon (`SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = YES`, `SUPPORTS_MACCATALYST = NO`). No native macOS target. UIKit calls (e.g. `UIPasteboard`, `UIApplication.didEnterBackgroundNotification`) work as-is — no `#if os(macOS)` guards needed.

#### Logs Buffers

`ApplicationLogsView` and `AddonDetailView` share the same rolling-buffer pattern:
- `initialLogsLimit = 50` — entries fetched on the first load
- `maxLogsBufferSize = 250` — hard cap on the rolling buffer; live-tail keeps appending newest entries up to this size, then oldest drop off
- A `Timer` (2-3s interval, stored in `@Binding logsTimer`) drives the live tail while the view is visible (`onAppear` starts, `onDisappear` invalidates)

### Async Pattern

All SDK calls return `AnyPublisher<T, CCError>` (Combine). Views subscribe with `.sink()`, store subscriptions in `Set<AnyCancellable>`, and dispatch to main queue with `.receive(on: DispatchQueue.main)`.

### Logging

**Console logging via `debugLog()`** (`cleveriosclient/Logger/DebugLog.swift`) — `@inlinable` wrapper around `Swift.print` gated by `#if DEBUG`. Compiles to a no-op in Release builds, so the App Store binary contains no log strings (verified via `strings`). Uses `@autoclosure () -> String` so the literal string interpolation is never materialized in Release.

**Always use `debugLog(...)`, never `print(...)` directly** — a project-wide `grep "print("` should return zero hits outside `DebugLog.swift`. The bulk migration was done in commit `477db7a`.

To re-enable logs in a Release build (e.g. for a TestFlight diagnostic), flip `kForceConsoleLogs` to `true` in `DebugLog.swift` and rebuild Release. **Remember to flip back to `false` before App Store submission.**

**Remote logging** (`cleveriosclient/Logger/RemoteLogger.swift`) — sends logs to `https://log-ios.fredalix.com` for TestFlight debugging, distinct from console output. Configured on app launch, flushes on background. Levels: DEBUG/INFO/WARN/ERROR with metadata dictionaries. Continues to work in Release.

## Development Guidelines

- **CC prefix** for all SDK types, no prefix for app-level views
- **@Observable** (iOS 17+ macro) for `AppCoordinator` and `AppState`; **ObservableObject** (Combine) for SDK classes
- **Combine** for all async operations (not async/await)
- Clean build cache when modifying model structs to avoid stale JSON decoding
- **`debugLog()` over `print()`** — all console output must go through `debugLog()` (Apple App Store compliance, no log strings in Release binary)
- **Shared state in `AppState`, not in `ContentView.@State`** — anything that must survive view recreation (especially on iPad NavigationSplitView) belongs in AppState. Closures-as-providers is the pattern when AppState needs to read data still owned by a View
- **iPad navigation = `NavigationSplitView` (3 columns)** — new iPad layouts should follow this pattern, not push-stack navigation
- Domain encoding must match JavaScript's `encodeURIComponent` exactly for OAuth signature compatibility
