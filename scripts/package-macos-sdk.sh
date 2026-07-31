#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

usage() {
  cat <<'EOF'
usage: scripts/package-macos-sdk.sh <version> [output-dir]

Package an already-built weavec-bootstrap tree as a native macOS SDK.
Run ./build.sh first with the released macOS weavec1 SDK.
EOF
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage >&2
  exit 2
fi

[[ "$(uname -s)" == Darwin ]] || {
  printf 'package-macos-sdk: macOS host required\n' >&2
  exit 1
}

VERSION="$1"
OUTPUT_DIR="${2:-dist}"
ARCH="$(uname -m)"
case "$ARCH" in arm64|x86_64) ;; *) exit 1 ;; esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_NAME="weavec-bootstrap-${VERSION}-macos-${ARCH}"
RELEASE_BUILD="$ROOT/build/release/macos-${ARCH}"
PACKAGE_DIR="$RELEASE_BUILD/$PACKAGE_NAME"
ARCHIVE_DIR="$ROOT/$OUTPUT_DIR"
ARCHIVE="$ARCHIVE_DIR/$PACKAGE_NAME.tar.gz"
COMPILER_SOURCE="$ROOT/build/weavec-bootstrap"
HELPER_SOURCE="$ROOT/weavec-bootstrap-cat.sh"
PARSER_SOURCE="$ROOT/build/libweave-sexpr.bc"
COMPILER="$PACKAGE_DIR/bin/weavec-bootstrap"
HELPER="$PACKAGE_DIR/bin/weavec-bootstrap-cat"
PARSER="$PACKAGE_DIR/lib/libweave-sexpr.bc"
SMOKE_WIR="$RELEASE_BUILD/smoke.wir"
MULTIFILE_WIR="$RELEASE_BUILD/multifile.wir"

for tool in file otool python3 tar; do
  command -v "$tool" >/dev/null 2>&1 || {
    printf 'required tool not found: %s\n' "$tool" >&2
    exit 1
  }
done

[[ -x "$COMPILER_SOURCE" ]] || {
  printf 'missing compiler: %s\n' "$COMPILER_SOURCE" >&2
  exit 1
}
[[ -x "$HELPER_SOURCE" ]] || {
  printf 'missing multifile driver: %s\n' "$HELPER_SOURCE" >&2
  exit 1
}
[[ -s "$PARSER_SOURCE" ]] || {
  printf 'missing parser library: %s\n' "$PARSER_SOURCE" >&2
  exit 1
}

rm -rf "$RELEASE_BUILD"
mkdir -p "$PACKAGE_DIR/bin" "$PACKAGE_DIR/lib" "$ARCHIVE_DIR"
cp "$COMPILER_SOURCE" "$COMPILER"
cp "$HELPER_SOURCE" "$HELPER"
cp "$PARSER_SOURCE" "$PARSER"
chmod 0755 "$COMPILER" "$HELPER"

# macOS cannot produce a fully static executable (Apple's libSystem must
# always be linked dynamically), so a standalone release is instead required
# to depend on nothing beyond that always-present system library.
other_deps="$(otool -L "$COMPILER" | tail -n +2 | awk '{print $1}' | \
  grep -v '^/usr/lib/libSystem\.B\.dylib$' || true)"
if [[ -n "$other_deps" ]]; then
  printf 'release binary depends on more than libSystem:\n%s\n' "$other_deps" >&2
  otool -L "$COMPILER" >&2
  exit 1
fi

file "$COMPILER"
file "$PARSER"

cat > "$PACKAGE_DIR/SDK-MANIFEST" <<EOF
name=weavec-bootstrap
version=$VERSION
platform=macos-${ARCH}
compiler=bin/weavec-bootstrap
multifile_driver=bin/weavec-bootstrap-cat
parser_library=lib/libweave-sexpr.bc
weavec1_version=${WEAVEC1_VERSION:-v0.3.2}
EOF
printf '%s\n' "$VERSION" > "$PACKAGE_DIR/VERSION"
cp "$ROOT/README.md" "$PACKAGE_DIR/"
[[ -f "$ROOT/LICENSE" ]] && cp "$ROOT/LICENSE" "$PACKAGE_DIR/"
[[ -f "$ROOT/NOTICE" ]] && cp "$ROOT/NOTICE" "$PACKAGE_DIR/"

"$COMPILER" "$ROOT/test/01_return_42.weave" "$SMOKE_WIR"
[[ -s "$SMOKE_WIR" ]] || {
  printf 'SDK compiler smoke produced no WIR\n' >&2
  exit 1
}
"$HELPER" "$MULTIFILE_WIR" \
  "$ROOT/test/01_return_42.weave" \
  "$ROOT/test/02_return_constant.weave"
[[ -s "$MULTIFILE_WIR" ]] || {
  printf 'SDK multifile smoke produced no WIR\n' >&2
  exit 1
}

if command -v strip >/dev/null 2>&1; then
  strip -x "$COMPILER" 2>/dev/null || true
fi
rm -f "$ARCHIVE"
tar -C "$RELEASE_BUILD" -czf "$ARCHIVE" "$PACKAGE_NAME"
printf '%s\n' "$ARCHIVE"
