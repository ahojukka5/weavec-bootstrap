#!/usr/bin/env bash
# weavefront-cat.sh — concatenate multiple .weave files into one and compile.
#
# Usage: weavefront-cat.sh <output.wir> <file1.weave> [file2.weave ...]
#
# Each file must be a well-formed surface Weave program:
#   (program (name "...") (version "...") <decls...>)
#
# The script strips the outer (program ...) wrapper from every file,
# then emits a single combined program for weavefront to compile.

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: weavefront-cat.sh <output.wir> <file1.weave> [file2.weave ...]" >&2
  exit 1
fi

OUTPUT="$1"
shift
FILES=("$@")

WEAVEFRONT="${WEAVEFRONT:-$(dirname "$0")/build/weavefront}"

if [[ ! -x "$WEAVEFRONT" ]]; then
  echo "weavefront-cat: weavefront not found at $WEAVEFRONT (run ./build.sh first)" >&2
  exit 1
fi

TMP=$(mktemp /tmp/wfcat.XXXXXX)
trap 'rm -f "$TMP"' EXIT

{
  echo "(program"
  echo "  (name \"combined\")"
  echo "  (version \"0.1\")"

  for f in "${FILES[@]}"; do
    python3 - "$f" <<'PYEOF'
# Extract declarations from a surface Weave file.
# Strips: outer (program ...) wrapper, (name ...), (version ...) metadata.
# Uses paren counting to find the boundary of the outer form.
import sys, re

with open(sys.argv[1]) as fh:
    text = fh.read()

# Find the opening (program token
m = re.search(r'\(program\b', text)
if not m:
    sys.exit(0)  # no program form, nothing to extract

# Walk forward from '(' counting depth; collect inner text
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
            inner_start = i + 1  # character after opening '('
    elif c == ')':
        depth -= 1
        if depth == 0:
            inner_end = i  # position of closing ')'
            break
    elif c == ';' and not in_string:
        # skip line comment
        while i < len(text) and text[i] != '\n':
            i += 1
        continue
    i += 1

if inner_start is None or inner_end is None:
    sys.exit(0)

inner = text[inner_start:inner_end]

# Remove "program" keyword at start (it's the first token)
inner = re.sub(r'^\s*program\b', '', inner)

# Remove metadata: (name "...") and (version "...") top-level forms
# We do this with a simple state machine to handle quoted strings.
skip_re = re.compile(r'\s*\(\s*(name|version)\s')
result = []
i = 0
while i < len(inner):
    if re.match(r'\s*\(\s*(name|version)\s', inner[i:]):
        # skip this form by counting parens
        while i < len(inner) and inner[i] != '(':
            i += 1
        d = 0
        in_s = False
        while i < len(inner):
            c = inner[i]
            if in_s:
                if c == '\\': i += 2; continue
                if c == '"': in_s = False
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

exec "$WEAVEFRONT" "$TMP" "$OUTPUT"
