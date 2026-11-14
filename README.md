# XMonadMac

A small native macOS tiling window manager that copies xmonad's workspace model:
9 workspaces shared by all monitors, each monitor showing one of them, and
**`greedyView`**. If you're on screen A and press `mod-2` while workspace 2 is
on screen B, the two screens swap: A shows 2 and B shows 1, just like xmonad.

```
 before mod-2 on A          after
 ┌──────┐ ┌──────┐          ┌──────┐ ┌──────┐
 │  A:1*│ │  B:2 │   ──▶    │  A:2*│ │  B:1 │
 └──────┘ └──────┘          └──────┘ └──────┘
```

## How it works

macOS Spaces can't be scripted reliably without disabling SIP, so XMonadMac
doesn't use them. All windows live on one Space per display. Windows of hidden
workspaces are parked in a screen corner with one pixel showing (the same
approach AeroSpace uses). Switching is instant and workspaces can move freely
between monitors.

```
Sources/XMonadCore/StackSet.swift   pure model: workspaces, screens, greedyView, shift, …
Sources/XMonadCore/Layout.swift     Tall, Wide, Column, Full
Sources/XMonadCore/Settings.swift   config.yaml parsing + the default config
Sources/XMonadMac/Config.swift      loads ~/.config/xmonadmac/config.yaml, reloads on save
Sources/XMonadMac/WindowManager.swift  Accessibility API glue, tracking, rendering
Sources/XMonadMac/AX.swift          AXUIElement helpers, screens
Sources/XMonadMac/HotKeys.swift     global hotkeys (Carbon RegisterEventHotKey)
Sources/XMonadMac/Bar.swift         xmobar-like bar at the bottom of every screen
```

## Build and run

Requires macOS 13+ and the Xcode Command Line Tools (`xcode-select --install`).

```sh
swift test                 # model tests (greedyView, shift, layouts, …)
./scripts/bundle.sh        # builds build/XMonadMac.app
open build/XMonadMac.app
```

On first launch, macOS asks for **Accessibility** permission. Grant it in
System Settings → Privacy & Security → Accessibility. It starts managing
windows as soon as permission is granted.
By default the app is ad-hoc signed, and macOS ties the grant to the signature,
so every rebuild invalidates it. `bundle.sh` resets the stale entry for you, and
macOS asks again on the next launch. To keep the grant across rebuilds, sign
with a real certificate: `SIGN_IDENTITY="Apple Development: …" ./scripts/bundle.sh`.

**Quit Amethyst/yabai first**, since two tilers will fight each other. To start at
login, add `XMonadMac.app` under System Settings → General → Login Items.

### Recommended macOS settings

- Use **one Space per display** (remove the extra desktops in Mission Control).
- System Settings → Desktop & Dock → turn **off** "Automatically rearrange
  Spaces based on most recent use".
- Optional: turn off "When switching to an application, switch to a Space with
  open windows for the application".

## Keys

Default `mod` = **Option**, carried over from Amethyst (mod1 = Option,
mod2 = Option+Shift). On Swiss and other European layouts this means Option+digit
no longer types `# [ ] | { }`; set `mod: ctrl+alt` to keep them. skhd's
Option + q / Return / f / b stay free.

| Key | Action | From |
|---|---|---|
| `mod-1..9` | **greedyView**: bring workspace N here, swapping screens if needed | xmonad |
| `mod-shift-1..9` | send focused window to workspace N | Amethyst throw-space-N |
| `mod-shift-← / →` | send focused window to previous / next workspace | Amethyst throw-space-left/right |
| `mod-j / k` | focus next / previous window | Amethyst focus-cw/ccw |
| `mod-shift-j / k` | swap window down / up | Amethyst swap-cw/ccw |
| `mod-h / l` | shrink / expand master area (5 %) | Amethyst shrink/expand-main |
| `mod-shift-space` | next layout: Tall → Wide → Column → Full | Amethyst cycle-layout |
| `mod-,` | focus next screen | Amethyst focus-screen-cw |
| `mod-z` | re-scan windows and screens, then re-tile | Amethyst reevaluate-windows |
| `mod-shift-,` | send focused window to next screen | xmonad |
| `mod-m` / `mod-shift-m` | focus / swap with master | xmonad |
| `mod-t` | toggle floating | xmonad |
| `mod-shift-r` | restart XMonadMac (windows keep their workspaces) | |
| `mod-shift-q` | quit (restores all parked windows first) | xmonad |

Map keys to `view N` instead of `workspace N` for i3-style `W.view` (jump to the
other screen instead of swapping). More commands (`workspace-next`,
`focus-screen N`, `inc-master`, `spawn …`) are listed in the config file.

The menu bar icon (`menubar-icon: true`) has Restart, Reload Config, Edit Config,
Show Log, Re-tile and Quit.

## Configuration

Everything lives in `~/.config/xmonadmac/config.yaml`, written with all defaults
and comments on first launch. Saving the file applies it immediately (Restart in
the menu bar icon also works). If it has an error, the bar shows it and the previous settings
stay in effect. Example:

```yaml
mod: ctrl+alt
workspaces: [web, code, chat, 4, 5]
gap: 8
terminal: open -na Ghostty
keys:
  mod-1: workspace 1        # greedyView; use `view 1` for W.view
  mod-shift-1: shift 1
  cmd-shift-b: spawn open -a Safari
```

The `keys:` section replaces the default keymap as a whole; leave it out to keep
the defaults. Letter keys follow your keyboard layout.

## Bar

Each screen gets a second menu bar along the bottom, just above the Dock. It has the
same height, font and translucency as the one at the top, and tiled windows leave
room for it. Widgets:

| Widget | Shows | Click |
|---|---|---|
| `workspaces` | solid = active, outline = visible on a screen, dot = has windows, dim = empty | show it on this screen |
| `layout` | Tall / Wide / Column / Full | |
| `title` | focused window on that screen | |
| `network` | ↓ / ↑ throughput (Wi-Fi + Ethernet) | Activity Monitor |
| `cpu` | total CPU load | Activity Monitor |
| `memory` | memory used, like Activity Monitor | Activity Monitor |
| `date`, `clock` | `date-format` / `clock-format` | Calendar |

```yaml
bar:
  height: auto        # or a number
  left: [workspaces, layout, title]
  right: [network, cpu, memory, date, clock]
  hide-empty-workspaces: false
```

Right-click the bar → **Show in Bar** to switch widgets on and off; that rewrites
only the `left:` / `right:` lines of your config. The same menu has Reload Config,
Edit Config, Show Log, Re-tile and Quit. `bar: {enabled: false}` removes the bar.

Problems (missing Accessibility permission, config errors, hotkeys taken by
another app) appear in the bar in orange. The log is at
`~/Library/Logs/XMonadMac.log`.

## Known limitations (v0.1)

- Native fullscreen windows and minimized windows aren't managed. A window
  you un-minimize comes back on the current workspace.
- No mouse resizing of the master split. Dragging a tiled window gets undone
  on the next re-tile.
- Workspace state lives in memory. If the app crashes, windows stay parked
  in a corner. Relaunch it and they're adopted again, and `mod-shift-q` or Ctrl-C
  restores them properly.
- Apps that ignore Accessibility resize requests (some Electron apps, apps with
  a minimum size) may not fill their tile exactly.
