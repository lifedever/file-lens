#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-0.1.0}"
APP_NAME="FileLens"
SCHEME="FileLens"
DIST_DIR="dist"
BUILD_DIR="build/release"

rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

xcodebuild \
  -project "${APP_NAME}.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  -sdk macosx \
  build

APP_PATH="${BUILD_DIR}/Build/Products/Release/${APP_NAME}.app"
[ -d "$APP_PATH" ] || { echo "Build product missing: $APP_PATH" >&2; exit 1; }

DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_PATH="${DIST_DIR}/${DMG_NAME}"

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
