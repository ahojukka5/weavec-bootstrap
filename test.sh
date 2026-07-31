#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

# Single-test smoke for weavec-bootstrap. Run ./build.sh first so that
# build/toolchain.env describes the selected compiler and runtime.

WEAVEC_BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$WEAVEC_BOOTSTRAP_DIR/build"
TOOLCHAIN_ENV="$BUILD_DIR/toolchain.env"

cd "$WEAVEC_BOOTSTRAP_DIR"

[[ -f "$TOOLCHAIN_ENV" ]] || {
  echo "toolchain metadata missing: $TOOLCHAIN_ENV (run ./build.sh first)" >&2
  exit 1
}
# shellcheck disable=SC1090
source "$TOOLCHAIN_ENV"

WEAVEC_BOOTSTRAP="$BUILD_DIR/weavec-bootstrap"
WEAVE_RUNTIME_MODE="${WEAVE_RUNTIME_MODE:-source}"
WEAVE_RUNTIME_LIBRARY="${WEAVE_RUNTIME_LIBRARY:-}"
WEAVE_RUNTIME_C="${WEAVE_RUNTIME_C:-}"
WEAVE_RUNTIME_LIBC="${WEAVE_RUNTIME_LIBC:-glibc}"

log() {
  echo "[test] $*"
}

fail() {
  echo "[test] ERROR: $*" >&2
  exit 1
}

[[ -x "$WEAVEC_BOOTSTRAP" ]] || fail "weavec-bootstrap not found (run ./build.sh first)"
[[ -x "$WEAVEC1_BIN" ]] || fail "weavec1 not found: $WEAVEC1_BIN"

log "Test 01: return_42"
log "  Compiling Surface Weave to WIR..."
rm -f "$BUILD_DIR/01_return_42.wir"
"$WEAVEC_BOOTSTRAP" test/01_return_42.weave "$BUILD_DIR/01_return_42.wir" \
  || fail "weavec-bootstrap compilation failed"

log "  Comparing WIR output..."
diff test/01_return_42.expected.wir "$BUILD_DIR/01_return_42.wir" \
  || fail "WIR output mismatch"

log "  Compiling WIR to LLVM IR..."
"$WEAVEC1_BIN" "$BUILD_DIR/01_return_42.wir" \
  "$BUILD_DIR/01_return_42.ll" || fail "weavec1 compilation failed"

log "  Validating LLVM IR..."
llvm-as "$BUILD_DIR/01_return_42.ll" -o "$BUILD_DIR/01_return_42.bc" \
  || fail "LLVM validation failed"

log "  Compiling to executable..."
case "$WEAVE_RUNTIME_MODE" in
  sdk)
    clang -Wno-override-module -O2 -c "$BUILD_DIR/01_return_42.ll" \
      -o "$BUILD_DIR/01_return_42.o"
    if [[ "$(uname -s)" == Darwin ]]; then
      clang "$BUILD_DIR/01_return_42.o" "$WEAVE_RUNTIME_LIBRARY" \
        -o "$BUILD_DIR/01_return_42"
    else
      case "$WEAVE_RUNTIME_LIBC" in
        glibc)
          clang -static "$BUILD_DIR/01_return_42.o" "$WEAVE_RUNTIME_LIBRARY" \
            -o "$BUILD_DIR/01_return_42"
          ;;
        musl)
          command -v musl-gcc >/dev/null 2>&1 \
            || fail "musl-gcc is required for the musl SDK"
          musl-gcc -static "$BUILD_DIR/01_return_42.o" \
            "$WEAVE_RUNTIME_LIBRARY" -o "$BUILD_DIR/01_return_42"
          ;;
        *) fail "unknown SDK libc: $WEAVE_RUNTIME_LIBC" ;;
      esac
    fi
    ;;
  source)
    [[ -f "$WEAVE_RUNTIME_C" ]] || fail "runtime source not found"
    clang "$BUILD_DIR/01_return_42.ll" "$WEAVE_RUNTIME_C" \
      -o "$BUILD_DIR/01_return_42"
    ;;
  *) fail "unknown runtime mode: $WEAVE_RUNTIME_MODE" ;;
esac

log "  Running executable..."
set +e
"$BUILD_DIR/01_return_42"
EXIT_CODE=$?
set -e
if [[ $EXIT_CODE != 42 ]]; then
  fail "Expected exit code 42, got $EXIT_CODE"
fi

log "Test 01: PASSED"
log ""
log "All tests passed!"
