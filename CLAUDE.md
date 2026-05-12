# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Native iOS application for managing Clever Cloud infrastructure (applications, add-ons, organizations, network groups, environment variables, deployments, logs, metrics). Uses OAuth 1.0a authentication against the Clever Cloud API. Built with SwiftUI targeting iOS 17+, Swift 6.0.

## Build and Development Commands

```bash
# Build from command line
xcodebuild -project mycleverclient.xcodeproj -scheme cleveriosclient build

# Run unit tests
xcodebuild test -scheme cleveriosclient

# Run UI tests (UI test target is `mycleverclientUITests`)
xcodebuild test -project mycleverclient.xcodeproj -scheme cleveriosclient -only-testing:mycleverclientUITests

# Clean build cache (required when JSON decoding errors appear after model changes)
xcodebuild clean -project mycleverclient.xcodeproj && rm -rf DerivedData/

# Open in Xcode
open mycleverclient.xcodeproj
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

Two timers run alongside a push event stream:
- **Status polling fallback** (every 15s) — refreshes `applicationStatuses` via `CCApplicationService.getApplicationInstances` per app. Safety net only; the WebSocket event stream is the primary source of truth for status changes.
- **Data refresh** (every 10s) — refreshes the apps + addons lists via the `dataRefreshTick` closure.
- **Live events** — `CCEventsService` pushes `DEPLOYMENT_ACTION_BEGIN/_END` events that `AppState.handlePlatformEvent` maps directly into `applicationStatuses[appId]` (WIP→Deploying, OK→Running, FAIL→Failed, CANCELLED→Stopped).

Race-protection and debouncing:
- Per-app status fetches are tagged with the org they were issued under (captured into the sink). Responses that land after an org switch are dropped before mutating `applicationStatuses` — see `loadApplicationStatuses(for:)`.
- `cancelInFlight()` cancels all in-flight status requests and clears the dict. ContentView calls it from `autoRefreshOrganizationData` before re-launching loads on org switch.
- `markDataRefreshed()` stamps `lastDataRefreshAt` so the next auto-tick is debounced (3s window). Manual paths (pull-to-refresh, org switch, Cmd+R) call this to avoid piling on the timer-driven refresh.
- `refreshApplicationStatuses(forced:)` — timer-driven calls pass `forced: false` and respect the same 3s debounce against `lastStatusRefreshAt`.
- `.retry(1)` before `.timeout(10s)` on each status publisher absorbs transient Wi-Fi/cellular handoff failures without painting the app as "Error".

`AppState.startPolling(applicationsProvider:organizationIdProvider:dataRefreshTick:)` is idempotent (guard on `pollingTimer == nil`). ContentView passes closures that read its current `@State` arrays so AppState doesn't need to own all data state.

### scenePhase lifecycle (AppRootView)

`AppRootView` in `test0App.swift` observes `@Environment(\.scenePhase)`:
- `.background` / `.inactive` (when coming from `.active`) → `appState?.stopPolling()`. Timers and WebSocket are torn down.
- `.active` when `oldPhase == .background` → posts `appRefreshRequested`. ContentView's handler calls `startAppStatePolling()` (idempotent re-arm) then `autoRefreshOrganizationData(for:)`. The launch-time `.inactive → .active` transition is intentionally ignored so it doesn't stack a redundant load on top of `ContentView.onAppear`.

`AppRootView` also observes `coordinator.isAuthenticated` and calls `stopPolling()` on logout immediately rather than waiting for `ContentView.onDisappear`.

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
- `CCEventsService` - Real WebSocket client targeting `wss://api.clever-cloud.com/v2/events/event-socket`. Protocol reverse-engineered from `@clevercloud/client`: open WS, send `{"message_type":"oauth","authorization":"<OAuth 1.0a header signed for GET https://api.clever-cloud.com/v2/events/>"}` as the first frame; handle `socket_ready` (handshake done), heartbeat (reply pong), `type=error id=2001` (auth rejected), and `event: DEPLOYMENT_ACTION_BEGIN/_END` whose `data` field is a JSON string and must be re-parsed. Exponential reconnect backoff up to 30s. `connect()`/`disconnect()` are driven by `AppState.startPolling()` / `stopPolling()` and `scenePhase`, never by Views directly. `CCConnectionState` is Sendable (`.failed(String)`, not `.failed(Error)`) to satisfy Swift 6 strict-concurrency.
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

### Silent Background Refresh

`ContentView.testGetApplications(silent:onLoaded:)` and `testGetAddons(silent:)` take a `silent: Bool = false` flag.
- **Default (silent: false)** — used by manual paths (`autoRefreshOrganizationData`, pull-to-refresh, Cmd+R via `appRefreshRequested`). Sets `errorMessage = "Loading…"`, `isLoading = true`, and for addons clears `addons = []` for clear "I'm reloading" feedback.
- **silent: true** — used by the 10s `dataRefreshTick`. Skips all UI feedback mutations. The list is replaced **only if different** (`if addons != loadedAddons`) so SwiftUI doesn't re-render unchanged rows.
- The data-refresh tick is additionally **paused while a detail view is open** (`guard selectedDetailView == .dashboard else { return }` in `dataRefreshTick`). Status changes still arrive via the WebSocket; the underlying list refresh would only burn API calls and risk flashing the dashboard on return.

### Redeploy endpoint

`POST /v2/.../applications/{appId}/instances` — **not** `/deployments`, which is GET-only (POST returns 405). Use `CCApplicationService.restartApplication(applicationId:organizationId:)` at call sites. `CCApplicationService.deploy(...)` is kept for source-compat but routes through the same correct endpoint.

### Logging

**Console logging via `debugLog()`** (`cleveriosclient/Logger/DebugLog.swift`) — `@inlinable` wrapper around `Swift.print` gated by `#if DEBUG`. Compiles to a no-op in Release builds, so the App Store binary contains no log strings (verified via `strings`). Uses `@autoclosure () -> String` so the literal string interpolation is never materialized in Release.

**Always use `debugLog(...)`, never `print(...)` directly** — a project-wide `grep "print("` should return zero hits outside `DebugLog.swift`. The bulk migration was done in commit `477db7a`.

To re-enable logs in a Release build (e.g. for a TestFlight diagnostic), flip `kForceConsoleLogs` to `true` in `DebugLog.swift` and rebuild Release. **Remember to flip back to `false` before App Store submission.**

**Log-level convention** — `debugLog` calls prefix the message with an emoji that encodes the level: `❌` error, `⚠️` warn, `ℹ️` info, `🔍` debug. Use this convention so a future grep can filter by level. There is no remote log uploader: the App's only network activity is talking to Clever Cloud's API.

## Development Guidelines

- **CC prefix** for all SDK types, no prefix for app-level views
- **@Observable** (iOS 17+ macro) for `AppCoordinator` and `AppState`; **ObservableObject** (Combine) for SDK classes
- **Combine** for all async operations (not async/await)
- Clean build cache when modifying model structs to avoid stale JSON decoding
- **`debugLog()` over `print()`** — all console output must go through `debugLog()` (Apple App Store compliance, no log strings in Release binary)
- **Shared state in `AppState`, not in `ContentView.@State`** — anything that must survive view recreation (especially on iPad NavigationSplitView) belongs in AppState. Closures-as-providers is the pattern when AppState needs to read data still owned by a View
- **iPad navigation = `NavigationSplitView` (3 columns)** — new iPad layouts should follow this pattern, not push-stack navigation
- Domain encoding must match JavaScript's `encodeURIComponent` exactly for OAuth signature compatibility
