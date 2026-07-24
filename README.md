# weavec-bootstrap — Surface Weave Bootstrap Frontend

[![ci](https://github.com/ahojukka5/weavec-bootstrap/actions/workflows/ci.yml/badge.svg)](https://github.com/ahojukka5/weavec-bootstrap/actions/workflows/ci.yml)

> A deterministic surface-Weave-to-WIR frontend used to bootstrap the
> self-hosted `weavec` compiler.

This repository was previously named `weavefront`. It is a bootstrap component,
not the final user-facing compiler.

## Role

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

`weavec-bootstrap` owns the **surface → WIR** boundary. It is written in WIR,
built with the published `weavec1` SDK, and supplies the first frontend capable
of building [`weavec`](https://github.com/ahojukka5/weavec) from surface-Weave
source.

The frontend contains generic S-expression token, tree, lexer, parser, and
printer modules with deterministic surface validation and lowering layered on
top. See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Compiler chain

| Component | Repository | Role |
|---|---|---|
| `weavec0` | [`ahojukka5/weavec0`](https://github.com/ahojukka5/weavec0) | Hand-written Stage 0 seed and SDK. |
| `weavec1` | [`ahojukka5/weavec1`](https://github.com/ahojukka5/weavec1) | WIR compiler and Stage 1 SDK. |
| `weavec-bootstrap` | **this repository** | Surface-to-WIR bootstrap frontend. |
| `weavec` | [`ahojukka5/weavec`](https://github.com/ahojukka5/weavec) | User-facing self-hosted compiler. |

```text
weavec0 → weavec1 → weavec-bootstrap → weavec
```

Normal language and compiler development belongs in `weavec`. This repository
should remain a small, stable, reproducible bootstrap frontend.

## Prerequisites

Linux x86-64 builds download the versioned `weavec1` SDK and do not rebuild
`weavec0` or `weavec1` from source.

Required tools:

- Bash 4 or newer;
- LLVM 14 or newer: `clang`, `llvm-as`, and `llvm-link`;
- `curl`, `tar`, and `sha256sum`;
- `musl-gcc` only for the musl variant.

Ubuntu:

```bash
sudo apt-get install -y llvm clang curl musl-tools
```

macOS currently uses the source fallback:

```bash
brew install llvm git
export PATH="$(brew --prefix llvm)/bin:$PATH"
```

## Quick start

```bash
git clone https://github.com/ahojukka5/weavec-bootstrap.git
cd weavec-bootstrap
./build.sh
./test_all.sh
```

The first Linux build downloads `weavec1 v0.2.0`, verifies the archive against
`SHA256SUMS`, and caches it under `build/vendor/weavec1-sdk/`.

Compile a surface program:

```bash
./build/weavec-bootstrap test/01_return_42.weave /tmp/out.wir
```

## Stage 1 dependency

```text
weavec1-v0.2.0-linux-x86_64-<libc>/
├── bin/weavec1
├── lib/libweave-runtime.a
├── include/runtime.h
└── SDK-MANIFEST
```

`build.sh` records the resolved compiler, runtime, and libc selection in
`build/toolchain.env`. Both test commands source that file.

Select the Linux variant with:

```bash
WEAVEC1_LIBC=glibc ./build.sh
WEAVEC1_LIBC=musl ./build.sh
```

Environment overrides:

- `WEAVEC1_SDK=/path/to/sdk` uses an extracted SDK;
- `WEAVEC1_VERSION=vX.Y.Z` selects a published release;
- `WEAVEC1_LIBC=glibc|musl` selects the archive and linker;
- `WEAVEC1_RELEASE_BASE=<url>` overrides the release base;
- `WEAVEC1=/path/to/source` selects a pre-built source tree;
- `WEAVEC1_TAG=vX.Y.Z` selects the source fallback;
- `WEAVEC0` and `WEAVEC0_TAG` control Stage 0 only for source fallback.

## Build outputs

`./build.sh` produces three named artifacts:

```text
build/weavec-bootstrap       surface Weave → WIR executable
build/weavec-bootstrap.bc    complete frontend LLVM bitcode
build/libweave-sexpr.bc      reusable tokenizer/tree/lexer/parser library
```

The parser library combines the generated forms of:

```text
src/sexpr_tokens.wir
src/sexpr_tree.wir
src/sexpr_lexer.wir
src/sexpr_parser.wir
```

These sources belong here because they implement the parser used by the
bootstrap frontend. Downstream stages consume the single named library instead
of reaching into this repository for four unrelated `.ll` build products.

## Build pipeline

`./build.sh`:

1. resolves the Stage 1 SDK or source fallback;
2. compiles the linked `src/*.wir` modules with `weavec1`;
3. creates `build/libweave-sexpr.bc` from the four reusable parser modules;
4. combines all frontend modules into `build/weavec-bootstrap.bc`;
5. links the `build/weavec-bootstrap` executable with the matching runtime;
6. writes `build/toolchain.env` for tests and downstream bootstrap use.

## Repository layout

```text
weavec-bootstrap/
├── build.sh
├── test.sh
├── test_all.sh
├── weavec-bootstrap-cat.sh   multifile bootstrap driver
├── src/                      WIR frontend and S-expression modules
├── test/                     58 surface fixtures and WIR goldens
├── docs/ARCHITECTURE.md
└── build/                    generated artifacts and toolchain metadata
```

## Tests

`./test_all.sh` runs every surface fixture through:

1. surface Weave → WIR with `weavec-bootstrap`;
2. byte-for-byte comparison with the WIR golden;
3. WIR → LLVM IR with the resolved `weavec1` compiler;
4. native linking with the resolved runtime;
5. execution and exit-code verification.

CI covers Linux x86-64 glibc, Linux x86-64 musl, and the macOS source fallback.
`./test.sh` runs the smallest `return 42` smoke case.

## Multifile bootstrap path

`weavec-bootstrap-cat.sh` combines multiple `(program ...)` files and invokes
the frontend once:

```bash
./weavec-bootstrap-cat.sh combined.wir foo.weave bar.weave baz.weave
```

`weavec` uses this path to lower its own source tree during the first bootstrap
generation.

## Known limitations

- Surface Weave intentionally stays close to WIR.
- Output is compact and byte-stable rather than source-formatted.
- Diagnostics use byte offsets rather than full source ranges.
- Published dependency SDKs currently cover Linux x86-64 only.

## License

Licensed under the Apache License, Version 2.0. See [`LICENSE`](LICENSE) and
[`NOTICE`](NOTICE).

## Contributing

Read [`CONTRIBUTING.md`](CONTRIBUTING.md) before changing the lowering contract,
SDK assumptions, or bootstrap outputs.
