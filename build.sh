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

# Common tree/node/token/io declarations for most modules
cat > "$BUILD_DIR/common_decls.txt" <<'EOF'
declare ptr @tree_new()
declare i64 @tree_append_node(ptr, i32, i64, i64, i64, i64, i64)
declare i64 @tree_count(ptr)
declare i32 @node_kind(ptr, i64)
declare i64 @node_text_start(ptr, i64)
declare i64 @node_text_len(ptr, i64)
declare i64 @node_first_child(ptr, i64)
declare i64 @node_next_sibling(ptr, i64)
declare i64 @node_value(ptr, i64)
declare void @node_set_first_child(ptr, i64, i64)
declare void @node_set_next_sibling(ptr, i64, i64)
declare i32 @node_list()
declare i32 @node_ident()
declare i32 @node_string()
declare i32 @node_int()
declare i32 @token_eof()
declare i32 @token_lparen()
declare i32 @token_rparen()
declare i32 @token_ident()
declare i32 @token_string()
declare i32 @token_int()
declare i64 @write(i32, ptr, i64)
declare i64 @read(i32, ptr, i64)
declare i32 @open(ptr, i32, i32)
declare i32 @close(i32)
EOF

# Pipeline function declarations for driver
cat > "$BUILD_DIR/driver_decls.txt" <<'EOF'
declare ptr @lex(ptr, i64)
declare ptr @parse(ptr)
declare i32 @validate(ptr, ptr)
declare ptr @lower(ptr, ptr)
declare i32 @print_tree(ptr, ptr, i32)
declare i64 @lseek(i32, i64, i32)
EOF

# Pipeline function declarations for main (includes compile_file from driver)
cat > "$BUILD_DIR/main_decls.txt" <<'EOF'
declare i32 @compile_file(ptr, ptr)
EOF

# Special declarations just for surface_lower (it uses node_text_equals from surface_validate)
cat > "$BUILD_DIR/surface_lower_decls.txt" <<'EOF'
declare i32 @node_text_equals(ptr, ptr, i64, ptr, i64)
EOF

# Special declarations for sexpr_print (uses libc functions)
cat > "$BUILD_DIR/sexpr_print_decls.txt" <<'EOF'
declare i32 @snprintf(ptr, i64, ptr, ...)
EOF

# Helper function to add declarations to LLVM file
add_declarations() {
  local llfile="$1"
  local extra_decls="${2:-}"
  local tmpfile="${llfile}.tmp"

  # Insert declarations after the header (after "core-version:" line)
  awk '
    /^; core-version:/ {
      print
      print ""
      print "; external declarations"
      system("cat '"$BUILD_DIR"'/common_decls.txt")
      if (length("'"$extra_decls"'") > 0) {
        system("cat '"$extra_decls"'")
      }
      next
    }
    { print }
  ' "$llfile" > "$tmpfile"

  mv "$tmpfile" "$llfile"
}

# Compile all WIR modules
log "Compiling weavefront modules..."
$WEAVEC1 src/sexpr_tokens.wir "$BUILD_DIR/sexpr_tokens.ll" || fail "Failed to compile sexpr_tokens.wir"
$WEAVEC1 src/sexpr_tree.wir "$BUILD_DIR/sexpr_tree.ll" || fail "Failed to compile sexpr_tree.wir"
$WEAVEC1 src/sexpr_lexer.wir "$BUILD_DIR/sexpr_lexer.ll" || fail "Failed to compile sexpr_lexer.wir"
$WEAVEC1 src/sexpr_parser.wir "$BUILD_DIR/sexpr_parser.ll" || fail "Failed to compile sexpr_parser.wir"
add_declarations "$BUILD_DIR/sexpr_parser.ll"
$WEAVEC1 src/sexpr_print.wir "$BUILD_DIR/sexpr_print.ll" || fail "Failed to compile sexpr_print.wir"
add_declarations "$BUILD_DIR/sexpr_print.ll" "$BUILD_DIR/sexpr_print_decls.txt"
$WEAVEC1 src/surface_validate.wir "$BUILD_DIR/surface_validate.ll" || fail "Failed to compile surface_validate.wir"
add_declarations "$BUILD_DIR/surface_validate.ll"
$WEAVEC1 src/surface_lower.wir "$BUILD_DIR/surface_lower.ll" || fail "Failed to compile surface_lower.wir"
add_declarations "$BUILD_DIR/surface_lower.ll" "$BUILD_DIR/surface_lower_decls.txt"
$WEAVEC1 src/driver.wir "$BUILD_DIR/driver.ll" || fail "Failed to compile driver.wir"
add_declarations "$BUILD_DIR/driver.ll" "$BUILD_DIR/driver_decls.txt"
$WEAVEC1 src/main.wir "$BUILD_DIR/main.ll" || fail "Failed to compile main.wir"
add_declarations "$BUILD_DIR/main.ll" "$BUILD_DIR/main_decls.txt"

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
