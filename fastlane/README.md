# Fastlane — App Store screenshots

This folder configures **fastlane snapshot** to generate App Store screenshots for the **Clever iOS Client** app, in the two device formats Apple requires (iPhone 6.9" and iPad 13").

## One-time setup

```bash
# 1. Install Bundler (if not already)
gem install bundler

# 2. Install fastlane via Bundler
bundle install

# 3. Drop the SnapshotHelper.swift into the UI test target.
#    fastlane provides this file — it sets `setupSnapshot` and
#    captures named PNGs from inside the test cases.
bundle exec fastlane snapshot update
```

The `snapshot update` command writes `cleveriosclientUITests/SnapshotHelper.swift`. **Make sure that file is added to the `cleveriosclientUITests` target** in Xcode (Target Membership panel on the right). With `PBXFileSystemSynchronizedRootGroup` (Xcode 15+) it should be picked up automatically because the file is inside the `cleveriosclientUITests/` synchronized folder.

## Generate screenshots

```bash
bundle exec fastlane screenshots
```

This:
1. Builds the app + UI test target with `xcodebuild build-for-testing`.
2. Boots both simulators in parallel.
3. Runs the screenshot UI tests (see `cleveriosclientUITests/ScreenshotTests.swift`).
4. Drops PNG files in `fastlane/screenshots/en-US/`:
   - `iPhone 16 Pro Max-01-Login.png`
   - `iPhone 16 Pro Max-02-Dashboard.png`
   - …
   - `iPad Pro 13-inch (M4)-01-Login.png`
   - …

## Demo data — making screenshots reproducible

The app requires OAuth login, which can't be scripted in an unattended UI test. Two options:

### Option A (recommended) — Demo mode flag

Add a launch-environment-aware bypass in the app:

1. In `AppCoordinator.init()`, check for `ProcessInfo.processInfo.environment["UI_TEST_DEMO_MODE"] == "1"`.
2. When set, skip the OAuth flow and inject hard-coded demo OAuth tokens (matching the dedicated review demo account).
3. The UI test sets `app.launchEnvironment["UI_TEST_DEMO_MODE"] = "1"` before `app.launch()`.

This way every screenshot run starts authenticated against a real (demo) Clever Cloud account.

### Option B — Manual login

Less reproducible but faster initial setup: manually log into the simulator once with the demo account, then run `fastlane screenshots`. Tokens persist in the simulator Keychain between runs as long as the app isn't reinstalled (we set `reinstall_app(false)` in `Snapfile`).

## Upload to App Store Connect

Once screenshots look good:

```bash
# Optional, requires `pilot init` once
bundle exec fastlane deliver --skip_binary_upload --skip_metadata
```

Or do it manually via the App Store Connect web UI — drag-and-drop into the screenshots section of the version page.

## CI / Re-running

Re-running `bundle exec fastlane screenshots` is idempotent thanks to `clear_previous_screenshots(true)` in `Snapfile`. Output is git-ignored (see `.gitignore` — add `fastlane/screenshots/` if not already).
