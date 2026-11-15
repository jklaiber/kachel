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

## Widgets

| Widget | Shows | Click |
|---|---|---|
| `workspaces` | see above | show it on this display |
| `layout` | Tall, Wide, … | |
| `title` | the focused window on that display | |
| `network` | ↓ / ↑ throughput | Activity Monitor |
| `cpu` | CPU load | Activity Monitor |
| `memory` | memory used | Activity Monitor |
| `date`, `clock` | `date-format`, `clock-format` | Calendar |

```yaml
bar:
  enabled: true
  height: auto                 # same as the menu bar, or a number
  background: transparent      # or blur
  appearance: auto             # white or black text depending on the wallpaper
  left: [workspaces, layout, title]
  right: [network, cpu, memory, date, clock]
  hide-empty-workspaces: false
```

Right-click the bar for **Show in Bar** (switch widgets on and off), Settings,
the shortcut overview, the welcome window, Reload Config, Edit Config, Show
Log, Re-tile and Quit.

Problems (no Accessibility permission, a config error, a hotkey another app
has taken) show up in the bar in orange.

`menubar-icon: true` adds the same menu as an icon to the top menu bar.
