# Anchor — Product Design Spec
*Date: 2026-04-27 | Status: Approved for implementation planning*

---

## Overview

Anchor is a macOS menu bar app that automatically mounts and reconnects SMB/NFS network shares. It targets three user types — normal Mac users who want their NAS to just appear, developers who want home lab and office shares accessible everywhere, and IT admins managing fleets of Macs.

The key differentiator over existing tools (AutoMounter, SMBMounter, MacMount) is **mesh VPN-aware smart routing**: Anchor detects Tailscale, NetBird, and ZeroTier and automatically falls back to the mesh VPN peer when the user is off their local network. No manual switching, no re-entering credentials.

---

## Distribution & Monetisation

- **Platform:** Mac App Store (primary) + direct GitHub download (free build)
- **Model:** Free tier + one-time Pro IAP at **$9.99**
- **Apple cut:** 30% year 1, 15% thereafter (Small Business Programme). Net per sale: ~$7 / ~$8.50
- **Payment infrastructure:** StoreKit 2 (IAP) + RevenueCat (server-side entitlement validation, free up to $2,500/month MTR, then 1% above)

---

## Feature Split

### Free
- Up to **3 shares**
- SMB + NFS auto-mounting
- Network change detection (zero-poll, kernel-notified)
- Keychain credential storage
- Auto-mount on login and wake from sleep
- Auto-unmount when host unreachable
- Menu bar mount status

### Pro ($9.99 one-time)
- **Unlimited shares**
- **Mesh VPN detection + smart routing** — try LAN first, fall back to VPN peer automatically
  - Supported: Tailscale, NetBird, ZeroTier, generic WireGuard
- **Multi-profile support** — home / office / travel, shares assigned per profile
- **Config export/import** (JSON) — deploy to multiple Macs, fleet-friendly
- Share health notifications — system notification when a share goes unreachable and again when it reconnects

---

## Architecture

Two-process model. No root required. Mac App Store compatible.

```
┌─────────────────────────────────┐     ┌──────────────────────────────────┐
│  AnchorApp (SwiftUI)            │     │  AnchorHelper (login item)       │
│                                 │     │                                  │
│  • Menu bar icon + dropdown     │     │  • Registered via SMAppService   │
│  • Settings window              │◄───►│  • NWPathMonitor (network events)│
│  • Pro upgrade (StoreKit 2)     │     │  • NetFS (SMB/NFS mounting)      │
│  • RevenueCat entitlement check │     │  • VPN detection logic (Pro)     │
│                                 │     │  • Survives app quit             │
└─────────────────────────────────┘     └──────────────────────────────────┘
          │                                          │
          └──────────── App Group Container ─────────┘
                     config.json (shared)
                  + Darwin Distributed Notifications (status)
```

### Why two processes
`AnchorHelper` is registered as a login item via `SMAppService` (macOS 13+). It runs independently — if the user quits the menu bar app, mounting continues. The app is purely UI; the helper is the engine. This is the same pattern AutoMounter uses, proven through App Store review.

### Communication
- **Config:** JSON file in shared App Group container — app writes, helper reads on change
- **Status:** Darwin Distributed Notifications — helper posts mount state, app observes and updates menu bar icon

---

## Data Models

```swift
// Shared Swift package used by both targets

struct Share: Codable, Identifiable {
    var id: UUID = UUID()
    var displayName: String
    var host: String              // Primary (LAN) IP or hostname
    var shareName: String
    var username: String?         // nil = use Keychain default for host
    var port: Int?                // nil = 445 (SMB default)
    var unmountWhenUnreachable: Bool = true
    // Pro only — nil in free tier
    var fallbackHost: String?     // Mesh VPN IP or FQDN
    var profiles: Set<String> = []
}

struct AnchorConfig: Codable {
    var shares: [Share] = []
    var activeProfile: String? = nil
    var schemaVersion: Int = 1
}

enum MountState: String, Codable {
    case mounted, unmounted, unreachable, mounting, error
}
```

---

## Mounting Logic (AnchorHelper)

Triggered by: `NWPathMonitor` path change, wake from sleep, config file change.

```
for each share in config (filtered by activeProfile if set):
  1. Already mounted + host still up → skip
  2. Mounted but host unreachable + unmountWhenUnreachable → unmount via NetFS
  3. Not mounted:
     a. Check primary host: nc port 445, 1s timeout
     b. If reachable → mount via NetFS (credentials from Keychain)
     c. [Pro] If not reachable + fallbackHost set:
        - Check fallbackHost reachability
        - If reachable → mount via NetFS using fallbackHost
     d. If neither reachable → log, post unreachable notification, retry on next event
  4. Post MountState notification with share ID
```

NetFS is called with the system Keychain — no credential prompts if the user has previously connected in Finder with "Remember password" checked. First-time setup requires one manual Finder connection per share.

---

## Mesh VPN Detection (Pro)

Used to determine which interface type is active and inform the user in the settings UI. The actual routing decision is always preference-based (try LAN first regardless of VPN state).

| VPN | Detection method |
|-----|-----------------|
| Tailscale | Interface with `100.x.x.x` (not `100.64.x.x`) OR bundle ID `com.tailscale.ipn.macos` in running processes |
| NetBird | Interface with `100.64.x.x` OR process `io.netbird.client` |
| ZeroTier | Interface in `172.22.0.0/15` OR process `com.zerotier.one` |
| WireGuard (generic) | Any `utun` interface with a non-standard RFC1918 address |
| None detected | Try both hosts; use whichever port 445 connects on within 1s |

---

## Pro Protection (4 layers)

AutoMounter stores its licence in a plain plist (editable with any text editor). Anchor does not.

1. **StoreKit 2 IAP** — purchase is cryptographically signed and tied to the user's Apple ID
2. **RevenueCat server-side validation** — `Purchases.shared.getCustomerInfo()` called at launch; no server confirmation = Pro features disabled. Eliminates offline receipt spoofing.
3. **Keychain storage** — Pro entitlement token stored in Keychain (ACL-protected, not readable by other processes, not editable via plist)
4. **Enforcement in AnchorHelper** — Pro feature gates are checked in the helper process, not just the UI app. Patching `AnchorApp.app` does not bypass the helper's VPN routing logic.

---

## User Interface

### Menu Bar Icon States
| State | Icon |
|-------|------|
| All shares mounted | ⚓ (solid, accent colour) |
| Partial (some unreachable) | ⚓ (yellow tint) |
| None mounted (shares configured) | ⚓ (red tint) |
| No shares configured | ⚓ (gray, muted) |

### Menu Dropdown
```
● Home NAS     (192.168.0.99)
● Dev Server   (Unraid)
○ Office Scans (unreachable)

──────────────
[Pro] Profile: Home ▾
──────────────
Reconnect All
Open Anchor Settings...
──────────────
Anchor 1.0  •  Upgrade to Pro →   ← free users only
```

### Settings Window (3 tabs)

**Shares tab**
- List of configured shares with mount status
- Add / Edit / Remove
- Edit sheet: display name, host, share name, username (optional), port (optional)
- [Pro] Fallback host field (disabled + lock icon on free)
- [Pro] Profile assignment checkboxes

**Profiles tab** *(Pro only, locked on free)*
- Create / rename / delete profiles
- Active profile selector

**About tab**
- Version number
- Pro status (purchased / not purchased)
- Restore Purchase button
- Link to GitHub repo

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| UI | SwiftUI + AppKit (`NSStatusItem`) |
| Network events | `Network.framework` (`NWPathMonitor`) |
| Mounting | `NetFS.framework` |
| Credentials | `Security.framework` (Keychain) |
| Login helper | `ServiceManagement` (`SMAppService`) |
| IAP | `StoreKit 2` |
| Entitlement validation | RevenueCat SDK (`Purchases`) |
| Minimum macOS | 13.0 Ventura |
| Language | Swift 5.9+ |
| Dependencies | RevenueCat only (no other third-party) |

---

## Build Phases

### Phase 1 — Core (4–5 weeks)
- Xcode project: `AnchorApp` + `AnchorHelper` targets + `AnchorCore` shared Swift package
- Share config UI (list, add/edit/remove sheet)
- `AnchorHelper`: `NWPathMonitor` + `NetFS` mounting + Distributed Notifications
- `SMAppService` login helper registration
- Menu bar status icon with state colours
- Free tier enforcement: 3-share limit, Pro fields locked in UI
- Keychain credential read (no custom storage yet — relies on existing Keychain entries)

### Phase 2 — Pro (3–4 weeks)
- StoreKit 2 IAP flow (purchase, restore)
- RevenueCat SDK integration + server-side entitlement check
- Pro entitlement token → Keychain storage
- VPN detection (Tailscale, NetBird, ZeroTier)
- Smart routing: LAN-first + VPN fallback in AnchorHelper
- Unlimited shares unlock
- Profiles: create/switch/assign, config export/import JSON

### Phase 3 — App Store + Polish (2–3 weeks)
- App Sandbox entitlements audit (`network.client`, NetFS, Keychain)
- App Store screenshots, preview video, metadata
- App Store submission + review
- GitHub repo: public, **MIT licence (full source including Pro features)** — Pro enforcement is in RevenueCat + Keychain + helper, not in source obscurity. Full open source builds trust and GitHub stars.
- Notarisation for direct DMG download
- Minimal marketing page

---

## Success Metrics (6 months post-launch)

| Metric | Target |
|--------|--------|
| GitHub stars | 500 |
| Pro purchases | 100 (~$700 net) |
| App Store rating | 4.0+ |
| RevenueCat cost | $0 (under $2,500/month MTR) |

---

## Open Questions

- None — all key decisions resolved in design session.

---

## Decision Log

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Target audience | All levels (normal → admin) | Widest addressable market |
| Distribution | Mac App Store primary | Discoverability + Apple trust badge |
| Monetisation | One-time Pro IAP $9.99 | Proven price point (AutoMounter), no subscription friction |
| Feature gate | 3 shares + no VPN (free) | Share limit for normal users, VPN routing as clear upgrade story |
| Name | Anchor | Short, memorable, metaphor works ("stays anchored wherever you are") |
| Architecture | SwiftUI app + SMAppService helper | MAS-proven (AutoMounter pattern), no root required |
| Pro protection | StoreKit 2 + RevenueCat + Keychain + helper enforcement | 4-layer defence, significantly harder to bypass than Paddle/plist |
| Min macOS | 13.0 Ventura | Required for SMAppService; covers ~85% of active Macs |
