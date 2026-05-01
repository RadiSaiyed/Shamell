#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import sys
from collections import defaultdict
from pathlib import Path


METHODS = ("get", "post", "put", "patch", "delete")
METHOD_ORDER = {method: index for index, method in enumerate(METHODS)}
ROUTE_CALL = ".route("
DEFAULT_MAIN_RS = Path("services_rs/bff_gateway/src/main.rs")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Export the Shamell BFF runtime HTTP surface from main.rs either "
            "as an OpenAPI route-surface document or as METHOD PATH pairs."
        ),
    )
    parser.add_argument(
        "--main-rs",
        default=str(DEFAULT_MAIN_RS),
        help="Path to services_rs/bff_gateway/src/main.rs",
    )
    parser.add_argument(
        "--format",
        choices=("openapi", "route-pairs"),
        default="openapi",
        help="Output format",
    )
    return parser.parse_args()


def load_runtime_source(main_rs: Path) -> str:
    try:
        source = main_rs.read_text(encoding="utf-8")
    except FileNotFoundError as exc:
        raise SystemExit(f"missing file: {main_rs}") from exc
    marker = "\n#[cfg(test)]"
    marker_index = source.find(marker)
    if marker_index != -1:
        return source[:marker_index]
    return source


def _read_rust_string_literal(source: str, start_index: int) -> tuple[str, int]:
    if start_index >= len(source) or source[start_index] != '"':
        raise ValueError("expected Rust string literal")
    index = start_index + 1
    value: list[str] = []
    while index < len(source):
        char = source[index]
        if char == "\\":
            index += 1
            if index >= len(source):
                raise ValueError("unterminated escape sequence")
            value.append(source[index])
            index += 1
            continue
        if char == '"':
            return "".join(value), index + 1
        value.append(char)
        index += 1
    raise ValueError("unterminated Rust string literal")


def extract_runtime_routes(source: str) -> dict[str, list[str]]:
    routes: dict[str, set[str]] = defaultdict(set)
    index = 0
    while True:
        route_index = source.find(ROUTE_CALL, index)
        if route_index == -1:
            break
        cursor = route_index + len(ROUTE_CALL)
        while cursor < len(source) and source[cursor].isspace():
            cursor += 1
        path, cursor = _read_rust_string_literal(source, cursor)

        depth = 1
        body_start = cursor
        in_string = False
        escaping = False
        while cursor < len(source) and depth > 0:
            char = source[cursor]
            if in_string:
                if escaping:
                    escaping = False
                elif char == "\\":
                    escaping = True
                elif char == '"':
                    in_string = False
            else:
                if char == '"':
                    in_string = True
                elif char == "(":
                    depth += 1
                elif char == ")":
                    depth -= 1
            cursor += 1

        if depth != 0:
            raise ValueError(f"unterminated .route() call for path {path}")

        call_body = source[body_start : cursor - 1]
        methods = {
            match.group(1).lower()
            for match in re.finditer(r"\b(get|post|put|patch|delete)\s*\(", call_body)
        }
        if methods:
            routes[path].update(methods)
        index = cursor

    return {
        path: sorted(methods, key=lambda method: METHOD_ORDER[method])
        for path, methods in sorted(routes.items())
    }


def tag_for_path(path: str) -> str:
    if path == "/":
        return "root"
    first_segment = next((segment for segment in path.split("/") if segment), "")
    return first_segment or "root"


def openapi_path_for(path: str) -> str:
    if path == "/":
        return path
    segments = []
    for segment in path.strip("/").split("/"):
        if segment.startswith(":") and len(segment) > 1:
            segments.append(f"{{{segment[1:]}}}")
        else:
            segments.append(segment)
    return "/" + "/".join(segments)


def path_parameters_for(path: str) -> list[str]:
    params: list[str] = []
    for segment in path.strip("/").split("/"):
        if segment.startswith(":") and len(segment) > 1:
            params.append(segment[1:])
    return params


def operation_id_for(method: str, path: str) -> str:
    if path == "/":
        return f"{method}Root"
    components = [method]
    for raw_segment in path.strip("/").split("/"):
        segment = raw_segment.strip()
        if not segment:
            continue
        if segment.startswith(":"):
            segment = f"by_{segment[1:]}"
        segment = re.sub(r"[^A-Za-z0-9_]+", "_", segment)
        segment = re.sub(r"_+", "_", segment).strip("_")
        if not segment:
            continue
        components.append(segment)
    joined = "_".join(components)
    parts = [part for part in joined.split("_") if part]
    return "".join(part[:1].upper() + part[1:] for part in parts[:1]) + "".join(
        part[:1].upper() + part[1:] for part in parts[1:]
    )


def render_openapi(routes: dict[str, list[str]], main_rs: Path) -> str:
    lines = [
        "openapi: 3.0.3",
        "info:",
        "  title: Shamell BFF Runtime Surface",
        "  version: 0.1.0",
        "  description: |",
        f"    Auto-generated from `{main_rs.as_posix()}`.",
        "    This document tracks the live BFF route and HTTP-method surface only.",
        "    Request and response schemas are not yet described here.",
        "servers:",
        "  - url: https://api.shamell.example",
        "paths:",
    ]
    for path, methods in routes.items():
        openapi_path = openapi_path_for(path)
        path_parameters = path_parameters_for(path)
        lines.append(f"  {openapi_path}:")
        for method in methods:
            operation_id = operation_id_for(method, path)
            summary = f"Runtime surface entry for {method.upper()} {openapi_path}"
            lines.extend(
                [
                    f"    {method}:",
                    f"      tags: [{tag_for_path(path)}]",
                    f"      operationId: {operation_id}",
                    f"      summary: {summary}",
                    "      x-shamell-runtime-surface-only: true",
                ]
            )
            if path_parameters:
                lines.append("      parameters:")
                for param in path_parameters:
                    lines.extend(
                        [
                            f"        - name: {param}",
                            "          in: path",
                            "          required: true",
                            "          schema:",
                            "            type: string",
                        ]
                    )
            lines.extend(
                [
                    "      responses:",
                    "        default:",
                    (
                        "          description: Runtime path exists; schema "
                        "documentation is tracked separately."
                    ),
                ]
            )
    return "\n".join(lines) + "\n"


def render_route_pairs(routes: dict[str, list[str]]) -> str:
    lines: list[str] = []
    for path, methods in routes.items():
        for method in methods:
            lines.append(f"{method.upper()} {path}")
    return "\n".join(lines) + "\n"


def main() -> int:
    args = parse_args()
    main_rs = Path(args.main_rs)
    source = load_runtime_source(main_rs)
    routes = extract_runtime_routes(source)
    if args.format == "route-pairs":
        sys.stdout.write(render_route_pairs(routes))
        return 0
    sys.stdout.write(render_openapi(routes, main_rs))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
