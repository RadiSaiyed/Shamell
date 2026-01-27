import json
import os
from datetime import datetime, date, timedelta
from typing import Optional, List

from fastapi import FastAPI, APIRouter, HTTPException, Depends, Response
from pydantic import BaseModel, Field, ConfigDict
from sqlalchemy import (
    Boolean,
    Date,
    DateTime,
    ForeignKey,
    Integer,
    JSON,
    Numeric,
    String,
    Text,
    UniqueConstraint,
    BigInteger,
    create_engine,
    func,
    select,
)
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column

from shamell_shared import RequestIDMiddleware, configure_cors, add_standard_health, setup_json_logging


def _env_or(key: str, default: str) -> str:
    v = os.getenv(key)
    return v if v is not None else default


DB_URL = _env_or("DB_URL", "sqlite+pysqlite:////tmp/pms.db")
DB_SCHEMA = os.getenv("DB_SCHEMA") if not DB_URL.startswith("sqlite") else None
PAYMENT_LINK_BASE = os.getenv("PAYMENT_LINK_BASE", "https://pay.shamell.local/link")

app = FastAPI(title="PMS API", version="0.1.0")
setup_json_logging()
app.add_middleware(RequestIDMiddleware)
configure_cors(app, os.getenv("ALLOWED_ORIGINS", "*"))
add_standard_health(app)
router = APIRouter()


class Base(DeclarativeBase):
    pass


class Property(Base):
    __tablename__ = "properties"
    __table_args__ = {"schema": DB_SCHEMA} if DB_SCHEMA else {}
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(200))
    city: Mapped[Optional[str]] = mapped_column(String(128), default=None)
    timezone: Mapped[str] = mapped_column(String(64), default="UTC")
    currency: Mapped[str] = mapped_column(String(3), default="USD")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class RoomType(Base):
    __tablename__ = "room_types"
    __table_args__ = (
        UniqueConstraint("property_id", "code", name="uq_room_types_property_code"),
        {"schema": DB_SCHEMA} if DB_SCHEMA else {},
    )
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    property_id: Mapped[int] = mapped_column(Integer, ForeignKey("properties.id"))
    code: Mapped[str] = mapped_column(String(40))
    name: Mapped[str] = mapped_column(String(200))
    base_occupancy: Mapped[int] = mapped_column(Integer, default=1)
    max_occupancy: Mapped[int] = mapped_column(Integer, default=2)
    description: Mapped[Optional[str]] = mapped_column(Text, default=None)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    @property
    def max_guests(self) -> int:
        return self.max_occupancy


class Room(Base):
    __tablename__ = "rooms"
    __table_args__ = (
        UniqueConstraint("property_id", "number", name="uq_rooms_property_number"),
        {"schema": DB_SCHEMA} if DB_SCHEMA else {},
    )
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    property_id: Mapped[int] = mapped_column(Integer, ForeignKey("properties.id"))
    room_type_id: Mapped[int] = mapped_column(Integer, ForeignKey("room_types.id"))
    number: Mapped[str] = mapped_column(String(50))
    status: Mapped[str] = mapped_column(String(24), default="in_service")  # in_service/out_of_order
    housekeeping_status: Mapped[str] = mapped_column(String(32), default="clean")  # clean/dirty/inspected/out_of_service
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    @property
    def code(self) -> str:
        return self.number


class RatePlan(Base):
    __tablename__ = "rate_plans"
    __table_args__ = (
        UniqueConstraint("property_id", "code", name="uq_rate_plans_property_code"),
        {"schema": DB_SCHEMA} if DB_SCHEMA else {},
    )
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    property_id: Mapped[int] = mapped_column(Integer, ForeignKey("properties.id"))
    code: Mapped[str] = mapped_column(String(50))
    name: Mapped[str] = mapped_column(String(100))
    room_type_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("room_types.id"), default=None)
    currency: Mapped[str] = mapped_column(String(3), default="USD")
    base_rate_cents: Mapped[int] = mapped_column(BigInteger, default=0)
    is_public: Mapped[bool] = mapped_column(Boolean, default=True)
    cancellation_policy: Mapped[Optional[dict]] = mapped_column(JSON, default=None)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    @property
    def price_per_night_cents(self) -> int:
        return int(self.base_rate_cents or 0)


class DerivedRatePlan(Base):
    __tablename__ = "rate_plan_derived"
    __table_args__ = {"schema": DB_SCHEMA} if DB_SCHEMA else {}
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    parent_rate_plan_id: Mapped[int] = mapped_column(Integer, ForeignKey("rate_plans.id"))
    child_rate_plan_id: Mapped[int] = mapped_column(Integer, ForeignKey("rate_plans.id"))
    adjustment_type: Mapped[str] = mapped_column(String(16))  # percent/fixed
    adjustment_value: Mapped[float] = mapped_column(Numeric(8, 2))


class Season(Base):
    __tablename__ = "seasons"
    __table_args__ = {"schema": DB_SCHEMA} if DB_SCHEMA else {}
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    property_id: Mapped[int] = mapped_column(Integer, ForeignKey("properties.id"))
    name: Mapped[str] = mapped_column(String(100))
    start_date: Mapped[date] = mapped_column(Date)
    end_date: Mapped[date] = mapped_column(Date)


class Restriction(Base):
    __tablename__ = "restrictions"
    __table_args__ = (
        UniqueConstraint("property_id", "rate_plan_id", "room_type_id", "season_id", name="uq_restrictions_scope"),
        {"schema": DB_SCHEMA} if DB_SCHEMA else {},
    )
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    property_id: Mapped[int] = mapped_column(Integer, ForeignKey("properties.id"))
    rate_plan_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("rate_plans.id"), default=None)
    room_type_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("room_types.id"), default=None)
    season_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("seasons.id"), default=None)
    min_los: Mapped[Optional[int]] = mapped_column(Integer, default=None)
    max_los: Mapped[Optional[int]] = mapped_column(Integer, default=None)
    closed_to_arrival: Mapped[bool] = mapped_column(Boolean, default=False)
    closed_to_departure: Mapped[bool] = mapped_column(Boolean, default=False)
    stop_sell: Mapped[bool] = mapped_column(Boolean, default=False)


class Availability(Base):
    __tablename__ = "availability"
    __table_args__ = {"schema": DB_SCHEMA} if DB_SCHEMA else {}
    property_id: Mapped[int] = mapped_column(Integer, ForeignKey("properties.id"), primary_key=True)
    room_type_id: Mapped[int] = mapped_column(Integer, ForeignKey("room_types.id"), primary_key=True)
    date: Mapped[date] = mapped_column(Date, primary_key=True)
    total_inventory: Mapped[int] = mapped_column(Integer)
    rooms_blocked: Mapped[int] = mapped_column(Integer, default=0)
    rooms_sold: Mapped[int] = mapped_column(Integer, default=0)


class DailyRate(Base):
    __tablename__ = "daily_rates"
    __table_args__ = {"schema": DB_SCHEMA} if DB_SCHEMA else {}
    property_id: Mapped[int] = mapped_column(Integer, ForeignKey("properties.id"), primary_key=True)
    rate_plan_id: Mapped[int] = mapped_column(Integer, ForeignKey("rate_plans.id"), primary_key=True)
    room_type_id: Mapped[int] = mapped_column(Integer, ForeignKey("room_types.id"), primary_key=True)
    date: Mapped[date] = mapped_column(Date, primary_key=True)
    amount_cents: Mapped[int] = mapped_column(BigInteger)
    currency: Mapped[str] = mapped_column(String(3))


class Guest(Base):
    __tablename__ = "guests"
    __table_args__ = (
        UniqueConstraint("property_id", "email", name="uq_guests_property_email"),
        {"schema": DB_SCHEMA} if DB_SCHEMA else {},
    )
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    property_id: Mapped[int] = mapped_column(Integer, ForeignKey("properties.id"))
    first_name: Mapped[Optional[str]] = mapped_column(String(100), default=None)
    last_name: Mapped[Optional[str]] = mapped_column(String(100), default=None)
    email: Mapped[Optional[str]] = mapped_column(String(200), default=None)
    phone: Mapped[Optional[str]] = mapped_column(String(32), default=None)
    locale: Mapped[Optional[str]] = mapped_column(String(12), default=None)


class Reservation(Base):
    __tablename__ = "reservations"
    __table_args__ = {"schema": DB_SCHEMA} if DB_SCHEMA else {}
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    property_id: Mapped[int] = mapped_column(Integer, ForeignKey("properties.id"))
    guest_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("guests.id"), default=None)
    status: Mapped[str] = mapped_column(String(24), default="tentative")  # tentative/confirmed/in_house/checked_out/cancelled/no_show
    source: Mapped[str] = mapped_column(String(40), default="direct")
    check_in_date: Mapped[date] = mapped_column(Date)
    check_out_date: Mapped[date] = mapped_column(Date)
    adults: Mapped[int] = mapped_column(Integer, default=1)
    children: Mapped[int] = mapped_column(Integer, default=0)
    room_type_id: Mapped[int] = mapped_column(Integer, ForeignKey("room_types.id"))
    rate_plan_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("rate_plans.id"), default=None)
    total_amount_cents: Mapped[int] = mapped_column(BigInteger, default=0)
    currency: Mapped[str] = mapped_column(String(3), default="USD")
    guarantee_type: Mapped[Optional[str]] = mapped_column(String(32), default=None)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    @property
    def from_date(self) -> date:
        return self.check_in_date

    @property
    def to_date(self) -> date:
        return self.check_out_date

    @property
    def total_cents(self) -> int:
        return self.total_amount_cents


class ReservationRoom(Base):
    __tablename__ = "reservation_rooms"
    __table_args__ = (
        UniqueConstraint("reservation_id", "room_id", name="uq_reservation_room_room"),
        {"schema": DB_SCHEMA} if DB_SCHEMA else {},
    )
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    reservation_id: Mapped[int] = mapped_column(Integer, ForeignKey("reservations.id", ondelete="CASCADE"))
    room_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("rooms.id"), default=None)
    arrival_date: Mapped[date] = mapped_column(Date)
    departure_date: Mapped[date] = mapped_column(Date)
    status: Mapped[str] = mapped_column(String(24), default="unassigned")  # unassigned/assigned/occupied/cleaning


class Folio(Base):
    __tablename__ = "folios"
    __table_args__ = (
        UniqueConstraint("reservation_id", "is_master", name="uq_folios_reservation_master"),
        {"schema": DB_SCHEMA} if DB_SCHEMA else {},
    )
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    reservation_id: Mapped[int] = mapped_column(Integer, ForeignKey("reservations.id", ondelete="CASCADE"))
    name: Mapped[Optional[str]] = mapped_column(String(120), default=None)
    is_master: Mapped[bool] = mapped_column(Boolean, default=False)


class Charge(Base):
    __tablename__ = "charges"
    __table_args__ = {"schema": DB_SCHEMA} if DB_SCHEMA else {}
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    folio_id: Mapped[int] = mapped_column(Integer, ForeignKey("folios.id", ondelete="CASCADE"))
    post_date: Mapped[date] = mapped_column(Date)  # business date
    description: Mapped[str] = mapped_column(String(200))
    amount_cents: Mapped[int] = mapped_column(BigInteger)  # positive for debit, negative for credit
    currency: Mapped[str] = mapped_column(String(3))
    tax_included: Mapped[bool] = mapped_column(Boolean, default=True)
    tax_code: Mapped[Optional[str]] = mapped_column(String(20), default=None)
    revenue_account: Mapped[Optional[str]] = mapped_column(String(32), default=None)
    kind: Mapped[str] = mapped_column(String(20), default="charge")  # charge/payment/refund/fee/tax
    method: Mapped[Optional[str]] = mapped_column(String(40), default=None)  # cash/card/wallet/link
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Tax(Base):
    __tablename__ = "taxes"
    __table_args__ = (
        UniqueConstraint("property_id", "code", name="uq_taxes_property_code"),
        {"schema": DB_SCHEMA} if DB_SCHEMA else {},
    )
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    property_id: Mapped[int] = mapped_column(Integer, ForeignKey("properties.id"))
    code: Mapped[str] = mapped_column(String(40))
    name: Mapped[str] = mapped_column(String(120))
    rate_pct: Mapped[float] = mapped_column(Numeric(6, 3))
    applies_to: Mapped[str] = mapped_column(String(40))


class ChargeTax(Base):
    __tablename__ = "charge_taxes"
    __table_args__ = {"schema": DB_SCHEMA} if DB_SCHEMA else {}
    charge_id: Mapped[int] = mapped_column(Integer, ForeignKey("charges.id", ondelete="CASCADE"), primary_key=True)
    tax_id: Mapped[int] = mapped_column(Integer, ForeignKey("taxes.id"), primary_key=True)
    amount_cents: Mapped[int] = mapped_column(BigInteger)


class PaymentMethod(Base):
    __tablename__ = "payment_methods"
    __table_args__ = {"schema": DB_SCHEMA} if DB_SCHEMA else {}
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    guest_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("guests.id"), default=None)
    property_id: Mapped[int] = mapped_column(Integer, ForeignKey("properties.id"))
    psp: Mapped[str] = mapped_column(String(40))  # stripe/adyen/etc
    token: Mapped[str] = mapped_column(String(200))
    brand: Mapped[Optional[str]] = mapped_column(String(40), default=None)
    last4: Mapped[Optional[str]] = mapped_column(String(4), default=None)
    exp_month: Mapped[Optional[int]] = mapped_column(Integer, default=None)
    exp_year: Mapped[Optional[int]] = mapped_column(Integer, default=None)
    billing_name: Mapped[Optional[str]] = mapped_column(String(200), default=None)
    billing_address: Mapped[Optional[dict]] = mapped_column(JSON, default=None)


class Payment(Base):
    __tablename__ = "payments"
    __table_args__ = {"schema": DB_SCHEMA} if DB_SCHEMA else {}
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    folio_id: Mapped[int] = mapped_column(Integer, ForeignKey("folios.id", ondelete="CASCADE"))
    payment_method_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("payment_methods.id"), default=None)
    type: Mapped[str] = mapped_column(String(16))  # auth/capture/refund/void
    amount_cents: Mapped[int] = mapped_column(BigInteger)
    currency: Mapped[str] = mapped_column(String(3))
    psp: Mapped[str] = mapped_column(String(40))
    psp_ref: Mapped[Optional[str]] = mapped_column(String(120), default=None)
    status: Mapped[str] = mapped_column(String(24))  # succeeded/pending/failed
    captured_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), default=None)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class LedgerEntry(Base):
    __tablename__ = "ledger_entries"
    __table_args__ = {"schema": DB_SCHEMA} if DB_SCHEMA else {}
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    property_id: Mapped[int] = mapped_column(Integer, ForeignKey("properties.id"))
    reservation_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("reservations.id"), default=None)
    folio_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("folios.id"), default=None)
    entry_date: Mapped[date] = mapped_column(Date)
    type: Mapped[str] = mapped_column(String(16))  # debit/credit
    amount_cents: Mapped[int] = mapped_column(BigInteger)
    currency: Mapped[str] = mapped_column(String(3))
    source: Mapped[str] = mapped_column(String(32))  # charge/payment/adjustment
    source_id: Mapped[int] = mapped_column(Integer)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class ChannelMapping(Base):
    __tablename__ = "channel_mappings"
    __table_args__ = {"schema": DB_SCHEMA} if DB_SCHEMA else {}
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    property_id: Mapped[int] = mapped_column(Integer)
    channel: Mapped[str] = mapped_column(String(40))
    external_id: Mapped[str] = mapped_column(String(120))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class ChannelEvent(Base):
    __tablename__ = "channel_events"
    __table_args__ = {"schema": DB_SCHEMA} if DB_SCHEMA else {}
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    channel: Mapped[str] = mapped_column(String(40))
    event_type: Mapped[str] = mapped_column(String(40))
    payload_json: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class HousekeepingTask(Base):
    __tablename__ = "hk_tasks"
    __table_args__ = {"schema": DB_SCHEMA} if DB_SCHEMA else {}
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    room_id: Mapped[int] = mapped_column(Integer)
    status: Mapped[str] = mapped_column(String(24), default="open")  # open/in_progress/done
    priority: Mapped[str] = mapped_column(String(16), default="normal")  # low/normal/high
    note: Mapped[Optional[str]] = mapped_column(String(400), default=None)
    assignee: Mapped[Optional[str]] = mapped_column(String(120), default=None)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())


class MaintenanceIssue(Base):
    __tablename__ = "maintenance_issues"
    __table_args__ = {"schema": DB_SCHEMA} if DB_SCHEMA else {}
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    room_id: Mapped[int] = mapped_column(Integer)
    status: Mapped[str] = mapped_column(String(24), default="open")  # open/in_progress/resolved
    severity: Mapped[str] = mapped_column(String(16), default="medium")  # low/medium/high
    title: Mapped[str] = mapped_column(String(200))
    note: Mapped[Optional[str]] = mapped_column(String(400), default=None)
    reported_by: Mapped[Optional[str]] = mapped_column(String(120), default=None)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())


engine = create_engine(DB_URL, future=True)


def get_session() -> Session:
    with Session(engine) as s:
        yield s


def _startup():
    Base.metadata.create_all(engine)


app.router.on_startup.append(_startup)


class PropertyCreate(BaseModel):
    name: str
    city: Optional[str] = None
    timezone: str = "UTC"
    currency: str = Field(default="USD", min_length=3, max_length=3)


class PropertyOut(BaseModel):
    id: int
    name: str
    city: Optional[str]
    timezone: str
    currency: str
    created_at: Optional[datetime]
    model_config = ConfigDict(from_attributes=True)


@router.post("/properties", response_model=PropertyOut)
def create_property(req: PropertyCreate, s: Session = Depends(get_session)):
    p = Property(
        name=req.name.strip(),
        city=req.city or None,
        timezone=req.timezone,
        currency=req.currency.upper(),
    )
    s.add(p); s.commit(); s.refresh(p)
    return p


@router.get("/properties", response_model=List[PropertyOut])
def list_properties(s: Session = Depends(get_session)):
    stmt = select(Property).order_by(Property.id.desc())
    return s.execute(stmt).scalars().all()


class RoomTypeCreate(BaseModel):
    property_id: int
    code: Optional[str] = None
    name: str
    base_occupancy: int = Field(default=1, ge=1, le=10)
    max_occupancy: int = Field(default=2, ge=1, le=12)
    max_guests: Optional[int] = None
    description: Optional[str] = None


class RoomTypeOut(BaseModel):
    id: int
    property_id: int
    code: str
    name: str
    base_occupancy: int
    max_occupancy: int
    max_guests: int
    description: Optional[str]
    model_config = ConfigDict(from_attributes=True)


@router.post("/room_types", response_model=RoomTypeOut)
def create_room_type(req: RoomTypeCreate, s: Session = Depends(get_session)):
    max_occ = req.max_guests if req.max_guests is not None else req.max_occupancy
    base_occ = req.base_occupancy if req.base_occupancy <= max_occ else max_occ
    if base_occ > max_occ:
        raise HTTPException(status_code=400, detail="base_occupancy cannot exceed max_occupancy")
    code = (req.code or req.name).strip().upper().replace(" ", "-")[0:40]
    rt = RoomType(
        property_id=req.property_id,
        code=code,
        name=req.name.strip(),
        base_occupancy=base_occ,
        max_occupancy=max_occ,
        description=req.description or None,
    )
    s.add(rt); s.commit(); s.refresh(rt)
    return rt


@router.get("/room_types", response_model=List[RoomTypeOut])
def list_room_types(property_id: Optional[int] = None, s: Session = Depends(get_session)):
    stmt = select(RoomType)
    if property_id:
        stmt = stmt.where(RoomType.property_id == property_id)
    stmt = stmt.order_by(RoomType.id.desc())
    return s.execute(stmt).scalars().all()


class RoomCreate(BaseModel):
    property_id: int
    room_type_id: int
    number: Optional[str] = None
    code: Optional[str] = None
    status: str = "in_service"
    housekeeping_status: str = "clean"


class RoomOut(BaseModel):
    id: int
    property_id: int
    room_type_id: int
    code: str
    number: str
    status: str
    housekeeping_status: str
    model_config = ConfigDict(from_attributes=True)


@router.post("/rooms", response_model=RoomOut)
def create_room(req: RoomCreate, s: Session = Depends(get_session)):
    if req.status not in ("in_service", "out_of_order"):
        raise HTTPException(status_code=400, detail="bad status")
    number = (req.number or req.code or "").strip()
    if not number:
        raise HTTPException(status_code=400, detail="room number/code required")
    rm = Room(
        property_id=req.property_id,
        room_type_id=req.room_type_id,
        number=number,
        status=req.status,
        housekeeping_status=req.housekeeping_status,
    )
    s.add(rm); s.commit(); s.refresh(rm)
    return rm


@router.get("/rooms", response_model=List[RoomOut])
def list_rooms(property_id: Optional[int] = None, s: Session = Depends(get_session)):
    stmt = select(Room)
    if property_id:
        stmt = stmt.where(Room.property_id == property_id)
    stmt = stmt.order_by(Room.id.desc())
    return s.execute(stmt).scalars().all()


class RatePlanCreate(BaseModel):
    property_id: int
    code: Optional[str] = None
    name: str
    base_rate_cents: Optional[int] = Field(default=None, ge=0)
    price_per_night_cents: Optional[int] = Field(default=None, ge=0)
    currency: str = Field(default="USD", min_length=3, max_length=3)
    is_public: bool = True
    room_type_id: Optional[int] = None  # optional convenience to create a base daily rate


class RatePlanOut(BaseModel):
    id: int
    property_id: int
    code: str
    name: str
    room_type_id: Optional[int]
    base_rate_cents: int
    price_per_night_cents: int
    currency: str
    is_public: bool
    model_config = ConfigDict(from_attributes=True)


@router.post("/rate_plans", response_model=RatePlanOut)
def create_rate_plan(req: RatePlanCreate, s: Session = Depends(get_session)):
    code = (req.code or req.name).strip().upper().replace(" ", "-")[0:50]
    base_rate = req.base_rate_cents if req.base_rate_cents is not None else (req.price_per_night_cents or 0)
    rp = RatePlan(
        property_id=req.property_id,
        code=code,
        name=req.name.strip(),
        room_type_id=req.room_type_id,
        base_rate_cents=base_rate,
        currency=req.currency.upper(),
        is_public=req.is_public,
    )
    s.add(rp); s.commit(); s.refresh(rp)
    # optional base daily rate linked to a room type for simple pricing
    if req.room_type_id:
        dr = DailyRate(
            property_id=req.property_id,
            rate_plan_id=rp.id,
            room_type_id=req.room_type_id,
            date=date.today(),
            amount_cents=base_rate,
            currency=rp.currency,
        )
        s.merge(dr); s.commit()
    return rp


@router.get("/rate_plans", response_model=List[RatePlanOut])
def list_rate_plans(property_id: Optional[int] = None, room_type_id: Optional[int] = None, s: Session = Depends(get_session)):
    stmt = select(RatePlan)
    if property_id:
        stmt = stmt.where(RatePlan.property_id == property_id)
    if room_type_id:
        stmt = stmt.where((RatePlan.room_type_id == room_type_id) | (RatePlan.room_type_id.is_(None)))
    stmt = stmt.order_by(RatePlan.id.desc())
    return s.execute(stmt).scalars().all()


class BookingCreate(BaseModel):
    property_id: int
    room_type_id: int
    room_id: Optional[int] = None
    guest_name: str
    guest_phone: Optional[str] = None
    guest_email: Optional[str] = None
    from_iso: str
    to_iso: str
    adults: int = Field(default=1, ge=1, le=12)
    children: int = Field(default=0, ge=0, le=12)
    source: str = "direct"
    rate_plan_id: Optional[int] = None
    confirm: bool = True


class BookingOut(BaseModel):
    id: int
    property_id: int
    room_type_id: int
    room_id: Optional[int]
    guest_name: Optional[str]
    guest_phone: Optional[str]
    guest_email: Optional[str]
    check_in_date: date
    check_out_date: date
    from_date: date
    to_date: date
    status: str
    total_amount_cents: int
    total_cents: int
    currency: str
    rate_plan_id: Optional[int]
    model_config = ConfigDict(from_attributes=True)


def _nights(from_date: date, to_date: date) -> int:
    nd = (to_date - from_date).days
    if nd <= 0:
        raise HTTPException(status_code=400, detail="check_out must be after check_in")
    return nd


def _ensure_guest(s: Session, property_id: int, name: str, phone: Optional[str], email: Optional[str]) -> Optional[Guest]:
    if not name and not email:
        return None
    guest = None
    if email:
        guest = s.execute(
            select(Guest).where(Guest.property_id == property_id, Guest.email == email)
        ).scalar_one_or_none()
    if guest:
        if phone and not guest.phone:
            guest.phone = phone
        return guest
    guest = Guest(
        property_id=property_id,
        first_name=name.strip() if name else None,
        phone=phone or None,
        email=email or None,
    )
    s.add(guest)
    s.flush()
    return guest


def _calc_price(
    s: Session,
    property_id: int,
    room_type_id: int,
    f: date,
    t: date,
    rate_plan_id: Optional[int],
) -> tuple[int, Optional[int], str]:
    rp = None
    if rate_plan_id:
        rp = s.get(RatePlan, rate_plan_id)
        if rp and rp.property_id != property_id:
            rp = None
    if not rp:
        rp = s.execute(
            select(RatePlan).where(
                RatePlan.property_id == property_id, RatePlan.room_type_id == room_type_id
            ).order_by(RatePlan.id.asc())
        ).scalar_one_or_none()
    if not rp:
        rp = s.execute(
            select(RatePlan).where(RatePlan.property_id == property_id).order_by(RatePlan.id.asc())
        ).scalar_one_or_none()
    currency = rp.currency if rp else "USD"
    if not rp:
        prop = s.get(Property, property_id)
        if prop:
            currency = prop.currency
    total = 0
    nights = _nights(f, t)
    if rp:
        rates = s.execute(
            select(DailyRate).where(
                DailyRate.property_id == property_id,
                DailyRate.room_type_id == room_type_id,
                DailyRate.rate_plan_id == rp.id,
                DailyRate.date >= f,
                DailyRate.date < t,
            )
        ).scalars().all()
        rate_map = {dr.date: dr.amount_cents for dr in rates}
        cur = f
        for _ in range(nights):
            total += int(rate_map.get(cur, rp.base_rate_cents or 0))
            cur = cur + timedelta(days=1)
    return total, (rp.id if rp else None), currency


def _ensure_master_folio(s: Session, reservation_id: int) -> Folio:
    folio = s.execute(
        select(Folio).where(Folio.reservation_id == reservation_id, Folio.is_master.is_(True)).limit(1)
    ).scalar_one_or_none()
    if folio:
        return folio
    folio = Folio(reservation_id=reservation_id, name="Guest", is_master=True)
    s.add(folio)
    s.flush()
    return folio


_STATUS_MAP_IN = {
    "pending": "tentative",
    "tentative": "tentative",
    "confirmed": "confirmed",
    "checked_in": "in_house",
    "in_house": "in_house",
    "checked_out": "checked_out",
    "canceled": "cancelled",
    "cancelled": "cancelled",
    "no_show": "no_show",
}


def _normalize_status(status: str) -> str:
    norm = _STATUS_MAP_IN.get(status.lower())
    if not norm:
        raise HTTPException(status_code=400, detail="bad status")
    return norm


def _public_status(status: str) -> str:
    return {"tentative": "pending", "cancelled": "canceled", "in_house": "checked_in"}.get(status, status)


def _reservation_to_out(res: Reservation, s: Session) -> BookingOut:
    rr = s.execute(
        select(ReservationRoom).where(ReservationRoom.reservation_id == res.id).order_by(ReservationRoom.id.asc()).limit(1)
    ).scalar_one_or_none()
    guest = s.get(Guest, res.guest_id) if res.guest_id else None
    guest_name = None
    guest_phone = None
    guest_email = None
    if guest:
        guest_name = " ".join(filter(None, [guest.first_name, guest.last_name])).strip() or None
        guest_phone = guest.phone
        guest_email = guest.email
    return BookingOut(
        id=res.id,
        property_id=res.property_id,
        room_type_id=res.room_type_id,
        room_id=rr.room_id if rr else None,
        guest_name=guest_name,
        guest_phone=guest_phone,
        guest_email=guest_email,
        check_in_date=res.check_in_date,
        check_out_date=res.check_out_date,
        from_date=res.check_in_date,
        to_date=res.check_out_date,
        status=_public_status(res.status),
        total_amount_cents=res.total_amount_cents,
        total_cents=res.total_amount_cents,
        currency=res.currency,
        rate_plan_id=res.rate_plan_id,
    )


@router.post("/bookings", response_model=BookingOut)
def create_booking(req: BookingCreate, s: Session = Depends(get_session)):
    try:
        f = datetime.fromisoformat(req.from_iso).date()
        t = datetime.fromisoformat(req.to_iso).date()
    except Exception:
        raise HTTPException(status_code=400, detail="invalid date")
    _nights(f, t)
    # basic availability: count rooms for type minus overlapping reservations
    total_rooms = s.execute(
        select(func.count()).where(Room.room_type_id == req.room_type_id, Room.property_id == req.property_id)
    ).scalar_one()
    overlap = s.execute(
        select(func.count()).where(
            Reservation.room_type_id == req.room_type_id,
            Reservation.property_id == req.property_id,
            Reservation.status.in_(("tentative", "confirmed", "in_house")),
            Reservation.check_in_date < t,
            Reservation.check_out_date > f,
        )
    ).scalar_one()
    if overlap >= total_rooms:
        raise HTTPException(status_code=409, detail="no availability")
    total_cents, rp_id, currency = _calc_price(
        s,
        property_id=req.property_id,
        room_type_id=req.room_type_id,
        f=f,
        t=t,
        rate_plan_id=req.rate_plan_id,
    )
    guest = _ensure_guest(s, req.property_id, req.guest_name, req.guest_phone, req.guest_email)
    res = Reservation(
        property_id=req.property_id,
        guest_id=guest.id if guest else None,
        status="confirmed" if req.confirm else "tentative",
        source=req.source,
        check_in_date=f,
        check_out_date=t,
        adults=req.adults,
        children=req.children,
        room_type_id=req.room_type_id,
        rate_plan_id=rp_id,
        total_amount_cents=total_cents,
        currency=currency,
    )
    s.add(res)
    s.flush()
    rr = ReservationRoom(
        reservation_id=res.id,
        room_id=req.room_id,
        arrival_date=f,
        departure_date=t,
        status="assigned" if req.room_id else "unassigned",
    )
    s.add(rr)
    folio = _ensure_master_folio(s, res.id)
    if total_cents:
        ch = Charge(
            folio_id=folio.id,
            post_date=f,
            description="Lodging",
            amount_cents=total_cents,
            currency=currency,
            tax_included=True,
            kind="charge",
        )
        s.add(ch)
    s.commit(); s.refresh(res)
    return _reservation_to_out(res, s)


@router.get("/bookings", response_model=List[BookingOut])
def list_bookings(property_id: Optional[int] = None, status: str = "", s: Session = Depends(get_session)):
    stmt = select(Reservation)
    if property_id:
        stmt = stmt.where(Reservation.property_id == property_id)
    if status:
        stmt = stmt.where(Reservation.status == _normalize_status(status))
    stmt = stmt.order_by(Reservation.id.desc())
    resos = s.execute(stmt).scalars().all()
    return [_reservation_to_out(r, s) for r in resos]


@router.post("/bookings/{bid}/status", response_model=BookingOut)
def update_booking_status(bid: int, status: str, s: Session = Depends(get_session)):
    bk = s.get(Reservation, bid)
    if not bk:
        raise HTTPException(status_code=404, detail="not found")
    bk.status = _normalize_status(status)
    s.commit(); s.refresh(bk)
    return _reservation_to_out(bk, s)


class AvailabilityOut(BaseModel):
    room_type_id: int
    room_type_name: str
    available: int
    rate_plan_id: Optional[int]
    price_per_night_cents: Optional[int]
    currency: Optional[str]


@router.get("/availability", response_model=List[AvailabilityOut])
def availability(property_id: int, from_iso: str, to_iso: str, s: Session = Depends(get_session)):
    try:
        f = datetime.fromisoformat(from_iso).date()
        t = datetime.fromisoformat(to_iso).date()
    except Exception:
        raise HTTPException(status_code=400, detail="invalid date")
    nights = _nights(f, t)
    rtypes = s.execute(select(RoomType).where(RoomType.property_id == property_id)).scalars().all()
    out: List[AvailabilityOut] = []
    for rt in rtypes:
        total_rooms = s.execute(
            select(func.count()).where(Room.room_type_id == rt.id, Room.property_id == property_id)
        ).scalar_one()
        overlap = s.execute(
            select(func.count()).where(
                Reservation.room_type_id == rt.id,
                Reservation.property_id == property_id,
                Reservation.status.in_(("tentative", "confirmed", "in_house")),
                Reservation.check_in_date < t,
                Reservation.check_out_date > f,
            )
        ).scalar_one()
        avail = max(0, total_rooms - overlap)
        total_price, rp_id, currency = _calc_price(s, property_id, rt.id, f, t, None)
        per_night = int(total_price / nights) if nights and total_price else None
        out.append(
            AvailabilityOut(
                room_type_id=rt.id,
                room_type_name=rt.name,
                available=avail,
                rate_plan_id=rp_id,
                price_per_night_cents=per_night,
                currency=currency if total_price else None,
            )
        )
    return out


@router.post("/rooms/{rid}/housekeeping", response_model=RoomOut)
def update_housekeeping(rid: int, status: str = "clean", s: Session = Depends(get_session)):
    if status not in ("clean", "dirty", "inspected", "out_of_service"):
        raise HTTPException(status_code=400, detail="bad status")
    rm = s.get(Room, rid)
    if not rm:
        raise HTTPException(status_code=404, detail="not found")
    rm.housekeeping_status = status
    s.commit(); s.refresh(rm)
    return rm


class StatsOut(BaseModel):
    occupancy_pct: float
    arrivals: int
    departures: int
    revenue_cents: int
    active_bookings: int
    adr_cents: int
    revpar_cents: int


@router.get("/stats", response_model=StatsOut)
def stats(property_id: int, from_iso: str, to_iso: str, s: Session = Depends(get_session)):
    try:
        f = datetime.fromisoformat(from_iso).date()
        t = datetime.fromisoformat(to_iso).date()
    except Exception:
        raise HTTPException(status_code=400, detail="invalid date")
    total_rooms = s.execute(select(func.count()).where(Room.property_id == property_id)).scalar_one()
    # reservations overlapping range
    bstmt = select(Reservation).where(
        Reservation.property_id == property_id,
        Reservation.check_in_date < t,
        Reservation.check_out_date > f,
        Reservation.status.in_(("tentative", "confirmed", "in_house")),
    )
    bookings = s.execute(bstmt).scalars().all()
    revenue = sum(int(b.total_amount_cents or 0) for b in bookings)
    arrivals = sum(1 for b in bookings if b.check_in_date == f)
    departures = sum(1 for b in bookings if b.check_out_date == t)
    occupancy_pct = 0.0
    adr = 0
    revpar = 0
    if total_rooms > 0:
        occupancy_pct = min(1.0, len(bookings) / float(total_rooms))
        # ADR = revenue / number of occupied rooms (nights approximated by bookings count in window)
        if len(bookings) > 0:
            adr = int(revenue / len(bookings))
        # RevPAR = revenue / available rooms
        revpar = int(revenue / total_rooms) if total_rooms else 0
    return StatsOut(
        occupancy_pct=occupancy_pct,
        arrivals=arrivals,
        departures=departures,
        revenue_cents=revenue,
        active_bookings=len(bookings),
        adr_cents=adr,
        revpar_cents=revpar,
    )


class ChargeCreate(BaseModel):
    kind: str  # charge|payment|refund|fee|tax
    description: Optional[str] = None
    amount_cents: int
    method: Optional[str] = None
    post_date_iso: Optional[str] = None
    currency: Optional[str] = None


class ChargeOut(BaseModel):
    id: int
    reservation_id: int
    folio_id: int
    kind: str
    description: Optional[str]
    amount_cents: int
    currency: str
    post_date: date
    method: Optional[str]
    created_at: Optional[datetime]
    model_config = ConfigDict(from_attributes=True)


@router.post("/bookings/{bid}/charges", response_model=ChargeOut)
def add_charge(bid: int, req: ChargeCreate, s: Session = Depends(get_session)):
    bk = s.get(Reservation, bid)
    if not bk:
        raise HTTPException(status_code=404, detail="booking not found")
    kind = req.kind.lower()
    if kind not in ("charge", "payment", "refund", "fee", "tax"):
        raise HTTPException(status_code=400, detail="bad kind")
    try:
        post_date = datetime.fromisoformat(req.post_date_iso).date() if req.post_date_iso else bk.check_in_date
    except Exception:
        raise HTTPException(status_code=400, detail="invalid post_date")
    folio = _ensure_master_folio(s, bk.id)
    amt = req.amount_cents
    if kind == "payment":
        amt = -abs(req.amount_cents)
    if kind == "refund":
        amt = abs(req.amount_cents)
    ch = Charge(
        kind=kind,
        description=req.description or None,
        amount_cents=amt,
        currency=(req.currency or bk.currency).upper(),
        post_date=post_date,
        folio_id=folio.id,
        method=req.method or None,
    )
    s.add(ch); s.commit(); s.refresh(ch)
    return ChargeOut(
        id=ch.id,
        reservation_id=bk.id,
        folio_id=folio.id,
        kind=ch.kind,
        description=ch.description,
        amount_cents=ch.amount_cents,
        currency=ch.currency,
        post_date=ch.post_date,
        method=ch.method,
        created_at=ch.created_at,
    )


@router.get("/bookings/{bid}/folio", response_model=List[ChargeOut])
def get_folio(bid: int, s: Session = Depends(get_session)):
    bk = s.get(Reservation, bid)
    if not bk:
        raise HTTPException(status_code=404, detail="booking not found")
    folio_ids = select(Folio.id).where(Folio.reservation_id == bid)
    stmt = select(Charge).where(Charge.folio_id.in_(folio_ids)).order_by(Charge.post_date.asc(), Charge.id.asc())
    charges = s.execute(stmt).scalars().all()
    return [
        ChargeOut(
            id=c.id,
            reservation_id=bk.id,
            folio_id=c.folio_id,
            kind=c.kind,
            description=c.description,
            amount_cents=c.amount_cents,
            currency=c.currency,
            post_date=c.post_date,
            method=c.method,
            created_at=c.created_at,
        )
        for c in charges
    ]


class PaymentLinkOut(BaseModel):
    url: str
    balance_cents: int


@router.get("/bookings/{bid}/payment_link", response_model=PaymentLinkOut)
def payment_link(bid: int, s: Session = Depends(get_session)):
    bk = s.get(Reservation, bid)
    if not bk:
        raise HTTPException(status_code=404, detail="booking not found")
    folio_ids = select(Folio.id).where(Folio.reservation_id == bid)
    charges = s.execute(select(Charge).where(Charge.folio_id.in_(folio_ids))).scalars().all()
    balance = sum(c.amount_cents for c in charges)
    # Reservation total is a charge if missing folio entries
    if not charges:
        balance = bk.total_amount_cents
    token = f"{bid}-{int(datetime.utcnow().timestamp())}"
    link = PAYMENT_LINK_BASE.rstrip("/") + f"/?ref={token}&booking_id={bid}&amount_cents={max(balance,0)}"
    return PaymentLinkOut(url=link, balance_cents=balance)


@router.get("/bookings/{bid}/invoice.pdf")
def booking_invoice_pdf(bid: int, s: Session = Depends(get_session)):
    bk = s.get(Reservation, bid)
    if not bk:
        raise HTTPException(status_code=404, detail="booking not found")
    folio_ids = select(Folio.id).where(Folio.reservation_id == bid)
    charges = s.execute(select(Charge).where(Charge.folio_id.in_(folio_ids)).order_by(Charge.id.asc())).scalars().all()
    total = sum(c.amount_cents for c in charges) or bk.total_amount_cents
    guest = s.get(Guest, bk.guest_id) if bk.guest_id else None
    guest_name = " ".join(filter(None, [guest.first_name, guest.last_name])) if guest else ""
    # Minimal PDF (no external deps) — text-only, valid-enough for preview/print.
    lines = [
        "%PDF-1.4",
        "1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj",
        "2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj",
        "3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 4 0 R /Resources << >> >> endobj",
    ]
    text_lines = [
        f"Invoice for booking #{bk.id}",
        f"Guest: {guest_name}",
        f"Stay: {bk.check_in_date} -> {bk.check_out_date}",
        f"Total: {total} cents",
        "Charges:",
    ]
    y = 780
    content = ["BT /F1 12 Tf"]
    for t in text_lines:
        content.append(f"1 0 0 1 40 {y} Tm ({t}) Tj")
        y -= 16
    for c in charges:
        content.append(f"1 0 0 1 40 {y} Tm ({c.kind}: {c.amount_cents} {c.description or ''}) Tj")
        y -= 14
    content.append("ET")
    stream = "\n".join(content).encode("utf-8")
    lines.append(f"4 0 obj << /Length {len(stream)} >> stream".encode("utf-8").decode())
    lines.append(stream.decode())
    lines.append("endstream endobj")
    lines.append("xref 0 5")
    lines.append("0000000000 65535 f ")
    lines.append("trailer << /Size 5 /Root 1 0 R >>")
    lines.append("startxref 0")
    lines.append("%%EOF")
    pdf_bytes = "\n".join(lines).encode("utf-8")
    headers = {"Content-Disposition": f'inline; filename="invoice_{bid}.pdf"'}
    return Response(content=pdf_bytes, media_type="application/pdf", headers=headers)


@router.get("/reports/performance")
def report_performance(property_id: int, from_iso: str, to_iso: str, s: Session = Depends(get_session)):
    try:
        f = datetime.fromisoformat(from_iso).date()
        t = datetime.fromisoformat(to_iso).date()
    except Exception:
        raise HTTPException(status_code=400, detail="invalid date")
    total_rooms = s.execute(select(func.count()).where(Room.property_id == property_id)).scalar_one()
    bstmt = select(Reservation).where(
        Reservation.property_id == property_id,
        Reservation.check_in_date < t,
        Reservation.check_out_date > f,
        Reservation.status.in_(("tentative", "confirmed", "in_house")),
    )
    bookings = s.execute(bstmt).scalars().all()
    revenue = sum(int(b.total_amount_cents or 0) for b in bookings)
    adr = int(revenue / len(bookings)) if bookings else 0
    revpar = int(revenue / total_rooms) if total_rooms else 0
    occ_pct = min(1.0, len(bookings) / float(total_rooms)) if total_rooms else 0.0
    rows = [
        ["metric", "value"],
        ["rooms", str(total_rooms)],
        ["bookings", str(len(bookings))],
        ["revenue_cents", str(revenue)],
        ["adr_cents", str(adr)],
        ["revpar_cents", str(revpar)],
        ["occupancy_pct", f"{occ_pct:.4f}"],
    ]
    csv = "\n".join([",".join(r) for r in rows])
    headers = {"Content-Disposition": f'attachment; filename="performance_{property_id}.csv"'}
    return Response(content=csv, media_type="text/csv", headers=headers)


class HKTaskCreate(BaseModel):
    room_id: int
    priority: str = "normal"
    note: Optional[str] = None
    assignee: Optional[str] = None


class HKTaskOut(BaseModel):
    id: int
    room_id: int
    status: str
    priority: str
    note: Optional[str]
    assignee: Optional[str]
    created_at: Optional[datetime]
    updated_at: Optional[datetime]
    model_config = ConfigDict(from_attributes=True)


@router.post("/housekeeping/tasks", response_model=HKTaskOut)
def create_hk_task(req: HKTaskCreate, s: Session = Depends(get_session)):
    if req.priority not in ("low", "normal", "high"):
        raise HTTPException(status_code=400, detail="bad priority")
    t = HousekeepingTask(
        room_id=req.room_id,
        priority=req.priority,
        note=req.note or None,
        assignee=req.assignee or None,
    )
    s.add(t); s.commit(); s.refresh(t)
    return t


@router.get("/housekeeping/tasks", response_model=List[HKTaskOut])
def list_hk_tasks(room_id: Optional[int] = None, status: str = "", s: Session = Depends(get_session)):
    stmt = select(HousekeepingTask)
    if room_id:
        stmt = stmt.where(HousekeepingTask.room_id == room_id)
    if status:
        stmt = stmt.where(HousekeepingTask.status == status)
    stmt = stmt.order_by(HousekeepingTask.id.desc())
    return s.execute(stmt).scalars().all()


class HKTaskUpdate(BaseModel):
    status: Optional[str] = None
    note: Optional[str] = None
    assignee: Optional[str] = None


@router.post("/housekeeping/tasks/{tid}", response_model=HKTaskOut)
def update_hk_task(tid: int, req: HKTaskUpdate, s: Session = Depends(get_session)):
    t = s.get(HousekeepingTask, tid)
    if not t:
        raise HTTPException(status_code=404, detail="not found")
    if req.status:
        if req.status not in ("open", "in_progress", "done"):
            raise HTTPException(status_code=400, detail="bad status")
        t.status = req.status
    if req.note is not None:
        t.note = req.note
    if req.assignee is not None:
        t.assignee = req.assignee
    s.commit(); s.refresh(t)
    return t


class MaintenanceCreate(BaseModel):
    room_id: int
    title: str
    severity: str = "medium"
    note: Optional[str] = None
    reported_by: Optional[str] = None


class MaintenanceOut(BaseModel):
    id: int
    room_id: int
    title: str
    severity: str
    status: str
    note: Optional[str]
    reported_by: Optional[str]
    created_at: Optional[datetime]
    updated_at: Optional[datetime]
    model_config = ConfigDict(from_attributes=True)


@router.post("/maintenance/issues", response_model=MaintenanceOut)
def create_issue(req: MaintenanceCreate, s: Session = Depends(get_session)):
    if req.severity not in ("low", "medium", "high"):
        raise HTTPException(status_code=400, detail="bad severity")
    m = MaintenanceIssue(
        room_id=req.room_id,
        title=req.title.strip(),
        severity=req.severity,
        note=req.note or None,
        reported_by=req.reported_by or None,
    )
    s.add(m); s.commit(); s.refresh(m)
    return m


@router.get("/maintenance/issues", response_model=List[MaintenanceOut])
def list_issues(room_id: Optional[int] = None, status: str = "", s: Session = Depends(get_session)):
    stmt = select(MaintenanceIssue)
    if room_id:
        stmt = stmt.where(MaintenanceIssue.room_id == room_id)
    if status:
        stmt = stmt.where(MaintenanceIssue.status == status)
    stmt = stmt.order_by(MaintenanceIssue.id.desc())
    return s.execute(stmt).scalars().all()


class MaintenanceUpdate(BaseModel):
    status: Optional[str] = None
    severity: Optional[str] = None
    note: Optional[str] = None
    assignee: Optional[str] = None  # placeholder, not stored


@router.post("/maintenance/issues/{mid}", response_model=MaintenanceOut)
def update_issue(mid: int, req: MaintenanceUpdate, s: Session = Depends(get_session)):
    m = s.get(MaintenanceIssue, mid)
    if not m:
        raise HTTPException(status_code=404, detail="not found")
    if req.status:
        if req.status not in ("open", "in_progress", "resolved"):
            raise HTTPException(status_code=400, detail="bad status")
        m.status = req.status
    if req.severity:
        if req.severity not in ("low", "medium", "high"):
            raise HTTPException(status_code=400, detail="bad severity")
        m.severity = req.severity
    if req.note is not None:
        m.note = req.note
    s.commit(); s.refresh(m)
    return m


# ---------------- Guest-facing booking engine ----------------

class GuestAvailabilityOut(BaseModel):
    room_type_id: int
    room_type_name: str
    available: int
    price_per_night_cents: Optional[int]
    currency: Optional[str]
    max_guests: Optional[int]


@router.get("/guest/availability", response_model=List[GuestAvailabilityOut])
def guest_availability(property_id: int, from_iso: str, to_iso: str, s: Session = Depends(get_session)):
    avail = availability(property_id=property_id, from_iso=from_iso, to_iso=to_iso, s=s)
    rtypes = {
        rt.id: rt
        for rt in s.execute(select(RoomType).where(RoomType.property_id == property_id)).scalars().all()
    }
    out: List[GuestAvailabilityOut] = []
    for a in avail:
        rt = rtypes.get(a.room_type_id)
        out.append(
            GuestAvailabilityOut(
                room_type_id=a.room_type_id,
                room_type_name=a.room_type_name,
                available=a.available,
                price_per_night_cents=a.price_per_night_cents,
                currency=a.currency,
                max_guests=rt.max_occupancy if rt else None,
            )
        )
    return out


class GuestBookReq(BaseModel):
    property_id: int
    room_type_id: int
    guest_name: str
    guest_phone: Optional[str] = None
    guest_email: Optional[str] = None
    from_iso: str
    to_iso: str
    adults: int = 1
    children: int = 0
    rate_plan_id: Optional[int] = None
    confirm: bool = False


@router.post("/guest/book", response_model=BookingOut)
def guest_book(req: GuestBookReq, s: Session = Depends(get_session)):
    # reuse create_booking but without requiring operator auth; keeps same availability guard
    bk = create_booking(
        BookingCreate(
            property_id=req.property_id,
            room_type_id=req.room_type_id,
            room_id=None,
            guest_name=req.guest_name,
            guest_phone=req.guest_phone,
            guest_email=req.guest_email,
            from_iso=req.from_iso,
            to_iso=req.to_iso,
            adults=req.adults,
            children=req.children,
            rate_plan_id=req.rate_plan_id,
            source="guest",
            confirm=req.confirm,
        ),
        s,
    )
    return bk

class ChannelMappingCreate(BaseModel):
    property_id: int
    channel: str  # e.g. airbnb/booking/expedia
    external_id: str


class ChannelMappingOut(BaseModel):
    id: int
    property_id: int
    channel: str
    external_id: str
    model_config = ConfigDict(from_attributes=True)


@router.post("/channel/mappings", response_model=ChannelMappingOut)
def create_channel_mapping(req: ChannelMappingCreate, s: Session = Depends(get_session)):
    m = ChannelMapping(property_id=req.property_id, channel=req.channel.lower(), external_id=req.external_id.strip())
    s.add(m); s.commit(); s.refresh(m)
    return m


@router.get("/channel/mappings", response_model=List[ChannelMappingOut])
def list_channel_mappings(property_id: Optional[int] = None, s: Session = Depends(get_session)):
    stmt = select(ChannelMapping)
    if property_id:
        stmt = stmt.where(ChannelMapping.property_id == property_id)
    stmt = stmt.order_by(ChannelMapping.id.desc())
    return s.execute(stmt).scalars().all()


class ReservationWebhookPayload(BaseModel):
    property_id: Optional[int] = None
    room_type_id: Optional[int] = None
    guest_name: Optional[str] = None
    guest_phone: Optional[str] = None
    from_iso: Optional[str] = None
    to_iso: Optional[str] = None
    status: Optional[str] = None  # confirmed/canceled/pending
    total_cents: Optional[int] = None
    raw: dict = Field(default_factory=dict)


class AvailabilityWebhookPayload(BaseModel):
    property_id: Optional[int] = None
    room_type_id: Optional[int] = None
    available: Optional[int] = None
    price_per_night_cents: Optional[int] = None
    currency: Optional[str] = None
    raw: dict = Field(default_factory=dict)


def _record_event(s: Session, channel: str, event_type: str, payload: BaseModel):
    ev = ChannelEvent(channel=channel.lower(), event_type=event_type, payload_json=json.dumps(payload.model_dump()))
    s.add(ev); s.commit()


@router.post("/channel/webhooks/{channel}/reservation")
def channel_reservation_webhook(channel: str, payload: ReservationWebhookPayload, s: Session = Depends(get_session)):
    _record_event(s, channel, "reservation", payload)
    # Try to materialize a booking when enough data is present
    if payload.property_id and payload.room_type_id and payload.from_iso and payload.to_iso:
        try:
            f = datetime.fromisoformat(payload.from_iso).date()  # type: ignore[arg-type]
            t = datetime.fromisoformat(payload.to_iso).date()  # type: ignore[arg-type]
        except Exception:
            f = t = None  # type: ignore[assignment]
        if f and t:
            total_rooms = s.execute(
                select(func.count()).where(Room.room_type_id == payload.room_type_id)
            ).scalar_one()
            overlap = s.execute(
                select(func.count()).where(
                    Reservation.room_type_id == payload.room_type_id,
                    Reservation.status.in_(("tentative", "confirmed", "in_house")),
                    Reservation.check_in_date < t,
                    Reservation.check_out_date > f,
                )
            ).scalar_one()
            if overlap < total_rooms:
                prop = s.get(Property, payload.property_id)
                currency = prop.currency if prop else "USD"
                guest = _ensure_guest(
                    s,
                    payload.property_id,
                    payload.guest_name or "OTA Guest",
                    payload.guest_phone,
                    None,
                )
                status = _normalize_status(payload.status) if payload.status else "confirmed"
                res = Reservation(
                    property_id=payload.property_id,
                    room_type_id=payload.room_type_id,
                    guest_id=guest.id if guest else None,
                    status=status,
                    source=channel.lower(),
                    check_in_date=f,
                    check_out_date=t,
                    adults=1,
                    children=0,
                    total_amount_cents=payload.total_cents or 0,
                    currency=currency,
                )
                s.add(res)
                s.flush()
                s.add(
                    ReservationRoom(
                        reservation_id=res.id,
                        room_id=None,
                        arrival_date=f,
                        departure_date=t,
                        status="unassigned",
                    )
                )
                folio = _ensure_master_folio(s, res.id)
                if payload.total_cents:
                    s.add(
                        Charge(
                            folio_id=folio.id,
                            post_date=f,
                            description="OTA Booking",
                            amount_cents=payload.total_cents,
                            currency=currency,
                            kind="charge",
                        )
                    )
                s.commit()
    return {"ok": True}


@router.post("/channel/webhooks/{channel}/availability")
def channel_availability_webhook(channel: str, payload: AvailabilityWebhookPayload, s: Session = Depends(get_session)):
    _record_event(s, channel, "availability", payload)
    # Stub: we only persist the event today.
    return {"ok": True}


app.include_router(router)
