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

## Good to know

- Exit codes: `0` done, `1` Kachel refused the command (the reason is printed),
  `2` Kachel isn't running.
- The command reaches Kachel through a socket in
  `~/Library/Application Support/Kachel` that only your user can open.
- Without Homebrew, the command is the app itself:
  `/Applications/Kachel.app/Contents/MacOS/Kachel --ctl workspace 3`.
