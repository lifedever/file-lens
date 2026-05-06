#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

xcodebuild \
  -project FileLens.xcodeproj \
  -scheme FileLens \
  -configuration Debug \
  -derivedDataPath build \
  -sdk macosx \
  build

APP="build/Build/Products/Debug/FileLens.app"
[ -d "$APP" ] || { echo "Build product missing: $APP" >&2; exit 1; }

open "$APP"
