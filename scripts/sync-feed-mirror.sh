#!/usr/bin/env bash
#
# sync-feed-mirror.sh — Copy the published appcast to the old-feed mirror.
#
# Builds <= 1.0.1 read their Sparkle feed from
# https://dinhanhthi.github.io/FastMoji/appcast.xml. After the repo moved to
# Coprimal/FastMoji, GitHub no longer serves or redirects that address, so the user
# site dinhanhthi/dinhanhthi.github.io serves a copy at FastMoji/appcast.xml.
# scripts/publish-appcast.sh runs this script on every release so those builds always
# see the latest version. Never edit the mirror's appcast by hand.
#
# Usage: scripts/sync-feed-mirror.sh [appcast.xml]
#
set -euo pipefail

MIRROR_REPO="dinhanhthi/dinhanhthi.github.io"
MIRROR_PATH="FastMoji/appcast.xml"
SOURCE="${1:-appcast.xml}"

fail() {
  echo "error: $*" >&2
  exit 1
}

[[ -f "$SOURCE" ]] || fail "$SOURCE not found"

# Current blob sha of the mirror file; empty when the file does not exist yet (HTTP 404).
current_sha=""
if ! current_sha="$(gh api "repos/$MIRROR_REPO/contents/$MIRROR_PATH" --jq .sha 2>/dev/null)"; then
  status="$(gh api -i "repos/$MIRROR_REPO/contents/$MIRROR_PATH" 2>/dev/null | head -1 || true)"
  [[ "$status" == *" 404"* ]] || fail "cannot read $MIRROR_PATH in $MIRROR_REPO"
  current_sha=""
fi
local_sha="$(git hash-object "$SOURCE")"

if [[ "$current_sha" == "$local_sha" ]]; then
  echo "mirror already current ($MIRROR_REPO/$MIRROR_PATH)"
  exit 0
fi

version="$(grep -o '<sparkle:shortVersionString>[^<]*' "$SOURCE" | head -1 | sed 's/.*>//' || true)"

# The body goes through stdin: the base64 appcast grows with every release.
# No sha creates the file; a sha updates it.
base64 <"$SOURCE" | tr -d '\n' |
  jq -Rs --arg message "chore: sync FastMoji appcast ${version:-update}" --arg sha "$current_sha" \
    '{message: $message, content: .} + (if $sha == "" then {} else {sha: $sha} end)' |
  gh api -X PUT "repos/$MIRROR_REPO/contents/$MIRROR_PATH" --input - --jq .commit.sha >/dev/null ||
  fail "cannot update $MIRROR_PATH in $MIRROR_REPO"

echo "mirror updated: https://dinhanhthi.github.io/$MIRROR_PATH (${version:-unknown version})"
