<p align="center"><img src="Assets/icon.png" width="128" alt="limitbar icon"></p>

# limitbar

A macOS menu bar app that shows how much of your AI subscription limits you have used: Claude, Codex (ChatGPT), Gemini (via Antigravity) and Grok. A simpler tray app covers [Windows and Linux](#windows-and-linux).

It reuses the credentials your existing CLIs and browser already have. No accounts, no API keys, no servers. Requests go straight from your computer to each provider.

## What you get

- A menu bar strip with each signed-in provider's logo and its tightest limit in percent. It turns amber at 80% or more.
- A popover with a one-line verdict ("All clear", "Claude is nearly out") and a card per provider: 5-hour, weekly and daily windows, and when each one resets.
- A dashboard window with a chart of what used up the window. For Claude it is estimated from Claude Code session logs, for Codex it is measured from Codex session logs.
- Refresh every 5 minutes (configurable), on popover open, and on Cmd+R. The last known values are cached, so the bar shows data right after launch.

## Requirements

- macOS 15 or later.
- To build from source: a Swift 6 toolchain, either Xcode 16 or later, or just the Command Line Tools (`xcode-select --install`).
- At least one of the supported providers, signed in as described below.

## Install

### Download

1. Download `limitbar-<version>.dmg` from [Releases](https://github.com/Wake360/limitbar/releases). It runs on Apple silicon and Intel Macs.
2. Open the DMG and drag limitbar into Applications.
3. Open limitbar from Applications. The app is not notarized by Apple, so macOS blocks the first launch. Go to System Settings > Privacy & Security, scroll to "limitbar was blocked", and click Open Anyway.

If you prefer the terminal, this clears the block instead of step 3:

```sh
xattr -dr com.apple.quarantine /Applications/limitbar.app
```

### Build from source

```sh
git clone https://github.com/Wake360/limitbar.git
cd limitbar
scripts/bundle.sh
mv limitbar.app /Applications/
open /Applications/limitbar.app
```

`scripts/bundle.sh` builds a release binary, assembles `limitbar.app` and code-signs it. The app has no Dock icon; look for it in the menu bar.

To start it at login, open the popover, then Settings, and turn on "Launch at login".

### Optional: a stable signing identity

Without a signing certificate the script signs the app ad hoc. That works, but macOS treats every rebuild as a new app, so you click "Always Allow" on the Keychain prompts again after each update.

To keep those grants across rebuilds, create a self-signed certificate once:

1. Open Keychain Access, then Keychain Access > Certificate Assistant > Create a Certificate.
2. Name: `limitbar Local Signing`. Identity Type: Self Signed Root. Certificate Type: Code Signing.
3. Click Create.

`scripts/bundle.sh` uses it automatically when it exists.

### Make a DMG

```sh
scripts/dmg.sh
```

This runs `scripts/bundle.sh` and writes `dist/limitbar-<version>.dmg`. The version comes from `CFBundleShortVersionString` in `Sources/limitbar/Resources/Info.plist`.

## Providers

| Provider | Where limitbar reads credentials | How to sign in |
| --- | --- | --- |
| Claude | Keychain item `Claude Code-credentials` | Install [Claude Code](https://docs.claude.com/en/docs/claude-code) and run `claude` |
| Codex | `~/.codex/auth.json` | Install the [Codex CLI](https://github.com/openai/codex) and run `codex login` |
| Gemini | Keychain item from Antigravity (service `gemini`, account `antigravity`) | Open Antigravity and sign in |
| Grok | The `sso` cookie for grok.com in Chrome, Brave, Arc, Edge or Chromium | Log in to grok.com in one of those browsers, or paste the cookie in Settings |

Providers you don't use just stay hidden from the menu bar.

### First launch prompts

macOS will ask for permission the first time limitbar reads each credential:

- Keychain prompts for `Claude Code-credentials`, the Antigravity item and your browser's "Safe Storage" key (Grok only). Click "Always Allow".
- If the Grok row asks for Full Disk Access, add limitbar in System Settings > Privacy & Security > Full Disk Access, then relaunch it. Or paste the cookie in Settings instead: copy the value of the `sso` cookie from grok.com in your browser's developer tools.

## Privacy and safety

- limitbar only reads credentials. It never refreshes Claude or Codex tokens, because refreshing outside the CLI can sign you out of it. When a token expires, the row tells you to run `claude` or `codex login`.
- The Antigravity token is refreshed in memory for each fetch and never written back to the Keychain.
- A pasted Grok cookie is stored in your login Keychain under `limitbar grok sso`.
- Usage snapshots and a 14-day history are stored in `~/Library/Application Support/limitbar/`.
- Session logs in `~/.claude/projects` and `~/.codex/sessions` are read locally for the dashboard chart and never sent anywhere.
- Network requests go only to the providers' own usage endpoints. There is no telemetry.

## Development

```sh
swift build
swift test
swift test --filter claudeParse
```

Each provider in `Sources/limitbar/Providers/` has a pure `parse` function tested against a fixture in `Tests/limitbarTests/Fixtures/`. See `CLAUDE.md` for an architecture overview.

If the build fails on a beta macOS SDK, point it at an older one:

```sh
export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
```

## Uninstall

```sh
rm -rf /Applications/limitbar.app ~/Library/Application\ Support/limitbar
defaults delete com.filipvachek.limitbar
security delete-generic-password -s "limitbar grok sso"
```

The last command only matters if you pasted a Grok cookie.

## Windows and Linux

The Windows and Linux app lives in `tauri/` (Rust and Tauri). It is simpler than the macOS app: a tray icon whose menu lists the tightest limit per provider, and a window with the provider cards and settings. There is no drain chart.

### Install

- Windows 10 or 11: download `limitbar_<version>_x64-setup.exe` from [Releases](https://github.com/Wake360/limitbar/releases) and run it. It installs for your user only and needs no admin rights. The installer is not signed, so SmartScreen may warn: click More info, then Run anyway.
- Debian and Ubuntu: download `limitbar_<version>_amd64.deb` and run `sudo apt install ./limitbar_<version>_amd64.deb`.
- Other distributions: download `limitbar_<version>_amd64.AppImage`, run `chmod +x` on it and start it.

On GNOME, tray icons need the AppIndicator extension (`gnome-shell-extension-appindicator`). On Windows, left-click the tray icon to open the window. On Linux, use Open limitbar in the tray menu.

### Providers on Windows and Linux

| Provider | Where limitbar reads credentials |
| --- | --- |
| Claude | `~/.claude/.credentials.json`, or `$CLAUDE_CONFIG_DIR` |
| Codex | `~/.codex/auth.json`, or `$CODEX_HOME` |
| Gemini | Antigravity's entry in Windows Credential Manager or the Linux Secret Service keyring. Not yet tested. |
| Grok | Paste the `sso` cookie in the window. Browser cookies are not read. |

The refresh interval is saved in the app's config folder. A pasted Grok cookie goes to the system keyring under service `limitbar`, user `grok sso`. The same credential rules apply as on macOS: Claude and Codex tokens are never refreshed.

### Build from source

Install Rust and the [Tauri prerequisites](https://v2.tauri.app/start/prerequisites/) for your system, then:

```sh
cd tauri
cargo test
npx @tauri-apps/cli@2 build
```

Installers land in `tauri/target/release/bundle/`.

### Releases

Pushing a tag such as `v0.1.0` runs `.github/workflows/tauri.yml`, which builds the Windows and Linux installers and attaches them to a draft GitHub release. Build the macOS DMG locally with `scripts/dmg.sh` and add it to the same release.

## Caveats

limitbar uses private, undocumented endpoints. Any provider can change them without notice, and a row may break until the parser is updated. If that happens, please open an issue.

This project is not affiliated with or endorsed by Anthropic, OpenAI, Google or xAI. Product names and logos belong to their owners.

## License

MIT, see [LICENSE](LICENSE).
