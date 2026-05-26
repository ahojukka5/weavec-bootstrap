#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

# Single-test smoke for weavefront. Useful when iterating on the
# front-end alone — the full ladder is in test_all.sh.
#
# Requires ./build.sh to have run first. WEAVEC0 / WEAVEC1 env vars
# select which dependency copies to test against (same conventions
# as build.sh / test_all.sh).

WEAVEFRONT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$WEAVEFRONT_DIR/build"
VENDOR_DIR="$BUILD_DIR/vendor"

WEAVEFRONT="$BUILD_DIR/weavefront"
WEAVEC0_DIR="${WEAVEC0:-$VENDOR_DIR/weavec0}"
WEAVEC1_DIR="${WEAVEC1:-$VENDOR_DIR/weavec1}"
WEAVEC1_BIN="$WEAVEC1_DIR/build/weavec1"
RUNTIME="$WEAVEC0_DIR/runtime.c"

log() {
  echo "[test] $*"
}

fail() {
  echo "[test] ERROR: $*" >&2
  exit 1
}

[[ -x "$WEAVEFRONT" ]] || fail "weavefront not found at $WEAVEFRONT (run ./build.sh first)"
[[ -x "$WEAVEC1_BIN" ]] || fail "weavec1 not found at $WEAVEC1_BIN (run ./build.sh first or set WEAVEC1)"
[[ -f "$RUNTIME" ]] || fail "runtime not found at $RUNTIME (run ./build.sh first or set WEAVEC0)"

# Test 01: return_42
log "Test 01: return_42"
log "  Compiling Surface Weave to WIR..."
rm -f "$BUILD_DIR/01_return_42.wir"  # Remove old output
$WEAVEFRONT test/01_return_42.weave "$BUILD_DIR/01_return_42.wir" || fail "weavefront compilation failed"

log "  Comparing WIR output..."
if ! diff test/01_return_42.expected.wir "$BUILD_DIR/01_return_42.wir"; then
  fail "WIR output mismatch"
fi

log "  Compiling WIR to LLVM IR..."
"$WEAVEC1_BIN" "$BUILD_DIR/01_return_42.wir" "$BUILD_DIR/01_return_42.ll" || fail "weavec1 compilation failed"

log "  Validating LLVM IR..."
llvm-as "$BUILD_DIR/01_return_42.ll" -o "$BUILD_DIR/01_return_42.bc" || fail "LLVM validation failed"

log "  Compiling to executable..."
clang "$BUILD_DIR/01_return_42.ll" "$RUNTIME" -o "$BUILD_DIR/01_return_42" || fail "clang compilation failed"

log "  Running executable..."
"$BUILD_DIR/01_return_42"
EXIT_CODE=$?
if [[ $EXIT_CODE != 42 ]]; then
  fail "Expected exit code 42, got $EXIT_CODE"
fi

log "Test 01: PASSED"
log ""
log "All tests passed!"
