from __future__ import annotations

from fastapi.routing import APIRoute, APIWebSocketRoute
from starlette.routing import WebSocketRoute

import apps.bff.app.main as bff  # type: ignore[import]


def test_bff_has_no_duplicate_routes():
    """
    Duplicate method+path registrations are a footgun: in Starlette routing,
    the first matching route wins, so an earlier unprotected handler can shadow
    a later protected one.
    """
    seen: set[tuple[str, str]] = set()
    dups: list[tuple[str, str]] = []

    for r in bff.app.routes:
        path = getattr(r, "path", None)
        if not path:
            continue

        if isinstance(r, APIRoute):
            methods = r.methods or set()
            for m in sorted(methods):
                key = (m, path)
                if key in seen:
                    dups.append(key)
                seen.add(key)
            continue

        if isinstance(r, (APIWebSocketRoute, WebSocketRoute)):
            key = ("WEBSOCKET", path)
            if key in seen:
                dups.append(key)
            seen.add(key)
            continue

    assert not dups, f"Duplicate routes found: {dups}"

