from fastapi import FastAPI, HTTPException, Depends, APIRouter
from pydantic import BaseModel, Field, ConfigDict
from typing import Optional, List
import os
from shamell_shared import RequestIDMiddleware, configure_cors, add_standard_health, setup_json_logging
from sqlalchemy import create_engine, String, Integer, BigInteger, DateTime, Float, func
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, Session
from sqlalchemy import select


def _env_or(key: str, default: str) -> str:
    v = os.getenv(key)
    return v if v is not None else default


app = FastAPI(title="Agriculture API", version="0.1.0")
setup_json_logging()
app.add_middleware(RequestIDMiddleware)
configure_cors(app, os.getenv("ALLOWED_ORIGINS", "*"))
add_standard_health(app)

router = APIRouter()


DB_URL = _env_or("DB_URL", "sqlite+pysqlite:////tmp/agriculture.db")
DB_SCHEMA = os.getenv("DB_SCHEMA") if not DB_URL.startswith("sqlite") else None


class Base(DeclarativeBase):
    pass


class Listing(Base):
    __tablename__ = "listings"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    title: Mapped[str] = mapped_column(String(200))
    category: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    variety: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    description: Mapped[Optional[str]] = mapped_column(String(2000), default=None)
    pack_size: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    unit: Mapped[Optional[str]] = mapped_column(String(16), default=None)  # kg|ton|crate|box|ea
    min_qty: Mapped[Optional[float]] = mapped_column(Float, default=None)
    availability_from: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), default=None)
    availability_to: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), default=None)
    lead_time_days: Mapped[Optional[int]] = mapped_column(Integer, default=None)
    price_cents: Mapped[int] = mapped_column(BigInteger)
    currency: Mapped[str] = mapped_column(String(3), default="SYP")
    city: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    origin: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    certifications: Mapped[Optional[str]] = mapped_column(String(255), default=None)
    status: Mapped[str] = mapped_column(String(24), default="listed")  # listed|paused|out_of_stock
    image_url: Mapped[Optional[str]] = mapped_column(String(512), default=None)
    seller_wallet_id: Mapped[Optional[str]] = mapped_column(String(36), default=None)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class RFQ(Base):
    __tablename__ = "rfqs"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    product: Mapped[str] = mapped_column(String(200))
    category: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    quantity: Mapped[Optional[float]] = mapped_column(Float, default=None)
    unit: Mapped[Optional[str]] = mapped_column(String(16), default=None)
    city: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    target_date: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), default=None)
    notes: Mapped[Optional[str]] = mapped_column(String(2000), default=None)
    buyer_wallet_id: Mapped[Optional[str]] = mapped_column(String(36), default=None)
    status: Mapped[str] = mapped_column(String(24), default="open")  # open|quoted|closed
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class RFQReply(Base):
    __tablename__ = "rfq_replies"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    rfq_id: Mapped[int] = mapped_column(Integer)
    supplier_wallet_id: Mapped[Optional[str]] = mapped_column(String(36), default=None)
    price_per_unit_cents: Mapped[int] = mapped_column(BigInteger)
    currency: Mapped[str] = mapped_column(String(3), default="SYP")
    eta_days: Mapped[Optional[int]] = mapped_column(Integer, default=None)
    message: Mapped[Optional[str]] = mapped_column(String(1000), default=None)
    status: Mapped[str] = mapped_column(String(16), default="sent")
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Order(Base):
    __tablename__ = "orders"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    listing_id: Mapped[Optional[int]] = mapped_column(Integer, default=None)
    rfq_id: Mapped[Optional[int]] = mapped_column(Integer, default=None)
    buyer_wallet_id: Mapped[Optional[str]] = mapped_column(String(36), default=None)
    seller_wallet_id: Mapped[Optional[str]] = mapped_column(String(36), default=None)
    quantity: Mapped[Optional[float]] = mapped_column(Float, default=None)
    unit: Mapped[Optional[str]] = mapped_column(String(16), default=None)
    price_cents: Mapped[int] = mapped_column(BigInteger)
    currency: Mapped[str] = mapped_column(String(3), default="SYP")
    status: Mapped[str] = mapped_column(String(24), default="pending")  # pending|confirmed|canceled|fulfilled
    buyer_notes: Mapped[Optional[str]] = mapped_column(String(2000), default=None)
    supplier_notes: Mapped[Optional[str]] = mapped_column(String(2000), default=None)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


engine = create_engine(DB_URL, future=True)


def get_session() -> Session:
    with Session(engine) as s:
        yield s


def _startup():
    Base.metadata.create_all(engine)
    # Lightweight SQLite migrations to add new columns if existing DB is old
    if DB_URL.startswith("sqlite"):
        try:
            with engine.begin() as conn:
                cols = {c["name"] for c in conn.exec_driver_sql("PRAGMA table_info(listings)")}
                add_cols = []
                if "variety" not in cols:
                    add_cols.append("ALTER TABLE listings ADD COLUMN variety VARCHAR(64)")
                if "description" not in cols:
                    add_cols.append("ALTER TABLE listings ADD COLUMN description VARCHAR(2000)")
                if "pack_size" not in cols:
                    add_cols.append("ALTER TABLE listings ADD COLUMN pack_size VARCHAR(64)")
                if "unit" not in cols:
                    add_cols.append("ALTER TABLE listings ADD COLUMN unit VARCHAR(16)")
                if "min_qty" not in cols:
                    add_cols.append("ALTER TABLE listings ADD COLUMN min_qty FLOAT")
                if "availability_from" not in cols:
                    add_cols.append("ALTER TABLE listings ADD COLUMN availability_from TIMESTAMPTZ")
                if "availability_to" not in cols:
                    add_cols.append("ALTER TABLE listings ADD COLUMN availability_to TIMESTAMPTZ")
                if "lead_time_days" not in cols:
                    add_cols.append("ALTER TABLE listings ADD COLUMN lead_time_days INTEGER")
                if "origin" not in cols:
                    add_cols.append("ALTER TABLE listings ADD COLUMN origin VARCHAR(64)")
                if "certifications" not in cols:
                    add_cols.append("ALTER TABLE listings ADD COLUMN certifications VARCHAR(255)")
                if "status" not in cols:
                    add_cols.append("ALTER TABLE listings ADD COLUMN status VARCHAR(24) DEFAULT 'listed'")
                if "image_url" not in cols:
                    add_cols.append("ALTER TABLE listings ADD COLUMN image_url VARCHAR(512)")
                if "lead_time_days" not in cols:
                    add_cols.append("ALTER TABLE listings ADD COLUMN lead_time_days INTEGER")
                for stmt in add_cols:
                    try:
                        conn.exec_driver_sql(stmt)
                    except Exception:
                        pass
                # ensure rfqs, rfq_replies, orders tables exist
                conn.exec_driver_sql("""
                CREATE TABLE IF NOT EXISTS rfqs (
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  product VARCHAR(200),
                  category VARCHAR(64),
                  quantity FLOAT,
                  unit VARCHAR(16),
                  city VARCHAR(64),
                  target_date TIMESTAMPTZ,
                  notes VARCHAR(2000),
                  buyer_wallet_id VARCHAR(36),
                  status VARCHAR(24) DEFAULT 'open',
                  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
                )
                """)
                conn.exec_driver_sql("""
                CREATE TABLE IF NOT EXISTS rfq_replies (
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  rfq_id INTEGER,
                  supplier_wallet_id VARCHAR(36),
                  price_per_unit_cents BIGINT,
                  currency VARCHAR(3) DEFAULT 'SYP',
                  eta_days INTEGER,
                  message VARCHAR(1000),
                  status VARCHAR(16) DEFAULT 'sent',
                  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
                )
                """)
                conn.exec_driver_sql("""
                CREATE TABLE IF NOT EXISTS orders (
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  listing_id INTEGER,
                  rfq_id INTEGER,
                  buyer_wallet_id VARCHAR(36),
                  seller_wallet_id VARCHAR(36),
                  quantity FLOAT,
                  unit VARCHAR(16),
                  price_cents BIGINT,
                  currency VARCHAR(3) DEFAULT 'SYP',
                  status VARCHAR(24) DEFAULT 'pending',
                  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
                )
                """)
        except Exception:
            pass

app.router.on_startup.append(_startup)


class ListingCreate(BaseModel):
    title: str
    category: Optional[str] = None
    variety: Optional[str] = None
    description: Optional[str] = None
    pack_size: Optional[str] = None
    unit: Optional[str] = None
    min_qty: Optional[float] = None
    availability_from: Optional[str] = None
    availability_to: Optional[str] = None
    lead_time_days: Optional[int] = None
    price_cents: int = Field(ge=0)
    currency: str = "SYP"
    city: Optional[str] = None
    origin: Optional[str] = None
    certifications: Optional[str] = None
    status: Optional[str] = None
    image_url: Optional[str] = None
    seller_wallet_id: Optional[str] = None


class ListingUpdate(BaseModel):
    title: Optional[str] = None
    category: Optional[str] = None
    variety: Optional[str] = None
    description: Optional[str] = None
    pack_size: Optional[str] = None
    unit: Optional[str] = None
    min_qty: Optional[float] = None
    availability_from: Optional[str] = None
    availability_to: Optional[str] = None
    lead_time_days: Optional[int] = None
    price_cents: Optional[int] = Field(default=None, ge=0)
    currency: Optional[str] = None
    city: Optional[str] = None
    origin: Optional[str] = None
    certifications: Optional[str] = None
    status: Optional[str] = None
    image_url: Optional[str] = None
    seller_wallet_id: Optional[str] = None


class ListingOut(BaseModel):
    id: int
    title: str
    category: Optional[str]
    variety: Optional[str]
    description: Optional[str]
    pack_size: Optional[str]
    unit: Optional[str]
    min_qty: Optional[float]
    availability_from: Optional[str]
    availability_to: Optional[str]
    lead_time_days: Optional[int]
    price_cents: int
    currency: str
    city: Optional[str]
    origin: Optional[str]
    certifications: Optional[str]
    status: str
    image_url: Optional[str]
    seller_wallet_id: Optional[str]
    created_at: Optional[str]
    model_config = ConfigDict(from_attributes=True)


class RFQCreate(BaseModel):
    product: str
    category: Optional[str] = None
    quantity: Optional[float] = None
    unit: Optional[str] = None
    city: Optional[str] = None
    target_date: Optional[str] = None
    notes: Optional[str] = None
    buyer_wallet_id: Optional[str] = None


class RFQReplyCreate(BaseModel):
    price_per_unit_cents: int = Field(ge=0)
    currency: str = "SYP"
    eta_days: Optional[int] = None
    message: Optional[str] = None
    supplier_wallet_id: Optional[str] = None


class RFQOut(BaseModel):
    id: int
    product: str
    category: Optional[str]
    quantity: Optional[float]
    unit: Optional[str]
    city: Optional[str]
    target_date: Optional[str]
    notes: Optional[str]
    buyer_wallet_id: Optional[str]
    status: str
    created_at: Optional[str]
    model_config = ConfigDict(from_attributes=True)


class RFQReplyOut(BaseModel):
    id: int
    rfq_id: int
    supplier_wallet_id: Optional[str]
    price_per_unit_cents: int
    currency: str
    eta_days: Optional[int]
    message: Optional[str]
    status: str
    created_at: Optional[str]
    model_config = ConfigDict(from_attributes=True)


class OrderCreate(BaseModel):
    listing_id: Optional[int] = None
    rfq_id: Optional[int] = None
    buyer_wallet_id: Optional[str] = None
    seller_wallet_id: Optional[str] = None
    quantity: Optional[float] = None
    unit: Optional[str] = None
    price_cents: int = Field(ge=0)
    currency: str = "SYP"
    buyer_notes: Optional[str] = None
    supplier_notes: Optional[str] = None


class OrderOut(BaseModel):
    id: int
    listing_id: Optional[int]
    rfq_id: Optional[int]
    buyer_wallet_id: Optional[str]
    seller_wallet_id: Optional[str]
    quantity: Optional[float]
    unit: Optional[str]
    price_cents: int
    currency: str
    status: str
    buyer_notes: Optional[str]
    supplier_notes: Optional[str]
    created_at: Optional[str]
    model_config = ConfigDict(from_attributes=True)


class OrderUpdate(BaseModel):
    status: str
    buyer_notes: Optional[str] = None
    supplier_notes: Optional[str] = None


@router.post("/listings", response_model=ListingOut)
def create_listing(req: ListingCreate, s: Session = Depends(get_session)):
    l = Listing(
        title=req.title.strip(),
        category=(req.category or None),
        variety=(req.variety or None),
        description=(req.description or None),
        pack_size=(req.pack_size or None),
        unit=(req.unit or None),
        min_qty=req.min_qty,
        availability_from=(req.availability_from or None),
        availability_to=(req.availability_to or None),
        lead_time_days=req.lead_time_days,
        price_cents=req.price_cents,
        currency=req.currency or "SYP",
        city=(req.city or None),
        origin=(req.origin or None),
        certifications=(req.certifications or None),
        status=(req.status or "listed"),
        image_url=(req.image_url or None),
        seller_wallet_id=(req.seller_wallet_id or None),
    )
    s.add(l); s.commit(); s.refresh(l)
    return l


@router.get("/listings", response_model=List[ListingOut])
def list_listings(q: str = "", city: str = "", category: str = "", status: str = "", limit: int = 50, s: Session = Depends(get_session)):
    stmt = select(Listing)
    if q:
        stmt = stmt.where(func.lower(Listing.title).like(f"%{q.lower()}%"))
    if city:
        stmt = stmt.where(func.lower(Listing.city) == city.lower())
    if category:
        stmt = stmt.where(func.lower(Listing.category) == category.lower())
    if status:
        stmt = stmt.where(func.lower(Listing.status) == status.lower())
    stmt = stmt.order_by(Listing.id.desc()).limit(max(1, min(limit, 200)))
    return s.execute(stmt).scalars().all()


@router.get("/listings/{lid}", response_model=ListingOut)
def get_listing(lid: int, s: Session = Depends(get_session)):
    l = s.get(Listing, lid)
    if not l:
        raise HTTPException(status_code=404, detail="not found")
    return l


@router.patch("/listings/{lid}", response_model=ListingOut)
def update_listing(lid: int, req: ListingUpdate, s: Session = Depends(get_session)):
    l = s.get(Listing, lid)
    if not l:
        raise HTTPException(status_code=404, detail="not found")
    for k, v in req.model_dump(exclude_unset=True).items():
        setattr(l, k, v)
    s.add(l); s.commit(); s.refresh(l)
    return l


@router.post("/rfqs", response_model=RFQOut)
def create_rfq(req: RFQCreate, s: Session = Depends(get_session)):
    r = RFQ(
        product=req.product.strip(),
        category=(req.category or None),
        quantity=req.quantity,
        unit=(req.unit or None),
        city=(req.city or None),
        target_date=(req.target_date or None),
        notes=(req.notes or None),
        buyer_wallet_id=(req.buyer_wallet_id or None),
        status="open",
    )
    s.add(r); s.commit(); s.refresh(r)
    return r


@router.get("/rfqs", response_model=List[RFQOut])
def list_rfqs(status: str = "", city: str = "", limit: int = 100, s: Session = Depends(get_session)):
    stmt = select(RFQ)
    if status:
        stmt = stmt.where(func.lower(RFQ.status) == status.lower())
    if city:
        stmt = stmt.where(func.lower(RFQ.city) == city.lower())
    stmt = stmt.order_by(RFQ.id.desc()).limit(max(1, min(limit, 200)))
    return s.execute(stmt).scalars().all()


@router.get("/rfqs/{rid}", response_model=RFQOut)
def get_rfq(rid: int, s: Session = Depends(get_session)):
    r = s.get(RFQ, rid)
    if not r:
        raise HTTPException(status_code=404, detail="not found")
    return r


@router.post("/rfqs/{rid}/reply", response_model=RFQReplyOut)
def reply_rfq(rid: int, req: RFQReplyCreate, s: Session = Depends(get_session)):
    rfq = s.get(RFQ, rid)
    if not rfq:
        raise HTTPException(status_code=404, detail="rfq not found")
    rep = RFQReply(
        rfq_id=rid,
        supplier_wallet_id=(req.supplier_wallet_id or None),
        price_per_unit_cents=req.price_per_unit_cents,
        currency=req.currency or "SYP",
        eta_days=req.eta_days,
        message=(req.message or None),
        status="sent",
    )
    rfq.status = "quoted"
    s.add(rep); s.add(rfq); s.commit(); s.refresh(rep)
    return rep


@router.get("/rfqs/{rid}/replies", response_model=List[RFQReplyOut])
def list_rfq_replies(rid: int, s: Session = Depends(get_session)):
    rfq = s.get(RFQ, rid)
    if not rfq:
        raise HTTPException(status_code=404, detail="rfq not found")
    stmt = select(RFQReply).where(RFQReply.rfq_id == rid).order_by(RFQReply.id.desc())
    return s.execute(stmt).scalars().all()


@router.post("/orders", response_model=OrderOut)
def create_order(req: OrderCreate, s: Session = Depends(get_session)):
    o = Order(
        listing_id=req.listing_id,
        rfq_id=req.rfq_id,
        buyer_wallet_id=(req.buyer_wallet_id or None),
        seller_wallet_id=(req.seller_wallet_id or None),
        quantity=req.quantity,
        unit=(req.unit or None),
        price_cents=req.price_cents,
        currency=req.currency or "SYP",
        status="pending",
        buyer_notes=(req.buyer_notes or None),
        supplier_notes=(req.supplier_notes or None),
    )
    s.add(o); s.commit(); s.refresh(o)
    return o


@router.get("/orders", response_model=List[OrderOut])
def list_orders(limit: int = 100, status: str = "", s: Session = Depends(get_session)):
    stmt = select(Order)
    if status:
        stmt = stmt.where(func.lower(Order.status) == status.lower())
    stmt = stmt.order_by(Order.id.desc()).limit(max(1, min(limit, 200)))
    return s.execute(stmt).scalars().all()


@router.patch("/orders/{oid}", response_model=OrderOut)
def update_order(oid: int, req: OrderUpdate, s: Session = Depends(get_session)):
    o = s.get(Order, oid)
    if not o:
        raise HTTPException(status_code=404, detail="order not found")
    o.status = req.status
    if req.buyer_notes is not None:
        o.buyer_notes = req.buyer_notes
    if req.supplier_notes is not None:
        o.supplier_notes = req.supplier_notes
    s.add(o); s.commit(); s.refresh(o)
    return o


app.include_router(router)
