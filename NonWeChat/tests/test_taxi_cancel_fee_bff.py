from __future__ import annotations

from typing import Any, Dict, List

import apps.bff.app.main as bff  # type: ignore[import]
import httpx


class _DummySessionCtx:
    def __enter__(self) -> object:  # pragma: no cover - trivial
        return object()

    def __exit__(self, exc_type, exc, tb) -> bool:  # pragma: no cover - trivial
        return False


class _DummyResp:
    def __init__(self, status_code: int = 200) -> None:
        self.status_code = status_code
        self.headers: Dict[str, str] = {"content-type": "application/json"}

    def json(self) -> Dict[str, Any]:  # pragma: no cover - trivial
        return {"status": "ok"}


def _setup_taxi_cancel_stub(monkeypatch, *, fee_syp: int = 4_000) -> List[Dict[str, Any]]:
    """
    Stub for the BFF endpoint /taxi/rides/{id}/cancel to test the
    cancel-fee logic (best-effort fee) in a bank-like way.

    We simulate:
    - a ride with driver_id, rider_wallet_id, driver_wallet_id
    - TAXI_CANCEL_FEE_SYP == fee_syp
    - PAYMENTS_BASE set so _payments_url works
    - httpx.post instrumented so we can capture the transfer call
    """

    # Force Taxi internal mode
    monkeypatch.setattr(bff, "_use_taxi_internal", lambda: True, raising=False)
    monkeypatch.setattr(bff, "_TAXI_INTERNAL_AVAILABLE", True, raising=False)
    monkeypatch.setattr(bff, "_taxi_internal_session", lambda: _DummySessionCtx(), raising=False)

    # The cancel handler itself is not interesting here, only that it does not crash.
    def fake_cancel_ride(ride_id: str, request: object | None = None, s: object | None = None, **kwargs: Any):
        return {"id": ride_id, "status": "cancelled"}

    # Ride details with IDs and wallets so no additional lookups are needed.
    def fake_get_ride(ride_id: str, request: object | None = None, s: object | None = None, **kwargs: Any):
        return {
            "id": ride_id,
            "driver_id": "drv_1",
            "driver_wallet_id": "w_driver",
            "rider_wallet_id": "w_rider",
            "rider_phone": "+491700000002",
        }

    monkeypatch.setattr(bff, "_taxi_cancel_ride", fake_cancel_ride, raising=False)
    monkeypatch.setattr(bff, "_taxi_get_ride", fake_get_ride, raising=False)

    # Configure cancel fee & Payments
    monkeypatch.setattr(bff, "TAXI_CANCEL_FEE_SYP", fee_syp, raising=False)
    # Set guardrail limits generously so this setup path does not trigger them.
    monkeypatch.setattr(bff, "TAXI_CANCEL_MAX_PER_DRIVER_DAY", 1_000_000, raising=False)
    monkeypatch.setattr(bff, "PAYMENTS_BASE", "http://payments.local", raising=False)

    calls: List[Dict[str, Any]] = []

    def fake_post(url: str, json: Any | None = None, headers: Dict[str, str] | None = None, timeout: float = 10.0) -> _DummyResp:  # type: ignore[override]
        # We expect exactly one transfer call to /transfer.
        calls.append({"url": url, "json": json or {}, "headers": headers or {}})
        return _DummyResp()

    monkeypatch.setattr(httpx, "post", fake_post)

    return calls


def test_taxi_cancel_triggers_single_fee_transfer_via_bff(client, monkeypatch):
    """
    Bank-like invariant for Taxi cancel fee:

    - With TAXI_CANCEL_FEE_SYP set and wallets present exactly one
      rider->driver transfer is triggered.
    - Amount = TAXI_CANCEL_FEE_SYP * 100
    - Idempotency-Key contains ride_id and amount.
    """

    fee_syp = 4_000
    calls = _setup_taxi_cancel_stub(monkeypatch, fee_syp=fee_syp)

    ride_id = "ride_cancel_1"
    resp = client.post(f"/taxi/rides/{ride_id}/cancel", headers={"X-Test-Phone": "+491700000002"})
    assert resp.status_code == 200

    # Exactly one transfer call.
    assert len(calls) == 1
    call = calls[0]

    assert call["url"].endswith("/transfer")
    body = call["json"]
    assert body["from_wallet_id"] == "w_rider"
    assert body["to_wallet_id"] == "w_driver"
    assert body["amount_cents"] == fee_syp * 100

    key = call["headers"].get("Idempotency-Key", "")
    assert f"tx-taxi-cancel-{ride_id}-" in key
