#!/bin/bash
# Builds a Debug Mousse.app, signs it with the local Apple Development identity,
# installs it to ~/Applications and relaunches it from there (a stable path keeps the
# login item valid even when build/ is wiped).
#
# ENABLE_DEBUG_DYLIB=NO keeps the code in the main executable; otherwise Xcode's
# separate Mousse.debug.dylib keeps its ad-hoc signature and dyld refuses to load it
# into the re-signed (hardened) app.
#
# Signing with a stable identity (instead of ad-hoc) keeps macOS privacy permissions
# (Input Monitoring, Screen Recording) attached to the app across rebuilds.
#
# Usage: ./scripts/run_dev.sh
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP_NAME="Mousse"
BUILD_DIR="$ROOT/build"

export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
XCODEBUILD="$DEVELOPER_DIR/usr/bin/xcodebuild"

echo "==> Generating Xcode project"
xcodegen generate --quiet

echo "==> Building Debug"
"$XCODEBUILD" \
  -project "$APP_NAME.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Debug \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  ENABLE_DEBUG_DYLIB=NO \
  build -quiet 2>&1 | grep -vE "DVTPlugIn|CoreSimulator|CoreDevice|IDERunDestination|appintentsmetadataprocessor|Details:|Recovery Suggestion|^Code: |^--|^\{ platform|matching destinations|^$" || true

APP_PATH="$BUILD_DIR/Build/Products/Debug/$APP_NAME.app"
[ -d "$APP_PATH" ] || { echo "Build failed: $APP_PATH not found"; exit 1; }

IDENTITY="$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')"
if [ -n "$IDENTITY" ]; then
  echo "==> Signing with: $IDENTITY"
  codesign --force --options runtime \
    --entitlements "$ROOT/$APP_NAME/$APP_NAME.entitlements" \
    --sign "$IDENTITY" "$APP_PATH"
else
  echo "==> No Apple Development identity found; ad-hoc signing (permissions reset on each build)"
  codesign --force --entitlements "$ROOT/$APP_NAME/$APP_NAME.entitlements" --sign - "$APP_PATH"
fi

echo "==> Installing to ~/Applications"
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 0.5
INSTALL_PATH="$HOME/Applications/$APP_NAME.app"
mkdir -p "$HOME/Applications"
rm -rf "$INSTALL_PATH"
cp -R "$APP_PATH" "$INSTALL_PATH"

echo "==> Launching"
open "$INSTALL_PATH"
echo "==> Running: $INSTALL_PATH"
