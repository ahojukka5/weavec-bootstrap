#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

# weavefront test ladder. Run ./build.sh first; it records the resolved Stage 1
# compiler and runtime in build/toolchain.env for this script.

WEAVEFRONT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$WEAVEFRONT_DIR/build"
VENDOR_DIR="$BUILD_DIR/vendor"
TOOLCHAIN_ENV="$BUILD_DIR/toolchain.env"

cd "$WEAVEFRONT_DIR"

if [[ -f "$TOOLCHAIN_ENV" ]]; then
  # shellcheck disable=SC1090
  source "$TOOLCHAIN_ENV"
fi

WEAVEFRONT="$BUILD_DIR/weavefront"
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
  echo "[test-all] $*"
}

fail() {
  echo "[test-all] ERROR: $*" >&2
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

[[ -x "$WEAVEFRONT" ]] || {
  echo "weavefront not found at $WEAVEFRONT (run ./build.sh first)" >&2
  exit 1
}
[[ -x "$WEAVEC1_BIN" ]] || {
  echo "weavec1 not found at $WEAVEC1_BIN (run ./build.sh first)" >&2
  exit 1
}

case "$WEAVE_RUNTIME_MODE" in
  sdk)
    [[ -s "$WEAVE_RUNTIME_LIBRARY" ]] || {
      echo "runtime library not found: $WEAVE_RUNTIME_LIBRARY" >&2
      exit 1
    }
    if [[ "$WEAVE_RUNTIME_LIBC" == musl ]]; then
      command -v musl-gcc >/dev/null 2>&1 || {
        echo "musl-gcc is required for the musl SDK tests" >&2
        exit 1
      }
    fi
    ;;
  source)
    [[ -f "$WEAVE_RUNTIME_C" ]] || {
      echo "runtime source not found: $WEAVE_RUNTIME_C" >&2
      exit 1
    }
    ;;
  *)
    echo "unknown runtime mode: $WEAVE_RUNTIME_MODE" >&2
    exit 1
    ;;
esac

mkdir -p "$BUILD_DIR/test_wir" "$BUILD_DIR/test_ll" \
  "$BUILD_DIR/test_obj" "$BUILD_DIR/test_bin"

get_expected_exit() {
  case "$1" in
    01_return_42)                        echo 42  ;;
    02_return_constant)                  echo 0   ;;
    03_return_42)                        echo 42  ;;
    04_add_i32)                          echo 42  ;;
    05_one_arg_function)                 echo 43  ;;
    06_let_local)                        echo 42  ;;
    07_set_local)                        echo 42  ;;
    08_if)                               echo 42  ;;
    09_while)                            echo 42  ;;
    10_two_arg_function)                 echo 42  ;;
    11_string_literal)                   echo 42  ;;
    12_const_i64)                        echo 42  ;;
    13_i64_arithmetic)                   echo 42  ;;
    14_i64_comparisons)                  echo 42  ;;
    15_bool_ops)                         echo 42  ;;
    16_ptr_null)                         echo 42  ;;
    17_extern_malloc_free)               echo 42  ;;
    18_ptr_add_store_load_i64)           echo 42  ;;
    19_store_load_i8)                    echo 42  ;;
    20_call_void)                        echo 42  ;;
    21_call_i64)                         echo 42  ;;
    22_call_ptr)                         echo 42  ;;
    23_return_void)                      echo 42  ;;
    24_mod_i32)                          echo 2   ;;
    25_buffer_like_smoke)                echo 42  ;;
    26_ptr_params_call_i32)              echo 42  ;;
    27_bool_return)                      echo 42  ;;
    28_three_arg_function)               echo 42  ;;
    29_i32_memory_and_cast)              echo 42  ;;
    30_const_string_ptr)                 echo 42  ;;
    31_i64_sub_eq)                       echo 42  ;;
    32_not_bool)                         echo 42  ;;
    33_codegen_join_and_i64_arg)         echo 42  ;;
    34_store_i8_temp)                    echo 42  ;;
    35_ge_i32)                           echo 42  ;;
    36_sub_i32)                          echo 42  ;;
    37_mul_i32)                          echo 42  ;;
    38_div_i32)                          echo 42  ;;
    39_i32_comparisons_full)             echo 42  ;;
    40_i64_ge_gt)                        echo 42  ;;
    41_call_bool_direct)                 echo 42  ;;
    42_load_store_ptr)                   echo 42  ;;
    43_empty_do)                         echo 42  ;;
    44_if_fallthrough_join)              echo 42  ;;
    45_while_zero_iterations)            echo 42  ;;
    46_nested_while)                     echo 42  ;;
    47_forward_function_call)            echo 42  ;;
    48_multiple_externs_used_subset)     echo 42  ;;
    49_string_escape)                    echo 42  ;;
    50_negative_i32_literal)             echo 42  ;;
    51_debug_marker)                     echo 42  ;;
    52_integration_nested_control_flow)  echo 75  ;;
    53_integration_multi_function_chain) echo 35  ;;
    54_integration_memory_flow)          echo 100 ;;
    55_new_operators)                    echo 40  ;;
    56_extern_decl)                      echo 42  ;;
    57_struct_basic)                     echo 42  ;;
    58_const_decl)                       echo 42  ;;
    *) echo 42 ;;
  esac
}

link_test_executable() {
  local ll_file="$1"
  local object_file="$2"
  local bin_file="$3"

  case "$WEAVE_RUNTIME_MODE" in
    sdk)
      clang -Wno-override-module -O2 -c "$ll_file" -o "$object_file"
      case "$WEAVE_RUNTIME_LIBC" in
        glibc)
          clang -static "$object_file" "$WEAVE_RUNTIME_LIBRARY" \
            -o "$bin_file"
          ;;
        musl)
          musl-gcc -static "$object_file" "$WEAVE_RUNTIME_LIBRARY" \
            -o "$bin_file"
          ;;
        *) return 1 ;;
      esac
      ;;
    source)
      clang "$ll_file" "$WEAVE_RUNTIME_C" -o "$bin_file"
      ;;
  esac
}

for weave_file in test/*.weave; do
  test_name=$(basename "$weave_file" .weave)
  expected_wir="test/${test_name}.expected.wir"
  wir_file="$BUILD_DIR/test_wir/${test_name}.wir"

  log "Testing (wir): $test_name"

  rm -f "$wir_file"
  if ! "$WEAVEFRONT" "$weave_file" "$wir_file" 2>/dev/null; then
    fail "$test_name: weavefront compilation failed"
    continue
  fi
  chmod u+r "$wir_file" 2>/dev/null || true

  actual_wir=$(cat "$wir_file")
  expected=$(cat "$expected_wir")
  if [[ "$actual_wir" != "$expected" ]]; then
    fail "$test_name: WIR output mismatch"
    echo "  expected: $expected" >&2
    echo "  actual:   $actual_wir" >&2
    continue
  fi

  log "  ✓ $test_name PASSED"
  PASS_COUNT=$((PASS_COUNT + 1))
done

for weave_file in test/*.weave; do
  test_name=$(basename "$weave_file" .weave)
  wir_file="$BUILD_DIR/test_wir/${test_name}.wir"
  ll_file="$BUILD_DIR/test_ll/${test_name}.ll"
  object_file="$BUILD_DIR/test_obj/${test_name}.o"
  bin_file="$BUILD_DIR/test_bin/${test_name}"

  log "Testing (e2e): $test_name"

  if [[ ! -f "$wir_file" ]]; then
    rm -f "$wir_file"
    if ! "$WEAVEFRONT" "$weave_file" "$wir_file" 2>/dev/null; then
      fail "$test_name: weavefront compilation failed"
      continue
    fi
    chmod u+r "$wir_file" 2>/dev/null || true
  fi

  if ! "$WEAVEC1_BIN" "$wir_file" "$ll_file" 2>&1 | \
      grep -q "compilation succeeded"; then
    fail "$test_name: weavec1 compilation failed"
    continue
  fi

  if ! link_test_executable "$ll_file" "$object_file" "$bin_file" \
      2>/dev/null; then
    fail "$test_name: executable link failed"
    continue
  fi

  set +e
  "$bin_file"
  actual_exit=$?
  set -e

  expected_exit=$(get_expected_exit "$test_name")
  if [[ $actual_exit != $expected_exit ]]; then
    fail "$test_name: expected exit $expected_exit, got $actual_exit"
    continue
  fi

  log "  ✓ $test_name PASSED (exit code: $actual_exit)"
  PASS_COUNT=$((PASS_COUNT + 1))
done

log ""
log "=========================================="
log "Test Results: $PASS_COUNT passed, $FAIL_COUNT failed"
log "=========================================="

if [[ $FAIL_COUNT -gt 0 ]]; then
  exit 1
fi

log "All tests passed!"
