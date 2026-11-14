<p align="center"><img src="assets/icon.svg" width="128" alt="Kachel icon: a green tiled stove"></p>

# Kachel

*Kachel* is German for tile, as in a *Kachelofen*, the tiled stove in the icon:
nine glazed tiles for nine workspaces.

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

macOS Spaces can't be scripted reliably without disabling SIP, so Kachel
doesn't use them. All windows live on one Space per display. Windows of hidden
workspaces are parked in a screen corner with one pixel showing (the same
approach AeroSpace uses). Switching is instant and workspaces can move freely
between monitors.

```
Sources/KachelCore/StackSet.swift   pure model: workspaces, screens, greedyView, shift, …
Sources/KachelCore/Layout.swift     Tall, Wide, Column, Full
Sources/KachelCore/Settings.swift   config.yaml parsing + the default config
Sources/Kachel/Config.swift      loads ~/.config/kachel/config.yaml, reloads on save
Sources/Kachel/WindowManager.swift  Accessibility API glue, tracking, rendering
Sources/Kachel/AX.swift          AXUIElement helpers, screens
Sources/Kachel/HotKeys.swift     global hotkeys (Carbon RegisterEventHotKey)
Sources/Kachel/Bar.swift         xmobar-like bar at the bottom of every screen
```

## Install

```bash
brew install --cask jklaiber/tap/kachel
```

Then grant Accessibility (System Settings → Privacy & Security → Accessibility)
and quit Amethyst, yabai or AeroSpace if they're running. Releases are ad-hoc
signed, so macOS asks for Accessibility again after each upgrade. If macOS still
refuses to open the app, install with `--no-quarantine`.

## Build and run

Requires macOS 13+ and the Xcode Command Line Tools (`xcode-select --install`).

```sh
swift test                 # model tests (greedyView, shift, layouts, …)
./scripts/bundle.sh        # builds build/Kachel.app
open build/Kachel.app
```

On first launch, macOS asks for **Accessibility** permission. Grant it in
System Settings → Privacy & Security → Accessibility. It starts managing
windows as soon as permission is granted.
By default the app is ad-hoc signed, and macOS ties the grant to the signature,
so every rebuild invalidates it. `bundle.sh` resets the stale entry for you, and
macOS asks again on the next launch. To keep the grant across rebuilds, sign
with a real certificate: `SIGN_IDENTITY="Apple Development: …" ./scripts/bundle.sh`.

**Quit Amethyst/yabai first**, since two tilers will fight each other. To start at
login, add `Kachel.app` under System Settings → General → Login Items.

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
| `mod-shift-space` | next layout: Tall → Wide → Three-column → Column → Full | Amethyst cycle-layout |
| `mod-,` / `mod-.` | focus next / previous screen | Amethyst focus-screen-cw, xmonad |
| `mod-z` | re-scan windows and screens, then re-tile | Amethyst reevaluate-windows |
| `mod-shift-,` / `mod-shift-.` | send focused window to next / previous screen | xmonad |
| `mod-p` | **window search**: type to find any open window; ↩ go there, ⇧↩ bring it here | xmonad Prompt.Window / dmenu |
| `mod-tab` | **back and forth** to the workspace this screen showed before | xmonad toggleWS |
| `mod-a` / `mod-shift-a` | make the focused window shorter / taller in its column | xmonad ResizableTall |
| `mod-s` | **scratchpad**: show/hide a floating terminal over any workspace (see `scratchpads:`) | xmonad NamedScratchpad |
| `mod-shift-f` | toggle fullscreen: show the workspace in Full until pressed again | xmonad ToggleLayouts |
| `ctrl-alt-←/→/↑/↓` | focus the window in that direction, also across screens | xmonad Navigation2D, AeroSpace |
| `ctrl-alt-shift-←/→/↑/↓` | swap with the window in that direction | |
| `mod-shift-p` | **app rule**: always open the focused app on workspace N (1–9), F float, ⌫ remove; saved under `rules:` | xmonad manageHook |
| `mod-m` / `mod-shift-m` | focus / swap with master | xmonad |
| `mod-t` | toggle floating | xmonad |
| `mod-shift-r` | restart Kachel (windows keep their workspaces) | |
| `mod-shift-q` | quit (restores all parked windows first) | xmonad |

Map keys to `view N` instead of `workspace N` for i3-style `W.view` (jump to the
other screen instead of swapping). More commands (`workspace-next`,
`focus-screen N`, `inc-master`, `spawn …`) are listed in the config file.

The menu bar icon (off by default; `menubar-icon: true` or right-click the bar → Show in Bar → Icon in Top Menu Bar) has Restart, Reload Config, Edit Config,
Show Log, Re-tile and Quit.

## Configuration

Everything lives in `~/.config/kachel/config.yaml`, written with all defaults
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
`~/Library/Logs/Kachel.log`.

## Trackpad gestures

Swipe with three fingers (or four, `gestures.fingers`) to switch workspaces on
the screen under the pointer: left for the next one, right for the previous one,
like macOS Spaces. Swipes skip empty workspaces and the ones already shown on
another screen (`skip-empty`, like xmonad's `CycleWS` with `HiddenNonEmptyWS`).
Any command can go on a swipe, up and down included.

Turn macOS's own swipe off first: System Settings → Trackpad → More Gestures →
"Swipe between full-screen applications" → Off.

Kachel reads the trackpad through Apple's private `MultitouchSupport`
framework, as BetterTouchTool and similar tools do. If a macOS update breaks
it, swipes stop working and everything else keeps going. The switch is instant;
there's no sliding animation.

## Scratchpads

A scratchpad is a window you summon with one key: it floats over whatever
workspace you're on, and the same key puts it away again. If it isn't open,
Kachel starts it. The default is a terminal:

```yaml
scratchpads:
  - name: term
    app: org.alacritty                  # bundle ID or app name
    title: scratchpad                   # optional: only windows with this in the title
    run: open -na Alacritty --args --title scratchpad -o window.dynamic_title=false
    size: [0.6, 0.55]                   # share of the screen
    position: center                    # or top, like a drop-down terminal
  - name: notes
    app: com.apple.Notes
    run: open -a Notes
keys:
  mod-s: scratchpad term
  mod-n: scratchpad notes
```

## Focus border

A frame in your accent colour around the focused window. `border:` sets
`width`, `color` (`accent` or `"#RRGGBB"`), `radius` (match your windows'
corners) and `smart` (no frame when a window is alone on its screen).

## Mouse

- Drag the edge between master and stack (Tall, Wide, Three-column) to move the split.
- Drag the top or bottom edge of a window in a column to make it taller or
  shorter; the others make room (xmonad's ResizableTall). `reset-sizes`
  evens everything out again.
- Drag a tiled window by its title bar onto another one to swap them, also
  across screens (Amethyst's `mouse-swaps-windows`). Drop it on an empty part
  of another screen to move it there. Anything else snaps back.
- `focus-follows-mouse: true`: the window under the pointer gets focus when
  the pointer rests on it.
- `mouse-follows-focus: window`: when focus moves by keyboard, the pointer
  jumps to the focused window's centre (`screen`: only between screens; `off`).

## Workspaces on fixed screens

```yaml
workspace-screens:
  "8": external      # main, external, builtin, 1…n (left to right), or part of the display's name
  "9": DELL
```

A pinned workspace always shows on its screen while that screen is connected:
`mod-8` brings it up there and moves focus over. Without that screen, it
behaves like any other workspace. Swipes skip workspaces pinned to another
screen.

## Tips for the corner trick

Like AeroSpace, Kachel hides the windows of other workspaces in a screen corner
with one pixel showing. Some macOS settings make that nicer:

- Mission Control shows parked windows tiny. Turn on "Group windows by
  application": `defaults write com.apple.dock expose-group-apps -bool true && killall Dock`
- Every monitor needs a free bottom-left or bottom-right corner, or parked
  windows peek onto the neighbouring monitor. Arrange displays accordingly.
- An auto-hiding Dock at the bottom covers the one-pixel slivers.
- Turn off "Automatically rearrange Spaces based on most recent use" and use
  one Space per display.

## Known limitations

- Native fullscreen and minimized windows aren't tiled. They keep their
  workspace and come back there.
- Apps with a minimum size (some Electron apps) can't shrink into a small tile.
  Kachel asks twice, then leaves them; the log names them.
- If Kachel crashes, it first puts parked windows back on screen. The next
  start restores every window's workspace from the state it saves after each
  change.
