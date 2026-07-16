#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build --build-system native >/dev/null
APP=".build/debug/WinegoldNative.app"
BIN=".build/debug/WinegoldNative"
LOG="$HOME/Library/Application Support/WinegoldNative/winegold.log"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Sources/WinegoldNative/WinegoldNative-Info.plist "$APP/Contents/Info.plist"
cp "$BIN" "$APP/Contents/MacOS/WinegoldNative"
chmod +x "$APP/Contents/MacOS/WinegoldNative"

run_case() {
  local name="$1"
  shift
  pkill -x WinegoldNative 2>/dev/null || true
  : > "$LOG"
  local open_args=( -n -F )
  for variable in "$@"; do open_args+=( --env "$variable" ); done
  open_args+=( "$APP" )
  open "${open_args[@]}"
  local pid=""
  for _ in $(seq 1 50); do
    pid=$(pgrep -n -x WinegoldNative || true)
    [[ -n "$pid" ]] && break
    sleep 0.02
  done
  for _ in $(seq 1 100); do
    grep -q '\[Perf\] panel_first_frame' "$LOG" && break
    sleep 0.02
  done
  screencapture -x "/tmp/winegold-${name}.png" 2>/dev/null || true
  python3 - "$LOG" "$name" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
def value(marker):
    match = re.search(rf"\[Perf\] {marker} uptime=([0-9.]+)", text)
    if not match:
        raise SystemExit(f"missing {marker} for {sys.argv[2]}")
    return float(match.group(1))
latency = (value("panel_first_frame") - value("panel_open_requested")) * 1000
print(f"{sys.argv[2]} first-frame latency: {latency:.2f} ms")
if latency >= 100:
    raise SystemExit(f"first-frame latency exceeded 100 ms: {latency:.2f} ms")
PY
  [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
}

run_case shortcut WINEGOLD_UI_TEST_SHOW_PANEL=1 WINEGOLD_UI_TEST_TOGGLE_CLOSE=1
run_case drag WINEGOLD_UI_TEST_DRAG_PATH="${1:-/tmp}"
