# weavec-bootstrap — Surface Weave Bootstrap Frontend

[![ci](https://github.com/ahojukka5/weavec-bootstrap/actions/workflows/ci.yml/badge.svg)](https://github.com/ahojukka5/weavec-bootstrap/actions/workflows/ci.yml)

> A deterministic surface-Weave-to-WIR frontend used to bootstrap the
> self-hosted `weavec` compiler.

This repository was previously named `weavefront`. The new name makes its role
explicit: it is part of the bootstrap chain, not the final user-facing
compiler.

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

`weavec-bootstrap` owns the **surface → WIR** edge. It is written in WIR and
built with the published `weavec1` SDK. It provides the frontend needed to build
[`weavec`](https://github.com/ahojukka5/weavec) from surface-Weave source.

The frontend contains a generic S-expression lexer, parser, tree, and printer,
with deterministic surface validation and lowering layered on top. See
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Compiler chain

| Component | Repository | Role |
|---|---|---|
| `weavec0` | [`ahojukka5/weavec0`](https://github.com/ahojukka5/weavec0) | Hand-written Stage 0 seed and SDK. |
| `weavec1` | [`ahojukka5/weavec1`](https://github.com/ahojukka5/weavec1) | WIR compiler and Stage 1 SDK. |
| `weavec-bootstrap` | **this repository** | Surface-to-WIR bootstrap frontend, formerly `weavefront`. |
| `weavec` | [`ahojukka5/weavec`](https://github.com/ahojukka5/weavec) | User-facing self-hosted compiler, formerly `weavec2`. |

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

The current executable retains the historical path `build/weavefront` for
compatibility. Conceptually it is the `weavec-bootstrap` command:

```bash
./build/weavefront test/01_return_42.weave /tmp/out.wir
```

## Stage 1 SDK

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

## Build pipeline

`./build.sh`:

1. resolves the Stage 1 SDK or source fallback;
2. compiles the linked `src/*.wir` modules with `weavec1`;
3. combines the LLVM modules into `build/weavefront.bc`;
4. links the executable with the matching runtime;
5. writes `build/toolchain.env` for tests and downstream bootstrap use.

The `build/weavefront*` filenames are compatibility names from the former
repository identity. New documentation refers to the component as
`weavec-bootstrap`.

## Repository layout

```text
weavec-bootstrap/
├── build.sh
├── test.sh
├── test_all.sh
├── weavefront-cat.sh          historical multifile script name
├── src/                       WIR frontend modules
├── test/                      58 surface fixtures and WIR goldens
├── docs/ARCHITECTURE.md
└── build/                     generated frontend and toolchain metadata
```

## Tests

`./test_all.sh` runs every surface fixture through:

1. surface Weave → WIR with the bootstrap frontend;
2. byte-for-byte comparison with the WIR golden;
3. WIR → LLVM IR with the resolved `weavec1` compiler;
4. native linking with the resolved runtime;
5. execution and exit-code verification.

CI covers:

- Linux x86-64 glibc SDK;
- Linux x86-64 musl SDK;
- macOS source fallback.

`./test.sh` runs the smallest `return 42` smoke case.

## Multifile bootstrap path

The historical `weavefront-cat.sh` script combines multiple `(program ...)`
files and invokes the frontend once:

```bash
./weavefront-cat.sh combined.wir foo.weave bar.weave baz.weave
```

`weavec` currently uses this path to lower its own source tree during the first
bootstrap generation.

## Known limitations

- Surface Weave intentionally stays close to WIR.
- Output is compact and byte-stable rather than source-formatted.
- Diagnostics use byte offsets rather than full source ranges.
- Published SDKs currently cover Linux x86-64 only.
- Executable and helper filenames still contain the historical `weavefront`
  name for compatibility.

## License

Licensed under the Apache License, Version 2.0. See [`LICENSE`](LICENSE) and
[`NOTICE`](NOTICE).

## Contributing

Read [`CONTRIBUTING.md`](CONTRIBUTING.md) before changing the lowering contract,
SDK assumptions, or bootstrap outputs.
