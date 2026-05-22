#!/usr/bin/env bash
set -euo pipefail

WEAVEC1="../weavec1/build/weavec1"
BUILD_DIR="build"
RUNTIME="../weavec0/runtime.c"

log() {
  echo "[weavefront] $*"
}

fail() {
  echo "[weavefront] ERROR: $*" >&2
  exit 1
}

# Check weavec1 exists
[[ -x "$WEAVEC1" ]] || fail "weavec1 not found at $WEAVEC1"

# Create build directory
mkdir -p "$BUILD_DIR"

# Compile all WIR modules
# Each module declares its external dependencies via (extern ...) in the WIR source.
# weavec1 emits the corresponding LLVM declare statements automatically.
log "Compiling weavefront modules..."
$WEAVEC1 src/sexpr_tokens.wir "$BUILD_DIR/sexpr_tokens.ll" || fail "Failed to compile sexpr_tokens.wir"
$WEAVEC1 src/sexpr_tree.wir "$BUILD_DIR/sexpr_tree.ll" || fail "Failed to compile sexpr_tree.wir"
$WEAVEC1 src/sexpr_lexer.wir "$BUILD_DIR/sexpr_lexer.ll" || fail "Failed to compile sexpr_lexer.wir"
$WEAVEC1 src/sexpr_parser.wir "$BUILD_DIR/sexpr_parser.ll" || fail "Failed to compile sexpr_parser.wir"
$WEAVEC1 src/sexpr_print.wir "$BUILD_DIR/sexpr_print.ll" || fail "Failed to compile sexpr_print.wir"
$WEAVEC1 src/surface_validate.wir "$BUILD_DIR/surface_validate.ll" || fail "Failed to compile surface_validate.wir"
$WEAVEC1 src/surface_lower.wir "$BUILD_DIR/surface_lower.ll" || fail "Failed to compile surface_lower.wir"
$WEAVEC1 src/driver.wir "$BUILD_DIR/driver.ll" || fail "Failed to compile driver.wir"
$WEAVEC1 src/main.wir "$BUILD_DIR/main.ll" || fail "Failed to compile main.wir"

# Link LLVM modules together
log "Linking LLVM modules..."
llvm-link \
  "$BUILD_DIR/sexpr_tokens.ll" \
  "$BUILD_DIR/sexpr_tree.ll" \
  "$BUILD_DIR/sexpr_lexer.ll" \
  "$BUILD_DIR/sexpr_parser.ll" \
  "$BUILD_DIR/sexpr_print.ll" \
  "$BUILD_DIR/surface_validate.ll" \
  "$BUILD_DIR/surface_lower.ll" \
  "$BUILD_DIR/driver.ll" \
  "$BUILD_DIR/main.ll" \
  -o "$BUILD_DIR/weavefront.bc" || fail "Failed to link LLVM modules"

# Compile to executable
log "Compiling to executable..."
clang "$BUILD_DIR/weavefront.bc" "$RUNTIME" -o "$BUILD_DIR/weavefront" || fail "Failed to compile weavefront"

log "Build complete: $BUILD_DIR/weavefront"
