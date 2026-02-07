from fastapi import FastAPI, HTTPException, Depends, Header, APIRouter
from pydantic import BaseModel, Field, ConfigDict
from typing import Optional, List
import os
from shamell_shared import RequestIDMiddleware, configure_cors, add_standard_health, setup_json_logging
from sqlalchemy import create_engine, String, Integer, BigInteger, DateTime, func
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, Session
from sqlalchemy import select
from datetime import datetime, timezone, date, timedelta, time
from zoneinfo import ZoneInfo
import uuid
import os


def _env_or(key: str, default: str) -> str:
    v = os.getenv(key)
    return v if v is not None else default


def _env_bool(key: str, default: bool = False) -> bool:
    v = os.getenv(key)
    if v is None:
        return default
    return v.strip().lower() in ("1", "true", "yes", "y", "on", "t")


app = FastAPI(title="Doctors API", version="0.1.0")
setup_json_logging()
app.add_middleware(RequestIDMiddleware)
configure_cors(app, os.getenv("ALLOWED_ORIGINS", "*"))
add_standard_health(app)

router = APIRouter()


DB_URL = _env_or("DB_URL", "sqlite+pysqlite:////tmp/doctors.db")
DB_SCHEMA = os.getenv("DB_SCHEMA") if not DB_URL.startswith("sqlite") else None


class Base(DeclarativeBase):
    pass


class Doctor(Base):
    __tablename__ = "doctors"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(200))
    speciality: Mapped[Optional[str]] = mapped_column(String(120), default=None)
    city: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    timezone: Mapped[str] = mapped_column(String(64), default="UTC")
    languages: Mapped[Optional[str]] = mapped_column(String(120), default=None)  # comma-separated
    insurance: Mapped[Optional[str]] = mapped_column(String(64), default="public")  # public|private|both
    address: Mapped[Optional[str]] = mapped_column(String(200), default=None)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class DoctorAvailability(Base):
    __tablename__ = "doctor_availability"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    doctor_id: Mapped[int] = mapped_column(Integer)
    weekday: Mapped[int] = mapped_column(Integer)  # 0=Monday, 6=Sunday
    start_minute: Mapped[int] = mapped_column(Integer)  # minutes from midnight
    end_minute: Mapped[int] = mapped_column(Integer)
    slot_minutes: Mapped[int] = mapped_column(Integer, default=20)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Appointment(Base):
    __tablename__ = "appointments"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    doctor_id: Mapped[int] = mapped_column(Integer)
    patient_name: Mapped[Optional[str]] = mapped_column(String(120), default=None)
    patient_phone: Mapped[Optional[str]] = mapped_column(String(32), default=None)
    ts: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True))
    status: Mapped[str] = mapped_column(String(16), default="booked")  # booked|canceled|completed
    duration_minutes: Mapped[int] = mapped_column(Integer, default=20)
    reason: Mapped[Optional[str]] = mapped_column(String(200), default=None)
    patient_email: Mapped[Optional[str]] = mapped_column(String(120), default=None)
    insurance: Mapped[Optional[str]] = mapped_column(String(32), default=None)
    rescheduled_from_ts: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), default=None)
    canceled_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), default=None)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Service(Base):
    __tablename__ = "services"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    doctor_id: Mapped[int] = mapped_column(Integer)
    name: Mapped[str] = mapped_column(String(120))
    duration_minutes: Mapped[int] = mapped_column(Integer, default=20)
    insurance: Mapped[Optional[str]] = mapped_column(String(32), default=None)
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
    _seed_demo_data()

app.router.on_startup.append(_startup)


def _parse_ts_iso(ts_iso: str) -> datetime:
    try:
        ts = datetime.fromisoformat(ts_iso.replace("Z", "+00:00"))
    except Exception:
        raise HTTPException(status_code=400, detail="invalid ts")
    if ts.tzinfo is None:
        raise HTTPException(status_code=400, detail="ts must include timezone")
    return ts


def _get_tz(tz_name: str) -> ZoneInfo:
    try:
        return ZoneInfo(tz_name)
    except Exception:
        raise HTTPException(status_code=400, detail="invalid timezone")


def _active_appointments(s: Session, doctor_id: int) -> List[Appointment]:
    stmt = select(Appointment).where(Appointment.doctor_id == doctor_id, Appointment.status != "canceled")
    return s.execute(stmt).scalars().all()


def _list_slots_for_range(s: Session, doctor: Doctor, start: datetime, end: datetime) -> List[SlotOut]:
    tz = _get_tz(doctor.timezone or "UTC")
    # normalize to doctor's tz
    start = start.astimezone(tz)
    end = end.astimezone(tz)
    avails = s.execute(select(DoctorAvailability).where(DoctorAvailability.doctor_id == doctor.id)).scalars().all()
    apps = _active_appointments(s, doctor.id)
    slots: List[SlotOut] = []
    cur_day = start.date()
    while cur_day <= end.date():
        for a in avails:
            if a.weekday != cur_day.weekday():
                continue
            day_start = datetime.combine(cur_day, time(), tzinfo=tz) + timedelta(minutes=a.start_minute)
            day_end = datetime.combine(cur_day, time(), tzinfo=tz) + timedelta(minutes=a.end_minute)
            slot_len = a.slot_minutes or 20
            t = day_start
            while t < day_end:
                if start <= t <= end:
                    if not _has_conflict(apps, t, slot_len):
                        slots.append(SlotOut(doctor_id=doctor.id, ts_iso=t.isoformat(), duration_minutes=slot_len))
                t += timedelta(minutes=slot_len)
        cur_day += timedelta(days=1)
    slots.sort(key=lambda x: x.ts_iso)
    return slots


def _has_conflict(existing: List[Appointment], start_ts: datetime, duration_minutes: int, ignore_id: Optional[str] = None) -> bool:
    end_ts = start_ts + timedelta(minutes=duration_minutes)
    for a in existing:
        if ignore_id and a.id == ignore_id:
            continue
        if a.ts is None:
            continue
        a_duration = a.duration_minutes or 20
        a_end = a.ts + timedelta(minutes=a_duration)
        # Overlap check
        if a.ts < end_ts and a_end > start_ts and a.status != "canceled":
            return True
    return False


def _seed_default_availability(s: Session, doctor_id: int):
    # Default Monday-Friday 09:00-17:00, 20 minute slots
    current = s.execute(select(DoctorAvailability).where(DoctorAvailability.doctor_id == doctor_id)).scalars().all()
    if current:
        return
    rows = []
    for weekday in range(5):
        rows.append(DoctorAvailability(doctor_id=doctor_id, weekday=weekday, start_minute=9 * 60, end_minute=17 * 60, slot_minutes=20))
    s.add_all(rows)
    s.commit()


def _parse_hhmm(val: str) -> int:
    try:
        hh, mm = val.split(":")
        hhi = int(hh); mmi = int(mm)
        if hhi < 0 or hhi > 23 or mmi < 0 or mmi > 59:
            raise ValueError()
        return hhi * 60 + mmi
    except Exception:
        raise HTTPException(status_code=400, detail="time must be HH:MM 24h")


def _seed_demo_data():
    if not _env_bool("DOCTORS_DEMO_SEED", False):
        return
    with Session(engine) as s:
        existing = s.execute(select(func.count(Doctor.id))).scalar() or 0
        if existing > 0:
            return
        samples = [
            ("Dr. Anna Müller", "Allgemeinmedizin", "Berlin", "Europe/Berlin"),
            ("Dr. Samir Youssef", "Dermatologie", "Hamburg", "Europe/Berlin"),
            ("Dr. Laura Rossi", "Pädiatrie", "Munich", "Europe/Berlin"),
        ]
        for name, spec, city, tz in samples:
            d = Doctor(name=name, speciality=spec, city=city, timezone=tz)
            s.add(d)
            s.flush()
            _seed_default_availability(s, d.id)
            # Seed a few services
            s.add_all(
                [
                    Service(doctor_id=d.id, name="Consultation", duration_minutes=20, insurance="public"),
                    Service(doctor_id=d.id, name="Follow-up", duration_minutes=15, insurance="public"),
                    Service(doctor_id=d.id, name="Skin check", duration_minutes=25, insurance="private"),
                ]
            )
        s.commit()


class DoctorCreate(BaseModel):
    name: str
    speciality: Optional[str] = None
    city: Optional[str] = None
    timezone: Optional[str] = Field(default="UTC", description="IANA timezone, e.g. Europe/Berlin")
    languages: Optional[str] = None
    insurance: Optional[str] = Field(default="public", description="public|private|both")
    address: Optional[str] = None


class DoctorOut(BaseModel):
    id: int
    name: str
    speciality: Optional[str]
    city: Optional[str]
    timezone: str
    languages: Optional[str]
    insurance: Optional[str]
    address: Optional[str]
    model_config = ConfigDict(from_attributes=True)


class AvailabilityBlock(BaseModel):
    weekday: int = Field(ge=0, le=6, description="0=Monday, 6=Sunday")
    start_time: str = Field(description="HH:MM 24h")
    end_time: str = Field(description="HH:MM 24h")
    slot_minutes: int = Field(default=20, ge=5, le=180)


class AvailabilityOut(AvailabilityBlock):
    id: int
    doctor_id: int
    model_config = ConfigDict(from_attributes=True)


class SlotOut(BaseModel):
    doctor_id: int
    ts_iso: str
    duration_minutes: int
    location: Optional[str] = None


class DoctorSearchOut(DoctorOut):
    next_slots: List[str] = []


class DoctorProfileOut(DoctorOut):
    services: List[str] = []


class BookRequest(BaseModel):
    slot_iso: str
    patient_name: str
    patient_phone: Optional[str] = None
    patient_email: Optional[str] = None
    reason: Optional[str] = None
    insurance: Optional[str] = None


class AppointmentCreate(BaseModel):
    doctor_id: int
    patient_name: Optional[str] = None
    patient_phone: Optional[str] = None
    patient_email: Optional[str] = None
    reason: Optional[str] = None
    ts_iso: str
    duration_minutes: int = Field(default=20, ge=5, le=180)
    insurance: Optional[str] = None


class AppointmentOut(BaseModel):
    id: str
    doctor_id: int
    patient_name: Optional[str]
    patient_phone: Optional[str]
    patient_email: Optional[str]
    reason: Optional[str]
    ts_iso: str
    duration_minutes: int
    status: str
    insurance: Optional[str] = None
    rescheduled_from_ts_iso: Optional[str] = None
    canceled_at_iso: Optional[str] = None
    created_at_iso: Optional[str] = None


class AppointmentReschedule(BaseModel):
    ts_iso: str
    duration_minutes: Optional[int] = Field(default=None, ge=5, le=180)


@router.post("/doctors", response_model=DoctorOut)
def create_doctor(req: DoctorCreate, idempotency_key: Optional[str] = Header(default=None, alias="Idempotency-Key"), s: Session = Depends(get_session)):
    if idempotency_key:
        ie = s.get(Idempotency, idempotency_key)
        if ie and ie.ref_id:
            try:
                d0 = s.get(Doctor, int(ie.ref_id))
                if d0:
                    return d0
            except Exception:
                pass
    tz_name = req.timezone or "UTC"
    _get_tz(tz_name)  # validate timezone string
    d = Doctor(
        name=req.name.strip(),
        speciality=(req.speciality or None),
        city=(req.city or None),
        timezone=tz_name,
        languages=(req.languages or None),
        insurance=(req.insurance or "public"),
        address=(req.address or None),
    )
    s.add(d)
    s.commit()
    s.refresh(d)
    _seed_default_availability(s, d.id)
    if idempotency_key:
        try:
            s.add(Idempotency(key=idempotency_key, ref_id=str(d.id)))
            s.commit()
        except Exception:
            pass
    return d


@router.get("/doctors", response_model=List[DoctorOut])
def list_doctors(q: str = "", city: str = "", speciality: str = "", limit: int = 50, s: Session = Depends(get_session)):
    stmt = select(Doctor)
    if q:
        stmt = stmt.where(func.lower(Doctor.name).like(f"%{q.lower()}%"))
    if city:
        stmt = stmt.where(func.lower(Doctor.city) == city.lower())
    if speciality:
        stmt = stmt.where(func.lower(Doctor.speciality) == speciality.lower())
    stmt = stmt.order_by(Doctor.id.desc()).limit(max(1, min(limit, 200)))
    return s.execute(stmt).scalars().all()


@router.get("/doctors/search", response_model=List[DoctorSearchOut])
def search_doctors(
    q: str = "",
    city: str = "",
    speciality: str = "",
    insurance: str = "",
    language: str = "",
    from_iso: Optional[str] = None,
    to_iso: Optional[str] = None,
    limit: int = 50,
    s: Session = Depends(get_session),
):
    stmt = select(Doctor)
    if q:
        stmt = stmt.where(func.lower(Doctor.name).like(f"%{q.lower()}%") | func.lower(Doctor.speciality).like(f"%{q.lower()}%"))
    if city:
        stmt = stmt.where(func.lower(Doctor.city) == city.lower())
    if speciality:
        stmt = stmt.where(func.lower(Doctor.speciality) == speciality.lower())
    if insurance:
        stmt = stmt.where(func.lower(Doctor.insurance) == insurance.lower())
    if language:
        stmt = stmt.where(func.lower(Doctor.languages).like(f"%{language.lower()}%"))
    docs = s.execute(stmt.order_by(Doctor.id.desc()).limit(max(1, min(limit, 200)))).scalars().all()

    try:
        start = _parse_ts_iso(from_iso) if from_iso else datetime.now(timezone.utc)
    except Exception:
        start = datetime.now(timezone.utc)
    try:
        end = _parse_ts_iso(to_iso) if to_iso else start + timedelta(days=7)
    except Exception:
        end = start + timedelta(days=7)

    out: List[DoctorSearchOut] = []
    for d in docs:
        slots = _list_slots_for_range(s, d, start, end)
        next_slots = [sl.ts_iso for sl in slots[:3]]
        out.append(
            DoctorSearchOut(
                id=d.id,
                name=d.name,
                speciality=d.speciality,
                city=d.city,
                timezone=d.timezone,
                languages=d.languages,
                insurance=d.insurance,
                address=d.address,
                next_slots=next_slots,
            )
        )
    return out


@router.get("/doctors/{doctor_id}", response_model=DoctorProfileOut)
def get_doctor(doctor_id: int, s: Session = Depends(get_session)):
    d = s.get(Doctor, doctor_id)
    if not d:
        raise HTTPException(status_code=404, detail="doctor not found")
    # Placeholder services; extend with real services when available
    services = [s.name for s in s.execute(select(Service).where(Service.doctor_id == doctor_id)).scalars().all()]
    return DoctorProfileOut(
        id=d.id,
        name=d.name,
        speciality=d.speciality,
        city=d.city,
        timezone=d.timezone,
        languages=d.languages,
        insurance=d.insurance,
        address=d.address,
        services=services,
    )


@router.get("/doctors/{doctor_id}/availability", response_model=List[AvailabilityOut])
def get_doctor_availability(doctor_id: int, s: Session = Depends(get_session)):
    d = s.get(Doctor, doctor_id)
    if not d:
        raise HTTPException(status_code=404, detail="doctor not found")
    stmt = select(DoctorAvailability).where(DoctorAvailability.doctor_id == doctor_id).order_by(DoctorAvailability.weekday.asc(), DoctorAvailability.start_minute.asc())
    return s.execute(stmt).scalars().all()


@router.get("/doctors/{doctor_id}/slots", response_model=List[SlotOut])
def get_doctor_slots(
    doctor_id: int,
    from_iso: Optional[str] = None,
    to_iso: Optional[str] = None,
    s: Session = Depends(get_session),
):
    d = s.get(Doctor, doctor_id)
    if not d:
        raise HTTPException(status_code=404, detail="doctor not found")
    start = _parse_ts_iso(from_iso) if from_iso else datetime.now(timezone.utc)
    end = _parse_ts_iso(to_iso) if to_iso else start + timedelta(days=7)
    return _list_slots_for_range(s, d, start, end)


@router.post("/doctors/{doctor_id}/book", response_model=AppointmentOut)
def book_doctor_slot(
    doctor_id: int,
    req: BookRequest,
    idempotency_key: Optional[str] = Header(default=None, alias="Idempotency-Key"),
    s: Session = Depends(get_session),
):
    d = s.get(Doctor, doctor_id)
    if not d:
        raise HTTPException(status_code=404, detail="doctor not found")
    tz = _get_tz(d.timezone or "UTC")
    slot_ts = _parse_ts_iso(req.slot_iso).astimezone(tz)
    duration = 20
    if idempotency_key:
        ie = s.get(Idempotency, idempotency_key)
        if ie and ie.ref_id:
            a0 = s.get(Appointment, ie.ref_id)
            if a0:
                return _appt_to_out(a0)
    avails = s.execute(select(DoctorAvailability).where(DoctorAvailability.doctor_id == doctor_id)).scalars().all()
    if avails and not _slot_allowed(avails, tz, slot_ts, duration):
        raise HTTPException(status_code=400, detail="requested slot not available")
    existing = _active_appointments(s, doctor_id)
    if _has_conflict(existing, slot_ts, duration):
        raise HTTPException(status_code=409, detail="slot already booked")
    aid = str(uuid.uuid4())
    a = Appointment(
        id=aid,
        doctor_id=doctor_id,
        patient_name=req.patient_name.strip(),
        patient_phone=(req.patient_phone or None),
        patient_email=(req.patient_email or None),
        reason=(req.reason or None),
        insurance=(req.insurance or None),
        ts=slot_ts,
        duration_minutes=duration,
        status="booked",
    )
    s.add(a)
    s.commit()
    if idempotency_key:
        try:
            s.add(Idempotency(key=idempotency_key, ref_id=aid))
            s.commit()
        except Exception:
            pass
    return _appt_to_out(a)


@router.put("/doctors/{doctor_id}/availability", response_model=List[AvailabilityOut])
def set_doctor_availability(doctor_id: int, blocks: List[AvailabilityBlock], s: Session = Depends(get_session)):
    d = s.get(Doctor, doctor_id)
    if not d:
        raise HTTPException(status_code=404, detail="doctor not found")
    rows: List[DoctorAvailability] = []
    for b in blocks:
        start_m = _parse_hhmm(b.start_time)
        end_m = _parse_hhmm(b.end_time)
        if end_m <= start_m:
            raise HTTPException(status_code=400, detail="end_time must be after start_time")
        rows.append(DoctorAvailability(doctor_id=doctor_id, weekday=b.weekday, start_minute=start_m, end_minute=end_m, slot_minutes=b.slot_minutes))
    # replace existing
    existing = s.execute(select(DoctorAvailability).where(DoctorAvailability.doctor_id == doctor_id)).scalars().all()
    for e in existing:
        s.delete(e)
    if rows:
        s.add_all(rows)
    s.commit()
    stmt = select(DoctorAvailability).where(DoctorAvailability.doctor_id == doctor_id).order_by(DoctorAvailability.weekday.asc(), DoctorAvailability.start_minute.asc())
    return s.execute(stmt).scalars().all()


def _appt_to_out(a: Appointment) -> AppointmentOut:
    return AppointmentOut(
        id=a.id,
        doctor_id=a.doctor_id,
        patient_name=a.patient_name,
        patient_phone=a.patient_phone,
        patient_email=a.patient_email,
        reason=a.reason,
        ts_iso=(a.ts.isoformat() if a.ts else ""),
        duration_minutes=a.duration_minutes or 20,
        status=a.status,
        insurance=a.insurance,
        rescheduled_from_ts_iso=(a.rescheduled_from_ts.isoformat() if a.rescheduled_from_ts else None),
        canceled_at_iso=(a.canceled_at.isoformat() if a.canceled_at else None),
        created_at_iso=(a.created_at.isoformat() if a.created_at else None),
    )


def _slot_allowed(avails: List[DoctorAvailability], tz: ZoneInfo, start_ts: datetime, duration_minutes: int) -> bool:
    local = start_ts.astimezone(tz)
    weekday = local.weekday()
    start_min = local.hour * 60 + local.minute
    for av in avails:
        if av.weekday != weekday:
            continue
        slot_len = av.slot_minutes or duration_minutes or 20
        if duration_minutes != slot_len:
            continue
        end_min = start_min + duration_minutes
        if start_min < av.start_minute or end_min > av.end_minute:
            continue
        if slot_len and (start_min - av.start_minute) % slot_len != 0:
            continue
        return True
    return False


@router.post("/appointments", response_model=AppointmentOut)
def create_appt(req: AppointmentCreate, idempotency_key: Optional[str] = Header(default=None, alias="Idempotency-Key"), s: Session = Depends(get_session)):
    d = s.get(Doctor, req.doctor_id)
    if not d:
        raise HTTPException(status_code=404, detail="doctor not found")
    tz = _get_tz(d.timezone or "UTC")
    ts = _parse_ts_iso(req.ts_iso)
    duration = req.duration_minutes or 20
    if idempotency_key:
        ie = s.get(Idempotency, idempotency_key)
        if ie and ie.ref_id:
            a0 = s.get(Appointment, ie.ref_id)
            if a0:
                return _appt_to_out(a0)
    avails = s.execute(select(DoctorAvailability).where(DoctorAvailability.doctor_id == req.doctor_id)).scalars().all()
    if avails and not _slot_allowed(avails, tz, ts, duration):
        raise HTTPException(status_code=400, detail="requested slot not available")
    existing = _active_appointments(s, req.doctor_id)
    if _has_conflict(existing, ts, duration):
        raise HTTPException(status_code=409, detail="slot already booked")
    aid = os.urandom(8).hex()
    a = Appointment(
        id=aid,
        doctor_id=req.doctor_id,
        patient_name=(req.patient_name or None),
        patient_phone=(req.patient_phone or None),
        patient_email=(req.patient_email or None),
        reason=(req.reason or None),
        ts=ts,
        duration_minutes=duration,
        status="booked",
        insurance=req.insurance,
    )
    s.add(a)
    s.commit()
    if idempotency_key:
        try:
            s.add(Idempotency(key=idempotency_key, ref_id=aid))
            s.commit()
        except Exception:
            pass
    return _appt_to_out(a)


@router.get("/appointments", response_model=List[AppointmentOut])
def list_appts(doctor_id: Optional[int] = None, limit: int = 50, s: Session = Depends(get_session)):
    stmt = select(Appointment)
    if doctor_id is not None:
        stmt = stmt.where(Appointment.doctor_id == doctor_id)
    stmt = stmt.order_by(Appointment.ts.desc()).limit(max(1, min(limit, 200)))
    rows = s.execute(stmt).scalars().all()
    return [_appt_to_out(a) for a in rows]


@router.get("/slots", response_model=List[SlotOut])
def list_slots(doctor_id: int, start_date: Optional[str] = None, days: int = 7, s: Session = Depends(get_session)):
    doctor = s.get(Doctor, doctor_id)
    if not doctor:
        raise HTTPException(status_code=404, detail="doctor not found")
    tz = _get_tz(doctor.timezone or "UTC")
    days = max(1, min(days, 31))
    if start_date:
        try:
            start = date.fromisoformat(start_date)
        except Exception:
            raise HTTPException(status_code=400, detail="invalid start_date, expected YYYY-MM-DD")
    else:
        start = datetime.now(tz=tz).date()
    avails = s.execute(select(DoctorAvailability).where(DoctorAvailability.doctor_id == doctor_id)).scalars().all()
    existing = _active_appointments(s, doctor_id)
    out: List[SlotOut] = []
    now_tz = datetime.now(tz=tz)
    for i in range(days):
        day_date = start + timedelta(days=i)
        base = datetime.combine(day_date, time(0, 0, tzinfo=tz))
        weekday = day_date.weekday()
        day_avails = [a for a in avails if a.weekday == weekday]
        for av in day_avails:
            slot_len = av.slot_minutes or 20
            window_start = base + timedelta(minutes=av.start_minute)
            window_end = base + timedelta(minutes=av.end_minute)
            cur = window_start
            while cur + timedelta(minutes=slot_len) <= window_end:
                if cur <= now_tz:
                    cur += timedelta(minutes=slot_len)
                    continue
                if not _has_conflict(existing, cur, slot_len):
                    out.append(SlotOut(doctor_id=doctor_id, ts_iso=cur.isoformat(), duration_minutes=slot_len))
                cur += timedelta(minutes=slot_len)
    return out


@router.post("/appointments/{appt_id}/cancel", response_model=AppointmentOut)
def cancel_appointment(appt_id: str, s: Session = Depends(get_session)):
    a = s.get(Appointment, appt_id)
    if not a:
        raise HTTPException(status_code=404, detail="appointment not found")
    if a.status == "canceled":
        return _appt_to_out(a)
    a.status = "canceled"
    a.canceled_at = datetime.now(timezone.utc)
    s.add(a)
    s.commit()
    s.refresh(a)
    return _appt_to_out(a)


@router.post("/appointments/{appt_id}/reschedule", response_model=AppointmentOut)
def reschedule_appointment(appt_id: str, req: AppointmentReschedule, s: Session = Depends(get_session)):
    a = s.get(Appointment, appt_id)
    if not a:
        raise HTTPException(status_code=404, detail="appointment not found")
    if a.status == "canceled":
        raise HTTPException(status_code=400, detail="cannot reschedule a canceled appointment")
    doctor = s.get(Doctor, a.doctor_id)
    if not doctor:
        raise HTTPException(status_code=404, detail="doctor not found")
    tz = _get_tz(doctor.timezone or "UTC")
    new_ts = _parse_ts_iso(req.ts_iso)
    new_duration = req.duration_minutes or a.duration_minutes or 20
    avails = s.execute(select(DoctorAvailability).where(DoctorAvailability.doctor_id == a.doctor_id)).scalars().all()
    if avails and not _slot_allowed(avails, tz, new_ts, new_duration):
        raise HTTPException(status_code=400, detail="requested slot not available")
    existing = _active_appointments(s, a.doctor_id)
    if _has_conflict(existing, new_ts, new_duration, ignore_id=a.id):
        raise HTTPException(status_code=409, detail="slot already booked")
    a.rescheduled_from_ts = a.ts
    a.ts = new_ts
    a.duration_minutes = new_duration
    a.status = "booked"
    s.add(a)
    s.commit()
    s.refresh(a)
    return _appt_to_out(a)


@router.get("/admin/calendar", response_model=List[AppointmentOut])
def admin_calendar(
    from_iso: Optional[str] = None,
    to_iso: Optional[str] = None,
    doctor_id: Optional[int] = None,
    status: str = "",
    s: Session = Depends(get_session),
):
    start = _parse_ts_iso(from_iso) if from_iso else datetime.now(timezone.utc)
    end = _parse_ts_iso(to_iso) if to_iso else start + timedelta(days=7)
    stmt = select(Appointment).where(Appointment.ts >= start, Appointment.ts <= end)
    if doctor_id is not None:
        stmt = stmt.where(Appointment.doctor_id == doctor_id)
    if status:
        stmt = stmt.where(Appointment.status == status)
    rows = s.execute(stmt.order_by(Appointment.ts.asc())).scalars().all()
    return [_appt_to_out(r) for r in rows]


class AppointmentStatusUpdate(BaseModel):
    status: str


@router.post("/admin/appointments/{appt_id}/status", response_model=AppointmentOut)
def admin_update_status(appt_id: str, req: AppointmentStatusUpdate, s: Session = Depends(get_session)):
    a = s.get(Appointment, appt_id)
    if not a:
        raise HTTPException(status_code=404, detail="appointment not found")
    a.status = req.status.strip()
    s.add(a)
    s.commit()
    s.refresh(a)
    return _appt_to_out(a)


class ServiceCreate(BaseModel):
    name: str
    duration_minutes: int = Field(default=20, ge=5)
    insurance: Optional[str] = None


@router.get("/admin/services", response_model=List[ServiceCreate])
def list_services_admin(doctor_id: int, s: Session = Depends(get_session)):
    stmt = select(Service).where(Service.doctor_id == doctor_id).order_by(Service.id.desc())
    rows = s.execute(stmt).scalars().all()
    return [ServiceCreate(name=r.name, duration_minutes=r.duration_minutes, insurance=r.insurance) for r in rows]


@router.post("/admin/services", response_model=ServiceCreate)
def add_service_admin(doctor_id: int, req: ServiceCreate, s: Session = Depends(get_session)):
    d = s.get(Doctor, doctor_id)
    if not d:
        raise HTTPException(status_code=404, detail="doctor not found")
    svc = Service(doctor_id=doctor_id, name=req.name.strip(), duration_minutes=req.duration_minutes, insurance=(req.insurance or None))
    s.add(svc)
    s.commit()
    return req


app.include_router(router)
