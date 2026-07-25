# Contributing to weavec-bootstrap

`weavec-bootstrap` is the deterministic surface-Weave-to-WIR-v2 frontend used to
bootstrap the self-hosted [`weavec`](https://github.com/ahojukka5/weavec)
compiler. It is a frozen bootstrap component, not the primary language-development
repository.

## Principles

- **WIR v2 is the boundary contract.** Emit only forms already accepted by
  `weavec1`; never extend WIR here.
- **Determinism is required.** The same `.weave` input must produce byte-identical
  `.wir` output across supported hosts.
- **Inventories are explicit.** Production modules belong in the `build.sh`
  `MODULES` array. Test cases belong in `test/manifest.txt`. Parser-library
  exports belong in `PARSER_SDK_EXPORTS`.
- **No dead bootstrap surface.** Every source function must be reachable from
  `main` or an approved parser SDK export, and every extern must be used.
- **No feature without an end-to-end fixture.** Add a matching source, WIR
  golden, and manifest entry.
- **Keep the surface close to WIR.** Avoid inference, macro expansion,
  optimization, or hidden control-flow transformations.
- **Keep host ABI details local.** Variadic native APIs require fixed-signature
  wrappers in `runtime/portable.c`; do not enlarge the Stage 0 runtime for
  frontend-only needs.
- **Prefer changes in `weavec`.** User-facing language evolution belongs in the
  final compiler unless this stage must learn a form to bootstrap it.
- **Keep documentation navigable.** Files under `docs/` use lowercase
  kebab-case names and all local Markdown links must resolve.

## What does not belong here

- New WIR primitives or backend LLVM behavior.
- General language evolution not required for bootstrap.
- Type inference, packages, macros, pattern matching, or optimization.
- Compatibility aliases or unbuilt source files.
- Runtime externs introduced only to avoid a local portability wrapper.

## Development workflow

1. Create a focused branch.
2. Read `docs/architecture.md` and identify the affected boundary.
3. Edit the smallest relevant source, build, test, portability, or documentation
   component.
4. Add or update `test/NN_<name>.weave`, its `.expected.wir`, and
   `test/manifest.txt` when behavior changes.
5. Update `PARSER_SDK_EXPORTS` only when the downstream binary interface changes.
6. Run:

   ```sh
   python3 scripts/check_docs.py
   python3 scripts/audit_bootstrap.py
   ./build.sh
   ./test_all.sh
   ```

7. Confirm these artifacts exist:

   ```text
   build/weavec-bootstrap
   build/weavec-bootstrap.bc
   build/libweave-sexpr.bc
   build/audit/weavec-bootstrap.json
   ```

8. Review WIR goldens, executable exit codes, reachability changes, and SDK
   exports.
9. Update README, architecture, changelog, and dependency documentation when a
   public contract changes.
10. Open a focused pull request.

CI validates documentation consistency, Linux glibc, Linux musl, arm64 macOS
source fallback, both static SDK packages, and the complete current `weavec`
downstream ladder.

## Dependency changes

The normal Linux dependency is selected with `WEAVEC1_VERSION`,
`WEAVEC1_LIBC`, and optionally `WEAVEC1_SDK`. Do not update a version pin before
the corresponding release assets and `SHA256SUMS` exist.

A new `weavec-bootstrap` release must exist before changing the default pin in
`weavec`.

See [`docs/index.md`](docs/index.md),
[`docs/architecture.md`](docs/architecture.md), and
[`docs/releasing.md`](docs/releasing.md).

## Licensing

By submitting a contribution, you agree that it is licensed under the Apache
License, Version 2.0. See [`LICENSE`](LICENSE).
