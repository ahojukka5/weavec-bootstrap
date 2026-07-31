# Releasing weavec-bootstrap

`weavec-bootstrap` publishes static Linux x86-64 SDK archives for glibc and
musl, and native macOS SDK archives for arm64 and x86-64. A release packages
the bootstrap executable, multifile driver, and the single parser-library
boundary consumed by `weavec`.

## Version and immutability

`VERSION` contains the release version without the `v` prefix. Tags and archive
names use the prefix:

```text
VERSION: X.Y.Z
tag:     vX.Y.Z
```

A normal push to `master` creates the selected release only when it does not
already exist. Existing `VERSION` releases remain immutable. An explicit tag
workflow may replace damaged assets for that same tag.

## Release prerequisites

Before changing `VERSION`, confirm:

1. `python3 scripts/audit_bootstrap.py` passes with every source function
   reachable and every extern used;
2. all 58 manifest cases pass on Linux glibc, Linux musl, and native macOS;
3. the complete current downstream `weavec` ladder passes using this source
   tree;
4. all four release packaging jobs pass their installed-layout smoke tests;
5. `CHANGELOG.md`, README, architecture, and dependency pins are current;
6. the selected `weavec1` release and `SHA256SUMS` already exist.

Do not update the default `weavec` SDK pin until the new bootstrap release assets
and checksums are published.

## SDK layout

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

The executable is statically linked for the selected libc. The parser library is
LLVM bitcode and is linked by downstream bootstrap consumers as one unit.
`weavec-bootstrap-cat` requires Python 3 at runtime.

The executable includes the local fixed-signature host shim from
`runtime/portable.c`; this is an implementation detail and does not add another
SDK file or public runtime dependency.

Each macOS archive (`weavec-bootstrap-vX.Y.Z-macos-<arm64|x86_64>/`) has the
same layout without a libc suffix. See
[macOS bootstrap SDK](macos-sdk.md) for the self-containment contract macOS
uses in place of full static linking.

## Local validation and packaging

Use the version selected by the repository:

```sh
version="v$(tr -d '[:space:]' < VERSION)"
```

For glibc:

```sh
python3 scripts/audit_bootstrap.py
WEAVEC1_LIBC=glibc ./build.sh
./test_all.sh
bash scripts/package-linux-sdk.sh glibc "$version" dist
```

For musl:

```sh
python3 scripts/audit_bootstrap.py
WEAVEC1_LIBC=musl ./build.sh
./test_all.sh
bash scripts/package-linux-sdk.sh musl "$version" dist
```

The packaging script verifies static linkage, compiles single-file and
multifile samples through the installed layout, and writes `SDK-MANIFEST`.

On macOS, package the native host architecture the same way:

```sh
python3 scripts/audit_bootstrap.py
./build.sh
./test_all.sh
scripts/package-macos-sdk.sh "$version" dist
```

## Published assets

A normal release contains:

```text
weavec-bootstrap-vX.Y.Z-linux-x86_64-glibc.tar.gz
weavec-bootstrap-vX.Y.Z-linux-x86_64-musl.tar.gz
weavec-bootstrap-vX.Y.Z-macos-arm64.tar.gz
weavec-bootstrap-vX.Y.Z-macos-x86_64.tar.gz
SHA256SUMS
```

Downstream builds must pin the tag and verify the selected archive against
`SHA256SUMS` before extraction.

## Publication workflow

`.github/workflows/release.yml` builds both Linux libc variants and both native
macOS architectures for pull requests, `master`, explicit tags, and manual
dispatches. On a successful `master` push it publishes the release selected by
`VERSION` when absent, folding all four archives into one `SHA256SUMS`.

After publication:

1. verify that the tag resolves to the merged release commit;
2. verify both archives and `SHA256SUMS` are present;
3. update the default `WEAVEC_BOOTSTRAP_VERSION` and source fallback ref in
   `weavec`;
4. run the complete `weavec` matrix against the published SDKs;
5. do not add further features to the released bootstrap line—only bootstrap
   correctness, security, portability, reproducibility, or packaging fixes.
