from __future__ import annotations

from typing import Any, Dict, List

import apps.bff.app.main as bff  # type: ignore[import]
import httpx


class _DummySessionCtx:
    def __enter__(self) -> object:  # pragma: no cover - trivial
        return object()

    def __exit__(self, exc_type, exc, tb) -> bool:  # pragma: no cover - trivial
        return False


class _RideResult:
    def __init__(self, price_cents: int, rider_wallet_id: str, driver_wallet_id: str) -> None:
        self.price_cents = price_cents
        self.rider_wallet_id = rider_wallet_id
        self.driver_wallet_id = driver_wallet_id
        self.rider_phone = "+491700000123"

    def dict(self) -> Dict[str, Any]:
        return {
            "price_cents": self.price_cents,
            "rider_wallet_id": self.rider_wallet_id,
            "driver_wallet_id": self.driver_wallet_id,
            "rider_phone": self.rider_phone,
        }


def test_taxi_story_payout_guardrail_not_hit_for_single_complete(client, monkeypatch):
    """
    Story: Rider books taxi and completes ride once.

    - With a normal TAXI_PAYOUT_MAX_PER_DRIVER_DAY, a single completion
      should:
        - succeed (HTTP 200)
        - trigger exactly two escrow transfers rider->escrow and escrow->driver
        - not trigger the payout guardrail.
    """

    driver_id = "drv_story"
    ride_id = "ride_story_1"
    price_cents = 80_000

    # Taxi internals
    monkeypatch.setattr(bff, "_use_taxi_internal", lambda: True, raising=False)
    monkeypatch.setattr(bff, "_TAXI_INTERNAL_AVAILABLE", True, raising=False)
    monkeypatch.setattr(bff, "_taxi_internal_session", lambda: _DummySessionCtx(), raising=False)

    def fake_complete_ride(
        ride_id: str,
        driver_id: str,
        request: object | None = None,
        s: object | None = None,
        **kwargs: Any,
    ):
        return _RideResult(price_cents=price_cents, rider_wallet_id="w_rider_story", driver_wallet_id="w_driver_story")

    monkeypatch.setattr(bff, "_taxi_complete_ride", fake_complete_ride, raising=False)

    # Guardrail and escrow configuration
    monkeypatch.setattr(bff, "ESCROW_WALLET_ID", "w_escrow_story", raising=False)
    monkeypatch.setattr(bff, "PAYMENTS_BASE", "http://payments.local", raising=False)
    monkeypatch.setattr(bff, "TAXI_PAYOUT_MAX_PER_DRIVER_DAY", 10, raising=False)

    calls: List[Dict[str, Any]] = []

    def fake_post(url: str, json: Any | None = None, headers: Dict[str, str] | None = None, timeout: float = 10.0) -> httpx.Response:  # type: ignore[override]
        # Only capture transfer calls; other posts are not expected here.
        if url.endswith("/transfer"):
            calls.append(
                {
                    "url": url,
                    "json": json or {},
                    "headers": headers or {},
                }
            )
        # Minimal dummy Response for FastAPI/httpx
        resp = httpx.Response(status_code=200, json={"status": "ok"})
        return resp

    monkeypatch.setattr(httpx, "post", fake_post)

    admin_phone = "+491700000099"
    monkeypatch.setenv("BFF_ADMINS", admin_phone)
    bff.BFF_ADMINS.add(admin_phone)
    resp = client.post(
        f"/taxi/rides/{ride_id}/complete",
        params={"driver_id": driver_id},
        headers={"X-Test-Phone": admin_phone},
    )
    assert resp.status_code == 200

    # Guardrail should not fire for a single completion; we expect two transfers.
    assert len(calls) == 2
    by_pair = {(c["json"].get("from_wallet_id"), c["json"].get("to_wallet_id")): c for c in calls}
    assert ("w_rider_story", "w_escrow_story") in by_pair
    assert ("w_escrow_story", "w_driver_story") in by_pair


def test_taxi_story_cancel_guardrail_blocks_after_limit(client, monkeypatch):
    """
    Story: Rider cancels multiple rides with the same driver.

    - With TAXI_CANCEL_MAX_PER_DRIVER_DAY=1:
        * First cancel triggers one fee transfer rider->driver.
        * Second cancel on same driver does not trigger another transfer
          and relies on the guardrail instead.
    """

    driver_id = "drv_story_cancel"
    ride_ids = ["ride_cancel_story_1", "ride_cancel_story_2"]

    monkeypatch.setattr(bff, "_use_taxi_internal", lambda: True, raising=False)
    monkeypatch.setattr(bff, "_TAXI_INTERNAL_AVAILABLE", True, raising=False)
    monkeypatch.setattr(bff, "_taxi_internal_session", lambda: _DummySessionCtx(), raising=False)

    def fake_cancel_ride(ride_id: str, request: object | None = None, s: object | None = None, **kwargs: Any):
        return {"id": ride_id, "status": "cancelled"}

    def fake_get_ride(ride_id: str, request: object | None = None, s: object | None = None, **kwargs: Any):
        # Always return same driver/wallets, only ride_id differs.
        return {
            "id": ride_id,
            "driver_id": driver_id,
            "driver_wallet_id": "w_driver_story",
            "rider_wallet_id": "w_rider_story",
            "rider_phone": "+491700000555",
        }

    monkeypatch.setattr(bff, "_taxi_cancel_ride", fake_cancel_ride, raising=False)
    monkeypatch.setattr(bff, "_taxi_get_ride", fake_get_ride, raising=False)

    # Guardrail: only one cancel-fee transfer per driver per day.
    monkeypatch.setattr(bff, "TAXI_CANCEL_FEE_SYP", 4000, raising=False)
    monkeypatch.setattr(bff, "TAXI_CANCEL_MAX_PER_DRIVER_DAY", 1, raising=False)
    monkeypatch.setattr(bff, "PAYMENTS_BASE", "http://payments.local", raising=False)

    calls: List[Dict[str, Any]] = []

    def fake_post(url: str, json: Any | None = None, headers: Dict[str, str] | None = None, timeout: float = 10.0) -> httpx.Response:  # type: ignore[override]
        if url.endswith("/transfer"):
            calls.append(
                {
                    "url": url,
                    "json": json or {},
                    "headers": headers or {},
                }
            )
        return httpx.Response(status_code=200, json={"status": "ok"})

    monkeypatch.setattr(httpx, "post", fake_post)

    # First cancel: should trigger one transfer.
    r1 = client.post(f"/taxi/rides/{ride_ids[0]}/cancel", headers={"X-Test-Phone": "+491700000555"})
    assert r1.status_code == 200

    # Second cancel: guardrail should block additional transfers.
    r2 = client.post(f"/taxi/rides/{ride_ids[1]}/cancel", headers={"X-Test-Phone": "+491700000555"})
    assert r2.status_code == 200

    # Exactly one transfer for both cancels combined.
    assert len(calls) == 1
    body = calls[0]["json"]
    assert body["from_wallet_id"] == "w_rider_story"
    assert body["to_wallet_id"] == "w_driver_story"


def test_taxi_story_payout_guardrail_blocks_after_limit(client, monkeypatch):
    """
    Story: Same driver completes multiple rides in one day.

    - With TAXI_PAYOUT_MAX_PER_DRIVER_DAY=1:
        * First completion triggers two escrow legs (rider->escrow, escrow->driver).
        * Second completion for the same driver does not trigger additional transfers
          because the payout guardrail skips settlement.
    """

    driver_id = "drv_story_payout_limit"
    ride_ids = ["ride_story_limit_1", "ride_story_limit_2"]
    price_cents = 50_000

    # Taxi internals via in-process helpers.
    monkeypatch.setattr(bff, "_use_taxi_internal", lambda: True, raising=False)
    monkeypatch.setattr(bff, "_TAXI_INTERNAL_AVAILABLE", True, raising=False)
    monkeypatch.setattr(bff, "_taxi_internal_session", lambda: _DummySessionCtx(), raising=False)

    def fake_complete_ride(
        ride_id: str,
        driver_id: str,
        request: object | None = None,
        s: object | None = None,
        **kwargs: Any,
    ):
        return _RideResult(
            price_cents=price_cents,
            rider_wallet_id="w_rider_story_limit",
            driver_wallet_id="w_driver_story_limit",
        )

    monkeypatch.setattr(bff, "_taxi_complete_ride", fake_complete_ride, raising=False)

    # Guardrail: only one payout settlement per driver per rolling day.
    monkeypatch.setattr(bff, "ESCROW_WALLET_ID", "w_escrow_story_limit", raising=False)
    monkeypatch.setattr(bff, "PAYMENTS_BASE", "http://payments.local", raising=False)
    monkeypatch.setattr(bff, "TAXI_PAYOUT_MAX_PER_DRIVER_DAY", 1, raising=False)
    # Reset in-memory payout events so previous tests do not interfere.
    monkeypatch.setattr(bff, "_TAXI_PAYOUT_EVENTS", {}, raising=False)

    calls: List[Dict[str, Any]] = []

    def fake_post(url: str, json: Any | None = None, headers: Dict[str, str] | None = None, timeout: float = 10.0) -> httpx.Response:  # type: ignore[override]
        if url.endswith("/transfer"):
            calls.append(
                {
                    "url": url,
                    "json": json or {},
                    "headers": headers or {},
                }
            )
        return httpx.Response(status_code=200, json={"status": "ok"})

    monkeypatch.setattr(httpx, "post", fake_post)

    # First completion: should trigger two settlement transfers.
    admin_phone = "+491700000099"
    monkeypatch.setenv("BFF_ADMINS", admin_phone)
    bff.BFF_ADMINS.add(admin_phone)
    r1 = client.post(
        f"/taxi/rides/{ride_ids[0]}/complete",
        params={"driver_id": driver_id},
        headers={"X-Test-Phone": admin_phone},
    )
    assert r1.status_code == 200

    # Second completion: guardrail should block additional settlement legs.
    r2 = client.post(
        f"/taxi/rides/{ride_ids[1]}/complete",
        params={"driver_id": driver_id},
        headers={"X-Test-Phone": admin_phone},
    )
    assert r2.status_code == 200

    # Overall: still exactly two transfers (from first completion only).
    assert len(calls) == 2
    by_pair = {(c["json"].get("from_wallet_id"), c["json"].get("to_wallet_id")): c for c in calls}
    assert ("w_rider_story_limit", "w_escrow_story_limit") in by_pair
    assert ("w_escrow_story_limit", "w_driver_story_limit") in by_pair
