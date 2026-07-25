#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

# =============================================================================
# weavec-bootstrap — surface Weave (.weave) to WIR (.wir) bootstrap frontend
# =============================================================================
#
# Linux x86-64 builds consume the published weavec1 SDK by default. The SDK
# contains the Stage 1 compiler and matching static Weave runtime library, so
# neither weavec0 nor weavec1 needs to be built from source.
#
# Environment overrides:
#
#   WEAVEC1_SDK=/path/to/extracted/sdk
#   WEAVEC1_VERSION=v0.3.1
#   WEAVEC1_LIBC=glibc|musl
#   WEAVEC1=/path/to/weavec1/source
#   WEAVEC1_TAG=v0.3.1
#   WEAVEC0=/path/to/weavec0/source
#   WEAVEC0_TAG=v0.4.0
# =============================================================================

WEAVEC_BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$WEAVEC_BOOTSTRAP_DIR/build"
VENDOR_DIR="$BUILD_DIR/vendor"
TOOLCHAIN_ENV="$BUILD_DIR/toolchain.env"
SEXPR_LIBRARY="$BUILD_DIR/libweave-sexpr.bc"
PORTABLE_RUNTIME_C="$WEAVEC_BOOTSTRAP_DIR/runtime/portable.c"
STACK_SIZE="0x1000000"

WEAVEC1_VERSION="${WEAVEC1_VERSION:-v0.3.1}"
WEAVEC1_TAG="${WEAVEC1_TAG:-$WEAVEC1_VERSION}"
WEAVEC1_LIBC="${WEAVEC1_LIBC:-glibc}"
WEAVEC1_RELEASE_BASE="${WEAVEC1_RELEASE_BASE:-https://github.com/ahojukka5/weavec1/releases/download}"
WEAVEC1_REPO="https://github.com/ahojukka5/weavec1.git"

WEAVEC0_TAG="${WEAVEC0_TAG:-v0.4.0}"
WEAVEC0_REPO="https://github.com/ahojukka5/weavec0.git"

DEPENDENCY_MODE=""
WEAVEC0_DIR=""
WEAVEC1_DIR=""
WEAVEC1_BIN=""
RUNTIME_LIBRARY=""
RUNTIME_C=""

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

log()  { printf '[weavec-bootstrap] %s\n' "$*" >&2; }
fail() { printf '[weavec-bootstrap] error: %s\n' "$*" >&2; exit 1; }
require_tool() {
  command -v "$1" >/dev/null 2>&1 || fail "required tool not found: $1"
}

host_has_published_sdk() {
  [[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]]
}

validate_sdk() {
  local sdk="$1"
  [[ -x "$sdk/bin/weavec1" ]] || \
    fail "SDK compiler missing: $sdk/bin/weavec1"
  [[ -s "$sdk/lib/libweave-runtime.a" ]] || \
    fail "SDK runtime library missing: $sdk/lib/libweave-runtime.a"

  WEAVEC1_BIN="$sdk/bin/weavec1"
  RUNTIME_LIBRARY="$sdk/lib/libweave-runtime.a"
  DEPENDENCY_MODE=sdk
}

download_weavec1_sdk() {
  require_tool curl
  require_tool sha256sum
  require_tool tar

  case "$WEAVEC1_LIBC" in
    glibc|musl) ;;
    *) fail "WEAVEC1_LIBC must be glibc or musl" ;;
  esac

  local package="weavec1-${WEAVEC1_VERSION}-linux-x86_64-${WEAVEC1_LIBC}"
  local archive="$package.tar.gz"
  local vendor_root="$VENDOR_DIR/weavec1-sdk"
  local sdk="$vendor_root/$package"
  local cache="$BUILD_DIR/downloads"
  local archive_path="$cache/$archive"
  local sums_path="$cache/weavec1-${WEAVEC1_VERSION}-SHA256SUMS"
  local release_url="$WEAVEC1_RELEASE_BASE/$WEAVEC1_VERSION"

  if [[ -d "$sdk" ]]; then
    log "using cached weavec1 SDK: $sdk"
    validate_sdk "$sdk"
    return
  fi

  mkdir -p "$cache" "$vendor_root"
  log "downloading weavec1 SDK $WEAVEC1_VERSION ($WEAVEC1_LIBC)"
  curl --fail --location --retry 3 --output "$archive_path" \
    "$release_url/$archive"
  curl --fail --location --retry 3 --output "$sums_path" \
    "$release_url/SHA256SUMS"

  local expected
  expected="$(awk -v name="$archive" '$2 == name { print $1; exit }' \
    "$sums_path")"
  [[ -n "$expected" ]] || fail "checksum not found for $archive"
  printf '%s  %s\n' "$expected" "$archive_path" | sha256sum --check -

  rm -rf "$sdk"
  tar -C "$vendor_root" -xzf "$archive_path"
  validate_sdk "$sdk"
}

ensure_weavec0_source() {
  require_tool git

  if [[ -n "${WEAVEC0:-}" ]]; then
    WEAVEC0_DIR="$WEAVEC0"
    log "using WEAVEC0 source tree: $WEAVEC0_DIR"
  else
    WEAVEC0_DIR="$VENDOR_DIR/weavec0-source"
    if [[ ! -d "$WEAVEC0_DIR/.git" ]]; then
      log "fetching weavec0 source fallback $WEAVEC0_TAG"
      mkdir -p "$(dirname "$WEAVEC0_DIR")"
      git clone --depth 1 --branch "$WEAVEC0_TAG" "$WEAVEC0_REPO" \
        "$WEAVEC0_DIR"
    fi
  fi

  [[ -x "$WEAVEC0_DIR/build.sh" ]] || \
    fail "weavec0 build.sh missing: $WEAVEC0_DIR/build.sh"
  if [[ ! -x "$WEAVEC0_DIR/weavec0" ]]; then
    log "building weavec0 source fallback"
    (cd "$WEAVEC0_DIR" && ./build.sh)
  fi

  RUNTIME_C="$WEAVEC0_DIR/runtime.c"
  [[ -f "$RUNTIME_C" ]] || fail "weavec0 runtime.c missing: $RUNTIME_C"
}

ensure_weavec1_source() {
  ensure_weavec0_source

  if [[ -n "${WEAVEC1:-}" ]]; then
    WEAVEC1_DIR="$WEAVEC1"
    log "using WEAVEC1 source tree: $WEAVEC1_DIR"
  else
    WEAVEC1_DIR="$VENDOR_DIR/weavec1-source"
    if [[ ! -d "$WEAVEC1_DIR/.git" ]]; then
      log "fetching weavec1 source fallback $WEAVEC1_TAG"
      mkdir -p "$(dirname "$WEAVEC1_DIR")"
      git clone --depth 1 --branch "$WEAVEC1_TAG" "$WEAVEC1_REPO" \
        "$WEAVEC1_DIR"
    fi
  fi

  [[ -x "$WEAVEC1_DIR/build.sh" ]] || \
    fail "weavec1 build.sh missing: $WEAVEC1_DIR/build.sh"

  WEAVEC1_BIN="$WEAVEC1_DIR/build/weavec1"
  if [[ ! -x "$WEAVEC1_BIN" ]]; then
    log "building weavec1 source fallback"
    (cd "$WEAVEC1_DIR" && WEAVEC0="$WEAVEC0_DIR" ./build.sh)
  fi
  [[ -x "$WEAVEC1_BIN" ]] || fail "weavec1 compiler was not built"
  DEPENDENCY_MODE=source
}

ensure_dependencies() {
  if [[ -n "${WEAVEC1_SDK:-}" ]]; then
    log "using WEAVEC1_SDK: $WEAVEC1_SDK"
    validate_sdk "$WEAVEC1_SDK"
  elif [[ -n "${WEAVEC1:-}" ]]; then
    ensure_weavec1_source
  elif host_has_published_sdk; then
    download_weavec1_sdk
  else
    log "no published SDK for $(uname -s)/$(uname -m); using source fallback"
    ensure_weavec1_source
  fi
}

write_toolchain_env() {
  mkdir -p "$BUILD_DIR"
  {
    printf 'WEAVEC1_BIN=%q\n' "$WEAVEC1_BIN"
    printf 'WEAVE_RUNTIME_MODE=%q\n' "$DEPENDENCY_MODE"
    printf 'WEAVE_RUNTIME_LIBRARY=%q\n' "$RUNTIME_LIBRARY"
    printf 'WEAVE_RUNTIME_C=%q\n' "$RUNTIME_C"
    printf 'WEAVE_RUNTIME_LIBC=%q\n' "$WEAVEC1_LIBC"
  } > "$TOOLCHAIN_ENV"
}

compile_modules() {
  mkdir -p "$BUILD_DIR"
  log "compiling weavec-bootstrap modules"
  local module
  for module in "${MODULES[@]}"; do
    local src="src/${module}.wir"
    local ll="$BUILD_DIR/${module}.ll"
    [[ -f "$src" ]] || fail "missing source module: $src"
    "$WEAVEC1_BIN" "$src" "$ll" || fail "failed to compile ${module}.wir"
    [[ -s "$ll" ]] || fail "weavec1 produced empty LLVM IR for ${module}"
  done
}

build_sexpr_library() {
  log "linking reusable S-expression parser library"
  llvm-link \
    "$BUILD_DIR/sexpr_tokens.ll" \
    "$BUILD_DIR/sexpr_tree.ll" \
    "$BUILD_DIR/sexpr_lexer.ll" \
    "$BUILD_DIR/sexpr_parser.ll" \
    -o "$SEXPR_LIBRARY" \
    || fail "failed to link $SEXPR_LIBRARY"
  [[ -s "$SEXPR_LIBRARY" ]] || fail "empty S-expression parser library"
}

link_with_sdk() {
  local object="$BUILD_DIR/weavec-bootstrap.o"
  local portable_object="$BUILD_DIR/weavec-bootstrap-portable.o"
  clang -Wno-override-module -O2 -c "$BUILD_DIR/weavec-bootstrap.bc" -o "$object"

  log "linking static weavec-bootstrap executable ($WEAVEC1_LIBC)"
  case "$WEAVEC1_LIBC" in
    glibc)
      clang -O2 -c "$PORTABLE_RUNTIME_C" -o "$portable_object"
      clang -static "$object" "$portable_object" "$RUNTIME_LIBRARY" \
        -Wl,-z,stack-size="$STACK_SIZE" \
        -o "$BUILD_DIR/weavec-bootstrap"
      ;;
    musl)
      require_tool musl-gcc
      musl-gcc -O2 -c "$PORTABLE_RUNTIME_C" -o "$portable_object"
      musl-gcc -static "$object" "$portable_object" "$RUNTIME_LIBRARY" \
        -Wl,-z,stack-size="$STACK_SIZE" \
        -o "$BUILD_DIR/weavec-bootstrap"
      ;;
  esac
}

link_with_source() {
  log "linking weavec-bootstrap with source runtime fallback"
  if [[ "$(uname -s)" == Darwin ]]; then
    clang "$BUILD_DIR/weavec-bootstrap.bc" "$RUNTIME_C" "$PORTABLE_RUNTIME_C" \
      -Wl,-stack_size,"$STACK_SIZE" \
      -o "$BUILD_DIR/weavec-bootstrap"
  else
    clang "$BUILD_DIR/weavec-bootstrap.bc" "$RUNTIME_C" "$PORTABLE_RUNTIME_C" \
      -Wl,-z,stack-size="$STACK_SIZE" \
      -o "$BUILD_DIR/weavec-bootstrap"
  fi
}

link_and_compile() {
  local link_args=()
  local module
  for module in "${MODULES[@]}"; do
    link_args+=("$BUILD_DIR/${module}.ll")
  done

  log "linking frontend LLVM modules"
  llvm-link "${link_args[@]}" -o "$BUILD_DIR/weavec-bootstrap.bc" \
    || fail "llvm-link failed"

  case "$DEPENDENCY_MODE" in
    sdk) link_with_sdk ;;
    source) link_with_source ;;
    *) fail "unknown dependency mode: $DEPENDENCY_MODE" ;;
  esac
}

main() {
  cd "$WEAVEC_BOOTSTRAP_DIR"
  require_tool awk
  require_tool clang
  require_tool llvm-as
  require_tool llvm-link
  [[ -f "$PORTABLE_RUNTIME_C" ]] || \
    fail "portable runtime missing: $PORTABLE_RUNTIME_C"
  ensure_dependencies
  write_toolchain_env
  compile_modules
  build_sexpr_library
  link_and_compile
  log "build complete: $BUILD_DIR/weavec-bootstrap"
  log "parser library: $SEXPR_LIBRARY"
}

main "$@"
