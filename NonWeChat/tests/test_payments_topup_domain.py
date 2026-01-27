from __future__ import annotations

import uuid
from typing import Dict

import pytest
from fastapi import Request
from sqlalchemy import create_engine, select
from sqlalchemy.orm import Session

import apps.payments.app.main as pay  # type: ignore[import]


class _DummyRequest(Request):
    """
    Minimal Request-like object that only exposes headers for Payments
    functions that expect a FastAPI Request.
    """

    def __init__(self, headers: Dict[str, str] | None = None):
        scope = {"type": "http", "headers": []}
        super().__init__(scope)
        self._test_headers = {k: v for k, v in (headers or {}).items()}

    @property  # type: ignore[override]
    def headers(self) -> Dict[str, str]:
        return self._test_headers


@pytest.fixture()
def payments_engine():
    """
    Isolated SQLite engine for topup tests.
    Uses the Payments models without modifying the global engine.
    """

    engine = create_engine(
        "sqlite+pysqlite:///:memory:",
        connect_args={"check_same_thread": False},
        pool_pre_ping=True,
    )
    pay.Base.metadata.create_all(engine)
    return engine


def _create_wallet(session: Session, phone: str, balance_cents: int) -> str:
    u = pay.User(id=str(uuid.uuid4()), phone=phone)
    w = pay.Wallet(
        id=str(uuid.uuid4()),
        user_id=u.id,
        balance_cents=balance_cents,
        currency=pay.DEFAULT_CURRENCY,
    )
    session.add(u)
    session.add(w)
    session.commit()
    session.refresh(w)
    return w.id


def test_topup_increases_balance_and_writes_ledger(payments_engine):
    """
    Domain test for topup():

    - create a wallet with initial balance
    - call topup() directly (admin_ok=True)
    - ensure that:
      - balance increases by amount_cents
      - a Txn with kind='topup' is written
      - two ledger entries exist (wallet credit + external debit)
    """
    engine = payments_engine
    amount = 12_345

    with Session(engine) as s:
        wid = _create_wallet(s, "+491700000100", 1_000)
        req = pay.TopupReq(amount_cents=amount)
        resp = pay.topup(
            wallet_id=wid,
            req=req,
            request=_DummyRequest(),
            s=s,
            admin_ok=True,
        )

        assert resp.wallet_id == wid
        assert resp.balance_cents == 1_000 + amount

        # Check directly from DB
        w = s.get(pay.Wallet, wid)
        assert w is not None
        assert w.balance_cents == 1_000 + amount

        txns = s.execute(select(pay.Txn)).scalars().all()
        assert len(txns) == 1
        t = txns[0]
        assert t.to_wallet_id == wid
        assert t.amount_cents == amount
        assert t.kind == "topup"

        # Ledger: one credit for wallet, one debit for external (wallet_id=None)
        entries = s.execute(select(pay.LedgerEntry)).scalars().all()
        assert len(entries) == 2
        wallet_credits = [e for e in entries if e.wallet_id == wid and e.amount_cents > 0]
        extern_debits = [e for e in entries if e.wallet_id is None and e.amount_cents < 0]
        assert len(wallet_credits) == 1
        assert len(extern_debits) == 1


def test_topup_idempotency_with_same_key(payments_engine):
    """
    Check idempotency for topup():

    - topup() is called with an Idempotency-Key
    - a second call with the same key must not create a second booking
      and only returns the current wallet snapshot.
    """
    engine = payments_engine
    amount = 5_000
    key = f"topup-{uuid.uuid4().hex[:8]}"

    # First call
    with Session(engine) as s1:
        wid = _create_wallet(s1, "+491700000200", 0)
        req = pay.TopupReq(amount_cents=amount)
        resp1 = pay.topup(
            wallet_id=wid,
            req=req,
            request=_DummyRequest({"Idempotency-Key": key}),
            s=s1,
            admin_ok=True,
        )
        assert resp1.wallet_id == wid
        assert resp1.balance_cents == amount

    # Second call with same key
    with Session(engine) as s2:
        req2 = pay.TopupReq(amount_cents=amount)
        resp2 = pay.topup(
            wallet_id=wid,
            req=req2,
            request=_DummyRequest({"Idempotency-Key": key}),
            s=s2,
            admin_ok=True,
        )
        # Must return the same final balance
        assert resp2.wallet_id == wid
        assert resp2.balance_cents == amount

    # Only one Txn may exist and the balance must only have been increased once
    with Session(engine) as s3:
        txns = s3.execute(select(pay.Txn)).scalars().all()
        assert len(txns) == 1
        t = txns[0]
        assert t.to_wallet_id == wid
        assert t.amount_cents == amount
        assert t.kind == "topup"

        w = s3.get(pay.Wallet, wid)
        assert w is not None
        assert w.balance_cents == amount
