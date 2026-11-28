#!/bin/bash
# Start the built app like a user would and check that it runs, on whatever
# macOS this is (CI runs it on several versions and on Intel). Accessibility
# can't be granted here, so this covers start-up, the bar, Settings and the
# kachel command, not moving windows; the tests cover that with fakes.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/Kachel.app/Contents/MacOS/Kachel"
LOG="$HOME/Library/Logs/Kachel.log"

echo "== version"
"$APP" --version

echo "== start"
"$APP" & PID=$!
for _ in $(seq 1 40); do
    sleep 0.5
    "$APP" --ctl version >/dev/null 2>&1 && break
done
"$APP" --ctl version                       # the socket answers
"$APP" --ctl settings                      # Settings opens (SwiftUI)
if "$APP" --ctl subscribe nothing 2>/dev/null; then
    echo "subscribe took an event that doesn't exist" >&2; exit 1
fi
"$APP" --ctl subscribe >/dev/null & SUB=$!   # listens until Kachel quits
sleep 5
kill -0 "$PID"                             # still running after a few seconds

echo "== quit"
kill -TERM "$PID"
wait "$PID" || true
wait "$SUB"                                # the subscriber ended cleanly
grep -q "starting Kachel" "$LOG"
tail -1 "$LOG" | grep -q "quit"

echo "== drawing (the documentation images)"
OUT="$(mktemp -d)"
"$APP" --render-screenshots "$OUT"
test "$(ls "$OUT"/*.png | wc -l)" -ge 6

echo "smoke test passed"
