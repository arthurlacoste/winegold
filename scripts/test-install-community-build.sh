#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/install-community-build.sh"

pass=0
fail=0
failures=()

assert() {
  if "$@"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    failures+=("$*")
    echo "FAIL: $*" >&2
  fi
}

failinfo() {
  echo >&2
  echo "Install script test failures: $fail" >&2
  for f in "${failures[@]}"; do
    echo "- $f" >&2
  done
  echo >&2
}
trap 'failinfo' EXIT

# 1. Script exists and is executable
assert test -f "$SCRIPT"
assert test -x "$SCRIPT"

# 2. Reject non-macOS without running actual install path completely
DARWIN_CAPTURED=0
if ! uname -s | grep -qi '^darwin$'; then
  DARWIN_CAPTURED=1
  export WINE_GOLD_REPO="nonexistent-owner/winegold-test-repo-does-not-exist"
  export APP_VERSION="v0.0.1-test-nope"
  if "$SCRIPT"; then
    echo "FAIL: script should fail on non-darwin" >&2
    fail=$((fail + 1))
  else
    pass=$((pass + 1))
  fi
fi

if [[ "$DARWIN_CAPTURED" -eq 0 ]]; then
  TMP_DIR="$(mktemp -dt winegold-installer-test.XXXXXX)"
  cleanup() { rm -rf "$TMP_DIR"; }
  trap cleanup EXIT

  INSTALL_DIR="$TMP_DIR/Applications"
  mkdir -p "$INSTALL_DIR"
  export WINE_GOLD_REPO="arthurlacoste/winegold"
  export APP_NAME="WinegoldTestApp"
  export INSTALL_DIR
  export TMPDIR="$TMP_DIR"

  # 3. Resolve latest release and install using script defaults on macOS
  assert "$SCRIPT"

  app_path="$INSTALL_DIR/${APP_NAME}.app"
  assert test -d "$app_path"

  # 4. Ad-hoc signature is present
  signature=$(codesign -dvvv "$app_path" 2>&1 || true)
  assert echo "$signature" | grep -qi 'adhoc'

  # 5. Quarantine attribute is removed
  quarantine=$(xattr -l "$app_path" 2>/dev/null | grep -i '^com.apple.quarantine' || true)
  assert test -z "$quarantine"

  # 6. Symlink cleanup is consistent (build script expects Applications at /Applications or custom symlink)
  if [[ -L "$INSTALL_DIR/Applications" ]]; then
    target=$(readlink "$INSTALL_DIR/Applications" || true)
    assert test "$target" = "/Applications"
  fi
fi

trap - EXIT
if [[ "$fail" -eq 0 ]]; then
  echo "install-community-build test passed: $pass assertions" >&2
  exit 0
else
  failinfo
  exit 1
fi
