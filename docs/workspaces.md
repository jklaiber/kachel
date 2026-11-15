# Workspaces and displays

## The model

Kachel has nine workspaces (`workspaces:` names them). They're shared by all
displays: every display shows exactly one of them, and one display has focus.

- **`mod-N`** (`workspace N`, xmonad's `greedyView`) brings workspace N to the
  display you're on. If it's already showing on another display, the two
  displays **swap**.
- **`view N`** instead moves focus to the display that already shows N
  (i3-style). Bind it in `keys:` if you prefer that.
- **`mod-shift-N`** sends the focused window to workspace N; you stay where you are.
- **`mod-tab`** (`workspace-back`) goes back to the workspace this display showed
  before, and again to return. With `workspace-back-and-forth: true`, pressing
  the key of the workspace you're already on does the same.

```
 before mod-2 on A          after
 ┌──────┐ ┌──────┐          ┌──────┐ ┌──────┐
 │  A:1*│ │  B:2 │   ──▶    │  A:2*│ │  B:1 │
 └──────┘ └──────┘          └──────┘ └──────┘
```

## Several displays

Displays are numbered from left to right.

| Keys | Command |
|---|---|
| `mod-,` / `mod-.` | focus the next / previous display |
| `mod-shift-,` / `mod-shift-.` | send the window to the next / previous display |
| `ctrl-alt-arrows` | focus the window in that direction, across displays too |

With `mouse-follows-focus: window` the pointer follows when focus changes
display. When a window closes, focus stays on its display.

## Pinning workspaces to a display

```yaml
workspace-screens:
  "8": external      # main (menu bar), external, builtin, 1…n from the left, or part of the name
  "9": DELL
```

A pinned workspace always shows on its display while that display is connected:
`mod-8` brings it up there and moves focus over. Without that display it's an
ordinary workspace. Trackpad swipes skip workspaces pinned to another display.

## How hiding works

Kachel doesn't use macOS Spaces. Every display keeps a single Space, and the
windows of hidden workspaces are moved into a screen corner with one pixel
visible (macOS doesn't allow windows fully off screen). Switching workspaces
just moves windows, so it's instant.

A few macOS settings make that nicer; the [welcome window](getting-started.md#the-welcome-window)
checks them:

- **One Space per display**, and *Automatically rearrange Spaces* off.
- *Group windows by application* in Mission Control, so parked windows don't look tiny there.
- Every display needs a free bottom-left or bottom-right corner, or parked
  windows peek onto the neighbouring display. Arrange displays accordingly.
- An auto-hiding Dock at the bottom covers the one-pixel slivers.

Kachel keeps track of which workspace every window is on across sleep,
restarts and crashes; see [Troubleshooting](troubleshooting.md#windows-and-workspaces).
