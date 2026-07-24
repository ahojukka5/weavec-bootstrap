# weavefront — Weave Surface Language Frontend

[![ci](https://github.com/ahojukka5/weavefront/actions/workflows/ci.yml/badge.svg)](https://github.com/ahojukka5/weavefront/actions/workflows/ci.yml)

> The surface-language frontend for the Weave compiler chain. It converts
> `.weave` source files into stable WIR (`.wir`) for `weavec1` or `weavec2`.

## Overview

The compiler chain is split into small, independently buildable stages:

```text
.weave ──[ weavefront ]──> .wir ──[ weavec1 / weavec2 ]──> .ll
       ──[ clang ]──> executable
```

`weavefront` owns the **surface → WIR** edge. It is written in WIR and built
with the published `weavec1` SDK. Surface Weave adds program packaging,
entry-point declarations, structs, constants, and validation around the stable
low-level WIR operations used in function bodies.

The frontend is built on a generic S-expression lexer, parser, tree, and
printer. Surface validation and lowering run on top of that layer. See
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the module map.

## Prerequisites

Linux x86-64 builds download a versioned `weavec1` SDK. They do not clone or
build `weavec0` or `weavec1` from source.

Required tools:

- Bash 4 or newer
- LLVM 14 or newer: `clang`, `llvm-as`, and `llvm-link`
- `curl`, `tar`, and `sha256sum` for SDK acquisition
- `musl-gcc` only when building against the musl SDK

Ubuntu installation:

```bash
sudo apt-get install -y llvm clang curl musl-tools
```

macOS currently uses the source fallback because no macOS SDK is published:

```bash
brew install llvm git
export PATH="$(brew --prefix llvm)/bin:$PATH"
```

## Quick start

```bash
git clone https://github.com/ahojukka5/weavefront.git
cd weavefront
./build.sh
./test_all.sh
```

On Linux, the first build downloads `weavec1 v0.2.0`, verifies its archive
against the release `SHA256SUMS`, and extracts it under
`build/vendor/weavec1-sdk/`. Later builds reuse the cached SDK.

Compile a small surface program:

```bash
./build/weavefront test/01_return_42.weave /tmp/out.wir
cat /tmp/out.wir
```

## Published Stage 1 SDK

The default Linux dependency is:

```text
weavec1-v0.2.0-linux-x86_64-<libc>/
├── bin/weavec1
├── lib/libweave-runtime.a
├── include/runtime.h
└── SDK-MANIFEST
```

`build.sh` records the selected compiler and runtime in
`build/toolchain.env`. Both `test.sh` and `test_all.sh` read that file instead
of reconstructing vendor paths independently.

### Select glibc or musl

```bash
WEAVEC1_LIBC=glibc ./build.sh
WEAVEC1_LIBC=musl ./build.sh
```

Both variants produce a statically linked `build/weavefront` executable.

### Environment overrides

- `WEAVEC1_SDK=/path/to/sdk` uses an already extracted SDK.
- `WEAVEC1_VERSION=vX.Y.Z` selects a published release.
- `WEAVEC1_LIBC=glibc|musl` selects the archive and linker.
- `WEAVEC1_RELEASE_BASE=<url>` overrides the GitHub Release base URL.
- `WEAVEC1=/path/to/source` forces a pre-built source tree.
- `WEAVEC1_TAG=vX.Y.Z` selects the source fallback tag.
- `WEAVEC0=/path/to/source` and `WEAVEC0_TAG=vX.Y.Z` control the Stage 0
  source fallback used on platforms without an SDK.

Explicit `WEAVEC1_SDK` and `WEAVEC1` values take precedence over automatic
platform selection.

## Build pipeline

`./build.sh` performs these steps:

1. Resolve the Stage 1 dependency.
   - Linux x86-64: download and verify the published SDK.
   - Other platforms: build the pinned source tags.
2. Compile every WIR module under `src/` with `bin/weavec1`.
3. Link the generated LLVM modules into `build/weavefront.bc`.
4. Link the final executable.
   - SDK mode: use the matching static `libweave-runtime.a`.
   - Source mode: use the Stage 0 runtime source fallback.
5. Write `build/toolchain.env` for the test commands.

## Repository layout

```text
weavefront/
├── build.sh
├── test.sh
├── test_all.sh
├── weavefront-cat.sh
├── src/
│   ├── sexpr_*.wir
│   ├── surface_*.wir
│   ├── driver.wir
│   └── main.wir
├── test/
├── docs/
│   └── ARCHITECTURE.md
└── build/
    ├── toolchain.env
    ├── vendor/weavec1-sdk/
    ├── downloads/
    └── weavefront
```

## Test ladder

`./test_all.sh` walks every `test/*.weave` fixture through the full pipeline:

1. Surface Weave → WIR with `weavefront`.
2. Compare the WIR byte-for-byte with the checked-in golden.
3. WIR → LLVM IR with the resolved `weavec1` compiler.
4. Link with the resolved runtime and libc toolchain.
5. Run the executable and verify its exit code.

The CI matrix runs the complete ladder with:

- Linux x86-64 glibc SDK
- Linux x86-64 musl SDK
- macOS source fallback

`./test.sh` runs only the smallest `return 42` smoke case.

## Examples

Every file under [`test/`](test) is an end-to-end example. Useful starting
points include:

- [`test/01_return_42.weave`](test/01_return_42.weave)
- [`test/08_if.weave`](test/08_if.weave)
- [`test/09_while.weave`](test/09_while.weave)
- [`test/17_extern_malloc_free.weave`](test/17_extern_malloc_free.weave)
- [`test/57_struct_basic.weave`](test/57_struct_basic.weave)
- [`test/52_integration_nested_control_flow.weave`](test/52_integration_nested_control_flow.weave)

## Multifile compilation

`weavefront-cat.sh` combines multiple `(program ...)` files and invokes the
frontend once:

```bash
./weavefront-cat.sh combined.wir foo.weave bar.weave baz.weave
```

This is the bootstrap path used by `weavec2`.

## Compiler chain

| Stage | Repository | Role |
|---|---|---|
| `weavec0` | [`ahojukka5/weavec0`](https://github.com/ahojukka5/weavec0) | Hand-written LLVM-IR seed compiler and runtime SDK. |
| `weavec1` | [`ahojukka5/weavec1`](https://github.com/ahojukka5/weavec1) | WIR-written compiler and published Stage 1 SDK. |
| `weavefront` | **this repository** | Surface Weave → WIR frontend. |
| `weavec2` | [`ahojukka5/weavec2`](https://github.com/ahojukka5/weavec2) | Self-hosted surface compiler. |

Once `weavec2` fully replaces the split frontend/backend path, `weavefront`
and `weavec1` can mostly freeze as bootstrap stages.

## Known limitations

- Surface Weave intentionally stays close to WIR.
- The pretty-printer emits compact, byte-stable single-line WIR.
- Diagnostics use byte offsets rather than full line and column ranges.
- `src/string_utils.wir` remains outside the linked module list until another
  module consumes its wrappers.
- Published SDKs currently cover Linux x86-64 only; macOS uses source builds.

## License

Licensed under the Apache License, Version 2.0. See [`LICENSE`](LICENSE) and
[`NOTICE`](NOTICE).

## Contributing

Read [`CONTRIBUTING.md`](CONTRIBUTING.md) and the known limitations before
opening a pull request.
