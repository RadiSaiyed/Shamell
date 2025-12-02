from fastapi import FastAPI, HTTPException, Depends, Request, APIRouter
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field
from typing import Optional, List
import os, time, json, threading, logging
import httpx
from shamell_shared import RequestIDMiddleware, configure_cors, add_standard_health, setup_json_logging
from sqlalchemy import create_engine, String, Integer, DateTime, Boolean, func, select, or_
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, Session
from datetime import datetime, timezone, timedelta
import uuid
from typing import Set


def _env_or(key: str, default: str) -> str:
    v = os.getenv(key)
    return v if v is not None else default


app = FastAPI(title="Chat API", version="0.1.0")
setup_json_logging()
app.add_middleware(RequestIDMiddleware)
configure_cors(app, os.getenv("ALLOWED_ORIGINS", "*"))
add_standard_health(app)

router = APIRouter()


DB_URL = _env_or("DB_URL", "sqlite+pysqlite:////tmp/chat.db")
DB_SCHEMA = os.getenv("DB_SCHEMA") if not DB_URL.startswith("sqlite") else None
FCM_SERVER_KEY = os.getenv("FCM_SERVER_KEY", "")
FCM_ENDPOINT = "https://fcm.googleapis.com/fcm/send"
PURGE_INTERVAL_SECONDS = int(os.getenv("CHAT_PURGE_INTERVAL_SECONDS", "600"))
logger = logging.getLogger("chat")


class Base(DeclarativeBase):
    pass


class Device(Base):
    __tablename__ = "devices"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[str] = mapped_column(String(12), primary_key=True)  # short ID (e.g. 8–12 chars)
    public_key: Mapped[str] = mapped_column(String(255))  # base64
    name: Mapped[Optional[str]] = mapped_column(String(120), default=None)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Message(Base):
    __tablename__ = "messages"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    sender_id: Mapped[str] = mapped_column(String(12))
    recipient_id: Mapped[str] = mapped_column(String(12))
    sender_pubkey: Mapped[str] = mapped_column(String(255))  # copy of sender pubkey (for client verify)
    sender_dh_pub: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    nonce_b64: Mapped[str] = mapped_column(String(64))
    box_b64: Mapped[str] = mapped_column(String(8192))  # ciphertext
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())
    delivered_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), nullable=True)
    read_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), nullable=True)
    expire_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), nullable=True)
    sealed_sender: Mapped[bool] = mapped_column(Boolean, default=False)
    sender_hint: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    prev_key_id: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    key_id: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)


class PushToken(Base):
    __tablename__ = "push_tokens"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    device_id: Mapped[str] = mapped_column(String(24), index=True)
    token: Mapped[str] = mapped_column(String(512))
    platform: Mapped[Optional[str]] = mapped_column(String(30), default=None)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())
    last_seen_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())


class ContactRule(Base):
    __tablename__ = "contact_rules"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    device_id: Mapped[str] = mapped_column(String(24), index=True)  # owner
    peer_id: Mapped[str] = mapped_column(String(24), index=True)
    blocked: Mapped[bool] = mapped_column(default=False)
    hidden: Mapped[bool] = mapped_column(default=False)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())


engine = create_engine(DB_URL, future=True)


def get_session() -> Session:
    with Session(engine) as s:
        yield s


def _startup():
    Base.metadata.create_all(engine)
    _start_purge_thread()

app.router.on_startup.append(_startup)


class RegisterReq(BaseModel):
    device_id: str = Field(min_length=4, max_length=24)
    public_key_b64: str = Field(min_length=32)
    name: Optional[str] = None


class DeviceOut(BaseModel):
    device_id: str
    public_key_b64: str
    name: Optional[str]


@router.post("/devices/register", response_model=DeviceOut)
def register(req: RegisterReq, s: Session = Depends(get_session)):
    did = req.device_id.strip()
    if s.get(Device, did):
        # Update public key / name if changed
        d = s.get(Device, did)
        d.public_key = req.public_key_b64
        d.name = req.name
        s.add(d); s.commit(); s.refresh(d)
        return DeviceOut(device_id=d.id, public_key_b64=d.public_key, name=d.name)
    d = Device(id=did, public_key=req.public_key_b64, name=req.name)
    s.add(d); s.commit(); s.refresh(d)
    return DeviceOut(device_id=d.id, public_key_b64=d.public_key, name=d.name)


@router.get("/devices/{device_id}", response_model=DeviceOut)
def get_device(device_id: str, s: Session = Depends(get_session)):
    d = s.get(Device, device_id)
    if not d: raise HTTPException(status_code=404, detail="not found")
    return DeviceOut(device_id=d.id, public_key_b64=d.public_key, name=d.name)


class SendReq(BaseModel):
    sender_id: str
    recipient_id: str
    sender_pubkey_b64: str
    sender_dh_pub_b64: Optional[str] = None
    nonce_b64: str
    box_b64: str
    idempotency_key: Optional[str] = None
    expire_after_seconds: Optional[int] = Field(default=None, ge=10, le=7 * 24 * 3600)
    client_ts: Optional[str] = None
    sealed_sender: bool = False
    sender_hint: Optional[str] = None
    sender_fingerprint: Optional[str] = None
    key_id: Optional[str] = None
    prev_key_id: Optional[str] = None


class ContactRuleReq(BaseModel):
    peer_id: str = Field(min_length=4, max_length=24)
    blocked: bool = False
    hidden: bool = False


class MsgOut(BaseModel):
    id: str
    sender_id: Optional[str] = None
    recipient_id: str
    sender_pubkey_b64: Optional[str] = None
    sender_dh_pub_b64: Optional[str] = None
    nonce_b64: str
    box_b64: str
    created_at: Optional[str]
    delivered_at: Optional[str] = None
    read_at: Optional[str] = None
    expire_at: Optional[str] = None
    sealed_sender: bool = False
    sender_hint: Optional[str] = None
    sender_fingerprint: Optional[str] = None
    key_id: Optional[str] = None
    prev_key_id: Optional[str] = None


@router.post("/messages/send", response_model=MsgOut)
def send_message(req: SendReq, s: Session = Depends(get_session)):
    if not s.get(Device, req.sender_id) or not s.get(Device, req.recipient_id):
        raise HTTPException(status_code=404, detail="unknown device")
    if _is_blocked(s, device_id=req.recipient_id, peer_id=req.sender_id):
        raise HTTPException(status_code=403, detail="blocked by recipient")
    # naive idempotency: check if identical ciphertext exists recently
    existed = s.execute(select(Message).where(Message.sender_id == req.sender_id, Message.recipient_id == req.recipient_id, Message.nonce_b64 == req.nonce_b64, Message.box_b64 == req.box_b64).limit(1)).scalars().first()
    if existed:
        return MsgOut(id=existed.id, sender_id=existed.sender_id, recipient_id=existed.recipient_id, sender_pubkey_b64=existed.sender_pubkey, nonce_b64=existed.nonce_b64, box_b64=existed.box_b64, created_at=existed.created_at.isoformat() if existed.created_at else None, delivered_at=existed.delivered_at.isoformat() if existed.delivered_at else None, read_at=existed.read_at.isoformat() if existed.read_at else None, expire_at=existed.expire_at.isoformat() if existed.expire_at else None)
    mid = str(uuid.uuid4())
    exp_at = None
    if req.expire_after_seconds:
        try:
            exp_at = datetime.now(timezone.utc) + timedelta(seconds=int(req.expire_after_seconds))
        except Exception:
            exp_at = None
    hint = (req.sender_hint or req.sender_fingerprint) if req.sealed_sender else None
    sender_fp = req.sender_fingerprint if req.sealed_sender else None
    m = Message(id=mid, sender_id=req.sender_id, recipient_id=req.recipient_id, sender_pubkey=req.sender_pubkey_b64, sender_dh_pub=req.sender_dh_pub_b64, nonce_b64=req.nonce_b64, box_b64=req.box_b64, expire_at=exp_at, sealed_sender=req.sealed_sender, sender_hint=hint, key_id=req.key_id, prev_key_id=req.prev_key_id)
    s.add(m); s.commit(); s.refresh(m)
    _notify_recipient(recipient_id=req.recipient_id, message_id=mid, s=s)
    return MsgOut(id=m.id, sender_id=None if m.sealed_sender else m.sender_id, recipient_id=m.recipient_id, sender_pubkey_b64=None if m.sealed_sender else m.sender_pubkey, sender_dh_pub_b64=None if m.sealed_sender else m.sender_dh_pub, nonce_b64=m.nonce_b64, box_b64=m.box_b64, created_at=m.created_at.isoformat() if m.created_at else None, delivered_at=m.delivered_at.isoformat() if m.delivered_at else None, read_at=m.read_at.isoformat() if m.read_at else None, expire_at=m.expire_at.isoformat() if m.expire_at else None, sealed_sender=m.sealed_sender, sender_hint=m.sender_hint or sender_fp, sender_fingerprint=sender_fp or m.sender_hint, key_id=m.key_id, prev_key_id=m.prev_key_id)


@router.get("/messages/inbox", response_model=List[MsgOut])
def inbox(device_id: str, since_iso: Optional[str] = None, limit: int = 50, sealed_view: bool = True, s: Session = Depends(get_session)):
    if not s.get(Device, device_id):
        raise HTTPException(status_code=404, detail="unknown device")
    _purge_expired(s)
    blocked = _blocked_peers(s, device_id)
    hidden = _hidden_peers(s, device_id)
    q = select(Message).where(Message.recipient_id == device_id)
    if since_iso:
        try:
            ts = datetime.fromisoformat(since_iso.replace("Z", "+00:00"))
            q = q.where(Message.created_at >= ts)
        except Exception:
            raise HTTPException(status_code=400, detail="invalid since")
    now = datetime.now(timezone.utc)
    q = q.where(or_(Message.expire_at == None, Message.expire_at >= now))  # type: ignore[comparison-overlap]
    q = q.order_by(Message.created_at.desc()).limit(max(1, min(limit, 200)))
    rows = [r for r in s.execute(q).scalars().all() if r.sender_id not in blocked and r.sender_id not in hidden]
    # mark delivered
    now = datetime.now(timezone.utc)
    changed = False
    for r in rows:
        if r.delivered_at is None:
            r.delivered_at = now
            s.add(r)
            changed = True
    if changed:
        s.commit()
    out = []
    for r in rows:
        out.append(
            MsgOut(
                id=r.id,
                sender_id=None if (r.sealed_sender or sealed_view) else r.sender_id,
                recipient_id=r.recipient_id,
                sender_pubkey_b64=None if (r.sealed_sender or sealed_view) else r.sender_pubkey,
                sender_dh_pub_b64=r.sender_dh_pub,
                nonce_b64=r.nonce_b64,
                box_b64=r.box_b64,
                created_at=r.created_at.isoformat() if r.created_at else None,
                delivered_at=r.delivered_at.isoformat() if r.delivered_at else None,
                read_at=r.read_at.isoformat() if r.read_at else None,
                expire_at=r.expire_at.isoformat() if r.expire_at else None,
                sealed_sender=r.sealed_sender or sealed_view,
                sender_hint=r.sender_hint,
                sender_fingerprint=r.sender_hint,
                key_id=r.key_id,
                prev_key_id=r.prev_key_id,
            )
        )
    return out


@router.get("/messages/stream")
def stream(device_id: str, sealed_view: bool = True, s: Session = Depends(get_session)):
    # Basic SSE that polls every second for new messages
    if not s.get(Device, device_id):
        raise HTTPException(status_code=404, detail="unknown device")
    def _gen():
        last = datetime.now(timezone.utc)
        while True:
            time.sleep(1)
            _purge_expired(s)
            now = datetime.now(timezone.utc)
            blocked = _blocked_peers(s, device_id)
            hidden = _hidden_peers(s, device_id)
            rows = s.execute(select(Message).where(Message.recipient_id == device_id, Message.created_at >= last, or_(Message.expire_at == None, Message.expire_at >= now)).order_by(Message.created_at.asc()).limit(100)).scalars().all()  # type: ignore[comparison-overlap]
            rows = [r for r in rows if r.sender_id not in blocked and r.sender_id not in hidden]
            if rows:
                now = datetime.now(timezone.utc)
                changed = False
                for r in rows:
                    if r.delivered_at is None:
                        r.delivered_at = now
                        s.add(r)
                        changed = True
                if changed:
                    s.commit()
                last = rows[-1].created_at or last
                for r in rows:
                    payload = {
                        "id": r.id,
                        "sender_id": None if (r.sealed_sender or sealed_view) else r.sender_id,
                        "recipient_id": r.recipient_id,
                        "nonce_b64": r.nonce_b64,
                        "box_b64": r.box_b64,
                        "sender_pubkey_b64": None if (r.sealed_sender or sealed_view) else r.sender_pubkey,
                        "sender_dh_pub_b64": r.sender_dh_pub,
                        "created_at": r.created_at.isoformat() if r.created_at else None,
                        "delivered_at": r.delivered_at.isoformat() if r.delivered_at else None,
                        "read_at": r.read_at.isoformat() if r.read_at else None,
                        "expire_at": r.expire_at.isoformat() if r.expire_at else None,
                        "sealed_sender": r.sealed_sender or sealed_view,
                        "sender_hint": r.sender_hint,
                        "sender_fingerprint": r.sender_hint,
                        "key_id": r.key_id,
                        "prev_key_id": r.prev_key_id,
                    }
                    yield f"data: {json.dumps(payload)}\n\n"
    return StreamingResponse(_gen(), media_type="text/event-stream")


class ReadReq(BaseModel):
    read: bool = True


@router.post("/messages/{mid}/read")
def mark_read(mid: str, req: ReadReq, s: Session = Depends(get_session)):
    m = s.get(Message, mid)
    if not m:
        raise HTTPException(status_code=404, detail="not found")
    m.read_at = datetime.now(timezone.utc)
    s.add(m); s.commit(); s.refresh(m)
    return {"ok": True, "id": m.id, "read_at": m.read_at.isoformat() if m.read_at else None}


class PushTokenReq(BaseModel):
    token: str = Field(min_length=8)
    platform: Optional[str] = None
    ts: Optional[str] = None


@router.post("/devices/{device_id}/push_token")
def register_push_token(device_id: str, req: PushTokenReq, s: Session = Depends(get_session)):
    if not s.get(Device, device_id):
        raise HTTPException(status_code=404, detail="unknown device")
    # Dedup by token to avoid bloat
    s.query(PushToken).filter(PushToken.token == req.token).delete()
    rec = PushToken(device_id=device_id, token=req.token, platform=req.platform)
    s.add(rec)
    s.commit()
    return {"ok": True, "token": req.token, "platform": req.platform or "unknown"}


@router.post("/devices/{device_id}/block")
def set_block(device_id: str, req: ContactRuleReq, s: Session = Depends(get_session)):
    if not s.get(Device, device_id):
        raise HTTPException(status_code=404, detail="unknown device")
    if device_id == req.peer_id:
        raise HTTPException(status_code=400, detail="cannot block self")
    r = s.query(ContactRule).filter(ContactRule.device_id == device_id, ContactRule.peer_id == req.peer_id).first()
    if not r:
        r = ContactRule(device_id=device_id, peer_id=req.peer_id, blocked=req.blocked, hidden=req.hidden)
    else:
        r.blocked = req.blocked
        r.hidden = req.hidden
    s.add(r); s.commit(); s.refresh(r)
    return {"ok": True, "peer_id": req.peer_id, "blocked": r.blocked, "hidden": r.hidden}


@router.get("/devices/{device_id}/hidden")
def list_hidden(device_id: str, s: Session = Depends(get_session)):
    if not s.get(Device, device_id):
        raise HTTPException(status_code=404, detail="unknown device")
    rows = s.query(ContactRule.peer_id).filter(ContactRule.device_id == device_id, ContactRule.hidden == True).all()
    return {"hidden": [r[0] for r in rows]}


app.include_router(router)


# --- Helpers ---
def _notify_recipient(recipient_id: str, message_id: str, s: Session):
    if not FCM_SERVER_KEY:
        return
    if _has_hidden(s, device_id=recipient_id):
        return
    tokens = s.query(PushToken).filter(PushToken.device_id == recipient_id).all()
    if not tokens:
        return
    headers = {
        "Authorization": f"key={FCM_SERVER_KEY}",
        "Content-Type": "application/json",
    }
    for tok in tokens:
        payload = {
            "to": tok.token,
            "priority": "high",
            "data": {
                "type": "chat",
                "device_id": recipient_id,
                "mid": message_id,
            },
        }
        try:
            httpx.post(FCM_ENDPOINT, headers=headers, json=payload, timeout=5)
        except Exception:
            continue


def _purge_expired(s: Session):
    now = datetime.now(timezone.utc)
    try:
        s.query(Message).filter(Message.expire_at != None, Message.expire_at < now).delete()  # type: ignore[comparison-overlap]
        s.commit()
    except Exception:
        s.rollback()


def _blocked_peers(s: Session, device_id: str) -> Set[str]:
    try:
        rows = s.query(ContactRule.peer_id).filter(ContactRule.device_id == device_id, ContactRule.blocked == True).all()
        return {r[0] for r in rows}
    except Exception:
        return set()


def _hidden_peers(s: Session, device_id: str) -> Set[str]:
    try:
        rows = s.query(ContactRule.peer_id).filter(ContactRule.device_id == device_id, ContactRule.hidden == True).all()
        return {r[0] for r in rows}
    except Exception:
        return set()


def _has_hidden(s: Session, device_id: str) -> bool:
    try:
        return bool(s.query(ContactRule).filter(ContactRule.device_id == device_id, ContactRule.hidden == True).first())
    except Exception:
        return False


def _is_blocked(s: Session, device_id: str, peer_id: Optional[str]) -> bool:
    if peer_id is None:
        # quick existence check
        return bool(s.query(ContactRule).filter(ContactRule.device_id == device_id, ContactRule.blocked == True).first())
    return bool(
        s.query(ContactRule)
        .filter(ContactRule.device_id == device_id, ContactRule.peer_id == peer_id, ContactRule.blocked == True)
        .first()
    )


def _start_purge_thread():
    if PURGE_INTERVAL_SECONDS <= 0:
        return
    def _loop():
        while True:
            try:
                with Session(engine) as s:
                    _purge_expired(s)
            except Exception as e:
                logger.warning("purge loop error: %s", e)
            time.sleep(PURGE_INTERVAL_SECONDS)
    t = threading.Thread(target=_loop, daemon=True)
    t.start()
