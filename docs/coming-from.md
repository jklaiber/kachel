# Coming from xmonad or Amethyst

Kachel's workspace model is xmonad's; its default keys follow Amethyst
(`mod1` = Option, `mod2` = Option+Shift).

## From xmonad

| xmonad | Kachel |
|---|---|
| `W.greedyView` (`mod-N`) | `workspace N`, the default on `mod-1…9` |
| `W.view` | `view N`: jump to the display already showing it |
| `W.shift` (`mod-shift-N`) | `shift N` |
| `toggleWS` | `workspace-back` (`mod-tab`), or `workspace-back-and-forth: true` |
| `CycleWS` with `HiddenNonEmptyWS` | trackpad swipes with `skip-empty: true`, `workspace-next` / `-prev` |
| Tall, Mirror Tall, Full | `tall`, `wide`, `full` |
| `ThreeColMid` | `three-column` |
| `ResizableTall` (`MirrorShrink` / `MirrorExpand`) | `shorter` / `taller` (`mod-shift-h` / `mod-shift-l`) |
| `ToggleLayouts` Full | `toggle-fullscreen` (`mod-shift-f`) |
| `Navigation2D` | `focus left` / `right` / `up` / `down`, `swap …` (`ctrl-alt-arrows`) |
| `NamedScratchpad` | [`scratchpads:`](scratchpads.md) |
| `manageHook` (`doShift`, `doFloat`) | [`rules:`](window-search-and-rules.md#app-rules), `mod-shift-p` |
| `insertPosition` | `new-windows:` `end`, `below`, `above`, `master` |
| `smartBorders` | `border.smart` |
| `XMonad.Prompt.Window` / dmenu | window search (`mod-p`) |
| xmobar | [the bar](bar.md) |
| `mod-q` recompile | saving `config.yaml` applies it; `mod-shift-r` restarts |

Not there (yet): tabbed and BSP layouts, dynamic workspaces, `CopyWindow`.

## From Amethyst

| Amethyst | Kachel |
|---|---|
| `focus-cw` / `focus-ccw` | `mod-j` / `mod-k` |
| `swap-cw` / `swap-ccw` | `mod-shift-j` / `mod-shift-k` |
| `shrink-main` / `expand-main` | `mod-h` / `mod-l` |
| `cycle-layout` | `mod-shift-space` |
| `throw-space-N` | `mod-shift-N` |
| `throw-space-left` / `-right` | `mod-shift-←` / `→` |
| `focus-screen-cw` | `mod-,` |
| `reevaluate-windows` | `mod-z` |
| `mouse-swaps-windows`, `mouse-resizes-windows` | always on, see [Mouse and trackpad](mouse-and-trackpad.md) |
| `float-small-windows` | `float-small-windows` |
| `floating` | `floating:` or `rules:` with `float: true` |
| `new-windows-to-main` | `new-windows: master` |
| `window-margin-size` | `gap` |
| `window-resize-step` | `ratio-step` |
| `mouse-follows-focus`, `focus-follows-mouse` | same names |

The big difference: Amethyst tiles each macOS Space separately, so a Space
stays on its display. Kachel's workspaces aren't Spaces and can show on any
display.

## From AeroSpace

Same idea for hiding windows (a screen corner instead of Spaces), and
`workspace-to-monitor-force-assignment` is Kachel's
[`workspace-screens`](workspaces.md#pinning-workspaces-to-a-display). Kachel
tiles xmonad-style (master and stack) instead of i3's tree, and `mod-N` swaps
displays (`greedyView`) instead of focusing the other display.
