#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

usage() {
  cat <<'EOF'
usage: scripts/publish-macos-sdk.sh [version] [output-dir]

Build the native-host bootstrap SDK archive and publish it to the matching
GitHub release without relying on GitHub Actions. The default version is
v<VERSION> and the default output directory is dist.
EOF
}

if [[ $# -gt 2 ]]; then
  usage >&2
  exit 2
fi

[[ "$(uname -s)" == Darwin ]] || {
  printf 'publish-macos-sdk: macOS host required\n' >&2
  exit 1
}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPECTED_VERSION="v$(tr -d '[:space:]' < "$ROOT/VERSION")"
VERSION="${1:-$EXPECTED_VERSION}"
OUTPUT_DIR="${2:-dist}"

[[ "$VERSION" == "$EXPECTED_VERSION" ]] || {
  printf 'publish-macos-sdk: requested %s, repository VERSION requires %s\n' \
    "$VERSION" "$EXPECTED_VERSION" >&2
  exit 1
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'publish-macos-sdk: required tool not found: %s\n' "$1" >&2
    exit 1
  }
}

require_tool gh
require_tool git
require_tool shasum

cd "$ROOT"
[[ -z "$(git status --porcelain --untracked-files=normal)" ]] || {
  printf 'publish-macos-sdk: working tree must be clean\n' >&2
  exit 1
}
gh auth status >/dev/null

archive="$(scripts/package-macos-sdk.sh "$VERSION" "$OUTPUT_DIR" | tail -n 1)"
[[ -f "$archive" ]] || {
  printf 'publish-macos-sdk: package script did not produce %s\n' "$archive" >&2
  exit 1
}
archive="$(cd "$(dirname "$archive")" && pwd)/$(basename "$archive")"
archive_name="$(basename "$archive")"

work="$(mktemp -d "${TMPDIR:-/tmp}/weavec-bootstrap-release-XXXXXX")"
trap 'rm -rf "$work"' EXIT
sums="$work/SHA256SUMS"
new_hash="$(shasum -a 256 "$archive" | awk '{print $1}')"

if gh release view "$VERSION" >/dev/null 2>&1; then
  mkdir -p "$work/existing"
  if gh release download "$VERSION" \
      --pattern SHA256SUMS --dir "$work/existing" >/dev/null 2>&1; then
    awk -v name="$archive_name" '$2 != name { print }' \
      "$work/existing/SHA256SUMS" > "$sums"
  else
    : > "$sums"
  fi
  printf '%s  %s\n' "$new_hash" "$archive_name" >> "$sums"
  LC_ALL=C sort -k2,2 -u "$sums" -o "$sums"
  gh release upload "$VERSION" "$archive" "$sums" --clobber
else
  printf '%s  %s\n' "$new_hash" "$archive_name" > "$sums"
  gh release create "$VERSION" "$archive" "$sums" \
    --target "$(git rev-parse HEAD)" \
    --title "weavec-bootstrap $VERSION" \
    --notes "Native macOS bootstrap SDK. Linux builds continue to use the unchanged v0.3.0 SDK assets."
fi

assets="$(gh release view "$VERSION" --json assets --jq '.assets[].name')"
grep -Fxq "$archive_name" <<<"$assets"
grep -Fxq SHA256SUMS <<<"$assets"

gh release view "$VERSION" --json url --jq '.url'
