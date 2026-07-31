# macOS bootstrap SDK

`weavec-bootstrap` publishes native macOS packages so ordinary final-compiler
development can consume the frozen bootstrap frontend without reconstructing the
compiler chain.

## Dependency

The macOS bootstrap build downloads and checksum-verifies the released
`weavec1 v0.3.2` package for the host architecture, or uses an already
extracted SDK directory passed through `WEAVEC1_SDK`. It never builds
`weavec0` or `weavec1` as an implicit fallback.

## Self-containment contract

macOS cannot produce a fully static executable the way the Linux glibc and
musl SDKs do (Apple's libSystem must always be linked dynamically). The
packaging script enforces the closest practical equivalent instead:
`bin/weavec-bootstrap` must depend on nothing but
`/usr/lib/libSystem.B.dylib`, verified with `otool -L`.

## Package layout

```text
weavec-bootstrap-vX.Y.Z-macos-<arm64|x86_64>/
├── bin/weavec-bootstrap
├── bin/weavec-bootstrap-cat
├── lib/libweave-sexpr.bc
├── SDK-MANIFEST
├── VERSION
├── README.md
├── LICENSE
└── NOTICE
```

The package exposes the same compiler, multifile driver, and parser-library
boundary as the Linux SDKs.

## Build and package

```sh
./build.sh
scripts/package-macos-sdk.sh vX.Y.Z
```

The packaging script verifies the compiler's only linked dependency is
`libSystem.B.dylib`, then the smoke test lowers one source and one multifile
input before creating the archive.

## Publish

Publication is automatic, same as the Linux SDKs: see
[Publication workflow](releasing.md#publication-workflow). The `build-macos`
release job builds and packages both `macos-arm64` and `macos-x86_64` on
hosted GitHub Actions runners; `publish-release` folds their archives into the
same `SHA256SUMS` used for the Linux assets.
