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


class DoctorCreate(BaseModel):
    name: str
    speciality: Optional[str] = None
    city: Optional[str] = None


class DoctorOut(BaseModel):
    id: int
    name: str
    speciality: Optional[str]
    city: Optional[str]
    model_config = ConfigDict(from_attributes=True)


@router.post("/doctors", response_model=DoctorOut)
def create_doctor(req: DoctorCreate, idempotency_key: Optional[str] = Header(default=None, alias="Idempotency-Key"), s: Session = Depends(get_session)):
    if idempotency_key:
        ie = s.get(Idempotency, idempotency_key)
        if ie and ie.ref_id:
            try:
                d0 = s.get(Doctor, int(ie.ref_id))
                if d0: return d0
            except Exception:
                pass
    d = Doctor(name=req.name.strip(), speciality=(req.speciality or None), city=(req.city or None))
    s.add(d); s.commit(); s.refresh(d)
    if idempotency_key:
        try: s.add(Idempotency(key=idempotency_key, ref_id=str(d.id))); s.commit()
        except Exception: pass
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


class AppointmentCreate(BaseModel):
    doctor_id: int
    patient_name: Optional[str] = None
    patient_phone: Optional[str] = None
    ts_iso: str


class AppointmentOut(BaseModel):
    id: str
    doctor_id: int
    patient_name: Optional[str]
    patient_phone: Optional[str]
    ts_iso: str
    status: str


@router.post("/appointments", response_model=AppointmentOut)
def create_appt(req: AppointmentCreate, idempotency_key: Optional[str] = Header(default=None, alias="Idempotency-Key"), s: Session = Depends(get_session)):
    d = s.get(Doctor, req.doctor_id)
    if not d:
        raise HTTPException(status_code=404, detail="doctor not found")
    try:
        ts = datetime.fromisoformat(req.ts_iso.replace("Z", "+00:00"))
    except Exception:
        raise HTTPException(status_code=400, detail="invalid ts")
    if idempotency_key:
        ie = s.get(Idempotency, idempotency_key)
        if ie and ie.ref_id:
            a0 = s.get(Appointment, ie.ref_id)
            if a0:
                return AppointmentOut(id=a0.id, doctor_id=a0.doctor_id, patient_name=a0.patient_name, patient_phone=a0.patient_phone, ts_iso=(a0.ts.isoformat() if a0.ts else ""), status=a0.status)
    aid = os.urandom(8).hex()
    a = Appointment(id=aid, doctor_id=req.doctor_id, patient_name=(req.patient_name or None), patient_phone=(req.patient_phone or None), ts=ts, status="booked")
    s.add(a); s.commit()
    if idempotency_key:
        try: s.add(Idempotency(key=idempotency_key, ref_id=aid)); s.commit()
        except Exception: pass
    return AppointmentOut(id=aid, doctor_id=req.doctor_id, patient_name=req.patient_name, patient_phone=req.patient_phone, ts_iso=ts.isoformat(), status="booked")


@router.get("/appointments", response_model=List[AppointmentOut])
def list_appts(doctor_id: Optional[int] = None, limit: int = 50, s: Session = Depends(get_session)):
    stmt = select(Appointment)
    if doctor_id is not None:
        stmt = stmt.where(Appointment.doctor_id == doctor_id)
    stmt = stmt.order_by(Appointment.id.desc()).limit(max(1, min(limit, 200)))
    rows = s.execute(stmt).scalars().all()
    out: List[AppointmentOut] = []
    for a in rows:
        out.append(AppointmentOut(id=a.id, doctor_id=a.doctor_id, patient_name=a.patient_name, patient_phone=a.patient_phone, ts_iso=(a.ts.isoformat() if a.ts else ""), status=a.status))
    return out


app.include_router(router)
