#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────
# FileLens Dev Build Script
# 编译 Debug → 改写 bundle ID 为 .dev → 装到 /Applications/FileLens dev.app
# 与正式版 (com.lifedever.FileLens) 完全隔离:bundle ID 不同 →
# SwiftData store / UserDefaults / 偏好设置全部独立
#
# Usage: ./scripts/dev.sh
# ─────────────────────────────────────────────

APP_NAME="FileLens"
DEV_APP_NAME="FileLens dev"
BUNDLE_ID="com.lifedever.FileLens.dev"

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/.dev-build"
INSTALL_PATH="/Applications/${DEV_APP_NAME}.app"

mkdir -p "${BUILD_DIR}"
echo "── Building ${DEV_APP_NAME} ──"

cd "${PROJECT_ROOT}"

# 用 xcodebuild Debug 编译。bundle ID 在 project.yml 里是 prod 值,
# 这里编完之后再覆写 Info.plist。这种方式不用为 dev 单独维护 xcconfig。
xcodebuild \
  -project "${APP_NAME}.xcodeproj" \
  -scheme "${APP_NAME}" \
  -configuration Debug \
  -derivedDataPath "${BUILD_DIR}" \
  -sdk macosx \
  build \
  > "${BUILD_DIR}/build.log" 2>&1 || {
    echo "Build failed. Last 30 lines of log:"
    tail -30 "${BUILD_DIR}/build.log"
    exit 1
  }

BUILT_APP="${BUILD_DIR}/Build/Products/Debug/${APP_NAME}.app"
[ -d "${BUILT_APP}" ] || { echo "Build product missing: ${BUILT_APP}" >&2; exit 1; }

# Stage:把 Debug 产物拷到 .dev-build/<DEV_APP_NAME>.app,改名 + 改 plist
STAGE="${BUILD_DIR}/${DEV_APP_NAME}.app"
rm -rf "${STAGE}"
cp -R "${BUILT_APP}" "${STAGE}"

# 改 Info.plist 三个字段:bundle ID / 显示名 / bundle name(Finder 用 name)
PLIST="${STAGE}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${BUNDLE_ID}" "${PLIST}"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName ${DEV_APP_NAME}" "${PLIST}" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string ${DEV_APP_NAME}" "${PLIST}"
/usr/libexec/PlistBuddy -c "Set :CFBundleName ${DEV_APP_NAME}" "${PLIST}" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleName string ${DEV_APP_NAME}" "${PLIST}"

# 改完必须重签 —— 否则 Gatekeeper 会拒,菜单栏图标 / 通知都不工作
codesign --force --deep --no-strict --sign - "${STAGE}" 2>&1 | grep -v 'replacing existing signature' || true

# 杀光所有 FileLens 相关进程(包括 prod 和上一次 dev)
pkill -9 -f "FileLens" 2>/dev/null && sleep 0.4 || true

# 装到 /Applications,launchd 第一次 register 时缓存这个路径,
# 之后 NSRunningApplication 查 bundleID 也能稳定命中
rm -rf "${INSTALL_PATH}"
cp -R "${STAGE}" "${INSTALL_PATH}"

# 让 LaunchServices 立刻知道这个 bundle 的存在(避免老缓存覆盖)
/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister \
  -f "${INSTALL_PATH}" >/dev/null 2>&1 || true

open "${INSTALL_PATH}"

echo ""
echo "── Done ──"
echo "  ${INSTALL_PATH}"
echo "  bundle id: ${BUNDLE_ID}"
echo "  data dir:  ~/Library/Application Support/${BUNDLE_ID}/"
