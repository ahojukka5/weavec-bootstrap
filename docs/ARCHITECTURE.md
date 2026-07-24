<!-- SPDX-License-Identifier: Apache-2.0 -->

# weavec-bootstrap architecture

This document describes the bootstrap frontend formerly published as
`weavefront`. The top-level [README](../README.md) covers installation and
normal use.

## Role in the compiler chain

```text
.weave source
      ↓
weavec-bootstrap
      ↓
     WIR
      ↓
   weavec1
      ↓
   LLVM IR
```

`weavec-bootstrap` owns the surface-Weave-to-WIR boundary used to build the
first generation of [`weavec`](https://github.com/ahojukka5/weavec). It is
written in WIR and built with the published `weavec1` SDK on Linux x86-64.

Everything below WIR is a backend responsibility. The bootstrap frontend may
validate and rewrite surface forms, but it must emit only WIR already admitted
by the backend contract.

## Why this repository remains separate

`weavec` contains its own surface frontend and is the final user-facing
compiler. This repository exists so that a clean machine can build that
compiler before a trusted `weavec` binary exists.

```text
weavec0 → weavec1 → weavec-bootstrap → weavec
```

Once `weavec` can be reproduced directly from a published `weavec` binary, this
repository should mostly freeze as part of the fallback bootstrap chain.

## Design philosophy

### Generic S-expression layer

Surface Weave and WIR are S-expression languages. The `sexpr_*.wir` modules
implement a generic lexer, parser, tree, and printer with no surface-language
knowledge.

The `surface_*.wir` modules perform semantic validation and lowering on the
generic tree. This isolates surface changes from syntax-tree mechanics.

### Surface stays close to WIR

Surface Weave adds program packaging, entry points, structs, constants, and
validation. Function bodies retain explicit WIR-style operations. Lowering is
therefore primarily a deterministic tree rewrite.

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

`driver.wir` orchestrates the phases. `main.wir` provides the historical
compatibility command:

```text
weavefront <input.weave> <output.wir>
```

New documentation refers to the component as `weavec-bootstrap`; the executable
name remains `weavefront` until downstream bootstrap scripts have migrated.

## Module map

### Generic S-expression infrastructure

| Module | Role |
|---|---|
| `sexpr_tokens.wir` | Token kinds and token storage helpers. |
| `sexpr_tree.wir` | First-child/next-sibling tree storage and accessors. |
| `sexpr_lexer.wir` | Whitespace, comment, identifier, string, and integer lexing. |
| `sexpr_parser.wir` | Generic recursive-descent S-expression parsing. |
| `sexpr_print.wir` | Deterministic WIR rendering with a growable buffer. |
| `string_utils.wir` | Optional extern wrappers; currently not linked. |

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
explicit WIR form understood by `weavec1`.

## Unified source buffer

Lowering creates synthetic nodes such as `core-module`, `core-version`, and
`decls`. Those tokens do not exist in the original input, but the generic
printer expects every node to reference source text.

The lowering pass creates one buffer:

```text
synthetic keyword text + original source text
```

Synthetic nodes point into the keyword prefix. Copied nodes retain their text
after their offsets are shifted. One printer can then render original and
generated nodes deterministically.

## Build and dependency model

On Linux x86-64, `build.sh` downloads the selected `weavec1` SDK and verifies
the archive against release `SHA256SUMS`.

```text
bin/weavec1
lib/libweave-runtime.a
include/runtime.h
```

The build:

1. compiles linked `src/*.wir` modules to LLVM IR with `weavec1`;
2. combines them into `build/weavefront.bc` with `llvm-link`;
3. links the historical compatibility executable `build/weavefront`;
4. writes compiler, runtime, and libc paths to `build/toolchain.env`.

`test.sh` and `test_all.sh` source `build/toolchain.env`. Linux builds do not
clone or rebuild `weavec0` or `weavec1`; macOS uses the source fallback.

## Testing

The 58 surface fixtures each pass through:

1. surface Weave → WIR;
2. comparison with the WIR golden;
3. WIR → LLVM IR with `weavec1`;
4. native linking with the resolved runtime;
5. execution and exit-code verification.

CI runs on Linux glibc, Linux musl, and the macOS source fallback.

## Multifile bootstrap path

The historical `weavefront-cat.sh` script combines multiple `(program ...)`
files into one surface compilation. `weavec` uses this path to lower its own
source tree during the initial bootstrap.

## Technical constraints

WIR remains deliberately explicit. The bootstrap frontend therefore has:

- no type inference;
- no macro system;
- no in-language module resolver;
- no optimisation pass;
- no varargs-based formatting;
- compact byte-stable output rather than source formatting.

## Non-goals

- Extending the WIR contract from the frontend.
- Duplicating general language development from `weavec`.
- Backend LLVM optimisation.
- A general standard library.
- A package system in the bootstrap frontend.
- Preserving source comments through lowering.

Changes to the public lowering contract must remain deterministic and be
covered by an end-to-end surface fixture.
