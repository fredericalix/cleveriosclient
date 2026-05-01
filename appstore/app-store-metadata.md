# App Store Metadata — Clever iOS Client

Copy/paste this directly into App Store Connect. Character limits in headings are Apple's hard limits — App Store Connect will reject longer strings.

> **Disclaimer reminder:** the App is an unofficial third-party client. The metadata below avoids using "Clever Cloud" as if endorsed; we keep it factual ("for Clever Cloud") to comply with Apple Guideline 4.1 and trademark courtesy.

---

## App name (max 30 chars)

```
Clever iOS Client
```
*(17 chars — already configured in Xcode)*

## Subtitle (max 30 chars)

Pick one — recommend the first:

```
Clever Cloud on the go
```
*(22 chars)*

Alternates:
```
Manage your Clever Cloud apps
```
*(29 chars)*

```
PaaS dashboard for your pocket
```
*(30 chars)*

## Promotional Text (max 170 chars — editable without review)

```
Manage your Clever Cloud applications, add-ons, deployments, logs, and metrics from anywhere. Live tail your logs and watch deployments in real time.
```
*(154 chars)*

## Description (max 4000 chars)

```
Clever iOS Client is an unofficial mobile dashboard for Clever Cloud, the European Platform-as-a-Service. Bring your apps with you — check status, restart, redeploy, scale, and tail logs from your iPhone, iPad, or Mac.

WHAT YOU CAN DO

• Switch between your personal space and any organization you belong to
• See every application and add-on in one place, with live status
• Tail application logs and add-on logs in real time
• Browse deployment history and trigger restart or redeploy
• Edit environment variables and application configuration
• View live metrics — CPU, memory, instance count — powered by Warp10
• Manage custom domains (vhosts) and TLS
• Inspect Network Groups, peers, and grab WireGuard configs
• Scale instances and flavors on the fly

DESIGNED FOR APPLE PLATFORMS

• Native SwiftUI on iOS 18+ — fast, fluid, accessible
• iPad: three-column layout with sidebar, list, and detail
• Mac: runs as a "Designed for iPad" app on Apple Silicon
• OAuth 1.0a with HMAC-SHA512 — your tokens stay in the iOS Keychain on your device

PRIVACY FIRST

No tracking. No analytics. No ads. The app only talks to Clever Cloud's official API and a small developer-operated diagnostic log endpoint (anonymous, opt-out by uninstall). Read the full privacy policy at the link below.

OPEN SOURCE

The project is open source. File issues, request features, and read the code on GitHub.

WHO IT'S FOR

Developers and DevOps engineers who already host on Clever Cloud and want a fast, focused mobile companion to the official console — for on-call duty, quick restarts, deployment monitoring, or just keeping an eye on production while away from a laptop.

NOT AFFILIATED WITH CLEVER CLOUD

This is an unofficial, third-party app. It is not affiliated with, endorsed by, or sponsored by Clever Cloud SAS. "Clever Cloud" is a trademark of Clever Cloud SAS.

REQUIREMENTS

• A Clever Cloud account (free signup at clever-cloud.com)
• iOS 18.0 or later
• Internet connection

QUESTIONS? Email frederic.alix@fredalix.com or open an issue on GitHub.
```
*(~2150 chars — well under 4000)*

## Keywords (max 100 chars total, comma-separated, no spaces)

```
clevercloud,paas,devops,deploy,logs,metrics,addon,cloud,hosting,sre,sysadmin,server,kubernetes
```
*(94 chars)*

> **Tip:** don't include words already in the app name/subtitle ("clever", "cloud" are fine here because the title is "Clever iOS Client"). Avoid plurals if singular is searched more.

## What's New in this Version (max 4000 chars — for v1.0)

```
First public release.

• Manage applications: status, restart, redeploy, scale, environment variables, domains
• Manage add-ons: details, configuration, embedded log viewer
• Live tail logs (apps and add-ons) with rolling buffer
• Live metrics powered by Warp10 — CPU, memory, instances
• Network Groups: peers, members, WireGuard configs
• Three-column layout on iPad, navigation stack on iPhone
• Runs on Apple Silicon Macs as "Designed for iPad"
• OAuth 1.0a, HMAC-SHA512, tokens stored in the iOS Keychain
• No tracking, no analytics, no ads
```

## Marketing URL (optional)

If you publish a landing page (e.g., `https://github.com/fredericalix/cleveriosclient`), put it here. Otherwise leave blank.

## Support URL (required)

```
https://www.fredalix.com/en/cleveriosclient/support
```
*(Astro page at `fredalix.com/src/pages/en/cleveriosclient/support.astro` — deploy via `docker compose build && docker compose up -d`)*

## Privacy Policy URL (required)

```
https://www.fredalix.com/en/cleveriosclient/privacy
```
*(Astro page at `fredalix.com/src/pages/en/cleveriosclient/privacy.astro` — deploy via `docker compose build && docker compose up -d`)*

## Copyright

```
2026 Frédéric Alix
```

## Primary category / Secondary

- **Primary:** Productivity
- **Secondary:** Developer Tools *(optional, helps discoverability among devs)*

## Age rating

4+ — no objectionable content. The questionnaire in App Store Connect should yield 4+ automatically (no violence, no profanity, no sexual content, no gambling, no unrestricted web access — the App only talks to Clever Cloud's API).

## Sign-In Information for App Review (CRITICAL)

App Store reviewers cannot sign up to Clever Cloud just to test your app — you **must** provide working credentials. Create a dedicated test account with at least:

- 1 small application (e.g., a Node.js or Python "Hello World")
- 1 add-on (e.g., a free Postgres or Redis tier)
- Some deployment history (push a couple of commits)
- Some log activity

Then in **App Store Connect → App Review Information → Sign-In required → YES**:

- **Username:** `appreview-clevercloud@<yourdomain>` *(or whatever email you used)*
- **Password:** *(strong, dedicated, not your personal password)*

In the **Notes** field:

```
Clever iOS Client is an unofficial mobile client for Clever Cloud (https://www.clever-cloud.com), a European PaaS. Sign-in uses Clever Cloud's official OAuth 1.0a flow.

To test:
1. Tap "Sign in with Clever Cloud" on the launch screen.
2. You will be redirected to Clever Cloud's web authorization page in Safari. Enter the demo credentials provided above.
3. You will be redirected back to the app and shown the dashboard with personal-space organizations, applications, and add-ons.

The demo account has a sample Node.js application and a sample Postgres add-on so you can exercise every tab (Environment, Configuration, Metrics, Deployments, Logs, Domains, Advanced).

Privacy policy: https://www.fredalix.com/en/cleveriosclient/privacy
Support: https://www.fredalix.com/en/cleveriosclient/support
```

## Screenshots required

- **iPhone 6.9"** (1320×2868 px) — iPhone 16 Pro Max
- **iPad 13"** (2064×2752 px) — iPad Pro M4 13"

Captured manually from the iOS simulator (`Cmd+S`) after a real OAuth login with the demo account. Apple infers smaller-device screenshots from these two automatically. See `appstore/submission-checklist.md` Phase 3 for the step-by-step capture flow (status-bar override + ordering).

Suggested 5 screens:

1. Login screen ("Sign in with Clever Cloud")
2. Dashboard — sidebar (orgs) + apps list + add-ons (iPad three-column shines here)
3. Application detail — Metrics tab (best visual: charts)
4. Application detail — Logs streaming (best visual: live tail)
5. Application detail — Deployments tab (clear value proposition)
