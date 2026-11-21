# Layouts

`mod-shift-space` cycles through the layouts listed in `layouts:`; each
workspace remembers its own. `prev-layout` goes the other way, and
`layout NAME` (e.g. `layout full`) switches straight to one; bind them in
`keys:` or in **Settings → Shortcuts**.

| Layout | What it does |
|---|---|
| `tall` | master on the left, the others stacked on the right (xmonad's Tall) |
| `tall-right` | the same with the master on the right |
| `wide` | master on top, the others side by side below (Mirror Tall) |
| `widescreen-tall` | the masters side by side on the left, the stack on the right; for wide displays with `inc-master` |
| `three-column` | master in the middle, stacks on both sides (ThreeColMid); good for wide displays |
| `two-pane` | master and one pane; the other windows wait behind that pane, the focused one in front |
| `column` | all windows side by side |
| `rows` | all windows on top of each other, full width |
| `bsp` | each window takes half of what's left, alternating side by side and on top of each other |
| `full` | one window at a time, the focused one |
| `floating` | nothing is tiled: windows stay where you put them, on this workspace |

```yaml
layouts: [tall, wide, three-column, column, full]
gap: 5                     # between windows
padding: auto              # at the screen edges; auto = the same as gap
builtin-display-padding: true   # false: none on the MacBook's own display
smart-gaps: false          # true: no gap or padding for a window alone on its display
window-limit: 0            # at most this many tiled windows; the others float. 0 = no limit
ratio: 0.5                 # master size on new workspaces
ratio-step: 0.05           # what mod-h / mod-l change
```

`increase-window-limit` / `decrease-window-limit` change the limit with a key.

## A layout per workspace

```yaml
workspace-layouts:
  "1": full
  "9": three-column
```

Those workspaces start with that layout: when Kachel starts and as soon as you
change it. The others keep the layout they had, also across restarts. The keys
still switch layouts on any workspace. **Settings → General → Workspaces →
Starting layout per workspace** sets the same. Only layouts from `layouts:` work
here, so `mod-shift-space` can always cycle on from them.

## Pausing tiling

`toggle-tiling` pauses tiling: windows stay where they are and you can move them
freely, for a presentation or screen sharing. Workspaces still switch, and the
bar shows *Paused*. The same command resumes it, and every workspace is tiled
again.

## Sizes

| Keys | Command | Effect |
|---|---|---|
| `mod-h` / `mod-l` | `shrink` / `expand` | narrower / wider master |
| `mod-shift-h` / `mod-shift-l` | `shorter` / `taller` | the focused window's share of its column |
| – | `inc-master` / `dec-master` | more / fewer windows in the master area |
| – | `reset-sizes` | equal shares and the default master size again |
| `mod-shift-f` | `toggle-fullscreen` | Full until pressed again (xmonad's ToggleLayouts) |

The mouse works too: drag the edge between master and stack, or the top/bottom
edge of a window in a column. See [Mouse and trackpad](mouse-and-trackpad.md).

**Minimum sizes**: some apps can't get smaller than a certain size. Kachel
learns that from the window and gives it the room it needs in its column; if
the column is too small for all of them, they overlap evenly and stay on screen.
A window too *wide* for its column grows towards the middle over its neighbour
(the columns don't move for it): widen it with `mod-l` / `mod-h`, or float it.

## New windows

```yaml
new-windows: end    # end of the stack (default) | below | above (xmonad) | master
```

A new window always gets focus. Floating windows (dialogs, small windows,
[rules](window-search-and-rules.md#app-rules)) aren't tiled.
