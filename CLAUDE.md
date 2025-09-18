# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a native iOS application for managing Clever Cloud applications and add-ons with OAuth 1.0a authentication. The app provides a modern SwiftUI interface for managing applications, organizations, add-ons, network groups, and environment variables.

## Build and Development Commands

### Xcode Operations
```bash
# Open project in Xcode
open cleveriosclient.xcodeproj

# Build from command line
xcodebuild -project cleveriosclient.xcodeproj -scheme cleveriosclient build

# Clean build cache (use when encountering JSON decoding errors after model changes)
xcodebuild clean -project cleveriosclient.xcodeproj
rm -rf DerivedData/
```

### Testing
```bash
# Run unit tests
xcodebuild test -scheme cleveriosclient

# Run UI tests
xcodebuild test -scheme cleveriosclientUITests
```

## Architecture

### Project Structure
```
cleveriosclient/
├── CleverCloudSDK/         # Core SDK implementation
│   ├── Core/              # OAuth, HTTP client, configuration, error handling
│   ├── Models/            # Data models (all Codable for JSON serialization)
│   └── Services/          # API service implementations per domain
├── Views/                 # SwiftUI view components
├── Logger/               # Remote logging system for TestFlight debugging
└── Assets.xcassets/      # App icons, colors, branding assets
```

### Key Architectural Components

**CleverCloudSDK**: The core SDK (`cleveriosclient/CleverCloudSDK/CleverCloudSDK.swift:5`) provides:
- OAuth 1.0a authentication with official Clever Cloud credentials
- Service layer for all API operations (applications, organizations, add-ons, network groups, deployments, environment)
- ObservableObject pattern for SwiftUI integration
- Error handling with CCError types
- Combine publishers for async operations

**AppCoordinator**: Main app coordinator (`cleveriosclient/AppCoordinator.swift:9`) manages:
- Global authentication state
- OAuth token lifecycle with keychain storage
- SDK initialization and configuration
- Root view routing based on auth state
- Timer-based auth state monitoring (2-second intervals)

**Remote Logging**: TestFlight debugging system (`cleveriosclient/Logger/RemoteLogger.swift`) with:
- Centralized remote logging endpoint (https://log-ios.fredalix.com)
- Device info, session tracking, offline buffering
- Automatic flushing on app backgrounding
- Different log levels (DEBUG, INFO, WARN, ERROR) with contextual metadata

### OAuth Configuration
- **Consumer Key**: `T5nFjKeHH4AIlEveuGhB5S3xg8T19e` (from clever-tools)
- **Consumer Secret**: `MgVMqTr6fWlf2M0tkC2MXOnhfqBWDT` (configured in AppCoordinator.swift:63)
- Authentication flow handled by CCOAuthService
- Tokens stored securely in iOS Keychain via CCKeychainManager

### Event System
Hybrid approach for real-time updates:
- **Primary**: WebSocket events (99% complete, minor "Error 2001" issue after handshake)
- **Fallback**: Intelligent polling every 15 seconds when WebSocket unavailable
- Handled by CCEventsService

### Data Models
All models in `CleverCloudSDK/Models/` are Codable and follow the CC prefix convention:
- CCApplication, CCOrganization, CCAddon, CCNetworkGroup, CCDeployment
- CCEnvironment for variables and domains
- CCError for standardized error handling
- Request/response models for API operations

### SwiftUI Integration
- Uses @Observable pattern for iOS 17+
- Environment object injection for SDK access
- Published properties for reactive UI updates
- Modern SwiftUI architecture with coordinators

## Development Guidelines

### Code Style
- Swift 6.0 with strict concurrency
- SwiftUI declarative UI patterns
- Combine for async operations
- ObservableObject/Observable for state management
- CC prefix for SDK types, no prefix for app views

### Authentication Testing
Debug mode enables extensive logging. Access token verification through `CleverCloudSDK.testAuthentication()` method.

### Network Layer
All API calls use CCHTTPClient with:
- OAuth 1.0a signature generation
- Automatic retry logic
- Request/response logging in debug mode
- JSON serialization/deserialization with error handling

### Build Cache Issues
If encountering JSON decoding errors after model modifications, clean build cache before rebuilding.

### TestFlight Debugging
Remote logging automatically configured on app launch. Logs include device info, user actions, and performance metrics for debugging production issues.