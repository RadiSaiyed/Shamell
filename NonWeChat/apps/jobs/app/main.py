from fastapi import FastAPI, HTTPException, Depends, Header, APIRouter
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


app = FastAPI(title="Jobs API", version="0.1.0")
setup_json_logging()
app.add_middleware(RequestIDMiddleware)
configure_cors(app, os.getenv("ALLOWED_ORIGINS", "*"))
add_standard_health(app)

router = APIRouter()


DB_URL = _env_or("DB_URL", "sqlite+pysqlite:////tmp/jobs.db")
DB_SCHEMA = os.getenv("DB_SCHEMA") if not DB_URL.startswith("sqlite") else None


class Base(DeclarativeBase):
    pass


class Job(Base):
    __tablename__ = "jobs"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    title: Mapped[str] = mapped_column(String(200))
    company: Mapped[Optional[str]] = mapped_column(String(200), default=None)
    city: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    salary_cents: Mapped[Optional[int]] = mapped_column(BigInteger, default=None)
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


class JobCreate(BaseModel):
    title: str
    company: Optional[str] = None
    city: Optional[str] = None
    salary_cents: Optional[int] = Field(default=None, ge=0)


class JobOut(BaseModel):
    id: int
    title: str
    company: Optional[str]
    city: Optional[str]
    salary_cents: Optional[int]
    model_config = ConfigDict(from_attributes=True)


@router.post("/jobs", response_model=JobOut)
def create_job(req: JobCreate, idempotency_key: Optional[str] = Header(default=None, alias="Idempotency-Key"), s: Session = Depends(get_session)):
    if idempotency_key:
        ie = s.get(Idempotency, idempotency_key)
        if ie and ie.ref_id:
            try:
                j0 = s.get(Job, int(ie.ref_id))
                if j0: return j0
            except Exception:
                pass
    j = Job(title=req.title.strip(), company=(req.company or None), city=(req.city or None), salary_cents=req.salary_cents)
    s.add(j); s.commit(); s.refresh(j)
    if idempotency_key:
        try: s.add(Idempotency(key=idempotency_key, ref_id=str(j.id))); s.commit()
        except Exception: pass
    return j


@router.get("/jobs", response_model=List[JobOut])
def list_jobs(q: str = "", city: str = "", company: str = "", limit: int = 50, s: Session = Depends(get_session)):
    stmt = select(Job)
    if q:
        stmt = stmt.where(func.lower(Job.title).like(f"%{q.lower()}%"))
    if city:
        stmt = stmt.where(func.lower(Job.city) == city.lower())
    if company:
        stmt = stmt.where(func.lower(Job.company) == company.lower())
    stmt = stmt.order_by(Job.id.desc()).limit(max(1, min(limit, 200)))
    return s.execute(stmt).scalars().all()


app.include_router(router)
