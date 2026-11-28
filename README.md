<p align="center"><img src="docs/images/icon.svg" width="128" alt="Kachel icon: a green tiled stove"></p>

# Kachel

[![CI](https://github.com/jklaiber/kachel/actions/workflows/ci.yml/badge.svg)](https://github.com/jklaiber/kachel/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/jklaiber/kachel)](https://github.com/jklaiber/kachel/releases/latest)
[![Docs](https://img.shields.io/badge/docs-jklaiber.github.io%2Fkachel-blue)](https://jklaiber.github.io/kachel/)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

*Kachel* is German for tile, as in a *Kachelofen*, the tiled stove in the icon:
nine glazed tiles for nine workspaces.

![Kachel: three tiled windows, the focused one framed in orange, Kachel's bar along the bottom](docs/images/screenshots/desktop.png)

A native tiling window manager for macOS with **xmonad's workspace model**: nine
workspaces shared by all displays, each display showing one of them, and
**`greedyView`**. Press `mod-2` while workspace 2 is on the other display, and
the two displays swap.

```
 before mod-2 on A          after
 ┌──────┐ ┌──────┐          ┌──────┐ ┌──────┐
 │  A:1*│ │  B:2 │   ──▶    │  A:2*│ │  B:1 │
 └──────┘ └──────┘          └──────┘ └──────┘
```

**📖 Documentation: [jklaiber.github.io/kachel](https://jklaiber.github.io/kachel/)**

## Install

```bash
brew install --cask jklaiber/tap/kachel
```

Open Kachel and grant Accessibility; the welcome window walks you through it and
checks the macOS settings that get in the way. Quit Amethyst, yabai or AeroSpace
first. Upgrades keep the permission.

## What it does

- **Workspaces shared by all displays**, switched instantly, without macOS
  Spaces and without disabling SIP.
- **Eleven layouts**, from Tall and Three-column to BSP, a starting layout per
  workspace; drag edges to resize.
- **A bar along the bottom** of every display, in the style of the menu bar.
- **Window search** (`mod-p`), **app rules** (`mod-shift-p`) and **scratchpads**
  (`mod-s`).
- **Trackpad swipes** between workspaces, mouse drag-to-swap, focus border.
- **A settings window** like System Settings, and a shortcut overview when you
  hold `mod`.
- **A `kachel` command** for scripts, launchers and other bars: run any
  command, ask where everything is as JSON, or follow every change.
- **Dependable**: workspaces survive a restart, a crash puts windows back and
  starts Kachel again, a hung app doesn't hold it up.
- Everything lives in `~/.config/kachel/config.yaml`; the settings window
  writes into it with your comments kept.

## A few keys

`mod` is Option by default.

| Key | Action |
|---|---|
| `mod-1` … `mod-9` | show workspace N here (swap displays if needed) |
| `mod-shift-1` … `9` | move the window to workspace N |
| `mod-j` / `mod-k` | focus next / previous window |
| `mod-shift-j` / `mod-shift-k` | swap with next / previous window |
| `mod-h` / `mod-l` | narrower / wider master |
| `mod-shift-space` | next layout |
| `mod-p` | search windows |
| `mod-tab` | back to the previous workspace |

All of them are in the [keys page](https://jklaiber.github.io/kachel/keys/).
Coming from xmonad, Amethyst or AeroSpace? See
[Coming from…](https://jklaiber.github.io/kachel/coming-from/).

## Build

Requires macOS 26+ and Xcode 26 (or its Command Line Tools).

```bash
swift test
./scripts/bundle.sh && open build/Kachel.app
```

More in [Development](https://jklaiber.github.io/kachel/development/).
Changes are listed in [CHANGELOG.md](CHANGELOG.md).

## Contributing

Bug reports, ideas and pull requests are welcome; see
[CONTRIBUTING.md](CONTRIBUTING.md). Questions go to
[Discussions](https://github.com/jklaiber/kachel/discussions), security problems
to [private reporting](SECURITY.md).

## Licence

[MIT](LICENSE) © Julian Klaiber
