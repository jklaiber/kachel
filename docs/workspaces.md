---
title: "Workspaces and displays"
---

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

<figure class="swap not-content" aria-label="Before: display A shows workspace 1 and has focus, display B shows workspace 2. After mod-2 on A: A shows 2, B shows 1.">
<div class="swap-stage"><div class="swap-displays"><div class="swap-display focused"><b>1</b><span>Display A</span></div><div class="swap-display"><b>2</b><span>Display B</span></div></div><span class="swap-caption">Before: you press <kbd class="keys"><kbd>mod</kbd><kbd>2</kbd></kbd> on A</span></div>
<div class="swap-arrow" aria-hidden="true">→</div>
<div class="swap-stage"><div class="swap-displays"><div class="swap-display focused"><b>2</b><span>Display A</span></div><div class="swap-display"><b>1</b><span>Display B</span></div></div><span class="swap-caption">After: the two displays swapped</span></div>
</figure>

## Several displays

Displays are numbered from left to right.

| Keys | Command |
|---|---|
| `mod-,` / `mod-.` | focus the next / previous display |
| `mod-shift-,` / `mod-shift-.` | send the window to the next / previous display |
| `ctrl-alt-arrows` | focus the window in that direction, across displays too |

With `mouse-follows-focus: window` the pointer follows when focus changes
display. When a window closes, focus stays on its display.

## Following focus to a hidden workspace

When a window on a hidden workspace gets focus without a Kachel key (a link
opens in it, ⌘Tab, the Dock, a notification), Kachel shows its workspace. Where:

```yaml
follow-focus-screen: current   # on the display you're on (default)
# follow-focus-screen: last    # on the display that showed it last; yours keeps its workspace
```

With `last`, a link from Slack on one display opens Chrome's workspace on the
other display, where you had it, instead of replacing what you're working on.
If that display isn't connected any more, it's `current`. Pinned workspaces
(below) always go to their display, and the workspace keys aren't affected.
Settings → General → Workspaces has the same choice.

## Pinning workspaces to a display

```yaml
workspace-screens:
  "8": external      # main (menu bar), external, builtin, 1…n from the left, or part of the name
  "9": DELL
```

A pinned workspace always shows on its display while that display is connected:
`mod-8` brings it up there and moves focus over. Without that display it's an
ordinary workspace. Trackpad swipes skip workspaces pinned to another display.

## Plugging displays in and out

Kachel recognises displays by name, not by their position:

- A display that stays keeps its workspace, also when one to its left is unplugged.
- Windows of a display you unplug stay on their workspaces, out of sight until you show them.
- A display you plug in shows its pinned workspace, otherwise the one it showed
  last time it was connected (docking a laptop gives you back what you had).
- Focus stays on the display it was on.

## After a restart

Kachel remembers which workspace every window is on. Quit and start Kachel
again and they're all where they were. After a restart of the Mac, window IDs
start over, so Kachel recognises windows by app and title as their apps open
them again (for ten minutes after it starts):

- the same title, or almost (`— Edited`, `•`, `(2)` don't count);
- a window whose title changed (a browser showing another tab) goes where that
  app's windows were, if they were all on one workspace;
- anything else lands on the current workspace, like a new window.

Layouts and sizes come back too. Titles are stored only as hashes, never as text.

## Fullscreen

There are two kinds:

- **Kachel's own**, `mod-shift-f` (`toggle-fullscreen`): the workspace shows its
  focused window in the Full layout until you press it again. The menu bar and
  Kachel's bar stay, no Space of its own, switching stays instant.
- **macOS's**, the green button or ⌃⌘F: the window moves to a Space of its own.
  Kachel leaves it alone meanwhile. It stays on its workspace (the other windows
  there take the room), isn't parked or moved, and when it leaves fullscreen it's
  tiled in its old place again, also if its workspace isn't on screen then.

To get to a macOS fullscreen window and back, use macOS: Mission Control, ⌘Tab,
the Dock, or the swipe between Spaces. While you're in its Space, macOS doesn't
show Kachel the windows of your desktop, so workspace keys pressed there take
effect when you're back on the desktop.

## How hiding works

Kachel doesn't use macOS Spaces. Every display keeps a single Space, and the
windows of hidden workspaces are moved into a screen corner with one pixel
visible (macOS doesn't allow windows fully off screen). Switching workspaces
just moves windows, so it's instant.

A few macOS settings make that nicer; the [welcome window](/kachel/getting-started/#the-welcome-window)
checks them:

- **One Space per display**, and *Automatically rearrange Spaces* off.
- *Group windows by application* in Mission Control, so parked windows don't look tiny there.
- Every display needs a free bottom-left or bottom-right corner, or parked
  windows peek onto the neighbouring display. Arrange displays accordingly.
- An auto-hiding Dock at the bottom covers the one-pixel slivers.

Kachel keeps track of which workspace every window is on across sleep,
restarts and crashes; see [Troubleshooting](/kachel/troubleshooting/#windows-and-workspaces).
