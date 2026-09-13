<div align="center">

# ConBarAI for macOS

**The AI console that hides underneath the island.**

One keystroke (⌥⏎) and it drops from the notch like a Dynamic Island; another
and it tucks itself away. Inside lives **pi** (pi.dev), a lightweight agent
that answers anything and controls your Mac. No new windows, no lost flow.

[Screenshots](README.md#capturas) · [Install](#install) · [Shortcuts](#shortcuts) · [Security](#security)

`macOS 13+ · native on Apple silicon (M1–M6), also runs on Intel · MIT · by 686f6c61`

</div>

---

## Install

### Option A — DMG (recommended)

1. Grab `ConBarAI-x.y.z.dmg` from the [releases](https://github.com/686f6c61/ConBarAI-MacOS/releases).
2. Drag **ConBarAI** into **Applications**.
3. Double-click: it self-configures (LaunchAgents, skills, `~/.local/bin/conbarai`)
   and the pill now lives in your notch. No Dock icon, no sudo.
4. Open Settings (menu-bar terminal icon) → **Providers & models**, paste
   your API key (NaN, OpenAI, Claude, Z.ai, Kimi or x.ai), load live model
   lists and pick a default.

Missing `pi` or `tmux`? **The island installs them for you**: on first
open it shows a cover with a button that installs them through their
official channel (Homebrew for tmux, npm for pi). With no package manager
it downloads nothing on its own — it points you to
[brew.sh](https://brew.sh) or [nodejs.org](https://nodejs.org). From the
terminal: `conbarai deps`. OpenCode works as an optional fallback agent.

### Option B — from source

```bash
git clone https://github.com/686f6c61/ConBarAI-MacOS
cd ConBarAI-MacOS && ./install.sh
```

Builds (Swift + SwiftTerm), registers the same LaunchAgents. `./uninstall.sh`
removes everything cleanly.

## What it does

- **Instant console**: ⌥⏎ or click the notch; pi with the bundled skills
  (`macos-operator`, `mac-gui-pilot`, `conbarai-ops`); one session per folder;
  ⌘N fresh conversation, ⌘W hides.
- **Ask anything, control the Mac**: macos-operator ships the full command
  toolbox (System Events, Shortcuts, defaults, Finder, networking, brew,
  launchd…) under a diagnose-first, know-your-rollback discipline;
  mac-gui-pilot adds verified computer-use.
- **Providers & models**: 6 providers, live model lists from their APIs, keys
  stored in `~/.config/conbarai/auth` (0600) and injected via environment —
  never committed.
- **Crash forensics**: a LaunchAgent watches system `.ips` reports; on a
  crash, a tool-less agent writes a structured report (What happened /
  Evidence / Likely cause / Fix with rollbacks / Prevention).
- **Self-update**: `conbarai update` downloads the latest release DMG,
  replaces the .app and relaunches the agents.

## Shortcuts

| Shortcut | Action |
|---|---|
| ⌥⏎ / click the island | show/hide the console |
| ⌘N or ⌘K | new conversation (clean; recover old ones with `pi -r`) |
| ⌘W | hide the island |
| `/model`, `/new`, `/compact`… | pi commands (full list: `conbarai help`) |

## Security

- User-space only, no sudo; TCC permissions only if you grant them.
- API keys in `~/.config/conbarai/auth` (0600), injected via environment.
- Crash analysis runs `pi --no-tools`: it only reasons over evidence gathered
  by ConBarAI with a closed read-only command list.
- Only outbound call of its own: update checks against `api.github.com`
  (disableable).
- The installer never executes remote scripts.

## Updates & uninstall

```bash
conbarai update --check   # any news?
conbarai update           # download DMG, swap .app, relaunch
./uninstall.sh            # clean removal
```

Native port of [ubuntu-ConBarAI](https://github.com/686f6c61/ubuntu-ConBarAI):
same missions, different house — NSPanel+SwiftTerm instead of GTK, launchd
instead of systemd, `.ips` instead of journald.

## License

MIT — same as the Ubuntu version.
