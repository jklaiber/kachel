# Mouse and trackpad

## Mouse

- **Move the split**: drag the edge between master and stack (Tall, Wide,
  Three-column).
- **Resize within a column**: drag a window's top or bottom edge; the others
  make room. `reset-sizes` evens them out.
- **Swap**: drag a tiled window by its title bar onto another one, also on
  another display. Drop it on an empty part of another display to move it there.
  Anything else snaps back.

```yaml
focus-follows-mouse: false    # true: the window under the pointer gets focus when the pointer rests
mouse-follows-focus: window   # window: pointer to the focused window's centre; screen; off
```

## Trackpad swipes

Swipe with three fingers (or four) to switch workspaces on the display under
the pointer, like macOS Spaces. Swipes skip empty workspaces and the ones shown
on another display (xmonad's `CycleWS` with `HiddenNonEmptyWS`).

```yaml
gestures:
  enabled: true
  fingers: 3
  skip-empty: true
  direction: auto              # like macOS (follows Natural scrolling); natural; reversed
  swipe-left: workspace-next   # any command; ~ for nothing
  swipe-right: workspace-prev
  swipe-up: ~
  swipe-down: ~
```

Turn macOS's own swipe off first: System Settings → Trackpad → More Gestures →
*Swipe between full-screen applications* → Off. The
[welcome window](getting-started.md#the-welcome-window) checks it.

`haptics: true` gives a light tap on the trackpad when a swipe triggers or a
window snaps into place.

!!! note
    Swipes are read through Apple's private `MultitouchSupport` framework, as
    BetterTouchTool and similar tools do. If a macOS update breaks it, swipes
    stop working and everything else keeps going.
