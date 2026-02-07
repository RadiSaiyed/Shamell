from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List

import apps.bff.app.main as bff


class _DummySessionCtx:
    def __enter__(self) -> object:  # pragma: no cover - trivial
        return object()

    def __exit__(self, exc_type, exc, tb) -> bool:  # pragma: no cover - trivial
        return False


def _make_tx(
    tid: str,
    wallet_id: str,
    *,
    kind: str,
    direction: str,
    days_ago: int = 0,
) -> Dict[str, Any]:
    base = datetime.now(timezone.utc) - timedelta(days=days_ago)
    iso = base.replace(microsecond=0).isoformat().replace("+00:00", "Z")
    if direction == "out":
        return {
            "id": tid,
            "kind": kind,
            "from_wallet_id": wallet_id,
            "to_wallet_id": "other",
            "amount_cents": 100,
            "created_at": iso,
        }
    return {
        "id": tid,
        "kind": kind,
        "from_wallet_id": "other",
        "to_wallet_id": wallet_id,
        "amount_cents": 100,
        "created_at": iso,
    }


def _setup_internal_txns(monkeypatch, wallet_id: str, txns: List[Dict[str, Any]]):
    """
    Configure payments_txns so that it only reads the supplied
    test transactions from the internal Payments API.
    """

    def fake_use_internal() -> bool:
        return True

    def fake_list_txns(wallet_id: str, limit: int, s: object):
        return txns

    monkeypatch.setattr(bff, "_use_pay_internal", lambda: True)
    monkeypatch.setattr(bff, "_PAY_INTERNAL_AVAILABLE", True, raising=False)
    monkeypatch.setattr(bff, "_pay_internal_session", lambda: _DummySessionCtx())
    monkeypatch.setattr(bff, "_pay_list_txns", fake_list_txns)


def test_payments_txns_dir_filter(monkeypatch):
    wallet_id = "w1"
    txns = [
        _make_tx("t_out", wallet_id, kind="transfer", direction="out", days_ago=1),
        _make_tx("t_in", wallet_id, kind="transfer", direction="in", days_ago=1),
    ]
    _setup_internal_txns(monkeypatch, wallet_id, txns)

    all_tx = bff.payments_txns(wallet_id=wallet_id, limit=10)
    ids_all = {t["id"] for t in all_tx}
    assert ids_all == {"t_out", "t_in"}

    out_tx = bff.payments_txns(wallet_id=wallet_id, limit=10, dir="out")
    ids_out = {t["id"] for t in out_tx}
    assert ids_out == {"t_out"}

    in_tx = bff.payments_txns(wallet_id=wallet_id, limit=10, dir="in")
    ids_in = {t["id"] for t in in_tx}
    assert ids_in == {"t_in"}


def test_payments_txns_kind_and_date_filter(monkeypatch):
    wallet_id = "w1"
    txns = [
        _make_tx("t_recent_transfer", wallet_id, kind="transfer", direction="out", days_ago=1),
        _make_tx("t_recent_cash", wallet_id, kind="cash_topup", direction="out", days_ago=1),
        _make_tx("t_old_transfer", wallet_id, kind="transfer", direction="out", days_ago=30),
    ]
    _setup_internal_txns(monkeypatch, wallet_id, txns)

    now = datetime.now(timezone.utc)
    from_iso = (now - timedelta(days=7)).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    to_iso = now.replace(microsecond=0).isoformat().replace("+00:00", "Z")

    # Nur "transfer"-Transaktionen der letzten 7 Tage
    filtered = bff.payments_txns(
        wallet_id=wallet_id,
        limit=10,
        dir="out",
        kind="transfer",
        from_iso=from_iso,
        to_iso=to_iso,
    )
    ids = {t["id"] for t in filtered}
    assert ids == {"t_recent_transfer"}
