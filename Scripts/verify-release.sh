#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────
# FileLens — Release Integrity Check
#
# Hits every URL the autoupdate flow depends on for <version> and bails
# loudly on the first failure. release.sh runs this at the end so a
# silent Gitee/manifest/notes problem can't slip into a published
# release. The CI workflow `.github/workflows/verify-release.yml`
# also runs it on every tag push and weekly to catch link rot.
#
# Usage:  ./Scripts/verify-release.sh <version>
#   e.g.  ./Scripts/verify-release.sh 1.1.0
#
# Exit:   0 = all green, 1 = at least one check failed
# ─────────────────────────────────────────────

if [ $# -lt 1 ]; then
  echo "Usage: $0 <version>  (e.g. $0 1.1.0)" >&2
  exit 1
fi

VERSION="$1"
TAG="v${VERSION}"
REPO="lifedever/file-lens"
GITEE_REPO="lifedever/file-lens"
APP_NAME="FileLens"
# DMGs are tiny right now (~1.6 MB) but a placeholder/empty file is
# usually <50KB — generous floor catches obviously-wrong uploads
# without breaking when binary size genuinely shrinks.
MIN_DMG_BYTES=500000
MIN_NOTES_CHARS=500

FAILED=0

# ── helpers ──────────────────────────────────────────
fail() { echo "❌ $*" >&2; FAILED=1; }
pass() { echo "✅ $*"; }

# Hit a URL, follow redirects, assert HTTP 200 and >= min_bytes.
check_url() {
  local label="$1" url="$2" min_bytes="$3"
  local code size
  code=$(curl -sSL -o /dev/null -w "%{http_code}" "$url" || echo "000")
  size=$(curl -sSL -o /dev/null -w "%{size_download}" "$url" || echo "0")
  if [ "$code" != "200" ]; then
    fail "${label}: HTTP ${code} (${url})"
    return
  fi
  if [ "$size" -lt "$min_bytes" ]; then
    fail "${label}: size ${size} < expected min ${min_bytes} (${url})"
    return
  fi
  pass "${label}: HTTP 200, ${size} bytes"
}

# Fetch a Gitee release body via API; assert it has actual notes
# (not the "see GitHub" placeholder).
check_gitee_body() {
  local tag="$1"
  local body len
  body=$(curl -sSL "https://gitee.com/api/v5/repos/${GITEE_REPO}/releases/tags/${tag}" \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('body',''))" 2>/dev/null || echo "")
  len=${#body}
  if [ "$len" -lt "$MIN_NOTES_CHARS" ]; then
    fail "Gitee release body only ${len} chars — looks like a placeholder. Re-run release.sh or PATCH the body manually."
    return
  fi
  if ! echo "$body" | grep -q "${APP_NAME}"; then
    fail "Gitee release body missing '${APP_NAME}' header — body content looks wrong"
    return
  fi
  pass "Gitee release body: ${len} chars, contains '${APP_NAME}'"
}

# Same for GitHub release. Uses the GitHub REST API directly so the
# script works without `gh` installed (CI sometimes has, sometimes
# doesn't); GH_TOKEN is optional but lifts rate limits.
check_github_body() {
  local tag="$1"
  # Build auth args as a properly-quoted string for eval; an empty
  # bash array under `set -u` triggers "unbound variable", and the
  # ${arr[@]+"${arr[@]}"} workaround tangles with -H value parsing.
  local auth_args=""
  local token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
  if [ -n "$token" ]; then
    auth_args="-H \"Authorization: Bearer ${token}\""
  fi
  local body len
  body=$(eval curl -sSL ${auth_args} \
    "https://api.github.com/repos/${REPO}/releases/tags/${tag}" \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('body','') or '')" 2>/dev/null || echo "")
  len=${#body}
  if [ "$len" -lt "$MIN_NOTES_CHARS" ]; then
    fail "GitHub release body only ${len} chars"
    return
  fi
  pass "GitHub release body: ${len} chars"
}

# Manifest must (a) exist on both mirrors, (b) advertise the same
# version we're verifying, (c) reference the right DMG URLs.
check_manifest() {
  local label="$1" url="$2"
  local raw version arm_url x86_url
  raw=$(curl -sSL "$url" || true)
  if [ -z "$raw" ]; then
    fail "${label}: failed to fetch (${url})"
    return
  fi
  version=$(echo "$raw" | python3 -c "import sys,json; print(json.load(sys.stdin).get('version',''))" 2>/dev/null || echo "")
  if [ "$version" != "$VERSION" ]; then
    fail "${label}: version='${version}', expected '${VERSION}'"
    return
  fi
  arm_url=$(echo "$raw" | python3 -c "
import sys, json
d = json.load(sys.stdin)
arr = d.get('assets', {}).get('arm64', {}).get('dmg_urls', [])
print(arr[0] if arr else '')
" 2>/dev/null || echo "")
  x86_url=$(echo "$raw" | python3 -c "
import sys, json
d = json.load(sys.stdin)
arr = d.get('assets', {}).get('x86_64', {}).get('dmg_urls', [])
print(arr[0] if arr else '')
" 2>/dev/null || echo "")
  if [ -z "$arm_url" ] || [ -z "$x86_url" ]; then
    fail "${label}: assets.arm64/x86_64.dmg_urls missing"
    return
  fi
  pass "${label}: version=${version}, arm64 + x86_64 DMG URLs present"
}

# ── 1. DMG availability on both mirrors ──────────────
echo ""
echo "── DMG availability ──"
check_url "Gitee arm64 DMG" \
  "https://gitee.com/${GITEE_REPO}/releases/download/${TAG}/${APP_NAME}-${VERSION}-arm64.dmg" \
  "$MIN_DMG_BYTES"
check_url "Gitee x86_64 DMG" \
  "https://gitee.com/${GITEE_REPO}/releases/download/${TAG}/${APP_NAME}-${VERSION}-x86_64.dmg" \
  "$MIN_DMG_BYTES"
check_url "GitHub arm64 DMG" \
  "https://github.com/${REPO}/releases/download/${TAG}/${APP_NAME}-${VERSION}-arm64.dmg" \
  "$MIN_DMG_BYTES"
check_url "GitHub x86_64 DMG" \
  "https://github.com/${REPO}/releases/download/${TAG}/${APP_NAME}-${VERSION}-x86_64.dmg" \
  "$MIN_DMG_BYTES"

# ── 2. Manifest accessible & consistent on both mirrors ──
echo ""
echo "── Manifest consistency ──"
check_manifest "Gitee manifest" \
  "https://gitee.com/${GITEE_REPO}/raw/main/web/api/latest.json"
check_manifest "GitHub raw manifest" \
  "https://raw.githubusercontent.com/${REPO}/main/web/api/latest.json"

# ── 3. Release notes are real (not placeholder) ──────
echo ""
echo "── Release notes ──"
check_gitee_body "$TAG"
check_github_body "$TAG"

echo ""
if [ "$FAILED" -ne 0 ]; then
  echo "❌ Verification FAILED for ${TAG} — fix the issues above before announcing this release."
  exit 1
fi
echo "🎉 All release checks passed for ${TAG}."
