# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

macOS menu bar app (Swift 6, SwiftUI `MenuBarExtra`) showing subscription usage windows for Claude, Codex, Gemini and Grok. No third-party dependencies. User-facing docs in `README.md`.

## Commands

Xcode is not installed, only Command Line Tools. The default SDK (MacOSX27.0) fails to compile, so `~/.zshenv` pins the SDK for every build and test:

```sh
export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
```

```sh
swift build
swift test
swift test --filter claudeParse
scripts/bundle.sh
scripts/dmg.sh
```

`scripts/bundle.sh` builds a universal (arm64 and x86_64) release, assembles `limitbar.app` and signs it with the self-signed "limitbar Local Signing" identity in the login Keychain when present (ad hoc otherwise), so Keychain and Full Disk Access grants survive rebuilds. `scripts/dmg.sh` wraps the app in `dist/limitbar-<version>.dmg` with an Applications link. Tests use swift-testing (`@Test`, `#expect`); `Package.swift` passes the Command Line Tools testing plugin path via `unsafeFlags`. `LiveProbe.swift` hits real endpoints with real Keychain credentials; exclude it from normal runs.

## Architecture

- `Provider` is an enum, not a protocol. `Store.liveFetcher` switches over it and calls each provider's static `fetch()`.
- Each file in `Providers/` is an enum with a pure `parse(Data, ..., now:) -> Snapshot` (tested against `Tests/limitbarTests/Fixtures/<provider>.json`) and an async `fetch()` that reads local credentials and calls a private endpoint. Every provider returns the same shape: `Snapshot` with `[UsageWindow]` of kind `fiveHour`, `weekly`, `daily` or `credits`.
- `Store` (`@MainActor @Observable`) holds one `ProviderStatus` per provider: `empty`, `fresh`, `stale(last, message)` or `loggedOut(last, hint)`. Providers fetch in parallel via a task group; one failure never blocks others. `CredentialError.missing/expired` maps to `loggedOut`, any other error to `stale`. The last snapshot is kept and persisted to `~/Library/Application Support/limitbar/snapshots.json`, loaded as `stale(_, "cached")` on launch.
- `Store` takes an injectable `Fetcher` closure and file URL; tests use these instead of network.
- `HTTP.check` (in `Claude.swift`) turns 401/403 into `CredentialError.expired(loginHint)`.
- `Credentials.swift` handles Keychain JSON, credential JSON files, and Chromium cookie decryption (Chrome, Brave, Arc, Edge, Chromium Safe Storage keys) for the Grok `sso` cookie.
- `Limits`: per provider, the tightest window (`highest`) is the availability. `hot` at 80% used or more. `backAt` for a hot provider is the latest reset among its hot windows, nil if any hot window lacks a reset; for a cool one it is the tightest window's reset. `ordered`/`tightest` rank providers by used percent.
- `Verdict`: pure copy for the popover headline and line ("All clear", "X is nearly out", "Everything is used up", "No data yet") from `Limits`.
- `History`: `history.jsonl` next to `snapshots.json`, one `Snapshot` per line, entries older than 14 days pruned on init. Owned by `Store`, which appends each fresh snapshot.
- `Sessions/`: read-only parsing of Claude Code and Codex logs. `ClaudeSessions` yields `UsageEvent`s (tokens), `CodexSessions` yields `PercentPoint`s (`used_percent` readings).
- `Drain`: what ate the window. Claude is estimated, sharing used percent across sessions by token weight. Codex is measured, from rises in `used_percent`. Three named sessions plus Other, stacked as `Band`s, and `climb` is the steepest 30-minute rise (10 points or more).
- Views: colours live in `Views/Theme.swift` (adaptive light/dark tokens, `Provider.accent`). `MenuBarLabel` draws one non-template strip with every signed-in provider's logo and number (amber at 80% or more), or a dashed ring when none, from the pure `items`. `PopoverView` leads with the verdict and shows a `ProviderCard` per provider. `DashboardView` is a `NavigationSplitView` with a sidebar of rings, a header with the countdown, window cards, and the `DrainChart` and sessions cards.

## Windows and Linux app

`tauri/` is a separate Tauri 2 app for Windows and Linux. `src/providers.rs` ports the Swift parsers and fetches (tests reuse `Tests/limitbarTests/Fixtures`), `src/main.rs` runs the refresh loop, tray menu and commands, `ui/` is plain HTML and JS with no build step. Rust lives in `~/.cargo/bin`, not on PATH. Run `cargo test` in `tauri/`. `.github/workflows/tauri.yml` builds the NSIS, deb and AppImage installers on a `v*` tag.

## Credential rules

- Claude (Keychain `Claude Code-credentials`) and Codex (`~/.codex/auth.json`): never refresh tokens from this app. An expired token means `loggedOut` with the login hint, because refreshing outside the CLI can invalidate its session.
- Antigravity (Keychain service `gemini`, account `antigravity`, `go-keyring-base64:` JSON): feeds the `gemini` row. Each fetch refreshes an access token in memory with the Antigravity client; never write back to the Keychain item.
- Fixtures never contain real secrets; tokens are the literal `"test-token"`.
