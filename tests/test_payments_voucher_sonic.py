from __future__ import annotations

import uuid
from typing import Dict

import apps.payments.app.main as pay  # type: ignore[import]
import pytest
from fastapi import Request
from sqlalchemy import create_engine, select
from sqlalchemy.orm import Session
from datetime import datetime, timedelta, timezone


class _DummyRequest(Request):
    """Minimal Request-like object exposing headers only."""

    def __init__(self, headers: Dict[str, str] | None = None):
        scope = {"type": "http", "headers": []}
        super().__init__(scope)
        self._test_headers = {k: v for k, v in (headers or {}).items()}

    @property  # type: ignore[override]
    def headers(self) -> Dict[str, str]:
        return self._test_headers


def _engine():
    engine = create_engine(
        "sqlite+pysqlite:///:memory:",
        connect_args={"check_same_thread": False},
        pool_pre_ping=True,
    )
    pay.Base.metadata.create_all(engine)
    # Disable short TTL side effects for tests
    pay.SONIC_TTL_SECS = 30
    return engine


def _create_wallet(session: Session, phone: str, balance_cents: int) -> str:
    u = pay.User(id=str(uuid.uuid4()), phone=phone)
    w = pay.Wallet(id=str(uuid.uuid4()), user_id=u.id, balance_cents=balance_cents, currency=pay.DEFAULT_CURRENCY)
    session.add(u); session.add(w); session.commit(); session.refresh(w)
    return w.id


def test_topup_redeem_idempotent_once():
    eng = _engine()
    code = "ABC12345"
    amount = 7_000
    ikey = f"idem-voucher-{uuid.uuid4().hex[:8]}"
    with Session(eng) as s:
        wid = _create_wallet(s, "+491700001111", 0)
        tv = pay.TopupVoucher(
            id=str(uuid.uuid4()),
            code=code,
            amount_cents=amount,
            currency=pay.DEFAULT_CURRENCY,
            status="reserved",
            batch_id=str(uuid.uuid4()),
        )
        s.add(tv); s.commit()

    # First redeem
    with Session(eng) as s1:
        req = pay.TopupRedeemReq(code=code, amount_cents=amount, sig=pay._voucher_sig(code, amount), to_wallet_id=wid)  # type: ignore[attr-defined]
        resp1 = pay.topup_redeem(req=req, request=_DummyRequest({"Idempotency-Key": ikey}), s=s1)  # type: ignore[arg-type]
        assert resp1["ok"] is True

    # Second redeem with same Idempotency-Key must not double-credit
    with Session(eng) as s2:
        req2 = pay.TopupRedeemReq(code=code, amount_cents=amount, sig=pay._voucher_sig(code, amount), to_wallet_id=wid)  # type: ignore[attr-defined]
        resp2 = pay.topup_redeem(req=req2, request=_DummyRequest({"Idempotency-Key": ikey}), s=s2)  # type: ignore[arg-type]
        assert resp2["ok"] is True

    with Session(eng) as s3:
        w = s3.get(pay.Wallet, wid)
        assert w is not None
        assert w.balance_cents == amount  # credited only once
        tv_db = s3.scalar(select(pay.TopupVoucher).where(pay.TopupVoucher.code == code))
        assert tv_db is not None
        assert tv_db.status == "redeemed"
        txns = s3.scalars(select(pay.Txn)).all()
        assert len(txns) == 1


def test_sonic_issue_and_redeem_idempotent():
    eng = _engine()
    amt = 5_000
    ikey = f"idem-sonic-{uuid.uuid4().hex[:8]}"
    with Session(eng) as s:
        from_w = _create_wallet(s, "+491700002222", 10_000)
        to_w = _create_wallet(s, "+491700002223", 0)

    with Session(eng) as s1:
        issue_req = pay.SonicIssueReq(from_wallet_id=from_w, amount_cents=amt, currency=pay.DEFAULT_CURRENCY)
        issued = pay.sonic_issue(issue_req, s=s1, admin_ok=True)  # type: ignore[arg-type]
        # reserve deducted
        fw = s1.get(pay.Wallet, from_w)
        assert fw.balance_cents == 10_000 - amt

    # Redeem once
    with Session(eng) as s2:
        redeem_req = pay.SonicRedeemReq(token=issued.token, to_wallet_id=to_w)
        resp1 = pay.sonic_redeem(redeem_req, request=_DummyRequest({"Idempotency-Key": ikey}), s=s2)
        assert resp1.wallet_id == to_w

    # Redeem again with same key (must be idempotent)
    with Session(eng) as s3:
        redeem_req2 = pay.SonicRedeemReq(token=issued.token, to_wallet_id=to_w)
        resp2 = pay.sonic_redeem(redeem_req2, request=_DummyRequest({"Idempotency-Key": ikey}), s=s3)
        assert resp2.wallet_id == to_w

    with Session(eng) as s4:
        tw = s4.get(pay.Wallet, to_w)
        assert tw.balance_cents == amt  # credited only once
        st = s4.scalar(select(pay.SonicToken))
        assert st is not None and st.status == "redeemed"
        txns = s4.scalars(select(pay.Txn)).all()
        assert len(txns) == 1


def test_sonic_token_expired_redeem_rejected():
    eng = _engine()
    amt = 500
    with Session(eng) as s:
        fw = _create_wallet(s, "+491700003333", 1_000)
        tw = _create_wallet(s, "+491700003334", 0)
        past = int((datetime.now(timezone.utc) - timedelta(seconds=5)).timestamp())
        payload = {"v": 1, "from": fw, "amt": amt, "ccy": pay.DEFAULT_CURRENCY, "exp": past, "n": "nonce"}
        token = pay._sonic_encode(payload)  # type: ignore[attr-defined]
        # still record the token to mimic issue flow
        st = pay.SonicToken(
            id=str(uuid.uuid4()),
            token_hash=pay._sonic_hash(token),  # type: ignore[attr-defined]
            from_wallet_id=fw,
            amount_cents=amt,
            currency=pay.DEFAULT_CURRENCY,
            status="reserved",
            expires_at=datetime.fromtimestamp(past, tz=timezone.utc),
            nonce="nonce",
        )
        s.add(st); s.commit()

    with Session(eng) as s2:
        redeem_req = pay.SonicRedeemReq(token=token, to_wallet_id=tw)
        with pytest.raises(Exception):
            pay.sonic_redeem(redeem_req, request=_DummyRequest(), s=s2)
