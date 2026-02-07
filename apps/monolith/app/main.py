import os
import sys
import uuid
from fastapi import FastAPI
from sqlalchemy import select
from sqlalchemy.orm import Session

# Ensure we can import the individual service apps
BASE_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
if BASE_DIR not in sys.path:
    sys.path.append(BASE_DIR)
# Ensure local libs (e.g. shamell_shared) are importable
LIB_DIR = os.path.join(BASE_DIR, "libs")
if LIB_DIR not in sys.path:
    sys.path.append(LIB_DIR)
# Also add nested python package directories (e.g. libs/shamell_shared/python)
LIB_PY_DIR = os.path.join(LIB_DIR, "shamell_shared", "python")
if os.path.isdir(LIB_PY_DIR) and LIB_PY_DIR not in sys.path:
    sys.path.append(LIB_PY_DIR)
from shamell_shared import configure_cors  # type: ignore[import]

# Default all domains to internal mode when running the monolith so BFF
# calls stay in-process and no external *_BASE_URL is required.
_INTERNAL_DEFAULTS = {
    "TAXI_INTERNAL_MODE": "on",
    "BUS_INTERNAL_MODE": "on",
    "STAYS_INTERNAL_MODE": "on",
    "PAY_INTERNAL_MODE": "on",
    "COMMERCE_INTERNAL_MODE": "on",
    "FOOD_INTERNAL_MODE": "on",
    "FREIGHT_INTERNAL_MODE": "on",
    "AGRICULTURE_INTERNAL_MODE": "on",
    "LIVESTOCK_INTERNAL_MODE": "on",
    "CARRENTAL_INTERNAL_MODE": "on",
    "CARMARKET_INTERNAL_MODE": "on",
    "EQUIPMENT_INTERNAL_MODE": "on",
    "DOCTORS_INTERNAL_MODE": "on",
    "FLIGHTS_INTERNAL_MODE": "on",
    "REAL_ESTATE_INTERNAL_MODE": "on",
}
for k, v in _INTERNAL_DEFAULTS.items():
    os.environ.setdefault(k, v)
# Monolith-only guard: reject external *_BASE_URL usage when enabled.
MONOLITH_ONLY = os.getenv("MONOLITH_ONLY", "1").lower() not in ("0", "false", "off")


def _assert_monolith_only():
    """
    Fail fast if MONOLITH_ONLY is enabled but external BASE_URLs are set.
    This ensures all domains run in-process without HTTP hops.
    """
    if not MONOLITH_ONLY:
        return
    offenders = []
    for k, v in os.environ.items():
        if k.endswith("_BASE_URL") and v:
            offenders.append(f"{k}={v}")
    if offenders:
        raise RuntimeError(
            "MONOLITH_ONLY is enabled but external BASE_URL env vars are set; "
            "unset these to run purely in-process:\n" + "\n".join(offenders)
        )

# Shared DB + internal secrets for monolith mode. To avoid table name
# collisions across domains, each service gets its own DB unless
# explicitly overridden.
MONOLITH_DB_URL = os.getenv("MONOLITH_DB_URL", "sqlite+pysqlite:////tmp/shamell-monolith.db")
os.environ.setdefault("DB_URL", MONOLITH_DB_URL)
if os.getenv("MONOLITH_MODE", "0") in ("1", "true", "True"):
    os.environ.setdefault("BUS_DB_URL", "sqlite+pysqlite:////tmp/shamell-bus.db")
    os.environ.setdefault("STAYS_DB_URL", "sqlite+pysqlite:////tmp/shamell-stays.db")
    os.environ.setdefault("FOOD_DB_URL", "sqlite+pysqlite:////tmp/shamell-food.db")
    os.environ.setdefault("COMMERCE_DB_URL", "sqlite+pysqlite:////tmp/shamell-commerce.db")
    os.environ.setdefault("PAYMENTS_DB_URL", "sqlite+pysqlite:////tmp/shamell-payments.db")
    os.environ.setdefault("TAXI_DB_URL", "sqlite+pysqlite:////tmp/shamell-taxi.db")
_shared_internal_secret = (
    os.getenv("INTERNAL_API_SECRET")
    or os.getenv("PAYMENTS_INTERNAL_SECRET")
    or uuid.uuid4().hex
)
os.environ.setdefault("INTERNAL_API_SECRET", _shared_internal_secret)
os.environ.setdefault("PAYMENTS_INTERNAL_SECRET", _shared_internal_secret)

# Import routers for domains that already expose APIRouter instances.
# Each import is isolated so one missing legacy module does not disable
# all available routers (e.g. payments/chat in the slim current repo).
jobs_router = None
food_router = None
stays_router = None
payments_router = None
taxi_router = None
bus_router = None
commerce_router = None
carrental_router = None
freight_router = None
agriculture_router = None
doctors_router = None
equipment_router = None
flights_router = None
chat_router = None
carmarket_router = None
livestock_router = None
realestate_router = None
pos_router = None
courier_router = None
pms_router = None
urbify_router = None


def _import_router(module_path: str):
    try:
        module = __import__(module_path, fromlist=["router"])
    except Exception:
        return None
    return getattr(module, "router", None)


def _import_module(module_path: str):
    try:
        return __import__(module_path, fromlist=["*"])
    except Exception:
        return None


# Core services present in this repo layout.
payments_router = _import_router("apps.payments.app.main")
chat_router = _import_router("apps.chat.app.main")

# Optional legacy services.
jobs_router = _import_router("apps.jobs.app.main")
food_router = _import_router("apps.food.app.main")
stays_router = _import_router("apps.stays.app.main")
taxi_router = _import_router("apps.taxi.app.main")
bus_router = _import_router("apps.bus.app.main")
commerce_router = _import_router("apps.commerce.app.main")
carrental_router = _import_router("apps.carrental.app.main")
freight_router = _import_router("apps.freight.app.main")
agriculture_router = _import_router("apps.agriculture.app.main")
doctors_router = _import_router("apps.doctors.app.main")
flights_router = _import_router("apps.flights.app.main")
carmarket_router = _import_router("apps.carmarket.app.main")
livestock_router = _import_router("apps.livestock.app.main")
pos_router = _import_router("apps.pos.app.main")
equipment_router = _import_router("apps.equipment.app.main")
pms_router = _import_router("apps.pms.app.main")
realestate_router = _import_router("apps.realestate.app.main")

courier_main = _import_module("apps.courier.app.main")
if courier_main is not None:
    courier_router = getattr(courier_main, "router", None)
    if hasattr(courier_main, "on_startup"):
        try:
            courier_main.on_startup()  # type: ignore[call-arg]
        except Exception:
            pass
    try:
        courier_main.Base.metadata.create_all(courier_main.engine)  # type: ignore[attr-defined]
    except Exception:
        pass

urbify_main = _import_module("apps.urbify.app.main")
if urbify_main is not None:
    urbify_router = getattr(urbify_main, "router", None)
    if hasattr(urbify_main, "on_startup"):
        try:
            urbify_main.on_startup()  # type: ignore[call-arg]
        except Exception:
            pass
    try:
        urbify_main.Base.metadata.create_all(urbify_main.engine)  # type: ignore[attr-defined]
    except Exception:
        pass


def _mount_service_app(path_prefix: str, app_import_path: str):
    """
    Helper to import an existing FastAPI app and mount it under `path_prefix`.
    `app_import_path` is a dotted path to the module, which must expose `app`.
    """
    module = __import__(app_import_path, fromlist=["app"])
    svc_app = getattr(module, "app")
    # When mounting, we rely on each service app having its own routers under its own prefix.
    root_app.mount(path_prefix, svc_app)


root_app = FastAPI(title="Shamell Monolith", version="0.1.0")

# Shared CORS configuration (secure defaults, configurable via ALLOWED_ORIGINS).
configure_cors(root_app, os.getenv("ALLOWED_ORIGINS", ""))


@root_app.get("/health")
def monolith_health():
    # Lightweight top-level health for the combined app.
    env = os.getenv("ENV", "dev")
    return {"status": "ok", "env": env, "service": "Shamell Monolith"}


def monolith_startup():
    """
    Ensure that critical internal services initialise their database schema
    when running in the monolith.

    In the standalone containers this is handled via each service app's
    own startup hooks. When using the monolith (internal mode), we invoke
    the minimal bootstrap logic here so that required tables exist before
    the BFF hits those services.
    """
    _assert_monolith_only()
    # Payments: create users / wallets tables so /payments/users etc. work.
    try:
        from apps.payments.app import main as payments_main  # type: ignore[import]
        try:
            payments_main.on_startup()  # type: ignore[attr-defined]
        except Exception:
            # Best-effort: we don't want a payments init issue to prevent
            # the entire monolith from starting.
            pass
    except Exception:
        # Payments module not importable; ignore in monolith startup.
        pass

    # Stays (Hotels & Stays): ensure core tables like listings / operators
    # exist so that the operator and guest flows can be used inside the
    # monolith without running a separate stays-api container.
    try:
        from apps.stays.app import main as stays_main  # type: ignore[import]
        try:
            # Mirror the standalone app's startup behaviour:
            # Base.metadata.create_all(engine) + SQLite migrations.
            stays_main.Base.metadata.create_all(stays_main.engine)  # type: ignore[attr-defined]
            if hasattr(stays_main, "_ensure_sqlite_migrations"):
                stays_main._ensure_sqlite_migrations()  # type: ignore[attr-defined]
        except Exception:
            # Best-effort: a stays init issue must not prevent the monolith
            # itself from starting; affected endpoints will surface errors.
            pass
    except Exception:
        # Stays module not importable; ignore in monolith startup.
        pass

    # Bus: ensure that the core tables exist so that the Bus
    # enduser and operator flows work when running in the monolith
    # without a separate bus-api container.
    try:
        from apps.bus.app import main as bus_main  # type: ignore[import]
        try:
            # Prefer the bus app's own schema initialiser (which also applies
            # lightweight SQLite migrations) when available.
            if hasattr(bus_main, "on_startup"):
                bus_main.on_startup()  # type: ignore[call-arg]
            else:
                bus_main.Base.metadata.create_all(bus_main.engine)  # type: ignore[attr-defined]
        except Exception:
            # Best-effort: if initialisation fails we still start the monolith;
            # affected Bus endpoints will surface errors at runtime.
            pass

        # In dev/test, seed a basic list of Syrian cities so that the Bus
        # operator and consumer UIs have meaningful choices in the From/To
        # dropdowns without manual setup. Existing cities are preserved;
        # we only insert missing ones.
        try:
            env = os.getenv("ENV", "dev").lower()
            if env in ("dev", "test"):
                cities = [
                    ("Damascus", "Syria"),
                    ("Aleppo", "Syria"),
                    ("Homs", "Syria"),
                    ("Hama", "Syria"),
                    ("Latakia", "Syria"),
                    ("Tartus", "Syria"),
                    ("Raqqa", "Syria"),
                    ("Deir ez-Zor", "Syria"),
                    ("Idlib", "Syria"),
                    ("As-Suwayda", "Syria"),
                    ("Daraa", "Syria"),
                    ("Al-Hasakah", "Syria"),
                ]
                with Session(bus_main.engine) as s:  # type: ignore[attr-defined]
                    City = bus_main.City  # type: ignore[attr-defined]
                    for name, country in cities:
                        stmt = select(City).where(City.name == name)
                        existing = s.execute(stmt).scalars().first()
                        if existing is not None:
                            continue
                        c = City(
                            id=str(uuid.uuid4()),
                            name=name,
                            country=country,
                        )
                        s.add(c)
                    s.commit()
        except Exception:
            # Seeding cities is best-effort and must not break startup.
            pass
    except Exception:
        # Bus module not importable; ignore in monolith startup.
        pass

    # Carrental: ensure core tables exist so BFF internal mode works.
    try:
        from apps.carrental.app import main as carrental_main  # type: ignore[import]
        try:
            if hasattr(carrental_main, "_startup"):
                carrental_main._startup()  # type: ignore[call-arg]
            else:
                carrental_main.Base.metadata.create_all(carrental_main.engine)  # type: ignore[attr-defined]
        except Exception:
            # Best-effort; errors surface at endpoint call time.
            pass
    except Exception:
        pass

    # Equipment rental: ensure schema exists for internal mode
    try:
        from apps.equipment.app import main as equipment_main  # type: ignore[import]
        try:
            if hasattr(equipment_main, "_startup"):
                equipment_main._startup()  # type: ignore[call-arg]
            else:
                equipment_main.Base.metadata.create_all(equipment_main.engine)  # type: ignore[attr-defined]
        except Exception:
            pass
    except Exception:
        pass

    # POS: ensure core tables exist
    try:
        from apps.pos.app import main as pos_main  # type: ignore[import]
        try:
            if hasattr(pos_main, "on_startup"):
                pos_main.on_startup()  # type: ignore[call-arg]
            else:
                pos_main.Base.metadata.create_all(pos_main.engine)  # type: ignore[attr-defined]
        except Exception:
            pass
    except Exception:
        pass

    # Taxi: ensure that the core tables exist so that the Taxi
    # domain can be used in-process (internal mode) without a
    # separate taxi-api container.
    try:
        from apps.taxi.app import main as taxi_main  # type: ignore[import]
        try:
            taxi_main.Base.metadata.create_all(taxi_main.engine)  # type: ignore[attr-defined]
        except Exception:
            # Best-effort: Taxi init issues must not prevent the monolith
            # from starting; affected Taxi endpoints will surface errors.
            pass
    except Exception:
        # Taxi module not importable; ignore in monolith startup.
        pass

    # Commerce and Food: ensure minimal tables to support operator/consumer flows
    for module_path in ("apps.commerce.app.main", "apps.food.app.main"):
        try:
            mod = __import__(module_path, fromlist=["Base", "engine"])
            base = getattr(mod, "Base", None)
            eng = getattr(mod, "engine", None)
            if base is not None and eng is not None:
                try:
                    base.metadata.create_all(eng)
                except Exception:
                    pass
            # Best-effort demo seeding for Food in local dev (restaurants + menus)
            if module_path == "apps.food.app.main":
                try:
                    seed = getattr(mod, "_ensure_demo_restaurants", None)
                    if callable(seed):
                        seed()
                except Exception:
                    # Seeding must never break monolith startup.
                    pass
        except Exception:
            continue

    # BFF-side storage (Officials / Friends / Nearby presence, etc.):
    # ensure that the lightweight social/official tables exist when running
    # the monolith, even if the BFF app's own startup hooks are not executed.
    try:
        from apps.bff.app import main as bff_main  # type: ignore[import]
        try:
            # Official accounts + feeds + template messages (WeChat-like service accounts).
            if hasattr(bff_main, "_officials_startup"):
                bff_main._officials_startup()  # type: ignore[attr-defined]
        except Exception:
            # Best-effort: failures here should not block the monolith; affected
            # endpoints (e.g. official feed, template messages) will surface errors.
            pass
        try:
            # Friends graph for Moments / chat (phone-based contacts).
            if hasattr(bff_main, "_friends_startup"):
                bff_main._friends_startup()  # type: ignore[attr-defined]
        except Exception:
            pass
        try:
            # People Nearby presence profile/location table.
            if hasattr(bff_main, "_nearby_startup"):
                bff_main._nearby_startup()  # type: ignore[attr-defined]
        except Exception:
            pass
    except Exception:
        # BFF module not importable; ignore in monolith startup.
        pass

# Register startup hook without deprecated decorator
root_app.router.on_startup.append(monolith_startup)
# Also run once at import time to ensure schemas exist in test/dev contexts
try:
    monolith_startup()
except Exception:
    pass


# Optional: mount stub apps for dev/demo when enabled.
if os.getenv("ENABLE_STUBS", "false").lower() == "true":
    try:
        from apps.bff.app.payments_stub import app as payments_stub_app
        root_app.mount("/stub/payments", payments_stub_app)
    except Exception:
        pass
    try:
        from apps.bff.app.taxi_stub import app as taxi_stub_app
        root_app.mount("/stub/taxi", taxi_stub_app)
    except Exception:
        pass


# Mount existing services.
# Domain services under their existing prefixes (without routers yet).
try:
    _mount_service_app("/agents", "apps.agents.app.main")
except Exception:
    # Optional module in this branch layout.
    pass

# Attach routers for domains that already export routers.
if jobs_router is not None:
    root_app.include_router(jobs_router, prefix="/jobs")
if food_router is not None:
    root_app.include_router(food_router, prefix="/food")
if stays_router is not None:
    root_app.include_router(stays_router, prefix="/stays")
if payments_router is not None:
    root_app.include_router(payments_router, prefix="/payments")
if taxi_router is not None:
    root_app.include_router(taxi_router, prefix="/taxi")
if bus_router is not None:
    root_app.include_router(bus_router, prefix="/bus")
if commerce_router is not None:
    root_app.include_router(commerce_router, prefix="/commerce")
if carrental_router is not None:
    root_app.include_router(carrental_router, prefix="/carrental")
if equipment_router is not None:
    root_app.include_router(equipment_router, prefix="/equipment")
if freight_router is not None:
    # Legacy freight prefix (kept for backwards compatibility)
    root_app.include_router(freight_router, prefix="/freight")
if agriculture_router is not None:
    root_app.include_router(agriculture_router, prefix="/agriculture")
if doctors_router is not None:
    root_app.include_router(doctors_router, prefix="/doctors")
if flights_router is not None:
    root_app.include_router(flights_router, prefix="/flights")
if chat_router is not None:
    root_app.include_router(chat_router, prefix="/chat")
if carmarket_router is not None:
    root_app.include_router(carmarket_router, prefix="/carmarket")
if livestock_router is not None:
    root_app.include_router(livestock_router, prefix="/livestock")
if pms_router is not None:
    root_app.include_router(pms_router, prefix="/pms")
if pos_router is not None:
    root_app.include_router(pos_router, prefix="/pos")
if courier_router is not None:
    root_app.include_router(courier_router, prefix="/courier")
if urbify_router is not None:
    root_app.include_router(urbify_router, prefix="/urbify")
if realestate_router is not None:
    root_app.include_router(realestate_router, prefix="/realestate")

# BFF stays at root (/) so its routes remain unchanged.
# Keep this mount last so explicit monolith include_router() paths above
# are matched first instead of being shadowed by the catch-all mount.
_mount_service_app("/", "apps.bff.app.main")


app = root_app
