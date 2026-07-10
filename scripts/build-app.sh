#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIGURATION="${CONFIGURATION:-release}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT/.build/artifacts}"
INFO_PLIST="$ROOT/Sources/WinegoldNative/WinegoldNative-Info.plist"
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
APP_NAME="${APP_NAME:-Winegold}"
EXECUTABLE_NAME="${EXECUTABLE_NAME:-WinegoldNative}"
APP="$OUTPUT_DIR/${APP_NAME}.app"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: VERSION must use MAJOR.MINOR.PATCH, got '$VERSION'" >&2
    exit 1
fi

if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "error: BUILD_NUMBER must be a positive integer, got '$BUILD_NUMBER'" >&2
    exit 1
fi

swift build -c "$CONFIGURATION" --build-system native
BIN_DIR="$(swift build -c "$CONFIGURATION" --build-system native --show-bin-path)"
BIN="$BIN_DIR/WinegoldNative"

if [[ ! -x "$BIN" ]]; then
    echo "error: release executable not found at $BIN" >&2
    exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$INFO_PLIST" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $APP_NAME" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $EXECUTABLE_NAME" "$APP/Contents/Info.plist"

cp "$ROOT/Sources/WinegoldNative/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/Sources/WinegoldNative/Resources/icon-bar.svg" "$APP/Contents/Resources/icon-bar.svg"
cp -R "$ROOT/Sources/WinegoldNative/Resources/AppIcon.icon" "$APP/Contents/Resources/AppIcon.icon"
cp "$BIN" "$APP/Contents/MacOS/$EXECUTABLE_NAME"
chmod +x "$APP/Contents/MacOS/$EXECUTABLE_NAME"
printf 'APPL????' > "$APP/Contents/PkgInfo"

xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

if [[ ! -x "$APP/Contents/MacOS/$EXECUTABLE_NAME" ]]; then
    echo "error: packaged app does not contain an executable" >&2
    exit 1
fi

if [[ ! -f "$APP/Contents/Resources/AppIcon.icns" || ! -f "$APP/Contents/Resources/icon-bar.svg" ]]; then
    echo "error: packaged app is missing required resources" >&2
    exit 1
fi

echo "$APP"
