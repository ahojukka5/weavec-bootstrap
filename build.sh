#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

# =============================================================================
# weavefront — surface Weave (.weave) → WIR (.wir) frontend, build script
# =============================================================================
#
# Pipeline:
#
#   1. Acquire weavec0 (Stage 0 seed compiler, hand-written LLVM IR).
#      Honour the WEAVEC0 env var (path to a pre-built source tree),
#      or clone the pinned $WEAVEC0_TAG from upstream into
#      build/vendor/weavec0. We need weavec0 for its runtime.c
#      (malloc / free / puts / file I/O).
#
#   2. Acquire weavec1 (Stage 1 compiler, WIR-written). Honour WEAVEC1,
#      or clone $WEAVEC1_TAG into build/vendor/weavec1. weavec1's own
#      build.sh is invoked with WEAVEC0 pointing at the source tree
#      from step 1, so we don't fetch / build weavec0 twice.
#
#   3. Compile every weavefront WIR module under src/ with weavec1 →
#      LLVM IR.
#
#   4. Link the modules with weavec0's runtime.c to produce the
#      weavefront binary.
#
# Environment:
#
#   WEAVEC0
#       Absolute path to an existing weavec0 source tree where
#       ./build.sh has already been run. Skips the vendor fetch and
#       reuses the binary + runtime.c in place.
#
#   WEAVEC0_TAG  (default: v0.2.0)
#       Git tag/ref pulled from github.com/ahojukka5/weavec0 when no
#       WEAVEC0 is provided.
#
#   WEAVEC1
#       Absolute path to an existing weavec1 source tree where
#       ./build.sh has already been run. Skips the vendor fetch and
#       reuses build/weavec1 in place.
#
#   WEAVEC1_TAG  (default: v0.1.0)
#       Git tag/ref pulled from github.com/ahojukka5/weavec1 when no
#       WEAVEC1 is provided.
# =============================================================================

WEAVEFRONT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$WEAVEFRONT_DIR/src"
BUILD_DIR="$WEAVEFRONT_DIR/build"
VENDOR_DIR="$BUILD_DIR/vendor"

WEAVEC0_TAG="${WEAVEC0_TAG:-v0.2.0}"
WEAVEC0_REPO="https://github.com/ahojukka5/weavec0.git"

WEAVEC1_TAG="${WEAVEC1_TAG:-v0.1.0}"
WEAVEC1_REPO="https://github.com/ahojukka5/weavec1.git"

WEAVEC0_DIR=""        # populated by ensure_weavec0
WEAVEC1_DIR=""        # populated by ensure_weavec1
WEAVEC1_BIN=""        # path to the weavec1 executable
RUNTIME_C=""          # path to weavec0/runtime.c

# Module compile order. string_utils.wir is intentionally not in this
# list — it defines extern wrappers nothing currently consumes; revisit
# when a module actually links against it.
MODULES=(
  sexpr_tokens
  sexpr_tree
  sexpr_lexer
  sexpr_parser
  sexpr_print
  surface_validate
  surface_lower
  surface_struct
  driver
  main
)

log()  { printf '[weavefront] %s\n' "$*" >&2; }
fail() { printf '[weavefront] error: %s\n' "$*" >&2; exit 1; }
require_tool() { command -v "$1" >/dev/null 2>&1 || fail "required tool not found: $1"; }

ensure_weavec0() {
  if [[ -n "${WEAVEC0:-}" ]]; then
    WEAVEC0_DIR="$WEAVEC0"
    log "using WEAVEC0 from env: $WEAVEC0_DIR"
  else
    WEAVEC0_DIR="$VENDOR_DIR/weavec0"
    if [[ ! -d "$WEAVEC0_DIR/.git" ]]; then
      log "fetching weavec0 $WEAVEC0_TAG from $WEAVEC0_REPO"
      mkdir -p "$(dirname "$WEAVEC0_DIR")"
      git clone --depth 1 --branch "$WEAVEC0_TAG" "$WEAVEC0_REPO" "$WEAVEC0_DIR"
    fi
  fi

  [[ -d "$WEAVEC0_DIR" ]] || fail "weavec0 source dir not found: $WEAVEC0_DIR"
  [[ -x "$WEAVEC0_DIR/build.sh" ]] || fail "weavec0 build.sh not found at $WEAVEC0_DIR/build.sh"

  if [[ ! -x "$WEAVEC0_DIR/weavec0" ]] || [[ ! -d "$WEAVEC0_DIR/build/bootstrap-tests/bc" ]]; then
    log "building weavec0 ($WEAVEC0_DIR)"
    ( cd "$WEAVEC0_DIR" && ./build.sh ) || fail "weavec0 build failed"
  fi

  RUNTIME_C="$WEAVEC0_DIR/runtime.c"
  [[ -f "$RUNTIME_C" ]] || fail "weavec0 runtime.c not found at $RUNTIME_C"
}

ensure_weavec1() {
  if [[ -n "${WEAVEC1:-}" ]]; then
    WEAVEC1_DIR="$WEAVEC1"
    log "using WEAVEC1 from env: $WEAVEC1_DIR"
  else
    WEAVEC1_DIR="$VENDOR_DIR/weavec1"
    if [[ ! -d "$WEAVEC1_DIR/.git" ]]; then
      log "fetching weavec1 $WEAVEC1_TAG from $WEAVEC1_REPO"
      mkdir -p "$(dirname "$WEAVEC1_DIR")"
      git clone --depth 1 --branch "$WEAVEC1_TAG" "$WEAVEC1_REPO" "$WEAVEC1_DIR"
    fi
  fi

  [[ -d "$WEAVEC1_DIR" ]] || fail "weavec1 source dir not found: $WEAVEC1_DIR"
  [[ -x "$WEAVEC1_DIR/build.sh" ]] || fail "weavec1 build.sh not found at $WEAVEC1_DIR/build.sh"

  WEAVEC1_BIN="$WEAVEC1_DIR/build/weavec1"
  if [[ ! -x "$WEAVEC1_BIN" ]]; then
    log "building weavec1 ($WEAVEC1_DIR)"
    # weavec1's own build.sh honours WEAVEC0 — point it at the source
    # tree we already prepared so it doesn't fetch / build weavec0
    # a second time.
    ( cd "$WEAVEC1_DIR" && WEAVEC0="$WEAVEC0_DIR" ./build.sh ) \
      || fail "weavec1 build failed"
  fi
  [[ -x "$WEAVEC1_BIN" ]] || fail "weavec1 binary not built at $WEAVEC1_BIN"
}

compile_modules() {
  mkdir -p "$BUILD_DIR"
  log "compiling weavefront modules"
  local module
  for module in "${MODULES[@]}"; do
    local src="$SRC_DIR/${module}.wir"
    local ll="$BUILD_DIR/${module}.ll"
    [[ -f "$src" ]] || fail "missing source module: $src"
    "$WEAVEC1_BIN" "$src" "$ll" || fail "failed to compile ${module}.wir"
    [[ -s "$ll" ]] || fail "weavec1 produced empty LLVM IR for ${module}"
  done
}

link_and_compile() {
  local link_args=()
  local module
  for module in "${MODULES[@]}"; do
    link_args+=("$BUILD_DIR/${module}.ll")
  done

  log "linking LLVM modules"
  llvm-link "${link_args[@]}" -o "$BUILD_DIR/weavefront.bc" \
    || fail "llvm-link failed"

  log "compiling to executable"
  clang "$BUILD_DIR/weavefront.bc" "$RUNTIME_C" -o "$BUILD_DIR/weavefront" \
    || fail "clang link failed"
}

main() {
  require_tool clang
  require_tool llvm-as
  require_tool llvm-link
  require_tool git
  ensure_weavec0
  ensure_weavec1
  compile_modules
  link_and_compile
  log "build complete: $BUILD_DIR/weavefront"
}

main "$@"
