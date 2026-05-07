#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────
# FileLens Local Update-Test Build
# 编译 Release 配置 → 改 Info.plist 版本号到指定低版本 →
# 装到 /Applications/FileLens.app(prod bundle ID 不动)。
#
# 用途:本地测自动更新自替换流程。dev.sh 用 .dev bundle ID,
# UpdateController 在 .dev 下走"打开 DMG 让用户拖装"分支(见
# UpdateController.swift `isDev` 判断),不会触发 in-app 自替换;
# release.sh 又强制走 GitHub/Gitee 上传链路,本地不能重复用。
# 本脚本填这个空。
#
# Usage:
#   ./scripts/test-update.sh           # 默认版本 1.0.0
#   ./scripts/test-update.sh 1.0.5     # 自定义版本号
#
# 跑完会:
#   - /Applications/FileLens.app 被替换成 Release-config 包,版本号写死为传入值
#   - 启动后会拉 manifest 发现 latest > 当前版本,弹更新对话框
#   - 点 "安装并重启" 走完整自替换流程(下载 DMG → mount → 替换 → relaunch)
#
# 想还原到正常版本:重跑 release.sh 或者从 dist/ 里的最新 DMG 拖到 /Applications。
# ─────────────────────────────────────────────

APP_NAME="FileLens"
BUNDLE_ID="com.lifedever.FileLens"
VERSION="${1:-1.0.0}"

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/.test-update-build"
INSTALL_PATH="/Applications/${APP_NAME}.app"

cd "${PROJECT_ROOT}"
mkdir -p "${BUILD_DIR}"

echo "── Building ${APP_NAME} (Release, version=${VERSION}) ──"

# 当前 host 架构,只编一个 arch 够测了 —— release.sh 才负责双 arch
HOST_ARCH=$(uname -m)
case "${HOST_ARCH}" in
  arm64|x86_64) ;;
  *) echo "Unsupported host arch: ${HOST_ARCH}" >&2; exit 1 ;;
esac

xcodebuild \
  -project "${APP_NAME}.xcodeproj" \
  -scheme "${APP_NAME}" \
  -configuration Release \
  -derivedDataPath "${BUILD_DIR}" \
  -sdk macosx \
  ARCHS="${HOST_ARCH}" \
  ONLY_ACTIVE_ARCH=NO \
  build \
  > "${BUILD_DIR}/build.log" 2>&1 || {
    echo "Build failed. Last 30 lines:"
    tail -30 "${BUILD_DIR}/build.log"
    exit 1
  }

BUILT_APP="${BUILD_DIR}/Build/Products/Release/${APP_NAME}.app"
[ -d "${BUILT_APP}" ] || { echo "Build product missing: ${BUILT_APP}" >&2; exit 1; }

# 防御:不能是 Debug 形态(主二进制 stub + .debug.dylib + __preview.dylib),
# 那样测出来跟真实用户拿到的 release 不一样,自替换路径也可能对不上。
if [ -f "${BUILT_APP}/Contents/MacOS/${APP_NAME}.debug.dylib" ] \
   || [ -f "${BUILT_APP}/Contents/MacOS/__preview.dylib" ]; then
  echo "ERROR: built app contains debug/preview dylibs — Release config didn't take effect" >&2
  ls -la "${BUILT_APP}/Contents/MacOS/" >&2
  exit 1
fi

# 防御:bundle ID 必须是 prod,不然 self-replace 路径不会触发
ACTUAL_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "${BUILT_APP}/Contents/Info.plist")
if [ "${ACTUAL_ID}" != "${BUNDLE_ID}" ]; then
  echo "Bundle ID mismatch: expected ${BUNDLE_ID}, got ${ACTUAL_ID}" >&2
  exit 1
fi

# 改版本号 —— 这是测试的核心
PLIST="${BUILT_APP}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${PLIST}"
echo "  Version overridden to ${VERSION}"

# 改完必须重签
codesign --force --deep --no-strict --sign - "${BUILT_APP}" 2>&1 \
  | grep -v 'replacing existing signature' || true

# 杀光所有 prod FileLens 进程(不动 dev)
pkill -9 -f "/Applications/${APP_NAME}.app/Contents/MacOS/${APP_NAME}" 2>/dev/null \
  && sleep 0.4 || true

# 装到 /Applications
rm -rf "${INSTALL_PATH}"
cp -R "${BUILT_APP}" "${INSTALL_PATH}"

# LaunchServices 注册
/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister \
  -f "${INSTALL_PATH}" >/dev/null 2>&1 || true

open "${INSTALL_PATH}"

echo ""
echo "── Done ──"
echo "  ${INSTALL_PATH}"
echo "  bundle id:  ${BUNDLE_ID}"
echo "  version:    ${VERSION}"
echo "  arch:       ${HOST_ARCH}"
echo ""
echo "App started — should pop the update dialog within seconds."
echo "Click \"Install and Restart\" to test self-replace flow end-to-end."
