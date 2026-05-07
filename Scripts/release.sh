#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────
# FileLens Release Script
# 编译 Release → 打 DMG → (可选) 上传 GitHub Release
#
# Usage: ./scripts/release.sh <version> [arch]
#   version: 1.0.2 (必填)
#   arch:    arm64(默认) / x86_64 / universal
#
# 例:
#   ./scripts/release.sh 1.0.2
#   ./scripts/release.sh 1.0.2 universal
#
# bundle ID = com.lifedever.FileLens(prod),与 dev (com.lifedever.FileLens.dev)
# 完全隔离。
# ─────────────────────────────────────────────

APP_NAME="FileLens"
BUNDLE_ID="com.lifedever.FileLens"
REPO="lifedever/FileLens"

if [ $# -lt 1 ]; then
  echo "Usage: $0 <version> [arch]" >&2
  echo "  e.g. $0 1.0.2" >&2
  exit 1
fi

VERSION="$1"
ARCH="${2:-arm64}"
TAG="v${VERSION}"

case "$ARCH" in
  arm64)     ARCHS_FLAG="arm64" ;;
  x86_64)    ARCHS_FLAG="x86_64" ;;
  universal) ARCHS_FLAG="arm64 x86_64" ;;
  *) echo "Unknown arch: $ARCH (use arm64 / x86_64 / universal)" >&2; exit 1 ;;
esac

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/.release/${ARCH}"
DIST_DIR="${PROJECT_ROOT}/dist"
APP_PATH="${BUILD_DIR}/Build/Products/Release/${APP_NAME}.app"
DMG_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}-${ARCH}.dmg"

cd "${PROJECT_ROOT}"

echo "══════════════════════════════════════════"
echo "  ${APP_NAME} Release ${TAG} (${ARCH})"
echo "══════════════════════════════════════════"

# Clean
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}" "${DIST_DIR}"

# Build
echo ""
echo "── Building Release ──"
xcodebuild \
  -project "${APP_NAME}.xcodeproj" \
  -scheme "${APP_NAME}" \
  -configuration Release \
  -derivedDataPath "${BUILD_DIR}" \
  -sdk macosx \
  ARCHS="${ARCHS_FLAG}" \
  ONLY_ACTIVE_ARCH=NO \
  MARKETING_VERSION="${VERSION}" \
  build \
  > "${BUILD_DIR}/build.log" 2>&1 || {
    echo "Build failed. Last 30 lines of log:"
    tail -30 "${BUILD_DIR}/build.log"
    exit 1
  }

[ -d "${APP_PATH}" ] || { echo "Build product missing: ${APP_PATH}" >&2; exit 1; }

# 防御:确认输出 bundle id 是 prod,而不是 dev 串了。dev.sh 改 plist 是
# 在编译产物的拷贝上做,不污染源 plist;万一以后引入 per-config xcconfig
# 出错,这一行能立刻报。
ACTUAL_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "${APP_PATH}/Contents/Info.plist")
if [ "${ACTUAL_ID}" != "${BUNDLE_ID}" ]; then
  echo "Bundle ID mismatch: expected ${BUNDLE_ID}, got ${ACTUAL_ID}" >&2
  exit 1
fi

# DMG
echo ""
echo "── Creating DMG ──"
rm -f "${DMG_PATH}"

if command -v create-dmg >/dev/null 2>&1; then
  create-dmg \
    --volname "${APP_NAME}" \
    --window-size 500 320 \
    --icon-size 96 \
    --app-drop-link 350 160 \
    --icon "${APP_NAME}.app" 150 160 \
    "${DMG_PATH}" \
    "${APP_PATH}"
else
  STAGING="${BUILD_DIR}/dmg-staging"
  rm -rf "$STAGING"; mkdir -p "$STAGING"
  cp -R "${APP_PATH}" "$STAGING/"
  ln -s /Applications "$STAGING/Applications"
  hdiutil create -volname "${APP_NAME}" -srcfolder "$STAGING" -ov -format UDZO "${DMG_PATH}" -quiet
fi

echo "  ${DMG_PATH}"
echo "  size: $(du -h "${DMG_PATH}" | cut -f1)"

# (可选) 上传 GitHub Release
echo ""
read -p "Upload to GitHub Release ${TAG}? [y/N] " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
  if ! command -v gh >/dev/null 2>&1; then
    echo "gh CLI not installed; skipping upload" >&2
    exit 0
  fi

  # Tag:存在就 verify HEAD,不存在就创建并推送
  if git rev-parse "${TAG}" >/dev/null 2>&1; then
    TAG_COMMIT=$(git rev-list -n 1 "${TAG}")
    HEAD_COMMIT=$(git rev-parse HEAD)
    if [ "${TAG_COMMIT}" != "${HEAD_COMMIT}" ]; then
      echo "  ERROR: Tag ${TAG} exists but points to ${TAG_COMMIT:0:7}, not HEAD (${HEAD_COMMIT:0:7})." >&2
      echo "  Delete first:  git tag -d ${TAG} && git push origin :refs/tags/${TAG}" >&2
      exit 1
    fi
    echo "  Tag ${TAG} already on HEAD."
  else
    echo "  Creating tag ${TAG}..."
    git tag -a "${TAG}" -m "Release ${TAG}"
    git push origin "${TAG}"
  fi

  # 优先用 dist/v<version>-notes.md(发版前手写的双语 release notes),
  # 没有就 fallback 到 GitHub 自动从 commit 生成的笔记。
  NOTES_FILE="${PROJECT_ROOT}/dist/v${VERSION}-notes.md"
  NOTES_FLAGS=()
  if [ -f "${NOTES_FILE}" ]; then
    NOTES_FLAGS=(--notes-file "${NOTES_FILE}")
    echo "  Using notes from: ${NOTES_FILE}"
  else
    NOTES_FLAGS=(--generate-notes)
  fi

  if gh release view "${TAG}" --repo "${REPO}" >/dev/null 2>&1; then
    echo "  Release ${TAG} exists, uploading asset..."
    gh release upload "${TAG}" "${DMG_PATH}" --repo "${REPO}" --clobber
  else
    gh release create "${TAG}" "${DMG_PATH}" \
      --repo "${REPO}" \
      --title "${APP_NAME} ${TAG}" \
      "${NOTES_FLAGS[@]}"
  fi
  echo ""
  echo "  https://github.com/${REPO}/releases/tag/${TAG}"
fi

echo ""
echo "Done."
