# Releasing weavec-bootstrap

`weavec-bootstrap` publishes static Linux x86-64 SDK archives for glibc and
musl. A release packages the bootstrap command, multifile driver, and the single
public parser-library boundary consumed by `weavec`.

## Version

`VERSION` contains the release version without the `v` prefix. The release tag
and archive names use the prefix:

```text
VERSION: 0.2.0
tag:     v0.2.0
```

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

## Local packaging

Build and test the matching libc variant first:

```sh
WEAVEC1_LIBC=glibc ./build.sh
./test_all.sh
bash scripts/package-linux-sdk.sh glibc v0.2.0 dist
```

For musl:

```sh
WEAVEC1_LIBC=musl ./build.sh
./test_all.sh
bash scripts/package-linux-sdk.sh musl v0.2.0 dist
```

The packaging script verifies that the compiler has no dynamic ELF interpreter,
runs a single-file compiler smoke test, runs the installed-layout multifile
driver, and writes `SDK-MANIFEST`.

## CI and publication

`.github/workflows/release.yml` builds both SDK variants for pull requests,
`master`, explicit tags, and manual dispatches.

On a successful push to `master`, the workflow creates the immutable release
selected by `VERSION` when it does not already exist. An explicit `v*` tag build
may replace assets for that same tag. Each release contains both archives and a
`SHA256SUMS` file.

Before changing `VERSION`:

1. confirm the complete glibc, musl, and macOS CI matrix is green;
2. confirm the public SDK layout remains compatible or document the break;
3. update `CHANGELOG.md` and this document when the package contract changes;
4. update the `weavec` SDK pin only after the release assets and checksums exist.
