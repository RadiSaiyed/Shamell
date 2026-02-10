#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path

TARGET_CONTAINER_PORTS = {"8081", "8082", "8083"}
LOCAL_HOST_EXPRESSIONS = {"127.0.0.1", "localhost", "::1", "[::1]"}


@dataclass
class Violation:
    path: Path
    line: int
    value: str
    reason: str


def _strip_quotes(value: str) -> str:
    clean = (value or "").strip()
    if len(clean) >= 2 and clean[0] == clean[-1] and clean[0] in {"'", '"'}:
        return clean[1:-1].strip()
    return clean


def _extract_scalar(raw: str) -> str:
    clean = (raw or "").strip()
    if not clean:
        return ""
    if clean[0] in {"'", '"'}:
        quote = clean[0]
        end = clean.find(quote, 1)
        if end > 0:
            return clean[: end + 1]
        return clean
    hash_index = clean.find(" #")
    if hash_index >= 0:
        clean = clean[:hash_index].strip()
    return clean


def _short_mapping_parts(raw_value: str) -> tuple[str | None, str | None, str | None]:
    clean = _strip_quotes(raw_value)
    if "/" in clean:
        clean = clean.rsplit("/", 1)[0]
    parts = clean.rsplit(":", 2)
    if len(parts) == 1:
        return None, None, parts[0].strip()
    if len(parts) == 2:
        return None, parts[0].strip(), parts[1].strip()
    return parts[0].strip(), parts[1].strip(), parts[2].strip()


def _parse_env_expression(expr: str) -> tuple[str, str | None, str | None] | None:
    clean = _strip_quotes(expr)
    m = re.match(r"^\$\{([A-Za-z_][A-Za-z0-9_]*)(?:(:-|-)(.*))?\}$", clean)
    if not m:
        return None
    name = m.group(1)
    op = m.group(2)
    default = m.group(3)
    return name, op, default


def _resolve_host_expression(
    expr: str,
    env_values: dict[str, str],
    *,
    depth: int = 0,
) -> str:
    if depth > 6:
        return _strip_quotes(expr)
    parsed = _parse_env_expression(expr)
    if not parsed:
        return _strip_quotes(expr)
    name, op, default = parsed
    current = (env_values.get(name) or "").strip()
    if op == ":-":
        chosen = current if current else (default or "")
    elif op == "-":
        chosen = current if name in env_values else (default or "")
    else:
        chosen = current
    if not chosen:
        return ""
    return _resolve_host_expression(chosen, env_values, depth=depth + 1)


def _is_local_host_expression(expr: str, env_values: dict[str, str]) -> bool:
    clean = _resolve_host_expression(expr, env_values)
    return clean in LOCAL_HOST_EXPRESSIONS


def _violations_for_short_mapping(
    path: Path,
    line: int,
    value: str,
    env_values: dict[str, str],
) -> list[Violation]:
    host_ip, _host_port, container_port = _short_mapping_parts(value)
    if (container_port or "").strip() not in TARGET_CONTAINER_PORTS:
        return []
    if host_ip and _is_local_host_expression(host_ip, env_values):
        return []
    reason = (
        "container port is bound without explicit localhost host_ip"
        if not host_ip
        else f"host_ip `{host_ip}` is not localhost-only"
    )
    return [Violation(path=path, line=line, value=value, reason=reason)]


def _violations_for_long_mapping(
    path: Path,
    line: int,
    mapping: dict[str, str],
    env_values: dict[str, str],
) -> list[Violation]:
    target = _strip_quotes(mapping.get("target", ""))
    if target not in TARGET_CONTAINER_PORTS:
        return []
    host_ip = mapping.get("host_ip", "").strip()
    if host_ip and _is_local_host_expression(host_ip, env_values):
        return []
    reason = (
        "long-syntax port mapping has no localhost host_ip"
        if not host_ip
        else f"host_ip `{host_ip}` is not localhost-only"
    )
    rendered = ", ".join(f"{k}={v}" for k, v in sorted(mapping.items()))
    return [Violation(path=path, line=line, value=rendered, reason=reason)]


def _scan_compose_file(path: Path, env_values: dict[str, str]) -> list[Violation]:
    violations: list[Violation] = []
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except Exception as exc:  # pragma: no cover
        return [
            Violation(
                path=path,
                line=1,
                value="",
                reason=f"unable to read file: {exc}",
            )
        ]

    in_ports_block = False
    ports_indent = 0
    i = 0
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()
        indent = len(line) - len(line.lstrip(" "))

        if not in_ports_block:
            if re.match(r"^\s*ports:\s*$", line):
                in_ports_block = True
                ports_indent = indent
            i += 1
            continue

        if stripped and not stripped.startswith("#") and indent <= ports_indent:
            in_ports_block = False
            continue

        item_match = re.match(r"^\s*-\s*(.+?)\s*$", line)
        if not item_match:
            i += 1
            continue

        item_indent = indent
        raw_value = _extract_scalar(item_match.group(1))
        if not raw_value or raw_value.startswith("#"):
            i += 1
            continue

        if re.match(r"^[A-Za-z_][\w-]*\s*:", raw_value) and not raw_value.startswith(("'", '"')):
            mapping: dict[str, str] = {}
            key, value = raw_value.split(":", 1)
            mapping[key.strip().lower()] = value.strip()
            j = i + 1
            while j < len(lines):
                child = lines[j]
                child_stripped = child.strip()
                child_indent = len(child) - len(child.lstrip(" "))
                if child_stripped and not child_stripped.startswith("#") and child_indent <= item_indent:
                    break
                key_match = re.match(r"^\s*([A-Za-z_][\w-]*)\s*:\s*(.*?)\s*$", child)
                if key_match:
                    mapping[key_match.group(1).lower()] = key_match.group(2).strip()
                j += 1
            violations.extend(_violations_for_long_mapping(path, i + 1, mapping, env_values))
            i = j
            continue

        violations.extend(_violations_for_short_mapping(path, i + 1, raw_value, env_values))
        i += 1

    return violations


def _discover_compose_files(root: Path) -> list[Path]:
    out: list[Path] = []
    for pattern in ("docker-compose*.yml", "docker-compose*.yaml"):
        out.extend(root.rglob(pattern))
    return sorted({p.resolve() for p in out})


def _collect_compose_files(inputs: list[str]) -> list[Path]:
    if not inputs:
        return _discover_compose_files(Path.cwd())

    out: list[Path] = []
    for raw in inputs:
        p = Path(raw).resolve()
        if p.is_dir():
            out.extend(_discover_compose_files(p))
            continue
        if p.is_file():
            out.append(p)
            continue
        raise FileNotFoundError(raw)
    return sorted({p for p in out})


def _parse_env_file(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        k = key.strip()
        if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", k):
            continue
        out[k] = _strip_quotes(value.strip())
    return out


def _build_env_values(env_files: list[str]) -> dict[str, str]:
    out: dict[str, str] = {}
    for raw in env_files:
        p = Path(raw).resolve()
        if not p.is_file():
            raise FileNotFoundError(raw)
        out.update(_parse_env_file(p))
    # Runtime environment overrides file values (matches compose interpolation precedence).
    for k, v in os.environ.items():
        out[k] = v
    return out


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Fail if Docker Compose mappings expose container port 8081/8082 "
            "without localhost-only host_ip."
        )
    )
    parser.add_argument(
        "paths",
        nargs="*",
        help="Optional directories/files to scan (defaults to current repo).",
    )
    parser.add_argument(
        "--env-file",
        action="append",
        default=[],
        help="Optional env file(s) used to resolve host_ip variable expressions.",
    )
    args = parser.parse_args()

    try:
        files = _collect_compose_files(args.paths)
        env_values = _build_env_values(args.env_file or [])
    except FileNotFoundError as exc:
        print(f"[FAIL] path not found: {exc}", file=sys.stderr)
        return 2

    if not files:
        print("[OK] no docker-compose*.yml files found")
        return 0

    violations: list[Violation] = []
    for compose_file in files:
        violations.extend(_scan_compose_file(compose_file, env_values))

    if not violations:
        print(f"[OK] internal port exposure guard passed ({len(files)} files scanned)")
        return 0

    print("[FAIL] detected non-localhost exposure for container ports 8081/8082:", file=sys.stderr)
    for v in violations:
        print(
            f"  - {v.path}:{v.line}: {v.reason} | value={v.value}",
            file=sys.stderr,
        )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
