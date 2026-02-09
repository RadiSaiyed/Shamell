from __future__ import annotations

import apps.bff.app.main as bff  # type: ignore[import]


def test_csrf_guard_blocks_cross_site_cookie_write(client, monkeypatch):
    """
    Defense-in-depth: when a browser sends an auth cookie, non-idempotent
    cross-site requests must be blocked (classic CSRF).
    """
    monkeypatch.setattr(bff, "CSRF_GUARD_ENABLED", True, raising=False)
    monkeypatch.setattr(bff, "_CSRF_ORIGIN_WILDCARD", False, raising=False)
    monkeypatch.setattr(bff, "_CSRF_ALLOWED_ORIGINS", {"http://localhost:5173"}, raising=False)

    r = client.post(
        "/auth/logout",
        cookies={"sa_session": "a" * 32},
        headers={
            "Origin": "https://evil.example",
            "Sec-Fetch-Site": "cross-site",
        },
    )
    assert r.status_code == 403


def test_csrf_guard_allows_allowed_origin_cookie_write(client, monkeypatch):
    monkeypatch.setattr(bff, "CSRF_GUARD_ENABLED", True, raising=False)
    monkeypatch.setattr(bff, "_CSRF_ORIGIN_WILDCARD", False, raising=False)
    monkeypatch.setattr(bff, "_CSRF_ALLOWED_ORIGINS", {"http://localhost:5173"}, raising=False)

    r = client.post(
        "/auth/logout",
        cookies={"sa_session": "a" * 32},
        headers={"Origin": "http://localhost:5173"},
    )
    assert r.status_code == 200


def test_csrf_guard_skips_header_session(client, monkeypatch):
    """
    Header-based sessions (`sa_cookie`) are not CSRFable via a normal browser,
    so we don't apply the guard there (keeps non-browser clients working).
    """
    monkeypatch.setattr(bff, "CSRF_GUARD_ENABLED", True, raising=False)
    monkeypatch.setattr(bff, "_CSRF_ORIGIN_WILDCARD", False, raising=False)
    monkeypatch.setattr(bff, "_CSRF_ALLOWED_ORIGINS", {"http://localhost:5173"}, raising=False)

    r = client.post(
        "/auth/logout",
        cookies={"sa_session": "a" * 32},
        headers={
            "Origin": "https://evil.example",
            "sa_cookie": "a" * 32,
        },
    )
    assert r.status_code == 200

