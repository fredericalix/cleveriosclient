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

The app requires OAuth login, which can't be scripted in an unattended UI test. The demo-mode bypass is implemented in `AppCoordinator.init()` (look for `injectDemoTokensIfRequested()`): when the launch environment contains `UI_TEST_DEMO_MODE=1` plus `UI_TEST_OAUTH_TOKEN` and `UI_TEST_OAUTH_SECRET`, the app skips the keychain lookup, injects the tokens straight into the SDK configuration, and lands authenticated.

`ScreenshotTests.swift` already sets `app.launchEnvironment["UI_TEST_DEMO_MODE"] = "1"` for every test except the login screenshot. You only need to provide the two token env vars when invoking fastlane.

### Step 1 — Obtain demo OAuth tokens (one-time)

Tokens come from a real OAuth login on the dedicated demo Clever Cloud account (`appletesting@fredalix.com`). They are NEVER hardcoded in source.

1. Boot a simulator and run the app from Xcode (`Cmd+R`).
2. Tap **Sign in with Clever Cloud**, complete the OAuth flow with the demo account credentials.
3. Once back in the app authenticated, in Xcode:
   - Pause execution (Debug → Pause).
   - In the LLDB console, run:
     ```
     po CCKeychainManager().loadCredentials()
     ```
   - Copy the `token` and `secret` strings from the printed struct.

### Step 2 — Wire the tokens into fastlane

Create `fastlane/.env` (gitignored — the `.env` rule in `.gitignore` already covers it) with:

```bash
UI_TEST_DEMO_MODE=1
UI_TEST_OAUTH_TOKEN=<paste-token-from-step-1>
UI_TEST_OAUTH_SECRET=<paste-secret-from-step-1>
```

fastlane reads `.env` automatically.

### Step 3 — Run the captures

```bash
bundle exec fastlane screenshots
```

Every test except `test01_Login` will launch fully authenticated against the demo account.

### Falling back to manual capture

If you'd rather skip the bypass for the first submission, just take screenshots manually from the simulator after a real OAuth login. fastlane setup remains untouched in the repo for future runs.

## Upload to App Store Connect

Once screenshots look good:

```bash
# Optional, requires `pilot init` once
bundle exec fastlane deliver --skip_binary_upload --skip_metadata
```

Or do it manually via the App Store Connect web UI — drag-and-drop into the screenshots section of the version page.

## CI / Re-running

Re-running `bundle exec fastlane screenshots` is idempotent thanks to `clear_previous_screenshots(true)` in `Snapfile`. Output is git-ignored (see `.gitignore` — add `fastlane/screenshots/` if not already).
