#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

# weavec-bootstrap test ladder. Run ./build.sh first; it records the resolved
# Stage 1 compiler and runtime in build/toolchain.env for this script.

WEAVEC_BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$WEAVEC_BOOTSTRAP_DIR/build"
VENDOR_DIR="$BUILD_DIR/vendor"
TOOLCHAIN_ENV="$BUILD_DIR/toolchain.env"
MANIFEST="$WEAVEC_BOOTSTRAP_DIR/test/manifest.txt"

cd "$WEAVEC_BOOTSTRAP_DIR"

if [[ -f "$TOOLCHAIN_ENV" ]]; then
  # shellcheck disable=SC1090
  source "$TOOLCHAIN_ENV"
fi

WEAVEC_BOOTSTRAP="$BUILD_DIR/weavec-bootstrap"
WEAVEC1_DIR="${WEAVEC1:-$VENDOR_DIR/weavec1-source}"
WEAVEC0_DIR="${WEAVEC0:-$VENDOR_DIR/weavec0-source}"
WEAVEC1_BIN="${WEAVEC1_BIN:-$WEAVEC1_DIR/build/weavec1}"
WEAVE_RUNTIME_MODE="${WEAVE_RUNTIME_MODE:-source}"
WEAVE_RUNTIME_LIBRARY="${WEAVE_RUNTIME_LIBRARY:-}"
WEAVE_RUNTIME_C="${WEAVE_RUNTIME_C:-$WEAVEC0_DIR/runtime.c}"
WEAVE_RUNTIME_LIBC="${WEAVE_RUNTIME_LIBC:-glibc}"

PASS_COUNT=0
FAIL_COUNT=0

log() {
  printf '[test-all] %s\n' "$*"
}

fail() {
  printf '[test-all] ERROR: %s\n' "$*" >&2
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    printf '[test-all] required tool not found: %s\n' "$1" >&2
    exit 1
  }
}

[[ -x "$WEAVEC_BOOTSTRAP" ]] || {
  printf 'weavec-bootstrap not found at %s (run ./build.sh first)\n' \
    "$WEAVEC_BOOTSTRAP" >&2
  exit 1
}
[[ -x "$WEAVEC1_BIN" ]] || {
  printf 'weavec1 not found at %s (run ./build.sh first)\n' "$WEAVEC1_BIN" >&2
  exit 1
}
[[ -f "$MANIFEST" ]] || {
  printf 'test manifest not found: %s\n' "$MANIFEST" >&2
  exit 1
}

require_tool clang
require_tool diff
require_tool llvm-as

case "$WEAVE_RUNTIME_MODE" in
  sdk)
    [[ -s "$WEAVE_RUNTIME_LIBRARY" ]] || {
      printf 'runtime library not found: %s\n' "$WEAVE_RUNTIME_LIBRARY" >&2
      exit 1
    }
    if [[ "$WEAVE_RUNTIME_LIBC" == musl ]]; then
      require_tool musl-gcc
    fi
    ;;
  source)
    [[ -f "$WEAVE_RUNTIME_C" ]] || {
      printf 'runtime source not found: %s\n' "$WEAVE_RUNTIME_C" >&2
      exit 1
    }
    ;;
  *)
    printf 'unknown runtime mode: %s\n' "$WEAVE_RUNTIME_MODE" >&2
    exit 1
    ;;
esac

mkdir -p "$BUILD_DIR/test_wir" "$BUILD_DIR/test_ll" \
  "$BUILD_DIR/test_obj" "$BUILD_DIR/test_bin" "$BUILD_DIR/test_logs"

link_test_executable() {
  local ll_file="$1"
  local object_file="$2"
  local bin_file="$3"

  case "$WEAVE_RUNTIME_MODE" in
    sdk)
      clang -Wno-override-module -O2 -c "$ll_file" -o "$object_file"
      if [[ "$(uname -s)" == Darwin ]]; then
        clang "$object_file" "$WEAVE_RUNTIME_LIBRARY" -o "$bin_file"
      else
        case "$WEAVE_RUNTIME_LIBC" in
          glibc)
            clang -static "$object_file" "$WEAVE_RUNTIME_LIBRARY" -o "$bin_file"
            ;;
          musl)
            musl-gcc -static "$object_file" "$WEAVE_RUNTIME_LIBRARY" -o "$bin_file"
            ;;
          *) return 1 ;;
        esac
      fi
      ;;
    source)
      clang "$ll_file" "$WEAVE_RUNTIME_C" -o "$bin_file"
      ;;
  esac
}

run_case() {
  local name="$1"
  local expected_exit="$2"
  local weave_file="test/${name}.weave"
  local expected_wir="test/${name}.expected.wir"
  local wir_file="$BUILD_DIR/test_wir/${name}.wir"
  local ll_file="$BUILD_DIR/test_ll/${name}.ll"
  local bc_file="$BUILD_DIR/test_ll/${name}.bc"
  local object_file="$BUILD_DIR/test_obj/${name}.o"
  local bin_file="$BUILD_DIR/test_bin/${name}"
  local frontend_log="$BUILD_DIR/test_logs/${name}.frontend.log"
  local backend_log="$BUILD_DIR/test_logs/${name}.backend.log"

  [[ -f "$weave_file" ]] || {
    fail "$name: source fixture is missing"
    return
  }
  [[ -f "$expected_wir" ]] || {
    fail "$name: expected WIR fixture is missing"
    return
  }

  log "Testing: $name"
  rm -f "$wir_file" "$ll_file" "$bc_file" "$object_file" "$bin_file" \
    "$frontend_log" "$backend_log"

  if ! "$WEAVEC_BOOTSTRAP" "$weave_file" "$wir_file" \
      >"$frontend_log" 2>&1; then
    cat "$frontend_log" >&2
    fail "$name: surface-to-WIR compilation failed"
    return
  fi
  if [[ ! -s "$wir_file" ]]; then
    fail "$name: frontend produced empty WIR"
    return
  fi
  if [[ ! -r "$wir_file" ]]; then
    fail "$name: frontend output is not owner-readable"
    return
  fi

  if ! cmp -s "$expected_wir" "$wir_file"; then
    diff -u "$expected_wir" "$wir_file" >&2 || true
    fail "$name: WIR output differs byte for byte"
    return
  fi

  if ! "$WEAVEC1_BIN" "$wir_file" "$ll_file" >"$backend_log" 2>&1; then
    cat "$backend_log" >&2
    fail "$name: WIR-to-LLVM compilation failed"
    return
  fi
  if [[ ! -s "$ll_file" ]]; then
    fail "$name: backend produced empty LLVM IR"
    return
  fi
  if ! llvm-as "$ll_file" -o "$bc_file"; then
    fail "$name: generated LLVM IR does not assemble"
    return
  fi
  if ! link_test_executable "$ll_file" "$object_file" "$bin_file"; then
    fail "$name: executable link failed"
    return
  fi

  set +e
  "$bin_file"
  local actual_exit=$?
  set -e

  if [[ "$actual_exit" != "$expected_exit" ]]; then
    fail "$name: expected exit $expected_exit, got $actual_exit"
    return
  fi

  PASS_COUNT=$((PASS_COUNT + 1))
  log "  ✓ $name (exit code: $actual_exit)"
}

run_multifile_case() {
  local name="$1"
  local expected_exit="$2"
  local def_file="test/multifile/${name}_def.weave"
  local use_file="test/multifile/${name}_use.weave"
  local expected_wir="test/multifile/${name}.expected.wir"
  local combined_weave="$BUILD_DIR/test_wir/${name}.combined.weave"
  local wir_file="$BUILD_DIR/test_wir/${name}.wir"
  local ll_file="$BUILD_DIR/test_ll/${name}.ll"
  local bc_file="$BUILD_DIR/test_ll/${name}.bc"
  local object_file="$BUILD_DIR/test_obj/${name}.o"
  local bin_file="$BUILD_DIR/test_bin/${name}"
  local frontend_log="$BUILD_DIR/test_logs/${name}.frontend.log"
  local backend_log="$BUILD_DIR/test_logs/${name}.backend.log"
  local cat_helper="$WEAVEC_BOOTSTRAP_DIR/weavec-bootstrap-cat.sh"

  [[ -f "$def_file" && -f "$use_file" ]] || {
    fail "$name: multifile sources are missing"
    return
  }
  [[ -f "$expected_wir" ]] || {
    fail "$name: expected WIR fixture is missing"
    return
  }
  [[ -x "$cat_helper" ]] || {
    fail "$name: multifile driver is missing"
    return
  }

  log "Testing: $name (multifile)"
  rm -f "$wir_file" "$ll_file" "$bc_file" "$object_file" "$bin_file" \
    "$frontend_log" "$backend_log" "$combined_weave"

  if ! WEAVEC_BOOTSTRAP="$WEAVEC_BOOTSTRAP" \
      WEAVEC_BOOTSTRAP_CAT_SOURCE="$combined_weave" \
      "$cat_helper" "$wir_file" "$def_file" "$use_file" \
      >"$frontend_log" 2>&1; then
    cat "$frontend_log" >&2
    fail "$name: multifile surface-to-WIR compilation failed"
    return
  fi
  if [[ ! -s "$wir_file" ]]; then
    fail "$name: frontend produced empty WIR"
    return
  fi

  local def_count
  def_count="$(grep -c '(fn uniquely_named_tail_decl' "$wir_file" || true)"
  if [[ "$def_count" != 1 ]]; then
    fail "$name: uniquely named tail declaration count is $def_count, expected 1"
    return
  fi

  if ! cmp -s "$expected_wir" "$wir_file"; then
    diff -u "$expected_wir" "$wir_file" >&2 || true
    fail "$name: WIR output differs byte for byte"
    return
  fi

  if ! "$WEAVEC1_BIN" "$wir_file" "$ll_file" >"$backend_log" 2>&1; then
    cat "$backend_log" >&2
    fail "$name: WIR-to-LLVM compilation failed"
    return
  fi
  if ! llvm-as "$ll_file" -o "$bc_file"; then
    fail "$name: generated LLVM IR does not assemble"
    return
  fi
  if ! link_test_executable "$ll_file" "$object_file" "$bin_file"; then
    fail "$name: executable link failed"
    return
  fi

  set +e
  "$bin_file"
  local actual_exit=$?
  set -e

  if [[ "$actual_exit" != "$expected_exit" ]]; then
    fail "$name: expected exit $expected_exit, got $actual_exit"
    return
  fi

  PASS_COUNT=$((PASS_COUNT + 1))
  log "  ✓ $name (exit code: $actual_exit)"
}

while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%%#*}"
  line="${line#"${line%%[![:space:]]*}"}"
  [[ -z "$line" ]] && continue

  read -r kind name expected_exit extra <<<"$line"
  if [[ "$kind" != pass || -z "$name" || -z "$expected_exit" || -n "${extra:-}" ]]; then
    printf '[test-all] invalid manifest entry: %s\n' "$line" >&2
    exit 1
  fi
  if [[ ! "$expected_exit" =~ ^[0-9]+$ ]] || (( expected_exit > 255 )); then
    printf '[test-all] invalid exit code in manifest: %s\n' "$line" >&2
    exit 1
  fi

  run_case "$name" "$expected_exit"
done < "$MANIFEST"

log "Testing: extract_program_decls self-test"
if python3 "$WEAVEC_BOOTSTRAP_DIR/scripts/extract_program_decls.py" --self-test; then
  PASS_COUNT=$((PASS_COUNT + 1))
  log "  ✓ extract_program_decls"
else
  fail "extract_program_decls self-test failed"
fi

run_multifile_case "tail_decl" 7

log ""
log "=========================================="
log "Test Results: $PASS_COUNT passed, $FAIL_COUNT failed"
log "=========================================="

if (( FAIL_COUNT > 0 )); then
  exit 1
fi

log "All tests passed!"
