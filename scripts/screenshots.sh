#!/bin/bash
# Re-render the README images in assets/screenshots with Kachel's own views
# and made-up content (see Sources/Kachel/Screenshots.swift).
set -euo pipefail
cd "$(dirname "$0")/.."
swift build
"$(swift build --show-bin-path)/Kachel" --render-screenshots assets/screenshots
