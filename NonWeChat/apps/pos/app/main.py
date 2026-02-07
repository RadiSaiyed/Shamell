import os
import uuid
import json
import asyncio
import base64
from datetime import datetime, date
from typing import List, Optional, Set

from fastapi import FastAPI, APIRouter, HTTPException, Depends, Response, WebSocket, WebSocketDisconnect
from pydantic import BaseModel, Field, ConfigDict
from sqlalchemy import (
    create_engine,
    String,
    Integer,
    BigInteger,
    DateTime,
    Date,
    Float,
    func,
    select,
    text,
)
from sqlalchemy.orm import DeclarativeBase, Session, Mapped, mapped_column

from shamell_shared import RequestIDMiddleware, configure_cors, add_standard_health, setup_json_logging


def _env_or(key: str, default: str) -> str:
    v = os.getenv(key)
    return v if v is not None else default


DB_URL = _env_or("POS_DB_URL", "sqlite+pysqlite:////tmp/pos.db")
DB_SCHEMA = os.getenv("DB_SCHEMA") if not DB_URL.startswith("sqlite") else None
PAYMENTS_BASE = os.getenv("PAYMENTS_BASE_URL", "")

app = FastAPI(title="POS API", version="0.1.0")
setup_json_logging()
app.add_middleware(RequestIDMiddleware)
configure_cors(app, os.getenv("ALLOWED_ORIGINS", "*"))
add_standard_health(app)
router = APIRouter()


class Base(DeclarativeBase):
    pass


class Item(Base):
    __tablename__ = "items"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(200))
    price_cents: Mapped[int] = mapped_column(BigInteger, default=0)
    currency: Mapped[str] = mapped_column(String(3), default="SYP")
    category: Mapped[Optional[str]] = mapped_column(String(80), default=None)
    description: Mapped[Optional[str]] = mapped_column(String(400), default=None)
    image_url: Mapped[Optional[str]] = mapped_column(String(400), default=None)
    allergens_json: Mapped[Optional[str]] = mapped_column(String(400), default=None)
    diet_tags_json: Mapped[Optional[str]] = mapped_column(String(400), default=None)
    service_charge_pct: Mapped[float] = mapped_column(Float, default=0.0)
    tax_pct: Mapped[float] = mapped_column(Float, default=0.0)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())
    combo_json: Mapped[Optional[str]] = mapped_column(String(400), default=None)  # list of item_ids
    is_combo: Mapped[int] = mapped_column(Integer, default=0)
    combo_price_cents: Mapped[Optional[int]] = mapped_column(BigInteger, default=None)
    modifier_groups_json: Mapped[Optional[str]] = mapped_column(String(400), default=None)


class Modifier(Base):
    __tablename__ = "modifiers"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    item_id: Mapped[int] = mapped_column(Integer)
    name: Mapped[str] = mapped_column(String(120))
    price_cents: Mapped[int] = mapped_column(BigInteger, default=0)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class ModifierGroup(Base):
    __tablename__ = "modifier_groups"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(120))
    required: Mapped[int] = mapped_column(Integer, default=0)
    min_choices: Mapped[int] = mapped_column(Integer, default=0)
    max_choices: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class ModifierOption(Base):
    __tablename__ = "modifier_options"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    group_id: Mapped[int] = mapped_column(Integer)
    name: Mapped[str] = mapped_column(String(120))
    price_cents: Mapped[int] = mapped_column(BigInteger, default=0)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class InventoryItem(Base):
    __tablename__ = "inventory_items"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(200))
    unit: Mapped[str] = mapped_column(String(32), default="unit")
    stock_qty: Mapped[float] = mapped_column(Float, default=0.0)
    low_stock_threshold: Mapped[Optional[float]] = mapped_column(Float, default=None)
    batch_control: Mapped[bool] = mapped_column(Integer, default=0)
    purchase_price_cents: Mapped[int] = mapped_column(BigInteger, default=0)
    mhd: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class InventoryMovement(Base):
    __tablename__ = "inventory_movements"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    inventory_item_id: Mapped[int] = mapped_column(Integer)
    qty: Mapped[float] = mapped_column(Float)
    reason: Mapped[str] = mapped_column(String(64), default="adjustment")
    note: Mapped[Optional[str]] = mapped_column(String(200), default=None)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())
    batch_code: Mapped[Optional[str]] = mapped_column(String(80), default=None)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class RecipeLine(Base):
    __tablename__ = "recipe_lines"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    item_id: Mapped[int] = mapped_column(Integer)
    inventory_item_id: Mapped[int] = mapped_column(Integer)
    qty: Mapped[float] = mapped_column(Float)
    unit_cost_cents: Mapped[int] = mapped_column(BigInteger, default=0)


class Supplier(Base):
    __tablename__ = "suppliers"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(200))
    contact: Mapped[Optional[str]] = mapped_column(String(120), default=None)
    phone: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class PurchaseOrder(Base):
    __tablename__ = "purchase_orders"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    supplier_id: Mapped[int] = mapped_column(Integer)
    status: Mapped[str] = mapped_column(String(32), default="open")  # open/received/canceled
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class PurchaseOrderLine(Base):
    __tablename__ = "purchase_order_lines"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    po_id: Mapped[int] = mapped_column(Integer)
    inventory_item_id: Mapped[int] = mapped_column(Integer)
    qty: Mapped[float] = mapped_column(Float)
    price_cents: Mapped[int] = mapped_column(BigInteger, default=0)
    currency: Mapped[str] = mapped_column(String(3), default="SYP")


class Table(Base):
    __tablename__ = "tables"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(50))
    capacity: Mapped[int] = mapped_column(Integer, default=2)
    status: Mapped[str] = mapped_column(String(16), default="free")  # free/occupied/cleaning/held


class Reservation(Base):
    __tablename__ = "reservations"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    table_id: Mapped[int] = mapped_column(Integer)
    guest_name: Mapped[str] = mapped_column(String(120))
    guest_phone: Mapped[Optional[str]] = mapped_column(String(32), default=None)
    from_ts: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True))
    to_ts: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True))
    status: Mapped[str] = mapped_column(String(24), default="booked")
    party_size: Mapped[Optional[int]] = mapped_column(Integer, default=None)
    note: Mapped[Optional[str]] = mapped_column(String(200), default=None)


class Order(Base):
    __tablename__ = "orders"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    table_id: Mapped[Optional[int]] = mapped_column(Integer, default=None)
    status: Mapped[str] = mapped_column(String(24), default="open")  # open/paid/canceled/voided
    total_cents: Mapped[int] = mapped_column(BigInteger, default=0)
    tax_cents: Mapped[int] = mapped_column(BigInteger, default=0)
    tax_pct: Mapped[float] = mapped_column(Float, default=0.0)
    service_pct: Mapped[float] = mapped_column(Float, default=0.0)
    discount_cents: Mapped[int] = mapped_column(BigInteger, default=0)
    currency: Mapped[str] = mapped_column(String(3), default="SYP")
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())
    tip_cents: Mapped[int] = mapped_column(BigInteger, default=0)
    payment_method: Mapped[Optional[str]] = mapped_column(String(32), default=None)
    paid_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True))
    device_id: Mapped[Optional[str]] = mapped_column(String(64), default=None)


class OrderLine(Base):
    __tablename__ = "order_lines"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    order_id: Mapped[str] = mapped_column(String(36))
    item_id: Mapped[int] = mapped_column(Integer)
    qty: Mapped[int] = mapped_column(Integer, default=1)
    price_cents: Mapped[int] = mapped_column(BigInteger, default=0)
    discount_cents: Mapped[int] = mapped_column(BigInteger, default=0)
    service_pct: Mapped[float] = mapped_column(Float, default=0.0)
    tax_pct: Mapped[float] = mapped_column(Float, default=0.0)
    note: Mapped[Optional[str]] = mapped_column(String(200), default=None)
    modifiers_json: Mapped[Optional[str]] = mapped_column(String(400), default=None)
    course: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    station: Mapped[Optional[str]] = mapped_column(String(64), default=None)


class KitchenTicket(Base):
    __tablename__ = "kitchen_tickets"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    order_id: Mapped[str] = mapped_column(String(36))
    status: Mapped[str] = mapped_column(String(24), default="new")  # new/doing/done/fire/recall
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())
    station: Mapped[Optional[str]] = mapped_column(String(64), default=None)


class Shift(Base):
    __tablename__ = "shifts"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    device_id: Mapped[str] = mapped_column(String(64), default="POS")
    opened_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())
    closed_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True))
    opening_cash_cents: Mapped[int] = mapped_column(BigInteger, default=0)
    closing_cash_cents: Mapped[int] = mapped_column(BigInteger, default=0)
    counted_cash_cents: Mapped[int] = mapped_column(BigInteger, default=0)
    note: Mapped[Optional[str]] = mapped_column(String(240), default=None)


class ServiceRule(Base):
    __tablename__ = "service_rules"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    rule_type: Mapped[str] = mapped_column(String(16), default="service")  # service/discount
    pct: Mapped[float] = mapped_column(Float, default=0.0)
    table_id: Mapped[Optional[int]] = mapped_column(Integer, default=None)
    device_id: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    start_minute: Mapped[Optional[int]] = mapped_column(Integer, default=None)  # minutes since midnight
    end_minute: Mapped[Optional[int]] = mapped_column(Integer, default=None)
    days_mask: Mapped[Optional[int]] = mapped_column(Integer, default=None)  # bitmask for weekday


class PrinterConfig(Base):
    __tablename__ = "printers"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(120))
    station: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    driver: Mapped[str] = mapped_column(String(32), default="escpos")  # escpos/pdf
    target: Mapped[str] = mapped_column(String(200))  # e.g., URL or file
    layout_json: Mapped[Optional[str]] = mapped_column(String(2000), default=None)
    char_width: Mapped[int] = mapped_column(Integer, default=32)


class PrinterJob(Base):
    __tablename__ = "printer_jobs"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    printer_id: Mapped[int] = mapped_column(Integer)
    order_id: Mapped[str] = mapped_column(String(36))
    payload_json: Mapped[str] = mapped_column(String(4000))
    status: Mapped[str] = mapped_column(String(16), default="queued")
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), onupdate=func.now())
    retry_count: Mapped[int] = mapped_column(Integer, default=0)
    last_error: Mapped[Optional[str]] = mapped_column(String(400), default=None)


class PaymentRecord(Base):
    __tablename__ = "payments"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    order_id: Mapped[str] = mapped_column(String(36))
    amount_cents: Mapped[int] = mapped_column(BigInteger, default=0)
    method: Mapped[str] = mapped_column(String(32), default="cash")
    status: Mapped[str] = mapped_column(String(16), default="captured")
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Waitlist(Base):
    __tablename__ = "waitlist"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    guest_name: Mapped[str] = mapped_column(String(120))
    phone: Mapped[Optional[str]] = mapped_column(String(32), default=None)
    party_size: Mapped[int] = mapped_column(Integer, default=2)
    status: Mapped[str] = mapped_column(String(16), default="waiting")  # waiting/seated/canceled
    table_id: Mapped[Optional[int]] = mapped_column(Integer, default=None)
    note: Mapped[Optional[str]] = mapped_column(String(200), default=None)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class WaitlistCreate(BaseModel):
    guest_name: str
    phone: Optional[str] = None
    party_size: int = 2
    note: Optional[str] = None


class WaitlistOut(BaseModel):
    id: int
    guest_name: str
    phone: Optional[str]
    party_size: int
    status: str
    table_id: Optional[int]
    note: Optional[str]
    created_at: Optional[datetime]
    model_config = ConfigDict(from_attributes=True)


engine = create_engine(DB_URL, future=True)
active_sockets: Set[WebSocket] = set()


async def _broadcast(msg: dict):
    for ws in list(active_sockets):
        try:
            await ws.send_json(msg)
        except Exception:
            try:
                active_sockets.remove(ws)
            except KeyError:
                pass


def _queue_broadcast(msg: dict):
    try:
        loop = asyncio.get_event_loop()
        loop.create_task(_broadcast(msg))
    except RuntimeError:
        # no running loop
        pass


def get_session():
    with Session(engine) as s:
        yield s


def on_startup():
    Base.metadata.create_all(engine)
    # lightweight migrations for new columns
    from sqlalchemy import inspect, text
    insp = inspect(engine)
    if insp.has_table("orders", schema=DB_SCHEMA):
        cols = {c["name"] for c in insp.get_columns("orders", schema=DB_SCHEMA)}
        tbl = f'{"%s." % DB_SCHEMA if DB_SCHEMA else ""}orders'
        if "tax_cents" not in cols:
            try:
                with engine.begin() as conn:
                    conn.execute(text(f"ALTER TABLE {tbl} ADD COLUMN tax_cents BIGINT DEFAULT 0"))
            except Exception:
                pass
        if "tax_pct" not in cols:
            try:
                with engine.begin() as conn:
                    conn.execute(text(f"ALTER TABLE {tbl} ADD COLUMN tax_pct FLOAT DEFAULT 0.0"))
            except Exception:
                pass
        if "service_pct" not in cols:
            try:
                with engine.begin() as conn:
                    conn.execute(text(f"ALTER TABLE {tbl} ADD COLUMN service_pct FLOAT DEFAULT 0.0"))
            except Exception:
                pass
        if "discount_cents" not in cols:
            try:
                with engine.begin() as conn:
                    conn.execute(text(f"ALTER TABLE {tbl} ADD COLUMN discount_cents BIGINT DEFAULT 0"))
            except Exception:
                pass
        for col, ddl in [
            ("is_combo", "INTEGER DEFAULT 0"),
            ("combo_price_cents", "BIGINT"),
        ]:
            if col not in cols:
                try:
                    with engine.begin() as conn:
                        conn.execute(text(f"ALTER TABLE {tbl} ADD COLUMN {col} {ddl}"))
                except Exception:
                    pass
        for col, ddl in [
            ("tip_cents", "BIGINT DEFAULT 0"),
            ("payment_method", "VARCHAR(32)"),
            ("paid_at", "TIMESTAMP"),
            ("device_id", "VARCHAR(64)"),
        ]:
            if col not in cols:
                try:
                    with engine.begin() as conn:
                        conn.execute(text(f"ALTER TABLE {tbl} ADD COLUMN {col} {ddl}"))
                except Exception:
                    pass
    if insp.has_table("order_lines", schema=DB_SCHEMA):
        cols = {c["name"] for c in insp.get_columns("order_lines", schema=DB_SCHEMA)}
        tbl = f'{"%s." % DB_SCHEMA if DB_SCHEMA else ""}order_lines'
        for col, ddl in [
            ("discount_cents", "BIGINT DEFAULT 0"),
            ("service_pct", "FLOAT DEFAULT 0.0"),
            ("tax_pct", "FLOAT DEFAULT 0.0"),
            ("course", "VARCHAR(64)"),
            ("station", "VARCHAR(64)"),
        ]:
            if col not in cols:
                try:
                    with engine.begin() as conn:
                        conn.execute(text(f"ALTER TABLE {tbl} ADD COLUMN {col} {ddl}"))
                except Exception:
                    pass
    if insp.has_table("shifts", schema=DB_SCHEMA) is False:
        Shift.__table__.create(engine)
    for model, name in [
        (ModifierGroup, "modifier_groups"),
        (ModifierOption, "modifier_options"),
        (ServiceRule, "service_rules"),
        (PaymentRecord, "payments"),
        (Waitlist, "waitlist"),
        (PrinterConfig, "printers"),
        (PrinterJob, "printer_jobs"),
    ]:
        if insp.has_table(name, schema=DB_SCHEMA) is False:
            model.__table__.create(engine)
    if insp.has_table("items", schema=DB_SCHEMA):
        cols = {c["name"] for c in insp.get_columns("items", schema=DB_SCHEMA)}
        tbl = f'{"%s." % DB_SCHEMA if DB_SCHEMA else ""}items'
        for col, ddl in [
            ("image_url", "VARCHAR(400)"),
            ("allergens_json", "VARCHAR(400)"),
            ("diet_tags_json", "VARCHAR(400)"),
        ]:
            if col not in cols:
                try:
                    with engine.begin() as conn:
                        conn.execute(text(f"ALTER TABLE {tbl} ADD COLUMN {col} {ddl}"))
                except Exception:
                    pass
    if insp.has_table("tables", schema=DB_SCHEMA):
        cols = {c["name"] for c in insp.get_columns("tables", schema=DB_SCHEMA)}
        tbl = f'{"%s." % DB_SCHEMA if DB_SCHEMA else ""}tables'
        if "status" not in cols:
            try:
                with engine.begin() as conn:
                    conn.execute(text(f"ALTER TABLE {tbl} ADD COLUMN status VARCHAR(16) DEFAULT 'free'"))
            except Exception:
                pass
    if insp.has_table("reservations", schema=DB_SCHEMA):
        cols = {c["name"] for c in insp.get_columns("reservations", schema=DB_SCHEMA)}
        tbl = f'{"%s." % DB_SCHEMA if DB_SCHEMA else ""}reservations'
        for col, ddl in [("party_size", "INTEGER"), ("note", "VARCHAR(200)")]:
            if col not in cols:
                try:
                    with engine.begin() as conn:
                        conn.execute(text(f"ALTER TABLE {tbl} ADD COLUMN {col} {ddl}"))
                except Exception:
                    pass
    if insp.has_table("printers", schema=DB_SCHEMA):
        cols = {c["name"] for c in insp.get_columns("printers", schema=DB_SCHEMA)}
        tbl = f'{"%s." % DB_SCHEMA if DB_SCHEMA else ""}printers'
        if "char_width" not in cols:
            try:
                with engine.begin() as conn:
                    conn.execute(text(f"ALTER TABLE {tbl} ADD COLUMN char_width INTEGER DEFAULT 32"))
            except Exception:
                pass
    if insp.has_table("printer_jobs", schema=DB_SCHEMA):
        cols = {c["name"] for c in insp.get_columns("printer_jobs", schema=DB_SCHEMA)}
        tbl = f'{"%s." % DB_SCHEMA if DB_SCHEMA else ""}printer_jobs'
        if "retry_count" not in cols:
            try:
                with engine.begin() as conn:
                    conn.execute(text(f"ALTER TABLE {tbl} ADD COLUMN retry_count INTEGER DEFAULT 0"))
            except Exception:
                pass
        if "last_error" not in cols:
            try:
                with engine.begin() as conn:
                    conn.execute(text(f"ALTER TABLE {tbl} ADD COLUMN last_error VARCHAR(400)"))
            except Exception:
                pass


app.router.on_startup.append(on_startup)


# --- Schemas ---
class ItemCreate(BaseModel):
    name: str
    price_cents: int = Field(ge=0)
    currency: str = Field(default="SYP", min_length=3, max_length=3)
    category: Optional[str] = None
    description: Optional[str] = None
    image_url: Optional[str] = None
    allergens: List[str] = Field(default_factory=list)
    diet_tags: List[str] = Field(default_factory=list)
    modifiers: List[str] = Field(default_factory=list)
    service_charge_pct: float = 0.0
    tax_pct: float = 0.0
    combo_item_ids: List[int] = Field(default_factory=list)
    combo_price_cents: Optional[int] = None
    modifier_group_ids: List[int] = Field(default_factory=list)


class ItemOut(BaseModel):
    id: int
    name: str
    price_cents: int
    currency: str
    category: Optional[str]
    description: Optional[str]
    modifier_groups_json: Optional[str]
    image_url: Optional[str]
    allergens_json: Optional[str]
    diet_tags_json: Optional[str]
    model_config = ConfigDict(from_attributes=True)


@router.post("/items", response_model=ItemOut)
def create_item(req: ItemCreate, s: Session = Depends(get_session)):
    it = Item(
        name=req.name.strip(),
        price_cents=req.price_cents,
        currency=req.currency,
        category=req.category,
        description=req.description,
        image_url=req.image_url,
        allergens_json=json.dumps(req.allergens),
        diet_tags_json=json.dumps(req.diet_tags),
        service_charge_pct=req.service_charge_pct,
        tax_pct=req.tax_pct,
        combo_json=json.dumps(req.combo_item_ids),
        is_combo=1 if req.combo_item_ids else 0,
        combo_price_cents=req.combo_price_cents,
        modifier_groups_json=json.dumps(req.modifier_group_ids),
    )
    s.add(it); s.commit(); s.refresh(it)
    for m in req.modifiers:
        if not m.strip():
            continue
        s.add(Modifier(item_id=it.id, name=m.strip(), price_cents=0))
    s.commit()
    return it


@router.get("/items", response_model=List[ItemOut])
def list_items(q: str = "", category: str = "", limit: int = 100, s: Session = Depends(get_session)):
    stmt = select(Item)
    if q:
        stmt = stmt.where(func.lower(Item.name).like(f"%{q.lower()}%"))
    if category:
        stmt = stmt.where(func.lower(Item.category) == category.lower())
    stmt = stmt.order_by(Item.id.desc()).limit(max(1, min(limit, 500)))
    return s.execute(stmt).scalars().all()


class ModifierGroupCreate(BaseModel):
    name: str
    required: bool = False
    min_choices: int = 0
    max_choices: int = 0
    options: List[str] = Field(default_factory=list)


class ModifierGroupOut(BaseModel):
    id: int
    name: str
    required: bool
    min_choices: int
    max_choices: int
    options: List[dict]
    model_config = ConfigDict(from_attributes=True)


@router.post("/modifier-groups", response_model=ModifierGroupOut)
def create_modifier_group(req: ModifierGroupCreate, s: Session = Depends(get_session)):
    mg = ModifierGroup(
        name=req.name,
        required=1 if req.required else 0,
        min_choices=req.min_choices,
        max_choices=req.max_choices,
    )
    s.add(mg); s.commit(); s.refresh(mg)
    opts = []
    for opt in req.options:
        o = ModifierOption(group_id=mg.id, name=opt.strip(), price_cents=0)
        s.add(o); opts.append(o)
    s.commit()
    return ModifierGroupOut(
        id=mg.id,
        name=mg.name,
        required=bool(mg.required),
        min_choices=mg.min_choices,
        max_choices=mg.max_choices,
        options=[{"id": o.id, "name": o.name, "price_cents": o.price_cents} for o in opts],
    )


@router.get("/modifier-groups", response_model=List[ModifierGroupOut])
def list_modifier_groups(s: Session = Depends(get_session)):
    groups = s.execute(select(ModifierGroup)).scalars().all()
    opts = s.execute(select(ModifierOption)).scalars().all()
    opt_by_group = {}
    for o in opts:
        opt_by_group.setdefault(o.group_id, []).append(o)
    out = []
    for g in groups:
        out.append(
            ModifierGroupOut(
                id=g.id,
                name=g.name,
                required=bool(g.required),
                min_choices=g.min_choices,
                max_choices=g.max_choices,
                options=[{"id": o.id, "name": o.name, "price_cents": o.price_cents} for o in opt_by_group.get(g.id, [])],
            )
        )
    return out


class InventoryItemCreate(BaseModel):
    name: str
    unit: str = "unit"
    stock_qty: float = 0.0
    low_stock_threshold: Optional[float] = None
    batch_control: bool = False
    purchase_price_cents: int = 0
    mhd: Optional[str] = None


class InventoryItemOut(BaseModel):
    id: int
    name: str
    unit: str
    stock_qty: float
    low_stock_threshold: Optional[float]
    model_config = ConfigDict(from_attributes=True)


@router.post("/inventory/items", response_model=InventoryItemOut)
def create_inventory_item(req: InventoryItemCreate, s: Session = Depends(get_session)):
    inv = InventoryItem(
        name=req.name.strip(),
        unit=req.unit,
        stock_qty=req.stock_qty,
        low_stock_threshold=req.low_stock_threshold,
        batch_control=1 if req.batch_control else 0,
        purchase_price_cents=req.purchase_price_cents,
        mhd=req.mhd,
    )
    s.add(inv); s.commit(); s.refresh(inv)
    return inv


@router.get("/inventory/items", response_model=List[InventoryItemOut])
def list_inventory_items(q: str = "", s: Session = Depends(get_session)):
    stmt = select(InventoryItem)
    if q:
        stmt = stmt.where(func.lower(InventoryItem.name).like(f"%{q.lower()}%"))
    stmt = stmt.order_by(InventoryItem.id.desc())
    return s.execute(stmt).scalars().all()


class MovementCreate(BaseModel):
    inventory_item_id: int
    qty: float
    reason: str = "adjustment"
    note: Optional[str] = None
    batch_code: Optional[str] = None


@router.post("/inventory/movements", response_model=InventoryItemOut)
def create_movement(req: MovementCreate, s: Session = Depends(get_session)):
    inv = s.get(InventoryItem, req.inventory_item_id)
    if not inv:
        raise HTTPException(status_code=404, detail="inventory item not found")
    inv.stock_qty = (inv.stock_qty or 0) + req.qty
    mv = InventoryMovement(
        inventory_item_id=req.inventory_item_id,
        qty=req.qty,
        reason=req.reason,
        note=req.note,
        batch_code=req.batch_code,
    )
    s.add(mv); s.add(inv); s.commit(); s.refresh(inv)
    return inv


class RecipeLineCreate(BaseModel):
    inventory_item_id: int
    qty: float
    unit_cost_cents: int = 0


@router.post("/recipes/{item_id}")
def set_recipe(item_id: int, lines: List[RecipeLineCreate], s: Session = Depends(get_session)):
    s.query(RecipeLine).filter(RecipeLine.item_id == item_id).delete()
    for ln in lines:
        rl = RecipeLine(
            item_id=item_id,
            inventory_item_id=ln.inventory_item_id,
            qty=ln.qty,
            unit_cost_cents=ln.unit_cost_cents,
        )
        s.add(rl)
    s.commit()
    return {"ok": True}


class SupplierCreate(BaseModel):
    name: str
    contact: Optional[str] = None
    phone: Optional[str] = None


class SupplierOut(BaseModel):
    id: int
    name: str
    contact: Optional[str]
    phone: Optional[str]
    model_config = ConfigDict(from_attributes=True)


@router.post("/suppliers", response_model=SupplierOut)
def create_supplier(req: SupplierCreate, s: Session = Depends(get_session)):
    sp = Supplier(name=req.name.strip(), contact=req.contact, phone=req.phone)
    s.add(sp); s.commit(); s.refresh(sp)
    return sp


@router.get("/suppliers", response_model=List[SupplierOut])
def list_suppliers(s: Session = Depends(get_session)):
    return s.execute(select(Supplier).order_by(Supplier.id.desc())).scalars().all()


class POLineCreate(BaseModel):
    inventory_item_id: int
    qty: float
    price_cents: int = 0
    currency: str = "SYP"


class POCreate(BaseModel):
    supplier_id: int
    lines: List[POLineCreate]


@router.post("/procurement/orders")
def create_po(req: POCreate, s: Session = Depends(get_session)):
    po = PurchaseOrder(supplier_id=req.supplier_id, status="open")
    s.add(po); s.commit(); s.refresh(po)
    for ln in req.lines:
        pol = PurchaseOrderLine(
            po_id=po.id,
            inventory_item_id=ln.inventory_item_id,
            qty=ln.qty,
            price_cents=ln.price_cents,
            currency=ln.currency,
        )
        s.add(pol)
    s.commit()
    return {"id": po.id, "status": po.status}


@router.post("/procurement/orders/{po_id}/receive")
def receive_po(po_id: int, s: Session = Depends(get_session)):
    po = s.get(PurchaseOrder, po_id)
    if not po:
        raise HTTPException(status_code=404, detail="po not found")
    po.status = "received"
    lines = s.execute(select(PurchaseOrderLine).where(PurchaseOrderLine.po_id == po_id)).scalars().all()
    for ln in lines:
        inv = s.get(InventoryItem, ln.inventory_item_id)
        if inv:
            inv.stock_qty = (inv.stock_qty or 0) + ln.qty
            mv = InventoryMovement(
                inventory_item_id=inv.id,
                qty=ln.qty,
                reason="po_receive",
                note=f"PO {po_id}",
            )
            s.add(mv); s.add(inv)
    s.add(po); s.commit()
    return {"ok": True}


class TableCreate(BaseModel):
    name: str
    capacity: int = 2


class TableUpdate(BaseModel):
    name: Optional[str] = None
    capacity: Optional[int] = None
    status: Optional[str] = None


class TableOut(BaseModel):
    id: int
    name: str
    capacity: int
    status: str
    model_config = ConfigDict(from_attributes=True)


@router.post("/tables", response_model=TableOut)
def create_table(req: TableCreate, s: Session = Depends(get_session)):
    t = Table(name=req.name.strip(), capacity=req.capacity)
    s.add(t); s.commit(); s.refresh(t)
    return t


@router.get("/tables", response_model=List[TableOut])
def list_tables(s: Session = Depends(get_session)):
    return s.execute(select(Table).order_by(Table.id.asc())).scalars().all()


@router.post("/tables/{tid}", response_model=TableOut)
def update_table(tid: int, req: TableUpdate, s: Session = Depends(get_session)):
    t = s.get(Table, tid)
    if not t:
        raise HTTPException(status_code=404, detail="not found")
    if req.name:
        t.name = req.name
    if req.capacity is not None:
        t.capacity = req.capacity
    if req.status:
        t.status = req.status
    s.commit(); s.refresh(t)
    return t


class ReservationCreate(BaseModel):
    table_id: int
    guest_name: str
    guest_phone: Optional[str] = None
    from_iso: str
    to_iso: str
    party_size: Optional[int] = None
    note: Optional[str] = None


class ReservationOut(BaseModel):
    id: int
    table_id: int
    guest_name: str
    guest_phone: Optional[str]
    from_ts: Optional[datetime]
    to_ts: Optional[datetime]
    status: str
    party_size: Optional[int]
    note: Optional[str]
    model_config = ConfigDict(from_attributes=True)


@router.post("/reservations", response_model=ReservationOut)
def create_reservation(req: ReservationCreate, s: Session = Depends(get_session)):
    try:
        f = datetime.fromisoformat(req.from_iso)
        t = datetime.fromisoformat(req.to_iso)
    except Exception:
        raise HTTPException(status_code=400, detail="invalid time")
    res = Reservation(
        table_id=req.table_id,
        guest_name=req.guest_name.strip(),
        guest_phone=req.guest_phone,
        from_ts=f,
        to_ts=t,
        status="booked",
        party_size=req.party_size,
        note=req.note,
    )
    s.add(res); s.commit(); s.refresh(res)
    return res


@router.get("/reservations", response_model=List[ReservationOut])
def list_reservations(s: Session = Depends(get_session)):
    return s.execute(select(Reservation).order_by(Reservation.id.desc())).scalars().all()


class OrderLineIn(BaseModel):
    item_id: int
    qty: int = Field(ge=1)
    note: Optional[str] = None
    modifiers: List[int] = Field(default_factory=list)  # option ids
    discount_cents: int = 0
    service_pct: float = 0.0
    tax_pct: float = 0.0
    course: Optional[str] = None
    station: Optional[str] = None


class OrderCreate(BaseModel):
    table_id: Optional[int] = None
    currency: str = "SYP"
    tax_pct: float = 0.0
    service_pct: float = 0.0
    discount_cents: int = 0
    device_id: Optional[str] = None
    lines: List[OrderLineIn]


class OrderOut(BaseModel):
    id: str
    table_id: Optional[int]
    status: str
    total_cents: int
    tax_cents: int
    tax_pct: float
    service_pct: float
    discount_cents: int
    tip_cents: int
    payment_method: Optional[str]
    paid_at: Optional[datetime]
    currency: str
    paid_cents: Optional[int] = None
    remaining_cents: Optional[int] = None
    model_config = ConfigDict(from_attributes=True)


class OrderLineOut(BaseModel):
    id: int
    item_id: int
    qty: int
    price_cents: int
    discount_cents: int
    service_pct: float
    tax_pct: float
    note: Optional[str]
    modifiers: List[int]
    course: Optional[str]
    station: Optional[str]
    model_config = ConfigDict(from_attributes=True)

    @classmethod
    def from_db(cls, ln: OrderLine):
        return cls(
            id=ln.id,
            item_id=ln.item_id,
            qty=ln.qty,
            price_cents=ln.price_cents,
            discount_cents=ln.discount_cents,
            service_pct=ln.service_pct,
            tax_pct=ln.tax_pct,
            note=ln.note,
            modifiers=json.loads(ln.modifiers_json or "[]"),
            course=ln.course,
            station=ln.station,
        )


class OrderDetail(BaseModel):
    order: OrderOut
    lines: List[OrderLineOut]


@router.post("/orders", response_model=OrderOut)
def create_order(req: OrderCreate, s: Session = Depends(get_session)):
    if not req.lines:
        raise HTTPException(status_code=400, detail="no lines")
    items = {i.id: i for i in s.execute(select(Item)).scalars().all()}
    mods = {}
    for m in s.execute(select(Modifier)).scalars().all():
        mods.setdefault(m.item_id, []).append(m)
    options = {o.id: o for o in s.execute(select(ModifierOption)).scalars().all()}
    total = 0
    for ln in req.lines:
        it = items.get(ln.item_id)
        if not it:
            raise HTTPException(status_code=404, detail=f"item {ln.item_id} not found")
        mod_price = 0
        for mid in ln.modifiers:
            if mid in options:
                mod_price += options[mid].price_cents or 0
            else:
                maybe = [m for m in mods.get(ln.item_id, []) if m.id == mid]
                if maybe:
                    mod_price += maybe[0].price_cents or 0
        base_price = it.combo_price_cents if (it.is_combo and it.combo_price_cents is not None) else it.price_cents
        line_base = ((base_price or 0) + mod_price) * ln.qty
        line_service = int(line_base * (ln.service_pct / 100.0)) if ln.service_pct > 0 else 0
        line_tax = int(line_base * (ln.tax_pct / 100.0)) if ln.tax_pct > 0 else 0
        line_discount = max(0, ln.discount_cents)
        total += line_base + line_service + line_tax - line_discount
    # apply rules
    now = datetime.utcnow()
    minute = now.hour * 60 + now.minute
    weekday_mask = 1 << now.weekday()
    rules = s.execute(select(ServiceRule)).scalars().all()
    extra_service = 0.0
    extra_discount = 0.0
    for r in rules:
        if r.table_id and req.table_id and r.table_id != req.table_id:
            continue
        if r.device_id and req.device_id and r.device_id != req.device_id:
            continue
        if r.start_minute is not None and r.end_minute is not None:
            if not (r.start_minute <= minute <= r.end_minute):
                continue
        if r.days_mask is not None and (r.days_mask & weekday_mask) == 0:
            continue
        if r.rule_type == "service":
            extra_service += r.pct
        elif r.rule_type == "discount":
            extra_discount += r.pct
    eff_service_pct = req.service_pct + extra_service
    eff_discount_pct = extra_discount
    tax_cents = int(total * (req.tax_pct / 100.0)) if req.tax_pct > 0 else 0
    service_cents = int(total * (eff_service_pct / 100.0)) if eff_service_pct > 0 else 0
    auto_discount = int(total * (eff_discount_pct / 100.0)) if eff_discount_pct > 0 else 0
    total_after = total + tax_cents + service_cents - max(0, req.discount_cents)
    total_after -= auto_discount
    total_after = max(0, total_after)
    order_id = str(uuid.uuid4())
    od = Order(
        id=order_id,
        table_id=req.table_id,
        status="open",
        total_cents=total_after,
        tax_cents=tax_cents,
        tax_pct=req.tax_pct,
        service_pct=eff_service_pct,
        discount_cents=max(0, req.discount_cents),
        currency=req.currency,
        device_id=req.device_id,
    )
    s.add(od); s.commit()
    stations_for_routing = set()
    for ln in req.lines:
        it = items[ln.item_id]
        base_price = it.combo_price_cents if (it.is_combo and it.combo_price_cents is not None) else it.price_cents
        mod_price = 0
        for mid in ln.modifiers:
            if mid in options:
                mod_price += options[mid].price_cents or 0
        ol = OrderLine(
            order_id=order_id,
            item_id=ln.item_id,
            qty=ln.qty,
            price_cents=(base_price or 0) + mod_price,
            note=ln.note,
            modifiers_json=json.dumps(ln.modifiers),
            discount_cents=max(0, ln.discount_cents),
            service_pct=ln.service_pct,
            tax_pct=ln.tax_pct,
            course=ln.course,
            station=ln.station,
        )
        s.add(ol)
        if ln.station:
            stations_for_routing.add(ln.station)
    if not stations_for_routing:
        stations_for_routing.add(None)
    kt = KitchenTicket(order_id=order_id, status="new")
    first_station = req.lines[0].station if req.lines else None
    kt.station = first_station
    s.add(kt)
    for st in stations_for_routing:
        _route_printers(order_id, st, s)
    _route_printers(order_id, first_station, s)
    # auto-decrement inventory per recipe
    for ln in req.lines:
        rec_lines = s.execute(select(RecipeLine).where(RecipeLine.item_id == ln.item_id)).scalars().all()
        for rl in rec_lines:
            inv = s.get(InventoryItem, rl.inventory_item_id)
            if not inv:
                continue
    inv.stock_qty = (inv.stock_qty or 0) - (rl.qty * ln.qty)
    mv = InventoryMovement(
        inventory_item_id=inv.id,
        qty=-(rl.qty * ln.qty),
        reason="order_consume",
        note=f"Order {order_id}",
    )
    s.add(mv); s.add(inv)
s.commit()
_queue_broadcast({"type": "orders_changed"})
_queue_broadcast({"type": "tickets_changed"})
return _order_to_out(s, od)


@router.get("/orders", response_model=List[OrderOut])
def list_orders(status: str = "", limit: int = 50, s: Session = Depends(get_session)):
    stmt = select(Order)
    if status:
        stmt = stmt.where(Order.status == status)
    stmt = stmt.order_by(Order.created_at.desc()).limit(max(1, min(limit, 200)))
    ods = s.execute(stmt).scalars().all()
    return [_order_to_out(s, od) for od in ods]


@router.get("/orders/{order_id}/receipt.pdf")
def receipt_pdf(order_id: str, s: Session = Depends(get_session)):
    od = s.get(Order, order_id)
    if not od:
        raise HTTPException(status_code=404, detail="not found")
    lines = s.execute(select(OrderLine).where(OrderLine.order_id == order_id)).scalars().all()
    layout = {
        "type": "receipt",
        "order_id": order_id,
        "subtotal": od.total_cents - od.tax_cents,
        "tax_cents": od.tax_cents,
        "service_pct": od.service_pct,
        "discount_cents": od.discount_cents,
        "tip_cents": od.tip_cents,
        "currency": od.currency,
        "items": [{"item_id": l.item_id, "qty": l.qty, "price_cents": l.price_cents} for l in lines],
        "total": od.total_cents,
    }
    content = json.dumps(layout, indent=2).encode("utf-8")
    headers = {"Content-Disposition": f'attachment; filename="receipt_{order_id}.json"'}
    return Response(content=content, media_type="application/json", headers=headers)


class PrinterOut(BaseModel):
    id: int
    name: str
    station: Optional[str]
    driver: str
    target: str
    layout_json: Optional[str]
    char_width: int
    model_config = ConfigDict(from_attributes=True)


class PrinterCreate(BaseModel):
    name: str
    station: Optional[str] = None
    driver: str = "escpos"
    target: str
    layout_json: Optional[str] = None
    char_width: int = 32


@router.post("/printers", response_model=PrinterOut)
def create_printer(req: PrinterCreate, s: Session = Depends(get_session)):
    pr = PrinterConfig(
        name=req.name,
        station=req.station,
        driver=req.driver,
        target=req.target,
        layout_json=req.layout_json,
        char_width=req.char_width,
    )
    s.add(pr); s.commit(); s.refresh(pr)
    return pr


@router.get("/printers", response_model=List[PrinterOut])
def list_printers(s: Session = Depends(get_session)):
    return s.execute(select(PrinterConfig)).scalars().all()


class PrinterJobOut(BaseModel):
    id: int
    printer_id: int
    order_id: str
    payload_json: str
    status: str
    created_at: Optional[datetime]
    updated_at: Optional[datetime]
    retry_count: int
    last_error: Optional[str]
    target: Optional[str] = None
    driver: Optional[str] = None
    station: Optional[str] = None
    model_config = ConfigDict(from_attributes=True)


class RenderOut(BaseModel):
    driver: Optional[str] = None
    layout: dict
    raw_output: str = ""
    raw_base64: Optional[str] = None
    media_type: str = "text/plain"


@router.get("/printer-jobs", response_model=List[PrinterJobOut])
def list_printer_jobs(status: str = "queued", limit: int = 50, s: Session = Depends(get_session)):
    stmt = select(PrinterJob)
    if status:
        stmt = stmt.where(PrinterJob.status == status)
    stmt = stmt.order_by(PrinterJob.created_at.asc()).limit(max(1, min(limit, 200)))
    jobs = s.execute(stmt).scalars().all()
    out = []
    printers = {p.id: p for p in s.execute(select(PrinterConfig)).scalars().all()}
    for j in jobs:
        pr = printers.get(j.printer_id)
        station = None
        try:
            station = json.loads(j.payload_json).get("station")
        except Exception:
            pass
        out.append(
            PrinterJobOut(
                id=j.id,
                printer_id=j.printer_id,
                order_id=j.order_id,
                payload_json=j.payload_json,
                status=j.status,
                created_at=j.created_at,
                updated_at=j.updated_at,
                retry_count=j.retry_count,
                last_error=j.last_error,
                target=pr.target if pr else None,
                driver=pr.driver if pr else None,
                station=station,
            )
        )
    return out


class PrinterJobUpdate(BaseModel):
    status: str
    last_error: Optional[str] = None


class PrinterJobClaim(BaseModel):
    printer_id: int
    station: Optional[str] = None


@router.post("/printer-jobs/claim", response_model=PrinterJobOut)
def claim_job(req: PrinterJobClaim, s: Session = Depends(get_session)):
    stmt = select(PrinterJob).where(PrinterJob.printer_id == req.printer_id, PrinterJob.status == "queued")
    if req.station:
        stmt = stmt.where(PrinterJob.payload_json.like(f'%\"station\": \"{req.station}\"%'))
    stmt = stmt.order_by(PrinterJob.created_at.asc()).limit(1)
    job = s.execute(stmt).scalar_one_or_none()
    if not job:
        raise HTTPException(status_code=404, detail="no job")
    job.status = "printing"
    s.commit(); s.refresh(job)
    pr = s.get(PrinterConfig, job.printer_id)
    station = None
    try:
        station = json.loads(job.payload_json).get("station")
    except Exception:
        pass
    return PrinterJobOut(
        id=job.id,
        printer_id=job.printer_id,
        order_id=job.order_id,
        payload_json=job.payload_json,
        status=job.status,
        created_at=job.created_at,
        updated_at=job.updated_at,
        retry_count=job.retry_count,
        last_error=job.last_error,
        target=pr.target if pr else None,
        driver=pr.driver if pr else None,
        station=station,
    )


@router.post("/printer-jobs/{jid}/deliver", response_model=PrinterJobOut)
def deliver_job(jid: int, s: Session = Depends(get_session)):
    job = s.get(PrinterJob, jid)
    if not job:
        raise HTTPException(status_code=404, detail="not found")
    pr = s.get(PrinterConfig, job.printer_id)
    payload = json.loads(job.payload_json)
    order_id = payload.get("order_id")
    station = payload.get("station")
    od = s.get(Order, order_id)
    if not od:
        raise HTTPException(status_code=404, detail="order missing")
    lines = s.execute(select(OrderLine).where(OrderLine.order_id == order_id)).scalars().all()
    if station:
        lines = [l for l in lines if l.station == station]
    layout = _render_layout(pr, od, lines, station)
    _render_driver_output(pr, layout)  # side-effect placeholder
    job.status = "done"
    job.last_error = None
    s.commit(); s.refresh(job)
    return job


@router.post("/printer-jobs/{jid}", response_model=PrinterJobOut)
def update_printer_job(jid: int, req: PrinterJobUpdate, s: Session = Depends(get_session)):
    job = s.get(PrinterJob, jid)
    if not job:
        raise HTTPException(status_code=404, detail="not found")
    job.status = req.status
    job.last_error = req.last_error
    if req.status == "error":
        job.retry_count = job.retry_count + 1
    s.commit(); s.refresh(job)
    return job


@router.get("/printer-jobs/{jid}/render")
def render_job(jid: int, s: Session = Depends(get_session)):
    job = s.get(PrinterJob, jid)
    if not job:
        raise HTTPException(status_code=404, detail="not found")
    pr = s.get(PrinterConfig, job.printer_id)
    payload = json.loads(job.payload_json)
    order_id = payload.get("order_id")
    station = payload.get("station")
    od = s.get(Order, order_id)
    if not od:
        raise HTTPException(status_code=404, detail="order missing")
    lines = s.execute(select(OrderLine).where(OrderLine.order_id == order_id)).scalars().all()
    if station:
        lines = [l for l in lines if l.station == station]
    layout = _render_layout(pr, od, lines, station)
    raw, raw_b64, media = _render_driver_output(pr, layout)
    return {
        "driver": pr.driver if pr else None,
        "layout": layout,
        "raw_output": raw,
        "raw_base64": raw_b64,
        "media_type": media,
    }


def _render_driver_output(pr: Optional[PrinterConfig], layout: dict) -> tuple[str, Optional[str], str]:
    driver = pr.driver if pr else "escpos"
    width = pr.char_width if pr else 32
    media = "text/plain"
    # if template provided and rendered present, build a text body respecting width
    def render_template_lines(template) -> str:
        lines_out = []

        def wrap(text: str) -> list[str]:
            res = []
            while text:
                if len(text) <= width:
                    res.append(text)
                    break
                res.append(text[:width])
                text = text[width:]
            return res or [""]

        def format_row(left: str, right: str) -> str:
            space = max(0, width - len(left) - len(right))
            return left + (" " * space) + right

        if isinstance(template, list):
            for item in template:
                if isinstance(item, str):
                    lines_out.extend(wrap(item))
                elif isinstance(item, dict):
                    t = item.get("type", "text")
                    if t == "text":
                        txt = str(item.get("text", ""))
                        align = item.get("align", "left")
                        if align == "center":
                            pad = max(0, (width - len(txt)) // 2)
                            txt = (" " * pad) + txt
                        elif align == "right":
                            pad = max(0, width - len(txt))
                            txt = (" " * pad) + txt
                        lines_out.extend(wrap(txt))
                    elif t == "row":
                        left = str(item.get("left", ""))
                        right = str(item.get("right", ""))
                        lines_out.append(format_row(left, right))
                    elif t == "blank":
                        count = int(item.get("count", 1))
                        for _ in range(count):
                            lines_out.append("")
        elif isinstance(template, dict):
            for v in template.values():
                if isinstance(v, str):
                    lines_out.extend(wrap(v))
        return "\n".join(lines_out) + "\n"

    if layout.get("rendered"):
        rendered = layout["rendered"]
        layout_text = render_template_lines(rendered)
    else:
        layout_text = None

    if driver == "escpos":
        parts = bytearray()
        parts.extend(b"\x1b@")  # init

        def wrap(text: str) -> list[str]:
            res = []
            while text:
                if len(text) <= width:
                    res.append(text)
                    break
                res.append(text[:width])
                text = text[width:]
            return res or [""]

        def esc_align(al: str) -> bytes:
            val = 0
            if al == "center":
                val = 1
            elif al == "right":
                val = 2
            return b"\x1ba" + bytes([val])

        def esc_bold(on: bool) -> bytes:
            return b"\x1bE" + (b"\x01" if on else b"\x00")

        def esc_size(double_width: bool, double_height: bool) -> bytes:
            val = 0
            if double_width:
                val |= 0x20
            if double_height:
                val |= 0x10
            return b"\x1d!" + bytes([val])

        if layout_text:
            parts.extend(layout_text.encode("latin-1", errors="ignore"))
        else:
            parts.extend(f"ORDER {layout.get('order_id','')}\n".encode("latin-1", errors="ignore"))
            for ln in layout.get("lines", []):
                line_txt = f"{ln.get('qty','')} x {ln.get('item_id','')} {ln.get('price_cents','')}"
                for seg in wrap(line_txt):
                    parts.extend(seg.encode("latin-1", errors="ignore") + b"\n")
            parts.extend(f"TOTAL {layout.get('total_cents','')} {layout.get('currency','')}\n".encode("latin-1", errors="ignore"))

        # ensure cut
        parts.extend(b"\n\x1dV\x41\x03")
        raw = parts.decode("latin-1", errors="ignore")
        raw_b64 = base64.b64encode(raw.encode("latin-1", errors="ignore")).decode("ascii")
        return raw, raw_b64, "application/octet-stream"
    if driver == "pdf":
        body = layout_text or ""
        if not body:
            body += f"PDF-ORDER {layout.get('order_id','')}\n"
            for ln in layout.get("lines", []):
                body += f"{ln.get('qty','')} x {ln.get('item_id','')} {ln.get('price_cents','')}\n"
        raw_b64 = base64.b64encode(body.encode("utf-8")).decode("ascii")
        return body, raw_b64, "application/pdf"
    # default: json string
    try:
        raw = json.dumps(layout, indent=2)
    except Exception:
        raw = str(layout)
    return raw, None, media


def _render_layout(pr: Optional[PrinterConfig], od: Order, lines: List[OrderLine], station: Optional[str]):
    # grouping by course for kitchen/expeditor grouping
    course_groups = {}
    for l in lines:
        key = l.course or "default"
        course_groups.setdefault(key, []).append(l)
    layout = {
        "printer": {"id": pr.id if pr else None, "name": pr.name if pr else None, "driver": pr.driver if pr else None},
        "order_id": od.id,
        "station": station,
        "lines": [
            {"item_id": l.item_id, "qty": l.qty, "price_cents": l.price_cents, "station": l.station, "course": l.course}
            for l in lines
        ],
        "courses": {
            k: [
                {"item_id": l.item_id, "qty": l.qty, "price_cents": l.price_cents, "station": l.station, "course": l.course}
                for l in v
            ]
            for k, v in course_groups.items()
        },
        "total_cents": od.total_cents,
        "currency": od.currency,
    }
    # simple placeholder replacement in template if provided
    if pr and pr.layout_json:
        try:
            template = json.loads(pr.layout_json)
        except Exception:
            template = pr.layout_json

        def replace(obj):
            if isinstance(obj, str):
                return obj.replace("{{order_id}}", od.id).replace("{{currency}}", od.currency)
            if isinstance(obj, list):
                return [replace(x) for x in obj]
            if isinstance(obj, dict):
                return {k: replace(v) for k, v in obj.items()}
            return obj

        layout["rendered"] = replace(template)
    return layout


class TicketOut(BaseModel):
    id: int
    order_id: str
    status: str
    created_at: Optional[datetime]
    model_config = ConfigDict(from_attributes=True)


@router.get("/kitchen/tickets", response_model=List[TicketOut])
def list_tickets(status: str = "", s: Session = Depends(get_session)):
    stmt = select(KitchenTicket)
    if status:
        stmt = stmt.where(KitchenTicket.status == status)
    stmt = stmt.order_by(KitchenTicket.created_at.asc())
    tickets = s.execute(stmt).scalars().all()
    # include basic course/station info from order lines
    out: List[dict] = []
    for t in tickets:
        lines = s.execute(select(OrderLine).where(OrderLine.order_id == t.order_id)).scalars().all()
        out.append({
            "id": t.id,
            "order_id": t.order_id,
            "status": t.status,
            "created_at": t.created_at,
            "courses": list({ln.course for ln in lines if ln.course}),
            "stations": list({ln.station for ln in lines if ln.station}),
        })
    return out


class TicketUpdate(BaseModel):
    status: str


@router.post("/kitchen/tickets/{tid}", response_model=TicketOut)
def update_ticket(tid: int, req: TicketUpdate, s: Session = Depends(get_session)):
    kt = s.get(KitchenTicket, tid)
    if not kt:
        raise HTTPException(status_code=404, detail="not found")
    if req.status not in ("new", "doing", "done", "fire", "recall"):
        raise HTTPException(status_code=400, detail="bad status")
    kt.status = req.status
    s.commit(); s.refresh(kt)
    _queue_broadcast({"type": "tickets_changed"})
    _route_printers(kt.order_id, kt.station, s)
    return kt


# --- Shifts / Cashbook ---
class ShiftCreate(BaseModel):
    device_id: str = "POS"
    opening_cash_cents: int = 0
    note: Optional[str] = None


class ShiftClose(BaseModel):
    closing_cash_cents: int = 0
    counted_cash_cents: int = 0
    note: Optional[str] = None


class ShiftOut(BaseModel):
    id: int
    device_id: str
    opened_at: Optional[datetime]
    closed_at: Optional[datetime]
    opening_cash_cents: int
    closing_cash_cents: int
    counted_cash_cents: int
    note: Optional[str]
    model_config = ConfigDict(from_attributes=True)


@router.post("/shifts", response_model=ShiftOut)
def open_shift(req: ShiftCreate, s: Session = Depends(get_session)):
    sh = Shift(
        device_id=req.device_id,
        opening_cash_cents=max(0, req.opening_cash_cents),
        note=req.note,
    )
    s.add(sh); s.commit(); s.refresh(sh)
    return sh


@router.post("/shifts/{sid}/close", response_model=ShiftOut)
def close_shift(sid: int, req: ShiftClose, s: Session = Depends(get_session)):
    sh = s.get(Shift, sid)
    if not sh:
        raise HTTPException(status_code=404, detail="not found")
    sh.closed_at = datetime.utcnow()
    sh.closing_cash_cents = max(0, req.closing_cash_cents)
    sh.counted_cash_cents = max(0, req.counted_cash_cents)
    sh.note = req.note
    s.commit(); s.refresh(sh)
    return sh


@router.get("/shifts", response_model=List[ShiftOut])
def list_shifts(limit: int = 20, s: Session = Depends(get_session)):
    stmt = select(Shift).order_by(Shift.id.desc()).limit(max(1, min(limit, 200)))
    return s.execute(stmt).scalars().all()


# --- Service/Discount Rules ---
class ServiceRuleCreate(BaseModel):
    rule_type: str = "service"  # service/discount
    pct: float = 0.0
    table_id: Optional[int] = None
    device_id: Optional[str] = None
    start_minute: Optional[int] = None
    end_minute: Optional[int] = None
    days_mask: Optional[int] = None


class ServiceRuleOut(BaseModel):
    id: int
    rule_type: str
    pct: float
    table_id: Optional[int]
    device_id: Optional[str]
    start_minute: Optional[int]
    end_minute: Optional[int]
    days_mask: Optional[int]
    model_config = ConfigDict(from_attributes=True)


@router.post("/rules", response_model=ServiceRuleOut)
def create_rule(req: ServiceRuleCreate, s: Session = Depends(get_session)):
    if req.rule_type not in ("service", "discount"):
        raise HTTPException(status_code=400, detail="bad rule type")
    sr = ServiceRule(
        rule_type=req.rule_type,
        pct=req.pct,
        table_id=req.table_id,
        device_id=req.device_id,
        start_minute=req.start_minute,
        end_minute=req.end_minute,
        days_mask=req.days_mask,
    )
    s.add(sr); s.commit(); s.refresh(sr)
    return sr


@router.get("/rules", response_model=List[ServiceRuleOut])
def list_rules(s: Session = Depends(get_session)):
    return s.execute(select(ServiceRule).order_by(ServiceRule.id.desc())).scalars().all()


# --- Payments / partials ---
class PaymentCreate(BaseModel):
    amount_cents: int
    method: str = "cash"
    status: str = "captured"


class PaymentOut(BaseModel):
    id: int
    order_id: str
    amount_cents: int
    method: str
    status: str
    remaining_cents: int
    model_config = ConfigDict(from_attributes=True)


def _compute_paid(s: Session, order_id: str) -> int:
    return int(
        s.execute(select(func.sum(PaymentRecord.amount_cents)).where(PaymentRecord.order_id == order_id)).scalar() or 0
    )


def _order_to_out(s: Session, od: Order) -> OrderOut:
    paid = _compute_paid(s, od.id)
    remaining = max(0, (od.total_cents + od.tip_cents) - paid)
    return OrderOut(
        id=od.id,
        table_id=od.table_id,
        status=od.status,
        total_cents=od.total_cents,
        tax_cents=od.tax_cents,
        tax_pct=od.tax_pct,
        service_pct=od.service_pct,
        discount_cents=od.discount_cents,
        tip_cents=od.tip_cents,
        payment_method=od.payment_method,
        paid_at=od.paid_at,
        currency=od.currency,
        paid_cents=paid,
        remaining_cents=remaining,
    )


def _route_printers(order_id: str, station: Optional[str], s: Session):
    printers = s.execute(select(PrinterConfig)).scalars().all()
    for pr in printers:
        if pr.station and station and pr.station != station:
            continue
        payload = json.dumps({"order_id": order_id, "station": station}, ensure_ascii=False)
        s.add(PrinterJob(printer_id=pr.id, order_id=order_id, payload_json=payload, status="queued"))


@router.post("/orders/{order_id}/payments", response_model=PaymentOut)
def add_payment(order_id: str, req: PaymentCreate, s: Session = Depends(get_session)):
    od = s.get(Order, order_id)
    if not od:
        raise HTTPException(status_code=404, detail="not found")
    pay = PaymentRecord(order_id=order_id, amount_cents=req.amount_cents, method=req.method, status=req.status)
    s.add(pay); s.commit(); s.refresh(pay)
    paid = _compute_paid(s, order_id)
    due = max(0, (od.total_cents + od.tip_cents) - paid)
    if due == 0:
        od.status = "paid"
        od.paid_at = datetime.utcnow()
        s.commit()
    _queue_broadcast({"type": "orders_changed"})
    return PaymentOut(
        id=pay.id,
        order_id=order_id,
        amount_cents=pay.amount_cents,
        method=pay.method,
        status=pay.status,
        remaining_cents=due,
    )


class RefundRequest(BaseModel):
    amount_cents: int
    method: str = "cash"


@router.post("/orders/{order_id}/refund", response_model=PaymentOut)
def refund_payment(order_id: str, req: RefundRequest, s: Session = Depends(get_session)):
    od = s.get(Order, order_id)
    if not od:
        raise HTTPException(status_code=404, detail="not found")
    amt = max(0, req.amount_cents)
    pay = PaymentRecord(order_id=order_id, amount_cents=-amt, method=req.method, status="refunded")
    s.add(pay); s.commit(); s.refresh(pay)
    paid = _compute_paid(s, order_id)
    due = max(0, (od.total_cents + od.tip_cents) - paid)
    if due > 0 and od.status == "paid":
        od.status = "open"
        od.paid_at = None
        s.commit()
    _queue_broadcast({"type": "orders_changed"})
    return PaymentOut(
        id=pay.id,
        order_id=order_id,
        amount_cents=pay.amount_cents,
        method=pay.method,
        status=pay.status,
        remaining_cents=due,
    )


# --- Waitlist ---
@router.post("/waitlist", response_model=WaitlistOut)
def add_waitlist(req: WaitlistCreate, s: Session = Depends(get_session)):
    wl = Waitlist(
        guest_name=req.guest_name.strip(),
        phone=req.phone,
        party_size=req.party_size,
        note=req.note,
    )
    s.add(wl); s.commit(); s.refresh(wl)
    return wl


@router.get("/waitlist", response_model=List[WaitlistOut])
def list_waitlist(s: Session = Depends(get_session)):
    return s.execute(select(Waitlist).order_by(Waitlist.created_at.desc())).scalars().all()


class WaitlistSeat(BaseModel):
    table_id: Optional[int] = None
    status: str = "seated"


@router.post("/waitlist/{wid}", response_model=WaitlistOut)
def update_waitlist(wid: int, req: WaitlistSeat, s: Session = Depends(get_session)):
    wl = s.get(Waitlist, wid)
    if not wl:
        raise HTTPException(status_code=404, detail="not found")
    wl.status = req.status
    wl.table_id = req.table_id
    s.commit(); s.refresh(wl)
    return wl


class PayLinkOut(BaseModel):
    payment_link: str
    amount_cents: int
    currency: str


@router.post("/orders/{order_id}/pay", response_model=PayLinkOut)
def create_payment_link(order_id: str, s: Session = Depends(get_session)):
    od = s.get(Order, order_id)
    if not od:
        raise HTTPException(status_code=404, detail="not found")
    link = ""
    if PAYMENTS_BASE:
        link = PAYMENTS_BASE.rstrip("/") + f"/pay?order_id={order_id}&amount_cents={od.total_cents}"
    else:
        link = f"https://pay.local/pay?order_id={order_id}&amount_cents={od.total_cents}"
    od.status = "open"
    s.commit()
    return PayLinkOut(payment_link=link, amount_cents=od.total_cents, currency=od.currency)


# --- QR Ordering (guest creates an order by table code) ---
class QROrderLine(BaseModel):
    item_id: int
    qty: int = Field(ge=1)
    note: Optional[str] = None
    modifiers: List[int] = Field(default_factory=list)


class QROrderCreate(BaseModel):
    table_id: int
    currency: str = "SYP"
    lines: List[QROrderLine]
    tip_cents: int = 0
    customer_name: Optional[str] = None
    customer_phone: Optional[str] = None
    note: Optional[str] = None
    device_code: Optional[str] = None


@router.post("/qr/orders", response_model=OrderOut)
def create_qr_order(req: QROrderCreate, s: Session = Depends(get_session)):
    od = create_order(OrderCreate(table_id=req.table_id, currency=req.currency, tax_pct=0.0, service_pct=0.0, discount_cents=0, lines=req.lines, device_id=req.device_code), s=s)
    db_od = s.get(Order, od.id)
    if db_od:
        db_od.tip_cents = max(0, req.tip_cents)
        s.commit()
    _queue_broadcast({"type": "orders_changed"})
    return _order_to_out(s, od)


@router.get("/orders/{order_id}", response_model=OrderDetail)
def order_detail(order_id: str, s: Session = Depends(get_session)):
    od = s.get(Order, order_id)
    if not od:
        raise HTTPException(status_code=404, detail="not found")
    lines = s.execute(select(OrderLine).where(OrderLine.order_id == order_id)).scalars().all()
    return OrderDetail(order=_order_to_out(s, od), lines=[OrderLineOut.from_db(l) for l in lines])


@router.get("/qr/menu")
def qr_menu(s: Session = Depends(get_session)):
    items = s.execute(select(Item)).scalars().all()
    mods = s.execute(select(Modifier)).scalars().all()
    groups = s.execute(select(ModifierGroup)).scalars().all()
    opts = s.execute(select(ModifierOption)).scalars().all()
    mod_by_item = {}
    for m in mods:
        mod_by_item.setdefault(m.item_id, []).append({"id": m.id, "name": m.name, "price_cents": m.price_cents})
    opt_by_group = {}
    for o in opts:
        opt_by_group.setdefault(o.group_id, []).append({"id": o.id, "name": o.name, "price_cents": o.price_cents})
    return {
        "items": [
            {
                "id": i.id,
                "name": i.name,
                "price_cents": i.price_cents,
                "currency": i.currency,
                "image_url": i.image_url,
                "allergens": json.loads(i.allergens_json or "[]"),
                "diet_tags": json.loads(i.diet_tags_json or "[]"),
                "modifiers": mod_by_item.get(i.id, []),
                "modifier_groups": json.loads(i.modifier_groups_json or "[]"),
            }
            for i in items
        ],
        "modifier_groups": [
            {
                "id": g.id,
                "name": g.name,
                "required": bool(g.required),
                "min_choices": g.min_choices,
                "max_choices": g.max_choices,
                "options": opt_by_group.get(g.id, []),
            }
            for g in groups
        ],
    }


@router.get("/qr/orders/{order_id}", response_model=OrderOut)
def qr_order_status(order_id: str, s: Session = Depends(get_session)):
    od = s.get(Order, order_id)
    if not od:
        raise HTTPException(status_code=404, detail="not found")
    return od


# --- Payments / settle / void ---
class SettleRequest(BaseModel):
    payment_method: str = "cash"
    tip_cents: int = 0
    device_id: Optional[str] = None


@router.post("/orders/{order_id}/settle", response_model=OrderOut)
def settle_order(order_id: str, req: SettleRequest, s: Session = Depends(get_session)):
    od = s.get(Order, order_id)
    if not od:
        raise HTTPException(status_code=404, detail="not found")
    if od.status == "voided":
        raise HTTPException(status_code=400, detail="order voided")
    od.tip_cents = max(0, req.tip_cents)
    od.payment_method = req.payment_method
    od.device_id = req.device_id
    pay = PaymentRecord(order_id=order_id, amount_cents=od.total_cents + od.tip_cents, method=req.payment_method, status="captured")
    s.add(pay)
    od.status = "paid"
    od.paid_at = datetime.utcnow()
    s.commit(); s.refresh(od)
    _queue_broadcast({"type": "orders_changed"})
    return od


@router.post("/orders/{order_id}/void", response_model=OrderOut)
def void_order(order_id: str, reason: str = "void", s: Session = Depends(get_session)):
    od = s.get(Order, order_id)
    if not od:
        raise HTTPException(status_code=404, detail="not found")
    od.status = "voided"
    s.commit(); s.refresh(od)
    _queue_broadcast({"type": "orders_changed"})
    return od


def _recalc_order_totals(s: Session, order_id: str):
    od = s.get(Order, order_id)
    if not od:
        return
    lines = s.execute(select(OrderLine).where(OrderLine.order_id == order_id)).scalars().all()
    base_total = 0
    for l in lines:
        base_total += (l.price_cents * l.qty) - l.discount_cents
        base_total += int((l.price_cents * l.qty) * (l.service_pct / 100.0))
        base_total += int((l.price_cents * l.qty) * (l.tax_pct / 100.0))
    tax_cents = int(base_total * (od.tax_pct / 100.0)) if od.tax_pct > 0 else 0
    service_cents = int(base_total * (od.service_pct / 100.0)) if od.service_pct > 0 else 0
    od.total_cents = max(0, base_total + tax_cents + service_cents - od.discount_cents)
    s.commit()


class SplitRequest(BaseModel):
    line_ids: List[int]


@router.post("/orders/{order_id}/split", response_model=OrderOut)
def split_order(order_id: str, req: SplitRequest, s: Session = Depends(get_session)):
    od = s.get(Order, order_id)
    if not od:
        raise HTTPException(status_code=404, detail="not found")
    if not req.line_ids:
        raise HTTPException(status_code=400, detail="no lines")
    new_id = str(uuid.uuid4())
    new_order = Order(
        id=new_id,
        table_id=od.table_id,
        status="open",
        tax_pct=od.tax_pct,
        service_pct=od.service_pct,
        discount_cents=0,
        currency=od.currency,
    )
    s.add(new_order); s.commit()
    lines = s.execute(select(OrderLine).where(OrderLine.id.in_(req.line_ids))).scalars().all()
    for ln in lines:
        clone = OrderLine(
            order_id=new_id,
            item_id=ln.item_id,
            qty=ln.qty,
            price_cents=ln.price_cents,
            discount_cents=ln.discount_cents,
            service_pct=ln.service_pct,
            tax_pct=ln.tax_pct,
            note=ln.note,
            modifiers_json=ln.modifiers_json,
            course=ln.course,
            station=ln.station,
        )
        s.add(clone)
        s.delete(ln)
    s.commit()
    _recalc_order_totals(s, order_id)
    _recalc_order_totals(s, new_id)
    _queue_broadcast({"type": "orders_changed"})
    return new_order


class JoinRequest(BaseModel):
    order_ids: List[str]


@router.post("/orders/join", response_model=OrderOut)
def join_orders(req: JoinRequest, s: Session = Depends(get_session)):
    if len(req.order_ids) < 2:
        raise HTTPException(status_code=400, detail="need 2+ orders")
    target_id = req.order_ids[0]
    target = s.get(Order, target_id)
    if not target:
        raise HTTPException(status_code=404, detail="target not found")
    for oid in req.order_ids[1:]:
        od = s.get(Order, oid)
        if not od:
            continue
        lines = s.execute(select(OrderLine).where(OrderLine.order_id == oid)).scalars().all()
        for ln in lines:
            ln.order_id = target_id
        od.status = "voided"
    s.commit()
    _recalc_order_totals(s, target_id)
    s.refresh(target)
    _queue_broadcast({"type": "orders_changed"})
    return target


# --- ESC/POS stub ---
@router.get("/orders/{order_id}/print/escpos")
def escpos_stub(order_id: str, s: Session = Depends(get_session)):
    od = s.get(Order, order_id)
    if not od:
        raise HTTPException(status_code=404, detail="not found")
    lines = s.execute(select(OrderLine).where(OrderLine.order_id == order_id)).scalars().all()
    layout = {
        "title": f"ORDER {order_id}",
        "items": [{"name": str(l.item_id), "qty": l.qty, "price": l.price_cents} for l in lines],
        "total": od.total_cents,
        "currency": od.currency,
    }
    target_bytes = json.dumps(layout, indent=2).encode("utf-8")
    headers = {"Content-Disposition": f'attachment; filename=\"order_{order_id}.json\"'}
    return Response(content=target_bytes, media_type="application/json", headers=headers)


@router.get("/reports/daily")
def report_daily(s: Session = Depends(get_session)):
    today = date.today()
    start = datetime.combine(today, datetime.min.time())
    end = datetime.combine(today, datetime.max.time())
    total = s.execute(
        select(func.sum(Order.total_cents)).where(
            Order.created_at >= start,
            Order.created_at <= end,
            Order.status == "paid",
        )
    ).scalar() or 0
    orders = s.execute(
        select(func.count()).where(
            Order.created_at >= start,
            Order.created_at <= end,
        )
    ).scalar() or 0
    low_stock = s.execute(
        select(InventoryItem).where(
            InventoryItem.low_stock_threshold.is_not(None),
            InventoryItem.stock_qty <= InventoryItem.low_stock_threshold,
        )
    ).scalars().all()
    return {
        "orders": orders,
        "total_cents": int(total),
        "low_stock": [{"id": i.id, "name": i.name, "stock_qty": i.stock_qty, "unit": i.unit} for i in low_stock],
    }


app.include_router(router)


@app.websocket("/pos/ws")
async def websocket_endpoint(ws: WebSocket):
    await ws.accept()
    active_sockets.add(ws)
    try:
        # send initial snapshot
        with Session(engine) as s:
            orders = [_order_to_out(s, od).model_dump() for od in s.execute(select(Order)).scalars().all()]
            tickets = [
                {
                    "id": t.id,
                    "order_id": t.order_id,
                    "status": t.status,
                    "created_at": t.created_at,
                }
                for t in s.execute(select(KitchenTicket)).scalars().all()
            ]
        await ws.send_json({"type": "snapshot", "orders": orders, "tickets": tickets})
        while True:
            await ws.receive_text()  # no-op, keep alive
    except WebSocketDisconnect:
        pass
    finally:
        if ws in active_sockets:
            active_sockets.remove(ws)
