import apps.bff.app.main as bff


def test_admin_block_phone_requires_superadmin_and_blocks_otp(client, admin_auth, user_auth, monkeypatch):
    # Keep test isolated from global state.
    monkeypatch.setattr(bff, "_BLOCKED_PHONES", set(), raising=False)
    monkeypatch.setattr(bff, "SUPERADMIN_PHONE", admin_auth.phone, raising=False)

    target = "+491700001234"

    # Non-superadmin cannot block
    r = client.post("/admin/block_phone", json={"phone": target}, headers=user_auth.headers())
    assert r.status_code == 403

    # Superadmin blocks
    r = client.post("/admin/block_phone", json={"phone": target}, headers=admin_auth.headers())
    assert r.status_code == 200
    assert r.json().get("blocked") is True

    # Blocked phone must not receive OTP
    r = client.post("/auth/request_code", json={"phone": target})
    assert r.status_code == 403

    # Unblock restores OTP flow
    r = client.post("/admin/unblock_phone", json={"phone": target}, headers=admin_auth.headers())
    assert r.status_code == 200
    assert r.json().get("blocked") is False
    r = client.post("/auth/request_code", json={"phone": target})
    assert r.status_code == 200


def test_legacy_block_driver_endpoints_disabled_in_prod(client, monkeypatch):
    # Legacy endpoints should be removed in prod/staging (404) even if someone probes them.
    monkeypatch.setenv("ENV", "prod")
    assert client.post("/admin/block_driver", json={"phone": "+491700001111"}).status_code == 404
    assert client.post("/admin/unblock_driver", json={"phone": "+491700001111"}).status_code == 404

