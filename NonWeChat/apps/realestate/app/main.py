from fastapi import FastAPI, HTTPException, Depends, Request, Header, APIRouter
from pydantic import BaseModel, Field, ConfigDict
from typing import Optional, List
import os
from shamell_shared import RequestIDMiddleware, configure_cors, add_standard_health, setup_json_logging
from sqlalchemy import create_engine, String, Integer, BigInteger, DateTime, Float, func
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, Session
from sqlalchemy import select
from datetime import datetime
import uuid
import httpx


def _env_or(key: str, default: str) -> str:
    v = os.getenv(key)
    return v if v is not None else default


app = FastAPI(title="RealEstate API", version="0.1.0")
setup_json_logging()
app.add_middleware(RequestIDMiddleware)
configure_cors(app, os.getenv("ALLOWED_ORIGINS", "*"))
add_standard_health(app)

router = APIRouter()


DB_URL = _env_or("DB_URL", "sqlite+pysqlite:////tmp/realestate.db")
DB_SCHEMA = os.getenv("DB_SCHEMA") if not DB_URL.startswith("sqlite") else None
PAYMENTS_BASE = _env_or("PAYMENTS_BASE_URL", "")


class Base(DeclarativeBase):
    pass


class Property(Base):
    __tablename__ = "properties"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    title: Mapped[str] = mapped_column(String(200))
    price_cents: Mapped[int] = mapped_column(BigInteger)
    currency: Mapped[str] = mapped_column(String(3), default="SYP")
    address: Mapped[Optional[str]] = mapped_column(String(255), default=None)
    city: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    bedrooms: Mapped[Optional[int]] = mapped_column(Integer, default=None)
    bathrooms: Mapped[Optional[int]] = mapped_column(Integer, default=None)
    area_sqm: Mapped[Optional[float]] = mapped_column(Float, default=None)
    description: Mapped[Optional[str]] = mapped_column(String(2000), default=None)
    owner_wallet_id: Mapped[Optional[str]] = mapped_column(String(36), default=None)
    status: Mapped[str] = mapped_column(String(16), default="listed")  # listed|reserved|sold|rented
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Inquiry(Base):
    __tablename__ = "inquiries"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    property_id: Mapped[int] = mapped_column(Integer)
    name: Mapped[str] = mapped_column(String(120))
    phone: Mapped[Optional[str]] = mapped_column(String(32), default=None)
    message: Mapped[Optional[str]] = mapped_column(String(1000), default=None)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Idempotency(Base):
    __tablename__ = "idempotency"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    key: Mapped[str] = mapped_column(String(120), primary_key=True)
    ref_id: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


engine = create_engine(DB_URL, future=True)


def get_session() -> Session:
    with Session(engine) as s:
        yield s


def _startup():
    Base.metadata.create_all(engine)

app.router.on_startup.append(_startup)


class PropertyCreate(BaseModel):
    title: str
    price_cents: int = Field(ge=0)
    currency: str = "SYP"
    address: Optional[str] = None
    city: Optional[str] = None
    bedrooms: Optional[int] = None
    bathrooms: Optional[int] = None
    area_sqm: Optional[float] = None
    description: Optional[str] = None
    owner_wallet_id: Optional[str] = None


class PropertyUpdate(BaseModel):
    title: Optional[str] = None
    price_cents: Optional[int] = Field(default=None, ge=0)
    currency: Optional[str] = None
    address: Optional[str] = None
    city: Optional[str] = None
    bedrooms: Optional[int] = None
    bathrooms: Optional[int] = None
    area_sqm: Optional[float] = None
    description: Optional[str] = None
    owner_wallet_id: Optional[str] = None
    status: Optional[str] = None


class PropertyOut(BaseModel):
    id: int
    title: str
    price_cents: int
    currency: str
    address: Optional[str]
    city: Optional[str]
    bedrooms: Optional[int]
    bathrooms: Optional[int]
    area_sqm: Optional[float]
    description: Optional[str]
    owner_wallet_id: Optional[str]
    status: str
    model_config = ConfigDict(from_attributes=True)


@router.post("/properties", response_model=PropertyOut)
def create_property(req: PropertyCreate, idempotency_key: Optional[str] = Header(default=None, alias="Idempotency-Key"), s: Session = Depends(get_session)):
    if idempotency_key:
        ie = s.get(Idempotency, idempotency_key)
        if ie and ie.ref_id:
            try:
                p0 = s.get(Property, int(ie.ref_id))
                if p0: return p0
            except Exception:
                pass
    p = Property(
        title=req.title.strip(), price_cents=req.price_cents, currency=req.currency,
        address=(req.address or None), city=(req.city or None), bedrooms=req.bedrooms, bathrooms=req.bathrooms,
        area_sqm=req.area_sqm, description=(req.description or None), owner_wallet_id=(req.owner_wallet_id or None)
    )
    s.add(p); s.commit(); s.refresh(p)
    if idempotency_key:
        try: s.add(Idempotency(key=idempotency_key, ref_id=str(p.id))); s.commit()
        except Exception: pass
    return p


@router.get("/properties", response_model=List[PropertyOut])
def list_properties(q: str = "", city: str = "", min_price: Optional[int] = None, max_price: Optional[int] = None, min_bedrooms: Optional[int] = None, limit: int = 20, s: Session = Depends(get_session)):
    limit = max(1, min(limit, 100))
    stmt = select(Property)
    if q: stmt = stmt.where(func.lower(Property.title).like(f"%{q.lower()}%"))
    if city: stmt = stmt.where(func.lower(Property.city) == city.lower())
    if min_price is not None: stmt = stmt.where(Property.price_cents >= int(min_price))
    if max_price is not None: stmt = stmt.where(Property.price_cents <= int(max_price))
    if min_bedrooms is not None: stmt = stmt.where(Property.bedrooms >= int(min_bedrooms))
    stmt = stmt.order_by(Property.id.desc()).limit(limit)
    return s.execute(stmt).scalars().all()


@router.get("/properties/{pid}", response_model=PropertyOut)
def get_property(pid: int, s: Session = Depends(get_session)):
    p = s.get(Property, pid)
    if not p: raise HTTPException(status_code=404, detail="not found")
    return p


@router.patch("/properties/{pid}", response_model=PropertyOut)
def update_property(pid: int, req: PropertyUpdate, s: Session = Depends(get_session)):
    p = s.get(Property, pid)
    if not p: raise HTTPException(status_code=404, detail="not found")
    for k, v in req.model_dump(exclude_unset=True).items(): setattr(p, k, v)
    s.add(p); s.commit(); s.refresh(p)
    return p


@router.delete("/properties/{pid}")
def delete_property(pid: int, s: Session = Depends(get_session)):
    p = s.get(Property, pid)
    if not p: raise HTTPException(status_code=404, detail="not found")
    s.delete(p); s.commit(); return {"ok": True}


class InquiryCreate(BaseModel):
    property_id: int
    name: str
    phone: Optional[str] = None
    message: Optional[str] = None


@router.post("/inquiries")
def create_inquiry(req: InquiryCreate, idempotency_key: Optional[str] = Header(default=None, alias="Idempotency-Key"), s: Session = Depends(get_session)):
    if not s.get(Property, req.property_id): raise HTTPException(status_code=404, detail="property not found")
    if idempotency_key:
        ie = s.get(Idempotency, idempotency_key)
        if ie and ie.ref_id:
            return {"ok": True, "inquiry_id": int(ie.ref_id)}
    iq = Inquiry(property_id=req.property_id, name=req.name.strip(), phone=(req.phone or None), message=(req.message or None))
    s.add(iq); s.commit();
    if idempotency_key:
        try: s.add(Idempotency(key=idempotency_key, ref_id=str(iq.id))); s.commit()
        except Exception: pass
    return {"ok": True, "inquiry_id": iq.id}


@router.post("/reserve")
def reserve_property(pid: int, s: Session = Depends(get_session)):
    p = s.get(Property, pid)
    if not p:
        raise HTTPException(status_code=404, detail="not found")
    if p.status not in ("listed", "reserved"):
        raise HTTPException(status_code=400, detail="cannot reserve in current status")
    p.status = "reserved"
    s.add(p); s.commit(); s.refresh(p)
    return PropertyOut.model_validate(p)


app.include_router(router)


def _pay(from_wallet: str, to_wallet: str, amount_cents: int, ikey: str, ref: str) -> dict:
    if not PAYMENTS_BASE: raise RuntimeError("PAYMENTS_BASE_URL not configured")
    url = PAYMENTS_BASE.rstrip('/') + '/transfer'
    headers = {"Content-Type": "application/json", "Idempotency-Key": ikey, "X-Merchant": "realestate", "X-Ref": ref}
    r = httpx.post(url, json={"from_wallet_id": from_wallet, "to_wallet_id": to_wallet, "amount_cents": amount_cents}, headers=headers, timeout=10)
    r.raise_for_status(); return r.json()


class ReserveReq(BaseModel):
    property_id: int
    buyer_wallet_id: str
    deposit_cents: int = Field(ge=1)


@app.post("/reserve")
def reserve(req: ReserveReq, idempotency_key: Optional[str] = Header(default=None, alias="Idempotency-Key"), s: Session = Depends(get_session)):
    p = s.get(Property, req.property_id)
    if not p: raise HTTPException(status_code=404, detail="property not found")
    if not p.owner_wallet_id: raise HTTPException(status_code=400, detail="owner wallet missing")
    if idempotency_key:
        ie = s.get(Idempotency, idempotency_key)
        if ie and ie.ref_id:
            return {"ok": True, "property_id": p.id, "status": p.status, "payments_txn_id": ie.ref_id}
    ikey = idempotency_key or f"reserve-{p.id}-{uuid.uuid4().hex[:8]}"
    resp = _pay(req.buyer_wallet_id, p.owner_wallet_id, req.deposit_cents, ikey=ikey, ref=f"reserve-{p.id}")
    p.status = "reserved"
    s.add(p); s.commit(); s.refresh(p)
    txn = str(resp.get("id") or resp.get("txn_id") or "")
    if idempotency_key:
        try: s.add(Idempotency(key=idempotency_key, ref_id=txn)); s.commit()
        except Exception: pass
    return {"ok": True, "property_id": p.id, "status": p.status, "payments_txn_id": txn}
