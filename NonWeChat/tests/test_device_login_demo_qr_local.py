def test_device_login_demo_uses_local_qr_generator(client):
    """
    The device-login demo renders a QR code that includes a one-time token.
    That token must never be sent to third-party QR generators.
    """

    r = client.get("/auth/device_login_demo")
    assert r.status_code == 200
    body = r.text
    assert "api.qrserver.com" not in body
    assert "/qr.png" in body

