#!/bin/bash
# Release notes for a version, from CHANGELOG.md:
#   ./scripts/release-notes.sh 0.1.5 > notes.md
# Fails if CHANGELOG.md has no section for that version, so nothing is
# released without notes.
set -euo pipefail
cd "$(dirname "$0")/.."
V="${1#v}"

section="$(awk -v v="$V" '
    $0 ~ "^## \\[" v "\\]" { on = 1; next }
    on && /^## \[/ { exit }
    on && /^\[[^]]+\]: / { exit }
    on { print }
' CHANGELOG.md)"
# Trim leading/trailing blank lines.
section="$(printf '%s\n' "$section" | sed -e '/./,$!d' | sed -e ':a' -e '/^\n*$/{$d;N;ba' -e '}')"
if [[ -z "${section//[[:space:]]/}" ]]; then
    echo "error: CHANGELOG.md has no section for $V" >&2
    exit 1
fi

# Links relative to the repo (e.g. config.example.yaml) don't work on the
# releases page: point them at the files as of this version.
section="$(printf '%s\n' "$section" | sed -E "s#\]\(([^):/#][^):]*)\)#](https://github.com/jklaiber/kachel/blob/v$V/\1)#g")"

compare="$(grep -E "^\[$V\]: " CHANGELOG.md | sed -E "s/^\[$V\]: //" || true)"

cat <<NOTES
$section

## Install or upgrade

\`\`\`bash
brew install --cask jklaiber/tap/kachel     # first time
brew upgrade --cask kachel                  # from an earlier version
\`\`\`

Or download \`Kachel-$V.zip\` below (universal: Apple Silicon and Intel).
After installing or upgrading, grant Accessibility again under System Settings →
Privacy & Security → Accessibility: the app is ad-hoc signed, so macOS treats each
version as a new app.
NOTES
if [[ -n "$compare" && "$compare" == *compare* ]]; then
    printf '\n**Full changelog**: %s\n' "$compare"
fi
