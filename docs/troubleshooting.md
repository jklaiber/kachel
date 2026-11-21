# Troubleshooting

## Nothing happens

Almost always the **Accessibility** permission. Kachel shows it in the bar in
orange, and the welcome window (right-click the bar → *Welcome and Setup
Check…*) has a button for it.

Since 0.1.18, upgrades keep the permission. Coming from an older version, or
after a rebuild without a signing certificate, macOS treats Kachel as a new
app: the old entry in System Settings → Privacy & Security → Accessibility may
look switched on but no longer count. Remove it with **–** and add Kachel again.

## A shortcut doesn't work

- Another app may have taken it: the bar says so in orange, and the log too.
- macOS shortcuts and skhd win over Kachel. List what's taken:
  `/Applications/Kachel.app/Contents/MacOS/Kachel --list-taken-keys`
- Two window managers at once (Amethyst, AeroSpace, yabai) fight over keys and
  windows. Quit the others.

## Windows and workspaces

- **After sleep, a restart or a crash**, windows keep their workspaces: Kachel
  saves the state after every change and restores it on the next start. If it
  crashes, it first puts parked windows back on screen.
- **Minimized and native fullscreen windows** aren't tiled; they keep their
  workspace and come back there.
- **An app that keeps its window after closing it** (Calendar, many Electron
  apps) still counts as having a window on that workspace until it really closes.
- **Apps with a minimum size** can't shrink into a small tile; Kachel gives them
  the room they need, and windows overlap evenly if nothing fits. An app that
  ignores the resize is asked twice, then left as it is; the log names it.

## The log

Everything Kachel does is logged to `~/Library/Logs/Kachel.log` (also *Show Log*
in the bar's menu): commands, new, closed and returning windows with their size
and position, displays coming and going, focus changes from macOS, sleep and
lock, moves that didn't work, config errors.

It's written so you can attach it to a bug report: **no window titles** (a
window shows as `title #3fa2 (23 chars)`, the same tag for the same title while
Kachel runs) and **no user name** (your home folder is written as `~`). App
names, display names and your config's commands are in it.

## The kachel command

[`kachel`](command-line.md) shows what Kachel sees and runs commands:

```bash
kachel dump                # write every workspace and window to the log
kachel query windows       # the same as JSON
kachel workspace 3         # any command from config.yaml
```

From a clone of the repository, `scripts/kachel-ctl` does the same with the dev build.

## After a crash

If Kachel crashes or is force-quit, a small helper process puts windows from
hidden workspaces back on screen, unminimizes the ones Kachel minimized, and
starts Kachel again (not if it keeps crashing: three times in ten minutes).
The next time, Kachel offers to report the crash: **Report on GitHub…** opens
a new issue with the crash details filled in, for you to look over and send.

## Command line options

| Option | |
|---|---|
| `--print-default-config` | print the default config with all comments |
| `--list-taken-keys` | key combinations macOS and skhd already use |
| `--render-screenshots DIR` | draw the documentation images |
