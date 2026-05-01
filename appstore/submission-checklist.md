# App Store Submission Checklist — Clever iOS Client

This is a step-by-step checklist for the **first** App Store submission. Tick each box as you go. Estimated total: **6-8 hours of real work**, spread over 1-2 days.

---

## Phase 0 — What is already done in this repo

- [x] Bundle ID `com.fredalix.cciosclient`, signing automatic (team `DS6BK4WLCX`)
- [x] AppIcon 1024×1024 with light/dark/tinted variants
- [x] OAuth callback URL scheme (`com.fredalix.cctoolkit`)
- [x] App category set to Productivity (`public.app-category.utilities`)
- [x] **`PrivacyInfo.xcprivacy`** created at `cleveriosclient/PrivacyInfo.xcprivacy`
- [x] **`ITSAppUsesNonExemptEncryption = NO`** added to Debug + Release build settings
- [x] **`kForceConsoleLogs = false`** verified in `DebugLog.swift`
- [x] Privacy policy text drafted at `appstore/privacy-policy.md`
- [x] Support page drafted at `appstore/support.md`
- [x] App Store metadata drafted at `appstore/app-store-metadata.md`
- [x] Fastlane snapshot configured (`Gemfile`, `fastlane/Snapfile`, `fastlane/Fastfile`)
- [x] Screenshot UI tests scaffolded at `cleveriosclientUITests/ScreenshotTests.swift`

---

## Phase 1 — Decisions you (the developer) need to make

- [x] **Hosting chosen:** Astro pages on `fredalix.com` (Frédéric's personal site).
  - Privacy: `https://www.fredalix.com/en/cleveriosclient/privacy`
  - Support: `https://www.fredalix.com/en/cleveriosclient/support`
  - Source: `~/fax/src/fredalix.com/src/pages/en/cleveriosclient/{privacy,support}.astro`
- [ ] **Decide marketing version.** Currently `2` build `23`. For the first App Store release you can either:
  - Keep `2` and bump build to `24` (continues your existing TestFlight numbering — simpler)
  - Reset to `1.0` build `1` (clean slate — but ASC will reject if `1.0/1` was ever uploaded)
- [ ] **Create a dedicated Clever Cloud demo account for App Review.** Provision:
  - 1 small app (Node.js/Python "Hello World") with at least 2 deployments
  - 1 free add-on (Postgres or Redis tier)
  - Enough log/metric activity to make screens look alive
- [ ] **Pick a subtitle** from the candidates in `appstore/app-store-metadata.md`.

---

## Phase 2 — Publish the privacy policy + support pages

The two `.astro` pages have already been created in `~/fax/src/fredalix.com/`. They use the existing `BaseLayout` (Header + Footer + SEOHead) and respect the site's design tokens. To deploy:

- [x] Pages created locally and `npm run build` passes (verified).
- [ ] Commit and push to the `fredalix.com` repo:
  ```bash
  cd ~/fax/src/fredalix.com
  git add src/pages/en/cleveriosclient/
  git commit -m "Add privacy + support pages for Clever iOS Client"
  git push
  ```
- [ ] Deploy on the production server (Docker + Traefik):
  ```bash
  # On the production host where docker-compose runs:
  docker compose build --no-cache
  docker compose up -d
  ```
- [ ] Confirm both URLs return **HTTPS 200**:
  ```bash
  curl -I https://www.fredalix.com/en/cleveriosclient/privacy
  curl -I https://www.fredalix.com/en/cleveriosclient/support
  ```
- [ ] (Optional but recommended) **Fix the canonical URL bug:** `astro.config.mjs` declares `site: 'https://fredalix.com'` but Traefik only serves `www.fredalix.com`. Update to `https://www.fredalix.com` so canonicals/og:url/sitemap point to URLs that actually resolve. This is a site-wide SEO improvement, not just for these new pages.

---

## Phase 3 — Generate App Store screenshots

- [ ] Install bundler + fastlane:
  ```bash
  gem install bundler
  bundle install
  bundle exec fastlane snapshot update    # writes SnapshotHelper.swift
  ```
- [ ] **Add demo-mode bypass to the app** (see `fastlane/README.md`, Option A):
  - In `AppCoordinator.init()`, check `ProcessInfo.processInfo.environment["UI_TEST_DEMO_MODE"] == "1"`.
  - If yes, inject the demo OAuth tokens (use the same demo account as App Review).
  - This way `ScreenshotTests.swift` can run unattended.
- [ ] Run the capture:
  ```bash
  bundle exec fastlane screenshots
  ```
- [ ] Verify outputs in `fastlane/screenshots/en-US/`:
  - At least 4 PNGs at **1320×2868** (iPhone 16 Pro Max)
  - At least 4 PNGs at **2064×2752** (iPad Pro 13" M4)
- [ ] (Optional) Tweak scenarios in `cleveriosclientUITests/ScreenshotTests.swift` if any screen comes out empty.

---

## Phase 4 — Build & upload the IPA

- [ ] Pull the latest, clean build:
  ```bash
  xcodebuild clean -project cleveriosclient.xcodeproj
  rm -rf DerivedData/
  ```
- [ ] (If you decided to bump version in Phase 1) Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in Xcode → Project → cleveriosclient target → Build Settings.
- [ ] In Xcode: **Product → Destination → Any iOS Device (arm64)**.
- [ ] **Product → Archive**. Wait for the archive to appear in **Organizer**.
- [ ] In Organizer: select the archive → **Distribute App** → **App Store Connect** → **Upload**.
  - Code signing: Automatic.
  - Upload symbols: **YES** (for crash reports).
  - Manage version & build number: **NO** (we control it explicitly).
- [ ] Wait for ASC to finish processing the build (5-30 min). You'll get an email when it's ready, OR:
  ```bash
  # Check status via the API (requires App Store Connect API key)
  # Or just refresh ASC → Builds → Activity
  ```

---

## Phase 5 — Fill in App Store Connect

Go to <https://appstoreconnect.apple.com> → **My Apps** → **Clever iOS Client**.

### 5.1 — App Information (one-time, top of left sidebar)

- [ ] **Name**: `Clever iOS Client`
- [ ] **Subtitle**: from your choice in Phase 1
- [ ] **Privacy Policy URL**: from Phase 2
- [ ] **Category**: Primary = **Productivity**, Secondary (optional) = **Developer Tools**
- [ ] **Content Rights**: confirm you own / licensed all content → **Yes**

### 5.2 — Pricing and Availability

- [ ] **Price**: Free (Tier 0)
- [ ] **Availability**: All countries (default)
- [ ] **Distribution Methods**: Public on the App Store

### 5.3 — Version page (e.g., "iOS App 1.0" or whichever version)

Section by section, paste from `appstore/app-store-metadata.md`:

- [ ] **Promotional Text** (paste from metadata file)
- [ ] **Description** (paste from metadata file)
- [ ] **Keywords** (paste from metadata file — comma-separated, no spaces)
- [ ] **Support URL** (from Phase 2)
- [ ] **Marketing URL** (optional)
- [ ] **Screenshots**: drag-and-drop the PNGs from `fastlane/screenshots/en-US/`. Order them deliberately:
  1. Dashboard (most informative first)
  2. Application detail — Metrics
  3. Application detail — Logs
  4. Application detail — Deployments
  5. Login
- [ ] **App Preview**: skip (optional, video preview)
- [ ] **Copyright**: `2026 Frédéric Alix`
- [ ] **Trade Representative Contact Information**: only if Korea-distributed (skip)
- [ ] **Build**: scroll to the **Build** section → click **Add Build** → select the build uploaded in Phase 4.

### 5.4 — App Privacy (left sidebar — separate from version page)

- [ ] Click **Get Started** if first time, or **Edit**.
- [ ] Question: *Does your app collect data?* → **Yes** (because of diagnostic logs).
- [ ] Add data type: **Diagnostics → Crash Data** (and/or **Performance Data** + **Other Diagnostic Data**).
  - Linked to the user? **No**
  - Used for tracking? **No**
  - Purpose: **App Functionality**
- [ ] Save and confirm. Make sure no other category is checked.

### 5.5 — Age Rating

- [ ] Click **Edit** next to Age Rating.
- [ ] Answer **None / No** to every question (no violence, no profanity, no medical info, no gambling, no unrestricted web access — the app only talks to Clever Cloud's API).
- [ ] Result should be **4+**.

### 5.6 — App Review Information

- [ ] **First Name / Last Name / Phone / Email**: your contact details.
- [ ] **Sign-in required**: **YES**
  - **Username**: demo Clever Cloud account email
  - **Password**: demo Clever Cloud account password
- [ ] **Notes**: paste the block from `appstore/app-store-metadata.md` § "Sign-In Information for App Review".
- [ ] **Attachment**: optional — skip unless reviewer asks.

### 5.7 — Version Release

- [ ] **Manually release this version** (recommended — gives you control after approval).
- [ ] (Alternative: Automatically release immediately after approval.)

### 5.8 — Submit

- [ ] At the top of the version page, click **Add for Review**.
- [ ] Answer the export compliance question:
  - *Does your app use encryption?* → **Yes**
  - *Is your app exempt under Category 5 Part 2?* → **Yes** (only standard crypto: TLS, HMAC-SHA512 via CryptoKit). Confirm.
- [ ] Confirm IDFA: **Does your app use the Advertising Identifier (IDFA)?** → **No** (we don't use AdSupport.framework).
- [ ] Click **Submit for Review**.

---

## Phase 6 — During review

Apple's first-app review typically takes **24-48 hours**. You may get:

- **In Review** → fast path, almost always approved.
- **Metadata Rejected** → ASC textual fix, no rebuild needed. Re-submit in <1 hour.
- **Binary Rejected** → fix code, re-archive, re-upload, re-submit.

Common rejection causes for this kind of app:
- Demo account broken or empty → reviewer can't see anything → **Guideline 2.1**.
- Missing privacy policy URL or 404 → **Guideline 5.1.1**.
- Mention of "Clever Cloud" without disclaimer → **Guideline 4.1** / trademark.
- Crash on launch on the latest iPad (always test the latest hardware in TestFlight before submitting).

If rejected, the **Resolution Center** in ASC is where you'll get the message and can reply.

---

## Phase 7 — Post-approval

- [ ] If you chose **Manually release**, go to ASC → version page → **Release This Version**.
- [ ] Watch the App Store URL go live (search for "Clever iOS Client" — sometimes takes 1-2 hours to appear in search).
- [ ] Verify the listing on a phone: title, screenshots, description, age, category.
- [ ] Verify in-app: launch from a device that does NOT have the TestFlight build, sign in with a real account, exercise each tab.
- [ ] Tag the release in git:
  ```bash
  git tag v2.0-appstore   # or whatever you chose
  git push origin v2.0-appstore
  ```
- [ ] Update `README.md` with an App Store badge linking to the listing.

---

## Quick verification commands

```bash
# Build and check there are no warnings:
xcodebuild -scheme cleveriosclient -configuration Release build

# Confirm zero log strings in the Release binary (App Store compliance):
strings build/Release-iphoneos/cleveriosclient.app/cleveriosclient | grep -iE "fetching|loaded|debugLog" || echo "OK — no log strings"

# Confirm PrivacyInfo is shipped:
unzip -l <path-to-ipa>/cleveriosclient.ipa | grep PrivacyInfo

# Test screenshot generation:
bundle exec fastlane screenshots

# Confirm URLs are live:
curl -I https://<your-host>/privacy-policy
curl -I https://<your-host>/support
```
