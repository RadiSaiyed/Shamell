from fastapi import FastAPI, HTTPException, Depends, Request, APIRouter
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field
from typing import Optional, List
import os, time, json, threading, logging
import base64
import hashlib
import hmac
import httpx
import secrets
import re
from shamell_shared import RequestIDMiddleware, configure_cors, add_standard_health, setup_json_logging
from starlette.middleware.trustedhost import TrustedHostMiddleware
from sqlalchemy import create_engine, String, Integer, DateTime, Boolean, ForeignKey, func, select, or_, text
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, Session
from datetime import datetime, timezone, timedelta
import uuid
from typing import Set


def _env_or(key: str, default: str) -> str:
    v = os.getenv(key)
    return v if v is not None else default


_ENV_LOWER = _env_or("ENV", "dev").lower()
# Never expose interactive API docs by default in prod.
_ENABLE_DOCS = _ENV_LOWER in ("dev", "test") or os.getenv("ENABLE_API_DOCS_IN_PROD", "").lower() in (
    "1",
    "true",
    "yes",
    "on",
)
app = FastAPI(
    title="Chat API",
    version="0.1.0",
    docs_url="/docs" if _ENABLE_DOCS else None,
    redoc_url="/redoc" if _ENABLE_DOCS else None,
    openapi_url="/openapi.json" if _ENABLE_DOCS else None,
)
setup_json_logging()
app.add_middleware(RequestIDMiddleware)
configure_cors(app, os.getenv("ALLOWED_ORIGINS", ""))
add_standard_health(app)

# Trusted hosts: mitigate Host header attacks and misrouting.
_allowed_hosts_raw = (os.getenv("ALLOWED_HOSTS") or "").strip()
if _allowed_hosts_raw:
    _allowed_hosts = [h.strip() for h in _allowed_hosts_raw.split(",") if h.strip()]
    # Keep local health checks working even if ALLOWED_HOSTS is minimal.
    for _extra in ("localhost", "127.0.0.1"):
        if _extra not in _allowed_hosts:
            _allowed_hosts.append(_extra)
    app.add_middleware(TrustedHostMiddleware, allowed_hosts=_allowed_hosts)
DB_URL = _env_or("DB_URL", "sqlite+pysqlite:////tmp/chat.db")
DB_SCHEMA = os.getenv("DB_SCHEMA") if not DB_URL.startswith("sqlite") else None
INTERNAL_API_SECRET = os.getenv("INTERNAL_API_SECRET") or os.getenv("CHAT_INTERNAL_SECRET") or ""
FCM_SERVER_KEY = os.getenv("FCM_SERVER_KEY", "")
FCM_ENDPOINT = "https://fcm.googleapis.com/fcm/send"
PURGE_INTERVAL_SECONDS = int(os.getenv("CHAT_PURGE_INTERVAL_SECONDS", "600"))
logger = logging.getLogger("chat")
_CHAT_AUTH_DEFAULT = "true" if _ENV_LOWER in ("prod", "production", "staging") else "false"
CHAT_ENFORCE_DEVICE_AUTH = _env_or("CHAT_ENFORCE_DEVICE_AUTH", _CHAT_AUTH_DEFAULT).lower() == "true"
_DEVICE_ID_RE = re.compile(r"^[A-Za-z0-9_-]{4,24}$")

# ---- Internal-only guard (defense-in-depth) ----
# In production/staging the Chat service should not be directly exposed to end
# users. The public surface is the BFF; Chat is an internal service.
_require_internal_raw = _env_or("CHAT_REQUIRE_INTERNAL_SECRET", "").strip().lower()
if _require_internal_raw in ("0", "false", "no", "off"):
    CHAT_REQUIRE_INTERNAL_SECRET = False
elif _require_internal_raw:
    CHAT_REQUIRE_INTERNAL_SECRET = True
else:
    CHAT_REQUIRE_INTERNAL_SECRET = _ENV_LOWER in ("prod", "production", "staging")


def _require_internal_secret(request: Request) -> None:
    if not CHAT_REQUIRE_INTERNAL_SECRET:
        return
    provided = (request.headers.get("X-Internal-Secret") or "").strip()
    if not INTERNAL_API_SECRET:
        # Misconfiguration: fail closed so the service is not accidentally exposed.
        raise HTTPException(status_code=503, detail="internal auth not configured")
    if not provided or not hmac.compare_digest(provided, INTERNAL_API_SECRET):
        raise HTTPException(status_code=401, detail="internal auth required")


router = APIRouter(dependencies=[Depends(_require_internal_secret)])


class Base(DeclarativeBase):
    pass


class Device(Base):
    __tablename__ = "devices"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[str] = mapped_column(String(12), primary_key=True)  # short ID (e.g. 8–12 chars)
    public_key: Mapped[str] = mapped_column(String(255))  # base64
    key_version: Mapped[Optional[int]] = mapped_column(Integer, default=0)
    name: Mapped[Optional[str]] = mapped_column(String(120), default=None)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class DeviceAuth(Base):
    __tablename__ = "device_auth"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    device_id: Mapped[str] = mapped_column(String(24), primary_key=True)
    token_hash: Mapped[str] = mapped_column(String(64))
    rotated_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


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


class Group(Base):
    __tablename__ = "groups"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    name: Mapped[str] = mapped_column(String(120))
    creator_id: Mapped[str] = mapped_column(String(12))
    key_version: Mapped[Optional[int]] = mapped_column(Integer, default=0)
    avatar_b64: Mapped[Optional[str]] = mapped_column(String(65535), nullable=True)
    avatar_mime: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class GroupMember(Base):
    __tablename__ = "group_members"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    group_id: Mapped[str] = mapped_column(String(36), index=True)
    device_id: Mapped[str] = mapped_column(String(12), index=True)
    role: Mapped[Optional[str]] = mapped_column(String(20), default="member")
    joined_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class GroupMessage(Base):
    __tablename__ = "group_messages"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    group_id: Mapped[str] = mapped_column(String(36), index=True)
    sender_id: Mapped[str] = mapped_column(String(12))
    text: Mapped[str] = mapped_column(String(4096), default="")
    kind: Mapped[Optional[str]] = mapped_column(String(20), nullable=True)
    nonce_b64: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    box_b64: Mapped[Optional[str]] = mapped_column(String(65535), nullable=True)
    attachment_b64: Mapped[Optional[str]] = mapped_column(String(65535), nullable=True)
    attachment_mime: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    voice_secs: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())
    expire_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), nullable=True)


class GroupKeyEvent(Base):
    __tablename__ = "group_key_events"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    group_id: Mapped[str] = mapped_column(String(36), index=True)
    version: Mapped[int] = mapped_column(Integer)
    actor_id: Mapped[str] = mapped_column(String(12))
    key_fp: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class DeviceKeyEvent(Base):
    __tablename__ = "device_key_events"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    device_id: Mapped[str] = mapped_column(String(24), index=True)
    version: Mapped[int] = mapped_column(Integer)
    old_key_fp: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    new_key_fp: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


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
    muted: Mapped[bool] = mapped_column(default=False)
    starred: Mapped[bool] = mapped_column(default=False)
    pinned: Mapped[bool] = mapped_column(default=False)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())


class GroupPrefs(Base):
    __tablename__ = "group_prefs"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    device_id: Mapped[str] = mapped_column(String(24), index=True)
    group_id: Mapped[str] = mapped_column(String(36), index=True)
    muted: Mapped[bool] = mapped_column(default=False)
    pinned: Mapped[bool] = mapped_column(default=False)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())


engine = create_engine(DB_URL, future=True)


def get_session() -> Session:
    with Session(engine) as s:
        yield s


def _startup():
    Base.metadata.create_all(engine)
    # best-effort schema migration for new ContactRule fields
    try:
        with engine.begin() as conn:
            conn.execute(text("ALTER TABLE contact_rules ADD COLUMN muted BOOLEAN DEFAULT 0"))
    except Exception:
        pass
    try:
        with engine.begin() as conn:
            conn.execute(text("ALTER TABLE contact_rules ADD COLUMN starred BOOLEAN DEFAULT 0"))
    except Exception:
        pass
    try:
        with engine.begin() as conn:
            conn.execute(text("ALTER TABLE contact_rules ADD COLUMN pinned BOOLEAN DEFAULT 0"))
    except Exception:
        pass
    # best-effort schema migration for group message extensions
    try:
        with engine.begin() as conn:
            conn.execute(text("ALTER TABLE group_messages ADD COLUMN kind VARCHAR(20)"))
    except Exception:
        pass
    try:
        with engine.begin() as conn:
            conn.execute(text("ALTER TABLE groups ADD COLUMN key_version INTEGER DEFAULT 0"))
    except Exception:
        pass
    # best-effort schema migration for device key rotations
    try:
        with engine.begin() as conn:
            conn.execute(text("ALTER TABLE devices ADD COLUMN key_version INTEGER DEFAULT 0"))
    except Exception:
        pass
    try:
        with engine.begin() as conn:
            conn.execute(text("ALTER TABLE groups ADD COLUMN avatar_b64 VARCHAR(65535)"))
    except Exception:
        pass
    try:
        with engine.begin() as conn:
            conn.execute(text("ALTER TABLE groups ADD COLUMN avatar_mime VARCHAR(64)"))
    except Exception:
        pass
    try:
        with engine.begin() as conn:
            conn.execute(text("ALTER TABLE group_messages ADD COLUMN nonce_b64 VARCHAR(64)"))
    except Exception:
        pass
    try:
        with engine.begin() as conn:
            conn.execute(text("ALTER TABLE group_messages ADD COLUMN box_b64 VARCHAR(65535)"))
    except Exception:
        pass
    try:
        with engine.begin() as conn:
            conn.execute(text("ALTER TABLE group_messages ADD COLUMN attachment_b64 VARCHAR(65535)"))
    except Exception:
        pass
    try:
        with engine.begin() as conn:
            conn.execute(text("ALTER TABLE group_messages ADD COLUMN attachment_mime VARCHAR(64)"))
    except Exception:
        pass
    try:
        with engine.begin() as conn:
            conn.execute(text("ALTER TABLE group_messages ADD COLUMN voice_secs INTEGER"))
    except Exception:
        pass
    _start_purge_thread()

app.router.on_startup.append(_startup)


class RegisterReq(BaseModel):
    device_id: str = Field(min_length=4, max_length=24)
    public_key_b64: str = Field(min_length=32, max_length=255)
    name: Optional[str] = Field(default=None, max_length=120)


class DeviceOut(BaseModel):
    device_id: str
    public_key_b64: str
    name: Optional[str]
    key_version: int = 0


class DeviceRegisterOut(DeviceOut):
    auth_token: Optional[str] = None


def _fp_for_key(public_key_b64: str) -> str:
    try:
        raw = base64.b64decode(public_key_b64)
        h = hashlib.sha256(raw).hexdigest()
        return h[:16]
    except Exception:
        return ""


def _hash_device_token(token: str) -> str:
    return hashlib.sha256((token or "").encode()).hexdigest()


def _issue_device_token(s: Session, device_id: str) -> str:
    token = secrets.token_hex(32)
    digest = _hash_device_token(token)
    row = s.get(DeviceAuth, device_id)
    if not row:
        row = DeviceAuth(device_id=device_id, token_hash=digest)
    else:
        row.token_hash = digest
        row.rotated_at = datetime.now(timezone.utc)
    s.add(row)
    return token


def _require_device_actor(request: Request, s: Session) -> Optional[str]:
    if not CHAT_ENFORCE_DEVICE_AUTH:
        return None
    actor = (request.headers.get("X-Chat-Device-Id") or request.headers.get("x-chat-device-id") or "").strip()
    token = (request.headers.get("X-Chat-Device-Token") or request.headers.get("x-chat-device-token") or "").strip()
    if not actor or not token:
        raise HTTPException(status_code=401, detail="chat device auth required")
    if not _DEVICE_ID_RE.fullmatch(actor):
        raise HTTPException(status_code=401, detail="invalid chat device id")
    row = s.get(DeviceAuth, actor)
    if not row:
        raise HTTPException(status_code=401, detail="unknown chat device auth")
    if not hmac.compare_digest(_hash_device_token(token), row.token_hash):
        raise HTTPException(status_code=401, detail="invalid chat device token")
    return actor


def _enforce_device_actor(request: Request, s: Session, device_id: str) -> Optional[str]:
    actor = _require_device_actor(request, s)
    if actor is not None and actor != device_id:
        raise HTTPException(status_code=403, detail="device auth mismatch")
    return actor


@router.post("/devices/register", response_model=DeviceRegisterOut)
def register(request: Request, req: RegisterReq, s: Session = Depends(get_session)):
    did = req.device_id.strip()
    issued_token: Optional[str] = None
    if s.get(Device, did):
        # Update public key / name if changed
        d = s.get(Device, did)
        old_key = (d.public_key or "").strip()
        new_key = req.public_key_b64.strip()
        auth_row = s.get(DeviceAuth, did)
        if auth_row is not None:
            _enforce_device_actor(request, s, did)
        else:
            # One-time bootstrap for legacy devices: only if public key matches
            # current key exactly, then issue initial device token.
            if new_key != old_key:
                raise HTTPException(
                    status_code=401,
                    detail="device auth bootstrap requires unchanged public key",
                )
            issued_token = _issue_device_token(s, did)
        if new_key and old_key and new_key != old_key:
            cur_ver = int(getattr(d, "key_version", 0) or 0)
            next_ver = cur_ver + 1
            try:
                d.key_version = next_ver
            except Exception:
                pass
            try:
                old_fp = _fp_for_key(old_key) or None
            except Exception:
                old_fp = None
            try:
                new_fp = _fp_for_key(new_key) or None
            except Exception:
                new_fp = None
            try:
                s.add(
                    DeviceKeyEvent(
                        device_id=did,
                        version=next_ver,
                        old_key_fp=old_fp,
                        new_key_fp=new_fp,
                    )
                )
            except Exception:
                pass
            logger.info("device %s key rotated to v%s", did, next_ver)
        d.public_key = new_key or d.public_key
        d.name = req.name
        s.add(d); s.commit(); s.refresh(d)
        return DeviceRegisterOut(
            device_id=d.id,
            public_key_b64=d.public_key,
            name=d.name,
            key_version=int(getattr(d, "key_version", 0) or 0),
            auth_token=issued_token,
        )
    d = Device(id=did, public_key=req.public_key_b64, name=req.name, key_version=0)
    issued_token = _issue_device_token(s, did)
    s.add(d); s.commit(); s.refresh(d)
    return DeviceRegisterOut(
        device_id=d.id,
        public_key_b64=d.public_key,
        name=d.name,
        key_version=0,
        auth_token=issued_token,
    )


@router.get("/devices/{device_id}", response_model=DeviceOut)
def get_device(device_id: str, s: Session = Depends(get_session)):
    d = s.get(Device, device_id)
    if not d: raise HTTPException(status_code=404, detail="not found")
    return DeviceOut(
        device_id=d.id,
        public_key_b64=d.public_key,
        name=d.name,
        key_version=int(getattr(d, "key_version", 0) or 0),
    )


class SendReq(BaseModel):
    sender_id: str = Field(min_length=4, max_length=24)
    recipient_id: str = Field(min_length=4, max_length=24)
    sender_pubkey_b64: str = Field(min_length=32, max_length=255)
    sender_dh_pub_b64: Optional[str] = Field(default=None, max_length=255)
    nonce_b64: str = Field(min_length=8, max_length=64)
    box_b64: str = Field(min_length=16, max_length=8192)
    idempotency_key: Optional[str] = Field(default=None, max_length=128)
    expire_after_seconds: Optional[int] = Field(default=None, ge=10, le=7 * 24 * 3600)
    client_ts: Optional[str] = None
    sealed_sender: bool = False
    sender_hint: Optional[str] = Field(default=None, max_length=64)
    sender_fingerprint: Optional[str] = Field(default=None, max_length=64)
    key_id: Optional[str] = Field(default=None, max_length=64)
    prev_key_id: Optional[str] = Field(default=None, max_length=64)


class ContactRuleReq(BaseModel):
    peer_id: str = Field(min_length=4, max_length=24)
    blocked: bool = False
    hidden: bool = False


class ContactPrefsReq(BaseModel):
    peer_id: str = Field(min_length=4, max_length=24)
    muted: Optional[bool] = None
    starred: Optional[bool] = None
    pinned: Optional[bool] = None


class GroupPrefsReq(BaseModel):
    group_id: str = Field(min_length=1, max_length=36)
    muted: Optional[bool] = None
    pinned: Optional[bool] = None


class GroupPrefsOut(BaseModel):
    group_id: str
    muted: bool = False
    pinned: bool = False


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


class GroupCreateReq(BaseModel):
    device_id: str = Field(min_length=4, max_length=24)
    name: str = Field(min_length=1, max_length=120)
    member_ids: Optional[List[str]] = Field(default=None, max_length=128)
    group_id: Optional[str] = None


class GroupOut(BaseModel):
    group_id: str
    name: str
    creator_id: str
    created_at: Optional[str] = None
    member_count: int = 0
    key_version: int = 0
    avatar_b64: Optional[str] = None
    avatar_mime: Optional[str] = None


class GroupSendReq(BaseModel):
    sender_id: str = Field(min_length=4, max_length=24)
    text: Optional[str] = Field(default=None, max_length=4096)
    kind: Optional[str] = Field(default=None, max_length=20)
    nonce_b64: Optional[str] = Field(default=None, max_length=64)
    box_b64: Optional[str] = Field(default=None, max_length=65535)
    attachment_b64: Optional[str] = Field(default=None, max_length=65535)
    attachment_mime: Optional[str] = Field(default=None, max_length=64)
    voice_secs: Optional[int] = Field(default=None, ge=1, le=120)
    expire_after_seconds: Optional[int] = Field(default=None, ge=10, le=7 * 24 * 3600)


class GroupMsgOut(BaseModel):
    id: str
    group_id: str
    sender_id: str
    text: str
    kind: Optional[str] = None
    nonce_b64: Optional[str] = None
    box_b64: Optional[str] = None
    attachment_b64: Optional[str] = None
    attachment_mime: Optional[str] = None
    voice_secs: Optional[int] = None
    created_at: Optional[str] = None
    expire_at: Optional[str] = None


class GroupInviteReq(BaseModel):
    inviter_id: str = Field(min_length=4, max_length=24)
    member_ids: List[str] = Field(min_length=1, max_length=128)


class GroupLeaveReq(BaseModel):
    device_id: str = Field(min_length=4, max_length=24)


class GroupRoleReq(BaseModel):
    actor_id: str = Field(min_length=4, max_length=24)
    target_id: str = Field(min_length=4, max_length=24)
    role: str = Field(min_length=3, max_length=20)


class GroupUpdateReq(BaseModel):
    actor_id: str = Field(min_length=4, max_length=24)
    name: Optional[str] = Field(default=None, max_length=120)
    avatar_b64: Optional[str] = Field(default=None, max_length=65535)
    avatar_mime: Optional[str] = Field(default=None, max_length=64)


class GroupMemberOut(BaseModel):
    device_id: str
    role: Optional[str] = None
    joined_at: Optional[str] = None


class GroupKeyRotateReq(BaseModel):
    actor_id: str = Field(min_length=4, max_length=24)
    key_fp: Optional[str] = Field(default=None, max_length=64)


class GroupKeyEventOut(BaseModel):
    group_id: str
    version: int
    actor_id: str
    key_fp: Optional[str] = None
    created_at: Optional[str] = None


@router.post("/messages/send", response_model=MsgOut)
def send_message(request: Request, req: SendReq, s: Session = Depends(get_session)):
    _enforce_device_actor(request, s, req.sender_id)
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


@router.post("/groups/create", response_model=GroupOut)
def create_group(request: Request, req: GroupCreateReq, s: Session = Depends(get_session)):
    owner_id = req.device_id.strip()
    _enforce_device_actor(request, s, owner_id)
    if not s.get(Device, owner_id):
        raise HTTPException(status_code=404, detail="unknown device")
    gid = (req.group_id or f"grp_{uuid.uuid4().hex[:10]}").strip()
    if not gid:
        raise HTTPException(status_code=400, detail="invalid group id")
    if s.get(Group, gid):
        raise HTTPException(status_code=409, detail="group exists")
    name = req.name.strip() or gid
    g = Group(id=gid, name=name[:120], creator_id=owner_id)
    s.add(g)
    # Add creator + members that already exist as devices
    members = [owner_id] + (req.member_ids or [])
    seen: Set[str] = set()
    for mid in members:
        mid = str(mid).strip()
        if not mid or mid in seen:
            continue
        seen.add(mid)
        if not s.get(Device, mid):
            continue
        role = "admin" if mid == owner_id else "member"
        s.add(GroupMember(group_id=gid, device_id=mid, role=role))
    s.commit()
    try:
        s.refresh(g)
    except Exception:
        pass
    # System event: group created (and initial invites)
    try:
        sys_mid = str(uuid.uuid4())
        others = [m for m in seen if m != owner_id]
        ev = {
            "event": "create",
            "actor_id": owner_id,
            "name": g.name,
            "member_ids": others,
        }
        txt = json.dumps(ev, ensure_ascii=False)
        s.add(
            GroupMessage(
                id=sys_mid,
                group_id=gid,
                sender_id=owner_id[:12],
                text=txt[:4096],
                kind="system",
            )
        )
        s.commit()
        _notify_group(group_id=gid, sender_id=owner_id, message_id=sys_mid, s=s)
    except Exception:
        pass
    count = s.query(GroupMember).filter(GroupMember.group_id == gid).count()
    return GroupOut(
        group_id=g.id,
        name=g.name,
        creator_id=g.creator_id,
        created_at=g.created_at.isoformat() if g.created_at else None,
        member_count=count,
        key_version=int(getattr(g, "key_version", 0) or 0),
        avatar_b64=getattr(g, "avatar_b64", None),
        avatar_mime=getattr(g, "avatar_mime", None),
    )


@router.get("/groups/list", response_model=List[GroupOut])
def list_groups(request: Request, device_id: str, s: Session = Depends(get_session)):
    did = device_id.strip()
    _enforce_device_actor(request, s, did)
    if not s.get(Device, did):
        raise HTTPException(status_code=404, detail="unknown device")
    gids = [r[0] for r in s.query(GroupMember.group_id).filter(GroupMember.device_id == did).all()]
    if not gids:
        return []
    groups = s.query(Group).filter(Group.id.in_(gids)).order_by(Group.created_at.desc()).all()
    out: List[GroupOut] = []
    for g in groups:
        count = s.query(GroupMember).filter(GroupMember.group_id == g.id).count()
        out.append(
            GroupOut(
                group_id=g.id,
                name=g.name,
                creator_id=g.creator_id,
                created_at=g.created_at.isoformat() if g.created_at else None,
                member_count=count,
                key_version=int(getattr(g, "key_version", 0) or 0),
                avatar_b64=getattr(g, "avatar_b64", None),
                avatar_mime=getattr(g, "avatar_mime", None),
            )
        )
    return out


@router.post("/groups/{group_id}/update", response_model=GroupOut)
def update_group(group_id: str, request: Request, req: GroupUpdateReq, s: Session = Depends(get_session)):
    actor = req.actor_id.strip()
    _enforce_device_actor(request, s, actor)
    if not s.get(Device, actor):
        raise HTTPException(status_code=404, detail="unknown device")
    g = s.get(Group, group_id)
    if not g:
        raise HTTPException(status_code=404, detail="unknown group")
    if not _is_group_admin(s, group_id, actor):
        raise HTTPException(status_code=403, detail="admin required")

    changed = False
    sys_events: List[dict] = []

    if req.name is not None:
        new_name = req.name.strip()
        if new_name and new_name != g.name:
            old_name = g.name
            g.name = new_name[:120]
            changed = True
            sys_events.append(
                {
                    "event": "rename",
                    "actor_id": actor,
                    "old_name": old_name,
                    "new_name": g.name,
                }
            )

    if req.avatar_b64 is not None:
        new_b64 = (req.avatar_b64 or "").strip() or None
        new_mime = (req.avatar_mime or "").strip() or None
        old_b64 = getattr(g, "avatar_b64", None) or None
        old_mime = getattr(g, "avatar_mime", None) or None
        if new_b64 != old_b64 or (new_b64 and new_mime != old_mime):
            action = "update"
            if not old_b64 and new_b64:
                action = "set"
            elif old_b64 and not new_b64:
                action = "remove"
            g.avatar_b64 = new_b64
            g.avatar_mime = new_mime
            changed = True
            sys_events.append(
                {
                    "event": "avatar",
                    "actor_id": actor,
                    "action": action,
                }
            )

    sys_mids: List[str] = []
    if changed:
        try:
            for ev in sys_events:
                mid = str(uuid.uuid4())
                sys_mids.append(mid)
                txt = json.dumps(ev, ensure_ascii=False)
                s.add(
                    GroupMessage(
                        id=mid,
                        group_id=group_id,
                        sender_id=actor[:12],
                        text=txt[:4096],
                        kind="system",
                    )
                )
        except Exception:
            sys_mids = []
        s.add(g)
        s.commit()
        try:
            for mid in sys_mids:
                _notify_group(group_id=group_id, sender_id=actor, message_id=mid, s=s)
        except Exception:
            pass

    count = s.query(GroupMember).filter(GroupMember.group_id == g.id).count()
    return GroupOut(
        group_id=g.id,
        name=g.name,
        creator_id=g.creator_id,
        created_at=g.created_at.isoformat() if g.created_at else None,
        member_count=count,
        key_version=int(getattr(g, "key_version", 0) or 0),
        avatar_b64=getattr(g, "avatar_b64", None),
        avatar_mime=getattr(g, "avatar_mime", None),
    )


@router.post("/groups/{group_id}/messages/send", response_model=GroupMsgOut)
def send_group_message(group_id: str, request: Request, req: GroupSendReq, s: Session = Depends(get_session)):
    sender_id = req.sender_id.strip()
    _enforce_device_actor(request, s, sender_id)
    if not s.get(Device, sender_id):
        raise HTTPException(status_code=404, detail="unknown device")
    g = s.get(Group, group_id)
    if not g:
        raise HTTPException(status_code=404, detail="unknown group")
    if not _is_group_member(s, group_id, sender_id):
        raise HTTPException(status_code=403, detail="not a member")
    mid = str(uuid.uuid4())
    nonce_val = (req.nonce_b64 or "").strip() or None
    box_val = (req.box_b64 or "").strip() or None
    if box_val and not nonce_val:
        raise HTTPException(status_code=400, detail="missing nonce")
    if nonce_val and not box_val:
        raise HTTPException(status_code=400, detail="missing box")
    sealed = bool(nonce_val and box_val)
    kind = (req.kind or "").strip().lower() or None
    text_val = (req.text or "").strip()
    att_b64 = (req.attachment_b64 or "").strip() or None
    att_mime = (req.attachment_mime or "").strip() or None
    voice_secs = req.voice_secs
    if sealed:
        kind = "sealed"
        text_val = ""
        att_b64 = None
        att_mime = None
        voice_secs = None
    if not sealed and not text_val and not att_b64 and not kind:
        raise HTTPException(status_code=400, detail="empty message")
    if kind == "voice":
        if not att_b64:
            raise HTTPException(status_code=400, detail="missing voice attachment")
        if voice_secs is None:
            voice_secs = 1
    exp_at = None
    if req.expire_after_seconds:
        try:
            exp_at = datetime.now(timezone.utc) + timedelta(seconds=int(req.expire_after_seconds))
        except Exception:
            exp_at = None
    m = GroupMessage(
        id=mid,
        group_id=group_id,
        sender_id=sender_id,
        text=text_val[:4096],
        kind=kind,
        nonce_b64=nonce_val,
        box_b64=box_val,
        attachment_b64=att_b64,
        attachment_mime=att_mime,
        voice_secs=voice_secs,
        expire_at=exp_at,
    )
    s.add(m); s.commit()
    try:
        s.refresh(m)
    except Exception:
        pass
    _notify_group(group_id=group_id, sender_id=sender_id, message_id=mid, s=s)
    return GroupMsgOut(
        id=m.id,
        group_id=m.group_id,
        sender_id=m.sender_id,
        text=m.text,
        kind=m.kind,
        nonce_b64=m.nonce_b64,
        box_b64=m.box_b64,
        attachment_b64=m.attachment_b64,
        attachment_mime=m.attachment_mime,
        voice_secs=m.voice_secs,
        created_at=m.created_at.isoformat() if m.created_at else None,
        expire_at=m.expire_at.isoformat() if m.expire_at else None,
    )


@router.get("/groups/{group_id}/messages/inbox", response_model=List[GroupMsgOut])
def group_inbox(group_id: str, request: Request, device_id: str, since_iso: Optional[str] = None, limit: int = 50, s: Session = Depends(get_session)):
    did = device_id.strip()
    _enforce_device_actor(request, s, did)
    if not s.get(Device, did):
        raise HTTPException(status_code=404, detail="unknown device")
    g = s.get(Group, group_id)
    if not g:
        raise HTTPException(status_code=404, detail="unknown group")
    if not _is_group_member(s, group_id, did):
        raise HTTPException(status_code=403, detail="not a member")
    _purge_expired(s)
    q = select(GroupMessage).where(GroupMessage.group_id == group_id)
    if since_iso:
        try:
            ts = datetime.fromisoformat(since_iso.replace("Z", "+00:00"))
            q = q.where(GroupMessage.created_at >= ts)
        except Exception:
            raise HTTPException(status_code=400, detail="invalid since")
    now = datetime.now(timezone.utc)
    q = q.where(or_(GroupMessage.expire_at == None, GroupMessage.expire_at >= now))  # type: ignore[comparison-overlap]
    q = q.order_by(GroupMessage.created_at.asc()).limit(max(1, min(limit, 200)))
    rows = s.execute(q).scalars().all()
    out: List[GroupMsgOut] = []
    for r in rows:
        out.append(
            GroupMsgOut(
                id=r.id,
                group_id=r.group_id,
                sender_id=r.sender_id,
                text=r.text,
                kind=r.kind,
                nonce_b64=r.nonce_b64,
                box_b64=r.box_b64,
                attachment_b64=r.attachment_b64,
                attachment_mime=r.attachment_mime,
                voice_secs=r.voice_secs,
                created_at=r.created_at.isoformat() if r.created_at else None,
                expire_at=r.expire_at.isoformat() if r.expire_at else None,
            )
        )
    return out


@router.get("/groups/{group_id}/members", response_model=List[GroupMemberOut])
def group_members(group_id: str, request: Request, device_id: str, s: Session = Depends(get_session)):
    did = device_id.strip()
    _enforce_device_actor(request, s, did)
    if not s.get(Device, did):
        raise HTTPException(status_code=404, detail="unknown device")
    if not s.get(Group, group_id):
        raise HTTPException(status_code=404, detail="unknown group")
    if not _is_group_member(s, group_id, did):
        raise HTTPException(status_code=403, detail="not a member")
    rows = (
        s.query(GroupMember)
        .filter(GroupMember.group_id == group_id)
        .order_by(GroupMember.joined_at.asc())
        .all()
    )
    return [
        GroupMemberOut(
            device_id=r.device_id,
            role=r.role,
            joined_at=r.joined_at.isoformat() if r.joined_at else None,
        )
        for r in rows
    ]


@router.post("/groups/{group_id}/invite", response_model=GroupOut)
def invite_members(group_id: str, request: Request, req: GroupInviteReq, s: Session = Depends(get_session)):
    inviter_id = req.inviter_id.strip()
    _enforce_device_actor(request, s, inviter_id)
    if not s.get(Device, inviter_id):
        raise HTTPException(status_code=404, detail="unknown device")
    g = s.get(Group, group_id)
    if not g:
        raise HTTPException(status_code=404, detail="unknown group")
    if not _is_group_admin(s, group_id, inviter_id):
        raise HTTPException(status_code=403, detail="admin required")
    added = False
    added_ids: List[str] = []
    for mid in req.member_ids:
        mid = str(mid).strip()
        if not mid or mid == inviter_id:
            continue
        if not s.get(Device, mid):
            continue
        if _is_group_member(s, group_id, mid):
            continue
        s.add(GroupMember(group_id=group_id, device_id=mid, role="member"))
        added_ids.append(mid)
        added = True
    if added:
        try:
            sys_mid = str(uuid.uuid4())
            ev = {"event": "invite", "actor_id": inviter_id, "member_ids": added_ids}
            txt = json.dumps(ev, ensure_ascii=False)
            s.add(
                GroupMessage(
                    id=sys_mid,
                    group_id=group_id,
                    sender_id=inviter_id[:12],
                    text=txt[:4096],
                    kind="system",
                )
            )
        except Exception:
            sys_mid = None
        s.commit()
        try:
            if sys_mid:
                _notify_group(group_id=group_id, sender_id=inviter_id, message_id=sys_mid, s=s)
        except Exception:
            pass
    count = s.query(GroupMember).filter(GroupMember.group_id == group_id).count()
    return GroupOut(
        group_id=g.id,
        name=g.name,
        creator_id=g.creator_id,
        created_at=g.created_at.isoformat() if g.created_at else None,
        member_count=count,
        key_version=int(getattr(g, "key_version", 0) or 0),
        avatar_b64=getattr(g, "avatar_b64", None),
        avatar_mime=getattr(g, "avatar_mime", None),
    )


@router.post("/groups/{group_id}/leave")
def leave_group(group_id: str, request: Request, req: GroupLeaveReq, s: Session = Depends(get_session)):
    did = req.device_id.strip()
    _enforce_device_actor(request, s, did)
    if not s.get(Device, did):
        raise HTTPException(status_code=404, detail="unknown device")
    g = s.get(Group, group_id)
    if not g:
        raise HTTPException(status_code=404, detail="unknown group")
    if not _is_group_member(s, group_id, did):
        raise HTTPException(status_code=403, detail="not a member")
    s.query(GroupMember).filter(GroupMember.group_id == group_id, GroupMember.device_id == did).delete()
    s.commit()
    remaining = s.query(GroupMember).filter(GroupMember.group_id == group_id).all()
    if not remaining:
        try:
            s.query(GroupMessage).filter(GroupMessage.group_id == group_id).delete()
        except Exception:
            pass
        try:
            s.delete(g)
        except Exception:
            pass
        s.commit()
        return {"ok": True, "deleted": True}
    try:
        sys_mid = str(uuid.uuid4())
        ev = {"event": "leave", "actor_id": did}
        txt = json.dumps(ev, ensure_ascii=False)
        s.add(
            GroupMessage(
                id=sys_mid,
                group_id=group_id,
                sender_id=did[:12],
                text=txt[:4096],
                kind="system",
            )
        )
        s.commit()
        _notify_group(group_id=group_id, sender_id=did, message_id=sys_mid, s=s)
    except Exception:
        pass
    admins = [m for m in remaining if (m.role or "") == "admin"]
    if not admins:
        remaining[0].role = "admin"
        admins = [remaining[0]]
    if g.creator_id == did:
        g.creator_id = admins[0].device_id
        s.add(g)
    s.commit()
    return {"ok": True}


@router.post("/groups/{group_id}/set_role")
def set_group_role(group_id: str, request: Request, req: GroupRoleReq, s: Session = Depends(get_session)):
    actor = req.actor_id.strip()
    target = req.target_id.strip()
    _enforce_device_actor(request, s, actor)
    role = req.role.strip().lower()
    if role not in ("admin", "member"):
        raise HTTPException(status_code=400, detail="invalid role")
    if not s.get(Device, actor) or not s.get(Device, target):
        raise HTTPException(status_code=404, detail="unknown device")
    if not s.get(Group, group_id):
        raise HTTPException(status_code=404, detail="unknown group")
    if not _is_group_admin(s, group_id, actor):
        raise HTTPException(status_code=403, detail="admin required")
    row = s.query(GroupMember).filter(GroupMember.group_id == group_id, GroupMember.device_id == target).first()
    if not row:
        raise HTTPException(status_code=404, detail="not a member")
    row.role = role
    s.add(row); s.commit(); s.refresh(row)
    try:
        sys_mid = str(uuid.uuid4())
        ev = {
            "event": "role",
            "actor_id": actor,
            "target_id": target,
            "role": role,
        }
        txt = json.dumps(ev, ensure_ascii=False)
        s.add(
            GroupMessage(
                id=sys_mid,
                group_id=group_id,
                sender_id=actor[:12],
                text=txt[:4096],
                kind="system",
            )
        )
        s.commit()
        _notify_group(group_id=group_id, sender_id=actor, message_id=sys_mid, s=s)
    except Exception:
        pass
    return {"ok": True, "device_id": target, "role": row.role}


@router.post("/groups/{group_id}/keys/rotate", response_model=GroupKeyEventOut)
def rotate_group_key(group_id: str, request: Request, req: GroupKeyRotateReq, s: Session = Depends(get_session)):
    actor = req.actor_id.strip()
    _enforce_device_actor(request, s, actor)
    if not s.get(Device, actor):
        raise HTTPException(status_code=404, detail="unknown device")
    g = s.get(Group, group_id)
    if not g:
        raise HTTPException(status_code=404, detail="unknown group")
    if not _is_group_admin(s, group_id, actor):
        raise HTTPException(status_code=403, detail="admin required")
    cur_ver = int(getattr(g, "key_version", 0) or 0)
    next_ver = cur_ver + 1
    try:
        g.key_version = next_ver
        s.add(g)
    except Exception:
        pass
    key_fp = (req.key_fp or "").strip() or None
    sys_mid = None
    try:
        sys_mid = str(uuid.uuid4())
        ev_msg = {
            "event": "key_rotated",
            "actor_id": actor,
            "version": next_ver,
            "key_fp": key_fp,
        }
        txt = json.dumps(ev_msg, ensure_ascii=False)
        s.add(
            GroupMessage(
                id=sys_mid,
                group_id=group_id,
                sender_id=actor[:12],
                text=txt[:4096],
                kind="system",
            )
        )
    except Exception:
        sys_mid = None
    ev = GroupKeyEvent(
        group_id=group_id,
        version=next_ver,
        actor_id=actor,
        key_fp=key_fp,
    )
    s.add(ev)
    s.commit()
    try:
        s.refresh(ev)
    except Exception:
        pass
    logger.info("group %s key rotated to v%s by %s", group_id, next_ver, actor)
    try:
        if sys_mid:
            _notify_group(group_id=group_id, sender_id=actor, message_id=sys_mid, s=s)
    except Exception:
        pass
    return GroupKeyEventOut(
        group_id=group_id,
        version=next_ver,
        actor_id=actor,
        key_fp=key_fp,
        created_at=ev.created_at.isoformat() if ev.created_at else None,
    )


@router.get("/groups/{group_id}/keys/events", response_model=List[GroupKeyEventOut])
def list_key_events(group_id: str, request: Request, device_id: str, limit: int = 20, s: Session = Depends(get_session)):
    did = device_id.strip()
    _enforce_device_actor(request, s, did)
    if not s.get(Device, did):
        raise HTTPException(status_code=404, detail="unknown device")
    if not s.get(Group, group_id):
        raise HTTPException(status_code=404, detail="unknown group")
    if not _is_group_admin(s, group_id, did):
        raise HTTPException(status_code=403, detail="admin required")
    q = (
        s.query(GroupKeyEvent)
        .filter(GroupKeyEvent.group_id == group_id)
        .order_by(GroupKeyEvent.created_at.desc())
        .limit(max(1, min(limit, 200)))
        .all()
    )
    out: List[GroupKeyEventOut] = []
    for r in q:
        out.append(
            GroupKeyEventOut(
                group_id=r.group_id,
                version=int(r.version or 0),
                actor_id=r.actor_id,
                key_fp=r.key_fp,
                created_at=r.created_at.isoformat() if r.created_at else None,
            )
        )
    return out


@router.get("/messages/inbox", response_model=List[MsgOut])
def inbox(request: Request, device_id: str, since_iso: Optional[str] = None, limit: int = 50, sealed_view: bool = True, s: Session = Depends(get_session)):
    _enforce_device_actor(request, s, device_id)
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
def stream(request: Request, device_id: str, sealed_view: bool = True, s: Session = Depends(get_session)):
    _enforce_device_actor(request, s, device_id)
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
    device_id: Optional[str] = None


@router.post("/messages/{mid}/read")
def mark_read(mid: str, request: Request, req: ReadReq, s: Session = Depends(get_session)):
    m = s.get(Message, mid)
    if not m:
        raise HTTPException(status_code=404, detail="not found")
    actor = _require_device_actor(request, s)
    claimed = (req.device_id or "").strip() or None
    if actor and actor != m.recipient_id:
        raise HTTPException(status_code=403, detail="not recipient")
    if claimed and claimed != m.recipient_id:
        raise HTTPException(status_code=403, detail="not recipient")
    m.read_at = datetime.now(timezone.utc)
    s.add(m); s.commit(); s.refresh(m)
    return {"ok": True, "id": m.id, "read_at": m.read_at.isoformat() if m.read_at else None}


class PushTokenReq(BaseModel):
    token: str = Field(min_length=8, max_length=512)
    platform: Optional[str] = Field(default=None, max_length=30)
    ts: Optional[str] = None


@router.post("/devices/{device_id}/push_token")
def register_push_token(device_id: str, request: Request, req: PushTokenReq, s: Session = Depends(get_session)):
    _enforce_device_actor(request, s, device_id)
    if not s.get(Device, device_id):
        raise HTTPException(status_code=404, detail="unknown device")
    # Dedup by token to avoid bloat
    s.query(PushToken).filter(PushToken.token == req.token).delete()
    rec = PushToken(device_id=device_id, token=req.token, platform=req.platform)
    s.add(rec)
    s.commit()
    return {"ok": True, "token": req.token, "platform": req.platform or "unknown"}


@router.post("/devices/{device_id}/block")
def set_block(device_id: str, request: Request, req: ContactRuleReq, s: Session = Depends(get_session)):
    _enforce_device_actor(request, s, device_id)
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


@router.post("/devices/{device_id}/prefs")
def set_prefs(device_id: str, request: Request, req: ContactPrefsReq, s: Session = Depends(get_session)):
    _enforce_device_actor(request, s, device_id)
    if not s.get(Device, device_id):
        raise HTTPException(status_code=404, detail="unknown device")
    if device_id == req.peer_id:
        raise HTTPException(status_code=400, detail="cannot set prefs for self")
    r = s.query(ContactRule).filter(ContactRule.device_id == device_id, ContactRule.peer_id == req.peer_id).first()
    if not r:
        r = ContactRule(device_id=device_id, peer_id=req.peer_id)
    if req.muted is not None:
        r.muted = bool(req.muted)
    if req.starred is not None:
        r.starred = bool(req.starred)
    if req.pinned is not None:
        r.pinned = bool(req.pinned)
    s.add(r); s.commit(); s.refresh(r)
    return {
        "ok": True,
        "peer_id": req.peer_id,
        "muted": r.muted,
        "starred": r.starred,
        "pinned": r.pinned,
    }


@router.get("/devices/{device_id}/prefs")
def list_prefs(device_id: str, request: Request, s: Session = Depends(get_session)):
    _enforce_device_actor(request, s, device_id)
    if not s.get(Device, device_id):
        raise HTTPException(status_code=404, detail="unknown device")
    rows = s.query(ContactRule).filter(ContactRule.device_id == device_id).all()
    out = []
    for r in rows:
        out.append(
            {
                "peer_id": r.peer_id,
                "blocked": bool(r.blocked),
                "hidden": bool(r.hidden),
                "muted": bool(r.muted),
                "starred": bool(r.starred),
                "pinned": bool(r.pinned),
            }
        )
    return {"prefs": out}


@router.post("/devices/{device_id}/group_prefs")
def set_group_prefs(device_id: str, request: Request, req: GroupPrefsReq, s: Session = Depends(get_session)):
    _enforce_device_actor(request, s, device_id)
    if not s.get(Device, device_id):
        raise HTTPException(status_code=404, detail="unknown device")
    gid = req.group_id.strip()
    if not gid:
        raise HTTPException(status_code=400, detail="invalid group id")
    if not s.get(Group, gid):
        raise HTTPException(status_code=404, detail="unknown group")
    if not _is_group_member(s, gid, device_id):
        raise HTTPException(status_code=403, detail="not a member")
    r = (
        s.query(GroupPrefs)
        .filter(GroupPrefs.device_id == device_id, GroupPrefs.group_id == gid)
        .first()
    )
    if not r:
        r = GroupPrefs(device_id=device_id, group_id=gid)
    if req.muted is not None:
        r.muted = bool(req.muted)
    if req.pinned is not None:
        r.pinned = bool(req.pinned)
    s.add(r)
    s.commit()
    try:
        s.refresh(r)
    except Exception:
        pass
    return {"ok": True, "group_id": gid, "muted": bool(r.muted), "pinned": bool(r.pinned)}


@router.get("/devices/{device_id}/group_prefs", response_model=List[GroupPrefsOut])
def list_group_prefs(device_id: str, request: Request, s: Session = Depends(get_session)):
    _enforce_device_actor(request, s, device_id)
    if not s.get(Device, device_id):
        raise HTTPException(status_code=404, detail="unknown device")
    rows = s.query(GroupPrefs).filter(GroupPrefs.device_id == device_id).all()
    out: List[GroupPrefsOut] = []
    for r in rows:
        out.append(
            GroupPrefsOut(
                group_id=r.group_id,
                muted=bool(r.muted),
                pinned=bool(r.pinned),
            )
        )
    return out


@router.get("/devices/{device_id}/hidden")
def list_hidden(device_id: str, request: Request, s: Session = Depends(get_session)):
    _enforce_device_actor(request, s, device_id)
    if not s.get(Device, device_id):
        raise HTTPException(status_code=404, detail="unknown device")
    rows = s.query(ContactRule.peer_id).filter(ContactRule.device_id == device_id, ContactRule.hidden == True).all()
    return {"hidden": [r[0] for r in rows]}


app.include_router(router)


# --- Helpers ---
def _notify_recipient(
    recipient_id: str,
    message_id: str,
    s: Session,
    group_id: Optional[str] = None,
    sender_id: Optional[str] = None,
    group_name: Optional[str] = None,
):
    if not FCM_SERVER_KEY:
        return
    try:
        msg = s.get(Message, message_id)
    except Exception:
        msg = None
    sender_hint = None
    if msg is not None:
        try:
            if _is_muted(s, device_id=recipient_id, peer_id=msg.sender_id):
                return
        except Exception:
            pass
        try:
            sender_hint = (msg.sender_hint or "").strip() or None
        except Exception:
            sender_hint = None
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
                **({"sender_hint": sender_hint} if sender_hint else {}),
                **({"sender_id": sender_id} if sender_id else {}),
                **({"group_id": group_id} if group_id else {}),
                **({"group_name": group_name} if group_name else {}),
            },
        }
        try:
            httpx.post(FCM_ENDPOINT, headers=headers, json=payload, timeout=5)
        except Exception:
            continue


def _is_group_member(s: Session, group_id: str, device_id: str) -> bool:
    try:
        return bool(
            s.query(GroupMember)
            .filter(GroupMember.group_id == group_id, GroupMember.device_id == device_id)
            .first()
        )
    except Exception:
        return False


def _is_group_admin(s: Session, group_id: str, device_id: str) -> bool:
    try:
        r = (
            s.query(GroupMember)
            .filter(GroupMember.group_id == group_id, GroupMember.device_id == device_id)
            .first()
        )
        if not r:
            return False
        return (r.role or "").lower() == "admin"
    except Exception:
        return False


def _group_members(s: Session, group_id: str) -> List[str]:
    try:
        rows = s.query(GroupMember.device_id).filter(GroupMember.group_id == group_id).all()
        return [r[0] for r in rows]
    except Exception:
        return []


def _notify_group(group_id: str, sender_id: str, message_id: str, s: Session):
    if not FCM_SERVER_KEY:
        return
    group_name = None
    try:
        g = s.get(Group, group_id)
        if g is not None:
            group_name = (getattr(g, "name", "") or "").strip() or None
    except Exception:
        group_name = None
    members = _group_members(s, group_id)
    for did in members:
        if did == sender_id:
            continue
        # Respect group mute for recipient (WeChat-like).
        try:
            if (
                s.query(GroupPrefs)
                .filter(
                    GroupPrefs.device_id == did,
                    GroupPrefs.group_id == group_id,
                    GroupPrefs.muted == True,
                )
                .first()
            ):
                continue
        except Exception:
            pass
        # Best-effort: respect blocks against sender
        try:
            if _is_blocked(s, device_id=did, peer_id=sender_id):
                continue
        except Exception:
            pass
        _notify_recipient(
            recipient_id=did,
            message_id=message_id,
            s=s,
            group_id=group_id,
            sender_id=sender_id,
            group_name=group_name,
        )


def _purge_expired(s: Session):
    now = datetime.now(timezone.utc)
    try:
        s.query(Message).filter(Message.expire_at != None, Message.expire_at < now).delete()  # type: ignore[comparison-overlap]
        s.query(GroupMessage).filter(GroupMessage.expire_at != None, GroupMessage.expire_at < now).delete()  # type: ignore[comparison-overlap]
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


def _is_muted(s: Session, device_id: str, peer_id: Optional[str]) -> bool:
    if peer_id is None:
        return bool(
            s.query(ContactRule)
            .filter(ContactRule.device_id == device_id, ContactRule.muted == True)
            .first()
        )
    return bool(
        s.query(ContactRule)
        .filter(
            ContactRule.device_id == device_id,
            ContactRule.peer_id == peer_id,
            ContactRule.muted == True,
        )
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
