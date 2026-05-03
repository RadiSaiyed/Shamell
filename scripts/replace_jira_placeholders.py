#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


UNRESOLVED_PATTERNS = (
    re.compile(r"\{\{[A-Z0-9_]+\}\}"),
    re.compile(r"\b[A-Z]+-KEY-[A-Z0-9-]+\b"),
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Replace Jira placeholder tokens in CSV templates using a simple "
            "KEY=VALUE mapping file."
        ),
    )
    parser.add_argument(
        "--mapping",
        required=True,
        help="Path to a KEY=VALUE mapping file.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Do not write files; only report what would change.",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Fail if unresolved placeholder tokens remain after replacement.",
    )
    parser.add_argument(
        "files",
        nargs="+",
        help="One or more files to update in place.",
    )
    return parser.parse_args()


def load_mapping(mapping_path: Path) -> dict[str, str]:
    try:
        raw_lines = mapping_path.read_text(encoding="utf-8").splitlines()
    except FileNotFoundError as exc:
        raise SystemExit(f"missing mapping file: {mapping_path}") from exc

    mapping: dict[str, str] = {}
    for line_number, raw_line in enumerate(raw_lines, start=1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise SystemExit(
                f"invalid mapping line {line_number} in {mapping_path}: {raw_line!r}",
            )
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if not key or not value:
            raise SystemExit(
                f"invalid mapping line {line_number} in {mapping_path}: {raw_line!r}",
            )
        mapping[key] = value
        if not key.startswith("{{") and not key.endswith("}}"):
            mapping[f"{{{{{key}}}}}"] = value
    return mapping


def replace_tokens(text: str, mapping: dict[str, str]) -> tuple[str, int]:
    replaced = text
    replacement_count = 0
    for token in sorted(mapping, key=len, reverse=True):
        occurrences = replaced.count(token)
        if occurrences == 0:
            continue
        replaced = replaced.replace(token, mapping[token])
        replacement_count += occurrences
    return replaced, replacement_count


def unresolved_tokens(text: str) -> list[str]:
    matches: list[str] = []
    for pattern in UNRESOLVED_PATTERNS:
        matches.extend(match.group(0) for match in pattern.finditer(text))
    return sorted(set(matches))


def main() -> int:
    args = parse_args()
    mapping = load_mapping(Path(args.mapping))
    had_error = False

    for raw_path in args.files:
        path = Path(raw_path)
        try:
            original = path.read_text(encoding="utf-8")
        except FileNotFoundError:
            print(f"missing file: {path}", file=sys.stderr)
            had_error = True
            continue

        updated, replacement_count = replace_tokens(original, mapping)
        unresolved = unresolved_tokens(updated)

        if args.dry_run:
            print(
                f"{path}: replacements={replacement_count} "
                f"unresolved={len(unresolved)}",
            )
        else:
            if updated != original:
                path.write_text(updated, encoding="utf-8")
            print(
                f"{path}: replacements={replacement_count} "
                f"unresolved={len(unresolved)}",
            )

        if unresolved:
            print(f"{path}: unresolved placeholders: {', '.join(unresolved)}", file=sys.stderr)
            if args.check:
                had_error = True

    return 1 if had_error else 0


if __name__ == "__main__":
    raise SystemExit(main())
