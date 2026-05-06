#!/usr/bin/env bash
# Usage: ./Scripts/release.sh [VERSION] [ARCH]
#   VERSION default: 0.1.0
#   ARCH    default: arm64 (also supports x86_64, "universal" for arm64+x86_64)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-0.1.0}"
ARCH="${2:-arm64}"
APP_NAME="FileLens"
SCHEME="FileLens"
DIST_DIR="dist"
BUILD_DIR="build/release-${ARCH}"

case "$ARCH" in
  arm64)     ARCHS_FLAG="arm64" ;;
  x86_64)    ARCHS_FLAG="x86_64" ;;
  universal) ARCHS_FLAG="arm64 x86_64" ;;
  *) echo "Unknown arch: $ARCH (use arm64 / x86_64 / universal)" >&2; exit 1 ;;
esac

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

xcodebuild \
  -project "${APP_NAME}.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  -sdk macosx \
  ARCHS="$ARCHS_FLAG" \
  ONLY_ACTIVE_ARCH=NO \
  build

APP_PATH="${BUILD_DIR}/Build/Products/Release/${APP_NAME}.app"
[ -d "$APP_PATH" ] || { echo "Build product missing: $APP_PATH" >&2; exit 1; }

DMG_NAME="${APP_NAME}-${VERSION}-${ARCH}.dmg"
DMG_PATH="${DIST_DIR}/${DMG_NAME}"
rm -f "$DMG_PATH"

if command -v create-dmg >/dev/null 2>&1; then
  create-dmg \
    --volname "$APP_NAME" \
    --window-size 500 320 \
    --icon-size 96 \
    --app-drop-link 350 160 \
    --icon "${APP_NAME}.app" 150 160 \
    "$DMG_PATH" \
    "$APP_PATH"
else
  STAGING="${BUILD_DIR}/dmg-staging"
  rm -rf "$STAGING"; mkdir -p "$STAGING"
  cp -R "$APP_PATH" "$STAGING/"
  ln -s /Applications "$STAGING/Applications"
  hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH"
fi

echo "Built: $DMG_PATH"
