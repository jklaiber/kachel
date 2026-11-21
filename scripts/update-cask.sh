#!/bin/bash
# Write Casks/kachel.rb into jklaiber/homebrew-tap for a released version.
#   ./scripts/update-cask.sh 0.1.0 <sha256 of Kachel-0.1.0.zip>
# In CI it pushes with $TAP_GITHUB_TOKEN; locally it uses your SSH key.
set -euo pipefail
VERSION="$1"
SHA="$2"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
if [[ -n "${TAP_GITHUB_TOKEN:-}" ]]; then
    git clone -q "https://x-access-token:${TAP_GITHUB_TOKEN}@github.com/jklaiber/homebrew-tap.git" "$WORK/tap"
    git -C "$WORK/tap" config user.name "github-actions[bot]"
    git -C "$WORK/tap" config user.email "41898282+github-actions[bot]@users.noreply.github.com"
else
    git clone -q git@github.com:jklaiber/homebrew-tap.git "$WORK/tap"
fi

mkdir -p "$WORK/tap/Casks"
cat > "$WORK/tap/Casks/kachel.rb" <<CASK
# This file is written by scripts/update-cask.sh in jklaiber/kachel. Don't edit.
cask "kachel" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/jklaiber/kachel/releases/download/v#{version}/Kachel-#{version}.zip"
  name "Kachel"
  desc "Tiling window manager with xmonad's workspace model"
  homepage "https://github.com/jklaiber/kachel"

  depends_on macos: :tahoe

  app "Kachel.app"
  # The `kachel` command: the app's own executable, which acts as the
  # command line tool when started under this name.
  binary "#{appdir}/Kachel.app/Contents/MacOS/Kachel", target: "kachel"

  # Kachel is signed with its own certificate but not notarized (no paid
  # Apple Developer ID); without this macOS refuses to open the downloaded app.
  postflight_steps do
    run "/usr/bin/xattr",
        args:           ["-dr", "com.apple.quarantine", "{{appdir}}/Kachel.app"],
        must_succeed:   false,
        writable_paths: ["{{appdir}}/Kachel.app"]
  end

  uninstall quit: "io.github.jklaiber.kachel"

  zap trash: [
    "~/.config/kachel",
    "~/Library/Application Support/Kachel",
    "~/Library/Logs/Kachel.log",
  ]

  caveats <<~EOS
    Kachel needs Accessibility permission: System Settings → Privacy & Security
    → Accessibility. Upgrades keep it.

    Quit Amethyst, yabai or AeroSpace first, and use one Space per display.
    Config: ~/.config/kachel/config.yaml (written on first launch).
  EOS
end
CASK

cd "$WORK/tap"
if git diff --quiet && git diff --cached --quiet && [[ -z "$(git status --porcelain)" ]]; then
    echo "cask already up to date"
    exit 0
fi
git add Casks/kachel.rb
git commit -q -m "kachel $VERSION"
git push -q
echo "pushed Casks/kachel.rb ($VERSION) to jklaiber/homebrew-tap"
