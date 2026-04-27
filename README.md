# Anchor

> Auto-mount your SMB/NFS network shares. Wherever you are.

Anchor is a macOS menu bar app that keeps your network shares mounted — at home on your LAN, at the office, or anywhere via Tailscale, NetBird, or ZeroTier. No manual reconnecting.

## Features

### Free
- Up to 3 shares auto-mounted on login and wake
- SMB + NFS support
- Instant network-change detection (zero polling — kernel-notified)
- Credentials stored securely in Keychain

### Pro ($9.99 one-time)
- Unlimited shares
- **Mesh VPN smart routing** — tries LAN first, falls back to Tailscale / NetBird / ZeroTier automatically
- Multi-profile support (Home / Office / Travel)
- Config export/import for fleet deployment
- Share health notifications

## Requirements
- macOS 13.0 Ventura or later

## Installation

**Mac App Store** — *coming soon*

**Direct download (free build)** — *coming soon*

## Building from source

Requirements: Xcode 15+, macOS 13+

```bash
git clone https://github.com/mikezieseniss/anchor
cd anchor
xcodegen generate
open Anchor.xcodeproj
```

## Architecture

Two-process model — no root required, Mac App Store compatible:
- `AnchorApp` — SwiftUI menu bar UI, settings, Pro upgrade
- `AnchorHelper` — Login item via `SMAppService`; handles all mounting via `NetFS`

Communication via shared App Group container (JSON config) + Darwin Distributed Notifications.

## Mesh VPN Detection

Anchor automatically detects and uses the right address for your mesh VPN:

| VPN | Detection |
|-----|-----------|
| Tailscale | `100.x.x.x` interface + process check |
| NetBird | `100.64.0.0/10` interface |
| ZeroTier | `172.22.0.0/15` interface |
| WireGuard | Generic `utun` interface |

## License
MIT
