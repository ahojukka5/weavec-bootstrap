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

## Executable reachability root

The repository has one intentional reachability root: `main`, which owns the
standalone `weavec-bootstrap` executable. Parser modules
(`sexpr_tokens`, `sexpr_tree`, `sexpr_lexer`, `sexpr_parser`) remain part of
that executable. They are not a second public product.

Every source function must be reachable from `main`. The audit rejects
unresolved direct calls, unreachable functions, unused extern declarations, and
a leftover `PARSER_SDK_EXPORTS` inventory. Its JSON report is written to:

```text
build/audit/weavec-bootstrap.json
```

`weavec` consumes this repository through the bootstrap command and the
multifile driver only. Final `weavec` obtains lex, parse, tree accessors, and
token/node helpers from `src/parser/*.weave`. It does not link lower-stage
parser bitcode.

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
build/toolchain.env
```

Every host uses the selected checksum-verified `weavec1` SDK and matching
runtime: Linux x86-64 links statically, and macOS arm64/x86-64 link natively
against nothing but `libSystem.B.dylib`. There is no source-chain fallback.
The executable owns its 16 MiB main-thread stack requirement.

## Multifile bootstrap

`weavec-bootstrap-cat.sh` removes outer `(program ...)` wrappers, concatenates
module declarations in caller-supplied order, and invokes the frontend once.
The first `weavec` build uses this deterministic path. The combiner keeps every
top-level declaration from every source unit, including the final declaration
before end-of-file.

## Verification model

The repository enforces four layers:

### Static boundary audit

- exact production source inventory;
- exactly one WIR v2 declaration per production module;
- exact test source/golden/manifest inventory;
- resolved direct calls;
- full function reachability from `main`;
- all extern declarations used.

### Frontend ladder

Each manifest case runs through:

```text
surface source → WIR v2 → byte-identical golden → LLVM → native executable
```

### Platform matrix

- Linux x86-64 glibc SDK;
- Linux x86-64 musl SDK;
- native arm64 macOS SDK.

### Downstream compatibility

CI packages the Linux glibc SDK from this tree after the test job and
passes it to current `weavec` as `WEAVEC_BOOTSTRAP_SDK`. The downstream
checkout is `weavec`'s default branch: this seed must keep bootstrapping
the current compiler. A published bootstrap SDK pin would not test the
frontend under review. The job still checks that the first lowering
product is WIR v2.

## Invariants

- The same source produces byte-identical WIR.
- Lowering emits only admitted WIR v2.
- Production and test inventories are explicit and complete.
- Parser modules stay inside the bootstrap executable.
- Host ABI details stay behind fixed-signature local wrappers.
- A change is not compatible unless the real downstream compiler still builds
  and self-hosts.

## Non-goals

- WIR evolution.
- LLVM lowering or optimization.
- General surface-language development.
- Type inference, macros, package resolution, or pattern matching.
- Source-comment preservation.
