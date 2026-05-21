# WeaveFront Architecture

## Overview

**weavefront** is a frontend compiler that transforms Surface Weave (`.weave` files) into WIR (Weave Intermediate Representation, `.wir` files). It implements a clean separation of concerns using a generic S-expression infrastructure.

## Design Philosophy

### Key Insight
Both Surface Weave and WIR are S-expression languages. Rather than building WIR-specific parsing logic, weavefront is built around a **generic S-expression layer** that handles the syntax, with separate phases for semantic validation and transformation.

### Responsibility Split
- **weavefront**: `.weave` → `.wir` (frontend/lowering only)
- **weavec1**: `.wir` → `.ll` (stable backend, unchanged)
- **clang**: `.ll` → executable (LLVM toolchain)

## Architecture

```
Surface Weave (.weave)
  ↓
[1] Generic S-expression Lexer (sexpr_lexer.wir)
  ↓
Token Stream
  ↓
[2] Generic S-expression Parser (sexpr_parser.wir)
  ↓
Generic S-expression Tree (sexpr_tree.wir)
  ↓
[3] Surface Validation (surface_validate.wir)
  ↓
[4] Surface → WIR Lowering (surface_lower.wir)
  ↓
WIR S-expression Tree
  ↓
[5] S-expression Pretty-Printer (sexpr_print.wir)
  ↓
WIR Text (.wir)
```

## Module Structure

### Core Infrastructure

#### `sexpr_tokens.wir`
Defines token kind constants as zero-argument functions returning i32:
- `token_eof()` - end of file
- `token_lparen()` - left parenthesis `(`
- `token_rparen()` - right parenthesis `)`
- `token_ident()` - identifier
- `token_string()` - string literal
- `token_int()` - integer literal

#### `sexpr_tree.wir`
Generic S-expression tree structure with 48-byte node layout:
- **Node kinds**: LIST, IDENT, STRING, INT
- **Node fields**: kind, text_start, text_len, first_child, next_sibling, value
- **Tree container**: nodes array, count, capacity
- **Operations**: tree_new, tree_append_node, accessors

Uses first-child/next-sibling representation for memory efficiency.

#### `sexpr_lexer.wir`
Character-by-character lexer producing token streams:
- Skip whitespace and comments (`;` to newline)
- Lex identifiers (alphanumeric + underscore/dash)
- Lex strings with escape sequences (`\"`, `\\`, `\n`)
- Lex integers (including negative)
- **Integer parsing**: Implements parse_integer() using subtraction-based arithmetic (WIR lacks division/modulo operators)
- Parallel arrays: kinds, starts, lengths, values

#### `sexpr_parser.wir`
Recursive descent parser for S-expressions:
- Rules: `sexpr := atom | list`, `atom := IDENT | STRING | INT`, `list := LPAREN sexpr* RPAREN`
- Builds tree using tree_append_node
- Links children via first_child/next_sibling
- **Pointer-based state**: Uses malloc/free for token index tracking (WIR lacks bitwise operators)

#### `sexpr_print.wir`
Pretty-printer for S-expression trees:
- Growable buffer (4096-byte initial capacity)
- Recursive tree traversal
- **Integer printing**: Custom print_i64() using subtraction-based conversion
- Special handling: Reads ident/string from source, formats int from value field

### Surface Language Layer

#### `surface_validate.wir`
Validates Surface Weave structure:
- Root must be `(program ...)`
- Must contain exactly one `(entry ...)` or `(fn ...)`
- Entry must have a name (identifier)
- Returns i32: 0 for success, non-zero for failure

#### `surface_lower.wir`
Transforms Surface tree to WIR tree:

**Transformation rules**:
```
(program
  (name "foo")
  (version "0.1")
  (entry main ...body))

→ lowers to →

(core-module
  (core-version 1)
  (decls
    (fn main ...body)))
```

**Implementation approach**:
1. Build unified source buffer: WIR keywords + original source
2. Create synthetic WIR nodes with offsets into keyword section
3. Copy original nodes with text_start adjusted by keyword section length
4. Transform `(entry ...)` to `(fn ...)`, copy body recursively

**Unified source layout**:
```
Offset 0:  "core-module"     (11 bytes)
Offset 11: "core-version"    (12 bytes)
Offset 23: "fn"              (2 bytes)
Offset 25: "decls"           (5 bytes)
Offset 30: [original source content]
```

### Pipeline Orchestration

#### `driver.wir`
Compilation pipeline coordinator:
1. Read source file
2. Lex to tokens
3. Parse to tree
4. Validate Surface structure
5. Lower to WIR tree (with unified source)
6. Open output file
7. Print WIR tree to file
8. Cleanup and return status

#### `main.wir`
CLI argument parser:
- Usage: `weavefront input.weave output.wir`
- Validates argument count
- Calls driver with file paths
- Returns exit code

## Build System

### `build.sh`
Builds weavefront using weavec1:
1. Create declaration files (common_decls.txt, driver_decls.txt, etc.)
2. Compile each .wir module to .ll using weavec1
3. Inject external declarations into .ll files (using awk)
4. Link .ll modules with llvm-link
5. Compile to executable with clang + runtime.c

**Declaration injection**: Uses awk to insert LLVM declarations after the `;core-version:` comment, enabling cross-module references without modifying weavec1.

### `test.sh`
End-to-end test suite:
1. Compile Surface Weave to WIR using weavefront
2. Compare WIR output against expected output
3. Compile WIR to LLVM IR using weavec1
4. Validate LLVM IR with llvm-as
5. Compile to executable with clang
6. Run executable and verify exit code

## Technical Constraints & Solutions

### WIR Operator Limitations

**Problem**: WIR lacks certain operators found in higher-level IRs.

**Solutions**:
- **No division/modulo**: Use subtraction-based algorithms
  - Integer parsing: Build value digit-by-digit using `value = value * 10 + digit`
  - Integer printing: Extract digits by repeated subtraction of 10
- **No bitwise operators**: Use pointer-based state passing with malloc/free
- **No type conversion operators** (i32↔i64): Use repeated addition/subtraction loops
- **No varargs support**: Avoid snprintf/printf, implement custom formatters

### Integer Handling

**Parsing** (`parse_integer` in sexpr_lexer.wir):
```wir
result = 0
for each digit_char in source:
  digit = digit_char - '0'  ; Get numeric value
  ; Convert i32 digit to i64 using loop
  digit_i64 = 0
  repeat digit times: digit_i64 = digit_i64 + 1
  result = result * 10 + digit_i64
```

**Printing** (`print_i64` in sexpr_print.wir):
```wir
; Extract digits right-to-left using repeated subtraction
while value > 0:
  quotient = 0
  temp = value
  while temp >= 10:
    temp = temp - 10
    quotient = quotient + 1
  digit = temp  ; Last digit (0-9)
  store digit
  value = quotient
```

### Source Text Management

**Challenge**: Synthetic WIR nodes need text for pretty-printing, but don't exist in original source.

**Solution**: Build unified source buffer:
1. Allocate buffer = keyword_section_size + original_source_size
2. Write WIR keywords ("core-module", "fn", etc.) to start of buffer
3. Copy original source after keywords
4. Synthetic nodes: text_start points into keyword section
5. Copied nodes: text_start adjusted by adding keyword section length
6. Pretty-printer reads from unified source for all nodes

### LLVM Declaration Management

**Challenge**: weavec1 doesn't generate `declare` statements for extern functions, causing llvm-link errors.

**Solution**: Post-process generated .ll files:
1. Create declaration .txt files during build
2. Use awk to inject declarations after `;core-version:` comment
3. Different declaration sets per module (common, driver-specific, etc.)

## Surface Weave Language

### Syntax

Surface Weave is a thin wrapper around WIR that adds module metadata:

```weave
(program
  (name "program-name")     ; Optional
  (version "0.1.0")         ; Optional
  (entry function-name      ; Entry point
    (params ...)
    (returns type)
    body))
```

### Transformation

The `(entry ...)` form is transformed to `(fn ...)` and wrapped in WIR structure:
- `(program ...)` → `(core-module ...)`
- `(entry ...)` → `(fn ...)`
- Metadata (name, version) is discarded
- Body forms pass through unchanged (already WIR-like)

### Philosophy

Surface Weave is **not** a high-level language. It's a convenient syntax for writing WIR with module packaging. The body of an entry point uses the same low-level WIR operations as direct WIR code.

## Performance Characteristics

### Time Complexity
- Lexing: O(n) where n = source length
- Parsing: O(n) where n = token count
- Lowering: O(m) where m = node count (tree copy + transform)
- Printing: O(m) where m = node count

### Space Complexity
- Token stream: O(n) for n tokens
- Tree: O(m) for m nodes (48 bytes/node)
- Unified source: O(k + s) where k = keyword length (30 bytes), s = original source length

### Scalability
Integer parsing/printing using subtraction is O(d) where d = digit count. For typical integers (< 10 digits), overhead is negligible. For very large integers, this becomes a bottleneck.

## Future Enhancements

### Potential Improvements
1. **Pretty-printing**: Add proper indentation and newlines (currently single-line output)
2. **Integer operations**: If WIR gains div/mod operators, replace subtraction-based algorithms
3. **Error reporting**: Add line/column tracking, user-friendly error messages
4. **Optimization**: Cache unified source between compilations
5. **Multiple entries**: Support multiple `(entry ...)` forms, generate multiple WIR `(fn ...)`

### Non-Goals
- **Type system**: WIR already has types, no inference needed
- **Macros**: Keep Surface Weave minimal
- **Standard library**: That's for the WIR/runtime layer
- **Module system**: Inter-file dependencies handled by linker

## Testing

### Test Strategy
End-to-end integration tests:
1. Write Surface Weave program (`.weave`)
2. Define expected WIR output (`.expected.wir`)
3. Compile and compare outputs
4. Compile to executable and verify behavior

### Current Tests
- `01_return_42.weave`: Basic integer return value
  - Tests: lexing, parsing, lowering, integer handling, full pipeline
  - Verifies: exit code 42

## Summary

weavefront successfully demonstrates:
- Clean separation of syntax (generic S-expressions) from semantics (Surface validation/lowering)
- Practical workarounds for IR operator limitations
- Tree-based transformation (not text manipulation)
- Stable integration with existing weavec1 backend

The architecture is extensible: new Surface forms can be added without modifying the S-expression infrastructure, and the generic layers can be reused for other S-expression languages.
