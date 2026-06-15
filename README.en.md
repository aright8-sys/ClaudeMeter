<p align="center">
  <img src="Assets/AppIcon.png" width="128" height="128" alt="ClaudeMeter logo">
</p>

<h1 align="center">ClaudeMeter</h1>

<p align="center">
  A lightweight macOS menu bar app that lets you <strong>see how much of your Claude quota is left, at a glance</strong>.
</p>

<p align="center">
  <a href="README.md">中文</a> ·
  <strong>English</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue?logo=apple" alt="platform">
  <img src="https://img.shields.io/badge/Swift-SwiftUI-orange?logo=swift&logoColor=white" alt="swift">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="license">
</p>

<p align="center">
  <img src="docs/screenshot.png" width="420" alt="ClaudeMeter screenshot">
</p>

It lives in your menu bar and shows the current **5-hour window** utilization percentage plus a countdown to the next reset; open the panel to also see your weekly quota. The numbers match the terminal `/usage` command and the desktop app exactly — because it reads the same account-level endpoint, covering usage across all your devices.

- 🪶 **Lightweight** — native Swift + SwiftUI, no dependencies, just a few MB
- 📊 **Accurate** — real account-level usage, identical to `/usage`
- 🔕 **Unobtrusive** — menu-bar only, no Dock icon, low-frequency polling
- 🔒 **Zero config** — reuses your local Claude Code session; no keys to enter

> 📦 **Download**: grab the prebuilt `ClaudeMeter.app` from [Releases](https://github.com/aright8-sys/ClaudeMeter/releases/latest), or build it yourself (see below).

> ### ⚠️ Disclaimer
>
> This is a personal project, **not affiliated with, authorized, or endorsed by Anthropic**.
> It relies on an **undocumented internal endpoint** (the same one Claude Code itself calls
> for the `/usage` command), which may change or stop working at any time and break this tool.
>
> This tool **does not collect, upload, or store** any of your data. Your session credential
> is read from the local macOS Keychain only at runtime, used solely to query usage directly
> from Anthropic's official endpoint, and is never sent to any third party.
>
> For personal, educational use only — **use at your own risk**.

## How it works

It reuses the OAuth session that Claude Code stores in the macOS Keychain and calls the same
endpoint as `/usage`, `GET https://api.anthropic.com/api/oauth/usage`, returning **real
account-level usage** — identical to the terminal `/usage` and the desktop app, covering
all devices:

- **5-hour window** utilization + reset time
- **Weekly (all models)** utilization + reset time

### Keychain access

On first launch, macOS asks whether to allow ClaudeMeter to read `Claude Code-credentials` —
click "Always Allow" (you won't be asked again). The token is refreshed by Claude Code itself
and written back to the Keychain; ClaudeMeter always reads the latest one. When the session
expires, the panel prompts you to sign in again via Claude Code.

## Build & run

Requires macOS 14+ and a Swift toolchain (Xcode or the Command Line Tools is enough — you
don't need to open Xcode).

```bash
./build-app.sh            # compile and package into ClaudeMeter.app
open ClaudeMeter.app      # run
cp -r ClaudeMeter.app /Applications/   # install (optional)
```

Development:

```bash
swift build               # compile only
swift run                 # run directly (appears in the Dock as a normal process; the packaged app does not)
```

## Usage

After launching, click the gauge icon in the menu bar:

- Ring progress = official 5-hour window utilization (matches `/usage`)
- 5-hour window / weekly utilization + their reset countdowns

Refresh strategy: usage is polled every 600 seconds, and once immediately when you open the
panel (skipped if refreshed within the last 60 seconds, to avoid rate limiting); a separate
30-second timer only updates the countdown.

## Project layout

```
Sources/ClaudeMeter/
  ClaudeMeterApp.swift   App entry + MenuBarExtra
  AppState.swift         State, refresh scheduling, derived values
  UsageAPI.swift         Keychain token read + official usage endpoint
  ProgressRing.swift     Ring progress component
  PopoverView.swift      Popover panel UI
  Format.swift           Display formatting
build-app.sh             Packaging script (writes LSUIElement)
```

## License

[MIT](LICENSE)
