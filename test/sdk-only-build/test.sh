#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

CHECKOUT="$TMP/bootstrap"
SDK="$TMP/weavec1-sdk"
TOOLS="$TMP/tools"
LOG="$TMP/invocations"
mkdir -p "$CHECKOUT/runtime" "$CHECKOUT/src" "$SDK/bin" "$SDK/lib" "$TOOLS"
cp "$ROOT/build.sh" "$CHECKOUT/build.sh"
cp "$ROOT/runtime/portable.c" "$CHECKOUT/runtime/portable.c"
cp "$ROOT/src"/*.wir "$CHECKOUT/src/"
printf 'runtime archive\n' > "$SDK/lib/libweave-runtime.a"

cat > "$SDK/bin/weavec1" <<EOF
#!/usr/bin/env bash
printf 'weavec1 %s %s\n' "\$1" "\$2" >> "$LOG"
printf '; fake llvm\n' > "\$2"
EOF
chmod +x "$SDK/bin/weavec1"

cat > "$TOOLS/uname" <<'EOF'
#!/usr/bin/env bash
case "${WEAVEC1_TEST_HOST:-macos}:${1:-}" in
  macos:-s) printf 'Darwin\n' ;;
  macos:-m) printf 'arm64\n' ;;
  linux:-s) printf 'Linux\n' ;;
  linux:-m) printf 'x86_64\n' ;;
  macos:*) printf 'Darwin\n' ;;
  linux:*) printf 'Linux\n' ;;
esac
EOF

cat > "$TOOLS/llvm-link" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
output=""
while (($#)); do
  if [[ "$1" == -o ]]; then output="$2"; shift 2; else shift; fi
done
[[ -n "$output" ]]
printf 'linked bitcode\n' > "$output"
EOF

cat > "$TOOLS/clang" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
output=""
while (($#)); do
  if [[ "$1" == -o ]]; then output="$2"; shift 2; else shift; fi
done
[[ -n "$output" ]]
printf 'native output\n' > "$output"
chmod +x "$output"
EOF

cat > "$TOOLS/git" <<'EOF'
#!/usr/bin/env bash
printf 'sdk-only-build: git must not be called\n' >&2
exit 97
EOF
chmod +x "$TOOLS"/*

run_build() {
  local host="$1"
  rm -rf "$CHECKOUT/build"
  (
    cd "$CHECKOUT"
    PATH="$TOOLS:$PATH" \
    WEAVEC1_TEST_HOST="$host" \
    WEAVEC1_SDK="$SDK" \
      ./build.sh
  )
  [[ -x "$CHECKOUT/build/weavec-bootstrap" ]]
  [[ -s "$CHECKOUT/build/libweave-sexpr.bc" ]]
  grep -Fq 'WEAVE_RUNTIME_MODE=sdk' "$CHECKOUT/build/toolchain.env"
  grep -Fq "WEAVEC1_SDK=$SDK" "$CHECKOUT/build/toolchain.env"
}

: > "$LOG"
run_build macos
grep -Fq 'WEAVEC1_VERSION=v0.3.2' "$CHECKOUT/build/toolchain.env"

run_build linux
grep -Fq 'WEAVEC1_VERSION=v0.3.1' "$CHECKOUT/build/toolchain.env"

[[ "$(grep -c '^weavec1 ' "$LOG")" -eq 20 ]]
printf 'sdk-only-build: host-specific SDK boundary passed\n'
