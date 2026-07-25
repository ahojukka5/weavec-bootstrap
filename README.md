# weavec-bootstrap — Surface Weave Bootstrap Frontend

[![ci](https://github.com/ahojukka5/weavec-bootstrap/actions/workflows/ci.yml/badge.svg)](https://github.com/ahojukka5/weavec-bootstrap/actions/workflows/ci.yml)
[![release](https://github.com/ahojukka5/weavec-bootstrap/actions/workflows/release.yml/badge.svg)](https://github.com/ahojukka5/weavec-bootstrap/actions/workflows/release.yml)

`weavec-bootstrap` is the deterministic frontend used to bootstrap the
self-hosted [`weavec`](https://github.com/ahojukka5/weavec) compiler. It lowers
surface Weave to stable WIR v2. It is not the final user-facing compiler.

## Position in the compiler chain

```text
weavec0 → weavec1 → weavec-bootstrap → weavec
   WIR      LLVM        surface → WIR      self-hosted compiler
```

| Component | Responsibility |
|---|---|
| [`weavec0`](https://github.com/ahojukka5/weavec0) | Minimal hand-written Stage 0 seed and runtime SDK. |
| [`weavec1`](https://github.com/ahojukka5/weavec1) | Stable WIR v2 backend and Stage 1 SDK. |
| **`weavec-bootstrap`** | Frozen surface-Weave-to-WIR-v2 bootstrap frontend and parser SDK. |
| [`weavec`](https://github.com/ahojukka5/weavec) | User-facing self-hosted compiler and language development. |

Language evolution belongs in `weavec`. This repository changes only when the
bootstrap chain requires a correctness, security, portability, reproducibility,
or packaging fix.

## Contract

The frontend accepts a deliberately small surface language and emits only WIR
v2 already admitted by `weavec1`. Function bodies remain close to explicit WIR
operations; lowering is a deterministic tree rewrite, not an optimizing or
inferential compiler pass.

The repository enforces these boundaries:

- every production `src/*.wir` file is listed exactly once in `build.sh`;
- every production module declares `(core-version 2)` exactly once;
- every direct WIR call resolves to a source function or declared extern;
- every source function is reachable from `main` or a documented parser SDK export;
- every declared extern is used;
- every test source and WIR golden belongs to exactly one manifest case;
- the parser SDK exports exactly the symbols listed in `PARSER_SDK_EXPORTS`;
- the current downstream `weavec` full ladder must pass with this source tree.

Run the static audit directly with:

```bash
python3 scripts/audit_bootstrap.py
```

The audit writes a machine-readable report to
`build/audit/weavec-bootstrap.json`.

## Dependencies

Linux x86-64 builds consume the checksum-verified `weavec1 v0.3.1` SDK by
default. The selected archive provides both the compiler and matching static
runtime library.

macOS uses pinned source fallbacks:

- `weavec1 v0.3.1`;
- `weavec0 v0.4.0`.

Important overrides:

```text
WEAVEC1_SDK=/path/to/extracted/sdk
WEAVEC1_VERSION=vX.Y.Z
WEAVEC1_LIBC=glibc|musl
WEAVEC1=/path/to/weavec1/source
WEAVEC1_TAG=vX.Y.Z
WEAVEC0=/path/to/weavec0/source
WEAVEC0_TAG=vX.Y.Z
```

Explicit source and SDK paths take precedence over published downloads.

## Build and test

Required tools:

- Bash 4 or newer;
- LLVM 14 or newer: `clang`, `llvm-as`, and `llvm-link`;
- `curl`, `tar`, and `sha256sum` for SDK downloads;
- Python 3 for the multifile driver;
- `musl-gcc` for the musl build.

```bash
git clone https://github.com/ahojukka5/weavec-bootstrap.git
cd weavec-bootstrap
python3 scripts/audit_bootstrap.py
./build.sh
./test_all.sh
```

Select the Linux libc variant with:

```bash
WEAVEC1_LIBC=glibc ./build.sh
WEAVEC1_LIBC=musl ./build.sh
```

`test_all.sh` reads `test/manifest.txt` and runs all 58 cases through one complete
pipeline:

```text
surface Weave
  → weavec-bootstrap
  → byte-identical WIR v2 golden
  → weavec1
  → valid LLVM bitcode
  → native executable
  → expected exit code
```

## Build products

`./build.sh` produces:

```text
build/weavec-bootstrap       surface Weave → WIR v2 executable
build/weavec-bootstrap.bc    complete frontend LLVM bitcode
build/libweave-sexpr.bc      reusable parser-library boundary
build/toolchain.env          resolved compiler/runtime configuration
```

The executable links a tiny local host shim from `runtime/portable.c`. The shim
provides fixed-signature wrappers for host APIs whose native C interfaces are
variadic. This keeps arm64 macOS, glibc, and musl on one stable ABI without
expanding the Stage 0 runtime.

## Parser SDK

The parser library combines:

```text
src/sexpr_tokens.wir
src/sexpr_tree.wir
src/sexpr_lexer.wir
src/sexpr_parser.wir
```

Its 13 public symbols are listed in `PARSER_SDK_EXPORTS`. Downstream stages link
`libweave-sexpr.bc` as one unit and must not depend on individual generated
module files.

## Multifile bootstrap

```bash
./weavec-bootstrap-cat.sh /tmp/combined.wir foo.weave bar.weave
```

The driver strips outer program wrappers, combines modules in caller-supplied
order, and invokes the frontend once. `weavec` uses this path for its first
bootstrap build.

## Published SDK

Releases publish static Linux x86-64 archives for glibc and musl:

```text
weavec-bootstrap-vX.Y.Z-linux-x86_64-<libc>/
├── bin/
│   ├── weavec-bootstrap
│   └── weavec-bootstrap-cat
├── lib/
│   └── libweave-sexpr.bc
├── SDK-MANIFEST
├── VERSION
├── README.md
├── LICENSE
└── NOTICE
```

The installed multifile driver requires Python 3. Release assets include
`SHA256SUMS`; downstream builds must pin a version and verify the selected
archive before extraction. See [`docs/RELEASING.md`](docs/RELEASING.md).

## CI coverage

CI validates:

- Linux x86-64 with the glibc `weavec1` SDK;
- Linux x86-64 with the musl `weavec1` SDK;
- arm64 macOS using pinned source fallbacks;
- all static source, test, reachability, extern, and parser-export invariants;
- the complete current `weavec` correctness, performance, quantum, and self-host ladders.

The release workflow separately builds and smokes both static SDK variants.

## Non-goals

- Extending WIR from the frontend.
- General language development.
- Type inference, macros, package resolution, or optimization.
- Preserving source comments through lowering.
- Publishing non-Linux binary SDKs at this stage.

## Documentation

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- [`docs/RELEASING.md`](docs/RELEASING.md)
- [`CONTRIBUTING.md`](CONTRIBUTING.md)
- [`CHANGELOG.md`](CHANGELOG.md)

## License

Licensed under the Apache License, Version 2.0. See [`LICENSE`](LICENSE) and
[`NOTICE`](NOTICE).
