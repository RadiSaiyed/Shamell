from fastapi import FastAPI, HTTPException, Depends, Header, APIRouter
from pydantic import BaseModel, Field, ConfigDict
from typing import Optional, List
import os
from shamell_shared import RequestIDMiddleware, configure_cors, add_standard_health, setup_json_logging
from sqlalchemy import create_engine, String, Integer, BigInteger, DateTime, func
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, Session
from sqlalchemy import select
from datetime import datetime


def _env_or(key: str, default: str) -> str:
    v = os.getenv(key)
    return v if v is not None else default


app = FastAPI(title="Flights API", version="0.1.0")
setup_json_logging()
app.add_middleware(RequestIDMiddleware)
configure_cors(app, os.getenv("ALLOWED_ORIGINS", "*"))
add_standard_health(app)

router = APIRouter()


DB_URL = _env_or("DB_URL", "sqlite+pysqlite:////tmp/flights.db")
DB_SCHEMA = os.getenv("DB_SCHEMA") if not DB_URL.startswith("sqlite") else None


class Base(DeclarativeBase):
    pass


class Flight(Base):
    __tablename__ = "flights"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    code: Mapped[str] = mapped_column(String(16))
    from_city: Mapped[str] = mapped_column(String(64))
    to_city: Mapped[str] = mapped_column(String(64))
    dep_ts: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True))
    arr_ts: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True))
    price_cents: Mapped[int] = mapped_column(BigInteger)
    currency: Mapped[str] = mapped_column(String(3), default="SYP")
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Booking(Base):
    __tablename__ = "bookings"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    flight_id: Mapped[int] = mapped_column(Integer)
    name: Mapped[Optional[str]] = mapped_column(String(120), default=None)
    phone: Mapped[Optional[str]] = mapped_column(String(32), default=None)
    status: Mapped[str] = mapped_column(String(16), default="booked")  # booked|canceled|completed


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


class FlightCreate(BaseModel):
    code: str
    from_city: str
    to_city: str
    dep_iso: str
    arr_iso: str
    price_cents: int = Field(ge=0)


class FlightOut(BaseModel):
    id: int
    code: str
    from_city: str
    to_city: str
    dep_iso: str
    arr_iso: str
    price_cents: int
    currency: str
    model_config = ConfigDict(from_attributes=False)


@router.post("/flights", response_model=FlightOut)
def create_flight(req: FlightCreate, idempotency_key: Optional[str] = Header(default=None, alias="Idempotency-Key"), s: Session = Depends(get_session)):
    try:
        dep = datetime.fromisoformat(req.dep_iso.replace("Z", "+00:00"))
        arr = datetime.fromisoformat(req.arr_iso.replace("Z", "+00:00"))
    except Exception:
        raise HTTPException(status_code=400, detail="invalid time")
    if idempotency_key:
        ie = s.get(Idempotency, idempotency_key)
        if ie and ie.ref_id:
            try:
                f0 = s.get(Flight, int(ie.ref_id))
                if f0:
                    return FlightOut(id=f0.id, code=f0.code, from_city=f0.from_city, to_city=f0.to_city, dep_iso=(f0.dep_ts.isoformat() if f0.dep_ts else ""), arr_iso=(f0.arr_ts.isoformat() if f0.arr_ts else ""), price_cents=f0.price_cents, currency=f0.currency)
            except Exception:
                pass
    f = Flight(code=req.code.strip(), from_city=req.from_city.strip(), to_city=req.to_city.strip(), dep_ts=dep, arr_ts=arr, price_cents=req.price_cents, currency="SYP")
    s.add(f); s.commit(); s.refresh(f)
    if idempotency_key:
        try: s.add(Idempotency(key=idempotency_key, ref_id=str(f.id))); s.commit()
        except Exception: pass
    return FlightOut(id=f.id, code=f.code, from_city=f.from_city, to_city=f.to_city, dep_iso=dep.isoformat(), arr_iso=arr.isoformat(), price_cents=f.price_cents, currency=f.currency)


@router.get("/flights", response_model=List[FlightOut])
def list_flights(q: str = "", frm: str = "", to: str = "", limit: int = 50, s: Session = Depends(get_session)):
    stmt = select(Flight)
    if q:
        stmt = stmt.where(func.lower(Flight.code).like(f"%{q.lower()}%"))
    if frm:
        stmt = stmt.where(func.lower(Flight.from_city) == frm.lower())
    if to:
        stmt = stmt.where(func.lower(Flight.to_city) == to.lower())
    stmt = stmt.order_by(Flight.id.desc()).limit(max(1, min(limit, 200)))
    rows = s.execute(stmt).scalars().all()
    out: List[FlightOut] = []
    for f in rows:
        out.append(FlightOut(id=f.id, code=f.code, from_city=f.from_city, to_city=f.to_city, dep_iso=(f.dep_ts.isoformat() if f.dep_ts else ""), arr_iso=(f.arr_ts.isoformat() if f.arr_ts else ""), price_cents=f.price_cents, currency=f.currency))
    return out


class BookingCreate(BaseModel):
    flight_id: int
    name: Optional[str] = None
    phone: Optional[str] = None


class BookingOut(BaseModel):
    id: str
    flight_id: int
    name: Optional[str]
    phone: Optional[str]
    status: str


@router.post("/bookings", response_model=BookingOut)
def create_booking(req: BookingCreate, idempotency_key: Optional[str] = Header(default=None, alias="Idempotency-Key"), s: Session = Depends(get_session)):
    f = s.get(Flight, req.flight_id)
    if not f:
        raise HTTPException(status_code=404, detail="flight not found")
    if idempotency_key:
        ie = s.get(Idempotency, idempotency_key)
        if ie and ie.ref_id:
            b0 = s.get(Booking, ie.ref_id)
            if b0:
                return BookingOut(id=b0.id, flight_id=b0.flight_id, name=b0.name, phone=b0.phone, status=b0.status)
    bid = os.urandom(8).hex()
    b = Booking(id=bid, flight_id=req.flight_id, name=(req.name or None), phone=(req.phone or None), status="booked")
    s.add(b); s.commit()
    if idempotency_key:
        try: s.add(Idempotency(key=idempotency_key, ref_id=bid)); s.commit()
        except Exception: pass
    return BookingOut(id=bid, flight_id=req.flight_id, name=req.name, phone=req.phone, status="booked")


@router.get("/bookings/{bid}", response_model=BookingOut)
def get_booking(bid: str, s: Session = Depends(get_session)):
    b = s.get(Booking, bid)
    if not b:
        raise HTTPException(status_code=404, detail="not found")
    return BookingOut(id=b.id, flight_id=b.flight_id, name=b.name, phone=b.phone, status=b.status)


app.include_router(router)
