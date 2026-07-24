# Contributing to weavec-bootstrap

`weavec-bootstrap` is the deterministic surface-Weave-to-WIR frontend used to
bootstrap the self-hosted [`weavec`](https://github.com/ahojukka5/weavec)
compiler. The repository was formerly named `weavefront`.

It is written in WIR and built with the published `weavec1` SDK on Linux.

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
- **Prefer changes in `weavec`.** New user-facing language development belongs
  in the final compiler unless the bootstrap frontend must learn the form to
  build that compiler.

## What does not belong here

- New WIR primitives or backend LLVM behavior.
- General language evolution that is not required for bootstrap.
- High-level systems such as packages, macros, inference, or pattern matching.
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

CI validates:

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

## Historical command names

The build currently retains `build/weavefront` and `weavefront-cat.sh` as
compatibility paths. Treat `weavec-bootstrap` as the component name in new
prose, issues, and design documents.

## Licensing

By submitting a contribution, you agree that it is licensed under the Apache
License, Version 2.0. See [`LICENSE`](LICENSE).
