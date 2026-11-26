---
title: "Coming from xmonad, Amethyst, skhd or AeroSpace"
---

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
| `NamedScratchpad` | [`scratchpads:`](/kachel/scratchpads/) |
| `manageHook` (`doShift`, `doFloat`) | [`rules:`](/kachel/window-search-and-rules/#app-rules), `mod-shift-p` |
| `insertPosition` | `new-windows:` `end`, `below`, `above`, `master` |
| `smartBorders` | `border.smart` |
| `XMonad.Prompt.Window` / dmenu | window search (`mod-p`) |
| xmobar | [the bar](/kachel/bar/) |
| `mod-q` recompile | saving `config.yaml` applies it; `mod-shift-r` restarts |

Not there (yet): tabbed layouts, dynamic workspaces, `CopyWindow`.

## From Amethyst

| Amethyst | Kachel |
|---|---|
| `focus-cw` / `focus-ccw` | `mod-j` / `mod-k` |
| `swap-cw` / `swap-ccw` | `mod-shift-j` / `mod-shift-k` |
| `shrink-main` / `expand-main` | `mod-h` / `mod-l` |
| `cycle-layout` / `cycle-layout-backward` | `mod-shift-space` / `prev-layout` |
| `select-<layout>-layout` | `layout <name>` |
| layouts `tall-right`, `two-pane`, `row`, `widescreen-tall`, `bsp`, `floating` | the same, `row` is `rows` ([Layouts](/kachel/layouts/)) |
| `toggle-tiling` | `toggle-tiling` |
| `toggle-focus-follows-mouse` | `toggle-focus-follows-mouse` |
| `window-max-count`, `increase-` / `decrease-window-max-count` | `window-limit`, `increase-` / `decrease-window-limit` |
| `follow-space-thrown-windows` | `follow-moved-windows` (off by default, on in Amethyst) |
| `throw-space-N` | `mod-shift-N` |
| `throw-space-left` / `-right` | `mod-shift-←` / `→` |
| `focus-screen-cw` | `mod-,` |
| `reevaluate-windows` | `mod-z` |
| `mouse-swaps-windows`, `mouse-resizes-windows` | always on, see [Mouse and trackpad](/kachel/mouse-and-trackpad/) |
| `float-small-windows` | `float-small-windows` |
| `floating` | `rules:` with `float: true` |
| `new-windows-to-main` | `new-windows: master` |
| `window-margin-size` | `gap` |
| `smart-window-margins` | `smart-gaps` |
| `screen-padding-*`, `disable-padding-on-builtin-display` | `padding`, `builtin-display-padding: false` |
| `window-resize-step` | `ratio-step` |
| `mouse-follows-focus`, `focus-follows-mouse` | same names |

The big difference: Amethyst tiles each macOS Space separately, so a Space
stays on its display. Kachel's workspaces aren't Spaces and can show on any
display.

## From skhd

Kachel's `keys:` cover what skhd does for a window manager: any key
combination runs a command, `spawn` runs a shell command. A combination can be
one-sided like skhd's `lalt`: `mod: left-alt` ([Keys](/kachel/keys/#only-the-left-or-right-key)).

| skhd | Kachel |
|---|---|
| `lalt - j : …` | `mod: left-alt`, then `mod-j: …` |
| `cmd - return : open -na Alacritty` | `cmd-return: spawn open -na Alacritty` |
| `lalt - q : skhd --key "cmd - w"` | `mod-q: send-key cmd-w` |

`send-key` presses the combination in the front app with exactly the modifiers
you give: the Option you still hold for the shortcut doesn't get in, so
`send-key cmd-w` closes a tab and not all windows. It can't send one of
Kachel's own shortcuts (that would trigger itself).

## From AeroSpace

Same idea for hiding windows (a screen corner instead of Spaces), and
`workspace-to-monitor-force-assignment` is Kachel's
[`workspace-screens`](/kachel/workspaces/#pinning-workspaces-to-a-display). Kachel
tiles xmonad-style (master and stack) instead of i3's tree, and `mod-N` swaps
displays (`greedyView`) instead of focusing the other display.
