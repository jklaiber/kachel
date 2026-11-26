---
title: "Scratchpads"
---

A scratchpad is a window you summon with one key, like xmonad's
NamedScratchpad: it floats over whatever workspace you're on, and the same key
puts it away again. If it isn't open, Kachel starts it.

```yaml
scratchpads:
  - name: term
    app: org.alacritty                # bundle ID or app name
    title: scratchpad                 # optional: only windows with this in the title
    run: open -na Alacritty --args --title scratchpad -o window.dynamic_title=false
    size: [0.6, 0.55]                 # share of the display
    position: center                  # or top, like a drop-down terminal
keys:
  mod-s: scratchpad term
```

The easiest way to set one up is **Settings… → Scratchpads**: *Add a Scratchpad*
starts from the window you last used, and *Take App and Title from the Focused
Window* fills in the details.

## Examples

**Quick notes in one text file**:

```yaml
  - name: notes
    app: com.apple.TextEdit
    title: quicknotes.txt          # only this file, not other TextEdit documents
    run: open -a TextEdit ~/Documents/quicknotes.txt
    size: [0.4, 0.6]
    position: top
```

**Apple Notes**:

```yaml
  - name: notes
    app: com.apple.Notes
    run: open -a Notes
    size: [0.45, 0.7]
```

**A Markdown file in your editor**:

```yaml
  - name: notes
    app: org.alacritty
    title: quicknotes
    run: open -na Alacritty --args --title quicknotes -o window.dynamic_title=false -e zsh -lc 'nvim ~/notes/quick.md'
```

:::tip[Tools from Homebrew or Nix]
Commands started by Kachel only see the system `PATH`. Start such tools
through your login shell (`zsh -lc '…'`), as in the last example.
:::

## Good to know

- Use `title` whenever the app has other windows, so the scratchpad only takes
  its own. It's a case-insensitive *contains* match on the window title: use a
  short part that stays the same, like the file name. Apps often show more in
  the title (the folder, the app name, "— Edited"), and not always the path the
  way you wrote it.
- `run` is a shell command (`/bin/sh -c`): quote paths with spaces, as in
  `run: open -a TextEdit "$HOME/My Docs/notes.txt"`, or the shell splits them.
  Use `$HOME` inside quotes: `~` isn't expanded there.
- After `run`, Kachel waits 15 seconds for a window that fits `app` and
  `title`, and doesn't start the app again meanwhile. If none comes, the bar
  says so, and when a window of the app is there but its title doesn't fit, it
  says that too. If `run` itself fails, the bar shows the error.
- On another workspace or display, the key brings the scratchpad over there.
- The app keeps running while the scratchpad is put away, so nothing is lost.
