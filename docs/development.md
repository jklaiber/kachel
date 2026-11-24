# Development

Requires macOS 26+ and Xcode 26 (or its Command Line Tools) (`xcode-select --install`).

```bash
swift test                    # the model, and the window manager against made-up windows and displays
./scripts/bundle.sh           # build/Kachel.app
open build/Kachel.app
```

macOS ties the Accessibility permission to the app's signature. Releases are
signed with the project's own self-signed "Kachel Signing" certificate, so
upgrades keep the permission. Locally, `bundle.sh` signs with it too when it's
in your keychain. Without it, each build gets a new ad-hoc signature and macOS
asks for Accessibility again (`bundle.sh` removes the stale entry). To keep
the permission across your own rebuilds, use any certificate of yours:
`SIGN_IDENTITY="Apple Development: …" ./scripts/bundle.sh`.

## Layout of the code

| Path | |
|---|---|
| `Sources/KachelCore/` | the pure model, fully unit-tested: `StackSet` (workspaces, displays, greedyView), `Layout`, `Settings` (parsing, the default config, careful edits of the YAML), `WindowSearch`, `Navigation`, `ShortcutList` |
| `Sources/Kachel/WindowManager.swift` | the window manager's state and lifecycle; its parts are in `WindowManager+….swift`: `Discovery` (new, closed and returning windows), `Rendering` (tiling, parking), `Actions` (commands), `Focus`, `Mouse`, `Scratchpads`, `Search`, `State`, `Command`, `Overlays` |
| `Sources/Kachel/WindowSystem.swift`, `AX.swift` | everything WindowManager asks macOS about windows, behind the `WindowSystem` and `AppWindow` protocols |
| `Sources/Kachel/Watchdog.swift`, `CrashPrompt.swift`, `Ctl.swift`, `UpdateCheck.swift` | crash recovery, crash reports, the `kachel` command, the update notice |
| `Sources/Kachel/Bar.swift`, `WindowSwitcher.swift`, `RulePicker.swift`, `ShortcutOverview.swift` | the panels |
| `Sources/Kachel/SettingsWindow.swift`, `WelcomeWindow.swift` | the SwiftUI windows |
| `Sources/Kachel/Gestures.swift` | trackpad swipes |
| `config.example.yaml` | the default config; a test keeps it equal to the built-in one |

## Tests

```bash
swift test
```

- `Tests/KachelCoreTests`: the model, layouts, config parsing and editing.
- `Tests/KachelTests`: the real `WindowManager` driven by a fake window system
  (`FakeWindowSystem.swift`): windows open, close, switch tabs, get new handles,
  vanish while the screen is locked; workspaces switch on one or two displays;
  made-up displays (any name, size and arrangement) are plugged in and out.
  Time is made up too (`FakeClock`): `clock.advance(by: 61)` is a minute later
  at once, and work Kachel schedules (the checks 0.3 s after tiling) runs on
  the way, in order.
  It runs headless: no windows of its own, nothing moved on your screen, nothing
  written to your log or saved state. A scenario that broke in real use belongs here.
- `Tests/KachelTests/UITests.swift`: Kachel's own UI (the bar, Settings, the
  welcome window, window search, alerts) drawn with made-up content and compared
  pixel by pixel with references in `__Snapshots__/macOS-<version>/`. Rendering is
  exactly reproducible on one macOS version, so any change shows: the test writes
  `….actual.png` and a `….diff.png` with the changes in red next to the reference.
  After an intended change, record new references and look at them before
  committing:

  ```bash
  KACHEL_RECORD_SNAPSHOTS=1 swift test --filter UITests
  ```

  On a macOS version without references, the first run records them. Pictures
  are compared on your Mac only: another Mac (CI's virtual one) smooths text a
  little differently, so pixels never match across machines. CI still runs the
  checks that hold everywhere: the pictures aren't blank, the crash alert's
  text isn't cut off, the config warnings show.

Kachel supports macOS 26 and newer: it's built around Liquid Glass. CI runs on
GitHub's macOS 26 machines, Apple Silicon and Intel. GitHub's Intel Macs are
virtual without usable graphics, so the UI tests and the app start run on Apple
Silicon only; Intel builds and runs everything else. On Apple Silicon CI runs:
the build (an API newer than Kachel's minimum macOS fails it), `swift test`, and
`scripts/smoke-test.sh`, which starts the built app and checks that it runs,
answers the `kachel` command, opens Settings, quits cleanly and draws the
documentation images. Accessibility can't be granted there, so moving real
windows is covered by the fake window system, not by CI.

After changing the default config:

```bash
swift run Kachel --print-default-config > config.example.yaml
```

## Images

The images in these docs are drawn by Kachel itself, with made-up windows and
our own wallpaper: `./scripts/screenshots.sh` renders them into
`docs/images/screenshots/`.

## Documentation

These pages live in `docs/` and are built with MkDocs Material; every push to
`main` publishes them. To preview locally:

```bash
python3 -m venv .venv && .venv/bin/pip install -r docs/requirements.txt
.venv/bin/mkdocs serve
```

`mkdocs build --strict` fails on broken links; CI runs it on every push and pull request.

## Releasing

1. Move the `[Unreleased]` notes in `CHANGELOG.md` under a new version heading,
   with its compare link at the bottom.
2. `git tag -a v0.1.8 -m "Kachel 0.1.8" && git push origin v0.1.8`

The release workflow tests, builds the universal app, publishes the GitHub
release with that changelog section as its notes, and updates the Homebrew cask
in `jklaiber/homebrew-tap`. A version without a changelog entry isn't released.
