#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# weavec-bootstrap-cat.sh — combine multiple .weave programs and lower to WIR.
#
# Usage: weavec-bootstrap-cat.sh <output.wir> <file1.weave> [file2.weave ...]
#
# Each file must be a well-formed surface Weave program:
#   (program (name "...") (version "...") <decls...>)
#
# The script strips each outer (program ...) wrapper, removes name/version
# metadata, emits one combined program, and invokes weavec-bootstrap once.

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: weavec-bootstrap-cat.sh <output.wir> <file1.weave> [file2.weave ...]" >&2
  exit 1
fi

OUTPUT="$1"
shift
FILES=("$@")

WEAVEC_BOOTSTRAP="${WEAVEC_BOOTSTRAP:-$(dirname "$0")/build/weavec-bootstrap}"

if [[ ! -x "$WEAVEC_BOOTSTRAP" ]]; then
  echo "weavec-bootstrap-cat: compiler not found at $WEAVEC_BOOTSTRAP (run ./build.sh first)" >&2
  exit 1
fi

TMP=$(mktemp /tmp/weavec-bootstrap-cat.XXXXXX)
trap 'rm -f "$TMP"' EXIT

{
  echo "(program"
  echo "  (name \"combined\")"
  echo "  (version \"0.1\")"

  for f in "${FILES[@]}"; do
    python3 - "$f" <<'PYEOF'
# Extract declarations from a surface Weave file.
# Strips the outer (program ...) wrapper and name/version metadata.
import re
import sys

with open(sys.argv[1]) as fh:
    text = fh.read()

m = re.search(r'\(program\b', text)
if not m:
    sys.exit(0)

pos = m.start()
depth = 0
inner_start = None
inner_end = None
i = pos
in_string = False
while i < len(text):
    c = text[i]
    if in_string:
        if c == '\\':
            i += 2
            continue
        if c == '"':
            in_string = False
    elif c == '"':
        in_string = True
    elif c == '(':
        depth += 1
        if depth == 1:
            inner_start = i + 1
    elif c == ')':
        depth -= 1
        if depth == 0:
            inner_end = i
            break
    elif c == ';':
        while i < len(text) and text[i] != '\n':
            i += 1
        continue
    i += 1

if inner_start is None or inner_end is None:
    sys.exit(0)

inner = text[inner_start:inner_end]
inner = re.sub(r'^\s*program\b', '', inner)

result = []
i = 0
while i < len(inner):
    if re.match(r'\s*\(\s*(name|version)\s', inner[i:]):
        while i < len(inner) and inner[i] != '(':
            i += 1
        d = 0
        in_s = False
        while i < len(inner):
            c = inner[i]
            if in_s:
                if c == '\\':
                    i += 2
                    continue
                if c == '"':
                    in_s = False
            elif c == '"':
                in_s = True
            elif c == '(':
                d += 1
            elif c == ')':
                d -= 1
                if d == 0:
                    i += 1
                    break
            i += 1
    else:
        result.append(inner[i])
        i += 1

print(''.join(result), end='')
PYEOF
  done

  echo ")"
} > "$TMP"

exec "$WEAVEC_BOOTSTRAP" "$TMP" "$OUTPUT"
