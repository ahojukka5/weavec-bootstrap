#!/usr/bin/env bash
set -euo pipefail

WEAVEFRONT="./build/weavefront"
WEAVEC1="../weavec1/build/weavec1"
RUNTIME="../weavec0/runtime.c"
BUILD_DIR="build"

log() {
  echo "[test] $*"
}

fail() {
  echo "[test] ERROR: $*" >&2
  exit 1
}

# Check weavefront exists
[[ -x "$WEAVEFRONT" ]] || fail "weavefront not found at $WEAVEFRONT (run ./build.sh first)"

# Check weavec1 exists
[[ -x "$WEAVEC1" ]] || fail "weavec1 not found at $WEAVEC1"

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
$WEAVEC1 "$BUILD_DIR/01_return_42.wir" "$BUILD_DIR/01_return_42.ll" || fail "weavec1 compilation failed"

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
