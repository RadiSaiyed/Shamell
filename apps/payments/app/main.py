from fastapi import FastAPI, HTTPException
from fastapi import Depends, APIRouter
from shamell_shared import RequestIDMiddleware, configure_cors, add_standard_health, setup_json_logging
from starlette.requests import Request
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field, ConfigDict
from typing import Optional, List
import re
import os
import uuid

from sqlalchemy import create_engine, String, BigInteger, ForeignKey, Integer, DateTime, func, UniqueConstraint
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship, Session
from sqlalchemy import select, func as sa_func
from sqlalchemy import text as sa_text
from datetime import datetime, timezone, timedelta
import base64 as _b64
import json as _json
import secrets as _secrets
import hashlib as _hashlib
import hmac as _hmac
from typing import Dict


def _env_or(key: str, default: str) -> str:
    v = os.getenv(key)
    return v if v is not None else default


DB_URL = _env_or("PAYMENTS_DB_URL", _env_or("DB_URL", "sqlite+pysqlite:////tmp/payments.db"))
DB_SCHEMA = os.getenv("DB_SCHEMA") if not DB_URL.startswith("sqlite") else None
AUTO_CREATE = _env_or("AUTO_CREATE_SCHEMA", "true").lower() == "true"
DEFAULT_CURRENCY = _env_or("DEFAULT_CURRENCY", "SYP")
DEV_ENABLE_TOPUP = _env_or("DEV_ENABLE_TOPUP", "false").lower() == "true"
ALLOW_INSECURE_DEV_ADMIN_BYPASS = _env_or("ALLOW_INSECURE_DEV_ADMIN_BYPASS", "false").lower() == "true"
SONIC_SECRET = os.getenv("SONIC_SECRET", "change-me-sonic")
SONIC_TTL_SECS = int(_env_or("SONIC_TTL_SECS", "120"))
TOPUP_SECRET = os.getenv("TOPUP_SECRET", "change-me-topup")

# Admin/internal protection
ADMIN_TOKEN = os.getenv("ADMIN_TOKEN")
ADMIN_TOKEN_SHA256 = os.getenv("ADMIN_TOKEN_SHA256") or os.getenv("PAYMENTS_ADMIN_TOKEN_SHA256")
INTERNAL_API_SECRET = os.getenv("INTERNAL_API_SECRET") or os.getenv("PAYMENTS_INTERNAL_SECRET")

# Fees & KYC
FEE_WALLET_PHONE = _env_or("FEE_WALLET_PHONE", "+963999999999")
MERCHANT_FEE_BPS = int(_env_or("MERCHANT_FEE_BPS", "150"))

def _env_int(key: str, default: int) -> int:
    try:
        return int(os.getenv(key, str(default)))
    except Exception:
        return default

KYC_LIMITS = {
    0: {
        "tx_max": _env_int("KYC_L0_TX_MAX_CENTS", 100_000_000),
        "daily_max": _env_int("KYC_L0_DAILY_MAX_CENTS", 500_000_000),
    },
    1: {
        "tx_max": _env_int("KYC_L1_TX_MAX_CENTS", 500_000_000),
        "daily_max": _env_int("KYC_L1_DAILY_MAX_CENTS", 2_000_000_000),
    },
    2: {
        "tx_max": _env_int("KYC_L2_TX_MAX_CENTS", 1_000_000_000),
        "daily_max": _env_int("KYC_L2_DAILY_MAX_CENTS", 3_000_000_000),
    },
}

# Red-packet defaults (WeChat-style hongbao)
REDPACKET_DEFAULT_TTL_SECS = _env_int("REDPACKET_TTL_SECS", 24 * 3600)
REDPACKET_MAX_COUNT = _env_int("REDPACKET_MAX_COUNT", 128)

ALLOWED_ROLES = {
    # Core payment roles
    "merchant",
    "qr_seller",
    "cashout_operator",
    # Legacy/admin/backoffice roles kept for compatibility
    "admin",
    "superadmin",
    "seller",
    "ops",
    "operator_bus",
    "operator_taxi",
}


class Base(DeclarativeBase):
    pass


class User(Base):
    __tablename__ = "users"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    phone: Mapped[str] = mapped_column(String(32), unique=True, index=True)
    kyc_level: Mapped[int] = mapped_column(Integer, default=0)
    wallet: Mapped["Wallet"] = relationship(back_populates="user", uselist=False)


class Wallet(Base):
    __tablename__ = "wallets"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    if DB_SCHEMA:
        user_id: Mapped[str] = mapped_column(String(36), ForeignKey(f"{DB_SCHEMA}.users.id"), unique=True)
    else:
        user_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.id"), unique=True)
    balance_cents: Mapped[int] = mapped_column(BigInteger, default=0)
    currency: Mapped[str] = mapped_column(String(3), default=DEFAULT_CURRENCY)
    user: Mapped[User] = relationship(back_populates="wallet")


class Txn(Base):
    __tablename__ = "txns"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    from_wallet_id: Mapped[Optional[str]] = mapped_column(String(36), nullable=True)
    to_wallet_id: Mapped[str] = mapped_column(String(36))
    amount_cents: Mapped[int] = mapped_column(BigInteger)
    kind: Mapped[str] = mapped_column(String(16))  # topup|transfer
    fee_cents: Mapped[int] = mapped_column(BigInteger, default=0)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class LedgerEntry(Base):
    __tablename__ = "ledger_entries"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    wallet_id: Mapped[Optional[str]] = mapped_column(String(36), nullable=True)
    amount_cents: Mapped[int] = mapped_column(BigInteger)
    txn_id: Mapped[Optional[str]] = mapped_column(String(36), nullable=True)
    description: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Idempotency(Base):
    __tablename__ = "idempotency"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    ikey: Mapped[str] = mapped_column(String(128), unique=True, index=True)
    endpoint: Mapped[str] = mapped_column(String(32))
    txn_id: Mapped[Optional[str]] = mapped_column(String(36), nullable=True)
    amount_cents: Mapped[Optional[int]] = mapped_column(BigInteger, nullable=True)
    currency: Mapped[Optional[str]] = mapped_column(String(3), nullable=True)
    wallet_id: Mapped[Optional[str]] = mapped_column(String(36), nullable=True)
    balance_cents: Mapped[Optional[int]] = mapped_column(BigInteger, nullable=True)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Alias(Base):
    __tablename__ = "aliases"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    handle: Mapped[str] = mapped_column(String(32), unique=True, index=True)  # normalized (lowercase, no @)
    display: Mapped[str] = mapped_column(String(32))  # as chosen (may contain case)
    user_id: Mapped[str] = mapped_column(String(36))
    wallet_id: Mapped[str] = mapped_column(String(36))
    status: Mapped[str] = mapped_column(String(16), default="pending")  # pending|active|blocked
    code_hash: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    code_expires_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class AliasDeviceEvent(Base):
    __tablename__ = "alias_device_events"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    handle: Mapped[Optional[str]] = mapped_column(String(32), nullable=True)
    to_wallet_id: Mapped[str] = mapped_column(String(36))
    device_id: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    ip: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class RiskDeny(Base):
    __tablename__ = "risk_denylists"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    kind: Mapped[str] = mapped_column(String(16))  # ip|device
    value: Mapped[str] = mapped_column(String(64), index=True)
    note: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class RiskBackoff(Base):
    __tablename__ = "risk_backoff"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    key_type: Mapped[str] = mapped_column(String(16))  # device|ip
    key_value: Mapped[str] = mapped_column(String(64), index=True)
    strikes: Mapped[int] = mapped_column(Integer, default=0)
    last_strike: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), nullable=True)

class SonicToken(Base):
    __tablename__ = "sonic_tokens"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    token_hash: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    from_wallet_id: Mapped[str] = mapped_column(String(36))
    to_wallet_id: Mapped[Optional[str]] = mapped_column(String(36), nullable=True)
    amount_cents: Mapped[int] = mapped_column(BigInteger)
    currency: Mapped[str] = mapped_column(String(3), default=DEFAULT_CURRENCY)
    status: Mapped[str] = mapped_column(String(16), default="reserved")  # reserved|redeemed|expired|cancelled
    expires_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())
    redeemed_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), nullable=True)
    nonce: Mapped[str] = mapped_column(String(24))


class CashMandate(Base):
    __tablename__ = "cash_mandates"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    code: Mapped[str] = mapped_column(String(8), unique=True, index=True)
    secret_hash: Mapped[str] = mapped_column(String(64))  # sha256 hex
    amount_cents: Mapped[int] = mapped_column(BigInteger)
    currency: Mapped[str] = mapped_column(String(3), default=DEFAULT_CURRENCY)
    from_wallet_id: Mapped[str] = mapped_column(String(36))
    status: Mapped[str] = mapped_column(String(16), default="reserved")  # reserved|redeemed|cancelled|expired
    expires_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())
    redeemed_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), nullable=True)
    agent_id: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    attempts: Mapped[int] = mapped_column(Integer, default=0)


# --- Topup Voucher (kiosk) ---
class TopupVoucher(Base):
    __tablename__ = "topup_vouchers"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    code: Mapped[str] = mapped_column(String(24), unique=True, index=True)
    amount_cents: Mapped[int] = mapped_column(BigInteger)
    currency: Mapped[str] = mapped_column(String(3), default=DEFAULT_CURRENCY)
    status: Mapped[str] = mapped_column(String(16), default="reserved")  # reserved|redeemed|void|expired
    batch_id: Mapped[str] = mapped_column(String(36), index=True)
    seller_id: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    note: Mapped[Optional[str]] = mapped_column(String(128), nullable=True)
    funding_wallet_id: Mapped[Optional[str]] = mapped_column(String(36), nullable=True)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())
    redeemed_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), nullable=True)
    expires_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), nullable=True)

# (External provider scaffold removed as requested)


# ---- Simple features inspired by popular wallets ----
class Favorite(Base):
    __tablename__ = "favorites"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    owner_wallet_id: Mapped[str] = mapped_column(String(36))
    favorite_wallet_id: Mapped[str] = mapped_column(String(36))
    alias: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class PaymentRequest(Base):
    __tablename__ = "payment_requests"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    from_wallet_id: Mapped[str] = mapped_column(String(36))  # requester (payee)
    to_wallet_id: Mapped[str] = mapped_column(String(36))    # recipient (payer)
    amount_cents: Mapped[int] = mapped_column(BigInteger)
    currency: Mapped[str] = mapped_column(String(3), default=DEFAULT_CURRENCY)
    message: Mapped[Optional[str]] = mapped_column(String(255), default=None)
    status: Mapped[str] = mapped_column(String(16), default="pending")  # pending|accepted|canceled|expired
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())
    expires_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), nullable=True)


class RedPacket(Base):
    """
    WeChat-style red-packet pool.

    Funds are reserved from creator_wallet_id on issue and moved into a
    global liability bucket (wallet_id=None). Individual claims then draw
    down from remaining_amount_cents and credit claimant wallets.
    """
    __tablename__ = "red_packets"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    creator_wallet_id: Mapped[str] = mapped_column(String(36))
    group_id: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)  # optional Mirsaal/group binding
    total_amount_cents: Mapped[int] = mapped_column(BigInteger)
    remaining_amount_cents: Mapped[int] = mapped_column(BigInteger)
    total_count: Mapped[int] = mapped_column(Integer)
    claimed_count: Mapped[int] = mapped_column(Integer, default=0)
    mode: Mapped[str] = mapped_column(String(16), default="fixed")  # fixed|random
    message: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    status: Mapped[str] = mapped_column(String(16), default="active")  # active|exhausted|expired|cancelled
    currency: Mapped[str] = mapped_column(String(3), default=DEFAULT_CURRENCY)
    expires_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class RedPacketClaim(Base):
    """
    Individual claim from a red packet.
    """
    __tablename__ = "red_packet_claims"
    __table_args__ = (
        UniqueConstraint("redpacket_id", "wallet_id", name="uq_redpacket_wallet"),
        {"schema": DB_SCHEMA} if DB_SCHEMA else {},
    )
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    redpacket_id: Mapped[str] = mapped_column(String(36))
    wallet_id: Mapped[str] = mapped_column(String(36))
    amount_cents: Mapped[int] = mapped_column(BigInteger)
    claim_index: Mapped[int] = mapped_column(Integer)  # 1-based claim order within packet
    claimed_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class SavingsAccount(Base):
    __tablename__ = "savings_accounts"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    wallet_id: Mapped[str] = mapped_column(String(36), unique=True, index=True)
    balance_cents: Mapped[int] = mapped_column(BigInteger, default=0)
    currency: Mapped[str] = mapped_column(String(3), default=DEFAULT_CURRENCY)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class BillPayment(Base):
    __tablename__ = "bill_payments"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    from_wallet_id: Mapped[str] = mapped_column(String(36))
    to_wallet_id: Mapped[str] = mapped_column(String(36))
    biller_code: Mapped[str] = mapped_column(String(64))
    reference: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    amount_cents: Mapped[int] = mapped_column(BigInteger)
    currency: Mapped[str] = mapped_column(String(3), default=DEFAULT_CURRENCY)
    status: Mapped[str] = mapped_column(String(16), default="posted")  # posted|failed
    txn_id: Mapped[str] = mapped_column(String(36))
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


# --- Roles/Directory (for BFF gating) ---
class Role(Base):
    __tablename__ = "roles"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    phone: Mapped[str] = mapped_column(String(32), index=True)
    role: Mapped[str] = mapped_column(String(32), index=True)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


if DB_URL.startswith("sqlite"):
    engine = create_engine(DB_URL, pool_pre_ping=True, connect_args={"check_same_thread": False})
else:
    engine = create_engine(DB_URL, pool_pre_ping=True)


def get_session():
    with Session(engine) as s:
        yield s


app = FastAPI(title="Payments API", version="0.1.0")
setup_json_logging()
app.add_middleware(RequestIDMiddleware)
configure_cors(app, os.getenv("ALLOWED_ORIGINS", "*"))
add_standard_health(app)

router = APIRouter()


def require_admin(request: Request) -> bool:
    token = request.headers.get("X-Admin-Token")
    internal = request.headers.get("X-Internal-Secret")
    if INTERNAL_API_SECRET and internal and _hmac.compare_digest(internal, INTERNAL_API_SECRET):
        return True
    if ADMIN_TOKEN and token and _hmac.compare_digest(token, ADMIN_TOKEN):
        return True
    if ADMIN_TOKEN_SHA256 and token:
        import hashlib
        digest = hashlib.sha256(token.encode()).hexdigest()
        if _hmac.compare_digest(digest, ADMIN_TOKEN_SHA256):
            return True
    if (
        _env_or("ENV", "dev") == "dev"
        and DEV_ENABLE_TOPUP
        and ALLOW_INSECURE_DEV_ADMIN_BYPASS
        and not (ADMIN_TOKEN or ADMIN_TOKEN_SHA256 or INTERNAL_API_SECRET)
    ):
        return True
    raise HTTPException(status_code=401, detail="Admin token required")


def _mark_request_expired(req: PaymentRequest, s: Session) -> bool:
    """
    Mark a payment request as expired if its expires_at is in the past.
    Returns True if it was marked expired.
    """
    try:
        exp = req.expires_at
        if isinstance(exp, str):
            try:
                exp = datetime.fromisoformat(exp)
            except Exception:
                exp = None
        if exp and isinstance(exp, datetime):
            if exp.tzinfo is None:
                exp = exp.replace(tzinfo=timezone.utc)
            if exp < datetime.now(timezone.utc) and req.status == "pending":
                req.status = "expired"
                s.add(req)
                s.commit()
                return True
    except Exception:
        pass
    return False


def on_startup():
    if AUTO_CREATE:
        Base.metadata.create_all(engine)
        _run_simple_migrations()
        _ensure_fee_wallet()
    # Ensure auxiliary tables exist (idempotent)
    try:
        _ensure_idempotency_table()
    except Exception:
        pass
    try:
        _ensure_aliases_table()
    except Exception:
        pass
    try:
        _ensure_alias_device_events_table()
    except Exception:
        pass
    try:
        _ensure_risk_tables()
    except Exception:
        pass
    try:
        _ensure_topup_vouchers_table()
    except Exception:
        pass
    try:
        _ensure_roles_table()
    except Exception:
        pass
    # Optional: run Alembic migrations on startup when enabled
    if _env_or("RUN_ALEMBIC_ON_STARTUP", "false").lower() == "true":
        import logging as _lg
        _lg.getLogger(__name__).info("running alembic upgrade head on startup")
        try:
            from alembic.config import Config as _AlCfg
            from alembic import command as _alcmd
            cfg = _AlCfg("/app/apps/payments/alembic.ini")
            _alcmd.upgrade(cfg, "head")
            _lg.getLogger(__name__).info("alembic upgrade head: success")
        except Exception as e:
            _lg.getLogger(__name__).error(f"alembic upgrade failed: {e}")
        try:
            _ensure_idempotency_table()
            _lg.getLogger(__name__).info("idempotency table ensured")
        except Exception as e:
            _lg.getLogger(__name__).error(f"ensure idempotency table failed: {e}")
        try:
            _ensure_aliases_table()
            _lg.getLogger(__name__).info("aliases table ensured")
        except Exception as e:
            _lg.getLogger(__name__).error(f"ensure aliases table failed: {e}")
        try:
            _ensure_sonic_tokens_table()
            _lg.getLogger(__name__).info("sonic_tokens table ensured")
        except Exception as e:
            _lg.getLogger(__name__).error(f"ensure sonic_tokens table failed: {e}")
        try:
            _ensure_cash_mandate_table()
            _lg.getLogger(__name__).info("cash_mandates table ensured")
        except Exception as e:
            _lg.getLogger(__name__).error(f"ensure cash_mandates table failed: {e}")
    # Ensure external tables (create_all already does, but keep guard paths)
    try:
        with engine.begin() as conn:
            # create tables if not exist in dev/sqlite fallback
            conn.exec_driver_sql("""
            CREATE TABLE IF NOT EXISTS favorites (
              id TEXT PRIMARY KEY,
              owner_wallet_id TEXT,
              favorite_wallet_id TEXT,
              alias TEXT,
              created_at TIMESTAMPTZ DEFAULT NOW()
            )
            """)
            conn.exec_driver_sql("""
            CREATE TABLE IF NOT EXISTS payment_requests (
              id TEXT PRIMARY KEY,
              from_wallet_id TEXT,
              to_wallet_id TEXT,
              amount_cents BIGINT,
              currency TEXT,
              message TEXT,
              status TEXT,
              created_at TIMESTAMPTZ DEFAULT NOW(),
              expires_at TIMESTAMPTZ
            )
            """)
    except Exception:
        pass


app.router.on_startup.append(on_startup)

def _run_simple_migrations():
    # Best-effort add columns if missing (for dev/demo only)
    with engine.begin() as conn:
        # users.kyc_level
        try:
            conn.exec_driver_sql("ALTER TABLE users ADD COLUMN kyc_level INTEGER DEFAULT 0")
        except Exception:
            pass
        # txns.fee_cents
        try:
            conn.exec_driver_sql("ALTER TABLE txns ADD COLUMN fee_cents BIGINT DEFAULT 0")
        except Exception:
            pass
        # txns.created_at
        try:
            conn.exec_driver_sql("ALTER TABLE txns ADD COLUMN created_at TIMESTAMPTZ DEFAULT NOW()")
        except Exception:
            pass
        # idempotency.amount_cents / currency / wallet_id / balance_cents
        for col_sql in [
            "ALTER TABLE idempotency ADD COLUMN amount_cents BIGINT",
            "ALTER TABLE idempotency ADD COLUMN currency VARCHAR(3)",
            "ALTER TABLE idempotency ADD COLUMN wallet_id VARCHAR(36)",
            "ALTER TABLE idempotency ADD COLUMN balance_cents BIGINT",
        ]:
            try:
                conn.exec_driver_sql(col_sql)
            except Exception:
                pass


def _ensure_fee_wallet():
    if not FEE_WALLET_PHONE:
        return
    with Session(engine) as s:
        u = s.scalar(select(User).where(User.phone == FEE_WALLET_PHONE))
        if not u:
            u = User(id=str(uuid.uuid4()), phone=FEE_WALLET_PHONE, kyc_level=2)
            w = Wallet(id=str(uuid.uuid4()), user_id=u.id, balance_cents=0, currency=DEFAULT_CURRENCY)
            u.wallet = w
            s.add_all([u, w])
            s.commit()
    
def _ensure_idempotency_table():
    if DB_URL.startswith("sqlite"):
        # SQLite: rely on create_all + simple migrations
        _run_simple_migrations()
        return
    schema = DB_SCHEMA or "public"
    create_sql = f"""
    CREATE TABLE IF NOT EXISTS {schema}.idempotency (
        id VARCHAR(36) PRIMARY KEY,
        ikey VARCHAR(128) UNIQUE,
        endpoint VARCHAR(32) NOT NULL,
        txn_id VARCHAR(36),
        amount_cents BIGINT,
        currency VARCHAR(3),
        wallet_id VARCHAR(36),
        balance_cents BIGINT,
        created_at TIMESTAMPTZ DEFAULT NOW()
    );
    """
    idx_sql = f"CREATE UNIQUE INDEX IF NOT EXISTS ix_{schema}_idempotency_ikey ON {schema}.idempotency (ikey);"
    with engine.begin() as conn:
        conn.exec_driver_sql(create_sql)
        conn.exec_driver_sql(idx_sql)
        try:
            exists = conn.exec_driver_sql(
                "SELECT column_name FROM information_schema.columns WHERE table_schema = :schema AND table_name = 'idempotency' AND column_name = 'amount_cents'",
                {"schema": schema},
            ).fetchone()
            if not exists:
                conn.exec_driver_sql(f"ALTER TABLE {schema}.idempotency ADD COLUMN amount_cents BIGINT")
                conn.exec_driver_sql(f"ALTER TABLE {schema}.idempotency ADD COLUMN currency VARCHAR(3)")
                conn.exec_driver_sql(f"ALTER TABLE {schema}.idempotency ADD COLUMN wallet_id VARCHAR(36)")
                conn.exec_driver_sql(f"ALTER TABLE {schema}.idempotency ADD COLUMN balance_cents BIGINT")
        except Exception:
            pass


def _ensure_aliases_table():
    if DB_URL.startswith("sqlite"):
        return
    schema = DB_SCHEMA or "public"
    create_sql = f"""
    CREATE TABLE IF NOT EXISTS {schema}.aliases (
        id VARCHAR(36) PRIMARY KEY,
        handle VARCHAR(32) UNIQUE,
        display VARCHAR(32) NOT NULL,
        user_id VARCHAR(36) NOT NULL,
        wallet_id VARCHAR(36) NOT NULL,
        status VARCHAR(16) NOT NULL DEFAULT 'pending',
        code_hash VARCHAR(64),
        code_expires_at TIMESTAMPTZ,
        created_at TIMESTAMPTZ DEFAULT NOW()
    );
    """
    idx_sql = f"CREATE UNIQUE INDEX IF NOT EXISTS ix_{schema}_alias_handle ON {schema}.aliases (handle);"
    with engine.begin() as conn:
        conn.exec_driver_sql(create_sql)
        conn.exec_driver_sql(idx_sql)


def _ensure_alias_device_events_table():
    if DB_URL.startswith("sqlite"):
        return
    schema = DB_SCHEMA or "public"
    create_sql = f"""
    CREATE TABLE IF NOT EXISTS {schema}.alias_device_events (
        id VARCHAR(36) PRIMARY KEY,
        handle VARCHAR(32),
        to_wallet_id VARCHAR(36) NOT NULL,
        device_id VARCHAR(64),
        ip VARCHAR(64),
        created_at TIMESTAMPTZ DEFAULT NOW()
    );
    """
    idx_sql = f"CREATE INDEX IF NOT EXISTS ix_{schema}_alias_dev_min ON {schema}.alias_device_events (to_wallet_id, created_at);"
    with engine.begin() as conn:
        conn.exec_driver_sql(create_sql)
        conn.exec_driver_sql(idx_sql)


def _ensure_risk_tables():
    if DB_URL.startswith("sqlite"):
        return
    schema = DB_SCHEMA or "public"
    with engine.begin() as conn:
        conn.exec_driver_sql(f"""
        CREATE TABLE IF NOT EXISTS {schema}.risk_denylists (
            id VARCHAR(36) PRIMARY KEY,
            kind VARCHAR(16) NOT NULL,
            value VARCHAR(64) NOT NULL,
            note VARCHAR(255),
            created_at TIMESTAMPTZ DEFAULT NOW()
        );
        """)
        conn.exec_driver_sql(f"CREATE INDEX IF NOT EXISTS ix_{schema}_risk_deny ON {schema}.risk_denylists (kind, value);")
        conn.exec_driver_sql(f"""
        CREATE TABLE IF NOT EXISTS {schema}.risk_backoff (
            id VARCHAR(36) PRIMARY KEY,
            key_type VARCHAR(16) NOT NULL,
            key_value VARCHAR(64) NOT NULL,
            strikes INTEGER NOT NULL DEFAULT 0,
            last_strike TIMESTAMPTZ
        );
        """)
        conn.exec_driver_sql(f"CREATE INDEX IF NOT EXISTS ix_{schema}_risk_backoff ON {schema}.risk_backoff (key_type, key_value);")


def _ensure_sonic_tokens_table():
    if DB_URL.startswith("sqlite"):
        return
    schema = DB_SCHEMA or "public"
    create_sql = f"""
    CREATE TABLE IF NOT EXISTS {schema}.sonic_tokens (
        id VARCHAR(36) PRIMARY KEY,
        token_hash VARCHAR(64) UNIQUE,
        from_wallet_id VARCHAR(36) NOT NULL,
        to_wallet_id VARCHAR(36),
        amount_cents BIGINT NOT NULL,
        currency VARCHAR(3) NOT NULL DEFAULT '{DEFAULT_CURRENCY}',
        status VARCHAR(16) NOT NULL DEFAULT 'reserved',
        expires_at TIMESTAMPTZ,
        created_at TIMESTAMPTZ DEFAULT NOW(),
        redeemed_at TIMESTAMPTZ,
        nonce VARCHAR(24) NOT NULL
    );
    """
    idx_sql = f"CREATE UNIQUE INDEX IF NOT EXISTS ix_{schema}_sonic_hash ON {schema}.sonic_tokens (token_hash);"
    with engine.begin() as conn:
        conn.exec_driver_sql(create_sql)
        conn.exec_driver_sql(idx_sql)


def _ensure_cash_mandate_table():
    if DB_URL.startswith("sqlite"):
        return
    schema = DB_SCHEMA or "public"
    create_sql = f"""
    CREATE TABLE IF NOT EXISTS {schema}.cash_mandates (
        id VARCHAR(36) PRIMARY KEY,
        code VARCHAR(8) UNIQUE,
        secret_hash VARCHAR(64) NOT NULL,
        amount_cents BIGINT NOT NULL,
        currency VARCHAR(3) NOT NULL DEFAULT '{DEFAULT_CURRENCY}',
        from_wallet_id VARCHAR(36) NOT NULL,
        status VARCHAR(16) NOT NULL DEFAULT 'reserved',
        expires_at TIMESTAMPTZ,
        created_at TIMESTAMPTZ DEFAULT NOW(),
        redeemed_at TIMESTAMPTZ,
        agent_id VARCHAR(64),
        attempts INTEGER NOT NULL DEFAULT 0
    );
    """
    idx_sql = f"CREATE UNIQUE INDEX IF NOT EXISTS ix_{schema}_cash_code ON {schema}.cash_mandates (code);"
    with engine.begin() as conn:
        conn.exec_driver_sql(create_sql)
        conn.exec_driver_sql(idx_sql)


def _ensure_roles_table():
    if DB_URL.startswith("sqlite"):
        return
    schema = DB_SCHEMA or "public"
    create_sql = f"""
    CREATE TABLE IF NOT EXISTS {schema}.roles (
        id VARCHAR(36) PRIMARY KEY,
        phone VARCHAR(32) NOT NULL,
        role VARCHAR(32) NOT NULL,
        created_at TIMESTAMPTZ DEFAULT NOW()
    );
    """
    idx1 = f"CREATE INDEX IF NOT EXISTS ix_{schema}_roles_phone ON {schema}.roles (phone);"
    idx2 = f"CREATE INDEX IF NOT EXISTS ix_{schema}_roles_role ON {schema}.roles (role);"
    with engine.begin() as conn:
        conn.exec_driver_sql(create_sql)
        conn.exec_driver_sql(idx1)
        conn.exec_driver_sql(idx2)


def _ensure_topup_vouchers_table():
    if DB_URL.startswith("sqlite"):
        # SQLite: best-effort schema evolution
        with engine.begin() as conn:
            try:
                cols = [row[1] for row in conn.exec_driver_sql("PRAGMA table_info(topup_vouchers)").fetchall()]
            except Exception:
                cols = []
            if not cols:
                # Table missing entirely -> create
                conn.exec_driver_sql(
                    """
                    CREATE TABLE IF NOT EXISTS topup_vouchers (
                        id VARCHAR(36) PRIMARY KEY,
                        code VARCHAR(24) UNIQUE,
                        amount_cents BIGINT NOT NULL,
                        currency VARCHAR(3) NOT NULL DEFAULT '""" + DEFAULT_CURRENCY + """',
                        status VARCHAR(16) NOT NULL DEFAULT 'reserved',
                        batch_id VARCHAR(36) NOT NULL,
                        seller_id VARCHAR(64),
                        note VARCHAR(128),
                        funding_wallet_id VARCHAR(36),
                        created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
                        redeemed_at TIMESTAMPTZ,
                        expires_at TIMESTAMPTZ
                    );
                    """
                )
            else:
                if "funding_wallet_id" not in cols:
                    try:
                        conn.exec_driver_sql("ALTER TABLE topup_vouchers ADD COLUMN funding_wallet_id VARCHAR(36)")
                    except Exception:
                        pass
            try:
                conn.exec_driver_sql("CREATE UNIQUE INDEX IF NOT EXISTS ix_topup_code ON topup_vouchers (code)")
            except Exception:
                pass
        return
    schema = DB_SCHEMA or "public"
    create_sql = f"""
    CREATE TABLE IF NOT EXISTS {schema}.topup_vouchers (
        id VARCHAR(36) PRIMARY KEY,
        code VARCHAR(24) UNIQUE,
        amount_cents BIGINT NOT NULL,
        currency VARCHAR(3) NOT NULL DEFAULT '{DEFAULT_CURRENCY}',
        status VARCHAR(16) NOT NULL DEFAULT 'reserved',
        batch_id VARCHAR(36) NOT NULL,
        seller_id VARCHAR(64),
        note VARCHAR(128),
        funding_wallet_id VARCHAR(36),
        created_at TIMESTAMPTZ DEFAULT NOW(),
        redeemed_at TIMESTAMPTZ,
        expires_at TIMESTAMPTZ
    );
    """
    idx_sql = f"CREATE UNIQUE INDEX IF NOT EXISTS ix_{schema}_topup_code ON {schema}.topup_vouchers (code);"
    with engine.begin() as conn:
        conn.exec_driver_sql(create_sql)
        conn.exec_driver_sql(idx_sql)
        try:
            exists = conn.exec_driver_sql(
                "SELECT column_name FROM information_schema.columns WHERE table_schema = :schema AND table_name = 'topup_vouchers' AND column_name = 'funding_wallet_id'",
                {"schema": schema},
            ).fetchone()
            if not exists:
                conn.exec_driver_sql(f"ALTER TABLE {schema}.topup_vouchers ADD COLUMN funding_wallet_id VARCHAR(36)")
        except Exception:
            # Best-effort; if migrations are managed elsewhere, ignore.
            pass


class CreateUserReq(BaseModel):
    phone: str = Field(..., description="E.164 phone number")


class UserResp(BaseModel):
    user_id: str
    wallet_id: str
    phone: str
    balance_cents: int
    currency: str


@router.post("/users", response_model=UserResp)
def create_user(req: CreateUserReq, s: Session = Depends(get_session)):
    # idempotent on phone
    u = s.scalar(select(User).where(User.phone == req.phone))
    if not u:
        u = User(id=str(uuid.uuid4()), phone=req.phone)
        w = Wallet(id=str(uuid.uuid4()), user_id=u.id, balance_cents=0, currency=DEFAULT_CURRENCY)
        u.wallet = w
        s.add(u)
        s.add(w)
        s.commit()
    else:
        w = s.scalar(select(Wallet).where(Wallet.user_id == u.id))
    return UserResp(user_id=u.id, wallet_id=w.id, phone=u.phone, balance_cents=w.balance_cents, currency=w.currency)


class TopupReq(BaseModel):
    amount_cents: int = Field(..., gt=0)


class WalletResp(BaseModel):
    wallet_id: str
    balance_cents: int
    currency: str


@router.post("/wallets/{wallet_id}/topup", response_model=WalletResp)
def topup(wallet_id: str, req: TopupReq, request: Request, s: Session = Depends(get_session), admin_ok: bool = Depends(require_admin)):
    # Allow only when DEV flag is on or caller is admin
    is_admin = bool(admin_ok) or (INTERNAL_API_SECRET and request.headers.get("X-Internal-Secret") == INTERNAL_API_SECRET)
    if not DEV_ENABLE_TOPUP and not is_admin:
        raise HTTPException(status_code=403, detail="Topup disabled")
    # Idempotency
    ikey = request.headers.get("Idempotency-Key")
    if ikey:
        existed = s.scalar(select(Idempotency).where(Idempotency.ikey == ikey))
        if existed:
            w0 = s.get(Wallet, wallet_id)
            if not w0:
                raise HTTPException(status_code=404, detail="Wallet not found")
            return WalletResp(wallet_id=w0.id, balance_cents=w0.balance_cents, currency=w0.currency)
    # Lock wallet row
    w = s.execute(select(Wallet).where(Wallet.id == wallet_id).with_for_update()).scalars().first()
    if not w:
        raise HTTPException(status_code=404, detail="Wallet not found")
    # transactional unit: dual-write (ledger + balance)
    w.balance_cents += req.amount_cents
    txn_id = str(uuid.uuid4())
    s.add(Txn(id=txn_id, from_wallet_id=None, to_wallet_id=wallet_id, amount_cents=req.amount_cents, kind="topup", fee_cents=0))
    # Ledger: credit wallet, debit external (wallet_id=None)
    s.add(LedgerEntry(id=str(uuid.uuid4()), wallet_id=wallet_id, amount_cents=+req.amount_cents, txn_id=txn_id, description="topup"))
    s.add(LedgerEntry(id=str(uuid.uuid4()), wallet_id=None, amount_cents=-req.amount_cents, txn_id=txn_id, description="topup_external"))
    if ikey:
        s.add(Idempotency(id=str(uuid.uuid4()), ikey=ikey, endpoint="topup", txn_id=txn_id))
    s.commit()
    s.refresh(w)
    return WalletResp(wallet_id=w.id, balance_cents=w.balance_cents, currency=w.currency)


# Favorites endpoints
class FavoriteCreate(BaseModel):
    owner_wallet_id: str
    favorite_wallet_id: str
    alias: Optional[str] = None


class FavoriteOut(BaseModel):
    id: str
    owner_wallet_id: str
    favorite_wallet_id: str
    alias: Optional[str] = None


@router.post("/favorites", response_model=FavoriteOut)
def create_favorite(req: FavoriteCreate, s: Session = Depends(get_session)):
    if req.owner_wallet_id == req.favorite_wallet_id:
        raise HTTPException(status_code=400, detail="Cannot favorite self")
    # Avoid duplicates
    existing = s.execute(select(Favorite).where(Favorite.owner_wallet_id == req.owner_wallet_id,
                                               Favorite.favorite_wallet_id == req.favorite_wallet_id)).scalars().first()
    if existing:
        existing.alias = (req.alias or existing.alias)
        s.add(existing); s.commit(); s.refresh(existing)
        return FavoriteOut(id=existing.id, owner_wallet_id=existing.owner_wallet_id,
                           favorite_wallet_id=existing.favorite_wallet_id, alias=existing.alias)
    fav = Favorite(id=str(uuid.uuid4()), owner_wallet_id=req.owner_wallet_id,
                   favorite_wallet_id=req.favorite_wallet_id, alias=(req.alias or None))
    s.add(fav); s.commit(); s.refresh(fav)
    return FavoriteOut(id=fav.id, owner_wallet_id=fav.owner_wallet_id, favorite_wallet_id=fav.favorite_wallet_id, alias=fav.alias)


@router.get("/favorites", response_model=List[FavoriteOut])
def list_favorites(owner_wallet_id: str, s: Session = Depends(get_session)):
    rows = s.execute(select(Favorite).where(Favorite.owner_wallet_id == owner_wallet_id).order_by(Favorite.created_at.desc())).scalars().all()
    return [FavoriteOut(id=f.id, owner_wallet_id=f.owner_wallet_id, favorite_wallet_id=f.favorite_wallet_id, alias=f.alias) for f in rows]


@router.delete("/favorites/{fid}")
def delete_favorite(fid: str, s: Session = Depends(get_session)):
    f = s.get(Favorite, fid)
    if not f:
        raise HTTPException(status_code=404, detail="not found")
    s.delete(f); s.commit()
    return {"ok": True}


# Payment Requests endpoints
class PaymentRequestCreate(BaseModel):
    from_wallet_id: str  # requester (payee)
    to_wallet_id: str    # payer
    amount_cents: int = Field(..., gt=0)
    message: Optional[str] = None
    expires_in_secs: Optional[int] = Field(default=None, ge=60, le=7*24*3600)


class PaymentRequestOut(BaseModel):
    id: str
    from_wallet_id: str
    to_wallet_id: str
    amount_cents: int
    currency: str
    message: Optional[str]
    status: str


@router.post("/requests", response_model=PaymentRequestOut)
def create_request(req: PaymentRequestCreate, s: Session = Depends(get_session)):
    fw = s.get(Wallet, req.from_wallet_id)
    tw = s.get(Wallet, req.to_wallet_id)
    if not fw or not tw:
        raise HTTPException(status_code=404, detail="Wallet not found")
    rid = str(uuid.uuid4())
    exp = None
    if req.expires_in_secs:
        exp = datetime.now(timezone.utc) + timedelta(seconds=int(req.expires_in_secs))
    pr = PaymentRequest(id=rid, from_wallet_id=fw.id, to_wallet_id=tw.id, amount_cents=req.amount_cents,
                        currency=fw.currency, message=(req.message or None), status="pending", expires_at=exp)
    s.add(pr); s.commit(); s.refresh(pr)
    return PaymentRequestOut(id=pr.id, from_wallet_id=pr.from_wallet_id, to_wallet_id=pr.to_wallet_id,
                             amount_cents=pr.amount_cents, currency=pr.currency, message=pr.message, status=pr.status)


@router.get("/requests", response_model=List[PaymentRequestOut])
def list_requests(wallet_id: str, kind: str = "", limit: int = 100, s: Session = Depends(get_session)):
    limit = max(1, min(limit, 500))
    q = select(PaymentRequest)
    if kind == "incoming":
        q = q.where(PaymentRequest.to_wallet_id == wallet_id)
    elif kind == "outgoing":
        q = q.where(PaymentRequest.from_wallet_id == wallet_id)
    else:
        q = q.where((PaymentRequest.to_wallet_id == wallet_id) | (PaymentRequest.from_wallet_id == wallet_id))
    q = q.order_by(PaymentRequest.created_at.desc()).limit(limit)
    rows = s.execute(q).scalars().all()
    return [PaymentRequestOut(id=r.id, from_wallet_id=r.from_wallet_id, to_wallet_id=r.to_wallet_id,
                              amount_cents=r.amount_cents, currency=r.currency, message=r.message, status=r.status) for r in rows]


@router.post("/requests/{rid}/cancel")
def cancel_request(rid: str, s: Session = Depends(get_session)):
    r = s.get(PaymentRequest, rid)
    if not r:
        raise HTTPException(status_code=404, detail="not found")
    if _mark_request_expired(r, s):
        raise HTTPException(status_code=400, detail="expired")
    if r.status != "pending":
        raise HTTPException(status_code=400, detail="not pending")
    r.status = "canceled"
    s.add(r); s.commit()
    return {"ok": True}


def _accept_request_core(rid: str, ikey: str | None, s: Session, to_wallet_id: Optional[str] = None) -> WalletResp:
    r = s.get(PaymentRequest, rid)
    if not r:
        raise HTTPException(status_code=404, detail="not found")
    # Idempotency: allow retries without double debit
    if ikey:
        existed = s.scalar(select(Idempotency).where(Idempotency.ikey == ikey))
        if existed and existed.txn_id:
            txn = s.get(Txn, existed.txn_id)
            if txn:
                payer_id = existed.wallet_id or txn.from_wallet_id
                payer = s.get(Wallet, payer_id) if payer_id else None
                if payer:
                    bal = existed.balance_cents if existed.balance_cents is not None else payer.balance_cents
                    cur = existed.currency or payer.currency
                    return WalletResp(wallet_id=payer.id, balance_cents=bal, currency=cur)
    if _mark_request_expired(r, s):
        raise HTTPException(status_code=400, detail="expired")
    if r.status != "pending":
        raise HTTPException(status_code=400, detail="not pending")
    if to_wallet_id and to_wallet_id != r.to_wallet_id:
        raise HTTPException(status_code=400, detail="wallet mismatch for request")
    # lock payer and payee
    payer = s.execute(select(Wallet).where(Wallet.id == r.to_wallet_id).with_for_update()).scalars().first()
    payee = s.execute(select(Wallet).where(Wallet.id == r.from_wallet_id).with_for_update()).scalars().first()
    if not payer or not payee:
        raise HTTPException(status_code=404, detail="wallet missing")
    if payer.balance_cents < r.amount_cents:
        raise HTTPException(status_code=400, detail="insufficient funds")
    payer.balance_cents -= r.amount_cents
    payee.balance_cents += r.amount_cents
    txn_id = str(uuid.uuid4())
    s.add(Txn(id=txn_id, from_wallet_id=payer.id, to_wallet_id=payee.id, amount_cents=r.amount_cents, kind="transfer", fee_cents=0))
    meta = f"request:{r.id}"
    s.add(LedgerEntry(id=str(uuid.uuid4()), wallet_id=payer.id, amount_cents=-r.amount_cents, txn_id=txn_id, description="transfer_debit;"+meta))
    s.add(LedgerEntry(id=str(uuid.uuid4()), wallet_id=payee.id, amount_cents=+r.amount_cents, txn_id=txn_id, description="transfer_credit;"+meta))
    r.status = "accepted"
    s.add(r)
    if ikey:
        s.add(Idempotency(id=str(uuid.uuid4()), ikey=ikey, endpoint="request_accept", txn_id=txn_id, amount_cents=r.amount_cents, currency=r.currency, wallet_id=payer.id, balance_cents=payer.balance_cents))
    s.commit()
    s.refresh(payer)
    return WalletResp(wallet_id=payer.id, balance_cents=payer.balance_cents, currency=payer.currency)


class AcceptRequestReq(BaseModel):
    to_wallet_id: str


@router.post("/requests/{rid}/accept", response_model=WalletResp)
def accept_request(rid: str, request: Request, body: AcceptRequestReq, s: Session = Depends(get_session)):
    ikey = request.headers.get("Idempotency-Key")
    return _accept_request_core(rid, ikey, s, to_wallet_id=body.to_wallet_id)


# --- Red Packet (Hongbao-style pooled payments) ---
class RedPacketIssueReq(BaseModel):
    creator_wallet_id: str
    amount_cents: int = Field(..., gt=0)
    count: int = Field(1, ge=1)
    mode: Optional[str] = Field(default=None, description="fixed|random; default random for count>1")
    group_id: Optional[str] = Field(default=None, description="Optional Mirsaal/group identifier")
    message: Optional[str] = Field(default=None, max_length=255)
    expires_in_secs: Optional[int] = Field(default=None, ge=60, le=7 * 24 * 3600)


class RedPacketIssueResp(BaseModel):
    id: str
    creator_wallet_id: str
    total_amount_cents: int
    total_count: int
    mode: str
    message: Optional[str]
    status: str
    currency: str
    expires_at: Optional[str]


@router.post("/redpacket/issue", response_model=RedPacketIssueResp)
def redpacket_issue(req: RedPacketIssueReq, s: Session = Depends(get_session)):
    if req.count < 1:
        raise HTTPException(status_code=400, detail="count must be >= 1")
    if req.count > REDPACKET_MAX_COUNT:
        raise HTTPException(status_code=400, detail="count exceeds max per packet")
    mode = (req.mode or ("fixed" if req.count == 1 else "random")).strip().lower()
    if mode not in ("fixed", "random"):
        raise HTTPException(status_code=400, detail="mode must be fixed or random")
    # Basic wallet + KYC checks on creator
    from_w = s.execute(
        select(Wallet).where(Wallet.id == req.creator_wallet_id).with_for_update()
    ).scalars().first()
    if not from_w:
        raise HTTPException(status_code=404, detail="Creator wallet not found")
    amt = int(req.amount_cents)
    if amt <= 0:
        raise HTTPException(status_code=400, detail="amount_cents must be > 0")
    # For random splits, require at least 1 cent per share
    if mode == "random" and amt < req.count:
        raise HTTPException(status_code=400, detail="amount too small for random split")
    # Simple per-transaction KYC guardrail (reuse transfer limits)
    u = s.get(User, from_w.user_id)
    level = u.kyc_level if u else 0
    lim = KYC_LIMITS.get(level, KYC_LIMITS[0])
    if amt > lim["tx_max"]:
        raise HTTPException(status_code=400, detail="Exceeds per-transaction limit for KYC level")
    if from_w.balance_cents < amt:
        raise HTTPException(status_code=400, detail="Insufficient funds")
    from_w.balance_cents -= amt
    # Expiry
    ttl = req.expires_in_secs or REDPACKET_DEFAULT_TTL_SECS
    expires_at: Optional[datetime] = None
    if ttl and ttl > 0:
        expires_at = datetime.now(timezone.utc) + timedelta(seconds=int(ttl))
    rp_id = str(uuid.uuid4())
    rp = RedPacket(
        id=rp_id,
        creator_wallet_id=from_w.id,
        group_id=req.group_id or None,
        total_amount_cents=amt,
        remaining_amount_cents=amt,
        total_count=req.count,
        claimed_count=0,
        mode=mode,
        message=(req.message or None),
        status="active",
        currency=from_w.currency,
        expires_at=expires_at,
    )
    s.add(rp)
    # Reserve funds into pool (wallet_id=None liability)
    s.add(
        LedgerEntry(
            id=str(uuid.uuid4()),
            wallet_id=from_w.id,
            amount_cents=-amt,
            txn_id=None,
            description="redpacket_reserve_debit",
        )
    )
    s.add(
        LedgerEntry(
            id=str(uuid.uuid4()),
            wallet_id=None,
            amount_cents=amt,
            txn_id=None,
            description="redpacket_reserve_pool",
        )
    )
    s.commit()
    s.refresh(rp)
    return RedPacketIssueResp(
        id=rp.id,
        creator_wallet_id=rp.creator_wallet_id,
        total_amount_cents=rp.total_amount_cents,
        total_count=rp.total_count,
        mode=rp.mode,
        message=rp.message,
        status=rp.status,
        currency=rp.currency,
        expires_at=rp.expires_at.isoformat() if rp.expires_at else None,
    )


class RedPacketClaimReq(BaseModel):
    redpacket_id: str
    wallet_id: str


class RedPacketClaimOut(BaseModel):
    redpacket_id: str
    wallet_id: str
    amount_cents: int
    claim_index: int
    total_count: int
    claimed_count: int
    message: Optional[str]
    currency: str
    status: str


@router.post("/redpacket/claim", response_model=RedPacketClaimOut)
def redpacket_claim(req: RedPacketClaimReq, s: Session = Depends(get_session)):
    rp = (
        s.execute(
            select(RedPacket)
            .where(RedPacket.id == req.redpacket_id)
            .with_for_update()
        )
        .scalars()
        .first()
    )
    if not rp:
        raise HTTPException(status_code=404, detail="red packet not found")
    # Expiry handling (best-effort)
    now = datetime.now(timezone.utc)
    exp = rp.expires_at
    if isinstance(exp, str):
        try:
            exp = datetime.fromisoformat(exp)
        except Exception:
            exp = None
    if exp is not None:
        if exp.tzinfo is None:
            exp = exp.replace(tzinfo=timezone.utc)
        if exp < now and rp.status == "active":
            rp.status = "expired"
            s.add(rp)
            s.commit()
            raise HTTPException(status_code=400, detail="red packet expired")
    # Idempotent: if this wallet already claimed, return existing share
    existing = (
        s.execute(
            select(RedPacketClaim).where(
                RedPacketClaim.redpacket_id == rp.id,
                RedPacketClaim.wallet_id == req.wallet_id,
            )
        )
        .scalars()
        .first()
    )
    if existing:
        return RedPacketClaimOut(
            redpacket_id=existing.redpacket_id,
            wallet_id=existing.wallet_id,
            amount_cents=existing.amount_cents,
            claim_index=existing.claim_index,
            total_count=rp.total_count,
            claimed_count=rp.claimed_count,
            message=rp.message,
            currency=rp.currency,
            status=rp.status,
        )
    if rp.status != "active":
        raise HTTPException(status_code=400, detail="red packet not active")
    if rp.claimed_count >= rp.total_count or rp.remaining_amount_cents <= 0:
        rp.status = "exhausted"
        s.add(rp)
        s.commit()
        raise HTTPException(status_code=400, detail="red packet empty")
    # Lock claimant wallet row
    to_w = (
        s.execute(
            select(Wallet).where(Wallet.id == req.wallet_id).with_for_update()
        )
        .scalars()
        .first()
    )
    if not to_w:
        raise HTTPException(status_code=404, detail="wallet not found")
    remaining_slots = rp.total_count - rp.claimed_count
    if remaining_slots <= 0 or rp.remaining_amount_cents <= 0:
        rp.status = "exhausted"
        s.add(rp)
        s.commit()
        raise HTTPException(status_code=400, detail="red packet empty")
    # Determine share
    if rp.mode == "fixed":
        base = rp.total_amount_cents // rp.total_count
        if base <= 0:
            base = max(1, rp.remaining_amount_cents // remaining_slots)
        if remaining_slots == 1:
            amount = rp.remaining_amount_cents
        else:
            # Ensure at least 1 cent remains for each future slot
            max_for_this = rp.remaining_amount_cents - (remaining_slots - 1)
            amount = min(base, max_for_this)
    else:  # random
        if remaining_slots == 1:
            amount = rp.remaining_amount_cents
        else:
            min_per = 1
            max_for_this = rp.remaining_amount_cents - (remaining_slots - 1) * min_per
            if max_for_this < min_per:
                max_for_this = min_per
            spread = max_for_this - min_per
            if spread <= 0:
                amount = min_per
            else:
                amount = min_per + _secrets.randbelow(spread + 1)
    if amount <= 0 or amount > rp.remaining_amount_cents:
        raise HTTPException(status_code=500, detail="internal split error")
    rp.remaining_amount_cents -= amount
    rp.claimed_count += 1
    if rp.remaining_amount_cents <= 0 or rp.claimed_count >= rp.total_count:
        rp.status = "exhausted"
    claim_index = rp.claimed_count
    to_w.balance_cents += amount
    txn_id = str(uuid.uuid4())
    s.add(
        Txn(
            id=txn_id,
            from_wallet_id=rp.creator_wallet_id,
            to_wallet_id=to_w.id,
            amount_cents=amount,
            kind="redpacket",
            fee_cents=0,
        )
    )
    s.add(
        LedgerEntry(
            id=str(uuid.uuid4()),
            wallet_id=None,
            amount_cents=-amount,
            txn_id=txn_id,
            description=f"redpacket_release:{rp.id}"
            + (f"; group={rp.group_id}" if getattr(rp, "group_id", None) else ""),
        )
    )
    s.add(
        LedgerEntry(
            id=str(uuid.uuid4()),
            wallet_id=to_w.id,
            amount_cents=amount,
            txn_id=txn_id,
            description=f"redpacket_claim:{rp.id}"
            + (f"; group={rp.group_id}" if getattr(rp, "group_id", None) else ""),
        )
    )
    claim = RedPacketClaim(
        id=str(uuid.uuid4()),
        redpacket_id=rp.id,
        wallet_id=to_w.id,
        amount_cents=amount,
        claim_index=claim_index,
    )
    s.add(claim)
    s.commit()
    s.refresh(rp)
    s.refresh(claim)
    return RedPacketClaimOut(
        redpacket_id=claim.redpacket_id,
        wallet_id=claim.wallet_id,
        amount_cents=claim.amount_cents,
        claim_index=claim.claim_index,
        total_count=rp.total_count,
        claimed_count=rp.claimed_count,
        message=rp.message,
        currency=rp.currency,
        status=rp.status,
    )


class RedPacketClaimSummary(BaseModel):
    wallet_id: str
    amount_cents: int
    claim_index: int
    claimed_at: Optional[datetime]


class RedPacketStatusOut(BaseModel):
    id: str
    creator_wallet_id: str
    group_id: Optional[str]
    total_amount_cents: int
    remaining_amount_cents: int
    total_count: int
    claimed_count: int
    mode: str
    message: Optional[str]
    status: str
    currency: str
    expires_at: Optional[str]
    claims: List[RedPacketClaimSummary] = []


@router.get("/redpacket/status/{rid}", response_model=RedPacketStatusOut)
def redpacket_status(rid: str, s: Session = Depends(get_session)):
    rp = s.get(RedPacket, rid)
    if not rp:
        raise HTTPException(status_code=404, detail="red packet not found")
    # Auto-mark expired (best-effort)
    now = datetime.now(timezone.utc)
    exp = rp.expires_at
    if isinstance(exp, str):
        try:
            exp = datetime.fromisoformat(exp)
        except Exception:
            exp = None
    if exp is not None:
        if exp.tzinfo is None:
            exp = exp.replace(tzinfo=timezone.utc)
        if exp < now and rp.status == "active":
            rp.status = "expired"
            s.add(rp)
            s.commit()
    claims = (
        s.execute(
            select(RedPacketClaim)
            .where(RedPacketClaim.redpacket_id == rp.id)
            .order_by(RedPacketClaim.claim_index.asc())
        )
        .scalars()
        .all()
    )
    return RedPacketStatusOut(
        id=rp.id,
        creator_wallet_id=rp.creator_wallet_id,
        group_id=rp.group_id,
        total_amount_cents=rp.total_amount_cents,
        remaining_amount_cents=rp.remaining_amount_cents,
        total_count=rp.total_count,
        claimed_count=rp.claimed_count,
        mode=rp.mode,
        message=rp.message,
        status=rp.status,
        currency=rp.currency,
        expires_at=rp.expires_at.isoformat() if rp.expires_at else None,
        claims=[
            RedPacketClaimSummary(
                wallet_id=c.wallet_id,
                amount_cents=c.amount_cents,
                claim_index=c.claim_index,
                claimed_at=c.claimed_at if isinstance(c.claimed_at, datetime) else None,
            )
            for c in claims
        ],
    )


# (External provider endpoints removed)


# --- Savings (simple wallet-linked savings balance) ---
class SavingsDepositReq(BaseModel):
    wallet_id: str
    amount_cents: int = Field(..., gt=0)


class SavingsWithdrawReq(BaseModel):
    wallet_id: str
    amount_cents: int = Field(..., gt=0)


class SavingsOverviewResp(BaseModel):
    wallet_id: str
    savings_balance_cents: int
    currency: str


def _get_or_create_savings_account(s: Session, wallet: Wallet) -> SavingsAccount:
    sa = s.execute(
        select(SavingsAccount).where(SavingsAccount.wallet_id == wallet.id).with_for_update()
    ).scalars().first()
    if not sa:
        sa = SavingsAccount(
            id=str(uuid.uuid4()),
            wallet_id=wallet.id,
            balance_cents=0,
            currency=wallet.currency,
        )
        s.add(sa)
        s.flush()
    return sa


@router.post("/savings/deposit", response_model=SavingsOverviewResp)
def savings_deposit(req: SavingsDepositReq, s: Session = Depends(get_session)):
    w = s.execute(
        select(Wallet).where(Wallet.id == req.wallet_id).with_for_update()
    ).scalars().first()
    if not w:
        raise HTTPException(status_code=404, detail="wallet not found")
    if req.amount_cents <= 0:
        raise HTTPException(status_code=400, detail="amount_cents must be > 0")
    if w.balance_cents < req.amount_cents:
        raise HTTPException(status_code=400, detail="insufficient funds")
    sa = _get_or_create_savings_account(s, w)
    w.balance_cents -= req.amount_cents
    sa.balance_cents += req.amount_cents
    sa.updated_at = datetime.now(timezone.utc)
    # Ledger: move to savings liability pool
    s.add(
        LedgerEntry(
            id=str(uuid.uuid4()),
            wallet_id=w.id,
            amount_cents=-req.amount_cents,
            txn_id=None,
            description="savings_deposit_debit",
        )
    )
    s.add(
        LedgerEntry(
            id=str(uuid.uuid4()),
            wallet_id=None,
            amount_cents=req.amount_cents,
            txn_id=None,
            description="savings_reserve_credit",
        )
    )
    # Txn record for history (does not affect KYC/velocity; filtered by kind)
    s.add(
        Txn(
            id=str(uuid.uuid4()),
            from_wallet_id=w.id,
            to_wallet_id=w.id,
            amount_cents=req.amount_cents,
            kind="savings_deposit",
            fee_cents=0,
        )
    )
    s.commit()
    s.refresh(sa)
    return SavingsOverviewResp(
        wallet_id=w.id,
        savings_balance_cents=sa.balance_cents,
        currency=sa.currency,
    )


@router.post("/savings/withdraw", response_model=SavingsOverviewResp)
def savings_withdraw(req: SavingsWithdrawReq, s: Session = Depends(get_session)):
    w = s.execute(
        select(Wallet).where(Wallet.id == req.wallet_id).with_for_update()
    ).scalars().first()
    if not w:
        raise HTTPException(status_code=404, detail="wallet not found")
    sa = s.execute(
        select(SavingsAccount).where(SavingsAccount.wallet_id == w.id).with_for_update()
    ).scalars().first()
    if not sa or sa.balance_cents <= 0:
        raise HTTPException(status_code=400, detail="no savings balance")
    if req.amount_cents <= 0:
        raise HTTPException(status_code=400, detail="amount_cents must be > 0")
    if sa.balance_cents < req.amount_cents:
        raise HTTPException(status_code=400, detail="insufficient savings balance")
    sa.balance_cents -= req.amount_cents
    sa.updated_at = datetime.now(timezone.utc)
    w.balance_cents += req.amount_cents
    # Ledger: release from savings pool
    s.add(
        LedgerEntry(
            id=str(uuid.uuid4()),
            wallet_id=None,
            amount_cents=-req.amount_cents,
            txn_id=None,
            description="savings_reserve_debit",
        )
    )
    s.add(
        LedgerEntry(
            id=str(uuid.uuid4()),
            wallet_id=w.id,
            amount_cents=req.amount_cents,
            txn_id=None,
            description="savings_withdraw_credit",
        )
    )
    # Txn record for history (does not affect KYC/velocity; filtered by kind)
    s.add(
        Txn(
            id=str(uuid.uuid4()),
            from_wallet_id=w.id,
            to_wallet_id=w.id,
            amount_cents=req.amount_cents,
            kind="savings_withdraw",
            fee_cents=0,
        )
    )
    s.commit()
    s.refresh(sa)
    return SavingsOverviewResp(
        wallet_id=w.id,
        savings_balance_cents=sa.balance_cents,
        currency=sa.currency,
    )


@router.get("/savings/overview", response_model=SavingsOverviewResp)
def savings_overview(wallet_id: str, s: Session = Depends(get_session)):
    w = s.get(Wallet, wallet_id)
    if not w:
        raise HTTPException(status_code=404, detail="wallet not found")
    sa = s.execute(
        select(SavingsAccount).where(SavingsAccount.wallet_id == w.id)
    ).scalars().first()
    bal = sa.balance_cents if sa else 0
    cur = sa.currency if sa else w.currency
    return SavingsOverviewResp(
        wallet_id=w.id,
        savings_balance_cents=bal,
        currency=cur,
    )


# --- Bill payments (utility-style payments) ---
class BillPayReq(BaseModel):
    from_wallet_id: str
    to_wallet_id: str
    biller_code: str
    amount_cents: int = Field(..., gt=0)
    reference: Optional[str] = None


@router.post("/bills/pay", response_model=WalletResp)
def bills_pay(req: BillPayReq, request: Request, s: Session = Depends(get_session)):
    if req.from_wallet_id == req.to_wallet_id:
        raise HTTPException(status_code=400, detail="Cannot pay bill to same wallet")
    # Lock wallets
    from_w = (
        s.execute(
            select(Wallet).where(Wallet.id == req.from_wallet_id).with_for_update()
        )
        .scalars()
        .first()
    )
    to_w = (
        s.execute(select(Wallet).where(Wallet.id == req.to_wallet_id).with_for_update())
        .scalars()
        .first()
    )
    if not from_w or not to_w:
        raise HTTPException(status_code=404, detail="Wallet not found")
    if req.amount_cents <= 0:
        raise HTTPException(status_code=400, detail="amount_cents must be > 0")
    # Simple KYC per-transaction check (reuse transfer limits)
    u = s.get(User, from_w.user_id)
    level = u.kyc_level if u else 0
    lim = KYC_LIMITS.get(level, KYC_LIMITS[0])
    if req.amount_cents > lim["tx_max"]:
        raise HTTPException(
            status_code=400, detail="Exceeds per-transaction limit for KYC level"
        )
    # Daily total (best-effort)
    today = datetime.now(timezone.utc).date()
    start = datetime.combine(today, datetime.min.time(), tzinfo=timezone.utc)
    end = start + timedelta(days=1)
    total_today = 0
    for row in s.execute(
        select(Txn.amount_cents).where(
            Txn.from_wallet_id == from_w.id,
            Txn.created_at >= start,
            Txn.created_at < end,
            ~Txn.kind.like("savings%"),
        )
    ):
        total_today += int(row[0])
    if total_today + req.amount_cents > lim["daily_max"]:
        raise HTTPException(
            status_code=400, detail="Exceeds daily limit for KYC level"
        )
    if from_w.balance_cents < req.amount_cents:
        raise HTTPException(status_code=400, detail="Insufficient funds")
    # Settle balances
    from_w.balance_cents -= req.amount_cents
    to_w.balance_cents += req.amount_cents
    txn_id = str(uuid.uuid4())
    s.add(
        Txn(
            id=txn_id,
            from_wallet_id=from_w.id,
            to_wallet_id=to_w.id,
            amount_cents=req.amount_cents,
            kind="bill",
            fee_cents=0,
        )
    )
    desc_meta = f"bill:{req.biller_code}"
    if req.reference:
        desc_meta += f" ref={req.reference}"
    s.add(
        LedgerEntry(
            id=str(uuid.uuid4()),
            wallet_id=from_w.id,
            amount_cents=-req.amount_cents,
            txn_id=txn_id,
            description="bill_debit;" + desc_meta,
        )
    )
    s.add(
        LedgerEntry(
            id=str(uuid.uuid4()),
            wallet_id=to_w.id,
            amount_cents=req.amount_cents,
            txn_id=txn_id,
            description="bill_credit;" + desc_meta,
        )
    )
    bp = BillPayment(
        id=str(uuid.uuid4()),
        from_wallet_id=from_w.id,
        to_wallet_id=to_w.id,
        biller_code=req.biller_code,
        reference=(req.reference or None),
        amount_cents=req.amount_cents,
        currency=from_w.currency,
        status="posted",
        txn_id=txn_id,
    )
    s.add(bp)
    s.commit()
    s.refresh(from_w)
    return WalletResp(
        wallet_id=from_w.id,
        balance_cents=from_w.balance_cents,
        currency=from_w.currency,
    )

class TransferReq(BaseModel):
    from_wallet_id: str
    to_wallet_id: Optional[str] = None
    to_alias: Optional[str] = None
    amount_cents: int = Field(..., gt=0)


@router.post("/transfer", response_model=WalletResp)
def transfer(req: TransferReq, request: Request, s: Session = Depends(get_session)):
    if req.from_wallet_id == req.to_wallet_id:
        raise HTTPException(status_code=400, detail="Cannot transfer to same wallet")
    # Idempotency
    ikey = request.headers.get("Idempotency-Key")
    if ikey:
        existed = s.scalar(select(Idempotency).where(Idempotency.ikey == ikey))
        if existed:
            w_id = existed.wallet_id or req.to_wallet_id
            to_w0 = s.get(Wallet, w_id) if w_id else None
            if not to_w0:
                raise HTTPException(status_code=404, detail="Wallet not found")
            bal = existed.balance_cents if existed.balance_cents is not None else to_w0.balance_cents
            cur = existed.currency or to_w0.currency
            return WalletResp(wallet_id=to_w0.id, balance_cents=bal, currency=cur)
    # Resolve alias if provided
    to_wallet_id = req.to_wallet_id
    if not to_wallet_id and req.to_alias:
        handle = req.to_alias.lstrip("@").strip().lower()
        al = s.scalar(select(Alias).where(Alias.handle == handle, Alias.status == "active"))
        if not al:
            raise HTTPException(status_code=404, detail="Alias not found")
        to_wallet_id = al.wallet_id
    if not to_wallet_id:
        raise HTTPException(status_code=400, detail="Missing destination wallet or alias")
    # Lock both rows to avoid race
    from_w = s.execute(select(Wallet).where(Wallet.id == req.from_wallet_id).with_for_update()).scalars().first()
    to_w = s.execute(select(Wallet).where(Wallet.id == to_wallet_id).with_for_update()).scalars().first()
    if not from_w or not to_w:
        raise HTTPException(status_code=404, detail="Wallet not found")
    # KYC checks on sender
    u = s.get(User, from_w.user_id)
    level = u.kyc_level if u else 0
    lim = KYC_LIMITS.get(level, KYC_LIMITS[0])
    if req.amount_cents > lim["tx_max"]:
        raise HTTPException(status_code=400, detail="Exceeds per-transaction limit for KYC level")
    # daily total
    today = datetime.now(timezone.utc).date()
    start = datetime.combine(today, datetime.min.time(), tzinfo=timezone.utc)
    end = start + timedelta(days=1)
    total_today = 0
    for row in s.execute(
        select(Txn.amount_cents).where(
            Txn.from_wallet_id == from_w.id,
            Txn.created_at >= start,
            Txn.created_at < end,
            ~Txn.kind.like("savings%"),
        )
    ):
        total_today += int(row[0])
    if total_today + req.amount_cents > lim["daily_max"]:
        raise HTTPException(status_code=400, detail="Exceeds daily limit for KYC level")

    if from_w.balance_cents < req.amount_cents:
        raise HTTPException(status_code=400, detail="Insufficient funds")
    # Velocity limits (per-minute) for alias payments (sender-side)
    if req.to_alias:
        start_min = datetime.now(timezone.utc) - timedelta(seconds=60)
        cnt = s.execute(
            select(sa_func.count(Txn.id)).where(
                Txn.from_wallet_id == from_w.id,
                Txn.created_at >= start_min,
                ~Txn.kind.like("savings%"),
            )
        ).scalar() or 0
        if int(cnt) >= ALIAS_VELOCITY_MAX_TX:
            raise HTTPException(status_code=429, detail="Too many transfers (alias velocity)")
        sum_min = s.execute(
            select(sa_func.coalesce(sa_func.sum(Txn.amount_cents), 0)).where(
                Txn.from_wallet_id == from_w.id,
                Txn.created_at >= start_min,
                ~Txn.kind.like("savings%"),
            )
        ).scalar() or 0
        if int(sum_min) + req.amount_cents > ALIAS_VELOCITY_MAX_CENTS:
            raise HTTPException(status_code=429, detail="Amount velocity exceeded (alias)")
        # Inbound alias velocity (receiver-side)
        rx_cnt = s.execute(
            select(sa_func.count(Txn.id)).where(
                Txn.to_wallet_id == to_w.id,
                Txn.created_at >= start_min,
                ~Txn.kind.like("savings%"),
            )
        ).scalar() or 0
        if int(rx_cnt) >= ALIAS_RX_VELOCITY_MAX_TX:
            raise HTTPException(status_code=429, detail="Receiver busy (alias inbound velocity)")
        rx_sum = s.execute(
            select(sa_func.coalesce(sa_func.sum(Txn.amount_cents), 0)).where(
                Txn.to_wallet_id == to_w.id,
                Txn.created_at >= start_min,
                ~Txn.kind.like("savings%"),
            )
        ).scalar() or 0
        if int(rx_sum) + req.amount_cents > ALIAS_RX_VELOCITY_MAX_CENTS:
            raise HTTPException(status_code=429, detail="Receiver amount velocity exceeded (alias)")
        # Device/IP heuristic + risk score
        try:
            device_id = request.headers.get("X-Device-ID")
            ip = request.client.host if request.client else None
        except Exception:
            device_id = None; ip = None

        # Denylists (hard block)
        reasons: list[str] = []
        # Config denylists
        if device_id and device_id in RISK_DENY_DEVICE_IDS:
            retry_ms = _risk_backoff_ms(s, "device", device_id)
            raise HTTPException(status_code=429, detail={"error":"device_blocked","retry_after_ms": retry_ms, "score": None, "reasons":["device_denylist"]}, headers={"Retry-After": str(max(1, retry_ms // 1000))})
        if ip and any(_match_cidr_24(ip, pref) for pref in RISK_DENY_IP_PREFIXES):
            retry_ms = _risk_backoff_ms(s, "ip", ip)
            raise HTTPException(status_code=429, detail={"error":"ip_blocked","retry_after_ms": retry_ms, "score": None, "reasons":["ip_denylist"]}, headers={"Retry-After": str(max(1, retry_ms // 1000))})

        # DB denylists
        if device_id:
            if s.scalar(select(RiskDeny).where(RiskDeny.kind=="device", RiskDeny.value==device_id)):
                retry_ms = _risk_backoff_ms(s, "device", device_id)
                raise HTTPException(status_code=429, detail={"error":"device_blocked","retry_after_ms": retry_ms, "score": None, "reasons":["device_denylist_db"]}, headers={"Retry-After": str(max(1, retry_ms // 1000))})
        if ip:
            # brute check any row; for /24 values we use matcher; otherwise exact equal
            for row in s.execute(select(RiskDeny).where(RiskDeny.kind=="ip")).scalars().all():
                if ("/24" in row.value and _match_cidr_24(ip, row.value)) or ("/24" not in row.value and ip == row.value):
                    retry_ms = _risk_backoff_ms(s, "ip", ip)
                    raise HTTPException(status_code=429, detail={"error":"ip_blocked","retry_after_ms": retry_ms, "score": None, "reasons":["ip_denylist_db"]}, headers={"Retry-After": str(max(1, retry_ms // 1000))})

        # record event
        s.add(AliasDeviceEvent(id=str(uuid.uuid4()), handle=(req.to_alias.lstrip("@") if req.to_alias else None), to_wallet_id=to_w.id, device_id=device_id, ip=ip))

        wnd5 = datetime.now(timezone.utc) - timedelta(minutes=5)
        dev_cnt5 = 0
        ip_cnt5 = 0
        if device_id:
            dev_cnt5 = int(s.execute(select(sa_func.count(AliasDeviceEvent.id)).where(AliasDeviceEvent.device_id == device_id, AliasDeviceEvent.created_at >= wnd5)).scalar() or 0)
        if ip:
            ip_cnt5 = int(s.execute(select(sa_func.count(AliasDeviceEvent.id)).where(AliasDeviceEvent.ip == ip, AliasDeviceEvent.created_at >= wnd5)).scalar() or 0)

        # per-minute device velocity (hard cap)
        dev_cnt1 = 0
        if device_id:
            dev_cnt1 = int(s.execute(select(sa_func.count(AliasDeviceEvent.id)).where(AliasDeviceEvent.to_wallet_id == to_w.id, AliasDeviceEvent.device_id == device_id, AliasDeviceEvent.created_at >= start_min)).scalar() or 0)
            if dev_cnt1 > ALIAS_DEVICE_MAX_TX_PER_MIN:
                retry_ms = _risk_backoff_ms(s, "device", device_id)
                raise HTTPException(status_code=429, detail={"error":"device_velocity","retry_after_ms": retry_ms, "score": None, "reasons":["device_per_min_cap"]}, headers={"Retry-After": str(max(1, retry_ms // 1000))})

        # risk score (5-min window)
        score = 0
        if not device_id:
            score += 1
        if not ip:
            score += 1
        # UA parsing (basic)
        try:
            ua = request.headers.get("User-Agent", "")
        except Exception:
            ua = ""
        if not ua:
            score += 1; reasons.append("ua_missing")
        else:
            final_ua = ua.lower()
            if any(b in final_ua for b in ["curl","python-requests","bot","crawler"]):
                score += 2; reasons.append("ua_suspect")

        score += dev_cnt5 // 3
        score += ip_cnt5 // 10

        if score >= RISK_SCORE_THRESHOLD:
            retry_ms = _risk_backoff_ms(s, "device", device_id) if device_id else _risk_backoff_ms(s, "ip", ip)
            raise HTTPException(status_code=429, detail={"error":"risk_score","retry_after_ms": retry_ms, "score": score, "reasons": reasons}, headers={"Retry-After": str(max(1, retry_ms // 1000))})
    # fees
    fee_cents = (req.amount_cents * MERCHANT_FEE_BPS) // 10_000 if MERCHANT_FEE_BPS > 0 else 0
    net = req.amount_cents - fee_cents
    if net < 0:
        raise HTTPException(status_code=400, detail="Amount too small for fees")
    # settle (balances)
    from_w.balance_cents -= req.amount_cents
    to_w.balance_cents += net
    # fee wallet
    fee_w = None
    if FEE_WALLET_PHONE and fee_cents > 0:
        fu = s.scalar(select(User).where(User.phone == FEE_WALLET_PHONE))
        fee_w = s.scalar(select(Wallet).where(Wallet.user_id == fu.id)) if fu else None
        if fee_w:
            fee_w.balance_cents += fee_cents
    txn_id = str(uuid.uuid4())
    s.add(Txn(id=txn_id, from_wallet_id=from_w.id, to_wallet_id=to_w.id, amount_cents=req.amount_cents, kind="transfer", fee_cents=fee_cents))
    # ledger dual-write
    merch = request.headers.get("X-Merchant")
    ref = request.headers.get("X-Ref")
    meta = []
    if merch:
        meta.append(f"m={merch}")
    if ref:
        meta.append(f"ref={ref}")
    meta_str = (" "+" ".join(meta)) if meta else ""
    s.add(LedgerEntry(id=str(uuid.uuid4()), wallet_id=from_w.id, amount_cents=-req.amount_cents, txn_id=txn_id, description=("transfer_debit"+meta_str)))
    s.add(LedgerEntry(id=str(uuid.uuid4()), wallet_id=to_w.id, amount_cents=+net, txn_id=txn_id, description=("transfer_credit"+meta_str)))
    if fee_w and fee_cents > 0:
        s.add(LedgerEntry(id=str(uuid.uuid4()), wallet_id=fee_w.id, amount_cents=+fee_cents, txn_id=txn_id, description="fee_credit"))
    if ikey:
        s.add(Idempotency(id=str(uuid.uuid4()), ikey=ikey, endpoint="transfer", txn_id=txn_id, amount_cents=req.amount_cents, currency=from_w.currency, wallet_id=to_w.id, balance_cents=to_w.balance_cents))
    s.commit()
    s.refresh(to_w)
    return WalletResp(wallet_id=to_w.id, balance_cents=to_w.balance_cents, currency=to_w.currency)


@router.get("/wallets/{wallet_id}", response_model=WalletResp)
def get_wallet(wallet_id: str, s: Session = Depends(get_session)):
    w = s.get(Wallet, wallet_id)
    if not w:
        raise HTTPException(status_code=404, detail="Wallet not found")
    return WalletResp(wallet_id=w.id, balance_cents=w.balance_cents, currency=w.currency)


class TxnItem(BaseModel):
    id: str
    from_wallet_id: Optional[str]
    to_wallet_id: str
    amount_cents: int
    fee_cents: int
    kind: str
    created_at: Optional[datetime]
    meta: Optional[str] = None


@router.get("/txns", response_model=List[TxnItem])
def list_txns(wallet_id: str, limit: int = 50, s: Session = Depends(get_session)):
    if limit < 1 or limit > 200:
        limit = 50
    rows = s.execute(
        select(Txn).where(
            (Txn.from_wallet_id == wallet_id) | (Txn.to_wallet_id == wallet_id)
        ).order_by(Txn.created_at.desc()).limit(limit)
    ).scalars().all()
    meta_map: Dict[str, str] = {}
    if rows:
        ids = [t.id for t in rows]
        le_rows = s.execute(
            select(LedgerEntry.txn_id, LedgerEntry.description).where(
                LedgerEntry.txn_id.in_(ids)
            )
        ).all()
        for tid, desc in le_rows:
            if not tid:
                continue
            if tid in meta_map:
                continue
            if desc:
                meta_map[str(tid)] = str(desc)
    return [
        TxnItem(
            id=t.id,
            from_wallet_id=t.from_wallet_id,
            to_wallet_id=t.to_wallet_id,
            amount_cents=t.amount_cents,
            fee_cents=t.fee_cents or 0,
            kind=t.kind,
            created_at=t.created_at,
            meta=meta_map.get(t.id),
        )
        for t in rows
    ]


class FeesSummary(BaseModel):
    total_fee_cents: int
    from_ts: Optional[str] = None
    to_ts: Optional[str] = None


@router.get("/admin/fees/summary", response_model=FeesSummary)
def fees_summary(from_iso: Optional[str] = None, to_iso: Optional[str] = None, s: Session = Depends(get_session), admin_ok: bool = Depends(require_admin)):
    start = None
    end = None
    if from_iso:
        try:
            start = datetime.fromisoformat(from_iso.replace("Z", "+00:00"))
        except Exception:
            raise HTTPException(status_code=400, detail="Invalid from_iso")
    if to_iso:
        try:
            end = datetime.fromisoformat(to_iso.replace("Z", "+00:00"))
        except Exception:
            raise HTTPException(status_code=400, detail="Invalid to_iso")
    conds = []
    if start:
        conds.append(Txn.created_at >= start)
    if end:
        conds.append(Txn.created_at <= end)
    q = select(sa_func.coalesce(sa_func.sum(Txn.fee_cents), 0))
    if conds:
        from sqlalchemy import and_  # local import to keep top tidy
        q = q.where(and_(*conds))
    total = s.execute(q).scalar() or 0
    return FeesSummary(total_fee_cents=int(total), from_ts=(start.isoformat() if start else None), to_ts=(end.isoformat() if end else None))


class RedPacketCampaignPaymentsStats(BaseModel):
    campaign_id: str
    total_packets_issued: int
    total_packets_claimed: int
    total_amount_cents: int
    claimed_amount_cents: int
    unique_creators: int
    unique_claimants: int
    from_ts: Optional[str] = None
    to_ts: Optional[str] = None


@router.get(
    "/admin/redpacket_campaigns/payments_analytics",
    response_model=RedPacketCampaignPaymentsStats,
)
def redpacket_campaign_payments_analytics(
    campaign_id: str,
    from_iso: Optional[str] = None,
    to_iso: Optional[str] = None,
    s: Session = Depends(get_session),
    admin_ok: bool = Depends(require_admin),
):
    """
    Aggregate Red‑Packet payments KPIs for a single campaign.

    A campaign is identified via RedPacket.group_id, matching either
    the plain campaign_id or 'campaign:<campaign_id>' for flexibility.
    """
    cid = (campaign_id or "").strip()
    if not cid:
        raise HTTPException(status_code=400, detail="campaign_id required")
    start = None
    end = None
    if from_iso:
        try:
            start = datetime.fromisoformat(from_iso.replace("Z", "+00:00"))
        except Exception:
            raise HTTPException(status_code=400, detail="Invalid from_iso")
    if to_iso:
        try:
            end = datetime.fromisoformat(to_iso.replace("Z", "+00:00"))
        except Exception:
            raise HTTPException(status_code=400, detail="Invalid to_iso")
    from sqlalchemy import and_, or_  # type: ignore

    conds = [
        or_(RedPacket.group_id == cid, RedPacket.group_id == f"campaign:{cid}")
    ]
    if start:
        conds.append(RedPacket.created_at >= start)
    if end:
        conds.append(RedPacket.created_at <= end)
    q = select(RedPacket).where(and_(*conds))
    packets = s.execute(q).scalars().all()
    total_packets_issued = len(packets)
    total_amount_cents = 0
    creators = set()
    for p in packets:
        try:
            total_amount_cents += int(p.total_amount_cents or 0)
        except Exception:
            pass
        if getattr(p, "creator_wallet_id", None):
            creators.add(p.creator_wallet_id)
    unique_creators = len(creators)

    total_packets_claimed = 0
    claimed_amount_cents = 0
    unique_claimants = 0
    if packets:
        rp_ids = [p.id for p in packets]
        cq = select(RedPacketClaim).where(RedPacketClaim.redpacket_id.in_(rp_ids))
        if start:
            cq = cq.where(RedPacketClaim.claimed_at >= start)
        if end:
            cq = cq.where(RedPacketClaim.claimed_at <= end)
        claims = s.execute(cq).scalars().all()
        total_packets_claimed = len(claims)
        claimants = set()
        for c in claims:
            try:
                claimed_amount_cents += int(c.amount_cents or 0)
            except Exception:
                pass
            if getattr(c, "wallet_id", None):
                claimants.add(c.wallet_id)
        unique_claimants = len(claimants)

    return RedPacketCampaignPaymentsStats(
        campaign_id=cid,
        total_packets_issued=int(total_packets_issued),
        total_packets_claimed=int(total_packets_claimed),
        total_amount_cents=int(total_amount_cents),
        claimed_amount_cents=int(claimed_amount_cents),
        unique_creators=int(unique_creators),
        unique_claimants=int(unique_claimants),
        from_ts=start.isoformat() if start else None,
        to_ts=end.isoformat() if end else None,
    )


class MerchantQRReq(BaseModel):
    wallet_id: Optional[str] = None
    phone: Optional[str] = None
    amount_cents: Optional[int] = None


@router.post("/merchant/qr")
def merchant_qr(req: MerchantQRReq, s: Session = Depends(get_session), admin_ok: bool = Depends(require_admin)):
    wid = req.wallet_id
    if not wid:
        if not req.phone:
            raise HTTPException(status_code=400, detail="wallet_id or phone required")
        u = s.scalar(select(User).where(User.phone == req.phone))
        if not u:
            raise HTTPException(status_code=404, detail="User not found")
        w = s.scalar(select(Wallet).where(Wallet.user_id == u.id))
        if not w:
            raise HTTPException(status_code=404, detail="Wallet not found")
        wid = w.id
    amt = req.amount_cents if req.amount_cents and req.amount_cents > 0 else None
    # Simple QR payload (string) – can be rendered client-side
    payload = f"PAY|wallet={wid}" + (f"|amount={amt}" if amt else "")
    return {"qr": payload}


class KycReq(BaseModel):
    level: int = Field(..., ge=0, le=2)


@router.post("/admin/users/{user_id}/kyc")
def set_kyc(user_id: str, req: KycReq, s: Session = Depends(get_session), admin_ok: bool = Depends(require_admin)):
    u = s.get(User, user_id)
    if not u:
        raise HTTPException(status_code=404, detail="User not found")
    u.kyc_level = req.level
    s.commit()
    return {"user_id": u.id, "kyc_level": u.kyc_level}

# --- Admin utilities ---
class AdminTxnItem(BaseModel):
    id: str
    from_wallet_id: Optional[str]
    to_wallet_id: str
    amount_cents: int
    fee_cents: int
    kind: str
    created_at: Optional[datetime]


@router.get("/admin/txns", response_model=List[AdminTxnItem])
def admin_list_txns(
    wallet_id: Optional[str] = None,
    from_iso: Optional[str] = None,
    to_iso: Optional[str] = None,
    limit: int = 50,
    offset: int = 0,
    s: Session = Depends(get_session),
    admin_ok: bool = Depends(require_admin),
):
    q = select(Txn)
    conds = []
    if wallet_id:
        conds.append((Txn.from_wallet_id == wallet_id) | (Txn.to_wallet_id == wallet_id))
    if from_iso:
        try:
            start = datetime.fromisoformat(from_iso.replace("Z", "+00:00"))
            conds.append(Txn.created_at >= start)
        except Exception:
            raise HTTPException(status_code=400, detail="Invalid from_iso")
    if to_iso:
        try:
            end = datetime.fromisoformat(to_iso.replace("Z", "+00:00"))
            conds.append(Txn.created_at <= end)
        except Exception:
            raise HTTPException(status_code=400, detail="Invalid to_iso")
    if conds:
        from sqlalchemy import and_  # type: ignore
        q = q.where(and_(*conds))
    if limit < 1 or limit > 500:
        limit = 50
    q = q.order_by(Txn.created_at.desc()).limit(limit).offset(max(offset, 0))
    rows = s.execute(q).scalars().all()
    return [
        AdminTxnItem(
            id=t.id,
            from_wallet_id=t.from_wallet_id,
            to_wallet_id=t.to_wallet_id,
            amount_cents=t.amount_cents,
            fee_cents=t.fee_cents or 0,
            kind=t.kind,
            created_at=t.created_at,
        )
        for t in rows
    ]


class AdminWallet(BaseModel):
    wallet_id: str
    phone: str
    balance_cents: int
    currency: str


@router.get("/admin/wallets/search", response_model=List[AdminWallet])
def admin_wallets_search(
    phone: Optional[str] = None,
    wallet_id: Optional[str] = None,
    limit: int = 50,
    s: Session = Depends(get_session),
    admin_ok: bool = Depends(require_admin),
):
    if limit < 1 or limit > 200:
        limit = 50
    q = select(User, Wallet).where(Wallet.user_id == User.id)
    if wallet_id:
        q = q.where(Wallet.id == wallet_id)
    if phone:
        try:
            q = q.where(User.phone.ilike(f"%{phone}%"))
        except Exception:
            q = q.where(User.phone.like(f"%{phone}%"))
    q = q.limit(limit)
    rows = s.execute(q).all()
    out: List[AdminWallet] = []
    for u, w in rows:
        out.append(AdminWallet(wallet_id=w.id, phone=u.phone, balance_cents=w.balance_cents, currency=w.currency))
    return out


# Public resolve: phone -> wallet
class ResolvePhoneOut(BaseModel):
    user_id: str
    wallet_id: str
    phone: str


@router.get("/resolve/phone/{phone}", response_model=ResolvePhoneOut)
def resolve_phone(phone: str, s: Session = Depends(get_session)):
    u = s.scalar(select(User).where(User.phone == phone))
    if not u:
        raise HTTPException(status_code=404, detail="phone not found")
    w = s.scalar(select(Wallet).where(Wallet.user_id == u.id))
    if not w:
        raise HTTPException(status_code=404, detail="wallet not found for phone")
    return ResolvePhoneOut(user_id=u.id, wallet_id=w.id, phone=u.phone)


@router.get("/admin/txns/export")
def admin_txns_export(
    wallet_id: Optional[str] = None,
    from_iso: Optional[str] = None,
    to_iso: Optional[str] = None,
    limit: int = 1000,
    offset: int = 0,
    s: Session = Depends(get_session),
    admin_ok: bool = Depends(require_admin),
):
    q = select(Txn)
    conds = []
    if wallet_id:
        conds.append((Txn.from_wallet_id == wallet_id) | (Txn.to_wallet_id == wallet_id))
    if from_iso:
        try:
            start = datetime.fromisoformat(from_iso.replace("Z", "+00:00"))
            conds.append(Txn.created_at >= start)
        except Exception:
            raise HTTPException(status_code=400, detail="Invalid from_iso")
    if to_iso:
        try:
            end = datetime.fromisoformat(to_iso.replace("Z", "+00:00"))
            conds.append(Txn.created_at <= end)
        except Exception:
            raise HTTPException(status_code=400, detail="Invalid to_iso")
    if conds:
        from sqlalchemy import and_  # type: ignore
        q = q.where(and_(*conds))
    if limit < 1 or limit > 5000:
        limit = 1000
    q = q.order_by(Txn.created_at.desc()).limit(limit).offset(max(offset, 0))
    rows = s.execute(q).scalars().all()
    # Streaming CSV
    import io, csv, datetime as _dt
    def _iter():
        buf = io.StringIO()
        writer = csv.writer(buf)
        writer.writerow(["id", "from_wallet_id", "to_wallet_id", "amount_cents", "fee_cents", "kind", "created_at"])
        yield buf.getvalue(); buf.seek(0); buf.truncate(0)
        for t in rows:
            writer.writerow([t.id, t.from_wallet_id or "", t.to_wallet_id, t.amount_cents, t.fee_cents or 0, t.kind, (t.created_at.isoformat() if t.created_at else "")])
            yield buf.getvalue(); buf.seek(0); buf.truncate(0)
    filename = f"txns_{_dt.datetime.utcnow().strftime('%Y%m%d_%H%M%S')} .csv".replace(' ', '')
    headers = {"Content-Disposition": f"attachment; filename=\"{filename}\""}
    return StreamingResponse(_iter(), media_type="text/csv", headers=headers)


@router.get("/admin/txns/export_by_merchant")
def admin_txns_export_by_merchant(
    merchant: str,
    campaign_id: Optional[str] = None,
    from_iso: Optional[str] = None,
    to_iso: Optional[str] = None,
    limit: int = 1000,
    offset: int = 0,
    s: Session = Depends(get_session),
    admin_ok: bool = Depends(require_admin),
):
    # Export transactions whose ledger entries contain merchant tag m=<merchant>
    mtag = f"m={merchant.strip().lower()}"
    from sqlalchemy import and_  # type: ignore
    q = (
        select(Txn)
        .join(LedgerEntry, LedgerEntry.txn_id == Txn.id)
        .where(sa_func.lower(LedgerEntry.description).like(f"%{mtag}%"))
    )
    # Optional Kampagnen-Filter: group=campaign:<id> oder group=<id>
    cid = (campaign_id or "").strip()
    if cid:
        ctag1 = f"group=campaign:{cid.lower()}"
        ctag2 = f"group={cid.lower()}"
        q = q.where(
            sa_func.lower(LedgerEntry.description).like(f"%{ctag1}%")
            | sa_func.lower(LedgerEntry.description).like(f"%{ctag2}%")
        )
    if from_iso:
        try:
            start = datetime.fromisoformat(from_iso.replace("Z", "+00:00"))
            q = q.where(Txn.created_at >= start)
        except Exception:
            raise HTTPException(status_code=400, detail="Invalid from_iso")
    if to_iso:
        try:
            end = datetime.fromisoformat(to_iso.replace("Z", "+00:00"))
            q = q.where(Txn.created_at <= end)
        except Exception:
            raise HTTPException(status_code=400, detail="Invalid to_iso")
    if limit < 1 or limit > 5000:
        limit = 1000
    q = q.order_by(Txn.created_at.desc()).limit(limit).offset(max(offset, 0))
    rows = s.execute(q).scalars().all()
    # For each txn, fetch the first matching ledger meta string (optional)
    meta_map = {}
    for t in rows:
        le_q = select(LedgerEntry).where(
            LedgerEntry.txn_id == t.id,
            sa_func.lower(LedgerEntry.description).like(f"%{mtag}%"),
        )
        if cid:
            ctag1 = f"group=campaign:{cid.lower()}"
            ctag2 = f"group={cid.lower()}"
            le_q = le_q.where(
                sa_func.lower(LedgerEntry.description).like(f"%{ctag1}%")
                | sa_func.lower(LedgerEntry.description).like(f"%{ctag2}%")
            )
        le = s.execute(le_q.limit(1)).scalars().first()
        meta_map[t.id] = le.description if le and le.description else ""
    import io, csv, datetime as _dt
    def _iter():
        buf = io.StringIO(); w = csv.writer(buf)
        w.writerow(["id", "from_wallet_id", "to_wallet_id", "amount_cents", "fee_cents", "kind", "created_at", "meta"])
        yield buf.getvalue(); buf.seek(0); buf.truncate(0)
        for t in rows:
            w.writerow([t.id, t.from_wallet_id or "", t.to_wallet_id, t.amount_cents, t.fee_cents or 0, t.kind, (t.created_at.isoformat() if t.created_at else ""), meta_map.get(t.id, "")])
            yield buf.getvalue(); buf.seek(0); buf.truncate(0)
    filename = f"txns_{merchant}_{_dt.datetime.utcnow().strftime('%Y%m%d_%H%M%S')} .csv".replace(' ', '')
    headers = {"Content-Disposition": f"attachment; filename=\"{filename}\""}
    return StreamingResponse(_iter(), media_type="text/csv", headers=headers)


@router.get("/admin/wallets/export")
def admin_wallets_export(
    s: Session = Depends(get_session),
    admin_ok: bool = Depends(require_admin),
):
    # Export wallets with associated phone and balances
    q = select(User, Wallet).where(Wallet.user_id == User.id)
    rows = s.execute(q).all()
    import io, csv, datetime as _dt
    def _iter():
        buf = io.StringIO(); writer = csv.writer(buf)
        writer.writerow(["wallet_id", "phone", "balance_cents", "currency"])
        yield buf.getvalue(); buf.seek(0); buf.truncate(0)
        for u, w in rows:
            writer.writerow([w.id, u.phone, w.balance_cents, w.currency])
            yield buf.getvalue(); buf.seek(0); buf.truncate(0)
    filename = f"wallets_{_dt.datetime.utcnow().strftime('%Y%m%d_%H%M%S')} .csv".replace(' ', '')
    headers = {"Content-Disposition": f"attachment; filename=\"{filename}\""}
    return StreamingResponse(_iter(), media_type="text/csv", headers=headers)


@router.get("/admin/txns/count")
def admin_txns_count(
    wallet_id: Optional[str] = None,
    from_iso: Optional[str] = None,
    to_iso: Optional[str] = None,
    s: Session = Depends(get_session),
    admin_ok: bool = Depends(require_admin),
):
    q = select(sa_func.count(Txn.id))
    conds = []
    if wallet_id:
        conds.append((Txn.from_wallet_id == wallet_id) | (Txn.to_wallet_id == wallet_id))
    if from_iso:
        try:
            start = datetime.fromisoformat(from_iso.replace("Z", "+00:00"))
            conds.append(Txn.created_at >= start)
        except Exception:
            raise HTTPException(status_code=400, detail="Invalid from_iso")
    if to_iso:
        try:
            end = datetime.fromisoformat(to_iso.replace("Z", "+00:00"))
            conds.append(Txn.created_at <= end)
        except Exception:
            raise HTTPException(status_code=400, detail="Invalid to_iso")
    if conds:
        from sqlalchemy import and_  # type: ignore
        q = q.where(and_(*conds))
    total = s.execute(q).scalar() or 0
    return {"count": int(total)}


@router.get("/admin/ledger/reconcile/all")
def admin_ledger_reconcile_all(
    only_nonzero: bool = False,
    limit: int = 1000,
    s: Session = Depends(get_session),
    admin_ok: bool = Depends(require_admin),
):
    # Build reconciliation for all wallets (limited)
    if limit < 1 or limit > 5000:
        limit = 1000
    pairs = s.execute(select(User, Wallet).where(Wallet.user_id == User.id).limit(limit)).all()
    # Precompute ledger sums
    results = []
    for u, w in pairs:
        total = s.execute(select(sa_func.coalesce(sa_func.sum(LedgerEntry.amount_cents), 0)).where(LedgerEntry.wallet_id == w.id)).scalar() or 0
        delta = int(total) - int(w.balance_cents)
        if only_nonzero and delta == 0:
            continue
        results.append({
            "wallet_id": w.id,
            "phone": u.phone,
            "ledger_sum_cents": int(total),
            "balance_cents": int(w.balance_cents),
            "delta_cents": delta,
        })
    return results


@router.post("/admin/ledger/seed")
def admin_ledger_seed(
    dry_run: bool = True,
    limit: int = 1000,
    s: Session = Depends(get_session),
    admin_ok: bool = Depends(require_admin),
):
    # Seed ledger entries for wallets that have no ledger sum (sum==0) but positive/nonzero balance
    if limit < 1 or limit > 10000:
        limit = 1000
    pairs = s.execute(select(User, Wallet).where(Wallet.user_id == User.id).limit(limit)).all()
    to_seed = []
    for u, w in pairs:
        total = s.execute(select(sa_func.coalesce(sa_func.sum(LedgerEntry.amount_cents), 0)).where(LedgerEntry.wallet_id == w.id)).scalar() or 0
        if total == 0 and w.balance_cents != 0:
            to_seed.append({"wallet_id": w.id, "amount_cents": int(w.balance_cents), "phone": u.phone})
    if dry_run:
        return {"dry_run": True, "will_seed": to_seed, "count": len(to_seed)}
    for item in to_seed:
        s.add(LedgerEntry(id=str(uuid.uuid4()), wallet_id=item["wallet_id"], amount_cents=item["amount_cents"], txn_id=None, description="seed_balance"))
    if to_seed:
        s.commit()
    return {"dry_run": False, "seeded": len(to_seed)}


@router.get("/admin/ledger/reconcile/{wallet_id}")
def admin_ledger_reconcile(wallet_id: str, s: Session = Depends(get_session), admin_ok: bool = Depends(require_admin)):
    # Sum ledger entries for this wallet and compare with wallet.balance_cents
    w = s.get(Wallet, wallet_id)
    if not w:
        raise HTTPException(status_code=404, detail="Wallet not found")
    total = s.execute(select(sa_func.coalesce(sa_func.sum(LedgerEntry.amount_cents), 0)).where(LedgerEntry.wallet_id == wallet_id)).scalar() or 0
    return {
        "wallet_id": wallet_id,
        "ledger_sum_cents": int(total),
        "balance_cents": int(w.balance_cents),
        "delta_cents": int(total) - int(w.balance_cents),
    }


@router.get("/idempotency/{ikey}")
def idempotency_status(ikey: str, s: Session = Depends(get_session)):
    rec = s.scalar(select(Idempotency).where(Idempotency.ikey == ikey))
    if not rec:
        return {"exists": False}
    return {"exists": True, "txn_id": rec.txn_id, "endpoint": rec.endpoint, "created_at": rec.created_at}


# --- Alias Registry ---
class AliasRequest(BaseModel):
    handle: str
    user_id: Optional[str] = None
    wallet_id: Optional[str] = None


class AliasVerifyReq(BaseModel):
    handle: str
    code: str


class AliasResolve(BaseModel):
    handle: str
    wallet_id: str
    user_id: str
    status: str


def _normalize_handle(h: str) -> str:
    base = h.strip().lstrip("@").lower()
    if not re.fullmatch(r"[a-z][a-z0-9_\.]{1,19}", base):
        raise HTTPException(status_code=400, detail="Invalid handle format")
    if base in RESERVED_ALIASES:
        raise HTTPException(status_code=400, detail="Handle is reserved")
    return base


def _alias_code_hash(code: str) -> str:
    return _hmac.new(ALIAS_CODE_PEPPER.encode(), code.encode(), _hashlib.sha256).hexdigest()


def _ipv4_to_tuple(ip: str) -> Optional[tuple[int,int,int,int]]:
    try:
        parts = ip.split('.')
        if len(parts) != 4:
            return None
        return tuple(int(p) for p in parts)  # type: ignore
    except Exception:
        return None


def _match_cidr_24(ip: Optional[str], cidr: str) -> bool:
    # cidr format: a.b.c.0/24
    if not ip:
        return False
    if "/24" not in cidr:
        # fallback simple prefix match
        return ip.startswith(cidr)
    net, _ = cidr.split('/24', 1)
    ipt = _ipv4_to_tuple(ip)
    nett = _ipv4_to_tuple(net.rstrip('.0'))
    if not ipt or not nett:
        return False
    return ipt[0] == nett[0] and ipt[1] == nett[1] and ipt[2] == nett[2]


def _risk_backoff_ms(s: Session, key_type: str, key_value: Optional[str]) -> int:
    if not key_value:
        return RISK_RETRY_BASE_MS
    rec = s.execute(select(RiskBackoff).where(RiskBackoff.key_type == key_type, RiskBackoff.key_value == key_value).with_for_update()).scalars().first()
    now = datetime.now(timezone.utc)
    if not rec:
        rec = RiskBackoff(id=str(uuid.uuid4()), key_type=key_type, key_value=key_value, strikes=1, last_strike=now)
        s.add(rec)
        s.commit()
        return RISK_RETRY_BASE_MS
    # decay after 10 minutes
    if rec.last_strike and (now - rec.last_strike) > timedelta(minutes=10):
        rec.strikes = 1
    else:
        rec.strikes = (rec.strikes or 0) + 1
    rec.last_strike = now
    s.commit()
    return RISK_RETRY_BASE_MS * (2 ** max(0, rec.strikes - 1))


@router.post("/alias/request")
def alias_request(req: AliasRequest, s: Session = Depends(get_session)):
    handle = _normalize_handle(req.handle)
    # Resolve user/wallet
    if not req.user_id and not req.wallet_id:
        raise HTTPException(status_code=400, detail="user_id or wallet_id required")
    if req.user_id:
        u = s.get(User, req.user_id)
        if not u:
            raise HTTPException(status_code=404, detail="User not found")
        w = s.scalar(select(Wallet).where(Wallet.user_id == u.id))
        if not w:
            raise HTTPException(status_code=404, detail="Wallet not found")
    else:
        w = s.get(Wallet, req.wallet_id)
        if not w:
            raise HTTPException(status_code=404, detail="Wallet not found")
        u = s.get(User, w.user_id)
    # Collision check
    existing = s.scalar(select(Alias).where(Alias.handle == handle))
    if existing and existing.user_id != u.id:
        raise HTTPException(status_code=409, detail="Handle already taken")
    # Only one active alias per user (simple rule)
    active = s.scalar(select(Alias).where(Alias.user_id == u.id, Alias.status == "active"))
    if active and active.handle != handle:
        raise HTTPException(status_code=409, detail="User already has an alias")
    code = f"{_secrets.randbelow(1_000_000):06d}"
    h = _alias_code_hash(code)
    expires = datetime.now(timezone.utc) + timedelta(seconds=ALIAS_CODE_TTL_SECS)
    if existing:
        existing.display = req.handle.strip()
        existing.wallet_id = w.id
        existing.user_id = u.id
        existing.status = "pending"
        existing.code_hash = h
        existing.code_expires_at = expires
    else:
        s.add(Alias(id=str(uuid.uuid4()), handle=handle, display=req.handle.strip(), user_id=u.id, wallet_id=w.id, status="pending", code_hash=h, code_expires_at=expires))
    s.commit()
    # For now, return code in response (SMS/Push to be integrated)
    return {"ok": True, "handle": f"@{handle}", "code": code, "expires_at": expires.isoformat()}


@router.post("/alias/verify")
def alias_verify(req: AliasVerifyReq, s: Session = Depends(get_session)):
    handle = _normalize_handle(req.handle)
    al = s.scalar(select(Alias).where(Alias.handle == handle))
    if not al:
        raise HTTPException(status_code=404, detail="Handle not found")
    if not al.code_expires_at or al.code_expires_at < datetime.now(timezone.utc):
        raise HTTPException(status_code=400, detail="Code expired")
    if _alias_code_hash(req.code) != (al.code_hash or ""):
        raise HTTPException(status_code=400, detail="Invalid code")
    al.status = "active"
    al.code_hash = None
    al.code_expires_at = None
    s.commit()
    return {"ok": True, "handle": f"@{handle}", "wallet_id": al.wallet_id, "user_id": al.user_id}


@router.get("/alias/resolve/{handle}", response_model=AliasResolve)
def alias_resolve(handle: str, s: Session = Depends(get_session)):
    h = _normalize_handle(handle)
    al = s.scalar(select(Alias).where(Alias.handle == h))
    if not al or al.status != "active":
        raise HTTPException(status_code=404, detail="Alias not found")
    return AliasResolve(handle=f"@{h}", wallet_id=al.wallet_id, user_id=al.user_id, status=al.status)


# --- Admin: Alias moderation ---
class AliasBlockReq(BaseModel):
    handle: str
    reason: Optional[str] = None


class AliasRenameReq(BaseModel):
    from_handle: str
    to_handle: str


@router.post("/admin/alias/block")
def admin_alias_block(req: AliasBlockReq, s: Session = Depends(get_session), admin_ok: bool = Depends(require_admin)):
    h = _normalize_handle(req.handle)
    al = s.scalar(select(Alias).where(Alias.handle == h))
    if not al:
        raise HTTPException(status_code=404, detail="Handle not found")
    al.status = "blocked"
    s.commit()
    return {"ok": True, "handle": f"@{h}", "status": al.status}


@router.post("/admin/alias/rename")
def admin_alias_rename(req: AliasRenameReq, s: Session = Depends(get_session), admin_ok: bool = Depends(require_admin)):
    src = _normalize_handle(req.from_handle)
    dst = _normalize_handle(req.to_handle)
    if src == dst:
        raise HTTPException(status_code=400, detail="Handles identical")
    a_src = s.scalar(select(Alias).where(Alias.handle == src))
    if not a_src:
        raise HTTPException(status_code=404, detail="Source not found")
    a_dst = s.scalar(select(Alias).where(Alias.handle == dst))
    if a_dst:
        raise HTTPException(status_code=409, detail="Destination taken")
    # rename (keep same user/wallet), reset to pending for fresh verification (optional); here we keep active
    a_src.handle = dst
    a_src.display = req.to_handle.strip()
    s.commit()
    return {"ok": True, "from": f"@{src}", "to": f"@{dst}"}


@router.get("/admin/alias/search")
def admin_alias_search(handle: Optional[str] = None, status: Optional[str] = None, user_id: Optional[str] = None, limit: int = 50, s: Session = Depends(get_session), admin_ok: bool = Depends(require_admin)):
    q = select(Alias)
    if handle:
        h = _normalize_handle(handle)
        q = q.where(Alias.handle.like(f"%{h}%"))
    if status:
        q = q.where(Alias.status == status)
    if user_id:
        q = q.where(Alias.user_id == user_id)
    rows = s.execute(q.limit(max(1, min(limit, 200)))).scalars().all()
    return [{"handle": f"@{a.handle}", "display": a.display, "user_id": a.user_id, "wallet_id": a.wallet_id, "status": a.status, "created_at": a.created_at} for a in rows]


# --- Admin: Risk denylist endpoints ---
class RiskDenyReq(BaseModel):
    kind: str  # ip|device
    value: str
    note: Optional[str] = None


@router.post("/admin/risk/deny/add")
def admin_risk_deny_add(req: RiskDenyReq, s: Session = Depends(get_session), admin_ok: bool = Depends(require_admin)):
    k = req.kind.strip().lower()
    if k not in ("ip", "device"):
        raise HTTPException(status_code=400, detail="invalid kind")
    existed = s.scalar(select(RiskDeny).where(RiskDeny.kind==k, RiskDeny.value==req.value.strip()))
    if existed:
        return {"ok": True, "exists": True}
    s.add(RiskDeny(id=str(uuid.uuid4()), kind=k, value=req.value.strip(), note=(req.note or None)))
    s.commit()
    return {"ok": True}


@router.post("/admin/risk/deny/remove")
def admin_risk_deny_remove(req: RiskDenyReq, s: Session = Depends(get_session), admin_ok: bool = Depends(require_admin)):
    k = req.kind.strip().lower()
    row = s.scalar(select(RiskDeny).where(RiskDeny.kind==k, RiskDeny.value==req.value.strip()))
    if not row:
        return {"ok": True, "removed": 0}
    s.delete(row)
    s.commit()
    return {"ok": True, "removed": 1}


@router.get("/admin/risk/deny/list")
def admin_risk_deny_list(kind: Optional[str] = None, limit: int = 200, s: Session = Depends(get_session), admin_ok: bool = Depends(require_admin)):
    q = select(RiskDeny)
    if kind:
        q = q.where(RiskDeny.kind==kind)
    rows = s.execute(q.limit(max(1, min(limit, 500)))).scalars().all()
    return [{"kind": r.kind, "value": r.value, "note": r.note, "created_at": r.created_at} for r in rows]


@router.get("/admin/risk/events")
def admin_risk_events(minutes: int = 5, to_wallet_id: Optional[str] = None, device_id: Optional[str] = None, ip: Optional[str] = None, limit: int = 100, s: Session = Depends(get_session), admin_ok: bool = Depends(require_admin)):
    if minutes < 1 or minutes > 1440:
        minutes = 5
    since = datetime.now(timezone.utc) - timedelta(minutes=minutes)
    q = select(AliasDeviceEvent).where(AliasDeviceEvent.created_at >= since)
    if to_wallet_id:
        q = q.where(AliasDeviceEvent.to_wallet_id == to_wallet_id)
    if device_id:
        q = q.where(AliasDeviceEvent.device_id == device_id)
    if ip:
        q = q.where(AliasDeviceEvent.ip == ip)
    rows = s.execute(q.order_by(AliasDeviceEvent.created_at.desc()).limit(max(1, min(limit, 1000)))).scalars().all()
    return [{
        "handle": e.handle,
        "to_wallet_id": e.to_wallet_id,
        "device_id": e.device_id,
        "ip": e.ip,
        "ts": e.created_at,
    } for e in rows]


@router.get("/admin/risk/metrics")
def admin_risk_metrics(minutes: int = 5, top: int = 10, s: Session = Depends(get_session), admin_ok: bool = Depends(require_admin)):
    if minutes < 1 or minutes > 1440:
        minutes = 5
    since = datetime.now(timezone.utc) - timedelta(minutes=minutes)
    # Top devices
    dev_rows = s.execute(sa_text(
        """
        select coalesce(device_id,'') as device_id, count(*) as cnt
        from {schema}.alias_device_events
        where created_at >= :since
        group by device_id
        order by cnt desc
        limit :top
        """.format(schema=DB_SCHEMA or 'public')
    ), {"since": since, "top": top}).all()
    # Top IPs
    ip_rows = s.execute(sa_text(
        """
        select coalesce(ip,'') as ip, count(*) as cnt
        from {schema}.alias_device_events
        where created_at >= :since
        group by ip
        order by cnt desc
        limit :top
        """.format(schema=DB_SCHEMA or 'public')
    ), {"since": since, "top": top}).all()
    # Top receivers
    rx_rows = s.execute(sa_text(
        """
        select to_wallet_id, count(*) as cnt
        from {schema}.alias_device_events
        where created_at >= :since
        group by to_wallet_id
        order by cnt desc
        limit :top
        """.format(schema=DB_SCHEMA or 'public')
    ), {"since": since, "top": top}).all()
    return {
        "window_minutes": minutes,
        "top_devices": [{"device_id": r[0] or None, "count": int(r[1])} for r in dev_rows],
        "top_ips": [{"ip": r[0] or None, "count": int(r[1])} for r in ip_rows],
        "top_receivers": [{"to_wallet_id": r[0], "count": int(r[1])} for r in rx_rows]
    }


@router.post("/admin/aliases/ensure")
def admin_aliases_ensure(s: Session = Depends(get_session), admin_ok: bool = Depends(require_admin)):
    _ensure_aliases_table()
    return {"ok": True}


# ---- Sonic Pay (offline near-field token) ----
def _sonic_hmac(data: bytes) -> str:
    return _hmac.new(SONIC_SECRET.encode(), data, _hashlib.sha256).hexdigest()


def _sonic_encode(payload: dict) -> str:
    raw = _json.dumps(payload, separators=(",", ":")).encode()
    sig = _sonic_hmac(raw)
    return _b64.urlsafe_b64encode(raw).decode().rstrip("=") + "." + sig


def _sonic_decode(token: str) -> dict:
    try:
        raw_b64, sig = token.split(".", 1)
        pad = '=' * (-len(raw_b64) % 4)
        raw = _b64.urlsafe_b64decode((raw_b64 + pad).encode())
        if _sonic_hmac(raw) != sig:
            raise HTTPException(status_code=400, detail="Invalid signature")
        payload = _json.loads(raw.decode())
        return payload
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid token format")


def _sonic_hash(token: str) -> str:
    return _hashlib.sha256(token.encode()).hexdigest()


class SonicIssueReq(BaseModel):
    from_wallet_id: str
    amount_cents: int = Field(..., gt=0)
    currency: Optional[str] = None


class SonicIssueResp(BaseModel):
    token: str
    code: str
    expires_at: Optional[str]
    amount_cents: int
    currency: str


@router.post("/sonic/issue", response_model=SonicIssueResp)
def sonic_issue(req: SonicIssueReq, s: Session = Depends(get_session), admin_ok: bool = Depends(require_admin)):
    from_w = s.execute(select(Wallet).where(Wallet.id == req.from_wallet_id).with_for_update()).scalars().first()
    if not from_w:
        raise HTTPException(status_code=404, detail="Wallet not found")
    amt = req.amount_cents
    if from_w.balance_cents < amt:
        raise HTTPException(status_code=400, detail="Insufficient funds")
    # Reserve funds
    from_w.balance_cents -= amt
    nonce = _secrets.token_urlsafe(8)
    exp = int((datetime.now(timezone.utc) + timedelta(seconds=SONIC_TTL_SECS)).timestamp())
    payload = {"v": 1, "from": from_w.id, "amt": amt, "ccy": (req.currency or from_w.currency), "exp": exp, "n": nonce}
    token = _sonic_encode(payload)
    th = _sonic_hash(token)
    st_id = str(uuid.uuid4())
    s.add(SonicToken(id=st_id, token_hash=th, from_wallet_id=from_w.id, amount_cents=amt, currency=(req.currency or from_w.currency), status="reserved", expires_at=datetime.fromtimestamp(exp, tz=timezone.utc), nonce=nonce))
    # Ledger reserve
    s.add(LedgerEntry(id=str(uuid.uuid4()), wallet_id=from_w.id, amount_cents=-amt, txn_id=None, description="sonic_reserve_debit"))
    s.add(LedgerEntry(id=str(uuid.uuid4()), wallet_id=None, amount_cents=+amt, txn_id=None, description="sonic_reserve_external"))
    s.commit()
    # Short code for human confirmation
    code = ("SP-" + _hashlib.sha1(th.encode()).hexdigest()[-6:]).upper()
    return SonicIssueResp(token=token, code=code, expires_at=datetime.fromtimestamp(exp, tz=timezone.utc).isoformat(), amount_cents=amt, currency=(req.currency or from_w.currency))


class SonicRedeemReq(BaseModel):
    token: str
    to_wallet_id: str


@router.post("/sonic/redeem")
def sonic_redeem(req: SonicRedeemReq, request: Request, s: Session = Depends(get_session)):
    # Allow idempotent client retries via Idempotency-Key
    ikey = request.headers.get("Idempotency-Key")
    if ikey:
        existed = s.scalar(select(Idempotency).where(Idempotency.ikey == ikey))
        if existed and existed.txn_id:
            tx = s.get(Txn, existed.txn_id)
            if tx:
                to_w = s.get(Wallet, req.to_wallet_id)
                return WalletResp(wallet_id=to_w.id, balance_cents=to_w.balance_cents, currency=to_w.currency)
    # Validate token
    payload = _sonic_decode(req.token)
    now = int(datetime.now(timezone.utc).timestamp())
    if int(payload.get("exp", 0)) < now:
        raise HTTPException(status_code=400, detail="Token expired")
    amt = int(payload.get("amt", 0))
    if amt <= 0:
        raise HTTPException(status_code=400, detail="Invalid amount")
    from_id = payload.get("from")
    th = _sonic_hash(req.token)
    st = s.execute(select(SonicToken).where(SonicToken.token_hash == th).with_for_update()).scalars().first()
    if not st or st.status != "reserved" or st.from_wallet_id != from_id:
        raise HTTPException(status_code=400, detail="Invalid or used token")
    # Transfer reserved funds to receiver; release external reserve
    to_w = s.execute(select(Wallet).where(Wallet.id == req.to_wallet_id).with_for_update()).scalars().first()
    if not to_w:
        raise HTTPException(status_code=404, detail="Receiver wallet not found")
    to_w.balance_cents += amt
    s.add(LedgerEntry(id=str(uuid.uuid4()), wallet_id=None, amount_cents=-amt, txn_id=None, description="sonic_reserve_release"))
    txn_id = str(uuid.uuid4())
    s.add(Txn(id=txn_id, from_wallet_id=from_id, to_wallet_id=to_w.id, amount_cents=amt, kind="transfer", fee_cents=0))
    s.add(LedgerEntry(id=str(uuid.uuid4()), wallet_id=to_w.id, amount_cents=+amt, txn_id=txn_id, description="sonic_credit"))
    st.status = "redeemed"
    st.to_wallet_id = to_w.id
    st.redeemed_at = datetime.now(timezone.utc)
    if ikey:
        s.add(Idempotency(id=str(uuid.uuid4()), ikey=ikey, endpoint="sonic_redeem", txn_id=txn_id))
    s.commit()
    s.refresh(to_w)
    return WalletResp(wallet_id=to_w.id, balance_cents=to_w.balance_cents, currency=to_w.currency)


# --- Cash Mandate (code-based cash send) ---
class CashCreateReq(BaseModel):
    from_wallet_id: str
    amount_cents: int = Field(..., gt=0)
    secret_phrase: str = Field(..., min_length=3, max_length=64)
    recipient_phone: Optional[str] = None


class CashResp(BaseModel):
    code: str
    expires_at: Optional[str]
    amount_cents: int
    currency: str
    sms_text: Optional[str] = None


def _hash_secret(secret: str) -> str:
    pepper = os.getenv("CASH_SECRET_PEPPER", "")
    data = secret.strip().lower().encode()
    return _hmac.new(pepper.encode(), data, _hashlib.sha256).hexdigest()


def _gen_code(s: Session) -> str:
    # 8-digit numeric, unique
    for _ in range(10):
        code = f"{_secrets.randbelow(10_0000_000):08d}"
        if not s.scalar(select(CashMandate).where(CashMandate.code == code)):
            return code
    raise HTTPException(status_code=500, detail="Could not generate code")


@router.post("/cash/create", response_model=CashResp)
def cash_create(req: CashCreateReq, request: Request, s: Session = Depends(get_session), admin_ok: bool = Depends(require_admin)):
    # Idempotency map to mandate id
    ikey = request.headers.get("Idempotency-Key")
    if ikey:
        existed = s.scalar(select(Idempotency).where(Idempotency.ikey == ikey))
        if existed and existed.txn_id:
            cm = s.get(CashMandate, existed.txn_id)
            if cm:
                return CashResp(code=cm.code, expires_at=cm.expires_at.isoformat() if cm.expires_at else None, amount_cents=cm.amount_cents, currency=cm.currency, sms_text=f"Code {cm.code} Amt {cm.amount_cents} SYP. Secret erforderlich.")
    from_w = s.execute(select(Wallet).where(Wallet.id == req.from_wallet_id).with_for_update()).scalars().first()
    if not from_w:
        raise HTTPException(status_code=404, detail="Wallet not found")
    # KYC & amount checks (simple)
    u = s.get(User, from_w.user_id)
    level = u.kyc_level if u else 0
    lim = KYC_LIMITS.get(level, KYC_LIMITS[0])
    if req.amount_cents > lim["tx_max"]:
        raise HTTPException(status_code=400, detail="Exceeds per-transaction limit for KYC level")
    if from_w.balance_cents < req.amount_cents:
        raise HTTPException(status_code=400, detail="Insufficient funds")
    # Reserve funds
    from_w.balance_cents -= req.amount_cents
    cm_id = str(uuid.uuid4())
    code = _gen_code(s)
    secret_hash = _hash_secret(req.secret_phrase)
    expires = datetime.now(timezone.utc) + timedelta(hours=48)
    cm = CashMandate(id=cm_id, code=code, secret_hash=secret_hash, amount_cents=req.amount_cents, currency=from_w.currency, from_wallet_id=from_w.id, status="reserved", expires_at=expires)
    s.add(cm)
    # Ledger: reserve external
    s.add(LedgerEntry(id=str(uuid.uuid4()), wallet_id=from_w.id, amount_cents=-req.amount_cents, txn_id=None, description="cash_reserve_debit"))
    s.add(LedgerEntry(id=str(uuid.uuid4()), wallet_id=None, amount_cents=+req.amount_cents, txn_id=None, description="cash_reserve_external"))
    # Record idempotency->mandate id
    if ikey:
        s.add(Idempotency(id=str(uuid.uuid4()), ikey=ikey, endpoint="cash_create", txn_id=cm_id))
    s.commit()
    sms_text = f"Cash-Code: {code}, Betrag: {req.amount_cents} {from_w.currency}. Geheimwort erforderlich. Gueltig 48h."
    return CashResp(code=code, expires_at=expires.isoformat(), amount_cents=req.amount_cents, currency=from_w.currency, sms_text=sms_text)


class CashRedeemReq(BaseModel):
    code: str
    secret_phrase: str
    agent_id: Optional[str] = None


@router.post("/cash/redeem")
def cash_redeem(req: CashRedeemReq, s: Session = Depends(get_session), admin_ok: bool = Depends(require_admin)):
    cm = s.scalar(select(CashMandate).where(CashMandate.code == req.code))
    if not cm:
        raise HTTPException(status_code=404, detail="Code not found")
    if cm.status != "reserved":
        raise HTTPException(status_code=400, detail=f"Not redeemable: {cm.status}")
    now = datetime.now(timezone.utc)
    if cm.expires_at and now > cm.expires_at:
        cm.status = "expired"
        s.commit()
        raise HTTPException(status_code=400, detail="Code expired")
    # Secret check with attempts limit
    if cm.attempts >= 5:
        raise HTTPException(status_code=403, detail="Too many attempts")
    if _hash_secret(req.secret_phrase) != cm.secret_hash:
        cm.attempts += 1
        s.commit()
        raise HTTPException(status_code=403, detail="Invalid secret")
    # Mark redeemed
    cm.status = "redeemed"
    cm.redeemed_at = now
    cm.agent_id = req.agent_id
    # Ledger: release reserve external (balance zero across external)
    s.add(LedgerEntry(id=str(uuid.uuid4()), wallet_id=None, amount_cents=-cm.amount_cents, txn_id=None, description="cash_reserve_release"))
    s.commit()
    return {"ok": True, "code": cm.code, "amount_cents": cm.amount_cents, "currency": cm.currency, "redeemed_at": cm.redeemed_at}


class CashCancelReq(BaseModel):
    code: str


@router.post("/cash/cancel")
def cash_cancel(req: CashCancelReq, s: Session = Depends(get_session), admin_ok: bool = Depends(require_admin)):
    cm = s.scalar(select(CashMandate).where(CashMandate.code == req.code))
    if not cm:
        raise HTTPException(status_code=404, detail="Code not found")
    if cm.status != "reserved":
        raise HTTPException(status_code=400, detail=f"Cannot cancel: {cm.status}")
    # Refund sender
    from_w = s.execute(select(Wallet).where(Wallet.id == cm.from_wallet_id).with_for_update()).scalars().first()
    if not from_w:
        raise HTTPException(status_code=404, detail="Sender wallet not found")
    from_w.balance_cents += cm.amount_cents
    cm.status = "cancelled"
    # Ledger: reverse external reserve
    s.add(LedgerEntry(id=str(uuid.uuid4()), wallet_id=from_w.id, amount_cents=+cm.amount_cents, txn_id=None, description="cash_cancel_refund"))
    s.add(LedgerEntry(id=str(uuid.uuid4()), wallet_id=None, amount_cents=-cm.amount_cents, txn_id=None, description="cash_reserve_remove"))
    s.commit()
    return {"ok": True, "code": cm.code, "status": cm.status}


@router.get("/cash/status/{code}")
def cash_status(code: str, s: Session = Depends(get_session)):
    cm = s.scalar(select(CashMandate).where(CashMandate.code == code))
    if not cm:
        return {"exists": False}
    return {
        "exists": True,
        "status": cm.status,
        "amount_cents": cm.amount_cents,
        "currency": cm.currency,
        "from_wallet_id": cm.from_wallet_id,
        "expires_at": cm.expires_at.isoformat() if cm.expires_at else None,
        "redeemed_at": cm.redeemed_at.isoformat() if cm.redeemed_at else None,
        "agent_id": cm.agent_id,
        "attempts": cm.attempts,
    }


# --- Topup Voucher (kiosk) endpoints ---
def _gen_voucher_code(n: int = 10) -> str:
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # exclude ambiguous
    return "".join(_secrets.choice(alphabet) for _ in range(max(6, min(24, n))))


def _gen_unique_voucher_code(s: Session, seen: set[str], n: int = 10, attempts: int = 5) -> str:
    """
    Generate a voucher code that does not collide with existing or in-batch codes.
    """
    for _ in range(max(1, attempts)):
        code = _gen_voucher_code(n)
        if code in seen:
            continue
        # Fast existence check to avoid unique constraint violations on commit
        exists = s.scalar(select(sa_func.count(TopupVoucher.id)).where(TopupVoucher.code == code))
        if exists and int(exists) > 0:
            continue
        return code
    raise HTTPException(status_code=500, detail="Failed to generate unique voucher code")


def _voucher_sig(code: str, amount_cents: int) -> str:
    raw = f"{code}|{amount_cents}".encode()
    return _hmac.new(TOPUP_SECRET.encode(), raw, _hashlib.sha256).hexdigest()


class TopupBatchCreateReq(BaseModel):
    amount_cents: int = Field(..., gt=0)
    count: int = Field(..., ge=1, le=1000)
    seller_id: Optional[str] = None
    expires_in_days: Optional[int] = Field(default=None, ge=1, le=365)
    note: Optional[str] = None
    funding_wallet_id: Optional[str] = None


@router.post("/topup/batch_create")
def topup_batch_create(req: TopupBatchCreateReq, s: Session = Depends(get_session), admin_ok: bool = Depends(require_admin)):
    batch_id = str(uuid.uuid4())
    now = datetime.now(timezone.utc)
    exp = (now + timedelta(days=req.expires_in_days)) if req.expires_in_days else None
    items = []
    # If a funding wallet is provided, ensure it exists and has enough balance.
    total_value = int(req.amount_cents) * int(req.count)
    funding_w: Optional[Wallet] = None
    env = _env_or("ENV", "dev").lower()
    if not req.funding_wallet_id and env not in ("dev", "test"):
        raise HTTPException(status_code=400, detail="funding_wallet_id required outside dev/test")
    if req.funding_wallet_id:
        funding_w = s.execute(select(Wallet).where(Wallet.id == req.funding_wallet_id).with_for_update()).scalars().first()
        if not funding_w:
            raise HTTPException(status_code=404, detail="Funding wallet not found")
        if funding_w.balance_cents < total_value:
            raise HTTPException(status_code=400, detail="Insufficient funds in funding wallet")
        funding_w.balance_cents -= total_value
        # Track liability movement: move funds to external reserve account (wallet=None)
        s.add(LedgerEntry(id=str(uuid.uuid4()), wallet_id=funding_w.id, amount_cents=-total_value, txn_id=None, description="voucher_batch_reserve"))
        s.add(LedgerEntry(id=str(uuid.uuid4()), wallet_id=None, amount_cents=+total_value, txn_id=None, description="voucher_batch_external"))
    seen_codes: set[str] = set()
    for _ in range(req.count):
        code = _gen_unique_voucher_code(s, seen_codes, 10)
        seen_codes.add(code)
        tv = TopupVoucher(
            id=str(uuid.uuid4()),
            code=code,
            amount_cents=req.amount_cents,
            currency=DEFAULT_CURRENCY,
            status="reserved",
            batch_id=batch_id,
            seller_id=(req.seller_id or None),
            note=(req.note or None),
            funding_wallet_id=funding_w.id if funding_w else None,
            created_at=now,
            expires_at=exp,
            # Link the funding source so redeem can reverse liability if needed.
            # Stored via seller_id / note if needed; kept simple for now.
        )
        s.add(tv)
        sig = _voucher_sig(code, req.amount_cents)
        payload = f"TOPUP|code={code}|amount={req.amount_cents}|sig={sig}"
        items.append({"code": code, "amount_cents": req.amount_cents, "currency": DEFAULT_CURRENCY, "sig": sig, "payload": payload})
    s.commit()
    return {"batch_id": batch_id, "items": items}


class TopupBatchSummary(BaseModel):
    batch_id: str
    seller_id: Optional[str] = None
    amount_cents: int
    currency: str
    created_at: Optional[datetime] = None
    total: int
    reserved: int
    redeemed: int
    void: int
    expired: int


@router.get("/topup/batches", response_model=List[TopupBatchSummary])
def topup_batches(seller_id: Optional[str] = None, limit: int = 50, s: Session = Depends(get_session), admin_ok: bool = Depends(require_admin)):
    if limit < 1 or limit > 2000:
        limit = 50
    base = select(TopupVoucher.batch_id).distinct()
    if seller_id:
        base = base.where(TopupVoucher.seller_id == seller_id)
    bids = [r[0] for r in s.execute(base.limit(limit)).all()]
    out: List[TopupBatchSummary] = []
    for bid in bids:
        rows = s.execute(select(TopupVoucher).where(TopupVoucher.batch_id == bid)).scalars().all()
        if not rows:
            continue
        first = rows[0]
        total = len(rows)
        reserved = sum(1 for r in rows if r.status == "reserved")
        redeemed = sum(1 for r in rows if r.status == "redeemed")
        void = sum(1 for r in rows if r.status == "void")
        expired = sum(1 for r in rows if r.status == "expired")
        out.append(TopupBatchSummary(
            batch_id=bid,
            seller_id=first.seller_id,
            amount_cents=first.amount_cents,
            currency=first.currency,
            created_at=first.created_at,  # type: ignore
            total=total,
            reserved=reserved,
            redeemed=redeemed,
            void=void,
            expired=expired,
        ))
    return out


class TopupVoucherItem(BaseModel):
    code: str
    amount_cents: int
    currency: str
    status: str
    created_at: Optional[datetime] = None
    redeemed_at: Optional[datetime] = None
    expires_at: Optional[datetime] = None
    sig: str
    payload: str
    seller_id: Optional[str] = None
    note: Optional[str] = None


@router.get("/topup/batches/{batch_id}", response_model=List[TopupVoucherItem])
def topup_batch_detail(batch_id: str, s: Session = Depends(get_session), admin_ok: bool = Depends(require_admin)):
    rows = s.execute(select(TopupVoucher).where(TopupVoucher.batch_id == batch_id)).scalars().all()
    out: List[TopupVoucherItem] = []
    for r in rows:
        sig = _voucher_sig(r.code, r.amount_cents)
        payload = f"TOPUP|code={r.code}|amount={r.amount_cents}|sig={sig}"
        out.append(TopupVoucherItem(
            code=r.code,
            amount_cents=r.amount_cents,
            currency=r.currency,
            status=r.status,
            created_at=r.created_at,  # type: ignore
            redeemed_at=r.redeemed_at,  # type: ignore
            expires_at=r.expires_at,  # type: ignore
            sig=sig,
            payload=payload,
            seller_id=r.seller_id,
            note=r.note,
        ))
    return out


@router.post("/topup/vouchers/{code}/void")
def topup_voucher_void(code: str, s: Session = Depends(get_session), admin_ok: bool = Depends(require_admin)):
    tv = s.scalar(select(TopupVoucher).where(TopupVoucher.code == code))
    if not tv:
        raise HTTPException(status_code=404, detail="Code not found")
    if tv.status != "reserved":
        raise HTTPException(status_code=400, detail=f"Cannot void: {tv.status}")
    tv.status = "void"
    # Refund funding wallet if present
    if tv.funding_wallet_id:
        fw = s.execute(select(Wallet).where(Wallet.id == tv.funding_wallet_id).with_for_update()).scalars().first()
        if fw:
            fw.balance_cents += tv.amount_cents
        # Reverse external reserve
        s.add(LedgerEntry(id=str(uuid.uuid4()), wallet_id=None, amount_cents=-tv.amount_cents, txn_id=None, description="voucher_batch_external_release"))
        s.add(LedgerEntry(id=str(uuid.uuid4()), wallet_id=fw.id if fw else None, amount_cents=+tv.amount_cents, txn_id=None, description="voucher_void_refund"))
    s.commit()
    return {"ok": True, "code": tv.code, "status": tv.status}


class TopupRedeemReq(BaseModel):
    code: str
    amount_cents: int
    sig: str
    to_wallet_id: str


@router.post("/topup/redeem")
def topup_redeem(req: TopupRedeemReq, request: Request, s: Session = Depends(get_session)):
    ikey = request.headers.get("Idempotency-Key")
    if ikey:
        existed = s.scalar(select(Idempotency).where(Idempotency.ikey == ikey))
        if existed and existed.txn_id:
            tx = s.get(Txn, existed.txn_id)
            if tx:
                w0 = s.get(Wallet, tx.to_wallet_id)
                if not w0:
                    raise HTTPException(status_code=404, detail="Wallet not found")
                # Prevent changing the destination wallet on retries
                if req.to_wallet_id and req.to_wallet_id != w0.id:
                    raise HTTPException(status_code=400, detail="Idempotent retry must target same wallet")
                return {"ok": True, "code": req.code, "amount_cents": tx.amount_cents, "currency": DEFAULT_CURRENCY, "wallet_id": w0.id}
    tv = s.execute(select(TopupVoucher).where(TopupVoucher.code == req.code).with_for_update()).scalars().first()
    if not tv:
        raise HTTPException(status_code=404, detail="Code not found")
    # Expiry and status checks
    now = datetime.now(timezone.utc)
    if tv.expires_at and tv.expires_at < now:
        tv.status = "expired"
        # Refund funding wallet if present
        if tv.funding_wallet_id:
            fw = s.execute(select(Wallet).where(Wallet.id == tv.funding_wallet_id).with_for_update()).scalars().first()
            if fw:
                fw.balance_cents += tv.amount_cents
            s.add(LedgerEntry(id=str(uuid.uuid4()), wallet_id=None, amount_cents=-tv.amount_cents, txn_id=None, description="voucher_batch_external_release"))
            s.add(LedgerEntry(id=str(uuid.uuid4()), wallet_id=fw.id if fw else None, amount_cents=+tv.amount_cents, txn_id=None, description="voucher_expire_refund"))
        s.commit()
        raise HTTPException(status_code=400, detail="Voucher expired")
    if tv.status != "reserved":
        raise HTTPException(status_code=400, detail=f"Cannot redeem: {tv.status}")
    if int(req.amount_cents) != int(tv.amount_cents):
        raise HTTPException(status_code=400, detail="Amount mismatch")
    expected = _voucher_sig(tv.code, tv.amount_cents)
    if (req.sig or "").strip().lower() != expected.lower():
        raise HTTPException(status_code=403, detail="Invalid signature")
    # Credit wallet
    w = s.execute(select(Wallet).where(Wallet.id == req.to_wallet_id).with_for_update()).scalars().first()
    if not w:
        raise HTTPException(status_code=404, detail="Wallet not found")
    # If the voucher was funded, release external reserve accordingly.
    if tv.funding_wallet_id:
        s.add(LedgerEntry(id=str(uuid.uuid4()), wallet_id=None, amount_cents=-tv.amount_cents, txn_id=None, description="voucher_redeem_external_release"))
    w.balance_cents += tv.amount_cents
    txn_id = str(uuid.uuid4())
    s.add(Txn(id=txn_id, from_wallet_id=None, to_wallet_id=w.id, amount_cents=tv.amount_cents, kind="topup", fee_cents=0))
    s.add(LedgerEntry(id=str(uuid.uuid4()), wallet_id=w.id, amount_cents=+tv.amount_cents, txn_id=txn_id, description="voucher_redeem"))
    if not tv.funding_wallet_id:
        s.add(LedgerEntry(id=str(uuid.uuid4()), wallet_id=None, amount_cents=-tv.amount_cents, txn_id=txn_id, description="voucher_external"))
    tv.status = "redeemed"
    tv.redeemed_at = now
    if ikey:
        s.add(Idempotency(id=str(uuid.uuid4()), ikey=ikey, endpoint="topup_redeem", txn_id=txn_id))
    s.commit()
    return {"ok": True, "code": tv.code, "amount_cents": tv.amount_cents, "currency": tv.currency, "wallet_id": w.id}


# --- Debug/Admin: DB Introspection ---
@router.get("/admin/debug/tables")
def admin_debug_tables(s: Session = Depends(get_session), admin_ok: bool = Depends(require_admin)):
    schema = DB_SCHEMA or "public"
    rows = s.execute(sa_text(
        """
        select table_schema, table_name
        from information_schema.tables
        where table_schema = :schema
        order by table_name
        """
    ), {"schema": schema}).all()
    tbls = [f"{r[0]}.{r[1]}" for r in rows]
    return {"schema": schema, "tables": tbls}
# Alias / velocity config
ALIAS_CODE_TTL_SECS = int(_env_or("ALIAS_CODE_TTL_SECS", "600"))  # 10 minutes
ALIAS_VELOCITY_MAX_TX = int(_env_or("ALIAS_VELOCITY_MAX_TX", "10"))  # per sender/min
ALIAS_VELOCITY_MAX_CENTS = int(_env_or("ALIAS_VELOCITY_MAX_CENTS", "500000"))
ALIAS_RX_VELOCITY_MAX_TX = int(_env_or("ALIAS_RX_VELOCITY_MAX_TX", "20"))  # per receiver/min
ALIAS_RX_VELOCITY_MAX_CENTS = int(_env_or("ALIAS_RX_VELOCITY_MAX_CENTS", "1000000"))
ALIAS_DEVICE_MAX_TX_PER_MIN = int(_env_or("ALIAS_DEVICE_MAX_TX_PER_MIN", "5"))
ALIAS_CODE_PEPPER = os.getenv("ALIAS_CODE_PEPPER", "")
RESERVED_ALIASES = set(a.strip() for a in _env_or("RESERVED_ALIASES", "admin,root,support,help,sys,ops").split(","))

# Risk controls
RISK_DENY_IP_PREFIXES = [p.strip() for p in _env_or("RISK_DENY_IP_PREFIXES", "").split(",") if p.strip()]
RISK_DENY_DEVICE_IDS = set(a.strip() for a in _env_or("RISK_DENY_DEVICE_IDS", "").split(",") if a.strip())
RISK_SCORE_THRESHOLD = int(_env_or("RISK_SCORE_THRESHOLD", "5"))
RISK_RETRY_BASE_MS = int(_env_or("RISK_RETRY_BASE_MS", "30000"))


# --- Roles Admin API ---
class RoleItem(BaseModel):
    id: str
    phone: str
    role: str
    created_at: Optional[datetime] = None


class RoleUpsert(BaseModel):
    phone: str
    role: str
    model_config = ConfigDict(json_schema_extra={"examples": [{"phone": "+963...", "role": "merchant"}]})


@router.get("/admin/roles", response_model=List[RoleItem])
def roles_list(phone: Optional[str] = None, role: Optional[str] = None, limit: int = 200, s: Session = Depends(get_session), admin_ok: bool = Depends(require_admin)):
    q = select(Role)
    if phone:
        q = q.where(Role.phone == phone)
    if role:
        q = q.where(Role.role == role)
    q = q.limit(max(1, min(limit, 1000)))
    rows = s.execute(q).scalars().all()
    return [RoleItem(id=r.id, phone=r.phone, role=r.role, created_at=r.created_at) for r in rows]


@router.post("/admin/roles")
def roles_add(body: RoleUpsert, s: Session = Depends(get_session), admin_ok: bool = Depends(require_admin)):
    ph = body.phone.strip()
    ro = body.role.strip().lower()
    if not ph or not ro:
        raise HTTPException(status_code=400, detail="phone and role required")
    if ro not in ALLOWED_ROLES:
        raise HTTPException(status_code=400, detail=f"unsupported role {ro}")
    # Ensure user + wallet exist for this phone so roles (e.g. driver)
    # always have a wallet to receive funds. Idempotent on phone.
    u = s.scalar(select(User).where(User.phone == ph))
    if not u:
        u = User(id=str(uuid.uuid4()), phone=ph)
        w = Wallet(id=str(uuid.uuid4()), user_id=u.id, balance_cents=0, currency=DEFAULT_CURRENCY)
        u.wallet = w
        s.add(u)
        s.add(w)
        s.flush()
    exists = s.scalar(select(Role).where(Role.phone == ph, Role.role == ro))
    if exists:
        return {"ok": True, "id": exists.id, "phone": exists.phone, "role": exists.role}
    r = Role(id=str(uuid.uuid4()), phone=ph, role=ro)
    s.add(r); s.commit()
    return {"ok": True, "id": r.id, "phone": r.phone, "role": r.role}


@router.delete("/admin/roles")
def roles_remove(body: RoleUpsert, s: Session = Depends(get_session), admin_ok: bool = Depends(require_admin)):
    ph = body.phone.strip(); ro = body.role.strip().lower()
    r = s.scalar(select(Role).where(Role.phone == ph, Role.role == ro))
    if not r:
        return {"ok": True, "removed": 0}
    s.delete(r); s.commit()
    return {"ok": True, "removed": 1}


@router.get("/admin/roles/check")
def roles_check(phone: str, role: str, s: Session = Depends(get_session), admin_ok: bool = Depends(require_admin)):
    ph = (phone or "").strip(); ro = (role or "").strip().lower()
    if not ph or not ro:
        return {"ok": True, "has": False}
    has = s.scalar(select(Role).where(Role.phone == ph, Role.role == ro)) is not None
    return {"ok": True, "has": has}


app.include_router(router)
