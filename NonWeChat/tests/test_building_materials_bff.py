from __future__ import annotations

from typing import Any, Dict, List

import apps.bff.app.main as bff  # type: ignore[import]


def test_building_materials_alias_uses_commerce_products(client, monkeypatch):
  # Prepare a fake commerce_products implementation that captures calls.
  calls: List[Dict[str, Any]] = []

  def fake_commerce_products(q: str = "", limit: int = 50):
    calls.append({"q": q, "limit": limit})
    return [{"id": 1, "name": "Cement 50kg", "price_cents": 250000, "currency": "SYP"}]

  monkeypatch.setattr(bff, "commerce_products", fake_commerce_products, raising=False)

  resp = client.get("/building/materials?q=cement&limit=25")
  assert resp.status_code == 200
  data = resp.json()
  assert isinstance(data, list)
  assert data and data[0]["name"] == "Cement 50kg"

  assert calls == [{"q": "cement", "limit": 25}]

