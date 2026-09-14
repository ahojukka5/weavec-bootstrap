#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Extract top-level declarations from a surface Weave program.

Used by weavec-bootstrap-cat to strip one outer ``(program ...)`` wrapper and
emit every remaining top-level declaration, including the last form before the
program's closing parenthesis.

The previous inline combiner walked bytes and dropped ``(name ...)`` /
``(version ...)`` at every cursor position. Nested forms such as
``(params (name i32))`` could be treated as metadata, and a matching failure
could discard the final declaration of a source unit.
"""

from __future__ import print_function

import argparse
import re
import sys
from pathlib import Path


METADATA = re.compile(r"^\(\s*(name|version)\b")


class ExtractError(ValueError):
    pass


def skip_comment(text, index):
    newline = text.find("\n", index)
    return len(text) if newline == -1 else newline


def skip_space_and_comments(text, index):
    n = len(text)
    while index < n:
        ch = text[index]
        if ch in " \t\r\n":
            index += 1
            continue
        if ch == ";":
            index = skip_comment(text, index)
            continue
        break
    return index


def scan_string(text, index):
    """Return the index after a string that starts at ``index`` (a quote)."""
    n = len(text)
    index += 1
    while index < n:
        ch = text[index]
        if ch == "\\":
            if index + 1 >= n:
                raise ExtractError("unterminated string escape")
            index += 2
            continue
        if ch == '"':
            return index + 1
        index += 1
    raise ExtractError("unterminated string literal")


def scan_list(text, index):
    """Return the index after a list that starts at ``index`` (a '(')."""
    n = len(text)
    depth = 0
    while index < n:
        ch = text[index]
        if ch == '"':
            index = scan_string(text, index)
            continue
        if ch == ";":
            index = skip_comment(text, index)
            continue
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            index += 1
            if depth == 0:
                return index
            continue
        index += 1
    raise ExtractError("unclosed list")


def find_program(text):
    """Return (inner_start, inner_end) for the outer (program ...) form."""
    n = len(text)
    index = 0
    while index < n:
        ch = text[index]
        if ch == ";":
            index = skip_comment(text, index)
            continue
        if ch == '"':
            index = scan_string(text, index)
            continue
        if ch == "(" and text.startswith("program", index + 1):
            end = index + 1 + len("program")
            if end == n or not (text[end].isalnum() or text[end] in "_-"):
                inner_start = index + 1
                inner_end = scan_list(text, index) - 1
                return inner_start, inner_end
        index += 1
    raise ExtractError("missing top-level (program ...) form")


def top_level_forms(inner):
    forms = []
    index = 0
    n = len(inner)
    while True:
        index = skip_space_and_comments(inner, index)
        if index >= n:
            return forms
        if inner.startswith("program", index):
            end = index + len("program")
            if end == n or not (inner[end].isalnum() or inner[end] in "_-"):
                index = end
                continue
        if inner[index] != "(":
            raise ExtractError(
                "expected a list at top level, found {0!r}".format(inner[index])
            )
        end = scan_list(inner, index)
        forms.append(inner[index:end])
        index = end


def extract_declarations(text):
    inner_start, inner_end = find_program(text)
    inner = text[inner_start:inner_end]
    kept = []
    for form in top_level_forms(inner):
        if METADATA.match(form) is not None:
            continue
        kept.append(form)
    if not kept:
        return ""
    return "\n" + "\n".join(kept) + "\n"


def extract_path(path):
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as exc:
        raise ExtractError("cannot read {0}: {1}".format(path, exc))
    try:
        return extract_declarations(text)
    except ExtractError as exc:
        raise ExtractError("{0}: {1}".format(path, exc))


def _self_test():
    library = """\
; comment containing (program should not win
(program
  (name "lib")
  (version "0.1")
  (fn helper
    (params (name i32))
    (returns i32)
    (do
      (return (param_get name))))
  (fn uniquely_named_tail_decl
    (params)
    (returns i32)
    (do
      (return (const_i32 7))))
)
"""
    caller = """\
(program
  (name "use")
  (version "0.1")
  (entry main)
  (fn main
    (params)
    (returns i32)
    (do
      (return (call_i32 uniquely_named_tail_decl))))
)
"""
    lib_out = extract_declarations(library)
    use_out = extract_declarations(caller)
    assert "(params (name i32))" in lib_out, lib_out
    assert lib_out.count("uniquely_named_tail_decl") == 1
    assert lib_out.rstrip().endswith(")")
    assert "(fn uniquely_named_tail_decl" in lib_out
    assert "(fn helper" in lib_out
    assert "(name " not in lib_out.replace("(params (name i32))", "")
    assert "(entry main)" in use_out
    combined = (
        '(program\n  (name "combined")\n  (version "0.1")\n'
        + lib_out
        + use_out
        + ")\n"
    )
    assert combined.count("(fn uniquely_named_tail_decl") == 1
    assert combined.count("(fn main") == 1


def main(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("path", nargs="?", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args(argv)
    if args.self_test:
        _self_test()
        print("extract_program_decls: self-test passed")
        return 0
    if args.path is None:
        parser.error("path is required unless --self-test is set")
    try:
        sys.stdout.write(extract_path(args.path))
    except ExtractError as exc:
        sys.stderr.write("weavec-bootstrap-cat: {0}\n".format(exc))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
