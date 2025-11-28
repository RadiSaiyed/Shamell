from fastapi import FastAPI, HTTPException, Depends, Request, Header
from pydantic import BaseModel, Field, ConfigDict
from typing import Optional, List
import os
from shamell_shared import RequestIDMiddleware, configure_cors, add_standard_health, setup_json_logging
from sqlalchemy import create_engine, String, Integer, BigInteger, DateTime, Float, func
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, Session
from sqlalchemy import select
from datetime import datetime, timezone
import uuid
import httpx


def _env_or(key: str, default: str) -> str:
    v = os.getenv(key)
    return v if v is not None else default


app = FastAPI(title="Carrental API", version="0.1.0")
setup_json_logging()
app.add_middleware(RequestIDMiddleware)
configure_cors(app, os.getenv("ALLOWED_ORIGINS", "*"))
add_standard_health(app)

router = APIRouter()


DB_URL = _env_or("DB_URL", "sqlite+pysqlite:////tmp/carrental.db")
DB_SCHEMA = os.getenv("DB_SCHEMA") if not DB_URL.startswith("sqlite") else None
PAYMENTS_BASE = _env_or("PAYMENTS_BASE_URL", "")


class Base(DeclarativeBase):
    pass


class Car(Base):
    __tablename__ = "cars"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    title: Mapped[str] = mapped_column(String(200))
    make: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    model: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    year: Mapped[Optional[int]] = mapped_column(Integer, default=None)
    city: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    price_per_day_cents: Mapped[Optional[int]] = mapped_column(BigInteger, default=None)
    price_per_hour_cents: Mapped[Optional[int]] = mapped_column(BigInteger, default=None)
    currency: Mapped[str] = mapped_column(String(3), default="SYP")
    owner_wallet_id: Mapped[Optional[str]] = mapped_column(String(36), default=None)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Booking(Base):
    __tablename__ = "bookings"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    car_id: Mapped[int] = mapped_column(Integer)
    renter_name: Mapped[Optional[str]] = mapped_column(String(120), default=None)
    renter_phone: Mapped[Optional[str]] = mapped_column(String(32), default=None)
    renter_wallet_id: Mapped[Optional[str]] = mapped_column(String(36), default=None)
    from_ts: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True))
    to_ts: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True))
    status: Mapped[str] = mapped_column(String(16), default="requested")  # requested|confirmed|canceled|completed
    amount_cents: Mapped[Optional[int]] = mapped_column(BigInteger, default=None)
    payments_txn_id: Mapped[Optional[str]] = mapped_column(String(64), default=None)
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


class CarCreate(BaseModel):
    title: str
    price_per_day_cents: Optional[int] = Field(default=None, ge=0)
    price_per_hour_cents: Optional[int] = Field(default=None, ge=0)
    make: Optional[str] = None
    model: Optional[str] = None
    year: Optional[int] = Field(default=None, ge=1900, le=2100)
    city: Optional[str] = None
    owner_wallet_id: Optional[str] = None


class CarUpdate(BaseModel):
    title: Optional[str] = None
    price_per_day_cents: Optional[int] = Field(default=None, ge=0)
    price_per_hour_cents: Optional[int] = Field(default=None, ge=0)
    make: Optional[str] = None
    model: Optional[str] = None
    year: Optional[int] = Field(default=None, ge=1900, le=2100)
    city: Optional[str] = None
    owner_wallet_id: Optional[str] = None


class CarOut(BaseModel):
    id: int
    title: str
    make: Optional[str]
    model: Optional[str]
    year: Optional[int]
    city: Optional[str]
    price_per_day_cents: Optional[int]
    price_per_hour_cents: Optional[int]
    currency: str
    owner_wallet_id: Optional[str]
    model_config = ConfigDict(from_attributes=True)


@router.post("/cars", response_model=CarOut)
def create_car(req: CarCreate, s: Session = Depends(get_session)):
    c = Car(
        title=req.title.strip(),
        make=(req.make or None), model=(req.model or None),
        year=req.year, city=(req.city or None),
        price_per_day_cents=req.price_per_day_cents,
        price_per_hour_cents=req.price_per_hour_cents,
        owner_wallet_id=(req.owner_wallet_id or None),
    )
    s.add(c); s.commit(); s.refresh(c)
    return c


@router.get("/cars", response_model=List[CarOut])
def list_cars(q: str = "", city: str = "", make: str = "", limit: int = 20, s: Session = Depends(get_session)):
    limit = max(1, min(limit, 100))
    stmt = select(Car)
    if q:
        stmt = stmt.where(func.lower(Car.title).like(f"%{q.lower()}%"))
    if city:
        stmt = stmt.where(func.lower(Car.city) == city.lower())
    if make:
        stmt = stmt.where(func.lower(Car.make) == make.lower())
    stmt = stmt.order_by(Car.id.desc()).limit(limit)
    return s.execute(stmt).scalars().all()


@router.get("/cars/{car_id}", response_model=CarOut)
def get_car(car_id: int, s: Session = Depends(get_session)):
    c = s.get(Car, car_id)
    if not c:
        raise HTTPException(status_code=404, detail="not found")
    return c


@router.patch("/cars/{car_id}", response_model=CarOut)
def update_car(car_id: int, req: CarUpdate, s: Session = Depends(get_session)):
    c = s.get(Car, car_id)
    if not c:
        raise HTTPException(status_code=404, detail="not found")
    data = req.model_dump(exclude_unset=True)
    for k, v in data.items():
        setattr(c, k, v)
    s.add(c); s.commit(); s.refresh(c)
    return c


@router.delete("/cars/{car_id}")
def delete_car(car_id: int, s: Session = Depends(get_session)):
    c = s.get(Car, car_id)
    if not c:
        raise HTTPException(status_code=404, detail="not found")
    s.delete(c); s.commit()
    return {"ok": True}


def _hours_between(a: datetime, b: datetime) -> float:
    return max(0.0, (b - a).total_seconds() / 3600.0)


def _quote_amount(c: Car, hours: float) -> int:
    import math
    pd = c.price_per_day_cents or 0
    ph = c.price_per_hour_cents or 0
    if pd <= 0 and ph <= 0:
        return 0
    days = math.ceil(hours / 24.0)
    cost_day = (days * pd) if pd > 0 else None
    cost_hour = (math.ceil(hours) * ph) if ph > 0 else None
    opts = [x for x in [cost_day, cost_hour] if x is not None]
    return int(min(opts) if opts else 0)


class QuoteReq(BaseModel):
    car_id: int
    from_iso: str
    to_iso: str


class QuoteOut(BaseModel):
    hours: float
    amount_cents: int
    currency: str


@router.post("/quote", response_model=QuoteOut)
def quote(req: QuoteReq, s: Session = Depends(get_session)):
    c = s.get(Car, req.car_id)
    if not c:
        raise HTTPException(status_code=404, detail="car not found")
    try:
        start = datetime.fromisoformat(req.from_iso.replace("Z", "+00:00"))
        end = datetime.fromisoformat(req.to_iso.replace("Z", "+00:00"))
        if end <= start:
            raise ValueError("range")
    except Exception:
        raise HTTPException(status_code=400, detail="invalid time range")
    hours = _hours_between(start, end)
    amount = _quote_amount(c, hours)
    return QuoteOut(hours=round(hours, 2), amount_cents=amount, currency=c.currency)


def _overlaps(a_start: datetime, a_end: datetime, b_start: datetime, b_end: datetime) -> bool:
    return (a_start < b_end) and (a_end > b_start)


class BookReq(BaseModel):
    car_id: int
    renter_name: Optional[str] = None
    renter_phone: Optional[str] = None
    renter_wallet_id: Optional[str] = None
    from_iso: str
    to_iso: str
    confirm: bool = False


class BookingOut(BaseModel):
    id: str
    car_id: int
    renter_name: Optional[str]
    renter_phone: Optional[str]
    from_iso: str
    to_iso: str
    status: str
    amount_cents: Optional[int]
    payments_txn_id: Optional[str]
    model_config = ConfigDict(from_attributes=False)


def _pay_transfer(from_wallet: str, to_wallet: str, amount_cents: int, ikey: str, ref: str) -> dict:
    if not PAYMENTS_BASE:
        raise RuntimeError("PAYMENTS_BASE_URL not configured")
    url = PAYMENTS_BASE.rstrip('/') + '/transfer'
    headers = {"Content-Type": "application/json", "Idempotency-Key": ikey, "X-Merchant": "carrental", "X-Ref": ref}
    payload = {"from_wallet_id": from_wallet, "to_wallet_id": to_wallet, "amount_cents": amount_cents}
    r = httpx.post(url, json=payload, headers=headers, timeout=10)
    r.raise_for_status()
    return r.json()


@router.post("/book", response_model=BookingOut)
def book(req: BookReq, idempotency_key: Optional[str] = Header(default=None, alias="Idempotency-Key"), s: Session = Depends(get_session)):
    c = s.get(Car, req.car_id)
    if not c:
        raise HTTPException(status_code=404, detail="car not found")
    try:
        start = datetime.fromisoformat(req.from_iso.replace("Z", "+00:00"))
        end = datetime.fromisoformat(req.to_iso.replace("Z", "+00:00"))
        if end <= start:
            raise ValueError("range")
    except Exception:
        raise HTTPException(status_code=400, detail="invalid time range")
    # availability: any overlapping requested/confirmed booking blocks
    rows = s.execute(select(Booking).where(Booking.car_id == c.id, Booking.status.in_(["requested", "confirmed"])) ).scalars().all()
    for b in rows:
        if _overlaps(start, end, b.from_ts, b.to_ts):
            raise HTTPException(status_code=409, detail="not available")
    hours = _hours_between(start, end)
    amount = _quote_amount(c, hours)
    if idempotency_key:
        ie = s.get(Idempotency, idempotency_key)
        if ie and ie.ref_id:
            b0 = s.get(Booking, ie.ref_id)
            if b0:
                return BookingOut(id=b0.id, car_id=b0.car_id, renter_name=b0.renter_name, renter_phone=b0.renter_phone, from_iso=b0.from_ts.isoformat(), to_iso=b0.to_ts.isoformat(), status=b0.status, amount_cents=b0.amount_cents, payments_txn_id=b0.payments_txn_id)
    b_id = str(uuid.uuid4())
    status = "requested"
    pay_txn = None
    if req.confirm and c.owner_wallet_id and req.renter_wallet_id and amount > 0:
        # take payment immediately
        resp = _pay_transfer(req.renter_wallet_id, c.owner_wallet_id, amount, ikey=f"booking-{b_id}", ref=f"booking-{b_id}")
        pay_txn = str(resp.get("id") or resp.get("txn_id") or "")
        status = "confirmed"
    b = Booking(id=b_id, car_id=c.id, renter_name=req.renter_name, renter_phone=req.renter_phone, renter_wallet_id=(req.renter_wallet_id or None), from_ts=start, to_ts=end, status=status, amount_cents=amount, payments_txn_id=pay_txn)
    s.add(b); s.commit(); s.refresh(b)
    if idempotency_key:
        try: s.add(Idempotency(key=idempotency_key, ref_id=b.id)); s.commit()
        except Exception: pass
    return BookingOut(id=b.id, car_id=b.car_id, renter_name=b.renter_name, renter_phone=b.renter_phone, from_iso=b.from_ts.isoformat(), to_iso=b.to_ts.isoformat(), status=b.status, amount_cents=b.amount_cents, payments_txn_id=b.payments_txn_id)


@router.get("/bookings/{booking_id}", response_model=BookingOut)
def get_booking(booking_id: str, s: Session = Depends(get_session)):
    b = s.get(Booking, booking_id)
    if not b:
        raise HTTPException(status_code=404, detail="not found")
    return BookingOut(id=b.id, car_id=b.car_id, renter_name=b.renter_name, renter_phone=b.renter_phone, from_iso=b.from_ts.isoformat(), to_iso=b.to_ts.isoformat(), status=b.status, amount_cents=b.amount_cents, payments_txn_id=b.payments_txn_id)


@router.get("/bookings", response_model=List[BookingOut])
def list_bookings(status: str = "", limit: int = 100, s: Session = Depends(get_session)):
    stmt = select(Booking)
    if status:
        stmt = stmt.where(Booking.status == status)
    stmt = stmt.order_by(Booking.created_at.desc()).limit(max(1, min(limit, 500)))
    rows = s.execute(stmt).scalars().all()
    out: List[BookingOut] = []
    for b in rows:
        out.append(BookingOut(id=b.id, car_id=b.car_id, renter_name=b.renter_name, renter_phone=b.renter_phone, from_iso=b.from_ts.isoformat(), to_iso=b.to_ts.isoformat(), status=b.status, amount_cents=b.amount_cents, payments_txn_id=b.payments_txn_id))
    return out


@router.get("/admin/cars/export")
def admin_cars_export(s: Session = Depends(get_session)):
    import io, csv, datetime as _dt
    rows = s.execute(select(Car).order_by(Car.id.desc())).scalars().all()
    def _iter():
        buf = io.StringIO(); w=csv.writer(buf)
        w.writerow(["id","title","make","model","year","city","price_per_day_cents","price_per_hour_cents","currency","owner_wallet_id"])
        yield buf.getvalue(); buf.seek(0); buf.truncate(0)
        for c in rows:
            w.writerow([c.id,c.title,c.make or "",c.model or "",c.year or "",c.city or "",c.price_per_day_cents or 0,c.price_per_hour_cents or 0,c.currency,c.owner_wallet_id or ""])
            yield buf.getvalue(); buf.seek(0); buf.truncate(0)
    filename = f"cars_{_dt.datetime.utcnow().strftime('%Y%m%d_%H%M%S')}.csv"
    headers = {"Content-Disposition": f"attachment; filename=\"{filename}\""}
    return StreamingResponse(_iter(), media_type="text/csv", headers=headers)


@router.get("/admin/bookings/export")
def admin_bookings_export(status: str = "", limit: int = 1000, s: Session = Depends(get_session)):
    import io, csv, datetime as _dt
    stmt = select(Booking)
    if status:
        stmt = stmt.where(Booking.status == status)
    stmt = stmt.order_by(Booking.created_at.desc()).limit(max(1, min(limit, 5000)))
    rows = s.execute(stmt).scalars().all()
    def _iter():
        buf = io.StringIO(); w=csv.writer(buf)
        w.writerow(["id","car_id","renter_name","renter_phone","from_iso","to_iso","status","amount_cents","payments_txn_id","created_at"])
        yield buf.getvalue(); buf.seek(0); buf.truncate(0)
        for b in rows:
            w.writerow([b.id,b.car_id,b.renter_name or "",b.renter_phone or "",(b.from_ts.isoformat() if b.from_ts else ""),(b.to_ts.isoformat() if b.to_ts else ""),b.status,b.amount_cents or 0,b.payments_txn_id or "",(b.created_at.isoformat() if b.created_at else "")])
            yield buf.getvalue(); buf.seek(0); buf.truncate(0)
    filename = f"bookings_{_dt.datetime.utcnow().strftime('%Y%m%d_%H%M%S')}.csv"
    headers = {"Content-Disposition": f"attachment; filename=\"{filename}\""}
    return StreamingResponse(_iter(), media_type="text/csv", headers=headers)


class ConfirmReq(BaseModel):
    confirm: bool = True


@router.post("/bookings/{booking_id}/confirm", response_model=BookingOut)
def confirm_booking(booking_id: str, req: ConfirmReq, s: Session = Depends(get_session)):
    b = s.get(Booking, booking_id)
    if not b:
        raise HTTPException(status_code=404, detail="not found")
    if b.status != "requested":
        raise HTTPException(status_code=400, detail="cannot confirm now")
    c = s.get(Car, b.car_id)
    if not c:
        raise HTTPException(status_code=404, detail="car not found")
    if req.confirm and c.owner_wallet_id and b.renter_wallet_id and (b.amount_cents or 0) > 0:
        resp = _pay_transfer(b.renter_wallet_id, c.owner_wallet_id, int(b.amount_cents or 0), ikey=f"booking-{b.id}", ref=f"booking-{b.id}")
        b.payments_txn_id = str(resp.get("id") or resp.get("txn_id") or "")
        b.status = "confirmed"
        s.add(b); s.commit(); s.refresh(b)
    return BookingOut(id=b.id, car_id=b.car_id, renter_name=b.renter_name, renter_phone=b.renter_phone, from_iso=b.from_ts.isoformat(), to_iso=b.to_ts.isoformat(), status=b.status, amount_cents=b.amount_cents, payments_txn_id=b.payments_txn_id)


@router.post("/bookings/{booking_id}/cancel", response_model=BookingOut)
def cancel_booking(booking_id: str, s: Session = Depends(get_session)):
    b = s.get(Booking, booking_id)
    if not b:
        raise HTTPException(status_code=404, detail="not found")
    if b.status in ("canceled", "completed"):
        return BookingOut(id=b.id, car_id=b.car_id, renter_name=b.renter_name, renter_phone=b.renter_phone, from_iso=b.from_ts.isoformat(), to_iso=b.to_ts.isoformat(), status=b.status, amount_cents=b.amount_cents, payments_txn_id=b.payments_txn_id)
    b.status = "canceled"
    s.add(b); s.commit(); s.refresh(b)
    return BookingOut(id=b.id, car_id=b.car_id, renter_name=b.renter_name, renter_phone=b.renter_phone, from_iso=b.from_ts.isoformat(), to_iso=b.to_ts.isoformat(), status=b.status, amount_cents=b.amount_cents, payments_txn_id=b.payments_txn_id)


app.include_router(router)
