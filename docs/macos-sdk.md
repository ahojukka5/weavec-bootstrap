# macOS bootstrap SDK

`weavec-bootstrap` publishes native macOS packages so ordinary final-compiler
development can consume the frozen bootstrap frontend without reconstructing the
compiler chain.

## Dependency

The macOS bootstrap build downloads and checksum-verifies the released
`weavec1 v0.3.2` package for the host architecture, or uses an already
extracted SDK directory passed through `WEAVEC1_SDK`. It never builds
`weavec0` or `weavec1` as an implicit fallback.

Linux continues to use the unchanged `weavec1 v0.3.1` SDK. The build selects the
Stage 1 release by host; `WEAVEC1_VERSION` remains an explicit override.

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

## Publish without GitHub Actions

From a clean target-Mac checkout containing a qualified build, run:

```sh
scripts/publish-macos-sdk.sh
```

The publisher derives `v<VERSION>`, builds the native archive, creates or updates
the matching GitHub Release, preserves checksums for existing assets, and
verifies that the archive and `SHA256SUMS` are visible.

Version `v0.3.1` adds macOS bootstrap packages only. The unchanged Linux
bootstrap SDK remains `v0.3.0`; downstream `weavec` builds select the dependency
version by host.

The release workflow may publish the same assets when GitHub Actions are
available, but it is optional and is not part of the manual development path.
