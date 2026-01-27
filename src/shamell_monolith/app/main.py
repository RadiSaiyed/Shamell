import asyncio
import os
import sys

from fastapi import FastAPI
from shamell_shared import (
    apply_trusted_hosts,
    configure_cors,
    enforce_prod_env,
    require_non_sqlite,
)

# Ensure we can import the service packages from src during dev runs
BASE_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
SRC_DIR = os.path.join(BASE_DIR, "src")
if SRC_DIR not in sys.path:
    sys.path.append(SRC_DIR)

# Default core domains to internal mode so BFF calls stay in-process.
_INTERNAL_DEFAULTS = {
    "CHAT_INTERNAL_MODE": "on",
    "PAYMENTS_INTERNAL_MODE": "on",
    "PAY_INTERNAL_MODE": "on",
    "BFF_PROFILE": "core",
}
for k, v in _INTERNAL_DEFAULTS.items():
    os.environ.setdefault(k, v)

# Monolith-only guard: reject external *_BASE_URL usage when enabled.
MONOLITH_ONLY = os.getenv("MONOLITH_ONLY", "1").lower() not in ("0", "false", "off")
ENV = os.getenv("ENV", "dev").lower()


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
            "unset these to run purely in-process:\n"
            + "\n".join(offenders)
        )


# Shared DB + internal secrets for monolith mode. To avoid table name
# collisions across domains, each service gets its own DB unless
# explicitly overridden.
MONOLITH_DB_URL = os.getenv("MONOLITH_DB_URL", "sqlite+pysqlite:////tmp/shamell-monolith.db")
os.environ.setdefault("DB_URL", MONOLITH_DB_URL)
if os.getenv("MONOLITH_MODE", "0") in ("1", "true", "True"):
    os.environ.setdefault("PAYMENTS_DB_URL", "sqlite+pysqlite:////tmp/shamell-payments.db")
INTERNAL_API_SECRET = os.getenv("INTERNAL_API_SECRET")
PAYMENTS_INTERNAL_SECRET = os.getenv("PAYMENTS_INTERNAL_SECRET")
ALLOWED_HOSTS = os.getenv("ALLOWED_HOSTS")
require_non_sqlite("monolith", MONOLITH_DB_URL, "MONOLITH_DB_URL")
enforce_prod_env(
    "monolith",
    required={
        "INTERNAL_API_SECRET": INTERNAL_API_SECRET,
        "PAYMENTS_INTERNAL_SECRET": PAYMENTS_INTERNAL_SECRET,
        "ALLOWED_HOSTS": ALLOWED_HOSTS,
    },
    forbidden={
        "INTERNAL_API_SECRET": (INTERNAL_API_SECRET, {"change-me", "monolith-internal"}),
        "PAYMENTS_INTERNAL_SECRET": (
            PAYMENTS_INTERNAL_SECRET,
            {"change-me", "monolith-internal"},
        ),
    },
)


def _mount_service_app(path_prefix: str, app_import_path: str):
    """
    Helper to import an existing FastAPI app and mount it under `path_prefix`.
    `app_import_path` is a dotted path to the module, which must expose `app`.
    """
    module = __import__(app_import_path, fromlist=["app"])
    svc_app = getattr(module, "app")
    # When mounting, we rely on each service app having its own routers under its own prefix.
    root_app.mount(path_prefix, svc_app)


# NOTE: The monolith mounts the BFF at "/". FastAPI does not merge mounted
# sub-app routes into the parent OpenAPI schema, and the parent's default
# `/openapi.json`/`/docs` would also shadow the BFF docs.
#
# In production, API docs are intentionally allowlisted (Traefik + app-level).
# To avoid accidentally exposing a "second" set of docs paths, the monolith's
# own docs/openapi are disabled in prod.
_ENABLE_MONOLITH_DOCS = ENV not in ("prod", "production")
root_app = FastAPI(
    title="Shamell Monolith",
    version="0.1.0",
    docs_url="/_monolith/docs" if _ENABLE_MONOLITH_DOCS else None,
    swagger_ui_oauth2_redirect_url=(
        "/_monolith/docs/oauth2-redirect" if _ENABLE_MONOLITH_DOCS else None
    ),
    redoc_url="/_monolith/redoc" if _ENABLE_MONOLITH_DOCS else None,
    openapi_url="/_monolith/openapi.json" if _ENABLE_MONOLITH_DOCS else None,
)
configure_cors(root_app, os.getenv("ALLOWED_ORIGINS", "*"))
apply_trusted_hosts(root_app, os.getenv("ALLOWED_HOSTS"))


@root_app.get("/health")
def monolith_health():
    # Lightweight top-level health for the combined app.
    env = os.getenv("ENV", "dev")
    return {"status": "ok", "env": env, "service": "Shamell Monolith"}


async def monolith_startup():
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
        from shamell_payments.app import main as payments_main  # type: ignore[import]
        try:
            payments_main.on_startup()  # type: ignore[attr-defined]
        except Exception:
            # Best-effort: we don't want a payments init issue to prevent
            # the entire monolith from starting.
            pass
    except Exception:
        # Payments module not importable; ignore in monolith startup.
        pass

    # Chat: ensure core tables exist for in-process access.
    try:
        from shamell_chat.app import main as chat_main  # type: ignore[import]
        try:
            chat_main._startup()  # type: ignore[attr-defined]
        except Exception:
            pass
    except Exception:
        pass

    # BFF-side storage (Officials / Friends / Nearby presence, etc.):
    # ensure that the lightweight social/official tables exist when running
    # the monolith, even if the BFF app's own startup hooks are not executed.
    try:
        from shamell_bff.app import main as bff_main  # type: ignore[import]
        try:
            # Mounted sub-apps do NOT automatically run lifespan hooks in FastAPI/Starlette.
            # Run the BFF startup manually to mount feature routes and seed defaults.
            if hasattr(bff_main, "_startup") and hasattr(bff_main, "app"):
                res = bff_main._startup(bff_main.app)  # type: ignore[attr-defined]
                if asyncio.iscoroutine(res):
                    await res
        except Exception:
            pass
        try:
            # Official accounts + feeds + template messages (Shamell-like service accounts).
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
    # Avoid creating an un-awaited coroutine when running inside an existing loop.
    try:
        asyncio.get_running_loop()
    except RuntimeError:
        asyncio.run(monolith_startup())
except Exception:
    pass


# Mount existing services.
# BFF remains at root (/) so its routes remain unchanged.
_mount_service_app("/", "shamell_bff.app.main")


app = root_app
