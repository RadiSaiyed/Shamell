from __future__ import annotations

import apps.bff.app.main as bff  # type: ignore[import]


def test_auth_rate_limit_cannot_be_bypassed_by_x_forwarded_for(client, monkeypatch):
    """
    Best practice: do not trust spoofable proxy headers unless the immediate
    peer is trusted. Otherwise, IP-based rate limiting can be bypassed.
    """
    phone = "+491700009999"

    monkeypatch.setattr(bff, "_AUTH_RATE_PHONE", {}, raising=False)
    monkeypatch.setattr(bff, "_AUTH_RATE_IP", {}, raising=False)
    monkeypatch.setattr(bff, "AUTH_MAX_PER_PHONE", 999, raising=False)
    monkeypatch.setattr(bff, "AUTH_MAX_PER_IP", 1, raising=False)

    # Default should be "auto": without trusted proxies, XFF must not be used.
    monkeypatch.setattr(bff, "TRUST_PROXY_HEADERS_MODE", "auto", raising=False)
    monkeypatch.setattr(bff, "TRUST_PRIVATE_PROXY_HOPS", False, raising=False)
    monkeypatch.setattr(bff, "TRUSTED_PROXY_CIDRS", [], raising=False)

    r1 = client.post("/auth/request_code", json={"phone": phone}, headers={"X-Forwarded-For": "1.1.1.1"})
    r2 = client.post("/auth/request_code", json={"phone": phone}, headers={"X-Forwarded-For": "2.2.2.2"})
    assert r1.status_code == 200
    assert r2.status_code == 429

