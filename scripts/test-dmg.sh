#!/bin/bash
set -euo pipefail

DMG="${1:-}"

if [[ -z "$DMG" ]]; then
    echo "usage: $0 path/to/Winegold.dmg" >&2
    exit 2
fi

if [[ ! -s "$DMG" ]]; then
    echo "error: DMG not found or empty at $DMG" >&2
    exit 1
fi

ATTACH_PLIST="$(mktemp "${TMPDIR:-/tmp}/winegold-dmg-attach.XXXXXX")"
MOUNT_POINT=""
cleanup() {
    if [[ -n "$MOUNT_POINT" && -d "$MOUNT_POINT" ]]; then
        hdiutil detach "$MOUNT_POINT" >/dev/null || true
    fi
    rm -f "$ATTACH_PLIST"
}
trap cleanup EXIT

hdiutil attach -readonly -nobrowse -plist "$DMG" > "$ATTACH_PLIST"

entity_count="$(/usr/libexec/PlistBuddy -c 'Print :system-entities' "$ATTACH_PLIST" 2>/dev/null | grep -c 'Dict {' || true)"
for ((index = 0; index < entity_count; index++)); do
    candidate="$(/usr/libexec/PlistBuddy -c "Print :system-entities:$index:mount-point" "$ATTACH_PLIST" 2>/dev/null || true)"
    if [[ -n "$candidate" ]]; then
        MOUNT_POINT="$candidate"
        break
    fi
done

if [[ -z "$MOUNT_POINT" || ! -d "$MOUNT_POINT" ]]; then
    echo "error: could not determine mounted DMG path" >&2
    exit 1
fi

if [[ ! -d "$MOUNT_POINT/Winegold.app" ]]; then
    echo "error: Winegold.app is missing from DMG" >&2
    exit 1
fi

if [[ ! -x "$MOUNT_POINT/Winegold.app/Contents/MacOS/WinegoldNative" ]]; then
    echo "error: Winegold.app executable is missing from DMG" >&2
    exit 1
fi

if [[ ! -L "$MOUNT_POINT/Applications" ]]; then
    echo "error: Applications symlink is missing from DMG" >&2
    exit 1
fi

if [[ "$(readlink "$MOUNT_POINT/Applications")" != "/Applications" ]]; then
    echo "error: Applications symlink does not target /Applications" >&2
    exit 1
fi

echo "DMG contents verified at $MOUNT_POINT"
