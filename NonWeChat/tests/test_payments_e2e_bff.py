import uuid
from typing import Any, Dict, List

import pytest
from fastapi import HTTPException

import apps.bff.app.main as bff  # type: ignore[import]


class _DummySessionCtx:
    def __enter__(self) -> object:  # pragma: no cover - trivial
        return object()

    def __exit__(self, exc_type, exc, tb) -> bool:  # pragma: no cover - trivial
        return False


def _setup_fake_payments(monkeypatch) -> Dict[str, Any]:
    """
    Configure BFF payments helpers to use a simple in-memory state instead
    of the real Payments service. This allows us to exercise the BFF
    /payments/* endpoints end-to-end without a real DB.
    """

    state: Dict[str, Any] = {
        "wallets": {
            # system wallet for initial topups
            "sys": {"wallet_id": "sys", "balance_cents": 1_000_000, "currency": "SYP", "phone": "sys"},
        },
        "txns": [],  # type: List[Dict[str, Any]]
    }

    def _fake_use_internal() -> bool:
        return True

    def _fake_create_user(req_model, s: object):
        phone = getattr(req_model, "phone", "")
        wid = f"w_{phone}"
        w = state["wallets"].setdefault(
            wid,
            {"wallet_id": wid, "balance_cents": 0, "currency": "SYP", "phone": phone},
        )
        return {
            "user_id": f"u_{phone}",
            "wallet_id": w["wallet_id"],
            "phone": w["phone"],
            "balance_cents": w["balance_cents"],
            "currency": w["currency"],
        }

    def _fake_get_wallet(wallet_id: str, s: object):
        w = state["wallets"].get(wallet_id)
        if not w:
            raise HTTPException(status_code=404, detail="Wallet not found")
        return {
            "wallet_id": w["wallet_id"],
            "balance_cents": w["balance_cents"],
            "currency": w["currency"],
        }

    def _fake_transfer(req_model, request, s: object):
        from_id = getattr(req_model, "from_wallet_id", "")
        to_id = getattr(req_model, "to_wallet_id", "")
        amount = int(getattr(req_model, "amount_cents", 0))
        if amount <= 0:
            raise HTTPException(status_code=400, detail="amount must be > 0")
        fw = state["wallets"].get(from_id)
        tw = state["wallets"].get(to_id)
        if not fw or not tw:
            raise HTTPException(status_code=404, detail="Wallet not found")
        if fw["balance_cents"] < amount:
            raise HTTPException(status_code=400, detail="Insufficient funds")
        fw["balance_cents"] -= amount
        tw["balance_cents"] += amount
        state["txns"].append(
            {
                "id": f"txn_{uuid.uuid4().hex[:8]}",
                "from_wallet_id": from_id,
                "to_wallet_id": to_id,
                "amount_cents": amount,
                "fee_cents": 0,
                "kind": "transfer",
                "created_at": None,
            }
        )
        # BFF expects WalletResp of the *receiver* wallet
        return _fake_get_wallet(to_id, s)

    def _fake_list_txns(wallet_id: str, limit: int, s: object):
        items = [
            t
            for t in reversed(state["txns"])
            if t.get("from_wallet_id") == wallet_id or t.get("to_wallet_id") == wallet_id
        ]
        return items[: max(1, min(limit, 200))]

    monkeypatch.setattr(bff, "_use_pay_internal", _fake_use_internal)
    monkeypatch.setattr(bff, "_PAY_INTERNAL_AVAILABLE", True, raising=False)
    monkeypatch.setattr(bff, "_pay_internal_session", lambda: _DummySessionCtx())
    monkeypatch.setattr(bff, "_pay_create_user", _fake_create_user)
    monkeypatch.setattr(bff, "_pay_get_wallet", _fake_get_wallet)
    monkeypatch.setattr(bff, "_pay_transfer", _fake_transfer)
    monkeypatch.setattr(bff, "_pay_list_txns", _fake_list_txns)
    return state


def test_payments_basic_transfer_flow_via_bff(client, monkeypatch):
    """
    End-to-end over BFF only (no real Payments DB):

    - Create two users via /payments/users
    - Top up wallet A by transferring from synthetic 'sys' wallet
    - Transfer from A to B via /payments/transfer
    - Verify balances via /payments/wallets/{id} and /wallets/{id}/snapshot
    """

    state = _setup_fake_payments(monkeypatch)

    phone_a = f"+4917000{uuid.uuid4().hex[:6]}"
    phone_b = f"+4917001{uuid.uuid4().hex[:6]}"

    resp_a = client.post("/payments/users", json={"phone": phone_a})
    resp_b = client.post("/payments/users", json={"phone": phone_b})
    assert resp_a.status_code == 200
    assert resp_b.status_code == 200
    wa = resp_a.json()["wallet_id"]
    wb = resp_b.json()["wallet_id"]

    # Top up A from system wallet 'sys'
    topup_amount = 10_000
    resp_topup = client.post(
        "/payments/transfer",
        json={
            "from_wallet_id": "sys",
            "to_wallet_id": wa,
            "amount_cents": topup_amount,
        },
    )
    assert resp_topup.status_code == 200

    # Check balances via BFF payments endpoint
    wa_info = client.get(f"/payments/wallets/{wa}").json()
    wb_info = client.get(f"/payments/wallets/{wb}").json()

    assert wa_info["balance_cents"] == topup_amount
    assert wb_info["balance_cents"] == 0

    # Transfer from A to B
    transfer_amount = 4_000
    resp_tx = client.post(
        "/payments/transfer",
        json={
            "from_wallet_id": wa,
            "to_wallet_id": wb,
            "amount_cents": transfer_amount,
        },
    )
    assert resp_tx.status_code == 200

    # Verify balances via generic wallet snapshot (uses _pay_get_wallet + _pay_list_txns)
    snap_a = client.get(f"/wallets/{wa}/snapshot").json()
    snap_b = client.get(f"/wallets/{wb}/snapshot").json()
    bal_a = snap_a["wallet"]["balance_cents"]
    bal_b = snap_b["wallet"]["balance_cents"]

    assert bal_a == topup_amount - transfer_amount
    assert bal_b == transfer_amount

