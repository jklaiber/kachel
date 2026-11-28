# Contributing to Kachel

Thanks for helping! Bug reports, ideas and pull requests are all welcome.

## Questions and ideas

Ask in [Discussions](https://github.com/jklaiber/kachel/discussions). Issues are
for bugs and concrete feature requests.

## Reporting a bug

Use the bug report form. The most useful things to include:

- your macOS and Kachel versions, and how many displays you use
- what you did, what you expected, and what happened
- the lines from `~/Library/Logs/Kachel.log` around the time it happened
  (bar → right-click → *Show Log*); it holds no window titles and no user name
- the part of your `~/.config/kachel/config.yaml` that matters

Security problems go through [private reporting](SECURITY.md), not issues.

## Building

Requires macOS 26+ and Xcode 26 (or its Command Line Tools).

```bash
swift test                          # the model, and the window manager against made-up windows
./scripts/bundle.sh && open build/Kachel.app
```

Without a signing certificate, every rebuild asks for Accessibility again. The
[Development page](https://jklaiber.github.io/kachel/development/) explains how
to sign builds so the permission sticks.

## How the code fits together

Start with [Architecture](https://jklaiber.github.io/kachel/architecture/): the
model and the window manager, what happens on a key press or a new window, how
it's tested, and every place a new command, setting, layout or bar widget
touches.

## Pull requests

- Keep a pull request to one change, and open an issue or discussion first for
  bigger ones, so we can agree on the approach.
- Logic that doesn't need macOS belongs in `Sources/KachelCore` with tests.
  Window handling is tested in `Tests/KachelTests` against a fake window system
  (made-up windows, displays and time): a bug from real use belongs there as a
  test. A change to Kachel's own UI changes the reference images in
  `Tests/KachelTests/__Snapshots__`: re-record them
  (`KACHEL_RECORD_SNAPSHOTS=1 swift test --filter UITests`) and look at them.
  `swift test` must pass.
- A new or changed setting goes into the default config in `Settings.swift`.
  Regenerate `config.example.yaml` afterwards (a test checks they match):
  `swift run Kachel --print-default-config > config.example.yaml`
- Add a line under `[Unreleased]` in [CHANGELOG.md](CHANGELOG.md) for anything a
  user would notice. Release notes are made from it.
- Update the pages in `docs/` if behaviour or settings change.
  `npm run build` in `website/` checks the links.

By contributing, you agree that your contributions are licensed under the
[MIT licence](LICENSE).

## Conduct

Be kind and assume good intent; see the [Code of Conduct](CODE_OF_CONDUCT.md).
