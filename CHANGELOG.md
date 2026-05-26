# Changelog

All notable changes to `weavefront` are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning is
[SemVer](https://semver.org/) with the caveat that `0.x` is the early
phase: minor versions may break things until the surface-language
contract stabilises.

## [Unreleased]

## [0.1.0] — 2026-05-27

The first public release of `weavefront`.

### Added
- Apache-2.0 licensing (`LICENSE`, `NOTICE`, SPDX headers on every
  owned source file).
- `CONTRIBUTING.md` describing the very narrow merge bar.
- `CHANGELOG.md` (this file).
- `.editorconfig` and `.gitattributes` for consistent line endings /
  indentation.
- GitHub Actions CI matrix (`ubuntu-latest`, `macos-latest`) that
  fetches the pinned `weavec0` and `weavec1` dependencies and runs the
  full ladder.
- `docs/ARCHITECTURE.md` — design and module map, refreshed for
  external readers.

### Changed
- Layout rename: `tests/` → `test/`, matching `weavec0` / `weavec1` /
  `weavec2`.
- `build.sh` no longer assumes `../weavec0/` and `../weavec1/` siblings.
  It now honours `WEAVEC0` / `WEAVEC1` env vars (paths to existing
  source trees); when unset, it git-clones the pinned `WEAVEC0_TAG`
  (default `v0.2.0`) and `WEAVEC1_TAG` (default `v0.1.0`) from GitHub
  into `build/vendor/`. Vendored copies are gitignored. weavec1's own
  build.sh is invoked with `WEAVEC0=$WEAVEC0_DIR` so the weavec0
  dependency is built once.
- `test.sh` and `test_all.sh` resolve `WEAVEC0` / `WEAVEC1` with the
  same env-or-vendor convention so the test runner finds the
  dependencies wherever `build.sh` put them.
- `WEAVEFRONT_ARCHITECTURE.md` → `docs/ARCHITECTURE.md`, content
  brought up to date (mentions `surface_struct.wir` and
  `string_utils.wir`, drops the "Current Tests: 01_return_42" section
  that was three iterations of the project ago).

### Removed
- `test/multifile_a.weave` and `test/multifile_b.weave` (previously
  under `tests/`). These fixtures had no `*.expected.wir` files and
  aborted `test_all.sh` mid-ladder. The multifile concatenation
  workflow itself is still supported via `weavefront-cat.sh`, which
  is what `weavec2`'s build uses. Documenting and re-testing that
  contract is a separate follow-up.

### Known limitations
- The repository ships a `src/string_utils.wir` module declaring
  `strlen` / `strncmp` / `memchr` extern wrappers, but no current
  module links against it. It is intentionally not in `build.sh`'s
  `MODULES` list. Revisit when a module actually consumes it.
- Pretty-printing is single-line: the output WIR is correct and
  byte-stable but not human-formatted. The downstream compilers
  don't care; tooling that consumes the `.wir` may want to add
  indentation downstream.
- No line/column information is tracked through lowering. Error
  messages refer to byte offsets in the source. Acceptable for the
  v0.x phase; revisit when the surface language gains more failure
  modes worth diagnosing.
