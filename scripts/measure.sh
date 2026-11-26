#!/bin/bash
# How much CPU and memory the running Kachel uses, measured the same
# way every time. Leave the Mac alone while it runs (that's the idle number).
#
#   scripts/measure.sh            # 60 seconds
#   scripts/measure.sh 120        # longer
#   SAMPLE=1 scripts/measure.sh   # also where the time goes (call stacks)
#
# Targets (docs/development.md): idle CPU under 0.5 %, memory under 100 MB.
set -euo pipefail

secs="${1:-60}"
pid=$(pgrep -f 'Kachel.app/Contents/MacOS/Kachel$' | head -1 || true)
[ -n "$pid" ] || { echo "Kachel isn't running" >&2; exit 1; }
count=$(pgrep -f 'Kachel.app/Contents/MacOS/Kachel$' | wc -l | tr -d ' ')
[ "$count" = 1 ] || echo "note: $count Kachel processes are running; measuring $pid" >&2

app=$(ps -o command= -p "$pid" | sed 's|/Contents/MacOS/Kachel$||')
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist" 2>/dev/null || echo '?')

# CPU time used so far, in seconds ("[[dd-]hh:]mm:ss.cc").
cputime() {
    ps -o time= -p "$pid" | awk -F'[:-]' '{ s = 0; for (i = 1; i <= NF; i++) s = s * 60 + $i; print s }'
}

echo "Kachel $version (pid $pid): measuring for $secs s…"
c0=$(cputime); t0=$(date +%s)
if [ "${SAMPLE:-}" = 1 ]; then
    out="${TMPDIR:-/tmp}/kachel-sample.txt"
    sample "$pid" "$secs" -file "$out" >/dev/null 2>&1 || true
else
    sleep "$secs"
fi
c1=$(cputime); t1=$(date +%s)
elapsed=$((t1 - t0))

footprint=$(vmmap --summary "$pid" 2>/dev/null | awk '/^Physical footprint:/ { print $3 }')
threads=$(ps -M -p "$pid" | tail -n +2 | wc -l | tr -d ' ')

awk -v c="$(echo "$c1 - $c0" | bc)" -v e="$elapsed" \
    -v mem="$footprint" -v th="$threads" 'BEGIN {
    printf "  CPU        %.2f %%  (%.2f s in %d s)\n", 100 * c / e, c, e
    printf "  memory     %s\n", mem
    printf "  threads    %d\n", th
}'

if [ "${SAMPLE:-}" = 1 ]; then
    echo
    echo "Main thread, Kachel's own functions (samples, 1 ms each):"
    awk '/Main Thread/ { on = 1; next } on && /^    [0-9]+ Thread_/ { exit } on' "$out" \
        | grep '(in Kachel)' | sed -E 's/^[ +!:|]*//; s/ \(in Kachel\).*//' \
        | awk '{ n = $1; $1 = ""; if (n > best[$0]) best[$0] = n } END { for (k in best) print best[k], k }' \
        | sort -rn | sed -n '2,16p'
    echo "Full call stacks: $out"
fi
