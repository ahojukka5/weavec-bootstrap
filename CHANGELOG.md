# Changelog

All notable changes to `weavec-bootstrap` are recorded here. The repository was
named `weavefront` through release `v0.1.0`. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning follows
[SemVer](https://semver.org/); the bootstrap surface contract remains pre-1.0.

## [Unreleased]

### Changed

- Renamed the repository from `weavefront` to `weavec-bootstrap` to distinguish
  the bootstrap frontend from the final `weavec` compiler.
- Updated documentation, links, notices, and compiler-chain terminology to use
  `weavec0 → weavec1 → weavec-bootstrap → weavec`.
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

### Compatibility

- The executable path `build/weavefront` and helper `weavefront-cat.sh` retain
  their historical names until downstream bootstrap scripts migrate.

### Fixed

- End-to-end tests no longer depend on a checked-out `runtime.c` in SDK mode;
  they link with the packaged `libweave-runtime.a`.
- Architecture documentation no longer claims `string_utils.wir` is linked or
  used by active lowering modules.

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
  ladder. Multifile compilation remains supported through the historical
  `weavefront-cat.sh` helper.

### Known limitations

- `src/string_utils.wir` is present but not linked until an active module needs
  its wrappers.
- The printer emits compact single-line WIR.
- Diagnostics refer to byte offsets rather than complete source ranges.
