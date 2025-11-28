from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import Dict, List, Optional
import time

app = FastAPI(title="Payments Stub")

class Wallet(BaseModel):
    id: str
    balance_cents: int = 0
    currency: str = "SYP"

class Txn(BaseModel):
    id: str
    wallet_id: str
    amount_cents: int
    reference: str = ""
    created_at: str

_wallets: Dict[str, Wallet] = {}
_phone_wallet: Dict[str, str] = {}
_txns: Dict[str, List[Txn]] = {}
_seq = {"user": 0, "txn": 0}
_idempotency: Dict[str, str] = {}

def _now_iso():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

def _new_txn_id() -> str:
    _seq["txn"] += 1
    return f"t{_seq['txn']}"

def _ensure_wallet(wid: str) -> Wallet:
    if wid not in _wallets:
        _wallets[wid] = Wallet(id=wid)
    if wid not in _txns:
        _txns[wid] = []
    return _wallets[wid]

def _amount_from(body: dict) -> int:
    if body is None:
        return 0
    if "amount_cents" in body and isinstance(body["amount_cents"], int):
        return int(body["amount_cents"])
    amt = body.get("amount")
    try:
        # amount is major units (SYP) float-like string
        return int(round(float(str(amt)) * 100))
    except Exception:
        return 0

@app.post("/users")
def create_user(body: dict):
    phone = str((body or {}).get("phone") or "").strip()
    if not phone:
        raise HTTPException(400, "phone required")
    if phone in _phone_wallet:
        wid = _phone_wallet[phone]
    else:
        _seq["user"] += 1
        wid = f"w{_seq['user']}"
        _ensure_wallet(wid)
        _phone_wallet[phone] = wid
    return {"wallet_id": wid, "phone": phone}

@app.get("/resolve/phone/{phone}")
def resolve_phone(phone: str):
    wid = _phone_wallet.get(phone)
    if not wid:
        raise HTTPException(404, "phone not found")
    return {"wallet_id": wid}

@app.get("/wallets/{wallet_id}")
def get_wallet(wallet_id: str):
    w = _ensure_wallet(wallet_id)
    return w.dict()

@app.post("/wallets/{wallet_id}/topup")
def topup(wallet_id: str, body: dict):
    ik = body.get("_ik") or None
    if ik and ik in _idempotency:
        return {"idempotent": True}
    w = _ensure_wallet(wallet_id)
    cents = _amount_from(body)
    if cents <= 0:
        raise HTTPException(400, "amount required")
    w.balance_cents += cents
    tid = _new_txn_id()
    _txns[wallet_id].insert(0, Txn(id=tid, wallet_id=wallet_id, amount_cents=cents, reference="topup", created_at=_now_iso()))
    if ik:
        _idempotency[ik] = tid
    return {"id": tid, "wallet_id": wallet_id, "balance_cents": w.balance_cents}

@app.post("/transfer")
def transfer(body: dict):
    if not isinstance(body, dict):
        raise HTTPException(400, "invalid body")
    ik = body.get("Idempotency-Key") or body.get("idempotency_key") or None
    if ik and ik in _idempotency:
        return {"idempotent": True, "txn": _idempotency[ik]}
    from_w = str(body.get("from_wallet_id") or "").strip()
    to_w = str(body.get("to_wallet_id") or "").strip()
    if not from_w or not to_w:
        raise HTTPException(400, "wallets required")
    cents = _amount_from(body)
    if cents <= 0:
        raise HTTPException(400, "amount required")
    ref = str(body.get("reference") or "")
    fw = _ensure_wallet(from_w)
    tw = _ensure_wallet(to_w)
    fw.balance_cents -= cents
    tw.balance_cents += cents
    ts = _now_iso()
    t1 = Txn(id=_new_txn_id(), wallet_id=from_w, amount_cents=-cents, reference=ref, created_at=ts)
    t2 = Txn(id=_new_txn_id(), wallet_id=to_w, amount_cents=cents, reference=ref, created_at=ts)
    _txns[from_w].insert(0, t1)
    _txns[to_w].insert(0, t2)
    if ik:
        _idempotency[ik] = t2.id
    return {"ok": True, "reference": ref, "amount_cents": cents}

@app.get("/txns")
def list_txns(wallet_id: str, dir: str = "", limit: int = 20):
    _ensure_wallet(wallet_id)
    arr = list(_txns.get(wallet_id, []))
    if dir == "in":
        arr = [t for t in arr if t.amount_cents > 0]
    elif dir == "out":
        arr = [t for t in arr if t.amount_cents < 0]
    return [t.dict() for t in arr[:max(1, min(limit, 100))]]

# Initialize an ESCROW wallet for taxi settlement
_ensure_wallet("escrow")

