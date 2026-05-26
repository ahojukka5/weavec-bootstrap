<!-- SPDX-License-Identifier: Apache-2.0 -->

# weavefront architecture

This document describes how `weavefront` is put together. It is aimed
at contributors and curious readers — if you only want to use the
compiler, the [top-level README](../README.md) is enough.

## Role in the Weave chain

```
.weave file  ──[ weavefront ]──>  .wir file  ──[ weavec1 / weavec2 ]──>  .ll  ──[ clang ]──>  exe
   surface                          stable                                  LLVM IR
   syntax                          backend
                                 contract
```

`weavefront` is the **frontend** of the chain: it converts surface
Weave (`.weave`) into the stable WIR (`.wir`) the backends consume.
Everything below WIR is the responsibility of `weavec1` /
`weavec2`. weavefront itself is **written in WIR** and compiled by
`weavec1`, the same way `weavec1` is written in WIR and compiled by
`weavec0`.

## Design philosophy

### Generic S-expression layer, semantic phase on top

Both surface Weave and WIR are S-expression languages. Rather than
hand-rolling WIR-specific parsing logic, weavefront is built around
a **generic S-expression infrastructure** (`sexpr_*.wir`) that has
no knowledge of surface Weave or WIR. The surface-language phases
(`surface_*.wir`) run on top of that generic tree.

This separation lets the generic layer be reused for other
S-expression dialects and keeps surface-specific churn out of the
parser.

### Surface stays close to WIR

Surface Weave is **not** a high-level language. It is a thin
re-wrapping of WIR that adds module packaging, optional struct
declarations, and a few sugar forms. The body of a function uses
the same low-level WIR operations as direct WIR code. Implication:
the lowering pass is mostly a tree rewrite, not a translation.

## Pipeline

```
Surface Weave (.weave)
   │
   ▼
sexpr_lexer.wir        → token stream
   │
   ▼
sexpr_parser.wir       → generic S-expression tree
   │
   ▼
surface_validate.wir   → reject malformed surface programs
   │
   ▼
surface_struct.wir     → lower (struct ...) into getter/setter fns
surface_lower.wir      → lower (program …) into (core-module …),
                         (entry …) into (fn …)
   │
   ▼
sexpr_print.wir        → emit WIR text
   │
   ▼
WIR (.wir)
```

`driver.wir` wires these phases together; `main.wir` is the CLI
entry point.

## Module map

### Generic S-expression infrastructure

| Module | Role |
|---|---|
| `sexpr_tokens.wir` | Token kind constants (zero-arg fns returning i32: `token_eof`, `token_lparen`, `token_rparen`, `token_ident`, `token_string`, `token_int`). |
| `sexpr_tree.wir` | Tree node layout (48 bytes; first-child / next-sibling), `tree_new`, `tree_append_node`, accessors. |
| `sexpr_lexer.wir` | Character-by-character lexer. Skips whitespace and `;` comments, handles `"`-quoted strings with `\\`, `\"`, `\n` escapes, parses signed integers. |
| `sexpr_parser.wir` | Recursive descent: `sexpr := atom \| list`, `atom := IDENT \| STRING \| INT`, `list := LPAREN sexpr* RPAREN`. Links children via `first_child` / `next_sibling`. |
| `sexpr_print.wir` | Pretty-printer with a growable buffer. Reads ident/string text from the source buffer; formats integers from the node's `value` field. |
| `string_utils.wir` | Small `strlen` / `strncmp` / `memchr` helpers used by the lowering passes. |

### Surface-language layer

| Module | Role |
|---|---|
| `surface_validate.wir` | Validates the surface tree: root must be `(program …)`; one or more `(entry …)` / `(fn …)`; each entry must have a name. |
| `surface_struct.wir` | Lowers `(struct Name (field fname ftype) …)` into a set of getter/setter `(fn …)` nodes that the WIR backend can consume directly. |
| `surface_lower.wir` | Lowers `(program …)` into `(core-module (core-version 1) (decls …))`. Transforms `(entry …)` into `(fn …)`, copies all `(fn …)` and `(extern …)` and `(const …)` nodes into `decls`, drops `(name …)` and `(version …)` metadata. |

### Pipeline glue

| Module | Role |
|---|---|
| `driver.wir` | Orchestrates: read source → lex → parse → validate → lower → print → write output. |
| `main.wir` | CLI entry: `weavefront <input.weave> <output.wir>`. |

## Surface → WIR transformation

The core rewrite the lowering pass performs:

```
(program
  (name "demo")             ; dropped
  (version "0.1")           ; dropped
  (entry main
    (params)
    (returns i32)
    (do (return (const_i32 42)))))
```

becomes:

```
(core-module
  (core-version 1)
  (decls
    (fn main
      (params)
      (returns i32)
      (do (return (const_i32 42))))))
```

The body itself is left untouched — it is already valid WIR.

### Unified source buffer

The lowering pass introduces **synthetic** WIR nodes (`core-module`,
`core-version`, `fn`, `decls`, plus whatever struct lowering emits)
that do not exist in the original source. The pretty-printer reads
node text from a source buffer, so synthetic nodes need text to
exist somewhere.

Solution: at the start of lowering, allocate a **unified source
buffer** = keyword section + original source. Synthetic nodes point
into the keyword section; copied nodes have their `text_start`
shifted by the keyword section's length. The pretty-printer reads
from this unified buffer for every node.

## Technical constraints

WIR is a deliberately small instruction set. A few features that
mainstream IRs take for granted are absent and have to be worked
around:

| Missing | Workaround |
|---|---|
| Division / modulo | Subtraction-based loops. Integer parsing builds the value digit-by-digit; integer printing extracts digits by repeated subtraction of 10. |
| Bitwise operators | Pointer-indirection via `malloc` / `free` for state passing where bit tricks would have sufficed. |
| Type conversion (`i32 ↔ i64`) | Repeated increment loops for the few sites that need it. |
| Varargs | No `printf` / `snprintf`; all formatting is hand-rolled. |

These are not bottlenecks for typical inputs (lex, parse, lower a
few thousand lines), but they put a floor on per-iteration cost.

## Build and dependencies

`build.sh` compiles each `src/*.wir` module to LLVM IR with
`weavec1`, then links the modules together with `llvm-link` and
finally produces an executable with `clang`. The script vendors a
pinned `weavec0` (Stage 0 seed) and `weavec1` (Stage 1) into
`build/vendor/` on first run; both can be overridden via the
`WEAVEC0` / `WEAVEC1` environment variables.

The runtime — `malloc`, `free`, `puts`, file-I/O helpers — comes
from `weavec0`'s `runtime.c`, which the build script reuses out of
the vendor copy.

## Testing

The test ladder lives under `test/` and is driven by
`test_all.sh`. Each ladder entry is a pair `NN_name.weave` +
`NN_name.expected.wir`. The runner:

1. Runs `weavefront NN_name.weave NN_name.wir`.
2. Diffs the produced WIR against `NN_name.expected.wir`.
3. Compiles the WIR through `weavec1` to LLVM IR.
4. Validates the IR with `llvm-as`.
5. Compiles to an executable with `clang` and verifies the exit
   code matches the per-test expectation.

A passing run is a four-stage end-to-end check, not just a parser
diff. `test.sh` is a single-test smoke for `01_return_42` and is
useful when iterating on the front-end alone.

## Non-goals

- **Type system / inference** — WIR already has types; surface Weave
  passes them through.
- **Macros** — the language is intentionally minimal.
- **Standard library** — that belongs to the WIR / runtime layer.
- **Optimisation** — the backend (`weavec1` / `weavec2`) does its
  own work; weavefront should be byte-stable.
- **Module system / import resolution** — multifile builds are
  handled by `weavefront-cat.sh`, which concatenates surface
  sources before compilation. An in-language module system is out
  of scope for v0.x.
