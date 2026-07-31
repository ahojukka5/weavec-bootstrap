<!-- SPDX-License-Identifier: Apache-2.0 -->

# Documentation

`weavec-bootstrap` is a frozen surface-Weave-to-WIR-v2 bootstrap frontend. The
repository documentation is intentionally small and describes only the stable
bootstrap boundary.

## Documents

- [Architecture](architecture.md) — module graph, lowering pipeline, parser SDK,
  portability boundary, and verification model.
- [macOS bootstrap SDK](macos-sdk.md) — native Stage 1 dependency, package layout,
  smoke validation, and target-host publication.
- [Releasing](releasing.md) — SDK layout, validation, publication, and dependency
  ordering.
- [Contributing](../CONTRIBUTING.md) — change policy and required checks.
- [Changelog](../CHANGELOG.md) — released and pending changes.

## Naming policy

Files under `docs/` use lowercase kebab-case names. Conventional repository-root
files such as `README.md`, `CHANGELOG.md`, `CONTRIBUTING.md`, `LICENSE`, and
`NOTICE` retain their standard names.
