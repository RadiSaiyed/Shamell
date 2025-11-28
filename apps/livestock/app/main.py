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


app = FastAPI(title="Livestock API", version="0.1.0")
setup_json_logging()
app.add_middleware(RequestIDMiddleware)
configure_cors(app, os.getenv("ALLOWED_ORIGINS", "*"))
add_standard_health(app)

router = APIRouter()


DB_URL = _env_or("DB_URL", "sqlite+pysqlite:////tmp/livestock.db")
DB_SCHEMA = os.getenv("DB_SCHEMA") if not DB_URL.startswith("sqlite") else None


class Base(DeclarativeBase):
    pass


class Listing(Base):
    __tablename__ = "listings"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    title: Mapped[str] = mapped_column(String(200))
    species: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    weight_kg: Mapped[Optional[float]] = mapped_column(BigInteger, default=None)
    price_cents: Mapped[int] = mapped_column(BigInteger)
    currency: Mapped[str] = mapped_column(String(3), default="SYP")
    city: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    seller_wallet_id: Mapped[Optional[str]] = mapped_column(String(36), default=None)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


engine = create_engine(DB_URL, future=True)


def get_session() -> Session:
    with Session(engine) as s:
        yield s


def _startup():
    Base.metadata.create_all(engine)

app.router.on_startup.append(_startup)


class ListingCreate(BaseModel):
    title: str
    species: Optional[str] = None
    weight_kg: Optional[float] = Field(default=None, ge=0)
    price_cents: int = Field(ge=0)
    city: Optional[str] = None
    seller_wallet_id: Optional[str] = None


class ListingOut(BaseModel):
    id: int
    title: str
    species: Optional[str]
    weight_kg: Optional[float]
    price_cents: int
    currency: str
    city: Optional[str]
    seller_wallet_id: Optional[str]
    model_config = ConfigDict(from_attributes=True)


@router.post("/listings", response_model=ListingOut)
def create_listing(req: ListingCreate, s: Session = Depends(get_session)):
    l = Listing(title=req.title.strip(), species=(req.species or None), weight_kg=req.weight_kg,
                price_cents=req.price_cents, city=(req.city or None), seller_wallet_id=(req.seller_wallet_id or None))
    s.add(l); s.commit(); s.refresh(l)
    return l


@router.get("/listings", response_model=List[ListingOut])
def list_listings(q: str = "", city: str = "", species: str = "", limit: int = 50, s: Session = Depends(get_session)):
    stmt = select(Listing)
    if q:
        stmt = stmt.where(func.lower(Listing.title).like(f"%{q.lower()}%"))
    if city:
        stmt = stmt.where(func.lower(Listing.city) == city.lower())
    if species:
        stmt = stmt.where(func.lower(Listing.species) == species.lower())
    stmt = stmt.order_by(Listing.id.desc()).limit(max(1, min(limit, 200)))
    return s.execute(stmt).scalars().all()


@router.get("/listings/{lid}", response_model=ListingOut)
def get_listing(lid: int, s: Session = Depends(get_session)):
    l = s.get(Listing, lid)
    if not l:
        raise HTTPException(status_code=404, detail="not found")
    return l


app.include_router(router)
