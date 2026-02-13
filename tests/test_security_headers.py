def test_security_headers_present_on_metrics(client):
    """
    Stellt sicher, dass der Security-Header-Middleware grundlegende
    Browser-Schutzheader auf Antworten setzt.
    """

    # /metrics is admin-only; authenticate as admin for header checks.
    import apps.bff.app.main as bff  # type: ignore[import]

    admin_phone = "+491700000099"
    bff.BFF_ADMINS.add(admin_phone)
    resp = client.get("/metrics", headers={"X-Test-Phone": admin_phone})
    assert resp.status_code == 200
    headers = resp.headers
    assert headers.get("X-Content-Type-Options") == "nosniff"
    assert headers.get("X-Frame-Options") == "DENY"
    assert headers.get("Referrer-Policy") == "strict-origin-when-cross-origin"
