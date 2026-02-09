import uuid
from datetime import datetime, timedelta, timezone

import apps.bff.app.main as bff  # type: ignore[import]
import apps.payments.app.main as pay


def _create_wallet(client, phone: str) -> str:
    resp = client.post("/payments/users", json={"phone": phone})
    assert resp.status_code == 200
    data = resp.json()
    return data["wallet_id"]


def _topup(client, wallet_id: str, amount: int, internal_secret: str | None = None, auth_phone: str | None = None):
    headers = {"Idempotency-Key": f"topup-{uuid.uuid4().hex}"}
    if auth_phone:
        headers["X-Test-Phone"] = auth_phone
    if internal_secret:
        headers["X-Internal-Secret"] = internal_secret
    resp = client.post(
        f"/payments/wallets/{wallet_id}/topup",
        headers=headers,
        json={"amount_cents": amount},
    )
    assert resp.status_code == 200


def test_payment_request_accept_idempotent_and_expires(client, monkeypatch):
    # Enable dev topup path
    monkeypatch.setenv("DEV_ENABLE_TOPUP", "true")
    monkeypatch.setenv("BFF_DEV_ALLOW_TOPUP", "true")
    monkeypatch.setattr(pay, "INTERNAL_API_SECRET", "test-internal-secret", raising=False)

    payer_phone = "+15550001001"
    payee_phone = "+15550001002"
    payer_wallet = _create_wallet(client, payer_phone)
    payee_wallet = _create_wallet(client, payee_phone)

    # Fund payer
    admin_phone = "+491700000099"
    monkeypatch.setenv("BFF_ADMINS", admin_phone)
    bff.BFF_ADMINS.add(admin_phone)
    _topup(client, payer_wallet, 50_000, internal_secret="test-internal-secret", auth_phone=admin_phone)

    # Create request payee <- payer
    req = client.post(
        "/payments/requests",
        headers={"X-Test-Phone": payee_phone},
        json={
            "from_wallet_id": payee_wallet,
            "to_wallet_id": payer_wallet,
            "amount_cents": 10_000,
            "message": "test req",
            "expires_in_secs": 3600,
        },
    )
    assert req.status_code == 200
    rid = req.json()["id"]

    # Accept with idempotency key
    ikey = f"req-{uuid.uuid4().hex}"
    acc1 = client.post(
        f"/payments/requests/{rid}/accept",
        headers={"Idempotency-Key": ikey, "X-Test-Phone": payer_phone},
        json={"to_wallet_id": payer_wallet},
    )
    assert acc1.status_code == 200
    bal_after = acc1.json()["balance_cents"]

    # Retry with same idempotency key -> same balance, no double debit
    acc2 = client.post(
        f"/payments/requests/{rid}/accept",
        headers={"Idempotency-Key": ikey, "X-Test-Phone": payer_phone},
        json={"to_wallet_id": payer_wallet},
    )
    assert acc2.status_code == 200
    assert acc2.json()["balance_cents"] == bal_after

    # Manually expire another request and ensure accept is rejected
    req2 = client.post(
        "/payments/requests",
        headers={"X-Test-Phone": payee_phone},
        json={
            "from_wallet_id": payee_wallet,
            "to_wallet_id": payer_wallet,
            "amount_cents": 5_000,
            "message": "expire me",
            "expires_in_secs": 3600,
        },
    )
    rid2 = req2.json()["id"]
    # Force expiry in DB
    with pay.Session(pay.engine) as s:  # type: ignore[attr-defined]
        r = s.get(pay.PaymentRequest, rid2)  # type: ignore[attr-defined]
        r.expires_at = datetime.now(timezone.utc) - timedelta(seconds=1)
        s.add(r); s.commit()

    acc_exp = client.post(
        f"/payments/requests/{rid2}/accept",
        headers={"X-Test-Phone": payer_phone},
        json={"to_wallet_id": payer_wallet},
    )
    assert acc_exp.status_code == 400
    assert "expired" in acc_exp.json().get("detail", "")
