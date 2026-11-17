# The bar

![The bar: workspaces, layout, window title, network, CPU, memory, date and clock](images/screenshots/bar.png)

Every display gets a second menu bar along the bottom, just above the Dock,
with the same height, font and translucency as the one at the top. Tiled
windows leave room for it.

## Workspaces

| Looks like | Means |
|---|---|
| solid | the workspace you're in |
| outline | shown on a display |
| dot | has windows |
| dim | empty |

Click a workspace to show it on that display.

With `workspace-counts: true`, each workspace shows how many windows it has, as
a small number next to it, instead of the dot.

## Windows on this workspace

In the Full layout you only see one window. The bar can show the others:

| `windows:` | Shows |
|---|---|
| `tabs` | every window's name, the focused one highlighted; click a tab to switch to it |
| `dots` | one dot per window, the focused one filled |
| `position` | which window and how many, next to the layout: `Full 2/4` |
| `off` | only the focused window's title |

`windows-full-only: true` (the default) shows them only in the Full layout,
including `toggle-fullscreen`; in the other layouts you see the windows anyway.
**Settings → Bar** has the same choices, with a preview.

## Widgets

| Widget | Shows | Click |
|---|---|---|
| `workspaces` | see above | show it on this display |
| `layout` | Tall, Wide, … | |
| `title` | the focused window on that display | |
| `network` | ↓ / ↑ throughput | Activity Monitor |
| `cpu` | CPU load | Activity Monitor |
| `memory` | memory used | Activity Monitor |
| `battery` | battery level, like the menu bar's icon; a bolt while plugged in, red below 10 %. `battery-percentage: false` shows the icon only. Not shown on Macs without a battery | Battery settings |
| `date`, `clock` | `date-format`, `clock-format` | Calendar |

```yaml
bar:
  enabled: true
  height: auto                 # same as the menu bar, or a number
  background: transparent      # or blur
  appearance: auto             # white or black text depending on the wallpaper
  left: [workspaces, layout, title]
  right: [network, cpu, memory, battery, date, clock]
  hide-empty-workspaces: false
  battery-percentage: true     # false: battery icon only
  windows: tabs                # position, dots, tabs or off
  windows-full-only: true
  workspace-counts: false
```

Right-click the bar for **Show in Bar** (switch widgets on and off), Settings,
the shortcut overview, the welcome window, Reload Config, Edit Config, Show
Log, Re-tile and Quit.

Problems (no Accessibility permission, a config error, a hotkey another app
has taken) show up in the bar in orange.

`menubar-icon: true` adds the same menu as an icon to the top menu bar.
