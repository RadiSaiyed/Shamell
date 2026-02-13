#!/usr/bin/env python3
from __future__ import annotations

import os
import sys
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Violation:
    kind: str
    path: Path
    detail: str


REPO_ROOT = Path(__file__).resolve().parents[1]

# Defensive cleanup guardrails: these legacy/non-product verticals must not
# reappear in the codebase. We keep this list explicit (vs. "allow-list only")
# so adding new services remains possible without constantly updating checks.
BANNED_PATHS = [
    "NonWeChat",
    "apps/monolith",
    "apps/taxi",
    "apps/courier",
    "apps/stays",
    "apps/carrental",
    "apps/commerce",
    "apps/agriculture",
    "apps/livestock",
    "apps/building",
    "apps/food",
]

# We also ban legacy route prefixes from appearing in runtime service code
# (tests intentionally assert 404s for some of these).
BANNED_ROUTE_PREFIXES = [
    "/courier",
    "/stays",
    "/carrental",
    "/commerce",
    "/agriculture",
    "/livestock",
    "/building",
    "/pms",
    "/payments-debug",
]

SEARCH_ROOTS = [
    "apps",
    "clients/shamell_flutter/lib",
]

SEARCH_SUFFIXES = {
    ".py",
    ".dart",
    ".html",
    ".md",
    ".yml",
    ".yaml",
    ".json",
    ".toml",
    ".txt",
}

IGNORE_DIRS = {
    ".git",
    ".venv",
    ".venv311",
    "venv",
    "__pycache__",
    ".pytest_cache",
    ".mypy_cache",
    ".ruff_cache",
    "node_modules",
    "build",
    ".dart_tool",
    "Pods",
    ".gradle",
}


def _is_ignored_dir(path: Path) -> bool:
    return path.name in IGNORE_DIRS


def _iter_files(root: Path) -> list[Path]:
    files: list[Path] = []
    if not root.exists():
        return files
    for dirpath, dirnames, filenames in os.walk(root):
        # Prune ignored directories in-place.
        dirnames[:] = [d for d in dirnames if d not in IGNORE_DIRS]
        base = Path(dirpath)
        for name in filenames:
            p = base / name
            if p.suffix.lower() in SEARCH_SUFFIXES:
                files.append(p)
    return files


def main() -> int:
    violations: list[Violation] = []

    for rel in BANNED_PATHS:
        p = REPO_ROOT / rel
        if p.exists():
            violations.append(Violation(kind="banned_path", path=p, detail=f"found legacy path `{rel}`"))

    for rel_root in SEARCH_ROOTS:
        base = REPO_ROOT / rel_root
        for path in _iter_files(base):
            try:
                data = path.read_text(encoding="utf-8")
            except Exception:
                # Best-effort; skip binary/invalid files.
                continue
            for prefix in BANNED_ROUTE_PREFIXES:
                if prefix in data:
                    violations.append(
                        Violation(
                            kind="banned_route_prefix",
                            path=path,
                            detail=f"found legacy route prefix `{prefix}` in `{path.relative_to(REPO_ROOT)}`",
                        )
                    )

    if not violations:
        print("OK: legacy artifacts are absent")
        return 0

    print("FAIL: legacy artifacts detected")
    for v in violations:
        print(f"- {v.kind}: {v.detail}")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())

