#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# weavec-bootstrap-cat — combine multiple .weave programs and lower to WIR.
#
# Usage: weavec-bootstrap-cat <output.wir> <file1.weave> [file2.weave ...]
#
# Each file must be a well-formed surface Weave program:
#   (program (name "...") (version "...") <decls...>)
#
# The script strips each outer (program ...) wrapper, removes only top-level
# name/version metadata, emits one combined program, and invokes weavec-bootstrap
# once. Every remaining top-level declaration is preserved, including the
# final declaration of each source unit.

set -euo pipefail

command_name="$(basename "$0")"
if [[ $# -lt 2 ]]; then
  echo "Usage: $command_name <output.wir> <file1.weave> [file2.weave ...]" >&2
  exit 1
fi

OUTPUT="$1"
shift
FILES=("$@")

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -n "${WEAVEC_BOOTSTRAP:-}" ]]; then
  COMPILER="$WEAVEC_BOOTSTRAP"
elif [[ -x "$SCRIPT_DIR/weavec-bootstrap" ]]; then
  # Installed SDK layout: bin/weavec-bootstrap-cat beside bin/weavec-bootstrap.
  COMPILER="$SCRIPT_DIR/weavec-bootstrap"
else
  # Source-tree layout.
  COMPILER="$SCRIPT_DIR/build/weavec-bootstrap"
fi

if [[ ! -x "$COMPILER" ]]; then
  echo "$command_name: compiler not found at $COMPILER" >&2
  exit 1
fi

EXTRACT=""
for candidate in \
  "$SCRIPT_DIR/scripts/extract_program_decls.py" \
  "$SCRIPT_DIR/extract_program_decls.py"
do
  if [[ -f "$candidate" ]]; then
    EXTRACT="$candidate"
    break
  fi
done
if [[ -z "$EXTRACT" ]]; then
  echo "$command_name: declaration extractor not found" >&2
  exit 1
fi

TMP=$(mktemp /tmp/weavec-bootstrap-cat.XXXXXX)
trap 'rm -f "$TMP"' EXIT

{
  echo "(program"
  echo "  (name \"combined\")"
  echo "  (version \"0.1\")"

  for f in "${FILES[@]}"; do
    python3 "$EXTRACT" "$f"
  done

  echo ")"
} > "$TMP"

if [[ -n "${WEAVEC_BOOTSTRAP_CAT_SOURCE:-}" ]]; then
  cp "$TMP" "$WEAVEC_BOOTSTRAP_CAT_SOURCE"
fi

exec "$COMPILER" "$TMP" "$OUTPUT"
