# WeaveFront - Weave Surface Language Compiler

WeaveFront is the surface language compiler for Weave, compiling `.weave` files (surface syntax) to `.wir` files (WIR intermediate representation).

## Architecture

```
┌─────────────────┐
│  .weave file    │  ← Surface language (user-friendly syntax)
│  fn main() {...}│
└────────┬────────┘
         │ weavefront (written in WIR)
         ▼
┌─────────────────┐
│   .wir file     │  ← WIR (stable backend contract)
│  (core-module)  │
└────────┬────────┘
         │ weavec1/weavec2
         ▼
┌─────────────────┐
│   LLVM IR       │  ← Machine codegen target
└────────┬────────┘
         │ clang
         ▼
┌─────────────────┐
│  executable     │
└─────────────────┘
```

## Compiler Implementation

**Key Point**: The weavefront compiler is written in WIR itself, using the stable core we built.

- `src/main.wir` - Compiler implementation in WIR
- Compiled by weavec1 (or weavec2)
- Dogfooding our own stable backend!

## Current Status

**Phase 1: Proof of Concept** ✅

The compiler currently supports a minimal subset just to prove the concept:

### Supported Syntax

```rust
fn main() -> i32 {
  return 42;
}
```

### Compilation Pipeline

```bash
# .weave → .wir
./build/weavefront > output.wir

# .wir → .ll → executable
weavec1 output.wir output.ll
clang output.ll -o program
```

## Building

```bash
# Prerequisites: weavec1 must be built first
cd ../weavec1 && ./build.sh

# Build weavefront and run tests
cd ../weavefront
./build.sh
```

## Tests

- `tests/01_return_42.weave` - Basic function returning constant

The build script automatically:
1. Compiles weavefront from WIR to LLVM IR to executable
2. Runs weavefront to compile `.weave` to `.wir`
3. Compiles `.wir` to `.ll` using weavec1
4. Compiles `.ll` to executable using clang
5. Runs executable and verifies exit code

## Next Steps

The current implementation is intentionally minimal (hardcoded WIR output). Next phases:

### Phase 2: Real Lexer/Parser
- Implement proper tokenization
- Recursive descent parser for surface syntax
- AST construction

### Phase 3: Extended Surface Syntax
- Variables and assignments
- Arithmetic expressions
- If statements
- While loops
- Function calls

### Phase 4: Advanced Features
- Type inference
- Pattern matching
- Macros
- Module system

## Philosophy

Following the Weave project philosophy:

- **Auditability**: Explicit lowering from surface to WIR
- **Determinism**: Same .weave always produces same .wir
- **Stability**: WIR backend remains frozen, surface can evolve
- **Dogfooding**: Compiler written in WIR, compiled by weavec1

## Directory Structure

```
weavefront/
├── README.md           # This file
├── build.sh            # Build script
├── src/
│   └── main.wir        # Compiler implementation (WIR)
├── tests/
│   └── 01_return_42.weave  # Test cases
└── build/
    ├── weavefront      # Compiled compiler executable
    ├── *.wir           # Generated WIR files
    ├── *.ll            # Generated LLVM IR
    └── *.out           # Generated executables
```

## Design Decisions

### Why stdout for output?

The current implementation outputs WIR to stdout (using `puts`) rather than file I/O. This avoids complications with extern function declarations in weavec1 and keeps the initial implementation simple. Future versions will add proper file I/O.

### Why WIR implementation?

Writing the compiler in WIR itself:
- Validates the stable core is actually usable
- Dogfoods our own toolchain
- Demonstrates the bootstrap principle
- Ensures WIR has enough primitives for real programs

### Why minimal initial implementation?

The "hardcoded output" approach allows us to:
- Verify the full pipeline works end-to-end
- Establish test infrastructure
- Validate the architecture
- Iterate quickly on the design

Proper parsing will be added incrementally in Phase 2.
