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
  Minimal Request-like object that only exposes headers for the
  Payments transfer/topup functions that expect a FastAPI Request.
  """

  def __init__(self, headers: Dict[str, str] | None = None):
    scope = {"type": "http", "headers": []}
    super().__init__(scope)
    # FastAPI/Starlette normalise header names to lowercase; a simple dict is enough here.
    self._test_headers = {k: v for k, v in (headers or {}).items()}

  @property  # type: ignore[override]
  def headers(self) -> Dict[str, str]:
    return self._test_headers


@pytest.fixture()
def payments_engine(tmp_path):
  """
  Isolated SQLite engine just for these tests.
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


def test_transfer_debits_and_credits_wallets(payments_engine):
  """
  Direct domain test for Payments.transfer:

  - create wallets A and B with initial balance
  - call transfer()
  - ensure that:
    - A is debited by amount
    - B is credited by amount (net of fees)
    - exactly one Txn is written
  """
  engine = payments_engine

  with Session(engine) as s:
    wa = _create_wallet(s, "+491700000001", 50_000)
    wb = _create_wallet(s, "+491700000002", 5_000)

    amount = 10_000
    req = pay.TransferReq(
        from_wallet_id=wa,
        to_wallet_id=wb,
        amount_cents=amount,
    )
    resp = pay.transfer(req=req, request=_DummyRequest(), s=s)

    # Response represents receiver wallet (net after fees)
    assert resp.wallet_id == wb
    fee_bps = getattr(pay, "MERCHANT_FEE_BPS", 0)
    expected_fee = (amount * fee_bps) // 10_000 if fee_bps > 0 else 0
    expected_net = amount - expected_fee
    assert resp.balance_cents == 5_000 + expected_net

    # Read back directly from DB
    from_w = s.get(pay.Wallet, wa)
    to_w = s.get(pay.Wallet, wb)
    assert from_w is not None and to_w is not None
    assert from_w.balance_cents == 50_000 - amount
    assert to_w.balance_cents == 5_000 + expected_net

    # Exactly one Txn with expected direction
    txns = s.execute(select(pay.Txn)).scalars().all()
    assert len(txns) == 1
    t = txns[0]
    assert t.from_wallet_id == wa
    assert t.to_wallet_id == wb
    assert t.amount_cents == 10_000
    assert t.kind == "transfer"


def test_transfer_idempotency_with_same_key(payments_engine):
  """
  Verify idempotency logic in Payments.transfer:

  - a transfer with an Idempotency-Key is executed
  - a second call with the same key must not create a second booking
    and must only return the receiver snapshot.
  """
  engine = payments_engine
  key = f"idem-{uuid.uuid4().hex[:8]}"

  # First execution
  with Session(engine) as s1:
    wa = _create_wallet(s1, "+491700000010", 30_000)
    wb = _create_wallet(s1, "+491700000011", 0)
    amount = 5_000
    req = pay.TransferReq(
        from_wallet_id=wa,
        to_wallet_id=wb,
        amount_cents=amount,
    )
    resp1 = pay.transfer(req=req, request=_DummyRequest({"Idempotency-Key": key}), s=s1)
    assert resp1.wallet_id == wb

  # Second execution with same key
  with Session(engine) as s2:
    req2 = pay.TransferReq(
        from_wallet_id=wa,
        to_wallet_id=wb,
        amount_cents=amount,
    )
    resp2 = pay.transfer(req=req2, request=_DummyRequest({"Idempotency-Key": key}), s=s2)
    # Must also only return the current receiver snapshot
    assert resp2.wallet_id == wb

  # Both calls together must have created only one transaction
  with Session(engine) as s3:
    txns = s3.execute(select(pay.Txn)).scalars().all()
    assert len(txns) == 1
    t = txns[0]
    assert t.from_wallet_id == wa
    assert t.to_wallet_id == wb
    assert t.amount_cents == amount

    from_w = s3.get(pay.Wallet, wa)
    to_w = s3.get(pay.Wallet, wb)
    assert from_w is not None and to_w is not None
    # Only a single debit/credit (including fees)
    fee_bps = getattr(pay, "MERCHANT_FEE_BPS", 0)
    expected_fee = (amount * fee_bps) // 10_000 if fee_bps > 0 else 0
    expected_net = amount - expected_fee
    assert from_w.balance_cents == 30_000 - amount
    assert to_w.balance_cents == expected_net
