def test_security_headers_present_on_metrics(client):
    """
    Stellt sicher, dass der Security-Header-Middleware grundlegende
    Browser-Schutzheader auf Antworten setzt.
    """

    resp = client.get("/metrics")
    assert resp.status_code == 200
    headers = resp.headers
    assert headers.get("X-Content-Type-Options") == "nosniff"
    assert headers.get("X-Frame-Options") == "DENY"
    assert headers.get("Referrer-Policy") == "strict-origin-when-cross-origin"

