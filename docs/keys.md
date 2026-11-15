# Keys

`mod` is **Option** (⌥) by default (`mod:` changes it: `alt`, `ctrl+alt`,
`alt+cmd`, …). **Hold `mod` alone** for a moment and Kachel shows every
shortcut, grouped (`shortcut-overview: 0.8`, seconds; `0` turns it off).

## Default keys

| Key | Action |
|---|---|
| `mod-1…9` | show workspace N here (swaps displays if it's on another one) |
| `mod-shift-1…9` | send the window to workspace N |
| `mod-shift-←` / `→` | send the window to the previous / next workspace |
| `mod-tab` | back and forth between the last two workspaces |
| `mod-j` / `mod-k` | focus next / previous window |
| `mod-shift-j` / `mod-shift-k` | swap with next / previous window |
| `mod-m` / `mod-shift-m` | focus / swap with the master |
| `ctrl-alt-←→↑↓` | focus the window in that direction |
| `ctrl-alt-shift-←→↑↓` | swap with the window in that direction |
| `mod-h` / `mod-l` | narrower / wider master |
| `mod-shift-h` / `mod-shift-l` | shorter / taller window in its column |
| `mod-shift-space` | next layout |
| `mod-shift-f` | toggle fullscreen |
| `mod-t` | float / tile the window |
| `mod-,` / `mod-.` | focus next / previous display |
| `mod-shift-,` / `mod-shift-.` | send the window to the next / previous display |
| `mod-p` | search windows |
| `mod-shift-p` | always open this app on a workspace |
| `mod-s` | terminal scratchpad |
| `mod-z` | re-tile |
| `mod-shift-r` | restart Kachel |
| `mod-shift-q` | quit Kachel |

## Changing keys

In **Settings… → Shortcuts**: click a shortcut and press new keys; pick what it
does from a menu. Or in `config.yaml`:

```yaml
keys:
  mod-1: workspace 1
  cmd-shift-b: spawn open -a Safari
  mod-x: ~                       # unbind
```

Modifiers are `mod`, `cmd`, `ctrl`, `alt` (Option) and `shift`; letters follow
your keyboard layout. **A `keys:` section replaces the default keymap as a
whole**; leave it out to keep the defaults.

## Taken keys

Before using keys that another Kachel shortcut, macOS (System Settings →
Keyboard → Keyboard Shortcuts) or skhd already uses, the settings window asks.
In a terminal:

```bash
/Applications/Kachel.app/Contents/MacOS/Kachel --list-taken-keys
```

## All commands

| Command | |
|---|---|
| `workspace N` | show workspace N here (greedyView) |
| `view N` | go to workspace N (W.view) |
| `shift N` | send the window to workspace N |
| `workspace-back` | the previous workspace of this display |
| `workspace-next`, `workspace-prev` | the next / previous workspace |
| `shift-next`, `shift-prev` | send the window to the next / previous workspace |
| `focus-down`, `focus-up`, `focus-master` | focus next / previous / master |
| `swap-down`, `swap-up`, `swap-master` | swap with next / previous / master |
| `focus left` / `right` / `up` / `down` | focus in a direction |
| `swap left` / `right` / `up` / `down` | swap in a direction |
| `focus-screen N`, `shift-to-screen N` | focus display N / send the window there |
| `focus-next-screen`, `focus-prev-screen` | focus the next / previous display |
| `shift-to-next-screen`, `shift-to-prev-screen` | send the window to the next / previous display |
| `next-layout`, `toggle-fullscreen` | layouts |
| `shrink`, `expand`, `inc-master`, `dec-master` | the master area |
| `taller`, `shorter`, `reset-sizes` | window sizes |
| `toggle-float`, `close` | the focused window |
| `window-search`, `app-rule` | search windows, set an app rule |
| `scratchpad NAME` | show / hide a scratchpad |
| `terminal`, `spawn COMMAND` | run something |
| `shortcuts`, `settings`, `welcome` | Kachel's windows |
| `refresh`, `reload`, `restart`, `quit` | Kachel itself |
