#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Apply the reviewed one-time migration from WIR v1 to WIR v2."""

from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SRC_DIR = ROOT / "src"
TEST_DIR = ROOT / "test"


def replace_exact(path: Path, old: str, new: str, expected: int | None = None) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if expected is not None and count != expected:
        raise RuntimeError(f"{path}: expected {expected} occurrence(s) of {old!r}, found {count}")
    if count:
        path.write_text(text.replace(old, new), encoding="utf-8")


def migrate_wir_files() -> None:
    production = sorted(SRC_DIR.glob("*.wir"))
    goldens = sorted(TEST_DIR.glob("*.expected.wir"))
    if not production:
        raise RuntimeError("no production WIR modules found")
    if not goldens:
        raise RuntimeError("no WIR goldens found")

    for path in production + goldens:
        text = path.read_text(encoding="utf-8")
        count = text.count("(core-version 1)")
        if count < 1:
            raise RuntimeError(f"{path}: no WIR v1 marker found")
        migrated = text.replace("(core-version 1)", "(core-version 2)")
        if "(core-version 1)" in migrated:
            raise RuntimeError(f"{path}: WIR v1 marker remains after migration")
        path.write_text(migrated, encoding="utf-8")

    lower = SRC_DIR / "surface_lower.wir"
    old = """        (let core_version_num i64
          (call_i64 tree_append_node
            (local_get dest_tree)
            (call_i32 node_int)
            (const_i64 0)
            (const_i64 1)
            (const_i64 -1)
            (const_i64 -1)
            (const_i64 1)))"""
    new = """        (let core_version_num i64
          (call_i64 tree_append_node
            (local_get dest_tree)
            (call_i32 node_int)
            (const_i64 0)
            (const_i64 1)
            (const_i64 -1)
            (const_i64 -1)
            (const_i64 2)))"""
    replace_exact(lower, old, new, expected=1)


def migrate_dependency_pins() -> None:
    build = ROOT / "build.sh"
    replace_exact(build, "v0.2.0", "v0.3.1", expected=3)
    replace_exact(build, "v0.2.1", "v0.4.0", expected=2)

    ci = ROOT / ".github" / "workflows" / "ci.yml"
    replace_exact(ci, "v0.2.0", "v0.3.1", expected=2)
    replace_exact(ci, "v0.2.1", "v0.4.0", expected=1)

    release = ROOT / ".github" / "workflows" / "release.yml"
    replace_exact(release, "v0.2.0", "v0.3.1", expected=1)


def main() -> None:
    migrate_wir_files()
    migrate_dependency_pins()


if __name__ == "__main__":
    main()
