# App Store Submission Checklist — My Clever Client

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
- [x] Demo Clever Cloud account created (`appletesting@fredalix.com`)

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
  git commit -m "Add privacy + support pages for My Clever Client"
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

## Phase 3 — Capture App Store screenshots (manual)

Apple only requires two device classes for a universal app:

- **iPhone 6.9"** — 1320×2868 px → simulator **iPhone 16 Pro Max** (iOS 18+)
- **iPad 13"** — 2064×2752 px → simulator **iPad Pro 13-inch (M4)** (iPadOS 18+)

Apple infers all smaller sizes from these two.

### Status bar override

Before capturing, force the simulator status bar to the Apple convention (9:41, full battery, full signal):

```bash
# Boot the simulator first (Xcode → Product → Destination → choose device → Cmd+R).
# Then while it's running:
xcrun simctl status_bar booted override \
  --time "9:41" \
  --dataNetwork wifi \
  --wifiMode active \
  --wifiBars 3 \
  --cellularMode active \
  --cellularBars 4 \
  --batteryState charged \
  --batteryLevel 100
```

The override persists until you reboot the simulator or run `xcrun simctl status_bar booted clear`.

### Capture flow (per device)

1. **Product → Destination → iPhone 16 Pro Max** (then iPad Pro 13" M4 after).
2. **Cmd+R** to build and launch.
3. Apply the status bar override above.
4. **Login screen** → `Cmd+S` (Simulator → File → Save Screen). PNG drops on the Desktop.
5. Tap **Sign in with Clever Cloud** → log in with `appletesting@fredalix.com` (password from your password manager).
6. Capture each screen with `Cmd+S`:
   - **02-Dashboard**: sidebar orgs + apps list + add-ons (the iPad 3-column layout shines here).
   - **03-AppDetail-Metrics**: tap an app → Metrics tab (visual heavy).
   - **04-AppDetail-Logs**: Logs tab in stream (also visual heavy).
   - **05-AppDetail-Deployments**: Deployments tab.
7. Rename PNGs on the Desktop with the `01-`, `02-`, … prefix — App Store Connect orders screenshots alphabetically.
8. **Drop them** in `appstore/screenshots/iphone-6.9/` (and `appstore/screenshots/ipad-13/` after the iPad pass).

### Verification

```bash
# Sizes must be exactly 1320x2868 (iPhone) and 2064x2752 (iPad)
sips -g pixelWidth -g pixelHeight appstore/screenshots/iphone-6.9/*.png
sips -g pixelWidth -g pixelHeight appstore/screenshots/ipad-13/*.png
```

Visually check each PNG:
- Status bar reads `9:41`, full bars and battery.
- No real personal data (the `appletesting@fredalix.com` content is the only acceptable user-visible identifier).
- No notification banners covering content.

### Repeat on iPad Pro 13"

iPad's simulator has its own Keychain — you'll log in again. The 3-column NavigationSplitView in the Dashboard is the most distinctive iPad screenshot.

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

Go to <https://appstoreconnect.apple.com> → **My Apps** → **My Clever Client**.

### 5.1 — App Information (one-time, top of left sidebar)

- [ ] **Name**: `My Clever Client`
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
- [ ] **Screenshots**: drag-and-drop the PNGs from `appstore/screenshots/`. Order them deliberately:
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
- [ ] Watch the App Store URL go live (search for "My Clever Client" — sometimes takes 1-2 hours to appear in search).
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

# Confirm screenshot sizes (must be 1320x2868 iPhone, 2064x2752 iPad):
sips -g pixelWidth -g pixelHeight appstore/screenshots/iphone-6.9/*.png
sips -g pixelWidth -g pixelHeight appstore/screenshots/ipad-13/*.png

# Confirm URLs are live:
curl -I https://<your-host>/privacy-policy
curl -I https://<your-host>/support
```
