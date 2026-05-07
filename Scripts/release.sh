#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────
# FileLens Release Script
# 编译 arm64 + x86_64 各一个 DMG → 上传 GitHub + Gitee → 写 manifest
#
# Usage: ./scripts/release.sh <version>
#   version: 1.1.1 (必填)
#
# Manifest 按架构组织:assets.arm64.dmg_urls / assets.x86_64.dmg_urls,
# 每组都是 [Gitee, GitHub] 优先级数组。App 内根据 #if arch 选对应的。
#
# 一次性配置:
#   1. gitee.com 仓库 lifedever/file-lens
#   2. git remote add gitee git@gitee.com:lifedever/file-lens.git
#   3. ~/.zshrc:  export GITEE_TOKEN=xxx
# ─────────────────────────────────────────────

APP_NAME="FileLens"
BUNDLE_ID="com.lifedever.FileLens"
REPO="lifedever/FileLens"          # GitHub repo (renamed 2026-05-07)
GITEE_REPO="lifedever/file-lens"   # Gitee repo (unchanged)

if [ $# -lt 1 ]; then
  echo "Usage: $0 <version>" >&2
  echo "  e.g. $0 1.1.1" >&2
  exit 1
fi

VERSION="$1"
TAG="v${VERSION}"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="${PROJECT_ROOT}/dist"
NOTES_FILE="${PROJECT_ROOT}/dist/v${VERSION}-notes.md"

cd "${PROJECT_ROOT}"
mkdir -p "${DIST_DIR}"

echo "══════════════════════════════════════════"
echo "  ${APP_NAME} Release ${TAG}"
echo "══════════════════════════════════════════"

# ── Build per arch ────────────────────────────────────
# 输出: ${DIST_DIR}/FileLens-${VERSION}-arm64.dmg + -x86_64.dmg

build_arch() {
  local ARCH="$1"
  local BUILD_DIR="${PROJECT_ROOT}/.release/${ARCH}"
  local APP_PATH="${BUILD_DIR}/Build/Products/Release/${APP_NAME}.app"
  local DMG_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}-${ARCH}.dmg"

  echo ""
  echo "── Building ${ARCH} ──"
  rm -rf "${BUILD_DIR}"
  mkdir -p "${BUILD_DIR}"

  xcodebuild \
    -project "${APP_NAME}.xcodeproj" \
    -scheme "${APP_NAME}" \
    -configuration Release \
    -derivedDataPath "${BUILD_DIR}" \
    -sdk macosx \
    ARCHS="${ARCH}" \
    ONLY_ACTIVE_ARCH=NO \
    MARKETING_VERSION="${VERSION}" \
    build \
    > "${BUILD_DIR}/build.log" 2>&1 || {
      echo "Build failed (${ARCH}). Last 30 lines:"
      tail -30 "${BUILD_DIR}/build.log"
      exit 1
    }

  [ -d "${APP_PATH}" ] || { echo "Build product missing: ${APP_PATH}" >&2; exit 1; }

  # 防御:bundle ID 应该是 prod
  local ACTUAL_ID
  ACTUAL_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "${APP_PATH}/Contents/Info.plist")
  if [ "${ACTUAL_ID}" != "${BUNDLE_ID}" ]; then
    echo "Bundle ID mismatch on ${ARCH}: expected ${BUNDLE_ID}, got ${ACTUAL_ID}" >&2
    exit 1
  fi

  echo "  Creating DMG..."
  rm -f "${DMG_PATH}"
  if command -v create-dmg >/dev/null 2>&1; then
    create-dmg \
      --volname "${APP_NAME}" \
      --window-size 500 320 \
      --icon-size 96 \
      --app-drop-link 350 160 \
      --icon "${APP_NAME}.app" 150 160 \
      "${DMG_PATH}" \
      "${APP_PATH}" >/dev/null
  else
    local STAGING="${BUILD_DIR}/dmg-staging"
    rm -rf "${STAGING}"; mkdir -p "${STAGING}"
    cp -R "${APP_PATH}" "${STAGING}/"
    ln -s /Applications "${STAGING}/Applications"
    hdiutil create -volname "${APP_NAME}" -srcfolder "${STAGING}" \
      -ov -format UDZO "${DMG_PATH}" -quiet
  fi
  echo "  ${DMG_PATH} ($(du -h "${DMG_PATH}" | cut -f1))"
}

build_arch arm64
build_arch x86_64

ARM64_DMG="${DIST_DIR}/${APP_NAME}-${VERSION}-arm64.dmg"
X86_64_DMG="${DIST_DIR}/${APP_NAME}-${VERSION}-x86_64.dmg"

# ── GitHub Release ───────────────────────────────────
echo ""
read -p "Upload to GitHub Release ${TAG}? [y/N] " -n 1 -r
echo ""
GITHUB_OK=0
if [[ $REPLY =~ ^[Yy]$ ]]; then
  if ! command -v gh >/dev/null 2>&1; then
    echo "gh CLI not installed; skipping GitHub upload" >&2
  else
    if git rev-parse "${TAG}" >/dev/null 2>&1; then
      TAG_COMMIT=$(git rev-list -n 1 "${TAG}")
      HEAD_COMMIT=$(git rev-parse HEAD)
      if [ "${TAG_COMMIT}" != "${HEAD_COMMIT}" ]; then
        echo "  Tag ${TAG} exists on ${TAG_COMMIT:0:7}, not HEAD." >&2
        echo "  Delete first: git tag -d ${TAG} && git push origin :refs/tags/${TAG}" >&2
        exit 1
      fi
    else
      echo "  Creating tag ${TAG}..."
      git tag -a "${TAG}" -m "Release ${TAG}"
      git push origin "${TAG}"
    fi

    NOTES_FLAGS=()
    if [ -f "${NOTES_FILE}" ]; then
      NOTES_FLAGS=(--notes-file "${NOTES_FILE}")
    else
      NOTES_FLAGS=(--generate-notes)
    fi

    if gh release view "${TAG}" --repo "${REPO}" >/dev/null 2>&1; then
      gh release upload "${TAG}" "${ARM64_DMG}" "${X86_64_DMG}" \
        --repo "${REPO}" --clobber
    else
      gh release create "${TAG}" "${ARM64_DMG}" "${X86_64_DMG}" \
        --repo "${REPO}" \
        --title "${APP_NAME} ${TAG}" \
        "${NOTES_FLAGS[@]}"
    fi
    GITHUB_OK=1
    echo "  https://github.com/${REPO}/releases/tag/${TAG}"
  fi
fi

# ── Gitee Mirror ─────────────────────────────────────
# History: v1.1.0 was uploaded only to GitHub because every Gitee step
# below used `|| true` and `curl -s ... > /dev/null`, so a missing
# remote / failed API call swallowed silently. The manifest then
# pointed users at dead Gitee URLs. Each step now exits hard on error.
GITEE_OK=0
if [ -n "${GITEE_TOKEN:-}" ]; then
  echo ""
  echo "── Pushing to Gitee (${GITEE_REPO}) ──"
  if ! git remote get-url gitee >/dev/null 2>&1; then
    echo "❌ gitee remote not configured. Run:" >&2
    echo "   git remote add gitee git@gitee.com:${GITEE_REPO}.git" >&2
    exit 1
  fi
  git push gitee main
  git push gitee "${TAG}"

  # Build the create-release JSON via python3 so the notes body (with
  # newlines, quotes, markdown) is escaped correctly. Falls back to a
  # GitHub link if no notes file exists for this tag.
  CREATE_PAYLOAD=$(mktemp)
  NOTES_FILE_REL="${NOTES_FILE}" \
  TAG_REL="${TAG}" \
  REPO_REL="${REPO}" \
  APP_NAME_REL="${APP_NAME}" \
  GITEE_TOKEN_REL="${GITEE_TOKEN}" \
    python3 - <<'PY' > "${CREATE_PAYLOAD}"
import json, os
notes_path = os.environ['NOTES_FILE_REL']
tag = os.environ['TAG_REL']
repo = os.environ['REPO_REL']
body = (open(notes_path).read()
        if os.path.exists(notes_path)
        else f"See https://github.com/{repo}/releases/tag/{tag}")
print(json.dumps({
    'access_token': os.environ['GITEE_TOKEN_REL'],
    'tag_name': tag,
    'name': f"{os.environ['APP_NAME_REL']} {tag}",
    'body': body,
    'target_commitish': 'main',
}))
PY
  CREATE_BODY=$(mktemp)
  CREATE_CODE=$(curl -sS -o "${CREATE_BODY}" -w "%{http_code}" -X POST \
    "https://gitee.com/api/v5/repos/${GITEE_REPO}/releases" \
    -H "Content-Type: application/json" \
    --data-binary @"${CREATE_PAYLOAD}")
  rm -f "${CREATE_PAYLOAD}"
  GITEE_ID=$(python3 -c "import sys,json; print(json.load(open('${CREATE_BODY}')).get('id',''))" 2>/dev/null || true)

  # Re-running release.sh for an existing tag: create returns an error,
  # but the release does exist — look it up by tag and PATCH the body
  # so the notes stay in sync with what we ship.
  if [ -z "${GITEE_ID}" ] || [ "${GITEE_ID}" = "None" ]; then
    GITEE_ID=$(curl -sS "https://gitee.com/api/v5/repos/${GITEE_REPO}/releases/tags/${TAG}?access_token=${GITEE_TOKEN}" \
      | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || true)
    if [ -n "${GITEE_ID}" ] && [ "${GITEE_ID}" != "None" ] && [ -f "${NOTES_FILE}" ]; then
      PATCH_PAYLOAD=$(mktemp)
      NOTES_FILE_REL="${NOTES_FILE}" \
      TAG_REL="${TAG}" \
      APP_NAME_REL="${APP_NAME}" \
      GITEE_TOKEN_REL="${GITEE_TOKEN}" \
        python3 - <<'PY' > "${PATCH_PAYLOAD}"
import json, os
print(json.dumps({
    'access_token': os.environ['GITEE_TOKEN_REL'],
    'tag_name': os.environ['TAG_REL'],
    'name': f"{os.environ['APP_NAME_REL']} {os.environ['TAG_REL']}",
    'body': open(os.environ['NOTES_FILE_REL']).read(),
}))
PY
      curl -sS -o /dev/null -X PATCH \
        "https://gitee.com/api/v5/repos/${GITEE_REPO}/releases/${GITEE_ID}" \
        -H "Content-Type: application/json" \
        --data-binary @"${PATCH_PAYLOAD}"
      rm -f "${PATCH_PAYLOAD}"
      echo "  (Gitee release already existed — body patched with notes)"
    fi
  fi

  if [ -z "${GITEE_ID}" ] || [ "${GITEE_ID}" = "None" ]; then
    echo "❌ Could not resolve Gitee release id for ${TAG}" >&2
    echo "   Create-release HTTP ${CREATE_CODE}, body:" >&2
    cat "${CREATE_BODY}" >&2; echo "" >&2
    rm -f "${CREATE_BODY}"
    exit 1
  fi
  rm -f "${CREATE_BODY}"
  echo "  Gitee release id: ${GITEE_ID}"

  for DMG in "${ARM64_DMG}" "${X86_64_DMG}"; do
    NAME=$(basename "${DMG}")
    echo "  Uploading ${NAME}..."
    UP_BODY=$(mktemp)
    UP_CODE=$(curl -sS -o "${UP_BODY}" -w "%{http_code}" -X POST \
      "https://gitee.com/api/v5/repos/${GITEE_REPO}/releases/${GITEE_ID}/attach_files" \
      -F "access_token=${GITEE_TOKEN}" \
      -F "file=@${DMG}")
    if [ "${UP_CODE}" != "200" ] && [ "${UP_CODE}" != "201" ]; then
      echo "❌ Gitee upload failed for ${NAME} (HTTP ${UP_CODE})" >&2
      cat "${UP_BODY}" >&2; echo "" >&2
      rm -f "${UP_BODY}"
      exit 1
    fi
    rm -f "${UP_BODY}"
  done
  GITEE_OK=1
  echo "  https://gitee.com/${GITEE_REPO}/releases/tag/${TAG}"
else
  echo ""
  echo "  (Gitee mirror disabled — set GITEE_TOKEN env to enable)"
fi

# ── Manifest ──────────────────────────────────────────
echo ""
echo "── Updating update manifest ──"
MANIFEST_PATH="${PROJECT_ROOT}/web/api/latest.json"
mkdir -p "$(dirname "${MANIFEST_PATH}")"

# 双源 + 双 arch 的 URL 矩阵
GH_ARM64="https://github.com/${REPO}/releases/download/${TAG}/${APP_NAME}-${VERSION}-arm64.dmg"
GH_X86="https://github.com/${REPO}/releases/download/${TAG}/${APP_NAME}-${VERSION}-x86_64.dmg"
GITEE_ARM64=""
GITEE_X86=""
if [ "${GITEE_OK}" = "1" ]; then
  GITEE_ARM64="https://gitee.com/${GITEE_REPO}/releases/download/${TAG}/${APP_NAME}-${VERSION}-arm64.dmg"
  GITEE_X86="https://gitee.com/${GITEE_REPO}/releases/download/${TAG}/${APP_NAME}-${VERSION}-x86_64.dmg"
fi

NOTES_RAW=""
if [ -f "${NOTES_FILE}" ]; then
  NOTES_RAW=$(cat "${NOTES_FILE}")
fi

VERSION="${VERSION}" TAG="${TAG}" REPO="${REPO}" \
GH_ARM64="${GH_ARM64}" GH_X86="${GH_X86}" \
GITEE_ARM64="${GITEE_ARM64}" GITEE_X86="${GITEE_X86}" \
NOTES_RAW="${NOTES_RAW}" \
python3 - <<'PY' > "${MANIFEST_PATH}"
import json, os

def urls(*candidates):
    return [u for u in candidates if u]

arm64_urls = urls(os.environ.get("GITEE_ARM64", ""), os.environ["GH_ARM64"])
x86_urls = urls(os.environ.get("GITEE_X86", ""), os.environ["GH_X86"])

manifest = {
    "version": os.environ["VERSION"],
    "tag": os.environ["TAG"],
    "url": f"https://github.com/{os.environ['REPO']}/releases/tag/{os.environ['TAG']}",
    "assets": {
        "arm64":  {"dmg_urls": arm64_urls},
        "x86_64": {"dmg_urls": x86_urls},
    },
    # 兼容字段:老 client(< 1.1.1)只读 dmg_urls / dmg_url。给它们一个
    # universal-ish 兜底 —— 实际上是 arm64 链接(国内大多 Apple Silicon)。
    # 老 client 拿到这个可能架构不匹配,但还能下载完后报"应用损坏"提示重试,
    # 用户主动到官网重下时就能选对架构。新 client 走 assets 不受影响。
    "dmg_urls": arm64_urls,
    "dmg_url": arm64_urls[0] if arm64_urls else "",
    "notes": os.environ.get("NOTES_RAW", ""),
}
print(json.dumps(manifest, ensure_ascii=False, indent=2))
PY
echo "  ${MANIFEST_PATH}"

read -p "Commit + push manifest to deploy via Pages? [y/N] " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
  git add web/api/latest.json
  git commit -m "release: update manifest to ${VERSION}" 2>&1 | tail -2 || echo "  (nothing to commit)"
  git push 2>&1 | tail -3 || true
fi

# ── Homebrew tap ──────────────────────────────────────
HOMEBREW_TAP_PATH="${HOMEBREW_TAP_PATH:-${HOME}/Documents/Dev/myspace/homebrew-tap}"
HOMEBREW_CASK_PATH="${HOMEBREW_TAP_PATH}/Casks/filelens.rb"
echo ""
echo "── Updating Homebrew tap ──"
if [ -f "${HOMEBREW_CASK_PATH}" ]; then
  read -p "Update ${HOMEBREW_CASK_PATH} to ${VERSION}? [y/N] " -n 1 -r
  echo ""
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    NEW_SHA=$(shasum -a 256 "${ARM64_DMG}" | awk '{print $1}')
    echo "  arm64 sha256: ${NEW_SHA}"
    sed -i '' \
      -e "s|^  version \".*\"$|  version \"${VERSION}\"|" \
      -e "s|^  sha256 \".*\"$|  sha256 \"${NEW_SHA}\"|" \
      "${HOMEBREW_CASK_PATH}"
    (
      cd "${HOMEBREW_TAP_PATH}"
      git add Casks/filelens.rb
      git commit -m "filelens ${VERSION}"
      git push
    )
    echo "  Tap updated. Test:  brew install --cask --force lifedever/tap/filelens"
  fi
else
  echo "  Skipped (no tap at ${HOMEBREW_CASK_PATH})"
fi

echo ""
# ── Final integrity check ─────────────────────────────
# Hits every URL the autoupdate flow depends on, from the same network
# release.sh just used. Catches silent failures one of the upload steps
# might have introduced (the original v1.1.0 → Gitee miss is the canon
# failure mode this guards against).
echo "── Verifying release integrity ──"
if [ -x "${PROJECT_ROOT}/Scripts/verify-release.sh" ]; then
  "${PROJECT_ROOT}/Scripts/verify-release.sh" "${VERSION}"
else
  echo "  (Scripts/verify-release.sh missing — skipping; run it manually before announcing)"
fi

echo ""
echo "Done."
