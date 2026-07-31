# Changelog

All notable changes to `weavec-bootstrap` are recorded here. The repository was
named `weavefront` through release `v0.1.0`. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning follows
[SemVer](https://semver.org/); the bootstrap surface contract remains pre-1.0.

## [Unreleased]

### Added

- A documentation index and automated checks for lowercase documentation names
  and valid local Markdown links.
- Native macOS SDK packaging for the compiler, multifile driver, and parser
  library, verified with a `libSystem`-only self-containment check and
  published automatically by the release workflow alongside the Linux SDKs.

### Changed

- Standardized maintained files under `docs/` on lowercase kebab-case names.
- Switched every supported host to the released `weavec1 v0.3.2` SDK and removed
  implicit Stage 0 and Stage 1 source-chain fallbacks.
- Bumped the bootstrap SDK version to 0.3.1.

## [0.3.0] — 2026-07-25

### Added

- `scripts/audit_bootstrap.py` and a machine-readable
  `build/audit/weavec-bootstrap.json` report covering source inventory, WIR
  version declarations, direct calls, reachability, extern use, tests, and
  parser SDK exports.
- `test/manifest.txt` as the exact 58-case source/golden/exit-code inventory.
- `PARSER_SDK_EXPORTS` as the explicit 13-symbol downstream parser-library
  contract.
- A local fixed-signature host wrapper in `runtime/portable.c` for portable
  output-file creation.
- A permanent CI gate that runs the complete current `weavec` correctness,
  performance, quantum, and self-host ladders with the frontend source under
  review.

### Changed

- Migrated all production modules and WIR goldens from WIR v1 to WIR v2.
- Surface lowering now emits `(core-version 2)`.
- Updated the default Stage 1 dependency to `weavec1 v0.3.1` and the Stage 0
  source fallback to `weavec0 v0.4.0`.
- Reworked `test_all.sh` into one manifest-driven surface-to-native ladder with
  byte-for-byte WIR comparison and explicit LLVM assembly.
- CI and release workflows now run the static bootstrap audit and preserve its
  diagnostics on failure.
- The build compiles the local portability wrapper with the selected glibc,
  musl, or macOS toolchain.

### Removed

- Unbuilt `src/string_utils.wir` residue.
- Unreachable compatibility helpers `copy_node`, `link4`, and `print_indent`.
- Unused source extern declarations for `atoi`, `snprintf`, and `strlen`.

### Fixed

- Output-file permissions on arm64 macOS are now deterministic. The frontend no
  longer calls variadic `open` through an incorrect fixed LLVM signature when
  creating output files.
- Compact single-line WIR goldens are recognized correctly by the WIR-version
  audit.
- Failed audit and build jobs retain actionable logs and JSON reports.

## [0.2.0] — 2026-07-24

### Added

- Static Linux x86-64 SDK archives for glibc and musl.
- `bin/weavec-bootstrap-cat` as an installed-layout multifile driver.
- `lib/libweave-sexpr.bc` as the versioned downstream parser-library boundary.
- `SDK-MANIFEST`, `VERSION`, release checksums, packaging smoke tests, and
  automated GitHub Release publication.
- `docs/RELEASING.md` for the SDK contract and release process.

### Changed

- Renamed the repository from `weavefront` to `weavec-bootstrap` to distinguish
  the bootstrap frontend from the final `weavec` compiler.
- Renamed the executable from `build/weavefront` to
  `build/weavec-bootstrap`.
- Renamed the multifile driver from `weavefront-cat.sh` to
  `weavec-bootstrap-cat.sh`.
- Linked the reusable `sexpr_tokens`, `sexpr_tree`, `sexpr_lexer`, and
  `sexpr_parser` modules into one named `build/libweave-sexpr.bc` library for
  downstream bootstrap consumers.
- Removed the historical compatibility paths; current files, environment
  variables, diagnostics, tests, and documentation use canonical component
  names.
- Linux x86-64 builds consume the published `weavec1 v0.2.0` SDK instead of
  cloning and rebuilding `weavec0` and `weavec1`.
- Stage 1 SDK downloads are verified against release `SHA256SUMS` and cached
  under `build/vendor/weavec1-sdk/`.
- glibc and musl are supported as explicit static build variants.
- `build.sh` writes `build/toolchain.env` as the resolved compiler, runtime,
  linker, and libc contract.
- `test.sh` and `test_all.sh` consume that toolchain file rather than
  reconstruct vendor paths.
- CI validates Linux glibc SDK, Linux musl SDK, and macOS source-fallback
  builds.

### Fixed

- End-to-end tests no longer depend on a checked-out `runtime.c` in SDK mode;
  they link with the packaged `libweave-runtime.a`.
- Architecture documentation no longer claims `string_utils.wir` is linked or
  used by active lowering modules.
- The bootstrap CLI diagnostics and their explicit WIR byte lengths now use the
  canonical `weavec-bootstrap` command name.
- The bootstrap executable owns its 16 MiB main-thread stack requirement on
  Linux and macOS, so downstream compilers no longer patch this repository's
  build script.
- The multifile driver resolves either the source-tree compiler or the sibling
  executable in an extracted SDK.

## [0.1.0] — 2026-05-27

The first public release, published under the repository name `weavefront`.

### Added

- Apache-2.0 licensing and SPDX headers.
- `CONTRIBUTING.md`, this changelog, and repository formatting files.
- GitHub Actions CI on Linux and macOS.
- `docs/ARCHITECTURE.md` for the module and lowering design.

### Changed

- Renamed `tests/` to `test/`.
- Removed sibling-repository assumptions. The initial release fetched pinned
  `weavec0 v0.2.0` and `weavec1 v0.1.0` source trees into `build/vendor/`.
- Aligned `test.sh` and `test_all.sh` with the initial env-or-vendor build
  convention.
- Moved and refreshed the architecture document.

### Removed

- Unpaired multifile fixtures that had no expected WIR files and aborted the
  ladder. Multifile compilation remained supported in that release through the
  then-named `weavefront-cat.sh` helper.
