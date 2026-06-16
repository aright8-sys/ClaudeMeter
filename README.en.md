<p align="center">
  <img src="Assets/AppIcon.png" width="128" height="128" alt="ClaudeMeter logo">
</p>

<h1 align="center">ClaudeMeter</h1>

<p align="center">
  A lightweight macOS menu bar app: <strong>watch your Claude quota and track usage &amp; cost across your AI coding tools</strong>.
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
  <img src="docs/screenshot.png" width="380" alt="ClaudeMeter screenshot">
</p>

It lives in your menu bar and shows the current **5-hour window** utilization plus a countdown to the next reset; open the panel to also see your weekly quota and a **30-day usage ledger** — tokens and estimated dollar cost broken down by day and by model, with a Token / Cost toggle.

- 🪶 **Lightweight** — native Swift + SwiftUI, no third-party dependencies, just a few MB
- 📊 **Quota** — captures Claude Code's statusline data; 5-hour / weekly windows at a glance
- 🧾 **Multi-tool ledger** — Claude Code & Codex local logs + Cursor cloud usage, unified by day/model
- 💸 **Cost estimate** — equivalent spend computed from official API pricing; Token / Cost toggle
- 🖱️ **Interactive** — hover the daily bar chart to instantly see that day's numbers

> 📦 **Download**: grab the prebuilt `ClaudeMeter.app` from [Releases](https://github.com/aright8-sys/ClaudeMeter/releases/latest), or build it yourself (see below).

## 🆕 Changelog

### v2.0.0

- **Quota now captured from the statusline**: no longer reads a Keychain token or calls Anthropic's private endpoint. Instead it installs a transparent wrapper into Claude Code's `statusLine.command` and captures the `rate_limits` payload Claude Code emits on every render. More robust, never touches your credentials, and coexists with similar tools like [vibe-usage](https://github.com/vibe-cafe/vibe-usage-app).
- **New "ledger" feature**: scans local session logs and aggregates tokens by day + model, fully local:
  - **Claude Code** — `~/.claude/projects/**/*.jsonl`
  - **Codex** — `~/.codex/{sessions,archived_sessions}/**/*.jsonl`
- **Cursor usage added**: reads your Cursor session from its local database and fetches your cloud usage from `cursor.com` (**the only data source that goes online**).
- **Token / Cost toggle**: cost is the "equivalent API value" from official pricing (input/output + cache-read ×0.1, cache-writes excluded, matching vibe-usage's methodology).
- **Daily bar chart**: hover to instantly show that day's date and value, with the hovered bar highlighted.
- Removed the old `UsageAPI.swift` (OAuth endpoint approach).

## ⚠️ Disclaimer & data notes

> This is a personal project, **not affiliated with, authorized, or endorsed by Anthropic, OpenAI, or Cursor**.
> It depends on **undocumented / reverse-engineered formats and endpoints** (Claude Code's statusline
> payload, each tool's local logs, Cursor's dashboard API), any of which may change or break at any time.
>
> **Where your data goes**:
> - **Quota + Claude/Codex ledger**: entirely local — no network, no upload.
> - **Cursor ledger**: reads your local Cursor session and **makes a network request to `cursor.com`**
>   to fetch your account's cloud usage. Used only to display on your machine; never sent to any third party.
>
> **Cost is for reference only**: it's an "equivalent value" computed from API pricing, **not what you
> actually pay** (subscribers pay a flat monthly fee). Cursor's internal models such as `auto`/`composer`
> use approximate rates, not official pricing.
>
> For personal, educational use only — **use at your own risk**.

## How it works

### Quota (statusline capture)

On every statusline render, Claude Code pipes a JSON payload (including `rate_limits`) via stdin to your
configured `statusLine.command`. When you first enable it, ClaudeMeter installs a transparent wrapper into
that command (the script lives in `~/.claudemeter/`). The wrapper does two things:

1. tees the `rate_limits` slice (5-hour / weekly windows) to `~/.claudemeter/claude-rate-limits.json`;
2. re-runs your **original** statusline command with identical stdin, so your existing statusline keeps
   working untouched.

The install is idempotent, self-healing, and can be disabled/restored anytime.

### Ledger (local logs + Cursor cloud)

AI coding tools write session logs locally, and each assistant message carries its own token usage.
ClaudeMeter scans those logs, aggregates by day + model, and converts to cost using official pricing:

| Source | Location | Network |
| --- | --- | --- |
| Claude Code | `~/.claude/projects/**/*.jsonl` | No |
| Codex | `~/.codex/{sessions,archived_sessions}/**/*.jsonl` | No |
| Cursor | reads token from local `state.vscdb` → requests `cursor.com` | **Yes** |

## Build & run

Requires macOS 14+ and a Swift toolchain (Xcode or the Command Line Tools is enough — you don't need to
open Xcode).

```bash
./build-app.sh            # compile and package into ClaudeMeter.app
open ClaudeMeter.app      # run
cp -r ClaudeMeter.app /Applications/   # install (optional)
```

Development:

```bash
swift build               # compile only
swift run                 # run directly
```

## Usage

After launching, click the gauge icon in the menu bar:

- **Quota**: ring progress = 5-hour window utilization; below it, 5-hour / weekly utilization with reset
  countdowns. On first use, click "Enable" in the panel to install the statusline hook once, then send a
  message in Claude Code to trigger a statusline render.
- **Ledger**: last 30 days of usage, with a Token / Cost toggle in the top-right; hover the daily bar chart
  for a given day, and see the per-model ranking below.

## Project layout

```
Sources/ClaudeMeter/
  ClaudeMeterApp.swift   App entry + MenuBarExtra
  AppState.swift         State, refresh scheduling, derived values
  StatuslineHook.swift   Install/uninstall the statusline wrapper
  RateLimitReader.swift  Read the capture file, parse quota windows
  UsageHistory.swift     Scan local logs + aggregation + pricing
  CursorReader.swift     Read Cursor token + fetch cloud usage (SQLite + HTTP)
  HistoryView.swift      Ledger UI (Token/Cost, bar chart, per-model)
  ProgressRing.swift     Ring progress component
  PopoverView.swift      Popover panel UI
  Format.swift           Display formatting
build-app.sh             Packaging script (writes LSUIElement)
```

## License

[MIT](LICENSE)
