#!/bin/zsh
set -euo pipefail

# Fixture-only UI benchmark. Runs the app with inert adapters and a scaled
# history (about 900 entries) and reports page switch times and focus checks.
# Usage: ./script/measure_ui_performance.sh [app_path] [runs]

script_dir=${0:A:h}
project_dir=${script_dir:h}
app_path=${1:-"$project_dir/dist/Lerro.app"}
runs=${2:-3}
page_switch_budget_ms=70
launch_timeout_seconds=60
bundle_id=app.lerro.mac
frame_key="NSWindow Frame main"
frame_value="200 150 988 690 0 0 1920 1050 "
binary="$app_path/Contents/MacOS/Lerro"

[[ -x "$binary" ]] || {
    print -u2 "Missing app binary: $binary"
    exit 64
}

print "Load average: $(uptime | sed 's/.*load averages*: //')"
print "Results are noisy under load."

# Fixture runs share the bundle id, so AppKit autosaves the window frame
# into the real defaults domain. Restore it when the script exits.
had_frame=0
if saved_frame=$(defaults read "$bundle_id" "$frame_key" 2>/dev/null); then
    had_frame=1
fi
work_dir=$(mktemp -d)
restore_state() {
    if (( had_frame )); then
        defaults write "$bundle_id" "$frame_key" -string "$saved_frame"
    else
        defaults delete "$bundle_id" "$frame_key" 2>/dev/null || true
    fi
    rm -rf "$work_dir"
}
trap restore_state EXIT

# run_app <mode> <output_file>: one launch, killed after the timeout.
run_app() {
    local mode=$1 output=$2
    LERRO_FIXTURE_MODE=1 LERRO_FIXTURE_SCALE=large LERRO_FIXTURE_BENCHMARK=$mode \
        "$binary" -"$frame_key" "$frame_value" >"$output" 2>/dev/null &
    local app_pid=$!
    ( sleep $launch_timeout_seconds; kill $app_pid 2>/dev/null ) &
    local watchdog_pid=$!
    wait $app_pid || true
    pkill -P $watchdog_pid 2>/dev/null || true
    kill $watchdog_pid 2>/dev/null || true
}

: >"$work_dir/page-switch.txt"
for run in {1..$runs}; do
    print "Page switch run $run of $runs"
    run_app page-switch "$work_dir/run.txt"
    grep '^BENCHMARK page-switch' "$work_dir/run.txt" >>"$work_dir/page-switch.txt" || {
        print -u2 "Run $run produced no page-switch lines"
    }
done

result=0
python3 - "$work_dir/page-switch.txt" "$page_switch_budget_ms" <<'PY' || result=1
import re
import statistics
import sys

lines = open(sys.argv[1]).read().splitlines()
budget = float(sys.argv[2])
pages = {}
for line in lines:
    fields = dict(re.findall(r"(\w+)=(\S+)", line))
    pages.setdefault(fields["page"], []).append(
        (float(fields["median_ms"]), float(fields["cpu_median_ms"]))
    )
if not pages:
    print("No page-switch results.")
    sys.exit(1)
over = False
print(f"Page switch median across runs (budget {budget:g} ms)")
for page, samples in pages.items():
    wall = statistics.median(s[0] for s in samples)
    cpu = statistics.median(s[1] for s in samples)
    verdict = "OK" if wall <= budget else "OVER"
    over = over or verdict == "OVER"
    print(f"  {page:<11} wall {wall:6.1f} ms  cpu {cpu:6.1f} ms  {verdict}")
sys.exit(1 if over else 0)
PY

print "Focus check"
run_app focus "$work_dir/focus.txt"
cat "$work_dir/focus.txt"
grep -q '^BENCHMARK focus result=pass' "$work_dir/focus.txt" || result=1

exit $result
