import apps.bff.app.main as bff


def _grant_admin(phone: str, monkeypatch):
    """
    Ensure the given phone is treated as admin for the duration of the test.
    """
    monkeypatch.setenv("BFF_ADMINS", phone)
    bff.BFF_ADMINS.add(phone)


def test_taxi_topup_qr_single_use(client, admin_auth, monkeypatch):
    driver_phone = "+491700000201"
    amount = 1234
    _grant_admin(admin_auth.phone, monkeypatch)

    # Create driver
    r_driver = client.post("/taxi/drivers", json={"name": "Driver QR", "phone": driver_phone})
    assert r_driver.status_code == 200
    driver_id = r_driver.json()["id"]

    # Admin generates QR for the driver
    r_qr = client.post(
        "/taxi/topup_qr/create",
        headers=admin_auth.headers(),
        json={"driver_phone": driver_phone, "amount_cents": amount},
    )
    assert r_qr.status_code == 200
    payload = r_qr.json()["payload"]
    assert payload.startswith("TAXI_TOPUP|")

    # Driver redeems QR and balance increases
    r_redeem = client.post("/taxi/topup_qr/redeem", headers={"X-Test-Phone": driver_phone}, json={"payload": payload})
    assert r_redeem.status_code == 200
    out = r_redeem.json()
    assert out["ok"] is True
    assert out["amount_cents"] == amount
    assert out["driver_id"] == driver_id
    assert out["balance_cents"] == amount

    # Second redemption must be rejected (single-use)
    r_redeem_again = client.post(
        "/taxi/topup_qr/redeem", headers={"X-Test-Phone": driver_phone}, json={"payload": payload}
    )
    assert r_redeem_again.status_code == 410
