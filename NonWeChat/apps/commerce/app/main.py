from fastapi import FastAPI, HTTPException, Depends, APIRouter
from pydantic import BaseModel, Field, ConfigDict
from typing import Optional, List
import os
from shamell_shared import RequestIDMiddleware, configure_cors, add_standard_health, setup_json_logging
from sqlalchemy import create_engine, String, Integer, BigInteger, DateTime, func
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, Session
from sqlalchemy import select


def _env_or(key: str, default: str) -> str:
    v = os.getenv(key)
    return v if v is not None else default


app = FastAPI(title="Commerce API", version="0.1.0")
setup_json_logging()
app.add_middleware(RequestIDMiddleware)
configure_cors(app, os.getenv("ALLOWED_ORIGINS", "*"))
add_standard_health(app)

router = APIRouter()


DB_URL = _env_or("COMMERCE_DB_URL", _env_or("DB_URL", "sqlite+pysqlite:////tmp/commerce.db"))
DB_SCHEMA = os.getenv("DB_SCHEMA") if not DB_URL.startswith("sqlite") else None


class Base(DeclarativeBase):
    pass


class Product(Base):
    __tablename__ = "products"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(200))
    price_cents: Mapped[int] = mapped_column(BigInteger)
    currency: Mapped[str] = mapped_column(String(3), default="SYP")
    sku: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    merchant_wallet_id: Mapped[Optional[str]] = mapped_column(String(36), default=None)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Order(Base):
    __tablename__ = "orders"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    product_id: Mapped[int] = mapped_column(Integer)
    quantity: Mapped[int] = mapped_column(Integer)
    buyer_wallet_id: Mapped[str] = mapped_column(String(36))
    seller_wallet_id: Mapped[Optional[str]] = mapped_column(String(36), default=None)
    amount_cents: Mapped[int] = mapped_column(BigInteger)
    currency: Mapped[str] = mapped_column(String(3), default="SYP")
    status: Mapped[str] = mapped_column(String(16), default="paid_escrow")
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[Optional[str]] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


engine = create_engine(DB_URL, future=True)


def get_session() -> Session:
    with Session(engine) as s:
        yield s


def _startup():
    Base.metadata.create_all(engine)

app.router.on_startup.append(_startup)


class ProductCreate(BaseModel):
    name: str
    price_cents: int = Field(ge=0)
    sku: Optional[str] = None
    merchant_wallet_id: Optional[str] = None


class ProductOut(BaseModel):
    id: int
    name: str
    price_cents: int
    currency: str
    sku: Optional[str]
    merchant_wallet_id: Optional[str]
    model_config = ConfigDict(from_attributes=True)


class OrderCreate(BaseModel):
    product_id: int
    quantity: int = Field(gt=0)
    buyer_wallet_id: str = Field(min_length=1)


class OrderOut(BaseModel):
    id: int
    product_id: int
    quantity: int
    buyer_wallet_id: str
    seller_wallet_id: Optional[str]
    shipment_id: Optional[str]
    amount_cents: int
    currency: str
    status: str
    created_at: Optional[str]
    updated_at: Optional[str]
    model_config = ConfigDict(from_attributes=True)


class OrderStatusUpdate(BaseModel):
    status: str = Field(min_length=1)


@router.post("/products", response_model=ProductOut)
def create_product(req: ProductCreate, s: Session = Depends(get_session)):
    p = Product(name=req.name.strip(), price_cents=req.price_cents, sku=(req.sku or None), merchant_wallet_id=(req.merchant_wallet_id or None))
    s.add(p); s.commit(); s.refresh(p)
    return p


@router.get("/products", response_model=List[ProductOut])
def list_products(q: str = "", limit: int = 50, s: Session = Depends(get_session)):
    stmt = select(Product)
    if q:
        stmt = stmt.where(func.lower(Product.name).like(f"%{q.lower()}%"))
    stmt = stmt.order_by(Product.id.desc()).limit(max(1, min(limit, 200)))
    return s.execute(stmt).scalars().all()


@router.get("/products/{pid}", response_model=ProductOut)
def get_product(pid: int, s: Session = Depends(get_session)):
    p = s.get(Product, pid)
    if not p:
        raise HTTPException(status_code=404, detail="not found")
    return p


@router.post("/orders", response_model=OrderOut)
def create_order(req: OrderCreate, s: Session = Depends(get_session)):
    """
    Create a simple commerce order for a product.

    Building Materials uses this for escrow-backed orders:
      - Amount is derived from product.price_cents * quantity.
      - seller_wallet_id comes from Product.merchant_wallet_id.
      - Status is initialised as 'paid_escrow' once the BFF has moved funds
        from buyer_wallet -> ESCROW_WALLET.
    """
    p = s.get(Product, req.product_id)
    if not p:
        raise HTTPException(status_code=404, detail="product not found")
    buyer_wallet_id = req.buyer_wallet_id.strip()
    if not buyer_wallet_id:
        raise HTTPException(status_code=400, detail="buyer_wallet_id required")
    seller_wallet_id = (p.merchant_wallet_id or "").strip()
    if not seller_wallet_id:
        raise HTTPException(status_code=400, detail="product has no merchant_wallet_id")
    amount_cents = int(p.price_cents) * int(req.quantity)
    if amount_cents <= 0:
        raise HTTPException(status_code=400, detail="amount must be > 0")
    o = Order(
        product_id=req.product_id,
        quantity=req.quantity,
        buyer_wallet_id=buyer_wallet_id,
        seller_wallet_id=seller_wallet_id,
        amount_cents=amount_cents,
        currency=p.currency,
        status="paid_escrow",
    )
    s.add(o)
    s.commit()
    s.refresh(o)
    return o


@router.get("/orders", response_model=List[OrderOut])
def list_orders(
    buyer_wallet_id: str = "",
    seller_wallet_id: str = "",
    limit: int = 50,
    s: Session = Depends(get_session),
):
    stmt = select(Order)
    if buyer_wallet_id:
        stmt = stmt.where(Order.buyer_wallet_id == buyer_wallet_id)
    if seller_wallet_id:
        stmt = stmt.where(Order.seller_wallet_id == seller_wallet_id)
    stmt = stmt.order_by(Order.id.desc()).limit(max(1, min(limit, 200)))
    return s.execute(stmt).scalars().all()


@router.get("/orders/{oid}", response_model=OrderOut)
def get_order(oid: int, s: Session = Depends(get_session)):
    o = s.get(Order, oid)
    if not o:
        raise HTTPException(status_code=404, detail="not found")
    return o


@router.post("/orders/{oid}/status", response_model=OrderOut)
def update_order_status(oid: int, req: OrderStatusUpdate, s: Session = Depends(get_session)):
    """
    Update an order status.

    Business rules (who may transition which status) are enforced at the
    BFF layer; this endpoint simply persists the new status.
    """
    o = s.get(Order, oid)
    if not o:
        raise HTTPException(status_code=404, detail="not found")
    val = req.status.strip()
    if not val:
        raise HTTPException(status_code=400, detail="status required")
    o.status = val
    s.add(o)
    s.commit()
    s.refresh(o)
    return o


app.include_router(router)
