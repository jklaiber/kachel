# XMonadMac – session handoff

Paste this file (or point the new session at it) to continue where we left off.

## Goal
A native macOS tiling window manager with **exactly xmonad's workspace behaviour**:
9 workspaces shared across all monitors, each monitor shows one, and `mod-N` is
**greedyView** (if workspace N is visible on the other screen, the two screens swap).
The user comes from xmonad on Linux and currently uses Amethyst, which can't do this
because native macOS Spaces belong to one display each.

## Design decisions (already made)
- **Don't use macOS Spaces.** Same trick as AeroSpace: one Space per display;
  windows of hidden workspaces are parked in a screen corner with 1px visible
  (corner chosen so it doesn't overlap another display). No SIP changes needed.
- **Accessibility API** (AXUIElement) to move, resize and focus windows; private
  `_AXUIElementGetWindow` for stable window IDs (same as Amethyst/yabai/AeroSpace).
- **Carbon `RegisterEventHotKey`** for global hotkeys.
- **Default mod = Ctrl+Option.** The user types on a Swiss keyboard, where Option+digit produces `| @ # [ ]`.
- **Config as code** in `Sources/XMonadMac/Config.swift` (like `xmonad.hs`), rebuild to apply.
- Pure model split into a library target `XMonadCore` (StackSet + Layout) with XCTest tests.

## Project layout
```
Package.swift                       swift-tools 5.9, macOS 13+, targets: XMonadCore, XMonadMac, XMonadCoreTests
Sources/XMonadCore/StackSet.swift   workspaces, screens, greedyView, view, shift, insertUp, focus/swap, layouts state
Sources/XMonadCore/Layout.swift     Tall, Mirror Tall, Full with gaps
Sources/XMonadMac/Config.swift      keybindings, mod, gaps, terminal command, floating bundle IDs
Sources/XMonadMac/WindowManager.swift  tracking (AXObserver + NSWorkspace notifications + 2s poll), render, hide/show, focus sync
Sources/XMonadMac/AX.swift          AX helpers, AXWindow wrapper, Screen (AX coords, sorted left→right)
Sources/XMonadMac/HotKeys.swift     Carbon hotkey registration
Sources/XMonadMac/StatusBar.swift   menu bar item "[1] <2> 5  Tall" + Re-tile/Quit menu
Sources/XMonadMac/main.swift        accessory app, Accessibility prompt, SIGINT/SIGTERM restore
Tests/XMonadCoreTests/StackSetTests.swift
scripts/bundle.sh                   swift build -c release → build/XMonadMac.app (LSUIElement, ad-hoc signed)
README.md                           user docs, keybindings, macOS settings, limitations
```

## Status
- All code written, **never compiled** (previous session ran on Linux, no Swift toolchain).
  Expect a few compile errors on first `swift build`.
- Nothing pushed to GitHub yet. The user wants a repo under their GitHub account
  **jklaiber** (e.g. `jklaiber/xmonadmac`).

## Next steps
1. `swift build` and `swift test` on the Mac; fix compile errors and failing tests.
2. `git init`, create the GitHub repo (`gh repo create jklaiber/xmonadmac --private --source . --push`).
3. Optional: add a GitHub Actions workflow on `macos-latest` running `swift build` + `swift test`.
4. Run `./scripts/bundle.sh && open build/XMonadMac.app`, grant Accessibility, quit Amethyst first.
   Use one Space per display; turn off "Automatically rearrange Spaces".
5. Test greedyView across two monitors, the shift keys, floating, quit restoring windows.
6. Known gaps to consider later: mouse-resize of the master split, persisting state across
   restarts, minimized/fullscreen windows, apps that ignore AX resizes.

## Alternative already discussed
AeroSpace's `summon-workspace` command is described as xmonad-like. It wasn't confirmed
whether it does the exact two-screen swap; worth comparing against XMonadMac.
