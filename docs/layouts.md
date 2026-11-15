# Layouts

`mod-shift-space` cycles through the layouts listed in `layouts:`; each
workspace remembers its own.

| Layout | What it does |
|---|---|
| `tall` | master on the left, the others stacked on the right (xmonad's Tall) |
| `wide` | master on top, the others side by side below (Mirror Tall) |
| `three-column` | master in the middle, stacks on both sides (ThreeColMid); good for wide displays |
| `column` | all windows side by side |
| `full` | one window at a time, the focused one |

```yaml
layouts: [tall, wide, three-column, column, full]
gap: 5            # between windows and at the edges
ratio: 0.5        # master size on new workspaces
ratio-step: 0.05  # what mod-h / mod-l change
```

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
learns that from the window and gives it the room it needs; if the column is
too small for all of them, they overlap evenly and stay on screen.

## New windows

```yaml
new-windows: end    # end of the stack (default) | below | above (xmonad) | master
```

A new window always gets focus. Floating windows (dialogs, small windows,
[rules](window-search-and-rules.md#app-rules)) aren't tiled.
