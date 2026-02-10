import apps.bff.app.main as bff


def test_http_5xx_details_are_scrubbed_in_prod(client, monkeypatch):
    # In prod/staging, HTTP 5xx details must not leak implementation info.
    monkeypatch.setenv("ENV", "prod")
    monkeypatch.setattr(bff, "_qr", None, raising=False)

    resp = client.get("/qr.png", params={"data": "hello"})
    assert resp.status_code == 500
    body = resp.json()
    assert body.get("detail") == "internal error"
    assert body.get("request_id")

