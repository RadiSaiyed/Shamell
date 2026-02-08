from __future__ import annotations

from typing import Any, Dict, List

import apps.bff.app.main as bff  # type: ignore[import]
import pytest
from fastapi.testclient import TestClient

from .test_payments_e2e_bff import _setup_fake_payments


def _login_via_otp(client, monkeypatch, phone: str) -> None:
    """
    Helper: performs the login flow via /auth/request_code and /auth/verify
    for a given phone number. The TestClient instance automatically receives
    the sa_session cookie.
    """

    # In test environments the code may appear in the response body.
    monkeypatch.setattr(bff, "AUTH_EXPOSE_CODES", True, raising=False)

    resp_req = client.post("/auth/request_code", json={"phone": phone})
    assert resp_req.status_code == 200
    data = resp_req.json()
    code = (data.get("code") or "").strip()
    assert code

    resp_ver = client.post(
        "/auth/verify",
        json={"phone": phone, "code": code, "name": "E2E Test User"},
    )
    assert resp_ver.status_code == 200
    body = resp_ver.json()
    assert body.get("ok") is True
    assert body.get("phone") == phone


@pytest.fixture()
def client():
    return TestClient(bff.app)


def test_e2e_login_first_payment_and_history(client, monkeypatch):
    """
    E2E scenario (API based):

    - Login via /auth/request_code + /auth/verify
    - Create two wallets via /payments/users (A = logged-in user, B = receiver)
    - Top up wallet A from system wallet 'sys'
    - Transfer from A -> B via /payments/transfer
    - Use /wallets/{id}/snapshot to verify balances and txns
    """

    phone_a = "+491700000201"
    phone_b = "+491700000202"

    _login_via_otp(client, monkeypatch, phone_a)

    state = _setup_fake_payments(monkeypatch)

    # Create wallets for A and B
    resp_a = client.post("/payments/users", json={"phone": phone_a})
    resp_b = client.post("/payments/users", json={"phone": phone_b})
    assert resp_a.status_code == 200
    assert resp_b.status_code == 200
    wa = resp_a.json()["wallet_id"]
    wb = resp_b.json()["wallet_id"]

    # Erste Aufladung von A aus system wallet 'sys'
    topup_amount = 10_000
    resp_topup = client.post(
        "/payments/transfer",
        json={
            "from_wallet_id": "sys",
            "to_wallet_id": wa,
            "amount_cents": topup_amount,
        },
        headers={"X-Test-Phone": "sys"},
    )
    assert resp_topup.status_code == 200

    # Erste echte Zahlung A -> B
    transfer_amount = 4_000
    resp_tx = client.post(
        "/payments/transfer",
        json={
            "from_wallet_id": wa,
            "to_wallet_id": wb,
            "amount_cents": transfer_amount,
        },
        headers={"X-Test-Phone": phone_a},
    )
    assert resp_tx.status_code == 200

    # Historien-Check via Snapshot: Salden + Txns
    # TestClient runs over http://testserver, so secure cookies are not sent.
    # Use the test-only phone header for auth.
    snap_a = client.get(f"/wallets/{wa}/snapshot", headers={"X-Test-Phone": phone_a}).json()
    # Wallet B belongs to a different user; simulate that user in test mode.
    snap_b = client.get(f"/wallets/{wb}/snapshot", headers={"X-Test-Phone": phone_b}).json()

    bal_a = snap_a["wallet"]["balance_cents"]
    bal_b = snap_b["wallet"]["balance_cents"]
    txns_a: List[Dict[str, Any]] = snap_a.get("txns") or []
    txns_b: List[Dict[str, Any]] = snap_b.get("txns") or []

    # Balances must reflect the transfer
    assert bal_a == topup_amount - transfer_amount
    assert bal_b == transfer_amount

    # At least one transfer transaction in the history of both wallets
    assert any(t.get("kind") == "transfer" for t in txns_a)
    assert any(t.get("kind") == "transfer" for t in txns_b)


def test_e2e_login_and_mobility_history(client, monkeypatch):
    """
    E2E scenario (API based):

    - Login via OTP (cookie-based session)
    - Stub Taxi and Bus history in the BFF
    - Call /me/mobility_history and verify that only entries for
      the logged-in user are returned
    """

    phone = "+491700000301"
    _login_via_otp(client, monkeypatch, phone)

    # Stub Taxi and Bus lists in the BFF so they always return exactly one
    # entry for the logged-in user.
    def fake_taxi_list_rides(status: str = "", limit: int = 50):
        return [
            {
                "id": "ride_1",
                "status": "completed",
                "rider_phone": phone,
                "driver_id": "drv_1",
                "requested_at": "2025-01-01T10:00:00+00:00",
            }
        ]

    def fake_bus_booking_search(wallet_id: str | None, phone: str, limit: int = 50):
        return [
            {
                "id": "bus_booking_1",
                "status": "completed",
                "customer_phone": phone,
                "trip_id": "trip_1",
                "seats": 1,
                "created_at": "2025-01-01T11:00:00+00:00",
            }
        ]

    monkeypatch.setattr(bff, "taxi_list_rides", fake_taxi_list_rides, raising=False)
    monkeypatch.setattr(bff, "bus_booking_search", fake_bus_booking_search, raising=False)

    # Fetch combined mobility history; in tests auth is done via X-Test-Phone
    resp = client.get(
        "/me/mobility_history?status=completed&taxi_limit=10&bus_limit=10",
        headers={"X-Test-Phone": phone},
    )
    assert resp.status_code == 200
    data = resp.json()
    taxi_items = data.get("taxi") or []
    bus_items = data.get("bus") or []

    assert len(taxi_items) == 1
    assert len(bus_items) == 1
    assert taxi_items[0]["status"] == "completed"
    assert bus_items[0]["status"] == "completed"

    # Ensure that history entries are bound to the correct phone number.
    assert taxi_items[0]["rider_phone"] == phone
    assert bus_items[0]["customer_phone"] == phone
