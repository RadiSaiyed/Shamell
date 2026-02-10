from __future__ import annotations

import os

import apps.bff.app.main as bff  # type: ignore[import]


def test_metrics_does_not_leak_internal_api_secret_in_json(client, monkeypatch):
    """
    Ensure that /metrics does not accidentally echo INTERNAL_API_SECRET or
    PAYMENTS_INTERNAL_SECRET values even if they are set in the environment.
    """

    secret = "INTERNAL_SECRET_SENTINEL"
    pay_secret = "PAYMENTS_SECRET_SENTINEL"

    monkeypatch.setenv("INTERNAL_API_SECRET", secret)
    monkeypatch.setenv("PAYMENTS_INTERNAL_SECRET", pay_secret)
    # Reload secrets into module-level variables if they were already read.
    monkeypatch.setattr(bff, "INTERNAL_API_SECRET", secret, raising=False)
    monkeypatch.setattr(bff, "PAYMENTS_INTERNAL_SECRET", pay_secret, raising=False)

    # /metrics is admin-only; authenticate as admin for this privacy test.
    admin_phone = "+491700000099"
    monkeypatch.setenv("BFF_ADMINS", admin_phone)
    bff.BFF_ADMINS.add(admin_phone)

    resp = client.get("/metrics", headers={"X-Test-Phone": admin_phone})
    assert resp.status_code == 200
    body = resp.text
    assert secret not in body
    assert pay_secret not in body


def test_admin_metrics_does_not_leak_internal_api_secret_in_html(client, monkeypatch):
    """
    Ensure that /admin/metrics (HTML) does not accidentally echo INTERNAL_API_SECRET
    or PAYMENTS_INTERNAL_SECRET. This endpoint is admin-only, but should still never
    contain raw secrets.
    """

    secret = "INTERNAL_SECRET_SENTINEL_HTML"
    pay_secret = "PAYMENTS_SECRET_SENTINEL_HTML"

    monkeypatch.setenv("INTERNAL_API_SECRET", secret)
    monkeypatch.setenv("PAYMENTS_INTERNAL_SECRET", pay_secret)
    monkeypatch.setattr(bff, "INTERNAL_API_SECRET", secret, raising=False)
    monkeypatch.setattr(bff, "PAYMENTS_INTERNAL_SECRET", pay_secret, raising=False)

    # Simulate an admin by forcing _require_admin_v2 to accept a dummy request.
    monkeypatch.setattr(bff, "_require_admin_v2", lambda request: "admin@test", raising=False)

    resp = client.get("/admin/metrics")
    assert resp.status_code == 200
    html = resp.text
    assert secret not in html
    assert pay_secret not in html
