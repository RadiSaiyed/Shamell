from __future__ import annotations

from fastapi.testclient import TestClient


def test_bff_route_allowlist_blocks_unlisted_paths(monkeypatch):
    import apps.bff.app.main as bff  # type: ignore[import]

    # Enable allowlist explicitly (default is disabled in ENV=test).
    monkeypatch.setattr(bff, "BFF_ROUTE_ALLOWLIST_ENABLED", True, raising=False)
    monkeypatch.setattr(bff, "BFF_ALLOWED_PATHS_EXACT", {"/health"}, raising=False)
    monkeypatch.setattr(bff, "BFF_ALLOWED_PATH_PREFIXES", ["/auth"], raising=False)

    client = TestClient(bff.app)

    assert client.get("/health").status_code == 200

    # Not allowlisted => 404 even though the route exists in the codebase.
    assert client.get("/agriculture").status_code == 404

    # Allowlisted prefix => request reaches handler (400 due to missing payload).
    assert client.post("/auth/request_code", json={}).status_code == 400

