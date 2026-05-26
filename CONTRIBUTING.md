# Contributing to weavefront

Thanks for your interest in `weavefront`. Before opening a PR or filing
an issue, please understand the very narrow scope: `weavefront` is the
**surface-language frontend** of the Weave compiler chain. It lowers
`.weave` source into the stable WIR (`.wir`) contract that
[`weavec1`](https://github.com/ahojukka5/weavec1) and `weavec2`
consume. weavefront itself is written in WIR and is compiled by
`weavec1`.

## Principles

- **The WIR contract is stable.** weavefront's output is the input to
  `weavec1` / `weavec2`. Any change to the surface → WIR lowering must
  produce WIR that the backends already accept. Don't extend WIR from
  the frontend.
- **Determinism matters.** Same `.weave` input must produce
  byte-identical `.wir` output across runs and platforms. The test
  ladder diffs `weavefront`'s output against checked-in
  `*.expected.wir` fixtures; a divergence is a regression.
- **No feature without a test.** A patch that adds or changes a
  surface form must come with a `test/NN_<name>.weave` +
  `test/NN_<name>.expected.wir` pair exercising it end-to-end through
  `./test_all.sh` (which also runs the produced WIR through `weavec1`
  and asserts the executable's exit code).
- **Keep surface close to WIR.** Surface Weave is a thin wrapper, not
  a high-level language. Don't sneak in syntax sugar, inference, or
  optimisation passes — those belong to other layers.

## What does NOT belong here

- New WIR primitives. Those go in the backends.
- High-level language features (type inference, macros, modules,
  pattern matching). weavefront is intentionally minimal.
- Anything that requires extending the C-runtime extern set admitted
  by `weavec0`. If you need a new runtime function, it goes in
  `weavec0` first, gets a tagged release, then the `WEAVEC0_TAG`
  pin in `build.sh` is bumped.
- Optimisations / code generation tweaks — the backend (`weavec1` /
  `weavec2`) does its own work; weavefront output should stay
  byte-stable.

## Workflow

1. Fork and create a feature branch.
2. Edit the relevant `src/*.wir`, add or update test fixtures under
   `test/`. Pair each new `NN_<name>.weave` with a
   `NN_<name>.expected.wir`.
3. Run `./build.sh` locally — must succeed on macOS or Linux with
   the LLVM toolchain installed.
4. Run `./test_all.sh` — full ladder must end with
   `<N> passed, 0 failed`.
5. Open a PR. CI re-runs the full ladder on Linux and macOS.

## Licensing

By submitting a contribution, you agree that your contribution is
licensed under the Apache License, Version 2.0 (see
[`LICENSE`](LICENSE)).
