<!-- SPDX-License-Identifier: Apache-2.0 -->

# weavefront architecture

This document describes the internal structure of `weavefront`. The top-level
[README](../README.md) covers installation and normal use.

## Role in the compiler chain

```text
.weave source
      ↓
  weavefront
      ↓
    WIR
      ↓
weavec1 or weavec2
      ↓
   LLVM IR
```

`weavefront` owns the surface-Weave-to-WIR boundary. It is itself written in WIR
and built with the published `weavec1` SDK on Linux x86-64.

Everything below WIR is a backend responsibility. `weavefront` validates and
rewrites surface forms but must emit only WIR already admitted by the backend
contract.

## Design philosophy

### Generic S-expression layer

Surface Weave and WIR are both S-expression languages. The `sexpr_*.wir`
modules implement a generic lexer, parser, tree, and printer that do not know
the surface language.

The `surface_*.wir` modules run semantic validation and lowering on the generic
tree. This keeps parser infrastructure reusable and isolates surface-language
changes from syntax-tree mechanics.

### Surface stays close to WIR

Surface Weave adds packaging, entry points, structs, constants, and validation.
Function bodies retain explicit WIR-style operations. Lowering is therefore
mostly a deterministic tree rewrite rather than a high-level translation.

## Pipeline

```text
Surface Weave
    ↓
sexpr_lexer.wir
    ↓
sexpr_parser.wir
    ↓
surface_validate.wir
    ↓
surface_struct.wir
    ↓
surface_lower.wir
    ↓
sexpr_print.wir
    ↓
WIR
```

`driver.wir` orchestrates the phases. `main.wir` provides the command-line
entry point:

```text
weavefront <input.weave> <output.wir>
```

## Module map

### Generic S-expression infrastructure

| Module | Role |
|---|---|
| `sexpr_tokens.wir` | Token kinds and token storage helpers. |
| `sexpr_tree.wir` | First-child/next-sibling tree storage and accessors. |
| `sexpr_lexer.wir` | Whitespace, comment, identifier, string, and integer lexing. |
| `sexpr_parser.wir` | Generic recursive-descent S-expression parsing. |
| `sexpr_print.wir` | Deterministic WIR text rendering with a growable buffer. |
| `string_utils.wir` | Optional extern wrappers; currently not linked because no active module consumes them. |

### Surface-language layer

| Module | Role |
|---|---|
| `surface_validate.wir` | Validates the root program and admitted top-level forms. |
| `surface_struct.wir` | Lowers struct declarations into backend-compatible functions. |
| `surface_lower.wir` | Rewrites program packaging and entries into stable WIR declarations. |

### Pipeline glue

| Module | Role |
|---|---|
| `driver.wir` | Read, lex, parse, validate, lower, print, and write. |
| `main.wir` | CLI argument handling and process exit status. |

## Surface-to-WIR transformation

A small surface program:

```weave
(program
  (name "demo")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (return (const_i32 42)))))
```

becomes:

```wir
(core-module
  (core-version 1)
  (decls
    (fn main
      (params)
      (returns i32)
      (do
        (return (const_i32 42))))))
```

Program metadata is dropped, `entry` becomes `fn`, and the body remains in the
explicit WIR form already understood by the backend.

## Unified source buffer

Lowering creates synthetic nodes such as `core-module`, `core-version`, and
`decls`. Those tokens do not exist in the original input, but the generic
printer expects every node to reference source text.

The lowering pass therefore creates a unified source buffer:

```text
synthetic keyword text + original source text
```

Synthetic nodes point into the keyword prefix. Copied source nodes retain their
text after their offsets are shifted by the prefix length. The same printer can
then render both original and generated nodes deterministically.

## Build and dependency model

On Linux x86-64, `build.sh` downloads the selected `weavec1` SDK and verifies
the archive against release `SHA256SUMS`.

The SDK supplies:

```text
bin/weavec1
lib/libweave-runtime.a
include/runtime.h
```

The build then:

1. compiles each linked `src/*.wir` module to LLVM IR with `bin/weavec1`;
2. combines the modules into `build/weavefront.bc` with `llvm-link`;
3. links a static `build/weavefront` with the matching runtime library;
4. writes the resolved paths and libc selection to `build/toolchain.env`.

`test.sh` and `test_all.sh` source `build/toolchain.env`. They do not infer
compiler or runtime paths independently.

The published SDK path means Linux builds do not clone or rebuild `weavec0` or
`weavec1`. macOS currently uses the source fallback because no native Stage 1
SDK is published.

## Testing

The full ladder under `test/` contains 58 surface fixtures. For each fixture,
`test_all.sh`:

1. runs surface Weave through `weavefront`;
2. compares WIR output with the checked-in golden;
3. compiles the WIR through the resolved Stage 1 compiler;
4. links with the resolved runtime and libc toolchain;
5. executes the result and checks the expected exit code.

CI runs the ladder on:

- Linux x86-64 with the glibc Stage 1 SDK;
- Linux x86-64 with the musl Stage 1 SDK;
- macOS with the source fallback.

`test.sh` is the single-case `return 42` smoke test.

## Multifile bootstrap path

`weavefront-cat.sh` combines multiple `(program ...)` source files into one
surface compilation. It strips the outer wrappers, emits one combined program,
and invokes `weavefront`.

The separate `weavec2` repository uses this path to lower its own source tree
during bootstrap.

## Technical constraints

WIR remains deliberately explicit. `weavefront` therefore avoids assumptions
about high-level runtime or compiler services:

- no type inference;
- no macro system;
- no in-language module resolver;
- no optimisation pass;
- no varargs-based formatting;
- compact byte-stable output rather than source formatting.

## Non-goals

- Extending the WIR contract from the frontend.
- Backend LLVM optimisation.
- A general standard library.
- A package or import system in the v0.x frontend.
- Preserving source comments through lowering.

Changes to the public lowering contract must remain deterministic and must be
covered by an end-to-end surface fixture.
