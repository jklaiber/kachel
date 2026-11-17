# Changelog

All notable changes to Kachel. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/). Each release's notes on GitHub are
taken from its section here.

## [Unreleased]

### Changed
- **Bar settings are grouped per widget**, in Settings → Bar and in config.yaml.
  The window lists each side's widgets in order, each with its options beneath
  it; right-click a widget to move it up, down or to the other side. In
  config.yaml, each widget's options sit in a block named after it
  (`workspaces:`, `title:`, `stats:`, `battery:`, `date:`, `clock:`). The old
  flat keys (`battery-percentage`, `date-format`, `clock-format`, `windows`,
  `windows-full-only`, `workspace-counts`, `hide-empty-workspaces`, `interval`)
  are no longer read: move them into the blocks, as in the default config.

### Fixed
- When an app moved or resized a tiled window by itself after it was tiled (e.g.
  iTerm sizing a tmux window to its session), the window stayed out of place
  until the next re-tile. Kachel now puts it back, a few times at most.

### Added
- **Battery widget** for the bar (`battery`): the battery level as an icon like
  the menu bar's, with or without the percentage (`bar.battery-percentage`, also
  in Settings → Bar). A bolt while plugged in, red when nearly empty; a click
  opens Battery settings. It's in the default bar; configs with their own
  `right:` list can add it from the bar's menu (Show in Bar → Battery).

## [0.1.14] - 2026-11-17

Six more layouts, a way to pause tiling, more control over spacing, and fixes for
Finder tabs and apps like Slack that bring a closed window back.

### Added
- **Six more layouts**: `tall-right`, `two-pane`, `rows`,
  `widescreen-tall`, `bsp` and `floating` (nothing tiled on that workspace).
- Commands **`layout NAME`** (straight to a layout), **`prev-layout`**,
  **`toggle-tiling`** (pause and resume tiling; the bar shows *Paused*),
  **`toggle-focus-follows-mouse`**, and **`increase-` / `decrease-window-limit`**.
- **`follow-moved-windows`**: sending a window to another workspace takes you
  there too. Off by default.
- **`smart-gaps`**: no gap or padding when a window is alone on its display.
- **`padding`**: space at the screen edges separate from `gap`, and
  `builtin-display-padding: false` for none on the MacBook's own display.
- **`window-limit`**: at most this many tiled windows per workspace; the others
  float.
- All of these in the settings window: General (Workspaces, Tiling, Layouts) and
  the command menus in Shortcuts and Trackpad.

### Changed
- Settings → App Rules: Float and Minimize are checkboxes next to their names.
  As switches side by side, it wasn't clear which switch belonged to which.
- Settings: text fields also apply when you leave them (a click elsewhere, Tab,
  another pane), not only on Return; before, a change without Return was lost.
- Settings → General: the shortcut overview slider shows its delay; the layouts
  that Next layout cycles through have their own group; pinning workspaces to
  displays folds away when there's only one display. Trackpad feedback moved to
  the Trackpad pane.

### Fixed
- Apps that hide a window when you close it and bring it back later (Slack,
  Telegram) hand out a new handle for it; Kachel kept the old one and stopped
  arranging the window. It now picks up the new one.
- Switching or closing native tabs (Finder, Terminal, TextEdit) shuffled the
  layout: macOS shows each tab as its own window, so the tab that appeared was
  treated as a new window. It now takes the previous tab's place.
- Windows that can't be moved are left alone instead of being tiled.
- A new window that briefly lacked its fullscreen button (some Electron apps)
  could be floated as a dialog for good. Kachel looks again shortly after and
  tiles it if it's a normal window.

## [0.1.13] - 2026-11-17

Every Teams meeting works like on Spaces, whatever it's called, and Outlook's
meeting reminder floats like it does without Kachel.

### Added
- App rules: `title-not` leaves out windows whose title contains one of the
  given texts. With it, one rule covers **every Teams meeting window**, whatever
  the meeting is called: Teams windows except the main one. Also a field in
  Settings → App Rules.

### Changed
- The default config includes the Teams rule: every Teams meeting window is
  minimized while its workspace is out of sight, so Teams shows its small call
  window. Configs that already list their own `rules:` keep them as they are.

### Fixed
- Windows an app keeps above other windows on its own, like Outlook's meeting
  reminder, are left alone, as in Amethyst: not tiled, not part of ⌥J / ⌥K, and
  not hidden when you switch workspaces. The app decides where they go.
- A dialog an app opened on another display joined the workspace you were on,
  so ⌥J / ⌥K jumped across displays to it. It now belongs to the workspace shown
  on the display where it appears.

## [0.1.12] - 2026-11-16

In the Full layout the bar shows the workspace's other windows as tabs, and every
app rule can be edited in Settings.

### Added
- **The windows of the workspace you're on, in the bar**: as tabs with their
  names (click one to switch to it), as dots, or as a position like `Full 2/4`.
  By default as tabs, and only in the Full layout, where the other windows are
  hidden (`bar.windows`, `bar.windows-full-only`).
- **Window count on each workspace** in the bar (`bar.workspace-counts`).
- Settings → Bar: these choices, with a live preview of the bar.
- Welcome and setup check: **Hide the Dock automatically**, recommended when the
  Dock is at the bottom, so the bar gets the bottom edge to itself. One click
  turns it on.

### Changed
- Settings → App Rules edits every rule, including ones with a window title
  (like the Teams meeting rule): a *Window title contains* field for each rule,
  and an explanation of what Workspace, Float and Minimize do. Comments on rules
  in config.yaml are kept.
- Updated Yams, the library that reads config.yaml, to 6.2.

### Fixed
- Changing a setting in the settings window sent the window to the back: the
  config reload gave focus to the current workspace's window. Kachel's own
  windows now stay in front.
- After granting Accessibility from the welcome window, it went behind other
  windows. It now comes back to the front with the next checks, also when you
  close System Settings.

## [0.1.11] - 2026-11-16

The bar's text is readable again with a wallpaper from Downloads, and Kachel
now shows its version.

### Added
- **Version information**: *About Kachel* in the bar's menu (the standard macOS
  About window), the version in Settings → General, `Kachel --version`, and the
  version at every start in the log.

### Changed
- Upgrade instructions say `brew update && brew upgrade --cask kachel`: without
  `brew update`, Homebrew may not see a new release for up to a day.

### Fixed
- Since 0.1.10, with a wallpaper in Downloads, Desktop, Documents or iCloud
  Drive, the bar's text followed light/dark mode and could be black on a dark
  wallpaper. It now takes the colour macOS uses for the menu bar, which follows
  the wallpaper, still without reading the file.

## [0.1.10] - 2026-11-16

Teams meetings work like they do with Spaces, the settings window covers the
bar's update interval, and Kachel is now MIT licensed.

### Added
- **Call windows like on Spaces**: a rule with `hide: minimize` minimizes a
  window while its workspace is out of sight and restores it when you come back.
  Microsoft Teams then shows its small call window on every workspace, as it
  does with Spaces, and clicking it takes you back to the meeting. Zoom and
  Webex have similar mini windows (not tested yet). Also the **Minimize** switch in
  Settings → App Rules.
- MIT licence, contributing guide, security policy and code of conduct; issue
  forms for bugs and feature requests, and Discussions for questions.
- Settings → Bar: how often CPU, memory and network update (`bar.interval`).

### Fixed
- On a fresh install the welcome window didn't appear: it opened before the app
  had finished launching, under macOS's Accessibility dialog. It now opens first,
  with the macOS dialog on top.
- With a wallpaper saved in Downloads, Desktop, Documents, iCloud Drive or on an
  external drive, macOS asked to let Kachel access that folder (the bar reads the
  wallpaper to choose white or black text). The bar now follows light or dark
  mode for those instead.
- On French and Belgian (AZERTY) keyboards, `mod-1` … `mod-9` didn't work: the
  number row types `& é " …` there, so the shortcuts landed on the numeric
  keypad. Digits now always mean the number row, and the shortcut recorder
  records it as 1–9.

## [0.1.9] - 2026-11-15

Apps that always float are now app rules, so the settings window shows and
edits them.

### Changed
- Apps that always float are now ordinary app rules with `float: true`, so the
  settings window shows and edits them. The default config lists System
  Settings, Calculator and Archive Utility under `rules:`.

### Removed
- The `floating:` list. Move its apps to `rules:` as `- app: <bundle ID>` with
  `float: true`; Kachel reports `floating` as an unknown setting.

## [0.1.8] - 2026-11-15

Kachel now has a documentation website, and focus comes back after unlocking
the Mac.

### Added
- **Documentation website** at [jklaiber.github.io/kachel](https://jklaiber.github.io/kachel/):
  getting started, a guide for people coming from xmonad, Amethyst and
  AeroSpace, every feature, the full configuration reference and
  troubleshooting. The README is now a short overview.

### Fixed
- After locking and unlocking the Mac, no window had focus, and switching
  workspaces didn't focus one either. Window tracking now pauses while the
  screen is locked, and focus returns to the window you used last (else the
  master).

## [0.1.7] - 2026-11-15

The settings window now covers everything without a detour through the file:
commands are picked from menus, scratchpads are edited in place, taken keys are
flagged, and changes can be undone.

### Added
- Settings: **command picker**. Shortcuts and swipes are chosen from menus
  (grouped, with submenus for workspaces, directions, displays and scratchpads)
  instead of typed; shell commands get a text field.
- Settings: **scratchpad editor**. Add, rename, remove and change scratchpads,
  with their key; "take app and title from the focused window" fills in the
  details. Renaming or removing also updates the keys and swipes that use it.
- Settings: **key conflict warnings** before taking a combination that another
  Kachel shortcut, macOS (Keyboard Shortcuts settings) or skhd already uses.
  `Kachel --list-taken-keys` prints them.
- Settings: **undo and redo** (⌘Z / ⇧⌘Z) for changes made in the window.

### Fixed
- A scratchpad with a `title` could take another window of the same app when it
  started (e.g. TextEdit reopening other documents). Only the matching window counts now.

## [0.1.6] - 2026-11-15

Kachel feels more like part of macOS: a settings window, a welcome window that
checks your setup, a shortcut overview, Liquid Glass and trackpad feedback.

### Added
- **Settings window** in the style of System Settings: General, Bar, Focus
  Border, Trackpad, Shortcuts (with a key recorder) and App Rules. Changes are
  written into `config.yaml` with its comments kept and apply at once; a change
  that wouldn't load is rolled back.
- **Welcome window** on first launch: Accessibility, then a check of the macOS
  settings that matter (Spaces, Mission Control, macOS tiling, Stage Manager,
  other window managers, trackpad swipes) with a fix for each.
- **Shortcut overview**: hold `mod` alone (`shortcut-overview`, 0.8 s) to see
  every shortcut grouped on glass.
- **Liquid Glass** for window search, the app rule picker and the new windows on
  macOS 26.
- **Trackpad feedback** (`haptics`) when a swipe triggers or a window snaps in.
- Commands `settings`, `welcome` and `shortcuts`.

## [0.1.5] - 2026-11-15

New windows no longer take over the master spot, the stack's heights move to
`mod-shift-h` / `mod-shift-l`, and focus stays on the right display when a
window closes.

### Added
- `new-windows: end | below | above | master` decides where a new window goes.
  The default is `end`: it joins the bottom of the stack, like in Amethyst.
  `above` is xmonad's behaviour, where a new window next to the focused master
  becomes the master.
- [`config.example.yaml`](config.example.yaml): the complete default config with
  every option explained. `Kachel --print-default-config` prints it, for
  example to `diff` your config after an upgrade.

### Changed
- `taller` / `shorter` (the focused window's height in its column) moved from
  `mod-shift-a` / `mod-a` to `mod-shift-l` / `mod-shift-h`, next to `mod-l` /
  `mod-h` for the master. Existing configs keep their own keys.
- Comments in the default config no longer refer to one particular
  Amethyst/skhd setup.

### Fixed
- Closing a window on one display moved focus to a window on the other display
  (whatever macOS activated next). Focus now stays on the display of the closed
  window, on the window you used last there.

## [0.1.4] - 2026-11-14

### Fixed
- Closing a window of an app that keeps running with its window hidden
  (Calendar, Claude, …) didn't re-tile the remaining windows.
- `mod-j` / `mod-k` and the swaps could land on such a hidden window, a
  put-away scratchpad or a minimized window, and focus seemed to vanish. They
  now skip windows that aren't on screen.

## [0.1.3] - 2026-11-14

### Added
- **Scratchpads** (xmonad's NamedScratchpad): one key shows a floating window
  over any workspace and puts it away again, starting the app if needed.
  Default: a terminal on `mod-s`.
- **Toggle fullscreen** (`mod-shift-f`): Full layout until pressed again.
- **Focus border**: a frame around the focused window, in your accent colour or
  any colour, matching each window's corner radius.
- **Directional focus and swap** (`ctrl-alt-arrows`, with `shift` to swap),
  across displays too. `mod-j` / `mod-k` keep cycling.
- **Back and forth** (`mod-tab`) between the last two workspaces of a display,
  and an optional `workspace-back-and-forth`.
- **Resizable windows in a column** (xmonad's ResizableTall): `taller` /
  `shorter`, or drag a window's top or bottom edge; `reset-sizes` evens them out.
- **Three-column layout**: master in the middle, stacks on both sides.
- **Pinned workspaces** (`workspace-screens`): a workspace always opens on a
  given display (`main`, `external`, `builtin`, a number or part of its name).
- `focus-follows-mouse`, and `mouse-follows-focus: window | screen | off`.
- README images, drawn by Kachel itself with made-up windows
  (`scripts/screenshots.sh`).

### Fixed
- `mod-m` / `mod-shift-m` could pick a floating dialog as the master.
- Windows wider than their tile (minimum width) could hang off the screen.
- Hiding a scratchpad now gives focus back to the window you used before it.

## [0.1.2] - 2026-11-14

### Added
- **Mouse**: drag a tiled window onto another to swap them, also across
  displays; drop it on an empty part of another display to move it there.
- **Crash safety**: if Kachel crashes, it first puts parked windows back on
  screen; the workspace state is saved after every change and restored on the
  next start.
- Dialogs (windows without a fullscreen button) float automatically;
  optional `float-small-windows`.
- `start-at-login`.
- `mod-.` / `mod-shift-.`: focus / send a window to the previous display.
- Windows with a minimum size get the room they need in a stack instead of
  overlapping; if nothing fits, they overlap evenly within the screen.

### Fixed
- After the Mac slept with the lid closed, every window ended up on workspace 1.
- Apps that ignore the first resize (some Electron apps) are asked again.

## [0.1.1] - 2026-11-14

### Fixed
- Trackpad swipes went the wrong way with "Natural scrolling" turned off. The
  new `gestures.direction: auto` follows the macOS setting, like Spaces do.

## [0.1.0] - 2026-11-14

First release.

### Added
- xmonad's workspace model on macOS: 9 workspaces shared by all displays,
  `greedyView` swaps displays, windows of hidden workspaces parked in a corner
  instead of using macOS Spaces.
- Layouts Tall, Wide, Column and Full; master ratio and count; gaps.
- A second menu bar at the bottom of every display: clickable workspaces,
  layout, window title, CPU, memory, network, date and clock.
- Window search (`mod-p`) and app rules with a picker (`mod-shift-p`).
- Trackpad swipes between workspaces.
- Moving the master split with the mouse.
- Configuration in `~/.config/kachel/config.yaml`, applied on save.
- Homebrew: `brew install --cask jklaiber/tap/kachel`.

[Unreleased]: https://github.com/jklaiber/kachel/compare/v0.1.14...HEAD
[0.1.14]: https://github.com/jklaiber/kachel/compare/v0.1.13...v0.1.14
[0.1.13]: https://github.com/jklaiber/kachel/compare/v0.1.12...v0.1.13
[0.1.12]: https://github.com/jklaiber/kachel/compare/v0.1.11...v0.1.12
[0.1.11]: https://github.com/jklaiber/kachel/compare/v0.1.10...v0.1.11
[0.1.10]: https://github.com/jklaiber/kachel/compare/v0.1.9...v0.1.10
[0.1.9]: https://github.com/jklaiber/kachel/compare/v0.1.8...v0.1.9
[0.1.8]: https://github.com/jklaiber/kachel/compare/v0.1.7...v0.1.8
[0.1.7]: https://github.com/jklaiber/kachel/compare/v0.1.6...v0.1.7
[0.1.6]: https://github.com/jklaiber/kachel/compare/v0.1.5...v0.1.6
[0.1.5]: https://github.com/jklaiber/kachel/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/jklaiber/kachel/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/jklaiber/kachel/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/jklaiber/kachel/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/jklaiber/kachel/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/jklaiber/kachel/releases/tag/v0.1.0
