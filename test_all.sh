#!/usr/bin/env bash
set -euo pipefail

WEAVEFRONT="./build/weavefront"
WEAVEC1="../weavec1/build/weavec1"
RUNTIME="../weavec0/runtime.c"
BUILD_DIR="build"
TEST_DIR="tests/weavec1_ports"

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

# Function to get expected exit code for a test
get_expected_exit() {
  case "$1" in
    01_return_constant) echo 0 ;;
    02_return_42) echo 42 ;;
    03_add) echo 42 ;;
    04_one_arg_function) echo 43 ;;
    05_let_local) echo 42 ;;
    06_set_local) echo 42 ;;
    07_if) echo 42 ;;
    08_while) echo 42 ;;
    09_two_arg_function) echo 42 ;;
    10_string_literal) echo 42 ;;
    11_const_i64) echo 42 ;;
    12_i64_arithmetic) echo 42 ;;
    13_i64_comparisons) echo 42 ;;
    14_bool_ops) echo 42 ;;
    15_ptr_null) echo 42 ;;
    16_extern_malloc_free) echo 42 ;;
    17_ptr_add_store_load_i64) echo 42 ;;
    18_store_load_i8) echo 42 ;;
    19_call_void) echo 0 ;;
    20_call_i64) echo 42 ;;
    21_call_ptr) echo 42 ;;
    22_return_void) echo 0 ;;
    23_mod_i32) echo 42 ;;
    24_buffer_like_smoke) echo 42 ;;
    25_ptr_params_call_i32) echo 42 ;;
    26_bool_return) echo 1 ;;
    27_three_arg_function) echo 42 ;;
    28_i32_memory_and_cast) echo 42 ;;
    29_const_string_ptr) echo 42 ;;
    30_i64_sub_eq) echo 42 ;;
    31_not_bool) echo 42 ;;
    32_codegen_join_and_i64_arg) echo 42 ;;
    33_store_i8_temp) echo 42 ;;
    34_ge_i32) echo 42 ;;
    35_sub_i32) echo 42 ;;
    36_mul_i32) echo 42 ;;
    37_div_i32) echo 42 ;;
    38_i32_comparisons_full) echo 42 ;;
    39_i64_ge_gt) echo 42 ;;
    40_call_bool_direct) echo 42 ;;
    41_load_store_ptr) echo 42 ;;
    42_empty_do) echo 0 ;;
    43_if_fallthrough_join) echo 42 ;;
    44_while_zero_iterations) echo 42 ;;
    45_nested_while) echo 42 ;;
    46_forward_function_call) echo 43 ;;
    47_multiple_externs_used_subset) echo 42 ;;
    48_string_escape) echo 42 ;;
    49_negative_i32_literal) echo 42 ;;
    54_debug_marker) echo 42 ;;
    55_integration_nested_control_flow) echo 42 ;;
    56_integration_multi_function_chain) echo 43 ;;
    57_integration_memory_flow) echo 42 ;;
    59_new_operators) echo 40 ;;
    *) echo 42 ;;  # Default to 42
  esac
}

# Test each .weave file
for weave_file in "$TEST_DIR"/*.weave; do
  test_name=$(basename "$weave_file" .weave)
  wir_file="$BUILD_DIR/test_wir/${test_name}.wir"
  ll_file="$BUILD_DIR/test_ll/${test_name}.ll"
  bin_file="$BUILD_DIR/test_bin/${test_name}"

  log "Testing: $test_name"

  # Step 1: Compile .weave to .wir
  if ! $WEAVEFRONT "$weave_file" "$wir_file" 2>/dev/null; then
    fail "$test_name: weavefront compilation failed"
    continue
  fi

  # Step 2: Compile .wir to .ll
  if ! $WEAVEC1 "$wir_file" "$ll_file" 2>&1 | grep -q "compilation succeeded"; then
    fail "$test_name: weavec1 compilation failed"
    continue
  fi

  # Step 3: Validate LLVM
  if ! llvm-as "$ll_file" -o "$BUILD_DIR/test_bin/${test_name}.bc" 2>/dev/null; then
    fail "$test_name: LLVM validation failed"
    continue
  fi

  # Step 4: Compile to executable
  if ! clang "$ll_file" "$RUNTIME" -o "$bin_file" 2>/dev/null; then
    fail "$test_name: clang compilation failed"
    continue
  fi

  # Step 5: Run and check exit code
  set +e
  "$bin_file"
  actual_exit=$?
  set -e

  expected_exit=$(get_expected_exit "$test_name")
  if [[ $actual_exit != $expected_exit ]]; then
    fail "$test_name: Expected exit code $expected_exit, got $actual_exit"
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
