# Changelog

All notable changes to Kachel. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/). Each release's notes on GitHub are
taken from its section here.

## [Unreleased]

### Added
- `kachel subscribe` prints a line of JSON for every change: the workspace,
  the focused window and its title, a workspace's layout, its windows. Other
  bars (SketchyBar) and scripts can follow along instead of asking every
  second. `kachel subscribe workspace focus` for only some of them.

### Changed
- Less work while you're not doing anything: the clock wakes Kachel once a
  minute instead of every second (unless it shows seconds), and the bar
  redraws in about a quarter of the time.

## [0.1.27] - 2026-11-27

The layout as a picture in the bar.

### Changed
- The bar shows the layout as a small picture instead of its name: Tall as
  a big window and three small ones, and so on, two-pane turned on a portrait
  display. **Settings → Bar → Layout** (or `bar: layout: {show: name}`) brings
  the name back.

## [0.1.26] - 2026-11-27

Two-pane on a portrait display.

### Changed
- Two-pane follows the shape of the display: on a display turned to portrait,
  the master is on top and the second pane below it, with the other windows
  waiting behind that pane. Resizing the master (keys or mouse) changes its
  height there.

## [0.1.25] - 2026-11-26

Much lighter on CPU and memory while you work.

### Changed
- Kachel uses much less CPU and memory: under 1 % CPU while idle instead of
  3 %, and about 35 MB of memory instead of 200 MB.
  - The bar redraws only when what it shows changes (the clock, once a minute).
  - The focus border is drawn as a layer, not as a picture the size of the
    window.
  - The 2-second check for new and closed windows asks every app only when
    the window server's list changed, or every 10 seconds; before, it woke up
    every app every time.
  - A focus change no longer sends every window on the workspace its place
    again: only windows that move get a request, so their apps stay asleep.
  - Badge icons in the bar are drawn once into a small picture.
  - Timers leave macOS some slack to run them together with other work.

## [0.1.24] - 2026-11-26

An About page in Settings, update checks every hour and from the menus, and
focus fixes.

### Added
- **Settings → About**: version and updates (with **Check Now**), links to the
  documentation, the changelog and to report a problem, and where your config
  and log are. **About Kachel** in the menus opens it; the update setting moved
  there from General.
- **Check for Updates…** in the menu bar icon's and the bar's menus: looks
  right away and always answers, also when you're up to date.

### Changed
- The update check looks once an hour instead of once a day, and after your
  Mac wakes. It asks GitHub whether anything changed since its last answer,
  so "nothing new" is a short, empty answer.

### Fixed
- Settings (and Kachel's other windows) open on the first try from the menu bar
  icon or the bar's menu, instead of behind the app you're in.
- A window restored from minimized (Teams with `hide: minimize`) no longer
  takes focus back when you move on with a Kachel shortcut right after (#17).

## [0.1.23] - 2026-11-26

A fix for switching workspaces from an empty display.

### Fixed

- From an empty workspace, the key for a workspace shown on the other display
  brings it here (swapping the displays) instead of only moving focus to that
  display. macOS keeps the other display's window in front, and Kachel took
  that for a wish to go there (#16).

## [0.1.22] - 2026-11-26

Unread counts and your own widgets in the bar, `send-key`, settings that
explain themselves, and fixes for empty workspaces, the focus border and
secure input.

### Added
- Settings explain themselves: the settings that aren't obvious (focus and
  pointer, workspaces, tiling, swipes, call rules, scratchpads) have a line of
  explanation under them, and the trickier ones an ⓘ with an example and a
  link to the docs.
- `send-key cmd-w`: a shortcut presses a key combination in the front app, like
  `skhd --key`, with exactly the modifiers given, so the Option you hold for the
  shortcut doesn't get in ([#11](https://github.com/jklaiber/kachel/issues/11)).
  Also in Settings → Shortcuts.
- `badges` in the bar: unread counts from the Dock icons (Slack, Mail,
  Outlook, …) with the app's icon, only while there's a number
  ([#14](https://github.com/jklaiber/kachel/issues/14)). New in the default bar.
- Your own bar widgets: the first line of a shell command, every few seconds,
  with an optional icon and click command (`bar.widgets`, or Settings → Bar →
  Your Widgets) ([#14](https://github.com/jklaiber/kachel/issues/14)).

### Fixed
- Switching to an empty workspace could bounce back to the previous one a
  moment later, because the app left in front kept focus and Kachel followed
  it ([#15](https://github.com/jklaiber/kachel/issues/15)). Kachel takes focus
  on an empty workspace forcefully again (0.1.21 had made it a request macOS can
  ignore), and doesn't follow focus back to the workspace you just left unless
  you clicked or typed.
- The focus border could still end up behind a window after clicking it while it
  was already focused: clicks now check it too
  ([#13](https://github.com/jklaiber/kachel/issues/13)).
- With a one-sided `mod` (`left-alt`), shortcuts stopped working without a word
  when an app turned on secure input (Terminal's Secure Keyboard Entry, password
  prompts): the bar and the log now say so and name the app
  ([#12](https://github.com/jklaiber/kachel/issues/12)).

## [0.1.21] - 2026-11-24

Kachel now requires macOS 26 (Tahoe). Restored meeting windows keep focus, the
focus border stays on top, and a workspace can follow focus to the display it
was last on.

### Added
- `follow-focus-screen: last`: when a window on a hidden workspace gets focus
  (a link opens in it, ⌘Tab, the Dock), its workspace shows up on the display
  it was last on, and yours keeps its workspace
  ([#10](https://github.com/jklaiber/kachel/issues/10)). Also in Settings →
  General → Workspaces; the default stays as before.

### Changed
- Kachel now requires **macOS 26 (Tahoe)**: it's built around Liquid Glass, and
  only what CI can test is supported. Homebrew keeps older Macs on 0.1.20.
- An unknown setting in `config.yaml` (a typo, or a setting from a newer Kachel)
  no longer stops the whole file from loading: it's ignored, with a note in the
  bar and at the top of Settings, and a suggestion when it looks like a typo
  ("unknown setting 'gapp' ignored (did you mean 'gap'?)"). Values that don't
  fit are still errors.

### Fixed
- A window restored from minimized (`hide: minimize`, e.g. a Teams meeting) could
  end up behind another app when its workspace came back: Kachel now checks
  that it stays in front and focuses it again unless you clicked or typed
  meanwhile ([#8](https://github.com/jklaiber/kachel/issues/8)).
- The focus border could end up behind the focused window when the app brought
  its window forward after Kachel placed the frame: it's put back on top of it
  shortly after every focus change ([#9](https://github.com/jklaiber/kachel/issues/9)).
- A scratchpad whose window didn't match its `app` / `title` started its app
  again on every key press, with nothing saying why
  ([#7](https://github.com/jklaiber/kachel/issues/7)). Now it isn't started
  again while it's starting (15 s), the bar says when no matching window
  appeared (and when the app's window is there but its title doesn't fit), and
  a failing `run` command is reported. The docs explain that `run` is a shell
  command and how `title` matches.

## [0.1.20] - 2026-11-21

Workspaces come back after a restart of the Mac, a hung app can't freeze Kachel
any more, and every workspace can start with its own layout.

### Added
- Workspaces survive a restart of the Mac: windows go back to the workspace
  they were on, recognised by app and title (also when the title changed a
  bit, like "— Edited"; an app's windows whose titles changed go where that
  app's windows were). Layouts and sizes of the workspaces come back too.
  Titles are only stored as hashes.
- A starting layout per workspace: `workspace-layouts: {"1": full}`, or in
  Settings → General → Workspaces → Starting layout per workspace. It applies
  when Kachel starts and as soon as you change it; the keys still switch layouts.
- `kachel settings` opens the settings.
- The log says more, so a problem can be traced from it: size and position of
  new, closed and returning windows and why a window floats, every display
  (name, size, position) when displays change, windows Accessibility stops
  listing, and focus changes macOS makes.

### Changed
- A hung app no longer freezes Kachel: every app gets its own queue for what
  Kachel asks of it, an app that doesn't answer is noticed and not waited for,
  and once it answers again its windows are put in place once more.
  Switching to a workspace with a frozen app took up to 7.5 s, now under 0.1 s.
- The log no longer contains window titles or your user name: a title is
  written as a tag (`title #3fa2 (23 chars)`), your home folder as `~`, and the
  wallpaper's file name is left out. `kachel dump` follows the same rules.

## [0.1.19] - 2026-11-21

Plugging displays in and out keeps your workspaces where they were, and
Kachel's window handling is now covered by tests.

### Changed
- The window manager is split into parts and talks to macOS through one
  interface, so it can be tested: a new test suite drives it with made-up
  windows and displays (tab switches, windows coming back, locked screen,
  Teams meetings on two displays). No change in behaviour.

### Fixed
- Unplugging a display to the left of another made the remaining one switch
  workspaces, hiding what you were looking at. Displays are now recognised by
  name: the ones that stay keep their workspace.
- A display plugged back in gets its workspace back (the one it showed before,
  or the one pinned to it with `workspace-screens`) instead of a random free one.
- Several windows appearing at once (an app restoring its windows) were tiled
  in random order; now in the order they were opened.
- A native tab switch right after the window first appeared could put the new
  tab at the end of the stack instead of in the old tab's place.

## [0.1.18] - 2026-11-21

Crash recovery, the `kachel` command, an update notice, and upgrades keep the
Accessibility permission from now on.

### Added
- The `kachel` command (installed by Homebrew): run any command from the
  config (`kachel workspace 3`) and ask where things are as JSON
  (`kachel query windows`, `workspaces`, `screens`, `focused`). See
  [Command line](https://jklaiber.github.io/kachel/command-line/).
- If Kachel crashes or is force-quit, a helper puts windows from hidden
  workspaces back on screen, unminimizes the ones Kachel minimized, and starts
  Kachel again.
- After a crash, Kachel offers to report it: a GitHub issue with the crash
  details filled in, for you to look over and send.
- Update notice: once a day Kachel looks up the latest release on GitHub, and
  the menu shows when a newer one is out. Turn it off with
  `check-for-updates: false` or in Settings → General.

### Changed
- Releases are signed with Kachel's own certificate, the same every time, so
  macOS keeps the Accessibility permission on upgrade. Upgrading to this
  version asks one last time.

### Removed
- `scripts/kachel-ctl` no longer sends commands as a system-wide notification
  that any app could post; it's now a wrapper around the `kachel` command.

### Fixed
- `brew upgrade` (and logging out) left windows of hidden workspaces parked in
  a corner: quitting from outside now puts them back like ⌥⇧Q does.

## [0.1.17] - 2026-11-19

The bar makes way for the Dock, and mod can be only the left Option key.

### Added
- The bar makes way for the Dock: when a hidden Dock slides up at the bottom,
  the bar fades out on that screen and comes back once the Dock hides again.
  On by default; turn it off with `bar.make-way-for-dock: false` or in
  Settings → Bar.
- `mod: left-alt`: only the left Option key is Kachel's modifier, and the
  right one stays free for typing (ü, @, [ … on Swiss and German layouts).
  `left-` and `right-` work with every modifier; Settings → General →
  Which keys sets the same.

## [0.1.16] - 2026-11-17

Fixes a crash after using Settings → Bar, and widgets can be dragged into order.

### Changed
- Settings → Bar: drag a widget by its grip to reorder it, also to the other
  side, as in other macOS lists. Right-click still offers Move Up / Down.

### Fixed
- Kachel could crash when the battery level changed after Settings → Bar had
  been open: every redraw of the bar preview left a battery watcher behind that
  macOS then called after it was gone. Previews no longer watch the battery, and
  a watcher unregisters when it goes away.

## [0.1.15] - 2026-11-17

A battery widget, bar settings grouped per widget, and windows that apps move
after tiling are put back.

### Added
- **Battery widget** for the bar (`battery`): the battery level as an icon like
  the menu bar's, with or without the percentage (`bar:` → `battery:` →
  `percentage:`, also in Settings → Bar). A bolt while plugged in, red when nearly empty; a click
  opens Battery settings. It's in the default bar; configs with their own
  `right:` list can add it from the bar's menu (Show in Bar → Battery).

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

[Unreleased]: https://github.com/jklaiber/kachel/compare/v0.1.27...HEAD
[0.1.27]: https://github.com/jklaiber/kachel/compare/v0.1.26...v0.1.27
[0.1.26]: https://github.com/jklaiber/kachel/compare/v0.1.25...v0.1.26
[0.1.25]: https://github.com/jklaiber/kachel/compare/v0.1.24...v0.1.25
[0.1.24]: https://github.com/jklaiber/kachel/compare/v0.1.23...v0.1.24
[0.1.23]: https://github.com/jklaiber/kachel/compare/v0.1.22...v0.1.23
[0.1.22]: https://github.com/jklaiber/kachel/compare/v0.1.21...v0.1.22
[0.1.21]: https://github.com/jklaiber/kachel/compare/v0.1.20...v0.1.21
[0.1.20]: https://github.com/jklaiber/kachel/compare/v0.1.19...v0.1.20
[0.1.19]: https://github.com/jklaiber/kachel/compare/v0.1.18...v0.1.19
[0.1.18]: https://github.com/jklaiber/kachel/compare/v0.1.17...v0.1.18
[0.1.17]: https://github.com/jklaiber/kachel/compare/v0.1.16...v0.1.17
[0.1.16]: https://github.com/jklaiber/kachel/compare/v0.1.15...v0.1.16
[0.1.15]: https://github.com/jklaiber/kachel/compare/v0.1.14...v0.1.15
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
