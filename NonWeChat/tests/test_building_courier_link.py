from __future__ import annotations

from typing import Any, Dict

import apps.bff.app.main as bff  # type: ignore[import]


def test_building_attach_shipment_requires_operator_and_valid_ids(client, monkeypatch, operator_taxi_auth):
  """
  Basic shaping test for /building/orders/{id}/attach_shipment:

    - requires operator role (freight)
    - validates that shipment exists (we stub the freight call)
    - stores mapping in _BUILDING_ORDER_SHIPMENTS
  """

  # Prepare a fake order getter that always returns a minimal order dict.
  def fake_get_order(request, order_id: int):
    return {"id": order_id, "status": "paid_escrow", "buyer_wallet_id": "w_buyer", "seller_wallet_id": "w_seller", "amount_cents": 10_000}

  monkeypatch.setattr(bff, "building_get_order", fake_get_order, raising=False)

  # Stub freight_get_shipment so the existence check passes.
  def fake_use_freight_internal() -> bool:
    return True

  def fake_internal_session():
    class _Ctx:
      def __enter__(self) -> object:  # pragma: no cover - trivial
        return object()

      def __exit__(self, exc_type, exc, tb) -> bool:  # pragma: no cover - trivial
        return False

    return _Ctx()

  def fake_get_shipment(sid: str, s: object) -> Dict[str, Any]:
    return {"id": sid, "status": "booked"}

  monkeypatch.setattr(bff, "_use_freight_internal", fake_use_freight_internal, raising=False)
  monkeypatch.setattr(bff, "_FREIGHT_INTERNAL_AVAILABLE", True, raising=False)
  monkeypatch.setattr(bff, "_freight_internal_session", fake_internal_session, raising=False)
  monkeypatch.setattr(bff, "_freight_get_shipment", fake_get_shipment, raising=False)

  # Ensure map is empty before.
  bff._BUILDING_ORDER_SHIPMENTS.clear()  # type: ignore[attr-defined]

  # Treat operator_taxi_auth as generic freight operator for this test.
  def fake_roles(phone: str) -> list[str]:
    if phone == operator_taxi_auth.phone:
      return ["operator_freight"]
    return []

  monkeypatch.setattr(bff, "_get_effective_roles", fake_roles, raising=False)

  # Call attach_shipment with operator auth.
  order_id = 123
  shipment_id = "ship-1"
  resp = client.post(
      f"/building/orders/{order_id}/attach_shipment",
      headers={"X-Test-Phone": operator_taxi_auth.phone},
      json={"shipment_id": shipment_id},
  )
  assert resp.status_code == 200
  data = resp.json()
  assert data["order_id"] == order_id
  assert data["shipment_id"] == shipment_id

  # Mapping should contain the link.
  assert bff._BUILDING_ORDER_SHIPMENTS.get(order_id) == shipment_id  # type: ignore[attr-defined]
