# Privacy Policy

**Effective date:** 2026-05-01
**App:** My Clever Client (`com.fredalix.cciosclient`)
**Developer:** Frédéric Alix
**Contact:** frederic.alix@fredalix.com

This privacy policy explains how the **My Clever Client** mobile application ("the App") handles your information. The App is an unofficial iOS client for the [Clever Cloud](https://www.clever-cloud.com) Platform-as-a-Service. It lets you manage your Clever Cloud applications, add-ons, organizations, environment variables, deployments, logs, and metrics from your iPhone, iPad, or Mac.

## TL;DR

- **The App does not track you.** No advertising, no analytics, no third-party trackers, no telemetry.
- **The App stores your Clever Cloud OAuth tokens locally** in the iOS Keychain on your device. They never leave your device except to talk to Clever Cloud's official API.
- **The data you see in the App** (your apps, add-ons, logs, metrics) belongs to your Clever Cloud account and is governed by [Clever Cloud's own privacy policy](https://www.clever-cloud.com/privacy/).

## 1. Data we process

### 1.1 Stored on your device only

The App stores the following on your device, in the iOS Keychain (encrypted) or in `UserDefaults`:

| Data | Storage | Purpose |
|---|---|---|
| Clever Cloud OAuth 1.0a token + secret | Keychain | Authenticate API calls to `api.clever-cloud.com` |
| Favorite organizations | UserDefaults | Remember your UI preferences |

This data never leaves your device, except as described below.

### 1.2 Sent to Clever Cloud

When you use the App, it makes authenticated requests to Clever Cloud's official API (`api.clever-cloud.com`, `c2-warp10-clevercloud-customers.services.clever-cloud.com`) to read and modify your account. Those requests are governed by **Clever Cloud's own privacy policy and terms of service**. We are not the data controller for your Clever Cloud account data.

### 1.3 No tracking, no analytics, no ads

The App does **not** use any third-party analytics SDK, advertising SDK, or tracking technology. There is no Google Analytics, no Firebase, no Facebook SDK, no AppsFlyer, no Adjust, no Sentry, no diagnostic log uploader. The App's only network activity is talking to Clever Cloud's official API.

The App's privacy manifest (`PrivacyInfo.xcprivacy`) declares `NSPrivacyTracking = false` and an empty `NSPrivacyTrackingDomains` list, consistent with this policy.

## 2. Permissions we ask for

The App asks for **no special iOS permissions**. It does not access your camera, microphone, contacts, photos, location, calendar, reminders, motion sensors, Bluetooth, or local network.

The only sensitive surface is the iOS Keychain, used to store your Clever Cloud OAuth tokens.

## 3. Children

The App is not directed to children under 13. We do not knowingly collect any data from children.

## 4. Your rights (GDPR / CCPA / similar)

You can:

- **Access / export your data** — All data is on your device. Sign out of the App to delete the OAuth tokens and the favorite organizations from your device.
- **For data inside your Clever Cloud account**, contact Clever Cloud directly per their privacy policy.
- **Any other request** — Email `frederic.alix@fredalix.com`. We respond within 30 days.

## 5. Security

OAuth tokens are stored in the iOS Keychain, which uses hardware-backed encryption on supported devices. All network traffic uses HTTPS (TLS 1.2+). OAuth requests to Clever Cloud are signed with HMAC-SHA512 (Apple CryptoKit).

## 6. Third parties

The App talks only to:

- **Clever Cloud** (`api.clever-cloud.com`, `c2-warp10-*.services.clever-cloud.com`) — to do its job. See their [privacy policy](https://www.clever-cloud.com/privacy/).

No other third parties. No analytics, no ads, no diagnostic log uploader.

## 7. Changes to this policy

If this policy changes materially, we will publish a new version with an updated effective date. Continued use of the App after that date constitutes acceptance of the new policy.

## 8. Contact

Questions, deletion requests, or anything else: **frederic.alix@fredalix.com**.

---

*This App is an unofficial, third-party client. It is not affiliated with, endorsed by, or sponsored by Clever Cloud SAS.*
