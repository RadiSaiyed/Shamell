from fastapi import FastAPI, HTTPException, Depends, Request, APIRouter
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field
from typing import Optional, List
import os, time
from shamell_shared import RequestIDMiddleware, configure_cors, add_standard_health, setup_json_logging
from sqlalchemy import create_engine, String, Integer, DateTime, func
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, Session
from sqlalchemy import select
from datetime import datetime, timezone
import uuid


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
    nonce_b64: Mapped[str] = mapped_column(String(64))
    box_b64: Mapped[str] = mapped_column(String(8192))  # ciphertext
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())
    delivered_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), nullable=True)
    read_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), nullable=True)


engine = create_engine(DB_URL, future=True)


def get_session() -> Session:
    with Session(engine) as s:
        yield s


def _startup():
    Base.metadata.create_all(engine)

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
    nonce_b64: str
    box_b64: str
    idempotency_key: Optional[str] = None


class MsgOut(BaseModel):
    id: str
    sender_id: str
    recipient_id: str
    sender_pubkey_b64: str
    nonce_b64: str
    box_b64: str
    created_at: Optional[str]


@router.post("/messages/send", response_model=MsgOut)
def send_message(req: SendReq, s: Session = Depends(get_session)):
    if not s.get(Device, req.sender_id) or not s.get(Device, req.recipient_id):
        raise HTTPException(status_code=404, detail="unknown device")
    # naive idempotency: check if identical ciphertext exists recently
    existed = s.execute(select(Message).where(Message.sender_id == req.sender_id, Message.recipient_id == req.recipient_id, Message.nonce_b64 == req.nonce_b64, Message.box_b64 == req.box_b64).limit(1)).scalars().first()
    if existed:
        return MsgOut(id=existed.id, sender_id=existed.sender_id, recipient_id=existed.recipient_id, sender_pubkey_b64=existed.sender_pubkey, nonce_b64=existed.nonce_b64, box_b64=existed.box_b64, created_at=existed.created_at.isoformat() if existed.created_at else None)
    mid = str(uuid.uuid4())
    m = Message(id=mid, sender_id=req.sender_id, recipient_id=req.recipient_id, sender_pubkey=req.sender_pubkey_b64, nonce_b64=req.nonce_b64, box_b64=req.box_b64)
    s.add(m); s.commit(); s.refresh(m)
    return MsgOut(id=m.id, sender_id=m.sender_id, recipient_id=m.recipient_id, sender_pubkey_b64=m.sender_pubkey, nonce_b64=m.nonce_b64, box_b64=m.box_b64, created_at=m.created_at.isoformat() if m.created_at else None)


@router.get("/messages/inbox", response_model=List[MsgOut])
def inbox(device_id: str, since_iso: Optional[str] = None, limit: int = 50, s: Session = Depends(get_session)):
    if not s.get(Device, device_id):
        raise HTTPException(status_code=404, detail="unknown device")
    q = select(Message).where(Message.recipient_id == device_id)
    if since_iso:
        try:
            ts = datetime.fromisoformat(since_iso.replace("Z", "+00:00"))
            q = q.where(Message.created_at >= ts)
        except Exception:
            raise HTTPException(status_code=400, detail="invalid since")
    q = q.order_by(Message.created_at.desc()).limit(max(1, min(limit, 200)))
    rows = s.execute(q).scalars().all()
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
    return [MsgOut(id=r.id, sender_id=r.sender_id, recipient_id=r.recipient_id, sender_pubkey_b64=r.sender_pubkey, nonce_b64=r.nonce_b64, box_b64=r.box_b64, created_at=r.created_at.isoformat() if r.created_at else None) for r in rows]


@router.get("/messages/stream")
def stream(device_id: str, s: Session = Depends(get_session)):
    # Basic SSE that polls every second for new messages
    if not s.get(Device, device_id):
        raise HTTPException(status_code=404, detail="unknown device")
    def _gen():
        last = datetime.now(timezone.utc)
        while True:
            time.sleep(1)
            rows = s.execute(select(Message).where(Message.recipient_id == device_id, Message.created_at >= last).order_by(Message.created_at.asc()).limit(100)).scalars().all()
            if rows:
                last = rows[-1].created_at or last
                for r in rows:
                    yield f"data: {{\"id\":\"{r.id}\",\"sender_id\":\"{r.sender_id}\",\"nonce_b64\":\"{r.nonce_b64}\",\"box_b64\":\"{r.box_b64}\",\"sender_pubkey_b64\":\"{r.sender_pubkey}\"}}\n\n"
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


app.include_router(router)
