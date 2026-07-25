#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Apply the reviewed fixed-signature output wrapper change exactly once."""

from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{path}: expected one replacement target, found {count}")
    path.write_text(text.replace(old, new), encoding="utf-8")


def patch_build() -> None:
    path = ROOT / "build.sh"
    replace_once(
        path,
        'SEXPR_LIBRARY="$BUILD_DIR/libweave-sexpr.bc"\nSTACK_SIZE="0x1000000"\n',
        'SEXPR_LIBRARY="$BUILD_DIR/libweave-sexpr.bc"\n'
        'PORTABLE_RUNTIME_C="$WEAVEC_BOOTSTRAP_DIR/runtime/portable.c"\n'
        'STACK_SIZE="0x1000000"\n',
    )

    replace_once(
        path,
        '''link_with_sdk() {
  local object="$BUILD_DIR/weavec-bootstrap.o"
  clang -Wno-override-module -O2 -c "$BUILD_DIR/weavec-bootstrap.bc" -o "$object"

  log "linking static weavec-bootstrap executable ($WEAVEC1_LIBC)"
  case "$WEAVEC1_LIBC" in
    glibc)
      clang -static "$object" "$RUNTIME_LIBRARY" \\
        -Wl,-z,stack-size="$STACK_SIZE" \\
        -o "$BUILD_DIR/weavec-bootstrap"
      ;;
    musl)
      require_tool musl-gcc
      musl-gcc -static "$object" "$RUNTIME_LIBRARY" \\
        -Wl,-z,stack-size="$STACK_SIZE" \\
        -o "$BUILD_DIR/weavec-bootstrap"
      ;;
  esac
}
''',
        '''link_with_sdk() {
  local object="$BUILD_DIR/weavec-bootstrap.o"
  local portable_object="$BUILD_DIR/weavec-bootstrap-portable.o"
  clang -Wno-override-module -O2 -c "$BUILD_DIR/weavec-bootstrap.bc" -o "$object"

  log "linking static weavec-bootstrap executable ($WEAVEC1_LIBC)"
  case "$WEAVEC1_LIBC" in
    glibc)
      clang -O2 -c "$PORTABLE_RUNTIME_C" -o "$portable_object"
      clang -static "$object" "$portable_object" "$RUNTIME_LIBRARY" \\
        -Wl,-z,stack-size="$STACK_SIZE" \\
        -o "$BUILD_DIR/weavec-bootstrap"
      ;;
    musl)
      require_tool musl-gcc
      musl-gcc -O2 -c "$PORTABLE_RUNTIME_C" -o "$portable_object"
      musl-gcc -static "$object" "$portable_object" "$RUNTIME_LIBRARY" \\
        -Wl,-z,stack-size="$STACK_SIZE" \\
        -o "$BUILD_DIR/weavec-bootstrap"
      ;;
  esac
}
''',
    )

    replace_once(
        path,
        '''link_with_source() {
  log "linking weavec-bootstrap with source runtime fallback"
  if [[ "$(uname -s)" == Darwin ]]; then
    clang "$BUILD_DIR/weavec-bootstrap.bc" "$RUNTIME_C" \\
      -Wl,-stack_size,"$STACK_SIZE" \\
      -o "$BUILD_DIR/weavec-bootstrap"
  else
    clang "$BUILD_DIR/weavec-bootstrap.bc" "$RUNTIME_C" \\
      -Wl,-z,stack-size="$STACK_SIZE" \\
      -o "$BUILD_DIR/weavec-bootstrap"
  fi
}
''',
        '''link_with_source() {
  log "linking weavec-bootstrap with source runtime fallback"
  if [[ "$(uname -s)" == Darwin ]]; then
    clang "$BUILD_DIR/weavec-bootstrap.bc" "$RUNTIME_C" "$PORTABLE_RUNTIME_C" \\
      -Wl,-stack_size,"$STACK_SIZE" \\
      -o "$BUILD_DIR/weavec-bootstrap"
  else
    clang "$BUILD_DIR/weavec-bootstrap.bc" "$RUNTIME_C" "$PORTABLE_RUNTIME_C" \\
      -Wl,-z,stack-size="$STACK_SIZE" \\
      -o "$BUILD_DIR/weavec-bootstrap"
  fi
}
''',
    )

    replace_once(
        path,
        '''  require_tool llvm-as
  require_tool llvm-link
  ensure_dependencies
''',
        '''  require_tool llvm-as
  require_tool llvm-link
  [[ -f "$PORTABLE_RUNTIME_C" ]] || \\
    fail "portable runtime missing: $PORTABLE_RUNTIME_C"
  ensure_dependencies
''',
    )


def patch_driver() -> None:
    path = ROOT / "src" / "driver.wir"
    replace_once(
        path,
        '''    ; External file I/O
    (extern open (params (path ptr) (flags i32) (mode i32)) (returns i32))
    (extern close (params (fd i32)) (returns i32))
''',
        '''    ; External file I/O. Output creation uses a non-variadic runtime
    ; wrapper so the mode argument follows one ABI on every supported host.
    (extern open (params (path ptr) (flags i32) (mode i32)) (returns i32))
    (extern weave_rt_open_write_trunc
      (params (path ptr) (mode i32))
      (returns i32))
    (extern close (params (fd i32)) (returns i32))
''',
    )
    replace_once(
        path,
        '''        ; 6. Open output file (O_WRONLY | O_CREAT | O_TRUNC = 1 | 64 | 512 = 577, mode 0644 = 420)
        (let out_fd i32 (call_i32 open (param_get output_path) (const_i32 577) (const_i32 420)))
''',
        '''        ; 6. Open output file through the fixed-signature wrapper.
        ; mode 0644 = 420.
        (let out_fd i32
          (call_i32 weave_rt_open_write_trunc
            (param_get output_path)
            (const_i32 420)))
''',
    )


def patch_tests() -> None:
    path = ROOT / "test_all.sh"
    replace_once(
        path,
        '''  if [[ ! -s "$wir_file" ]]; then
    fail "$name: frontend produced empty WIR"
    return
  fi

  if ! cmp -s "$expected_wir" "$wir_file"; then
''',
        '''  if [[ ! -s "$wir_file" ]]; then
    fail "$name: frontend produced empty WIR"
    return
  fi
  if [[ ! -r "$wir_file" ]]; then
    fail "$name: frontend output is not owner-readable"
    return
  fi

  if ! cmp -s "$expected_wir" "$wir_file"; then
''',
    )


def create_runtime() -> None:
    path = ROOT / "runtime" / "portable.c"
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        raise RuntimeError(f"{path}: already exists")
    path.write_text(
        '''// SPDX-License-Identifier: Apache-2.0
// Fixed-signature host wrappers used by the bootstrap frontend.

#define _POSIX_C_SOURCE 200809L

#include <fcntl.h>

int weave_rt_open_write_trunc(const char *path, int mode)
{
    return open(path, O_WRONLY | O_CREAT | O_TRUNC, mode);
}
''',
        encoding="utf-8",
    )


def main() -> None:
    patch_build()
    patch_driver()
    patch_tests()
    create_runtime()


if __name__ == "__main__":
    main()
