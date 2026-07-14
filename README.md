# My Clever Client 📱

A native iOS application for managing your Clever Cloud infrastructure — applications, add-ons, environment variables, deployments, logs, metrics, and Network Groups with a built-in WireGuard VPN.

![Swift Version](https://img.shields.io/badge/Swift-6.0-orange.svg)
![iOS Version](https://img.shields.io/badge/iOS-17.0%2B-blue.svg)
![License](https://img.shields.io/badge/License-MIT-green.svg)

## 🚀 Features

### Core
- ✅ **OAuth 1.0a authentication** — secure login against the Clever Cloud API, credentials stored in the Keychain
- ✅ **Personal space & organizations** — seamless context switching, with auto-refresh on switch
- ✅ **Applications** — list, real-time status, restart/redeploy, scaling, domains (vhosts)
- ✅ **Add-ons** — browse providers/plans, create, manage, embedded logs viewer
- ✅ **Environment variables** — secure per-application configuration management
- ✅ **Deployments** — history and actions
- ✅ **Logs** — live-tail viewer with a rolling buffer
- ✅ **Metrics** — application metrics via Warp10 time-series queries
- ✅ **Real-time events** — WebSocket event stream (`DEPLOYMENT_ACTION_BEGIN/_END`) with an intelligent 15s polling fallback

### Network Groups & in-app VPN 🔒
- ✅ **Full Network Groups management** — create/delete groups (personal space or organization), link applications and add-ons as members, inspect members (DNS names) and peers (NG-internal IPs)
- ✅ **Attach this device** — one tap creates a WireGuard peer for the iPhone, installs the VPN profile (iOS asks for consent) and connects; a per-group **VPN on/off toggle** then lives in the group's Overview tab
- ✅ **Add external peer** — generate a configuration for another device (laptop, server…): local Curve25519 keygen, `.conf` text + QR code, expiring-clipboard copy; the private key never leaves the device
- ✅ **In-app WireGuard tunnel** — a `PacketTunnelExtension` (NetworkExtension) drives the tunnel; deleting the device's peer (or the whole group) also removes the VPN profile from iOS Settings
- ✅ **Resilient API layer** — Network Group writes ride over transient v4 backend 5xx errors with idempotent, client-generated ids and safe retries

## 🛠 Installation

### Requirements
- iOS 17.0+ (also runs on Apple Silicon Macs as "Designed for iPad")
- Xcode 16+
- Swift 6.0

### Build

```bash
# Open in Xcode
open mycleverclient.xcodeproj

# Or build from the command line
xcodebuild -project mycleverclient.xcodeproj -scheme cleveriosclient build
```

Select your device/simulator and press `Cmd + R`. The in-app VPN requires a physical device (NetworkExtension does not run in the simulator) and the Network Extension + App Groups capabilities on both the app and `PacketTunnelExtension` targets.

### TestFlight
The app is distributed for beta testing via TestFlight.

## 🏗 Architecture

```
cleveriosclient/
├── CleverCloudSDK/          # Self-contained SDK (Combine-based)
│   ├── Core/                # OAuth 1.0a signing, HTTP client, Keychain, configuration
│   ├── Models/              # Codable models (CC prefix)
│   └── Services/            # One service per API domain (apps, add-ons, NG, events, Warp10…)
├── Views/                   # Scalability/metrics/WireGuard views
├── *.swift                  # Top-level SwiftUI views (ContentView, detail views…)
├── Logger/                  # debugLog() — console logging compiled out of Release builds
PacketTunnelExtension/       # NetworkExtension target running the WireGuard tunnel
Vendor/wireguard-apple/      # Vendored WireGuardKit + prebuilt libwg-go
```

- **UI**: SwiftUI, iOS 17 `@Observable` for app state; iPad/Mac get a 3-column `NavigationSplitView`, iPhone a `NavigationStack`
- **Networking**: Combine publishers everywhere; OAuth 1.0a (HMAC-SHA512) request signing
- **Real-time**: `CCEventsService` WebSocket (protocol mirrored from `@clevercloud/client`) + polling safety net
- **APIs**: Clever Cloud v2 (apps, orgs, add-ons…), v4 (network groups), Warp10 (metrics)

See `CLAUDE.md` for the detailed architecture notes and the hard-earned v4 Network Groups API gotchas (202-async writes, retry strategies, id conventions).

## 🧪 Development

```bash
# Unit tests
xcodebuild test -scheme cleveriosclient

# UI tests
xcodebuild test -project mycleverclient.xcodeproj -scheme cleveriosclient -only-testing:mycleverclientUITests

# Clean build cache (needed after model changes if JSON decoding misbehaves)
xcodebuild clean -project mycleverclient.xcodeproj && rm -rf DerivedData/
```

### Debug logging
All console output goes through `debugLog()` (`cleveriosclient/Logger/DebugLog.swift`): active in Debug builds, compiled to a no-op in Release so the App Store binary contains no log strings. To diagnose a Release/TestFlight build, flip `kForceConsoleLogs` to `true` and rebuild — and flip it back before submitting.

## 🤝 Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Make your changes (with tests where it makes sense)
4. Submit a pull request

### Code style
- Follow the Swift API Design Guidelines
- `CC` prefix for SDK types, no prefix for app-level views
- `debugLog()` instead of `print()` — always
- Combine for async SDK work; `@Observable` for app state

## 📄 License

This project is licensed under the MIT License — see the LICENSE file for details.

## 🙏 Acknowledgments

- The Clever Cloud team for the platform (and for investigating the bugs we reported 😄)
- [clever-tools](https://github.com/CleverCloud/clever-tools) — the reference implementation for OAuth and the Network Groups flows
- [wireguard-apple](https://github.com/WireGuard/wireguard-apple) for WireGuardKit

## 📞 Support

- **Issues**: report bugs via GitHub Issues

---

**Made with ❤️ for the Clever Cloud community**
