#!/usr/bin/env bash
set -euo pipefail

# WeaveFront build script
# Builds the surface language compiler using the stable WIR core (weavec1)

BUILD_DIR="build"
WEAVEC1="../weavec1/build/weavec1"
WEAVEFRONT="$BUILD_DIR/weavefront"
TEST_DIR="tests"

log() {
  printf '[weavefront] %s\n' "$*"
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

# Check that weavec1 exists
[[ -x "$WEAVEC1" ]] || fail "weavec1 not found at $WEAVEC1 - run 'cd ../weavec1 && ./build.sh' first"

log "building weavefront compiler"
mkdir -p "$BUILD_DIR"

# Compile the weavefront compiler (written in WIR) using weavec1
log "compile src/main.wir"
"$WEAVEC1" src/main.wir "$BUILD_DIR/main.ll"

# Create wrapper C file that calls weave_main
cat > "$BUILD_DIR/wrapper.c" <<'EOF'
extern int weave_main(int argc, char** argv);

int main(int argc, char** argv) {
    return weave_main(argc, argv);
}
EOF

# Link into executable
log "link weavefront"
clang "$BUILD_DIR/wrapper.c" "$BUILD_DIR/main.ll" -o "$WEAVEFRONT"

log "weavefront compiler built successfully"

# Run tests
log "running tests"

# Test 01: Compile 01_return_42.weave to WIR
log "test 01_return_42: compile .weave to .wir"
"$WEAVEFRONT" > "$BUILD_DIR/01_return_42.wir"

# Compile the generated WIR to LLVM IR
log "test 01_return_42: compile .wir to .ll"
"$WEAVEC1" "$BUILD_DIR/01_return_42.wir" "$BUILD_DIR/01_return_42.ll"

# Compile to executable
log "test 01_return_42: compile .ll to executable"
clang "$BUILD_DIR/01_return_42.ll" -o "$BUILD_DIR/01_return_42.out"

# Run and check exit code
log "test 01_return_42: run and check exit code"
set +e
"$BUILD_DIR/01_return_42.out"
exit_code=$?
set -e

if [[ "$exit_code" != "42" ]]; then
  fail "test 01_return_42 failed: expected exit code 42, got $exit_code"
fi

log "test 01_return_42: PASSED"

log "all tests passed!"
log "build complete"
