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
- `CCEventsService` - Polling-based status updates (WebSocket removed, polling every 15s)
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
- `ContentView` - Main dashboard after login (org picker, app/addon lists)
- `ApplicationDetailView` - Multi-tab app details (overview, env, config, deployments, domains, advanced)
- `AddonDetailView` - Add-on details and management
- `NetworkGroup*View` - Network group management and visualization (feature-flagged off)
- `LoginView` - OAuth login flow
- Scalability/metrics views are in `Views/` subdirectory

`CleverCloudViewModel` wraps SDK calls with Combine subscriptions and published state for the main dashboard.

### Async Pattern

All SDK calls return `AnyPublisher<T, CCError>` (Combine). Views subscribe with `.sink()`, store subscriptions in `Set<AnyCancellable>`, and dispatch to main queue with `.receive(on: DispatchQueue.main)`.

### Remote Logging

`RemoteLogger` sends logs to `https://log-ios.fredalix.com` for TestFlight debugging. Configured on app launch, flushes on background. Uses log levels: DEBUG, INFO, WARN, ERROR with metadata dictionaries.

## Development Guidelines

- **CC prefix** for all SDK types, no prefix for app-level views
- **@Observable** (iOS 17+ macro) for `AppCoordinator`; **ObservableObject** (Combine) for SDK classes
- **Combine** for all async operations (not async/await)
- Clean build cache when modifying model structs to avoid stale JSON decoding
- Network Groups feature is currently disabled via `isNetworkGroupsEnabled = false` flag in ContentView
- Domain encoding must match JavaScript's `encodeURIComponent` exactly for OAuth signature compatibility
