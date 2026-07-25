#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Audit the frozen weavec-bootstrap source, test, and parser SDK boundaries."""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import TypeAlias


ROOT = Path(__file__).resolve().parents[1]
SRC_DIR = ROOT / "src"
TEST_DIR = ROOT / "test"
BUILD_SCRIPT = ROOT / "build.sh"
MANIFEST = TEST_DIR / "manifest.txt"
EXPORTS_FILE = ROOT / "PARSER_SDK_EXPORTS"
DEFAULT_REPORT = ROOT / "build" / "audit" / "weavec-bootstrap.json"
PARSER_MODULES = {"sexpr_tokens", "sexpr_tree", "sexpr_lexer", "sexpr_parser"}
CALL_FORMS = {"call_bool", "call_i32", "call_i64", "call_ptr", "call_void"}
MODULE_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
TEST_RE = re.compile(r"^[0-9]{2}_[A-Za-z0-9_]+$")
CORE_VERSION_RE = re.compile(r"^\s*\(core-version\s+([0-9]+)\)\s*$")


@dataclass(frozen=True)
class StringLiteral:
    value: str


SExpr: TypeAlias = str | StringLiteral | list["SExpr"]


class ParseError(ValueError):
    pass


def parse_build_modules() -> tuple[list[str], list[str]]:
    modules: list[str] = []
    errors: list[str] = []
    in_modules = False
    closed = False

    for lineno, line in enumerate(BUILD_SCRIPT.read_text(encoding="utf-8").splitlines(), 1):
        stripped = line.strip()
        if not in_modules:
            if stripped == "MODULES=(":
                in_modules = True
            continue
        if stripped == ")":
            closed = True
            break
        if not stripped or stripped.startswith("#"):
            continue
        if not MODULE_RE.fullmatch(stripped):
            errors.append(f"build.sh:{lineno}: invalid MODULES entry `{stripped}`")
            continue
        modules.append(stripped)

    if not in_modules:
        errors.append("build.sh: missing MODULES array")
    elif not closed:
        errors.append("build.sh: unterminated MODULES array")

    seen: set[str] = set()
    for module in modules:
        if module in seen:
            errors.append(f"build.sh: duplicate MODULES entry `{module}`")
        seen.add(module)
    return modules, errors


def core_versions(path: Path) -> list[str]:
    return [
        match.group(1)
        for line in path.read_text(encoding="utf-8").splitlines()
        if (match := CORE_VERSION_RE.match(line)) is not None
    ]


def check_source_inventory(modules: list[str]) -> list[str]:
    errors: list[str] = []
    expected = set(modules)
    actual = {path.stem for path in SRC_DIR.glob("*.wir")}

    for name in sorted(expected - actual):
        errors.append(f"build.sh: listed source is missing: src/{name}.wir")
    for name in sorted(actual - expected):
        errors.append(f"src/{name}.wir: source is not listed in build.sh MODULES")

    for path in sorted(SRC_DIR.glob("*.wir")):
        versions = core_versions(path)
        if versions != ["2"]:
            rendered = ", ".join(versions) if versions else "none"
            errors.append(
                f"{path.relative_to(ROOT)}: expected exactly one core version 2, found {rendered}"
            )
        if "(core-version 1)" in path.read_text(encoding="utf-8"):
            errors.append(f"{path.relative_to(ROOT)}: residual WIR v1 marker")

    lower = (SRC_DIR / "surface_lower.wir").read_text(encoding="utf-8")
    marker = re.compile(
        r"\(let\s+core_version_num\s+i64.*?"
        r"\(call_i32\s+node_int\).*?"
        r"\(const_i64\s+2\)\)\)",
        re.S,
    )
    if marker.search(lower) is None:
        errors.append("src/surface_lower.wir: generated core version is not 2")

    return errors


def parse_manifest() -> tuple[dict[str, int], list[str]]:
    cases: dict[str, int] = {}
    errors: list[str] = []
    if not MANIFEST.is_file():
        return cases, ["test/manifest.txt: file is missing"]

    for lineno, line in enumerate(MANIFEST.read_text(encoding="utf-8").splitlines(), 1):
        stripped = line.split("#", 1)[0].strip()
        if not stripped:
            continue
        parts = stripped.split()
        if len(parts) != 3:
            errors.append(
                f"test/manifest.txt:{lineno}: expected `pass <name> <exit_code>`"
            )
            continue
        kind, name, exit_text = parts
        if kind != "pass":
            errors.append(f"test/manifest.txt:{lineno}: unsupported case kind `{kind}`")
        if not TEST_RE.fullmatch(name):
            errors.append(f"test/manifest.txt:{lineno}: invalid test name `{name}`")
        if name in cases:
            errors.append(f"test/manifest.txt:{lineno}: duplicate case `{name}`")
            continue
        try:
            exit_code = int(exit_text)
        except ValueError:
            errors.append(f"test/manifest.txt:{lineno}: exit code is not an integer")
            continue
        if not 0 <= exit_code <= 255:
            errors.append(f"test/manifest.txt:{lineno}: exit code is outside 0..255")
        cases[name] = exit_code

    if not cases:
        errors.append("test/manifest.txt: no cases found")
    return cases, errors


def check_test_inventory(cases: dict[str, int]) -> list[str]:
    errors: list[str] = []
    manifest_names = set(cases)
    sources = {path.stem for path in TEST_DIR.glob("*.weave")}
    goldens = {
        path.name.removesuffix(".expected.wir")
        for path in TEST_DIR.glob("*.expected.wir")
    }

    for name in sorted(manifest_names - sources):
        errors.append(f"test/manifest.txt: source is missing: test/{name}.weave")
    for name in sorted(sources - manifest_names):
        errors.append(f"test/{name}.weave: source is not listed in the manifest")
    for name in sorted(manifest_names - goldens):
        errors.append(f"test/manifest.txt: golden is missing: test/{name}.expected.wir")
    for name in sorted(goldens - manifest_names):
        errors.append(f"test/{name}.expected.wir: golden is not listed in the manifest")

    for path in sorted(TEST_DIR.glob("*.expected.wir")):
        versions = core_versions(path)
        if versions != ["2"]:
            rendered = ", ".join(versions) if versions else "none"
            errors.append(
                f"{path.relative_to(ROOT)}: expected exactly one core version 2, found {rendered}"
            )
        if "(core-version 1)" in path.read_text(encoding="utf-8"):
            errors.append(f"{path.relative_to(ROOT)}: residual WIR v1 marker")
    return errors


def read_exports() -> tuple[set[str], list[str]]:
    exports: set[str] = set()
    errors: list[str] = []
    if not EXPORTS_FILE.is_file():
        return exports, ["PARSER_SDK_EXPORTS: file is missing"]

    for lineno, line in enumerate(EXPORTS_FILE.read_text(encoding="utf-8").splitlines(), 1):
        symbol = line.split("#", 1)[0].strip()
        if not symbol:
            continue
        if not MODULE_RE.fullmatch(symbol):
            errors.append(f"PARSER_SDK_EXPORTS:{lineno}: invalid symbol `{symbol}`")
            continue
        if symbol in exports:
            errors.append(f"PARSER_SDK_EXPORTS:{lineno}: duplicate symbol `{symbol}`")
        exports.add(symbol)
    if not exports:
        errors.append("PARSER_SDK_EXPORTS: no exports found")
    return exports, errors


def tokenize(text: str, path: Path) -> list[str | StringLiteral]:
    tokens: list[str | StringLiteral] = []
    index = 0
    line = 1
    while index < len(text):
        ch = text[index]
        if ch in " \t\r":
            index += 1
            continue
        if ch == "\n":
            line += 1
            index += 1
            continue
        if ch == ";":
            newline = text.find("\n", index)
            if newline == -1:
                break
            index = newline
            continue
        if ch in "()":
            tokens.append(ch)
            index += 1
            continue
        if ch == '"':
            start_line = line
            index += 1
            chars: list[str] = []
            while index < len(text):
                ch = text[index]
                if ch == '"':
                    index += 1
                    tokens.append(StringLiteral("".join(chars)))
                    break
                if ch == "\\":
                    index += 1
                    if index >= len(text):
                        raise ParseError(f"{path}:{start_line}: unterminated string escape")
                    chars.extend(("\\", text[index]))
                    index += 1
                    continue
                if ch == "\n":
                    line += 1
                chars.append(ch)
                index += 1
            else:
                raise ParseError(f"{path}:{start_line}: unterminated string literal")
            continue

        start = index
        while index < len(text) and text[index] not in "()\"; \t\r\n":
            index += 1
        if start == index:
            raise ParseError(f"{path}:{line}: unexpected byte {text[index]!r}")
        tokens.append(text[start:index])
    return tokens


def parse_forms(tokens: list[str | StringLiteral], path: Path) -> list[SExpr]:
    forms: list[SExpr] = []
    index = 0

    def parse_one() -> SExpr:
        nonlocal index
        if index >= len(tokens):
            raise ParseError(f"{path}: unexpected end of file")
        token = tokens[index]
        index += 1
        if token == "(":
            result: list[SExpr] = []
            while True:
                if index >= len(tokens):
                    raise ParseError(f"{path}: unterminated list")
                if tokens[index] == ")":
                    index += 1
                    return result
                result.append(parse_one())
        if token == ")":
            raise ParseError(f"{path}: unexpected `)`")
        return token

    while index < len(tokens):
        forms.append(parse_one())
    return forms


def walk(node: SExpr):
    yield node
    if isinstance(node, list):
        for child in node:
            yield from walk(child)


def collect_declarations(
    forms_by_file: dict[Path, list[SExpr]],
) -> tuple[dict[str, tuple[Path, list[SExpr]]], set[str], list[str]]:
    functions: dict[str, tuple[Path, list[SExpr]]] = {}
    externs: set[str] = set()
    errors: list[str] = []

    for path, forms in forms_by_file.items():
        for form in forms:
            for node in walk(form):
                if not isinstance(node, list) or len(node) < 2:
                    continue
                head, name = node[0], node[1]
                if head not in {"fn", "extern"} or not isinstance(name, str):
                    continue
                if head == "extern":
                    externs.add(name)
                    continue
                previous = functions.get(name)
                if previous is not None:
                    errors.append(
                        f"duplicate function `{name}` in {path.relative_to(ROOT)} and "
                        f"{previous[0].relative_to(ROOT)}"
                    )
                    continue
                functions[name] = (path, node)
    return functions, externs, errors


def direct_calls(function: list[SExpr]) -> set[str]:
    calls: set[str] = set()
    for node in walk(function):
        if not isinstance(node, list) or len(node) < 2:
            continue
        head, target = node[0], node[1]
        if head in CALL_FORMS and isinstance(target, str):
            calls.add(target)
    return calls


def check_reachability(exports: set[str], report_path: Path) -> list[str]:
    errors: list[str] = []
    forms_by_file: dict[Path, list[SExpr]] = {}
    for path in sorted(SRC_DIR.glob("*.wir")):
        try:
            forms_by_file[path] = parse_forms(
                tokenize(path.read_text(encoding="utf-8"), path), path
            )
        except (OSError, UnicodeError, ParseError) as exc:
            errors.append(str(exc))

    functions, externs, declaration_errors = collect_declarations(forms_by_file)
    errors.extend(declaration_errors)

    roots = {"main"} | exports
    for root in sorted(roots - functions.keys()):
        errors.append(f"missing reachability root `{root}`")
    for name in sorted(exports & functions.keys()):
        module = functions[name][0].stem
        if module not in PARSER_MODULES:
            errors.append(
                f"PARSER_SDK_EXPORTS: `{name}` is defined outside parser modules in {module}"
            )

    graph = {name: direct_calls(node) for name, (_, node) in functions.items()}
    unresolved: dict[str, list[str]] = {}
    for caller, targets in graph.items():
        missing = sorted(targets - functions.keys() - externs)
        if missing:
            unresolved[caller] = missing
            errors.extend(f"{caller}: unresolved call target `{target}`" for target in missing)

    reachable: set[str] = set()
    pending = list(sorted(roots & functions.keys()))
    while pending:
        name = pending.pop()
        if name in reachable:
            continue
        reachable.add(name)
        pending.extend(sorted((graph[name] & functions.keys()) - reachable))

    unreachable = sorted(functions.keys() - reachable)
    for name in unreachable:
        errors.append(
            f"{functions[name][0].relative_to(ROOT)}: unreachable source function `{name}`"
        )

    called = set().union(*graph.values()) if graph else set()
    unused_externs = sorted(externs - called)
    for name in unused_externs:
        errors.append(f"unused source extern `{name}`")

    report = {
        "format": "weavec-bootstrap-audit-v1",
        "roots": sorted(roots),
        "parser_exports": sorted(exports),
        "source_files": len(forms_by_file),
        "function_count": len(functions),
        "reachable_count": len(reachable),
        "extern_count": len(externs),
        "unreachable": unreachable,
        "unused_externs": unused_externs,
        "unresolved_calls": unresolved,
        "functions": [
            {
                "name": name,
                "file": str(path.relative_to(ROOT)),
                "reachable": name in reachable,
                "calls": sorted(graph[name]),
            }
            for name, (path, _) in sorted(functions.items())
        ],
    }
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()
    report = args.report if args.report.is_absolute() else ROOT / args.report

    modules, errors = parse_build_modules()
    errors.extend(check_source_inventory(modules))
    cases, manifest_errors = parse_manifest()
    errors.extend(manifest_errors)
    errors.extend(check_test_inventory(cases))
    exports, export_errors = read_exports()
    errors.extend(export_errors)
    errors.extend(check_reachability(exports, report))

    if errors:
        for error in errors:
            print(error)
        print(f"audit report: {report.relative_to(ROOT)}")
        return 1

    data = json.loads(report.read_text(encoding="utf-8"))
    print(
        "Bootstrap audit passed: "
        f"{data['reachable_count']}/{data['function_count']} functions reachable; "
        f"{data['extern_count']} externs used; "
        f"{len(cases)} manifest cases; "
        f"{len(exports)} parser SDK exports."
    )
    print(f"audit report: {report.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
