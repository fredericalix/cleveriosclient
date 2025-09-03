# Remote Logging System

## Overview

The Remote Logging System enables real-time debugging of TestFlight deployments by sending device logs to a centralized backend server.

## Configuration

The logger is automatically configured on app launch with these settings:

- **Endpoint**: https://log-ios.fredalix.com/
- **Token**: cf4a1462-8666-4b75-874e-4a28e7f9ef4c
- **Batch Size**: 50 logs
- **Flush Interval**: 30 seconds

## Usage

### Basic Logging

```swift
// Debug level - detailed information
RemoteLogger.shared.debug("Loading applications...")

// Info level - important events
RemoteLogger.shared.info("User logged in successfully")

// Warning level - potential issues
RemoteLogger.shared.warn("API response took 3.5 seconds")

// Error level - failures and exceptions
RemoteLogger.shared.error("Failed to load data: \(error)")
```

### Logging with Metadata

```swift
RemoteLogger.shared.error("Network request failed", metadata: [
    "url": endpoint,
    "statusCode": "500",
    "duration": "1.23",
    "retryCount": "3"
])
```

### Network Request Logging

```swift
RemoteLogger.shared.logNetworkRequest(
    method: "GET",
    url: url.absoluteString,
    statusCode: httpResponse.statusCode,
    error: error
)
```

## Automatic Features

### Device Information
Every log automatically includes:
- Device ID (unique per installation)
- Device Model (e.g., "iPhone 15 Pro")
- iOS Version
- App Version & Build Number

### Context Information
- File name and line number
- Function name
- Current user ID (if available)
- Current organization ID (if available)
- Session ID

### Offline Support
- Logs are buffered when offline
- Automatically sent when connection restored
- Persisted to disk if buffer exceeds 1000 logs

## Log Levels

| Level | Icon | Usage |
|-------|------|-------|
| ERROR | ❌ | Failures, exceptions, critical issues |
| WARN | ⚠️ | Warnings, degraded performance, rate limits |
| INFO | ✅ | Success messages, important state changes |
| DEBUG | 🔍 | Detailed debugging information |

## Backend Dashboard

Access logs at: https://log-ios.fredalix.com/

Features:
- Real-time log streaming
- Filter by device, level, time range
- Search in messages
- Export logs as JSON/CSV

## TestFlight Benefits

1. **Remote Debugging**: See exactly what happens on testers' devices
2. **Device-Specific Issues**: Track problems by iOS version and device model
3. **User Journey**: Understand the sequence of actions before crashes
4. **Performance Monitoring**: Track slow operations and timeouts

## Privacy & Security

- Authentication via UUID token
- HTTPS encryption for all communications
- No personally identifiable information logged by default
- Logs retained for 30 days

## Troubleshooting

### Logs not appearing?
1. Check internet connection
2. Verify token is correct
3. Look for RemoteLogger errors in Xcode console
4. Force flush: `RemoteLogger.shared.flush()`

### Too many logs?
Adjust console output:
```swift
let config = LoggerConfiguration(enableConsoleOutput: false)
RemoteLogger.shared.configure(with: config)
```

## Best Practices

1. **Use appropriate log levels** - Don't use error for non-errors
2. **Add context** - Include relevant metadata
3. **Avoid sensitive data** - No passwords, tokens, or PII
4. **Be descriptive** - Future you will thank present you
5. **Log user actions** - Helps reconstruct issues

## Migration from print()

Replace print statements based on content:
- `print("❌ Error...")` → `RemoteLogger.shared.error(...)`
- `print("✅ Success...")` → `RemoteLogger.shared.info(...)`
- `print("🔍 Debug...")` → `RemoteLogger.shared.debug(...)`
- `print("⚠️ Warning...")` → `RemoteLogger.shared.warn(...)` 