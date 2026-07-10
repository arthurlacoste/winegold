#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

swift build --build-system native

APP=".build/debug/WinegoldNative.app"
BIN=".build/debug/WinegoldNative"

pkill -x WinegoldNative 2>/dev/null || true
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Sources/WinegoldNative/WinegoldNative-Info.plist "$APP/Contents/Info.plist"
cp Sources/WinegoldNative/Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Sources/WinegoldNative/Resources/icon-bar.svg "$APP/Contents/Resources/icon-bar.svg"
rm -rf "$APP/Contents/Resources/AppIcon.icon"
cp -R Sources/WinegoldNative/Resources/AppIcon.icon "$APP/Contents/Resources/AppIcon.icon"
cp "$BIN" "$APP/Contents/MacOS/WinegoldNative"
chmod +x "$APP/Contents/MacOS/WinegoldNative"
printf 'APPL????' > "$APP/Contents/PkgInfo"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

if ! open -n "$APP"; then
  echo "open failed, launching executable directly" >&2
  "$APP/Contents/MacOS/WinegoldNative" >/tmp/winegold-native.out 2>/tmp/winegold-native.err &
  disown
fi
