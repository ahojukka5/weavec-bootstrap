#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
CHECKOUT="$TMP/bootstrap"
TOOLS="$TMP/tools"
mkdir -p "$CHECKOUT/scripts" "$CHECKOUT/build" "$CHECKOUT/test" "$TOOLS"
cp "$ROOT/scripts/package-macos-sdk.sh" "$CHECKOUT/scripts/"
printf 'print("")\n' > "$CHECKOUT/scripts/extract_program_decls.py"
printf '# test\n' > "$CHECKOUT/README.md"
printf 'license\n' > "$CHECKOUT/LICENSE"
printf 'notice\n' > "$CHECKOUT/NOTICE"
printf '(program)\n' > "$CHECKOUT/test/01_return_42.weave"
printf '(program)\n' > "$CHECKOUT/test/02_return_constant.weave"

cat > "$CHECKOUT/build/weavec-bootstrap" <<'EOF'
#!/usr/bin/env bash
printf '(core-module (core-version 2) (decls))\n' > "$2"
EOF
cat > "$CHECKOUT/weavec-bootstrap-cat.sh" <<'EOF'
#!/usr/bin/env bash
printf '(core-module (core-version 2) (decls))\n' > "$1"
EOF
chmod +x "$CHECKOUT/build/weavec-bootstrap" "$CHECKOUT/weavec-bootstrap-cat.sh"

cat > "$TOOLS/uname" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in -s) echo Darwin ;; -m) echo arm64 ;; *) echo Darwin ;; esac
EOF
cat > "$TOOLS/file" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$TOOLS/otool" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
binary="${*: -1}"
printf '%s:\n' "$binary"
printf '\t/usr/lib/libSystem.B.dylib (compatibility version 1.0.0, current version 1.0.0)\n'
EOF
cat > "$TOOLS/strip" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$TOOLS"/*

(
  cd "$CHECKOUT"
  PATH="$TOOLS:$PATH" scripts/package-macos-sdk.sh v0.3.1 dist
)
archive="$CHECKOUT/dist/weavec-bootstrap-v0.3.1-macos-arm64.tar.gz"
[[ -s "$archive" ]]
for path in \
  bin/weavec-bootstrap \
  bin/weavec-bootstrap-cat \
  bin/extract_program_decls.py \
  SDK-MANIFEST; do
  tar -tzf "$archive" | grep -Fq \
    "weavec-bootstrap-v0.3.1-macos-arm64/$path"
done
if tar -tzf "$archive" | grep -F '/lib/'; then
  printf 'package-macos-sdk: leftover parser library in archive\n' >&2
  exit 1
fi
if tar -xOf "$archive" \
  weavec-bootstrap-v0.3.1-macos-arm64/SDK-MANIFEST | grep -F parser_library; then
  printf 'package-macos-sdk: leftover parser_library in SDK-MANIFEST\n' >&2
  exit 1
fi
printf 'package-macos-sdk: bootstrap package harness passed\n'
