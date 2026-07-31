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

GitHub Actions may publish all configured packages when credits and runners are
available, but release correctness must not depend on Actions.

A packaging-only release may add a new host without rebuilding unchanged host
artifacts. `v0.3.1` adds native macOS packages, while Linux builds continue to
consume the unchanged `v0.3.0` bootstrap SDK. Downstream resolvers therefore
select a version that actually contains the requested host package.

## Release prerequisites

Before changing `VERSION`, confirm:

1. `python3 scripts/audit_bootstrap.py` passes with every source function
   reachable and every extern used;
2. all 58 manifest cases pass on the host being packaged;
3. the complete current downstream `weavec` ladder passes using this source
   tree;
4. the selected release package passes its installed-layout smoke tests;
5. `CHANGELOG.md`, README, architecture, and dependency pins are current;
6. the selected host-specific `weavec1` release and `SHA256SUMS` exist.

Do not update the default `weavec` SDK pin until the required bootstrap host
asset and checksums are published.

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

For an intentionally republished Linux package:

```sh
python3 scripts/audit_bootstrap.py
WEAVEC1_LIBC=glibc ./build.sh
./test_all.sh
bash scripts/package-linux-sdk.sh glibc "$version" dist
```

For macOS:

```sh
python3 scripts/audit_bootstrap.py
./build.sh
./test_all.sh
scripts/package-macos-sdk.sh "$version" dist
```

## Manual macOS publication

When GitHub Actions are unavailable, publish the current Mac architecture from a
clean, locally qualified checkout:

```sh
scripts/publish-macos-sdk.sh
```

The script derives `v<VERSION>`, invokes the package script, creates or updates
the corresponding GitHub Release with `gh`, preserves checksums for existing
assets, replaces the current architecture archive, and verifies the published
asset names. Run it separately on each architecture being published.

## Published assets

A full cross-platform release may contain:

```text
weavec-bootstrap-vX.Y.Z-linux-x86_64-glibc.tar.gz
weavec-bootstrap-vX.Y.Z-linux-x86_64-musl.tar.gz
weavec-bootstrap-vX.Y.Z-macos-arm64.tar.gz
weavec-bootstrap-vX.Y.Z-macos-x86_64.tar.gz
SHA256SUMS
```

A platform-addition release may contain only the newly introduced host archives
and `SHA256SUMS`. Downstream builds must pin a version that contains the selected
package and verify it against that release's checksums before extraction.

## Post-publication checklist

After publication:

1. verify that the tag resolves to the intended release commit;
2. verify the host archive and `SHA256SUMS` are present;
3. update the corresponding host-specific bootstrap pin in `weavec`;
4. run the complete `weavec` ladder against the published SDK;
5. keep the released bootstrap line limited to correctness, security,
   portability, reproducibility, or packaging fixes.
