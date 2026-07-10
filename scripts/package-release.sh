#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/.build/artifacts/Winegold.app}"
ZIP="${2:-$ROOT/.build/artifacts/Winegold-macOS.zip}"

if [[ ! -d "$APP" ]]; then
    echo "error: app bundle not found at $APP" >&2
    exit 1
fi

if [[ ! -x "$APP/Contents/MacOS/WinegoldNative" ]]; then
    echo "error: app bundle is missing WinegoldNative executable" >&2
    exit 1
fi

mkdir -p "$(dirname "$ZIP")"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

if [[ ! -s "$ZIP" ]]; then
    echo "error: release archive was not created at $ZIP" >&2
    exit 1
fi

echo "$ZIP"
