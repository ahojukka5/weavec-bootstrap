# Contributing to weavefront

`weavefront` is the deterministic surface-Weave-to-WIR frontend. It is written
in WIR, built with the published `weavec1` SDK on Linux, and used to bootstrap
the self-hosted surface compiler.

## Principles

- **WIR is the boundary contract.** Surface lowering must emit WIR already
  accepted by the backend. Do not extend WIR from this repository.
- **Determinism is required.** The same `.weave` input must produce
  byte-identical `.wir` output across runs and platforms.
- **No feature without an end-to-end fixture.** Add a matching
  `test/NN_<name>.weave` and `test/NN_<name>.expected.wir` pair.
- **Keep the surface close to WIR.** Avoid type inference, macro expansion,
  optimisation, or hidden control-flow transformations.
- **Keep toolchain documentation synchronized.** Build, test, README, and
  architecture changes must agree on SDK paths and runtime linkage.

## What does not belong here

- New WIR primitives or backend LLVM behavior.
- High-level language systems such as packages, macros, inference, or pattern
  matching.
- Runtime externs added only in the frontend. Add the ABI to Stage 0, publish a
  new Stage 0 SDK, publish the corresponding Stage 1 SDK, and then update
  `WEAVEC1_VERSION` here.

## Development workflow

1. Create a focused branch.
2. Edit the relevant `src/*.wir` module.
3. Add or update paired fixtures under `test/`.
4. Run:

   ```sh
   ./build.sh
   ./test_all.sh
   ```

5. Confirm WIR goldens are intentional and end-to-end executables return the
   expected codes.
6. Update README, architecture, changelog, and dependency documentation when a
   public surface or toolchain contract changes.
7. Open a pull request.

CI validates the full ladder on:

- Linux x86-64 with the glibc `weavec1` SDK;
- Linux x86-64 with the musl `weavec1` SDK;
- macOS with the source fallback.

## Dependency changes

The normal Linux dependency is selected with:

- `WEAVEC1_VERSION` for the release;
- `WEAVEC1_LIBC` for glibc or musl;
- `WEAVEC1_SDK` for an extracted local SDK.

Do not update the version pin before the corresponding Stage 1 release exists
and its `SHA256SUMS` and archive contents have been verified.

## Licensing

By submitting a contribution, you agree that it is licensed under the Apache
License, Version 2.0. See [`LICENSE`](LICENSE).
