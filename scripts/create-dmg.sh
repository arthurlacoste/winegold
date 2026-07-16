#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/.build/artifacts/Winegold.app}"
DMG="${2:-$ROOT/.build/artifacts/Winegold-macOS.dmg}"
VOLUME_NAME="${3:-Winegold}"

if [[ ! -d "$APP" ]]; then
    echo "error: app bundle not found at $APP" >&2
    exit 1
fi

if [[ ! -x "$APP/Contents/MacOS/WinegoldNative" ]]; then
    echo "error: app bundle is missing WinegoldNative executable" >&2
    exit 1
fi

if ! command -v hdiutil >/dev/null 2>&1; then
    echo "error: hdiutil is required to create a DMG" >&2
    exit 1
fi

STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/winegold-dmg.XXXXXX")"
cleanup() {
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

mkdir -p "$(dirname "$DMG")"
rm -f "$DMG"

APP_NAME="$(basename "$APP")"
ditto "$APP" "$STAGING_DIR/$APP_NAME"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -format UDZO \
    -ov \
    "$DMG" >/dev/null

if [[ ! -s "$DMG" ]]; then
    echo "error: disk image was not created at $DMG" >&2
    exit 1
fi

echo "$DMG"
