#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Apply reviewed dead-code removal and compact-golden audit fixes exactly once."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FUNCTION_REMOVALS = {
    ROOT / "src" / "surface_lower.wir": {"copy_node"},
    ROOT / "src" / "surface_struct.wir": {"link4"},
    ROOT / "src" / "sexpr_print.wir": {"print_indent"},
}
EXTERN_REMOVALS = {"atoi", "snprintf", "strlen"}
DECL_RE = re.compile(r"^\s*\((fn|extern)\s+([A-Za-z_][A-Za-z0-9_-]*)\b")


def paren_delta(line: str) -> int:
    delta = 0
    in_string = False
    escaped = False
    for ch in line:
        if not in_string and ch == ";":
            break
        if in_string:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                in_string = False
            continue
        if ch == '"':
            in_string = True
        elif ch == "(":
            delta += 1
        elif ch == ")":
            delta -= 1
    return delta


def attached_comment_start(lines: list[str], decl_index: int) -> int:
    cursor = decl_index - 1
    while cursor >= 0 and lines[cursor].lstrip().startswith(";"):
        cursor -= 1
    if cursor >= 0 and not lines[cursor].strip():
        return cursor
    return cursor + 1


def remove_declarations(path: Path, functions: set[str]) -> tuple[set[str], set[str]]:
    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    ranges: list[tuple[int, int, str, str, str]] = []

    for index, line in enumerate(lines):
        match = DECL_RE.match(line.rstrip("\n"))
        if not match:
            continue
        kind, name = match.groups()
        if not ((kind == "fn" and name in functions) or (kind == "extern" and name in EXTERN_REMOVALS)):
            continue

        depth = 0
        replacement = ""
        for end in range(index, len(lines)):
            depth += paren_delta(lines[end])
            if depth <= 0:
                replacement = ")" * (-depth) + "\n" if depth < 0 else ""
                end += 1
                break
        else:
            raise RuntimeError(f"{path}: unterminated {kind} declaration {name}")

        start = attached_comment_start(lines, index) if kind == "fn" else index
        ranges.append((start, end, kind, name, replacement))

    found_functions = {name for _, _, kind, name, _ in ranges if kind == "fn"}
    found_externs = {name for _, _, kind, name, _ in ranges if kind == "extern"}

    for start, end, _, _, replacement in sorted(ranges, reverse=True):
        lines[start:end] = [replacement] if replacement else []

    while any(
        lines[index].strip() == "" and lines[index - 1].strip() == ""
        for index in range(1, len(lines))
    ):
        lines = [
            line
            for index, line in enumerate(lines)
            if not (
                index > 0
                and line.strip() == ""
                and lines[index - 1].strip() == ""
            )
        ]

    path.write_text("".join(lines), encoding="utf-8")
    return found_functions, found_externs


def update_audit_script() -> None:
    path = ROOT / "scripts" / "audit_bootstrap.py"
    text = path.read_text(encoding="utf-8")

    old_regex = 'CORE_VERSION_RE = re.compile(r"^\\s*\\(core-version\\s+([0-9]+)\\)\\s*$")\n'
    new_regex = (
        old_regex
        + 'CORE_VERSION_ANY_RE = re.compile(r"\\(core-version\\s+([0-9]+)\\)")\n'
    )
    if "CORE_VERSION_ANY_RE" not in text:
        if text.count(old_regex) != 1:
            raise RuntimeError("audit script core-version regex anchor changed")
        text = text.replace(old_regex, new_regex)

    old_block = '''    for path in sorted(TEST_DIR.glob("*.expected.wir")):\n        versions = core_versions(path)\n        if versions != ["2"]:\n            rendered = ", ".join(versions) if versions else "none"\n            errors.append(\n                f"{path.relative_to(ROOT)}: expected exactly one core version 2, found {rendered}"\n            )\n        if "(core-version 1)" in path.read_text(encoding="utf-8"):\n            errors.append(f"{path.relative_to(ROOT)}: residual WIR v1 marker")\n'''
    new_block = '''    for path in sorted(TEST_DIR.glob("*.expected.wir")):\n        text = path.read_text(encoding="utf-8")\n        versions = CORE_VERSION_ANY_RE.findall(text)\n        if versions != ["2"]:\n            rendered = ", ".join(versions) if versions else "none"\n            errors.append(\n                f"{path.relative_to(ROOT)}: expected exactly one core version 2, found {rendered}"\n            )\n        if "(core-version 1)" in text:\n            errors.append(f"{path.relative_to(ROOT)}: residual WIR v1 marker")\n'''
    if old_block in text:
        text = text.replace(old_block, new_block)
    elif new_block not in text:
        raise RuntimeError("audit script compact-golden block changed")

    path.write_text(text, encoding="utf-8")


def main() -> None:
    found_functions: set[str] = set()
    found_externs: set[str] = set()

    for path in sorted(ROOT.joinpath("src").glob("*.wir")):
        functions = FUNCTION_REMOVALS.get(path, set())
        found_fn, found_ext = remove_declarations(path, functions)
        found_functions.update(found_fn)
        found_externs.update(found_ext)

    expected_functions = set().union(*FUNCTION_REMOVALS.values())
    if found_functions != expected_functions:
        raise RuntimeError(
            f"function cleanup mismatch: expected {sorted(expected_functions)}, found {sorted(found_functions)}"
        )
    if found_externs != EXTERN_REMOVALS:
        raise RuntimeError(
            f"extern cleanup mismatch: expected {sorted(EXTERN_REMOVALS)}, found {sorted(found_externs)}"
        )

    update_audit_script()


if __name__ == "__main__":
    main()
