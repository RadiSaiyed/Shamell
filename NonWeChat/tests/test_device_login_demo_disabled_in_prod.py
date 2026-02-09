def test_device_login_demo_disabled_in_prod(client, monkeypatch):
    # In production this demo endpoint must not exist (404).
    monkeypatch.setenv("ENV", "prod")
    r = client.get("/auth/device_login_demo")
    assert r.status_code == 404

