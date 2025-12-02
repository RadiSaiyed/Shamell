import json
import os
from typing import Optional, List

from fastapi import Depends, FastAPI, HTTPException, APIRouter
from pydantic import BaseModel, Field, ConfigDict
from shamell_shared import (
    RequestIDMiddleware,
    configure_cors,
    add_standard_health,
    setup_json_logging,
)
from sqlalchemy import (
    Boolean,
    DateTime,
    Float,
    Integer,
    String,
    BigInteger,
    Text,
    create_engine,
    func,
    select,
    text as sql_text,
)
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column
from sqlalchemy import inspect


def _env_or(key: str, default: str) -> str:
    v = os.getenv(key)
    return v if v is not None else default


app = FastAPI(title="Livestock API", version="0.1.0")
setup_json_logging()
app.add_middleware(RequestIDMiddleware)
configure_cors(app, os.getenv("ALLOWED_ORIGINS", "*"))
add_standard_health(app)

router = APIRouter()


DB_URL = _env_or("DB_URL", "sqlite+pysqlite:////tmp/livestock.db")
DB_SCHEMA = os.getenv("DB_SCHEMA") if not DB_URL.startswith("sqlite") else None


class Base(DeclarativeBase):
    pass


class Listing(Base):
    __tablename__ = "listings"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    title: Mapped[str] = mapped_column(String(200))
    species: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    breed: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    sex: Mapped[Optional[str]] = mapped_column(String(16), default=None)
    age_months: Mapped[Optional[int]] = mapped_column(Integer, default=None)
    weight_kg: Mapped[Optional[float]] = mapped_column(Float, default=None)
    lot_size: Mapped[Optional[int]] = mapped_column(Integer, default=None)
    price_cents: Mapped[int] = mapped_column(BigInteger)
    currency: Mapped[str] = mapped_column(String(3), default="SYP")
    negotiable: Mapped[bool] = mapped_column(Boolean, default=True)
    city: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    farm_name: Mapped[Optional[str]] = mapped_column(String(120), default=None)
    description: Mapped[Optional[str]] = mapped_column(Text, default=None)
    photos: Mapped[Optional[str]] = mapped_column(Text, default=None)  # JSON list
    tags: Mapped[Optional[str]] = mapped_column(Text, default=None)  # JSON list
    status: Mapped[str] = mapped_column(String(24), default="available")
    quality_grade: Mapped[Optional[str]] = mapped_column(String(32), default=None)
    health_status: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    seller_wallet_id: Mapped[Optional[str]] = mapped_column(String(36), default=None)
    seller_phone: Mapped[Optional[str]] = mapped_column(String(32), default=None)
    created_at: Mapped[Optional[str]] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[Optional[str]] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class Offer(Base):
    __tablename__ = "offers"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    listing_id: Mapped[int] = mapped_column(Integer, nullable=False, index=True)
    buyer_phone: Mapped[Optional[str]] = mapped_column(String(32), default=None)
    buyer_name: Mapped[Optional[str]] = mapped_column(String(120), default=None)
    quantity: Mapped[Optional[int]] = mapped_column(Integer, default=None)
    offer_price_cents: Mapped[Optional[int]] = mapped_column(BigInteger, default=None)
    currency: Mapped[str] = mapped_column(String(3), default="SYP")
    note: Mapped[Optional[str]] = mapped_column(Text, default=None)
    status: Mapped[str] = mapped_column(String(24), default="open")  # open/accepted/declined
    delivery_city: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    preferred_date: Mapped[Optional[str]] = mapped_column(String(32), default=None)
    created_at: Mapped[Optional[str]] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[Optional[str]] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


engine = create_engine(DB_URL, future=True)


def get_session() -> Session:
    with Session(engine) as s:
        yield s


def _maybe_add_column(table: str, column_sql: str):
    with engine.begin() as conn:
        try:
            conn.execute(sql_text(column_sql))
        except Exception:
            # ignore if already exists / other benign failures
            pass


def _ensure_schema():
    insp = inspect(engine)
    if not insp.has_table("listings", schema=DB_SCHEMA):
        Base.metadata.create_all(engine)
        return
    cols = {c["name"] for c in insp.get_columns("listings", schema=DB_SCHEMA)}
    if "breed" not in cols:
        _maybe_add_column("listings", f'ALTER TABLE {"%s." % DB_SCHEMA if DB_SCHEMA else ""}listings ADD COLUMN breed VARCHAR(64)')
    if "sex" not in cols:
        _maybe_add_column("listings", f'ALTER TABLE {"%s." % DB_SCHEMA if DB_SCHEMA else ""}listings ADD COLUMN sex VARCHAR(16)')
    if "age_months" not in cols:
        _maybe_add_column("listings", f'ALTER TABLE {"%s." % DB_SCHEMA if DB_SCHEMA else ""}listings ADD COLUMN age_months INTEGER')
    if "lot_size" not in cols:
        _maybe_add_column("listings", f'ALTER TABLE {"%s." % DB_SCHEMA if DB_SCHEMA else ""}listings ADD COLUMN lot_size INTEGER')
    if "negotiable" not in cols:
        _maybe_add_column("listings", f'ALTER TABLE {"%s." % DB_SCHEMA if DB_SCHEMA else ""}listings ADD COLUMN negotiable BOOLEAN DEFAULT 1')
    if "farm_name" not in cols:
        _maybe_add_column("listings", f'ALTER TABLE {"%s." % DB_SCHEMA if DB_SCHEMA else ""}listings ADD COLUMN farm_name VARCHAR(120)')
    if "description" not in cols:
        _maybe_add_column("listings", f'ALTER TABLE {"%s." % DB_SCHEMA if DB_SCHEMA else ""}listings ADD COLUMN description TEXT')
    if "photos" not in cols:
        _maybe_add_column("listings", f'ALTER TABLE {"%s." % DB_SCHEMA if DB_SCHEMA else ""}listings ADD COLUMN photos TEXT')
    if "tags" not in cols:
        _maybe_add_column("listings", f'ALTER TABLE {"%s." % DB_SCHEMA if DB_SCHEMA else ""}listings ADD COLUMN tags TEXT')
    if "status" not in cols:
        _maybe_add_column("listings", f'ALTER TABLE {"%s." % DB_SCHEMA if DB_SCHEMA else ""}listings ADD COLUMN status VARCHAR(24) DEFAULT \"available\"')
    if "quality_grade" not in cols:
        _maybe_add_column("listings", f'ALTER TABLE {"%s." % DB_SCHEMA if DB_SCHEMA else ""}listings ADD COLUMN quality_grade VARCHAR(32)')
    if "health_status" not in cols:
        _maybe_add_column("listings", f'ALTER TABLE {"%s." % DB_SCHEMA if DB_SCHEMA else ""}listings ADD COLUMN health_status VARCHAR(64)')
    if "seller_phone" not in cols:
        _maybe_add_column("listings", f'ALTER TABLE {"%s." % DB_SCHEMA if DB_SCHEMA else ""}listings ADD COLUMN seller_phone VARCHAR(32)')
    if "updated_at" not in cols:
        _maybe_add_column("listings", f'ALTER TABLE {"%s." % DB_SCHEMA if DB_SCHEMA else ""}listings ADD COLUMN updated_at TIMESTAMP')
    # create missing tables
    Base.metadata.create_all(engine)
    # ensure offer columns
    insp = inspect(engine)
    if insp.has_table("offers", schema=DB_SCHEMA):
        ocols = {c["name"] for c in insp.get_columns("offers", schema=DB_SCHEMA)}
        if "delivery_city" not in ocols:
            _maybe_add_column("offers", f'ALTER TABLE {"%s." % DB_SCHEMA if DB_SCHEMA else ""}offers ADD COLUMN delivery_city VARCHAR(64)')
        if "preferred_date" not in ocols:
            _maybe_add_column("offers", f'ALTER TABLE {"%s." % DB_SCHEMA if DB_SCHEMA else ""}offers ADD COLUMN preferred_date VARCHAR(32)')


def _startup():
    _ensure_schema()


app.router.on_startup.append(_startup)


def _encode_list(vals: Optional[List[str]]) -> Optional[str]:
    if not vals:
        return None
    return json.dumps([v for v in vals if v is not None])


def _decode_list(raw: Optional[str]) -> List[str]:
    if not raw:
        return []
    try:
        data = json.loads(raw)
        if isinstance(data, list):
            return [str(v) for v in data]
    except Exception:
        pass
    return []


class ListingCreate(BaseModel):
    title: str
    species: Optional[str] = None
    breed: Optional[str] = None
    sex: Optional[str] = None
    age_months: Optional[int] = Field(default=None, ge=0, le=360)
    weight_kg: Optional[float] = Field(default=None, ge=0)
    lot_size: Optional[int] = Field(default=None, ge=0)
    price_cents: int = Field(ge=0)
    currency: str = Field(default="SYP", min_length=3, max_length=3)
    negotiable: bool = True
    city: Optional[str] = None
    farm_name: Optional[str] = None
    description: Optional[str] = None
    photos: List[str] = Field(default_factory=list)
    tags: List[str] = Field(default_factory=list)
    status: str = Field(default="available")
    quality_grade: Optional[str] = None
    health_status: Optional[str] = None
    seller_wallet_id: Optional[str] = None
    seller_phone: Optional[str] = None


class ListingUpdate(BaseModel):
    title: Optional[str] = None
    species: Optional[str] = None
    breed: Optional[str] = None
    sex: Optional[str] = None
    age_months: Optional[int] = Field(default=None, ge=0, le=360)
    weight_kg: Optional[float] = Field(default=None, ge=0)
    lot_size: Optional[int] = Field(default=None, ge=0)
    price_cents: Optional[int] = Field(default=None, ge=0)
    currency: Optional[str] = Field(default=None, min_length=3, max_length=3)
    negotiable: Optional[bool] = None
    city: Optional[str] = None
    farm_name: Optional[str] = None
    description: Optional[str] = None
    photos: Optional[List[str]] = None
    tags: Optional[List[str]] = None
    status: Optional[str] = None
    quality_grade: Optional[str] = None
    health_status: Optional[str] = None
    seller_wallet_id: Optional[str] = None
    seller_phone: Optional[str] = None


class ListingOut(BaseModel):
    id: int
    title: str
    species: Optional[str]
    breed: Optional[str]
    sex: Optional[str]
    age_months: Optional[int]
    weight_kg: Optional[float]
    lot_size: Optional[int]
    price_cents: int
    currency: str
    negotiable: bool
    city: Optional[str]
    farm_name: Optional[str]
    description: Optional[str]
    photos: List[str]
    tags: List[str]
    status: str
    quality_grade: Optional[str]
    health_status: Optional[str]
    seller_wallet_id: Optional[str]
    seller_phone: Optional[str]
    created_at: Optional[str]
    updated_at: Optional[str]
    model_config = ConfigDict(from_attributes=True)


class OfferCreate(BaseModel):
    listing_id: int
    buyer_phone: Optional[str] = None
    buyer_name: Optional[str] = None
    quantity: Optional[int] = Field(default=None, ge=1)
    offer_price_cents: Optional[int] = Field(default=None, ge=0)
    currency: str = Field(default="SYP", min_length=3, max_length=3)
    note: Optional[str] = None
    delivery_city: Optional[str] = None
    preferred_date: Optional[str] = None


class OfferUpdate(BaseModel):
    status: Optional[str] = None
    offer_price_cents: Optional[int] = Field(default=None, ge=0)
    note: Optional[str] = None
    delivery_city: Optional[str] = None
    preferred_date: Optional[str] = None


class OfferOut(BaseModel):
    id: int
    listing_id: int
    buyer_phone: Optional[str]
    buyer_name: Optional[str]
    quantity: Optional[int]
    offer_price_cents: Optional[int]
    currency: str
    note: Optional[str]
    status: str
    delivery_city: Optional[str]
    preferred_date: Optional[str]
    created_at: Optional[str]
    updated_at: Optional[str]
    model_config = ConfigDict(from_attributes=True)


def _listing_to_out(l: Listing) -> ListingOut:
    return ListingOut(
        id=l.id,
        title=l.title,
        species=l.species,
        breed=l.breed,
        sex=l.sex,
        age_months=l.age_months,
        weight_kg=l.weight_kg,
        lot_size=l.lot_size,
        price_cents=l.price_cents,
        currency=l.currency,
        negotiable=bool(l.negotiable),
        city=l.city,
        farm_name=l.farm_name,
        description=l.description,
        photos=_decode_list(l.photos),
        tags=_decode_list(l.tags),
        status=l.status or "available",
        quality_grade=l.quality_grade,
        health_status=l.health_status,
        seller_wallet_id=l.seller_wallet_id,
        seller_phone=l.seller_phone,
        created_at=getattr(l, "created_at", None),
        updated_at=getattr(l, "updated_at", None),
    )


@router.post("/listings", response_model=ListingOut)
def create_listing(req: ListingCreate, s: Session = Depends(get_session)):
    l = Listing(
        title=req.title.strip(),
        species=req.species or None,
        breed=req.breed or None,
        sex=req.sex or None,
        age_months=req.age_months,
        weight_kg=req.weight_kg,
        lot_size=req.lot_size,
        price_cents=req.price_cents,
        currency=req.currency,
        negotiable=req.negotiable,
        city=req.city or None,
        farm_name=req.farm_name or None,
        description=req.description or None,
        photos=_encode_list(req.photos),
        tags=_encode_list(req.tags),
        status=req.status or "available",
        quality_grade=req.quality_grade or None,
        health_status=req.health_status or None,
        seller_wallet_id=req.seller_wallet_id or None,
        seller_phone=req.seller_phone or None,
    )
    s.add(l)
    s.commit()
    s.refresh(l)
    return _listing_to_out(l)


@router.get("/listings", response_model=List[ListingOut])
def list_listings(
    q: str = "",
    city: str = "",
    species: str = "",
    breed: str = "",
    sex: str = "",
    status: str = "",
    limit: int = 50,
    offset: int = 0,
    min_price: Optional[int] = None,
    max_price: Optional[int] = None,
    order: str = "desc",
    min_weight: Optional[float] = None,
    max_weight: Optional[float] = None,
    negotiable: Optional[bool] = None,
    s: Session = Depends(get_session),
):
    stmt = select(Listing)
    if q:
        stmt = stmt.where(func.lower(Listing.title).like(f"%{q.lower()}%"))
    if city:
        stmt = stmt.where(func.lower(Listing.city) == city.lower())
    if species:
        stmt = stmt.where(func.lower(Listing.species) == species.lower())
    if breed:
        stmt = stmt.where(func.lower(Listing.breed) == breed.lower())
    if sex:
        stmt = stmt.where(func.lower(Listing.sex) == sex.lower())
    if status:
        stmt = stmt.where(func.lower(Listing.status) == status.lower())
    if min_price is not None:
        stmt = stmt.where(Listing.price_cents >= min_price)
    if max_price is not None:
        stmt = stmt.where(Listing.price_cents <= max_price)
    if min_weight is not None:
        stmt = stmt.where(Listing.weight_kg >= min_weight)
    if max_weight is not None:
        stmt = stmt.where(Listing.weight_kg <= max_weight)
    if negotiable is not None:
        stmt = stmt.where(Listing.negotiable == negotiable)
    if order.lower() == "asc":
        stmt = stmt.order_by(Listing.price_cents.asc(), Listing.id.desc())
    elif order.lower() == "desc":
        stmt = stmt.order_by(Listing.price_cents.desc(), Listing.id.desc())
    else:
        stmt = stmt.order_by(Listing.id.desc())
    stmt = stmt.limit(max(1, min(limit, 200))).offset(max(0, offset))
    rows = s.execute(stmt).scalars().all()
    return [_listing_to_out(r) for r in rows]


@router.get("/listings/{lid}", response_model=ListingOut)
def get_listing(lid: int, s: Session = Depends(get_session)):
    l = s.get(Listing, lid)
    if not l:
        raise HTTPException(status_code=404, detail="not found")
    return _listing_to_out(l)


@router.patch("/listings/{lid}", response_model=ListingOut)
def update_listing(lid: int, req: ListingUpdate, s: Session = Depends(get_session)):
    l = s.get(Listing, lid)
    if not l:
        raise HTTPException(status_code=404, detail="not found")
    for field, value in req.model_dump(exclude_unset=True).items():
        if field in ("photos", "tags") and value is not None:
            setattr(l, field, _encode_list(value))
        else:
            setattr(l, field, value)
    s.commit()
    s.refresh(l)
    return _listing_to_out(l)


@router.post("/listings/{lid}/offers", response_model=OfferOut)
def create_offer(lid: int, req: OfferCreate, s: Session = Depends(get_session)):
    listing = s.get(Listing, lid)
    if not listing:
        raise HTTPException(status_code=404, detail="listing not found")
    off = Offer(
        listing_id=lid,
        buyer_phone=req.buyer_phone or None,
        buyer_name=req.buyer_name or None,
        quantity=req.quantity,
        offer_price_cents=req.offer_price_cents,
        currency=req.currency,
        note=req.note or None,
        delivery_city=req.delivery_city or None,
        preferred_date=req.preferred_date or None,
    )
    s.add(off)
    s.commit()
    s.refresh(off)
    return OfferOut.model_validate(off)


@router.get("/listings/{lid}/offers", response_model=List[OfferOut])
def list_offers(lid: int, s: Session = Depends(get_session)):
    stmt = select(Offer).where(Offer.listing_id == lid).order_by(Offer.id.desc())
    offs = s.execute(stmt).scalars().all()
    return [OfferOut.model_validate(o) for o in offs]


@router.patch("/offers/{oid}", response_model=OfferOut)
def update_offer(oid: int, req: OfferUpdate, s: Session = Depends(get_session)):
    off = s.get(Offer, oid)
    if not off:
        raise HTTPException(status_code=404, detail="not found")
    for field, value in req.model_dump(exclude_unset=True).items():
        setattr(off, field, value)
    s.commit()
    s.refresh(off)
    return OfferOut.model_validate(off)


app.include_router(router)
