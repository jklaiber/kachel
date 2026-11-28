---
title: "Command line"
---

Homebrew installs a `kachel` command next to the app. It talks to the running
Kachel, so scripts, launchers (Raycast, Alfred, Shortcuts) and other bars can
switch workspaces or ask what's where.

```bash
kachel workspace 3          # any command from the config's keys
kachel shift 2
kachel next-layout
kachel scratchpad notes
kachel query focused        # JSON
```

Every command from [Keys](/kachel/keys/#all-commands) works: write it just like in
`keys:`. Also `kachel settings` opens Kachel's settings; `kachel help` lists the rest.

## Queries

`kachel query …` prints JSON, for scripts and tools like `jq`:

| Query | What you get |
|---|---|
| `kachel query workspaces` | every workspace: name, layout, which screen shows it, its window IDs |
| `kachel query windows` | every managed window: app, title, workspace, floating, frame |
| `kachel query screens` | every display: name, built-in or not, the workspace on it |
| `kachel query focused` | the workspace you're on and its focused window |

```bash
# The name of the workspace you're on, e.g. for another bar:
kachel query focused | jq -r .workspace.name

# Every Safari window and where it is:
kachel query windows | jq '.[] | select(.app == "Safari") | {title, workspace}'
```

## Events

`kachel subscribe` stays connected and prints a line of JSON each time
something changes, until you stop it or Kachel quits. Other bars and scripts
can follow along without asking every second:

| Event | When | What you get |
|---|---|---|
| `workspace` | you switch workspace, or a display shows another one | `workspace`, `previous`, `screen`, `visible` (the workspace on each display) |
| `focus` | another window gets focus, or its title changes | `workspace`, `window` (`id`, `app`, `bundle-id`, `title`; `null` on an empty workspace) |
| `layout` | a workspace changes layout | `workspace`, `layout` (`paused` while tiling is paused) |
| `windows` | a window opens, closes or moves to another workspace | `workspace`, `windows` (its window IDs) |

Name the events you want, or leave them out for all of them. Right away you
get where things are now: the `workspace`, its `layout` and the `focus`.

```bash
kachel subscribe workspace focus
# {"event":"workspace","previous":"1","screen":1,"visible":["2"],"workspace":"2"}
# {"event":"focus","window":{"app":"Safari","bundle-id":"com.apple.Safari","id":4127,"title":"Kachel"},"workspace":"2"}
```

```bash
# Tell SketchyBar about every workspace switch:
kachel subscribe workspace | while read -r line; do
    sketchybar --trigger kachel_workspace WORKSPACE="$(jq -r .workspace <<<"$line")"
done
```

## Good to know

- Exit codes: `0` done, `1` Kachel refused the command (the reason is printed),
  `2` Kachel isn't running.
- The command reaches Kachel through a socket in
  `~/Library/Application Support/Kachel` that only your user can open.
- Without Homebrew, the command is the app itself:
  `/Applications/Kachel.app/Contents/MacOS/Kachel --ctl workspace 3`.
