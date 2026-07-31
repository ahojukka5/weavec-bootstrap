#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

# Build the frozen bootstrap frontend from a released Stage 1 SDK. Rebuilding
# weavec0 or weavec1 is release-maintenance work in those repositories and is
# never an implicit dependency fallback here.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$ROOT/build"
VENDOR_DIR="$BUILD_DIR/vendor"
DOWNLOAD_DIR="$BUILD_DIR/downloads"
TOOLCHAIN_ENV="$BUILD_DIR/toolchain.env"
SEXPR_LIBRARY="$BUILD_DIR/libweave-sexpr.bc"
PORTABLE_RUNTIME_C="$ROOT/runtime/portable.c"
STACK_SIZE="0x1000000"

WEAVEC1_VERSION="${WEAVEC1_VERSION:-v0.3.2}"
WEAVEC1_LIBC="${WEAVEC1_LIBC:-glibc}"
WEAVEC1_RELEASE_BASE="${WEAVEC1_RELEASE_BASE:-https://github.com/ahojukka5/weavec1/releases/download}"
WEAVEC1_SDK_DIR=""
WEAVEC1_BIN=""
RUNTIME_LIBRARY=""
SDK_SUFFIX=""

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

resolve_sdk_suffix() {
  case "$(uname -s):$(uname -m)" in
    Linux:x86_64)
      case "$WEAVEC1_LIBC" in
        glibc|musl) ;;
        *) fail "WEAVEC1_LIBC must be glibc or musl" ;;
      esac
      SDK_SUFFIX="linux-x86_64-$WEAVEC1_LIBC"
      ;;
    Darwin:arm64) SDK_SUFFIX="macos-arm64" ;;
    Darwin:x86_64) SDK_SUFFIX="macos-x86_64" ;;
    *) fail "no published weavec1 SDK contract for $(uname -s)/$(uname -m)" ;;
  esac
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    fail "required checksum tool not found: sha256sum or shasum"
  fi
}

validate_sdk() {
  local sdk="$1"
  [[ -x "$sdk/bin/weavec1" ]] || fail "SDK compiler missing: $sdk/bin/weavec1"
  [[ -s "$sdk/lib/libweave-runtime.a" ]] || \
    fail "SDK runtime library missing: $sdk/lib/libweave-runtime.a"
  WEAVEC1_SDK_DIR="$sdk"
  WEAVEC1_BIN="$sdk/bin/weavec1"
  RUNTIME_LIBRARY="$sdk/lib/libweave-runtime.a"
}

download_sdk() {
  require_tool curl
  require_tool tar

  local package="weavec1-${WEAVEC1_VERSION}-${SDK_SUFFIX}"
  local archive="$package.tar.gz"
  local vendor_root="$VENDOR_DIR/weavec1-sdk"
  local sdk="$vendor_root/$package"
  local archive_path="$DOWNLOAD_DIR/$archive"
  local sums_path="$DOWNLOAD_DIR/weavec1-${WEAVEC1_VERSION}-SHA256SUMS"
  local release_url="$WEAVEC1_RELEASE_BASE/$WEAVEC1_VERSION"

  if [[ -d "$sdk" ]]; then
    log "using cached weavec1 SDK: $sdk"
    validate_sdk "$sdk"
    return
  fi

  mkdir -p "$DOWNLOAD_DIR" "$vendor_root"
  log "downloading weavec1 SDK $WEAVEC1_VERSION ($SDK_SUFFIX)"
  curl --fail --location --retry 3 --output "$archive_path" \
    "$release_url/$archive" || fail "published SDK asset is unavailable: $archive"
  curl --fail --location --retry 3 --output "$sums_path" \
    "$release_url/SHA256SUMS" || fail "published SDK checksums are unavailable"

  local expected actual
  expected="$(awk -v name="$archive" '$2 == name { print $1; exit }' "$sums_path")"
  [[ -n "$expected" ]] || fail "checksum not found for $archive"
  actual="$(sha256_file "$archive_path")"
  [[ "$actual" == "$expected" ]] || \
    fail "checksum mismatch for $archive: expected $expected, got $actual"

  rm -rf "$sdk"
  tar -C "$vendor_root" -xzf "$archive_path"
  validate_sdk "$sdk"
}

ensure_sdk() {
  if [[ -n "${WEAVEC1_SDK:-}" ]]; then
    log "using WEAVEC1_SDK: $WEAVEC1_SDK"
    validate_sdk "$WEAVEC1_SDK"
  else
    download_sdk
  fi
}

write_toolchain_env() {
  mkdir -p "$BUILD_DIR"
  {
    printf 'WEAVEC1_BIN=%q\n' "$WEAVEC1_BIN"
    printf 'WEAVE_RUNTIME_MODE=sdk\n'
    printf 'WEAVE_RUNTIME_LIBRARY=%q\n' "$RUNTIME_LIBRARY"
    printf 'WEAVE_RUNTIME_C=\n'
    printf 'WEAVE_RUNTIME_LIBC=%q\n' "$WEAVEC1_LIBC"
    printf 'WEAVEC1_SDK=%q\n' "$WEAVEC1_SDK_DIR"
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
    -o "$SEXPR_LIBRARY" || fail "failed to link $SEXPR_LIBRARY"
  [[ -s "$SEXPR_LIBRARY" ]] || fail "empty S-expression parser library"
}

link_executable() {
  local object="$BUILD_DIR/weavec-bootstrap.o"
  local portable_object="$BUILD_DIR/weavec-bootstrap-portable.o"
  clang -Wno-override-module -O2 -c "$BUILD_DIR/weavec-bootstrap.bc" -o "$object"
  clang -O2 -c "$PORTABLE_RUNTIME_C" -o "$portable_object"

  case "$(uname -s)" in
    Darwin)
      log "linking native macOS bootstrap executable"
      clang "$object" "$portable_object" "$RUNTIME_LIBRARY" \
        -Wl,-stack_size,"$STACK_SIZE" -o "$BUILD_DIR/weavec-bootstrap"
      ;;
    Linux)
      log "linking static Linux bootstrap executable ($WEAVEC1_LIBC)"
      case "$WEAVEC1_LIBC" in
        glibc)
          clang -static "$object" "$portable_object" "$RUNTIME_LIBRARY" \
            -Wl,-z,stack-size="$STACK_SIZE" -o "$BUILD_DIR/weavec-bootstrap"
          ;;
        musl)
          require_tool musl-gcc
          musl-gcc -static "$object" "$portable_object" "$RUNTIME_LIBRARY" \
            -Wl,-z,stack-size="$STACK_SIZE" -o "$BUILD_DIR/weavec-bootstrap"
          ;;
      esac
      ;;
  esac
}

link_modules() {
  local link_args=()
  local module
  for module in "${MODULES[@]}"; do
    link_args+=("$BUILD_DIR/${module}.ll")
  done
  log "linking frontend LLVM modules"
  llvm-link "${link_args[@]}" -o "$BUILD_DIR/weavec-bootstrap.bc" || \
    fail "llvm-link failed"
  link_executable
}

main() {
  cd "$ROOT"
  require_tool awk
  require_tool clang
  require_tool llvm-link
  [[ -f "$PORTABLE_RUNTIME_C" ]] || fail "portable runtime missing: $PORTABLE_RUNTIME_C"
  resolve_sdk_suffix
  ensure_sdk
  write_toolchain_env
  compile_modules
  build_sexpr_library
  link_modules
  log "dependency mode: published SDK ($SDK_SUFFIX)"
  log "build complete: $BUILD_DIR/weavec-bootstrap"
  log "parser library: $SEXPR_LIBRARY"
}

main "$@"
