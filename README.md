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
| **`weavec-bootstrap`** | Frozen surface-Weave-to-WIR-v2 bootstrap frontend. |
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
- every source function is reachable from `main`;
- every declared extern is used;
- every test source and WIR golden belongs to exactly one manifest case;
- the current downstream `weavec` full ladder must pass with an SDK
  packaged from this source tree.

Run the static audits directly with:

```bash
python3 scripts/check_docs.py
python3 scripts/audit_bootstrap.py
```

The bootstrap audit writes a machine-readable report to
`build/audit/weavec-bootstrap.json`.

## Dependencies

Every supported host consumes the checksum-verified `weavec1 v0.3.2` SDK by
default. Linux x86-64 selects glibc or musl with `WEAVEC1_LIBC`. macOS uses the
native `weavec1` archive for the host architecture. There is no source-chain
fallback: a missing host package is a dependency-release failure, not
permission to rebuild `weavec0` or `weavec1` from source.

Important overrides:

```text
WEAVEC1_SDK=/path/to/extracted/sdk
WEAVEC1_VERSION=vX.Y.Z
WEAVEC1_LIBC=glibc|musl
```

`WEAVEC1_SDK` takes precedence over a published download.

## Build and test

Required tools:

- Bash 4 or newer;
- LLVM 14 or newer: `clang`, `llvm-as`, and `llvm-link`;
- `curl`, `tar`, and `sha256sum` for SDK downloads;
- Python 3 for audits and the multifile driver;
- `musl-gcc` for the musl build.

```bash
git clone https://github.com/ahojukka5/weavec-bootstrap.git
cd weavec-bootstrap
python3 scripts/check_docs.py
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
build/toolchain.env          resolved compiler/runtime configuration
```

The executable links a tiny local host shim from `runtime/portable.c`. The shim
provides fixed-signature wrappers for host APIs whose native C interfaces are
variadic. This keeps arm64 macOS, glibc, and musl on one stable ABI without
expanding the Stage 0 runtime.

## Multifile bootstrap

```bash
./weavec-bootstrap-cat.sh /tmp/combined.wir foo.weave bar.weave
```

The driver strips outer program wrappers, combines modules in caller-supplied
order, and invokes the frontend once. `weavec` uses this path for its first
bootstrap build.

## Published SDK

Releases publish four archives: Linux x86-64 glibc, Linux x86-64 musl, macOS
arm64, and macOS x86-64. The Linux layout is:

```text
weavec-bootstrap-vX.Y.Z-linux-x86_64-<libc>/
├── bin/
│   ├── weavec-bootstrap
│   ├── weavec-bootstrap-cat
│   └── extract_program_decls.py
├── SDK-MANIFEST
├── VERSION
├── README.md
├── LICENSE
└── NOTICE
```

macOS archives use the same files without a libc suffix. See
[`docs/macos-sdk.md`](docs/macos-sdk.md). The installed multifile driver requires
Python 3. Release assets include `SHA256SUMS`; downstream builds must pin a
version and verify the selected archive before extraction. See
[`docs/releasing.md`](docs/releasing.md).

## CI coverage

CI validates:

- documentation filenames and local links;
- Linux x86-64 with the glibc `weavec1` SDK;
- Linux x86-64 with the musl `weavec1` SDK;
- native macOS arm64 and x86-64 with the `weavec1` SDK;
- all static source, test, reachability, and extern invariants;
- the complete current `weavec` correctness, performance, quantum, and
  self-host ladders, using a Linux glibc SDK packaged from this tree.

The release workflow separately builds and smokes all four SDK archives.

## Non-goals

- Extending WIR from the frontend.
- General language development.
- Type inference, macros, package resolution, or optimization.
- Preserving source comments through lowering.

## Documentation

Start with [`docs/index.md`](docs/index.md). The maintained design and release
contracts are:

- [`docs/architecture.md`](docs/architecture.md)
- [`docs/macos-sdk.md`](docs/macos-sdk.md)
- [`docs/releasing.md`](docs/releasing.md)
- [`CONTRIBUTING.md`](CONTRIBUTING.md)
- [`CHANGELOG.md`](CHANGELOG.md)

Files under `docs/` use lowercase kebab-case names. Conventional root metadata
keeps its standard uppercase spelling.

## License

Licensed under the Apache License, Version 2.0. See [`LICENSE`](LICENSE) and
[`NOTICE`](NOTICE).
