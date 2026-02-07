from fastapi import FastAPI, HTTPException, Depends, Request, Header, APIRouter
from pydantic import BaseModel, Field, ConfigDict
from typing import Optional, List
import os
import logging
from shamell_shared import RequestIDMiddleware, configure_cors, add_standard_health, setup_json_logging
from sqlalchemy import create_engine, String, Integer, BigInteger, DateTime, Float, func, ForeignKey
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, Session, relationship
from sqlalchemy import select
from datetime import datetime
import uuid

try:
    # Optional internal Payments integration (monolith mode).
    from apps.payments.app.main import (  # type: ignore[import]
        Session as _PaySession,
        engine as _pay_engine,
        transfer as _pay_transfer,
        TransferReq as _PayTransferReq,
        sonic_issue as _pay_sonic_issue,
        SonicIssueReq as _PaySonicIssueReq,
        sonic_redeem as _pay_sonic_redeem,
        SonicRedeemReq as _PaySonicRedeemReq,
    )
    _PAY_INTERNAL_AVAILABLE = True
except Exception:
    _PaySession = None  # type: ignore[assignment]
    _pay_engine = None  # type: ignore[assignment]
    _pay_transfer = None  # type: ignore[assignment]
    _PayTransferReq = None  # type: ignore[assignment]
    _pay_sonic_issue = None  # type: ignore[assignment]
    _PaySonicIssueReq = None  # type: ignore[assignment]
    _pay_sonic_redeem = None  # type: ignore[assignment]
    _PaySonicRedeemReq = None  # type: ignore[assignment]
    _PAY_INTERNAL_AVAILABLE = False


def _env_or(key: str, default: str) -> str:
    v = os.getenv(key)
    return v if v is not None else default


# Food depends on internal Payments; default to on and fail fast otherwise.
os.environ.setdefault("PAY_INTERNAL_MODE", "on")
os.environ.setdefault("PAYMENTS_INTERNAL_MODE", "on")


app = FastAPI(title="Food API", version="0.1.0")
setup_json_logging()
app.add_middleware(RequestIDMiddleware)
configure_cors(app, os.getenv("ALLOWED_ORIGINS", "*"))
add_standard_health(app)

router = APIRouter()


DB_URL = _env_or("FOOD_DB_URL", _env_or("DB_URL", "sqlite+pysqlite:////tmp/food.db"))
DB_SCHEMA = os.getenv("DB_SCHEMA") if not DB_URL.startswith("sqlite") else None


def _use_pay_internal() -> bool:
    """
    Prefer Payments internal calls when explicitly enabled (monolith mode).
    """
    mode = (os.getenv("PAYMENTS_INTERNAL_MODE") or os.getenv("PAY_INTERNAL_MODE") or "").lower()
    if mode != "on":
        return False
    return bool(
        _PAY_INTERNAL_AVAILABLE
        and _PaySession
        and _pay_engine
        and _pay_sonic_issue
        and _PaySonicIssueReq
        and _pay_sonic_redeem
        and _PaySonicRedeemReq
    )


def _assert_pay_internal() -> None:
    """
    Fail fast when Payments internal wiring is missing; Food no longer
    supports HTTP-based Payments calls.
    """
    if not _use_pay_internal():
        logging.error("Food requires PAY_INTERNAL_MODE=on and Payments module available (no PAYMENTS_BASE_URL fallback).")
        raise RuntimeError("Food payments internal integration missing; set PAY_INTERNAL_MODE=on and ensure apps.payments is importable.")


class Base(DeclarativeBase):
    pass


class Restaurant(Base):
    __tablename__ = "restaurants"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(200))
    city: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    address: Mapped[Optional[str]] = mapped_column(String(255), default=None)
    owner_wallet_id: Mapped[Optional[str]] = mapped_column(String(36), default=None)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())
    items: Mapped[List["MenuItem"]] = relationship(back_populates="restaurant")


class MenuItem(Base):
    __tablename__ = "menu_items"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    restaurant_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey(f"{DB_SCHEMA}.restaurants.id" if DB_SCHEMA else "restaurants.id"),
    )
    name: Mapped[str] = mapped_column(String(200))
    price_cents: Mapped[int] = mapped_column(BigInteger)
    currency: Mapped[str] = mapped_column(String(3), default="SYP")
    restaurant: Mapped[Restaurant] = relationship(back_populates="items")


class Order(Base):
    __tablename__ = "orders"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    restaurant_id: Mapped[int] = mapped_column(Integer)
    customer_name: Mapped[Optional[str]] = mapped_column(String(120), default=None)
    customer_phone: Mapped[Optional[str]] = mapped_column(String(32), default=None)
    customer_wallet_id: Mapped[Optional[str]] = mapped_column(String(36), default=None)
    total_cents: Mapped[int] = mapped_column(BigInteger, default=0)
    status: Mapped[str] = mapped_column(String(16), default="placed")  # placed|accepted|preparing|ready|completed|canceled
    payments_txn_id: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    escrow_token: Mapped[Optional[str]] = mapped_column(String(512), default=None)
    escrow_status: Mapped[str] = mapped_column(String(16), default="none")  # none|reserved|released|canceled
    escrow_code: Mapped[Optional[str]] = mapped_column(String(32), default=None)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class OrderItem(Base):
    __tablename__ = "order_items"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    order_id: Mapped[str] = mapped_column(String(36))
    menu_item_id: Mapped[int] = mapped_column(Integer)
    name: Mapped[str] = mapped_column(String(200))
    price_cents: Mapped[int] = mapped_column(BigInteger)
    qty: Mapped[int] = mapped_column(Integer, default=1)


class Idempotency(Base):
    __tablename__ = "idempotency"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    key: Mapped[str] = mapped_column(String(120), primary_key=True)
    order_id: Mapped[Optional[str]] = mapped_column(String(36), default=None)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


engine = create_engine(DB_URL, future=True)


def get_session() -> Session:
    with Session(engine) as s:
        yield s


def _ensure_demo_restaurants():
    """
    Best-effort seeding of a few demo restaurants + menus in local dev.
    Only runs on SQLite in ENV=dev/test and only when the restaurants
    table is still empty, so it won't interfere with manual data.
    """
    env = os.getenv("ENV", "dev").lower()
    if env not in ("dev", "test"):
        return
    if not DB_URL.startswith("sqlite"):
        return
    try:
        with Session(engine) as s:
            # Only seed when there are no restaurants yet
            existing = s.scalar(select(func.count(Restaurant.id)))
            if existing and int(existing) > 0:
                return

            now = datetime.utcnow()
            # Midnight Damascus – classic restaurant
            r1 = Restaurant(
                name="Midnight Damascus Restaurant",
                city="Damascus",
                address="Sarouja",
                owner_wallet_id=None,
                created_at=now,
            )
            # Sarouja Market Groceries – grocery-style
            r2 = Restaurant(
                name="Sarouja Market Groceries",
                city="Damascus",
                address="Sarouja",
                owner_wallet_id=None,
                created_at=now,
            )
            # City Convenience Shop
            r3 = Restaurant(
                name="City Convenience Shop",
                city="Damascus",
                address="Mazzeh",
                owner_wallet_id=None,
                created_at=now,
            )
            # Old Town Sweets Bakery
            r4 = Restaurant(
                name="Old Town Sweets Bakery",
                city="Damascus",
                address="Old Town",
                owner_wallet_id=None,
                created_at=now,
            )
            s.add_all([r1, r2, r3, r4])
            s.flush()

            def add_item(rest: Restaurant, name: str, cents: int):
                s.add(
                    MenuItem(
                        restaurant_id=rest.id,
                        name=name,
                        price_cents=cents,
                        currency="SYP",
                    )
                )

            # Menus
            add_item(r1, "Midnight shawarma plate", 45_000)
            add_item(r1, "Falafel sandwich", 20_000)
            add_item(r1, "Hummus bowl", 18_000)

            add_item(r2, "Fresh vegetables box", 35_000)
            add_item(r2, "Bread + dairy combo", 25_000)
            add_item(r2, "Basic groceries pack", 50_000)

            add_item(r3, "Convenience snacks combo", 15_000)
            add_item(r3, "Soft drinks (1.5L)", 8_000)
            add_item(r3, "Quick breakfast pack", 22_000)

            add_item(r4, "Assorted baklava box", 40_000)
            add_item(r4, "Kunafa slice", 18_000)
            add_item(r4, "Chocolate cake slice", 16_000)

            s.commit()
    except Exception:
        # Seeding must never break startup.
        pass


def _ensure_sqlite_migrations():
    # Minimal migration helper so existing SQLite DBs gain new escrow columns.
    if not DB_URL.startswith("sqlite"):
        return
    with engine.begin() as conn:
        try:
            cols = [row[1] for row in conn.exec_driver_sql("PRAGMA table_info(orders)").fetchall()]
        except Exception:
            return
        if "escrow_token" not in cols:
            conn.exec_driver_sql("ALTER TABLE orders ADD COLUMN escrow_token VARCHAR(512)")
        if "escrow_status" not in cols:
            conn.exec_driver_sql("ALTER TABLE orders ADD COLUMN escrow_status VARCHAR(16) DEFAULT 'none'")
        if "escrow_code" not in cols:
            conn.exec_driver_sql("ALTER TABLE orders ADD COLUMN escrow_code VARCHAR(32)")


def _startup():
    Base.metadata.create_all(engine)
    _ensure_sqlite_migrations()
    _assert_pay_internal()

app.router.on_startup.append(_startup)


# Schemas
class RestaurantCreate(BaseModel):
    name: str
    city: Optional[str] = None
    address: Optional[str] = None
    owner_wallet_id: Optional[str] = None


class RestaurantOut(BaseModel):
    id: int
    name: str
    city: Optional[str]
    address: Optional[str]
    owner_wallet_id: Optional[str]
    model_config = ConfigDict(from_attributes=True)


class MenuItemCreate(BaseModel):
    restaurant_id: int
    name: str
    price_cents: int = Field(ge=0)


class MenuItemOut(BaseModel):
    id: int
    restaurant_id: int
    name: str
    price_cents: int
    currency: str
    model_config = ConfigDict(from_attributes=True)


@router.post("/restaurants", response_model=RestaurantOut)
def create_restaurant(req: RestaurantCreate, s: Session = Depends(get_session)):
    r = Restaurant(name=req.name.strip(), city=(req.city or None), address=(req.address or None), owner_wallet_id=(req.owner_wallet_id or None))
    s.add(r); s.commit(); s.refresh(r)
    return r


@router.get("/restaurants", response_model=List[RestaurantOut])
def list_restaurants(q: str = "", city: str = "", limit: int = 50, s: Session = Depends(get_session)):
    stmt = select(Restaurant)
    if q:
        stmt = stmt.where(func.lower(Restaurant.name).like(f"%{q.lower()}%"))
    if city:
        stmt = stmt.where(func.lower(Restaurant.city) == city.lower())
    stmt = stmt.order_by(Restaurant.id.desc()).limit(max(1, min(limit, 200)))
    return s.execute(stmt).scalars().all()


@router.get("/restaurants/{rid}", response_model=RestaurantOut)
def get_restaurant(rid: int, s: Session = Depends(get_session)):
    r = s.get(Restaurant, rid)
    if not r: raise HTTPException(status_code=404, detail="not found")
    return r


@router.post("/menuitems", response_model=MenuItemOut)
def create_menu_item(req: MenuItemCreate, s: Session = Depends(get_session)):
    rest = s.get(Restaurant, req.restaurant_id)
    if not rest: raise HTTPException(status_code=404, detail="restaurant not found")
    mi = MenuItem(restaurant_id=req.restaurant_id, name=req.name.strip(), price_cents=req.price_cents, currency="SYP")
    s.add(mi); s.commit(); s.refresh(mi)
    return mi


@router.get("/restaurants/{rid}/menu", response_model=List[MenuItemOut])
def get_menu(rid: int, s: Session = Depends(get_session)):
    return s.execute(select(MenuItem).where(MenuItem.restaurant_id == rid).order_by(MenuItem.id.asc())).scalars().all()


class OrderItemIn(BaseModel):
    menu_item_id: int
    qty: int = Field(ge=1)


class OrderCreate(BaseModel):
    restaurant_id: int
    customer_name: Optional[str] = None
    customer_phone: Optional[str] = None
    customer_wallet_id: Optional[str] = None
    items: List[OrderItemIn]
    confirm: bool = False


class OrderOut(BaseModel):
    id: str
    restaurant_id: int
    total_cents: int
    status: str
    payments_txn_id: Optional[str]
    escrow_status: Optional[str] = None
    escrow_code: Optional[str] = None
    escrow_token: Optional[str] = None


def _pay(from_wallet: str, to_wallet: str, amount_cents: int, ikey: str, ref: str) -> dict:
    if _use_pay_internal():
        if not (_PaySession and _pay_engine and _pay_transfer and _PayTransferReq):
            raise RuntimeError("payments internal not available")

        class _ReqStub:
            def __init__(self, key: str, reference: str):
                headers = {}
                if key:
                    headers["Idempotency-Key"] = key
                if reference:
                    headers["X-Ref"] = reference
                self.headers = headers

        req_model = _PayTransferReq(from_wallet_id=from_wallet, to_wallet_id=to_wallet, amount_cents=amount_cents)  # type: ignore[call-arg]
        with _PaySession(_pay_engine) as ps:  # type: ignore[call-arg]
            resp = _pay_transfer(req_model, request=_ReqStub(ikey, ref), s=ps)  # type: ignore[call-arg]
        if hasattr(resp, "model_dump"):
            return resp.model_dump()  # type: ignore[return-value]
        if hasattr(resp, "dict"):
            return resp.dict()  # type: ignore[return-value]
        return resp  # type: ignore[return-value]
    raise RuntimeError("payments internal not available")


def _sonic_issue(from_wallet: str, amount_cents: int, ikey: str) -> dict:
    """
    Reserve funds from `from_wallet` using Payments Sonic tokens.
    In dev/monolith mode this uses the internal secret so that the Food
    service can act as a trusted backend.
    """
    if amount_cents <= 0:
        raise HTTPException(status_code=400, detail="invalid amount")
    if not _use_pay_internal():
        raise HTTPException(status_code=500, detail="payments internal not available")
    if not (_PaySession and _pay_engine and _pay_sonic_issue and _PaySonicIssueReq):
        raise RuntimeError("payments internal not available")
    req_model = _PaySonicIssueReq(from_wallet_id=from_wallet, amount_cents=int(amount_cents))  # type: ignore[call-arg]
    with _PaySession(_pay_engine) as ps:  # type: ignore[call-arg]
        resp = _pay_sonic_issue(req_model, s=ps, admin_ok=True)  # type: ignore[call-arg]
    if hasattr(resp, "model_dump"):
        return resp.model_dump()  # type: ignore[return-value]
    if hasattr(resp, "dict"):
        return resp.dict()  # type: ignore[return-value]
    return resp  # type: ignore[return-value]


def _sonic_redeem(token: str, to_wallet: str, ikey: str) -> dict:
    """
    Release previously reserved Sonic funds to the target wallet.
    """
    if not _use_pay_internal():
        raise HTTPException(status_code=500, detail="payments internal not available")
    if not (_PaySession and _pay_engine and _pay_sonic_redeem and _PaySonicRedeemReq):
        raise RuntimeError("payments internal not available")

    class _ReqStub:
        def __init__(self, key: str):
            self.headers = {"Idempotency-Key": key} if key else {}

    req_model = _PaySonicRedeemReq(token=token, to_wallet_id=to_wallet)  # type: ignore[call-arg]
    with _PaySession(_pay_engine) as ps:  # type: ignore[call-arg]
        resp = _pay_sonic_redeem(req_model, request=_ReqStub(ikey), s=ps)  # type: ignore[call-arg]
    if hasattr(resp, "model_dump"):
        return resp.model_dump()  # type: ignore[return-value]
    if hasattr(resp, "dict"):
        return resp.dict()  # type: ignore[return-value]
    return resp  # type: ignore[return-value]


@router.post("/orders", response_model=OrderOut)
def create_order(req: OrderCreate, idempotency_key: Optional[str] = Header(default=None, alias="Idempotency-Key"), s: Session = Depends(get_session)):
    # Idempotency: if key exists, return previous order
    if idempotency_key:
        ie = s.get(Idempotency, idempotency_key)
        if ie and ie.order_id:
            o0 = s.get(Order, ie.order_id)
            if o0:
                return OrderOut(
                    id=o0.id,
                    restaurant_id=o0.restaurant_id,
                    total_cents=o0.total_cents,
                    status=o0.status,
                    payments_txn_id=o0.payments_txn_id,
                    escrow_status=o0.escrow_status,
                    escrow_code=o0.escrow_code,
                    escrow_token=o0.escrow_token,
                )
    rest = s.get(Restaurant, req.restaurant_id)
    if not rest: raise HTTPException(status_code=404, detail="restaurant not found")
    # Load items
    ids = [it.menu_item_id for it in req.items]
    if not ids: raise HTTPException(status_code=400, detail="empty order")
    menu_map = {m.id: m for m in s.execute(select(MenuItem).where(MenuItem.id.in_(ids))).scalars().all()}
    total = 0
    for it in req.items:
        m = menu_map.get(it.menu_item_id)
        if not m: raise HTTPException(status_code=404, detail=f"menu item {it.menu_item_id} not found")
        total += int(m.price_cents) * int(it.qty)
    oid = str(uuid.uuid4())
    pay_txn: Optional[str] = None
    escrow_token: Optional[str] = None
    escrow_code: Optional[str] = None
    escrow_status = "none"
    status = "placed"
    payments_enabled = _use_pay_internal()
    # Escrow reserve via Sonic tokens: keep funds locked until delivery QR scan.
    if (
        req.confirm
        and req.customer_wallet_id
        and rest.owner_wallet_id
        and total > 0
        and payments_enabled
    ):
        try:
            resp = _sonic_issue(
                req.customer_wallet_id,
                total,
                ikey=f"food-escrow-{oid}",
            )
            token = str(resp.get("token") or "")
            code = str(resp.get("code") or "")
            if token:
                escrow_token = token
                escrow_code = code or None
                escrow_status = "reserved"
                status = "accepted"  # accepted once escrow is reserved
        except Exception:
            # Best-effort: if escrow fails, keep order in placed state.
            escrow_token = None
            escrow_code = None
            escrow_status = "none"
            status = "placed"
    o = Order(
        id=oid,
        restaurant_id=rest.id,
        customer_name=req.customer_name,
        customer_phone=req.customer_phone,
        customer_wallet_id=(req.customer_wallet_id or None),
        total_cents=total,
        status=status,
        payments_txn_id=pay_txn,
        escrow_token=escrow_token,
        escrow_status=escrow_status,
        escrow_code=escrow_code,
    )
    s.add(o); s.flush()
    # Persist order items
    for it in req.items:
        m = menu_map[it.menu_item_id]
        s.add(OrderItem(order_id=o.id, menu_item_id=m.id, name=m.name, price_cents=m.price_cents, qty=it.qty))
    # Link idempotency key to order (after items ready)
    if idempotency_key:
        try:
            s.add(Idempotency(key=idempotency_key, order_id=o.id))
        except Exception:
            pass
    s.commit(); s.refresh(o)
    return OrderOut(
        id=o.id,
        restaurant_id=o.restaurant_id,
        total_cents=o.total_cents,
        status=o.status,
        payments_txn_id=o.payments_txn_id,
        escrow_status=o.escrow_status,
        escrow_code=o.escrow_code,
        escrow_token=o.escrow_token,
    )


@router.get("/orders/{oid}", response_model=OrderOut)
def get_order(oid: str, s: Session = Depends(get_session)):
    o = s.get(Order, oid)
    if not o: raise HTTPException(status_code=404, detail="not found")
    return OrderOut(
        id=o.id,
        restaurant_id=o.restaurant_id,
        total_cents=o.total_cents,
        status=o.status,
        payments_txn_id=o.payments_txn_id,
        escrow_status=o.escrow_status,
        escrow_code=o.escrow_code,
        escrow_token=o.escrow_token,
    )


class StatusReq(BaseModel):
    status: str


@router.post("/orders/{oid}/status", response_model=OrderOut)
def set_status(oid: str, req: StatusReq, s: Session = Depends(get_session)):
    o = s.get(Order, oid)
    if not o: raise HTTPException(status_code=404, detail="not found")
    if req.status not in ("accepted","preparing","ready","completed","canceled"):
        raise HTTPException(status_code=400, detail="invalid status")
    o.status = req.status
    s.add(o); s.commit(); s.refresh(o)
    return OrderOut(
        id=o.id,
        restaurant_id=o.restaurant_id,
        total_cents=o.total_cents,
        status=o.status,
        payments_txn_id=o.payments_txn_id,
        escrow_status=o.escrow_status,
        escrow_code=o.escrow_code,
        escrow_token=o.escrow_token,
    )


@router.get("/orders", response_model=List[OrderOut])
def list_orders(phone: str = "", status: str = "", from_iso: str = "", to_iso: str = "", limit: int = 50, s: Session = Depends(get_session)):
    stmt = select(Order)
    if phone:
        stmt = stmt.where(Order.customer_phone == phone)
    if status:
        stmt = stmt.where(Order.status == status)
    # date range best-effort on created_at
    try:
        if from_iso:
            f = datetime.fromisoformat(from_iso.replace('Z','+00:00'))
            stmt = stmt.where(Order.created_at >= f)
        if to_iso:
            t = datetime.fromisoformat(to_iso.replace('Z','+00:00'))
            stmt = stmt.where(Order.created_at <= t)
    except Exception:
        pass
    stmt = stmt.order_by(Order.created_at.desc()).limit(max(1, min(limit, 200)))
    rows = s.execute(stmt).scalars().all()
    return [
        OrderOut(
            id=o.id,
            restaurant_id=o.restaurant_id,
            total_cents=o.total_cents,
            status=o.status,
            payments_txn_id=o.payments_txn_id,
            escrow_status=o.escrow_status,
            escrow_code=o.escrow_code,
            escrow_token=o.escrow_token,
        )
        for o in rows
    ]


class EscrowReleaseReq(BaseModel):
    token: Optional[str] = None


@router.post("/orders/{oid}/escrow_release", response_model=OrderOut)
def escrow_release(oid: str, req: EscrowReleaseReq, s: Session = Depends(get_session)):
    """
    Release escrow for a food order once the customer has scanned
    the courier's delivery QR code. This redeems the Sonic token
    and credits the restaurant owner's wallet.
    """
    o = s.get(Order, oid)
    if not o:
        raise HTTPException(status_code=404, detail="not found")
    if not o.escrow_token:
        raise HTTPException(status_code=400, detail="no escrow for order")
    if o.escrow_status == "released":
        return OrderOut(
            id=o.id,
            restaurant_id=o.restaurant_id,
            total_cents=o.total_cents,
            status=o.status,
            payments_txn_id=o.payments_txn_id,
            escrow_status=o.escrow_status,
            escrow_code=o.escrow_code,
            escrow_token=o.escrow_token,
        )
    if req.token and req.token != o.escrow_token:
        raise HTTPException(status_code=400, detail="token mismatch")
    rest = s.get(Restaurant, o.restaurant_id)
    if not rest or not rest.owner_wallet_id:
        raise HTTPException(status_code=400, detail="restaurant wallet missing")
    if not _use_pay_internal():
        raise HTTPException(status_code=500, detail="payments internal not available")
    try:
        _sonic_redeem(
            o.escrow_token,
            rest.owner_wallet_id,
            ikey=f"food-escrow-redeem-{oid}",
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))
    o.escrow_status = "released"
    o.status = "completed"
    s.add(o)
    s.commit()
    s.refresh(o)
    return OrderOut(
        id=o.id,
        restaurant_id=o.restaurant_id,
        total_cents=o.total_cents,
        status=o.status,
        payments_txn_id=o.payments_txn_id,
        escrow_status=o.escrow_status,
        escrow_code=o.escrow_code,
        escrow_token=o.escrow_token,
    )


app.include_router(router)
