# Cloudflare Tunnel Manager

A native macOS (SwiftUI) control panel for [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) — an **ngrok-like UI** for exposing local services to the internet, backed by Cloudflare's infrastructure instead of a paid tunneling SaaS.

Create, start, stop, and monitor tunnels from a window or the menu bar. It manages the `cloudflared` binary as a supervised subprocess, captures its logs live, and (for custom domains) drives the Cloudflare REST API to create the tunnel and DNS route for you.

### ⬇︎ Download

**[Download the latest macOS build](https://github.com/lisenhuang/CloudflareTunnelManager/releases/latest/download/CloudflareTunnelManager.dmg)** — this link always points to the newest release. Open the `.dmg` and drag the app into **Applications**.

---

## The one thing to understand first: Quick vs Named tunnels

Cloudflare Tunnel has **two modes**, and they serve different needs. This app supports both and the distinction shapes the whole UX:

| | **Quick Tunnel** ⚡️ | **Named Tunnel** 🌐 |
|---|---|---|
| URL | random `https://<name>.trycloudflare.com` | your own `app.dev.example.com` |
| Cloudflare account | **not required** | required |
| Domain on Cloudflare | not required | **required** (must be a zone you control) |
| Auth | none | scoped **API token** |
| DNS setup | none | automatic (CNAME via API) |
| Lifetime | ephemeral (dies with the process) | persistent / reusable |
| Best for | quick demos, webhooks, sharing `localhost` | stable dev/staging URLs |

**The true "ngrok replacement" experience is the Quick Tunnel** — zero config, no login, instant URL. Named tunnels are for when you want a stable custom hostname.

> A note on "OAuth login": Cloudflare does **not** offer an end-user OAuth2 flow for REST API access. The app authenticates named-tunnel operations with a **scoped API token** you paste once (stored in the macOS Keychain). The browser-based `cloudflared login` flow is a *different* thing (it issues a zone cert); this app deliberately avoids it by creating remotely-managed tunnels and running them with `--token`.

---

## Features

- **Dashboard** — list of all tunnels with live status (running / stopped / error), local target, and public URL.
- **One-click create** — Quick (instant) or Named (custom hostname); the app creates the tunnel, pushes the ingress config, and adds the DNS route automatically.
- **Process control** — start / stop / restart, with optional **auto-restart + exponential backoff** on crash.
- **Live logs** — per-tunnel, auto-scrolling, color-coded, copyable.
- **Menu-bar control** — quick start/stop and copy-URL without opening the main window.
- **cloudflared management** — detects the binary, offers a Homebrew install if missing, and lets you override the path.
- **Secure by design** — API tokens and per-tunnel connector tokens live in the **Keychain**; only non-secret config is written to disk.

---

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15+ / Swift 6 toolchain (to build)
- [`cloudflared`](https://github.com/cloudflare/cloudflared) — the app can install it via Homebrew (`brew install cloudflared`) or you can install it yourself
- A Cloudflare account + a domain on Cloudflare **only if** you want Named tunnels

---

## Build & run

### Quick dev run (SwiftPM)

```bash
swift run
```

### Build a proper `.app` bundle

```bash
./scripts/make-app.sh        # produces CloudflareTunnelManager.app
open CloudflareTunnelManager.app
```

### Open in Xcode

```bash
open Package.swift
```

---

## Continuous delivery (GitHub Actions)

Two workflows live in [`.github/workflows/`](.github/workflows):

| Workflow | Trigger | What it does |
|---|---|---|
| **CI** (`ci.yml`) | push / PR to `main` | builds release + verifies the `.app` assembles |
| **Release** (`release.yml`) | push a `v*` tag (or run manually) | builds a **universal** (Intel + Apple Silicon) app, packages a **drag-to-Applications `.dmg`** (+ a `.zip`), and publishes them to a **GitHub Release** |

> This repo has **no GitHub remote yet**. First push it to GitHub, then the workflows become active:
> ```bash
> gh repo create CloudflareTunnelManager --public --source=. --push   # or add a remote manually
> ```

### Cut a release

```bash
git tag v0.1.0
git push origin v0.1.0          # → Release workflow builds & publishes
```

Or run it from the **Actions → Release → Run workflow** button (it asks for a version and creates the tag). The result is a GitHub Release whose `.dmg` users **open and drag onto Applications**.

Each release publishes both versioned assets (`CloudflareTunnelManager-<ver>.dmg/.zip`) and **version-less copies** (`CloudflareTunnelManager.dmg/.zip`), so this URL is permanent and always serves the latest:

```
https://github.com/lisenhuang/CloudflareTunnelManager/releases/latest/download/CloudflareTunnelManager.dmg
```

### Signed & notarized builds (recommended for public download)

**With no secrets set, the build still works** — but it's *ad-hoc signed*, so on first launch macOS Gatekeeper blocks it and downloaders must right-click → Open (or `xattr -dr com.apple.quarantine …`). The generated release notes say so automatically.

To produce **notarized, double-click-to-run** builds, add these repo secrets (**Settings → Secrets and variables → Actions**). They require an [Apple Developer Program](https://developer.apple.com/programs/) membership:

| Secret | What it is |
|---|---|
| `MACOS_CERTIFICATE` | base64 of your **Developer ID Application** `.p12` (`base64 -i cert.p12 \| pbcopy`) |
| `MACOS_CERTIFICATE_PWD` | password for that `.p12` |
| `MACOS_CODESIGN_IDENTITY` | e.g. `Developer ID Application: Jane Doe (ABCDE12345)` |
| `MACOS_NOTARY_APPLE_ID` | your Apple ID email |
| `MACOS_NOTARY_TEAM_ID` | 10-char Team ID |
| `MACOS_NOTARY_PWD` | an [app-specific password](https://support.apple.com/en-us/102654) |

> **All-or-nothing:** set every `MACOS_*` secret together, or none. The workflow's _Validate signing_ step fails fast on a partial set rather than shipping a silently-broken build.

The same scripts run locally: `CODESIGN_IDENTITY="…" ./scripts/make-app.sh` then `./scripts/make-dmg.sh` and `MACOS_NOTARY_* … ./scripts/notarize.sh CloudflareTunnelManager-<ver>.dmg`.

---

## Cloudflare API token (for Named tunnels only)

Create a scoped token at **dash.cloudflare.com → My Profile → API Tokens** with:

- **Account · Cloudflare Tunnel · Edit**
- **Zone · DNS · Edit**
- **Zone · Zone · Read**

Paste it into **Settings → Account**. It is verified against `/user/tokens/verify` and stored in the Keychain.

---

## Architecture

Layered, with SwiftUI views on top of an observable `AppState`, which coordinates a set of focused services. Nothing in the UI talks to `Process` or the network directly.

```
Views (SwiftUI)
   │  reads/observes
   ▼
AppState  (@MainActor @Observable orchestrator)
   │
   ├── CloudflaredProcessService   launch & supervise cloudflared, stream logs
   ├── CloudflareAPIClient         REST: tunnels, ingress config, DNS routes
   ├── KeychainStore               API + connector tokens (Security framework)
   ├── TunnelStore                 JSON persistence (Application Support)
   ├── InstallationService         detect / brew-install cloudflared
   ├── BinaryLocator               find cloudflared (GUI apps don't inherit PATH)
   └── LogStore                    per-tunnel ring buffer
```

### What runs which command

- **Quick:** `cloudflared tunnel --url http://localhost:PORT --no-autoupdate` → the app parses the `*.trycloudflare.com` URL out of the output.
- **Named create (API):** `POST /accounts/{id}/cfd_tunnel` (config_src=cloudflare) → fetch connector token → `PUT …/configurations` (ingress) → `POST /zones/{id}/dns_records` (CNAME → `<tunnel-id>.cfargotunnel.com`, proxied).
- **Named run:** `cloudflared tunnel run --token <token> --no-autoupdate` — no local cert or credentials file needed.

### Folder structure

```
Sources/CloudflareTunnelManager/
├── App/         CloudflareTunnelManagerApp.swift   (scenes: Window, MenuBarExtra, Settings)
├── Models/      TunnelItem, TunnelMode, TunnelStatus, AppSettings, CloudflareModels
├── Services/    CloudflaredProcessService, CloudflareAPIClient, KeychainStore,
│                TunnelStore, InstallationService, BinaryLocator, LogStore
├── State/       AppState  (orchestrator)
├── Utilities/   TunnelInputParsing (URL/host validation, log parsing)
└── Views/       ContentView, TunnelRowView, TunnelDetailView, CreateTunnelSheet,
                 LogsView, SettingsView, AccountSettingsView, MenuBarView, StatusBadge
```

---

## Security & publishing notes

- **No secrets in the repo.** API tokens and connector tokens are stored only in the **Keychain**; tunnel/settings JSON (no secrets) lives in `~/Library/Application Support/CloudflareTunnelManager/`. The `.gitignore` additionally blocks `*.pem`, `.env`, `cert.pem`, exported `*.json`, etc. as a backstop.
- **App Sandbox is intentionally off.** A sandboxed app cannot spawn an arbitrary executable like `cloudflared`, so this ships as a **Developer ID–signed, notarized** app (not Mac App Store). For local dev the bundler applies an ad-hoc signature.

## Known limitations / roadmap

- Restoring previously-running tunnels on launch is stubbed (running state isn't persisted in the MVP).
- No automatic `cloudflared` version-update prompts yet.
- Named-tunnel deletion is best-effort on the API side.
- Multiple ingress rules per tunnel (one tunnel → many hostnames) is not yet exposed in the UI.
