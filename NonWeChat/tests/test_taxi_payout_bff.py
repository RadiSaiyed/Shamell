from __future__ import annotations

from typing import Any, Dict, List

import apps.bff.app.main as bff  # type: ignore[import]
import httpx


class _DummyResp:
  def __init__(self, status_code: int = 200) -> None:
      self.status_code = status_code
      self.headers: Dict[str, str] = {"content-type": "application/json"}

  def json(self) -> Dict[str, Any]:  # pragma: no cover - trivial
      return {"status": "ok"}


class _DummySessionCtx:
  def __enter__(self) -> object:  # pragma: no cover - trivial
      return object()

  def __exit__(self, exc_type, exc, tb) -> bool:  # pragma: no cover - trivial
      return False


def _setup_taxi_complete_stub(monkeypatch, *, price_cents: int = 50_000) -> List[Dict[str, Any]]:
  """
  Stubs the Taxi completion + Payments transfer chain in the BFF so that
  /taxi/rides/{id}/complete can be tested deterministically without real
  Taxi or Payments services.

  Invariants we want to see:
  - exactly two /transfer calls
  - first: rider -> escrow, amount = price_cents
  - second: escrow -> driver, amount = price_cents
  """

  # Enable "internal" Taxi mode so the BFF calls the in-process helpers
  # instead of HTTP Taxi.
  monkeypatch.setattr(bff, "_use_taxi_internal", lambda: True, raising=False)
  monkeypatch.setattr(bff, "_TAXI_INTERNAL_AVAILABLE", True, raising=False)

  # Fake result object returned by the internal Taxi completion.
  class _RideResult:
      def __init__(self) -> None:
          self.price_cents = price_cents
          self.rider_wallet_id = "w_rider"
          self.driver_wallet_id = "w_driver"
          self.rider_phone = "+491700000001"

      def dict(self) -> Dict[str, Any]:
          return {
              "price_cents": self.price_cents,
              "rider_wallet_id": self.rider_wallet_id,
              "driver_wallet_id": self.driver_wallet_id,
              "rider_phone": self.rider_phone,
          }

  def fake_complete_ride(
      ride_id: str,
      driver_id: str,
      request: object | None = None,
      s: object | None = None,
      **kwargs: Any,
  ):
      # Signature approximates the real Taxi endpoint; body is constant.
      return _RideResult()

  monkeypatch.setattr(bff, "_taxi_complete_ride", fake_complete_ride, raising=False)
  monkeypatch.setattr(bff, "_taxi_internal_session", lambda: _DummySessionCtx(), raising=False)

  # Ensure escrow + payments are configured so settlement branch executes.
  monkeypatch.setattr(bff, "ESCROW_WALLET_ID", "w_escrow", raising=False)
  monkeypatch.setattr(bff, "PAYMENTS_BASE", "http://payments.local", raising=False)
  # Set guardrail limits generously so this setup path does not trigger them.
  monkeypatch.setattr(bff, "TAXI_PAYOUT_MAX_PER_DRIVER_DAY", 1_000_000, raising=False)

  calls: List[Dict[str, Any]] = []

  def fake_post(url: str, json: Any | None = None, headers: Dict[str, str] | None = None, timeout: float = 10.0) -> _DummyResp:  # type: ignore[override]
      # Only capture /transfer calls; other httpx.post usages are not expected here.
      calls.append({"url": url, "json": json or {}, "headers": headers or {}})
      return _DummyResp()

  monkeypatch.setattr(httpx, "post", fake_post)

  # No resolve/phone or driver lookup should be needed because wallets are
  # provided directly on the ride; still, make sure PAYMENTS_BASE is set to
  # avoid early failures in _payments_url.

  return calls


def test_taxi_complete_triggers_two_settlement_transfers_via_bff(client, monkeypatch):
  """
  Bank-like invariant for Taxi escrow settlement:

  Completing a ride via the BFF should result in exactly two Payments
  transfers when an escrow wallet is configured:
    1) rider -> escrow
    2) escrow -> driver
  both with the same amount.
  """

  calls = _setup_taxi_complete_stub(monkeypatch, price_cents=50_000)

  ride_id = "ride_123"
  driver_id = "drv_1"
  resp = client.post(f"/taxi/rides/{ride_id}/complete", params={"driver_id": driver_id})
  assert resp.status_code == 200

  # Two transfers: rider->escrow and escrow->driver.
  assert len(calls) == 2

  # Use order-insensitive checks and map by from/to pair.
  by_pair = {(c["json"].get("from_wallet_id"), c["json"].get("to_wallet_id")): c for c in calls}

  assert ("w_rider", "w_escrow") in by_pair
  assert ("w_escrow", "w_driver") in by_pair

  leg1 = by_pair[("w_rider", "w_escrow")]
  leg2 = by_pair[("w_escrow", "w_driver")]

  assert leg1["json"]["amount_cents"] == 50_000
  assert leg2["json"]["amount_cents"] == 50_000

  # Idempotency keys encode ride_id and amount so that retried requests
  # will still be idempotent at Payments level.
  key1 = leg1["headers"].get("Idempotency-Key", "")
  key2 = leg2["headers"].get("Idempotency-Key", "")

  assert f"tx-escrow-r-{ride_id}-" in key1
  assert f"tx-escrow-d-{ride_id}-" in key2
