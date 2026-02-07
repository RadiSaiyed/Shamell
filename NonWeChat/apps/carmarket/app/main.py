from fastapi import FastAPI, HTTPException, Depends, Header, APIRouter
from pydantic import BaseModel, Field, ConfigDict
from typing import Optional, List
import os
from shamell_shared import RequestIDMiddleware, configure_cors, add_standard_health, setup_json_logging
from sqlalchemy import create_engine, String, BigInteger, Integer, DateTime, func
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, Session
from sqlalchemy import select
from datetime import datetime


def _env_or(key: str, default: str) -> str:
    v = os.getenv(key)
    return v if v is not None else default


app = FastAPI(title="Carmarket API", version="0.1.0")
setup_json_logging()
app.add_middleware(RequestIDMiddleware)
configure_cors(app, os.getenv("ALLOWED_ORIGINS", "*"))
add_standard_health(app)

router = APIRouter()


DB_URL = _env_or("DB_URL", "sqlite+pysqlite:////tmp/carmarket.db")
DB_SCHEMA = os.getenv("DB_SCHEMA") if not DB_URL.startswith("sqlite") else None


class Base(DeclarativeBase):
    pass


class Listing(Base):
    __tablename__ = "listings"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    title: Mapped[str] = mapped_column(String(200))
    price_cents: Mapped[int] = mapped_column(BigInteger)
    make: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    model: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    year: Mapped[Optional[int]] = mapped_column(Integer, default=None)
    city: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    contact_phone: Mapped[Optional[str]] = mapped_column(String(32), default=None)
    description: Mapped[Optional[str]] = mapped_column(String(2000), default=None)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Inquiry(Base):
    __tablename__ = "inquiries"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    listing_id: Mapped[int] = mapped_column(Integer)
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
    # simple ensure tables
    Base.metadata.create_all(engine)

app.router.on_startup.append(_startup)


class ListingCreate(BaseModel):
    title: str
    price_cents: int = Field(ge=0)
    make: Optional[str] = None
    model: Optional[str] = None
    year: Optional[int] = Field(default=None, ge=1900, le=2100)
    city: Optional[str] = None
    contact_phone: Optional[str] = None
    description: Optional[str] = None


class ListingUpdate(BaseModel):
    title: Optional[str] = None
    price_cents: Optional[int] = Field(default=None, ge=0)
    make: Optional[str] = None
    model: Optional[str] = None
    year: Optional[int] = Field(default=None, ge=1900, le=2100)
    city: Optional[str] = None
    contact_phone: Optional[str] = None
    description: Optional[str] = None


class ListingOut(BaseModel):
    id: int
    title: str
    price_cents: int
    make: Optional[str]
    model: Optional[str]
    year: Optional[int]
    city: Optional[str]
    contact_phone: Optional[str]
    description: Optional[str]
    created_at: Optional[datetime]
    model_config = ConfigDict(from_attributes=True)


class InquiryCreate(BaseModel):
    listing_id: int
    name: str
    phone: Optional[str] = None
    message: Optional[str] = None


@router.post("/listings", response_model=ListingOut)
def create_listing(req: ListingCreate, idempotency_key: Optional[str] = Header(default=None, alias="Idempotency-Key"), s: Session = Depends(get_session)):
    if idempotency_key:
        ie = s.get(Idempotency, idempotency_key)
        if ie and ie.ref_id:
            try:
                l0 = s.get(Listing, int(ie.ref_id))
                if l0: return l0
            except Exception:
                pass
    l = Listing(
        title=req.title.strip(),
        price_cents=req.price_cents,
        make=(req.make or None),
        model=(req.model or None),
        year=req.year,
        city=(req.city or None),
        contact_phone=(req.contact_phone or None),
        description=(req.description or None),
    )
    s.add(l)
    s.commit()
    s.refresh(l)
    if idempotency_key:
        try: s.add(Idempotency(key=idempotency_key, ref_id=str(l.id))); s.commit()
        except Exception: pass
    return l


@router.get("/listings", response_model=List[ListingOut])
def list_listings(q: str = "", city: str = "", make: str = "", min_price: Optional[int] = None, max_price: Optional[int] = None, limit: int = 20, s: Session = Depends(get_session)):
    limit = max(1, min(limit, 50))
    stmt = select(Listing)
    if q:
        ql = f"%{q.lower()}%"
        stmt = stmt.where(func.lower(Listing.title).like(ql))
    if city:
        stmt = stmt.where(func.lower(Listing.city) == city.lower())
    if make:
        stmt = stmt.where(func.lower(Listing.make) == make.lower())
    if min_price is not None:
        stmt = stmt.where(Listing.price_cents >= int(min_price))
    if max_price is not None:
        stmt = stmt.where(Listing.price_cents <= int(max_price))
    stmt = stmt.order_by(Listing.id.desc()).limit(limit)
    rows = s.execute(stmt).scalars().all()
    return rows


@router.get("/listings/{listing_id}", response_model=ListingOut)
def get_listing(listing_id: int, s: Session = Depends(get_session)):
    l = s.get(Listing, listing_id)
    if not l:
        raise HTTPException(status_code=404, detail="not found")
    return l


@router.patch("/listings/{listing_id}", response_model=ListingOut)
def update_listing(listing_id: int, req: ListingUpdate, s: Session = Depends(get_session)):
    l = s.get(Listing, listing_id)
    if not l:
        raise HTTPException(status_code=404, detail="not found")
    data = req.model_dump(exclude_unset=True)
    for k, v in data.items():
        setattr(l, k, v)
    s.add(l)
    s.commit()
    s.refresh(l)
    return l


@router.delete("/listings/{listing_id}")
def delete_listing(listing_id: int, s: Session = Depends(get_session)):
    l = s.get(Listing, listing_id)
    if not l:
        raise HTTPException(status_code=404, detail="not found")
    s.delete(l)
    s.commit()
    return {"ok": True}


@router.post("/inquiries")
def create_inquiry(req: InquiryCreate, idempotency_key: Optional[str] = Header(default=None, alias="Idempotency-Key"), s: Session = Depends(get_session)):
    if not s.get(Listing, req.listing_id):
        raise HTTPException(status_code=404, detail="listing not found")
    if idempotency_key:
        ie = s.get(Idempotency, idempotency_key)
        if ie and ie.ref_id:
            return {"ok": True, "inquiry_id": int(ie.ref_id)}
    iq = Inquiry(listing_id=req.listing_id, name=req.name.strip(), phone=(req.phone or None), message=(req.message or None))
    s.add(iq)
    s.commit()
    if idempotency_key:
        try: s.add(Idempotency(key=idempotency_key, ref_id=str(iq.id))); s.commit()
        except Exception: pass
    return {"ok": True, "inquiry_id": iq.id}


app.include_router(router)
