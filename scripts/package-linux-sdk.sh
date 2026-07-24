#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

usage() {
  cat <<'EOF'
usage: scripts/package-linux-sdk.sh <glibc|musl> <version> [output-dir]

Package an already-built weavec-bootstrap tree as a static Linux x86-64 SDK.
Run ./build.sh first with the matching WEAVEC1_LIBC value.
EOF
}

if [[ $# -lt 2 || $# -gt 3 ]]; then
  usage >&2
  exit 2
fi

LIBC="$1"
VERSION="$2"
OUTPUT_DIR="${3:-dist}"

case "$LIBC" in
  glibc|musl) ;;
  *)
    printf 'unsupported libc: %s\n' "$LIBC" >&2
    usage >&2
    exit 2
    ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_NAME="weavec-bootstrap-${VERSION}-linux-x86_64-${LIBC}"
RELEASE_BUILD="$ROOT/build/release/$LIBC"
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

require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'required tool not found: %s\n' "$1" >&2
    exit 1
  }
}

require_tool file
require_tool python3
require_tool readelf
require_tool tar

[[ -x "$COMPILER_SOURCE" ]] || {
  printf 'missing compiler: %s\n' "$COMPILER_SOURCE" >&2
  printf 'run WEAVEC1_LIBC=%s ./build.sh first\n' "$LIBC" >&2
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

if readelf -l "$COMPILER" | grep -q 'INTERP'; then
  printf 'compiler is dynamically linked: %s\n' "$COMPILER" >&2
  readelf -l "$COMPILER" >&2
  exit 1
fi

file "$COMPILER"
file "$PARSER"

cat > "$PACKAGE_DIR/SDK-MANIFEST" <<EOF
name=weavec-bootstrap
version=$VERSION
platform=linux-x86_64
libc=$LIBC
compiler=bin/weavec-bootstrap
multifile_driver=bin/weavec-bootstrap-cat
parser_library=lib/libweave-sexpr.bc
weavec1_version=${WEAVEC1_VERSION:-v0.2.0}
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
  strip --strip-unneeded "$COMPILER"
fi

rm -f "$ARCHIVE"
tar -C "$RELEASE_BUILD" -czf "$ARCHIVE" "$PACKAGE_NAME"
printf '%s\n' "$ARCHIVE"
