# Contributing to weavec-bootstrap

`weavec-bootstrap` is the deterministic surface-Weave-to-WIR frontend used to
bootstrap the self-hosted [`weavec`](https://github.com/ahojukka5/weavec)
compiler. It is written in WIR and built with the published `weavec1` SDK.

## Principles

- **WIR is the boundary contract.** Surface lowering must emit WIR already
  accepted by the backend. Do not extend WIR from this repository.
- **Determinism is required.** The same `.weave` input must produce
  byte-identical `.wir` output across runs and platforms.
- **No feature without an end-to-end fixture.** Add a matching
  `test/NN_<name>.weave` and `test/NN_<name>.expected.wir` pair.
- **Keep the surface close to WIR.** Avoid inference, macro expansion,
  optimisation, or hidden control-flow transformations.
- **Keep binary boundaries named.** Downstream stages consume
  `build/libweave-sexpr.bc`, never individual generated parser `.ll` files.
- **Prefer changes in `weavec`.** User-facing language development belongs in
  the final compiler unless this stage must learn the form to bootstrap it.

## What does not belong here

- New WIR primitives or backend LLVM behavior.
- General language evolution not required for bootstrap.
- High-level systems such as packages, macros, inference, or pattern matching.
- Runtime externs added only in the frontend. Release the ABI through Stage 0
  and Stage 1 before updating this repository.

## Development workflow

1. Create a focused branch.
2. Edit the relevant `src/*.wir` module.
3. Add or update paired fixtures under `test/`.
4. Run:

   ```sh
   ./build.sh
   ./test_all.sh
   ```

5. Confirm `build/weavec-bootstrap`, `build/weavec-bootstrap.bc`, and
   `build/libweave-sexpr.bc` exist.
6. Review WIR goldens and executable exit codes.
7. Update README, architecture, changelog, and dependency documentation when a
   public surface or toolchain contract changes.
8. Open a pull request.

CI validates Linux x86-64 with glibc and musl Stage 1 SDKs plus the macOS source
fallback.

## Dependency changes

The normal Linux dependency is selected with `WEAVEC1_VERSION`,
`WEAVEC1_LIBC`, and optionally `WEAVEC1_SDK`. Do not update the version pin
before the corresponding Stage 1 release and `SHA256SUMS` exist.

## Licensing

By submitting a contribution, you agree that it is licensed under the Apache
License, Version 2.0. See [`LICENSE`](LICENSE).
