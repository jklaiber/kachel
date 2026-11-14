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
Sources/XMonadCore/Layout.swift     Tall, Mirror Tall, Full
Sources/XMonadMac/Config.swift      ← your xmonad.hs: keys, mod, gaps, terminal, float rules
Sources/XMonadMac/WindowManager.swift  Accessibility API glue, tracking, rendering
Sources/XMonadMac/AX.swift          AXUIElement helpers, screens
Sources/XMonadMac/HotKeys.swift     global hotkeys (Carbon RegisterEventHotKey)
Sources/XMonadMac/StatusBar.swift   xmobar-ish menu bar item:  [1] <2> 5  Tall
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

Default `mod` = **Ctrl+Option**. Plain Option isn't the default because on Swiss and
other European layouts Option+digit types `| @ # [ ]`. Change it in `Config.swift`.

| Key | Action (xmonad equivalent) |
|---|---|
| `mod-1..9` | **greedyView**: bring workspace N here, swapping screens if needed |
| `mod-shift-1..9` | send focused window to workspace N (`W.shift`) |
| `mod-w / e / r` | focus screen 1 / 2 / 3 (left to right) |
| `mod-shift-w / e / r` | send window to the workspace on screen 1 / 2 / 3 |
| `mod-j / k`, `mod-tab` | focus next / previous window |
| `mod-m` | focus master |
| `mod-shift-j / k` | swap window down / up |
| `mod-return` | swap focused with master |
| `mod-h / l` | shrink / expand master area |
| `mod-, / .` | more / fewer windows in master |
| `mod-space` | next layout (Tall → Mirror → Full) |
| `mod-t` | toggle floating (sink) |
| `mod-n` | re-scan windows and screens, then re-tile |
| `mod-shift-return` | launch terminal |
| `mod-shift-c` | close focused window |
| `mod-shift-q` | quit (restores all parked windows first) |

If you prefer i3-style `W.view` (jump to the other screen instead of swapping),
change `wm.greedyView(i)` to `wm.view(i)` in `Config.swift`.

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
