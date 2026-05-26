# weavefront — Weave Surface Language Frontend

[![ci](https://github.com/ahojukka5/weavefront/actions/workflows/ci.yml/badge.svg)](https://github.com/ahojukka5/weavefront/actions/workflows/ci.yml)

> The surface-language frontend for the Weave compiler chain.
> Converts `.weave` source files into stable WIR (`.wir`) for
> [`weavec1`](https://github.com/ahojukka5/weavec1) / `weavec2` to
> compile to LLVM IR. weavefront itself is written in WIR and
> compiled by `weavec1`.

## Overview

The Weave compiler chain is split into separate stages that each do
one thing:

```
.weave  ──[ weavefront ]──>  .wir  ──[ weavec1 / weavec2 ]──>  .ll  ──[ clang ]──>  exe
```

`weavefront` owns the **surface → WIR** edge. It is intentionally
thin: surface Weave is a small wrapper around WIR that adds module
packaging (`(program …)`, `(name …)`, `(version …)`), an entry-point
form (`(entry …)`), and a struct-declaration form
(`(struct Name (field …))`). Function bodies use the same low-level
WIR operations as direct `.wir` code.

The compiler is built on a generic S-expression layer (lexer, parser,
tree, pretty-printer) with the surface-language phases
(validate, lower, struct-lower) running on top. See
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the module map and
design philosophy.

---

## Prerequisites

`weavefront` builds with a standard LLVM toolchain plus `git`:

- `clang`, `llvm-as`, `llvm-link` — LLVM 14 or newer (opaque pointers).
- `git` — to fetch the pinned `weavec0` and `weavec1` dependencies on
  first build.
- `bash` 4 or newer.

Installation hints:

```sh
# Debian / Ubuntu
sudo apt-get install -y llvm clang git

# macOS (Homebrew)
brew install llvm git
export PATH="$(brew --prefix llvm)/bin:$PATH"
```

CI runs on `ubuntu-latest` and `macos-latest` against the
package-manager LLVMs.

---

## Quick start

```sh
git clone https://github.com/ahojukka5/weavefront.git
cd weavefront
./build.sh
./test_all.sh
```

**Note**: the first `./build.sh` is slower than subsequent runs — it
also clones and builds the pinned `weavec0` and `weavec1` tags into
`build/vendor/`. Re-runs reuse the cached vendor copies.

Compile a tiny `.weave` source by hand:

```sh
cat test/01_return_42.weave
./build/weavefront test/01_return_42.weave /tmp/out.wir
cat /tmp/out.wir
```

---

## Repository layout

```text
weavefront/
  build.sh                    # build driver (fetches weavec0 + weavec1, compiles)
  test.sh                     # single-test smoke (01_return_42)
  test_all.sh                 # full ladder
  weavefront-cat.sh           # concatenate multiple .weave files into one
  src/                        # WIR source modules (~3.5k lines, 10 modules)
    sexpr_*.wir               # generic S-expression infra
    surface_*.wir             # surface-language phases
    driver.wir / main.wir     # pipeline glue + CLI
    string_utils.wir          # extern wrappers (not yet linked in)
  test/                       # 58 .weave + 58 .expected.wir pairs
  docs/
    ARCHITECTURE.md           # design notes / module map
  build/                      # build outputs (gitignored)
    vendor/{weavec0,weavec1}  # auto-fetched dependencies
```

---

## Build

```sh
./build.sh                    # full build
```

Environment overrides:

- `WEAVEC0=/path/to/weavec0` — point at an existing weavec0 source
  tree (where `./build.sh` has already produced `weavec0` and
  `build/bootstrap-tests/bc/`). Skips the vendor fetch entirely.
- `WEAVEC1=/path/to/weavec1` — same idea for weavec1.
- `WEAVEC0_TAG=vX.Y.Z` — change the pinned weavec0 tag (default
  `v0.2.0`). Delete `build/vendor/weavec0/` to force a refetch.
- `WEAVEC1_TAG=vX.Y.Z` — same idea for weavec1 (default `v0.1.0`).

The script:

1. **Resolves weavec0** — via `WEAVEC0` env or git-clone of
   `https://github.com/ahojukka5/weavec0` at `WEAVEC0_TAG` into
   `build/vendor/weavec0/`. Builds it if not already built. We
   need it for `runtime.c` (malloc / free / puts / file I/O).
2. **Resolves weavec1** — via `WEAVEC1` env or git-clone of
   `https://github.com/ahojukka5/weavec1` at `WEAVEC1_TAG` into
   `build/vendor/weavec1/`. Invokes weavec1's own `build.sh`
   with `WEAVEC0=$WEAVEC0_DIR` so the weavec0 dependency is built
   once, not twice.
3. **Compiles weavefront** — every WIR module under `src/` is
   compiled by `weavec1` to LLVM IR.
4. **Links** the modules with `llvm-link` and `clang` against
   weavec0's `runtime.c`, producing `build/weavefront`.

---

## Test ladder

`test_all.sh` walks `test/*.weave` and runs each fixture through the
full pipeline:

1. `weavefront <name>.weave <name>.wir` — surface → WIR.
2. Diff the produced WIR against the checked-in `<name>.expected.wir`
   golden — byte-equal required.
3. `weavec1 <name>.wir <name>.ll` — WIR → LLVM IR.
4. `clang <name>.ll runtime.c -o <name>` — link.
5. Run `<name>`; assert the exit code matches the declared value.

58 cases ship in `test/`. A passing run ends with
`<N> passed, 0 failed`.

`test.sh` runs only `01_return_42` and is useful when iterating on
the front-end alone.

---

## Examples

Every file under [`test/`](test) is a runnable end-to-end example.
Suggested entry points if you are reading the code for the first
time:

- [`test/01_return_42.weave`](test/01_return_42.weave) — the
  smallest possible surface program.
- [`test/08_if.weave`](test/08_if.weave) — branching.
- [`test/09_while.weave`](test/09_while.weave) — loops and mutable
  locals.
- [`test/17_extern_malloc_free.weave`](test/17_extern_malloc_free.weave)
  — declaring and calling C externs.
- [`test/57_struct_basic.weave`](test/57_struct_basic.weave) —
  struct declarations and their lowered getter / setter accessors.
- [`test/52_integration_nested_control_flow.weave`](test/52_integration_nested_control_flow.weave)
  — multi-feature integration test.

---

## Where weavefront fits in the chain

The Weave compiler chain is split across separate repositories:

| Stage | Repo | Role |
|-------|------|------|
| `weavec0` | [`ahojukka5/weavec0`](https://github.com/ahojukka5/weavec0) | Hand-written LLVM-IR seed compiler. Compiles WIR → LLVM. Tiny, frozen. |
| `weavec1` | [`ahojukka5/weavec1`](https://github.com/ahojukka5/weavec1) | WIR-written compiler. Compiled by `weavec0`. Same WIR → LLVM contract, self-hosted. |
| `weavefront` | **this repo** | Surface (`.weave`) → WIR (`.wir`) frontend. Written in WIR, compiled by `weavec1`. |
| `weavec2` | TBD | Surface-Weave compiler that goes straight to WIR / LLVM. Will replace this frontend + weavec1 chain for surface inputs. |

Once `weavec2` is stable, this frontend will mostly freeze: surface
inputs will go directly through `weavec2`.

---

## Multifile compilation

`weavefront-cat.sh` concatenates several `.weave` files into a single
combined surface program before invoking `weavefront`. It is the
multifile workflow `weavec2`'s own build uses:

```sh
./weavefront-cat.sh combined.wir foo.weave bar.weave baz.weave
```

Each input must be a well-formed `(program …)`; the script strips the
outer wrappers and re-emits a single combined program.

---

## Known limitations

These are intentional scope choices, not bugs:

- **Surface stays close to WIR.** There is no type inference, no
  macros, no pattern matching, no module system. Function bodies
  use the same low-level WIR operations as direct `.wir` code.
- **Single-line output.** The pretty-printer emits compact,
  byte-stable WIR. Downstream compilers don't care; tooling that
  consumes `.wir` may want to add its own indentation.
- **Byte-offset diagnostics.** Errors refer to byte positions in the
  source, not line / column. Acceptable for the v0.x phase.
- **`src/string_utils.wir` is currently unused.** It declares
  `strlen` / `strncmp` / `memchr` extern wrappers but no module
  links against it. Intentionally not in `build.sh`'s `MODULES`
  list; revisit when a module needs it.
- **The vendored dependency caches** at `build/vendor/weavec0/`
  and `build/vendor/weavec1/` are not auto-updated when
  `WEAVEC0_TAG` / `WEAVEC1_TAG` change. Delete the directories
  and re-run `./build.sh` to refetch.

---

## License

Licensed under the Apache License, Version 2.0. See
[`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).

## Contributing

Pull requests and issues are welcome. The merge bar is intentionally
narrow — please read [`CONTRIBUTING.md`](CONTRIBUTING.md) and the
**Known limitations** section above before opening a PR.
