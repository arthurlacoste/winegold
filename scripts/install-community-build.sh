#!/bin/bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: this installer is for macOS only" >&2
  exit 1
fi

REPO="${WINE_GOLD_REPO:-arthurlacoste/winegold}"
APP_NAME="${WINE_GOLD_APP_NAME:-Winegold}"
INSTALL_DIR="${WINE_GOLD_INSTALL_DIR:-/Applications}"
TMPDIR="${TMPDIR:-/tmp}"

if [[ -z "${APP_VERSION:-}" ]]; then
  release_url="https://api.github.com/repos/${REPO}/releases/latest"
else
  release_url="https://api.github.com/repos/${REPO}/releases/tags/${APP_VERSION}"
fi

if [[ ! -w "$INSTALL_DIR" && "$INSTALL_DIR" == "/Applications" ]]; then
  if [[ $EUID -ne 0 ]]; then
    echo "Installing to /Applications requires administrative privileges."
    exec sudo bash -c "$(printf '%q' "$0") $(printf '%q ' "$@")"
  fi
fi

echo "Resolving latest release ..."
dmg_url=$(curl -fsSL "$release_url" | grep -o '"browser_download_url": *"[^"]*\.dmg"' | head -1 | cut -d'"' -f4 || true)

if [[ -z "${dmg_url:-}" ]]; then
  echo "error: no DMG found in latest release" >&2
  exit 1
fi

dmg="$(mktemp "${TMPDIR}/winegold.XXXXXX.dmg")"
cleanup() { rm -f "$dmg"; }
trap cleanup EXIT

echo "Downloading ${APP_NAME} ..."
curl -fL --progress-bar "$dmg_url" -o "$dmg"

mount_dir="$(mktemp -dt winegold-install.XXXXXX)"
cleanup_mount() {
  if [[ -n "${mount_dir:-}" && -d "$mount_dir" ]]; then
    hdiutil detach "$mount_dir" >/dev/null 2>&1 || true
    rm -rf "$mount_dir"
  fi
}
trap cleanup_mount EXIT

echo "Mounting ..."
hdiutil attach -readonly -nobrowse -mountpoint "$mount_dir" "$dmg"

app_path="$mount_dir/${APP_NAME}.app"
if [[ ! -d "$app_path" ]]; then
  echo "error: ${APP_NAME}.app not found in DMG" >&2
  exit 1
fi

echo "Copying to ${INSTALL_DIR} ..."
if [[ -e "$INSTALL_DIR/${APP_NAME}.app" ]]; then
  rm -rf "$INSTALL_DIR/${APP_NAME}.app"
fi
cp -R "$app_path" "$INSTALL_DIR/"

echo "Ad-hoc signing ..."
codesign --force --deep --sign - "$INSTALL_DIR/${APP_NAME}.app" >/dev/null 2>&1 || true
xattr -dr com.apple.quarantine "$INSTALL_DIR/${APP_NAME}.app" 2>/dev/null || true

echo "Installed ${APP_NAME} to ${INSTALL_DIR}"
open "$INSTALL_DIR/${APP_NAME}.app" 2>/dev/null || true
