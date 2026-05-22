#!/usr/bin/env bash
set -euo pipefail

WEAVEFRONT="./build/weavefront"
WEAVEC1="../weavec1/build/weavec1"
RUNTIME="../weavec0/runtime.c"
BUILD_DIR="build"

PASS_COUNT=0
FAIL_COUNT=0

log() {
  echo "[test-all] $*"
}

fail() {
  echo "[test-all] ERROR: $*" >&2
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

# Check weavefront exists
[[ -x "$WEAVEFRONT" ]] || { echo "weavefront not found at $WEAVEFRONT (run ./build.sh first)" >&2; exit 1; }

# Check weavec1 exists
[[ -x "$WEAVEC1" ]] || { echo "weavec1 not found at $WEAVEC1" >&2; exit 1; }

# Create build directory
mkdir -p "$BUILD_DIR/test_wir" "$BUILD_DIR/test_ll" "$BUILD_DIR/test_bin"

# Expected exit code for each test name
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

# WIR-comparison tests: compile .weave and diff against .expected.wir
for weave_file in tests/*.weave; do
  test_name=$(basename "$weave_file" .weave)
  expected_wir="tests/${test_name}.expected.wir"
  wir_file="$BUILD_DIR/test_wir/${test_name}.wir"

  log "Testing (wir): $test_name"

  rm -f "$wir_file"
  if ! $WEAVEFRONT "$weave_file" "$wir_file" 2>/dev/null; then
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

# End-to-end run tests: compile .wir through weavec1, link, and run
for weave_file in tests/*.weave; do
  test_name=$(basename "$weave_file" .weave)
  wir_file="$BUILD_DIR/test_wir/${test_name}.wir"
  ll_file="$BUILD_DIR/test_ll/${test_name}.ll"
  bin_file="$BUILD_DIR/test_bin/${test_name}"

  log "Testing (e2e): $test_name"

  # Step 1: Compile .weave to .wir (reuse from wir pass if present)
  if [[ ! -f "$wir_file" ]]; then
    rm -f "$wir_file"
    if ! $WEAVEFRONT "$weave_file" "$wir_file" 2>/dev/null; then
      fail "$test_name: weavefront compilation failed"
      continue
    fi
    chmod u+r "$wir_file" 2>/dev/null || true
  fi

  # Step 2: Compile .wir to .ll
  if ! $WEAVEC1 "$wir_file" "$ll_file" 2>&1 | grep -q "compilation succeeded"; then
    fail "$test_name: weavec1 compilation failed"
    continue
  fi

  # Step 3: Compile to executable
  if ! clang "$ll_file" "$RUNTIME" -o "$bin_file" 2>/dev/null; then
    fail "$test_name: clang compilation failed"
    continue
  fi

  # Step 4: Run and check exit code
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
