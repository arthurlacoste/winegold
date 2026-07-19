#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

RECIPE_COUNT="${RECIPE_COUNT:-300}"
RUNS="${RUNS:-3}"
FIRST_FRAME_LIMIT_MS="${FIRST_FRAME_LIMIT_MS:-100}"
MATCHING_LIMIT_MS="${MATCHING_LIMIT_MS:-105}"
PUBLISH_LIMIT_MS="${PUBLISH_LIMIT_MS:-400}"
PALETTE_LIMIT_MS="${PALETTE_LIMIT_MS:-700}"
INPUT_PATH="${1:-}"

if ! [[ "$RECIPE_COUNT" =~ ^[0-9]+$ ]] || (( RECIPE_COUNT < 24 )); then
    echo "error: RECIPE_COUNT must be an integer >= 24" >&2
    exit 2
fi
if ! [[ "$RUNS" =~ ^[0-9]+$ ]] || (( RUNS < 1 )); then
    echo "error: RUNS must be an integer >= 1" >&2
    exit 2
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/winegold-recipe-stress.XXXXXX")"
RECIPES="$WORK/recipes"
SUPPORT="$WORK/support"
APP="$WORK/WinegoldNative.app"
BIN="$ROOT/.build/debug/WinegoldNative"
LOG="$SUPPORT/winegold.log"
RESULTS="$WORK/results.tsv"
FIXTURE="$WORK/fixture.json"
GENERATED_INPUT="$WORK/stress-input.txt"

cleanup() {
    pkill -x WinegoldNative 2>/dev/null || true
    if [[ "${KEEP_STRESS_FIXTURE:-0}" == "1" ]]; then
        echo "Fixture kept at: $WORK"
    else
        rm -rf "$WORK"
    fi
}
trap cleanup EXIT

mkdir -p "$RECIPES" "$SUPPORT" "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [[ -z "$INPUT_PATH" ]]; then
    python3 - "$GENERATED_INPUT" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
path.write_text(
    "WINEGOLD_STRESS_TOKEN\n"
    "project: winegold\n"
    "status: deterministic\n"
    + ("deterministic payload TODO-42\n" * 4096),
    encoding="utf-8",
)
PY
    INPUT_PATH="$GENERATED_INPUT"
fi
INPUT_PATH="$(cd "$(dirname "$INPUT_PATH")" && pwd)/$(basename "$INPUT_PATH")"
[[ -e "$INPUT_PATH" ]] || { echo "error: input does not exist: $INPUT_PATH" >&2; exit 2; }

python3 - "$RECIPES" "$RECIPE_COUNT" "$FIXTURE" <<'PY'
from pathlib import Path
import json
import sys

root = Path(sys.argv[1])
count = int(sys.argv[2])
manifest = Path(sys.argv[3])

templates = [
    ("cheap-extension", 'extension equals "txt"', True, True),
    ("cheap-kind-name", 'isFile and filename endsWith ".txt"', True, True),
    ("cheap-nested-or", '(extension equals "txt" and basename startsWith "stress") or isURL', True, True),
    ("cheap-deep", 'isFile and ((extension equals "txt" and filename contains "input") or (isURL and host exists))', True, True),
    ("cheap-regex", 'filename matches /stress-input[.]txt/i', True, True),
    ("cheap-not", 'isFile and not (extension in {"png" "jpg" "pdf"})', True, True),
    ("cheap-set", '(extension in {"txt" "md" "log"} and kind equals "file") or isText', True, True),
    ("cheap-false-extension", 'extension equals "png"', False, True),
    ("cheap-false-nested", '(extension equals "pdf" and filename contains "invoice") or isURL', False, True),
    ("cheap-false-not", 'not isFile or extension equals "zip"', False, True),

    ("metadata-size", 'size greaterThan 0', True, True),
    ("metadata-nested", 'isFile and (size greaterThan 1024 or mimeType exists)', True, True),
    ("metadata-or", '(extension equals "txt" and size lessThan 1048576) or isURL', True, True),
    ("metadata-deep", 'isFile and ((size greaterThan 100 and extension equals "txt") or (uti exists and filename contains "stress"))', True, True),
    ("metadata-false-large", 'size greaterThan 999999999', False, True),
    ("metadata-false-kind", 'isDirectory and size greaterThan 0', False, True),

    ("content-token", 'inside contains "WINEGOLD_STRESS_TOKEN"', True, True),
    ("content-nested", 'extension equals "txt" and (inside contains "WINEGOLD_STRESS_TOKEN" or inside contains "NEVER_PRESENT")', True, True),
    ("content-deep", 'isFile and ((inside contains "deterministic payload" and size greaterThan 1000) or (isURL and host exists))', True, True),
    ("content-not", 'inside contains "WINEGOLD_STRESS_TOKEN" and not (inside contains "FORBIDDEN_TOKEN")', True, True),
    ("content-regex-like", 'inside contains "TODO-42" and filename matches /stress.*[.]txt/i', True, True),
    ("content-false-missing", 'inside contains "THIS_TOKEN_DOES_NOT_EXIST"', False, True),
    ("content-false-branch", '(inside contains "NOPE" and extension equals "txt") or isURL', False, True),

    ("invalid-unclosed", 'isFile and (extension equals "txt"', False, False),
    ("invalid-operator", 'filename definitelyNotAnOperator "txt"', False, False),
]

specs = [templates[index % len(templates)] for index in range(count)]
invalid_count = sum(1 for _, _, _, valid in specs if not valid)
valid_count = count - invalid_count
expected_matches = 0
expected_palette_actions = 0
multi_action_recipes = 0

for index, (name, trigger, expected, valid) in enumerate(specs):
    path = root / f"{index:03d}-{name}.wg.yml"
    is_multi = valid and index % 10 == 0
    action_multiplier = 3 if is_multi else 1
    if valid:
        expected_palette_actions += action_multiplier
    if valid and expected:
        expected_matches += action_multiplier
    if is_multi:
        multi_action_recipes += 1
        command_block = (
            "actions:\n"
            "  - id: inspect\n"
            "    name: Inspect fixture\n"
            "    cmd:\n"
            "      exec: 'true'\n"
            "  - id: archive\n"
            "    name: Archive fixture\n"
            "    cmd:\n"
            "      exec: 'true'\n"
            "  - id: report\n"
            "    name: Report fixture\n"
            "    cmd:\n"
            "      exec: 'true'\n"
        )
    else:
        command_block = "cmd:\n  exec: 'true'\n"
    path.write_text(
        f"id: winegold.stress.{index:03d}\n"
        f"name: Stress recipe {index:03d} {name}\n"
        f"description: Deterministic fixture. expected={str(expected).lower()} valid={str(valid).lower()} multi={str(is_multi).lower()}\n"
        "version: 1.0.0\n"
        "enabled: true\n"
        f"trigger: {trigger}\n"
        + command_block,
        encoding="utf-8",
    )

manifest.write_text(json.dumps({
    "recipe_count": count,
    "template_count": len(templates),
    "valid_count": valid_count,
    "invalid_count": invalid_count,
    "multi_action_recipes": multi_action_recipes,
    "expected_palette_actions": expected_palette_actions,
    "expected_generated_matches": expected_matches,
}, indent=2), encoding="utf-8")

print(
    f"Generated {count} recipes from {len(templates)} templates: "
    f"valid={valid_count}, invalid={invalid_count}, multi={multi_action_recipes}, "
    f"expected_palette_actions={expected_palette_actions}, expected_generated_matches={expected_matches}"
)
PY

swift build --build-system native >/dev/null
cp Sources/WinegoldNative/WinegoldNative-Info.plist "$APP/Contents/Info.plist"
cp "$BIN" "$APP/Contents/MacOS/WinegoldNative"
chmod +x "$APP/Contents/MacOS/WinegoldNative"

if [[ "${WINEGOLD_SKIP_MACOS_CONFIRMATION:-0}" != "1" ]]; then
    pkill -x WinegoldNative 2>/dev/null || true
    open -n -F "$APP"
    printf 'Validate any macOS dialogs, then press Return to start measurements: '
    read -r
    pkill -x WinegoldNative 2>/dev/null || true
fi

# PR25: opening without input must publish the complete searchable palette.
pkill -x WinegoldNative 2>/dev/null || true
rm -f "$SUPPORT/winegold.db" "$LOG"
open -n -F \
    --env "WINEGOLD_APP_SUPPORT_DIR=$SUPPORT" \
    --env "WINEGOLD_RECIPE_ROOT=$RECIPES" \
    --env "WINEGOLD_UI_TEST_SHOW_PANEL=1" \
    "$APP"
for _ in $(seq 1 500); do
    grep -q '\[Perf\] palette_published' "$LOG" 2>/dev/null && break
    sleep 0.02
done
python3 - "$LOG" "$FIXTURE" "$PALETTE_LIMIT_MS" <<'PYCHECK'
from pathlib import Path
import json, re, sys
text = Path(sys.argv[1]).read_text(encoding="utf-8")
fixture = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
limit = float(sys.argv[3])
def value(marker):
    match = re.search(rf"\[Perf\] {marker} uptime=([0-9.]+)", text)
    if not match: raise SystemExit(f"missing {marker}\n{text[-4000:]}")
    return float(match.group(1))
match = re.search(r"\[Perf\] palette_published uptime=([0-9.]+).* actions=([0-9]+)", text)
if not match: raise SystemExit(f"missing palette_published\n{text[-4000:]}")
latency = (float(match.group(1)) - value("panel_open_requested")) * 1000
actions = int(match.group(2))
expected = int(fixture["expected_palette_actions"])
if actions < expected: raise SystemExit(f"palette published {actions}, expected at least {expected}")
if latency >= limit: raise SystemExit(f"palette publication {latency:.2f} >= {limit:.2f} ms")
print(f"palette: published={latency:.2f} ms actions={actions} expected_generated={expected}")
PYCHECK
pkill -x WinegoldNative 2>/dev/null || true

printf 'run\tfirst_frame_ms\tmatching_ms\tpublish_ms\tmatches\tinvalid_isolated\n' > "$RESULTS"

for run in $(seq 1 "$RUNS"); do
    pkill -x WinegoldNative 2>/dev/null || true
    rm -f "$SUPPORT/winegold.db" "$LOG"

    open -n -F \
        --env "WINEGOLD_APP_SUPPORT_DIR=$SUPPORT" \
        --env "WINEGOLD_RECIPE_ROOT=$RECIPES" \
        --env "WINEGOLD_UI_TEST_DRAG_PATH=$INPUT_PATH" \
        "$APP"

    for _ in $(seq 1 500); do
        grep -q '\[Perf\] matching_published .* remaining=0' "$LOG" 2>/dev/null && break
        sleep 0.02
    done

    python3 - "$LOG" "$run" "$RESULTS" "$FIXTURE" <<'PY'
from pathlib import Path
import json
import re
import sys

log = Path(sys.argv[1])
run = int(sys.argv[2])
results = Path(sys.argv[3])
fixture = json.loads(Path(sys.argv[4]).read_text(encoding="utf-8"))
expected = int(fixture["expected_generated_matches"])
invalid_expected = int(fixture["invalid_count"])
text = log.read_text(encoding="utf-8") if log.exists() else ""

def uptime(marker):
    match = re.search(rf"\[Perf\] {marker} uptime=([0-9.]+)", text)
    if not match:
        raise SystemExit(f"missing {marker} in run {run}\n{text[-4000:]}")
    return float(match.group(1))

open_time = uptime("panel_open_requested")
frame_time = uptime("panel_first_frame")
start_time = uptime("matching_started")
complete_time = uptime("matching_completed")
final = re.search(r"\[Perf\] matching_published uptime=([0-9.]+).* matches=([0-9]+) remaining=0", text)
if not final:
    raise SystemExit(f"missing final matching publication in run {run}\n{text[-4000:]}")

publish_time = float(final.group(1))
matches = int(final.group(2))
refresh_times = [float(value) for value in re.findall(r"\[Perf\] partial_refresh duration_ms=([0-9.]+)", text)]
if not refresh_times:
    raise SystemExit(f"missing partial refresh measurement in run {run}")
if max(refresh_times) >= 16:
    raise SystemExit(f"partial refresh exceeded 16 ms in run {run}: {max(refresh_times):.2f} ms")
if matches < expected:
    raise SystemExit(f"expected at least {expected} generated matches, got {matches} total in run {run}")

invalid_isolated = invalid_expected > 0 and "matching_completed" in text
first_ms = (frame_time - open_time) * 1000
matching_ms = (complete_time - start_time) * 1000
publish_ms = (publish_time - open_time) * 1000

with results.open("a", encoding="utf-8") as handle:
    handle.write(
        f"{run}\t{first_ms:.2f}\t{matching_ms:.2f}\t{publish_ms:.2f}\t"
        f"{matches}\t{int(invalid_isolated)}\n"
    )

print(
    f"run {run}: first={first_ms:.2f} ms matching={matching_ms:.2f} ms "
    f"published={publish_ms:.2f} ms matches={matches} invalid_isolated={invalid_isolated}"
)
PY

done

python3 - "$RESULTS" "$FIRST_FRAME_LIMIT_MS" "$MATCHING_LIMIT_MS" "$PUBLISH_LIMIT_MS" <<'PY'
from pathlib import Path
import statistics
import sys

lines = Path(sys.argv[1]).read_text().strip().splitlines()[1:]
rows = [line.split("\t") for line in lines]
first = [float(row[1]) for row in rows]
matching = [float(row[2]) for row in rows]
publish = [float(row[3]) for row in rows]
invalid_isolated = [int(row[5]) for row in rows]
limits = [float(value) for value in sys.argv[2:5]]

print(
    f"median: first={statistics.median(first):.2f} ms "
    f"matching={statistics.median(matching):.2f} ms "
    f"published={statistics.median(publish):.2f} ms"
)
print(
    f"worst:  first={max(first):.2f} ms "
    f"matching={max(matching):.2f} ms "
    f"published={max(publish):.2f} ms"
)

failures = []
if max(first) >= limits[0]:
    failures.append(f"first frame {max(first):.2f} >= {limits[0]:.2f} ms")
if max(matching) >= limits[1]:
    failures.append(f"matching {max(matching):.2f} >= {limits[1]:.2f} ms")
if max(publish) >= limits[2]:
    failures.append(f"publication {max(publish):.2f} >= {limits[2]:.2f} ms")
if not all(invalid_isolated):
    failures.append("invalid triggers were not isolated")
if failures:
    raise SystemExit("stress test failed: " + "; ".join(failures))
print("mixed recipe stress test passed")
PY
