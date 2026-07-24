<!-- SPDX-License-Identifier: Apache-2.0 -->

# weavec-bootstrap architecture

`weavec-bootstrap` is the WIR-written frontend that lowers surface Weave to the
stable WIR contract consumed by `weavec1`.

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

Everything below WIR is a backend responsibility. The bootstrap frontend may
validate and rewrite surface forms, but it emits only WIR already admitted by
the backend contract.

## Layers

### Generic S-expression infrastructure

| Module | Role |
|---|---|
| `sexpr_tokens.wir` | Token kinds and token storage. |
| `sexpr_tree.wir` | First-child/next-sibling tree storage and accessors. |
| `sexpr_lexer.wir` | Whitespace, comments, identifiers, strings, and integers. |
| `sexpr_parser.wir` | Generic recursive-descent S-expression parser. |
| `sexpr_print.wir` | Deterministic WIR rendering. |

### Surface-language lowering

| Module | Role |
|---|---|
| `surface_validate.wir` | Validate admitted top-level forms. |
| `surface_struct.wir` | Lower struct declarations. |
| `surface_lower.wir` | Rewrite program packaging and entries into WIR. |
| `driver.wir` | Orchestrate read, parse, validate, lower, print, and write. |
| `main.wir` | Command-line entry point. |

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

Surface Weave adds packaging, entry points, structs, constants, and validation.
Function bodies remain close to explicit WIR operations, so lowering is a
deterministic tree rewrite rather than a high-level optimizing translation.

## Reusable parser library

The tokenizer, tree, lexer, and parser are also required when bootstrapping the
self-hosted `weavec` compiler. `build.sh` links:

```text
sexpr_tokens.ll
sexpr_tree.ll
sexpr_lexer.ll
sexpr_parser.ll
```

into one named artifact:

```text
build/libweave-sexpr.bc
```

The **sources are in the correct repository**: they implement the generic parser
used by this bootstrap frontend. The old consumption model was wrong because a
downstream repo reached into `build/` for four individual generated files. The
named library makes that binary boundary explicit and versionable.

## Build products

On Linux x86-64, `build.sh` downloads and verifies the selected `weavec1` SDK.
The build produces:

```text
build/weavec-bootstrap
build/weavec-bootstrap.bc
build/libweave-sexpr.bc
build/toolchain.env
```

The executable is linked with the runtime matching the selected glibc or musl
SDK. macOS currently uses the source fallback.

`test.sh` and `test_all.sh` source `build/toolchain.env`; they do not infer
compiler or runtime paths independently.

## Multifile bootstrap

`weavec-bootstrap-cat.sh` strips the outer wrappers and metadata from multiple
`(program ...)` files, emits one combined program, and invokes
`weavec-bootstrap`. The first build of `weavec` uses this deterministic source
ordering path.

## Invariants

- Surface lowering emits only admitted WIR.
- Output is byte-stable for the same input.
- Parser support is exported as one named library.
- Build and test paths use canonical component names.
- New surface forms require end-to-end fixtures.

## Non-goals

- Extending WIR from the frontend.
- Backend LLVM optimization.
- Type inference, macros, or package resolution in the bootstrap stage.
- Preserving comments through lowering.
