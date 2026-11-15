# Changelog

All notable changes to Kachel. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/). Each release's notes on GitHub are
taken from its section here.

## [Unreleased]

### Added
- MIT licence, contributing guide, security policy and code of conduct; issue
  forms for bugs and feature requests, and Discussions for questions.

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

[Unreleased]: https://github.com/jklaiber/kachel/compare/v0.1.9...HEAD
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
