# Settings and config.yaml

Everything Kachel does is set in **`~/.config/kachel/config.yaml`**. Kachel writes
it with every option and an explanation on first launch, and applies changes
as soon as you save. You can edit it by hand, use the settings window, or both.

## The settings window

**Settings…** is in the bar's right-click menu (or the `settings` command, also
`kachel settings` in a terminal). It
looks and works like System Settings: General, Bar, Focus Border, Trackpad,
Shortcuts, App Rules and Scratchpads.

- Every change is written into `config.yaml` straight away, **comments
  included**, and applies at once. Edits in the file show up in the window.
- **Shortcuts**: click a shortcut and press new keys; pick what it does from
  menus. Kachel asks before taking keys that are already in use.
- **Scratchpads**: add, rename, resize, and fill in app and title from the
  focused window.
- **⌘Z / ⇧⌘Z** undo and redo.
- A change that wouldn't load is rolled back and shown at the top of the window.

## Editing the file

```yaml
mod: ctrl+alt
workspaces: [web, code, chat, 4, 5]
gap: 8
terminal: open -na Ghostty
keys:
  mod-1: workspace 1
  cmd-shift-b: spawn open -a Safari
```

- Anything you leave out uses the default.
- **`keys:` replaces the default keymap as a whole**; leave it out to keep it.
- If the file has an error (a value that doesn't fit, like `gap: banana`), the
  bar shows it in orange and the previous settings stay in effect.
- A setting Kachel doesn't know (a typo, or one from a newer version) is
  ignored with a note in the bar and at the top of Settings ("unknown setting
  'gapp' ignored (did you mean 'gap'?)"); everything else applies.

The [configuration reference](configuration.md) lists every option.
After an upgrade, compare your config with the new defaults:

```bash
diff ~/.config/kachel/config.yaml <(/Applications/Kachel.app/Contents/MacOS/Kachel --print-default-config)
```

## Focus border

A frame around the focused window, sitting on its edge:

```yaml
border:
  enabled: true
  width: 3
  color: accent        # your accent colour, or "#RRGGBB"
  radius: auto         # follows each window's corners, or a number
  smart: false         # true: no frame when a window is alone on its display
```

## Other settings

```yaml
start-at-login: false
menubar-icon: false          # Kachel's menu also as an icon in the top menu bar
shortcut-overview: 0.8       # hold mod this long to see all shortcuts; 0 = off
haptics: true
float-dialogs: true
float-small-windows: 0
check-for-updates: true      # once a day, look up the latest release on GitHub
```

With `check-for-updates`, a newer version shows up at the top of the bar's menu
and in Settings → General, with the command to upgrade. It only asks GitHub which
release is the latest; nothing about you or your Mac is sent.
