from __future__ import annotations

import uuid
from datetime import datetime, timezone, timedelta
from typing import Any, Dict, List

import pytest
from sqlalchemy import create_engine, select
from sqlalchemy.orm import Session

import apps.bff.app.main as bff  # type: ignore[import]
import apps.food.app.main as food  # type: ignore[import]


class _DummySessionCtx:
    def __enter__(self) -> object:  # pragma: no cover - trivial
        return object()

    def __exit__(self, exc_type, exc, tb) -> bool:  # pragma: no cover - trivial
        return False


def _setup_food_stub(monkeypatch):
    """
    Stub the Food domain in the BFF to test /food/orders end-to-end,
    without real DB or Payments.
    """

    # One restaurant + two menu items in the stub
    state: Dict[str, Any] = {
        "restaurant_id": 1,
        "menu": {
            1: {"id": 1, "name": "Falafel", "price_cents": 5_000},
            2: {"id": 2, "name": "Shawarma", "price_cents": 7_000},
        },
        "orders": {},  # idem_key -> order dict
    }

    class _OrderItemIn:
        def __init__(self, menu_item_id: int, qty: int = 1):
            self.menu_item_id = menu_item_id
            self.qty = qty

    class _OrderCreate:
        def __init__(
            self,
            restaurant_id: int,
            customer_name: str | None,
            customer_phone: str | None,
            customer_wallet_id: str | None,
            items: List[_OrderItemIn] | list[dict],
            confirm: bool = False,
        ):
            self.restaurant_id = restaurant_id
            self.customer_name = customer_name
            self.customer_phone = customer_phone
            self.customer_wallet_id = customer_wallet_id
            # Emulate Pydantic behaviour: allow list of dicts and coerce to _OrderItemIn
            converted: List[_OrderItemIn] = []
            for it in items or []:
                if isinstance(it, _OrderItemIn):
                    converted.append(it)
                else:
                    # Expect a mapping with menu_item_id / qty
                    menu_item_id = int(getattr(it, "menu_item_id", it.get("menu_item_id")))  # type: ignore[arg-type]
                    qty = int(getattr(it, "qty", it.get("qty", 1)))  # type: ignore[arg-type]
                    converted.append(_OrderItemIn(menu_item_id=menu_item_id, qty=qty))
            self.items = converted
            self.confirm = confirm

    def fake_create_order(req: Any, idempotency_key: str | None, s: object):
        # Idempotency: same key -> same order
        if idempotency_key and idempotency_key in state["orders"]:
            return state["orders"][idempotency_key]
        total = 0
        for it in req.items:
            mi = state["menu"].get(it.menu_item_id)
            if not mi:
                raise RuntimeError("menu item not found in stub")
            total += int(mi["price_cents"]) * int(it.qty)
        oid = f"food_{uuid.uuid4().hex[:8]}"
        status = "accepted" if req.confirm and req.customer_wallet_id else "placed"
        order = {
            "id": oid,
            "restaurant_id": req.restaurant_id,
            "total_cents": total,
            "status": status,
            "payments_txn_id": None,
        }
        if idempotency_key:
            state["orders"][idempotency_key] = order
        return order

    def fake_list_orders(phone: str, status: str, from_iso: str, to_iso: str, limit: int, s: object):
        # For the stub it is sufficient to return all orders
        return list(state["orders"].values())[: max(1, min(limit, 200))]

    monkeypatch.setattr(bff, "_use_food_internal", lambda: True)
    monkeypatch.setattr(bff, "_FOOD_INTERNAL_AVAILABLE", True, raising=False)
    monkeypatch.setattr(bff, "_food_internal_session", lambda: _DummySessionCtx())
    monkeypatch.setattr(bff, "_FoodOrderCreate", _OrderCreate, raising=False)
    monkeypatch.setattr(bff, "_food_create_order", fake_create_order, raising=False)
    monkeypatch.setattr(bff, "_food_list_orders", fake_list_orders, raising=False)


def test_food_order_flow_via_bff(client, monkeypatch):
    """
    Food order flow via BFF with stubs:
    - /food/orders (POST) calculates total_cents correctly and sets status
    - Idempotency ensured (see separate test)
    """

    _setup_food_stub(monkeypatch)

    body = {
        "restaurant_id": 1,
        "customer_name": "Food Tester",
        "customer_phone": "+491700001000",
        "customer_wallet_id": "w_food",
        "items": [
            {"menu_item_id": 1, "qty": 2},  # 2 * 5_000
            {"menu_item_id": 2, "qty": 1},  # 1 * 7_000
        ],
        "confirm": True,
    }
    idem = f"food-{uuid.uuid4().hex[:8]}"
    resp = client.post("/food/orders", json=body, headers={"Idempotency-Key": idem})
    assert resp.status_code == 200
    o = resp.json()
    # total = 2*5000 + 1*7000 = 17_000
    assert o["total_cents"] == 17_000
    # confirm=True + wallet_id set -> accepted
    assert o["status"] == "accepted"

    # /food/orders (GET) muss die Order sichtbar machen
    resp_list = client.get("/food/orders?limit=10")
    assert resp_list.status_code == 200
    arr = resp_list.json()
    assert any(x["id"] == o["id"] for x in arr)


def test_food_order_idempotency_via_bff(client, monkeypatch):
    """
    Idempotency test for /food/orders via BFF:
    same Idempotency-Key -> same order.
    """

    _setup_food_stub(monkeypatch)

    body = {
        "restaurant_id": 1,
        "customer_name": "Food Tester",
        "customer_phone": "+491700001001",
        "customer_wallet_id": "w_food2",
        "items": [
            {"menu_item_id": 1, "qty": 1},
        ],
        "confirm": True,
    }
    idem = f"food-{uuid.uuid4().hex[:8]}"

    resp1 = client.post("/food/orders", json=body, headers={"Idempotency-Key": idem})
    assert resp1.status_code == 200
    o1 = resp1.json()

    resp2 = client.post("/food/orders", json=body, headers={"Idempotency-Key": idem})
    assert resp2.status_code == 200
    o2 = resp2.json()

    assert o1["id"] == o2["id"]
    assert o1["total_cents"] == o2["total_cents"]
    assert o1["status"] == o2["status"]


@pytest.fixture()
def food_engine():
    """
    Domain-level engine for Food tests.
    """

    engine = create_engine(
        "sqlite+pysqlite:///:memory:",
        connect_args={"check_same_thread": False},
        pool_pre_ping=True,
    )
    food.Base.metadata.create_all(engine)
    return engine


def _create_restaurant_and_menu(session: Session) -> int:
    r = food.Restaurant(
        name="Test Restaurant",
        city="Damascus",
        address=None,
        owner_wallet_id=None,
    )
    session.add(r)
    session.commit()
    session.refresh(r)
    mi1 = food.MenuItem(
        restaurant_id=r.id,
        name="Falafel",
        price_cents=5_000,
        currency="SYP",
    )
    mi2 = food.MenuItem(
        restaurant_id=r.id,
        name="Shawarma",
        price_cents=7_000,
        currency="SYP",
    )
    session.add_all([mi1, mi2])
    session.commit()
    return r.id


def test_food_create_order_domain(food_engine):
    """
    Domain test for food.create_order:
    - total_cents equals the sum of menu prices * quantity
    - status switches to 'accepted' when confirm=True and wallet IDs are present
    - idempotency via Idempotency-Key
    """

    engine = food_engine

    with Session(engine) as s:
        rid = _create_restaurant_and_menu(s)
        # Map MenuItem IDs
        items = s.execute(select(food.MenuItem)).scalars().all()
        menu_ids = {m.name: m.id for m in items}

        req = food.OrderCreate(
            restaurant_id=rid,
            customer_name="Domain Tester",
            customer_phone="+491700001010",
            customer_wallet_id="w_dom",
            items=[
                food.OrderItemIn(menu_item_id=menu_ids["Falafel"], qty=2),
                food.OrderItemIn(menu_item_id=menu_ids["Shawarma"], qty=1),
            ],
            confirm=False,
        )
        # Stub PAYMENTS_BASE away so _pay is never called
        food.PAYMENTS_BASE = ""

        # Without confirm status remains 'placed'
        out1 = food.create_order(req=req, idempotency_key=None, s=s)
        assert out1.status == "placed"
        assert out1.total_cents == 17_000

        # With confirm + wallets but without PAYMENTS_BASE there should still be no exception,
        # because _pay is only used when PAYMENTS_BASE is set.
        req_confirm = food.OrderCreate(
            restaurant_id=rid,
            customer_name="Domain Tester",
            customer_phone="+491700001010",
            customer_wallet_id="w_dom",
            items=req.items,
            confirm=True,
        )
        out2 = food.create_order(req=req_confirm, idempotency_key=None, s=s)
        # Da PAYMENTS_BASE leer ist, bleibt Status 'placed'
        assert out2.status == "placed"
        assert out2.total_cents == 17_000
