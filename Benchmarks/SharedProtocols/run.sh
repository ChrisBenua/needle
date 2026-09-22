#!/usr/bin/env bash
#
# Builds the benchmark twice in release — once against upstream uber/needle,
# once against this fork — samples each, prints the comparison table, and
# checks the thresholds (upstream pass #2 > 1 s, fork pass #2 < 100 ms).
#
# Every sample is a FRESH PROCESS, and that is load-bearing. Pass #2 is measured
# against a cold Swift-runtime conformance cache; re-running it inside the same
# process would measure a warm one and quietly erase the effect the benchmark
# exists to show. Do not "optimise" this into an in-process loop.

set -euo pipefail

cd "$(dirname "$0")"

samples=5
check=1
while [ $# -gt 0 ]; do
    case "$1" in
        --samples) samples="$2"; shift 2 ;;
        --no-check) check=0; shift ;;
        -h|--help) sed -n '2,10p' "$0"; echo "usage: $0 [--samples N] [--no-check]"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

# Both modes share one Package.resolved path; SwiftPM rewrites it per mode, which
# is fine. Do NOT delete it between modes: that forces a full ~15-minute rebuild
# of the generated sources instead of an incremental one.
build() {
    local mode="$1"
    echo "Building ${mode} (release)…" >&2
    NEEDLE_SOURCE="${mode}" swift build -c release --scratch-path ".build-${mode}" >&2
    NEEDLE_SOURCE="${mode}" swift build -c release --scratch-path ".build-${mode}" --show-bin-path
}

upstream_bin=$(build upstream)
fork_bin=$(build fork)

# Minimum over the samples, per phase: the fastest run is the one least
# disturbed by other work on the machine.
collect() {
    local bin="$1"
    local i
    for ((i = 0; i < samples; i++)); do
        "${bin}/BenchNeedle" --json
    done | python3 -c '
import json, sys
rows = [json.loads(line) for line in sys.stdin if line.strip()]
print(rows[0]["types"], *(min(r[k] for r in rows) for k in ("pass1", "pass2", "pass3")))
'
}

echo "Sampling upstream ($samples fresh processes)…"
upstream=$(collect "$upstream_bin")
echo "Sampling fork     ($samples fresh processes)…"
fork=$(collect "$fork_bin")

python3 - "$upstream" "$fork" "$check" <<'PY'
import sys

types, u1, u2, u3 = (float(x) for x in sys.argv[1].split())
_,     f1, f2, f3 = (float(x) for x in sys.argv[2].split())
check = sys.argv[3] == "1"
n = int(types)

print()
print(f"{n} `shared` properties typed as protocols, best of each phase\n")
print(f"| {'phase':<24} | {'upstream':>12} | {'fork':>12} | {'speedup':>8} |")
print("|" + "-" * 26 + "|" + "-" * 14 + "|" + "-" * 14 + "|" + "-" * 10 + "|")

def row(label, u, f):
    print(f"| {label:<24} | {u / n * 1e6:>9.2f} µs | {f / n * 1e6:>9.2f} µs | {u / f:>7.2f}x |")

row("pass #1 (construct)", u1, f1)
row("pass #2 (hit, cold)", u2, f2)
row("pass #3 (hit, warm)", u3, f3)
print()
print(f"totals: upstream #1 {u1:.4f}s  #2 {u2:.4f}s  #3 {u3:.4f}s")
print(f"        fork     #1 {f1:.4f}s  #2 {f2:.4f}s  #3 {f3:.4f}s")

if check:
    ok = True
    if u2 <= 1.0:
        print(f"CHECK FAILED: upstream pass #2 took {u2:.4f}s, expected > 1s")
        ok = False
    if f2 >= 0.1:
        print(f"CHECK FAILED: fork pass #2 took {f2:.4f}s, expected < 100ms")
        ok = False
    if not ok:
        sys.exit(1)
    print("\nchecks passed: upstream pass #2 > 1s, fork pass #2 < 100ms")
PY
