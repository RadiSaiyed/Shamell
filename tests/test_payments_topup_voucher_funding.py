from __future__ import annotations

import uuid
from datetime import datetime, timezone

from sqlalchemy import create_engine, select
from sqlalchemy.orm import Session

import apps.payments.app.main as pay  # type: ignore[import]


class _DummyReq:
    def __init__(self, headers: dict[str, str]):
        self.headers = headers


class _ReqWithHeaders:
    def __init__(self, ikey: str | None):
        self._headers = {"Idempotency-Key": ikey} if ikey else {}

    def headers(self):
        return self._headers


def _make_wallet(s: Session, phone: str, balance: int) -> str:
    u = pay.User(id=str(uuid.uuid4()), phone=phone)
    s.add(u)
    s.commit()
    s.refresh(u)
    w = pay.Wallet(id=str(uuid.uuid4()), user_id=u.id, balance_cents=balance, currency=pay.DEFAULT_CURRENCY)
    s.add(w)
    s.commit()
    s.refresh(w)
    return w.id


def test_topup_batch_funds_and_redeems_from_reserve():
    engine = create_engine(
        "sqlite+pysqlite:///:memory:", connect_args={"check_same_thread": False}, pool_pre_ping=True
    )
    pay.Base.metadata.create_all(engine)
    with Session(engine) as s:
        funding_wallet = _make_wallet(s, "+491700100000", 100_000)
        target_wallet = _make_wallet(s, "+491700100001", 0)

        # Create funded batch of 2 vouchers @ 10_000 each
        batch_req = pay.TopupBatchCreateReq(amount_cents=10_000, count=2, funding_wallet_id=funding_wallet)
        resp = pay.topup_batch_create(req=batch_req, s=s, admin_ok=True)
        assert resp["items"] and len(resp["items"]) == 2

        # Funding wallet debited upfront
        fw = s.get(pay.Wallet, funding_wallet)
        assert fw.balance_cents == 80_000

        code = resp["items"][0]["code"]
        sig = resp["items"][0]["sig"]

        # Redeem first voucher
        redeem_req = pay.TopupRedeemReq(code=code, amount_cents=10_000, sig=sig, to_wallet_id=target_wallet)
        out = pay.topup_redeem(req=redeem_req, request=_DummyReq({"Idempotency-Key": "k1"}), s=s)  # type: ignore[arg-type]
        assert out["ok"] is True

        # Target wallet credited
        tw = s.get(pay.Wallet, target_wallet)
        assert tw.balance_cents == 10_000

        # Voucher marked redeemed and reserve released
        tv = s.scalar(select(pay.TopupVoucher).where(pay.TopupVoucher.code == code))
        assert tv and tv.status == "redeemed"
        # External reserve release ledger exists
        entries = list(s.execute(select(pay.LedgerEntry).where(pay.LedgerEntry.description == "voucher_redeem_external_release")).scalars())
        assert entries, "expected external reserve release ledger entry"

    # Idempotent retry cannot switch wallet: reuse same session with Idempotency-Key
    retry_req_same = pay.TopupRedeemReq(code=code, amount_cents=10_000, sig=sig, to_wallet_id=target_wallet)
    out_idem = pay.topup_redeem(req=retry_req_same, request=_DummyReq({"Idempotency-Key": "k1"}), s=s)  # type: ignore[arg-type]
    assert out_idem["wallet_id"] == target_wallet

    retry_req_diff = pay.TopupRedeemReq(code=code, amount_cents=10_000, sig=sig, to_wallet_id=funding_wallet)
    try:
        pay.topup_redeem(req=retry_req_diff, request=_DummyReq({"Idempotency-Key": "k1"}), s=s)  # type: ignore[arg-type]
    except Exception as e:  # noqa: BLE001
        assert "wallet" in str(e).lower()
    else:
        assert False, "retry with different wallet should fail"
