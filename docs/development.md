# Development

Requires macOS 13+ and the Xcode Command Line Tools (`xcode-select --install`).

```bash
swift test                    # the model: workspaces, layouts, config parsing and editing
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
  It runs headless: no windows of its own, nothing moved on your screen, nothing
  written to your log or saved state. A scenario that broke in real use belongs here.

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
