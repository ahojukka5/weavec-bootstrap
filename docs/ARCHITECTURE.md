<!-- SPDX-License-Identifier: Apache-2.0 -->

# weavec-bootstrap architecture

`weavec-bootstrap` is the frozen WIR-written frontend that lowers surface Weave
to the WIR v2 contract consumed by `weavec1`.

```text
surface .weave
      ↓
weavec-bootstrap
      ↓
    WIR v2
      ↓
   weavec1
      ↓
   LLVM IR
```

Everything below WIR is a backend responsibility. The frontend may validate and
rewrite surface forms, but it does not extend WIR or implement LLVM behavior.

## Module graph

The authoritative production order is the `MODULES` array in `build.sh`:

| Module | Responsibility |
|---|---|
| `sexpr_tokens.wir` | Token kinds and token storage. |
| `sexpr_tree.wir` | First-child/next-sibling tree storage and accessors. |
| `sexpr_lexer.wir` | Whitespace, comments, identifiers, strings, and integers. |
| `sexpr_parser.wir` | Generic recursive-descent S-expression parser. |
| `sexpr_print.wir` | Deterministic WIR rendering. |
| `surface_validate.wir` | Validate admitted top-level surface forms. |
| `surface_lower.wir` | Rewrite program packaging, entries, externs, functions, and constants into WIR v2. |
| `surface_struct.wir` | Generate explicit WIR functions for struct accessors. |
| `driver.wir` | Read, parse, validate, lower, print, and write one source file. |
| `main.wir` | Command-line entry point. |

No other `src/*.wir` file is permitted. The static audit rejects both missing
listed modules and unlisted source files.

## Lowering pipeline

```text
source bytes
    ↓
sexpr_lexer
    ↓
sexpr_parser
    ↓
surface_validate
    ↓
surface_struct + surface_lower
    ↓
sexpr_print
    ↓
WIR v2 bytes
```

The lowering pass constructs a new tree backed by a deterministic synthetic
keyword prefix plus original source bytes. It emits `(core-version 2)` and
preserves explicit WIR-like function bodies rather than introducing hidden
control flow or inferred types.

## Executable and parser-library roots

The repository has two intentional reachability root sets:

1. `main`, which owns the standalone `weavec-bootstrap` executable;
2. the symbols in `PARSER_SDK_EXPORTS`, which form the public downstream parser
   library used by `weavec`.

Every source function must be reachable from at least one of those roots. The
audit rejects unresolved direct calls, unreachable functions, and unused extern
declarations. Its JSON report is written to:

```text
build/audit/weavec-bootstrap.json
```

## Reusable parser SDK

`build.sh` links the generated forms of:

```text
sexpr_tokens.ll
sexpr_tree.ll
sexpr_lexer.ll
sexpr_parser.ll
```

into:

```text
build/libweave-sexpr.bc
```

The library is one named, versioned boundary. Downstream code must not reach
into this repository for individual generated `.ll` files. The exact exported
symbol inventory is maintained in `PARSER_SDK_EXPORTS` and verified against the
source definitions.

## Host portability boundary

The WIR code calls only fixed-signature externs. Native C APIs that are variadic
must be hidden behind local wrappers in `runtime/portable.c`.

The current wrapper owns output-file creation:

```text
weave_rt_open_write_trunc(path, mode)
```

This is necessary because the variadic `open` ABI differs on arm64 macOS. The
wrapper is compiled with the selected host/libc toolchain and linked into the
bootstrap executable. It is deliberately local to this repository; the frozen
Stage 0 runtime ABI is not expanded for a frontend-only portability detail.

## Build products

```text
build/weavec-bootstrap
build/weavec-bootstrap.bc
build/libweave-sexpr.bc
build/toolchain.env
```

Linux x86-64 uses the selected checksum-verified `weavec1` SDK and matching
static runtime. macOS builds pinned `weavec0` and `weavec1` source fallbacks.
The executable owns its 16 MiB main-thread stack requirement.

## Multifile bootstrap

`weavec-bootstrap-cat.sh` removes outer `(program ...)` wrappers, concatenates
module declarations in caller-supplied order, and invokes the frontend once.
The first `weavec` build uses this deterministic path.

## Verification model

The repository enforces four layers:

### Static boundary audit

- exact production source inventory;
- exactly one WIR v2 declaration per production module;
- exact test source/golden/manifest inventory;
- resolved direct calls;
- full function reachability from executable and parser SDK roots;
- all extern declarations used;
- exact parser SDK export inventory.

### Frontend ladder

Each manifest case runs through:

```text
surface source → WIR v2 → byte-identical golden → LLVM → native executable
```

### Platform matrix

- Linux x86-64 glibc SDK;
- Linux x86-64 musl SDK;
- arm64 macOS source fallback.

### Downstream compatibility

CI checks out the current `weavec` repository and runs its complete correctness,
performance, quantum, and self-host ladders using the bootstrap frontend source
under review.

## Invariants

- The same source produces byte-identical WIR.
- Lowering emits only admitted WIR v2.
- Production and test inventories are explicit and complete.
- Parser support is exported through one named library and one symbol list.
- Host ABI details stay behind fixed-signature local wrappers.
- A change is not compatible unless the real downstream compiler still builds
  and self-hosts.

## Non-goals

- WIR evolution.
- LLVM lowering or optimization.
- General surface-language development.
- Type inference, macros, package resolution, or pattern matching.
- Source-comment preservation.
