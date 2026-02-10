from __future__ import annotations

from fastapi import FastAPI, HTTPException, Request
from fastapi import WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse, Response, JSONResponse, StreamingResponse, FileResponse
from starlette.middleware.trustedhost import TrustedHostMiddleware
from starlette.responses import RedirectResponse
from shamell_shared import RequestIDMiddleware, configure_cors, add_standard_health, setup_json_logging
from pydantic import BaseModel
from .events import emit_event
from sqlalchemy import (
    create_engine as _sa_create_engine,
    String as _sa_String,
    Integer as _sa_Integer,
    Boolean as _sa_Boolean,
    DateTime as _sa_DateTime,
    Text as _sa_Text,
    UniqueConstraint as _sa_UniqueConstraint,
    delete as _sa_delete,
    func as _sa_func,
    select as _sa_select,
    text as _sa_text,
    Float as _sa_Float,
)
from sqlalchemy.orm import (
    DeclarativeBase as _sa_DeclarativeBase,
    Mapped as _sa_Mapped,
    mapped_column as _sa_mapped_column,
    Session as _sa_Session,
)
import httpx
import logging
import os
import asyncio, json as _json, re
import base64
import hashlib
import ipaddress
import socket
import hmac as _hmac
import html as _html
import math
from pathlib import Path
from functools import lru_cache
import secrets as _secrets
import time, uuid as _uuid
from typing import Any
from io import BytesIO
import urllib.parse as _urlparse
try:
    from PIL import Image, ImageDraw, ImageFont
except Exception:
    Image = None
try:
    import qrcode as _qr
except Exception:
    _qr = None
try:
    from reportlab.pdfgen import canvas as _pdfcanvas
    from reportlab.lib.pagesizes import A4
    from reportlab.lib.utils import ImageReader as _RLImageReader
except Exception:
    _pdfcanvas = None


def _env_or(key: str, default: str) -> str:
    v = os.getenv(key)
    return v if v is not None else default

def _parse_ip_networks(raw: str) -> list[ipaddress._BaseNetwork]:  # type: ignore[name-defined]
    out: list[ipaddress._BaseNetwork] = []  # type: ignore[name-defined]
    for chunk in (raw or "").split(","):
        item = chunk.strip()
        if not item:
            continue
        try:
            out.append(ipaddress.ip_network(item, strict=False))
        except Exception:
            continue
    return out

_TEMPLATES_DIR = Path(__file__).resolve().parent / "templates"


@lru_cache(maxsize=64)
def _load_html_template(name: str) -> str:
    # Only allow file basenames (no path traversal).
    if Path(name).name != name:
        raise RuntimeError("invalid template name")
    p = _TEMPLATES_DIR / name
    return p.read_text(encoding="utf-8")


def _html_template_response(name: str) -> HTMLResponse:
    try:
        return HTMLResponse(content=_load_html_template(name))
    except HTTPException:
        raise
    except Exception:
        # Avoid leaking filesystem paths in error messages.
        raise HTTPException(status_code=500, detail="Server misconfiguration")



_ENV_LOWER = _env_or("ENV", "dev").lower()
# In prod/staging, fail-closed route allowlisting reduces accidental exposure of
# legacy/unused endpoints. Keep it configurable for staged rollouts.
_BFF_ROUTE_ALLOWLIST_DEFAULT = "true" if _ENV_LOWER in ("prod", "production", "staging") else "false"
BFF_ROUTE_ALLOWLIST_ENABLED = _env_or("BFF_ROUTE_ALLOWLIST_ENABLED", _BFF_ROUTE_ALLOWLIST_DEFAULT).lower() == "true"

_DEFAULT_BFF_ALLOWED_PATHS_EXACT = {
    "/",
    "/health",
    "/favicon.ico",
    "/openapi.json",
    "/docs",
    "/docs/oauth2-redirect",
    "/redoc",
    "/qr.png",
    "/ds.js",
}
_DEFAULT_BFF_ALLOWED_PATH_PREFIXES = [
    # Core web/app surfaces
    "/app",
    "/home",
    "/login",
    "/brand",
    "/icons",
    # Core WeChat-like platform APIs
    "/auth",
    "/me",
    "/friends",
    "/chat",
    "/payments",
    "/wallets",
    "/topup",
    "/mini_apps",
    "/mini_programs",
    "/official_accounts",
    "/moments",
    "/channels",
    "/search",
    "/push",
    # Shared infra endpoints
    "/metrics",
    "/upstreams",
    "/osm",
    "/fleet",
    "/calls",
    "/livekit",
    "/admin",
    # Bus mini-app
    "/bus",
    # Stickers are used by chat in most clients
    "/stickers",
]

_BFF_ALLOWED_PATHS_EXACT_RAW = _env_or("BFF_ROUTE_ALLOWLIST_EXACT", "").strip()
if _BFF_ALLOWED_PATHS_EXACT_RAW:
    BFF_ALLOWED_PATHS_EXACT = {p.strip() for p in _BFF_ALLOWED_PATHS_EXACT_RAW.split(",") if p.strip()}
else:
    BFF_ALLOWED_PATHS_EXACT = _DEFAULT_BFF_ALLOWED_PATHS_EXACT

_BFF_ALLOWED_PREFIXES_RAW = _env_or("BFF_ROUTE_ALLOWLIST_PREFIXES", "").strip()
if _BFF_ALLOWED_PREFIXES_RAW:
    BFF_ALLOWED_PATH_PREFIXES = [p.strip() for p in _BFF_ALLOWED_PREFIXES_RAW.split(",") if p.strip()]
else:
    BFF_ALLOWED_PATH_PREFIXES = _DEFAULT_BFF_ALLOWED_PATH_PREFIXES
# Never expose interactive API docs by default in prod.
_ENABLE_DOCS = _ENV_LOWER in ("dev", "test") or os.getenv("ENABLE_API_DOCS_IN_PROD", "").lower() in (
    "1",
    "true",
    "yes",
    "on",
)
app = FastAPI(
    title="Shamell BFF",
    version="0.1.0",
    docs_url="/docs" if _ENABLE_DOCS else None,
    redoc_url="/redoc" if _ENABLE_DOCS else None,
    openapi_url="/openapi.json" if _ENABLE_DOCS else None,
)
setup_json_logging()
app.add_middleware(RequestIDMiddleware)
configure_cors(app, os.getenv("ALLOWED_ORIGINS", ""))
add_standard_health(app)

# Best practice: never leak internal stack traces / upstream exception details in prod/staging.
def _is_prod_env() -> bool:
    env = (os.getenv("ENV") or "dev").strip().lower()
    return env in ("prod", "production", "staging")


@app.exception_handler(HTTPException)
async def _http_exception_handler(request: Request, exc: HTTPException):
    try:
        # Scrub server-side error details in prod/staging.
        if _is_prod_env() and int(getattr(exc, "status_code", 500) or 500) >= 500:
            try:
                from shamell_shared.request_id import get_request_id  # type: ignore[import]

                rid = get_request_id()
            except Exception:
                rid = None
            payload: dict[str, Any] = {"detail": "internal error"}
            if rid:
                payload["request_id"] = rid
            return JSONResponse(status_code=exc.status_code, content=payload)
    except Exception:
        pass
    return JSONResponse(status_code=exc.status_code, content={"detail": exc.detail})


@app.exception_handler(Exception)
async def _unhandled_exception_handler(request: Request, exc: Exception):
    try:
        from shamell_shared.request_id import get_request_id  # type: ignore[import]

        rid = get_request_id()
    except Exception:
        rid = None
    try:
        logging.getLogger("shamell.errors").exception(
            "unhandled exception", extra={"request_id": rid}
        )
    except Exception:
        pass
    if _is_prod_env():
        payload: dict[str, Any] = {"detail": "internal error"}
        if rid:
            payload["request_id"] = rid
        return JSONResponse(status_code=500, content=payload)
    # dev/test: keep a useful error message for debugging.
    payload = {"detail": str(exc)}
    if rid:
        payload["request_id"] = rid
    return JSONResponse(status_code=500, content=payload)

# Trusted hosts: mitigate Host header attacks and misrouting.
_allowed_hosts_raw = (os.getenv("ALLOWED_HOSTS") or "").strip()
if _allowed_hosts_raw:
    _allowed_hosts = [h.strip() for h in _allowed_hosts_raw.split(",") if h.strip()]
    # Keep local health checks working even if ALLOWED_HOSTS is minimal.
    for _extra in ("localhost", "127.0.0.1"):
        if _extra not in _allowed_hosts:
            _allowed_hosts.append(_extra)
    app.add_middleware(TrustedHostMiddleware, allowed_hosts=_allowed_hosts)


def _running_under_pytest() -> bool:
    # pytest sets this env var per-test; used to avoid prod-only startup checks
    # breaking unit tests that temporarily set ENV=prod.
    return bool(os.getenv("PYTEST_CURRENT_TEST"))


def _should_validate_runtime_config() -> bool:
    if _running_under_pytest() and _env_or("BFF_VALIDATE_CONFIG_UNDER_PYTEST", "false").lower() not in (
        "1",
        "true",
        "yes",
        "on",
    ):
        return False
    env = (os.getenv("ENV") or "dev").strip().lower()
    default = "true" if env in ("prod", "production", "staging") else "false"
    raw = _env_or("BFF_VALIDATE_CONFIG", default).strip().lower()
    return raw in ("1", "true", "yes", "on")


def _validate_runtime_config() -> None:
    """
    Fail-fast config validation for prod/staging.

    This catches common misconfigurations that otherwise downgrade security
    silently (e.g., missing ALLOWED_HOSTS) or violate the "microservices in prod"
    constraint (internal domain modes).
    """
    if not _should_validate_runtime_config():
        return

    env = (os.getenv("ENV") or "dev").strip().lower()
    if env not in ("prod", "production", "staging"):
        return

    errors: list[str] = []
    warnings: list[str] = []

    # Host header hardening should always be enabled in prod/staging.
    allowed_hosts_raw = (os.getenv("ALLOWED_HOSTS") or "").strip()
    allowed_hosts = [h.strip() for h in allowed_hosts_raw.split(",") if h.strip()]
    if not allowed_hosts:
        errors.append("ALLOWED_HOSTS must be set (comma-separated) in prod/staging")
    elif "*" in allowed_hosts:
        errors.append("ALLOWED_HOSTS must not contain '*' in prod/staging")

    # CORS: prevent accidental wildcard origins in prod/staging.
    allowed_origins_raw = (os.getenv("ALLOWED_ORIGINS") or "").strip()
    allowed_origins = [o.strip() for o in allowed_origins_raw.split(",") if o.strip()]
    if "*" in allowed_origins:
        errors.append("ALLOWED_ORIGINS must not contain '*' in prod/staging")
    # Enforce TLS origins only (except local dev).
    insecure = [
        o
        for o in allowed_origins
        if o.startswith("http://")
        and not (o.startswith("http://localhost") or o.startswith("http://127.0.0.1"))
    ]
    if insecure:
        errors.append("ALLOWED_ORIGINS must use https:// in prod/staging (non-local origins)")
    if not allowed_origins:
        warnings.append("ALLOWED_ORIGINS is empty; browser clients may be unable to call the API")

    # Microservices-in-prod guardrails: forbid internal (single-process) domain modes.
    if _env_or("FORCE_INTERNAL_DOMAINS", "false").lower() in ("1", "true", "yes", "on"):
        errors.append("FORCE_INTERNAL_DOMAINS must be disabled in prod/staging")

    if (os.getenv("PAYMENTS_INTERNAL_MODE") or "auto").lower() == "on":
        errors.append("PAYMENTS_INTERNAL_MODE=on is forbidden in prod/staging (microservices required)")
    if (os.getenv("BUS_INTERNAL_MODE") or "auto").lower() == "on":
        errors.append("BUS_INTERNAL_MODE=on is forbidden in prod/staging (microservices required)")
    if (os.getenv("CHAT_INTERNAL_MODE") or "auto").lower() == "on":
        errors.append("CHAT_INTERNAL_MODE=on is forbidden in prod/staging (microservices required)")

    # Upstream bases and internal auth secrets should be configured in prod/staging.
    # These globals are defined below in this module (loaded at import time).
    try:
        if not PAYMENTS_BASE:
            errors.append("PAYMENTS_BASE_URL must be set in prod/staging")
        if not BUS_BASE:
            errors.append("BUS_BASE_URL must be set in prod/staging")
        if not CHAT_BASE:
            errors.append("CHAT_BASE_URL must be set in prod/staging")
    except Exception:
        # If globals aren't available for some reason, keep going.
        pass

    try:
        if not PAYMENTS_INTERNAL_SECRET:
            errors.append("PAYMENTS_INTERNAL_SECRET (or INTERNAL_API_SECRET) must be set in prod/staging")
        if not BUS_INTERNAL_SECRET:
            errors.append("BUS_INTERNAL_SECRET must be set in prod/staging")
        if not INTERNAL_API_SECRET:
            errors.append("INTERNAL_API_SECRET must be set in prod/staging (chat internal auth)")
    except Exception:
        pass

    # Never leak OTPs in prod/staging.
    try:
        if bool(AUTH_EXPOSE_CODES):
            errors.append("AUTH_EXPOSE_CODES must be disabled in prod/staging")
    except Exception:
        pass

    if warnings:
        try:
            logging.getLogger("shamell.config").warning(
                "bff startup config warnings: %s", "; ".join(warnings)
            )
        except Exception:
            pass
    if errors:
        raise RuntimeError("bff startup config invalid: " + "; ".join(errors))

_HTTPX_CLIENT: httpx.Client | None = None
_HTTPX_ASYNC_CLIENT: httpx.AsyncClient | None = None


def _httpx_client() -> httpx.Client:
    """Shared sync HTTPX client (keep-alive, pooled)."""
    global _HTTPX_CLIENT
    if _HTTPX_CLIENT is None:
        _HTTPX_CLIENT = httpx.Client(
            timeout=10.0,
            limits=httpx.Limits(max_keepalive_connections=20, max_connections=100),
        )
    return _HTTPX_CLIENT


def _httpx_async_client() -> httpx.AsyncClient:
    """Shared async HTTPX client (keep-alive, pooled)."""
    global _HTTPX_ASYNC_CLIENT
    if _HTTPX_ASYNC_CLIENT is None:
        _HTTPX_ASYNC_CLIENT = httpx.AsyncClient(
            timeout=10.0,
            limits=httpx.Limits(max_keepalive_connections=20, max_connections=100),
        )
    return _HTTPX_ASYNC_CLIENT

_audit_logger = logging.getLogger("shamell.audit")
_metrics_logger = logging.getLogger("shamell.metrics")
_AUDIT_EVENTS: list[dict[str, Any]] = []
_MAX_AUDIT_EVENTS = 2000


class _AuditInMemoryHandler(logging.Handler):
    """
    Kapselt alle Audit-Logs (logger \"shamell.audit\") in einem kleinen
    In-Memory-Puffer, damit /admin/stats und /admin/guardrails auch
    Domain-Events (z.B. payments/bus/chat) sehen.
    """

    def emit(self, record: logging.LogRecord) -> None:  # type: ignore[override]
        try:
            msg = record.msg
            if isinstance(msg, dict):
                payload = dict(msg)
            else:
                payload = {
                    "event": "audit",
                    "action": record.getMessage(),
                }
            if "ts_ms" not in payload:
                payload["ts_ms"] = int(time.time() * 1000)
            _AUDIT_EVENTS.append(payload)  # type: ignore[arg-type]
            if len(_AUDIT_EVENTS) > _MAX_AUDIT_EVENTS:
                del _AUDIT_EVENTS[: len(_AUDIT_EVENTS) - _MAX_AUDIT_EVENTS]
        except Exception:
            # Audit buffer must never break normal flows
            pass


_audit_logger.addHandler(_AuditInMemoryHandler())
_audit_logger.setLevel(logging.INFO)

# Simple background stats (internal-mode heartbeat etc.)
_BG_STATS: dict[str, Any] = {"last_tick_ms": None}

# Small in-memory caches for frequently used lists
_BUS_CITIES_CACHE: dict[str, Any] = {"ts": 0.0, "data": None}
_OSM_GEOCODE_CACHE: dict[str, tuple[float, Any]] = {}
_OSM_REVERSE_CACHE: dict[tuple[float, float], tuple[float, Any]] = {}

# Simple Moments cache / DB will be handled via dedicated SQLAlchemy models below.

# In-memory VoIP signaling connections (device_id -> WebSocket)
_CALL_WS_CONNECTIONS: dict[str, WebSocket] = {}


def _haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """
    Great-circle distance between two points on Earth (in km).
    Used for simple fleet heuristics (nearest driver, stop ordering).
    """
    try:
        r = 6371.0
        phi1 = math.radians(lat1)
        phi2 = math.radians(lat2)
        dphi = math.radians(lat2 - lat1)
        dlambda = math.radians(lon2 - lon1)
        a = math.sin(dphi / 2.0) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2.0) ** 2
        c = 2 * math.atan2(math.sqrt(a), math.sqrt(1.0 - a))
        return float(r * c)
    except Exception:
        return 0.0

# In-memory payment guardrails (best-effort)
_PAY_VELOCITY_WALLET: dict[str, list[float]] = {}
_PAY_VELOCITY_DEVICE: dict[str, list[float]] = {}
PAY_VELOCITY_WINDOW_SECS = int(os.getenv("PAY_VELOCITY_WINDOW_SECS", "60"))
PAY_VELOCITY_MAX_PER_WALLET = int(os.getenv("PAY_VELOCITY_MAX_PER_WALLET", "20"))
PAY_VELOCITY_MAX_PER_DEVICE = int(os.getenv("PAY_VELOCITY_MAX_PER_DEVICE", "40"))
PAY_MAX_PER_TXN_CENTS = int(os.getenv("PAY_MAX_PER_TXN_CENTS", "0"))  # 0 = disabled


def _legacy_console_removed_page(title: str = "Shamell") -> HTMLResponse:
    """
    Unified minimal page for all legacy HTML consoles.
    Keeps routes functional but clearly points to the Shamell UI.
    """
    html = f"""
<!doctype html>
<html><head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>{title}</title>
  <style>
    body{{font-family:sans-serif;margin:20px;max-width:640px;color:#0f172a;background:#ffffff;}}
    h1{{margin-bottom:8px;}}
    p{{margin:6px 0;}}
    code{{background:#f3f4f6;padding:2px 4px;border-radius:3px;font-size:13px;}}
  </style>
</head><body>
  <h1>{title}</h1>
  <p>This legacy HTML console has been removed.</p>
  <p>Please use the Shamell web app as the admin UI.</p>
  <p><code>http://localhost:8081</code></p>
</body></html>
"""
    return HTMLResponse(content=html)


@app.middleware("http")
async def _security_headers_mw(request: Request, call_next):
    """
    Adds basic security headers and can optionally enforce a
    global maintenance mode.
    """
    # Global maintenance mode: all non-admin / non-health routes are
    # answered with 503. Admins can still operate the system.
    if MAINTENANCE_MODE_ENABLED:
        path = request.url.path
        if not (path.startswith("/admin") or path.startswith("/health")):
            return JSONResponse(
                status_code=503,
                content={
                    "status": "maintenance",
                    "detail": "service temporarily unavailable",
                },
                headers={"Retry-After": "60"},
            )

    # Route allowlist (prod/staging default): reduce accidental exposure of
    # legacy/unused endpoints. Return 404 to avoid endpoint enumeration.
    if BFF_ROUTE_ALLOWLIST_ENABLED:
        try:
            path = request.url.path
        except Exception:
            path = ""
        if path:
            if path not in BFF_ALLOWED_PATHS_EXACT and not any(path.startswith(p) for p in BFF_ALLOWED_PATH_PREFIXES):
                return JSONResponse(status_code=404, content={"detail": "not found"})

    # Defense-in-depth CSRF guard: only applies to cookie-authenticated
    # non-idempotent requests. Header-based sessions (`sa_cookie`) are not
    # vulnerable to browser CSRF, because attackers cannot set custom headers.
    try:
        block = _csrf_guard(request)
        if block is not None:
            return block
    except Exception:
        # CSRF guard must never break normal flows
        pass

    response = await call_next(request)
    if SECURITY_HEADERS_ENABLED:
        try:
            headers = response.headers
            path = request.url.path
            headers.setdefault("X-Content-Type-Options", "nosniff")
            headers.setdefault("X-Frame-Options", "DENY")
            headers.setdefault("Referrer-Policy", "strict-origin-when-cross-origin")
            headers.setdefault("X-Permitted-Cross-Domain-Policies", "none")
            if HSTS_ENABLED:
                headers.setdefault("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
            headers.setdefault(
                "Content-Security-Policy",
                "default-src 'self'; img-src 'self' data:; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; connect-src 'self' https:; frame-ancestors 'none'",
            )
            # Prevent caching of sensitive API responses by browsers or intermediaries.
            if path.startswith(("/payments", "/me/", "/bus", "/auth", "/admin", "/chat", "/moments")):
                headers.setdefault("Cache-Control", "no-store")
        except Exception:
            # Security headers must never break normal flows
            pass
    return response

async def _start_bg_tasks():
    # Lightweight heartbeat only in dev/staging
    if _env_or("ENABLE_BFF_BG", "false").lower() != "true":
        return

    async def _loop():
        while True:
            try:
                _BG_STATS["last_tick_ms"] = int(time.time() * 1000)
            except Exception:
                pass
            await asyncio.sleep(60)

    asyncio.create_task(_loop())

# Register startup hook without deprecated decorator
app.router.on_startup.append(_validate_runtime_config)
app.router.on_startup.append(_start_bg_tasks)


async def _shutdown_http_clients():
    """Close shared HTTPX clients on shutdown."""
    global _HTTPX_CLIENT, _HTTPX_ASYNC_CLIENT
    try:
        if _HTTPX_CLIENT is not None:
            _HTTPX_CLIENT.close()
    except Exception:
        pass
    try:
        if _HTTPX_ASYNC_CLIENT is not None:
            await _HTTPX_ASYNC_CLIENT.aclose()
    except Exception:
        pass
    _HTTPX_CLIENT = None
    _HTTPX_ASYNC_CLIENT = None


app.router.on_shutdown.append(_shutdown_http_clients)

# --- Lightweight metrics intake (optional) ---
_METRICS = []  # in-memory ring buffer

@app.post("/metrics")
async def metrics_ingest(req: Request):
    if _ENV_LOWER not in ("dev", "test") and not METRICS_INGEST_SECRET:
        # Avoid unauthenticated log/memory spam in prod/staging when the secret
        # is not configured.
        raise HTTPException(status_code=403, detail="metrics ingest disabled")
    if METRICS_INGEST_SECRET:
        provided = (req.headers.get("X-Metrics-Secret") or "").strip()
        if not _hmac.compare_digest(provided, METRICS_INGEST_SECRET):
            raise HTTPException(status_code=401, detail="metrics auth required")

    # Lightweight size guardrails (best-effort; also enforce at the edge when possible).
    try:
        cl = req.headers.get("content-length")
        if cl and int(cl) > METRICS_INGEST_MAX_BYTES:
            raise HTTPException(status_code=413, detail="metrics payload too large")
    except ValueError:
        raise HTTPException(status_code=400, detail="invalid content-length")

    raw = await req.body()
    if raw and len(raw) > METRICS_INGEST_MAX_BYTES:
        raise HTTPException(status_code=413, detail="metrics payload too large")

    try:
        body = _json.loads(raw) if raw else {}
    except Exception:
        body = {}
    if not isinstance(body, dict):
        body = {}
    try:
        dev = (req.headers.get("X-Device-ID") or "")[:128]
    except Exception:
        dev = ""
    item = {"ts": int(time.time() * 1000), "device": dev, "data": body}
    _METRICS.append(item)
    if len(_METRICS) > 2000:
        del _METRICS[:len(_METRICS)-2000]
    try:
        _metrics_logger.info(item)
    except Exception:
        # Metrics logging must never break main flows
        pass
    return {"ok": True}

@app.get("/metrics", response_class=JSONResponse)
def metrics_dump(request: Request, limit: int = 200):
    _require_admin_v2(request)
    return {"items": _METRICS[-limit:]}


@app.get("/admin/metrics", response_class=HTMLResponse)
def metrics_html(request: Request, limit: int = 200):
    """
    Simple HTML view for metrics from Perf/_metrics.
    Black text on white background, without visual effects.
    """
    _require_admin_v2(request)
    # Legacy HTML dashboard removed – use Shamell instead.
    return _legacy_console_removed_page("Shamell · Metrics")
@app.get("/admin/stats", response_class=JSONResponse)
def admin_stats(request: Request, limit: int = 200):
    """
    JSON variant of the most important metric aggregates for the Superadmin UI.
    Returns sample metrics (avg/min/max) and action counts.
    """
    _require_admin_v2(request)
    items = _METRICS[-limit:]

    action_counts: dict[str, int] = {}
    sample_stats: dict[str, dict[str, float]] = {}

    for it in items:
        try:
            mtype = it.get("type", "")
            data = it.get("data", {}) or {}
            if not isinstance(data, dict):
                continue
            if mtype == "action":
                label = str(data.get("label", "") or "")
                if label:
                    action_counts[label] = action_counts.get(label, 0) + 1
            elif mtype == "sample":
                metric = str(data.get("metric", "") or "")
                val = data.get("value_ms")
                if metric and isinstance(val, (int, float)):
                    v = float(val)
                    st = sample_stats.get(metric)
                    if st is None:
                        st = {"count": 0.0, "sum": 0.0, "min": v, "max": v}
                        sample_stats[metric] = st
                    st["count"] += 1.0
                    st["sum"] += v
                    if v < st["min"]:
                        st["min"] = v
                    if v > st["max"]:
                        st["max"] = v
        except Exception:
            continue

    samples_out: dict[str, dict[str, float]] = {}
    for metric, st in sample_stats.items():
        cnt = int(st.get("count", 0.0) or 0)
        if cnt <= 0:
            continue
        total = st.get("sum", 0.0) or 0.0
        avg = total / cnt if cnt else 0.0
        samples_out[metric] = {
            "count": float(cnt),
            "avg_ms": avg,
            "min_ms": st.get("min", 0.0) or 0.0,
            "max_ms": st.get("max", 0.0) or 0.0,
        }

    # Guardrail counts from audit log (best-effort)
    guardrail_counts: dict[str, int] = {}
    try:
        # consider only recent audit events
        tail = _AUDIT_EVENTS[-limit:]
        for e in tail:
            action = str(e.get("action", "") or "")
            if not action:
                continue
            if "guardrail" in action:
                guardrail_counts[action] = guardrail_counts.get(action, 0) + 1
    except Exception:
        guardrail_counts = {}

    return {
        "samples": samples_out,
        "actions": action_counts,
        "total_events": len(items),
        "guardrails": guardrail_counts,
    }


@app.get("/admin/finance_stats", response_class=JSONResponse)
def admin_finance_stats(request: Request, from_iso: str | None = None, to_iso: str | None = None):
    """
    Finance statistics over the Payments domain service:
    - total_txns: number of transactions in the period
    - total_fee_cents: total fees charged in the period
    """
    _require_admin_v2(request)

    # For internal-mode deployments we rely on internal calls.
    if not _use_pay_internal():
        raise HTTPException(status_code=500, detail="payments internal not available")

    from_iso_eff = from_iso
    to_iso_eff = to_iso

    # Optional default period (last 24h) when nothing is provided
    if from_iso_eff is None and to_iso_eff is None:
        try:
            now = time.time()
            end = int(now)
            start = end - 86400
            from_iso_eff = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(start))
            to_iso_eff = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(end))
        except Exception:
            from_iso_eff = None
            to_iso_eff = None

    total_txns = 0
    total_fee_cents = 0
    fee_from_ts: str | None = None
    fee_to_ts: str | None = None

    try:
        with _pay_internal_session() as s:
            # Transaction count
            try:
                cnt = _pay_admin_txns_count(
                    wallet_id=None,
                    from_iso=from_iso_eff,
                    to_iso=to_iso_eff,
                    s=s,
                )
                if isinstance(cnt, dict):
                    total_txns = int(cnt.get("count") or 0)
            except Exception:
                total_txns = 0
            # Fee sum
            try:
                fees = _pay_fees_summary(from_iso=from_iso_eff, to_iso=to_iso_eff, s=s)
                if hasattr(fees, "dict"):
                    data = fees.dict()  # type: ignore[call-arg]
                elif isinstance(fees, dict):
                    data = fees
                else:
                    data = {}
                total_fee_cents = int(data.get("total_fee_cents") or 0)
                fee_from_ts = data.get("from_ts") or from_iso_eff
                fee_to_ts = data.get("to_ts") or to_iso_eff
            except Exception:
                total_fee_cents = 0
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"finance stats error: {e}")

    return {
        "from_iso": fee_from_ts or from_iso_eff,
        "to_iso": fee_to_ts or to_iso_eff,
        "total_txns": total_txns,
        "total_fee_cents": total_fee_cents,
    }


@app.get("/admin/guardrails", response_class=HTMLResponse)
def guardrails_html(request: Request, limit: int = 200) -> HTMLResponse:
    """
    Minimal admin dashboard for guardrail audit events (legacy HTML).
    Shows recent audit entries whose action contains "guardrail".
    """
    _require_admin_v2(request)
    try:
        tail = list(_AUDIT_EVENTS[-limit:])
    except Exception:
        tail = []
    guardrails = [
        e for e in tail
        if isinstance(e, dict) and "guardrail" in str(e.get("action", "")).lower()
    ]
    rows = []
    def esc(v: Any) -> str:
        return _html.escape(str(v or ""), quote=True)
    for e in guardrails:
        try:
            details = {k: v for k, v in e.items() if k not in ("ts_ms", "action", "phone")}
            try:
                details_json = _json.dumps(details, sort_keys=True, ensure_ascii=False)
            except Exception:
                details_json = str(details)
            rows.append(
                "<tr>"
                f"<td>{esc(e.get('ts_ms',''))}</td>"
                f"<td>{esc(e.get('action',''))}</td>"
                f"<td>{esc(e.get('phone','') or '')}</td>"
                f"<td><pre>{esc(details_json)}</pre></td>"
                "</tr>"
            )
        except Exception:
            continue
    if not rows:
        rows.append("<tr><td colspan='4'>No guardrail events yet.</td></tr>")
    html = f"""
<!doctype html>
<html><head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Shamell · Guardrails</title>
    <style>
    body{{font-family:sans-serif;margin:16px;max-width:900px;color:#0f172a;}}
    table{{border-collapse:collapse;width:100%;}}
    th,td{{border:1px solid #e5e7eb;padding:6px 8px;font-size:13px;text-align:left;}}
    th{{background:#f9fafb;font-weight:600;}}
    pre{{white-space:pre-wrap;font-family:ui-monospace,monospace;font-size:12px;margin:0;background:#f3f4f6;padding:6px 8px;border-radius:6px;}}
  </style>
</head><body>
  <h1>Guardrail Audit</h1>
  <p>Last {len(guardrails)} guardrail events (max {limit}). Non-guardrail audit items are hidden.</p>
  <table>
    <thead><tr><th>ts_ms</th><th>action</th><th>phone</th><th>details</th></tr></thead>
    <tbody>
      {"".join(rows)}
    </tbody>
  </table>
</body></html>
"""
    return HTMLResponse(content=html)


@app.get("/admin/quality", response_class=HTMLResponse)
def admin_quality(request: Request, limit: int = 200) -> HTMLResponse:
    """
    Compact quality dashboard for admins (legacy HTML).
    Replaced by Shamell; this route now only returns a minimal notice.
    """
    _require_admin_v2(request)
    # Legacy HTML dashboard removed – please use Shamell instead.
    return _legacy_console_removed_page("Shamell · Quality")


@app.get("/admin/info", response_class=JSONResponse)
def admin_info(request: Request):
    """
    Compact admin info about environment and domain modes.
    Only accessible for admins/superadmins.
    """
    _require_admin_v2(request)
    env = _env_or("ENV", "dev")
    domains: dict[str, dict[str, Any]] = {
        "payments": {"internal": bool(_use_pay_internal()), "base_url": PAYMENTS_BASE},
        "bus": {"internal": bool(_use_bus_internal()), "base_url": BUS_BASE},
        "chat": {"internal": bool(_use_chat_internal()), "base_url": CHAT_BASE},
        "livekit": {
            "configured": bool(LIVEKIT_PUBLIC_URL and LIVEKIT_API_KEY and LIVEKIT_API_SECRET),
            "public_url": LIVEKIT_PUBLIC_URL or None,
        },
    }
    internal_mode = any(bool(d.get("internal")) for d in domains.values())

    return {
        "env": env,
        "internal_mode": internal_mode,
        "security_headers": SECURITY_HEADERS_ENABLED,
        "domains": domains,
    }

# --- Wallet WebSocket (dev) ---
@app.websocket("/ws/payments/wallets/{wallet_id}")
async def ws_wallet_events(websocket: WebSocket, wallet_id: str):
    # Simple polling-based wallet credit stream over WS
    if _ENV_LOWER not in ("dev", "test") and os.getenv("ENABLE_WALLET_WS_IN_PROD", "").lower() not in (
        "1",
        "true",
        "yes",
        "on",
    ):
        # This endpoint is intentionally dev/test-only by default.
        await websocket.accept()
        await websocket.close(code=1008)
        return
    await websocket.accept()
    last_key = None
    try:
        while True:
            try:
                # fetch latest txn
                client = _httpx_async_client()
                r = await client.get(
                    _payments_url(f"/txns"),
                    params={"wallet_id": wallet_id, "limit": 1},
                    headers=_payments_headers(),
                )
                arr = r.json() if r.headers.get('content-type','').startswith('application/json') else []
                if arr:
                    t = arr[0]
                    key = f"{t.get('id','')}|{t.get('amount_cents',0)}|{t.get('created_at','')}"
                    if key and key != last_key:
                        last_key = key
                        await websocket.send_json({
                            "kind": "wallet_txn",
                            "wallet_id": wallet_id,
                            "amount_cents": t.get('amount_cents', 0),
                            "reference": t.get('reference', ''),
                            "created_at": t.get('created_at', ''),
                        })
            except Exception:
                pass
            await asyncio.sleep(3)
    except WebSocketDisconnect:
        return


# Upstream base URLs (prefer custom domains but allow service URLs)
PAYMENTS_BASE = _env_or("PAYMENTS_BASE_URL", "")
ESCROW_WALLET_ID = _env_or("ESCROW_WALLET_ID", "")
DEFAULT_CURRENCY = _env_or("DEFAULT_CURRENCY", "SYP")
BUS_BASE = _env_or("BUS_BASE_URL", "")
CHAT_BASE = _env_or("CHAT_BASE_URL", "")
PAYMENTS_INTERNAL_SECRET = os.getenv("PAYMENTS_INTERNAL_SECRET") or os.getenv("INTERNAL_API_SECRET")
INTERNAL_API_SECRET = os.getenv("INTERNAL_API_SECRET", "")
BUS_INTERNAL_SECRET = os.getenv("BUS_INTERNAL_SECRET", "")
ORS_BASE = _env_or("ORS_BASE_URL", "")
ORS_API_KEY = os.getenv("ORS_API_KEY", "")
TOMTOM_API_KEY = os.getenv("TOMTOM_API_KEY", "")
TOMTOM_BASE = _env_or("TOMTOM_BASE_URL", "https://api.tomtom.com")
NOMINATIM_BASE = _env_or("NOMINATIM_BASE_URL", "")
NOMINATIM_USER_AGENT = _env_or("NOMINATIM_USER_AGENT", "shamell/1.0 (contact@example.com)")
OSRM_BASE = _env_or("OSRM_BASE_URL", "")
OVERPASS_BASE = _env_or("OVERPASS_BASE_URL", "https://overpass-api.de/api/interpreter")

# Push endpoint SSRF guardrails (best-effort).
PUSH_ALLOWED_HOSTS = {
    h.strip().lower()
    for h in (os.getenv("PUSH_ALLOWED_HOSTS") or "").split(",")
    if h.strip()
}
PUSH_ALLOW_HTTP = _env_or("PUSH_ALLOW_HTTP", "false").lower() == "true"
PUSH_ALLOW_PRIVATE_IPS = _env_or("PUSH_ALLOW_PRIVATE_IPS", "false").lower() == "true"
PUSH_VALIDATE_DNS = _env_or("PUSH_VALIDATE_DNS", "true").lower() == "true"
try:
    PUSH_MAX_ENDPOINT_LEN = int(_env_or("PUSH_MAX_ENDPOINT_LEN", "2048"))
except Exception:
    PUSH_MAX_ENDPOINT_LEN = 2048
PUSH_MAX_ENDPOINT_LEN = max(256, min(PUSH_MAX_ENDPOINT_LEN, 8192))


def _payments_headers(extra: dict[str, str] | None = None) -> dict[str, str]:
    """
    Attach the internal auth header for all BFF->Payments HTTP calls.

    In prod/staging the Payments API should be treated as an internal-only
    service; the BFF is the public surface.
    """
    h: dict[str, str] = {}
    if extra:
        h.update(extra)
    if PAYMENTS_INTERNAL_SECRET:
        # Always override any caller-provided value (do not forward from clients).
        h["X-Internal-Secret"] = PAYMENTS_INTERNAL_SECRET
    return h

# Force all domains to use internal integrations; ignore external BASE_URLs.
#
# Default is OFF. Internal mode should be explicitly enabled per-domain
# (e.g. *_INTERNAL_MODE=on) or by leaving *_BASE_URL unset in dev/test.
FORCE_INTERNAL_DOMAINS = _env_or("FORCE_INTERNAL_DOMAINS", "false").lower() in ("1", "true", "yes", "on")


def _force_internal(avail: bool) -> bool:
    return bool(FORCE_INTERNAL_DOMAINS and avail)
OVERPASS_USER_AGENT = _env_or("OVERPASS_USER_AGENT", NOMINATIM_USER_AGENT)
BFF_TOPUP_SELLERS = set(a.strip() for a in os.getenv("BFF_TOPUP_SELLERS", "").split(",") if a.strip())
BFF_TOPUP_ALLOW_ALL = (_env_or("BFF_TOPUP_ALLOW_ALL", "false").lower() == "true")
BFF_ADMINS = set(a.strip() for a in os.getenv("BFF_ADMINS", "").split(",") if a.strip())
SUPERADMIN_PHONE = os.getenv("SUPERADMIN_PHONE", "").strip()

# Public catalog allowlist for mini-apps/mini-programs exposed via the BFF.
# Bus-only deployments can keep the mini-ecosystem tightly scoped by default.
MINI_CATALOG_ALLOWLIST = {
    x.strip().lower()
    for x in (os.getenv("MINI_CATALOG_ALLOWLIST") or "bus").split(",")
    if x.strip()
}

# Upper bound for per-process in-memory rate/velocity stores (best-effort).
# Prevents unbounded growth when attackers spam many unique keys (IPs, devices, wallet IDs).
try:
    RATE_STORE_MAX_KEYS = int(_env_or("RATE_STORE_MAX_KEYS", "20000"))
except Exception:
    RATE_STORE_MAX_KEYS = 20000
RATE_STORE_MAX_KEYS = max(0, min(RATE_STORE_MAX_KEYS, 200000))

# Simple in-memory rate limiting for auth flows (per process).
AUTH_RATE_WINDOW_SECS = int(_env_or("AUTH_RATE_WINDOW_SECS", "60"))
AUTH_MAX_PER_PHONE = int(_env_or("AUTH_MAX_PER_PHONE", "5"))
AUTH_MAX_PER_IP = int(_env_or("AUTH_MAX_PER_IP", "40"))
_AUTH_RATE_PHONE: dict[str, list[int]] = {}
_AUTH_RATE_IP: dict[str, list[int]] = {}

# Payments edge rate-limits (BFF layer, best-effort in-memory).
PAY_API_RATE_WINDOW_SECS = int(_env_or("PAY_API_RATE_WINDOW_SECS", "60"))
PAY_API_REQ_WRITE_MAX_PER_WALLET = int(_env_or("PAY_API_REQ_WRITE_MAX_PER_WALLET", "40"))
PAY_API_REQ_WRITE_MAX_PER_IP = int(_env_or("PAY_API_REQ_WRITE_MAX_PER_IP", "200"))
PAY_API_REQ_READ_MAX_PER_WALLET = int(_env_or("PAY_API_REQ_READ_MAX_PER_WALLET", "120"))
PAY_API_REQ_READ_MAX_PER_IP = int(_env_or("PAY_API_REQ_READ_MAX_PER_IP", "500"))
PAY_API_FAV_WRITE_MAX_PER_WALLET = int(_env_or("PAY_API_FAV_WRITE_MAX_PER_WALLET", "30"))
PAY_API_FAV_WRITE_MAX_PER_IP = int(_env_or("PAY_API_FAV_WRITE_MAX_PER_IP", "120"))
PAY_API_FAV_READ_MAX_PER_WALLET = int(_env_or("PAY_API_FAV_READ_MAX_PER_WALLET", "120"))
PAY_API_FAV_READ_MAX_PER_IP = int(_env_or("PAY_API_FAV_READ_MAX_PER_IP", "500"))
PAY_API_RESOLVE_MAX_PER_WALLET = int(_env_or("PAY_API_RESOLVE_MAX_PER_WALLET", "20"))
PAY_API_RESOLVE_MAX_PER_IP = int(_env_or("PAY_API_RESOLVE_MAX_PER_IP", "120"))
_PAY_API_RATE_WALLET: dict[str, list[int]] = {}
_PAY_API_RATE_IP: dict[str, list[int]] = {}

# Chat edge rate-limits (BFF layer, best-effort in-memory).
CHAT_RATE_WINDOW_SECS = int(_env_or("CHAT_RATE_WINDOW_SECS", "60"))
CHAT_REGISTER_MAX_PER_IP = int(_env_or("CHAT_REGISTER_MAX_PER_IP", "25"))
CHAT_SEND_MAX_PER_DEVICE = int(_env_or("CHAT_SEND_MAX_PER_DEVICE", "120"))
CHAT_SEND_MAX_PER_IP = int(_env_or("CHAT_SEND_MAX_PER_IP", "300"))
_CHAT_RATE_DEVICE: dict[str, list[int]] = {}
_CHAT_RATE_IP: dict[str, list[int]] = {}

# Maps/Geocoding/Routing abuse guardrails (BFF layer, best-effort in-memory).
MAPS_RATE_WINDOW_SECS = int(_env_or("MAPS_RATE_WINDOW_SECS", "60"))
MAPS_GEOCODE_MAX_PER_IP_AUTH = int(_env_or("MAPS_GEOCODE_MAX_PER_IP_AUTH", "120"))
MAPS_GEOCODE_MAX_PER_IP_ANON = int(_env_or("MAPS_GEOCODE_MAX_PER_IP_ANON", "30"))
MAPS_GEOCODE_BATCH_MAX_PER_IP_AUTH = int(_env_or("MAPS_GEOCODE_BATCH_MAX_PER_IP_AUTH", "20"))
MAPS_GEOCODE_BATCH_MAX_PER_IP_ANON = int(_env_or("MAPS_GEOCODE_BATCH_MAX_PER_IP_ANON", "5"))
MAPS_POI_MAX_PER_IP_AUTH = int(_env_or("MAPS_POI_MAX_PER_IP_AUTH", "120"))
MAPS_POI_MAX_PER_IP_ANON = int(_env_or("MAPS_POI_MAX_PER_IP_ANON", "30"))
MAPS_REVERSE_MAX_PER_IP_AUTH = int(_env_or("MAPS_REVERSE_MAX_PER_IP_AUTH", "180"))
MAPS_REVERSE_MAX_PER_IP_ANON = int(_env_or("MAPS_REVERSE_MAX_PER_IP_ANON", "60"))
MAPS_ROUTE_MAX_PER_IP_AUTH = int(_env_or("MAPS_ROUTE_MAX_PER_IP_AUTH", "60"))
MAPS_ROUTE_MAX_PER_IP_ANON = int(_env_or("MAPS_ROUTE_MAX_PER_IP_ANON", "20"))
try:
    MAPS_MAX_QUERY_LEN = int(_env_or("MAPS_MAX_QUERY_LEN", "256"))
except Exception:
    MAPS_MAX_QUERY_LEN = 256
MAPS_MAX_QUERY_LEN = max(32, min(MAPS_MAX_QUERY_LEN, 2048))
try:
    MAPS_MAX_BATCH_QUERIES = int(_env_or("MAPS_MAX_BATCH_QUERIES", "50"))
except Exception:
    MAPS_MAX_BATCH_QUERIES = 50
MAPS_MAX_BATCH_QUERIES = max(1, min(MAPS_MAX_BATCH_QUERIES, 500))
try:
    MAPS_CACHE_MAX_ITEMS = int(_env_or("MAPS_CACHE_MAX_ITEMS", "2000"))
except Exception:
    MAPS_CACHE_MAX_ITEMS = 2000
MAPS_CACHE_MAX_ITEMS = max(50, min(MAPS_CACHE_MAX_ITEMS, 20000))
try:
    MAPS_CACHE_TTL_SECS = int(_env_or("MAPS_CACHE_TTL_SECS", "600"))
except Exception:
    MAPS_CACHE_TTL_SECS = 600
MAPS_CACHE_TTL_SECS = max(30, min(MAPS_CACHE_TTL_SECS, 3600))
_MAPS_RATE_IP: dict[str, list[int]] = {}

# Fleet helper endpoints are CPU-bound; keep inputs bounded.
try:
    FLEET_MAX_STOPS = int(_env_or("FLEET_MAX_STOPS", "200"))
except Exception:
    FLEET_MAX_STOPS = 200
FLEET_MAX_STOPS = max(10, min(FLEET_MAX_STOPS, 2000))
try:
    FLEET_MAX_DEPOTS = int(_env_or("FLEET_MAX_DEPOTS", "50"))
except Exception:
    FLEET_MAX_DEPOTS = 50
FLEET_MAX_DEPOTS = max(1, min(FLEET_MAX_DEPOTS, 500))

# Chat WebSocket guardrails (BFF layer, best-effort per-process).
CHAT_WS_CONNECT_WINDOW_SECS = int(_env_or("CHAT_WS_CONNECT_WINDOW_SECS", "60"))
CHAT_WS_CONNECT_MAX_PER_IP = int(_env_or("CHAT_WS_CONNECT_MAX_PER_IP", "60"))
CHAT_WS_MAX_ACTIVE_PER_IP = int(_env_or("CHAT_WS_MAX_ACTIVE_PER_IP", "20"))
CHAT_WS_MAX_ACTIVE_PER_DEVICE = int(_env_or("CHAT_WS_MAX_ACTIVE_PER_DEVICE", "3"))
_CHAT_WS_CONNECT_RATE_IP: dict[str, list[int]] = {}
_CHAT_WS_ACTIVE_IP: dict[str, int] = {}
_CHAT_WS_ACTIVE_DEVICE: dict[str, int] = {}
_CHAT_WS_LOCK = asyncio.Lock()

# Global security headers toggle
SECURITY_HEADERS_ENABLED = _env_or("SECURITY_HEADERS_ENABLED", "true").lower() == "true"
HSTS_ENABLED = _env_or("HSTS_ENABLED", "true" if _ENV_LOWER in ("prod", "staging") else "false").lower() == "true"

# Proxy header trust (client IP resolution for rate limiting + audits).
# Best practice is to only trust proxy-provided headers when the immediate peer
# is a trusted proxy (explicit CIDR allowlist) or a private hop (cluster ingress).
TRUST_PROXY_HEADERS_MODE = _env_or("TRUST_PROXY_HEADERS", "auto").strip().lower()  # off|on|auto
TRUST_PRIVATE_PROXY_HOPS = _env_or("TRUST_PRIVATE_PROXY_HOPS", "true").lower() == "true"
TRUSTED_PROXY_CIDRS = _parse_ip_networks(_env_or("TRUSTED_PROXY_CIDRS", ""))

# CSRF guard (defense-in-depth)
# Only applies to cookie-authenticated, non-idempotent requests.
CSRF_GUARD_ENABLED = _env_or("CSRF_GUARD_ENABLED", "true" if _ENV_LOWER in ("prod", "staging") else "false").lower() == "true"
_CSRF_ALLOWED_ORIGINS_RAW = [o.strip() for o in (os.getenv("ALLOWED_ORIGINS") or "").split(",") if o.strip()]
if not _CSRF_ALLOWED_ORIGINS_RAW:
    _CSRF_ALLOWED_ORIGINS_RAW = ["http://localhost:5173", "http://127.0.0.1:5173"]
_CSRF_ORIGIN_WILDCARD = "*" in _CSRF_ALLOWED_ORIGINS_RAW
_CSRF_ALLOWED_ORIGINS = {o for o in _CSRF_ALLOWED_ORIGINS_RAW if o and o != "*"}

_AUTH_EXPOSE_DEFAULT = "true" if _ENV_LOWER in ("dev", "test") else "false"
# Whether auth codes should be returned in responses (for dev/test only).
AUTH_EXPOSE_CODES = _env_or("AUTH_EXPOSE_CODES", _AUTH_EXPOSE_DEFAULT).lower() == "true"

# Global maintenance mode toggle (read-only / outage banner).
MAINTENANCE_MODE_ENABLED = _env_or("MAINTENANCE_MODE", "false").lower() == "true"
METRICS_INGEST_SECRET = _env_or("METRICS_INGEST_SECRET", "").strip()
try:
    METRICS_INGEST_MAX_BYTES = int(_env_or("METRICS_INGEST_MAX_BYTES", "32768"))
except Exception:
    METRICS_INGEST_MAX_BYTES = 32768
# Keep bounds sane even if env is misconfigured.
METRICS_INGEST_MAX_BYTES = max(1024, min(METRICS_INGEST_MAX_BYTES, 1024 * 1024))

try:
    QR_MAX_DATA_LEN = int(_env_or("QR_MAX_DATA_LEN", "1024"))
except Exception:
    QR_MAX_DATA_LEN = 1024
QR_MAX_DATA_LEN = max(64, min(QR_MAX_DATA_LEN, 16384))

try:
    TOPUP_PRINT_MAX_ITEMS = int(_env_or("TOPUP_PRINT_MAX_ITEMS", "1200"))
except Exception:
    TOPUP_PRINT_MAX_ITEMS = 1200
TOPUP_PRINT_MAX_ITEMS = max(1, min(TOPUP_PRINT_MAX_ITEMS, 10000))
SECURITY_ALERT_WEBHOOK_URL = _env_or("SECURITY_ALERT_WEBHOOK_URL", "").strip()
SECURITY_ALERT_WINDOW_SECS = int(_env_or("SECURITY_ALERT_WINDOW_SECS", "300"))
SECURITY_ALERT_COOLDOWN_SECS = int(_env_or("SECURITY_ALERT_COOLDOWN_SECS", "600"))
SECURITY_ALERT_THRESHOLDS_RAW = _env_or(
    "SECURITY_ALERT_THRESHOLDS",
    (
        "payments_transfer_wallet_mismatch:5,"
        "alias_request_wallet_mismatch:5,"
        "alias_request_user_override_blocked:5,"
        "favorites_owner_wallet_mismatch:5,"
        "payments_request_from_wallet_mismatch:5,"
        "payments_edge_rate_limit_wallet:30,"
        "payments_edge_rate_limit_ip:50"
    ),
).strip()

# ---- Simple session auth (OTP via code; in-memory storage for demo) ----
AUTH_SESSION_TTL_SECS = int(_env_or("AUTH_SESSION_TTL_SECS", "86400"))
LOGIN_CODE_TTL_SECS = int(_env_or("LOGIN_CODE_TTL_SECS", "300"))
DEVICE_LOGIN_TTL_SECS = int(_env_or("DEVICE_LOGIN_TTL_SECS", "300"))
DEVICE_LOGIN_START_RATE_WINDOW_SECS = int(_env_or("DEVICE_LOGIN_START_RATE_WINDOW_SECS", "60"))
DEVICE_LOGIN_START_MAX_PER_IP = int(_env_or("DEVICE_LOGIN_START_MAX_PER_IP", "30"))
LIVEKIT_PUBLIC_URL = _env_or("LIVEKIT_PUBLIC_URL", _env_or("LIVEKIT_URL", "")).strip()
LIVEKIT_API_KEY = _env_or("LIVEKIT_API_KEY", "").strip()
LIVEKIT_API_SECRET = _env_or("LIVEKIT_API_SECRET", "").strip()
LIVEKIT_TOKEN_ENDPOINT_ENABLED = _env_or(
    "LIVEKIT_TOKEN_ENDPOINT_ENABLED",
    "true" if _ENV_LOWER in ("dev", "test") else "false",
).strip().lower() in ("1", "true", "yes", "on")
LIVEKIT_TOKEN_TTL_SECS_DEFAULT = int(_env_or("LIVEKIT_TOKEN_TTL_SECS", "300"))
LIVEKIT_TOKEN_MAX_TTL_SECS = int(_env_or("LIVEKIT_TOKEN_MAX_TTL_SECS", "3600"))
LIVEKIT_TOKEN_RATE_WINDOW_SECS = int(_env_or("LIVEKIT_TOKEN_RATE_WINDOW_SECS", "60"))
LIVEKIT_TOKEN_MAX_PER_PHONE = int(_env_or("LIVEKIT_TOKEN_MAX_PER_PHONE", "30"))
LIVEKIT_TOKEN_MAX_PER_IP = int(_env_or("LIVEKIT_TOKEN_MAX_PER_IP", "80"))
CALLING_ENABLED = _env_or(
    "CALLING_ENABLED",
    "true" if _ENV_LOWER in ("dev", "test") else "false",
).strip().lower() in ("1", "true", "yes", "on")
CALL_RATE_WINDOW_SECS = int(_env_or("CALL_RATE_WINDOW_SECS", "60"))
CALL_START_MAX_PER_PHONE = int(_env_or("CALL_START_MAX_PER_PHONE", "8"))
CALL_START_MAX_PER_IP = int(_env_or("CALL_START_MAX_PER_IP", "40"))
CALL_START_MAX_PER_CALLEE = int(_env_or("CALL_START_MAX_PER_CALLEE", "12"))
CALL_RING_TTL_SECS = int(_env_or("CALL_RING_TTL_SECS", "120"))
CALL_MAX_TTL_SECS = int(_env_or("CALL_MAX_TTL_SECS", "7200"))
CALL_RATE_WINDOW_SECS = max(1, min(CALL_RATE_WINDOW_SECS, 3600))
CALL_START_MAX_PER_PHONE = max(0, min(CALL_START_MAX_PER_PHONE, 1000))
CALL_START_MAX_PER_IP = max(0, min(CALL_START_MAX_PER_IP, 5000))
CALL_START_MAX_PER_CALLEE = max(0, min(CALL_START_MAX_PER_CALLEE, 2000))
CALL_RING_TTL_SECS = max(10, min(CALL_RING_TTL_SECS, 600))
CALL_MAX_TTL_SECS = max(CALL_RING_TTL_SECS, min(CALL_MAX_TTL_SECS, 12 * 3600))
_LOGIN_CODES: dict[str, tuple[str, int]] = {}  # phone -> (code, expires_at)
_SESSIONS: dict[str, tuple[str, int]] = {}     # sid -> (phone, expires_at)
# Legacy in-memory device-login store (DB-backed flow is used by the endpoints).
_DEVICE_LOGIN_CHALLENGES: dict[str, dict[str, Any]] = {}  # token -> metadata
_BLOCKED_PHONES: set[str] = set()
_PUSH_ENDPOINTS: dict[str, list[dict]] = {}
_AUTH_CLEANUP_INTERVAL_SECS = 60
_AUTH_LAST_CLEANUP_TS = 0
_DEVICE_LOGIN_START_RATE_IP: dict[str, list[int]] = {}
_LIVEKIT_TOKEN_RATE_PHONE: dict[str, list[int]] = {}
_LIVEKIT_TOKEN_RATE_IP: dict[str, list[int]] = {}
_CALL_START_RATE_PHONE: dict[str, list[int]] = {}
_CALL_START_RATE_IP: dict[str, list[int]] = {}
_CALL_START_RATE_CALLEE: dict[str, list[int]] = {}


def _parse_security_alert_thresholds(raw: str) -> dict[str, int]:
    out: dict[str, int] = {}
    for chunk in (raw or "").split(","):
        item = chunk.strip()
        if not item or ":" not in item:
            continue
        name, value = item.split(":", 1)
        action = name.strip()
        if not action:
            continue
        try:
            threshold = int(value.strip())
        except Exception:
            continue
        if threshold <= 0:
            continue
        out[action] = threshold
    return out


SECURITY_ALERT_THRESHOLDS = _parse_security_alert_thresholds(SECURITY_ALERT_THRESHOLDS_RAW)
_SECURITY_ALERT_EVENTS: dict[str, list[int]] = {}
_SECURITY_ALERT_LAST_SENT: dict[str, int] = {}

def _now() -> int:
    return int(time.time())

def _sha256_hex(s: str) -> str:
    """
    Stable SHA-256 hex digest helper.

    Used to store only hashes of bearer tokens (sessions, device-login tokens)
    at rest in the DB.
    """
    return hashlib.sha256((s or "").encode("utf-8")).hexdigest()

def _b64url(data: bytes) -> str:
    try:
        return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")
    except Exception:
        return ""


def _jwt_hs256(secret: str, payload: dict[str, Any]) -> str:
    """
    Minimal HS256 JWT encoder (no external deps).

    LiveKit expects HS256-signed access tokens using the API secret.
    """
    header = {"alg": "HS256", "typ": "JWT"}
    try:
        h = _b64url(_json.dumps(header, separators=(",", ":"), sort_keys=True).encode("utf-8"))
        p = _b64url(_json.dumps(payload, separators=(",", ":"), sort_keys=True).encode("utf-8"))
        msg = f"{h}.{p}".encode("utf-8")
        sig = _hmac.new((secret or "").encode("utf-8"), msg, hashlib.sha256).digest()
        s = _b64url(sig)
        if not h or not p or not s:
            return ""
        return f"{h}.{p}.{s}"
    except Exception:
        return ""


def _livekit_identity(*, phone: str, device_id: str | None, sid: str | None) -> str:
    """
    Return a stable, non-PII participant identity for LiveKit.

    Avoid leaking phone numbers to other participants by hashing.
    """
    base = _sha256_hex(f"phone:{(phone or '').strip()}")[:16]
    dev = (device_id or "").strip()
    if dev:
        return f"u_{base}_d_{_sha256_hex(f'dev:{dev}')[:8]}"
    if sid:
        return f"u_{base}_s_{_sha256_hex(f'sid:{sid}')[:8]}"
    return f"u_{base}"


def _dt_to_epoch_secs(dt: datetime) -> int:
    try:
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return int(dt.timestamp())
    except Exception:
        return 0


def _cleanup_auth_state(now: int | None = None) -> None:
    """
    Best-effort periodic cleanup of expired OTP codes and sessions
    to keep memory usage bounded across long-running processes.
    """
    global _AUTH_LAST_CLEANUP_TS
    ts = now or _now()
    if ts - _AUTH_LAST_CLEANUP_TS < _AUTH_CLEANUP_INTERVAL_SECS:
        return
    _AUTH_LAST_CLEANUP_TS = ts
    try:
        expired = [p for p, (_, exp) in list(_LOGIN_CODES.items()) if exp < ts]
        for phone in expired:
            _LOGIN_CODES.pop(phone, None)
    except Exception:
        pass
    try:
        expired_sids = [sid for sid, (_, exp) in list(_SESSIONS.items()) if exp < ts]
        for sid in expired_sids:
            _SESSIONS.pop(sid, None)
    except Exception:
        pass
    try:
        expired_tokens = [
            token
            for token, rec in list(_DEVICE_LOGIN_CHALLENGES.items())
            if int(rec.get("created_at") or 0) + DEVICE_LOGIN_TTL_SECS < ts
        ]
        for token in expired_tokens:
            _DEVICE_LOGIN_CHALLENGES.pop(token, None)
    except Exception:
        pass
    # DB-backed cleanup (best-effort): keep session/challenge tables bounded.
    try:
        now_dt = datetime.fromtimestamp(ts, timezone.utc)
        with _officials_session() as s:  # type: ignore[name-defined]
            try:
                s.execute(_sa_delete(AuthSessionDB).where(AuthSessionDB.expires_at < now_dt))  # type: ignore[name-defined]
            except Exception:
                pass
            try:
                s.execute(
                    _sa_delete(DeviceLoginChallengeDB).where(DeviceLoginChallengeDB.expires_at < now_dt)  # type: ignore[name-defined]
                )
            except Exception:
                pass
            try:
                s.commit()
            except Exception:
                pass
    except Exception:
        # Cleanup must never break normal flows.
        pass


def _issue_code(phone: str) -> str:
    _cleanup_auth_state()
    code = f"{_secrets.randbelow(1_000_000):06d}"
    _LOGIN_CODES[phone] = (code, _now()+LOGIN_CODE_TTL_SECS)
    return code


def _check_code(phone: str, code: str) -> bool:
    _cleanup_auth_state()
    rec = _LOGIN_CODES.get(phone)
    ok = bool(rec and rec[0] == code and rec[1] >= _now())
    if ok:
        # Drop code after successful use (no reuse)
        try:
            del _LOGIN_CODES[phone]
        except Exception:
            pass
    return ok


def _create_session(phone: str, *, device_id: str | None = None) -> str:
    _cleanup_auth_state()
    # Session IDs are bearer tokens; keep them high-entropy and do not log them.
    sid = _secrets.token_hex(16)  # 32 hex chars
    exp_ts = _now() + AUTH_SESSION_TTL_SECS
    _SESSIONS[sid] = (phone, exp_ts)
    # Persist session to DB so restarts and multi-instance deployments keep users signed in.
    try:
        exp_dt = datetime.fromtimestamp(exp_ts, timezone.utc)
        dev = (device_id or "").strip() or None
        if dev and len(dev) > 128:
            dev = dev[:128]
        with _officials_session() as s:  # type: ignore[name-defined]
            s.add(
                AuthSessionDB(  # type: ignore[name-defined]
                    sid_hash=_sha256_hex(sid),
                    phone=phone,
                    device_id=dev,
                    expires_at=exp_dt,
                )
            )
            s.commit()
    except Exception:
        # If persistence fails, fall back to in-memory sessions so login does not hard-break.
        pass
    return sid


def _normalize_session_token(raw: str | None) -> str | None:
    token = (raw or "").strip()
    if not token:
        return None
    if "=" in token:
        for part in token.split(";"):
            part = part.strip()
            if part.startswith("sa_session="):
                token = part.split("=", 1)[1]
                break
    token = token.strip()
    if not re.fullmatch(r"[a-f0-9]{32}", token):
        return None
    return token


def _normalize_device_id(raw: str | None) -> str | None:
    s = (raw or "").strip()
    if not s:
        return None
    # Keep identifiers bounded and log-safe.
    if len(s) > 128:
        s = s[:128]
    try:
        for ch in s:
            o = ord(ch)
            if o < 32 or o == 127:
                return None
    except Exception:
        return None
    return s


def _normalize_phone_e164(raw: str | None) -> str | None:
    """
    Best-effort E.164 normalizer for call flows.

    Auth flows currently accept arbitrary phone strings for flexibility, but
    calling is high-risk for abuse and should only accept canonical E.164.
    """
    s = (raw or "").strip()
    if not s:
        return None
    # Keep bounded and log-safe.
    if len(s) > 64:
        s = s[:64]
    # Normalize common input variants (spaces, dashes, 00 prefix).
    try:
        s = re.sub(r"[\\s\\-().]", "", s)
    except Exception:
        pass
    if s.startswith("00"):
        s = "+" + s[2:]
    if not re.fullmatch(r"\+[1-9][0-9]{7,14}", s):
        return None
    return s


def _normalize_call_id(raw: str | None) -> str | None:
    s = (raw or "").strip().lower()
    if not s:
        return None
    if not re.fullmatch(r"[a-f0-9]{32}", s):
        return None
    return s


def _extract_session_id_from_request(request: Request) -> str | None:
    sid = None
    try:
        raw = request.headers.get("sa_cookie") or request.headers.get("Sa-Cookie")
        if raw:
            sid = _normalize_session_token(raw)
    except Exception:
        sid = None
    if not sid:
        try:
            sid = _normalize_session_token(request.cookies.get("sa_session"))
        except Exception:
            sid = None
    return sid


def _normalize_device_login_token(raw: str | None) -> str | None:
    token = (raw or "").strip()
    if not token:
        return None
    if not re.fullmatch(r"[a-f0-9]{32}", token):
        return None
    return token


def _session_phone_from_sid(sid: str) -> str | None:
    """
    Resolve phone number for a session ID.

    Uses a small in-memory cache, but treats the DB as source of truth so
    sessions survive restarts and multi-instance deployments.
    """
    _cleanup_auth_state()
    now_ts = _now()
    sid_hash = _sha256_hex(sid)

    # DB is the source of truth so logout/revocation is immediate.
    try:
        with _officials_session() as s:  # type: ignore[name-defined]
            row = (
                s.execute(
                    _sa_select(AuthSessionDB).where(AuthSessionDB.sid_hash == sid_hash).limit(1)  # type: ignore[name-defined]
                )
                .scalars()
                .first()
            )
            if not row or getattr(row, "revoked_at", None):
                _SESSIONS.pop(sid, None)
                return None
            exp_dt = getattr(row, "expires_at", None)
            exp_ts = _dt_to_epoch_secs(exp_dt) if isinstance(exp_dt, datetime) else 0
            if exp_ts and exp_ts < now_ts:
                _SESSIONS.pop(sid, None)
                # Best-effort cleanup of expired session row.
                try:
                    s.execute(
                        _sa_delete(AuthSessionDB).where(AuthSessionDB.sid_hash == sid_hash)  # type: ignore[name-defined]
                    )
                    s.commit()
                except Exception:
                    pass
                return None
            phone = str(getattr(row, "phone", "") or "").strip()
            if not phone:
                _SESSIONS.pop(sid, None)
                return None
            if not exp_ts:
                exp_ts = now_ts + AUTH_SESSION_TTL_SECS
            _SESSIONS[sid] = (phone, exp_ts)
            return phone
    except Exception:
        # If DB is unavailable, fall back to the in-memory cache.
        rec = _SESSIONS.get(sid)
        if not rec:
            return None
        phone, exp = rec
        if exp < now_ts:
            _SESSIONS.pop(sid, None)
            return None
        return phone


def _normalize_ip(raw: str | None) -> str | None:
    candidate = (raw or "").strip()
    if not candidate:
        return None
    try:
        return str(ipaddress.ip_address(candidate))
    except Exception:
        return None


def _normalize_origin(raw: str | None) -> str | None:
    """
    Normalize an Origin header to a stable `scheme://host[:port]` form.
    Returns None for invalid/non-http(s) origins.
    """
    s = (raw or "").strip()
    if not s or s.lower() == "null":
        return None
    try:
        u = _urlparse.urlparse(s)
        scheme = (u.scheme or "").lower()
        if scheme not in ("http", "https"):
            return None
        host = (u.hostname or "").strip().lower()
        if not host:
            return None
        port = u.port
        if port:
            return f"{scheme}://{host}:{int(port)}"
        return f"{scheme}://{host}"
    except Exception:
        return None


def _csrf_guard(request: Request) -> Response | None:
    """
    Defense-in-depth CSRF guard.

    We only enforce this for cookie-authenticated, non-idempotent requests.
    Header-based sessions (`sa_cookie`) are not vulnerable to classic browser
    CSRF because attackers cannot set custom headers without passing CORS.
    """
    try:
        if not CSRF_GUARD_ENABLED:
            return None
    except Exception:
        return None

    try:
        method = (request.method or "").upper()
    except Exception:
        return None
    if method not in ("POST", "PUT", "PATCH", "DELETE"):
        return None

    # Only protect cookie-auth flows. If the request is using explicit header auth,
    # do not apply CSRF checks.
    try:
        if request.headers.get("sa_cookie") or request.headers.get("Sa-Cookie"):
            return None
    except Exception:
        return None
    try:
        if not (request.cookies.get("sa_session") or "").strip():
            return None
    except Exception:
        return None

    # Primary signal: Origin header (present on modern browsers for non-idempotent requests).
    origin_raw = None
    try:
        origin_raw = request.headers.get("Origin") or request.headers.get("origin")
    except Exception:
        origin_raw = None
    if origin_raw:
        origin = _normalize_origin(origin_raw)
        if not origin:
            return JSONResponse(status_code=403, content={"detail": "forbidden"})
        try:
            if _CSRF_ORIGIN_WILDCARD:
                return None
        except Exception:
            # If misconfigured, fail open (defense-in-depth only).
            return None
        try:
            if origin in _CSRF_ALLOWED_ORIGINS:
                return None
        except Exception:
            return None
        # Allow same-host even if scheme/proxy rewriting differs.
        try:
            req_host = (request.headers.get("host") or "").split(":", 1)[0].strip().lower()
            origin_host = (_urlparse.urlparse(origin).hostname or "").strip().lower()
            if req_host and origin_host and req_host == origin_host:
                return None
        except Exception:
            pass
        return JSONResponse(status_code=403, content={"detail": "forbidden"})

    # Fallback signal: Fetch metadata. If the browser says "cross-site" and we have
    # an auth cookie, block.
    try:
        sfs = (request.headers.get("Sec-Fetch-Site") or request.headers.get("sec-fetch-site") or "").strip().lower()
        if sfs == "cross-site":
            return JSONResponse(status_code=403, content={"detail": "forbidden"})
    except Exception:
        return None
    return None

def _should_trust_proxy_headers(peer: ipaddress._BaseAddress | None) -> bool:  # type: ignore[name-defined]
    mode = (TRUST_PROXY_HEADERS_MODE or "auto").strip().lower()
    if mode == "off":
        return False
    if mode == "on":
        return True
    # auto: trust only when the immediate peer is trusted.
    if peer is None:
        return False
    try:
        if TRUSTED_PROXY_CIDRS:
            for net in TRUSTED_PROXY_CIDRS:
                try:
                    if peer in net:
                        return True
                except Exception:
                    continue
        if TRUST_PRIVATE_PROXY_HOPS and (getattr(peer, "is_private", False) or getattr(peer, "is_loopback", False)):
            return True
    except Exception:
        return False
    return False


def _is_public_ip(ip_str: str) -> bool:
    try:
        ip = ipaddress.ip_address(ip_str)
        return not (
            ip.is_private
            or ip.is_loopback
            or ip.is_link_local
            or ip.is_multicast
            or ip.is_reserved
            or ip.is_unspecified
        )
    except Exception:
        return False


def _proxy_client_ip_from_headers(headers: Any) -> str | None:
    """
    Extract best-effort client IP from common proxy headers.
    Caller must ensure these headers are trusted.
    """
    try:
        # CDN-specific headers first (more reliable than XFF chains).
        for k in ("cf-connecting-ip", "true-client-ip", "x-real-ip"):
            v = None
            try:
                v = headers.get(k) or headers.get(k.upper()) or headers.get(k.title())
            except Exception:
                v = None
            ip = _normalize_ip(v)
            if ip:
                return ip
    except Exception:
        pass
    try:
        fwd = None
        try:
            fwd = headers.get("x-forwarded-for") or headers.get("X-Forwarded-For")
        except Exception:
            fwd = None
        if fwd:
            hops = [p.strip() for p in str(fwd).split(",") if p.strip()]
            # Prefer the first public IP from the left (original client).
            first_valid: str | None = None
            for hop in hops:
                ip = _normalize_ip(hop)
                if not ip:
                    continue
                if first_valid is None:
                    first_valid = ip
                if _is_public_ip(ip):
                    return ip
            return first_valid
    except Exception:
        pass
    return None


def _auth_client_ip(request: Request) -> str:
    """
    Best-effort resolution of the client IP for rate limiting.
    Prefer trusted proxy headers and avoid trusting attacker-controlled
    left-most X-Forwarded-For entries.
    """
    peer_ip: str | None = None
    peer_obj: ipaddress._BaseAddress | None = None  # type: ignore[name-defined]
    try:
        if request.client and request.client.host:
            peer_ip = str(request.client.host)
            peer_ip_norm = _normalize_ip(peer_ip)
            if peer_ip_norm:
                peer_obj = ipaddress.ip_address(peer_ip_norm)
                peer_ip = peer_ip_norm
    except Exception:
        pass

    # Only trust proxy headers when the immediate peer is trusted.
    if _should_trust_proxy_headers(peer_obj):
        ip = _proxy_client_ip_from_headers(request.headers)
        if ip:
            return ip

    # Fallback: direct peer (may be reverse proxy IP).
    if peer_ip:
        return peer_ip
    return "unknown"


def _ws_client_ip(ws: WebSocket) -> str:
    """
    Best-effort resolution of the client IP for WebSockets.
    Mirrors _auth_client_ip() but reads from WebSocket headers.
    """
    peer_ip: str | None = None
    peer_obj: ipaddress._BaseAddress | None = None  # type: ignore[name-defined]
    try:
        if ws.client and ws.client.host:
            peer_ip = str(ws.client.host)
            peer_ip_norm = _normalize_ip(peer_ip)
            if peer_ip_norm:
                peer_obj = ipaddress.ip_address(peer_ip_norm)
                peer_ip = peer_ip_norm
    except Exception:
        pass
    if _should_trust_proxy_headers(peer_obj):
        ip = _proxy_client_ip_from_headers(ws.headers)
        if ip:
            return ip
    if peer_ip:
        return peer_ip
    return "unknown"


def _audit_from_ws(ws: WebSocket, action: str, **extra: Any) -> None:
    try:
        ip = _ws_client_ip(ws)
    except Exception:
        ip = "unknown"
    _audit(action, ip=ip, **extra)


async def _chat_ws_guard_enter(ws: WebSocket, *, device_id: str) -> tuple[str, str] | None:
    """
    Enforce basic abuse guardrails for chat WebSockets:
    - require device_id (not login, but prevents useless open connections)
    - rate-limit connection attempts per IP
    - cap concurrent connections per IP and per device_id
    Returns (ip, device_id) when admitted, else None.
    """
    dev = (device_id or "").strip()
    if not dev:
        try:
            await ws.close(code=4400)
        except Exception:
            pass
        return None

    ip = _ws_client_ip(ws)
    if CHAT_WS_CONNECT_MAX_PER_IP > 0 and ip and ip != "unknown":
        hits_ip = _rate_limit_bucket(
            _CHAT_WS_CONNECT_RATE_IP,
            f"chat_ws_connect:{ip}",
            window_secs=CHAT_WS_CONNECT_WINDOW_SECS,
            max_hits=CHAT_WS_CONNECT_MAX_PER_IP,
        )
        if hits_ip > CHAT_WS_CONNECT_MAX_PER_IP:
            _audit_from_ws(ws, "chat_ws_connect_rate_limit_ip", device_id=dev, max=CHAT_WS_CONNECT_MAX_PER_IP, hits=hits_ip)
            try:
                await ws.close(code=1013)
            except Exception:
                pass
            return None

    async with _CHAT_WS_LOCK:
        if CHAT_WS_MAX_ACTIVE_PER_DEVICE > 0:
            cur_dev = int(_CHAT_WS_ACTIVE_DEVICE.get(dev, 0) or 0)
            if cur_dev + 1 > CHAT_WS_MAX_ACTIVE_PER_DEVICE:
                _audit_from_ws(ws, "chat_ws_active_limit_device", device_id=dev, max=CHAT_WS_MAX_ACTIVE_PER_DEVICE, hits=cur_dev + 1)
                try:
                    await ws.close(code=1013)
                except Exception:
                    pass
                return None
        if CHAT_WS_MAX_ACTIVE_PER_IP > 0 and ip and ip != "unknown":
            cur_ip = int(_CHAT_WS_ACTIVE_IP.get(ip, 0) or 0)
            if cur_ip + 1 > CHAT_WS_MAX_ACTIVE_PER_IP:
                _audit_from_ws(ws, "chat_ws_active_limit_ip", device_id=dev, max=CHAT_WS_MAX_ACTIVE_PER_IP, hits=cur_ip + 1)
                try:
                    await ws.close(code=1013)
                except Exception:
                    pass
                return None

        # Admit: increment counters.
        if CHAT_WS_MAX_ACTIVE_PER_DEVICE > 0:
            _CHAT_WS_ACTIVE_DEVICE[dev] = int(_CHAT_WS_ACTIVE_DEVICE.get(dev, 0) or 0) + 1
        if CHAT_WS_MAX_ACTIVE_PER_IP > 0 and ip and ip != "unknown":
            _CHAT_WS_ACTIVE_IP[ip] = int(_CHAT_WS_ACTIVE_IP.get(ip, 0) or 0) + 1

    return (ip, dev)


async def _chat_ws_guard_exit(ip: str, device_id: str) -> None:
    dev = (device_id or "").strip()
    async with _CHAT_WS_LOCK:
        if dev and CHAT_WS_MAX_ACTIVE_PER_DEVICE > 0:
            cur = int(_CHAT_WS_ACTIVE_DEVICE.get(dev, 0) or 0) - 1
            if cur <= 0:
                _CHAT_WS_ACTIVE_DEVICE.pop(dev, None)
            else:
                _CHAT_WS_ACTIVE_DEVICE[dev] = cur
        if ip and ip != "unknown" and CHAT_WS_MAX_ACTIVE_PER_IP > 0:
            cur = int(_CHAT_WS_ACTIVE_IP.get(ip, 0) or 0) - 1
            if cur <= 0:
                _CHAT_WS_ACTIVE_IP.pop(ip, None)
            else:
                _CHAT_WS_ACTIVE_IP[ip] = cur


def _check_payment_guardrails(from_wallet_id: str | None, amount_cents: int | None, device_id: str | None) -> None:
    """
    Best-effort anti-fraud guardrails for payments:
    - optional max amount per transaction
    - simple velocity limits per wallet and per device over a short window
    """
    try:
        now = time.time()
        amt = int(amount_cents or 0)
        fw = (from_wallet_id or "").strip()

        # Guardrail 1: maximum amount per transaction (when configured)
        if PAY_MAX_PER_TXN_CENTS > 0 and amt > PAY_MAX_PER_TXN_CENTS:
            _audit("pay_amount_guardrail", from_wallet_id=fw or None, amount_cents=amt, device_id=device_id)
            raise HTTPException(status_code=403, detail="payment amount exceeds guardrail")

        window = max(1, PAY_VELOCITY_WINDOW_SECS)

        # Guardrail 2: velocity per wallet
        if fw:
            events = _PAY_VELOCITY_WALLET.get(fw) or []
            events = [ts for ts in events if ts >= now - window]
            if len(events) >= max(1, PAY_VELOCITY_MAX_PER_WALLET):
                _PAY_VELOCITY_WALLET[fw] = events
                _audit("pay_velocity_guardrail_wallet", from_wallet_id=fw, amount_cents=amt, device_id=device_id)
                raise HTTPException(status_code=429, detail="payment velocity guardrail (wallet)")
            events.append(now)
            _PAY_VELOCITY_WALLET[fw] = events

        # Guardrail 3: Velocity pro Device
        dev = (device_id or "").strip()
        if dev:
            events_d = _PAY_VELOCITY_DEVICE.get(dev) or []
            events_d = [ts for ts in events_d if ts >= now - window]
            if len(events_d) >= max(1, PAY_VELOCITY_MAX_PER_DEVICE):
                _PAY_VELOCITY_DEVICE[dev] = events_d
                _audit("pay_velocity_guardrail_device", from_wallet_id=fw or None, amount_cents=amt, device_id=dev)
                raise HTTPException(status_code=429, detail="payment velocity guardrail (device)")
            events_d.append(now)
            _PAY_VELOCITY_DEVICE[dev] = events_d

        # Bound in-memory state even under key-spam attacks (best-effort).
        _prune_rate_store(_PAY_VELOCITY_WALLET, max_keys=RATE_STORE_MAX_KEYS, window_secs=window)
        _prune_rate_store(_PAY_VELOCITY_DEVICE, max_keys=RATE_STORE_MAX_KEYS, window_secs=window)
    except HTTPException:
        # Guardrail intentionally blocking request
        raise
    except Exception:
        # Guardrails must never break normal flows
        return


def _prune_rate_store(store: dict[str, list[Any]], *, max_keys: int, window_secs: int | None = None) -> None:
    """
    Keep in-memory per-process rate/velocity stores bounded.

    Stores map a key (ip/phone/device/wallet) to a list of timestamps (seconds).
    We prune only when the store grows beyond max_keys.
    """
    try:
        if max_keys <= 0:
            store.clear()
            return
        if len(store) <= max_keys:
            return

        now = float(time.time())
        cutoff = None
        if window_secs is not None:
            try:
                w = max(1.0, float(window_secs))
                cutoff = now - w
            except Exception:
                cutoff = None

        # Prefer removing stale keys first (keys with no recent activity).
        if cutoff is not None:
            for k, entries in list(store.items()):
                try:
                    if not entries:
                        store.pop(k, None)
                        continue
                    last = float(entries[-1])
                    if last < cutoff:
                        store.pop(k, None)
                except Exception:
                    store.pop(k, None)

        if len(store) <= max_keys:
            return

        # Still oversized: drop least-recently-used keys by last timestamp.
        items: list[tuple[float, str]] = []
        for k, entries in store.items():
            try:
                last = float(entries[-1]) if entries else 0.0
            except Exception:
                last = 0.0
            items.append((last, k))
        items.sort(key=lambda t: t[0])
        drop = len(store) - max_keys
        for i in range(min(drop, len(items))):
            store.pop(items[i][1], None)
    except Exception:
        return


def _rate_limit_auth(request: Request, phone: str) -> None:
    """
    Very simple in-memory rate limiter for auth endpoints.
    Limits per phone number and per IP within a short window.
    """
    now = _now()
    # Limit pro Telefonnummer
    if phone:
        lst = _AUTH_RATE_PHONE.get(phone) or []
        lst = [ts for ts in lst if ts >= now - AUTH_RATE_WINDOW_SECS]
        lst.append(now)
        _AUTH_RATE_PHONE[phone] = lst
        _prune_rate_store(_AUTH_RATE_PHONE, max_keys=RATE_STORE_MAX_KEYS, window_secs=AUTH_RATE_WINDOW_SECS)
        if len(lst) > AUTH_MAX_PER_PHONE:
            raise HTTPException(status_code=429, detail="rate limited: too many codes for this phone")
    # Limit pro IP
    ip = _auth_client_ip(request)
    if ip and ip != "unknown":
        lst_ip = _AUTH_RATE_IP.get(ip) or []
        lst_ip = [ts for ts in lst_ip if ts >= now - AUTH_RATE_WINDOW_SECS]
        lst_ip.append(now)
        _AUTH_RATE_IP[ip] = lst_ip
        _prune_rate_store(_AUTH_RATE_IP, max_keys=RATE_STORE_MAX_KEYS, window_secs=AUTH_RATE_WINDOW_SECS)
        if len(lst_ip) > AUTH_MAX_PER_IP:
            raise HTTPException(status_code=429, detail="rate limited: too many requests from this ip")


def _rate_limit_bucket(
    store: dict[str, list[int]],
    key: str,
    *,
    window_secs: int,
    max_hits: int,
) -> int:
    if max_hits <= 0:
        return 0
    now = _now()
    window = max(1, window_secs)
    entries = store.get(key) or []
    entries = [ts for ts in entries if ts >= now - window]
    entries.append(now)
    store[key] = entries
    _prune_rate_store(store, max_keys=RATE_STORE_MAX_KEYS, window_secs=window_secs)
    return len(entries)


def _rate_limit_payments_edge(
    request: Request,
    *,
    wallet_id: str,
    scope: str,
    wallet_max: int,
    ip_max: int,
) -> None:
    scope_key = (scope or "").strip().lower() or "default"
    wallet_key = (wallet_id or "").strip()
    if wallet_key:
        hits_wallet = _rate_limit_bucket(
            _PAY_API_RATE_WALLET,
            f"{scope_key}:{wallet_key}",
            window_secs=PAY_API_RATE_WINDOW_SECS,
            max_hits=wallet_max,
        )
        if wallet_max > 0 and hits_wallet > wallet_max:
            _audit_from_request(
                request,
                "payments_edge_rate_limit_wallet",
                scope=scope_key,
                wallet_id=wallet_key,
                max=wallet_max,
                hits=hits_wallet,
            )
            raise HTTPException(status_code=429, detail="rate limited: too many requests")
    ip = _auth_client_ip(request)
    if ip and ip != "unknown":
        hits_ip = _rate_limit_bucket(
            _PAY_API_RATE_IP,
            f"{scope_key}:{ip}",
            window_secs=PAY_API_RATE_WINDOW_SECS,
            max_hits=ip_max,
        )
        if ip_max > 0 and hits_ip > ip_max:
            _audit_from_request(
                request,
                "payments_edge_rate_limit_ip",
                scope=scope_key,
                ip=ip,
                max=ip_max,
                hits=hits_ip,
            )
            raise HTTPException(status_code=429, detail="rate limited: too many requests")


def _rate_limit_chat_edge(
    request: Request,
    *,
    device_id: str | None,
    scope: str,
    device_max: int,
    ip_max: int,
) -> None:
    scope_key = (scope or "").strip().lower() or "default"
    dev = (device_id or "").strip()
    if dev:
        hits_dev = _rate_limit_bucket(
            _CHAT_RATE_DEVICE,
            f"{scope_key}:{dev}",
            window_secs=CHAT_RATE_WINDOW_SECS,
            max_hits=device_max,
        )
        if device_max > 0 and hits_dev > device_max:
            _audit_from_request(
                request,
                "chat_edge_rate_limit_device",
                scope=scope_key,
                device_id=dev,
                max=device_max,
                hits=hits_dev,
            )
            raise HTTPException(status_code=429, detail="rate limited: too many requests")
    ip = _auth_client_ip(request)
    if ip and ip != "unknown":
        hits_ip = _rate_limit_bucket(
            _CHAT_RATE_IP,
            f"{scope_key}:{ip}",
            window_secs=CHAT_RATE_WINDOW_SECS,
            max_hits=ip_max,
        )
        if ip_max > 0 and hits_ip > ip_max:
            _audit_from_request(
                request,
                "chat_edge_rate_limit_ip",
                scope=scope_key,
                ip=ip,
                max=ip_max,
                hits=hits_ip,
            )
            raise HTTPException(status_code=429, detail="rate limited: too many requests")


def _rate_limit_maps_edge(
    request: Request,
    *,
    scope: str,
    ip_max_auth: int,
    ip_max_anon: int,
) -> None:
    """
    Best-effort in-memory rate limiting for maps/geocoding/routing endpoints.
    These endpoints can become a cost/abuse sink (paid API keys, heavy upstreams),
    so we enforce tighter limits for unauthenticated callers.
    """
    try:
        scope_key = (scope or "").strip().lower() or "default"
        ip = _auth_client_ip(request)
        if not ip or ip == "unknown":
            return
        # Authenticated callers get higher quota.
        phone = _auth_phone(request)
        max_hits = int(ip_max_auth if phone else ip_max_anon)
        max_hits = max(0, max_hits)
        if max_hits <= 0:
            return
        hits = _rate_limit_bucket(
            _MAPS_RATE_IP,
            f"{scope_key}:{ip}",
            window_secs=MAPS_RATE_WINDOW_SECS,
            max_hits=max_hits,
        )
        if hits > max_hits:
            _audit_from_request(
                request,
                "maps_rate_limit_ip",
                scope=scope_key,
                ip=ip,
                max=max_hits,
                hits=hits,
            )
            raise HTTPException(status_code=429, detail="rate limited")
    except HTTPException:
        raise
    except Exception:
        # Rate limiting must never break normal flows
        return


def _prune_ttl_cache(cache: dict[Any, tuple[float, Any]], *, max_items: int, ttl_secs: int) -> None:
    """
    Keep small in-memory TTL caches bounded to prevent memory DoS.
    Values must be stored as (ts, payload).
    """
    try:
        if max_items <= 0:
            cache.clear()
            return
        now = time.time()
        ttl = max(1, int(ttl_secs))
        # Drop expired entries first.
        for k, (ts, _v) in list(cache.items()):
            try:
                if now - float(ts) > ttl:
                    cache.pop(k, None)
            except Exception:
                # If an entry is malformed, drop it.
                cache.pop(k, None)
        # If still oversized, drop oldest entries.
        if len(cache) > max_items:
            items = sorted(cache.items(), key=lambda kv: float(kv[1][0]))
            drop = len(cache) - max_items
            for i in range(min(drop, len(items))):
                cache.pop(items[i][0], None)
    except Exception:
        return


def _auth_phone(request: Request) -> str | None:
    # Test-only shortcut: allow injecting a phone number via header
    # when ENV=test so API tests do not need to orchestrate cookie login.
    _cleanup_auth_state()
    try:
        if os.getenv("ENV") == "test":
            h_phone = request.headers.get("X-Test-Phone") or request.headers.get("x-test-phone")
            if h_phone:
                return h_phone
    except Exception:
        # Fall back to cookie-based auth
        pass
    # 1) Optional: session from custom header `sa_cookie` (for web clients
    #    that cannot use Set-Cookie / browser cookies).
    sid = None
    try:
        raw = request.headers.get("sa_cookie") or request.headers.get("Sa-Cookie")
        if raw:
            sid = _normalize_session_token(raw)
    except Exception:
        sid = None

    # 2) Fallback to regular cookie when no explicit header is used.
    if not sid:
        sid = _normalize_session_token(request.cookies.get("sa_session"))
    if not sid:
        return None
    return _session_phone_from_sid(sid)


def _auth_phone_ws(ws: WebSocket) -> str | None:
    """
    Best-effort session auth for WebSockets.

    Mirrors _auth_phone() behaviour for cookie-based sessions so WS endpoints
    do not become an unauthenticated bypass.
    """
    _cleanup_auth_state()
    try:
        if os.getenv("ENV") == "test":
            h_phone = ws.headers.get("X-Test-Phone") or ws.headers.get("x-test-phone")
            if h_phone:
                return h_phone
    except Exception:
        pass

    sid = None
    try:
        raw = ws.headers.get("sa_cookie") or ws.headers.get("Sa-Cookie")
        if raw:
            sid = _normalize_session_token(raw)
    except Exception:
        sid = None

    if not sid:
        try:
            sid = _normalize_session_token(ws.cookies.get("sa_session"))
        except Exception:
            sid = None

    if not sid:
        # Optional (discouraged) query-param fallback for non-browser clients.
        try:
            q = ws.query_params.get("sa_session") or ws.query_params.get("session") or ""
            sid = _normalize_session_token(q)
        except Exception:
            sid = None

    if not sid:
        return None
    return _session_phone_from_sid(sid)


def _audit(action: str, phone: str | None = None, **extra: Any) -> None:
    """
    Lightweight audit logger for critical admin/superadmin actions.
    Writes structured entries into the JSON log stream.
    """
    try:
        payload: dict[str, Any] = {
            "event": "audit",
            "action": action,
            "phone": phone or "",
            "ts_ms": int(time.time() * 1000),
        }
        for k, v in extra.items():
            if v is not None:
                payload[k] = v
        _audit_logger.info(payload)
        _maybe_send_security_alert(payload)
    except Exception:
        # Audit must never break normal flows
        pass


def _maybe_send_security_alert(payload: dict[str, Any]) -> None:
    if not SECURITY_ALERT_WEBHOOK_URL:
        return
    if not SECURITY_ALERT_THRESHOLDS:
        return
    action = str(payload.get("action") or "").strip()
    if not action:
        return
    threshold = int(SECURITY_ALERT_THRESHOLDS.get(action) or 0)
    if threshold <= 0:
        return
    now = _now()
    window = max(30, SECURITY_ALERT_WINDOW_SECS)
    events = _SECURITY_ALERT_EVENTS.get(action) or []
    events = [ts for ts in events if ts >= now - window]
    events.append(now)
    _SECURITY_ALERT_EVENTS[action] = events
    if len(events) < threshold:
        return
    last_sent = int(_SECURITY_ALERT_LAST_SENT.get(action) or 0)
    if last_sent and now - last_sent < max(30, SECURITY_ALERT_COOLDOWN_SECS):
        return
    _SECURITY_ALERT_LAST_SENT[action] = now
    sample_keys = (
        "phone",
        "caller_wallet_id",
        "requested_wallet_id",
        "scope",
        "ip",
        "hits",
        "max",
        "target_phone",
    )
    sample: dict[str, Any] = {}
    for key in sample_keys:
        value = payload.get(key)
        if value is not None and value != "":
            sample[key] = value
    alert_payload = {
        "source": "shamell-bff",
        "event": "security_alert",
        "action": action,
        "count": len(events),
        "threshold": threshold,
        "window_secs": window,
        "sample": sample,
        "ts_ms": int(time.time() * 1000),
    }
    try:
        _metrics_logger.info(alert_payload)
    except Exception:
        pass
    try:
        httpx.post(
            SECURITY_ALERT_WEBHOOK_URL,
            json={
                "text": (
                    f"Shamell security alert: {action} "
                    f"count={len(events)} threshold={threshold} window={window}s"
                ),
                "alert": alert_payload,
            },
            timeout=4,
        )
    except Exception:
        # Alert delivery must never break request path.
        return


def _audit_from_request(request: Request, action: str, **extra: Any) -> None:
    phone = ""
    try:
        phone = _auth_phone(request) or ""
    except Exception:
        phone = ""
    _audit(action, phone=phone, **extra)

def _require_seller(request: Request) -> str:
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    # Production/staging must be explicit: default-deny when seller roles are
    # not configured, otherwise any authenticated user could access money flows.
    if _ENV_LOWER in ("prod", "staging"):
        if BFF_TOPUP_ALLOW_ALL:
            return phone
        try:
            roles = _get_effective_roles(phone)
        except Exception:
            roles = []
        if "seller" in roles:
            return phone
        raise HTTPException(status_code=403, detail="seller role required")

    # Dev/test fallback: allow via Payments roles or local env allowlist.
    # Keep permissive behaviour in dev/test to avoid blocking local iteration.
    if BFF_TOPUP_ALLOW_ALL:
        return phone
    try:
        roles = _get_effective_roles(phone)
        if "seller" in roles:
            return phone
    except Exception:
        pass
    if not BFF_TOPUP_SELLERS or phone in BFF_TOPUP_SELLERS:
        return phone
    raise HTTPException(status_code=403, detail="seller not allowed")

def _require_admin(request: Request) -> str:
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    if phone in BFF_ADMINS and phone:
        return phone
    # Optionally allow sellers to manage sellers
    if phone in BFF_TOPUP_SELLERS:
        return phone
    raise HTTPException(status_code=403, detail="admin not allowed")


def _get_effective_roles(phone: str) -> list[str]:
    """
    Returns the effective roles for a phone number.
    Prefers Payments roles and falls back to local env lists.
    """
    roles: list[str] = []
    # Payments roles via internal API when configured
    try:
        if _use_pay_internal():
            if _PAY_INTERNAL_AVAILABLE:
                with _pay_internal_session() as s:
                    arr = _pay_roles_list(phone=phone, role=None, limit=500, s=s, admin_ok=True)
                    try:
                        roles = [str(getattr(x, "role", "") or "") for x in arr if getattr(x, "role", "")]  # type: ignore[attr-defined]
                    except Exception:
                        roles = []
        elif PAYMENTS_BASE and PAYMENTS_INTERNAL_SECRET:
            # External fallback; used only when configured
            r = httpx.get(
                _payments_url("/admin/roles"),
                params={"phone": phone, "limit": 500},
                headers={"X-Internal-Secret": PAYMENTS_INTERNAL_SECRET},
                timeout=8,
            )
            if r.headers.get("content-type", "").startswith("application/json"):
                arr = r.json()
                try:
                    roles = [str(x.get("role") or "") for x in arr if isinstance(x, dict) and (x.get("role") or "")]
                except Exception:
                    roles = []
    except Exception:
        # Fallback to local roles
        roles = []
    # Always consider local env-based lists as well
    if phone in BFF_ADMINS and "admin" not in roles:
        roles.append("admin")
    if phone in BFF_TOPUP_SELLERS and "seller" not in roles:
        roles.append("seller")
    return sorted(set(r for r in roles if r))


def _is_superadmin(phone: str) -> bool:
    """
    Superadmin resolution:

    - In production/staging environments only SUPERADMIN_PHONE
      is allowed as Superadmin.
    - We also honor the Payments role "superadmin" (and legacy ops/seller in
      test/dev) so granting the role in the DB is enough without relying on
      env overrides.
    """
    # Hard binding to a single phone number (production path)
    if phone.strip() == SUPERADMIN_PHONE:
        return True
    # Role-based superadmin (dev/test use payments roles)
    try:
        roles = _get_effective_roles(phone)
        if "superadmin" in roles:
            return True
        if _env_or("ENV", "dev").lower() == "test":
            return any(r in ("ops", "seller", "superadmin") for r in roles)
    except Exception:
        pass
    return False


def _is_admin(phone: str) -> bool:
    roles = _get_effective_roles(phone)
    # Admin: admin oder Superadmin
    return _is_superadmin(phone) or "admin" in roles


def _is_operator(phone: str, domain: str | None = None) -> bool:
    roles = _get_effective_roles(phone)
    if domain:
        if f"operator_{domain}" in roles:
            return True
    # Admin/Superadmin gelten immer auch als Operatoren
    return _is_admin(phone)


def _require_operator(request: Request, domain: str) -> str:
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    if _is_operator(phone, domain):
        return phone
    raise HTTPException(status_code=403, detail=f"operator for {domain} required")


def _require_superadmin(request: Request) -> str:
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    if _is_superadmin(phone):
        return phone
    raise HTTPException(status_code=403, detail="superadmin not allowed")


def _require_admin_or_superadmin(request: Request) -> str:
    """
    Allow both Admin and Superadmin (Payments role model).
    Used for operator provisioning flows where business owners or
    superadmins are allowed to manage domain operators.
    """
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    if _is_admin(phone) or _is_superadmin(phone):
        return phone
    raise HTTPException(status_code=403, detail="admin or superadmin required")


def _require_admin_v2(request: Request) -> str:
    """
    New admin check that uses the Payments role model.
    Currently only used selectively; existing _require_admin remains for backwards compatibility.
    """
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    if _is_admin(phone):
        return phone
    raise HTTPException(status_code=403, detail="admin not allowed")

def _is_disallowed_ip_for_callbacks(ip: ipaddress._BaseAddress) -> bool:  # type: ignore[name-defined]
    # Block obviously unsafe destinations. Private IPs are blocked unless explicitly allowed.
    if ip.is_loopback or ip.is_link_local or ip.is_multicast or ip.is_reserved or ip.is_unspecified:
        return True
    if ip.is_private and not PUSH_ALLOW_PRIVATE_IPS:
        return True
    return False


async def _validate_push_endpoint(endpoint: str) -> str:
    """
    Validate a user-provided callback/push URL to reduce SSRF risk.
    Returns a normalized URL (without fragment).
    """
    ep = (endpoint or "").strip()
    if not ep:
        raise HTTPException(status_code=400, detail="endpoint required")
    if len(ep) > PUSH_MAX_ENDPOINT_LEN:
        raise HTTPException(status_code=400, detail="endpoint too long")
    try:
        parsed = _urlparse.urlparse(ep)
    except Exception:
        raise HTTPException(status_code=400, detail="invalid endpoint")

    scheme = (parsed.scheme or "").lower()
    if scheme not in ("https", "http"):
        raise HTTPException(status_code=400, detail="endpoint must be http(s)")
    if scheme == "http" and not PUSH_ALLOW_HTTP:
        raise HTTPException(status_code=403, detail="http push endpoints disabled")

    # Must have hostname.
    host = (parsed.hostname or "").strip().lower()
    if not host:
        raise HTTPException(status_code=400, detail="endpoint host required")
    if parsed.username or parsed.password:
        raise HTTPException(status_code=400, detail="endpoint userinfo not allowed")

    # Block obvious local hostnames.
    if host in ("localhost",) or host.endswith(".localhost") or host.endswith(".local"):
        raise HTTPException(status_code=403, detail="endpoint host not allowed")

    # Optional allowlist: when configured, enforce exact hostname matches.
    if PUSH_ALLOWED_HOSTS and host not in PUSH_ALLOWED_HOSTS:
        raise HTTPException(status_code=403, detail="endpoint host not allowed")

    # Block private/loopback etc. for IP literals.
    try:
        ip = ipaddress.ip_address(host)
        if _is_disallowed_ip_for_callbacks(ip):
            raise HTTPException(status_code=403, detail="endpoint host not allowed")
    except ValueError:
        # Hostname: best-effort DNS resolution to detect private targets.
        if PUSH_VALIDATE_DNS:
            port: int
            try:
                port = int(parsed.port or (443 if scheme == "https" else 80))
            except Exception:
                port = 443 if scheme == "https" else 80

            def _resolve() -> list[str]:
                out: list[str] = []
                for _fam, _type, _proto, _canon, sockaddr in socket.getaddrinfo(host, port, type=socket.SOCK_STREAM):
                    try:
                        ip_str = sockaddr[0]
                        if ip_str:
                            out.append(ip_str)
                    except Exception:
                        continue
                return out

            try:
                ips = await asyncio.to_thread(_resolve)
            except Exception:
                ips = []
            if not ips:
                raise HTTPException(status_code=403, detail="endpoint host not resolvable")
            for ip_str in ips:
                try:
                    ip = ipaddress.ip_address(ip_str)
                    if _is_disallowed_ip_for_callbacks(ip):
                        raise HTTPException(status_code=403, detail="endpoint host not allowed")
                except HTTPException:
                    raise
                except Exception:
                    continue

    # Drop fragment (never relevant for callbacks) and return a normalized URL.
    try:
        cleaned = parsed._replace(fragment="").geturl()
    except Exception:
        cleaned = ep
    return cleaned


@app.post("/push/register")
async def push_register(req: Request):
    """
    Register a self-hosted push endpoint (Gotify / UnifiedPush) for the
    currently authenticated user (driver or passenger).
    """
    phone = _auth_phone(req)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    try:
        body = await req.json()
    except Exception:
        body = {}
    if not isinstance(body, dict):
        body = {}
    device_id = (body.get("device_id") or "").strip()
    endpoint = (body.get("endpoint") or "").strip()
    etype = (body.get("type") or "gotify").strip().lower()
    if not device_id or not endpoint:
        raise HTTPException(status_code=400, detail="device_id and endpoint required")
    if len(device_id) > 128:
        raise HTTPException(status_code=400, detail="device_id too long")
    # Prevent SSRF by validating the callback endpoint (only used for UnifiedPush).
    if etype == "unifiedpush":
        endpoint = await _validate_push_endpoint(endpoint)
    entries = [e for e in _PUSH_ENDPOINTS.get(phone, []) if e.get("device_id") != device_id]
    entries.append({"device_id": device_id, "endpoint": endpoint, "type": etype})
    _PUSH_ENDPOINTS[phone] = entries
    return {"ok": True, "phone": phone, "device_id": device_id, "type": etype}

def _validate_lat(lat: float) -> float:
    try:
        v = float(lat)
    except Exception:
        raise HTTPException(status_code=400, detail="invalid latitude")
    if v < -90.0 or v > 90.0:
        raise HTTPException(status_code=400, detail="invalid latitude")
    return v


def _validate_lon(lon: float) -> float:
    try:
        v = float(lon)
    except Exception:
        raise HTTPException(status_code=400, detail="invalid longitude")
    if v < -180.0 or v > 180.0:
        raise HTTPException(status_code=400, detail="invalid longitude")
    return v


def _normalize_maps_query(q: str) -> str:
    qq = str(q or "").strip()
    if not qq:
        raise HTTPException(status_code=400, detail="q required")
    if len(qq) > MAPS_MAX_QUERY_LEN:
        raise HTTPException(status_code=400, detail="q too long")
    return qq


_ORS_PROFILE_MAP = {
    "car": "driving-car",
    "driving": "driving-car",
    "driving-car": "driving-car",
    "truck": "driving-hgv",
    "hgv": "driving-hgv",
    "lorry": "driving-hgv",
    "driving-hgv": "driving-hgv",
    "bicycle": "cycling-regular",
    "bike": "cycling-regular",
    "cycling": "cycling-regular",
    "cycling-regular": "cycling-regular",
    "foot": "foot-walking",
    "walk": "foot-walking",
    "walking": "foot-walking",
    "pedestrian": "foot-walking",
    "foot-walking": "foot-walking",
}


@app.get("/osm/route")
def osm_route(
    request: Request,
    start_lat: float,
    start_lon: float,
    end_lat: float,
    end_lon: float,
    profile: str = "driving-car",
):
    """
    Lightweight proxy for OpenRouteService/GraphHopper style routing.

    Returns a simplified polyline and distance/duration so the client can draw
    the route on MapLibre/Google maps without talking to ORS directly.
    """
    _rate_limit_maps_edge(
        request,
        scope="maps_route",
        ip_max_auth=MAPS_ROUTE_MAX_PER_IP_AUTH,
        ip_max_anon=MAPS_ROUTE_MAX_PER_IP_ANON,
    )
    start_lat = _validate_lat(start_lat)
    start_lon = _validate_lon(start_lon)
    end_lat = _validate_lat(end_lat)
    end_lon = _validate_lon(end_lon)
    if not ORS_BASE and not OSRM_BASE and not TOMTOM_API_KEY:
        raise HTTPException(status_code=400, detail="no routing backend configured")
    try:
        points: list[list[float]] = []
        distance_m = 0.0
        duration_s = 0.0
        p = (profile or "").strip().lower()
        # Prefer TomTom Routing API when a key is configured.
        if TOMTOM_API_KEY:
            base = TOMTOM_BASE.rstrip("/")
            # TomTom Routing API expects "lat,lon:lat,lon" order in the path.
            path = f"/routing/1/calculateRoute/{float(start_lat)},{float(start_lon)}:{float(end_lat)},{float(end_lon)}/json"
            # Map generic profile to TomTom travelMode
            if p in ("truck", "hgv", "lorry"):
                travel_mode = "truck"
            elif p in ("bicycle", "bike", "cycling"):
                travel_mode = "bicycle"
            elif p in ("foot", "pedestrian", "walk", "walking"):
                travel_mode = "pedestrian"
            else:
                travel_mode = "car"
            params = {
                "key": TOMTOM_API_KEY,
                # Enable traffic-aware routing for accurate ETAs.
                "traffic": "true",
                "travelMode": travel_mode,
                # Ask TomTom for alternative routes where available.
                "maxAlternatives": "2",
            }
            try:
                r = _httpx_client().get(base + path, params=params)
            except Exception as e:
                raise HTTPException(status_code=502, detail=f"routing upstream error: {e}")
            if r.status_code >= 400:
                raise HTTPException(status_code=502, detail=f"routing upstream error: {r.text[:200]}")
            j = r.json()
            routes = j.get("routes") or []
            if routes:
                # Build normalized list of route variants.
                norm_routes: list[dict[str, object]] = []
                for rt in routes:
                    legs = rt.get("legs") or []
                    points_raw = []
                    if legs:
                        leg0 = legs[0]
                        points_raw = leg0.get("points") or []
                    pts: list[list[float]] = []
                    for pp in points_raw:
                        try:
                            lat = float(pp.get("latitude") or pp.get("lat") or 0.0)
                            lon = float(pp.get("longitude") or pp.get("lon") or 0.0)
                            pts.append([lat, lon])
                        except Exception:
                            continue
                    summary = rt.get("summary") or {}
                    try:
                        d_m = float(summary.get("lengthInMeters") or 0.0)
                    except Exception:
                        d_m = 0.0
                    try:
                        t_s = float(summary.get("travelTimeInSeconds") or 0.0)
                    except Exception:
                        t_s = 0.0
                    norm_routes.append(
                        {
                            "points": pts,
                            "distance_m": d_m,
                            "duration_s": t_s,
                        }
                    )
                if norm_routes:
                    first = norm_routes[0]
                    points = first.get("points") or []
                    try:
                        distance_m = float(first.get("distance_m") or 0.0)  # type: ignore[arg-type]
                    except Exception:
                        distance_m = 0.0
                    try:
                        duration_s = float(first.get("duration_s") or 0.0)  # type: ignore[arg-type]
                    except Exception:
                        duration_s = 0.0
                    return {
                        "points": points,
                        "distance_m": distance_m,
                        "duration_s": duration_s,
                        "routes": norm_routes,
                    }
        elif ORS_BASE:
            # Prevent path-injection: only allow a small profile allowlist.
            ors_profile = _ORS_PROFILE_MAP.get(p)
            if not ors_profile:
                raise HTTPException(status_code=400, detail="invalid profile")
            coords = [
                [float(start_lon), float(start_lat)],
                [float(end_lon), float(end_lat)],
            ]
            url = ORS_BASE.rstrip("/") + f"/v2/directions/{ors_profile}"
            headers = {"accept": "application/json", "content-type": "application/json"}
            if ORS_API_KEY:
                headers["Authorization"] = ORS_API_KEY
            body = {
                "coordinates": coords,
                "geometry": True,
            }
            r = _httpx_client().post(url, json=body, headers=headers)
            if r.status_code >= 400:
                raise HTTPException(status_code=502, detail=f"routing upstream error: {r.text[:200]}")
            j = r.json()
            routes = j.get("routes") or j.get("features") or []
            if routes:
                route = routes[0]
                coords_out = []
                try:
                    geom = route.get("geometry")
                    if isinstance(geom, dict):
                        coords_out = geom.get("coordinates") or []
                    elif isinstance(geom, list):
                        coords_out = geom
                    elif isinstance(geom, str):
                        # geometry is encoded polyline; for now keep empty -> client falls back
                        coords_out = []
                except Exception:
                    coords_out = []
                for c in coords_out:
                    try:
                        if isinstance(c, (list, tuple)) and len(c) >= 2:
                            lon, lat = float(c[0]), float(c[1])
                            points.append([lat, lon])
                    except Exception:
                        continue
                summary = route.get("summary") or {}
                try:
                    distance_m = float(summary.get("distance") or 0.0)
                except Exception:
                    distance_m = 0.0
                try:
                    duration_s = float(summary.get("duration") or 0.0)
                except Exception:
                    duration_s = 0.0
        elif OSRM_BASE:
            base = OSRM_BASE.rstrip("/")
            coords = f"{float(start_lon)},{float(start_lat)};{float(end_lon)},{float(end_lat)}"
            url = f"{base}/route/v1/driving/{coords}"
            params = {
                "overview": "full",
                "alternatives": "false",
                "steps": "false",
                "geometries": "geojson",
            }
            r = _httpx_client().get(url, params=params)
            if r.status_code >= 400:
                raise HTTPException(status_code=502, detail=f"routing upstream error: {r.text[:200]}")
            j = r.json()
            routes = j.get("routes") or []
            if routes:
                route = routes[0]
                try:
                    geom = route.get("geometry") or {}
                    coords_out = geom.get("coordinates") or []
                except Exception:
                    coords_out = []
                for c in coords_out:
                    try:
                        if isinstance(c, (list, tuple)) and len(c) >= 2:
                            lon, lat = float(c[0]), float(c[1])
                            points.append([lat, lon])
                    except Exception:
                        continue
                try:
                    distance_m = float(route.get("distance") or 0.0)
                except Exception:
                    distance_m = 0.0
                try:
                    duration_s = float(route.get("duration") or 0.0)
                except Exception:
                    duration_s = 0.0
        return {"points": points, "distance_m": distance_m, "duration_s": duration_s}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


def _osm_geocode_core(q: str):
    """
    Simple geocoding proxy backed by Nominatim or TomTom Search API.
    """
    now = time.time()
    cached = _OSM_GEOCODE_CACHE.get(q)
    if cached and (now - cached[0] < 60):
        return cached[1]
    # Prefer TomTom Search API when a key is configured.
    if TOMTOM_API_KEY:
        base = TOMTOM_BASE.rstrip("/")
        # Geocode query: /search/2/geocode/{query}.json?key=...
        from urllib.parse import quote
        path = f"/search/2/geocode/{quote(q)}.json"
        params = {"key": TOMTOM_API_KEY, "limit": "5"}
        try:
            r = _httpx_client().get(base + path, params=params)
            if r.status_code >= 400:
                raise HTTPException(status_code=502, detail=f"geocode upstream error: {r.text[:200]}")
            j = r.json()
            results = j.get("results") or []
            out: list[dict[str, object]] = []
            for item in results:
                try:
                    pos = item.get("position") or {}
                    lat = float(pos.get("lat") or pos.get("latitude") or 0.0)
                    lon = float(pos.get("lon") or pos.get("longitude") or 0.0)
                    addr = ""
                    address = item.get("address") or {}
                    if isinstance(address, dict):
                        addr = (address.get("freeformAddress") or "") or ""
                    out.append({"lat": lat, "lon": lon, "display_name": addr})
                except Exception:
                    continue
            _prune_ttl_cache(_OSM_GEOCODE_CACHE, max_items=MAPS_CACHE_MAX_ITEMS, ttl_secs=MAPS_CACHE_TTL_SECS)
            _OSM_GEOCODE_CACHE[q] = (now, out)
            return out
        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(status_code=502, detail=str(e))
    # Fallback: Nominatim / OSM when configured.
    if not NOMINATIM_BASE:
        raise HTTPException(status_code=400, detail="NOMINATIM_BASE_URL not configured and no TomTom key")
    url = NOMINATIM_BASE.rstrip("/") + "/search"
    params = {"q": q, "format": "json", "addressdetails": "0", "limit": "5"}
    headers = {"User-Agent": NOMINATIM_USER_AGENT}
    try:
        r = _httpx_client().get(url, params=params, headers=headers)
        if r.status_code >= 400:
            raise HTTPException(status_code=502, detail=f"geocode upstream error: {r.text[:200]}")
        arr = r.json()
        if not isinstance(arr, list):
            return []
        out = []
        for item in arr:
            try:
                lat = float(item.get("lat") or 0.0)
                lon = float(item.get("lon") or 0.0)
                out.append({
                    "lat": lat,
                    "lon": lon,
                    "display_name": (item.get("display_name") or ""),
                })
            except Exception:
                continue
        _prune_ttl_cache(_OSM_GEOCODE_CACHE, max_items=MAPS_CACHE_MAX_ITEMS, ttl_secs=MAPS_CACHE_TTL_SECS)
        _OSM_GEOCODE_CACHE[q] = (now, out)
        return out
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/osm/geocode")
def osm_geocode(request: Request, q: str):
    _rate_limit_maps_edge(
        request,
        scope="maps_geocode",
        ip_max_auth=MAPS_GEOCODE_MAX_PER_IP_AUTH,
        ip_max_anon=MAPS_GEOCODE_MAX_PER_IP_ANON,
    )
    qq = _normalize_maps_query(q)
    return _osm_geocode_core(qq)


@app.get("/osm/poi_search")
def osm_poi_search(
    request: Request,
    q: str,
    lat: float | None = None,
    lon: float | None = None,
    limit: int = 20,
):
    """
    POI-Suche (Tankstellen, Apotheken, Restaurants, ...) rund um eine Position.

    Bevorzugt TomTom Search API, fällt sonst auf Nominatim/OSM zurück.
    Antwortformat:
      - lat, lon, name, category, address
    """
    _rate_limit_maps_edge(
        request,
        scope="maps_poi",
        ip_max_auth=MAPS_POI_MAX_PER_IP_AUTH,
        ip_max_anon=MAPS_POI_MAX_PER_IP_ANON,
    )
    q = _normalize_maps_query(q)
    limit = max(1, min(limit, 50))
    if lat is not None:
        lat = _validate_lat(lat)
    if lon is not None:
        lon = _validate_lon(lon)
    # TomTom Search API
    if TOMTOM_API_KEY:
        base = TOMTOM_BASE.rstrip("/")
        from urllib.parse import quote

        path = f"/search/2/search/{quote(q)}.json"
        params: dict[str, object] = {"key": TOMTOM_API_KEY, "limit": limit}
        if lat is not None and lon is not None:
            params["lat"] = float(lat)
            params["lon"] = float(lon)
            params["radius"] = 5000
        try:
            r = _httpx_client().get(base + path, params=params)
            if r.status_code >= 400:
                raise HTTPException(status_code=502, detail=f"poi upstream error: {r.text[:200]}")
            j = r.json()
            results = j.get("results") or []
            out: list[dict[str, object]] = []
            for item in results:
                try:
                    pos = item.get("position") or {}
                    plat = float(pos.get("lat") or pos.get("latitude") or 0.0)
                    plon = float(pos.get("lon") or pos.get("longitude") or 0.0)
                    poi = item.get("poi") or {}
                    name = ""
                    category = ""
                    if isinstance(poi, dict):
                        name = (poi.get("name") or "") or ""
                        cats = poi.get("categories") or []
                        if isinstance(cats, list) and cats:
                            category = str(cats[0] or "")
                    address = ""
                    addr = item.get("address") or {}
                    if isinstance(addr, dict):
                        address = (addr.get("freeformAddress") or "") or ""
                    out.append(
                        {
                            "lat": plat,
                            "lon": plon,
                            "name": name,
                            "category": category,
                            "address": address,
                        }
                    )
                except Exception:
                    continue
            return out
        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(status_code=502, detail=str(e))

    # Fallback: Nominatim POI search via OSM when configured
    if not NOMINATIM_BASE:
        raise HTTPException(
            status_code=400, detail="NOMINATIM_BASE_URL not configured and no TomTom key"
        )
    url = NOMINATIM_BASE.rstrip("/") + "/search"
    params = {
        "q": q,
        "format": "json",
        "addressdetails": "1",
        "limit": str(limit),
    }
    if lat is not None and lon is not None:
        params["viewbox"] = (
            f"{lon-0.05},{lat+0.05},{lon+0.05},{lat-0.05}"
        )
        params["bounded"] = "1"
    headers = {"User-Agent": NOMINATIM_USER_AGENT}
    try:
        r = _httpx_client().get(url, params=params, headers=headers)
        if r.status_code >= 400:
            raise HTTPException(status_code=502, detail=f"poi upstream error: {r.text[:200]}")
        arr = r.json()
        if not isinstance(arr, list):
            return []
        out = []
        for item in arr:
            try:
                plat = float(item.get("lat") or 0.0)
                plon = float(item.get("lon") or 0.0)
                name = (item.get("display_name") or "") or ""
                addr = item.get("address") or {}
                cat = ""
                if isinstance(addr, dict):
                    cat = (
                        addr.get("amenity")
                        or addr.get("shop")
                        or addr.get("tourism")
                        or ""
                    )
                out.append(
                    {
                        "lat": plat,
                        "lon": plon,
                        "name": name,
                        "category": cat,
                        "address": name,
                    }
                )
            except Exception:
                continue
        return out
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/osm/geocode_batch")
async def osm_geocode_batch(request: Request):
    """
    Batch-Geocoding für Backend-Importe.

    Body:
      - queries: List[str]
      - max_per_query: int (optional, default 1)

    Antwort:
      {
        "results": [
          {
            "query": "...",
            "hits": [
              {"lat": ..., "lon": ..., "display_name": "..."},
              ...
            ]
          },
          ...
        ]
      }
    """
    # Batch geocoding can amplify abuse; require an authenticated caller.
    if not _auth_phone(request):
        raise HTTPException(status_code=401, detail="unauthorized")
    _rate_limit_maps_edge(
        request,
        scope="maps_geocode_batch",
        ip_max_auth=MAPS_GEOCODE_BATCH_MAX_PER_IP_AUTH,
        ip_max_anon=MAPS_GEOCODE_BATCH_MAX_PER_IP_ANON,
    )
    try:
        body = await request.json()
    except Exception:
        body = {}
    if not isinstance(body, dict):
        body = {}
    queries = body.get("queries") or []
    if not isinstance(queries, list):
        raise HTTPException(status_code=400, detail="queries must be a list")
    if len(queries) > MAPS_MAX_BATCH_QUERIES:
        raise HTTPException(status_code=413, detail="too many queries")
    max_per_query = int(body.get("max_per_query") or 1)
    max_per_query = max(1, min(max_per_query, 10))

    out: list[dict[str, object]] = []
    for raw_q in queries:
        q = str(raw_q or "").strip()
        if not q:
            out.append({"query": q, "hits": []})
            continue
        try:
            qq = _normalize_maps_query(q)
            hits = _osm_geocode_core(qq)
            if isinstance(hits, list):
                hits = hits[:max_per_query]
            else:
                hits = []
        except HTTPException as e:
            hits = [{"error": e.detail}]
        except Exception as e:
            hits = [{"error": str(e)}]
        out.append({"query": q, "hits": hits})
    return {"results": out}


@app.post("/fleet/optimize_stops")
async def fleet_optimize_stops(request: Request):
    """
    Simple stop-order optimisation for a single vehicle (e.g. deliveries or rides).

    Body:
      - origin: {lat, lon}
      - stops: [{id, lat, lon}, ...]
      - profile: optional (car/truck/bicycle/pedestrian), currently only used for future routing hooks

    Uses a greedy nearest-neighbour heuristic based on Haversine distance.
    Returns an ordered stop list and approximate total distance.
    """
    if not _auth_phone(request):
        raise HTTPException(status_code=401, detail="unauthorized")
    try:
        body = await request.json()
    except Exception:
        body = {}
    if not isinstance(body, dict):
        body = {}
    origin = body.get("origin") or {}
    stops = body.get("stops") or []
    if not isinstance(origin, dict) or not isinstance(stops, list):
        raise HTTPException(status_code=400, detail="origin and stops required")
    if len(stops) > FLEET_MAX_STOPS:
        raise HTTPException(status_code=413, detail="too many stops")
    try:
        o_lat = _validate_lat(origin.get("lat"))
        o_lon = _validate_lon(origin.get("lon"))
    except Exception:
        raise HTTPException(status_code=400, detail="invalid origin")
    # Normalise stops
    rem: list[dict[str, Any]] = []
    for s in stops:
        try:
            if not isinstance(s, dict):
                continue
            sid = str(s.get("id") or "")
            if not sid or len(sid) > 64:
                continue
            lat = _validate_lat(s.get("lat"))
            lon = _validate_lon(s.get("lon"))
            if not sid:
                continue
            rem.append({"id": sid, "lat": lat, "lon": lon})
        except Exception:
            continue
    if not rem:
        return {"ok": True, "origin": origin, "order": [], "total_km": 0.0}
    cur_lat = o_lat
    cur_lon = o_lon
    ordered: list[dict[str, Any]] = []
    total_km = 0.0
    while rem:
        best_idx = None
        best_km = float("inf")
        for i, s in enumerate(rem):
            d_km = _haversine_km(cur_lat, cur_lon, s["lat"], s["lon"])
            if d_km < best_km:
                best_km = d_km
                best_idx = i
        if best_idx is None:
            break
        nxt = rem.pop(best_idx)
        total_km += best_km if math.isfinite(best_km) else 0.0
        ordered.append(
            {
                "id": nxt["id"],
                "lat": nxt["lat"],
                "lon": nxt["lon"],
                "leg_km": best_km,
            }
        )
        cur_lat = nxt["lat"]
        cur_lon = nxt["lon"]
    return {
        "ok": True,
        "origin": {"lat": o_lat, "lon": o_lon},
        "order": ordered,
        "total_km": total_km,
    }


@app.post("/fleet/assign_deliveries")
async def fleet_assign_deliveries(request: Request):
    """
    Simple multi-depot assignment helper for planning scenarios.

    Body:
      - depots: [{id, lat, lon}, ...]
      - stops: [{id, lat, lon}, ...]

    Each stop is assigned to the nearest depot by Haversine distance.
    The result can be used per-depot with /fleet/optimize_stops to plan daily tours.
    """
    if not _auth_phone(request):
        raise HTTPException(status_code=401, detail="unauthorized")
    try:
        body = await request.json()
    except Exception:
        body = {}
    if not isinstance(body, dict):
        body = {}
    depots = body.get("depots") or []
    stops = body.get("stops") or []
    if not isinstance(depots, list) or not isinstance(stops, list):
        raise HTTPException(status_code=400, detail="depots and stops must be lists")
    if len(depots) > FLEET_MAX_DEPOTS:
        raise HTTPException(status_code=413, detail="too many depots")
    if len(stops) > FLEET_MAX_STOPS:
        raise HTTPException(status_code=413, detail="too many stops")
    norm_depots: list[dict[str, Any]] = []
    for d in depots:
        try:
            if not isinstance(d, dict):
                continue
            did = str(d.get("id") or "")
            if not did or len(did) > 64:
                continue
            lat = _validate_lat(d.get("lat"))
            lon = _validate_lon(d.get("lon"))
            norm_depots.append({"id": did, "lat": lat, "lon": lon})
        except Exception:
            continue
    if not norm_depots:
        raise HTTPException(status_code=400, detail="no valid depots provided")
    norm_stops: list[dict[str, Any]] = []
    for s in stops:
        try:
            if not isinstance(s, dict):
                continue
            sid = str(s.get("id") or "")
            if not sid or len(sid) > 64:
                continue
            lat = _validate_lat(s.get("lat"))
            lon = _validate_lon(s.get("lon"))
            norm_stops.append({"id": sid, "lat": lat, "lon": lon})
        except Exception:
            continue
    assignments: list[dict[str, Any]] = []
    per_depot: dict[str, dict[str, Any]] = {}
    for d in norm_depots:
        per_depot[d["id"]] = {"depot": d, "stops": [], "total_km": 0.0}
    for s in norm_stops:
        best_depot = None
        best_km = float("inf")
        for d in norm_depots:
            d_km = _haversine_km(d["lat"], d["lon"], s["lat"], s["lon"])
            if d_km < best_km:
                best_km = d_km
                best_depot = d
        if best_depot is None:
            continue
        did = best_depot["id"]
        assignments.append(
            {
                "stop_id": s["id"],
                "depot_id": did,
                "distance_km": best_km,
            }
        )
        pd = per_depot[did]
        pd["stops"].append(s)
        pd["total_km"] = float(pd.get("total_km") or 0.0) + (best_km if math.isfinite(best_km) else 0.0)
    return {
        "ok": True,
        "assignments": assignments,
        "per_depot": per_depot,
    }

@app.get("/osm/reverse")
def osm_reverse(request: Request, lat: float, lon: float):
    """
    Reverse geocoding proxy backed by Nominatim or TomTom.
    """
    _rate_limit_maps_edge(
        request,
        scope="maps_reverse",
        ip_max_auth=MAPS_REVERSE_MAX_PER_IP_AUTH,
        ip_max_anon=MAPS_REVERSE_MAX_PER_IP_ANON,
    )
    lat = _validate_lat(lat)
    lon = _validate_lon(lon)
    now = time.time()
    key = (round(lat, 5), round(lon, 5))
    cached = _OSM_REVERSE_CACHE.get(key)
    if cached and (now - cached[0] < 60):
        return cached[1]
    # Prefer TomTom Reverse Geocoding when configured.
    if TOMTOM_API_KEY:
        base = TOMTOM_BASE.rstrip("/")
        path = f"/search/2/reverseGeocode/{float(lat)},{float(lon)}.json"
        params = {"key": TOMTOM_API_KEY}
        try:
            r = _httpx_client().get(base + path, params=params)
            if r.status_code >= 400:
                raise HTTPException(status_code=502, detail=f"reverse upstream error: {r.text[:200]}")
            j = r.json()
            addresses = j.get("addresses") or []
            if not addresses:
                res = {"lat": lat, "lon": lon, "display_name": ""}
                _prune_ttl_cache(_OSM_REVERSE_CACHE, max_items=MAPS_CACHE_MAX_ITEMS, ttl_secs=MAPS_CACHE_TTL_SECS)
                _OSM_REVERSE_CACHE[key] = (now, res)
                return res
            addr0 = addresses[0]
            try:
                pos = addr0.get("position") or {}
                out_lat = float(pos.get("lat") or pos.get("latitude") or lat)
            except Exception:
                out_lat = lat
            try:
                pos = addr0.get("position") or {}
                out_lon = float(pos.get("lon") or pos.get("longitude") or lon)
            except Exception:
                out_lon = lon
            display_name = ""
            address = addr0.get("address") or {}
            if isinstance(address, dict):
                display_name = (address.get("freeformAddress") or "") or ""
            res = {"lat": out_lat, "lon": out_lon, "display_name": display_name}
            _prune_ttl_cache(_OSM_REVERSE_CACHE, max_items=MAPS_CACHE_MAX_ITEMS, ttl_secs=MAPS_CACHE_TTL_SECS)
            _OSM_REVERSE_CACHE[key] = (now, res)
            return res
        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(status_code=502, detail=str(e))
    # Fallback: Nominatim / OSM when configured.
    if not NOMINATIM_BASE:
        raise HTTPException(status_code=400, detail="NOMINATIM_BASE_URL not configured and no TomTom key")
    url = NOMINATIM_BASE.rstrip("/") + "/reverse"
    params = {"lat": lat, "lon": lon, "format": "json"}
    headers = {"User-Agent": NOMINATIM_USER_AGENT}
    try:
        r = _httpx_client().get(url, params=params, headers=headers)
        if r.status_code >= 400:
            raise HTTPException(status_code=502, detail=f"reverse upstream error: {r.text[:200]}")
        j = r.json()
        if not isinstance(j, dict):
            return {"lat": lat, "lon": lon, "display_name": ""}
        try:
            out_lat = float(j.get("lat") or lat)
        except Exception:
            out_lat = lat
        try:
            out_lon = float(j.get("lon") or lon)
        except Exception:
            out_lon = lon
        display_name = (j.get("display_name") or "")
        res = {"lat": out_lat, "lon": out_lon, "display_name": display_name}
        _prune_ttl_cache(_OSM_REVERSE_CACHE, max_items=MAPS_CACHE_MAX_ITEMS, ttl_secs=MAPS_CACHE_TTL_SECS)
        _OSM_REVERSE_CACHE[key] = (now, res)
        return res
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/auth/request_code")
async def auth_request_code(req: Request):
    try:
        body = await req.json()
        phone = (body.get("phone") or "").strip()
    except Exception:
        phone = ""
    if not phone:
        raise HTTPException(status_code=400, detail="phone required")
    phone_norm = _normalize_phone_e164(phone)
    if not phone_norm:
        raise HTTPException(status_code=400, detail="invalid phone")
    phone = phone_norm
    # Blocked phones: do not issue codes
    if phone in _BLOCKED_PHONES:
        raise HTTPException(status_code=403, detail="phone blocked")
    # Basic rate limiting per phone and IP
    _rate_limit_auth(req, phone)
    code = _issue_code(phone)
    resp = {"ok": True, "phone": phone, "ttl": LOGIN_CODE_TTL_SECS}
    # Only expose OTP code when explicitly allowed (typically dev/test).
    if AUTH_EXPOSE_CODES:
        resp["code"] = code
    return resp

@app.post("/auth/verify")
async def auth_verify(req: Request):
    try:
        body = await req.json()
        phone = (body.get("phone") or "").strip()
        code = (body.get("code") or "").strip()
        name = (body.get("name") or "").strip()
        device_id = _normalize_device_id(str(body.get("device_id") or ""))
    except Exception:
        raise HTTPException(status_code=400, detail="invalid body")
    phone_norm = _normalize_phone_e164(phone)
    if not phone_norm:
        raise HTTPException(status_code=400, detail="invalid phone")
    phone = phone_norm
    # Optional: also rate-limit verify requests (same limits as request_code)
    _rate_limit_auth(req, phone)
    if not _check_code(phone, code):
        raise HTTPException(status_code=400, detail="invalid code")
    # Ensure a payments wallet exists for this phone (idempotent).
    # Prefer internal Payments wiring in internal mode; fallback to HTTP
    # only when explicitly configured.
    wallet_id: str | None = None
    try:
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise RuntimeError("payments internal not available")
            data = {"phone": phone}
            try:
                req_model = _PayCreateUserReq(**data)  # type: ignore[name-defined]
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _pay_internal_session() as s:  # type: ignore[name-defined]
                user = _pay_create_user(req_model, s=s)  # type: ignore[name-defined]
                try:
                    wallet_id = getattr(user, "wallet_id", None) or getattr(user, "id", None)  # type: ignore[attr-defined]
                except Exception:
                    wallet_id = None
        elif PAYMENTS_BASE:
            url = PAYMENTS_BASE.rstrip('/') + '/users'
            r = await _httpx_async_client().post(
                url,
                json={"phone": phone},
                headers=_payments_headers(),
            )
            if r.headers.get("content-type","" ).startswith("application/json"):
                j = r.json()
                wallet_id = (j.get("wallet_id") or j.get("id")) if isinstance(j, dict) else None  # type: ignore[assignment]
    except HTTPException:
        # Input errors etc.; login should still work.
        wallet_id = None
    except Exception:
        # Payments must not hard-break login.
        wallet_id = None
    rider_id = None
    sid = _create_session(phone, device_id=device_id)
    # Also return the session ID in JSON so web clients
    # can send it explicitly as header (sa_cookie).
    resp = JSONResponse({"ok": True, "phone": phone, "wallet_id": wallet_id, "rider_id": rider_id, "session": sid})
    resp.set_cookie("sa_session", sid, max_age=AUTH_SESSION_TTL_SECS, httponly=True, secure=True, samesite="lax", path="/")
    return resp


@app.get("/me/wallet")
async def me_wallet(request: Request):
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    # Prefer internal Payments wiring in internal mode; fallback to HTTP only
    # when explicitly configured.
    try:
        wallet_id: str | None = None
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            data = {"phone": phone}
            try:
                req_model = _PayCreateUserReq(**data)  # type: ignore[name-defined]
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _pay_internal_session() as s:
                user = _pay_create_user(req_model, s=s)
                try:
                    wallet_id = getattr(user, "wallet_id", None) or getattr(user, "id", None)  # type: ignore[attr-defined]
                except Exception:
                    wallet_id = None
        else:
            if not PAYMENTS_BASE:
                raise HTTPException(status_code=500, detail="PAYMENTS_BASE_URL not configured")
            url = PAYMENTS_BASE.rstrip('/') + '/users'
            r = await _httpx_async_client().post(
                url,
                json={"phone": phone},
                headers=_payments_headers(),
            )
            if r.headers.get("content-type","" ).startswith("application/json"):
                j = r.json()
            else:
                j = {"raw": r.text, "status_code": r.status_code}
            try:
                if isinstance(j, dict):
                    wallet_id = (j.get("wallet_id") or j.get("id"))  # type: ignore[assignment]
            except Exception:
                wallet_id = None
        return {"ok": True, "phone": phone, "wallet_id": wallet_id}
    except HTTPException:
        raise
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/me/overview")
async def me_overview(request: Request):
    """
    Lightweight aggregate endpoint for clients:
      - authenticated phone number
      - roles (via /me/roles internally)
      - wallet information (via internal Payments or HTTP fallback)
    """
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")

    overview: dict[str, Any] = {"phone": phone}

    # Rollen wiederverwenden, ohne HTTP-Roundtrip
    try:
        roles_obj = me_roles(request)
        overview["roles"] = roles_obj.get("roles", []) if isinstance(roles_obj, dict) else []
    except HTTPException:
        raise
    except Exception:
        overview["roles"] = []

    # Wallet / User aus Payments holen (intern bevorzugt)
    wallet_info: Any = None
    wallet_id: str | None = None
    wallet_error: str | None = None
    try:
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise RuntimeError("payments internal not available")
            data = {"phone": phone}
            req_model = _PayCreateUserReq(**data)  # type: ignore[name-defined]
            with _pay_internal_session() as s:
                user = _pay_create_user(req_model, s=s)
                wallet_info = user
                # Versuche Wallet-ID abzuleiten
                try:
                    wallet_id = getattr(user, "wallet_id", None) or getattr(user, "id", None)  # type: ignore[attr-defined]
                except Exception:
                    wallet_id = None
                if wallet_id:
                    try:
                        wallet_obj = _pay_get_wallet(wallet_id=wallet_id, s=s)
                        wallet_info = wallet_obj
                    except Exception:
                        # Fallback: nur User-Objekt
                        pass
        elif PAYMENTS_BASE:
            r = await _httpx_async_client().post(
                _payments_url("/users"),
                json={"phone": phone},
                headers=_payments_headers(),
            )
            if r.headers.get("content-type", "").startswith("application/json"):
                j = r.json()
            else:
                j = {"raw": r.text, "status_code": r.status_code}
            wallet_info = j
            try:
                if isinstance(j, dict):
                    wallet_id = (j.get("wallet_id") or j.get("id"))  # type: ignore[assignment]
            except Exception:
                wallet_id = None
    except HTTPException:
        raise
    except Exception as e:
        wallet_error = str(e)

    if wallet_info is not None:
        overview["wallet"] = wallet_info
    if wallet_id:
        overview["wallet_id"] = wallet_id
    if wallet_error:
        overview["wallet_error"] = wallet_error

    return overview


@app.get("/me/dashboard")
async def me_dashboard(request: Request, tx_limit: int = 10):
    """
    A slightly richer aggregate endpoint for clients:
      - base data from /me/overview
      - recent payments of the primary wallet (if available)
    """
    if tx_limit <= 0:
        tx_limit = 10
    tx_limit = min(tx_limit, 50)

    overview = await me_overview(request)
    wallet_id = None
    try:
        wallet_id = overview.get("wallet_id")  # type: ignore[assignment]
        if not wallet_id and isinstance(overview.get("wallet"), dict):
            w = overview.get("wallet") or {}
            if isinstance(w, dict):
                wallet_id = (w.get("wallet_id") or w.get("id"))  # type: ignore[assignment]
    except Exception:
        wallet_id = None

    txns: Any = []
    tx_error: str | None = None
    if wallet_id:
        try:
            txns = payments_txns(wallet_id=str(wallet_id), limit=tx_limit, request=request)
        except HTTPException:
            raise
        except Exception as e:
            tx_error = str(e)

    overview["txns"] = txns
    if tx_error:
        overview["txns_error"] = tx_error
    return overview


@app.get("/me/home_snapshot")
async def me_home_snapshot(request: Request, response: Response = None):  # type: ignore[assignment]
    """
    Aggregated snapshot for the home screen:
      - base: /me/dashboard (phone, roles, wallet, recent payments)
      - flags: is_admin, is_superadmin, operator_domains
      - operator KPIs: Bus summary (if operator/admin)
    """
    snapshot: dict[str, Any] = {}
    base = await me_dashboard(request)
    snapshot.update(base)

    phone = _auth_phone(request)
    roles = base.get("roles") or []
    if not isinstance(roles, list):
        roles = []
    snapshot["roles"] = roles

    snapshot["is_admin"] = False
    snapshot["is_superadmin"] = False
    snapshot["operator_domains"] = []

    if phone:
        try:
            snapshot["is_admin"] = _is_admin(phone)
        except Exception:
            snapshot["is_admin"] = False
        try:
            snapshot["is_superadmin"] = _is_superadmin(phone)
        except Exception:
            snapshot["is_superadmin"] = False
        # Determine operator domains
        op_domains: list[str] = []
        for dom in ("bus",):
            try:
                if _is_operator(phone, dom):
                    op_domains.append(dom)
            except Exception:
                continue
        snapshot["operator_domains"] = op_domains
        # Optionally add operator KPIs (best-effort)
        if "bus" in op_domains:
            try:
                snapshot["bus_admin_summary"] = bus_admin_summary(request)
            except HTTPException:
                raise
            except Exception as e:
                snapshot["bus_admin_summary_error"] = str(e)

    # Home screen snapshot is user-specific; mark it explicitly as non-cacheable.
    try:
        if response is not None:
            response.headers.setdefault("Cache-Control", "no-store")
    except Exception:
        pass
    return snapshot


@app.get("/me/journey_snapshot")
async def me_journey_snapshot(request: Request, response: Response = None):  # type: ignore[assignment]
    """
    Aggregated "journey" snapshot for the home screen:
      - base: /me/home_snapshot (phone, roles, wallet, KPIs)
      - mobility history: most recent Bus rides via /me/mobility_history
      - missing parts are best-effort and returned as empty lists/fields.
    """
    try:
        base = await me_home_snapshot(request, response=response)
        journey: dict[str, Any] = {"home": base}

        # Mobility history (existing handler)
        try:
            mobility = me_mobility_history(request)  # type: ignore[assignment]
        except HTTPException:
            raise
        except Exception as e:
            mobility = {"error": str(e)}
        journey["mobility_history"] = mobility

        return journey
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/me/bus_history")
def me_bus_history(request: Request, status: str = "", limit: int = 50, response: Response = None):  # type: ignore[assignment]
    """
    Aggregated bus booking history for the logged-in user.

    Uses the existing bus booking search and then filters for
    customer_phone == own phone number. Status filter is optional.
    """
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    limit = max(1, min(limit, 200))
    status = (status or "").strip()
    try:
        raw = bus_booking_search(wallet_id=None, phone=phone, limit=limit * 2)
        items: list[Any] = []
        if isinstance(raw, list):
            for it in raw:
                try:
                    customer_phone = ""
                    current_status = ""
                    if isinstance(it, dict):
                        customer_phone = (str(it.get("customer_phone") or "")).strip()
                        current_status = (str(it.get("status") or "")).strip()
                    else:
                        customer_phone = (str(getattr(it, "customer_phone", "") or "")).strip()
                        current_status = (str(getattr(it, "status", "") or "")).strip()
                except Exception:
                    continue
                if customer_phone != phone:
                    continue
                if status and current_status != status:
                    continue
                items.append(it)
        out = items[:limit]
        try:
            if response is not None:
                response.headers.setdefault("Cache-Control", "no-store")
        except Exception:
            pass
        return out
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/me/mobility_history")
def me_mobility_history(
    request: Request,
    status: str = "",
    limit: int = 50,
    response: Response = None,  # type: ignore[assignment]
):
    """
    Combined mobility history for the logged-in user (bus only).

    This endpoint remains as a single place for mobility history in clients.
    """
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")

    limit = max(1, min(limit, 200))
    bus_items: list[dict[str, Any]] = []
    try:
        try:
            bus_items = me_bus_history(request, status=status, limit=limit)  # type: ignore[assignment]
        except HTTPException:
            raise
        except Exception as e:
            bus_items = [{"error": str(e)}]
        out = {"bus": bus_items}
        # Personalisierte Mobility-Historie sollte nicht gecacht werden.
        try:
            if response is not None:
                response.headers.setdefault("Cache-Control", "no-store")
        except Exception:
            pass
        return out
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/auth/logout")
def auth_logout(request: Request):
    # Best-effort session revocation (defense-in-depth).
    try:
        sid = None
        try:
            raw = request.headers.get("sa_cookie") or request.headers.get("Sa-Cookie")
            if raw:
                sid = _normalize_session_token(raw)
        except Exception:
            sid = None
        if not sid:
            try:
                sid = _normalize_session_token(request.cookies.get("sa_session"))
            except Exception:
                sid = None
        if sid:
            try:
                _SESSIONS.pop(sid, None)
            except Exception:
                pass
            try:
                with _officials_session() as s:  # type: ignore[name-defined]
                    s.execute(
                        _sa_delete(AuthSessionDB).where(AuthSessionDB.sid_hash == _sha256_hex(sid))  # type: ignore[name-defined]
                    )
                    s.commit()
            except Exception:
                # Logout must never break normal flows.
                pass
    except Exception:
        # Logout must never break normal flows.
        pass
    resp = JSONResponse({"ok": True})
    resp.delete_cookie("sa_session", path="/")
    return resp


@app.get("/auth/device_login_demo", response_class=HTMLResponse)
def device_login_demo() -> HTMLResponse:
    """
    Simple HTML demo page for the QR-based device login flow.
    Renders a QR code with a one-time device_login token and polls
    the backend until the phone approves the login.
    """
    # Never expose demo auth surfaces in prod/staging (attack-surface reduction).
    if (os.getenv("ENV") or "dev").strip().lower() in ("prod", "production", "staging"):
        raise HTTPException(status_code=404, detail="Not Found")
    return _html_template_response("device_login_demo.html")

# --- Simple admin: block/unblock phones by number (in-memory) ---
@app.post("/admin/block_phone")
async def admin_block_phone(req: Request):
    """
    Emergency login denial for a specific phone number.

    Best practice: superadmin-only, because this effectively prevents account
    access (DoS/abuse potential).

    Note: This blocklist is in-memory (best-effort). For durable enforcement
    use the Payments risk deny list.
    """
    _require_superadmin(req)
    try:
        body = await req.json()
        phone = (body.get("phone") or "").strip()
    except Exception:
        raise HTTPException(status_code=400, detail="invalid body")
    if not phone:
        raise HTTPException(status_code=400, detail="phone required")
    phone_norm = _normalize_phone_e164(phone)
    if not phone_norm:
        raise HTTPException(status_code=400, detail="invalid phone")
    phone = phone_norm
    _BLOCKED_PHONES.add(phone)
    _audit_from_request(req, "admin_block_phone", target_phone=phone)
    return {"ok": True, "phone": phone, "blocked": True}


@app.post("/admin/unblock_phone")
async def admin_unblock_phone(req: Request):
    _require_superadmin(req)
    try:
        body = await req.json()
        phone = (body.get("phone") or "").strip()
    except Exception:
        raise HTTPException(status_code=400, detail="invalid body")
    if not phone:
        raise HTTPException(status_code=400, detail="phone required")
    phone_norm = _normalize_phone_e164(phone)
    if not phone_norm:
        raise HTTPException(status_code=400, detail="invalid phone")
    phone = phone_norm
    try:
        _BLOCKED_PHONES.discard(phone)
    except Exception:
        pass
    _audit_from_request(req, "admin_unblock_phone", target_phone=phone)
    return {"ok": True, "phone": phone, "blocked": False}


# Legacy aliases (kept only for dev/test). Removed in prod/staging to reduce attack surface.
@app.post("/admin/block_driver")
async def admin_block_driver(req: Request):
    env_name = (os.getenv("ENV") or "dev").strip().lower()
    if env_name in ("prod", "production", "staging"):
        raise HTTPException(status_code=404, detail="Not Found")
    return await admin_block_phone(req)


@app.post("/admin/unblock_driver")
async def admin_unblock_driver(req: Request):
    env_name = (os.getenv("ENV") or "dev").strip().lower()
    if env_name in ("prod", "production", "staging"):
        raise HTTPException(status_code=404, detail="Not Found")
    return await admin_unblock_phone(req)

@app.get("/login", response_class=HTMLResponse)
def login_page() -> HTMLResponse:
    # Browser login page is no longer actively used.
    # Shamell provides the full login/dashboard UI.
    return _legacy_console_removed_page("Shamell Login")

@app.get("/home", response_class=HTMLResponse)
def home_page(request: Request):
    # Legacy HTML start page removed: always redirect to modern shell or login.
    if not _auth_phone(request):
        return RedirectResponse(url="/login", status_code=303)
    return RedirectResponse(url="/app", status_code=303)


@app.get("/", response_class=HTMLResponse)
def root_redirect(request: Request):
    # If authenticated, send to modern app shell; else to login
    if _auth_phone(request):
        return RedirectResponse(url="/app", status_code=303)
    return RedirectResponse(url="/login", status_code=303)


@app.get("/app", response_class=HTMLResponse)
def app_shell(request: Request) -> HTMLResponse:
    # Previously: large mixed SuperApp HTML console.
    # Now: BFF only exposes APIs; UI is Shamell.
    if not _auth_phone(request):
        return RedirectResponse(url="/login", status_code=303)
    return _legacy_console_removed_page("Shamell BFF")

@app.get("/upstreams/health")
def upstreams_health(request: Request):
    """
    Minimal upstream health map for the currently supported domains.

    Best practice: keep this endpoint side-effect free. In tests we never
    attempt internal wiring to avoid bootstrapping extra DB state.
    """
    # Ops endpoints should not be publicly enumerable in prod/staging.
    env_name = (os.getenv("ENV") or "dev").strip().lower()
    if env_name in ("prod", "production", "staging"):
        phone = _auth_phone(request)
        if not phone or not _is_admin(phone):
            raise HTTPException(status_code=404, detail="Not Found")
    out: dict[str, Any] = {}

    def _health_http(name: str, base: str) -> None:
        if not base:
            out[name] = {"error": "BASE_URL not set", "mode": "missing", "internal": False}
            return
        url = base.rstrip("/") + "/health"
        try:
            r = httpx.get(url, timeout=5.0)
            try:
                if r.headers.get("content-type", "").startswith("application/json"):
                    body: Any = r.json()
                else:
                    body = r.text
            except Exception:
                body = getattr(r, "text", "")
            out[name] = {"status_code": r.status_code, "body": body, "mode": "http", "internal": False}
        except Exception as e:
            out[name] = {"error": str(e), "mode": "http", "internal": False}

    # Payments
    if _ENV_LOWER != "test" and _use_pay_internal() and _PAY_INTERNAL_AVAILABLE:
        out["payments"] = {"status_code": 200, "body": {"status": "OK (internal)"}, "mode": "internal", "internal": True}
    else:
        _health_http("payments", PAYMENTS_BASE)

    # Bus
    if _ENV_LOWER != "test" and _use_bus_internal() and _BUS_INTERNAL_AVAILABLE:
        out["bus"] = {"status_code": 200, "body": {"status": "OK (internal)"}, "mode": "internal", "internal": True}
    else:
        _health_http("bus", BUS_BASE)

    # Chat
    if _ENV_LOWER != "test" and _use_chat_internal() and _CHAT_INTERNAL_AVAILABLE:
        out["chat"] = {"status_code": 200, "body": {"status": "OK (internal)"}, "mode": "internal", "internal": True}
    else:
        _health_http("chat", CHAT_BASE)

    # LiveKit is an external integration; only report config state (never secrets).
    out["livekit"] = {
        "configured": bool(LIVEKIT_PUBLIC_URL and LIVEKIT_API_KEY and LIVEKIT_API_SECRET),
        "url": LIVEKIT_PUBLIC_URL or None,
        "mode": "config",
    }

    return out


@app.get("/admin/overview", response_class=HTMLResponse)
def admin_overview_page():
    # Legacy Admin HTML overview removed – please use Shamell instead.
    return _legacy_console_removed_page("Shamell · Admin overview")

@app.get("/wallets/{wallet_id}")
def get_wallet(wallet_id: str, request: Request):
    # Wallet lookups contain sensitive financial data. Require auth and enforce
    # wallet ownership (or admin) to prevent IDOR.
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    wallet_id = (wallet_id or "").strip()
    caller_wallet_id = _resolve_wallet_id_for_phone(phone)
    if caller_wallet_id:
        if wallet_id != caller_wallet_id and not _is_admin(phone):
            raise HTTPException(status_code=403, detail="wallet does not belong to caller")
    else:
        # If we cannot resolve the caller wallet we still allow admins to proceed.
        if not _is_admin(phone):
            raise HTTPException(status_code=403, detail="wallet not found for caller")
    try:
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            try:
                with _pay_internal_session() as s:
                    return _pay_get_wallet(wallet_id=wallet_id, s=s)
            except HTTPException:
                raise
            except Exception as e:
                raise HTTPException(status_code=502, detail=str(e))
        if not PAYMENTS_BASE:
            raise HTTPException(status_code=500, detail="PAYMENTS_BASE_URL not configured")
        url = PAYMENTS_BASE.rstrip("/") + f"/wallets/{wallet_id}"
        r = httpx.get(url, headers=_payments_headers(), timeout=5.0)
        return r.json() if r.headers.get("content-type", "").startswith("application/json") else {"raw": r.text, "status_code": r.status_code}
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/wallets/{wallet_id}/snapshot")
def wallet_snapshot(
    wallet_id: str,
    request: Request,
    limit: int = 25,
    dir: str = "",
    kind: str = "",
    from_iso: str = "",
    to_iso: str = "",
    response: Response = None,  # type: ignore[assignment]
):
    """
    Aggregate for wallet overviews:
      - wallet object (get_wallet)
      - list of recent payments (payments_txns)
    """
    # Load wallet (surface errors in the snapshot best-effort)
    wallet: Any = None
    wallet_error: str | None = None
    wallet_status: int | None = None
    try:
        wallet = get_wallet(wallet_id, request=request)
    except HTTPException as e:
        wallet_error = str(e.detail)
        wallet_status = e.status_code
    except Exception as e:
        wallet_error = str(e)

    # Fetch transactions (errors should be clearly signalled)
    txns: Any = []
    try:
        txns = payments_txns(
            wallet_id=wallet_id,
            limit=limit,
            dir=dir,
            kind=kind,
            from_iso=from_iso,
            to_iso=to_iso,
            request=request,
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))

    out: dict[str, Any] = {"wallet_id": wallet_id, "wallet": wallet, "txns": txns}
    if wallet_error:
        out["wallet_error"] = wallet_error
        if wallet_status is not None:
            out["wallet_status"] = wallet_status
    # Wallet snapshots contain sensitive financial data; mark them explicitly
    # as non-cacheable so intermediaries and browsers do not reuse responses.
    try:
        if response is not None:
            response.headers.setdefault("Cache-Control", "no-store")
    except Exception:
        pass
    return out

from datetime import datetime, timezone, timedelta


@app.get("/payments/txns")
def payments_txns(
    wallet_id: str,
    request: Request = None,  # type: ignore[assignment]
    limit: int = 20,
    dir: str = "",
    kind: str = "",
    from_iso: str = "",
    to_iso: str = "",
):
    wallet_id = (wallet_id or "").strip()
    # Transaction lists are sensitive; require auth and enforce wallet ownership (or admin),
    # but allow internal callers (unit tests / in-process aggregation) to call without a Request.
    if request is not None:
        phone = _auth_phone(request)
        if not phone:
            raise HTTPException(status_code=401, detail="unauthorized")
        caller_wallet_id = _resolve_wallet_id_for_phone(phone)
        if caller_wallet_id:
            if wallet_id != caller_wallet_id and not _is_admin(phone):
                raise HTTPException(status_code=403, detail="wallet does not belong to caller")
        else:
            # If we cannot resolve the caller wallet we still allow admins to proceed.
            if not _is_admin(phone):
                raise HTTPException(status_code=403, detail="wallet not found for caller")
    try:
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            try:
                with _pay_internal_session() as s:
                    # Internal list, then apply filtering as before
                    arr = _pay_list_txns(wallet_id=wallet_id, limit=max(1, min(limit * 5, 500)), s=s)  # type: ignore[name-defined]
                    # list_txns already filters by wallet_id; we keep the additional filtering for compatible behaviour
                    arr = [t.model_dump() if hasattr(t, "model_dump") else (t.dict() if hasattr(t, "dict") else t) for t in arr]  # type: ignore[union-attr]
            except HTTPException:
                raise
            except Exception as e:
                raise HTTPException(status_code=502, detail=str(e))
        else:
            if not PAYMENTS_BASE:
                raise HTTPException(status_code=500, detail="PAYMENTS_BASE_URL not configured")
            url = PAYMENTS_BASE.rstrip("/") + f"/txns?wallet_id={wallet_id}&limit={max(1,min(limit*5,500))}"
            r = httpx.get(url, headers=_payments_headers(), timeout=10.0)
            arr = r.json() if r.headers.get("content-type", "").startswith("application/json") else []
        # server-side filtering (best-effort)
        def in_range(ts: str) -> bool:
            try:
                dt = datetime.fromisoformat(ts.replace('Z','+00:00'))
            except Exception:
                return True
            if from_iso:
                try:
                    f = datetime.fromisoformat(from_iso.replace('Z','+00:00'))
                    if dt < f: return False
                except Exception:
                    pass
            if to_iso:
                try:
                    t = datetime.fromisoformat(to_iso.replace('Z','+00:00'))
                    if dt > t: return False
                except Exception:
                    pass
            return True
        out = []
        dir = (dir or '').lower()
        kind = (kind or '').lower()
        for it in arr:
            try:
                row = it
                if not isinstance(row, dict):
                    # Pydantic/BaseModel -> dict
                    try:
                        row = it.model_dump()  # type: ignore[attr-defined]
                    except Exception:
                        try:
                            row = it.dict()  # type: ignore[attr-defined]
                        except Exception:
                            row = {}
                if dir == 'out' and (row.get('from_wallet_id','') != wallet_id):
                    continue
                if dir == 'in' and (row.get('to_wallet_id','') != wallet_id):
                    continue
                if kind and kind not in str(row.get('kind','')).lower():
                    continue
                if not in_range(str(row.get('created_at',''))):
                    continue
                out.append(row)
            except Exception:
                out.append(it)
        return out[:max(1,min(limit,200))]
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


# ---- Chat proxies ----
def _chat_url(path: str) -> str:
    if not CHAT_BASE:
        raise HTTPException(status_code=500, detail="CHAT_BASE_URL not configured")
    return CHAT_BASE.rstrip("/") + path


# --- Chat internal service (internal mode) ---
_CHAT_INTERNAL_AVAILABLE = False
try:
    from sqlalchemy.orm import Session as _ChatSession  # type: ignore[import]
    from apps.chat.app import main as _chat_main  # type: ignore[import]
    from apps.chat.app.main import (  # type: ignore[import]
        engine as _chat_engine,
        get_session as _chat_get_session,
        RegisterReq as _ChatRegisterReq,
        DeviceOut as _ChatDeviceOut,
        SendReq as _ChatSendReq,
        MsgOut as _ChatMsgOut,
        ReadReq as _ChatReadReq,
        PushTokenReq as _ChatPushTokenReq,
        ContactRuleReq as _ChatRuleReq,
        ContactPrefsReq as _ChatContactPrefsReq,
        GroupCreateReq as _ChatGroupCreateReq,
        GroupOut as _ChatGroupOut,
        GroupSendReq as _ChatGroupSendReq,
        GroupMsgOut as _ChatGroupMsgOut,
        GroupInviteReq as _ChatGroupInviteReq,
        GroupLeaveReq as _ChatGroupLeaveReq,
        GroupRoleReq as _ChatGroupRoleReq,
        GroupUpdateReq as _ChatGroupUpdateReq,
        GroupMemberOut as _ChatGroupMemberOut,
        GroupPrefsReq as _ChatGroupPrefsReq,
        GroupPrefsOut as _ChatGroupPrefsOut,
        GroupKeyRotateReq as _ChatGroupKeyRotateReq,
        GroupKeyEventOut as _ChatGroupKeyEventOut,
        register as _chat_register,
        get_device as _chat_get_device,
        send_message as _chat_send_message,
        inbox as _chat_inbox,
        mark_read as _chat_mark_read,
        register_push_token as _chat_register_push,
        set_block as _chat_set_block,
        set_prefs as _chat_set_prefs,
        list_prefs as _chat_list_prefs,
        create_group as _chat_create_group,
        list_groups as _chat_list_groups,
        send_group_message as _chat_send_group_message,
        group_inbox as _chat_group_inbox,
        group_members as _chat_group_members,
        invite_members as _chat_invite_members,
        leave_group as _chat_leave_group,
        set_group_role as _chat_set_group_role,
        update_group as _chat_update_group,
        set_group_prefs as _chat_set_group_prefs,
        list_group_prefs as _chat_list_group_prefs,
        rotate_group_key as _chat_rotate_group_key,
        list_key_events as _chat_list_key_events,
    )
    _CHAT_INTERNAL_AVAILABLE = True
except Exception:
    _ChatSession = None  # type: ignore[assignment]
    _chat_main = None  # type: ignore[assignment]
    _chat_engine = None  # type: ignore[assignment]
    _CHAT_INTERNAL_AVAILABLE = False


_CHAT_INTERNAL_BOOTSTRAPPED = False


def _use_chat_internal() -> bool:
    if _force_internal(_CHAT_INTERNAL_AVAILABLE):
        return True
    mode = os.getenv("CHAT_INTERNAL_MODE", "auto").lower()
    if mode == "off":
        return False
    if not _CHAT_INTERNAL_AVAILABLE:
        return False
    if mode == "on":
        return True
    # auto: allow fallback to internal only in dev/test. In prod/staging we
    # fail closed so missing CHAT_BASE_URL does not silently enable internal mode.
    env_name = (os.getenv("ENV") or "dev").strip().lower()
    if env_name in ("prod", "production", "staging"):
        return False
    return not bool(CHAT_BASE)


def _chat_internal_session():
    global _CHAT_INTERNAL_BOOTSTRAPPED
    if not _CHAT_INTERNAL_AVAILABLE or _ChatSession is None or _chat_engine is None:  # type: ignore[truthy-function]
        raise RuntimeError("Chat internal service not available")
    # Lazy bootstrap: avoid creating Chat tables in the BFF DB unless we are
    # actually running in internal mode (single-process).
    if not _CHAT_INTERNAL_BOOTSTRAPPED:
        try:
            if _use_chat_internal() and _chat_main is not None and hasattr(_chat_main, "_startup"):
                _chat_main._startup()  # type: ignore[attr-defined]
        except Exception:
            pass
        _CHAT_INTERNAL_BOOTSTRAPPED = True
    return _ChatSession(_chat_engine)  # type: ignore[call-arg]


def _chat_auth_headers_from_request(request: Request) -> Dict[str, str]:
    did = (
        request.headers.get("X-Chat-Device-Id")
        or request.headers.get("x-chat-device-id")
        or ""
    ).strip()
    tok = (
        request.headers.get("X-Chat-Device-Token")
        or request.headers.get("x-chat-device-token")
        or ""
    ).strip()
    headers: Dict[str, str] = {}
    if did:
        headers["X-Chat-Device-Id"] = did
    if tok:
        headers["X-Chat-Device-Token"] = tok
    if INTERNAL_API_SECRET:
        headers["X-Internal-Secret"] = INTERNAL_API_SECRET
    return headers


def _chat_auth_headers_from_ws(ws: WebSocket) -> Dict[str, str]:
    did = (
        ws.headers.get("X-Chat-Device-Id")
        or ws.headers.get("x-chat-device-id")
        or ws.query_params.get("chat_device_id")
        or ws.query_params.get("device_id")
        or ""
    ).strip()
    tok = (
        ws.headers.get("X-Chat-Device-Token")
        or ws.headers.get("x-chat-device-token")
        or ws.query_params.get("chat_device_token")
        or ""
    ).strip()
    headers: Dict[str, str] = {}
    if did:
        headers["X-Chat-Device-Id"] = did
    if tok:
        headers["X-Chat-Device-Token"] = tok
    if INTERNAL_API_SECRET:
        headers["X-Internal-Secret"] = INTERNAL_API_SECRET
    return headers


@app.post("/chat/devices/register")
async def chat_register(req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        did = ""
        if isinstance(body, dict):
            did = str(body.get("device_id") or "").strip()
        _rate_limit_chat_edge(
            req,
            device_id=did or None,
            scope="chat_register",
            device_max=0,
            ip_max=CHAT_REGISTER_MAX_PER_IP,
        )
    except HTTPException:
        raise
    except Exception:
        # Rate limiting must never hard-break chat flows.
        pass
    try:
        if _use_chat_internal():
            if not _CHAT_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="chat internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                creq = _ChatRegisterReq(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _chat_internal_session() as s:
                return _chat_register(request=req, req=creq, s=s)
        r = httpx.post(
            _chat_url("/devices/register"),
            json=body,
            headers=_chat_auth_headers_from_request(req),
            timeout=10,
        )
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/chat/devices/{device_id}")
def chat_get_device(device_id: str, request: Request):
    try:
        if _use_chat_internal():
            if not _CHAT_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="chat internal not available")
            with _chat_internal_session() as s:
                return _chat_get_device(device_id=device_id, s=s)
        r = httpx.get(
            _chat_url(f"/devices/{device_id}"),
            headers=_chat_auth_headers_from_request(request),
            timeout=10,
        )
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/chat/devices/{device_id}/push_token")
async def chat_push_token(device_id: str, req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        if _use_chat_internal():
            if not _CHAT_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="chat internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                preq = _ChatPushTokenReq(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _chat_internal_session() as s:
                return _chat_register_push(device_id=device_id, request=req, req=preq, s=s)  # type: ignore[arg-type]
        r = httpx.post(
            _chat_url(f"/devices/{device_id}/push_token"),
            json=body,
            headers=_chat_auth_headers_from_request(req),
            timeout=10,
        )
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/chat/devices/{device_id}/block")
async def chat_block(device_id: str, req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        if _use_chat_internal():
            if not _CHAT_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="chat internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                breq = _ChatRuleReq(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _chat_internal_session() as s:
                return _chat_set_block(device_id=device_id, request=req, req=breq, s=s)  # type: ignore[arg-type]
        r = httpx.post(
            _chat_url(f"/devices/{device_id}/block"),
            json=body,
            headers=_chat_auth_headers_from_request(req),
            timeout=10,
        )
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/chat/devices/{device_id}/prefs")
async def chat_prefs(device_id: str, req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        if _use_chat_internal():
            if not _CHAT_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="chat internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                preq = _ChatContactPrefsReq(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _chat_internal_session() as s:
                return _chat_set_prefs(device_id=device_id, request=req, req=preq, s=s)  # type: ignore[arg-type]
        r = httpx.post(
            _chat_url(f"/devices/{device_id}/prefs"),
            json=body,
            headers=_chat_auth_headers_from_request(req),
            timeout=10,
        )
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/chat/devices/{device_id}/prefs")
def chat_list_prefs(device_id: str, request: Request):
    try:
        if _use_chat_internal():
            if not _CHAT_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="chat internal not available")
            with _chat_internal_session() as s:
                return _chat_list_prefs(device_id=device_id, request=request, s=s)  # type: ignore[arg-type]
        r = httpx.get(
            _chat_url(f"/devices/{device_id}/prefs"),
            headers=_chat_auth_headers_from_request(request),
            timeout=10,
        )
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/chat/devices/{device_id}/group_prefs")
async def chat_group_prefs(device_id: str, req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        if _use_chat_internal():
            if not _CHAT_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="chat internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                preq = _ChatGroupPrefsReq(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _chat_internal_session() as s:
                return _chat_set_group_prefs(device_id=device_id, request=req, req=preq, s=s)  # type: ignore[arg-type]
        r = httpx.post(
            _chat_url(f"/devices/{device_id}/group_prefs"),
            json=body,
            headers=_chat_auth_headers_from_request(req),
            timeout=10,
        )
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/chat/devices/{device_id}/group_prefs")
def chat_list_group_prefs(device_id: str, request: Request):
    try:
        if _use_chat_internal():
            if not _CHAT_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="chat internal not available")
            with _chat_internal_session() as s:
                return _chat_list_group_prefs(device_id=device_id, request=request, s=s)  # type: ignore[arg-type]
        r = httpx.get(
            _chat_url(f"/devices/{device_id}/group_prefs"),
            headers=_chat_auth_headers_from_request(request),
            timeout=10,
        )
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/chat/messages/send")
async def chat_send(req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        sender = ""
        if isinstance(body, dict):
            sender = str(body.get("sender_id") or "").strip()
        _rate_limit_chat_edge(
            req,
            device_id=sender or None,
            scope="chat_send",
            device_max=CHAT_SEND_MAX_PER_DEVICE,
            ip_max=CHAT_SEND_MAX_PER_IP,
        )
    except HTTPException:
        raise
    except Exception:
        pass
    try:
        if _use_chat_internal():
            if not _CHAT_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="chat internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                sreq = _ChatSendReq(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _chat_internal_session() as s:
                msg = _chat_send_message(request=req, req=sreq, s=s)
            try:
                _update_official_service_session_on_message(
                    getattr(msg, "sender_id", None),
                    getattr(msg, "recipient_id", None),
                    getattr(msg, "created_at", None),
                )
            except Exception:
                pass
            try:
                emit_event(
                    "chat",
                    "message_sent",
                    {
                        "id": getattr(msg, "id", None),
                        "sender_id": getattr(msg, "sender_id", None),
                        "recipient_id": getattr(msg, "recipient_id", None),
                        "created_at": getattr(msg, "created_at", None),
                    },
                )
            except Exception:
                pass
            return msg
        r = httpx.post(
            _chat_url("/messages/send"),
            json=body,
            headers=_chat_auth_headers_from_request(req),
            timeout=10,
        )
        out = r.json()
        try:
            _update_official_service_session_on_message(
                out.get("sender_id"),
                out.get("recipient_id"),
                out.get("created_at"),
            )
        except Exception:
            pass
        try:
            payload = {
                "id": out.get("id"),
                "sender_id": out.get("sender_id"),
                "recipient_id": out.get("recipient_id"),
                "created_at": out.get("created_at"),
            }
            emit_event("chat", "message_sent", payload)
        except Exception:
            pass
        return out
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/chat/messages/inbox")
def chat_inbox(device_id: str, request: Request, since_iso: str = "", limit: int = 50):
    params = {"device_id": device_id, "limit": max(1, min(limit, 200))}
    if since_iso:
        params["since_iso"] = since_iso
    try:
        if _use_chat_internal():
            if not _CHAT_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="chat internal not available")
            with _chat_internal_session() as s:
                sin = since_iso or None
                return _chat_inbox(request=request, device_id=device_id, since_iso=sin, limit=limit, s=s)
        r = httpx.get(
            _chat_url("/messages/inbox"),
            params=params,
            headers=_chat_auth_headers_from_request(request),
            timeout=10,
        )
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/chat/messages/{mid}/read")
async def chat_mark_read(mid: str, req: Request):
    try:
        body = await req.json()
    except Exception:
        body = {"read": True}
    try:
        if _use_chat_internal():
            if not _CHAT_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="chat internal not available")
            data = body or {"read": True}
            if not isinstance(data, dict):
                data = {"read": True}
            try:
                rreq = _ChatReadReq(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _chat_internal_session() as s:
                return _chat_mark_read(mid=mid, request=req, req=rreq, s=s)
        r = httpx.post(
            _chat_url(f"/messages/{mid}/read"),
            json=body,
            headers=_chat_auth_headers_from_request(req),
            timeout=10,
        )
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/chat/groups/create")
async def chat_group_create(req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        if _use_chat_internal():
            if not _CHAT_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="chat internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                greq = _ChatGroupCreateReq(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _chat_internal_session() as s:
                return _chat_create_group(request=req, req=greq, s=s)  # type: ignore[arg-type]
        r = httpx.post(
            _chat_url("/groups/create"),
            json=body,
            headers=_chat_auth_headers_from_request(req),
            timeout=10,
        )
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/chat/groups/list")
def chat_group_list(device_id: str, request: Request):
    try:
        if _use_chat_internal():
            if not _CHAT_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="chat internal not available")
            with _chat_internal_session() as s:
                return _chat_list_groups(request=request, device_id=device_id, s=s)
        r = httpx.get(
            _chat_url("/groups/list"),
            params={"device_id": device_id},
            headers=_chat_auth_headers_from_request(request),
            timeout=10,
        )
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/chat/groups/{group_id}/update")
async def chat_group_update(group_id: str, req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        if _use_chat_internal():
            if not _CHAT_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="chat internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                ureq = _ChatGroupUpdateReq(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _chat_internal_session() as s:
                return _chat_update_group(group_id=group_id, request=req, req=ureq, s=s)  # type: ignore[arg-type]
        r = httpx.post(
            _chat_url(f"/groups/{group_id}/update"),
            json=body,
            headers=_chat_auth_headers_from_request(req),
            timeout=10,
        )
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/chat/groups/{group_id}/messages/send")
async def chat_group_send(group_id: str, req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        sender = ""
        if isinstance(body, dict):
            sender = str(body.get("sender_id") or "").strip()
        _rate_limit_chat_edge(
            req,
            device_id=sender or None,
            scope="chat_group_send",
            device_max=CHAT_SEND_MAX_PER_DEVICE,
            ip_max=CHAT_SEND_MAX_PER_IP,
        )
    except HTTPException:
        raise
    except Exception:
        pass
    try:
        if _use_chat_internal():
            if not _CHAT_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="chat internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                sreq = _ChatGroupSendReq(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _chat_internal_session() as s:
                return _chat_send_group_message(group_id=group_id, request=req, req=sreq, s=s)  # type: ignore[arg-type]
        r = httpx.post(
            _chat_url(f"/groups/{group_id}/messages/send"),
            json=body,
            headers=_chat_auth_headers_from_request(req),
            timeout=10,
        )
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/chat/groups/{group_id}/messages/inbox")
def chat_group_inbox(group_id: str, device_id: str, request: Request, since_iso: str = "", limit: int = 50):
    params = {"device_id": device_id, "limit": max(1, min(limit, 200))}
    if since_iso:
        params["since_iso"] = since_iso
    try:
        if _use_chat_internal():
            if not _CHAT_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="chat internal not available")
            with _chat_internal_session() as s:
                sin = since_iso or None
                return _chat_group_inbox(group_id=group_id, request=request, device_id=device_id, since_iso=sin, limit=limit, s=s)  # type: ignore[arg-type]
        r = httpx.get(
            _chat_url(f"/groups/{group_id}/messages/inbox"),
            params=params,
            headers=_chat_auth_headers_from_request(request),
            timeout=10,
        )
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/chat/groups/{group_id}/members")
def chat_group_members(group_id: str, device_id: str, request: Request):
    params = {"device_id": device_id}
    try:
        if _use_chat_internal():
            if not _CHAT_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="chat internal not available")
            with _chat_internal_session() as s:
                return _chat_group_members(group_id=group_id, request=request, device_id=device_id, s=s)
        r = httpx.get(
            _chat_url(f"/groups/{group_id}/members"),
            params=params,
            headers=_chat_auth_headers_from_request(request),
            timeout=10,
        )
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/chat/groups/{group_id}/invite")
async def chat_group_invite(group_id: str, req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        if _use_chat_internal():
            if not _CHAT_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="chat internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                ireq = _ChatGroupInviteReq(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _chat_internal_session() as s:
                return _chat_invite_members(group_id=group_id, request=req, req=ireq, s=s)  # type: ignore[arg-type]
        r = httpx.post(
            _chat_url(f"/groups/{group_id}/invite"),
            json=body,
            headers=_chat_auth_headers_from_request(req),
            timeout=10,
        )
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/chat/groups/{group_id}/leave")
async def chat_group_leave(group_id: str, req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        if _use_chat_internal():
            if not _CHAT_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="chat internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                lreq = _ChatGroupLeaveReq(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _chat_internal_session() as s:
                return _chat_leave_group(group_id=group_id, request=req, req=lreq, s=s)  # type: ignore[arg-type]
        r = httpx.post(
            _chat_url(f"/groups/{group_id}/leave"),
            json=body,
            headers=_chat_auth_headers_from_request(req),
            timeout=10,
        )
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/chat/groups/{group_id}/set_role")
async def chat_group_set_role(group_id: str, req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        if _use_chat_internal():
            if not _CHAT_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="chat internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                rreq = _ChatGroupRoleReq(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _chat_internal_session() as s:
                return _chat_set_group_role(group_id=group_id, request=req, req=rreq, s=s)  # type: ignore[arg-type]
        r = httpx.post(
            _chat_url(f"/groups/{group_id}/set_role"),
            json=body,
            headers=_chat_auth_headers_from_request(req),
            timeout=10,
        )
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/chat/groups/{group_id}/keys/rotate")
async def chat_group_rotate_key(group_id: str, req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        if _use_chat_internal():
            if not _CHAT_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="chat internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                rreq = _ChatGroupKeyRotateReq(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _chat_internal_session() as s:
                return _chat_rotate_group_key(group_id=group_id, request=req, req=rreq, s=s)  # type: ignore[arg-type]
        r = httpx.post(
            _chat_url(f"/groups/{group_id}/keys/rotate"),
            json=body,
            headers=_chat_auth_headers_from_request(req),
            timeout=10,
        )
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/chat/groups/{group_id}/keys/events")
def chat_group_key_events(group_id: str, device_id: str, request: Request, limit: int = 20):
    params = {"device_id": device_id, "limit": max(1, min(limit, 200))}
    try:
        if _use_chat_internal():
            if not _CHAT_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="chat internal not available")
            with _chat_internal_session() as s:
                return _chat_list_key_events(group_id=group_id, request=request, device_id=device_id, limit=limit, s=s)  # type: ignore[arg-type]
        r = httpx.get(
            _chat_url(f"/groups/{group_id}/keys/events"),
            params=params,
            headers=_chat_auth_headers_from_request(request),
            timeout=10,
        )
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.websocket("/ws/chat/inbox")
async def chat_inbox_ws(ws: WebSocket):
    await ws.accept()
    try:
        params = dict(ws.query_params)
        chat_headers = _chat_auth_headers_from_ws(ws)
        did = params.get("device_id") or chat_headers.get("X-Chat-Device-Id")
        guard = await _chat_ws_guard_enter(ws, device_id=str(did or ""))
        if guard is None:
            return
        g_ip, g_dev = guard
        since_iso = params.get("since_iso") or ""
        last_iso = since_iso
        try:
            while True:
                try:
                    if _use_chat_internal():
                        if not _CHAT_INTERNAL_AVAILABLE:
                            raise RuntimeError("chat internal not available")
                        q_since = last_iso or None
                        with _chat_internal_session() as s:
                            arr = _chat_inbox(request=ws, device_id=did, since_iso=q_since, limit=100, s=s)
                        if arr:
                            try:
                                last_iso = max([m.created_at or "" for m in arr]) or last_iso  # type: ignore[attr-defined]
                            except Exception:
                                pass
                            payload = [
                                {
                                    "id": getattr(m, "id", None),
                                    "sender_id": getattr(m, "sender_id", None),
                                    "recipient_id": getattr(m, "recipient_id", None),
                                    "nonce_b64": getattr(m, "nonce_b64", None),
                                    "box_b64": getattr(m, "box_b64", None),
                                    "sender_pubkey_b64": getattr(m, "sender_pubkey_b64", getattr(m, "sender_pubkey", None)),
                                    "sender_dh_pub_b64": getattr(m, "sender_dh_pub_b64", getattr(m, "sender_dh_pub", None)),
                                    "created_at": getattr(m, "created_at", None),
                                    "delivered_at": getattr(m, "delivered_at", None),
                                    "read_at": getattr(m, "read_at", None),
                                    "expire_at": getattr(m, "expire_at", None),
                                    "sealed_sender": getattr(m, "sealed_sender", False),
                                    "sender_hint": getattr(m, "sender_hint", None),
                                    "sender_fingerprint": getattr(m, "sender_fingerprint", getattr(m, "sender_hint", None)),
                                    "key_id": getattr(m, "key_id", None),
                                    "prev_key_id": getattr(m, "prev_key_id", None),
                                }
                                for m in arr
                            ]
                            await ws.send_json({"type": "inbox", "messages": payload})
                    else:
                        qparams = {"device_id": did, "limit": 100}
                        if last_iso:
                            qparams["since_iso"] = last_iso
                        r = httpx.get(
                            _chat_url("/messages/inbox"),
                            params=qparams,
                            headers=chat_headers,
                            timeout=10,
                        )
                        if r.status_code == 200:
                            arr = r.json()
                            if arr:
                                try:
                                    last_iso = max([m.get("created_at") or "" for m in arr]) or last_iso
                                except Exception:
                                    pass
                                await ws.send_json({"type": "inbox", "messages": arr})
                    await asyncio.sleep(2)
                except Exception as e:
                    await ws.send_json({"type": "error", "error": str(e)})
                    await asyncio.sleep(2)
        finally:
            await _chat_ws_guard_exit(g_ip, g_dev)
    except WebSocketDisconnect:
        return


@app.websocket("/ws/chat/groups")
async def chat_groups_ws(ws: WebSocket):
    """
    Real-time-ish group inbox stream.

    Mirrors /ws/chat/inbox by polling group inbox endpoints and emitting
    JSON frames of shape:
      {"type":"group_inbox","group_id":"...","messages":[...]}
    """
    await ws.accept()
    try:
        params = dict(ws.query_params)
        chat_headers = _chat_auth_headers_from_ws(ws)
        did = params.get("device_id") or chat_headers.get("X-Chat-Device-Id")
        guard = await _chat_ws_guard_enter(ws, device_id=str(did or ""))
        if guard is None:
            return
        g_ip, g_dev = guard
        last_by_gid: Dict[str, str] = {}
        # Optional resume map: since_map={"gid":"iso",...}
        since_map_raw = params.get("since_map") or ""
        if since_map_raw:
            try:
                decoded = _json.loads(since_map_raw)
                if isinstance(decoded, dict):
                    last_by_gid = {
                        str(k): str(v)
                        for k, v in decoded.items()
                        if str(k) and str(v)
                    }
            except Exception:
                last_by_gid = {}

        try:
            while True:
                try:
                    groups: List[Any] = []
                    if _use_chat_internal():
                        if not _CHAT_INTERNAL_AVAILABLE:
                            raise RuntimeError("chat internal not available")
                        with _chat_internal_session() as s:
                            groups = _chat_list_groups(request=ws, device_id=did, s=s)
                    else:
                        r = httpx.get(
                            _chat_url("/groups/list"),
                            params={"device_id": did},
                            headers=chat_headers,
                            timeout=10,
                        )
                        if r.status_code == 200:
                            groups = r.json() or []

                    for g in groups:
                        gid: str = ""
                        try:
                            gid = (
                                getattr(g, "group_id", None)
                                or getattr(g, "id", None)
                                or ""
                            )
                        except Exception:
                            gid = ""
                        if not gid and isinstance(g, dict):
                            gid = (g.get("group_id") or g.get("id") or "").strip()
                        if not gid:
                            continue

                        last_iso = last_by_gid.get(gid, "")
                        arr: List[Any] = []
                        if _use_chat_internal():
                            with _chat_internal_session() as s:
                                sin = last_iso or None
                                arr = _chat_group_inbox(
                                    group_id=gid,
                                    request=ws,
                                    device_id=did,
                                    since_iso=sin,
                                    limit=100,
                                    s=s,
                                )
                            if arr:
                                try:
                                    last_iso = (
                                        max(
                                            [
                                                getattr(m, "created_at", "") or ""
                                                for m in arr
                                            ]
                                        )
                                        or last_iso
                                    )
                                except Exception:
                                    pass
                                last_by_gid[gid] = last_iso
                                payload = [
                                    {
                                        "id": getattr(m, "id", None),
                                        "group_id": getattr(
                                            m, "group_id", getattr(m, "groupId", None)
                                        ),
                                        "sender_id": getattr(m, "sender_id", None),
                                        "text": getattr(m, "text", ""),
                                        "kind": getattr(m, "kind", None),
                                        "nonce_b64": getattr(m, "nonce_b64", None),
                                        "box_b64": getattr(m, "box_b64", None),
                                        "attachment_b64": getattr(m, "attachment_b64", None),
                                        "attachment_mime": getattr(m, "attachment_mime", None),
                                        "voice_secs": getattr(m, "voice_secs", None),
                                        "created_at": getattr(m, "created_at", None),
                                        "expire_at": getattr(m, "expire_at", None),
                                    }
                                    for m in arr
                                ]
                                await ws.send_json(
                                    {
                                        "type": "group_inbox",
                                        "group_id": gid,
                                        "messages": payload,
                                    }
                                )
                        else:
                            qparams: Dict[str, Any] = {
                                "device_id": did,
                                "limit": 100,
                            }
                            if last_iso:
                                qparams["since_iso"] = last_iso
                            r = httpx.get(
                                _chat_url(f"/groups/{gid}/messages/inbox"),
                                params=qparams,
                                headers=chat_headers,
                                timeout=10,
                            )
                            if r.status_code == 200:
                                arr = r.json() or []
                                if arr:
                                    try:
                                        last_iso = (
                                            max(
                                                [m.get("created_at") or "" for m in arr]
                                            )
                                            or last_iso
                                        )
                                    except Exception:
                                        pass
                                    last_by_gid[gid] = last_iso
                                    await ws.send_json(
                                        {
                                            "type": "group_inbox",
                                            "group_id": gid,
                                            "messages": arr,
                                        }
                                    )

                    await asyncio.sleep(2)
                except Exception as e:
                    await ws.send_json({"type": "error", "error": str(e)})
                    await asyncio.sleep(2)
        finally:
            await _chat_ws_guard_exit(g_ip, g_dev)
    except WebSocketDisconnect:
        return


@app.websocket("/ws/call/signaling")
async def call_signaling_ws(ws: WebSocket):
    """
    Lightweight VoIP signaling WebSocket.

    This endpoint routes JSON messages between devices based on `device_id`
    and `to` fields. It is intentionally kept stateless apart from an
    in-memory mapping of active connections so that the Flutter client
    (CallSignalingClient) can use it for invites/answers/hangups and
    later WebRTC SDP/ICE exchange.
    """
    # This signaling stub is intentionally disabled by default in prod/staging
    # until a proper auth binding exists (device token / session / JWT).
    env_name = (os.getenv("ENV") or "dev").strip().lower()
    enabled_default = "true" if env_name in ("dev", "test") else "false"
    enabled = _env_or("CALL_SIGNALING_ENABLED", enabled_default).strip().lower() in ("1", "true", "yes", "on")
    if not enabled:
        try:
            await ws.close(code=1008)  # policy violation / disabled
        except Exception:
            pass
        return

    await ws.accept()
    params = dict(ws.query_params)
    device_id = params.get("device_id") or ""
    if not device_id:
        await ws.close(code=4000)
        return
    # Best-effort input validation and connection abuse guardrails.
    if not re.fullmatch(r"[A-Za-z0-9_-]{4,24}", device_id):
        await ws.close(code=4400)
        return
    guard = await _chat_ws_guard_enter(ws, device_id=device_id)
    if guard is None:
        return
    g_ip, g_dev = guard
    # Register connection
    _CALL_WS_CONNECTIONS[device_id] = ws
    try:
        while True:
            try:
                payload = await ws.receive_text()
            except WebSocketDisconnect:
                break
            except Exception:
                continue
            try:
                msg = _json.loads(payload)
            except Exception:
                continue
            if not isinstance(msg, dict):
                continue
            msg.setdefault("from", device_id)
            t = str(msg.get("type") or "")
            # For now we simply route based on explicit `to` field.
            target = str(msg.get("to") or "")
            if target and target in _CALL_WS_CONNECTIONS:
                try:
                    await _CALL_WS_CONNECTIONS[target].send_text(_json.dumps(msg))
                except Exception:
                    # Drop broken targets; they will be cleaned up on their side.
                    try:
                        _CALL_WS_CONNECTIONS.pop(target, None)
                    except Exception:
                        pass
            # Optionally echo minimal ACK to sender for debugging
            if t == "invite":
                try:
                    await ws.send_text(
                        _json.dumps(
                            {
                                "type": "invite_ack",
                                "call_id": msg.get("call_id"),
                                "to": target,
                            }
                        )
                    )
                except Exception:
                    pass
    except WebSocketDisconnect:
        pass
    finally:
        try:
          # Remove only if mapping still points to this socket
          existing = _CALL_WS_CONNECTIONS.get(device_id)
          if existing is ws:
              _CALL_WS_CONNECTIONS.pop(device_id, None)
        except Exception:
            pass
        try:
            await _chat_ws_guard_exit(g_ip, g_dev)
        except Exception:
            pass



# ---- Payments proxy helpers ----
def _payments_url(path: str) -> str:
    if not PAYMENTS_BASE:
        raise HTTPException(status_code=500, detail="PAYMENTS_BASE_URL not configured")
    return PAYMENTS_BASE.rstrip("/") + path


def _to_cents(x: Any) -> int:
    """
    Convert a major-unit amount (e.g. SYP) into minor units (cents).
    Best-effort: returns 0 on invalid input.
    """
    try:
        if x is None:
            return 0
        # bool is a subclass of int; never accept it as an amount.
        if isinstance(x, bool):
            return 0
        if isinstance(x, (int, float)):
            return round(float(x) * 100)
        s = str(x).strip().replace(",", ".")
        if not s:
            return 0
        # Strip non-numeric except dot and minus.
        keep = "".join(ch for ch in s if (ch.isdigit() or ch in ".-"))
        if keep in ("", "-", ".", "-.", ".-"):
            return 0
        return round(float(keep) * 100)
    except Exception:
        return 0


def _normalize_amount(body: Any) -> Any:
    """
    Accept amount in major units (amount/amount_syp) and convert to amount_cents.
    Does not override an existing amount_cents.
    """
    if not isinstance(body, dict):
        return body
    if body.get("amount_cents") in (None, ""):
        if body.get("amount") not in (None, ""):
            body["amount_cents"] = _to_cents(body.get("amount"))
        elif body.get("amount_syp") not in (None, ""):
            body["amount_cents"] = _to_cents(body.get("amount_syp"))
    return body

# --- Payments internal service (internal mode) ---
_PAY_INTERNAL_AVAILABLE = False
try:
    from sqlalchemy.orm import Session as _PaySession  # type: ignore[import]
    from apps.payments.app import main as _pay_main  # type: ignore[import]
    from apps.payments.app.main import (  # type: ignore[import]
        engine as _pay_engine,
        get_session as _pay_get_session,
        # Models
        CreateUserReq as _PayCreateUserReq,
        TopupReq as _PayTopupReq,
        TransferReq as _PayTransferReq,
        PaymentRequestCreate as _PayRequestCreate,
        FavoriteCreate as _PayFavoriteCreate,
        RedPacketIssueReq as _PayRedPacketIssueReq,
        RedPacketClaimReq as _PayRedPacketClaimReq,
        SavingsDepositReq as _PaySavingsDepositReq,
        SavingsWithdrawReq as _PaySavingsWithdrawReq,
        BillPayReq as _PayBillPayReq,
        AliasRequest as _PayAliasRequest,
        AliasVerifyReq as _PayAliasVerifyReq,
        RiskDenyReq as _PayRiskDenyReq,
        SonicIssueReq as _PaySonicIssueReq,
        SonicRedeemReq as _PaySonicRedeemReq,
        CashCreateReq as _PayCashCreateReq,
        CashRedeemReq as _PayCashRedeemReq,
        CashCancelReq as _PayCashCancelReq,
        TopupBatchCreateReq as _PayTopupBatchCreateReq,
        TopupRedeemReq as _PayTopupRedeemReq,
        RoleUpsert as _PayRoleUpsert,
        # Core
        create_user as _pay_create_user,
        get_wallet as _pay_get_wallet,
        topup as _pay_wallet_topup,
        transfer as _pay_transfer,
        list_txns as _pay_list_txns,
        resolve_phone as _pay_resolve_phone,
        # Requests
        create_request as _pay_create_request,
        list_requests as _pay_list_requests,
        cancel_request as _pay_cancel_request,
        _accept_request_core as _pay_accept_request_core,
        # Favorites
        create_favorite as _pay_create_favorite,
        list_favorites as _pay_list_favorites,
        delete_favorite as _pay_delete_favorite,
        # Redpacket
        redpacket_issue as _pay_redpacket_issue,
        redpacket_claim as _pay_redpacket_claim,
        redpacket_status as _pay_redpacket_status,
        # Savings
        savings_deposit as _pay_savings_deposit,
        savings_withdraw as _pay_savings_withdraw,
        savings_overview as _pay_savings_overview,
        # Bills
        bills_pay as _pay_bills_pay,
        # Alias
        alias_request as _pay_alias_request,
        alias_verify as _pay_alias_verify,
        alias_resolve as _pay_alias_resolve,
        # Risk/admin
        fees_summary as _pay_fees_summary,
        admin_txns_count as _pay_admin_txns_count,
        admin_risk_deny_add as _pay_admin_risk_deny_add,
        admin_risk_deny_remove as _pay_admin_risk_deny_remove,
        admin_risk_deny_list as _pay_admin_risk_deny_list,
        admin_risk_events as _pay_admin_risk_events,
        admin_risk_metrics as _pay_admin_risk_metrics,
        # Sonic
        sonic_issue as _pay_sonic_issue,
        sonic_redeem as _pay_sonic_redeem,
        # Cash
        cash_create as _pay_cash_create,
        cash_redeem as _pay_cash_redeem,
        cash_cancel as _pay_cash_cancel,
        cash_status as _pay_cash_status,
        # Topup vouchers
        topup_batch_create as _pay_topup_batch_create,
        topup_batches as _pay_topup_batches,
        topup_batch_detail as _pay_topup_batch_detail,
        topup_voucher_void as _pay_topup_voucher_void,
        topup_redeem as _pay_topup_redeem,
        # Roles
        roles_list as _pay_roles_list,
        roles_add as _pay_roles_add,
        roles_remove as _pay_roles_remove,
    )
    _PAY_INTERNAL_AVAILABLE = True
except Exception:
    _PaySession = None  # type: ignore[assignment]
    _pay_main = None  # type: ignore[assignment]
    _pay_engine = None  # type: ignore[assignment]
    _pay_get_session = None  # type: ignore[assignment]
    _pay_accept_request_core = None  # type: ignore[assignment]
    _PAY_INTERNAL_AVAILABLE = False

_PAY_INTERNAL_BOOTSTRAPPED = False


def _use_pay_internal() -> bool:
    if _force_internal(_PAY_INTERNAL_AVAILABLE):
        return True
    # Back-compat: PAY_INTERNAL_MODE (on/off/auto) is older; PAYMENTS_INTERNAL_MODE preferred.
    mode = (os.getenv("PAYMENTS_INTERNAL_MODE") or os.getenv("PAY_INTERNAL_MODE") or "auto").lower()
    if mode == "off":
        return False
    if not _PAY_INTERNAL_AVAILABLE:
        return False
    if mode == "on":
        return True
    # auto
    # Allow fallback to internal only in dev/test. In prod/staging we fail
    # closed so missing PAYMENTS_BASE_URL does not silently enable internal mode.
    env_name = (os.getenv("ENV") or "dev").strip().lower()
    if env_name in ("prod", "production", "staging"):
        return False
    return not bool(PAYMENTS_BASE)


def _pay_internal_session():
    global _PAY_INTERNAL_BOOTSTRAPPED
    if not _PAY_INTERNAL_AVAILABLE or _PaySession is None or _pay_engine is None:  # type: ignore[truthy-function]
        raise RuntimeError("Payments internal service not available")
    # Lazy bootstrap: only create Payments tables when internal mode is actually used.
    if not _PAY_INTERNAL_BOOTSTRAPPED:
        try:
            if _use_pay_internal() and _pay_main is not None and hasattr(_pay_main, "on_startup"):
                _pay_main.on_startup()  # type: ignore[attr-defined]
        except Exception:
            pass
        _PAY_INTERNAL_BOOTSTRAPPED = True
    return _PaySession(_pay_engine)  # type: ignore[call-arg]


def _pay_accept_request(rid: str, s: Any):
    """
    Backward-compatible internal accept wrapper.
    Prefer _pay_accept_request_core when available (it supports idempotency and destination binding).
    """
    if _pay_accept_request_core is None:  # type: ignore[truthy-function]
        raise RuntimeError("Payments accept_request_core not available")
    return _pay_accept_request_core(rid=rid, ikey=None, s=s, to_wallet_id=None)  # type: ignore[call-arg]

# ---- Bus proxy helpers ----
def _bus_headers(extra: dict[str, str] | None = None) -> dict[str, str]:
    """
    Attach the internal auth header for all BFF->Bus HTTP calls.

    In prod/staging the Bus API should be treated as internal-only; the BFF is
    the public surface.
    """
    h: dict[str, str] = {}
    if extra:
        h.update(extra)
    if BUS_INTERNAL_SECRET:
        # Always override any caller-provided value (do not forward from clients).
        h["X-Internal-Secret"] = BUS_INTERNAL_SECRET
    return h


def _bus_url(path: str) -> str:
    if not BUS_BASE:
        raise HTTPException(status_code=500, detail="BUS_BASE_URL not configured")
    return BUS_BASE.rstrip("/") + path


# --- Bus internal service (internal mode) ---
_BUS_INTERNAL_AVAILABLE = False
try:
    from sqlalchemy.orm import Session as _BusSession  # type: ignore[import]
    from apps.bus.app import main as _bus_main  # type: ignore[import]
    from apps.bus.app.main import (  # type: ignore[import]
        engine as _bus_engine,
        get_session as _bus_get_session,
        BookReq as _BusBookReq,
        BoardReq as _BusBoardReq,
        CityIn as _BusCityIn,
        OperatorIn as _BusOperatorIn,
        RouteIn as _BusRouteIn,
        TripIn as _BusTripIn,
        operator_online as _bus_operator_online,
        operator_offline as _bus_operator_offline,
        list_cities as _bus_list_cities,
        create_city as _bus_create_city,
        list_operators as _bus_list_operators,
        create_operator as _bus_create_operator,
        create_route as _bus_create_route,
        list_routes as _bus_list_routes,
        create_trip as _bus_create_trip,
        search_trips as _bus_search_trips,
        trip_detail as _bus_trip_detail,
        publish_trip as _bus_publish_trip,
        unpublish_trip as _bus_unpublish_trip,
        cancel_trip as _bus_cancel_trip,
        quote as _bus_quote,
        book_trip as _bus_book_trip,
        booking_status as _bus_booking_status,
        booking_tickets as _bus_booking_tickets,
        booking_search as _bus_booking_search,
        cancel_booking as _bus_cancel_booking,
        ticket_board as _bus_ticket_board,
        operator_trips as _bus_operator_trips,
        operator_stats as _bus_operator_stats,
        admin_summary as _bus_admin_summary,
    )
    _BUS_INTERNAL_AVAILABLE = True
except Exception:
    _BusSession = None  # type: ignore[assignment]
    _bus_main = None  # type: ignore[assignment]
    _bus_engine = None  # type: ignore[assignment]
    _BUS_INTERNAL_AVAILABLE = False


def _use_bus_internal() -> bool:
    if _force_internal(_BUS_INTERNAL_AVAILABLE):
        return True
    mode = os.getenv("BUS_INTERNAL_MODE", "auto").lower()
    if mode == "off":
        return False
    if not _BUS_INTERNAL_AVAILABLE:
        return False
    if mode == "on":
        return True
    # auto: allow fallback to internal only in dev/test. In prod/staging we
    # fail closed so missing BUS_BASE_URL does not silently enable internal mode.
    env_name = (os.getenv("ENV") or "dev").strip().lower()
    if env_name in ("prod", "production", "staging"):
        return False
    return not bool(BUS_BASE)


def _bus_internal_session():
    if not _BUS_INTERNAL_AVAILABLE or _BusSession is None or _bus_engine is None:  # type: ignore[truthy-function]
        raise RuntimeError("Bus internal service not available")
    return _BusSession(_bus_engine)  # type: ignore[call-arg]


def _resolve_wallet_id_for_phone(phone: str) -> str | None:
    """
    Resolve a wallet_id for the given phone via Payments (internal or HTTP).
    Best-effort: returns None when unavailable or not found.
    """
    phone = (phone or "").strip()
    if not phone:
        return None
    try:
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                return None
            with _pay_internal_session() as s:  # type: ignore[name-defined]
                res = _pay_resolve_phone(phone=phone, s=s)  # type: ignore[name-defined]
                try:
                    wid = getattr(res, "wallet_id", None) or getattr(res, "id", None)
                except Exception:
                    wid = None
                return (wid or "").strip() or None
        if PAYMENTS_BASE:
            r = httpx.get(
                _payments_url(f"/resolve/phone/{phone}"),
                headers=_payments_headers(),
                timeout=6,
            )
            if r.status_code == 200 and r.headers.get("content-type", "").startswith("application/json"):
                try:
                    j = r.json()
                    if isinstance(j, dict):
                        wid = (j.get("wallet_id") or j.get("id") or "").strip()
                        return wid or None
                except Exception:
                    return None
    except HTTPException:
        raise
    except Exception:
        return None
    return None


def _require_caller_wallet(request: Request) -> tuple[str, str]:
    """
    Require an authenticated caller and resolve the caller-owned wallet id.
    """
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    wallet_id = _resolve_wallet_id_for_phone(phone)
    if not wallet_id:
        raise HTTPException(status_code=403, detail="wallet not found for caller")
    return phone, wallet_id


def _bus_operator_ids_for_phone(phone: str) -> list[str]:
    """
    Return all bus operator IDs that belong to the caller's wallet.
    """
    wid = _resolve_wallet_id_for_phone(phone)
    if not wid:
        return []
    try:
        if _use_bus_internal():
            if not _BUS_INTERNAL_AVAILABLE:
                return []
            with _bus_internal_session() as s:  # type: ignore[name-defined]
                ops = _bus_list_operators(limit=200, s=s)  # type: ignore[name-defined]
                out: list[str] = []
                for op in ops or []:
                    try:
                        if str(getattr(op, "wallet_id", "") or "").strip() != wid:
                            continue
                        oid = str(getattr(op, "id", "") or "").strip()
                        if oid:
                            out.append(oid)
                    except Exception:
                        continue
                return out
        if BUS_BASE:
            r = httpx.get(_bus_url("/operators"), headers=_bus_headers(), timeout=10)
            if r.headers.get("content-type", "").startswith("application/json"):
                arr = r.json()
                if isinstance(arr, list):
                    out = []
                    for op in arr:
                        try:
                            if str((op.get("wallet_id") or "")).strip() != wid:
                                continue
                            oid = str((op.get("id") or "")).strip()
                            if oid:
                                out.append(oid)
                        except Exception:
                            continue
                    return out
    except HTTPException:
        raise
    except Exception:
        return []
    return []


def _bus_all_operator_ids() -> list[str]:
    """
    Helper to list all bus operators (used in dev/test to relax ownership checks).
    """
    try:
        if _use_bus_internal():
            if not _BUS_INTERNAL_AVAILABLE:
                return []
            with _bus_internal_session() as s:  # type: ignore[name-defined]
                ops = _bus_list_operators(limit=200, s=s)  # type: ignore[name-defined]
                return [str(getattr(op, "id", "") or "").strip() for op in ops or [] if getattr(op, "id", None)]
        if BUS_BASE:
            r = httpx.get(_bus_url("/operators"), headers=_bus_headers(), timeout=10)
            if r.headers.get("content-type", "").startswith("application/json"):
                arr = r.json()
                if isinstance(arr, list):
                    return [str((op.get("id") or "")).strip() for op in arr if (op.get("id") or "").strip()]
    except Exception:
        return []
    return []


def _bus_route_owner(route_id: str) -> str | None:
    """
    Resolve the operator_id owning a given route.
    """
    rid = (route_id or "").strip()
    if not rid:
        return None
    try:
        if _use_bus_internal():
            if not _BUS_INTERNAL_AVAILABLE:
                return None
            with _bus_internal_session() as s:  # type: ignore[name-defined]
                routes = _bus_list_routes(origin_city_id=None, dest_city_id=None, s=s)  # type: ignore[name-defined]
                for rt in routes or []:
                    try:
                        if str(getattr(rt, "id", "") or "").strip() != rid:
                            continue
                        return str(getattr(rt, "operator_id", "") or "").strip() or None
                    except Exception:
                        continue
        elif BUS_BASE:
            r = httpx.get(_bus_url("/routes"), headers=_bus_headers(), timeout=10)
            if r.headers.get("content-type", "").startswith("application/json"):
                arr = r.json()
                if isinstance(arr, list):
                    for rt in arr:
                        try:
                            if str((rt.get("id") or "")).strip() != rid:
                                continue
                            return str((rt.get("operator_id") or "")).strip() or None
                        except Exception:
                            continue
    except HTTPException:
        raise
    except Exception:
        return None
    return None


def _bus_trip_route_id(trip_id: str) -> str | None:
    """
    Resolve the route_id for a given trip.
    """
    tid = (trip_id or "").strip()
    if not tid:
        return None
    try:
        if _use_bus_internal():
            if not _BUS_INTERNAL_AVAILABLE:
                return None
            with _bus_internal_session() as s:  # type: ignore[name-defined]
                trip = _bus_trip_detail(trip_id=tid, s=s)  # type: ignore[name-defined]
                try:
                    return str(getattr(trip, "route_id", "") or "").strip() or None
                except Exception:
                    return None
        if BUS_BASE:
            r = httpx.get(_bus_url(f"/trips/{tid}"), headers=_bus_headers(), timeout=10)
            if r.status_code == 404:
                return None
            if r.headers.get("content-type", "").startswith("application/json"):
                try:
                    j = r.json()
                    if isinstance(j, dict):
                        return str((j.get("route_id") or "")).strip() or None
                except Exception:
                    return None
    except HTTPException:
        raise
    except Exception:
        return None
    return None


@app.get("/qr.png")
def qr_png(data: str, box_size: int = 6, border: int = 2):
    if not data:
        raise HTTPException(status_code=400, detail="missing data")
    if len(data) > QR_MAX_DATA_LEN:
        raise HTTPException(status_code=413, detail="data too large")
    if _qr is None:
        raise HTTPException(status_code=500, detail="QR library not available")
    try:
        qr = _qr.QRCode(error_correction=_qr.constants.ERROR_CORRECT_M, box_size=max(1, min(int(box_size), 20)), border=max(1, min(int(border), 8)))
        qr.add_data(data)
        qr.make(fit=True)
        img = qr.make_image(fill_color="black", back_color="white")
        buf = BytesIO(); img.save(buf, format='PNG'); buf.seek(0)
        return StreamingResponse(buf, media_type='image/png')
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/bus/health")
def bus_health():
    """
    Bus health: prefer the internal Bus service when running in internal mode
    mode; otherwise proxy to an external BUS_BASE_URL if configured.
    """
    # Internal Bus (internal mode)
    if _use_bus_internal():
        if not _BUS_INTERNAL_AVAILABLE:
            raise HTTPException(status_code=500, detail="bus internal not available")
        # For now we keep the check simple: if the internal bus service is
        # importable we report a light-weight OK marker. Detailed DB/route
        # checks are handled via /bus/admin/summary.
        return {"status": "ok", "mode": "internal"}
    # External bus-api
    try:
        r = httpx.get(_bus_url("/health"), headers=_bus_headers(), timeout=10)
        return r.json() if r.headers.get('content-type','').startswith('application/json') else {"raw": r.text, "status_code": r.status_code}
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


# ---- Topup Kiosk proxies ----
@app.post("/topup/batch_create")
async def topup_batch_create(req: Request):
    if not PAYMENTS_BASE and not _use_pay_internal():
        raise HTTPException(status_code=500, detail="PAYMENTS_BASE_URL not configured")
    # Require authenticated seller (allowlist if configured)
    seller_phone = _require_seller(req)
    try:
        body = await req.json()
    except Exception:
        body = None
    # Accept amount_syp/amount and convert
    body = _normalize_amount(body)
    if isinstance(body, dict) and 'seller_id' not in body:
        body['seller_id'] = seller_phone
    try:
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                req_model = _PayTopupBatchCreateReq(**data)  # type: ignore[name-defined]
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _pay_internal_session() as s:
                return _pay_topup_batch_create(req_model, s=s, admin_ok=True)
        r = httpx.post(
            _payments_url("/topup/batch_create"),
            json=body,
            headers=_payments_headers(),
            timeout=20,
        )
        return r.json() if r.headers.get('content-type','').startswith('application/json') else {"raw": r.text, "status_code": r.status_code}
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/topup/batches")
def topup_batches(request: Request, seller_id: str = "", limit: int = 50):
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    is_admin = _is_admin(phone)
    if not is_admin:
        _require_seller(request)
    # Default to current seller; only admins may list other sellers.
    seller_id = (seller_id or "").strip()
    if seller_id:
        if not is_admin and seller_id != phone:
            raise HTTPException(status_code=403, detail="seller_id does not belong to caller")
    else:
        if not is_admin:
            seller_id = phone
    try:
        params = {}
        if seller_id:
            params["seller_id"] = seller_id
        params["limit"] = max(1, min(limit, 2000))
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            with _pay_internal_session() as s:
                return _pay_topup_batches(seller_id=seller_id or None, limit=max(1, min(limit, 2000)), s=s, admin_ok=True)
        if not PAYMENTS_INTERNAL_SECRET:
            raise HTTPException(status_code=403, detail="Server not configured for topup admin")
        r = httpx.get(
            _payments_url("/topup/batches"),
            params=params,
            headers=_payments_headers(),
            timeout=10,
        )
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/topup/batches/{batch_id}")
def topup_batch_detail(request: Request, batch_id: str):
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    is_admin = _is_admin(phone)
    if not is_admin:
        _require_seller(request)
    try:
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            with _pay_internal_session() as s:
                rows = _pay_topup_batch_detail(batch_id=batch_id, s=s, admin_ok=True)
            if not isinstance(rows, list):
                rows = []
            arr = []
            for it in rows:
                try:
                    if hasattr(it, "model_dump"):
                        # Use json-mode to avoid leaking non-JSON types (datetime/UUID/Decimal) to callers.
                        arr.append(it.model_dump(mode="json"))  # type: ignore[attr-defined]
                    else:
                        arr.append(it.dict())  # type: ignore[call-arg]
                except Exception:
                    arr.append(
                        {
                            "code": getattr(it, "code", ""),
                            "amount_cents": getattr(it, "amount_cents", 0),
                            "currency": getattr(it, "currency", ""),
                            "status": getattr(it, "status", ""),
                            "created_at": getattr(it, "created_at", None),
                            "redeemed_at": getattr(it, "redeemed_at", None),
                            "expires_at": getattr(it, "expires_at", None),
                            "sig": getattr(it, "sig", ""),
                            "payload": getattr(it, "payload", ""),
                            "seller_id": getattr(it, "seller_id", None),
                            "note": getattr(it, "note", None),
                        }
                    )
        else:
            if not PAYMENTS_INTERNAL_SECRET:
                raise HTTPException(status_code=403, detail="Server not configured for topup admin")
            r = httpx.get(
                _payments_url(f"/topup/batches/{batch_id}"),
                headers=_payments_headers(),
                timeout=15,
            )
            arr = r.json() if r.headers.get("content-type", "").startswith("application/json") else []
        if not isinstance(arr, list):
            arr = []
        # Ownership check: sellers may only see their own batch items.
        if not is_admin and arr:
            seller_ids = set()
            for v in arr:
                if not isinstance(v, dict):
                    continue
                sid = str((v.get("seller_id") or "")).strip()
                if sid:
                    seller_ids.add(sid)
            if not seller_ids:
                raise HTTPException(status_code=403, detail="batch owner unknown")
            if seller_ids != {phone}:
                raise HTTPException(status_code=403, detail="batch does not belong to caller")
        return arr
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/topup/vouchers/{code}/void")
async def topup_voucher_void(request: Request, code: str):
    # Nur Superadmin darf Vouchers invalidieren.
    _require_superadmin(request)
    if not PAYMENTS_INTERNAL_SECRET:
        raise HTTPException(status_code=403, detail="Server not configured for voucher admin")
    try:
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            with _pay_internal_session() as s:
                result = _pay_topup_voucher_void(code=code, s=s, admin_ok=True)
        else:
            r = httpx.post(
                _payments_url(f"/topup/vouchers/{code}/void"),
                headers=_payments_headers(),
                timeout=10,
            )
            result = r.json()
        _audit_from_request(request, "topup_voucher_void", code=code)
        return result
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/topup/redeem")
async def topup_redeem(req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    headers = {}
    try:
        ikey = req.headers.get("Idempotency-Key") if hasattr(req, 'headers') else None
    except Exception:
        ikey = None
    if ikey:
        headers["Idempotency-Key"] = ikey
    try:
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                treq = _PayTopupRedeemReq(**data)  # type: ignore[name-defined]
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _pay_internal_session() as s:
                return _pay_topup_redeem(treq, request=req, s=s)
        r = httpx.post(
            _payments_url("/topup/redeem"),
            json=body,
            headers=_payments_headers(headers),
            timeout=12,
        )
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/topup/print/{batch_id}", response_class=HTMLResponse)
def topup_print(request: Request, batch_id: str):
    """
    Printable QR sheet for a topup batch.

    In internal mode this uses the Payments domain directly;
    otherwise it falls back to the external PAYMENTS_BASE_URL.
    """
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    is_admin = _is_admin(phone)
    if not is_admin:
        _require_seller(request)
    # Fetch vouchers and render printable QR grid
    try:
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            with _pay_internal_session() as s:  # type: ignore[name-defined]
                rows = _pay_topup_batch_detail(batch_id=batch_id, s=s, admin_ok=True)  # type: ignore[name-defined]
                # rows is a list of Pydantic models; normalise to dicts
                arr = []
                for it in rows:
                    try:
                        if hasattr(it, "model_dump"):
                            arr.append(it.model_dump())  # type: ignore[attr-defined]
                        else:
                            arr.append(it.dict())  # type: ignore[call-arg]
                    except Exception:
                        arr.append({
                            "code": getattr(it, "code", ""),
                            "amount_cents": getattr(it, "amount_cents", 0),
                            "payload": getattr(it, "payload", ""),
                            "seller_id": getattr(it, "seller_id", None),
                        })
        else:
            if not PAYMENTS_INTERNAL_SECRET:
                raise HTTPException(status_code=403, detail="Server not configured for topup admin")
            r = httpx.get(
                _payments_url(f"/topup/batches/{batch_id}"),
                headers=_payments_headers(),
                timeout=15,
            )
            arr = r.json() if r.headers.get('content-type','').startswith('application/json') else []
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"fetch batch failed: {e}")
    if not isinstance(arr, list):
        arr = []
    if len(arr) > TOPUP_PRINT_MAX_ITEMS:
        raise HTTPException(status_code=413, detail="batch too large to print")
    # Ownership check: sellers may only print their own batch.
    if not is_admin and arr:
        seller_ids = set()
        for v in arr:
            if not isinstance(v, dict):
                continue
            sid = str((v.get("seller_id") or "")).strip()
            if sid:
                seller_ids.add(sid)
        if not seller_ids:
            raise HTTPException(status_code=403, detail="batch owner unknown")
        if seller_ids != {phone}:
            raise HTTPException(status_code=403, detail="batch does not belong to caller")
    _audit_from_request(request, "topup_print_batch", batch_id=batch_id)
    title = f"Topup Batch {batch_id}"
    rows = []
    for v in arr:
        if not isinstance(v, dict):
            continue
        payload = str(v.get("payload", "") or "")
        code = str(v.get("code", "") or "")
        try:
            amt = int(v.get("amount_cents", 0) or 0)
        except Exception:
            amt = 0
        img_q = _urlparse.quote_plus(payload)
        rows.append(
            "<div class=\"card\">"
            f"<img src=\"/qr.png?data={img_q}\" />"
            f"<div class=\"meta\"><b>{_html.escape(code)}</b><br/><small>{amt} SYP</small></div>"
            "</div>"
        )
    html = f"""
<!doctype html>
<html><head><meta charset=utf-8 /><meta name=viewport content='width=device-width, initial-scale=1' />
<title>{_html.escape(title)}</title>
<style>
  body{{font-family:sans-serif;margin:16px}}
  .grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(180px,1fr));gap:12px}}
  .card{{border:1px solid #ddd;border-radius:8px;padding:8px;text-align:center}}
  img{{width:160px;height:160px;}}
  .meta{{margin-top:6px;color:#333}}
  @media print{{ .no-print{{display:none}} body{{margin:0}} }}
  .toolbar{{position:sticky;top:0;background:#fff;padding:8px 0;margin-bottom:8px;border-bottom:1px solid #eee}}
  button{{padding:8px 12px;border-radius:6px;border:1px solid #999;background:#f7f7f7;cursor:pointer}}
  button:hover{{background:#eee}}
  small{{color:#666}}
  h1{{font-size:18px;margin:6px 0}}
  .sub{{color:#666;font-size:12px}}
  .wrap{{max-width:1024px;margin:0 auto}}
</style></head>
<body>
<div class=\"wrap\">
  <div class=\"toolbar no-print\"><button onclick=\"window.print()\">Print</button></div>
  <h1>{_html.escape(title)}</h1>
  <div class=\"sub\">Printable QR vouchers</div>
  <div class=\"grid\">{''.join(rows)}</div>
</div>
</body></html>
"""
    return HTMLResponse(content=html)


# ---- Admin: Roles management (proxies to Payments) ----
@app.get("/admin/roles")
def bff_roles_list(request: Request, phone: str = "", role: str = "", limit: int = 200):
    _require_admin_v2(request)
    params = {"limit": max(1, min(limit, 1000))}
    if phone:
        params["phone"] = phone
    if role:
        params["role"] = role
    try:
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            try:
                with _pay_internal_session() as s:
                    return _pay_roles_list(phone=phone or None, role=role or None, limit=max(1, min(limit, 1000)), s=s, admin_ok=True)
            except HTTPException:
                raise
            except Exception as e:
                raise HTTPException(status_code=502, detail=str(e))
        r = httpx.get(
            _payments_url("/admin/roles"),
            params=params,
            headers=_payments_headers(),
            timeout=10,
        )
        return r.json()
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/admin/ids_for_phone")
def admin_ids_for_phone(request: Request, phone: str):
    """
    Superadmin helper: returns core IDs associated with a phone number.

    - payments user_id / wallet_id
    - bus operator_id(s) (matched by wallet_id)
    - effective roles + admin/superadmin flags
    """
    _require_superadmin(request)
    phone = (phone or "").strip()
    if not phone:
        raise HTTPException(status_code=400, detail="phone required")

    user_id: str | None = None
    wallet_id: str | None = None
    roles: list[str] = []
    bus_operator_ids: list[str] = []
    stays_operator_ids: list[str] = []

    # Effective roles (from Payments or local allowlists)
    try:
        roles = _get_effective_roles(phone)
    except Exception:
        roles = []

    # Payments: resolve phone -> (user_id, wallet_id)
    try:
        if _use_pay_internal():
            if _PAY_INTERNAL_AVAILABLE:
                with _pay_internal_session() as s:  # type: ignore[name-defined]
                    try:
                        res = _pay_resolve_phone(phone=phone, s=s)  # type: ignore[name-defined]
                        user_id = getattr(res, "user_id", None)
                        wallet_id = getattr(res, "wallet_id", None)
                    except HTTPException:
                        # phone/wallet not found is allowed
                        user_id = None
                        wallet_id = None
        elif PAYMENTS_BASE:
            r = httpx.get(
                _payments_url(f"/resolve/phone/{phone}"),
                headers=_payments_headers(),
                timeout=6,
            )
            if r.status_code == 200 and r.headers.get("content-type", "").startswith("application/json"):
                try:
                    j = r.json()
                    if isinstance(j, dict):
                        uid = (j.get("user_id") or "").strip()
                        wid = (j.get("wallet_id") or "").strip()
                        user_id = uid or None
                        wallet_id = wid or None
                except Exception:
                    pass
    except Exception:
        user_id = user_id or None
        wallet_id = wallet_id or None

    # Bus operators: match by wallet_id (if available)
    try:
        if wallet_id:
            if _use_bus_internal():
                if not _BUS_INTERNAL_AVAILABLE:
                    raise HTTPException(status_code=500, detail="bus internal not available")
                with _bus_internal_session() as s:  # type: ignore[name-defined]
                    ops = _bus_list_operators(limit=200, s=s)  # type: ignore[name-defined]
                    for op in ops or []:
                        try:
                            wid = str(getattr(op, "wallet_id", "") or "").strip()
                            if wid != wallet_id:
                                continue
                            oid = str(getattr(op, "id", "") or "").strip()
                            if oid and oid not in bus_operator_ids:
                                bus_operator_ids.append(oid)
                        except Exception:
                            continue
            elif BUS_BASE:
                r = httpx.get(_bus_url("/operators"), headers=_bus_headers(), timeout=10)
                if r.headers.get("content-type", "").startswith("application/json"):
                    arr = r.json()
                    if isinstance(arr, list):
                        for op in arr:
                            try:
                                wid = str((op.get("wallet_id") or "")).strip()
                                if wid != wallet_id:
                                    continue
                                oid = str(op.get("id") or "").strip()
                                if oid and oid not in bus_operator_ids:
                                    bus_operator_ids.append(oid)
                            except Exception:
                                continue
    except HTTPException:
        raise
    except Exception:
        bus_operator_ids = bus_operator_ids or []

    # Legacy vertical removed: keep field for backward compatibility.
    stays_operator_ids = []

    # Admin / Superadmin IDs: reuse payments user_id when role is present
    is_admin = _hasAdminRole(roles) if roles else False
    is_superadmin = _hasSuperadminRole(roles) if roles else False
    admin_id = user_id if is_admin else None
    superadmin_id = user_id if is_superadmin else None

    return {
        "phone": phone,
        "user_id": user_id,
        "wallet_id": wallet_id,
        "roles": roles,
        "bus_operator_ids": bus_operator_ids,
        "stays_operator_ids": stays_operator_ids,
        "admin_id": admin_id,
        "superadmin_id": superadmin_id,
        "is_admin": is_admin,
        "is_superadmin": is_superadmin,
    }
@app.post("/admin/roles")
async def bff_roles_add(request: Request):
    _require_superadmin(request)
    try:
        body = await request.json()
    except Exception:
        body = None
    try:
        target_phone = ""
        target_role = ""
        try:
            if isinstance(body, dict):
                target_phone = (body.get("phone") or "").strip()
                target_role = (body.get("role") or "").strip()
        except Exception:
            target_phone = ""
            target_role = ""
        # Best-effort: ensure a user/wallet exists for this phone before
        # assigning roles. This makes the Superadmin "Grant role" button
        # robust even if the operator phone was never used in Payments before.
        try:
            if target_phone:
                dummy_req = Request({"type": "http", "headers": []})  # minimal ASGI scope
                # Monkey-patch json() to return our payload for internal call.
                async def _json_phone():
                    return {"phone": target_phone}
                setattr(dummy_req, "json", _json_phone)
                await payments_create_user(dummy_req)  # ignore result; idempotent
        except Exception:
            # Ignore failures here; /admin/roles will still return proper error details.
            pass
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                ru = _PayRoleUpsert(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            try:
                with _pay_internal_session() as s:
                    return _pay_roles_add(body=ru, s=s, admin_ok=True)
            except HTTPException:
                raise
            except Exception as e:
                raise HTTPException(status_code=502, detail=str(e))
        r = httpx.post(
            _payments_url("/admin/roles"),
            json=body,
            headers=_payments_headers(),
            timeout=10,
        )
        resp = r.json()
        _audit_from_request(request, "admin_role_add", target_phone=target_phone, target_role=target_role)
        return resp
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


class BusOperatorCreateReq(BaseModel):
    phone: str
    company_name: str


@app.post("/admin/bus/operator")
async def admin_bus_operator_create(request: Request):
    """
    Create or link a Bus operator for a given phone number.

    - Ensures a Payments user/wallet exists for the phone.
    - Creates a Bus operator (if none exists for that wallet yet) and
      links it to the wallet_id.
    - Grants the \"operator_bus\" role to the phone.

    This endpoint is intended for Admin/Superadmin use from the
    Superadmin dashboard and simplifies onboarding of bus operators.
    """
    _require_admin_or_superadmin(request)
    try:
      body = await request.json()
    except Exception:
      body = None
    if not isinstance(body, dict):
      body = {}
    try:
        req = BusOperatorCreateReq(**body)
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))
    phone = req.phone.strip()
    company_name = req.company_name.strip()
    if not phone or not company_name:
        raise HTTPException(status_code=400, detail="phone and company_name are required")

    # 1) Ensure payments user/wallet exists for this phone and resolve wallet_id.
    wallet_id: str | None = None
    try:
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            with _pay_internal_session() as s:  # type: ignore[name-defined]
                try:
                    # Resolve existing mapping first.
                    res = _pay_resolve_phone(phone=phone, s=s)  # type: ignore[name-defined]
                except Exception:
                    # If resolve fails, create user and try again using the
                    # same internal helper/Req model that the rest of the
                    # BFF uses for Payments.
                    _ = _pay_create_user(_PayCreateUserReq(phone=phone), s=s)  # type: ignore[name-defined]  # noqa: E501
                    res = _pay_resolve_phone(phone=phone, s=s)  # type: ignore[name-defined]
                try:
                    wallet_id = getattr(res, "wallet_id", None)
                except Exception:
                    wallet_id = None
        elif PAYMENTS_BASE:
            # Fallback: HTTP call to standalone Payments API.
            r = httpx.get(
                _payments_url(f"/resolve/phone/{phone}"),
                headers=_payments_headers(),
                timeout=10,
            )
            if r.status_code == 404:
                # Create user then resolve again.
                r_create = httpx.post(
                    _payments_url("/users"),
                    json={"phone": phone},
                    headers=_payments_headers(),
                    timeout=10,
                )
                if r_create.status_code >= 400:
                    raise HTTPException(status_code=r_create.status_code, detail=r_create.text)
                r = httpx.get(
                    _payments_url(f"/resolve/phone/{phone}"),
                    headers=_payments_headers(),
                    timeout=10,
                )
            if r.headers.get("content-type", "").startswith("application/json"):
                j = r.json()
                if isinstance(j, dict):
                    wid = (j.get("wallet_id") or j.get("id") or "").strip()
                    wallet_id = wid or None
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"payments resolve failed: {e}")

    if not wallet_id:
        raise HTTPException(status_code=500, detail="could not resolve wallet for phone")

    # 2) Ensure a Bus operator exists for this wallet_id.
    operator_id: str | None = None
    try:
        if _use_bus_internal():
            if not _BUS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="bus internal not available")
            with _bus_internal_session() as s:  # type: ignore[name-defined]
                ops = _bus_list_operators(limit=200, s=s)  # type: ignore[name-defined]
                # Try to find by wallet_id first.
                for op in ops or []:
                    try:
                        wid = str(getattr(op, "wallet_id", "") or "").strip()
                        if wid != wallet_id:
                            continue
                        oid = str(getattr(op, "id", "") or "").strip()
                        if oid:
                            operator_id = oid
                            break
                    except Exception:
                        continue
                # Fallback: match by company_name if no wallet match.
                if operator_id is None:
                    for op in ops or []:
                        try:
                            name = str(getattr(op, "name", "") or "").strip()
                            if name.lower() != company_name.lower():
                                continue
                            oid = str(getattr(op, "id", "") or "").strip()
                            if oid:
                                operator_id = oid
                                break
                        except Exception:
                            continue
                if operator_id is None:
                    # Create a new operator bound to this wallet.
                    op_in = _BusOperatorIn(name=company_name, wallet_id=wallet_id)  # type: ignore[name-defined]  # noqa: E501
                    op = _bus_create_operator(body=op_in, s=s)  # type: ignore[name-defined]
                    try:
                        operator_id = getattr(op, "id", None)
                    except Exception:
                        operator_id = None
        else:
            # External BUS_BASE_URL: use HTTP API.
            client = _httpx_client()
            r = client.get(_bus_url("/operators"), timeout=10)
            if r.headers.get("content-type", "").startswith("application/json"):
                arr = r.json()
                if isinstance(arr, list):
                    for op in arr:
                        try:
                            wid = str((op.get("wallet_id") or "")).strip()
                            if wid != wallet_id:
                                continue
                            oid = str((op.get("id") or "")).strip()
                            if oid:
                                operator_id = oid
                                break
                        except Exception:
                            continue
                    if operator_id is None:
                        for op in arr:
                            try:
                                name = str((op.get("name") or "")).strip()
                                if name.lower() != company_name.lower():
                                    continue
                                oid = str((op.get("id") or "")).strip()
                                if oid:
                                    operator_id = oid
                                    break
                            except Exception:
                                continue
            if operator_id is None:
                r = client.post(
                    _bus_url("/operators"),
                    json={"name": company_name, "wallet_id": wallet_id},
                    timeout=10,
                )
                if r.headers.get("content-type", "").startswith("application/json"):
                    j = r.json()
                    if isinstance(j, dict):
                        operator_id = (j.get("id") or "").strip() or None
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"bus operator provisioning failed: {e}")

    if not operator_id:
        raise HTTPException(status_code=500, detail="could not create or resolve bus operator")

    # 3) Grant operator_bus role via Payments.
    try:
        # We reuse the underlying role mechanism from /admin/roles.
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            data = {"phone": phone, "role": "operator_bus"}
            try:
                ru = _PayRoleUpsert(**data)  # type: ignore[name-defined]
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _pay_internal_session() as s:  # type: ignore[name-defined]
                _pay_roles_add(body=ru, s=s, admin_ok=True)  # type: ignore[name-defined]
        elif PAYMENTS_BASE:
            client = _httpx_client()
            r = client.post(
                _payments_url("/admin/roles"),
                json={"phone": phone, "role": "operator_bus"},
                headers=_payments_headers(),
                timeout=10,
            )
            if r.status_code >= 400:
                raise HTTPException(status_code=r.status_code, detail=r.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"granting operator_bus role failed: {e}")

    return {
        "phone": phone,
        "company_name": company_name,
        "wallet_id": wallet_id,
        "bus_operator_id": operator_id,
        "role": "operator_bus",
    }

@app.delete("/admin/roles")
async def bff_roles_remove(request: Request):
    _require_superadmin(request)
    try:
        body = await request.json()
    except Exception:
        body = None
    try:
        target_phone = ""
        target_role = ""
        try:
            if isinstance(body, dict):
                target_phone = (body.get("phone") or "").strip()
                target_role = (body.get("role") or "").strip()
        except Exception:
            target_phone = ""
            target_role = ""
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                ru = _PayRoleUpsert(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            try:
                with _pay_internal_session() as s:
                    return _pay_roles_remove(body=ru, s=s, admin_ok=True)
            except HTTPException:
                raise
            except Exception as e:
                raise HTTPException(status_code=502, detail=str(e))
        r = httpx.delete(
            _payments_url("/admin/roles"),
            json=body,
            headers=_payments_headers(),
            timeout=10,
        )
        resp = r.json()
        _audit_from_request(request, "admin_role_remove", target_phone=target_phone, target_role=target_role)
        return resp
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/dev/ping")
def dev_ping() -> dict[str, str]:
    """
    Lightweight health endpoint to verify that the current BFF build
    (including admin role routes) is deployed correctly.
    """
    # Reduce unnecessary public endpoints in prod/staging.
    env = _env_or("ENV", "dev").lower()
    if env not in ("dev", "test"):
        raise HTTPException(status_code=404, detail="not found")
    return {"status": "ok", "component": "bff", "kind": "dev-ping"}


@app.post("/dev/seed_demo")
async def dev_seed_demo(request: Request):
    """
    Create a small set of demo users and roles for local/dev environments.

    - Only available when ENV is dev or test.
    - Requires a valid Superadmin session.
    - Idempotent: re-running will not duplicate users or roles.
    """
    env = _env_or("ENV", "dev").lower()
    if env not in ("dev", "test"):
        # Do not expose this endpoint outside dev/test.
        raise HTTPException(status_code=404, detail="not found")

    phone = _auth_phone(request)
    if not phone or not _is_superadmin(phone):
        raise HTTPException(status_code=403, detail="superadmin required")

    # Static demo accounts covering the supported domains.
    demo_accounts: list[dict[str, Any]] = [
        {
            "phone": "+963000000001",
            "label": "Enduser demo (wallet only)",
            "roles": [],
        },
        {
            "phone": "+963000000003",
            "label": "Bus operator demo",
            "roles": ["operator_bus"],
        },
        {
            "phone": "+963000000010",
            "label": "Admin demo",
            "roles": ["admin"],
        },
    ]

    created: list[dict[str, Any]] = []
    errors: list[dict[str, Any]] = []

    try:
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            # Use internal Payments SQLAlchemy session for fast, idempotent seeding.
            with _pay_internal_session() as s:  # type: ignore[name-defined]
                for acc in demo_accounts:
                    ph = str(acc.get("phone") or "").strip()
                    if not ph:
                        continue
                    # Ensure user + wallet.
                    wallet_id: str | None = None
                    try:
                        data = {"phone": ph}
                        req_model = _PayCreateUserReq(**data)  # type: ignore[name-defined]
                        user = _pay_create_user(req_model, s=s)  # type: ignore[name-defined]
                        try:
                            wallet_id = getattr(user, "wallet_id", None) or getattr(user, "id", None)  # type: ignore[attr-defined]
                        except Exception:
                            wallet_id = None
                    except Exception as e:
                        errors.append({"phone": ph, "stage": "create_user", "error": str(e)})
                    # Ensure roles.
                    roles = [str(r) for r in (acc.get("roles") or [])]
                    for role in roles:
                        try:
                            ru = _PayRoleUpsert(phone=ph, role=role)  # type: ignore[name-defined]
                            _pay_roles_add(body=ru, s=s, admin_ok=True)  # type: ignore[name-defined]
                        except Exception as e:
                            errors.append({"phone": ph, "stage": f"role_add:{role}", "error": str(e)})
                    created.append(
                        {
                            "phone": ph,
                            "label": acc.get("label") or "",
                            "wallet_id": wallet_id,
                            "roles": roles,
                        }
                    )
        else:
            # Fallback: talk to external Payments API over HTTP, if configured.
            if not PAYMENTS_BASE:
                raise HTTPException(status_code=500, detail="PAYMENTS_BASE_URL not configured for seeding")
            for acc in demo_accounts:
                ph = str(acc.get("phone") or "").strip()
                if not ph:
                    continue
                wallet_id: str | None = None
                # Ensure user + wallet.
                try:
                    r = httpx.post(
                        _payments_url("/users"),
                        json={"phone": ph},
                        headers=_payments_headers(),
                        timeout=10,
                    )
                    if r.headers.get("content-type", "").startswith("application/json"):
                        j = r.json()
                        if isinstance(j, dict):
                            wallet_id = (j.get("wallet_id") or j.get("id"))  # type: ignore[assignment]
                except Exception as e:
                    errors.append({"phone": ph, "stage": "create_user_http", "error": str(e)})
                # Ensure roles via /admin/roles.
                roles = [str(r) for r in (acc.get("roles") or [])]
                for role in roles:
                    try:
                        body = {"phone": ph, "role": role}
                        httpx.post(
                            _payments_url("/admin/roles"),
                            json=body,
                            headers=_payments_headers(),
                            timeout=10,
                        )
                    except Exception as e:
                        errors.append({"phone": ph, "stage": f"role_add_http:{role}", "error": str(e)})
                created.append(
                    {
                        "phone": ph,
                        "label": acc.get("label") or "",
                        "wallet_id": wallet_id,
                        "roles": roles,
                    }
                )
    except HTTPException:
        raise
    except Exception as e:
        errors.append({"error": str(e), "stage": "seed_demo_global"})

    # Light audit entry so we can see in logs when demo data was seeded.
    _audit_from_request(request, "dev_seed_demo", env=env, accounts=len(demo_accounts), errors=len(errors))

    return {
        "ok": True,
        "env": env,
        "accounts": created,
        "errors": errors,
    }

@app.get("/admin/topup-sellers", response_class=HTMLResponse)
def bff_roles_admin_page(request: Request):
    _require_admin_v2(request)
    # Legacy HTML-Seite entfernt – bitte Shamell verwenden.
    return _legacy_console_removed_page("Shamell · Topup sellers")
@app.get("/me/roles")
def me_roles(request: Request):
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    roles = _get_effective_roles(phone)
    return {"phone": phone, "roles": roles}


@app.post("/auth/devices/register", response_class=JSONResponse)
async def auth_devices_register(request: Request) -> dict[str, Any]:
    """
    Registriert oder aktualisiert einen Geräte-Eintrag für den aktuellen Benutzer.

    Wird vom Client nach erfolgreichem Login aufgerufen und bildet die
    Basis für eine Geräte-Liste im Me-Tab (Multi-Device à la WeChat).
    """
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    try:
        body = await request.json()
    except Exception:
        body = {}
    if not isinstance(body, dict):
        body = {}
    device_id = _normalize_device_id(str(body.get("device_id") or ""))
    if not device_id:
        raise HTTPException(status_code=400, detail="device_id required")
    device_type = (body.get("device_type") or "").strip() or None
    device_name = (body.get("device_name") or "").strip() or None
    platform = (body.get("platform") or "").strip() or None
    app_version = (body.get("app_version") or "").strip() or None
    ip = _auth_client_ip(request)
    ua = request.headers.get("user-agent") or request.headers.get("User-Agent")
    with _officials_session() as s:
        row = (
            s.execute(
                _sa_select(DeviceSessionDB).where(
                    DeviceSessionDB.phone == phone,
                    DeviceSessionDB.device_id == device_id,
                )
            )
            .scalars()
            .first()
        )
        now = datetime.now(timezone.utc)
        if row:
            row.device_type = device_type or row.device_type
            row.device_name = device_name or row.device_name
            row.platform = platform or row.platform
            row.app_version = app_version or row.app_version
            row.last_ip = ip or row.last_ip
            row.user_agent = ua or row.user_agent
            row.last_seen_at = now
        else:
            row = DeviceSessionDB(
                phone=phone,
                device_id=device_id,
                device_type=device_type,
                device_name=device_name,
                platform=platform,
                app_version=app_version,
                last_ip=ip,
                user_agent=ua,
                last_seen_at=now,
            )

        # Bind the current auth session to this device id so device removal can revoke sessions.
        try:
            sid = _extract_session_id_from_request(request)
            if sid:
                sess_row = (
                    s.execute(
                        _sa_select(AuthSessionDB).where(  # type: ignore[name-defined]
                            AuthSessionDB.sid_hash == _sha256_hex(sid),  # type: ignore[name-defined]
                            AuthSessionDB.phone == phone,  # type: ignore[name-defined]
                        )
                    )
                    .scalars()
                    .first()
                )
                if sess_row and not getattr(sess_row, "revoked_at", None):
                    sess_row.device_id = device_id
                    s.add(sess_row)
        except Exception:
            pass

        s.add(row)
        s.commit()
        s.refresh(row)
        return {
            "id": row.id,
            "phone": row.phone,
            "device_id": row.device_id,
            "device_type": row.device_type,
            "device_name": row.device_name,
            "platform": row.platform,
            "app_version": row.app_version,
            "last_ip": row.last_ip,
            "user_agent": row.user_agent,
            "created_at": getattr(row, "created_at", None),
            "last_seen_at": getattr(row, "last_seen_at", None),
        }


@app.post("/auth/device_login/start", response_class=JSONResponse)
async def auth_device_login_start(request: Request) -> dict[str, Any]:
    """
    Startet einen QR‑Login‑Flow für ein neues Gerät (z.B. Web/Desktop).

    Unauthenticated endpoint: erstellt ein kurzlebiges Token, das als QR‑Code
    dargestellt werden kann (z.B. shamell://device_login?token=...).
    Das eigentliche Binden an einen Account passiert erst, wenn der Nutzer
    den Login auf dem Telefon bestätigt.
    """
    try:
      body = await request.json()
    except Exception:
      body = {}
    if not isinstance(body, dict):
        body = {}
    label = (body.get("label") or "").strip()
    if len(label) > 64:
        label = label[:64]
    device_id = _normalize_device_id(str(body.get("device_id") or ""))

    # Abuse guard: unauthenticated endpoint; rate-limit per IP (best-effort).
    try:
        ip = _auth_client_ip(request)
        if ip and ip != "unknown":
            hits = _rate_limit_bucket(
                _DEVICE_LOGIN_START_RATE_IP,
                ip,
                window_secs=max(1, DEVICE_LOGIN_START_RATE_WINDOW_SECS),
                max_hits=max(0, DEVICE_LOGIN_START_MAX_PER_IP),
            )
            if DEVICE_LOGIN_START_MAX_PER_IP > 0 and hits > DEVICE_LOGIN_START_MAX_PER_IP:
                raise HTTPException(status_code=429, detail="rate limited")
    except HTTPException:
        raise
    except Exception:
        # Rate limiting must never break the login flow.
        pass

    token = _secrets.token_hex(16)  # 32 hex chars
    now = _now()
    mem_rec = {
        "created_at": now,
        "status": "pending",
        "label": label,
        "device_id": device_id,
        "phone": None,
        "session": None,
    }
    # Persist challenge in DB (multi-instance safe); fall back to memory in dev/test.
    try:
        expires_dt = datetime.now(timezone.utc) + timedelta(seconds=max(1, DEVICE_LOGIN_TTL_SECS))
        with _officials_session() as s:  # type: ignore[name-defined]
            s.add(
                DeviceLoginChallengeDB(  # type: ignore[name-defined]
                    token_hash=_sha256_hex(token),
                    label=label or None,
                    status="pending",
                    phone=None,
                    device_id=device_id,
                    approved_at=None,
                    expires_at=expires_dt,
                )
            )
            s.commit()
    except Exception:
        _DEVICE_LOGIN_CHALLENGES[token] = mem_rec
    else:
        # Keep a small in-memory mirror for fast same-process flows.
        _DEVICE_LOGIN_CHALLENGES[token] = mem_rec
    return {"ok": True, "token": token, "label": label}


@app.post("/auth/device_login/approve", response_class=JSONResponse)
async def auth_device_login_approve(request: Request) -> dict[str, Any]:
    """
    Wird vom authentifizierten Telefon aufgerufen, nachdem ein QR‑Code
    für den Geräte‑Login gescannt wurde. Markiert das Token als genehmigt
    und erzeugt eine Session, die später vom neuen Gerät eingelöst wird.
    """
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    try:
        body = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="invalid body")
    if not isinstance(body, dict):
        raise HTTPException(status_code=400, detail="invalid body")
    token = (body.get("token") or "").strip()
    token = _normalize_device_login_token(token)
    if not token:
        raise HTTPException(status_code=400, detail="token required")
    _cleanup_auth_state()

    # Prefer DB-backed challenges so approval survives restarts.
    try:
        token_hash = _sha256_hex(token)
        with _officials_session() as s:  # type: ignore[name-defined]
            row = (
                s.execute(
                    _sa_select(DeviceLoginChallengeDB)  # type: ignore[name-defined]
                    .where(DeviceLoginChallengeDB.token_hash == token_hash)  # type: ignore[name-defined]
                    .limit(1)
                )
                .scalars()
                .first()
            )
            if row:
                exp_dt = getattr(row, "expires_at", None)
                exp_ts = _dt_to_epoch_secs(exp_dt) if isinstance(exp_dt, datetime) else 0
                if exp_ts and exp_ts < _now():
                    try:
                        s.delete(row)
                        s.commit()
                    except Exception:
                        pass
                    raise HTTPException(status_code=400, detail="challenge expired")
                status = str(getattr(row, "status", "") or "").strip().lower()
                bound = str(getattr(row, "phone", "") or "").strip() or None
                if status == "approved":
                    if bound and bound != phone:
                        raise HTTPException(status_code=409, detail="challenge already approved")
                    return {"ok": True, "token": token}
                if status != "pending":
                    raise HTTPException(status_code=400, detail="challenge not pending")
                row.status = "approved"
                row.phone = phone
                row.approved_at = datetime.now(timezone.utc)
                s.add(row)
                s.commit()
                return {"ok": True, "token": token}
    except HTTPException:
        raise
    except Exception:
        # Fall back to legacy in-memory store below.
        pass

    # Legacy in-memory fallback.
    rec = _DEVICE_LOGIN_CHALLENGES.get(token)
    if not rec:
        raise HTTPException(status_code=404, detail="challenge not found")
    try:
        created = int(rec.get("created_at") or 0)
    except Exception:
        created = 0
    if created <= 0 or created + DEVICE_LOGIN_TTL_SECS < _now():
        try:
            _DEVICE_LOGIN_CHALLENGES.pop(token, None)
        except Exception:
            pass
        raise HTTPException(status_code=400, detail="challenge expired")
    rec["status"] = "approved"
    rec["phone"] = phone
    rec["approved_at"] = _now()
    _DEVICE_LOGIN_CHALLENGES[token] = rec
    return {"ok": True, "token": token}


@app.post("/auth/device_login/redeem", response_class=JSONResponse)
async def auth_device_login_redeem(request: Request):
    """
    Wird vom neuen Gerät (z.B. Web/Desktop) aufgerufen, nachdem der Nutzer
    den QR‑Login auf dem Telefon bestätigt hat. Liefert eine Session‑ID und
    setzt optional das sa_session‑Cookie.
    """
    try:
        body = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="invalid body")
    if not isinstance(body, dict):
        raise HTTPException(status_code=400, detail="invalid body")
    token = _normalize_device_login_token((body.get("token") or "").strip())
    if not token:
        raise HTTPException(status_code=400, detail="token required")
    device_id_req = _normalize_device_id(str(body.get("device_id") or ""))
    _cleanup_auth_state()

    # Prefer DB-backed challenges so redeem works across restarts.
    try:
        token_hash = _sha256_hex(token)
        now_ts = _now()
        exp_ts = now_ts + AUTH_SESSION_TTL_SECS
        sid = _secrets.token_hex(16)
        exp_dt = datetime.fromtimestamp(exp_ts, timezone.utc)
        with _officials_session() as s:  # type: ignore[name-defined]
            row = (
                s.execute(
                    _sa_select(DeviceLoginChallengeDB)  # type: ignore[name-defined]
                    .where(DeviceLoginChallengeDB.token_hash == token_hash)  # type: ignore[name-defined]
                    .limit(1)
                )
                .scalars()
                .first()
            )
            if row:
                exp_dt_row = getattr(row, "expires_at", None)
                exp_ts_row = _dt_to_epoch_secs(exp_dt_row) if isinstance(exp_dt_row, datetime) else 0
                if exp_ts_row and exp_ts_row < _now():
                    try:
                        s.delete(row)
                        s.commit()
                    except Exception:
                        pass
                    raise HTTPException(status_code=400, detail="challenge expired")
                status = str(getattr(row, "status", "") or "").strip().lower()
                if status != "approved":
                    raise HTTPException(status_code=400, detail="challenge not approved")
                phone = str(getattr(row, "phone", "") or "").strip()
                if not phone:
                    raise HTTPException(status_code=400, detail="challenge not bound to user")
                dev = _normalize_device_id(str(getattr(row, "device_id", "") or "")) or device_id_req

                # Mint a fresh session and consume the challenge in one commit.
                s.add(
                    AuthSessionDB(  # type: ignore[name-defined]
                        sid_hash=_sha256_hex(sid),
                        phone=phone,
                        device_id=dev,
                        expires_at=exp_dt,
                    )
                )
                try:
                    s.delete(row)
                except Exception:
                    pass
                s.commit()
                _SESSIONS[sid] = (phone, exp_ts)
                resp = JSONResponse({"ok": True, "phone": phone, "session": sid})
                resp.set_cookie(
                    "sa_session",
                    sid,
                    max_age=AUTH_SESSION_TTL_SECS,
                    httponly=True,
                    secure=True,
                    samesite="lax",
                    path="/",
                )
                return resp
    except HTTPException:
        raise
    except Exception:
        # Fall back to legacy in-memory store below.
        pass

    # Legacy in-memory fallback.
    rec = _DEVICE_LOGIN_CHALLENGES.get(token)
    if not rec:
        raise HTTPException(status_code=404, detail="challenge not found")
    try:
        created = int(rec.get("created_at") or 0)
    except Exception:
        created = 0
    if created <= 0 or created + DEVICE_LOGIN_TTL_SECS < _now():
        try:
            _DEVICE_LOGIN_CHALLENGES.pop(token, None)
        except Exception:
            pass
        raise HTTPException(status_code=400, detail="challenge expired")
    status = (rec.get("status") or "").strip().lower()
    if status != "approved":
        raise HTTPException(status_code=400, detail="challenge not approved")
    phone = (rec.get("phone") or "").strip()
    if not phone:
        raise HTTPException(status_code=400, detail="challenge not bound to user")
    dev_mem = _normalize_device_id(str(rec.get("device_id") or "")) or device_id_req
    sid = _create_session(phone, device_id=dev_mem)
    try:
        _DEVICE_LOGIN_CHALLENGES.pop(token, None)
    except Exception:
        pass
    resp = JSONResponse({"ok": True, "phone": phone, "session": sid})
    resp.set_cookie(
        "sa_session",
        sid,
        max_age=AUTH_SESSION_TTL_SECS,
        httponly=True,
        secure=True,
        samesite="lax",
        path="/",
    )
    return resp


@app.post("/calls/start", response_class=JSONResponse)
async def calls_start(request: Request) -> dict[str, Any]:
    """
    Start a 1:1 call.

    Policy (current): any authenticated user can call any E.164 phone.
    Abuse is mitigated with tight rate limits + short ringing TTL.
    """
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    if not CALLING_ENABLED:
        raise HTTPException(status_code=404, detail="not found")
    # Calls require server-minted LiveKit tokens; keep surfaces consistent.
    if not LIVEKIT_TOKEN_ENDPOINT_ENABLED:
        raise HTTPException(status_code=404, detail="not found")

    try:
        body = await request.json()
    except Exception:
        body = {}
    if not isinstance(body, dict):
        body = {}

    to_phone = _normalize_phone_e164(str(body.get("to_phone") or body.get("to") or ""))
    if not to_phone:
        raise HTTPException(status_code=400, detail="to_phone must be E.164")
    if to_phone == phone:
        raise HTTPException(status_code=400, detail="invalid to_phone")

    mode = str(body.get("mode") or "video").strip().lower()
    if mode not in ("audio", "video"):
        raise HTTPException(status_code=400, detail="invalid mode")

    # Rate limit: caller phone, caller IP, callee phone (anti-harassment).
    try:
        hits_phone = _rate_limit_bucket(
            _CALL_START_RATE_PHONE,
            phone,
            window_secs=CALL_RATE_WINDOW_SECS,
            max_hits=CALL_START_MAX_PER_PHONE,
        )
        if CALL_START_MAX_PER_PHONE > 0 and hits_phone > CALL_START_MAX_PER_PHONE:
            raise HTTPException(status_code=429, detail="rate limited")
        ip = _auth_client_ip(request)
        if ip and ip != "unknown":
            hits_ip = _rate_limit_bucket(
                _CALL_START_RATE_IP,
                ip,
                window_secs=CALL_RATE_WINDOW_SECS,
                max_hits=CALL_START_MAX_PER_IP,
            )
            if CALL_START_MAX_PER_IP > 0 and hits_ip > CALL_START_MAX_PER_IP:
                raise HTTPException(status_code=429, detail="rate limited")
        hits_callee = _rate_limit_bucket(
            _CALL_START_RATE_CALLEE,
            to_phone,
            window_secs=CALL_RATE_WINDOW_SECS,
            max_hits=CALL_START_MAX_PER_CALLEE,
        )
        if CALL_START_MAX_PER_CALLEE > 0 and hits_callee > CALL_START_MAX_PER_CALLEE:
            raise HTTPException(status_code=429, detail="rate limited")
    except HTTPException:
        raise
    except Exception:
        # Rate limiting must not hard-break calls.
        pass

    call_id = _secrets.token_hex(16)
    room = f"call_{call_id}"
    now_ts = _now()
    now_dt = datetime.fromtimestamp(now_ts, timezone.utc)
    ring_exp_dt = now_dt + timedelta(seconds=int(CALL_RING_TTL_SECS))
    exp_dt = now_dt + timedelta(seconds=int(CALL_MAX_TTL_SECS))

    try:
        with _officials_session() as s:  # type: ignore[name-defined]
            s.add(
                CallDB(  # type: ignore[name-defined]
                    call_id=call_id,
                    room=room,
                    from_phone=phone,
                    to_phone=to_phone,
                    mode=mode,
                    status="ringing",
                    ring_expires_at=ring_exp_dt,
                    expires_at=exp_dt,
                )
            )
            s.commit()
    except Exception:
        raise HTTPException(status_code=502, detail="failed to start call")

    _audit_from_request(
        request,
        "call_started",
        call_id=call_id[-6:],
        to_phone=to_phone,
        mode=mode,
        ring_ttl_secs=int(CALL_RING_TTL_SECS),
    )
    return {
        "ok": True,
        "call_id": call_id,
        "to_phone": to_phone,
        "from_phone": phone,
        "mode": mode,
        "status": "ringing",
        "ring_expires_at": ring_exp_dt.isoformat().replace("+00:00", "Z"),
        "expires_at": exp_dt.isoformat().replace("+00:00", "Z"),
    }


@app.get("/calls/incoming", response_class=JSONResponse)
def calls_incoming(request: Request, limit: int = 20) -> dict[str, Any]:
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    if not CALLING_ENABLED:
        raise HTTPException(status_code=404, detail="not found")
    if limit <= 0:
        limit = 20
    limit = min(limit, 50)
    now_dt = datetime.fromtimestamp(_now(), timezone.utc)
    items: list[dict[str, Any]] = []
    try:
        with _officials_session() as s:  # type: ignore[name-defined]
            rows = (
                s.execute(
                    _sa_select(CallDB)  # type: ignore[name-defined]
                    .where(
                        CallDB.to_phone == phone,  # type: ignore[name-defined]
                        CallDB.ended_at.is_(None),  # type: ignore[name-defined]
                        CallDB.expires_at > now_dt,  # type: ignore[name-defined]
                        (
                            (CallDB.status != "ringing")  # type: ignore[name-defined]
                            | (CallDB.ring_expires_at > now_dt)  # type: ignore[name-defined]
                        ),
                    )
                    .order_by(CallDB.id.desc())  # type: ignore[name-defined]
                    .limit(limit)
                )
                .scalars()
                .all()
            )
            for row in rows:
                items.append(
                    {
                        "call_id": row.call_id,
                        "from_phone": row.from_phone,
                        "to_phone": row.to_phone,
                        "mode": row.mode,
                        "status": row.status,
                        "created_at": row.created_at.isoformat().replace("+00:00", "Z") if row.created_at else None,
                        "ring_expires_at": row.ring_expires_at.isoformat().replace("+00:00", "Z")
                        if row.ring_expires_at
                        else None,
                        "accepted_at": row.accepted_at.isoformat().replace("+00:00", "Z")
                        if getattr(row, "accepted_at", None)
                        else None,
                    }
                )
    except Exception:
        items = []
    return {"ok": True, "calls": items}


@app.post("/calls/{call_id}/accept", response_class=JSONResponse)
def calls_accept(call_id: str, request: Request) -> dict[str, Any]:
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    if not CALLING_ENABLED:
        raise HTTPException(status_code=404, detail="not found")
    cid = _normalize_call_id(call_id)
    if not cid:
        raise HTTPException(status_code=400, detail="invalid call_id")
    now_ts = _now()
    now_dt = datetime.fromtimestamp(now_ts, timezone.utc)
    try:
        with _officials_session() as s:  # type: ignore[name-defined]
            row = (
                s.execute(
                    _sa_select(CallDB)  # type: ignore[name-defined]
                    .where(CallDB.call_id == cid)  # type: ignore[name-defined]
                    .limit(1)
                )
                .scalars()
                .first()
            )
            if not row:
                raise HTTPException(status_code=404, detail="call not found")
            if row.to_phone != phone:
                raise HTTPException(status_code=403, detail="forbidden")
            if row.ended_at is not None:
                raise HTTPException(status_code=400, detail="call ended")
            exp_ts = _dt_to_epoch_secs(getattr(row, "expires_at", None))
            if not exp_ts or exp_ts <= now_ts:
                raise HTTPException(status_code=400, detail="call expired")
            ring_ts = _dt_to_epoch_secs(getattr(row, "ring_expires_at", None))
            if row.status == "ringing" and (not ring_ts or ring_ts <= now_ts):
                row.status = "missed"
                try:
                    s.commit()
                except Exception:
                    pass
                raise HTTPException(status_code=400, detail="call expired")
            if row.status != "accepted":
                row.status = "accepted"
                row.accepted_at = now_dt  # type: ignore[assignment]
                s.commit()
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(status_code=502, detail="failed to accept call")

    _audit_from_request(
        request,
        "call_accepted",
        call_id=cid[-6:],
    )
    return {"ok": True, "call_id": cid, "status": "accepted"}


@app.post("/calls/{call_id}/reject", response_class=JSONResponse)
def calls_reject(call_id: str, request: Request) -> dict[str, Any]:
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    if not CALLING_ENABLED:
        raise HTTPException(status_code=404, detail="not found")
    cid = _normalize_call_id(call_id)
    if not cid:
        raise HTTPException(status_code=400, detail="invalid call_id")
    now_ts = _now()
    now_dt = datetime.fromtimestamp(now_ts, timezone.utc)
    try:
        with _officials_session() as s:  # type: ignore[name-defined]
            row = (
                s.execute(
                    _sa_select(CallDB)  # type: ignore[name-defined]
                    .where(CallDB.call_id == cid)  # type: ignore[name-defined]
                    .limit(1)
                )
                .scalars()
                .first()
            )
            if not row:
                raise HTTPException(status_code=404, detail="call not found")
            if row.to_phone != phone:
                raise HTTPException(status_code=403, detail="forbidden")
            if row.ended_at is not None:
                raise HTTPException(status_code=400, detail="call ended")
            exp_ts = _dt_to_epoch_secs(getattr(row, "expires_at", None))
            if not exp_ts or exp_ts <= now_ts:
                row.status = "missed"
                try:
                    s.commit()
                except Exception:
                    pass
                raise HTTPException(status_code=400, detail="call expired")
            row.status = "rejected"
            row.ended_at = now_dt  # type: ignore[assignment]
            row.ended_by_phone = phone  # type: ignore[assignment]
            s.commit()
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(status_code=502, detail="failed to reject call")

    _audit_from_request(
        request,
        "call_rejected",
        call_id=cid[-6:],
    )
    return {"ok": True, "call_id": cid, "status": "rejected"}


@app.post("/calls/{call_id}/end", response_class=JSONResponse)
def calls_end(call_id: str, request: Request) -> dict[str, Any]:
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    if not CALLING_ENABLED:
        raise HTTPException(status_code=404, detail="not found")
    cid = _normalize_call_id(call_id)
    if not cid:
        raise HTTPException(status_code=400, detail="invalid call_id")
    now_dt = datetime.fromtimestamp(_now(), timezone.utc)
    try:
        with _officials_session() as s:  # type: ignore[name-defined]
            row = (
                s.execute(
                    _sa_select(CallDB)  # type: ignore[name-defined]
                    .where(CallDB.call_id == cid)  # type: ignore[name-defined]
                    .limit(1)
                )
                .scalars()
                .first()
            )
            if not row:
                raise HTTPException(status_code=404, detail="call not found")
            if phone not in (row.from_phone, row.to_phone):
                raise HTTPException(status_code=403, detail="forbidden")
            if row.ended_at is None:
                row.ended_at = now_dt  # type: ignore[assignment]
                row.ended_by_phone = phone  # type: ignore[assignment]
            row.status = "ended"
            s.commit()
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(status_code=502, detail="failed to end call")

    _audit_from_request(
        request,
        "call_ended",
        call_id=cid[-6:],
    )
    return {"ok": True, "call_id": cid, "status": "ended"}


@app.post("/livekit/token", response_class=JSONResponse)
async def livekit_token(request: Request) -> dict[str, Any]:
    """
    Mint a LiveKit access token for an authenticated user.

    LiveKit itself can be publicly reachable, but joining requires a server-minted
    token signed with LIVEKIT_API_SECRET.
    """
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")

    if not LIVEKIT_TOKEN_ENDPOINT_ENABLED:
        raise HTTPException(status_code=404, detail="not found")

    # Enforce sane config in prod/staging when the endpoint is enabled.
    if _ENV_LOWER in ("prod", "production", "staging"):
        if not LIVEKIT_API_KEY or not LIVEKIT_API_SECRET:
            raise HTTPException(status_code=503, detail="livekit not configured")
        if LIVEKIT_API_KEY in ("devkey", "change-me") or LIVEKIT_API_SECRET in ("devsecret", "change-me"):
            raise HTTPException(status_code=503, detail="livekit not configured")
        # Don't fall back to the internal docker URL in prod/staging; require an explicit public URL.
        raw_public_url = (os.getenv("LIVEKIT_PUBLIC_URL") or "").strip()
        if not raw_public_url:
            raise HTTPException(status_code=503, detail="livekit not configured")
        raw_public_norm = raw_public_url.lower()
        # Require TLS outside dev/test (wss/https). ws/http risks token leakage and MITM.
        if raw_public_norm.startswith("ws://") or raw_public_norm.startswith("http://"):
            raise HTTPException(status_code=503, detail="livekit not configured")
        # Never leak internal docker URLs to clients (misconfiguration safeguard).
        if "livekit:7880" in raw_public_norm or raw_public_norm.startswith("ws://livekit") or raw_public_norm.startswith("http://livekit"):
            raise HTTPException(status_code=503, detail="livekit not configured")

    if not LIVEKIT_PUBLIC_URL:
        raise HTTPException(status_code=503, detail="livekit not configured")

    try:
        body = await request.json()
    except Exception:
        body = {}
    if not isinstance(body, dict):
        body = {}

    call_id = _normalize_call_id(str(body.get("call_id") or body.get("id") or ""))
    room = ""
    call_exp_ts: int | None = None
    if call_id:
        # Call-minted tokens are only available when the calling feature is enabled.
        if not CALLING_ENABLED:
            raise HTTPException(status_code=404, detail="not found")
        now_ts_call = _now()
        now_dt = datetime.fromtimestamp(now_ts_call, timezone.utc)
        try:
            with _officials_session() as s:  # type: ignore[name-defined]
                row = (
                    s.execute(
                        _sa_select(CallDB)  # type: ignore[name-defined]
                        .where(CallDB.call_id == call_id)  # type: ignore[name-defined]
                        .limit(1)
                    )
                    .scalars()
                    .first()
                )
                if not row:
                    raise HTTPException(status_code=404, detail="call not found")
                if phone not in (row.from_phone, row.to_phone):
                    raise HTTPException(status_code=403, detail="forbidden")
                if row.ended_at is not None or row.status in ("ended", "rejected", "missed", "canceled"):
                    raise HTTPException(status_code=400, detail="call ended")
                exp_ts = _dt_to_epoch_secs(getattr(row, "expires_at", None))
                if not exp_ts or exp_ts <= now_ts_call:
                    try:
                        row.status = "missed"
                        s.commit()
                    except Exception:
                        pass
                    raise HTTPException(status_code=400, detail="call expired")
                ring_ts = _dt_to_epoch_secs(getattr(row, "ring_expires_at", None))
                if row.status == "ringing" and (not ring_ts or ring_ts <= now_ts_call):
                    try:
                        row.status = "missed"
                        s.commit()
                    except Exception:
                        pass
                    raise HTTPException(status_code=400, detail="call expired")
                # If the callee mints a token, treat that as an implicit accept.
                if row.status == "ringing" and row.to_phone == phone:
                    try:
                        row.status = "accepted"
                        row.accepted_at = now_dt  # type: ignore[assignment]
                        s.commit()
                    except Exception:
                        pass
                room = str(row.room or "").strip()
                call_exp_ts = _dt_to_epoch_secs(row.expires_at) if getattr(row, "expires_at", None) else None
        except HTTPException:
            raise
        except Exception:
            raise HTTPException(status_code=502, detail="call lookup failed")
        if not room or not re.fullmatch(r"[A-Za-z0-9_-]{4,128}", room):
            raise HTTPException(status_code=500, detail="invalid call room")
    else:
        # In non-dev environments, do not expose "mint arbitrary room token" capability.
        if _ENV_LOWER not in ("dev", "test"):
            raise HTTPException(status_code=400, detail="call_id required")
        room = str(body.get("room") or "").strip()
        if not room:
            room = f"call_{_secrets.token_hex(8)}"
        if not re.fullmatch(r"[A-Za-z0-9_-]{4,128}", room):
            raise HTTPException(status_code=400, detail="invalid room")

    ttl = LIVEKIT_TOKEN_TTL_SECS_DEFAULT
    try:
        ttl = int(body.get("ttl_secs") or ttl)
    except Exception:
        ttl = LIVEKIT_TOKEN_TTL_SECS_DEFAULT
    ttl = max(30, min(int(ttl), max(30, int(LIVEKIT_TOKEN_MAX_TTL_SECS))))
    # Never mint a token that outlives the call record (defense-in-depth).
    if call_exp_ts:
        remaining = int(call_exp_ts - _now())
        if remaining <= 0:
            raise HTTPException(status_code=400, detail="call expired")
        ttl = max(30, min(ttl, remaining))

    # Rate-limit token minting (best-effort).
    try:
        hits_phone = _rate_limit_bucket(
            _LIVEKIT_TOKEN_RATE_PHONE,
            phone,
            window_secs=max(1, LIVEKIT_TOKEN_RATE_WINDOW_SECS),
            max_hits=max(0, LIVEKIT_TOKEN_MAX_PER_PHONE),
        )
        if LIVEKIT_TOKEN_MAX_PER_PHONE > 0 and hits_phone > LIVEKIT_TOKEN_MAX_PER_PHONE:
            raise HTTPException(status_code=429, detail="rate limited")
        ip = _auth_client_ip(request)
        if ip and ip != "unknown":
            hits_ip = _rate_limit_bucket(
                _LIVEKIT_TOKEN_RATE_IP,
                ip,
                window_secs=max(1, LIVEKIT_TOKEN_RATE_WINDOW_SECS),
                max_hits=max(0, LIVEKIT_TOKEN_MAX_PER_IP),
            )
            if LIVEKIT_TOKEN_MAX_PER_IP > 0 and hits_ip > LIVEKIT_TOKEN_MAX_PER_IP:
                raise HTTPException(status_code=429, detail="rate limited")
    except HTTPException:
        raise
    except Exception:
        pass

    # Try to derive a stable per-device identity if the session is device-bound.
    sid = _extract_session_id_from_request(request)
    device_id = None
    try:
        if sid:
            with _officials_session() as s:  # type: ignore[name-defined]
                row = (
                    s.execute(
                        _sa_select(AuthSessionDB).where(  # type: ignore[name-defined]
                            AuthSessionDB.sid_hash == _sha256_hex(sid),  # type: ignore[name-defined]
                            AuthSessionDB.phone == phone,  # type: ignore[name-defined]
                        )
                    )
                    .scalars()
                    .first()
                )
                if row:
                    device_id = _normalize_device_id(str(getattr(row, "device_id", "") or ""))
    except Exception:
        device_id = None

    identity = _livekit_identity(phone=phone, device_id=device_id, sid=sid)
    now_ts = _now()
    exp_ts = now_ts + ttl
    payload = {
        "iss": LIVEKIT_API_KEY,
        "sub": identity,
        "nbf": now_ts,
        "exp": exp_ts,
        "video": {
            "room": room,
            "roomJoin": True,
            "canPublish": True,
            "canSubscribe": True,
            "canPublishData": True,
        },
    }
    token = _jwt_hs256(LIVEKIT_API_SECRET, payload)
    if not token:
        raise HTTPException(status_code=500, detail="failed to mint token")

    _audit_from_request(
        request,
        "livekit_token_minted",
        call_id=(call_id[-6:] if call_id else None),
        room=room,
        ttl=ttl,
        device_id=device_id,
    )
    return {"ok": True, "url": LIVEKIT_PUBLIC_URL, "room": room, "token": token, "ttl_secs": ttl}

@app.get("/auth/devices", response_class=JSONResponse)
def auth_devices_list(request: Request) -> dict[str, Any]:
    """
    Listet registrierte Geräte des aktuellen Benutzers auf.
    """
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    with _officials_session() as s:
        rows = (
            s.execute(
                _sa_select(DeviceSessionDB)
                .where(DeviceSessionDB.phone == phone)
                .order_by(DeviceSessionDB.last_seen_at.desc(), DeviceSessionDB.id.desc())
            )
            .scalars()
            .all()
        )
        items: list[dict[str, Any]] = []
        for row in rows:
            items.append(
                {
                    "id": row.id,
                    "phone": row.phone,
                    "device_id": row.device_id,
                    "device_type": row.device_type,
                    "device_name": row.device_name,
                    "platform": row.platform,
                    "app_version": row.app_version,
                    "last_ip": row.last_ip,
                    "user_agent": row.user_agent,
                    "created_at": getattr(row, "created_at", None),
                    "last_seen_at": getattr(row, "last_seen_at", None),
                }
            )
    return {"devices": items}


@app.delete("/auth/devices/{device_id}", response_class=JSONResponse)
def auth_devices_delete(device_id: str, request: Request) -> dict[str, Any]:
    """
    Entfernt einen Geräte-Eintrag für den aktuellen Benutzer.

    Best practice: removing a device should also revoke sessions bound
    to that device so stolen cookies/tokens cannot remain active.
    """
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    clean = _normalize_device_id(device_id)
    if not clean:
        raise HTTPException(status_code=400, detail="device_id required")
    with _officials_session() as s:
        row = (
            s.execute(
                _sa_select(DeviceSessionDB).where(
                    DeviceSessionDB.phone == phone,
                    DeviceSessionDB.device_id == clean,
                )
            )
            .scalars()
            .first()
        )
        if not row:
            return {"status": "ignored"}
        s.delete(row)
        revoked = 0
        try:
            # Revoke all DB-backed sessions associated with this device.
            # (No session IDs are stored in plaintext; we delete by device_id.)
            res = s.execute(
                _sa_delete(AuthSessionDB).where(  # type: ignore[name-defined]
                    AuthSessionDB.phone == phone,  # type: ignore[name-defined]
                    AuthSessionDB.device_id == clean,  # type: ignore[name-defined]
                )
            )
            try:
                revoked = int(getattr(res, "rowcount", 0) or 0)
            except Exception:
                revoked = 0
        except Exception:
            revoked = 0
        s.commit()
    # Also evict any in-memory cached sessions that were tied to this device, if possible.
    # We cannot reverse hashes to sids, so we rely on DB being the source of truth.
    _audit("auth_device_removed", phone=phone, device_id=clean, revoked_sessions=revoked)
    return {"status": "ok", "revoked_sessions": revoked}


@app.post("/me/dsr/export")
async def me_dsr_export(request: Request):
    """
    Lightweight endpoint for Data Subject export requests.
    It does not perform the export itself, but records the intent via audit log.
    """
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    try:
        body = await request.json()
    except Exception:
        body = {}
    reason = ""
    contact = ""
    if isinstance(body, dict):
        try:
            reason = str(body.get("reason") or "")
            contact = str(body.get("contact") or "")
        except Exception:
            reason = ""
            contact = ""
    _audit("dsr_export_request", phone=phone, reason=reason, contact=contact)
    return {"status": "accepted", "kind": "export"}


@app.post("/me/dsr/delete")
async def me_dsr_delete(request: Request):
    """
    Lightweight endpoint for Data Subject deletion requests.
    It records the request via audit log so that backoffice tools can act on it.
    """
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    try:
        body = await request.json()
    except Exception:
        body = {}
    reason = ""
    contact = ""
    if isinstance(body, dict):
        try:
            reason = str(body.get("reason") or "")
            contact = str(body.get("contact") or "")
        except Exception:
            reason = ""
            contact = ""
    _audit("dsr_delete_request", phone=phone, reason=reason, contact=contact)
    return {"status": "accepted", "kind": "delete"}


@app.get("/topup/print_pdf/{batch_id}")
def topup_print_pdf(request: Request, batch_id: str):
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    is_admin = _is_admin(phone)
    if not is_admin:
        _require_seller(request)
    # Fetch vouchers
    try:
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            with _pay_internal_session() as s:  # type: ignore[name-defined]
                rows = _pay_topup_batch_detail(batch_id=batch_id, s=s, admin_ok=True)  # type: ignore[name-defined]
                arr = []
                for it in rows:
                    try:
                        if hasattr(it, "model_dump"):
                            arr.append(it.model_dump())  # type: ignore[attr-defined]
                        else:
                            arr.append(it.dict())  # type: ignore[call-arg]
                    except Exception:
                        arr.append({
                            "code": getattr(it, "code", ""),
                            "amount_cents": getattr(it, "amount_cents", 0),
                            "payload": getattr(it, "payload", ""),
                            "seller_id": getattr(it, "seller_id", None),
                        })
        else:
            if not PAYMENTS_INTERNAL_SECRET:
                raise HTTPException(status_code=403, detail="Server not configured for topup admin")
            r = httpx.get(
                _payments_url(f"/topup/batches/{batch_id}"),
                headers=_payments_headers(),
                timeout=15,
            )
            arr = r.json() if r.headers.get('content-type','').startswith('application/json') else []
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"fetch batch failed: {e}")
    if not isinstance(arr, list):
        arr = []
    if len(arr) > TOPUP_PRINT_MAX_ITEMS:
        raise HTTPException(status_code=413, detail="batch too large to print")
    # Ownership check: sellers may only print their own batch.
    if not is_admin and arr:
        seller_ids = set()
        for v in arr:
            if not isinstance(v, dict):
                continue
            sid = str((v.get("seller_id") or "")).strip()
            if sid:
                seller_ids.add(sid)
        if not seller_ids:
            raise HTTPException(status_code=403, detail="batch owner unknown")
        if seller_ids != {phone}:
            raise HTTPException(status_code=403, detail="batch does not belong to caller")
    _audit_from_request(request, "topup_print_batch_pdf", batch_id=batch_id)
    if _pdfcanvas is None or _qr is None:
        raise HTTPException(status_code=500, detail="PDF/QR library not available")
    # Prepare PDF
    buf = BytesIO()
    c = _pdfcanvas.Canvas(buf, pagesize=A4)
    width, height = A4
    cols, rows = 3, 4
    cell_w = width / cols
    cell_h = height / rows
    x_margin = 12
    y_margin = 18
    i = 0
    for v in arr:
        if not isinstance(v, dict):
            continue
        payload = str(v.get("payload", "") or "")
        code = str(v.get("code", "") or "")
        try:
            amt = int(v.get("amount_cents", 0) or 0)
        except Exception:
            amt = 0
        # Make QR image
        try:
            q = _qr.QRCode(error_correction=_qr.constants.ERROR_CORRECT_M, box_size=6, border=2)
            q.add_data(payload)
            q.make(fit=True)
            img = q.make_image(fill_color="black", back_color="white")
            pil = img.convert('RGB') if hasattr(img, 'convert') else img
            img_reader = _RLImageReader(pil)
        except Exception:
            img_reader = None
        col = i % cols
        row = (i // cols) % rows
        if i > 0 and row == 0 and col == 0:
            c.showPage()
        # Compute coords (origin bottom-left)
        x = col * cell_w + x_margin
        y = height - ((row + 1) * cell_h) + y_margin
        # Draw QR centered in cell
        if img_reader:
            qr_size = min(cell_w - 2*x_margin, cell_h - 2*y_margin - 20)
            c.drawImage(img_reader, x + (cell_w - qr_size)/2, y + (cell_h - qr_size)/2, width=qr_size, height=qr_size, preserveAspectRatio=True, mask='auto')
        # Labels
        c.setFont("Helvetica", 9)
        c.drawCentredString(x + cell_w/2, y + 6, f"{code} • {amt} SYP")
        i += 1
    c.showPage()
    c.save()
    buf.seek(0)
    return StreamingResponse(buf, media_type='application/pdf')

@app.post("/payments/users")
async def payments_create_user(req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    if _use_pay_internal():
        if not _PAY_INTERNAL_AVAILABLE:
            raise HTTPException(status_code=500, detail="payments internal not available")
        data = body or {}
        if not isinstance(data, dict):
            data = {}
        try:
            req_model = _PayCreateUserReq(**data)
        except Exception as e:
            raise HTTPException(status_code=400, detail=str(e))
        try:
            with _pay_internal_session() as s:
                return _pay_create_user(req_model, s=s)
        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(status_code=502, detail=str(e))
    try:
        # Fallback: HTTP call to standalone Payments API if configured.
        r = httpx.post(
            _payments_url("/users"),
            json=body,
            headers=_payments_headers(),
            timeout=10,
        )
        return r.json()
    except HTTPException:
        # Already a structured HTTP error from upstream helper.
        raise
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/payments/wallets/{wallet_id}")
def payments_wallet(wallet_id: str, request: Request):
    phone, caller_wallet_id = _require_caller_wallet(request)
    if wallet_id != caller_wallet_id and not _is_admin(phone):
        raise HTTPException(status_code=403, detail="wallet does not belong to caller")
    if _use_pay_internal():
        if not _PAY_INTERNAL_AVAILABLE:
            raise HTTPException(status_code=500, detail="payments internal not available")
        try:
            with _pay_internal_session() as s:
                return _pay_get_wallet(wallet_id=wallet_id, s=s)
        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(status_code=502, detail=str(e))
    try:
        r = httpx.get(
            _payments_url(f"/wallets/{wallet_id}"),
            headers=_payments_headers(),
            timeout=10,
        )
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/payments/transfer")
async def payments_transfer(req: Request):
    # parse body (tolerate empty)
    try:
        body = await req.json()
    except Exception:
        body = None
    if not isinstance(body, dict):
        body = {}
    _phone, caller_wallet_id = _require_caller_wallet(req)
    from_wallet_id = str(body.get("from_wallet_id") or "").strip()
    if from_wallet_id and from_wallet_id != caller_wallet_id:
        _audit_from_request(
            req,
            "payments_transfer_wallet_mismatch",
            requested_wallet_id=from_wallet_id,
            caller_wallet_id=caller_wallet_id,
        )
        raise HTTPException(status_code=403, detail="from_wallet_id does not belong to caller")
    # Prevent wallet spoofing by forcing sender to caller-owned wallet.
    body["from_wallet_id"] = caller_wallet_id
    # forward idempotency and risk headers
    headers = {}
    try:
        ikey = req.headers.get("Idempotency-Key") if hasattr(req, 'headers') else None
        dev = req.headers.get("X-Device-ID") if hasattr(req, 'headers') else None
        ua = req.headers.get("User-Agent") if hasattr(req, 'headers') else None
    except Exception:
        ikey = None; dev = None; ua = None
    if ikey:
        headers["Idempotency-Key"] = ikey
    if dev:
        headers["X-Device-ID"] = dev
    if ua:
        headers["User-Agent"] = ua
    try:
        body = _normalize_amount(body)
        # Check guardrails before executing the payment (best-effort).
        if isinstance(body, dict):
            from_wallet_id = (body.get("from_wallet_id") or "") if body.get("from_wallet_id") is not None else ""
            amount_cents = body.get("amount_cents")
            _check_payment_guardrails(from_wallet_id, amount_cents, dev)

        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                req_model = _PayTransferReq(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            try:
                with _pay_internal_session() as s:
                    # Idempotency key is read from headers in the Payments API;
                    # simulating it via a request-like object is not needed here,
                    # because idempotency logic in the body (ikey) is not used.
                    result = _pay_transfer(req_model, request=req, s=s)
                try:
                    payload = {}
                    if isinstance(body, dict):
                        payload = {
                            "from_wallet_id": body.get("from_wallet_id"),
                            "to_wallet_id": body.get("to_wallet_id"),
                            "to_alias": body.get("to_alias"),
                            "amount_cents": body.get("amount_cents"),
                            "currency": body.get("currency"),
                            "device_id": dev,
                        }
                    emit_event("payments", "transfer", payload)
                except Exception:
                    pass
                return result
            except HTTPException:
                raise
            except Exception as e:
                raise HTTPException(status_code=502, detail=str(e))
        r = httpx.post(
            _payments_url("/transfer"),
            json=body,
            headers=_payments_headers(headers),
            timeout=10,
        )
        out = r.json()
        try:
            payload = {}
            if isinstance(body, dict):
                payload = {
                    "from_wallet_id": body.get("from_wallet_id"),
                    "to_wallet_id": body.get("to_wallet_id"),
                    "to_alias": body.get("to_alias"),
                    "amount_cents": body.get("amount_cents"),
                    "currency": body.get("currency"),
                    "device_id": dev,
                }
            emit_event("payments", "transfer", payload)
        except Exception:
            pass
        return out
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        # Guardrail or validation errors should be passed through directly
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/payments/wallets/{wallet_id}/topup")
async def payments_topup(wallet_id: str, req: Request):
    _require_admin_v2(req)
    dev_allow = _env_or("BFF_DEV_ALLOW_TOPUP", "false").lower() == "true"
    if not PAYMENTS_INTERNAL_SECRET and not dev_allow:
        raise HTTPException(status_code=403, detail="Server not configured for admin topup")
    try:
        body = await req.json()
    except Exception:
        body = None
    # Normalize amount payload once so both internal + HTTP paths share logic
    body = _normalize_amount(body)
    try:
        # Prefer internal Payments integration in internal mode to avoid
        # HTTP loops back into the same process.
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                req_model = _PayTopupReq(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            try:
                with _pay_internal_session() as s:
                    # Bypass require_admin dependency by passing admin_ok=True;
                    # BFF already enforced admin/secret above.
                    return _pay_wallet_topup(wallet_id=wallet_id, req=req_model, request=req, s=s, admin_ok=True)
            except HTTPException:
                raise
            except Exception as e:
                raise HTTPException(status_code=502, detail=str(e))

        headers: dict[str, str] = {}
        if PAYMENTS_INTERNAL_SECRET:
            headers["X-Internal-Secret"] = PAYMENTS_INTERNAL_SECRET
        try:
            ikey = req.headers.get("Idempotency-Key") if hasattr(req, "headers") else None
        except Exception:
            ikey = None
        if ikey:
            headers["Idempotency-Key"] = ikey
        r = httpx.post(
            _payments_url(f"/wallets/{wallet_id}/topup"),
            json=body,
            headers=_payments_headers(headers),
            timeout=10,
        )
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


# ---- Cash Mandate proxies ----
@app.post("/payments/cash/create")
async def payments_cash_create(req: Request):
    _require_admin_v2(req)
    if not PAYMENTS_INTERNAL_SECRET:
        raise HTTPException(status_code=403, detail="Server not configured for cash create")
    try:
        body = await req.json()
    except Exception:
        body = None
    headers = {"X-Internal-Secret": PAYMENTS_INTERNAL_SECRET}
    try:
        ikey = req.headers.get("Idempotency-Key") if hasattr(req, 'headers') else None
    except Exception:
        ikey = None
    if ikey:
        headers["Idempotency-Key"] = ikey
    try:
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                req_model = _PayCashCreateReq(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            try:
                # admin_ok=True because the BFF already protects via PAYMENTS_INTERNAL_SECRET
                with _pay_internal_session() as s:
                    return _pay_cash_create(req_model, request=req, s=s, admin_ok=True)
            except HTTPException:
                raise
            except Exception as e:
                raise HTTPException(status_code=502, detail=str(e))
        r = httpx.post(
            _payments_url("/cash/create"),
            json=body,
            headers=_payments_headers(headers),
            timeout=10,
        )
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


# ---- Favorites & Requests proxies ----
@app.post("/payments/favorites")
async def payments_fav_create(req: Request):
    phone, caller_wallet_id = _require_caller_wallet(req)
    can_admin = _is_admin(phone)
    _rate_limit_payments_edge(
        req,
        wallet_id=caller_wallet_id,
        scope="favorites_write",
        wallet_max=PAY_API_FAV_WRITE_MAX_PER_WALLET,
        ip_max=PAY_API_FAV_WRITE_MAX_PER_IP,
    )
    try:
        body = await req.json()
    except Exception:
        body = {}
    if not isinstance(body, dict):
        body = {}
    payload = dict(body)
    owner_wallet_id = str(payload.get("owner_wallet_id") or "").strip()
    if owner_wallet_id and owner_wallet_id != caller_wallet_id and not can_admin:
        _audit_from_request(
            req,
            "favorites_owner_wallet_mismatch",
            requested_wallet_id=owner_wallet_id,
            caller_wallet_id=caller_wallet_id,
        )
        raise HTTPException(status_code=403, detail="owner_wallet_id does not belong to caller")
    payload["owner_wallet_id"] = caller_wallet_id if not can_admin else (owner_wallet_id or caller_wallet_id)
    try:
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            data = payload or {}
            if not isinstance(data, dict):
                data = {}
            try:
                req_model = _PayFavoriteCreate(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            try:
                with _pay_internal_session() as s:
                    return _pay_create_favorite(req_model, s=s)
            except HTTPException:
                raise
            except Exception as e:
                raise HTTPException(status_code=502, detail=str(e))
        r = httpx.post(
            _payments_url("/favorites"),
            json=payload,
            headers=_payments_headers(),
            timeout=10,
        )
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/payments/favorites")
def payments_fav_list(request: Request, owner_wallet_id: str = ""):
    phone, caller_wallet_id = _require_caller_wallet(request)
    can_admin = _is_admin(phone)
    _rate_limit_payments_edge(
        request,
        wallet_id=caller_wallet_id,
        scope="favorites_read",
        wallet_max=PAY_API_FAV_READ_MAX_PER_WALLET,
        ip_max=PAY_API_FAV_READ_MAX_PER_IP,
    )
    requested_wallet_id = (owner_wallet_id or "").strip()
    if requested_wallet_id and requested_wallet_id != caller_wallet_id and not can_admin:
        raise HTTPException(status_code=403, detail="owner_wallet_id does not belong to caller")
    target_wallet_id = requested_wallet_id if requested_wallet_id else caller_wallet_id
    try:
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            try:
                with _pay_internal_session() as s:
                    return _pay_list_favorites(owner_wallet_id=target_wallet_id, s=s)
            except HTTPException:
                raise
            except Exception as e:
                raise HTTPException(status_code=502, detail=str(e))
        r = httpx.get(
            _payments_url("/favorites"),
            params={"owner_wallet_id": target_wallet_id},
            headers=_payments_headers(),
            timeout=10,
        )
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.delete("/payments/favorites/{fid}")
def payments_fav_delete(fid: str, request: Request):
    phone, caller_wallet_id = _require_caller_wallet(request)
    can_admin = _is_admin(phone)
    _rate_limit_payments_edge(
        request,
        wallet_id=caller_wallet_id,
        scope="favorites_write",
        wallet_max=PAY_API_FAV_WRITE_MAX_PER_WALLET,
        ip_max=PAY_API_FAV_WRITE_MAX_PER_IP,
    )
    fav_id = (fid or "").strip()
    if not fav_id:
        raise HTTPException(status_code=400, detail="favorite id required")
    try:
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            try:
                with _pay_internal_session() as s:
                    if not can_admin:
                        rows = _pay_list_favorites(owner_wallet_id=caller_wallet_id, s=s)
                        allowed = False
                        for row in rows or []:
                            try:
                                row_id = str(getattr(row, "id", "") or "")
                            except Exception:
                                row_id = ""
                            if row_id == fav_id:
                                allowed = True
                                break
                        if not allowed:
                            raise HTTPException(status_code=404, detail="favorite not found")
                    return _pay_delete_favorite(fid=fav_id, s=s)
            except HTTPException:
                raise
            except Exception as e:
                raise HTTPException(status_code=502, detail=str(e))
        if not can_admin:
            chk = httpx.get(
                _payments_url("/favorites"),
                params={"owner_wallet_id": caller_wallet_id},
                headers=_payments_headers(),
                timeout=10,
            )
            rows = chk.json() if chk.headers.get("content-type", "").startswith("application/json") else []
            allowed = False
            if isinstance(rows, list):
                for row in rows:
                    try:
                        row_id = str((row or {}).get("id") or "").strip()
                    except Exception:
                        row_id = ""
                    if row_id == fav_id:
                        allowed = True
                        break
            if not allowed:
                raise HTTPException(status_code=404, detail="favorite not found")
        r = httpx.delete(
            _payments_url(f"/favorites/{fav_id}"),
            headers=_payments_headers(),
            timeout=10,
        )
        return r.json() if r.headers.get("content-type", "").startswith("application/json") else {"raw": r.text}
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


# ---- Bus proxies (search, book, status, cities) ----
@app.get("/bus/cities")
def bus_cities(q: str = "", limit: int = 50):
    if _use_bus_internal():
        if not _BUS_INTERNAL_AVAILABLE:
            raise HTTPException(status_code=500, detail="bus internal not available")
        try:
            with _bus_internal_session() as s:
                return _bus_list_cities(q=q, limit=limit, s=s)
        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(status_code=502, detail=str(e))
    try:
        r = httpx.get(_bus_url("/cities"), params={"q": q, "limit": limit}, headers=_bus_headers(), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/bus/cities_cached")
def bus_cities_cached(limit: int = 50, response: Response = None):  # type: ignore[assignment]
    """
    Simplified cache for /bus/cities without search parameters.
    For q/filter please continue to use /bus/cities directly.
    """
    global _BUS_CITIES_CACHE
    # Do not enforce cache semantics for unusual limits
    if limit <= 0:
        limit = 50
    # Use cache only for standard case without filters
    if _BUS_CITIES_CACHE.get("data") is not None:
        try:
            ts = float(_BUS_CITIES_CACHE.get("ts") or 0.0)
        except Exception:
            ts = 0.0
        if time.time() - ts < 30.0:
            data = _BUS_CITIES_CACHE.get("data")
            try:
                if response is not None:
                    response.headers.setdefault("Cache-Control", "public, max-age=30")
            except Exception:
                pass
            return data
    data = bus_cities(q="", limit=limit)
    # Hide legacy test cities like "Origin City" / "Dest City" from
    # the cached list so that From/To dropdowns in the UI only show
    # real cities (e.g. Damascus, Aleppo, ...).
    try:
        if isinstance(data, list):
            def _name_for(x: Any) -> str:
                try:
                    if isinstance(x, dict):
                        return str(x.get("name", "") or "")
                    return str(getattr(x, "name", "") or "")
                except Exception:
                    return ""

            bad_prefixes = ("Origin City", "Dest City")
            data = [
                x for x in data
                if not _name_for(x).startswith(bad_prefixes)
            ]
    except Exception:
        # Never break the endpoint because of filtering issues.
        pass
    _BUS_CITIES_CACHE = {"ts": time.time(), "data": data}
    try:
        if response is not None:
            response.headers.setdefault("Cache-Control", "public, max-age=30")
    except Exception:
        pass
    return data


@app.get("/bus/trips/search")
def bus_trips_search(origin_city_id: str, dest_city_id: str, date: str):
    try:
        if _use_bus_internal():
            if not _BUS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="bus internal not available")
            with _bus_internal_session() as s:
                return _bus_search_trips(origin_city_id=origin_city_id, dest_city_id=dest_city_id, date=date, s=s)
        params = {"origin_city_id": origin_city_id, "dest_city_id": dest_city_id, "date": date}
        r = httpx.get(_bus_url("/trips/search"), params=params, headers=_bus_headers(), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/bus/trips/{trip_id}")
def bus_trip_detail(trip_id: str):
    if _use_bus_internal():
        if not _BUS_INTERNAL_AVAILABLE:
            raise HTTPException(status_code=500, detail="bus internal not available")
        try:
            with _bus_internal_session() as s:
                return _bus_trip_detail(trip_id=trip_id, s=s)
        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(status_code=502, detail=str(e))
    try:
        r = httpx.get(_bus_url(f"/trips/{trip_id}"), headers=_bus_headers(), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/bus/trips/{trip_id}/book")
async def bus_book(trip_id: str, req: Request):
    phone = _auth_phone(req)
    env_test = _ENV_LOWER == "test"
    if not phone and not env_test:
        raise HTTPException(status_code=401, detail="unauthorized")
    try:
        body = await req.json()
    except Exception:
        body = None
    if not isinstance(body, dict):
        body = {}
    wallet_from_body = (body.get("wallet_id") or "").strip()
    if phone:
        user_wallet = _resolve_wallet_id_for_phone(phone)
        if not user_wallet:
            raise HTTPException(status_code=400, detail="wallet not found for user")
        if wallet_from_body and wallet_from_body != user_wallet:
            raise HTTPException(status_code=403, detail="wallet does not belong to user")
        body["wallet_id"] = user_wallet
        if not (body.get("customer_phone") or "").strip():
            body["customer_phone"] = phone
    headers = {}
    try:
        ikey = req.headers.get("Idempotency-Key") if hasattr(req, 'headers') else None
    except Exception:
        ikey = None
    if ikey:
        headers["Idempotency-Key"] = ikey
    try:
        if _use_bus_internal():
            if not _BUS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="bus internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                req_model = _BusBookReq(**data)  # type: ignore[name-defined]
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            try:
                with _bus_internal_session() as s:
                    return _bus_book_trip(trip_id=trip_id, body=req_model, idempotency_key=ikey, s=s)
            except HTTPException:
                # Preserve domain HTTP errors (e.g. payment/validation issues)
                raise
            except Exception as e:
                raise HTTPException(status_code=502, detail=str(e))
        r = httpx.post(_bus_url(f"/trips/{trip_id}/book"), json=body, headers=_bus_headers(headers), timeout=15)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        # Let FastAPI propagate existing HTTPException (status + detail)
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/bus/bookings/search")
def bus_booking_search(
    request: Request,
    wallet_id: str | None = None,
    phone: str | None = None,
    limit: int = 20,
):
    """
    Search bus bookings.

    Security:
    - Admin: can search by wallet_id/phone (but at least one filter is required).
    - Regular users: can only search for their own wallet/phone.
    """
    caller_phone, caller_wallet_id = _require_caller_wallet(request)
    is_admin = _is_admin(caller_phone)

    # Fail-closed: prevent dumping all bookings when filters are missing.
    if is_admin and not (wallet_id or phone):
        raise HTTPException(status_code=400, detail="wallet_id or phone required")

    if not is_admin:
        # Enforce caller ownership. Do not allow searching arbitrary wallet/phone.
        if wallet_id and wallet_id.strip() != caller_wallet_id:
            raise HTTPException(status_code=403, detail="wallet_id does not belong to caller")
        if phone and phone.strip() != caller_phone:
            raise HTTPException(status_code=403, detail="phone does not belong to caller")
        wallet_id = caller_wallet_id
        phone = caller_phone

    limit = max(1, min(int(limit or 0), 200))
    params: dict[str, str | int] = {"limit": limit}
    if wallet_id:
        params["wallet_id"] = wallet_id.strip()
    if phone:
        params["phone"] = phone.strip()
    try:
        if _use_bus_internal():
            if not _BUS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="bus internal not available")
            with _bus_internal_session() as s:
                return _bus_booking_search(wallet_id=wallet_id, phone=phone, limit=limit, s=s)
        r = httpx.get(_bus_url("/bookings/search"), params=params, headers=_bus_headers(), timeout=10)
        r.raise_for_status()
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/bus/bookings/{booking_id}")
def bus_booking_status(booking_id: str, request: Request):
    phone, caller_wallet_id = _require_caller_wallet(request)
    is_admin = _is_admin(phone)

    def _booking_wallet_id(obj: Any) -> str:
        try:
            if isinstance(obj, dict):
                return str((obj.get("wallet_id") or "")).strip()
            return str(getattr(obj, "wallet_id", "") or "").strip()
        except Exception:
            return ""

    try:
        if _use_bus_internal():
            if not _BUS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="bus internal not available")
            with _bus_internal_session() as s:
                booking = _bus_booking_status(booking_id=booking_id, s=s)
                if not is_admin:
                    wid = _booking_wallet_id(booking)
                    if not wid or wid != caller_wallet_id:
                        raise HTTPException(status_code=403, detail="booking does not belong to caller wallet")
                return booking
        r = httpx.get(_bus_url(f"/bookings/{booking_id}"), headers=_bus_headers(), timeout=10)
        r.raise_for_status()
        booking = r.json() if r.headers.get("content-type", "").startswith("application/json") else {}
        if not is_admin:
            wid = _booking_wallet_id(booking)
            if not wid or wid != caller_wallet_id:
                raise HTTPException(status_code=403, detail="booking does not belong to caller wallet")
        return booking
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/bus/bookings/{booking_id}/tickets")
def bus_booking_tickets(booking_id: str, request: Request):
    phone, caller_wallet_id = _require_caller_wallet(request)
    is_admin = _is_admin(phone)

    def _booking_wallet_id(obj: Any) -> str:
        try:
            if isinstance(obj, dict):
                return str((obj.get("wallet_id") or "")).strip()
            return str(getattr(obj, "wallet_id", "") or "").strip()
        except Exception:
            return ""

    try:
        if _use_bus_internal():
            if not _BUS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="bus internal not available")
            with _bus_internal_session() as s:
                booking = _bus_booking_status(booking_id=booking_id, s=s)
                if not is_admin:
                    wid = _booking_wallet_id(booking)
                    if not wid or wid != caller_wallet_id:
                        raise HTTPException(status_code=403, detail="booking does not belong to caller wallet")
                return _bus_booking_tickets(booking_id=booking_id, s=s)
        r_status = httpx.get(_bus_url(f"/bookings/{booking_id}"), headers=_bus_headers(), timeout=10)
        r_status.raise_for_status()
        booking = r_status.json() if r_status.headers.get("content-type", "").startswith("application/json") else {}
        if not is_admin:
            wid = _booking_wallet_id(booking)
            if not wid or wid != caller_wallet_id:
                raise HTTPException(status_code=403, detail="booking does not belong to caller wallet")
        r = httpx.get(_bus_url(f"/bookings/{booking_id}/tickets"), headers=_bus_headers(), timeout=10)
        r.raise_for_status()
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/bus/bookings/{booking_id}/cancel")
async def bus_booking_cancel(booking_id: str, req: Request):
    """
    Cancel a bus booking for the authenticated rider and apply the
    time-based voucher/refund policy from the Bus domain.
    """
    phone = _auth_phone(req)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    # Resolve wallet for caller (used only for ownership check)
    wallet_id = _resolve_wallet_id_for_phone(phone)
    if not wallet_id:
        raise HTTPException(status_code=400, detail="wallet not found for user")
    try:
        # Verify that the booking belongs to this wallet/phone before cancelling.
        if _use_bus_internal():
            if not _BUS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="bus internal not available")
            with _bus_internal_session() as s:
                b = _bus_booking_status(booking_id=booking_id, s=s)
                if getattr(b, "wallet_id", None) and b.wallet_id != wallet_id:  # type: ignore[union-attr]
                    raise HTTPException(status_code=403, detail="booking does not belong to caller wallet")
                # Perform cancellation
                return _bus_cancel_booking(booking_id=booking_id, s=s)
        # External bus-api mode: fetch booking via HTTP to check wallet ownership.
        r_status = httpx.get(_bus_url(f"/bookings/{booking_id}"), headers=_bus_headers(), timeout=10)
        r_status.raise_for_status()
        booking = r_status.json()
        if isinstance(booking, dict):
            wid = (booking.get("wallet_id") or "").strip()
            if wid and wid != wallet_id:
                raise HTTPException(status_code=403, detail="booking does not belong to caller wallet")
        r = httpx.post(_bus_url(f"/bookings/{booking_id}/cancel"), headers=_bus_headers(), timeout=15)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))
@app.post("/bus/tickets/board")
async def bus_ticket_board(req: Request):
    phone = _require_operator(req, "bus")
    is_admin = _is_admin(phone)
    try:
        body = await req.json()
    except Exception:
        body = None
    if not isinstance(body, dict):
        body = {}
    payload = str((body.get("payload") or "")).strip()
    if not payload:
        raise HTTPException(status_code=400, detail="payload required")

    def _parse_ticket_payload(raw: str) -> dict[str, str]:
        parts = raw.split("|")
        if not parts or parts[0] != "TICKET":
            raise ValueError("invalid payload")
        out: dict[str, str] = {}
        for kv in parts[1:]:
            if "=" not in kv:
                continue
            k, v = kv.split("=", 1)
            out[k] = v
        return out

    try:
        payload_data = _parse_ticket_payload(payload)
    except Exception:
        raise HTTPException(status_code=400, detail="invalid payload")
    trip_id = (payload_data.get("trip") or "").strip()
    ticket_id = (payload_data.get("id") or "").strip()
    booking_id = (payload_data.get("b") or "").strip()
    if not trip_id:
        raise HTTPException(status_code=400, detail="trip missing in payload")
    if not is_admin:
        route_id = _bus_trip_route_id(trip_id)
        if route_id is None:
            raise HTTPException(status_code=404, detail="trip not found")
        owner = _bus_route_owner(route_id)
        if owner and owner not in _bus_operator_ids_for_phone(phone):
            raise HTTPException(status_code=403, detail="trip not allowed for caller")
    try:
        if _use_bus_internal():
            if not _BUS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="bus internal not available")
            try:
                breq = _BusBoardReq(**body)  # type: ignore[name-defined]
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _bus_internal_session() as s:
                res = _bus_ticket_board(body=breq, s=s)
                if not isinstance(res, dict):
                    res = {"result": res}
                booking = None
                tickets = None
                trip = None
                try:
                    if booking_id:
                        booking = _bus_booking_status(booking_id=booking_id, s=s)
                        tickets = _bus_booking_tickets(booking_id=booking_id, s=s)
                    if trip_id:
                        trip = _bus_trip_detail(trip_id=trip_id, s=s)
                except Exception:
                    booking = None
                    tickets = None
                    trip = None
                ticket_obj = None
                if tickets is not None:
                    try:
                        for tk in tickets:
                            try:
                                tid = getattr(tk, "id", None)
                            except Exception:
                                tid = None
                            if not tid and isinstance(tk, dict):
                                tid = (tk.get("id") or "").strip()
                            if str(tid or "") == ticket_id:
                                ticket_obj = tk
                                break
                    except Exception:
                        ticket_obj = None
                res["booking"] = booking
                res["ticket"] = ticket_obj
                res["trip"] = trip
                return res
        r = httpx.post(_bus_url("/tickets/board"), json=body, headers=_bus_headers(), timeout=10)
        data: Any
        if r.headers.get("content-type", "").startswith("application/json"):
            data = r.json()
            if not isinstance(data, dict):
                data = {"result": data}
        else:
            data = {"raw": r.text, "status_code": r.status_code}
        # Best-effort enrichment with booking/trip info for operator UI.
        booking = None
        tickets = None
        trip = None
        try:
            if booking_id:
                rb = httpx.get(_bus_url(f"/bookings/{booking_id}"), headers=_bus_headers(), timeout=10)
                if rb.headers.get("content-type", "").startswith("application/json"):
                    booking = rb.json()
                rtks = httpx.get(_bus_url(f"/bookings/{booking_id}/tickets"), headers=_bus_headers(), timeout=10)
                if rtks.headers.get("content-type", "").startswith("application/json"):
                    tickets = rtks.json()
            if trip_id:
                rt = httpx.get(_bus_url(f"/trips/{trip_id}"), headers=_bus_headers(), timeout=10)
                if rt.headers.get("content-type", "").startswith("application/json"):
                    trip = rt.json()
        except Exception:
            booking = None
            tickets = None
            trip = None
        ticket_obj = None
        if isinstance(tickets, list):
            try:
                for tk in tickets:
                    if not isinstance(tk, dict):
                        continue
                    tid = (tk.get("id") or "").strip()
                    if tid == ticket_id:
                        ticket_obj = tk
                        break
            except Exception:
                ticket_obj = None
        if isinstance(data, dict):
            data["booking"] = booking
            data["ticket"] = ticket_obj
            data["trip"] = trip
        return data
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/bus/cities")
async def bus_create_city(req: Request):
    if _ENV_LOWER in ("dev", "test"):
        phone = _auth_phone(req)
        if not phone:
            raise HTTPException(status_code=401, detail="unauthorized")
    else:
        _require_operator(req, "bus")
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        if _use_bus_internal():
            if not _BUS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="bus internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                req_model = _BusCityIn(**data)  # type: ignore[name-defined]
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _bus_internal_session() as s:
                return _bus_create_city(body=req_model, s=s)
        r = httpx.post(_bus_url("/cities"), json=body, headers=_bus_headers(), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/bus/operators")
async def bus_create_operator(req: Request):
    phone = _auth_phone(req)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    is_admin = _is_admin(phone)
    if not _is_operator(phone, "bus") and not is_admin:
        if _ENV_LOWER not in ("dev", "test"):
            raise HTTPException(status_code=403, detail="operator for bus required")
    try:
        body = await req.json()
    except Exception:
        body = None
    if not isinstance(body, dict):
        body = {}
    # Enforce that operators bind to caller wallet unless admin/dev override.
    wallet_id = (body.get("wallet_id") or "").strip()
    user_wallet = _resolve_wallet_id_for_phone(phone)
    if wallet_id and user_wallet and wallet_id != user_wallet and not is_admin and _ENV_LOWER not in ("dev", "test"):
        raise HTTPException(status_code=403, detail="wallet_id does not belong to caller")
    if not wallet_id:
        if user_wallet:
            wallet_id = user_wallet
        elif not is_admin and _ENV_LOWER not in ("dev", "test"):
            raise HTTPException(status_code=400, detail="wallet not found for operator phone")
    body["wallet_id"] = wallet_id or None
    # Basic validation
    name = (body.get("name") or "").strip()
    if not name:
        raise HTTPException(status_code=400, detail="name required")
    try:
        if _use_bus_internal():
            if not _BUS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="bus internal not available")
            try:
                req_model = _BusOperatorIn(**body)  # type: ignore[name-defined]
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _bus_internal_session() as s:
                return _bus_create_operator(body=req_model, s=s)
        r = httpx.post(_bus_url("/operators"), json=body, headers=_bus_headers(), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/bus/routes")
async def bus_create_route(req: Request):
    if _ENV_LOWER in ("dev", "test"):
        phone = _auth_phone(req)
        if not phone:
            raise HTTPException(status_code=401, detail="unauthorized")
    else:
        phone = _require_operator(req, "bus")
    is_admin = _is_admin(phone)
    try:
        body = await req.json()
    except Exception:
        body = None
    if not isinstance(body, dict):
        body = {}
    allowed_ops = _bus_operator_ids_for_phone(phone)
    if not allowed_ops and _ENV_LOWER in ("dev", "test"):
        allowed_ops = _bus_all_operator_ids()
        is_admin = True
    if not allowed_ops and not is_admin:
        raise HTTPException(status_code=403, detail="no bus operator linked to caller wallet")
    op_id = (body.get("operator_id") or "").strip()
    if not op_id and allowed_ops:
        op_id = allowed_ops[0]
        body["operator_id"] = op_id
    if not op_id:
        raise HTTPException(status_code=400, detail="operator_id required")
    if allowed_ops and op_id not in allowed_ops and not is_admin:
        raise HTTPException(status_code=403, detail="operator not allowed for caller")
    try:
        if _use_bus_internal():
            if not _BUS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="bus internal not available")
            try:
                req_model = _BusRouteIn(**body)  # type: ignore[name-defined]
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _bus_internal_session() as s:
                return _bus_create_route(body=req_model, s=s)
        r = httpx.post(_bus_url("/routes"), json=body, headers=_bus_headers(), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))

@app.get("/bus/routes")
def bus_list_routes(origin_city_id: str | None = None, dest_city_id: str | None = None):
    params: dict[str, str] = {}
    if origin_city_id:
        params["origin_city_id"] = origin_city_id
    if dest_city_id:
        params["dest_city_id"] = dest_city_id
    try:
        if _use_bus_internal():
            if not _BUS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="bus internal not available")
            with _bus_internal_session() as s:
                return _bus_list_routes(origin_city_id=origin_city_id, dest_city_id=dest_city_id, s=s)
        r = httpx.get(_bus_url("/routes"), params=params or None, headers=_bus_headers(), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))

@app.get("/bus/operators")
def bus_list_operators(request: Request):
    """
    List bus operators.

    - Superadmin/Admin: see all operators
    - Bus operators: only see operators that belong to their own wallet
    - Other users: 403
    """
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    is_admin = _is_admin(phone) or _is_superadmin(phone)
    is_op = _is_operator(phone, "bus")
    if not is_admin and not is_op:
        raise HTTPException(status_code=403, detail="operator or admin required")
    try:
        if _use_bus_internal():
            if not _BUS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="bus internal not available")
            with _bus_internal_session() as s:
                ops = _bus_list_operators(limit=50, s=s)
                if is_admin:
                    return ops
                wid = _resolve_wallet_id_for_phone(phone)
                if not wid:
                    return []
                filtered = []
                for op in ops or []:
                    try:
                        if str(getattr(op, "wallet_id", "") or "").strip() == wid:
                            filtered.append(op)
                    except Exception:
                        continue
                return filtered
        r = httpx.get(_bus_url("/operators"), headers=_bus_headers(), timeout=10)
        if not r.headers.get("content-type", "").startswith("application/json"):
            return []
        arr = r.json()
        if not isinstance(arr, list):
            return []
        if is_admin:
            return arr
        wid = _resolve_wallet_id_for_phone(phone)
        if not wid:
            return []
        out: list[dict] = []
        for op in arr:
            try:
                if not isinstance(op, dict):
                    continue
                if str((op.get("wallet_id") or "")).strip() == wid:
                    out.append(op)
            except Exception:
                continue
        return out
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/bus/operators/{operator_id}/online")
def bus_operator_online(operator_id: str, request: Request):
    """
    Toggle a Bus operator online.

    Security:
    - prod/staging: admin/superadmin OR bus-operator (for own operator_id) only
    - dev/test: any authenticated user (for local iteration)
    """
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    is_admin = _is_admin(phone) or _is_superadmin(phone)
    if _ENV_LOWER not in ("dev", "test") and not is_admin:
        _require_operator(request, "bus")
        allowed_ops = _bus_operator_ids_for_phone(phone)
        if not allowed_ops:
            raise HTTPException(status_code=403, detail="no bus operator linked to caller wallet")
        if operator_id not in allowed_ops:
            raise HTTPException(status_code=403, detail="operator not allowed for caller")
    try:
        if _use_bus_internal():
            if not _BUS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="bus internal not available")
            with _bus_internal_session() as s:
                return _bus_operator_online(operator_id=operator_id, s=s)
        r = httpx.post(_bus_url(f"/operators/{operator_id}/online"), headers=_bus_headers(), timeout=10)
        r.raise_for_status()
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/bus/operators/{operator_id}/offline")
def bus_operator_offline(operator_id: str, request: Request):
    """
    Toggle a Bus operator offline.

    Security:
    - prod/staging: admin/superadmin OR bus-operator (for own operator_id) only
    - dev/test: any authenticated user (for local iteration)
    """
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    is_admin = _is_admin(phone) or _is_superadmin(phone)
    if _ENV_LOWER not in ("dev", "test") and not is_admin:
        _require_operator(request, "bus")
        allowed_ops = _bus_operator_ids_for_phone(phone)
        if not allowed_ops:
            raise HTTPException(status_code=403, detail="no bus operator linked to caller wallet")
        if operator_id not in allowed_ops:
            raise HTTPException(status_code=403, detail="operator not allowed for caller")
    try:
        if _use_bus_internal():
            if not _BUS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="bus internal not available")
            with _bus_internal_session() as s:
                return _bus_operator_offline(operator_id=operator_id, s=s)
        r = httpx.post(_bus_url(f"/operators/{operator_id}/offline"), headers=_bus_headers(), timeout=10)
        r.raise_for_status()
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))

@app.get("/bus/operators/{operator_id}/stats")
def bus_operator_stats(operator_id: str, request: Request, period: str = "today"):
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    allowed_ops = _bus_operator_ids_for_phone(phone)
    is_admin = _is_admin(phone)
    # Allow any authenticated user in dev/test for local iteration.
    if _ENV_LOWER not in ("dev", "test"):
        if not is_admin:
            _require_operator(request, "bus")
        if not allowed_ops and not is_admin:
            raise HTTPException(status_code=403, detail="no bus operator linked to caller wallet")
        if allowed_ops and operator_id not in allowed_ops and not is_admin:
            raise HTTPException(status_code=403, detail="operator not allowed for caller")
    try:
        if _use_bus_internal():
            if not _BUS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="bus internal not available")
            with _bus_internal_session() as s:
                return _bus_operator_stats(operator_id=operator_id, period=period, s=s)
        r = httpx.get(_bus_url(f"/operators/{operator_id}/stats"), params={"period": period}, headers=_bus_headers(), timeout=10)
        r.raise_for_status()
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/bus/operators/{operator_id}/trips")
def bus_operator_trips(
    operator_id: str,
    request: Request,
    status: str | None = None,
    from_date: str | None = None,
    to_date: str | None = None,
    limit: int = 100,
    order: str = "desc",
):
    """
    List trips for a Bus operator (includes drafts). Protected via BFF auth.
    """
    if _ENV_LOWER in ("dev", "test"):
        phone = _auth_phone(request)
        if not phone:
            raise HTTPException(status_code=401, detail="unauthorized")
    else:
        phone = _require_operator(request, "bus")
    allowed_ops = _bus_operator_ids_for_phone(phone)
    is_admin = _is_admin(phone)
    if not allowed_ops and _ENV_LOWER in ("dev", "test"):
        allowed_ops = _bus_all_operator_ids()
        is_admin = True
    if not allowed_ops and not is_admin:
        raise HTTPException(status_code=403, detail="no bus operator linked to caller wallet")
    if allowed_ops and operator_id not in allowed_ops and not is_admin:
        raise HTTPException(status_code=403, detail="operator not allowed for caller")
    params: dict[str, Any] = {"limit": limit, "order": order}
    if status:
        params["status"] = status
    if from_date:
        params["from_date"] = from_date
    if to_date:
        params["to_date"] = to_date
    try:
        if _use_bus_internal():
            if not _BUS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="bus internal not available")
            with _bus_internal_session() as s:
                return _bus_operator_trips(
                    operator_id=operator_id,
                    status=status,
                    from_date=from_date,
                    to_date=to_date,
                    limit=limit,
                    order=order,
                    s=s,
                )
        r = httpx.get(_bus_url(f"/operators/{operator_id}/trips"), params=params, headers=_bus_headers(), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/bus/trips")
async def bus_create_trip(req: Request):
    if _ENV_LOWER in ("dev", "test"):
        phone = _auth_phone(req)
        if not phone:
            raise HTTPException(status_code=401, detail="unauthorized")
    else:
        phone = _require_operator(req, "bus")
    is_admin = _is_admin(phone)
    try:
        body = await req.json()
    except Exception:
        body = None
    if not isinstance(body, dict):
        body = {}
    route_id = (body.get("route_id") or "").strip()
    if not route_id:
        raise HTTPException(status_code=400, detail="route_id required")
    route_owner = _bus_route_owner(route_id)
    if route_owner is None:
        raise HTTPException(status_code=404, detail="route not found")
    allowed_ops = _bus_operator_ids_for_phone(phone)
    if not allowed_ops and _ENV_LOWER in ('dev','test'):
        allowed_ops = _bus_all_operator_ids()
        is_admin = True
    if not allowed_ops and not is_admin:
        raise HTTPException(status_code=403, detail="no bus operator linked to caller wallet")
    if allowed_ops and route_owner not in allowed_ops and not is_admin:
        raise HTTPException(status_code=403, detail="route not allowed for caller")
    try:
        if _use_bus_internal():
            if not _BUS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="bus internal not available")
            try:
                req_model = _BusTripIn(**body)  # type: ignore[name-defined]
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _bus_internal_session() as s:
                return _bus_create_trip(body=req_model, s=s)
        r = httpx.post(_bus_url("/trips"), json=body, headers=_bus_headers(), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/bus/trips/{trip_id}/publish")
def bus_publish_trip(trip_id: str, request: Request):
    """
    Publish a bus trip so that it appears in passenger search.
    """
    if _ENV_LOWER in ("dev", "test"):
        phone = _auth_phone(request)
        if not phone:
            raise HTTPException(status_code=401, detail="unauthorized")
    else:
        phone = _require_operator(request, "bus")
    allowed_ops = _bus_operator_ids_for_phone(phone)
    is_admin = _is_admin(phone)
    if not allowed_ops and _ENV_LOWER in ('dev','test'):
        allowed_ops = _bus_all_operator_ids()
        is_admin = True
    if not allowed_ops and not is_admin:
        raise HTTPException(status_code=403, detail="no bus operator linked to caller wallet")
    # Validate trip ownership before publishing
    route_id: str | None = None
    route_id = _bus_trip_route_id(trip_id)
    if route_id is None:
        raise HTTPException(status_code=404, detail="trip not found")
    if not route_id:
        raise HTTPException(status_code=400, detail="trip route missing")
    owner = _bus_route_owner(route_id)
    if owner is None:
        raise HTTPException(status_code=404, detail="route not found for trip")
    if allowed_ops and owner not in allowed_ops and not is_admin:
        raise HTTPException(status_code=403, detail="route not allowed for caller")
    try:
        if _use_bus_internal():
            if not _BUS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="bus internal not available")
            with _bus_internal_session() as s:
                return _bus_publish_trip(trip_id=trip_id, s=s)
        r = httpx.post(_bus_url(f"/trips/{trip_id}/publish"), headers=_bus_headers(), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/bus/trips/{trip_id}/unpublish")
def bus_unpublish_trip(trip_id: str, request: Request):
    """
    Unpublish a bus trip (set to draft) so it does not show up in passenger search.
    """
    if _ENV_LOWER in ("dev", "test"):
        phone = _auth_phone(request)
        if not phone:
            raise HTTPException(status_code=401, detail="unauthorized")
    else:
        phone = _require_operator(request, "bus")
    allowed_ops = _bus_operator_ids_for_phone(phone)
    is_admin = _is_admin(phone)
    if not allowed_ops and _ENV_LOWER in ("dev", "test"):
        allowed_ops = _bus_all_operator_ids()
        is_admin = True
    if not allowed_ops and not is_admin:
        raise HTTPException(status_code=403, detail="no bus operator linked to caller wallet")
    route_id: str | None = None
    route_id = _bus_trip_route_id(trip_id)
    if route_id is None:
        raise HTTPException(status_code=404, detail="trip not found")
    if not route_id:
        raise HTTPException(status_code=400, detail="trip route missing")
    owner = _bus_route_owner(route_id)
    if owner is None:
        raise HTTPException(status_code=404, detail="route not found for trip")
    if allowed_ops and owner not in allowed_ops and not is_admin:
        raise HTTPException(status_code=403, detail="route not allowed for caller")
    try:
        if _use_bus_internal():
            if not _BUS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="bus internal not available")
            with _bus_internal_session() as s:
                return _bus_unpublish_trip(trip_id=trip_id, s=s)
        r = httpx.post(_bus_url(f"/trips/{trip_id}/unpublish"), headers=_bus_headers(), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/bus/trips/{trip_id}/cancel")
def bus_cancel_trip(trip_id: str, request: Request):
    """
    Cancel a bus trip.
    """
    if _ENV_LOWER in ("dev", "test"):
        phone = _auth_phone(request)
        if not phone:
            raise HTTPException(status_code=401, detail="unauthorized")
    else:
        phone = _require_operator(request, "bus")
    allowed_ops = _bus_operator_ids_for_phone(phone)
    is_admin = _is_admin(phone)
    if not allowed_ops and _ENV_LOWER in ("dev", "test"):
        allowed_ops = _bus_all_operator_ids()
        is_admin = True
    if not allowed_ops and not is_admin:
        raise HTTPException(status_code=403, detail="no bus operator linked to caller wallet")
    route_id: str | None = None
    route_id = _bus_trip_route_id(trip_id)
    if route_id is None:
        raise HTTPException(status_code=404, detail="trip not found")
    if not route_id:
        raise HTTPException(status_code=400, detail="trip route missing")
    owner = _bus_route_owner(route_id)
    if owner is None:
        raise HTTPException(status_code=404, detail="route not found for trip")
    if allowed_ops and owner not in allowed_ops and not is_admin:
        raise HTTPException(status_code=403, detail="route not allowed for caller")
    try:
        if _use_bus_internal():
            if not _BUS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="bus internal not available")
            with _bus_internal_session() as s:
                return _bus_cancel_trip(trip_id=trip_id, s=s)
        r = httpx.post(_bus_url(f"/trips/{trip_id}/cancel"), headers=_bus_headers(), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))

@app.get("/bus/admin/summary")
def bus_admin_summary(request: Request):
    _require_operator(request, "bus")
    try:
        if _use_bus_internal():
            if not _BUS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="bus internal not available")
            with _bus_internal_session() as s:
                return _bus_admin_summary(s=s)
        r = httpx.get(_bus_url("/admin/summary"), headers=_bus_headers(), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/payments/requests")
async def payments_req_create(req: Request):
    phone, caller_wallet_id = _require_caller_wallet(req)
    can_admin = _is_admin(phone)
    _rate_limit_payments_edge(
        req,
        wallet_id=caller_wallet_id,
        scope="requests_write",
        wallet_max=PAY_API_REQ_WRITE_MAX_PER_WALLET,
        ip_max=PAY_API_REQ_WRITE_MAX_PER_IP,
    )
    try:
        body = await req.json()
    except Exception:
        body = {}
    if not isinstance(body, dict):
        body = {}
    payload = dict(body)
    from_wallet_id = str(payload.get("from_wallet_id") or "").strip()
    if from_wallet_id and from_wallet_id != caller_wallet_id and not can_admin:
        _audit_from_request(
            req,
            "payments_request_from_wallet_mismatch",
            requested_wallet_id=from_wallet_id,
            caller_wallet_id=caller_wallet_id,
        )
        raise HTTPException(status_code=403, detail="from_wallet_id does not belong to caller")
    if not can_admin:
        payload["from_wallet_id"] = caller_wallet_id
    try:
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            data = payload or {}
            if not isinstance(data, dict):
                data = {}
            try:
                req_model = _PayRequestCreate(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            try:
                with _pay_internal_session() as s:
                    return _pay_create_request(req_model, s=s)
            except HTTPException:
                raise
            except Exception as e:
                raise HTTPException(status_code=502, detail=str(e))
        r = httpx.post(
            _payments_url("/requests"),
            json=payload,
            headers=_payments_headers(),
            timeout=10,
        )
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/payments/requests")
def payments_req_list(request: Request, wallet_id: str = "", kind: str = "", limit: int = 100):
    phone, caller_wallet_id = _require_caller_wallet(request)
    can_admin = _is_admin(phone)
    _rate_limit_payments_edge(
        request,
        wallet_id=caller_wallet_id,
        scope="requests_read",
        wallet_max=PAY_API_REQ_READ_MAX_PER_WALLET,
        ip_max=PAY_API_REQ_READ_MAX_PER_IP,
    )
    requested_wallet_id = (wallet_id or "").strip()
    if requested_wallet_id and requested_wallet_id != caller_wallet_id and not can_admin:
        raise HTTPException(status_code=403, detail="wallet_id does not belong to caller")
    target_wallet_id = requested_wallet_id if requested_wallet_id else caller_wallet_id
    params = {"wallet_id": target_wallet_id}
    if kind: params["kind"] = kind
    params["limit"] = max(1, min(limit, 500))
    try:
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            try:
                with _pay_internal_session() as s:
                    return _pay_list_requests(wallet_id=target_wallet_id, kind=kind, limit=max(1, min(limit, 500)), s=s)
            except HTTPException:
                raise
            except Exception as e:
                raise HTTPException(status_code=502, detail=str(e))
        r = httpx.get(
            _payments_url("/requests"),
            params=params,
            headers=_payments_headers(),
            timeout=10,
        )
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/payments/resolve/phone/{phone}")
def payments_resolve_phone(phone: str, request: Request):
    caller_phone, caller_wallet_id = _require_caller_wallet(request)
    _rate_limit_payments_edge(
        request,
        wallet_id=caller_wallet_id,
        scope="resolve_phone",
        wallet_max=PAY_API_RESOLVE_MAX_PER_WALLET,
        ip_max=PAY_API_RESOLVE_MAX_PER_IP,
    )
    target_phone = (phone or "").strip()
    if not re.fullmatch(r"\+[1-9][0-9]{7,14}", target_phone):
        raise HTTPException(status_code=400, detail="invalid phone format")
    can_admin = _is_admin(caller_phone)
    result: Any
    try:
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            try:
                with _pay_internal_session() as s:
                    result = _pay_resolve_phone(phone=target_phone, s=s)
            except HTTPException:
                raise
            except Exception as e:
                raise HTTPException(status_code=502, detail=str(e))
        else:
            r = httpx.get(
                _payments_url(f"/resolve/phone/{target_phone}"),
                headers=_payments_headers(),
                timeout=10,
            )
            result = r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))
    if can_admin or target_phone == caller_phone:
        return result
    wallet_id = ""
    if isinstance(result, dict):
        wallet_id = str(result.get("wallet_id") or "").strip()
    else:
        try:
            wallet_id = str(getattr(result, "wallet_id", "") or "").strip()
        except Exception:
            wallet_id = ""
    if not wallet_id:
        raise HTTPException(status_code=404, detail="phone not found")
    _audit_from_request(request, "payments_resolve_phone_privacy_redact", target_phone=target_phone)
    return {"wallet_id": wallet_id}


@app.post("/payments/requests/by_phone")
async def payments_req_by_phone(req: Request):
    phone, caller_wallet_id = _require_caller_wallet(req)
    can_admin = _is_admin(phone)
    _rate_limit_payments_edge(
        req,
        wallet_id=caller_wallet_id,
        scope="requests_write",
        wallet_max=PAY_API_REQ_WRITE_MAX_PER_WALLET,
        ip_max=PAY_API_REQ_WRITE_MAX_PER_IP,
    )
    # body: {from_wallet_id, to_phone, amount_cents, message?, expires_in_secs?}
    try:
        body = await req.json()
    except Exception:
        body = {}
    if not isinstance(body, dict):
        body = {}
    payload = dict(body)
    requested_from_wallet_id = str(payload.get("from_wallet_id") or "").strip()
    if requested_from_wallet_id and requested_from_wallet_id != caller_wallet_id and not can_admin:
        raise HTTPException(status_code=403, detail="from_wallet_id does not belong to caller")
    if not can_admin:
        payload["from_wallet_id"] = caller_wallet_id
    to_phone = payload.get("to_phone")
    if not to_phone:
        raise HTTPException(status_code=400, detail="to_phone required")
    try:
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            with _pay_internal_session() as s:
                # resolve phone -> wallet
                try:
                    res = _pay_resolve_phone(phone=to_phone, s=s)
                    to_wallet = res.wallet_id
                except HTTPException:
                    raise
                except Exception as e:
                    raise HTTPException(status_code=502, detail=str(e))
                req_payload = {k: v for k, v in payload.items() if k != "to_phone"}
                req_payload["to_wallet_id"] = to_wallet
                try:
                    req_model = _PayRequestCreate(**req_payload)
                except Exception as e:
                    raise HTTPException(status_code=400, detail=str(e))
                pr = _pay_create_request(req_model, s=s)
            # SMS Notify bleibt wie bisher
            try:
                amt = payload.get("amount_cents")
                msg = payload.get("message") or ""
                if os.getenv("SMS_NOTIFY_URL"):
                    httpx.post(os.getenv("SMS_NOTIFY_URL"), json={"to": to_phone, "text": f"Payment request: {amt}. {msg}"}, timeout=5)
            except Exception:
                pass
            return pr
        # HTTP-Fallback
        rr = httpx.get(
            _payments_url(f"/resolve/phone/{to_phone}"),
            headers=_payments_headers(),
            timeout=10,
        )
        to_wallet = rr.json().get("wallet_id") if rr.status_code == 200 else None
        if not to_wallet:
            raise HTTPException(status_code=404, detail="phone not found")
        req_payload = {k: v for k, v in payload.items() if k != "to_phone"}
        req_payload["to_wallet_id"] = to_wallet
        r = httpx.post(
            _payments_url("/requests"),
            json=req_payload,
            headers=_payments_headers(),
            timeout=10,
        )
        try:
            j = r.json()
        except Exception:
            j = {"status_code": r.status_code, "raw": r.text}
        if r.status_code == 200:
            try:
                amt = payload.get("amount_cents")
                msg = payload.get("message") or ""
                if os.getenv('SMS_NOTIFY_URL'):
                    httpx.post(os.getenv('SMS_NOTIFY_URL'), json={"to": to_phone, "text": f"Payment request: {amt}. {msg}"}, timeout=5)
            except Exception:
                pass
        return j
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/payments/requests/{rid}/accept")
async def payments_req_accept(rid: str, req: Request):
    phone, caller_wallet_id = _require_caller_wallet(req)
    can_admin = _is_admin(phone)
    _rate_limit_payments_edge(
        req,
        wallet_id=caller_wallet_id,
        scope="requests_write",
        wallet_max=PAY_API_REQ_WRITE_MAX_PER_WALLET,
        ip_max=PAY_API_REQ_WRITE_MAX_PER_IP,
    )
    try:
        try:
            body = await req.json() if hasattr(req, "json") else {}
        except Exception:
            body = {}
        if not isinstance(body, dict):
            body = {}
        to_wallet_id = str(body.get("to_wallet_id") or "").strip()
        if to_wallet_id and to_wallet_id != caller_wallet_id and not can_admin:
            raise HTTPException(status_code=403, detail="to_wallet_id does not belong to caller")
        if not can_admin:
            to_wallet_id = caller_wallet_id
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            ikey = req.headers.get("Idempotency-Key") if hasattr(req, "headers") else None
            with _pay_internal_session() as s:
                if _pay_accept_request_core:  # type: ignore[truthy-function]
                    return _pay_accept_request_core(rid=rid, ikey=ikey, s=s, to_wallet_id=to_wallet_id)  # type: ignore[arg-type]
                return _pay_accept_request(rid=rid, s=s)
        r = httpx.post(
            _payments_url(f"/requests/{rid}/accept"),
            json={"to_wallet_id": to_wallet_id},
            headers=_payments_headers(),
            timeout=10,
        )
        return r.json()
    except HTTPException:
        raise
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/payments/requests/{rid}/cancel")
def payments_req_cancel(rid: str, request: Request):
    phone, caller_wallet_id = _require_caller_wallet(request)
    can_admin = _is_admin(phone)
    _rate_limit_payments_edge(
        request,
        wallet_id=caller_wallet_id,
        scope="requests_write",
        wallet_max=PAY_API_REQ_WRITE_MAX_PER_WALLET,
        ip_max=PAY_API_REQ_WRITE_MAX_PER_IP,
    )
    try:
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            try:
                with _pay_internal_session() as s:
                    if not can_admin:
                        incoming = _pay_list_requests(wallet_id=caller_wallet_id, kind="incoming", limit=500, s=s)
                        outgoing = _pay_list_requests(wallet_id=caller_wallet_id, kind="outgoing", limit=500, s=s)
                        owned = False
                        for row in list(incoming or []) + list(outgoing or []):
                            try:
                                row_id = str(getattr(row, "id", "") or "")
                            except Exception:
                                row_id = ""
                            if row_id == rid:
                                owned = True
                                break
                        if not owned:
                            raise HTTPException(status_code=404, detail="payment request not found")
                    return _pay_cancel_request(rid=rid, s=s)
            except HTTPException:
                raise
            except Exception as e:
                raise HTTPException(status_code=502, detail=str(e))
        if not can_admin:
            owned = False
            for kind in ("incoming", "outgoing"):
                chk = httpx.get(
                    _payments_url("/requests"),
                    params={"wallet_id": caller_wallet_id, "kind": kind, "limit": 500},
                    headers=_payments_headers(),
                    timeout=10,
                )
                rows = chk.json() if chk.headers.get("content-type", "").startswith("application/json") else []
                if isinstance(rows, list):
                    for row in rows:
                        try:
                            row_id = str((row or {}).get("id") or "").strip()
                        except Exception:
                            row_id = ""
                        if row_id == rid:
                            owned = True
                            break
                if owned:
                    break
            if not owned:
                raise HTTPException(status_code=404, detail="payment request not found")
        r = httpx.post(
            _payments_url(f"/requests/{rid}/cancel"),
            headers=_payments_headers(),
            timeout=10,
        )
        return r.json() if r.headers.get("content-type", "").startswith("application/json") else {"raw": r.text}
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/payments/cash/redeem")
async def payments_cash_redeem(req: Request):
    _require_admin_v2(req)
    if not PAYMENTS_INTERNAL_SECRET:
        raise HTTPException(status_code=403, detail="Server not configured for cash redeem")
    try:
        body = await req.json()
    except Exception:
        body = None
    headers = {"X-Internal-Secret": PAYMENTS_INTERNAL_SECRET}
    try:
        ikey = req.headers.get("Idempotency-Key") if hasattr(req, 'headers') else None
    except Exception:
        ikey = None
    if ikey:
        headers["Idempotency-Key"] = ikey
    try:
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                req_model = _PayCashRedeemReq(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            try:
                with _pay_internal_session() as s:
                    return _pay_cash_redeem(req_model, s=s, admin_ok=True)
            except HTTPException:
                raise
            except Exception as e:
                raise HTTPException(status_code=502, detail=str(e))
        r = httpx.post(
            _payments_url("/cash/redeem"),
            json=body,
            headers=_payments_headers(headers),
            timeout=10,
        )
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/payments/cash/cancel")
async def payments_cash_cancel(req: Request):
    _require_admin_v2(req)
    if not PAYMENTS_INTERNAL_SECRET:
        raise HTTPException(status_code=403, detail="Server not configured for cash cancel")
    try:
        body = await req.json()
    except Exception:
        body = None
    headers = {"X-Internal-Secret": PAYMENTS_INTERNAL_SECRET}
    try:
        ikey = req.headers.get("Idempotency-Key") if hasattr(req, 'headers') else None
    except Exception:
        ikey = None
    if ikey:
        headers["Idempotency-Key"] = ikey
    try:
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                req_model = _PayCashCancelReq(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            try:
                with _pay_internal_session() as s:
                    return _pay_cash_cancel(req_model, s=s, admin_ok=True)
            except HTTPException:
                raise
            except Exception as e:
                raise HTTPException(status_code=502, detail=str(e))
        r = httpx.post(
            _payments_url("/cash/cancel"),
            json=body,
            headers=_payments_headers(headers),
            timeout=10,
        )
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/payments/cash/status/{code}")
def payments_cash_status(code: str):
    try:
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            try:
                with _pay_internal_session() as s:
                    return _pay_cash_status(code=code, s=s)
            except HTTPException:
                raise
            except Exception as e:
                raise HTTPException(status_code=502, detail=str(e))
        r = httpx.get(
            _payments_url(f"/cash/status/{code}"),
            headers=_payments_headers(),
            timeout=10,
        )
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


# ---- Sonic Pay proxies ----
@app.post("/payments/sonic/issue")
async def payments_sonic_issue(req: Request):
    _require_admin_v2(req)
    if not PAYMENTS_INTERNAL_SECRET:
        raise HTTPException(status_code=403, detail="Server not configured for sonic issue")
    try:
        body = await req.json()
    except Exception:
        body = None
    headers = {"X-Internal-Secret": PAYMENTS_INTERNAL_SECRET}
    try:
        ikey = req.headers.get("Idempotency-Key") if hasattr(req, 'headers') else None
    except Exception:
        ikey = None
    if ikey:
        headers["Idempotency-Key"] = ikey
    try:
        body = _normalize_amount(body)
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                req_model = _PaySonicIssueReq(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            try:
                with _pay_internal_session() as s:
                    return _pay_sonic_issue(req_model, s=s, admin_ok=True)
            except HTTPException:
                raise
            except Exception as e:
                raise HTTPException(status_code=502, detail=str(e))
        r = httpx.post(
            _payments_url("/sonic/issue"),
            json=body,
            headers=_payments_headers(headers),
            timeout=10,
        )
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/payments/sonic/redeem")
async def payments_sonic_redeem(req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    if not isinstance(body, dict):
        body = {}
    # Auto-fill to_wallet_id from the authenticated user when missing.
    phone = _auth_phone(req)
    to_wallet = (body.get("to_wallet_id") or "").strip()
    if not to_wallet and phone:
        try:
            to_wallet = _resolve_wallet_id_for_phone(phone) or ""
        except Exception:
            to_wallet = ""
        if to_wallet:
            body["to_wallet_id"] = to_wallet
    headers = {}
    try:
        ikey = req.headers.get("Idempotency-Key") if hasattr(req, 'headers') else None
    except Exception:
        ikey = None
    if ikey:
        headers["Idempotency-Key"] = ikey
    try:
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                req_model = _PaySonicRedeemReq(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            try:
                with _pay_internal_session() as s:
                    return _pay_sonic_redeem(req_model, request=req, s=s)
            except HTTPException:
                raise
            except Exception as e:
                raise HTTPException(status_code=502, detail=str(e))
        r = httpx.post(
            _payments_url("/sonic/redeem"),
            json=body,
            headers=_payments_headers(headers),
            timeout=10,
        )
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


# ---- Red Packet (WeChat-style hongbao) proxies ----
@app.post("/payments/redpacket/issue")
async def payments_redpacket_issue(req: Request):
    # User-initiated pooled payment; mirrors /payments/transfer semantics.
    try:
        body = await req.json()
    except Exception:
        body = None
    headers: dict[str, str] = {}
    try:
        ikey = req.headers.get("Idempotency-Key") if hasattr(req, "headers") else None
        dev = req.headers.get("X-Device-ID") if hasattr(req, "headers") else None
        ua = req.headers.get("User-Agent") if hasattr(req, "headers") else None
    except Exception:
        ikey = None
        dev = None
        ua = None
    if ikey:
        headers["Idempotency-Key"] = ikey
    if dev:
        headers["X-Device-ID"] = dev
    if ua:
        headers["User-Agent"] = ua
    try:
        body = _normalize_amount(body)
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                req_model = _PayRedPacketIssueReq(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            try:
                with _pay_internal_session() as s:
                    result = _pay_redpacket_issue(req_model, s=s)
                try:
                    payload = {}
                    if isinstance(body, dict):
                        payload = {
                            "redpacket_id": getattr(result, "id", None),
                            "creator_wallet_id": body.get("creator_wallet_id"),
                            "amount_cents": body.get("amount_cents"),
                            "count": body.get("count"),
                            "mode": body.get("mode"),
                            "group_id": body.get("group_id"),
                        }
                    emit_event("payments", "redpacket_issue", payload)
                except Exception:
                    pass
                return result
            except HTTPException:
                raise
            except Exception as e:
                raise HTTPException(status_code=502, detail=str(e))
        r = httpx.post(
            _payments_url("/redpacket/issue"),
            json=body,
            headers=_payments_headers(headers),
            timeout=10,
        )
        out = r.json()
        try:
            payload = {}
            if isinstance(body, dict):
                payload = {
                    "redpacket_id": out.get("id"),
                    "creator_wallet_id": body.get("creator_wallet_id"),
                    "amount_cents": body.get("amount_cents"),
                    "count": body.get("count"),
                    "mode": body.get("mode"),
                    "group_id": body.get("group_id"),
                }
            emit_event("payments", "redpacket_issue", payload)
        except Exception:
            pass
        return out
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/payments/redpacket/claim")
async def payments_redpacket_claim(req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    if not isinstance(body, dict):
        body = {}
    # Auto-fill wallet_id for authenticated user when missing.
    phone = _auth_phone(req)
    wallet_id = (body.get("wallet_id") or "").strip()
    if not wallet_id and phone:
        try:
            wallet_id = _resolve_wallet_id_for_phone(phone) or ""
        except Exception:
            wallet_id = ""
        if wallet_id:
            body["wallet_id"] = wallet_id
    headers: dict[str, str] = {}
    try:
        ikey = req.headers.get("Idempotency-Key") if hasattr(req, "headers") else None
    except Exception:
        ikey = None
    if ikey:
        headers["Idempotency-Key"] = ikey
    try:
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                req_model = _PayRedPacketClaimReq(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            try:
                with _pay_internal_session() as s:
                    result = _pay_redpacket_claim(req_model, s=s)
                try:
                    payload = {}
                    if isinstance(body, dict):
                        payload = {
                            "redpacket_id": body.get("redpacket_id"),
                            "wallet_id": body.get("wallet_id"),
                        }
                    emit_event("payments", "redpacket_claim", payload)
                except Exception:
                    pass
                return result
            except HTTPException:
                raise
            except Exception as e:
                raise HTTPException(status_code=502, detail=str(e))
        r = httpx.post(
            _payments_url("/redpacket/claim"),
            json=body,
            headers=_payments_headers(headers),
            timeout=10,
        )
        out = r.json()
        try:
            payload = {}
            if isinstance(body, dict):
                payload = {
                    "redpacket_id": body.get("redpacket_id"),
                    "wallet_id": body.get("wallet_id"),
                    "amount_cents": out.get("amount_cents"),
                }
            emit_event("payments", "redpacket_claim", payload)
        except Exception:
            pass
        return out
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/payments/redpacket/status/{rid}")
def payments_redpacket_status(rid: str):
    try:
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            try:
                with _pay_internal_session() as s:
                    return _pay_redpacket_status(rid=rid, s=s)
            except HTTPException:
                raise
            except Exception as e:
                raise HTTPException(status_code=502, detail=str(e))
        r = httpx.get(
            _payments_url(f"/redpacket/status/{rid}"),
            headers=_payments_headers(),
            timeout=10,
        )
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/payments/idempotency/{ikey}")
def payments_idempotency(ikey: str, request: Request):
    _require_caller_wallet(request)
    try:
        r = httpx.get(
            _payments_url(f"/idempotency/{ikey}"),
            headers=_payments_headers(),
            timeout=10,
        )
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


# ---- Savings proxies ----
@app.post("/payments/savings/deposit")
async def payments_savings_deposit(req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    if not isinstance(body, dict):
        body = {}
    # Auto-fill wallet_id from authenticated user.
    phone = _auth_phone(req)
    wid = (body.get("wallet_id") or "").strip()
    if not wid and phone:
        try:
            wid = _resolve_wallet_id_for_phone(phone) or ""
        except Exception:
            wid = ""
        if wid:
            body["wallet_id"] = wid
    body = _normalize_amount(body)
    headers: dict[str, str] = {}
    try:
        ikey = req.headers.get("Idempotency-Key") if hasattr(req, "headers") else None
    except Exception:
        ikey = None
    if ikey:
        headers["Idempotency-Key"] = ikey
    try:
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                req_model = _PaySavingsDepositReq(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            try:
                with _pay_internal_session() as s:
                    result = _pay_savings_deposit(req_model, s=s)
                try:
                    payload = {}
                    if isinstance(body, dict):
                        payload = {
                            "wallet_id": body.get("wallet_id"),
                            "amount_cents": body.get("amount_cents"),
                        }
                    emit_event("payments", "savings_deposit", payload)
                except Exception:
                    pass
                return result
            except HTTPException:
                raise
            except Exception as e:
                raise HTTPException(status_code=502, detail=str(e))
        r = httpx.post(
            _payments_url("/savings/deposit"),
            json=body,
            headers=_payments_headers(headers),
            timeout=10,
        )
        out = r.json()
        try:
            payload = {}
            if isinstance(body, dict):
                payload = {
                    "wallet_id": body.get("wallet_id"),
                    "amount_cents": body.get("amount_cents"),
                }
            emit_event("payments", "savings_deposit", payload)
        except Exception:
            pass
        return out
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/payments/savings/withdraw")
async def payments_savings_withdraw(req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    if not isinstance(body, dict):
        body = {}
    phone = _auth_phone(req)
    wid = (body.get("wallet_id") or "").strip()
    if not wid and phone:
        try:
            wid = _resolve_wallet_id_for_phone(phone) or ""
        except Exception:
            wid = ""
        if wid:
            body["wallet_id"] = wid
    body = _normalize_amount(body)
    headers: dict[str, str] = {}
    try:
        ikey = req.headers.get("Idempotency-Key") if hasattr(req, "headers") else None
    except Exception:
        ikey = None
    if ikey:
        headers["Idempotency-Key"] = ikey
    try:
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                req_model = _PaySavingsWithdrawReq(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            try:
                with _pay_internal_session() as s:
                    result = _pay_savings_withdraw(req_model, s=s)
                try:
                    payload = {}
                    if isinstance(body, dict):
                        payload = {
                            "wallet_id": body.get("wallet_id"),
                            "amount_cents": body.get("amount_cents"),
                        }
                    emit_event("payments", "savings_withdraw", payload)
                except Exception:
                    pass
                return result
            except HTTPException:
                raise
            except Exception as e:
                raise HTTPException(status_code=502, detail=str(e))
        r = httpx.post(
            _payments_url("/savings/withdraw"),
            json=body,
            headers=_payments_headers(headers),
            timeout=10,
        )
        out = r.json()
        try:
            payload = {}
            if isinstance(body, dict):
                payload = {
                    "wallet_id": body.get("wallet_id"),
                    "amount_cents": body.get("amount_cents"),
                }
            emit_event("payments", "savings_withdraw", payload)
        except Exception:
            pass
        return out
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/payments/savings/overview")
def payments_savings_overview(wallet_id: str):
    try:
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            try:
                with _pay_internal_session() as s:
                    return _pay_savings_overview(wallet_id=wallet_id, s=s)
            except HTTPException:
                raise
            except Exception as e:
                raise HTTPException(status_code=502, detail=str(e))
        r = httpx.get(
            _payments_url(f"/savings/overview?wallet_id={wallet_id}"),
            headers=_payments_headers(),
            timeout=10,
        )
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/payments/bills/pay")
async def payments_bills_pay(req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    if not isinstance(body, dict):
        body = {}
    # Normalize amount payload so both internal + HTTP share the same format.
    body = _normalize_amount(body)
    headers: dict[str, str] = {}
    try:
        ikey = req.headers.get("Idempotency-Key") if hasattr(req, "headers") else None
        dev = req.headers.get("X-Device-ID") if hasattr(req, "headers") else None
        ua = req.headers.get("User-Agent") if hasattr(req, "headers") else None
    except Exception:
        ikey = None
        dev = None
        ua = None
    if ikey:
        headers["Idempotency-Key"] = ikey
    if dev:
        headers["X-Device-ID"] = dev
    if ua:
        headers["User-Agent"] = ua
    try:
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(
                    status_code=500, detail="payments internal not available"
                )
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                req_model = _PayBillPayReq(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            try:
                with _pay_internal_session() as s:
                    result = _pay_bills_pay(req_model, request=req, s=s)
                try:
                    payload = {}
                    if isinstance(body, dict):
                        payload = {
                            "from_wallet_id": body.get("from_wallet_id"),
                            "to_wallet_id": body.get("to_wallet_id"),
                            "biller_code": body.get("biller_code"),
                            "amount_cents": body.get("amount_cents"),
                            "device_id": dev,
                        }
                    emit_event("payments", "bill_pay", payload)
                except Exception:
                    pass
                return result
            except HTTPException:
                raise
            except Exception as e:
                raise HTTPException(status_code=502, detail=str(e))
        r = httpx.post(
            _payments_url("/bills/pay"),
            json=body,
            headers=_payments_headers(headers),
            timeout=10,
        )
        out = r.json()
        try:
            payload = {}
            if isinstance(body, dict):
                payload = {
                    "from_wallet_id": body.get("from_wallet_id"),
                    "to_wallet_id": body.get("to_wallet_id"),
                    "biller_code": body.get("biller_code"),
                    "amount_cents": body.get("amount_cents"),
                    "device_id": dev,
                }
            emit_event("payments", "bill_pay", payload)
        except Exception:
            pass
        return out
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


def _payments_billers_config() -> list[dict[str, str]]:
    return [
        {
            "code": "electricity",
            "label_en": "Electricity",
            "label_ar": "الكهرباء",
            "wallet_id": os.getenv("BILLER_ELECTRICITY_WALLET_ID", ""),
        },
        {
            "code": "mobile",
            "label_en": "Mobile top‑up",
            "label_ar": "شحن الجوال",
            "wallet_id": os.getenv("BILLER_MOBILE_WALLET_ID", ""),
        },
        {
            "code": "internet",
            "label_en": "Internet",
            "label_ar": "الإنترنت",
            "wallet_id": os.getenv("BILLER_INTERNET_WALLET_ID", ""),
        },
        {
            "code": "water",
            "label_en": "Water",
            "label_ar": "المياه",
            "wallet_id": os.getenv("BILLER_WATER_WALLET_ID", ""),
        },
    ]


@app.get("/payments/billers")
def payments_billers():
    """
    Static biller directory for enduser clients.

    Wallet IDs can be configured via environment variables:
      - BILLER_ELECTRICITY_WALLET_ID
      - BILLER_MOBILE_WALLET_ID
      - BILLER_INTERNET_WALLET_ID
      - BILLER_WATER_WALLET_ID
    """
    return _payments_billers_config()


# ---- Alias proxies ----
@app.post("/payments/alias/request")
async def payments_alias_request(req: Request):
    _phone, caller_wallet_id = _require_caller_wallet(req)
    try:
        body = await req.json()
    except Exception:
        body = None
    if not isinstance(body, dict):
        body = {}
    payload = dict(body)
    requested_wallet_id = str(payload.get("wallet_id") or "").strip()
    requested_user_id = str(payload.get("user_id") or "").strip()
    if requested_wallet_id and requested_wallet_id != caller_wallet_id:
        _audit_from_request(
            req,
            "alias_request_wallet_mismatch",
            requested_wallet_id=requested_wallet_id,
            caller_wallet_id=caller_wallet_id,
        )
        raise HTTPException(status_code=403, detail="wallet_id does not belong to caller")
    if requested_user_id:
        _audit_from_request(
            req,
            "alias_request_user_override_blocked",
            requested_user_id=requested_user_id,
        )
        raise HTTPException(status_code=403, detail="user_id override not allowed")
    payload["wallet_id"] = caller_wallet_id
    payload.pop("user_id", None)
    try:
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            data = payload or {}
            if not isinstance(data, dict):
                data = {}
            try:
                req_model = _PayAliasRequest(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            try:
                with _pay_internal_session() as s:
                    return _pay_alias_request(req_model, s=s)
            except HTTPException:
                raise
            except Exception as e:
                raise HTTPException(status_code=502, detail=str(e))
        r = httpx.post(
            _payments_url("/alias/request"),
            json=payload,
            headers=_payments_headers(),
            timeout=10,
        )
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))



# ---- Admin alias moderation proxies ----
@app.post("/payments/admin/alias/block")
async def payments_admin_alias_block(req: Request):
    _require_superadmin(req)
    if not PAYMENTS_INTERNAL_SECRET:
        raise HTTPException(status_code=403, detail="Server not configured for admin alias")
    try:
        body = await req.json()
    except Exception:
        body = None
    headers = {"X-Internal-Secret": PAYMENTS_INTERNAL_SECRET}
    try:
        r = httpx.post(
            _payments_url("/admin/alias/block"),
            json=body,
            headers=_payments_headers(headers),
            timeout=10,
        )
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/payments/admin/alias/rename")
async def payments_admin_alias_rename(req: Request):
    _require_superadmin(req)
    if not PAYMENTS_INTERNAL_SECRET:
        raise HTTPException(status_code=403, detail="Server not configured for admin alias")
    try:
        body = await req.json()
    except Exception:
        body = None
    headers = {"X-Internal-Secret": PAYMENTS_INTERNAL_SECRET}
    try:
        r = httpx.post(
            _payments_url("/admin/alias/rename"),
            json=body,
            headers=_payments_headers(headers),
            timeout=10,
        )
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/payments/admin/alias/search")
def payments_admin_alias_search(request: Request, handle: str = "", status: str = "", user_id: str = "", limit: int = 50):
    _require_superadmin(request)
    if not PAYMENTS_INTERNAL_SECRET:
        raise HTTPException(status_code=403, detail="Server not configured for admin alias")
    headers = {"X-Internal-Secret": PAYMENTS_INTERNAL_SECRET}
    params = {}
    if handle:
        params["handle"] = handle
    if status:
        params["status"] = status
    if user_id:
        params["user_id"] = user_id
    params["limit"] = limit
    try:
        r = httpx.get(
            _payments_url("/admin/alias/search"),
            headers=_payments_headers(headers),
            params=params,
            timeout=10,
        )
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


# ---- Admin risk proxies ----
@app.get("/payments/admin/risk/metrics")
def payments_admin_risk_metrics(request: Request, minutes: int = 5, top: int = 10):
    _require_superadmin(request)
    if not PAYMENTS_INTERNAL_SECRET:
        raise HTTPException(status_code=403, detail="Server not configured for admin risk")
    headers = {"X-Internal-Secret": PAYMENTS_INTERNAL_SECRET}
    params = {"minutes": minutes, "top": top}
    try:
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            with _pay_internal_session() as s:
                result = _pay_admin_risk_metrics(minutes=minutes, top=top, s=s, admin_ok=True)
        else:
            r = httpx.get(
                _payments_url("/admin/risk/metrics"),
                headers=_payments_headers(headers),
                params=params,
                timeout=10,
            )
            result = r.json()
        _audit_from_request(request, "risk_metrics", minutes=minutes, top=top)
        return result
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


# ---- Payments merchant export proxy ----
@app.get("/payments/admin/export/merchant")
def payments_admin_export_merchant(request: Request, merchant: str, from_iso: str = "", to_iso: str = ""):
    _require_admin_v2(request)
    if not PAYMENTS_INTERNAL_SECRET:
        raise HTTPException(status_code=403, detail="Server not configured for admin export")
    headers = {"X-Internal-Secret": PAYMENTS_INTERNAL_SECRET}
    params = {"merchant": merchant}
    if from_iso:
        params["from_iso"] = from_iso
    if to_iso:
        params["to_iso"] = to_iso
    try:
        _audit_from_request(request, "export_merchant_txns", merchant=merchant, from_iso=from_iso or None, to_iso=to_iso or None)
        with httpx.stream(
            "GET",
            _payments_url("/admin/txns/export_by_merchant"),
            headers=_payments_headers(headers),
            params=params,
            timeout=None,
        ) as r:
            disp = r.headers.get("content-disposition", f"attachment; filename=txns_{merchant}.csv")
            return StreamingResponse(r.iter_bytes(), media_type="text/csv", headers={"Content-Disposition": disp})
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/payments/admin/risk/events")
def payments_admin_risk_events(request: Request, minutes: int = 5, to_wallet_id: str = "", device_id: str = "", ip: str = "", limit: int = 100):
    _require_superadmin(request)
    if not PAYMENTS_INTERNAL_SECRET:
        raise HTTPException(status_code=403, detail="Server not configured for admin risk")
    headers = {"X-Internal-Secret": PAYMENTS_INTERNAL_SECRET}
    params = {"minutes": minutes, "limit": limit}
    if to_wallet_id:
        params["to_wallet_id"] = to_wallet_id
    if device_id:
        params["device_id"] = device_id
    if ip:
        params["ip"] = ip
    try:
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            with _pay_internal_session() as s:
                result = _pay_admin_risk_events(minutes=minutes, to_wallet_id=to_wallet_id or None, device_id=device_id or None, ip=ip or None, limit=limit, s=s, admin_ok=True)
        else:
            r = httpx.get(
                _payments_url("/admin/risk/events"),
                headers=_payments_headers(headers),
                params=params,
                timeout=10,
            )
            result = r.json()
        _audit_from_request(
            request,
            "risk_events",
            minutes=minutes,
            to_wallet_id=to_wallet_id or None,
            device_id=device_id or None,
            ip=ip or None,
            limit=limit,
        )
        return result
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/payments/admin/risk/deny/add")
async def payments_admin_risk_deny_add(req: Request):
    _require_superadmin(req)
    if not PAYMENTS_INTERNAL_SECRET:
        raise HTTPException(status_code=403, detail="Server not configured for admin risk")
    try:
        body = await req.json()
    except Exception:
        body = None
    headers = {"X-Internal-Secret": PAYMENTS_INTERNAL_SECRET}
    try:
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                rreq = _PayRiskDenyReq(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _pay_internal_session() as s:
                result = _pay_admin_risk_deny_add(rreq, s=s, admin_ok=True)
        else:
            r = httpx.post(
                _payments_url("/admin/risk/deny/add"),
                json=body,
                headers=_payments_headers(headers),
                timeout=10,
            )
            result = r.json()
        kind = ""
        value = ""
        try:
            if isinstance(body, dict):
                kind = (body.get("kind") or "").strip()
                value = (body.get("value") or "").strip()
        except Exception:
            pass
        _audit_from_request(req, "risk_deny_add", kind=kind, value=value)
        return result
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/payments/admin/risk/deny/remove")
async def payments_admin_risk_deny_remove(req: Request):
    _require_superadmin(req)
    if not PAYMENTS_INTERNAL_SECRET:
        raise HTTPException(status_code=403, detail="Server not configured for admin risk")
    try:
        body = await req.json()
    except Exception:
        body = None
    headers = {"X-Internal-Secret": PAYMENTS_INTERNAL_SECRET}
    try:
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                rreq = _PayRiskDenyReq(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _pay_internal_session() as s:
                result = _pay_admin_risk_deny_remove(rreq, s=s, admin_ok=True)
        else:
            r = httpx.post(
                _payments_url("/admin/risk/deny/remove"),
                json=body,
                headers=_payments_headers(headers),
                timeout=10,
            )
            result = r.json()
        kind = ""
        value = ""
        try:
            if isinstance(body, dict):
                kind = (body.get("kind") or "").strip()
                value = (body.get("value") or "").strip()
        except Exception:
            pass
        _audit_from_request(req, "risk_deny_remove", kind=kind, value=value)
        return result
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/payments/admin/risk/deny/list")
def payments_admin_risk_deny_list(request: Request, kind: str = "", limit: int = 200):
    _require_superadmin(request)
    if not PAYMENTS_INTERNAL_SECRET:
        raise HTTPException(status_code=403, detail="Server not configured for admin risk")
    headers = {"X-Internal-Secret": PAYMENTS_INTERNAL_SECRET}
    params = {"limit": limit}
    if kind:
        params["kind"] = kind
    try:
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            with _pay_internal_session() as s:
                result = _pay_admin_risk_deny_list(kind=kind or None, limit=limit, s=s, admin_ok=True)
        else:
            r = httpx.get(
                _payments_url("/admin/risk/deny/list"),
                headers=_payments_headers(headers),
                params=params,
                timeout=10,
            )
            result = r.json()
        _audit_from_request(request, "risk_deny_list", kind=kind or None, limit=limit)
        return result
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


# ---- Moments (lightweight social feed, BFF-side) ----

_MOMENTS_DB_URL = _env_or(
    "MOMENTS_DB_URL", _env_or("DB_URL", "sqlite+pysqlite:////tmp/moments.db")
)


class _MomentsBase(_sa_DeclarativeBase):
    pass


class MomentPostDB(_MomentsBase):
    __tablename__ = "moments_posts"
    id: _sa_Mapped[int] = _sa_mapped_column(
        _sa_Integer, primary_key=True, autoincrement=True
    )
    user_key: _sa_Mapped[str] = _sa_mapped_column(
        _sa_String(128), index=True
    )
    text: _sa_Mapped[str] = _sa_mapped_column(_sa_Text)
    visibility: _sa_Mapped[str] = _sa_mapped_column(
        _sa_String(16), default="public"
    )
    audience_tag: _sa_Mapped[str | None] = _sa_mapped_column(
        _sa_String(64), nullable=True
    )
    location_label: _sa_Mapped[str | None] = _sa_mapped_column(
        _sa_String(128), nullable=True
    )
    images_b64_json: _sa_Mapped[str | None] = _sa_mapped_column(
        _sa_Text, nullable=True
    )
    image_b64: _sa_Mapped[str | None] = _sa_mapped_column(
        _sa_Text, nullable=True
    )
    image_url: _sa_Mapped[str | None] = _sa_mapped_column(
        _sa_String(255), nullable=True
    )
    origin_official_account_id: _sa_Mapped[str | None] = _sa_mapped_column(
        _sa_String(64), nullable=True
    )
    origin_official_item_id: _sa_Mapped[str | None] = _sa_mapped_column(
        _sa_String(64), nullable=True
    )
    created_at: _sa_Mapped[datetime] = _sa_mapped_column(
        _sa_DateTime(timezone=True), server_default=_sa_func.now()
    )


class MomentLikeDB(_MomentsBase):
    __tablename__ = "moments_likes"
    __table_args__ = (
        _sa_UniqueConstraint(
            "user_key",
            "post_id",
            name="uq_moments_likes_user_post",
        ),
    )
    id: _sa_Mapped[int] = _sa_mapped_column(
        _sa_Integer, primary_key=True, autoincrement=True
    )
    post_id: _sa_Mapped[int] = _sa_mapped_column(
        _sa_Integer, index=True
    )
    user_key: _sa_Mapped[str] = _sa_mapped_column(
        _sa_String(128), index=True
    )
    created_at: _sa_Mapped[datetime] = _sa_mapped_column(
        _sa_DateTime(timezone=True), server_default=_sa_func.now()
    )


class MomentCommentDB(_MomentsBase):
    __tablename__ = "moments_comments"
    id: _sa_Mapped[int] = _sa_mapped_column(
        _sa_Integer, primary_key=True, autoincrement=True
    )
    post_id: _sa_Mapped[int] = _sa_mapped_column(_sa_Integer, index=True)
    user_key: _sa_Mapped[str] = _sa_mapped_column(
        _sa_String(128), index=True
    )
    text: _sa_Mapped[str] = _sa_mapped_column(_sa_Text)
    reply_to_id: _sa_Mapped[int | None] = _sa_mapped_column(
        _sa_Integer, nullable=True
    )
    created_at: _sa_Mapped[datetime] = _sa_mapped_column(
        _sa_DateTime(timezone=True), server_default=_sa_func.now()
    )


class MomentCommentLikeDB(_MomentsBase):
    __tablename__ = "moments_comment_likes"
    __table_args__ = (
        _sa_UniqueConstraint(
            "user_key",
            "comment_id",
            name="uq_moments_comment_likes_user_comment",
        ),
    )
    id: _sa_Mapped[int] = _sa_mapped_column(
        _sa_Integer, primary_key=True, autoincrement=True
    )
    comment_id: _sa_Mapped[int] = _sa_mapped_column(_sa_Integer, index=True)
    user_key: _sa_Mapped[str] = _sa_mapped_column(
        _sa_String(128), index=True
    )
    created_at: _sa_Mapped[datetime] = _sa_mapped_column(
        _sa_DateTime(timezone=True), server_default=_sa_func.now()
    )


class MomentTagDB(_MomentsBase):
    __tablename__ = "moments_tags"
    __table_args__ = (
        _sa_UniqueConstraint(
            "post_id",
            "tag",
            name="uq_moments_tags_post_tag",
        ),
    )
    id: _sa_Mapped[int] = _sa_mapped_column(
        _sa_Integer, primary_key=True, autoincrement=True
    )
    post_id: _sa_Mapped[int] = _sa_mapped_column(_sa_Integer, index=True)
    tag: _sa_Mapped[str] = _sa_mapped_column(_sa_String(64), index=True)
    created_at: _sa_Mapped[datetime] = _sa_mapped_column(
        _sa_DateTime(timezone=True), server_default=_sa_func.now()
    )


_moments_engine = _sa_create_engine(_MOMENTS_DB_URL, future=True)


def _moments_session() -> _sa_Session:
    return _sa_Session(_moments_engine)


class MomentPostOut(BaseModel):
    id: str
    text: str
    ts: str
    likes: int = 0
    liked_by_me: bool = False
    liked_by: list[str] | None = None
    comments: int = 0
    has_official_reply: bool = False
    visibility: str = "public"
    image_b64: str | None = None
    image_url: str | None = None
    author_name: str | None = None
    audience_tag: str | None = None
    location_label: str | None = None
    images: list[str] | None = None
    origin_official_account_id: str | None = None
    origin_official_item_id: str | None = None


class MomentCommentOut(BaseModel):
    id: str
    text: str
    ts: str
    author_name: str | None = None
    reply_to_id: str | None = None
    reply_to_name: str | None = None
    likes: int = 0
    liked_by_me: bool = False


class MomentNotificationsOut(BaseModel):
    last_comment_ts: str | None = None
    total_comments: int = 0
    redpacket_posts_30d: int = 0


class OfficialMomentsStatsOut(BaseModel):
    service_shares: int = 0
    subscription_shares: int = 0
    total_shares: int = 0
    redpacket_shares_30d: int = 0
    hot_accounts: int = 0


def _moments_cookie_key(request: Request) -> str:
    cookie = request.headers.get("sa_cookie") or request.cookies.get("sa_cookie") or ""
    if not cookie:
        cookie = "anon"
    return cookie


def _channels_user_key(request: Request) -> str:
    """
    Derive a stable per-user key for the Channels follower graph.

    Prefer an authenticated phone-based key when available so
    follows survive device changes, otherwise fall back to the
    Moments cookie key for anonymous users.
    """
    try:
        phone = _auth_phone(request)
    except Exception:
        phone = None
    if phone:
        return f"phone:{phone}"
    return _moments_cookie_key(request)


def _moments_pseudonym_for_user_key(user_key: str) -> str | None:
    """
    Stable but privacy-friendly label for a Moments author.
    Mirrors the comment labelling (User <hash>) without exposing phone or name.
    """
    uk = (user_key or "").strip()
    if not uk:
        return None
    try:
        import hashlib

        h = hashlib.sha256(uk.encode("utf-8")).hexdigest()[:6]
        return f"User {h}"
    except Exception:
        return None


def _phone_from_moments_user_key(user_key: str) -> str | None:
    """
    Best-effort mapping from a Moments user_key (sa_cookie value)
    back to the phone number via the in-memory _SESSIONS store.
    """
    try:
        uk = (user_key or "").strip()
        if not uk or uk == "anon":
            return None
        token = uk
        if "sa_session=" in token:
            for part in token.split(";"):
                part = part.strip()
                if part.startswith("sa_session="):
                    token = part.split("=", 1)[1]
                    break
        sid = token.strip()
        if not sid:
            return None
        phone = _session_phone_from_sid(sid)
        return str(phone or "").strip() or None
    except Exception:
        return None


_MOMENTS_HASHTAG_RE = re.compile(r"#([\w]+)", re.UNICODE)


def _moments_extract_tags(text: str) -> list[str]:
    try:
        tags: set[str] = set()
        for m in _MOMENTS_HASHTAG_RE.finditer(text or ""):
            raw = (m.group(1) or "").strip().lower()
            if not raw:
                continue
            tag = raw[:64]
            tags.add(tag)
        return sorted(tags)
    except Exception:
        return []


_MOMENTS_OFFICIAL_RE = re.compile(
    r"shamell://official/([^/\s]+)(?:/([^\s]+))?", re.IGNORECASE
)


def _moments_extract_official_origin(text: str) -> tuple[str | None, str | None]:
    try:
        m = _MOMENTS_OFFICIAL_RE.search(text)
        if not m:
            return None, None
        acc = (m.group(1) or "").strip()
        item = (m.group(2) or "").strip() or None
        if not acc:
            return None, None
        return acc, item
    except Exception:
        return None, None


def _moments_startup() -> None:
    logger = logging.getLogger("shamell.moments")
    try:
        _MomentsBase.metadata.create_all(_moments_engine)
    except Exception:
        logger.exception("failed to init moments tables")
    # Best-effort schema upgrade for audience_tag column on existing deployments.
    try:
        with _moments_engine.begin() as conn:
            if _MOMENTS_DB_URL.startswith("sqlite"):
                conn.execute(
                    _sa_text(
                        "ALTER TABLE moments_posts ADD COLUMN audience_tag VARCHAR(64)"
                    )
                )
            else:
                conn.execute(
                    _sa_text(
                        "ALTER TABLE moments_posts ADD COLUMN audience_tag VARCHAR(64)"
                    )
                )
    except Exception:
        # Ignore migration errors (column may already exist).
        pass
    # Best-effort schema upgrade for location_label column on existing deployments.
    try:
        with _moments_engine.begin() as conn:
            conn.execute(
                _sa_text(
                    "ALTER TABLE moments_posts ADD COLUMN location_label VARCHAR(128)"
                )
            )
    except Exception:
        # Ignore migration errors (column may already exist).
        pass
    # Best-effort schema upgrade for images_b64_json column on existing deployments.
    try:
        with _moments_engine.begin() as conn:
            conn.execute(
                _sa_text(
                    "ALTER TABLE moments_posts ADD COLUMN images_b64_json TEXT"
                )
            )
    except Exception:
        # Ignore migration errors (column may already exist).
        pass


app.router.on_startup.append(_moments_startup)


# ---- Friends (simple phone-based graph for Moments visibility and chat) ----

FRIENDS_DB_URL = _env_or(
    "FRIENDS_DB_URL", _env_or("DB_URL", "sqlite+pysqlite:////tmp/friends.db")
)


class _FriendsBase(_sa_DeclarativeBase):
    pass


class FriendDB(_FriendsBase):
    __tablename__ = "friends"
    __table_args__ = (
        _sa_UniqueConstraint(
            "user_phone",
            "friend_phone",
            name="uq_friends_user_friend",
        ),
    )
    id: _sa_Mapped[int] = _sa_mapped_column(
        _sa_Integer, primary_key=True, autoincrement=True
    )
    user_phone: _sa_Mapped[str] = _sa_mapped_column(_sa_String(32), index=True)
    friend_phone: _sa_Mapped[str] = _sa_mapped_column(_sa_String(32), index=True)
    created_at: _sa_Mapped[datetime] = _sa_mapped_column(
        _sa_DateTime(timezone=True), server_default=_sa_func.now()
    )


class FriendTagDB(_FriendsBase):
    __tablename__ = "friend_tags"
    __table_args__ = (
        _sa_UniqueConstraint(
            "user_phone",
            "friend_phone",
            "tag",
            name="uq_friend_tags_user_friend_tag",
        ),
    )
    id: _sa_Mapped[int] = _sa_mapped_column(
        _sa_Integer, primary_key=True, autoincrement=True
    )
    user_phone: _sa_Mapped[str] = _sa_mapped_column(_sa_String(32), index=True)
    friend_phone: _sa_Mapped[str] = _sa_mapped_column(_sa_String(32), index=True)
    tag: _sa_Mapped[str] = _sa_mapped_column(_sa_String(64), index=True)
    created_at: _sa_Mapped[datetime] = _sa_mapped_column(
        _sa_DateTime(timezone=True), server_default=_sa_func.now()
    )


class CloseFriendDB(_FriendsBase):
    __tablename__ = "close_friends"
    __table_args__ = (
        _sa_UniqueConstraint(
            "user_phone",
            "friend_phone",
            name="uq_close_friends_user_friend",
        ),
    )
    id: _sa_Mapped[int] = _sa_mapped_column(
        _sa_Integer, primary_key=True, autoincrement=True
    )
    user_phone: _sa_Mapped[str] = _sa_mapped_column(_sa_String(32), index=True)
    friend_phone: _sa_Mapped[str] = _sa_mapped_column(_sa_String(32), index=True)
    created_at: _sa_Mapped[datetime] = _sa_mapped_column(
        _sa_DateTime(timezone=True), server_default=_sa_func.now()
    )


class FriendRequestDB(_FriendsBase):
    __tablename__ = "friend_requests"
    id: _sa_Mapped[int] = _sa_mapped_column(
        _sa_Integer, primary_key=True, autoincrement=True
    )
    from_phone: _sa_Mapped[str] = _sa_mapped_column(_sa_String(32), index=True)
    to_phone: _sa_Mapped[str] = _sa_mapped_column(_sa_String(32), index=True)
    status: _sa_Mapped[str] = _sa_mapped_column(_sa_String(16), default="pending")
    created_at: _sa_Mapped[datetime] = _sa_mapped_column(
        _sa_DateTime(timezone=True), server_default=_sa_func.now()
    )


_friends_engine = _sa_create_engine(FRIENDS_DB_URL, future=True)
_friends_inited = False


def _friends_session() -> _sa_Session:
    """
    Returns a session for the friends DB.

    Similar to _officials_session, this lazily initialises the schema so that
    deployments that bypass FastAPI's startup events still get the friends
    tables (friends, close_friends, friend_tags, friend_requests).
    """
    global _friends_inited
    if not _friends_inited:
        try:
            _friends_startup()  # type: ignore[name-defined]
        except Exception:
            logging.getLogger("shamell.friends").exception(
                "failed to init friends DB from session helper"
            )
        _friends_inited = True
    return _sa_Session(_friends_engine)


def _friends_startup() -> None:
    logger = logging.getLogger("shamell.friends")
    try:
        _FriendsBase.metadata.create_all(_friends_engine)
    except Exception:
        logger.exception("failed to init friends tables via metadata")
    # Best-effort schema upgrade for FriendsDB on existing deployments,
    # mirroring the pattern used for Officials/Channels.
    try:
        with _friends_engine.begin() as conn:
            if FRIENDS_DB_URL.startswith("sqlite"):
                conn.execute(
                    _sa_text(
                        "CREATE TABLE IF NOT EXISTS friends ("
                        "id INTEGER PRIMARY KEY AUTOINCREMENT, "
                        "user_phone VARCHAR(32) NOT NULL, "
                        "friend_phone VARCHAR(32) NOT NULL, "
                        "created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP, "
                        "CONSTRAINT uq_friends_user_friend UNIQUE (user_phone, friend_phone)"
                        ")"
                    )
                )
                conn.execute(
                    _sa_text(
                        "CREATE TABLE IF NOT EXISTS friend_tags ("
                        "id INTEGER PRIMARY KEY AUTOINCREMENT, "
                        "user_phone VARCHAR(32) NOT NULL, "
                        "friend_phone VARCHAR(32) NOT NULL, "
                        "tag VARCHAR(64) NOT NULL, "
                        "created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP, "
                        "CONSTRAINT uq_friend_tags_user_friend_tag "
                        "UNIQUE (user_phone, friend_phone, tag)"
                        ")"
                    )
                )
                conn.execute(
                    _sa_text(
                        "CREATE TABLE IF NOT EXISTS close_friends ("
                        "id INTEGER PRIMARY KEY AUTOINCREMENT, "
                        "user_phone VARCHAR(32) NOT NULL, "
                        "friend_phone VARCHAR(32) NOT NULL, "
                        "created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP, "
                        "CONSTRAINT uq_close_friends_user_friend "
                        "UNIQUE (user_phone, friend_phone)"
                        ")"
                    )
                )
                conn.execute(
                    _sa_text(
                        "CREATE TABLE IF NOT EXISTS friend_requests ("
                        "id INTEGER PRIMARY KEY AUTOINCREMENT, "
                        "from_phone VARCHAR(32) NOT NULL, "
                        "to_phone VARCHAR(32) NOT NULL, "
                        "status VARCHAR(16) DEFAULT 'pending', "
                        "created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP"
                        ")"
                    )
                )
            else:
                conn.execute(
                    _sa_text(
                        "CREATE TABLE IF NOT EXISTS friends ("
                        "id SERIAL PRIMARY KEY, "
                        "user_phone VARCHAR(32) NOT NULL, "
                        "friend_phone VARCHAR(32) NOT NULL, "
                        "created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP, "
                        "CONSTRAINT uq_friends_user_friend UNIQUE (user_phone, friend_phone)"
                        ")"
                    )
                )
                conn.execute(
                    _sa_text(
                        "CREATE TABLE IF NOT EXISTS friend_tags ("
                        "id SERIAL PRIMARY KEY, "
                        "user_phone VARCHAR(32) NOT NULL, "
                        "friend_phone VARCHAR(32) NOT NULL, "
                        "tag VARCHAR(64) NOT NULL, "
                        "created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP, "
                        "CONSTRAINT uq_friend_tags_user_friend_tag "
                        "UNIQUE (user_phone, friend_phone, tag)"
                        ")"
                    )
                )
                conn.execute(
                    _sa_text(
                        "CREATE TABLE IF NOT EXISTS close_friends ("
                        "id SERIAL PRIMARY KEY, "
                        "user_phone VARCHAR(32) NOT NULL, "
                        "friend_phone VARCHAR(32) NOT NULL, "
                        "created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP, "
                        "CONSTRAINT uq_close_friends_user_friend "
                        "UNIQUE (user_phone, friend_phone)"
                        ")"
                    )
                )
                conn.execute(
                    _sa_text(
                        "CREATE TABLE IF NOT EXISTS friend_requests ("
                        "id SERIAL PRIMARY KEY, "
                        "from_phone VARCHAR(32) NOT NULL, "
                        "to_phone VARCHAR(32) NOT NULL, "
                        "status VARCHAR(16) DEFAULT 'pending', "
                        "created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP"
                        ")"
                    )
                )
    except Exception:
        logger.exception("failed to ensure friends tables exist")


app.router.on_startup.append(_friends_startup)


# ---- People Nearby (demo presence for \"People nearby\" feature) ----

NEARBY_DB_URL = _env_or(
    "NEARBY_DB_URL", _env_or("DB_URL", "sqlite+pysqlite:////tmp/nearby.db")
)
NEARBY_TTL_SECS = int(os.getenv("NEARBY_TTL_SECS", "10800"))  # default: 3 hours


class _NearbyBase(_sa_DeclarativeBase):
    pass


class NearbyPresenceDB(_NearbyBase):
    """
    Lightweight presence/profile table for People Nearby.

    Stores coarse location and optional status/gender/age metadata
    so the client can implement a WeChat-style People Nearby list.
    """

    __tablename__ = "nearby_presence"
    __table_args__ = (
        _sa_UniqueConstraint(
            "user_phone",
            name="uq_nearby_presence_user_phone",
        ),
    )
    id: _sa_Mapped[int] = _sa_mapped_column(
        _sa_Integer, primary_key=True, autoincrement=True
    )
    user_phone: _sa_Mapped[str] = _sa_mapped_column(_sa_String(32), index=True)
    status: _sa_Mapped[str | None] = _sa_mapped_column(
        _sa_String(160), nullable=True
    )
    gender: _sa_Mapped[str | None] = _sa_mapped_column(
        _sa_String(16), nullable=True
    )
    age_years: _sa_Mapped[int | None] = _sa_mapped_column(
        _sa_Integer, nullable=True
    )
    last_lat: _sa_Mapped[float | None] = _sa_mapped_column(
        _sa_Float, nullable=True
    )
    last_lon: _sa_Mapped[float | None] = _sa_mapped_column(
        _sa_Float, nullable=True
    )
    updated_at: _sa_Mapped[datetime] = _sa_mapped_column(
        _sa_DateTime(timezone=True),
        server_default=_sa_func.now(),
        index=True,
    )


_nearby_engine = _sa_create_engine(NEARBY_DB_URL, future=True)
_nearby_inited = False


def _nearby_session() -> _sa_Session:
    """
    Returns a session for the nearby presence DB.

    Lazily ensures the nearby_presence table exists so that \"People nearby\"
    queries do not fail with missing-table errors even when startup hooks
    are not triggered.
    """
    global _nearby_inited
    if not _nearby_inited:
        try:
            _nearby_startup()  # type: ignore[name-defined]
        except Exception:
            logging.getLogger("shamell.nearby").exception(
                "failed to init nearby DB from session helper"
            )
        _nearby_inited = True
    return _sa_Session(_nearby_engine)


def _nearby_startup() -> None:
    logger = logging.getLogger("shamell.nearby")
    try:
        _NearbyBase.metadata.create_all(_nearby_engine)
    except Exception:
        logger.exception("failed to init nearby tables via metadata")
    # Best-effort schema upgrade for NearbyPresenceDB on existing deployments.
    try:
        with _nearby_engine.begin() as conn:
            if NEARBY_DB_URL.startswith("sqlite"):
                conn.execute(
                    _sa_text(
                        "CREATE TABLE IF NOT EXISTS nearby_presence ("
                        "id INTEGER PRIMARY KEY AUTOINCREMENT, "
                        "user_phone VARCHAR(32) NOT NULL, "
                        "status VARCHAR(160), "
                        "gender VARCHAR(16), "
                        "age_years INTEGER, "
                        "last_lat FLOAT, "
                        "last_lon FLOAT, "
                        "updated_at TIMESTAMP WITH TIME ZONE "
                        "DEFAULT CURRENT_TIMESTAMP"
                        ")"
                    )
                )
            else:
                conn.execute(
                    _sa_text(
                        "CREATE TABLE IF NOT EXISTS nearby_presence ("
                        "id SERIAL PRIMARY KEY, "
                        "user_phone VARCHAR(32) NOT NULL, "
                        "status VARCHAR(160), "
                        "gender VARCHAR(16), "
                        "age_years INTEGER, "
                        "last_lat DOUBLE PRECISION, "
                        "last_lon DOUBLE PRECISION, "
                        "updated_at TIMESTAMP WITH TIME ZONE "
                        "DEFAULT CURRENT_TIMESTAMP"
                        ")"
                    )
                )
    except Exception:
        logger.exception("failed to ensure nearby_presence table exists")


app.router.on_startup.append(_nearby_startup)


# ---- Stickers (online sticker marketplace, BFF-side) ----

STICKERS_DB_URL = _env_or(
    "STICKERS_DB_URL", _env_or("DB_URL", "sqlite+pysqlite:////tmp/stickers.db")
)
_STICKERS_DB_SCHEMA = os.getenv("DB_SCHEMA") if not STICKERS_DB_URL.startswith("sqlite") else None


class _StickersBase(_sa_DeclarativeBase):
    pass


class StickerPurchaseDB(_StickersBase):
    __tablename__ = "sticker_purchases"
    __table_args__ = (
        _sa_UniqueConstraint(
            "user_phone",
            "pack_id",
            name="uq_sticker_purchases_user_pack",
        ),
        {"schema": _STICKERS_DB_SCHEMA} if _STICKERS_DB_SCHEMA else {},
    )
    id: _sa_Mapped[int] = _sa_mapped_column(
        _sa_Integer, primary_key=True, autoincrement=True
    )
    user_phone: _sa_Mapped[str] = _sa_mapped_column(
        _sa_String(32), index=True
    )
    pack_id: _sa_Mapped[str] = _sa_mapped_column(
        _sa_String(64), index=True
    )
    amount_cents: _sa_Mapped[int] = _sa_mapped_column(
        _sa_Integer, default=0
    )
    currency: _sa_Mapped[str] = _sa_mapped_column(
        _sa_String(8), default=DEFAULT_CURRENCY
    )
    created_at: _sa_Mapped[datetime] = _sa_mapped_column(
        _sa_DateTime(timezone=True), server_default=_sa_func.now()
    )


_stickers_engine = _sa_create_engine(STICKERS_DB_URL, future=True)


def _stickers_session() -> _sa_Session:
    return _sa_Session(_stickers_engine)


def _stickers_startup() -> None:
    logger = logging.getLogger("shamell.stickers")
    try:
        _StickersBase.metadata.create_all(_stickers_engine)
    except Exception:
        logger.exception("failed to init stickers tables")


app.router.on_startup.append(_stickers_startup)


@app.get("/moments/feed", response_class=JSONResponse)
def moments_feed(
    request: Request,
    limit: int = 50,
    official_account_id: str | None = None,
    official_category: str | None = None,
    official_city: str | None = None,
    own_only: bool = False,
):
    """
    Returns latest Moments posts.
    Visibility rules: public + own \"only_me\" posts.

    When own_only is true, only posts authored by the current user are returned.
    """
    user_key = _moments_cookie_key(request)
    try:
        limit_val = max(1, min(limit, 100))
        account_ids_filter: set[str] | None = None
        if not official_account_id and (official_category or official_city):
            try:
                with _officials_session() as osess:
                    stmt = _sa_select(OfficialAccountDB.id).where(
                        OfficialAccountDB.enabled == True  # type: ignore[comparison-overlap]
                    )
                    if official_category:
                        stmt = stmt.where(OfficialAccountDB.category == official_category)
                    if official_city:
                        stmt = stmt.where(OfficialAccountDB.city == official_city)
                    rows = osess.execute(stmt).scalars().all()
                    account_ids_filter = {str(r) for r in rows}
            except Exception:
                account_ids_filter = set()
        with _moments_session() as s:
            stmt = _sa_select(MomentPostDB)
            if own_only:
                stmt = stmt.where(MomentPostDB.user_key == user_key)
            if official_account_id:
                stmt = stmt.where(
                    MomentPostDB.origin_official_account_id == official_account_id
                )
            elif account_ids_filter:
                stmt = stmt.where(
                    MomentPostDB.origin_official_account_id.in_(account_ids_filter)
                )
            stmt = stmt.order_by(
                MomentPostDB.created_at.desc(), MomentPostDB.id.desc()
            ).limit(limit_val)
            rows = s.execute(stmt).scalars().all()
            post_ids = [r.id for r in rows]
            likes_map: dict[int, int] = {}
            liked_by_me: set[int] = set()
            liked_by_map: dict[int, list[str]] = {}
            comments_map: dict[int, int] = {}
            official_reply_ids: set[int] = set()
            if post_ids:
                likes_rows = (
                    s.execute(
                        _sa_select(
                            MomentLikeDB.post_id, _sa_func.count(MomentLikeDB.id)
                        ).where(MomentLikeDB.post_id.in_(post_ids)
                        ).group_by(MomentLikeDB.post_id)
                    )
                    .all()
                )
                for pid, cnt in likes_rows:
                    likes_map[int(pid)] = int(cnt)
                like_user_rows = (
                    s.execute(
                        _sa_select(MomentLikeDB.post_id, MomentLikeDB.user_key)
                        .where(MomentLikeDB.post_id.in_(post_ids))
                        .order_by(MomentLikeDB.created_at.asc(), MomentLikeDB.id.asc())
                    )
                    .all()
                )
                for pid, uk in like_user_rows:
                    try:
                        pid_int = int(pid)
                    except Exception:
                        continue
                    lst = liked_by_map.get(pid_int)
                    if lst is None:
                        lst = []
                        liked_by_map[pid_int] = lst
                    if len(lst) >= 8:
                        continue
                    try:
                        label = _moments_pseudonym_for_user_key(str(uk))
                    except Exception:
                        label = None
                    if label:
                        lst.append(label)
                comments_rows = (
                    s.execute(
                        _sa_select(
                            MomentCommentDB.post_id,
                            _sa_func.count(MomentCommentDB.id),
                        )
                        .where(MomentCommentDB.post_id.in_(post_ids))
                        .group_by(MomentCommentDB.post_id)
                    )
                    .all()
                )
                for pid, cnt in comments_rows:
                    comments_map[int(pid)] = int(cnt)
                official_rows = (
                    s.execute(
                        _sa_select(MomentCommentDB.post_id)
                        .where(
                            MomentCommentDB.post_id.in_(post_ids),
                            MomentCommentDB.user_key.like("official:%"),
                        )
                        .group_by(MomentCommentDB.post_id)
                    )
                    .scalars()
                    .all()
                )
                official_reply_ids = {int(pid) for pid in official_rows}
                my_likes = (
                    s.execute(
                        _sa_select(MomentLikeDB.post_id).where(
                            MomentLikeDB.post_id.in_(post_ids),
                            MomentLikeDB.user_key == user_key,
                        )
                    )
                    .scalars()
                    .all()
                )
                liked_by_me.update(int(pid) for pid in my_likes)
            out: list[dict[str, Any]] = []
            for row in rows:
                vis = (row.visibility or "public").strip().lower()
                if vis in ("only_me", "private") and row.user_key != user_key:
                    continue
                if vis in (
                    "friends",
                    "friends_only",
                    "close_friends",
                    "friends_tag",
                    "friends_except_tag",
                ) and row.user_key != user_key:
                    viewer_phone: str | None
                    author_phone: str | None
                    try:
                        viewer_phone = _auth_phone(request) or None
                    except Exception:
                        viewer_phone = None
                    try:
                        author_phone = _phone_from_moments_user_key(row.user_key)
                    except Exception:
                        author_phone = None
                    if not viewer_phone or not author_phone:
                        # Hide friends-only posts when we cannot validate the graph.
                        continue
                    try:
                        with _friends_session() as fs:
                            rel = fs.execute(
                                _sa_select(FriendDB).where(
                                    FriendDB.user_phone == viewer_phone,
                                    FriendDB.friend_phone == author_phone,
                                )
                            ).scalars().first()
                            if rel is None:
                                continue
                            if vis in ("close_friends", "friends_only"):
                                rel_cf = fs.execute(
                                    _sa_select(CloseFriendDB).where(
                                        CloseFriendDB.user_phone
                                        == author_phone,
                                        CloseFriendDB.friend_phone
                                        == viewer_phone,
                                    )
                                ).scalars().first()
                                if rel_cf is None:
                                    continue
                            if vis == "friends_tag":
                                tag = (
                                    getattr(row, "audience_tag", None) or ""
                                ).strip()
                                if tag:
                                    rel_tag = fs.execute(
                                        _sa_select(FriendTagDB).where(
                                            FriendTagDB.user_phone
                                            == author_phone,
                                            FriendTagDB.friend_phone
                                            == viewer_phone,
                                            FriendTagDB.tag == tag,
                                        )
                                    ).scalars().first()
                                    if rel_tag is None:
                                        continue
                            elif vis == "friends_except_tag":
                                tag = (
                                    getattr(row, "audience_tag", None) or ""
                                ).strip()
                                if tag:
                                    rel_tag = fs.execute(
                                        _sa_select(FriendTagDB).where(
                                            FriendTagDB.user_phone
                                            == author_phone,
                                            FriendTagDB.friend_phone
                                            == viewer_phone,
                                            FriendTagDB.tag == tag,
                                        )
                                    ).scalars().first()
                                    # If the viewer has this tag, they are excluded.
                                    if rel_tag is not None:
                                        continue
                    except Exception:
                        continue
                try:
                    ts = row.created_at
                except Exception:
                    ts = None
                ts_str = (
                    ts.isoformat().replace("+00:00", "Z")
                    if isinstance(ts, datetime)
                    else datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
                )
                try:
                    author_label = _moments_pseudonym_for_user_key(row.user_key)
                except Exception:
                    author_label = None
                images: list[str] = []
                try:
                    raw_images = (getattr(row, "images_b64_json", None) or "").strip()
                    if raw_images:
                        decoded_images = json.loads(raw_images)
                        if isinstance(decoded_images, list):
                            for it in decoded_images:
                                try:
                                    s = (it or "").strip()
                                except Exception:
                                    s = ""
                                if not s:
                                    continue
                                images.append(s)
                                if len(images) >= 9:
                                    break
                except Exception:
                    images = []
                images_out = images if len(images) > 1 else None
                image_b64_out = row.image_b64 or (images[0] if images else None)
                out.append(
                    MomentPostOut(
                        id=str(row.id),
                        text=row.text,
                        ts=ts_str,
                        likes=likes_map.get(row.id, 0),
                        liked_by_me=row.id in liked_by_me,
                        liked_by=liked_by_map.get(row.id) or None,
                        comments=comments_map.get(row.id, 0),
                        has_official_reply=row.id in official_reply_ids,
                        visibility=row.visibility or "public",
                        image_b64=image_b64_out,
                        image_url=row.image_url,
                        author_name=author_label,
                        origin_official_account_id=getattr(
                            row, "origin_official_account_id", None
                        ),
                        origin_official_item_id=getattr(
                            row, "origin_official_item_id", None
                        ),
                        audience_tag=getattr(row, "audience_tag", None),
                        location_label=getattr(row, "location_label", None),
                        images=images_out,
                    ).dict()
                )
        try:
            emit_event(
                "moments",
                "feed_view",
                {"user_key": user_key, "count": len(out)},
            )
        except Exception:
            pass
        return {"items": out}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/moments/topic/{tag}", response_class=JSONResponse)
def moments_topic(
    request: Request,
    tag: str,
    limit: int = 50,
):
    """
    Returns latest Moments posts for a given hashtag/topic.

    Hashtags are stored without the leading '#', case-insensitive.
    """
    user_key = _moments_cookie_key(request)
    tag_norm = (tag or "").strip().lstrip("#").lower()
    if not tag_norm:
        return {"items": []}
    try:
        limit_val = max(1, min(limit, 100))
        with _moments_session() as s:
            stmt = (
                _sa_select(MomentPostDB)
                .join(MomentTagDB, MomentTagDB.post_id == MomentPostDB.id)
                .where(MomentTagDB.tag == tag_norm)
                .order_by(MomentPostDB.created_at.desc(), MomentPostDB.id.desc())
                .limit(limit_val)
            )
            rows = s.execute(stmt).scalars().all()
            post_ids = [r.id for r in rows]
            likes_map: dict[int, int] = {}
            liked_by_me: set[int] = set()
            liked_by_map: dict[int, list[str]] = {}
            comments_map: dict[int, int] = {}
            official_reply_ids: set[int] = set()
            if post_ids:
                likes_rows = (
                    s.execute(
                        _sa_select(
                            MomentLikeDB.post_id, _sa_func.count(MomentLikeDB.id)
                        )
                        .where(MomentLikeDB.post_id.in_(post_ids))
                        .group_by(MomentLikeDB.post_id)
                    )
                    .all()
                )
                for pid, cnt in likes_rows:
                    likes_map[int(pid)] = int(cnt)
                like_user_rows = (
                    s.execute(
                        _sa_select(MomentLikeDB.post_id, MomentLikeDB.user_key)
                        .where(MomentLikeDB.post_id.in_(post_ids))
                        .order_by(MomentLikeDB.created_at.asc(), MomentLikeDB.id.asc())
                    )
                    .all()
                )
                for pid, uk in like_user_rows:
                    try:
                        pid_int = int(pid)
                    except Exception:
                        continue
                    lst = liked_by_map.get(pid_int)
                    if lst is None:
                        lst = []
                        liked_by_map[pid_int] = lst
                    if len(lst) >= 8:
                        continue
                    try:
                        label = _moments_pseudonym_for_user_key(str(uk))
                    except Exception:
                        label = None
                    if label:
                        lst.append(label)
                comments_rows = (
                    s.execute(
                        _sa_select(
                            MomentCommentDB.post_id,
                            _sa_func.count(MomentCommentDB.id),
                        )
                        .where(MomentCommentDB.post_id.in_(post_ids))
                        .group_by(MomentCommentDB.post_id)
                    )
                    .all()
                )
                for pid, cnt in comments_rows:
                    comments_map[int(pid)] = int(cnt)
                official_rows = (
                    s.execute(
                        _sa_select(MomentCommentDB.post_id)
                        .where(
                            MomentCommentDB.post_id.in_(post_ids),
                            MomentCommentDB.user_key.like("official:%"),
                        )
                        .group_by(MomentCommentDB.post_id)
                    )
                    .scalars()
                    .all()
                )
                official_reply_ids = {int(pid) for pid in official_rows}
                my_likes = (
                    s.execute(
                        _sa_select(MomentLikeDB.post_id).where(
                            MomentLikeDB.post_id.in_(post_ids),
                            MomentLikeDB.user_key == user_key,
                        )
                    )
                    .scalars()
                    .all()
                )
                liked_by_me.update(int(pid) for pid in my_likes)
            out: list[dict[str, Any]] = []
            for row in rows:
                if row.visibility in ("only_me", "private") and row.user_key != user_key:
                    continue
                if row.visibility in ("friends", "friends_only", "close_friends") and row.user_key != user_key:
                    viewer_phone: str | None
                    author_phone: str | None
                    try:
                        viewer_phone = _auth_phone(request) or None
                    except Exception:
                        viewer_phone = None
                    try:
                        author_phone = _phone_from_moments_user_key(row.user_key)
                    except Exception:
                        author_phone = None
                    if not viewer_phone or not author_phone:
                        continue
                    try:
                        with _friends_session() as fs:
                            rel = fs.execute(
                                _sa_select(FriendDB).where(
                                    (
                                        (FriendDB.user_phone == author_phone)
                                        & (FriendDB.friend_phone == viewer_phone)
                                    )
                                    | (
                                        (FriendDB.user_phone == viewer_phone)
                                        & (FriendDB.friend_phone == author_phone)
                                    )
                                )
                            ).scalars().first()
                            if rel is None:
                                continue
                            if row.visibility in ("close_friends", "friends_only"):
                                rel_cf = fs.execute(
                                    _sa_select(CloseFriendDB).where(
                                        CloseFriendDB.user_phone
                                        == author_phone,
                                        CloseFriendDB.friend_phone
                                        == viewer_phone,
                                    )
                                ).scalars().first()
                                if rel_cf is None:
                                    continue
                    except Exception:
                        continue
                try:
                    ts = row.created_at
                except Exception:
                    ts = None
                ts_str = (
                    ts.isoformat().replace("+00:00", "Z")
                    if isinstance(ts, datetime)
                    else datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
                )
                try:
                    author_label = _moments_pseudonym_for_user_key(row.user_key)
                except Exception:
                    author_label = None
                images: list[str] = []
                try:
                    raw_images = (getattr(row, "images_b64_json", None) or "").strip()
                    if raw_images:
                        decoded_images = json.loads(raw_images)
                        if isinstance(decoded_images, list):
                            for it in decoded_images:
                                try:
                                    s = (it or "").strip()
                                except Exception:
                                    s = ""
                                if not s:
                                    continue
                                images.append(s)
                                if len(images) >= 9:
                                    break
                except Exception:
                    images = []
                images_out = images if len(images) > 1 else None
                image_b64_out = row.image_b64 or (images[0] if images else None)
                out.append(
                    MomentPostOut(
                        id=str(row.id),
                        text=row.text,
                        ts=ts_str,
                        likes=likes_map.get(row.id, 0),
                        liked_by_me=row.id in liked_by_me,
                        liked_by=liked_by_map.get(row.id) or None,
                        comments=comments_map.get(row.id, 0),
                        has_official_reply=row.id in official_reply_ids,
                        visibility=row.visibility or "public",
                        image_b64=image_b64_out,
                        image_url=row.image_url,
                        author_name=author_label,
                        origin_official_account_id=getattr(
                            row, "origin_official_account_id", None
                        ),
                        origin_official_item_id=getattr(
                            row, "origin_official_item_id", None
                        ),
                        audience_tag=getattr(row, "audience_tag", None),
                        location_label=getattr(row, "location_label", None),
                        images=images_out,
                    ).dict()
                )
        try:
            emit_event(
                "moments",
                "topic_view",
                {"user_key": user_key, "tag": tag_norm, "count": len(out)},
            )
        except Exception:
            pass
        return {"items": out}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


class MomentPostIn(BaseModel):
    text: str
    visibility: str = "public"
    image_b64: str | None = None
    images_b64: list[str] | None = None
    location_label: str | None = None


class MomentPostUpdateIn(BaseModel):
    visibility: str | None = None


class MomentCommentIn(BaseModel):
    text: str
    reply_to_id: int | None = None


class MomentReportIn(BaseModel):
    reason: str | None = None


@app.post("/moments", response_class=JSONResponse)
def moments_create(request: Request, body: MomentPostIn):
    """
    Creates a new moment for the current user.
    """
    user_key = _moments_cookie_key(request)
    text = (body.text or "").strip()
    images: list[str] = []
    seen_images: set[str] = set()
    for raw in body.images_b64 or []:
        try:
            s = (raw or "").strip()
        except Exception:
            s = ""
        if not s:
            continue
        if s in seen_images:
            continue
        seen_images.add(s)
        images.append(s)
        if len(images) >= 9:
            break
    if not images:
        single = (body.image_b64 or "").strip()
        if single:
            images.append(single)
    if not text and not images:
        raise HTTPException(status_code=400, detail="empty moment")
    visibility_raw = (body.visibility or "public").strip()
    visibility_norm = visibility_raw.lower()
    visibility = visibility_norm
    audience_tag: str | None = None
    if visibility_norm.startswith("tag:"):
        # Visibility restricted to friends with a specific tag label.
        visibility = "friends_tag"
        # Preserve the original label casing after the "tag:" prefix so it
        # matches the user's contact label (e.g. "Family", "Work").
        audience_tag = visibility_raw.split(":", 1)[1].strip() or None
    elif visibility_norm.startswith("friends_except:"):
        # Visibility: all friends except those with a specific tag.
        visibility = "friends_except_tag"
        audience_tag = visibility_raw.split(":", 1)[1].strip() or None
    if visibility not in {
        "public",
        "friends",
        "friends_only",
        "close_friends",
        "only_me",
        "private",
        "friends_tag",
        "friends_except_tag",
    }:
        visibility = "public"
        audience_tag = None
    origin_acc_id, origin_item_id = _moments_extract_official_origin(text)
    tags = _moments_extract_tags(text)
    location_label = (body.location_label or "").strip()
    if location_label:
        location_label = location_label[:128]
    images_json: str | None = None
    if len(images) > 1:
        try:
            images_json = json.dumps(images)
        except Exception:
            images_json = None
    image_b64 = images[0] if images else None
    try:
        with _moments_session() as s:
            row = MomentPostDB(
                user_key=user_key,
                text=text,
                visibility=visibility,
                audience_tag=audience_tag,
                location_label=location_label or None,
                images_b64_json=images_json,
                image_b64=image_b64,
                origin_official_account_id=origin_acc_id,
                origin_official_item_id=origin_item_id,
            )
            s.add(row)
            s.commit()
            s.refresh(row)
            if tags:
                for tag in tags:
                    try:
                        s.add(MomentTagDB(post_id=row.id, tag=tag))
                    except Exception:
                        # Best-effort; ignore duplicates or failures.
                        pass
                try:
                    s.commit()
                except Exception:
                    s.rollback()
            ts = row.created_at
            ts_str = (
                ts.isoformat().replace("+00:00", "Z")
                if isinstance(ts, datetime)
                else datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
            )
            try:
                author_label = _moments_pseudonym_for_user_key(row.user_key)
            except Exception:
                author_label = None
            out = MomentPostOut(
                id=str(row.id),
                text=row.text,
                ts=ts_str,
                likes=0,
                liked_by_me=False,
                has_official_reply=False,
                visibility=row.visibility or "public",
                image_b64=row.image_b64,
                image_url=row.image_url,
                author_name=author_label,
                audience_tag=row.audience_tag,
                location_label=getattr(row, "location_label", None),
                images=images if len(images) > 1 else None,
            ).dict()
        try:
            emit_event(
                "moments",
                "post_create",
                {"user_key": user_key},
            )
        except Exception:
            pass
        return out
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.patch("/moments/{post_id}", response_class=JSONResponse)
def moments_update(post_id: int, request: Request, body: MomentPostUpdateIn):
    """
    Updates selected fields of a Moments post (currently visibility/audience_tag)
    for the post owner.
    """
    user_key = _moments_cookie_key(request)
    try:
        with _moments_session() as s:
            post = s.get(MomentPostDB, post_id)
            if not post:
                raise HTTPException(status_code=404, detail="moment not found")
            if post.user_key != user_key:
                raise HTTPException(status_code=403, detail="forbidden")
            changed = False
            visibility_raw = (
                (body.visibility or "").strip()
                if body.visibility is not None
                else ""
            )
            if visibility_raw:
                visibility_norm = visibility_raw.lower()
                visibility = visibility_norm
                audience_tag: str | None = None
                if visibility_norm.startswith("tag:"):
                    visibility = "friends_tag"
                    audience_tag = visibility_raw.split(":", 1)[1].strip() or None
                elif visibility_norm.startswith("friends_except:"):
                    visibility = "friends_except_tag"
                    audience_tag = visibility_raw.split(":", 1)[1].strip() or None
                if visibility not in {
                    "public",
                    "friends",
                    "friends_only",
                    "close_friends",
                    "only_me",
                    "private",
                    "friends_tag",
                    "friends_except_tag",
                }:
                    visibility = "public"
                    audience_tag = None
                post.visibility = visibility
                setattr(post, "audience_tag", audience_tag)
                changed = True
            if changed:
                s.commit()
            return {
                "status": "ok",
                "visibility": getattr(post, "visibility", "public"),
                "audience_tag": getattr(post, "audience_tag", None),
            }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/moments/{post_id}/report", response_class=JSONResponse)
def moments_report(post_id: int, request: Request, body: MomentReportIn | None = None):
    """
    Lightweight report endpoint for Moments posts.
    Does not persist anything, but emits an analytics/moderation event
    that backoffice tooling can consume.
    """
    user_key = _moments_cookie_key(request)
    reason = ""
    try:
        if body is not None:
            reason = (body.reason or "").strip()
        with _moments_session() as s:
            post = s.get(MomentPostDB, post_id)
            if not post:
                raise HTTPException(status_code=404, detail="moment not found")
        try:
            emit_event(
                "moments",
                "post_report",
                {
                    "user_key": user_key,
                    "post_id": post_id,
                    "reason": reason[:280] if reason else "",
                },
            )
        except Exception:
            # Reporting should never break the client.
            pass
        return {"status": "ok"}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/moments/{post_id}/like", response_class=JSONResponse)
def moments_like(post_id: int, request: Request):
    """
    Idempotent like endpoint; increments like count once per user.
    """
    user_key = _moments_cookie_key(request)
    try:
        send_push = False
        post_author_phone: str | None = None
        with _moments_session() as s:
            post = s.get(MomentPostDB, post_id)
            if not post:
                raise HTTPException(status_code=404, detail="moment not found")
            existing = (
                s.execute(
                    _sa_select(MomentLikeDB).where(
                        MomentLikeDB.post_id == post_id,
                        MomentLikeDB.user_key == user_key,
                    )
                )
                .scalars()
                .first()
            )
            if existing is None:
                like = MomentLikeDB(post_id=post_id, user_key=user_key)
                s.add(like)
                s.commit()
                send_push = True
            try:
                post_author_phone = _phone_from_moments_user_key(post.user_key)
            except Exception:
                post_author_phone = None
        try:
            emit_event(
                "moments",
                "post_like",
                {"user_key": user_key, "post_id": post_id},
            )
        except Exception:
            pass
        # Fire-and-forget push notification to post author (if different user)
        if send_push and post_author_phone:
            try:
                liker_phone = _auth_phone(request) or ""
            except Exception:
                liker_phone = ""
            if liker_phone != post_author_phone:
                try:
                    loop = asyncio.get_event_loop()
                    if loop.is_running():
                        loop.create_task(
                            _send_driver_push(
                                post_author_phone,
                                "New like on your Moment",
                                f"Your post #{post_id} received a new like.",
                                {"type": "moments_post_like", "post_id": post_id},
                            )
                        )
                except Exception:
                    pass
        return {"status": "ok"}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.delete("/moments/{post_id}/like", response_class=JSONResponse)
def moments_unlike(post_id: int, request: Request):
    """
    Idempotent unlike endpoint; removes the user's like when present.
    """
    user_key = _moments_cookie_key(request)
    try:
        with _moments_session() as s:
            post = s.get(MomentPostDB, post_id)
            if not post:
                raise HTTPException(status_code=404, detail="moment not found")
            existing = (
                s.execute(
                    _sa_select(MomentLikeDB).where(
                        MomentLikeDB.post_id == post_id,
                        MomentLikeDB.user_key == user_key,
                    )
                )
                .scalars()
                .first()
            )
            if existing is not None:
                s.delete(existing)
                s.commit()
        try:
            emit_event(
                "moments",
                "post_unlike",
                {"user_key": user_key, "post_id": post_id},
            )
        except Exception:
            pass
        return {"status": "ok"}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/moments/notifications", response_class=JSONResponse)
def moments_notifications(request: Request) -> dict[str, Any]:
    """
    Aggregated notification info for Moments:
    latest comment timestamp on the user's posts (excluding own comments)
    and total comment count.
    """
    user_key = _moments_cookie_key(request)
    try:
        with _moments_session() as s:
            post_ids = (
                s.execute(
                    _sa_select(MomentPostDB.id).where(
                        MomentPostDB.user_key == user_key
                    )
                )
                .scalars()
                .all()
            )
            if not post_ids:
                return MomentNotificationsOut(
                    last_comment_ts=None, total_comments=0, redpacket_posts_30d=0
                ).dict()

            row = (
                s.execute(
                    _sa_select(
                        _sa_func.count(MomentCommentDB.id),
                        _sa_func.max(MomentCommentDB.created_at),
                    ).where(
                        MomentCommentDB.post_id.in_(post_ids),
                        MomentCommentDB.user_key != user_key,
                    )
                )
                .first()
            )
            cnt = 0
            last_dt: Any = None
            if row:
                cnt, last_dt = row
            total = int(cnt or 0)

            # Red-packet mentions on my Moments in the last 30 days
            redpacket_30d = 0
            try:
                since = datetime.now(timezone.utc) - timedelta(days=30)
                rp_stmt = _sa_select(_sa_func.count(MomentPostDB.id)).where(
                    MomentPostDB.user_key == user_key,
                    MomentPostDB.created_at >= since,
                    (
                        MomentPostDB.text.contains("Red packet")
                        | MomentPostDB.text.contains(
                            "I am sending red packets via Shamell Pay"
                        )
                        | MomentPostDB.text.contains("حزمة حمراء")
                    ),
                )
                rp_count = s.execute(rp_stmt).scalar() or 0
                redpacket_30d = int(rp_count)
            except Exception:
                redpacket_30d = 0

            if not last_dt:
                return MomentNotificationsOut(
                    last_comment_ts=None,
                    total_comments=total,
                    redpacket_posts_30d=redpacket_30d,
                ).dict()
            ts_str = (
                last_dt.isoformat().replace("+00:00", "Z")
                if isinstance(last_dt, datetime)
                else datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
            )
            return MomentNotificationsOut(
                last_comment_ts=ts_str,
                total_comments=total,
                redpacket_posts_30d=redpacket_30d,
            ).dict()
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/me/official_moments_stats", response_class=JSONResponse)
def me_official_moments_stats(request: Request) -> dict[str, Any]:
    """
    Aggregated Moments share counts per Official kind for the current user.

    Counts how many Moments the user has posted that originate from
    service vs. subscription Official accounts (based on origin_official_account_id).
    """
    user_key = _moments_cookie_key(request)
    try:
        # Collect per-account share counts for this user's Moments.
        per_account: dict[str, int] = {}
        per_account_30d: dict[str, int] = {}
        with _moments_session() as ms:
            since_30 = datetime.now(timezone.utc) - timedelta(days=30)
            rows = (
                ms.execute(
                    _sa_select(
                        MomentPostDB.origin_official_account_id,
                        _sa_func.count(MomentPostDB.id),
                    )
                    .where(
                        MomentPostDB.user_key == user_key,
                        MomentPostDB.origin_official_account_id.is_not(None),
                    )
                    .group_by(MomentPostDB.origin_official_account_id)
                )
                .all()
            )
            for acc_id, cnt in rows:
                if not acc_id:
                    continue
                per_account[str(acc_id)] = int(cnt or 0)
            # Last 30 days counts per official for this user.
            try:
                rows_30 = (
                    ms.execute(
                        _sa_select(
                            MomentPostDB.origin_official_account_id,
                            _sa_func.count(MomentPostDB.id),
                        )
                        .where(
                            MomentPostDB.user_key == user_key,
                            MomentPostDB.origin_official_account_id.is_not(
                                None
                            ),
                            MomentPostDB.created_at >= since_30,
                        )
                        .group_by(MomentPostDB.origin_official_account_id)
                    )
                    .all()
                )
                for acc_id, cnt in rows_30:
                    if not acc_id:
                        continue
                    per_account_30d[str(acc_id)] = int(cnt or 0)
            except Exception:
                per_account_30d = {}
        if not per_account:
            return OfficialMomentsStatsOut(
                service_shares=0,
                subscription_shares=0,
                total_shares=0,
                redpacket_shares_30d=0,
                hot_accounts=0,
            ).dict()

        # Look up Official kind per account_id.
        service_shares = 0
        subscription_shares = 0
        hot_accounts = 0
        acc_ids = list(per_account.keys())
        try:
            with _officials_session() as os:
                acc_rows = (
                    os.execute(
                        _sa_select(
                            OfficialAccountDB.id,
                            OfficialAccountDB.kind,
                        ).where(OfficialAccountDB.id.in_(acc_ids))
                    )
                    .all()
                )
                kinds: dict[str, str] = {}
                for acc_id, kind in acc_rows:
                    kinds[str(acc_id)] = (kind or "service").strip().lower()
        except Exception:
            kinds = {}

        for acc_id, cnt in per_account.items():
            kind = kinds.get(acc_id, "service")
            if kind == "service":
                service_shares += cnt
            else:
                subscription_shares += cnt
            try:
                recent_cnt = int(per_account_30d.get(acc_id, 0) or 0)
                # Hot if either strong all-time or active in last 30 days.
                if int(cnt) >= 10 or recent_cnt >= 3:
                    hot_accounts += 1
            except Exception:
                continue

        total_shares = int(service_shares + subscription_shares)

        # Red-packet Moments by this user in the last 30 days (with official origin)
        redpacket_30d = 0
        try:
            since = datetime.now(timezone.utc) - timedelta(days=30)
            rp_rows = (
                ms.execute(  # type: ignore[name-defined]
                    _sa_select(_sa_func.count(MomentPostDB.id)).where(
                        MomentPostDB.user_key == user_key,
                        MomentPostDB.origin_official_account_id.is_not(None),
                        MomentPostDB.created_at >= since,
                        (
                            MomentPostDB.text.contains("Red packet")
                            | MomentPostDB.text.contains(
                                "I am sending red packets via Shamell Pay"
                            )
                            | MomentPostDB.text.contains("حزمة حمراء")
                        ),
                    )
                )
                .scalar()
                or 0
            )
            redpacket_30d = int(rp_rows)
        except Exception:
            redpacket_30d = 0

        return OfficialMomentsStatsOut(
            service_shares=service_shares,
            subscription_shares=subscription_shares,
            total_shares=total_shares,
            redpacket_shares_30d=redpacket_30d,
            hot_accounts=hot_accounts,
        ).dict()
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/moments/{post_id}/comments", response_class=JSONResponse)
def moments_comments(post_id: int, request: Request, limit: int = 100):
    """
    Returns comments for a given moment post.
    """
    user_key = _moments_cookie_key(request)
    try:
        limit_val = max(1, min(limit, 200))
        with _moments_session() as s:
            post = s.get(MomentPostDB, post_id)
            if not post:
                raise HTTPException(status_code=404, detail="moment not found")
            stmt = (
                _sa_select(MomentCommentDB)
                .where(MomentCommentDB.post_id == post_id)
                .order_by(
                    MomentCommentDB.created_at.asc(), MomentCommentDB.id.asc()
                )
                .limit(limit_val)
            )
            rows = s.execute(stmt).scalars().all()
            comment_ids = [r.id for r in rows]
            # Build stable but privacy-friendly labels from user_key
            label_map: dict[str, str] = {}
            likes_map: dict[int, int] = {}
            liked_set: set[int] = set()
            if comment_ids:
                likes_rows = (
                    s.execute(
                        _sa_select(
                            MomentCommentLikeDB.comment_id,
                            _sa_func.count(MomentCommentLikeDB.id),
                        )
                        .where(MomentCommentLikeDB.comment_id.in_(comment_ids))
                        .group_by(MomentCommentLikeDB.comment_id)
                    )
                    .all()
                )
                for cid, cnt in likes_rows:
                    likes_map[int(cid)] = int(cnt or 0)
                liked_rows = (
                    s.execute(
                        _sa_select(MomentCommentLikeDB.comment_id).where(
                            MomentCommentLikeDB.comment_id.in_(comment_ids),
                            MomentCommentLikeDB.user_key == user_key,
                        )
                    )
                    .scalars()
                    .all()
                )
                liked_set.update(int(cid) for cid in liked_rows)
            items: list[dict[str, Any]] = []
            for row in rows:
                ts = row.created_at
                ts_str = (
                    ts.isoformat().replace("+00:00", "Z")
                    if isinstance(ts, datetime)
                    else datetime.now(timezone.utc)
                    .isoformat()
                    .replace("+00:00", "Z")
                )
                author = None
                try:
                    uk = (row.user_key or "").strip()
                    if uk:
                        if uk.startswith("official:"):
                            author = f"Official · {uk.split(':', 1)[1]}"
                        elif uk in label_map:
                            author = label_map[uk]
                        else:
                            import hashlib

                            h = hashlib.sha256(uk.encode("utf-8")).hexdigest()[:6]
                            author = f"User {h}"
                            label_map[uk] = author
                except Exception:
                    author = None
                items.append(
                    MomentCommentOut(
                        id=str(row.id),
                        text=row.text,
                        ts=ts_str,
                        author_name=author,
                        reply_to_id=str(row.reply_to_id)
                        if getattr(row, "reply_to_id", None)
                        else None,
                        reply_to_name=None,
                        likes=likes_map.get(row.id, 0),
                        liked_by_me=row.id in liked_set,
                    ).dict()
                )
        return {"items": items}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/moments/{post_id}/comments", response_class=JSONResponse)
def moments_add_comment(post_id: int, request: Request, body: MomentCommentIn):
    """
    Adds a new comment to a moment post.
    """
    user_key = _moments_cookie_key(request)
    text = (body.text or "").strip()
    if not text:
        raise HTTPException(status_code=400, detail="empty comment")
    reply_to_id = body.reply_to_id
    try:
        post_author_phone: str | None = None
        commenter_phone: str | None = None
        with _moments_session() as s:
            post = s.get(MomentPostDB, post_id)
            if not post:
                raise HTTPException(status_code=404, detail="moment not found")
            if reply_to_id is not None:
                target = s.get(MomentCommentDB, reply_to_id)
                if not target or target.post_id != post_id:
                    reply_to_id = None
            row = MomentCommentDB(
                post_id=post_id,
                user_key=user_key,
                text=text,
                reply_to_id=reply_to_id,
            )
            s.add(row)
            s.commit()
            s.refresh(row)
            ts = row.created_at
            ts_str = (
                ts.isoformat().replace("+00:00", "Z")
                if isinstance(ts, datetime)
                else datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
            )
            author = None
            try:
                uk = (row.user_key or "").strip()
                if uk:
                    import hashlib

                    h = hashlib.sha256(uk.encode("utf-8")).hexdigest()[:6]
                    author = f"User {h}"
            except Exception:
                author = None
            out = MomentCommentOut(
                id=str(row.id),
                text=row.text,
                ts=ts_str,
                author_name=author,
                reply_to_id=str(row.reply_to_id)
                if getattr(row, "reply_to_id", None)
                else None,
                reply_to_name=None,
            ).dict()
            try:
                post_author_phone = _phone_from_moments_user_key(post.user_key)
            except Exception:
                post_author_phone = None
        try:
            commenter_phone = _auth_phone(request) or None
        except Exception:
            commenter_phone = None
        try:
            emit_event(
                "moments",
                "comment_create",
                {"user_key": user_key, "post_id": post_id},
            )
        except Exception:
            pass
        # Fire-and-forget push notification to post author (if different user)
        if post_author_phone and commenter_phone != post_author_phone:
            try:
                loop = asyncio.get_event_loop()
                if loop.is_running():
                    loop.create_task(
                        _send_driver_push(
                            post_author_phone,
                            "New comment on your Moment",
                            text[:120],
                            {
                                "type": "moments_comment",
                                "post_id": post_id,
                                "comment_id": row.id,
                            },
                        )
                    )
            except Exception:
                pass
        return out
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/moments/admin", response_class=JSONResponse)
def moments_admin_list(
    request: Request,
    limit: int = 100,
    redpacket_only: bool = False,
    origin_official_account_id: str | None = None,
    origin_official_item_id: str | None = None,
    campaign_id: str | None = None,
) -> dict[str, Any]:
    """
    Simple debug listing for Moments posts (QA only).
    Shows latest posts with basic metadata and like counts.
    """
    _require_admin_v2(request)
    try:
        limit_val = max(1, min(limit, 200))
        with _moments_session() as s:
            stmt = _sa_select(MomentPostDB)
            if redpacket_only:
                stmt = stmt.where(
                    MomentPostDB.text.contains("Red packet")
                    | MomentPostDB.text.contains(
                        "I am sending red packets via Shamell Pay"
                    )
                    | MomentPostDB.text.contains("حزمة حمراء")
                )
            if origin_official_account_id:
                stmt = stmt.where(
                    MomentPostDB.origin_official_account_id
                    == origin_official_account_id
                )
            target_item = origin_official_item_id or campaign_id
            if target_item:
                stmt = stmt.where(
                    MomentPostDB.origin_official_item_id == target_item
                )
            stmt = stmt.order_by(
                MomentPostDB.created_at.desc(), MomentPostDB.id.desc()
            ).limit(limit_val)
            rows = s.execute(stmt).scalars().all()
            post_ids = [r.id for r in rows]
            likes_map: dict[int, int] = {}
            comments_map: dict[int, int] = {}
            if post_ids:
                likes_rows = (
                    s.execute(
                        _sa_select(
                            MomentLikeDB.post_id, _sa_func.count(MomentLikeDB.id)
                        ).where(MomentLikeDB.post_id.in_(post_ids)
                        ).group_by(MomentLikeDB.post_id)
                    )
                    .all()
                )
                for pid, cnt in likes_rows:
                    likes_map[int(pid)] = int(cnt)
                comments_rows = (
                    s.execute(
                        _sa_select(
                            MomentCommentDB.post_id, _sa_func.count(MomentCommentDB.id)
                        ).where(MomentCommentDB.post_id.in_(post_ids)
                        ).group_by(MomentCommentDB.post_id)
                    )
                    .all()
                )
                for pid, cnt in comments_rows:
                    comments_map[int(pid)] = int(cnt)
            items: list[dict[str, Any]] = []
            for row in rows:
                ts = row.created_at
                ts_str = (
                    ts.isoformat().replace("+00:00", "Z")
                    if isinstance(ts, datetime)
                    else datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
                )
                items.append(
                    {
                        "id": row.id,
                        "user_key": row.user_key,
                        "text": row.text,
                        "visibility": row.visibility,
                        "created_at": ts_str,
                        "likes": likes_map.get(row.id, 0),
                        "has_image": bool(row.image_b64 or row.image_url),
                        "origin_official_account_id": getattr(
                            row, "origin_official_account_id", None
                        ),
                        "origin_official_item_id": getattr(
                            row, "origin_official_item_id", None
                        ),
                    }
                )
        return {"items": items}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/moments/topics/trending", response_class=JSONResponse)
def moments_trending_topics(request: Request, limit: int = 10) -> dict[str, Any]:
    """
    Returns simple trending hashtags for Moments.

    Currently ranks by total occurrences across all posts (best-effort).
    """
    user_key = _moments_cookie_key(request)
    try:
        limit_val = max(1, min(limit, 50))
        with _moments_session() as s:
            rows = (
                s.execute(
                    _sa_select(MomentTagDB.tag, _sa_func.count(MomentTagDB.id))
                    .group_by(MomentTagDB.tag)
                    .order_by(_sa_func.count(MomentTagDB.id).desc())
                    .limit(limit_val)
                )
                .all()
            )
        items: list[dict[str, Any]] = []
        for tag, cnt in rows:
            items.append(
                {
                    "tag": str(tag or ""),
                    "count": int(cnt or 0),
                }
            )
        try:
            emit_event(
                "moments",
                "trending_topics_view",
                {"user_key": user_key, "count": len(items)},
            )
        except Exception:
            pass
        return {"items": items}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/moments/admin/comments", response_class=JSONResponse)
def moments_admin_comments(
    request: Request,
    post_id: int | None = None,
    limit: int = 100,
    official_account_id: str | None = None,
) -> dict[str, Any]:
    """
    Admin JSON view for comments, optionally filtered by post_id.
    """
    _require_admin_v2(request)
    try:
        limit_val = max(1, min(limit, 500))
        with _moments_session() as s:
            stmt = (
                _sa_select(MomentCommentDB)
                .order_by(
                    MomentCommentDB.created_at.desc(),
                    MomentCommentDB.id.desc(),
                )
                .limit(limit_val)
            )
            if official_account_id:
                stmt = (
                    stmt.join(
                        MomentPostDB,
                        MomentCommentDB.post_id == MomentPostDB.id,
                    ).where(
                        MomentPostDB.origin_official_account_id
                        == official_account_id
                    )
                )
            if post_id is not None:
                stmt = stmt.where(MomentCommentDB.post_id == post_id)
            rows = s.execute(stmt).scalars().all()
            items: list[dict[str, Any]] = []
            for row in rows:
                ts = row.created_at
                ts_str = (
                    ts.isoformat().replace("+00:00", "Z")
                    if isinstance(ts, datetime)
                    else datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
                )
                items.append(
                    {
                        "id": row.id,
                        "post_id": row.post_id,
                        "user_key": row.user_key,
                        "text": row.text,
                        "created_at": ts_str,
                        "reply_to_id": row.reply_to_id,
                    }
                )
        return {"items": items}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.delete("/moments/admin/comments/{comment_id}", response_class=JSONResponse)
def moments_admin_delete_comment(comment_id: int, request: Request) -> dict[str, Any]:
    """
    Deletes a single comment (admin only).
    """
    _require_admin_v2(request)
    try:
        with _moments_session() as s:
            row = s.get(MomentCommentDB, comment_id)
            if not row:
                raise HTTPException(status_code=404, detail="comment not found")
            s.delete(row)
            s.commit()
        return {"status": "ok"}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.delete("/moments/comments/{comment_id}", response_class=JSONResponse)
def moments_delete_comment(comment_id: int, request: Request) -> dict[str, Any]:
    """
    Deletes a comment if it belongs to the current user (or admin).
    """
    user_key = _moments_cookie_key(request)
    try:
        with _moments_session() as s:
            row = s.get(MomentCommentDB, comment_id)
            if not row:
                raise HTTPException(status_code=404, detail="comment not found")
            is_admin = False
            try:
                _require_admin_v2(request)
                is_admin = True
            except Exception:
                is_admin = False
            if not is_admin and (row.user_key or "") != user_key:
                raise HTTPException(status_code=403, detail="forbidden")

            likes = (
                s.execute(
                    _sa_select(MomentCommentLikeDB).where(
                        MomentCommentLikeDB.comment_id == comment_id
                    )
                )
                .scalars()
                .all()
            )
            for like_row in likes:
                s.delete(like_row)
            s.delete(row)
            s.commit()
        return {"status": "ok"}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


class MomentAdminReplyIn(BaseModel):
    text: str
    official_account_id: str
    reply_to_id: int | None = None


@app.post("/moments/comments/{comment_id}/like", response_class=JSONResponse)
def moments_comment_like(comment_id: int, request: Request) -> dict[str, Any]:
    """
    Idempotent like endpoint for Moments comments.
    """
    user_key = _moments_cookie_key(request)
    try:
        send_push = False
        comment_author_phone: str | None = None
        post_id: int | None = None
        with _moments_session() as s:
            comment = s.get(MomentCommentDB, comment_id)
            if not comment:
                raise HTTPException(status_code=404, detail="comment not found")
            post_id = int(comment.post_id)
            existing = (
                s.execute(
                    _sa_select(MomentCommentLikeDB).where(
                        MomentCommentLikeDB.comment_id == comment_id,
                        MomentCommentLikeDB.user_key == user_key,
                    )
                )
                .scalars()
                .first()
            )
            if existing is None:
                row = MomentCommentLikeDB(comment_id=comment_id, user_key=user_key)
                s.add(row)
                s.commit()
                send_push = True
            likes = (
                s.execute(
                    _sa_select(_sa_func.count(MomentCommentLikeDB.id)).where(
                        MomentCommentLikeDB.comment_id == comment_id
                    )
                )
                .scalar()
                or 0
            )
            try:
                comment_author_phone = _phone_from_moments_user_key(comment.user_key)
            except Exception:
                comment_author_phone = None
        try:
            emit_event(
                "moments",
                "comment_like",
                {
                    "user_key": user_key,
                    "comment_id": comment_id,
                    "post_id": post_id,
                },
            )
        except Exception:
            pass
        # Fire-and-forget push notification to comment author (if different user)
        if send_push and comment_author_phone:
            try:
                liker_phone = _auth_phone(request) or ""
            except Exception:
                liker_phone = ""
            if liker_phone != comment_author_phone:
                try:
                    loop = asyncio.get_event_loop()
                    if loop.is_running():
                        loop.create_task(
                            _send_driver_push(
                                comment_author_phone,
                                "New like on your comment",
                                f"Your comment on post #{post_id} received a new like.",
                                {
                                    "type": "moments_comment_like",
                                    "comment_id": comment_id,
                                    "post_id": post_id,
                                },
                            )
                        )
                except Exception:
                    pass
        return {"likes": int(likes), "liked_by_me": True}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/me/friends", response_class=JSONResponse)
def me_friends(request: Request) -> dict[str, Any]:
    """
    Returns the current user's friends (simple phone-based graph).
    """
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    try:
        with _friends_session() as s:
            rows = (
                s.execute(
                    _sa_select(FriendDB).where(FriendDB.user_phone == phone)
                )
                .scalars()
                .all()
            )
            # Preload close-friend flags for this user for convenience.
            cf_rows = (
                s.execute(
                    _sa_select(CloseFriendDB.friend_phone).where(
                        CloseFriendDB.user_phone == phone
                    )
                )
                .scalars()
                .all()
            )
            cf_set = {r for r in cf_rows}
            # Preload tags per friend for this user.
            tag_rows = (
                s.execute(
                    _sa_select(
                        FriendTagDB.friend_phone, FriendTagDB.tag
                    ).where(FriendTagDB.user_phone == phone)
                )
                .all()
            )
            tags_map: dict[str, list[str]] = {}
            for fp, tag in tag_rows:
                try:
                    f = (fp or "").strip()
                    t = (tag or "").strip()
                except Exception:
                    continue
                if not f or not t:
                    continue
                tags_map.setdefault(f, []).append(t)
            friends: list[dict[str, Any]] = []
            for row in rows:
                fp = row.friend_phone
                friends.append(
                    {
                        "id": fp,
                        "phone": fp,
                        "close": fp in cf_set,
                        "tags": tags_map.get(fp, []),
                    }
                )
        return {"friends": friends}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/me/contacts/sync", response_class=JSONResponse)
async def me_contacts_sync(req: Request) -> dict[str, Any]:
    """
    Best‑effort Contact‑Sync:

    - Client sends a list of phone numbers from the address book.
    - Server returns a list of phones that also use Shamell so the
      client can show \"People you may know\" / add suggestions.
    """
    phone = _auth_phone(req)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    try:
        body = await req.json()
    except Exception:
        body = None
    numbers = []
    if isinstance(body, dict):
        raw = body.get("phones") or []
        if isinstance(raw, list):
            for v in raw:
                try:
                    s = (v or "").strip()
                except Exception:
                    s = ""
                if not s:
                    continue
                # Normalize very lightly: remove spaces; keep leading + if present.
                s = s.replace(" ", "")
                if not s:
                    continue
                # Do not include own phone
                if s == phone:
                    continue
                numbers.append(s)
    if not numbers:
        return {"matches": []}
    try:
        # Use Payments user directory as a proxy for \"is Shamell user\".
        # Prefer internal Payments integration when available.
        matches: list[dict[str, Any]] = []
        uniq = sorted({n for n in numbers})
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            try:
                from apps.payments.app.main import User as _PayUser  # type: ignore[import]
            except Exception:
                _PayUser = None  # type: ignore[assignment]
            if _PayUser is None:
                return {"matches": []}
            with _pay_internal_session() as s:  # type: ignore[name-defined]
                rows = (
                    s.execute(
                        _sa_select(_PayUser).where(_PayUser.phone.in_(uniq))  # type: ignore[arg-type]
                    )
                    .scalars()
                    .all()
                )
                for u in rows:
                    try:
                        p = getattr(u, "phone", None)
                        if not p:
                            continue
                        matches.append(
                            {
                                "phone": p,
                                "name": getattr(u, "full_name", "") or "",
                            }
                        )
                    except Exception:
                        continue
        elif PAYMENTS_BASE:
            base = PAYMENTS_BASE.rstrip("/")
            for chunk_start in range(0, len(uniq), 50):
                chunk = uniq[chunk_start : chunk_start + 50]
                try:
                    url = f"{base}/admin/users/lookup"
                    r = httpx.post(
                        url,
                        json={"phones": chunk},
                        headers=_payments_headers(),
                        timeout=6.0,
                    )
                    if r.status_code >= 200 and r.status_code < 300:
                        decoded = r.json()
                        arr = decoded.get("users") if isinstance(decoded, dict) else None
                        if isinstance(arr, list):
                            for u in arr:
                                if not isinstance(u, dict):
                                    continue
                                p = (u.get("phone") or "").strip()
                                if not p:
                                    continue
                                matches.append(
                                    {
                                        "phone": p,
                                        "name": (u.get("full_name") or "").strip(),
                                    }
                                )
                except Exception:
                    continue
        return {"matches": matches}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/me/friend_requests", response_class=JSONResponse)
def me_friend_requests(request: Request) -> dict[str, Any]:
    """
    Returns incoming and outgoing friend requests for the current user.
    """
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    try:
        with _friends_session() as s:
            incoming_rows = (
                s.execute(
                    _sa_select(FriendRequestDB).where(
                        FriendRequestDB.to_phone == phone,
                        FriendRequestDB.status == "pending",
                    )
                )
                .scalars()
                .all()
            )
            outgoing_rows = (
                s.execute(
                    _sa_select(FriendRequestDB).where(
                        FriendRequestDB.from_phone == phone,
                        FriendRequestDB.status == "pending",
                    )
                )
                .scalars()
                .all()
            )
            incoming: list[dict[str, Any]] = []
            outgoing: list[dict[str, Any]] = []
            for r in incoming_rows:
                incoming.append(
                    {
                        "id": r.id,
                        "request_id": r.id,
                        "from": r.from_phone,
                        "to": r.to_phone,
                        "status": r.status,
                    }
                )
            for r in outgoing_rows:
                outgoing.append(
                    {
                        "id": r.id,
                        "request_id": r.id,
                        "from": r.from_phone,
                        "to": r.to_phone,
                        "status": r.status,
                    }
                )
        return {"incoming": incoming, "outgoing": outgoing}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


class FriendRequestIn(BaseModel):
    target_id: str


@app.post("/friends/request", response_class=JSONResponse)
async def friends_request(req: Request, body: FriendRequestIn) -> dict[str, Any]:
    """
    Creates a friend request from the current user to target_id (phone).
    """
    phone = _auth_phone(req)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    target = (body.target_id or "").strip()
    if not target:
        raise HTTPException(status_code=400, detail="target_id required")
    if target == phone:
        raise HTTPException(status_code=400, detail="cannot add yourself")
    try:
        with _friends_session() as s:
            # Already friends?
            existing_friend = s.execute(
                _sa_select(FriendDB).where(
                    FriendDB.user_phone == phone,
                    FriendDB.friend_phone == target,
                )
            ).scalars().first()
            if existing_friend:
                return {"status": "already_friends"}
            # Existing pending request?
            existing_req = s.execute(
                _sa_select(FriendRequestDB).where(
                    FriendRequestDB.from_phone == phone,
                    FriendRequestDB.to_phone == target,
                    FriendRequestDB.status == "pending",
                )
            ).scalars().first()
            if existing_req:
                return {
                    "status": "pending",
                    "request_id": existing_req.id,
                }
            row = FriendRequestDB(
                from_phone=phone,
                to_phone=target,
                status="pending",
            )
            s.add(row)
            s.commit()
            s.refresh(row)
            return {
                "status": "ok",
                "request_id": row.id,
                "from": row.from_phone,
                "to": row.to_phone,
            }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


class FriendAcceptIn(BaseModel):
    request_id: int


@app.post("/friends/accept", response_class=JSONResponse)
async def friends_accept(req: Request, body: FriendAcceptIn) -> dict[str, Any]:
    """
    Accepts a pending friend request and establishes a bidirectional friend relation.
    """
    phone = _auth_phone(req)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    rid = body.request_id
    try:
        with _friends_session() as s:
            r = s.get(FriendRequestDB, rid)
            if not r or r.to_phone != phone or r.status != "pending":
                raise HTTPException(status_code=404, detail="request not found")
            r.status = "accepted"
            # Create symmetric friend rows
            def _ensure_friend(a: str, b: str) -> None:
                existing = s.execute(
                    _sa_select(FriendDB).where(
                        FriendDB.user_phone == a,
                        FriendDB.friend_phone == b,
                    )
                ).scalars().first()
                if not existing:
                    s.add(FriendDB(user_phone=a, friend_phone=b))

            _ensure_friend(r.from_phone, r.to_phone)
            _ensure_friend(r.to_phone, r.from_phone)
            s.add(r)
            s.commit()
        return {"status": "ok"}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


class FriendTagsIn(BaseModel):
    tags: list[str]


@app.post("/me/friends/{friend_phone}/tags", response_class=JSONResponse)
async def me_friend_tags_set(friend_phone: str, request: Request, body: FriendTagsIn) -> dict[str, Any]:
    """
    Sets the label/tags for a friend (per user).

    This replaces any existing tags between (user_phone, friend_phone)
    and is used for WeChat‑style contact labels like \"Family\" or \"Work\".
    """
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    target = (friend_phone or "").strip()
    if not target:
        raise HTTPException(status_code=400, detail="friend_phone required")
    # Normalise tags: trim, deduplicate, drop empty.
    tags_norm: list[str] = []
    seen: set[str] = set()
    for t in body.tags:
        try:
            v = (t or "").strip()
        except Exception:
            v = ""
        if not v:
            continue
        key = v.lower()
        if key in seen:
            continue
        seen.add(key)
        tags_norm.append(v)
    try:
        with _friends_session() as s:
            # Ensure the relation exists before tagging.
            rel = (
                s.execute(
                    _sa_select(FriendDB).where(
                        FriendDB.user_phone == phone,
                        FriendDB.friend_phone == target,
                    )
                )
                .scalars()
                .first()
            )
            if rel is None:
                raise HTTPException(status_code=404, detail="friend not found")
            # Remove existing tags for this pair.
            s.execute(
                _sa_text(
                    "DELETE FROM friend_tags WHERE user_phone = :u AND friend_phone = :f"
                ),
                {"u": phone, "f": target},
            )
            # Insert new tags.
            for v in tags_norm:
                s.add(
                    FriendTagDB(
                        user_phone=phone,
                        friend_phone=target,
                        tag=v,
                    )
                )
            s.commit()
        return {"status": "ok", "tags": tags_norm}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/me/close_friends", response_class=JSONResponse)
def me_close_friends(request: Request) -> dict[str, Any]:
    """
    Returns the current user's close friends (subset of friends).
    """
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    try:
        with _friends_session() as s:
            rows = (
                s.execute(
                    _sa_select(CloseFriendDB).where(
                        CloseFriendDB.user_phone == phone
                    )
                )
                .scalars()
                .all()
            )
            friends: list[dict[str, Any]] = []
            for row in rows:
                friends.append(
                    {
                        "id": row.friend_phone,
                        "phone": row.friend_phone,
                    }
                )
        return {"friends": friends}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/me/close_friends/{friend_phone}", response_class=JSONResponse)
def me_close_friends_add(friend_phone: str, request: Request) -> dict[str, Any]:
    """
    Marks an existing friend as close friend for Moments visibility.
    """
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    target = friend_phone.strip()
    if not target:
        raise HTTPException(status_code=400, detail="friend_phone required")
    if target == phone:
        raise HTTPException(status_code=400, detail="cannot mark yourself")
    try:
        with _friends_session() as s:
            rel = (
                s.execute(
                    _sa_select(FriendDB).where(
                        FriendDB.user_phone == phone,
                        FriendDB.friend_phone == target,
                    )
                )
                .scalars()
                .first()
            )
            if rel is None:
                raise HTTPException(
                    status_code=400, detail="not a friend"
                )
            existing = (
                s.execute(
                    _sa_select(CloseFriendDB).where(
                        CloseFriendDB.user_phone == phone,
                        CloseFriendDB.friend_phone == target,
                    )
                )
                .scalars()
                .first()
            )
            if existing is None:
                row = CloseFriendDB(
                    user_phone=phone,
                    friend_phone=target,
                )
                s.add(row)
                s.commit()
        return {"status": "ok"}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


class NearbyProfileIn(BaseModel):
    """
    Input model for updating the user's People Nearby profile.

    All fields are optional; empty strings / out-of-range values are normalised.
    """

    status: str | None = None
    gender: str | None = None  # \"male\", \"female\", \"other\" (best-effort)
    age_years: int | None = None


@app.delete("/me/close_friends/{friend_phone}", response_class=JSONResponse)
def me_close_friends_remove(friend_phone: str, request: Request) -> dict[str, Any]:
    """
    Removes a friend from the close-friends list.
    """
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    target = friend_phone.strip()
    if not target:
        raise HTTPException(status_code=400, detail="friend_phone required")
    try:
        with _friends_session() as s:
            row = (
                s.execute(
                    _sa_select(CloseFriendDB).where(
                        CloseFriendDB.user_phone == phone,
                        CloseFriendDB.friend_phone == target,
                    )
                )
                .scalars()
                .first()
            )
            if row is not None:
                s.delete(row)
                s.commit()
        return {"status": "ok"}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/me/nearby", response_class=JSONResponse)
def me_nearby(request: Request, lat: float, lon: float, limit: int = 40) -> dict[str, Any]:
    """
    Returns nearby Shamell users for the People Nearby feature.

    - Upserts the caller's latest location (coarse presence).
    - Returns other users seen recently (within NEARBY_TTL_SECS), sorted by distance.
    """
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    now = datetime.now(timezone.utc)
    try:
        limit_val = max(1, min(limit, 100))
        cutoff = now - timedelta(seconds=NEARBY_TTL_SECS)
        with _nearby_session() as s:
            # Upsert caller presence.
            row = (
                s.execute(
                    _sa_select(NearbyPresenceDB).where(
                        NearbyPresenceDB.user_phone == phone
                    )
                )
                .scalars()
                .first()
            )
            if row is None:
                row = NearbyPresenceDB(
                    user_phone=phone,
                    last_lat=float(lat),
                    last_lon=float(lon),
                    updated_at=now,
                )
                s.add(row)
            else:
                row.last_lat = float(lat)
                row.last_lon = float(lon)
                row.updated_at = now
            s.commit()

        # Load other recent presences in a second transaction to keep scope small.
        with _nearby_session() as s:
            rows = (
                s.execute(
                    _sa_select(NearbyPresenceDB).where(
                        NearbyPresenceDB.updated_at >= cutoff,
                        NearbyPresenceDB.user_phone != phone,
                    )
                )
                .scalars()
                .all()
            )

        items: list[dict[str, Any]] = []
        for r in rows:
            try:
                plat = float(r.last_lat or 0.0)
                plon = float(r.last_lon or 0.0)
            except Exception:
                plat, plon = 0.0, 0.0
            try:
                d_km = _haversine_km(float(lat), float(lon), plat, plon)
            except Exception:
                d_km = 0.0
            distance_m = max(0.0, d_km * 1000.0)
            # Basic, privacy‑friendly payload – phone as ID; no exact location.
            items.append(
                {
                    "id": r.user_phone,
                    "shamell_id": r.user_phone,
                    "name": r.user_phone,
                    "distance_m": distance_m,
                    "status": (r.status or "").strip(),
                    "gender": (r.gender or "").strip().lower(),
                    "age_years": r.age_years,
                }
            )

        items.sort(key=lambda it: float(it.get("distance_m") or 0.0))
        return {"results": items[:limit_val]}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/me/nearby/profile", response_class=JSONResponse)
def me_nearby_profile_get(request: Request) -> dict[str, Any]:
    """
    Returns the current user's People Nearby profile (status/gender/age).
    """
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    try:
        with _nearby_session() as s:
            row = (
                s.execute(
                    _sa_select(NearbyPresenceDB).where(
                        NearbyPresenceDB.user_phone == phone
                    )
                )
                .scalars()
                .first()
            )
        if not row:
            return {"status": "", "gender": "", "age_years": None}
        return {
            "status": (row.status or "").strip(),
            "gender": (row.gender or "").strip().lower(),
            "age_years": row.age_years,
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/me/nearby/profile", response_class=JSONResponse)
async def me_nearby_profile_set(request: Request, body: NearbyProfileIn) -> dict[str, Any]:
    """
    Updates the current user's People Nearby profile (status/gender/age).

    This does not change the last known location; that is updated via /me/nearby.
    """
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")

    raw_status = (body.status or "").strip()
    # Keep status reasonably short for UI.
    status = raw_status[:160]
    gender_raw = (body.gender or "").strip().lower()
    gender: str | None
    if gender_raw in ("male", "female", "other"):
        gender = gender_raw
    elif not gender_raw:
        gender = None
    else:
        # Unknown values are normalised to None to avoid surprises.
        gender = None

    age_val: int | None = None
    if body.age_years is not None:
        try:
            a = int(body.age_years)
        except Exception:
            a = None
        if a is not None and 13 <= a <= 120:
            age_val = a

    now = datetime.now(timezone.utc)
    try:
        with _nearby_session() as s:
            row = (
                s.execute(
                    _sa_select(NearbyPresenceDB).where(
                        NearbyPresenceDB.user_phone == phone
                    )
                )
                .scalars()
                .first()
            )
            if row is None:
                row = NearbyPresenceDB(
                    user_phone=phone,
                    status=status or None,
                    gender=gender,
                    age_years=age_val,
                    updated_at=now,
                )
                s.add(row)
            else:
                row.status = status or None
                row.gender = gender
                row.age_years = age_val
                row.updated_at = now
            s.commit()
        return {
            "status": status,
            "gender": gender or "",
            "age_years": age_val,
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/moments/admin/posts/{post_id}/comment", response_class=JSONResponse)
def moments_admin_add_official_comment(post_id: int, request: Request, body: MomentAdminReplyIn):
    """
    Adds a comment as Official account for a given post (admin/ops only).
    """
    _require_admin_v2(request)
    text = (body.text or "").strip()
    if not text:
        raise HTTPException(status_code=400, detail="empty comment")
    acc_id = (body.official_account_id or "").strip()
    if not acc_id:
        raise HTTPException(status_code=400, detail="official_account_id required")
    reply_to_id = body.reply_to_id
    try:
        with _officials_session() as osess:
            acc = osess.get(OfficialAccountDB, acc_id)
            if not acc or not acc.enabled:
                raise HTTPException(status_code=404, detail="official account not found")
        user_key = f"official:{acc_id}"
        with _moments_session() as s:
            post = s.get(MomentPostDB, post_id)
            if not post:
                raise HTTPException(status_code=404, detail="moment not found")
            if reply_to_id is not None:
                target = s.get(MomentCommentDB, reply_to_id)
                if not target or target.post_id != post_id:
                    reply_to_id = None
            row = MomentCommentDB(
                post_id=post_id,
                user_key=user_key,
                text=text,
                reply_to_id=reply_to_id,
            )
            s.add(row)
            s.commit()
            s.refresh(row)
            ts = row.created_at
            ts_str = (
                ts.isoformat().replace("+00:00", "Z")
                if isinstance(ts, datetime)
                else datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
            )
            author = f"Official · {acc_id}"
            out = MomentCommentOut(
                id=str(row.id),
                text=row.text,
                ts=ts_str,
                author_name=author,
                reply_to_id=str(row.reply_to_id)
                if getattr(row, "reply_to_id", None)
                else None,
                reply_to_name=None,
            ).dict()
        try:
            emit_event(
                "moments",
                "comment_create_official",
                {"account_id": acc_id, "post_id": post_id},
            )
        except Exception:
            pass
        return out
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/moments/admin/html", response_class=HTMLResponse)
def moments_admin_html(
    request: Request,
    limit: int = 100,
    redpacket_only: bool = False,
    origin_official_account_id: str | None = None,
    origin_official_item_id: str | None = None,
    campaign_id: str | None = None,
) -> HTMLResponse:
    """
    Minimal HTML view for QA to inspect Moments posts.
    """
    _require_admin_v2(request)
    try:
        limit_val = max(1, min(limit, 200))
        with _moments_session() as s:
            stmt = _sa_select(MomentPostDB)
            if redpacket_only:
                stmt = stmt.where(
                    MomentPostDB.text.contains("Red packet")
                    | MomentPostDB.text.contains(
                        "I am sending red packets via Shamell Pay"
                    )
                    | MomentPostDB.text.contains("حزمة حمراء")
                )
            # Optional filtering by origin official account / campaign (WeChat-style QA).
            if origin_official_account_id:
                stmt = stmt.where(
                    MomentPostDB.origin_official_account_id
                    == origin_official_account_id
                )
            target_item = origin_official_item_id or campaign_id
            if target_item:
                stmt = stmt.where(
                    MomentPostDB.origin_official_item_id == target_item
                )
            # Default ordering: latest first. For debugging "top" posts,
            # admins can bump limit and then sort by likes/comments in the UI.
            stmt = stmt.order_by(
                MomentPostDB.created_at.desc(), MomentPostDB.id.desc()
            ).limit(limit_val)
            rows = s.execute(stmt).scalars().all()
            post_ids = [r.id for r in rows]
            likes_map: dict[int, int] = {}
            comments_map: dict[int, int] = {}
            if post_ids:
                likes_rows = (
                    s.execute(
                        _sa_select(
                            MomentLikeDB.post_id, _sa_func.count(MomentLikeDB.id)
                        ).where(MomentLikeDB.post_id.in_(post_ids)
                        ).group_by(MomentLikeDB.post_id)
                    )
                    .all()
                )
                for pid, cnt in likes_rows:
                    likes_map[int(pid)] = int(cnt)
                comments_rows = (
                    s.execute(
                        _sa_select(
                            MomentCommentDB.post_id, _sa_func.count(MomentCommentDB.id)
                        ).where(MomentCommentDB.post_id.in_(post_ids)
                        ).group_by(MomentCommentDB.post_id)
                    )
                    .all()
                )
                for pid, cnt in comments_rows:
                    comments_map[int(pid)] = int(cnt)
        def esc(s: str) -> str:
            return _html.escape(s or "", quote=True)

        rows_html = []
        for row in rows:
            ts = row.created_at
            ts_str = (
                ts.isoformat().replace("+00:00", "Z")
                if isinstance(ts, datetime)
                else datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
            )
            origin_acc = getattr(row, "origin_official_account_id", None)
            origin_item = getattr(row, "origin_official_item_id", None)
            origin = ""
            if origin_acc:
                origin = esc(origin_acc)
                if origin_item:
                    origin += "/" + esc(origin_item)
            comments_count = comments_map.get(row.id, 0)
            comments_cell = (
                f'<a href="/moments/admin/comments/html?post_id={row.id}">{comments_count}</a>'
            )
            rows_html.append(
                f"<tr>"
                f"<td>{row.id}</td>"
                f"<td>{esc(row.user_key)}</td>"
                f"<td>{esc(row.visibility or 'public')}</td>"
                f"<td>{esc(ts_str)}</td>"
                f"<td>{likes_map.get(row.id, 0)}</td>"
                f"<td>{comments_cell}</td>"
                f"<td>{'✓' if (row.image_b64 or row.image_url) else ''}</td>"
                f"<td>{origin}</td>"
                f"<td><pre>{esc(row.text[:280])}</pre></td>"
                f"</tr>"
            )
        html = f"""
<!doctype html>
<html><head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Moments Admin</title>
  <style>
    body{{font-family:sans-serif;margin:20px;max-width:960px;color:#0f172a;}}
    h1{{margin-bottom:8px;}}
    table{{border-collapse:collapse;width:100%;margin-top:12px;}}
    th,td{{padding:6px 8px;border-bottom:1px solid #e5e7eb;font-size:13px;text-align:left;vertical-align:top;}}
    th{{background:#f9fafb;font-weight:600;}}
    pre{{white-space:pre-wrap;font-family:ui-monospace,monospace;font-size:12px;margin:0;}}
    .meta{{color:#6b7280;font-size:12px;margin-top:4px;}}
  </style>
</head><body>
  <h1>Moments Admin</h1>
  <div class="meta">Latest {len(rows)} moments (limit={limit_val}).</div>
  <p class="meta">
    <a href="/moments/admin/html">All</a> ·
    <a href="/moments/admin/html?redpacket_only=1">Only red‑packet posts</a>
  </p>
  <table>
    <thead>
      <tr>
        <th>ID</th>
        <th>User</th>
        <th>Visibility</th>
        <th>Created</th>
        <th>Likes</th>
        <th>Comments</th>
        <th>Img</th>
        <th>Origin (official)</th>
        <th>Text (truncated)</th>
      </tr>
    </thead>
    <tbody>
      {''.join(rows_html) if rows_html else '<tr><td colspan="9">No moments yet.</td></tr>'}
    </tbody>
  </table>
</body></html>
"""
        return HTMLResponse(content=html)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/moments/admin/comments/html", response_class=HTMLResponse)
def moments_admin_comments_html(request: Request) -> HTMLResponse:
    """
    Minimal HTML console for inspecting and moderating Moments comments.
    """
    _require_admin_v2(request)
    return _html_template_response("moments_admin_comments.html")


@app.get("/moments/admin/analytics", response_class=HTMLResponse)
def moments_admin_analytics(request: Request) -> HTMLResponse:
    """
    Lightweight HTML analytics for Moments.

    Shows total posts/likes/comments and simple per-user aggregates,
    similar to WeChat Moments QA dashboards.
    """
    _require_admin_v2(request)
    try:
        with _moments_session() as s:
            total_posts = (
                s.execute(_sa_select(_sa_func.count(MomentPostDB.id)))
                .scalar()
                or 0
            )
            total_likes = (
                s.execute(_sa_select(_sa_func.count(MomentLikeDB.id)))
                .scalar()
                or 0
            )
            total_comments = (
                s.execute(_sa_select(_sa_func.count(MomentCommentDB.id)))
                .scalar()
                or 0
            )
            total_official_shares = (
                s.execute(
                    _sa_select(_sa_func.count(MomentPostDB.id)).where(
                        MomentPostDB.origin_official_account_id.is_not(None)
                    )
                )
                .scalar()
                or 0
            )
            redpacket_posts = 0
            try:
                rp1 = (
                    s.execute(
                        _sa_select(_sa_func.count(MomentPostDB.id)).where(
                            MomentPostDB.text.contains("Red packet")
                        )
                    )
                    .scalar()
                    or 0
                )
                rp2 = (
                    s.execute(
                        _sa_select(_sa_func.count(MomentPostDB.id)).where(
                            MomentPostDB.text.contains(
                                "I am sending red packets via Shamell Pay"
                            )
                        )
                    )
                    .scalar()
                    or 0
                )
                rp3 = (
                    s.execute(
                        _sa_select(_sa_func.count(MomentPostDB.id)).where(
                            MomentPostDB.text.contains("حزمة حمراء")
                        )
                    )
                    .scalar()
                    or 0
                )
                redpacket_posts = int((rp1 or 0) + (rp2 or 0) + (rp3 or 0))
            except Exception:
                redpacket_posts = 0

            # Last 30 days activity
            since = datetime.now(timezone.utc) - timedelta(days=30)
            recent_posts = (
                s.execute(
                    _sa_select(_sa_func.count(MomentPostDB.id)).where(
                        MomentPostDB.created_at >= since
                    )
                )
                .scalar()
                or 0
            )
            recent_likes = (
                s.execute(
                    _sa_select(_sa_func.count(MomentLikeDB.id)).where(
                        MomentLikeDB.created_at >= since
                    )
                )
                .scalar()
                or 0
            )
            recent_comments = (
                s.execute(
                    _sa_select(_sa_func.count(MomentCommentDB.id)).where(
                        MomentCommentDB.created_at >= since
                    )
                )
                .scalar()
                or 0
            )

            # Red-packet mentions in the last 30 days
            recent_redpacket_posts = 0
            try:
                rp1_30 = (
                    s.execute(
                        _sa_select(_sa_func.count(MomentPostDB.id)).where(
                            MomentPostDB.created_at >= since,
                            MomentPostDB.text.contains("Red packet"),
                        )
                    )
                    .scalar()
                    or 0
                )
                rp2_30 = (
                    s.execute(
                        _sa_select(_sa_func.count(MomentPostDB.id)).where(
                            MomentPostDB.created_at >= since,
                            MomentPostDB.text.contains(
                                "I am sending red packets via Shamell Pay"
                            ),
                        )
                    )
                    .scalar()
                    or 0
                )
                rp3_30 = (
                    s.execute(
                        _sa_select(_sa_func.count(MomentPostDB.id)).where(
                            MomentPostDB.created_at >= since,
                            MomentPostDB.text.contains("حزمة حمراء"),
                        )
                    )
                    .scalar()
                    or 0
                )
                recent_redpacket_posts = int((rp1_30 or 0) + (rp2_30 or 0) + (rp3_30 or 0))
            except Exception:
                recent_redpacket_posts = 0

            # Top posters and commenters by user_key
            top_posters = (
                s.execute(
                    _sa_select(
                        MomentPostDB.user_key,
                        _sa_func.count(MomentPostDB.id),
                    )
                    .group_by(MomentPostDB.user_key)
                    .order_by(_sa_func.count(MomentPostDB.id).desc())
                    .limit(20)
                )
                .all()
            )
            top_commenters = (
                s.execute(
                    _sa_select(
                        MomentCommentDB.user_key,
                        _sa_func.count(MomentCommentDB.id),
                    )
                    .group_by(MomentCommentDB.user_key)
                    .order_by(_sa_func.count(MomentCommentDB.id).desc())
                    .limit(20)
                )
                .all()
            )

            top_topics = (
                s.execute(
                    _sa_select(
                        MomentTagDB.tag,
                        _sa_func.count(MomentTagDB.id),
                    )
                    .group_by(MomentTagDB.tag)
                    .order_by(_sa_func.count(MomentTagDB.id).desc())
                    .limit(20)
                )
                .all()
            )

        def esc(s: str) -> str:
            return _html.escape(s or "", quote=True)

        posters_rows: list[str] = []
        for user_key, cnt in top_posters:
            posters_rows.append(
                "<tr>"
                f"<td><pre>{esc(str(user_key or ''))}</pre></td>"
                f"<td>{int(cnt or 0)}</td>"
                "</tr>"
            )

        commenters_rows: list[str] = []
        for user_key, cnt in top_commenters:
            commenters_rows.append(
                "<tr>"
                f"<td><pre>{esc(str(user_key or ''))}</pre></td>"
                f"<td>{int(cnt or 0)}</td>"
                "</tr>"
            )

        topics_rows: list[str] = []
        for tag, cnt in top_topics:
            topics_rows.append(
                "<tr>"
                f"<td><pre>{esc(str(tag or ''))}</pre></td>"
                f"<td>{int(cnt or 0)}</td>"
                "</tr>"
            )

        html = f"""
<!doctype html>
<html><head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Moments · Analytics</title>
  <style>
    body{{font-family:sans-serif;margin:20px;max-width:1100px;color:#0f172a;}}
    h1{{margin-bottom:4px;}}
    h2{{margin-top:24px;margin-bottom:8px;}}
    table{{border-collapse:collapse;width:100%;margin-top:8px;}}
    th,td{{padding:6px 8px;border-bottom:1px solid #e5e7eb;font-size:13px;text-align:left;vertical-align:top;}}
    th{{background:#f9fafb;font-weight:600;}}
    .meta{{color:#6b7280;font-size:12px;margin-top:4px;}}
    pre{{white-space:pre-wrap;font-family:ui-monospace,monospace;font-size:12px;margin:0;}}
  </style>
</head><body>
  <h1>Moments · Analytics</h1>
  <div class="meta">
    Total posts: {int(total_posts)} · likes: {int(total_likes)} · comments: {int(total_comments)} · official shares: {int(total_official_shares)} · red-packet mentions: {int(redpacket_posts)}.
  </div>
  <div class="meta">
    Last 30 days — posts: {int(recent_posts)}, likes: {int(recent_likes)}, comments: {int(recent_comments)}, red-packet mentions: {int(recent_redpacket_posts)}.
  </div>
  <p class="meta">
    <a href="/moments/admin/html">Zurück zur Moments-Admin-Übersicht</a>
  </p>

  <h2>Top posters (by user_key)</h2>
  <table>
    <thead>
      <tr><th>User key</th><th>Posts</th></tr>
    </thead>
    <tbody>
      {''.join(posters_rows) if posters_rows else '<tr><td colspan="2">Keine Posts gefunden.</td></tr>'}
    </tbody>
  </table>

  <h2>Top commenters (by user_key)</h2>
  <table>
    <thead>
      <tr><th>User key</th><th>Comments</th></tr>
    </thead>
    <tbody>
      {''.join(commenters_rows) if commenters_rows else '<tr><td colspan="2">Keine Kommentare gefunden.</td></tr>'}
    </tbody>
  </table>

  <h2>Top topics (hashtags)</h2>
  <table>
    <thead>
      <tr><th>Tag</th><th>Posts</th></tr>
    </thead>
    <tbody>
      {''.join(topics_rows) if topics_rows else '<tr><td colspan="2">Keine Hashtag-Daten gefunden.</td></tr>'}
    </tbody>
  </table>
</body></html>
"""
        return HTMLResponse(content=html)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ---- Official accounts (merchant / brand layer, BFF-side) ----

_OFFICIALS_DB_URL = _env_or("OFFICIALS_DB_URL", _env_or("DB_URL", "sqlite+pysqlite:////tmp/officials.db"))
_OFFICIALS_DB_SCHEMA = os.getenv("DB_SCHEMA") if not _OFFICIALS_DB_URL.startswith("sqlite") else None


class _OfficialBase(_sa_DeclarativeBase):
    pass


class OfficialAccountDB(_OfficialBase):
    __tablename__ = "official_accounts"
    __table_args__ = ({"schema": _OFFICIALS_DB_SCHEMA} if _OFFICIALS_DB_SCHEMA else {})
    id: _sa_Mapped[str] = _sa_mapped_column(_sa_String(64), primary_key=True)
    kind: _sa_Mapped[str] = _sa_mapped_column(_sa_String(16), default="service")
    name: _sa_Mapped[str] = _sa_mapped_column(_sa_String(200))
    name_ar: _sa_Mapped[str | None] = _sa_mapped_column(_sa_String(200), nullable=True)
    avatar_url: _sa_Mapped[str | None] = _sa_mapped_column(_sa_String(255), nullable=True)
    verified: _sa_Mapped[bool] = _sa_mapped_column(_sa_Boolean, default=True)
    mini_app_id: _sa_Mapped[str | None] = _sa_mapped_column(_sa_String(64), nullable=True)
    description: _sa_Mapped[str | None] = _sa_mapped_column(_sa_String(255), nullable=True)
    chat_peer_id: _sa_Mapped[str | None] = _sa_mapped_column(_sa_String(64), nullable=True)
    category: _sa_Mapped[str | None] = _sa_mapped_column(_sa_String(64), nullable=True)
    city: _sa_Mapped[str | None] = _sa_mapped_column(_sa_String(64), nullable=True)
    address: _sa_Mapped[str | None] = _sa_mapped_column(_sa_String(255), nullable=True)
    opening_hours: _sa_Mapped[str | None] = _sa_mapped_column(_sa_String(255), nullable=True)
    website_url: _sa_Mapped[str | None] = _sa_mapped_column(_sa_String(255), nullable=True)
    qr_payload: _sa_Mapped[str | None] = _sa_mapped_column(_sa_String(255), nullable=True)
    featured: _sa_Mapped[bool] = _sa_mapped_column(_sa_Boolean, default=False)
    enabled: _sa_Mapped[bool] = _sa_mapped_column(_sa_Boolean, default=True)
    official: _sa_Mapped[bool] = _sa_mapped_column(_sa_Boolean, default=True)
    created_at: _sa_Mapped[str | None] = _sa_mapped_column(
        _sa_DateTime(timezone=True), server_default=_sa_func.now()
    )
    updated_at: _sa_Mapped[str | None] = _sa_mapped_column(
        _sa_DateTime(timezone=True),
        server_default=_sa_func.now(),
        onupdate=_sa_func.now(),
    )


class OfficialAccountRequestDB(_OfficialBase):
    __tablename__ = "official_account_requests"
    __table_args__ = ({"schema": _OFFICIALS_DB_SCHEMA} if _OFFICIALS_DB_SCHEMA else {})
    id: _sa_Mapped[int] = _sa_mapped_column(_sa_Integer, primary_key=True, autoincrement=True)
    account_id: _sa_Mapped[str] = _sa_mapped_column(_sa_String(64), index=True)
    kind: _sa_Mapped[str] = _sa_mapped_column(_sa_String(16), default="service")
    name: _sa_Mapped[str] = _sa_mapped_column(_sa_String(200))
    name_ar: _sa_Mapped[str | None] = _sa_mapped_column(_sa_String(200), nullable=True)
    description: _sa_Mapped[str | None] = _sa_mapped_column(_sa_String(255), nullable=True)
    category: _sa_Mapped[str | None] = _sa_mapped_column(_sa_String(64), nullable=True)
    city: _sa_Mapped[str | None] = _sa_mapped_column(_sa_String(64), nullable=True)
    address: _sa_Mapped[str | None] = _sa_mapped_column(_sa_String(255), nullable=True)
    opening_hours: _sa_Mapped[str | None] = _sa_mapped_column(_sa_String(255), nullable=True)
    website_url: _sa_Mapped[str | None] = _sa_mapped_column(_sa_String(255), nullable=True)
    mini_app_id: _sa_Mapped[str | None] = _sa_mapped_column(_sa_String(64), nullable=True)
    owner_name: _sa_Mapped[str | None] = _sa_mapped_column(_sa_String(200), nullable=True)
    contact_phone: _sa_Mapped[str | None] = _sa_mapped_column(_sa_String(64), nullable=True)
    contact_email: _sa_Mapped[str | None] = _sa_mapped_column(_sa_String(255), nullable=True)
    requester_phone: _sa_Mapped[str | None] = _sa_mapped_column(_sa_String(64), nullable=True)
    status: _sa_Mapped[str] = _sa_mapped_column(_sa_String(16), default="submitted")
    created_at: _sa_Mapped[datetime] = _sa_mapped_column(
        _sa_DateTime(timezone=True), server_default=_sa_func.now()
    )
    updated_at: _sa_Mapped[datetime] = _sa_mapped_column(
        _sa_DateTime(timezone=True),
        server_default=_sa_func.now(),
        onupdate=_sa_func.now(),
    )


class OfficialFeedItemDB(_OfficialBase):
    __tablename__ = "official_feed_items"
    __table_args__ = ({"schema": _OFFICIALS_DB_SCHEMA} if _OFFICIALS_DB_SCHEMA else {})
    id: _sa_Mapped[int] = _sa_mapped_column(_sa_Integer, primary_key=True, autoincrement=True)
    account_id: _sa_Mapped[str] = _sa_mapped_column(_sa_String(64), index=True)
    slug: _sa_Mapped[str] = _sa_mapped_column(_sa_String(64), unique=True)
    type: _sa_Mapped[str] = _sa_mapped_column(_sa_String(16), default="promo")
    title: _sa_Mapped[str | None] = _sa_mapped_column(_sa_String(255), nullable=True)
    snippet: _sa_Mapped[str | None] = _sa_mapped_column(_sa_String(512), nullable=True)
    thumb_url: _sa_Mapped[str | None] = _sa_mapped_column(_sa_String(255), nullable=True)
    ts: _sa_Mapped[str | None] = _sa_mapped_column(
        _sa_DateTime(timezone=True), server_default=_sa_func.now()
    )
    deeplink_json: _sa_Mapped[str | None] = _sa_mapped_column(_sa_Text, nullable=True)


class OfficialLocationDB(_OfficialBase):
    __tablename__ = "official_locations"
    __table_args__ = ({"schema": _OFFICIALS_DB_SCHEMA} if _OFFICIALS_DB_SCHEMA else {})
    id: _sa_Mapped[int] = _sa_mapped_column(_sa_Integer, primary_key=True, autoincrement=True)
    account_id: _sa_Mapped[str] = _sa_mapped_column(_sa_String(64), index=True)
    name: _sa_Mapped[str | None] = _sa_mapped_column(_sa_String(120), nullable=True)
    city: _sa_Mapped[str | None] = _sa_mapped_column(_sa_String(64), nullable=True)
    address: _sa_Mapped[str | None] = _sa_mapped_column(_sa_String(255), nullable=True)
    lat: _sa_Mapped[float | None] = _sa_mapped_column(_sa_Float, nullable=True)
    lon: _sa_Mapped[float | None] = _sa_mapped_column(_sa_Float, nullable=True)
    phone: _sa_Mapped[str | None] = _sa_mapped_column(_sa_String(32), nullable=True)
    opening_hours: _sa_Mapped[str | None] = _sa_mapped_column(_sa_String(255), nullable=True)


class MiniAppDB(_OfficialBase):
    __tablename__ = "mini_apps"
    __table_args__ = ({"schema": _OFFICIALS_DB_SCHEMA} if _OFFICIALS_DB_SCHEMA else {})
    id: _sa_Mapped[int] = _sa_mapped_column(_sa_Integer, primary_key=True, autoincrement=True)
    app_id: _sa_Mapped[str] = _sa_mapped_column(_sa_String(64), unique=True, index=True)
    title_en: _sa_Mapped[str] = _sa_mapped_column(_sa_String(200))
    title_ar: _sa_Mapped[str | None] = _sa_mapped_column(_sa_String(200), nullable=True)
    category_en: _sa_Mapped[str | None] = _sa_mapped_column(_sa_String(64), nullable=True)
    category_ar: _sa_Mapped[str | None] = _sa_mapped_column(_sa_String(64), nullable=True)
    description: _sa_Mapped[str | None] = _sa_mapped_column(_sa_String(255), nullable=True)
    icon: _sa_Mapped[str | None] = _sa_mapped_column(_sa_String(64), nullable=True)
    official: _sa_Mapped[bool] = _sa_mapped_column(_sa_Boolean, default=False)
    enabled: _sa_Mapped[bool] = _sa_mapped_column(_sa_Boolean, default=True)
    beta: _sa_Mapped[bool] = _sa_mapped_column(_sa_Boolean, default=False)
    runtime_app_id: _sa_Mapped[str | None] = _sa_mapped_column(
        _sa_String(64), nullable=True
    )
    rating: _sa_Mapped[float | None] = _sa_mapped_column(_sa_Float, nullable=True)
    usage_score: _sa_Mapped[int] = _sa_mapped_column(_sa_Integer, default=0)
    moments_shares: _sa_Mapped[int] = _sa_mapped_column(_sa_Integer, default=0)
    created_at: _sa_Mapped[str | None] = _sa_mapped_column(
        _sa_DateTime(timezone=True), server_default=_sa_func.now()
    )
    updated_at: _sa_Mapped[str | None] = _sa_mapped_column(
        _sa_DateTime(timezone=True),
        server_default=_sa_func.now(),
        onupdate=_sa_func.now(),
    )


class MiniAppRatingDB(_OfficialBase):
    __tablename__ = "mini_app_ratings"
    __table_args__ = (
        _sa_UniqueConstraint(
            "user_key",
            "app_id",
            name="uq_mini_app_ratings_user_app",
        ),
        {"schema": _OFFICIALS_DB_SCHEMA} if _OFFICIALS_DB_SCHEMA else {},
    )
    id: _sa_Mapped[int] = _sa_mapped_column(
        _sa_Integer, primary_key=True, autoincrement=True
    )
    user_key: _sa_Mapped[str] = _sa_mapped_column(_sa_String(128), index=True)
    app_id: _sa_Mapped[str] = _sa_mapped_column(_sa_String(64), index=True)
    rating: _sa_Mapped[int] = _sa_mapped_column(_sa_Integer)
    created_at: _sa_Mapped[datetime] = _sa_mapped_column(
        _sa_DateTime(timezone=True), server_default=_sa_func.now()
    )
    updated_at: _sa_Mapped[datetime] = _sa_mapped_column(
        _sa_DateTime(timezone=True),
        server_default=_sa_func.now(),
        onupdate=_sa_func.now(),
    )


class MiniProgramDB(_OfficialBase):
    """
    Lightweight registry for Mini‑Programs (WeChat‑style mini‑apps).

    This is intentionally minimal for the MVP: it tracks ownership and
    display metadata, while versions and releases are stored in the
    companion tables MiniProgramVersionDB and MiniProgramReleaseDB.
    """

    __tablename__ = "mini_programs"
    __table_args__ = ({"schema": _OFFICIALS_DB_SCHEMA} if _OFFICIALS_DB_SCHEMA else {})

    id: _sa_Mapped[int] = _sa_mapped_column(
        _sa_Integer, primary_key=True, autoincrement=True
    )
    app_id: _sa_Mapped[str] = _sa_mapped_column(
        _sa_String(64), unique=True, index=True
    )
    title_en: _sa_Mapped[str] = _sa_mapped_column(_sa_String(200))
    title_ar: _sa_Mapped[str | None] = _sa_mapped_column(
        _sa_String(200), nullable=True
    )
    description_en: _sa_Mapped[str | None] = _sa_mapped_column(
        _sa_String(512), nullable=True
    )
    description_ar: _sa_Mapped[str | None] = _sa_mapped_column(
        _sa_String(512), nullable=True
    )
    actions_json: _sa_Mapped[str | None] = _sa_mapped_column(
        _sa_Text, nullable=True
    )
    owner_name: _sa_Mapped[str | None] = _sa_mapped_column(
        _sa_String(200), nullable=True
    )
    owner_contact: _sa_Mapped[str | None] = _sa_mapped_column(
        _sa_String(200), nullable=True
    )
    scopes_json: _sa_Mapped[str | None] = _sa_mapped_column(
        _sa_Text, nullable=True
    )
    status: _sa_Mapped[str] = _sa_mapped_column(
        _sa_String(32), default="draft", server_default="draft"
    )
    review_status: _sa_Mapped[str] = _sa_mapped_column(
        _sa_String(32), default="draft", server_default="draft"
    )
    rating: _sa_Mapped[float | None] = _sa_mapped_column(
        _sa_Float, nullable=True
    )
    usage_score: _sa_Mapped[int] = _sa_mapped_column(_sa_Integer, default=0)
    created_at: _sa_Mapped[datetime] = _sa_mapped_column(
        _sa_DateTime(timezone=True), server_default=_sa_func.now()
    )
    updated_at: _sa_Mapped[datetime] = _sa_mapped_column(
        _sa_DateTime(timezone=True),
        server_default=_sa_func.now(),
        onupdate=_sa_func.now(),
    )


class MiniProgramVersionDB(_OfficialBase):
    """
    Individual version records for a Mini‑Program.

    A version references a static bundle_url (e.g. H5/JS bundle) and
    optional changelog text. Releases point at concrete versions.
    """

    __tablename__ = "mini_program_versions"
    __table_args__ = ({"schema": _OFFICIALS_DB_SCHEMA} if _OFFICIALS_DB_SCHEMA else {})

    id: _sa_Mapped[int] = _sa_mapped_column(
        _sa_Integer, primary_key=True, autoincrement=True
    )
    program_id: _sa_Mapped[int] = _sa_mapped_column(_sa_Integer, index=True)
    version: _sa_Mapped[str] = _sa_mapped_column(_sa_String(32))
    bundle_url: _sa_Mapped[str | None] = _sa_mapped_column(
        _sa_String(512), nullable=True
    )
    changelog_en: _sa_Mapped[str | None] = _sa_mapped_column(
        _sa_String(512), nullable=True
    )
    changelog_ar: _sa_Mapped[str | None] = _sa_mapped_column(
        _sa_String(512), nullable=True
    )
    created_at: _sa_Mapped[datetime] = _sa_mapped_column(
        _sa_DateTime(timezone=True), server_default=_sa_func.now()
    )


class MiniProgramReleaseDB(_OfficialBase):
    """
    Tracks which Mini‑Program version is currently released per channel.

    For now we keep this simple: each call to the release endpoint
    appends a new row; clients can query the newest row per program+channel.
    """

    __tablename__ = "mini_program_releases"
    __table_args__ = ({"schema": _OFFICIALS_DB_SCHEMA} if _OFFICIALS_DB_SCHEMA else {})

    id: _sa_Mapped[int] = _sa_mapped_column(
        _sa_Integer, primary_key=True, autoincrement=True
    )
    program_id: _sa_Mapped[int] = _sa_mapped_column(_sa_Integer, index=True)
    version_id: _sa_Mapped[int] = _sa_mapped_column(_sa_Integer, index=True)
    channel: _sa_Mapped[str] = _sa_mapped_column(
        _sa_String(32), default="prod", server_default="prod"
    )
    status: _sa_Mapped[str] = _sa_mapped_column(
        _sa_String(32), default="active", server_default="active"
    )


class MiniProgramRatingDB(_OfficialBase):
    """
    Per-user star ratings for Mini‑Programs (1–5).

    Mirrors MiniAppRatingDB so WeChat‑ähnliche Bewertungen auch
    für Mini‑Programs verfügbar sind.
    """

    __tablename__ = "mini_program_ratings"
    __table_args__ = (
        _sa_UniqueConstraint(
            "user_key",
            "app_id",
            name="uq_mini_program_ratings_user_app",
        ),
        {"schema": _OFFICIALS_DB_SCHEMA} if _OFFICIALS_DB_SCHEMA else {},
    )
    id: _sa_Mapped[int] = _sa_mapped_column(
        _sa_Integer, primary_key=True, autoincrement=True
    )
    user_key: _sa_Mapped[str] = _sa_mapped_column(_sa_String(128), index=True)
    app_id: _sa_Mapped[str] = _sa_mapped_column(_sa_String(64), index=True)
    rating: _sa_Mapped[int] = _sa_mapped_column(_sa_Integer)
    created_at: _sa_Mapped[datetime] = _sa_mapped_column(
        _sa_DateTime(timezone=True), server_default=_sa_func.now()
    )
    updated_at: _sa_Mapped[datetime] = _sa_mapped_column(
        _sa_DateTime(timezone=True),
        server_default=_sa_func.now(),
        onupdate=_sa_func.now(),
    )
    created_at: _sa_Mapped[datetime] = _sa_mapped_column(
        _sa_DateTime(timezone=True), server_default=_sa_func.now()
    )


class ChannelLikeDB(_OfficialBase):
    __tablename__ = "channel_likes"
    __table_args__ = (
        _sa_UniqueConstraint(
            "user_key",
            "item_id",
            name="uq_channel_likes_user_item",
        ),
        {"schema": _OFFICIALS_DB_SCHEMA} if _OFFICIALS_DB_SCHEMA else {},
    )
    id: _sa_Mapped[int] = _sa_mapped_column(
        _sa_Integer, primary_key=True, autoincrement=True
    )
    user_key: _sa_Mapped[str] = _sa_mapped_column(_sa_String(128), index=True)
    item_id: _sa_Mapped[str] = _sa_mapped_column(_sa_String(64), index=True)
    created_at: _sa_Mapped[datetime] = _sa_mapped_column(
        _sa_DateTime(timezone=True), server_default=_sa_func.now()
    )


class ChannelViewDB(_OfficialBase):
    __tablename__ = "channel_views"
    __table_args__ = (
        _sa_UniqueConstraint(
            "item_id",
            name="uq_channel_views_item",
        ),
        {"schema": _OFFICIALS_DB_SCHEMA} if _OFFICIALS_DB_SCHEMA else {},
    )
    id: _sa_Mapped[int] = _sa_mapped_column(
        _sa_Integer, primary_key=True, autoincrement=True
    )
    item_id: _sa_Mapped[str] = _sa_mapped_column(_sa_String(64), index=True)
    views: _sa_Mapped[int] = _sa_mapped_column(_sa_Integer, default=0)
    updated_at: _sa_Mapped[datetime] = _sa_mapped_column(
        _sa_DateTime(timezone=True),
        server_default=_sa_func.now(),
        onupdate=_sa_func.now(),
    )


class ChannelCommentDB(_OfficialBase):
    __tablename__ = "channel_comments"
    __table_args__ = (
        {"schema": _OFFICIALS_DB_SCHEMA} if _OFFICIALS_DB_SCHEMA else {},
    )
    id: _sa_Mapped[int] = _sa_mapped_column(
        _sa_Integer, primary_key=True, autoincrement=True
    )
    item_id: _sa_Mapped[str] = _sa_mapped_column(_sa_String(64), index=True)
    user_key: _sa_Mapped[str] = _sa_mapped_column(_sa_String(128), index=True)
    text: _sa_Mapped[str] = _sa_mapped_column(_sa_Text)
    created_at: _sa_Mapped[datetime] = _sa_mapped_column(
        _sa_DateTime(timezone=True), server_default=_sa_func.now()
    )


class RedPacketCampaignDB(_OfficialBase):
    __tablename__ = "redpacket_campaigns"
    __table_args__ = ({"schema": _OFFICIALS_DB_SCHEMA} if _OFFICIALS_DB_SCHEMA else {})
    id: _sa_Mapped[str] = _sa_mapped_column(_sa_String(64), primary_key=True)
    account_id: _sa_Mapped[str] = _sa_mapped_column(_sa_String(64), index=True)
    title: _sa_Mapped[str] = _sa_mapped_column(_sa_String(255))
    note: _sa_Mapped[str | None] = _sa_mapped_column(_sa_String(255), nullable=True)
    default_amount_cents: _sa_Mapped[int | None] = _sa_mapped_column(
        _sa_Integer, nullable=True
    )
    default_count: _sa_Mapped[int | None] = _sa_mapped_column(
        _sa_Integer, nullable=True
    )
    created_at: _sa_Mapped[str | None] = _sa_mapped_column(
        _sa_DateTime(timezone=True), server_default=_sa_func.now()
    )
    updated_at: _sa_Mapped[str | None] = _sa_mapped_column(
        _sa_DateTime(timezone=True),
        server_default=_sa_func.now(),
        onupdate=_sa_func.now(),
    )
    active: _sa_Mapped[bool] = _sa_mapped_column(_sa_Boolean, default=True)


class OfficialFollowDB(_OfficialBase):
    __tablename__ = "official_follows"
    __table_args__ = (
        _sa_UniqueConstraint("user_key", "account_id", name="uq_official_follows_user_account"),
        {"schema": _OFFICIALS_DB_SCHEMA} if _OFFICIALS_DB_SCHEMA else {},
    )
    id: _sa_Mapped[int] = _sa_mapped_column(_sa_Integer, primary_key=True, autoincrement=True)
    user_key: _sa_Mapped[str] = _sa_mapped_column(_sa_String(128), index=True)
    account_id: _sa_Mapped[str] = _sa_mapped_column(_sa_String(64), index=True)
    created_at: _sa_Mapped[str | None] = _sa_mapped_column(
        _sa_DateTime(timezone=True), server_default=_sa_func.now()
    )


class ChannelFollowDB(_OfficialBase):
    """
    Lightweight follower graph for Channels, separated from Officials.

    This models WeChat‑style \"Follow channel\" state per user and
    account, independent of whether the same Official is followed
    as a service/subscription account.
    """

    __tablename__ = "channel_follows"
    __table_args__ = (
        _sa_UniqueConstraint(
            "user_key",
            "account_id",
            name="uq_channel_follows_user_account",
        ),
        {"schema": _OFFICIALS_DB_SCHEMA} if _OFFICIALS_DB_SCHEMA else {},
    )
    id: _sa_Mapped[int] = _sa_mapped_column(
        _sa_Integer, primary_key=True, autoincrement=True
    )
    user_key: _sa_Mapped[str] = _sa_mapped_column(
        _sa_String(128), index=True
    )
    account_id: _sa_Mapped[str] = _sa_mapped_column(
        _sa_String(64), index=True
    )
    created_at: _sa_Mapped[datetime] = _sa_mapped_column(
        _sa_DateTime(timezone=True), server_default=_sa_func.now()
    )


class OfficialNotificationDB(_OfficialBase):
    __tablename__ = "official_notifications"
    __table_args__ = (
        _sa_UniqueConstraint(
            "user_key",
            "account_id",
            name="uq_official_notifications_user_account",
        ),
        {"schema": _OFFICIALS_DB_SCHEMA} if _OFFICIALS_DB_SCHEMA else {},
    )
    id: _sa_Mapped[int] = _sa_mapped_column(
        _sa_Integer, primary_key=True, autoincrement=True
    )
    user_key: _sa_Mapped[str] = _sa_mapped_column(
        _sa_String(128), index=True
    )
    account_id: _sa_Mapped[str] = _sa_mapped_column(
        _sa_String(64), index=True
    )
    mode: _sa_Mapped[str] = _sa_mapped_column(
        _sa_String(16), default="full"
    )


class OfficialAutoReplyDB(_OfficialBase):
    """
    Lightweight per‑Official auto‑reply configuration.

    For now this is intentionally minimal and focuses on "welcome"
    style replies that can be surfaced client‑side in a WeChat‑like
    way without breaking end‑to‑end chat encryption.
    """

    __tablename__ = "official_auto_replies"
    __table_args__ = ({"schema": _OFFICIALS_DB_SCHEMA} if _OFFICIALS_DB_SCHEMA else {})

    id: _sa_Mapped[int] = _sa_mapped_column(
        _sa_Integer, primary_key=True, autoincrement=True
    )
    account_id: _sa_Mapped[str] = _sa_mapped_column(
        _sa_String(64), index=True
    )
    kind: _sa_Mapped[str] = _sa_mapped_column(
        _sa_String(16), default="welcome"
    )
    keyword: _sa_Mapped[str | None] = _sa_mapped_column(
        _sa_String(64), nullable=True
    )
    text: _sa_Mapped[str] = _sa_mapped_column(_sa_Text)
    enabled: _sa_Mapped[bool] = _sa_mapped_column(_sa_Boolean, default=True)
    created_at: _sa_Mapped[datetime] = _sa_mapped_column(
        _sa_DateTime(timezone=True), server_default=_sa_func.now()
    )
    updated_at: _sa_Mapped[datetime] = _sa_mapped_column(
        _sa_DateTime(timezone=True),
        server_default=_sa_func.now(),
        onupdate=_sa_func.now(),
    )


class OfficialTemplateMessageDB(_OfficialBase):
    """
    Lightweight per-user template messages for Officials.

    This models WeChat‑style one‑time subscription messages that can
    be delivered from an Official account to a user without going
    through the end‑to‑end encrypted chat channel.
    """

    __tablename__ = "official_template_messages"
    __table_args__ = ({"schema": _OFFICIALS_DB_SCHEMA} if _OFFICIALS_DB_SCHEMA else {})

    id: _sa_Mapped[int] = _sa_mapped_column(
        _sa_Integer, primary_key=True, autoincrement=True
    )
    account_id: _sa_Mapped[str] = _sa_mapped_column(
        _sa_String(64), index=True
    )
    user_phone: _sa_Mapped[str] = _sa_mapped_column(
        _sa_String(32), index=True
    )
    title: _sa_Mapped[str] = _sa_mapped_column(_sa_String(200))
    body: _sa_Mapped[str] = _sa_mapped_column(_sa_Text)
    deeplink_json: _sa_Mapped[str | None] = _sa_mapped_column(
        _sa_Text, nullable=True
    )
    created_at: _sa_Mapped[datetime] = _sa_mapped_column(
        _sa_DateTime(timezone=True), server_default=_sa_func.now()
    )
    read_at: _sa_Mapped[datetime | None] = _sa_mapped_column(
        _sa_DateTime(timezone=True), nullable=True
    )


class OfficialServiceSessionDB(_OfficialBase):
    """
    Lightweight per-customer service session for Official accounts.

    This models a WeChat-like customer service "session" or ticket
    that can be surfaced in a unified service inbox for operators.
    """

    __tablename__ = "official_service_sessions"
    __table_args__ = ({"schema": _OFFICIALS_DB_SCHEMA} if _OFFICIALS_DB_SCHEMA else {})

    id: _sa_Mapped[int] = _sa_mapped_column(
        _sa_Integer, primary_key=True, autoincrement=True
    )
    account_id: _sa_Mapped[str] = _sa_mapped_column(_sa_String(64), index=True)
    customer_phone: _sa_Mapped[str] = _sa_mapped_column(
        _sa_String(32), index=True
    )
    chat_peer_id: _sa_Mapped[str | None] = _sa_mapped_column(
        _sa_String(64), nullable=True
    )
    status: _sa_Mapped[str] = _sa_mapped_column(
        _sa_String(16), default="open", index=True
    )
    last_message_ts: _sa_Mapped[datetime] = _sa_mapped_column(
        _sa_DateTime(timezone=True), server_default=_sa_func.now()
    )
    unread_by_operator: _sa_Mapped[bool] = _sa_mapped_column(
        _sa_Boolean, default=True
    )


class AuthSessionDB(_OfficialBase):
    """
    DB-backed auth sessions.

    We store only a SHA-256 hash of the bearer token (sid) to reduce blast
    radius in case of accidental DB reads/dumps.
    """

    __tablename__ = "auth_sessions"
    __table_args__ = (
        _sa_UniqueConstraint("sid_hash", name="uq_auth_sessions_sid_hash"),
        {"schema": _OFFICIALS_DB_SCHEMA} if _OFFICIALS_DB_SCHEMA else {},
    )

    id: _sa_Mapped[int] = _sa_mapped_column(
        _sa_Integer, primary_key=True, autoincrement=True
    )
    sid_hash: _sa_Mapped[str] = _sa_mapped_column(
        _sa_String(64), index=True
    )
    phone: _sa_Mapped[str] = _sa_mapped_column(
        _sa_String(32), index=True
    )
    device_id: _sa_Mapped[str | None] = _sa_mapped_column(
        _sa_String(128), index=True, nullable=True
    )
    expires_at: _sa_Mapped[datetime] = _sa_mapped_column(
        _sa_DateTime(timezone=True), index=True
    )
    created_at: _sa_Mapped[datetime] = _sa_mapped_column(
        _sa_DateTime(timezone=True), server_default=_sa_func.now()
    )
    revoked_at: _sa_Mapped[datetime | None] = _sa_mapped_column(
        _sa_DateTime(timezone=True), nullable=True
    )


class DeviceLoginChallengeDB(_OfficialBase):
    """
    DB-backed QR device-login challenges.

    Each challenge is identified by a random token (returned to clients),
    but stored as a SHA-256 hash in the DB.
    """

    __tablename__ = "device_login_challenges"
    __table_args__ = (
        _sa_UniqueConstraint("token_hash", name="uq_device_login_challenges_token_hash"),
        {"schema": _OFFICIALS_DB_SCHEMA} if _OFFICIALS_DB_SCHEMA else {},
    )

    id: _sa_Mapped[int] = _sa_mapped_column(
        _sa_Integer, primary_key=True, autoincrement=True
    )
    token_hash: _sa_Mapped[str] = _sa_mapped_column(
        _sa_String(64), index=True
    )
    label: _sa_Mapped[str | None] = _sa_mapped_column(
        _sa_String(128), nullable=True
    )
    status: _sa_Mapped[str] = _sa_mapped_column(
        _sa_String(16), default="pending", index=True
    )
    phone: _sa_Mapped[str | None] = _sa_mapped_column(
        _sa_String(32), index=True, nullable=True
    )
    device_id: _sa_Mapped[str | None] = _sa_mapped_column(
        _sa_String(128), nullable=True
    )
    created_at: _sa_Mapped[datetime] = _sa_mapped_column(
        _sa_DateTime(timezone=True), server_default=_sa_func.now()
    )
    expires_at: _sa_Mapped[datetime] = _sa_mapped_column(
        _sa_DateTime(timezone=True), index=True
    )
    approved_at: _sa_Mapped[datetime | None] = _sa_mapped_column(
        _sa_DateTime(timezone=True), nullable=True
    )


class DeviceSessionDB(_OfficialBase):
    """
    Lightweight per-device session registry for multi-device/Web login.

    Stores a row per (phone, device_id) so the Me-tab can show a
    list of active devices, similar to WeChat's device management.
    """

    __tablename__ = "device_sessions"
    __table_args__ = ({"schema": _OFFICIALS_DB_SCHEMA} if _OFFICIALS_DB_SCHEMA else {})

    id: _sa_Mapped[int] = _sa_mapped_column(
        _sa_Integer, primary_key=True, autoincrement=True
    )
    phone: _sa_Mapped[str] = _sa_mapped_column(_sa_String(32), index=True)
    device_id: _sa_Mapped[str] = _sa_mapped_column(_sa_String(128), index=True)
    device_type: _sa_Mapped[str | None] = _sa_mapped_column(
        _sa_String(32), nullable=True
    )
    device_name: _sa_Mapped[str | None] = _sa_mapped_column(
        _sa_String(128), nullable=True
    )
    platform: _sa_Mapped[str | None] = _sa_mapped_column(
        _sa_String(32), nullable=True
    )
    app_version: _sa_Mapped[str | None] = _sa_mapped_column(
        _sa_String(32), nullable=True
    )
    last_ip: _sa_Mapped[str | None] = _sa_mapped_column(
        _sa_String(64), nullable=True
    )
    user_agent: _sa_Mapped[str | None] = _sa_mapped_column(
        _sa_String(255), nullable=True
    )
    created_at: _sa_Mapped[datetime] = _sa_mapped_column(
        _sa_DateTime(timezone=True), server_default=_sa_func.now()
    )
    last_seen_at: _sa_Mapped[datetime] = _sa_mapped_column(
        _sa_DateTime(timezone=True),
        server_default=_sa_func.now(),
        onupdate=_sa_func.now(),
    )


class CallDB(_OfficialBase):
    """
    DB-backed 1:1 call registry for LiveKit token authorization.

    We treat the call_id as an opaque capability token (unguessable) and use
    it to authorize token minting for exactly two participants (from/to).
    """

    __tablename__ = "calls"
    __table_args__ = (
        _sa_UniqueConstraint("call_id", name="uq_calls_call_id"),
        {"schema": _OFFICIALS_DB_SCHEMA} if _OFFICIALS_DB_SCHEMA else {},
    )

    id: _sa_Mapped[int] = _sa_mapped_column(
        _sa_Integer, primary_key=True, autoincrement=True
    )
    call_id: _sa_Mapped[str] = _sa_mapped_column(
        _sa_String(32), index=True
    )
    room: _sa_Mapped[str] = _sa_mapped_column(
        _sa_String(128), index=True
    )
    from_phone: _sa_Mapped[str] = _sa_mapped_column(
        _sa_String(32), index=True
    )
    to_phone: _sa_Mapped[str] = _sa_mapped_column(
        _sa_String(32), index=True
    )
    mode: _sa_Mapped[str] = _sa_mapped_column(
        _sa_String(16), default="video", index=True
    )
    status: _sa_Mapped[str] = _sa_mapped_column(
        _sa_String(16), default="ringing", index=True
    )
    created_at: _sa_Mapped[datetime] = _sa_mapped_column(
        _sa_DateTime(timezone=True), server_default=_sa_func.now()
    )
    ring_expires_at: _sa_Mapped[datetime] = _sa_mapped_column(
        _sa_DateTime(timezone=True), index=True
    )
    expires_at: _sa_Mapped[datetime] = _sa_mapped_column(
        _sa_DateTime(timezone=True), index=True
    )
    accepted_at: _sa_Mapped[datetime | None] = _sa_mapped_column(
        _sa_DateTime(timezone=True), nullable=True
    )
    ended_at: _sa_Mapped[datetime | None] = _sa_mapped_column(
        _sa_DateTime(timezone=True), nullable=True
    )
    ended_by_phone: _sa_Mapped[str | None] = _sa_mapped_column(
        _sa_String(32), nullable=True
    )


_officials_engine = _sa_create_engine(_OFFICIALS_DB_URL, future=True)
_officials_inited = False


def _officials_session() -> _sa_Session:
    """
    Returns a session for the officials DB.

    In addition to relying on FastAPI's startup hook, this lazily ensures
    that the officials schema exists so that deployments that construct the
    app without running startup events still get the required tables
    (e.g. official_feed_items, official_template_messages).
    """
    global _officials_inited
    if not _officials_inited:
        try:
            # Best-effort; failures are logged inside _officials_startup.
            _officials_startup()  # type: ignore[name-defined]
        except Exception:
            logging.getLogger("shamell.officials").exception(
                "failed to init officials DB from session helper"
            )
        _officials_inited = True
    return _sa_Session(_officials_engine)


class OfficialAccountOut(BaseModel):
    id: str
    kind: str = "service"
    featured: bool = False
    name: str
    name_ar: str | None = None
    avatar_url: str | None = None
    verified: bool = True
    mini_app_id: str | None = None
    description: str | None = None
    chat_peer_id: str | None = None
    category: str | None = None
    city: str | None = None
    address: str | None = None
    opening_hours: str | None = None
    website_url: str | None = None
    qr_payload: str | None = None
    unread_count: int = 0
    last_item: dict[str, Any] | None = None
    followed: bool = True
    menu_items: list[dict[str, Any]] | None = None


class OfficialTemplateMessageIn(BaseModel):
    account_id: str
    user_phone: str
    title: str
    body: str
    deeplink_json: dict[str, Any] | None = None


class OfficialTemplateMessageOut(BaseModel):
    id: int
    account_id: str
    title: str
    body: str
    deeplink_json: dict[str, Any] | None = None
    created_at: str
    read_at: str | None = None


def _update_official_service_session_on_message(
    sender_id: str | None,
    recipient_id: str | None,
    created_at: Any,
) -> None:
    """
    Best-effort hook that keeps OfficialServiceSessionDB in sync with chat traffic.

    When a message goes between a service Official (via chat_peer_id) and a
    user device, we create or update a lightweight session so the operator
    sees it in the customer-service inbox.
    """
    try:
        s_id = (sender_id or "").strip()
        r_id = (recipient_id or "").strip()
        if not s_id or not r_id:
            return
        with _officials_session() as s:
            # Determine which side (if any) is an Official service account.
            off_sender = (
                s.execute(
                    _sa_select(OfficialAccountDB).where(
                        OfficialAccountDB.chat_peer_id == s_id
                    )
                )
                .scalars()
                .first()
            )
            off_recipient = (
                s.execute(
                    _sa_select(OfficialAccountDB).where(
                        OfficialAccountDB.chat_peer_id == r_id
                    )
                )
                .scalars()
                .first()
            )
            official = None
            customer_device_id: str | None = None
            incoming_for_operator = False
            if off_sender and not off_recipient:
                official = off_sender
                customer_device_id = r_id
                incoming_for_operator = False  # operator is sender
            elif off_recipient and not off_sender:
                official = off_recipient
                customer_device_id = s_id
                incoming_for_operator = True  # operator is recipient
            else:
                return
            # Only treat "service" officials as customer-service endpoints.
            try:
                kind_val = (getattr(official, "kind", "") or "").strip().lower()
                if kind_val and kind_val != "service":
                    return
            except Exception:
                return
            if not customer_device_id:
                return
            # Resolve customer phone from DeviceSessionDB.
            dev_row = (
                s.execute(
                    _sa_select(DeviceSessionDB)
                    .where(DeviceSessionDB.device_id == customer_device_id)
                    .order_by(
                        DeviceSessionDB.last_seen_at.desc(),
                        DeviceSessionDB.id.desc(),
                    )
                )
                .scalars()
                .first()
            )
            if not dev_row:
                return
            phone = (getattr(dev_row, "phone", "") or "").strip()
            if not phone:
                return
            # Determine timestamp for last_message_ts.
            ts_val: datetime
            try:
                if isinstance(created_at, datetime):
                    ts_val = created_at
                elif isinstance(created_at, str) and created_at:
                    ts_val = datetime.fromisoformat(
                        created_at.replace("Z", "+00:00")
                    )
                else:
                    ts_val = datetime.now(timezone.utc)
            except Exception:
                ts_val = datetime.now(timezone.utc)
            # Upsert session.
            sess = (
                s.execute(
                    _sa_select(OfficialServiceSessionDB)
                    .where(
                        OfficialServiceSessionDB.account_id == official.id,
                        OfficialServiceSessionDB.customer_phone == phone,
                    )
                    .order_by(
                        OfficialServiceSessionDB.last_message_ts.desc(),
                        OfficialServiceSessionDB.id.desc(),
                    )
                    .limit(1)
                )
                .scalars()
                .first()
            )
            if sess:
                sess.last_message_ts = ts_val
                if incoming_for_operator:
                    sess.unread_by_operator = True
                if not getattr(sess, "chat_peer_id", None):
                    try:
                        sess.chat_peer_id = getattr(official, "chat_peer_id", None)
                    except Exception:
                        pass
                if getattr(sess, "status", "open") != "closed":
                    sess.status = "open"
                s.add(sess)
                s.commit()
            else:
                sess = OfficialServiceSessionDB(
                    account_id=official.id,
                    customer_phone=phone,
                    chat_peer_id=getattr(official, "chat_peer_id", None),
                    status="open",
                    last_message_ts=ts_val,
                    unread_by_operator=incoming_for_operator,
                )
                s.add(sess)
                s.commit()
    except Exception:
        # Never break the main chat flow because of service-session bookkeeping.
        return


class OfficialFeedItemOut(BaseModel):
    id: str
    type: str = "promo"
    title: str | None = None
    snippet: str | None = None
    thumb_url: str | None = None
    ts: str | None = None
    deeplink: dict[str, Any] | None = None


class OfficialLocationOut(BaseModel):
    id: int
    name: str | None = None
    city: str | None = None
    address: str | None = None
    lat: float | None = None
    lon: float | None = None
    phone: str | None = None
    opening_hours: str | None = None


class ChannelItemOut(BaseModel):
    id: str
    title: str | None = None
    snippet: str | None = None
    thumb_url: str | None = None
    ts: str | None = None
    item_type: str | None = None
    official_account_id: str | None = None
    official_name: str | None = None
    official_avatar_url: str | None = None
    official_city: str | None = None
    official_category: str | None = None
    likes: int = 0
    liked_by_me: bool = False
    views: int = 0
    comments: int = 0
    official_is_hot: bool = False
    channel_followers: int = 0
    channel_followed_by_me: bool = False
    gifts: int = 0
    gifts_by_me: int = 0
    score: float | None = None


class ChannelGiftDB(_OfficialBase):
    """
    Simple per-user gift / coin log for Channels.

    This is a lightweight WeChat-style gift system that tracks how
    many "coins" a user sent to a given Channels clip. Money flows
    are intentionally decoupled and can be implemented later via
    the payments layer.
    """

    __tablename__ = "channel_gifts"
    __table_args__ = (
        {"schema": _OFFICIALS_DB_SCHEMA} if _OFFICIALS_DB_SCHEMA else {},
    )

    id: _sa_Mapped[int] = _sa_mapped_column(
        _sa_Integer, primary_key=True, autoincrement=True
    )
    user_key: _sa_Mapped[str] = _sa_mapped_column(_sa_String(128), index=True)
    account_id: _sa_Mapped[str] = _sa_mapped_column(_sa_String(64), index=True)
    item_id: _sa_Mapped[str] = _sa_mapped_column(_sa_String(64), index=True)
    gift_kind: _sa_Mapped[str] = _sa_mapped_column(
        _sa_String(32), default="coin"
    )
    coins: _sa_Mapped[int] = _sa_mapped_column(_sa_Integer, default=1)
    created_at: _sa_Mapped[datetime] = _sa_mapped_column(
        _sa_DateTime(timezone=True), server_default=_sa_func.now()
    )


def _sticker_packs_config() -> list[dict[str, Any]]:
    """
    Static sticker pack catalog for the Shamell sticker store.

    This is intentionally simple and mirrors the built‑in packs
    in the Flutter client so that the marketplace can render a
    WeChat‑like catalog without requiring binary updates for
    basic metadata changes.
    """
    return [
        {
            "id": "classic_smileys",
            "name_en": "Classic smileys",
            "name_ar": "الابتسامات الكلاسيكية",
            "stickers": ["😀", "😂", "🥲", "😅", "😍", "😎", "😭", "😡"],
            "price_cents": 0,
            "currency": DEFAULT_CURRENCY,
            "tags": ["free", "classic", "emoji"],
            "recommended": True,
        },
        {
            "id": "celebration",
            "name_en": "Celebrations",
            "name_ar": "الاحتفالات",
            "stickers": ["🎉", "🎂", "🎁", "🕌", "🕋", "🕯️", "🪅", "🥳"],
            "price_cents": 0,
            "currency": DEFAULT_CURRENCY,
            "tags": ["free", "celebration", "events"],
            "recommended": False,
        },
        {
            "id": "shamell_payments",
            "name_en": "Shamell Pay",
            "name_ar": "شامل باي",
            "stickers": ["💸", "💳", "📲", "🏧", "🧾", "✅"],
            "price_cents": 0,
            "currency": DEFAULT_CURRENCY,
            "tags": ["free", "shamell", "pay", "wallet"],
            "recommended": True,
        },
        {
            "id": "shamell_services",
            "name_en": "Shamell essentials",
            "name_ar": "أساسيات شامل",
            "stickers": ["🚌", "💳", "📲", "✅", "🔔", "🧾"],
            "price_cents": 0,
            "currency": DEFAULT_CURRENCY,
            "tags": ["free", "shamell", "essentials"],
            "recommended": True,
        },
        {
            "id": "daily_reactions",
            "name_en": "Daily reactions",
            "name_ar": "تفاعلات يومية",
            "stickers": ["🤝", "🙏", "🔥", "✅", "❌", "⏳", "⭐", "❤️"],
            "price_cents": 0,
            "currency": DEFAULT_CURRENCY,
            "tags": ["free", "reactions", "emoji"],
            "recommended": False,
        },
    ]


_OFFICIAL_ACCOUNTS: dict[str, OfficialAccountOut] = {
    "shamell_pay": OfficialAccountOut(
        id="shamell_pay",
        kind="service",
        featured=True,
        name="Shamell Pay",
        name_ar="شامل باي",
        avatar_url="/icons/pay.svg",
        verified=True,
        mini_app_id="payments",
        description="Scan & Pay, send money and manage your wallet.",
        chat_peer_id="shamell_pay",
        category="payments",
        city="Damascus",
        website_url="https://pay.shamell.app",
        menu_items=[
            {
                "id": "open_wallet",
                "kind": "mini_app",
                "mini_app_id": "payments",
                "label_en": "Open Wallet",
                "label_ar": "فتح المحفظة",
            }
        ],
    ),
    "shamell_bus": OfficialAccountOut(
        id="shamell_bus",
        kind="service",
        featured=True,
        name="Shamell Bus",
        name_ar="شامل باص",
        avatar_url="/icons/bus.svg",
        verified=True,
        mini_app_id="bus",
        description="Find routes, buy tickets and manage your rides.",
        chat_peer_id="shamell_bus",
        category="transport",
        city="Damascus",
        menu_items=[
            {
                "id": "open_bus",
                "kind": "mini_app",
                "mini_app_id": "bus",
                "label_en": "Open Bus",
                "label_ar": "فتح الباص",
            }
        ],
    ),
}

_OFFICIAL_FEED_SEED: dict[str, list[dict[str, Any]]] = {
    "shamell_pay": [
        {
            "id": "pay_hb_newyear",
            "type": "promo",
            "title": "New Year red packets",
            "snippet": "Send New Year red packets to friends via Shamell Pay.",
            "thumb_url": "/assets/feed/pay_hb.jpg",
            "ts": "2025-01-01T09:00:00Z",
            "deeplink": {"mini_app_id": "payments", "payload": {"section": "redpacket"}},
        },
    ],
    "shamell_bus": [
        {
            "id": "bus_new_routes",
            "type": "promo",
            "title": "New routes this week",
            "snippet": "Check out newly added bus routes and schedules.",
            "thumb_url": "/assets/feed/bus_routes.jpg",
            "ts": "2025-01-06T12:00:00Z",
            "deeplink": {"mini_app_id": "bus", "payload": {"section": "routes"}},
        },
    ],
}

# Per-user follow state: in-memory fallback keyed by sa_cookie.
_OFFICIAL_FOLLOWS: dict[str, set[str]] = {}


def _official_cookie_key(request: Request) -> str:
    cookie = request.headers.get("sa_cookie") or request.cookies.get("sa_cookie") or ""
    if not cookie:
        cookie = "anon"
    return cookie


def _officials_startup() -> None:
    logger = logging.getLogger("shamell.officials")
    try:
        _OfficialBase.metadata.create_all(_officials_engine)
    except Exception:
        logger.exception("failed to init official accounts tables")
        return
    # Best-effort schema upgrade for chat_peer_id and campaign defaults on existing deployments.
    try:
        with _officials_engine.begin() as conn:
            if _OFFICIALS_DB_URL.startswith("sqlite"):
                conn.execute(
                    _sa_text("ALTER TABLE official_accounts ADD COLUMN chat_peer_id VARCHAR(64)")
                )
                conn.execute(
                    _sa_text("ALTER TABLE official_accounts ADD COLUMN category VARCHAR(64)")
                )
                conn.execute(
                    _sa_text("ALTER TABLE official_accounts ADD COLUMN city VARCHAR(64)")
                )
                conn.execute(
                    _sa_text("ALTER TABLE official_accounts ADD COLUMN address VARCHAR(255)")
                )
                conn.execute(
                    _sa_text("ALTER TABLE official_accounts ADD COLUMN opening_hours VARCHAR(255)")
                )
                conn.execute(
                    _sa_text("ALTER TABLE official_accounts ADD COLUMN website_url VARCHAR(255)")
                )
                conn.execute(
                    _sa_text("ALTER TABLE official_accounts ADD COLUMN qr_payload VARCHAR(255)")
                )
                conn.execute(
                    _sa_text("ALTER TABLE official_accounts ADD COLUMN featured BOOLEAN DEFAULT 0")
                )
            else:
                table_name = "official_accounts"
                if _OFFICIALS_DB_SCHEMA:
                    table_name = f"{_OFFICIALS_DB_SCHEMA}.{table_name}"
                conn.execute(
                    _sa_text(
                        f"ALTER TABLE {table_name} ADD COLUMN chat_peer_id VARCHAR(64)"
                    )
                )
                conn.execute(
                    _sa_text(
                        f"ALTER TABLE {table_name} ADD COLUMN category VARCHAR(64)"
                    )
                )
                conn.execute(
                    _sa_text(
                        f"ALTER TABLE {table_name} ADD COLUMN city VARCHAR(64)"
                    )
                )
                conn.execute(
                    _sa_text(
                        f"ALTER TABLE {table_name} ADD COLUMN address VARCHAR(255)"
                    )
                )
                conn.execute(
                    _sa_text(
                        f"ALTER TABLE {table_name} ADD COLUMN opening_hours VARCHAR(255)"
                    )
                )
                conn.execute(
                    _sa_text(
                        f"ALTER TABLE {table_name} ADD COLUMN website_url VARCHAR(255)"
                    )
                )
                conn.execute(
                    _sa_text(
                        f"ALTER TABLE {table_name} ADD COLUMN qr_payload VARCHAR(255)"
                    )
                )
                conn.execute(
                    _sa_text(
                        f"ALTER TABLE {table_name} ADD COLUMN featured BOOLEAN DEFAULT FALSE"
                    )
                )
            # Best-effort schema upgrade for auth_sessions/device_login_challenges (new auth persistence layer).
            try:
                if _OFFICIALS_DB_URL.startswith("sqlite"):
                    conn.execute(
                        _sa_text("ALTER TABLE auth_sessions ADD COLUMN device_id VARCHAR(128)")
                    )
                else:
                    sess_table = "auth_sessions"
                    if _OFFICIALS_DB_SCHEMA:
                        sess_table = f"{_OFFICIALS_DB_SCHEMA}.{sess_table}"
                    conn.execute(
                        _sa_text(
                            f"ALTER TABLE {sess_table} ADD COLUMN device_id VARCHAR(128)"
                        )
                    )
            except Exception:
                pass
            try:
                if _OFFICIALS_DB_URL.startswith("sqlite"):
                    conn.execute(
                        _sa_text(
                            "ALTER TABLE device_login_challenges ADD COLUMN device_id VARCHAR(128)"
                        )
                    )
                else:
                    dl_table = "device_login_challenges"
                    if _OFFICIALS_DB_SCHEMA:
                        dl_table = f"{_OFFICIALS_DB_SCHEMA}.{dl_table}"
                    conn.execute(
                        _sa_text(
                            f"ALTER TABLE {dl_table} ADD COLUMN device_id VARCHAR(128)"
                        )
                    )
            except Exception:
                pass
            # Best-effort schema upgrade for MiniAppDB.moments_shares and runtime_app_id.
            if _OFFICIALS_DB_URL.startswith("sqlite"):
                try:
                    conn.execute(
                        _sa_text(
                            "ALTER TABLE mini_apps ADD COLUMN moments_shares INTEGER DEFAULT 0"
                        )
                    )
                except Exception:
                    pass
                try:
                    conn.execute(
                        _sa_text(
                            "ALTER TABLE mini_apps ADD COLUMN runtime_app_id VARCHAR(64)"
                        )
                    )
                except Exception:
                    pass
            # Best-effort schema upgrade for MiniProgramDB.actions_json on existing deployments.
            try:
                if _OFFICIALS_DB_URL.startswith("sqlite"):
                    conn.execute(
                        _sa_text(
                            "ALTER TABLE mini_programs ADD COLUMN actions_json TEXT"
                        )
                    )
                else:
                    prog_table = "mini_programs"
                    if _OFFICIALS_DB_SCHEMA:
                        prog_table = f"{_OFFICIALS_DB_SCHEMA}.{prog_table}"
                    conn.execute(
                        _sa_text(
                            f"ALTER TABLE {prog_table} ADD COLUMN actions_json TEXT"
                        )
                    )
            except Exception:
                pass
            # Best-effort schema upgrade for ChannelFollowDB on existing deployments.
            try:
                table_name = "channel_follows"
                if _OFFICIALS_DB_SCHEMA:
                    table_name = f"{_OFFICIALS_DB_SCHEMA}.{table_name}"
                conn.execute(
                    _sa_text(
                        f"CREATE TABLE IF NOT EXISTS {table_name} ("
                        "id INTEGER PRIMARY KEY AUTOINCREMENT, "
                        "user_key VARCHAR(128) NOT NULL, "
                        "account_id VARCHAR(64) NOT NULL, "
                        "created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP, "
                        "CONSTRAINT uq_channel_follows_user_account UNIQUE (user_key, account_id)"
                        ")"
                    )
                )
            except Exception:
                pass
            # Best-effort schema upgrade for ChannelGiftDB on existing deployments.
            try:
                table_name = "channel_gifts"
                if _OFFICIALS_DB_SCHEMA:
                    table_name = f"{_OFFICIALS_DB_SCHEMA}.{table_name}"
                conn.execute(
                    _sa_text(
                        f"CREATE TABLE IF NOT EXISTS {table_name} ("
                        "id INTEGER PRIMARY KEY AUTOINCREMENT, "
                        "user_key VARCHAR(128) NOT NULL, "
                        "account_id VARCHAR(64) NOT NULL, "
                        "item_id VARCHAR(64) NOT NULL, "
                        "gift_kind VARCHAR(32) DEFAULT 'coin', "
                        "coins INTEGER DEFAULT 1, "
                        "created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP"
                        ")"
                    )
                )
            except Exception:
                pass
            # Best-effort schema upgrade for OfficialFeedItemDB on existing deployments.
            try:
                table_name = "official_feed_items"
                if _OFFICIALS_DB_SCHEMA:
                    table_name = f"{_OFFICIALS_DB_SCHEMA}.{table_name}"
                if _OFFICIALS_DB_URL.startswith("sqlite"):
                    conn.execute(
                        _sa_text(
                            f"CREATE TABLE IF NOT EXISTS {table_name} ("
                            "id INTEGER PRIMARY KEY AUTOINCREMENT, "
                            "account_id VARCHAR(64) NOT NULL, "
                            "slug VARCHAR(64) NOT NULL UNIQUE, "
                            "type VARCHAR(16) DEFAULT 'promo', "
                            "title VARCHAR(255), "
                            "snippet VARCHAR(512), "
                            "thumb_url VARCHAR(255), "
                            "ts TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP, "
                            "deeplink_json TEXT"
                            ")"
                        )
                    )
                else:
                    conn.execute(
                        _sa_text(
                            f"CREATE TABLE IF NOT EXISTS {table_name} ("
                            "id SERIAL PRIMARY KEY, "
                            "account_id VARCHAR(64) NOT NULL, "
                            "slug VARCHAR(64) NOT NULL UNIQUE, "
                            "type VARCHAR(16) DEFAULT 'promo', "
                            "title VARCHAR(255), "
                            "snippet VARCHAR(512), "
                            "thumb_url VARCHAR(255), "
                            "ts TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP, "
                            "deeplink_json TEXT"
                            ")"
                        )
                    )
            except Exception:
                pass
            # Best-effort schema upgrade for OfficialServiceSessionDB on existing deployments.
            try:
                table_name = "official_service_sessions"
                if _OFFICIALS_DB_SCHEMA:
                    table_name = f"{_OFFICIALS_DB_SCHEMA}.{table_name}"
                conn.execute(
                    _sa_text(
                        f"CREATE TABLE IF NOT EXISTS {table_name} ("
                        "id INTEGER PRIMARY KEY AUTOINCREMENT, "
                        "account_id VARCHAR(64) NOT NULL, "
                        "customer_phone VARCHAR(32) NOT NULL, "
                        "chat_peer_id VARCHAR(64), "
                        "status VARCHAR(16) DEFAULT 'open', "
                        "last_message_ts TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP, "
                        "unread_by_operator BOOLEAN DEFAULT TRUE"
                        ")"
                    )
                )
            except Exception:
                pass
            # Best-effort schema upgrade for OfficialTemplateMessageDB on existing deployments.
            try:
                table_name = "official_template_messages"
                if _OFFICIALS_DB_SCHEMA:
                    table_name = f"{_OFFICIALS_DB_SCHEMA}.{table_name}"
                if _OFFICIALS_DB_URL.startswith("sqlite"):
                    conn.execute(
                        _sa_text(
                            f"CREATE TABLE IF NOT EXISTS {table_name} ("
                            "id INTEGER PRIMARY KEY AUTOINCREMENT, "
                            "account_id VARCHAR(64) NOT NULL, "
                            "user_phone VARCHAR(32) NOT NULL, "
                            "title VARCHAR(200) NOT NULL, "
                            "body TEXT NOT NULL, "
                            "deeplink_json TEXT, "
                            "created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP, "
                            "read_at TIMESTAMP WITH TIME ZONE"
                            ")"
                        )
                    )
                else:
                    conn.execute(
                        _sa_text(
                            f"CREATE TABLE IF NOT EXISTS {table_name} ("
                            "id SERIAL PRIMARY KEY, "
                            "account_id VARCHAR(64) NOT NULL, "
                            "user_phone VARCHAR(32) NOT NULL, "
                            "title VARCHAR(200) NOT NULL, "
                            "body TEXT NOT NULL, "
                            "deeplink_json TEXT, "
                            "created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP, "
                            "read_at TIMESTAMP WITH TIME ZONE"
                            ")"
                        )
                    )
            except Exception:
                pass
            # Best-effort schema upgrade for MiniProgramDB.usage_score, rating and scopes/review_status.
            try:
                if _OFFICIALS_DB_URL.startswith("sqlite"):
                    conn.execute(
                        _sa_text(
                            "ALTER TABLE mini_programs ADD COLUMN usage_score INTEGER DEFAULT 0"
                        )
                    )
                    conn.execute(
                        _sa_text(
                            "ALTER TABLE mini_programs ADD COLUMN rating REAL"
                        )
                    )
                    conn.execute(
                        _sa_text(
                            "ALTER TABLE mini_programs ADD COLUMN scopes_json TEXT"
                        )
                    )
                    conn.execute(
                        _sa_text(
                            "ALTER TABLE mini_programs ADD COLUMN review_status VARCHAR(32) DEFAULT 'draft'"
                        )
                    )
                else:
                    prog_table = "mini_programs"
                    if _OFFICIALS_DB_SCHEMA:
                        prog_table = f"{_OFFICIALS_DB_SCHEMA}.{prog_table}"
                    conn.execute(
                        _sa_text(
                            f"ALTER TABLE {prog_table} ADD COLUMN usage_score INTEGER DEFAULT 0"
                        )
                    )
                    conn.execute(
                        _sa_text(
                            f"ALTER TABLE {prog_table} ADD COLUMN rating DOUBLE PRECISION"
                        )
                    )
                    conn.execute(
                        _sa_text(
                            f"ALTER TABLE {prog_table} ADD COLUMN scopes_json TEXT"
                        )
                    )
                    conn.execute(
                        _sa_text(
                            f"ALTER TABLE {prog_table} ADD COLUMN review_status VARCHAR(32) DEFAULT 'draft'"
                        )
                    )
            except Exception:
                pass
            else:
                mini_table = "mini_apps"
                if _OFFICIALS_DB_SCHEMA:
                    mini_table = f"{_OFFICIALS_DB_SCHEMA}.{mini_table}"
                try:
                    conn.execute(
                        _sa_text(
                            f"ALTER TABLE {mini_table} ADD COLUMN moments_shares INTEGER DEFAULT 0"
                        )
                    )
                except Exception:
                    pass
                try:
                    conn.execute(
                        _sa_text(
                            f"ALTER TABLE {mini_table} ADD COLUMN runtime_app_id VARCHAR(64)"
                        )
                    )
                except Exception:
                    pass
            # Red-packet campaign defaults (amount/count/note) – best-effort.
            if _OFFICIALS_DB_URL.startswith("sqlite"):
                try:
                    conn.execute(
                        _sa_text(
                            "ALTER TABLE redpacket_campaigns ADD COLUMN default_amount_cents INTEGER"
                        )
                    )
                except Exception:
                    pass
                try:
                    conn.execute(
                        _sa_text(
                            "ALTER TABLE redpacket_campaigns ADD COLUMN default_count INTEGER"
                        )
                    )
                except Exception:
                    pass
                try:
                    conn.execute(
                        _sa_text(
                            "ALTER TABLE redpacket_campaigns ADD COLUMN note VARCHAR(255)"
                        )
                    )
                except Exception:
                    pass
            else:
                camp_table = "redpacket_campaigns"
                if _OFFICIALS_DB_SCHEMA:
                    camp_table = f"{_OFFICIALS_DB_SCHEMA}.{camp_table}"
                try:
                    conn.execute(
                        _sa_text(
                            f"ALTER TABLE {camp_table} ADD COLUMN default_amount_cents INTEGER"
                        )
                    )
                except Exception:
                    pass
                try:
                    conn.execute(
                        _sa_text(
                            f"ALTER TABLE {camp_table} ADD COLUMN note VARCHAR(255)"
                        )
                    )
                except Exception:
                    pass
                try:
                    conn.execute(
                        _sa_text(
                            f"ALTER TABLE {camp_table} ADD COLUMN default_count INTEGER"
                        )
                    )
                except Exception:
                    pass
    except Exception:
        # Ignore if column already exists or migration fails; model uses nullable field.
        pass

    # Ensure auth persistence tables stay forward-compatible even if earlier
    # best-effort ALTERs failed (e.g. because some columns already existed).
    try:
        with _officials_engine.begin() as conn:
            if _OFFICIALS_DB_URL.startswith("sqlite"):
                try:
                    conn.execute(
                        _sa_text("ALTER TABLE auth_sessions ADD COLUMN device_id VARCHAR(128)")
                    )
                except Exception:
                    pass
                try:
                    conn.execute(
                        _sa_text(
                            "ALTER TABLE device_login_challenges ADD COLUMN device_id VARCHAR(128)"
                        )
                    )
                except Exception:
                    pass
            else:
                sess_table = "auth_sessions"
                if _OFFICIALS_DB_SCHEMA:
                    sess_table = f"{_OFFICIALS_DB_SCHEMA}.{sess_table}"
                dl_table = "device_login_challenges"
                if _OFFICIALS_DB_SCHEMA:
                    dl_table = f"{_OFFICIALS_DB_SCHEMA}.{dl_table}"
                try:
                    conn.execute(
                        _sa_text(
                            f"ALTER TABLE {sess_table} ADD COLUMN IF NOT EXISTS device_id VARCHAR(128)"
                        )
                    )
                except Exception:
                    pass
                try:
                    conn.execute(
                        _sa_text(
                            f"ALTER TABLE {dl_table} ADD COLUMN IF NOT EXISTS device_id VARCHAR(128)"
                        )
                    )
                except Exception:
                    pass
    except Exception:
        pass
    # Seed built-in Official accounts and their feed items using a direct
    # SQLAlchemy Session bound to _officials_engine. We deliberately avoid
    # calling _officials_session() here to prevent recursive startup calls,
    # because _officials_session() itself triggers _officials_startup() on
    # first use.
    try:
        with _sa_Session(_officials_engine) as s:
            existing_ids = set(s.execute(_sa_select(OfficialAccountDB.id)).scalars().all())
            for acc in _OFFICIAL_ACCOUNTS.values():
                if acc.id in existing_ids:
                    continue
                row = OfficialAccountDB(
                    id=acc.id,
                    kind=acc.kind,
                    name=acc.name,
                    name_ar=acc.name_ar,
                    avatar_url=acc.avatar_url,
                    verified=acc.verified,
                    mini_app_id=acc.mini_app_id,
                    description=acc.description,
                    chat_peer_id=acc.chat_peer_id,
                    enabled=True,
                    official=True,
                )
                s.add(row)
            for account_id, items in _OFFICIAL_FEED_SEED.items():
                for item in items:
                    slug = item.get("id")
                    if not slug:
                        continue
                    exists = s.execute(
                        _sa_select(OfficialFeedItemDB).where(OfficialFeedItemDB.slug == slug)
                    ).scalars().first()
                    if exists:
                        continue
                    ts_val = None
                    ts_str = item.get("ts")
                    if ts_str:
                        try:
                            ts_val = datetime.fromisoformat(ts_str.replace("Z", "+00:00"))
                        except Exception:
                            ts_val = None
                    s.add(
                        OfficialFeedItemDB(
                            account_id=account_id,
                            slug=slug,
                            type=item.get("type") or "promo",
                            title=item.get("title"),
                            snippet=item.get("snippet"),
                            thumb_url=item.get("thumb_url"),
                            ts=ts_val,
                            deeplink_json=_json.dumps(item.get("deeplink"))
                            if item.get("deeplink") is not None
                            else None,
                        )
                    )
            s.commit()
    except Exception:
        logger.exception("failed to seed official accounts")


app.router.on_startup.append(_officials_startup)


def _official_menu_items_for(acc: OfficialAccountDB) -> list[dict[str, Any]] | None:
    """
    Lightweight, mini_app_id-based menu config for Official accounts.
    This avoids schema changes by deriving a simple menu from the mini_app_id.
    """
    mid = (acc.mini_app_id or "").strip()
    if not mid:
        return None
    items: list[dict[str, Any]] = []
    if mid in ("payments", "alias", "merchant"):
        items.append(
            {
                "id": "open_wallet",
                "kind": "mini_app",
                "mini_app_id": "payments",
                "label_en": "Open Wallet",
                "label_ar": "فتح المحفظة",
            }
        )
    elif mid == "bus":
        items.append(
            {
                "id": "open_bus",
                "kind": "mini_app",
                "mini_app_id": "bus",
                "label_en": "Open Bus",
                "label_ar": "فتح الباص",
            }
        )
    return items or None


class OfficialAccountAdminIn(BaseModel):
    id: str
    kind: str = "service"
    name: str
    name_ar: str | None = None
    avatar_url: str | None = None
    verified: bool = True
    mini_app_id: str | None = None
    description: str | None = None
    chat_peer_id: str | None = None
    category: str | None = None
    city: str | None = None
    address: str | None = None
    opening_hours: str | None = None
    website_url: str | None = None
    qr_payload: str | None = None
    featured: bool = False
    enabled: bool = True
    official: bool = True


class OfficialAccountSelfRegisterIn(BaseModel):
    """
    Lightweight payload for self‑service Official account registration.

    Merchants can propose a new WeChat‑style Official account; the
    request is stored separately and can later be reviewed and
    approved by ops before the actual OfficialAccountDB entry is
    created.
    """

    account_id: str
    kind: str = "service"
    name: str
    name_ar: str | None = None
    description: str | None = None
    category: str | None = None
    city: str | None = None
    address: str | None = None
    opening_hours: str | None = None
    website_url: str | None = None
    mini_app_id: str | None = None
    owner_name: str | None = None
    contact_phone: str | None = None
    contact_email: str | None = None


class OfficialAccountRequestOut(BaseModel):
    id: int
    account_id: str
    kind: str
    name: str
    name_ar: str | None = None
    description: str | None = None
    category: str | None = None
    city: str | None = None
    address: str | None = None
    opening_hours: str | None = None
    website_url: str | None = None
    mini_app_id: str | None = None
    owner_name: str | None = None
    contact_phone: str | None = None
    contact_email: str | None = None
    requester_phone: str | None = None
    status: str
    created_at: datetime | None = None
    updated_at: datetime | None = None


class OfficialNotificationIn(BaseModel):
    mode: str | None = None


class OfficialAutoReplyIn(BaseModel):
    kind: str = "welcome"
    keyword: str | None = None
    text: str
    enabled: bool = True


class OfficialAutoReplyOut(BaseModel):
    id: int
    account_id: str
    kind: str = "welcome"
    keyword: str | None = None
    text: str
    enabled: bool = True


class OfficialFeedItemAdminIn(BaseModel):
    account_id: str
    id: str
    type: str = "promo"
    title: str | None = None
    snippet: str | None = None
    thumb_url: str | None = None
    ts: str | None = None
    deeplink: dict[str, Any] | None = None


class OfficialLocationAdminIn(BaseModel):
    account_id: str
    name: str | None = None
    city: str | None = None
    address: str | None = None
    lat: float | None = None
    lon: float | None = None
    phone: str | None = None
    opening_hours: str | None = None


class RedPacketCampaignAdminIn(BaseModel):
    id: str
    account_id: str
    title: str
    active: bool = True
    default_amount_cents: int | None = None
    default_count: int | None = None
    note: str | None = None


class RedPacketCampaignTemplateOut(BaseModel):
    campaign_id: str
    account_id: str
    title: str
    text_en: str
    text_ar: str


class RedPacketCampaignTopMomentOut(BaseModel):
    post_id: int
    text: str | None = None
    ts: str | None = None
    likes: int = 0
    comments: int = 0
    score: float = 0.0


class MiniProgramActionConfig(BaseModel):
    """
    Single action/button in a Mini‑Program manifest.

    kind:
      - open_mod: open a Shamell module (wallet, bus, ...)
      - open_url: open external URL
      - close: close the Mini‑Program shell
    """

    id: str
    label_en: str
    label_ar: str
    kind: str = "open_mod"
    mod_id: str | None = None
    url: str | None = None


class MiniProgramAdminIn(BaseModel):
    """
    Admin payload for registering a Mini‑Program in the catalogue.

    This is deliberately minimal and focuses on identifiers and
    ownership; versioning is handled via MiniProgramVersionIn.
    """

    app_id: str
    title_en: str
    title_ar: str | None = None
    description_en: str | None = None
    description_ar: str | None = None
    owner_name: str | None = None
    owner_contact: str | None = None
    actions: list[MiniProgramActionConfig] | None = None
    scopes: list[str] | None = None


class MiniProgramVersionIn(BaseModel):
    """
    Admin payload for registering a new Mini‑Program version.
    """

    version: str
    bundle_url: str | None = None
    changelog_en: str | None = None
    changelog_ar: str | None = None


class MiniProgramReleaseIn(BaseModel):
    """
    Marks a specific Mini‑Program version as released on a channel.
    """

    version: str
    channel: str | None = "prod"


class MiniAppAdminIn(BaseModel):
    app_id: str
    title_en: str
    title_ar: str | None = None
    category_en: str | None = None
    category_ar: str | None = None
    description: str | None = None
    icon: str | None = None
    official: bool = False
    enabled: bool = True
    beta: bool = False
    runtime_app_id: str | None = None
    rating: float | None = None
    usage_score: int | None = None


class MiniAppRatingIn(BaseModel):
    rating: int


class MiniProgramRatingIn(BaseModel):
    rating: int


class MiniProgramSelfRegisterIn(BaseModel):
    """
    Lightweight payload for third‑party Mini‑Program self‑registration.

    Developers can register basic metadata for their Mini‑Program; the
    entry starts in status "draft" and can later be reviewed and
    activated by the Shamell ops team via the admin console.
    """

    app_id: str
    title_en: str
    title_ar: str | None = None
    description_en: str | None = None
    description_ar: str | None = None
    owner_name: str | None = None
    owner_contact: str | None = None
    scopes: list[str] | None = None


class MiniProgramSelfVersionIn(BaseModel):
    """
    Minimal payload for developers to propose a new Mini‑Program version.

    These versions are stored in MiniProgramVersionDB but do not
    automatically create a Release; publishing remains an ops action.
    """

    version: str
    bundle_url: str
    changelog_en: str | None = None
    changelog_ar: str | None = None


class ChannelCommentIn(BaseModel):
    text: str


class ChannelUploadIn(BaseModel):
    """
    Lightweight payload for creator-style Channels uploads.

    Creates a new OfficialFeedItemDB row of type "clip" (or "live"
    when requested) for a given Official account. Intended as a
    WeChat-like creator tool for merchants and ops; binary media
    is referenced via thumb_url / deeplink rather than uploaded
    directly. The same payload is also used for the lightweight
    /channels/live/start endpoint.
    """

    official_account_id: str
    title: str | None = None
    snippet: str | None = None
    thumb_url: str | None = None
    deeplink: dict[str, Any] | None = None
    # Optional WeChat-style livestream flag – when true the feed
    # item is stored as type "live" instead of a normal clip.
    is_live: bool | None = None


@app.post("/channels/live/start", response_class=JSONResponse)
def channels_live_start(request: Request, body: ChannelUploadIn) -> dict[str, Any]:
    """
    Convenience endpoint to start a Channels livestream.

    This behaves like /channels/upload but always stores the
    item as type "live" so that the Channels feed and Official
    feed can highlight it as a live session, similar to WeChat
    Channels "Go Live".
    """

    # Force live type regardless of caller-provided flag to keep
    # the semantics explicit for this endpoint.
    body.is_live = True
    return channels_upload(request, body)


@app.get("/admin/official_accounts", response_class=JSONResponse)
def admin_official_accounts_list(request: Request, kind: str | None = None) -> dict[str, Any]:
    _require_admin_v2(request)
    with _officials_session() as s:
        stmt = _sa_select(OfficialAccountDB)
        if kind:
            stmt = stmt.where(OfficialAccountDB.kind == kind)
        rows = s.execute(stmt.order_by(OfficialAccountDB.id)).scalars().all()
        items: list[dict[str, Any]] = []
        for acc in rows:
            items.append(
                {
                    "id": acc.id,
                    "kind": acc.kind,
                    "name": acc.name,
                    "name_ar": acc.name_ar,
                    "avatar_url": acc.avatar_url,
                    "verified": acc.verified,
                    "mini_app_id": acc.mini_app_id,
                    "description": acc.description,
                    "chat_peer_id": getattr(acc, "chat_peer_id", None),
                    "category": getattr(acc, "category", None),
                    "city": getattr(acc, "city", None),
                    "address": getattr(acc, "address", None),
                    "opening_hours": getattr(acc, "opening_hours", None),
                    "website_url": getattr(acc, "website_url", None),
                    "qr_payload": getattr(acc, "qr_payload", None),
                    "featured": getattr(acc, "featured", False),
                    "enabled": acc.enabled,
                    "official": acc.official,
                    "created_at": getattr(acc, "created_at", None),
                    "updated_at": getattr(acc, "updated_at", None),
                }
            )
    return {"accounts": items}


@app.get("/admin/official_account_requests", response_class=JSONResponse)
def admin_official_account_requests_list(
    request: Request, status: str | None = None
) -> dict[str, Any]:
    """
    Lists self‑service Official account registration requests (admin only).

    Ops can filter by status (submitted/approved/rejected) and use the
    separate approve/reject endpoints to drive verification, ähnlich
    zum Mini‑Programs‑Review‑Center.
    """
    _require_admin_v2(request)
    try:
        with _officials_session() as s:
            stmt = _sa_select(OfficialAccountRequestDB)
            if status:
                stmt = stmt.where(OfficialAccountRequestDB.status == status)
            rows = (
                s.execute(
                    stmt.order_by(OfficialAccountRequestDB.created_at.desc())
                )
                .scalars()
                .all()
            )
            items: list[dict[str, Any]] = []
            for row in rows:
                items.append(
                    OfficialAccountRequestOut(
                        id=row.id,
                        account_id=row.account_id,
                        kind=row.kind,
                        name=row.name,
                        name_ar=row.name_ar,
                        description=row.description,
                        category=row.category,
                        city=row.city,
                        address=row.address,
                        opening_hours=row.opening_hours,
                        website_url=row.website_url,
                        mini_app_id=row.mini_app_id,
                        owner_name=row.owner_name,
                        contact_phone=row.contact_phone,
                        contact_email=row.contact_email,
                        requester_phone=row.requester_phone,
                        status=row.status,
                        created_at=row.created_at,
                        updated_at=row.updated_at,
                    ).dict()
                )
        return {"requests": items}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/admin/official_accounts", response_class=JSONResponse)
def admin_official_accounts_create(request: Request, body: OfficialAccountAdminIn) -> dict[str, Any]:
    _require_admin_v2(request)
    data = body
    with _officials_session() as s:
        existing = s.get(OfficialAccountDB, data.id)
        if existing:
            raise HTTPException(status_code=409, detail="official account already exists")
        row = OfficialAccountDB(
            id=data.id,
            kind=data.kind,
            name=data.name,
            name_ar=data.name_ar,
            avatar_url=data.avatar_url,
            verified=data.verified,
            mini_app_id=data.mini_app_id,
            description=data.description,
            chat_peer_id=data.chat_peer_id,
            category=data.category,
            city=data.city,
            address=data.address,
            opening_hours=data.opening_hours,
            website_url=data.website_url,
            qr_payload=data.qr_payload,
            featured=data.featured,
            enabled=data.enabled,
            official=data.official,
        )
        s.add(row)
        s.commit()
        s.refresh(row)
        return {
            "id": row.id,
            "kind": row.kind,
            "name": row.name,
            "name_ar": row.name_ar,
            "avatar_url": row.avatar_url,
            "verified": row.verified,
            "mini_app_id": row.mini_app_id,
            "description": row.description,
            "chat_peer_id": getattr(row, "chat_peer_id", None),
            "category": getattr(row, "category", None),
            "city": getattr(row, "city", None),
            "address": getattr(row, "address", None),
            "opening_hours": getattr(row, "opening_hours", None),
            "website_url": getattr(row, "website_url", None),
            "qr_payload": getattr(row, "qr_payload", None),
            "featured": getattr(row, "featured", False),
            "enabled": row.enabled,
            "official": row.official,
        }


@app.patch("/admin/official_accounts/{account_id}", response_class=JSONResponse)
def admin_official_accounts_update(account_id: str, request: Request, body: dict[str, Any]) -> dict[str, Any]:
    _require_admin_v2(request)
    if not isinstance(body, dict):
        body = {}
    allowed_fields = {
        "kind",
        "name",
        "name_ar",
        "avatar_url",
        "verified",
        "mini_app_id",
        "description",
        "chat_peer_id",
        "category",
        "city",
        "address",
        "opening_hours",
        "website_url",
        "qr_payload",
        "featured",
        "enabled",
        "official",
    }
    with _officials_session() as s:
        row = s.get(OfficialAccountDB, account_id)
        if not row:
            raise HTTPException(status_code=404, detail="official account not found")
        for k, v in body.items():
            if k in allowed_fields:
                setattr(row, k, v)
        s.add(row)
        s.commit()
        s.refresh(row)
        return {
            "id": row.id,
            "kind": row.kind,
            "name": row.name,
            "name_ar": row.name_ar,
            "avatar_url": row.avatar_url,
            "verified": row.verified,
            "mini_app_id": row.mini_app_id,
            "description": row.description,
            "chat_peer_id": getattr(row, "chat_peer_id", None),
            "category": getattr(row, "category", None),
            "city": getattr(row, "city", None),
            "address": getattr(row, "address", None),
            "opening_hours": getattr(row, "opening_hours", None),
            "website_url": getattr(row, "website_url", None),
            "qr_payload": getattr(row, "qr_payload", None),
            "featured": getattr(row, "featured", False),
            "enabled": row.enabled,
            "official": row.official,
        }


@app.delete("/admin/official_accounts/{account_id}", response_class=JSONResponse)
def admin_official_accounts_delete(account_id: str, request: Request) -> dict[str, Any]:
    _require_admin_v2(request)
    with _officials_session() as s:
        row = s.get(OfficialAccountDB, account_id)
        if not row:
            raise HTTPException(status_code=404, detail="official account not found")
        s.delete(row)
        s.commit()
    return {"status": "ok"}


@app.post(
    "/admin/official_account_requests/{request_id}/approve",
    response_class=JSONResponse,
)
def admin_official_account_request_approve(
    request_id: int, request: Request
) -> dict[str, Any]:
    """
    Approves a self‑service Official account request and, if needed,
    creates the corresponding OfficialAccountDB entry.

    The created account is enabled and verified but marked as
    partner/third‑party (official=False) by default; Ops can later
    adjust flags via the Official‑Admin‑Konsole.
    """
    _require_admin_v2(request)
    try:
        with _officials_session() as s:
            req_row = s.get(OfficialAccountRequestDB, request_id)
            if not req_row:
                raise HTTPException(status_code=404, detail="request not found")
            # Ensure the target account exists or create it.
            acc_row = s.get(OfficialAccountDB, req_row.account_id)
            if not acc_row:
                kind = (req_row.kind or "service").strip() or "service"
                # Only accept basic kinds from self‑service; admin can
                # later reclassify (merchant/brand/gov).
                if kind not in {"service", "subscription"}:
                    kind = "service"
                acc_row = OfficialAccountDB(
                    id=req_row.account_id,
                    kind=kind,
                    name=req_row.name,
                    name_ar=req_row.name_ar,
                    description=req_row.description,
                    mini_app_id=req_row.mini_app_id,
                    category=req_row.category,
                    city=req_row.city,
                    address=req_row.address,
                    opening_hours=req_row.opening_hours,
                    website_url=req_row.website_url,
                    verified=True,
                    enabled=True,
                    official=False,
                )
                s.add(acc_row)
            req_row.status = "approved"
            s.add(req_row)
            s.commit()
            s.refresh(req_row)
            try:
                emit_event(
                    "officials",
                    "request_approved",
                    {
                        "request_id": req_row.id,
                        "account_id": req_row.account_id,
                        "requester_phone": req_row.requester_phone,
                    },
                )
            except Exception:
                pass
            out = OfficialAccountRequestOut(
                id=req_row.id,
                account_id=req_row.account_id,
                kind=req_row.kind,
                name=req_row.name,
                name_ar=req_row.name_ar,
                description=req_row.description,
                category=req_row.category,
                city=req_row.city,
                address=req_row.address,
                opening_hours=req_row.opening_hours,
                website_url=req_row.website_url,
                mini_app_id=req_row.mini_app_id,
                owner_name=req_row.owner_name,
                contact_phone=req_row.contact_phone,
                contact_email=req_row.contact_email,
                requester_phone=req_row.requester_phone,
                status=req_row.status,
                created_at=req_row.created_at,
                updated_at=req_row.updated_at,
            )
            return out.dict()
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post(
    "/admin/official_account_requests/{request_id}/reject",
    response_class=JSONResponse,
)
def admin_official_account_request_reject(
    request_id: int, request: Request
) -> dict[str, Any]:
    """
    Marks a self‑service Official account request as rejected.

    Does not delete any existing OfficialAccountDB entries – this is
    purely a review/verification decision.
    """
    _require_admin_v2(request)
    try:
        with _officials_session() as s:
            req_row = s.get(OfficialAccountRequestDB, request_id)
            if not req_row:
                raise HTTPException(status_code=404, detail="request not found")
            req_row.status = "rejected"
            s.add(req_row)
            s.commit()
            s.refresh(req_row)
            try:
                emit_event(
                    "officials",
                    "request_rejected",
                    {
                        "request_id": req_row.id,
                        "account_id": req_row.account_id,
                        "requester_phone": req_row.requester_phone,
                    },
                )
            except Exception:
                pass
            out = OfficialAccountRequestOut(
                id=req_row.id,
                account_id=req_row.account_id,
                kind=req_row.kind,
                name=req_row.name,
                name_ar=req_row.name_ar,
                description=req_row.description,
                category=req_row.category,
                city=req_row.city,
                address=req_row.address,
                opening_hours=req_row.opening_hours,
                website_url=req_row.website_url,
                mini_app_id=req_row.mini_app_id,
                owner_name=req_row.owner_name,
                contact_phone=req_row.contact_phone,
                contact_email=req_row.contact_email,
                requester_phone=req_row.requester_phone,
                status=req_row.status,
                created_at=req_row.created_at,
                updated_at=req_row.updated_at,
            )
            return out.dict()
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/admin/official_accounts/{account_id}/auto_replies", response_class=JSONResponse)
def admin_official_auto_replies_list(account_id: str, request: Request) -> dict[str, Any]:
    """
    Lists all auto‑reply rules for a single Official account.

    This is used by the in‑app owner console to configure welcome
    messages and, in the future, keyword‑based replies.
    """

    _require_admin_v2(request)
    with _officials_session() as s:
        acc = s.get(OfficialAccountDB, account_id)
        if not acc:
            raise HTTPException(status_code=404, detail="official account not found")
        stmt = _sa_select(OfficialAutoReplyDB).where(
            OfficialAutoReplyDB.account_id == account_id
        ).order_by(OfficialAutoReplyDB.id.asc())
        rows = s.execute(stmt).scalars().all()
        rules: list[dict[str, Any]] = []
        for row in rows:
            rules.append(
                {
                    "id": row.id,
                    "account_id": row.account_id,
                    "kind": row.kind,
                    "keyword": row.keyword,
                    "text": row.text,
                    "enabled": bool(row.enabled),
                }
            )
    return {"rules": rules}


@app.post("/admin/official_accounts/{account_id}/auto_replies", response_class=JSONResponse)
def admin_official_auto_replies_create(
    account_id: str, request: Request, body: OfficialAutoReplyIn
) -> dict[str, Any]:
    """
    Creates a single auto‑reply rule for an Official account.

    For now the primary use‑case is a "welcome" style message that
    can be surfaced in chat when a user first opens a conversation
    with the Official account.
    """

    _require_admin_v2(request)
    text = (body.text or "").strip()
    if not text:
        raise HTTPException(status_code=400, detail="text is required")
    kind = (body.kind or "welcome").strip().lower() or "welcome"
    keyword = (body.keyword or "").strip() or None
    with _officials_session() as s:
        acc = s.get(OfficialAccountDB, account_id)
        if not acc:
            raise HTTPException(status_code=404, detail="official account not found")
        row = OfficialAutoReplyDB(
            account_id=account_id,
            kind=kind,
            keyword=keyword,
            text=text,
            enabled=bool(body.enabled),
        )
        s.add(row)
        s.commit()
        s.refresh(row)
        return {
            "id": row.id,
            "account_id": row.account_id,
            "kind": row.kind,
            "keyword": row.keyword,
            "text": row.text,
            "enabled": bool(row.enabled),
        }


@app.patch("/admin/official_auto_replies/{rule_id}", response_class=JSONResponse)
def admin_official_auto_replies_update(
    rule_id: int, request: Request, body: dict[str, Any]
) -> dict[str, Any]:
    """
    Updates a single auto‑reply rule.
    """

    _require_admin_v2(request)
    if not isinstance(body, dict):
        body = {}
    allowed_fields = {"kind", "keyword", "text", "enabled"}
    with _officials_session() as s:
        row = s.get(OfficialAutoReplyDB, rule_id)
        if not row:
            raise HTTPException(status_code=404, detail="auto‑reply not found")
        for k, v in body.items():
            if k not in allowed_fields:
                continue
            if k == "kind" and isinstance(v, str):
                v = v.strip().lower() or "welcome"
            if k == "keyword":
                v = (v or "").strip() or None
            if k == "text":
                v = (v or "").strip()
                if not v:
                    raise HTTPException(status_code=400, detail="text is required")
            setattr(row, k, v)
        s.add(row)
        s.commit()
        s.refresh(row)
        return {
            "id": row.id,
            "account_id": row.account_id,
            "kind": row.kind,
            "keyword": row.keyword,
            "text": row.text,
            "enabled": bool(row.enabled),
        }


@app.delete("/admin/official_auto_replies/{rule_id}", response_class=JSONResponse)
def admin_official_auto_replies_delete(rule_id: int, request: Request) -> dict[str, Any]:
    """
    Deletes a single auto‑reply rule.
    """

    _require_admin_v2(request)
    with _officials_session() as s:
        row = s.get(OfficialAutoReplyDB, rule_id)
        if not row:
            raise HTTPException(status_code=404, detail="auto‑reply not found")
        s.delete(row)
        s.commit()
    return {"status": "ok"}


@app.get("/admin/official_feeds", response_class=JSONResponse)
def admin_official_feeds_list(request: Request, account_id: str = "", limit: int = 100) -> dict[str, Any]:
    _require_admin_v2(request)
    limit_val = max(1, min(limit, 500))
    with _officials_session() as s:
        stmt = _sa_select(OfficialFeedItemDB)
        if account_id:
            stmt = stmt.where(OfficialFeedItemDB.account_id == account_id)
        stmt = stmt.order_by(OfficialFeedItemDB.ts.desc(), OfficialFeedItemDB.id.desc()).limit(limit_val)
        rows = s.execute(stmt).scalars().all()
        items: list[dict[str, Any]] = []
        for row in rows:
            try:
                deeplink = _json.loads(row.deeplink_json) if row.deeplink_json else None
            except Exception:
                deeplink = None
            items.append(
                {
                    "account_id": row.account_id,
                    "id": row.slug,
                    "type": row.type,
                    "title": row.title,
                    "snippet": row.snippet,
                    "thumb_url": row.thumb_url,
                    "ts": row.ts.isoformat() if getattr(row, "ts", None) else None,
                    "deeplink": deeplink,
                }
            )
    return {"items": items}


@app.post("/admin/official_feeds", response_class=JSONResponse)
def admin_official_feeds_create(request: Request, body: OfficialFeedItemAdminIn) -> dict[str, Any]:
    _require_admin_v2(request)
    data = body
    with _officials_session() as s:
        acc = s.get(OfficialAccountDB, data.account_id)
        if not acc:
            raise HTTPException(status_code=404, detail="official account not found")
        exists = s.execute(
            _sa_select(OfficialFeedItemDB).where(OfficialFeedItemDB.slug == data.id)
        ).scalars().first()
        if exists:
            raise HTTPException(status_code=409, detail="feed item already exists")
        ts_val = None
        if data.ts:
            try:
                ts_val = datetime.fromisoformat(data.ts.replace("Z", "+00:00"))
            except Exception:
                ts_val = None
        deeplink_json = _json.dumps(data.deeplink) if data.deeplink is not None else None
        row = OfficialFeedItemDB(
            account_id=data.account_id,
            slug=data.id,
            type=data.type or "promo",
            title=data.title,
            snippet=data.snippet,
            thumb_url=data.thumb_url,
            ts=ts_val,
            deeplink_json=deeplink_json,
        )
        s.add(row)
        s.commit()
        s.refresh(row)
        return {
            "account_id": row.account_id,
            "id": row.slug,
            "type": row.type,
            "title": row.title,
            "snippet": row.snippet,
            "thumb_url": row.thumb_url,
            "ts": row.ts.isoformat() if getattr(row, "ts", None) else None,
            "deeplink": data.deeplink,
        }


@app.patch("/admin/official_feeds/{slug}", response_class=JSONResponse)
def admin_official_feeds_update(slug: str, request: Request, body: dict[str, Any]) -> dict[str, Any]:
    _require_admin_v2(request)
    if not isinstance(body, dict):
        body = {}
    with _officials_session() as s:
        row = s.execute(
            _sa_select(OfficialFeedItemDB).where(OfficialFeedItemDB.slug == slug)
        ).scalars().first()
        if not row:
            raise HTTPException(status_code=404, detail="feed item not found")
        if "account_id" in body and body["account_id"]:
            new_acc = s.get(OfficialAccountDB, body["account_id"])
            if not new_acc:
                raise HTTPException(status_code=404, detail="official account not found")
            row.account_id = body["account_id"]
        for field in ("type", "title", "snippet", "thumb_url"):
            if field in body:
                setattr(row, field, body[field])
        if "ts" in body:
            ts_val = None
            ts_str = body.get("ts")
            if ts_str:
                try:
                    ts_val = datetime.fromisoformat(str(ts_str).replace("Z", "+00:00"))
                except Exception:
                    ts_val = None
            row.ts = ts_val
        if "deeplink" in body:
            val = body.get("deeplink")
            row.deeplink_json = _json.dumps(val) if val is not None else None
        s.add(row)
        s.commit()
        s.refresh(row)
        deeplink_val = None
        try:
            deeplink_val = _json.loads(row.deeplink_json) if row.deeplink_json else None
        except Exception:
            deeplink_val = None
        return {
            "account_id": row.account_id,
            "id": row.slug,
            "type": row.type,
            "title": row.title,
            "snippet": row.snippet,
            "thumb_url": row.thumb_url,
            "ts": row.ts.isoformat() if getattr(row, "ts", None) else None,
            "deeplink": deeplink_val,
        }


@app.delete("/admin/official_feeds/{slug}", response_class=JSONResponse)
def admin_official_feeds_delete(slug: str, request: Request) -> dict[str, Any]:
    _require_admin_v2(request)
    with _officials_session() as s:
        row = s.execute(
            _sa_select(OfficialFeedItemDB).where(OfficialFeedItemDB.slug == slug)
        ).scalars().first()
        if not row:
            raise HTTPException(status_code=404, detail="feed item not found")
        s.delete(row)
        s.commit()
    return {"status": "ok"}


@app.get(
    "/admin/official_accounts/{account_id}/service_inbox",
    response_class=JSONResponse,
)
def admin_official_service_inbox(
    account_id: str,
    request: Request,
    status: str | None = None,
    limit: int = 100,
) -> dict[str, Any]:
    """
    Lists lightweight customer-service sessions for an Official account (admin only).

    This provides a WeChat-like unified service inbox with basic
    session state such as open/closed and unread-by-operator flag.
    """
    _require_admin_v2(request)
    limit_val = max(1, min(limit, 500))
    try:
        with _officials_session() as s:
            acc = s.get(OfficialAccountDB, account_id)
            if not acc:
                raise HTTPException(
                    status_code=404, detail="official account not found"
                )
            stmt = _sa_select(OfficialServiceSessionDB).where(
                OfficialServiceSessionDB.account_id == account_id
            )
            if status:
                stmt = stmt.where(OfficialServiceSessionDB.status == status)
            stmt = stmt.order_by(
                OfficialServiceSessionDB.unread_by_operator.desc(),
                OfficialServiceSessionDB.last_message_ts.desc(),
            ).limit(limit_val)
            rows = s.execute(stmt).scalars().all()
            items: list[dict[str, Any]] = []
            for row in rows:
                items.append(
                    {
                        "id": row.id,
                        "account_id": row.account_id,
                        "customer_phone": row.customer_phone,
                        "chat_peer_id": row.chat_peer_id,
                        "status": row.status,
                        "last_message_ts": row.last_message_ts.isoformat(),
                        "unread_by_operator": row.unread_by_operator,
                    }
                )
        return {"sessions": items}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post(
    "/admin/official_accounts/{account_id}/service_inbox/{session_id}/mark_read",
    response_class=JSONResponse,
)
def admin_official_service_inbox_mark_read(
    account_id: str, session_id: int, request: Request
) -> dict[str, Any]:
    """
    Marks a service session as read from the operator perspective.
    """
    _require_admin_v2(request)
    try:
        with _officials_session() as s:
            sess = s.get(OfficialServiceSessionDB, session_id)
            if not sess or sess.account_id != account_id:
                raise HTTPException(status_code=404, detail="session not found")
            if sess.unread_by_operator:
                sess.unread_by_operator = False
                s.add(sess)
                s.commit()
                s.refresh(sess)
            return {
                "id": sess.id,
                "account_id": sess.account_id,
                "customer_phone": sess.customer_phone,
                "chat_peer_id": sess.chat_peer_id,
                "status": sess.status,
                "last_message_ts": sess.last_message_ts.isoformat(),
                "unread_by_operator": sess.unread_by_operator,
            }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post(
    "/admin/official_accounts/{account_id}/service_inbox/{session_id}/close",
    response_class=JSONResponse,
)
def admin_official_service_inbox_close(
    account_id: str, session_id: int, request: Request
) -> dict[str, Any]:
    """
    Closes a customer-service session (sets status=closed).
    """
    _require_admin_v2(request)
    try:
        with _officials_session() as s:
            sess = s.get(OfficialServiceSessionDB, session_id)
            if not sess or sess.account_id != account_id:
                raise HTTPException(status_code=404, detail="session not found")
            sess.status = "closed"
            sess.unread_by_operator = False
            s.add(sess)
            s.commit()
            s.refresh(sess)
            return {
                "id": sess.id,
                "account_id": sess.account_id,
                "customer_phone": sess.customer_phone,
                "chat_peer_id": sess.chat_peer_id,
                "status": sess.status,
                "last_message_ts": sess.last_message_ts.isoformat(),
                "unread_by_operator": sess.unread_by_operator,
            }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post(
    "/admin/official_accounts/{account_id}/service_inbox/{session_id}/template_messages",
    response_class=JSONResponse,
)
def admin_official_service_inbox_send_template_message(
    account_id: str,
    session_id: int,
    request: Request,
    body: dict[str, Any],
) -> dict[str, Any]:
    """
    Sends a one-time Official template message to the customer behind a service session.

    This is a convenience wrapper around OfficialTemplateMessageDB so that
    operators can send WeChat-like subscription messages directly from
    the service inbox without handling phone numbers manually.
    """
    _require_admin_v2(request)
    if not isinstance(body, dict):
        body = {}
    title = (body.get("title") or "").strip()
    msg_body = (body.get("body") or "").strip()
    deeplink = body.get("deeplink_json")
    if not title:
        raise HTTPException(status_code=400, detail="title required")
    if not msg_body:
        raise HTTPException(status_code=400, detail="body required")
    try:
        with _officials_session() as s:
            sess = s.get(OfficialServiceSessionDB, session_id)
            if not sess or sess.account_id != account_id:
                raise HTTPException(status_code=404, detail="session not found")
            acc = s.get(OfficialAccountDB, account_id)
            if not acc:
                raise HTTPException(
                    status_code=404, detail="official account not found"
                )
            deeplink_json = (
                _json.dumps(deeplink) if isinstance(deeplink, dict) else None
            )
            row = OfficialTemplateMessageDB(
                account_id=account_id,
                user_phone=sess.customer_phone,
                title=title,
                body=msg_body,
                deeplink_json=deeplink_json,
            )
            s.add(row)
            s.commit()
            s.refresh(row)
            try:
                emit_event(
                    "officials",
                    "template_message_sent",
                    {
                        "account_id": row.account_id,
                        "user_phone": row.user_phone,
                        "message_id": row.id,
                        "session_id": sess.id,
                    },
                )
            except Exception:
                pass
            try:
                dl = (
                    _json.loads(row.deeplink_json)
                    if row.deeplink_json
                    else None
                )
            except Exception:
                dl = None
            out = OfficialTemplateMessageOut(
                id=row.id,
                account_id=row.account_id,
                title=row.title,
                body=row.body,
                deeplink_json=dl,
                created_at=row.created_at,
                read_at=row.read_at,
            )
            return out.dict()
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/admin/official_template_messages", response_class=JSONResponse)
def admin_official_template_messages_create(
    request: Request, body: OfficialTemplateMessageIn
) -> dict[str, Any]:
    """
    Creates a lightweight per-user Official template message (admin only).

    This models WeChat-like one-time subscription messages that are
    delivered outside the end-to-end encrypted chat stream.
    """
    _require_admin_v2(request)
    data = body
    try:
        with _officials_session() as s:
            acc = s.get(OfficialAccountDB, data.account_id)
            if not acc:
                raise HTTPException(
                    status_code=404, detail="official account not found"
                )
            deeplink_json = (
                _json.dumps(data.deeplink_json)
                if data.deeplink_json is not None
                else None
            )
            row = OfficialTemplateMessageDB(
                account_id=data.account_id,
                user_phone=data.user_phone,
                title=data.title,
                body=data.body,
                deeplink_json=deeplink_json,
            )
            s.add(row)
            s.commit()
            s.refresh(row)
            try:
                emit_event(
                    "officials",
                    "template_message_sent",
                    {
                        "account_id": row.account_id,
                        "user_phone": row.user_phone,
                        "message_id": row.id,
                    },
                )
            except Exception:
                pass
            try:
                deeplink = (
                    _json.loads(row.deeplink_json)
                    if row.deeplink_json
                    else None
                )
            except Exception:
                deeplink = None
            out = OfficialTemplateMessageOut(
                id=row.id,
                account_id=row.account_id,
                title=row.title,
                body=row.body,
                deeplink_json=deeplink,
                created_at=row.created_at,
                read_at=row.read_at,
            )
            return out.dict()
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/admin/official_locations", response_class=JSONResponse)
def admin_official_locations_list(request: Request, account_id: str = "", limit: int = 500) -> dict[str, Any]:
    _require_admin_v2(request)
    limit_val = max(1, min(limit, 1000))
    with _officials_session() as s:
        stmt = _sa_select(OfficialLocationDB)
        if account_id:
            stmt = stmt.where(OfficialLocationDB.account_id == account_id)
        stmt = stmt.order_by(OfficialLocationDB.id.desc()).limit(limit_val)
        rows = s.execute(stmt).scalars().all()
        items: list[dict[str, Any]] = []
        for row in rows:
            items.append(
                {
                    "id": row.id,
                    "account_id": row.account_id,
                    "name": row.name,
                    "city": row.city,
                    "address": row.address,
                    "lat": row.lat,
                    "lon": row.lon,
                    "phone": row.phone,
                    "opening_hours": row.opening_hours,
                }
            )
    return {"locations": items}


@app.post("/admin/official_locations", response_class=JSONResponse)
def admin_official_locations_create(request: Request, body: OfficialLocationAdminIn) -> dict[str, Any]:
    _require_admin_v2(request)
    data = body
    with _officials_session() as s:
        acc = s.get(OfficialAccountDB, data.account_id)
        if not acc:
            raise HTTPException(status_code=404, detail="official account not found")
        row = OfficialLocationDB(
            account_id=data.account_id,
            name=data.name,
            city=data.city,
            address=data.address,
            lat=data.lat,
            lon=data.lon,
            phone=data.phone,
            opening_hours=data.opening_hours,
        )
        s.add(row)
        s.commit()
        s.refresh(row)
        return {
            "id": row.id,
            "account_id": row.account_id,
            "name": row.name,
            "city": row.city,
            "address": row.address,
            "lat": row.lat,
            "lon": row.lon,
            "phone": row.phone,
            "opening_hours": row.opening_hours,
        }


@app.patch("/admin/official_locations/{loc_id}", response_class=JSONResponse)
def admin_official_locations_update(loc_id: int, request: Request, body: dict[str, Any]) -> dict[str, Any]:
    _require_admin_v2(request)
    if not isinstance(body, dict):
        body = {}
    allowed_fields = {"account_id", "name", "city", "address", "lat", "lon", "phone", "opening_hours"}
    with _officials_session() as s:
        row = s.get(OfficialLocationDB, loc_id)
        if not row:
            raise HTTPException(status_code=404, detail="location not found")
        if "account_id" in body and body["account_id"]:
            acc = s.get(OfficialAccountDB, body["account_id"])
            if not acc:
                raise HTTPException(status_code=404, detail="official account not found")
        for k, v in body.items():
            if k in allowed_fields:
                setattr(row, k, v)
        s.add(row)
        s.commit()
        s.refresh(row)
        return {
            "id": row.id,
            "account_id": row.account_id,
            "name": row.name,
            "city": row.city,
            "address": row.address,
            "lat": row.lat,
            "lon": row.lon,
            "phone": row.phone,
            "opening_hours": row.opening_hours,
        }


@app.delete("/admin/official_locations/{loc_id}", response_class=JSONResponse)
def admin_official_locations_delete(loc_id: int, request: Request) -> dict[str, Any]:
    _require_admin_v2(request)
    with _officials_session() as s:
        row = s.get(OfficialLocationDB, loc_id)
        if not row:
            raise HTTPException(status_code=404, detail="location not found")
        s.delete(row)
        s.commit()
    return {"status": "ok"}


@app.get("/admin/redpacket_campaigns", response_class=JSONResponse)
def admin_redpacket_campaigns_list(
    request: Request, account_id: str = "", only_active: bool = False
) -> dict[str, Any]:
    _require_admin_v2(request)
    with _officials_session() as s:
        stmt = _sa_select(RedPacketCampaignDB)
        if account_id:
            stmt = stmt.where(RedPacketCampaignDB.account_id == account_id)
        if only_active:
            stmt = stmt.where(RedPacketCampaignDB.active.is_(True))
        rows = s.execute(stmt.order_by(RedPacketCampaignDB.created_at.desc())).scalars().all()
        items: list[dict[str, Any]] = []
        for row in rows:
            created = getattr(row, "created_at", None)
            updated = getattr(row, "updated_at", None)
            created_str = None
            updated_str = None
            try:
                created_str = created.isoformat().replace("+00:00", "Z") if created else None
            except Exception:
                created_str = str(created) if created is not None else None
            try:
                updated_str = updated.isoformat().replace("+00:00", "Z") if updated else None
            except Exception:
                updated_str = str(updated) if updated is not None else None
            items.append(
                {
                    "id": row.id,
                    "account_id": row.account_id,
                    "title": row.title,
                    "active": bool(getattr(row, "active", True)),
                    "created_at": created_str,
                    "updated_at": updated_str,
                    "default_amount_cents": getattr(row, "default_amount_cents", None),
                    "default_count": getattr(row, "default_count", None),
                    "note": getattr(row, "note", None),
                }
            )
    return {"campaigns": items}


@app.post("/admin/redpacket_campaigns", response_class=JSONResponse)
def admin_redpacket_campaigns_create(
    request: Request, body: RedPacketCampaignAdminIn
) -> dict[str, Any]:
    _require_admin_v2(request)
    data = body
    cid = (data.id or "").strip()
    if not cid:
        raise HTTPException(status_code=400, detail="id is required")
    with _officials_session() as s:
        acc = s.get(OfficialAccountDB, data.account_id)
        if not acc:
            raise HTTPException(status_code=404, detail="official account not found")
        existing = s.get(RedPacketCampaignDB, cid)
        if existing:
            raise HTTPException(status_code=409, detail="campaign already exists")
        row = RedPacketCampaignDB(
            id=cid,
            account_id=data.account_id,
            title=data.title,
            active=data.active,
            default_amount_cents=data.default_amount_cents,
            default_count=data.default_count,
            note=data.note,
        )
        s.add(row)
        s.commit()
        s.refresh(row)
        created = getattr(row, "created_at", None)
        created_str = None
        try:
            created_str = created.isoformat().replace("+00:00", "Z") if created else None
        except Exception:
            created_str = str(created) if created is not None else None
        return {
            "id": row.id,
            "account_id": row.account_id,
            "title": row.title,
            "active": bool(getattr(row, "active", True)),
            "created_at": created_str,
        }


@app.patch("/admin/redpacket_campaigns/{campaign_id}", response_class=JSONResponse)
def admin_redpacket_campaigns_update(
    campaign_id: str, request: Request, body: dict[str, Any]
) -> dict[str, Any]:
    _require_admin_v2(request)
    if not isinstance(body, dict):
        body = {}
    allowed_fields = {"account_id", "title", "active", "default_amount_cents", "default_count", "note"}
    with _officials_session() as s:
        row = s.get(RedPacketCampaignDB, campaign_id)
        if not row:
            raise HTTPException(status_code=404, detail="campaign not found")
        if "account_id" in body and body["account_id"]:
            acc = s.get(OfficialAccountDB, body["account_id"])
            if not acc:
                raise HTTPException(status_code=404, detail="official account not found")
        for k, v in body.items():
            if k in allowed_fields:
                setattr(row, k, v)
        s.add(row)
        s.commit()
        s.refresh(row)
        created = getattr(row, "created_at", None)
        updated = getattr(row, "updated_at", None)
        created_str = None
        updated_str = None
        try:
            created_str = created.isoformat().replace("+00:00", "Z") if created else None
        except Exception:
            created_str = str(created) if created is not None else None
        try:
            updated_str = updated.isoformat().replace("+00:00", "Z") if updated else None
        except Exception:
            updated_str = str(updated) if updated is not None else None
        return {
            "id": row.id,
            "account_id": row.account_id,
            "title": row.title,
            "active": bool(getattr(row, "active", True)),
            "created_at": created_str,
            "updated_at": updated_str,
            "default_amount_cents": getattr(row, "default_amount_cents", None),
            "default_count": getattr(row, "default_count", None),
            "note": getattr(row, "note", None),
        }


@app.delete("/admin/redpacket_campaigns/{campaign_id}", response_class=JSONResponse)
def admin_redpacket_campaigns_delete(campaign_id: str, request: Request) -> dict[str, Any]:
    _require_admin_v2(request)
    with _officials_session() as s:
        row = s.get(RedPacketCampaignDB, campaign_id)
        if not row:
            raise HTTPException(status_code=404, detail="campaign not found")
        # Soft-delete: mark inactive but keep row for historical analytics.
        row.active = False
        s.add(row)
        s.commit()
    return {"status": "ok"}


@app.get(
    "/redpacket/campaigns/{campaign_id}/moments_template",
    response_class=JSONResponse,
)
def redpacket_campaign_moments_template(campaign_id: str) -> dict[str, Any]:
    """
    Returns a best-effort Moments share template for a given Red‑Packet campaign.

    Text is generated from the campaign title and Official account name and
    includes a shamell://official deep-link so Moments can later reconstruct
    origin_official_account_id/origin_official_item_id.
    """
    cid = (campaign_id or "").strip()
    if not cid:
        raise HTTPException(status_code=400, detail="campaign_id required")
    try:
        with _officials_session() as s:
            camp = s.get(RedPacketCampaignDB, cid)
            if not camp:
                raise HTTPException(status_code=404, detail="campaign not found")
            acc = s.get(OfficialAccountDB, camp.account_id)
            acc_name = (acc.name or camp.account_id) if acc else camp.account_id
        base_link = f"shamell://official/{camp.account_id}/{camp.id}"
        title = (camp.title or "").strip() or camp.id
        note = (camp.note or "").strip()
        def_amt = getattr(camp, "default_amount_cents", None)
        def_count = getattr(camp, "default_count", None)
        extra_en = ""
        extra_ar = ""
        try:
            if def_amt and isinstance(def_amt, (int, float)) and def_amt > 0:
                major = float(def_amt) / 100.0
                if def_count and isinstance(def_count, (int, float)) and def_count > 0:
                    extra_en = f"\nDefault: total {major:.2f}, {int(def_count)} recipients."
                    extra_ar = f"\nالإعداد الافتراضي: مجموع {major:.2f}، {int(def_count)} مستلمين."
                else:
                    extra_en = f"\nDefault: total {major:.2f}."
                    extra_ar = f"\nالإعداد الافتراضي: مجموع {major:.2f}."
            elif def_count and isinstance(def_count, (int, float)) and def_count > 0:
                extra_en = f"\nDefault: {int(def_count)} recipients."
                extra_ar = f"\nالإعداد الافتراضي: {int(def_count)} مستلمين."
        except Exception:
            extra_en = ""
            extra_ar = ""
        text_en = (
            f"Red packet campaign from {acc_name}: {title}.\n"
            f"I am sending red packets via Shamell Pay 🎁"
            f"{extra_en}\n"
            f"{base_link}"
        )
        if note:
            text_en = f"{text_en}\n{note}"
        text_ar = (
            f"حملة حزم حمراء من {acc_name}: {title}.\n"
            f"أرسل حزمًا حمراء عبر Shamell Pay 🎁"
            f"{extra_ar}\n"
            f"{base_link}"
        )
        if note:
            text_ar = f"{text_ar}\n{note}"
        return RedPacketCampaignTemplateOut(
            campaign_id=camp.id,
            account_id=camp.account_id,
            title=camp.title,
            text_en=text_en,
            text_ar=text_ar,
        ).dict()
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/admin/officials", response_class=HTMLResponse)
def admin_officials_console(request: Request) -> HTMLResponse:
    """
    Sehr einfache HTML-Konsole für Offizielle Accounts.

    Nutzt die JSON-Admin-API-Endpunkte und lässt bestehende Ops/Admins
    (über _require_admin_v2) neue Accounts anlegen, bearbeiten und
    aktivieren/deaktivieren – ohne zusätzliche Tools.
    """
    _require_admin_v2(request)
    return _html_template_response("admin_officials.html")


@app.get("/admin/miniapps", response_class=HTMLResponse)
def admin_miniapps_console(request: Request) -> HTMLResponse:
    """
    Einfache HTML-Konsole für Mini-Apps (Mini-Programme).

    Nutzt die JSON-Admin-Endpunkte /admin/mini_apps, um Partner- und
    Drittanbieter-Apps ähnlich wie WeChat Mini-Programs zu verwalten.
    """
    _require_admin_v2(request)
    return _html_template_response("admin_miniapps.html")


@app.get("/admin/miniprograms", response_class=HTMLResponse)
def admin_miniprograms_console(request: Request) -> HTMLResponse:
    """
    Einfache HTML-Konsole für Mini-Programme (Mini-Programs).

    Nutzt die öffentlichen JSON-Endpunkte /mini_programs und
    /mini_programs/{id}, um WeChat-ähnliche Mini-Programs zu
    inspizieren und neue Einträge anzulegen.
    """
    _require_admin_v2(request)
    return _html_template_response("admin_miniprograms.html")


@app.get("/admin/mini_programs/analytics", response_class=HTMLResponse)
def admin_miniprograms_analytics(request: Request) -> HTMLResponse:
    """
    Lightweight HTML analytics für Mini-Programs.

    Nutzt usage_score als einfache KPI – ähnlich zu WeChat
    Mini-Program \"popular\" / \"top\" Rankings.
    """
    _require_admin_v2(request)
    try:
        with _officials_session() as s:
            rows = (
                s.execute(
                    _sa_select(MiniProgramDB).order_by(
                        MiniProgramDB.usage_score.desc(), MiniProgramDB.app_id
                    )
                )
                .scalars()
                .all()
            )
        total_usage = 0
        for row in rows:
            try:
                total_usage += int(getattr(row, "usage_score", 0) or 0)
            except Exception:
                continue

        # Best-effort Moments share counts pro Mini-Program für Analytics:
        # lifetime und letzte 30 Tage (WeChat-like "hot last 30 days").
        moments_all: dict[str, int] = {}
        moments_30d: dict[str, int] = {}
        try:
            app_ids = [r.app_id for r in rows if getattr(r, "app_id", None)]
            if app_ids:
                with _moments_session() as ms:
                    since_30d = datetime.now(timezone.utc) - timedelta(days=30)
                    for app_id in app_ids:
                        try:
                            pattern = f"shamell://mini_program/{app_id}"
                            base_stmt = _sa_select(
                                _sa_func.count(MomentPostDB.id)
                            ).where(MomentPostDB.text.contains(pattern))
                            cnt_all = ms.execute(base_stmt).scalar() or 0
                            cnt_30 = (
                                ms.execute(
                                    base_stmt.where(
                                        MomentPostDB.created_at >= since_30d
                                    )
                                ).scalar()
                                or 0
                            )
                            moments_all[str(app_id)] = int(cnt_all or 0)
                            moments_30d[str(app_id)] = int(cnt_30 or 0)
                        except Exception:
                            continue
        except Exception:
            moments_all = {}
            moments_30d = {}

        def esc(s: str) -> str:
            return _html.escape(s or "", quote=True)

        rows_html: list[str] = []
        for row in rows:
            app_id = row.app_id
            title_en = row.title_en or ""
            title_ar = row.title_ar or ""
            owner = getattr(row, "owner_name", "") or ""
            status = (row.status or "").strip()
            try:
                usage = int(getattr(row, "usage_score", 0) or 0)
            except Exception:
                usage = 0
            share = 0.0
            if total_usage > 0 and usage > 0:
                try:
                    share = (usage / float(total_usage)) * 100.0
                except Exception:
                    share = 0.0
            try:
                rating_val = float(getattr(row, "rating", 0.0) or 0.0)
            except Exception:
                rating_val = 0.0
            try:
                m_all = int(
                    moments_all.get(app_id, 0)
                    or getattr(row, "moments_shares", 0)
                    or 0
                )
            except Exception:
                m_all = 0
            try:
                m_30 = int(moments_30d.get(app_id, 0) or 0)
            except Exception:
                m_30 = 0
            rows_html.append(
                "<tr>"
                f"<td><code>{esc(app_id)}</code></td>"
                f"<td>{esc(title_en)}<br/><span class=\"meta\">{esc(title_ar)}</span></td>"
                f"<td>{esc(owner)}</td>"
                f"<td>{esc(status)}</td>"
                f"<td>{usage}</td>"
                f"<td>{share:.1f}%</td>"
                f"<td>{rating_val:.1f}</td>"
                f"<td>{m_all}</td>"
                f"<td>{m_30}</td>"
                "</tr>"
            )

        html = f"""
<!doctype html>
<html><head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Mini-Programs · Analytics</title>
  <style>
    body{{font-family:sans-serif;margin:20px;max-width:960px;color:#0f172a;}}
    h1{{margin-bottom:4px;}}
    table{{border-collapse:collapse;width:100%;margin-top:12px;}}
    th,td{{padding:6px 8px;border-bottom:1px solid #e5e7eb;font-size:13px;text-align:left;vertical-align:top;}}
    th{{background:#f9fafb;font-weight:600;}}
    .meta{{color:#6b7280;font-size:12px;margin-top:2px;}}
    code{{background:#f3f4f6;padding:2px 4px;border-radius:3px;font-size:12px;}}
  </style>
</head><body>
  <h1>Mini-Programs · Analytics</h1>
  <div class="meta">
    Basierend auf usage_score (Open-Events via /mini_programs/&lt;id&gt;/track_open)
    und Moments-Sharing (Deep-Links auf shamell://mini_program/&lt;id&gt;).<br/>
    Dient als WeChat‑ähnliche Übersicht der beliebtesten und zuletzt in Moments
    geteilten Mini‑Programme.
  </div>
  <p class="meta">
    <a href="/admin/miniprograms">Zurück zur Mini‑Programs-Konsole</a>
    · <a href="/admin/mini_programs/review">Review‑Center</a>
  </p>
  <table>
    <thead>
      <tr>
        <th>App ID</th>
        <th>Title</th>
        <th>Owner</th>
        <th>Status</th>
        <th>Usage score</th>
        <th>Share of usage</th>
        <th>Avg. rating</th>
        <th>Moments shares</th>
        <th>Moments (30d)</th>
      </tr>
    </thead>
    <tbody>
      {''.join(rows_html) if rows_html else '<tr><td colspan="9">No Mini-Programs registered yet.</td></tr>'}
    </tbody>
  </table>
</body></html>
"""
        return HTMLResponse(content=html)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/admin/mini_programs/review", response_class=HTMLResponse)
def admin_miniprograms_review(request: Request) -> HTMLResponse:
    """
    Lightweight Review‑Center für Mini‑Programs – WeChat‑artig.

    Zeigt alle eingereichten Mini‑Programme (review_status=submitted)
    inklusive Owner, Status, Nutzung und Rating, plus schnelle
    Aktionen zum Approven/Rejecten.
    """
    _require_admin_v2(request)
    try:
        with _officials_session() as s:
            rows = (
                s.execute(
                    _sa_select(MiniProgramDB).order_by(
                        MiniProgramDB.review_status.desc(),
                        MiniProgramDB.created_at.desc(),
                        MiniProgramDB.id.desc(),
                    )
                )
                .scalars()
                .all()
            )
        review_rows: list[MiniProgramDB] = []
        other_rows: list[MiniProgramDB] = []
        for prog in rows:
            r_state = (getattr(prog, "review_status", "draft") or "").strip().lower()
            if r_state == "submitted":
                review_rows.append(prog)
            else:
                other_rows.append(prog)

        def esc(s: str) -> str:
            return _html.escape(s or "", quote=True)

        def esc_attr(s: str) -> str:
            return _html.escape(s or "", quote=True)

        def _row_html(prog: MiniProgramDB) -> str:
            app_id = prog.app_id or ""
            title_en = prog.title_en or ""
            title_ar = getattr(prog, "title_ar", "") or ""
            owner_name = getattr(prog, "owner_name", "") or ""
            owner_contact = getattr(prog, "owner_contact", "") or ""
            status = (prog.status or "draft").strip()
            review_status = (getattr(prog, "review_status", "draft") or "").strip()
            app_id_url = _urlparse.quote(app_id, safe="")
            try:
                usage = int(getattr(prog, "usage_score", 0) or 0)
            except Exception:
                usage = 0
            try:
                rating_val = float(getattr(prog, "rating", 0.0) or 0.0)
            except Exception:
                rating_val = 0.0
            created = getattr(prog, "created_at", None)
            created_str = ""
            try:
                if isinstance(created, datetime):
                    created_str = created.isoformat().replace("+00:00", "Z")
                elif created is not None:
                    created_str = str(created)
            except Exception:
                created_str = ""
            return (
                "<tr>"
                f"<td><code>{esc(app_id)}</code></td>"
                f"<td>{esc(title_en)}<br/><span class=\"muted\">{esc(title_ar)}</span></td>"
                f"<td>{esc(owner_name)}<br/><span class=\"muted\">{esc(owner_contact)}</span></td>"
                f"<td>{esc(status)}</td>"
                f"<td>{esc(review_status)}</td>"
                f"<td>{usage}</td>"
                f"<td>{rating_val:.1f}</td>"
                f"<td>{esc(created_str)}</td>"
                f"<td>"
                f"<a href=\"/mini_programs/{esc_attr(app_id_url)}\" target=\"_blank\">JSON</a>"
                "</td>"
                f"<td>"
                f"<button type=\"button\" class=\"mp-approve\" data-app-id=\"{esc_attr(app_id)}\">Approve</button><br/>"
                f"<button type=\"button\" class=\"mp-reject\" data-app-id=\"{esc_attr(app_id)}\">Reject</button><br/>"
                f"<button type=\"button\" class=\"mp-suspend\" data-app-id=\"{esc_attr(app_id)}\">Suspend</button>"
                "</td>"
                "</tr>"
            )

        submitted_html = "".join(_row_html(p) for p in review_rows)
        other_html = "".join(_row_html(p) for p in other_rows)

        html = f"""
<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Mini-Programs · Review-Center</title>
    <style>
      body {{ font-family: system-ui, -apple-system, BlinkMacSystemFont, sans-serif; margin: 16px; max-width: 1080px; color: #0f172a; }}
      h1 {{ margin-bottom: 4px; }}
      h2 {{ margin-top: 24px; margin-bottom: 8px; }}
      table {{ border-collapse: collapse; width: 100%; margin-top: 8px; }}
      th, td {{ border: 1px solid #e5e7eb; padding: 6px 8px; font-size: 13px; text-align: left; vertical-align: top; }}
      th {{ background: #f9fafb; font-weight: 600; }}
      .muted {{ color:#6b7280; font-size:12px; }}
      #flash {{ margin: 4px 0 8px; }}
      #flash.error {{ color:#b91c1c; }}
      #flash.success {{ color:#166534; }}
      button {{ font-size: 12px; padding: 2px 6px; margin: 1px 0; }}
    </style>
  </head>
  <body>
    <h1>Mini-Programs · Review-Center</h1>
    <p class="muted">
      WeChat‑ähnliche Review‑Übersicht: fokussiert auf eingereichte Mini‑Programs
      (<code>review_status = submitted</code>) mit schnellen Aktionen zum Approven/Rejekten.
    </p>
    <p class="muted">
      <a href="/admin/miniprograms">Mini‑Programs-Konsole</a>
      · <a href="/admin/mini_programs/analytics">Analytics</a>
    </p>
    <div id="flash" class="muted"></div>

    <h2>Eingereichte Mini-Programs (Review-Queue)</h2>
    <table>
      <thead>
        <tr>
          <th>App ID</th>
          <th>Title</th>
          <th>Owner</th>
          <th>Status</th>
          <th>Review</th>
          <th>Usage</th>
          <th>Rating</th>
          <th>Created</th>
          <th>Links</th>
          <th>Actions</th>
        </tr>
      </thead>
      <tbody>
        {submitted_html or '<tr><td colspan="10">Keine eingereichten Mini‑Programs.</td></tr>'}
      </tbody>
    </table>

    <h2>Weitere Mini-Programs</h2>
    <table>
      <thead>
        <tr>
          <th>App ID</th>
          <th>Title</th>
          <th>Owner</th>
          <th>Status</th>
          <th>Review</th>
          <th>Usage</th>
          <th>Rating</th>
          <th>Created</th>
          <th>Links</th>
          <th>Actions</th>
        </tr>
      </thead>
      <tbody>
        {other_html or '<tr><td colspan="10">Keine weiteren Mini‑Programs.</td></tr>'}
      </tbody>
    </table>

    <script>
      async function mpReviewUpdate(appId, status, reviewStatus) {{
        const flash = document.getElementById('flash');
        flash.textContent = '';
        flash.className = 'muted';
        if (!appId) {{
          flash.textContent = 'App-ID fehlt.';
          flash.className = 'error';
          return;
        }}
        const payload = {{}};
        if (status) payload.status = status;
        if (reviewStatus) payload.review_status = reviewStatus;
        try {{
          const r = await fetch('/admin/mini_programs/' + encodeURIComponent(appId), {{
            method: 'PATCH',
            headers: {{'content-type':'application/json'}},
            body: JSON.stringify(payload),
          }});
          if (!r.ok) {{
            const txt = await r.text();
            flash.textContent = 'Fehler beim Aktualisieren: ' + r.status + ' ' + txt;
            flash.className = 'error';
          }} else {{
            flash.textContent = 'Review-Status aktualisiert.';
            flash.className = 'success';
            window.location.reload();
          }}
        }} catch (e) {{
          flash.textContent = 'Fehler: ' + e;
          flash.className = 'error';
        }}
      }}

      function mpReviewApprove(appId) {{
        mpReviewUpdate(appId, 'active', 'approved');
      }}
      function mpReviewReject(appId) {{
        mpReviewUpdate(appId, 'disabled', 'rejected');
      }}
      function mpReviewSuspend(appId) {{
        mpReviewUpdate(appId, 'disabled', 'suspended');
      }}

      function bindReviewButtons() {{
        try {{
          document.querySelectorAll('button.mp-approve').forEach((btn) => {{
            btn.addEventListener('click', () => mpReviewApprove(btn.dataset.appId || ''));
          }});
          document.querySelectorAll('button.mp-reject').forEach((btn) => {{
            btn.addEventListener('click', () => mpReviewReject(btn.dataset.appId || ''));
          }});
          document.querySelectorAll('button.mp-suspend').forEach((btn) => {{
            btn.addEventListener('click', () => mpReviewSuspend(btn.dataset.appId || ''));
          }});
        }} catch (e) {{}}
      }}

      bindReviewButtons();
    </script>
  </body>
</html>
"""
        return HTMLResponse(content=html)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.patch("/admin/mini_programs/{app_id}", response_class=JSONResponse)
def admin_mini_program_update(
    app_id: str, request: Request, body: dict[str, Any]
) -> dict[str, Any]:
    """
    Admin‑Endpoint zum Aktualisieren einzelner Mini‑Program‑Felder.

    Unterstützt u.a. Status (draft/active/disabled), review_status
    (draft/submitted/approved/rejected/suspended) und scopes.
    """
    _require_admin_v2(request)
    if not isinstance(body, dict):
        raise HTTPException(status_code=400, detail="body must be object")
    app_id_clean = (app_id or "").strip()
    if not app_id_clean:
        raise HTTPException(status_code=400, detail="app_id required")
    allowed_status = {"draft", "active", "disabled"}
    allowed_review = {"draft", "submitted", "approved", "rejected", "suspended"}
    raw_status = body.get("status")
    raw_review = body.get("review_status")
    if raw_status is not None:
        status_val = str(raw_status).strip().lower()
        if status_val not in allowed_status:
            raise HTTPException(status_code=400, detail="invalid status")
    else:
        status_val = None
    if raw_review is not None:
        review_val = str(raw_review).strip().lower()
        if review_val not in allowed_review:
            raise HTTPException(status_code=400, detail="invalid review_status")
    else:
        review_val = None
    scopes_val = None
    if "scopes" in body:
        raw_scopes = body.get("scopes")
        if raw_scopes is None:
            scopes_val = None
        elif isinstance(raw_scopes, list):
            scopes_val = [str(s).strip() for s in raw_scopes if str(s).strip()]
        else:
            raise HTTPException(status_code=400, detail="scopes must be list of strings or null")
    try:
        with _officials_session() as s:
            prog = (
                s.execute(
                    _sa_select(MiniProgramDB).where(
                        MiniProgramDB.app_id == app_id_clean
                    )
                )
                .scalars()
                .first()
            )
            if not prog:
                raise HTTPException(status_code=404, detail="mini-program not found")
            if status_val is not None:
                prog.status = status_val
            if review_val is not None:
                prog.review_status = review_val
            if scopes_val is not None:
                if scopes_val:
                    try:
                        prog.scopes_json = _json.dumps(scopes_val)
                    except Exception:
                        prog.scopes_json = None
                else:
                    prog.scopes_json = None
            s.add(prog)
            s.commit()
            s.refresh(prog)
            scopes_list: list[str] = []
            try:
                raw_scopes = getattr(prog, "scopes_json", None)
                if raw_scopes:
                    val = _json.loads(raw_scopes)
                    if isinstance(val, list):
                        scopes_list = [
                            str(s).strip() for s in val if str(s).strip()
                        ]
            except Exception:
                scopes_list = []
            return {
                "app_id": prog.app_id,
                "status": prog.status,
                "review_status": getattr(prog, "review_status", "draft"),
                "scopes": scopes_list,
            }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/admin/officials/analytics", response_class=HTMLResponse)
def admin_officials_analytics(request: Request) -> HTMLResponse:
    """
    Lightweight HTML analytics for Official accounts.

    Shows follower counts, notification mode breakdown, feed items
    and Moments shares per account – WeChat-style merchant overview.
    """
    _require_admin_v2(request)
    try:
        # Aggregate per-account metrics from Official DB
        with _officials_session() as s:
            accounts = (
                s.execute(
                    _sa_select(OfficialAccountDB).order_by(OfficialAccountDB.id)
                )
                .scalars()
                .all()
            )
            follower_counts: dict[str, int] = {}
            notif_summary: dict[str, int] = {}
            notif_muted: dict[str, int] = {}
            feed_counts: dict[str, int] = {}
            feed_last_ts: dict[str, str] = {}

            rows = (
                s.execute(
                    _sa_select(
                        OfficialFollowDB.account_id,
                        _sa_func.count(OfficialFollowDB.id),
                    ).group_by(OfficialFollowDB.account_id)
                )
                .all()
            )
            for acc_id, cnt in rows:
                follower_counts[str(acc_id)] = int(cnt or 0)

            notif_rows = (
                s.execute(
                    _sa_select(
                        OfficialNotificationDB.account_id,
                        OfficialNotificationDB.mode,
                        _sa_func.count(OfficialNotificationDB.id),
                    ).group_by(
                        OfficialNotificationDB.account_id,
                        OfficialNotificationDB.mode,
                    )
                )
                .all()
            )
            for acc_id, mode, cnt in notif_rows:
                aid = str(acc_id)
                m = (mode or "").strip().lower()
                if m == "summary":
                    notif_summary[aid] = notif_summary.get(aid, 0) + int(cnt or 0)
                elif m == "muted":
                    notif_muted[aid] = notif_muted.get(aid, 0) + int(cnt or 0)

            feed_rows = (
                s.execute(
                    _sa_select(
                        OfficialFeedItemDB.account_id,
                        _sa_func.count(OfficialFeedItemDB.id),
                        _sa_func.max(OfficialFeedItemDB.ts),
                    ).group_by(OfficialFeedItemDB.account_id)
                )
                .all()
            )
            for acc_id, cnt, ts in feed_rows:
                aid = str(acc_id)
                feed_counts[aid] = int(cnt or 0)
                if ts is not None:
                    try:
                        ts_str = ts.isoformat().replace("+00:00", "Z")
                    except Exception:
                        ts_str = str(ts)
                    feed_last_ts[aid] = ts_str

        # Aggregate Moments shares per Official account (origin_official_account_id)
        moments_shares: dict[str, int] = {}
        moments_shares_30d: dict[str, int] = {}
        moments_unique_sharers: dict[str, int] = {}
        moments_unique_sharers_30d: dict[str, int] = {}
        moments_redpacket_shares: dict[str, int] = {}
        moments_redpacket_shares_30d: dict[str, int] = {}
        try:
            with _moments_session() as ms:
                since_30d = datetime.now(timezone.utc) - timedelta(days=30)

                base_stmt = _sa_select(
                    MomentPostDB.origin_official_account_id,
                    _sa_func.count(MomentPostDB.id),
                ).where(MomentPostDB.origin_official_account_id.is_not(None))

                # All Moments shares per official
                m_rows = ms.execute(
                    base_stmt.group_by(MomentPostDB.origin_official_account_id)
                ).all()
                for acc_id, cnt in m_rows:
                    if not acc_id:
                        continue
                    moments_shares[str(acc_id)] = int(cnt or 0)

                # Last 30 days Moments shares per official
                recent_rows = ms.execute(
                    base_stmt.where(MomentPostDB.created_at >= since_30d).group_by(
                        MomentPostDB.origin_official_account_id
                    )
                ).all()
                for acc_id, cnt in recent_rows:
                    if not acc_id:
                        continue
                    moments_shares_30d[str(acc_id)] = int(cnt or 0)

                # Unique sharers (distinct users who shared this official) – all time
                uniq_stmt = _sa_select(
                    MomentPostDB.origin_official_account_id,
                    _sa_func.count(_sa_func.distinct(MomentPostDB.user_key)),
                ).where(MomentPostDB.origin_official_account_id.is_not(None))
                uniq_rows = ms.execute(
                    uniq_stmt.group_by(MomentPostDB.origin_official_account_id)
                ).all()
                for acc_id, cnt in uniq_rows:
                    if not acc_id:
                        continue
                    moments_unique_sharers[str(acc_id)] = int(cnt or 0)

                # Unique sharers in the last 30 days
                uniq_recent_rows = ms.execute(
                    uniq_stmt.where(MomentPostDB.created_at >= since_30d).group_by(
                        MomentPostDB.origin_official_account_id
                    )
                ).all()
                for acc_id, cnt in uniq_recent_rows:
                    if not acc_id:
                        continue
                    moments_unique_sharers_30d[str(acc_id)] = int(cnt or 0)

                # Red-packet related Moments shares per official (same heuristics as Moments analytics)
                def _add_redpacket_rows(stmt, target: dict[str, int]):
                    rows = ms.execute(stmt).all()
                    for acc_id, cnt in rows:
                        if not acc_id:
                            continue
                        key = str(acc_id)
                        target[key] = target.get(key, 0) + int(cnt or 0)

                rp_stmt = base_stmt.group_by(MomentPostDB.origin_official_account_id)
                _add_redpacket_rows(
                    rp_stmt.where(MomentPostDB.text.contains("Red packet")),
                    moments_redpacket_shares,
                )
                _add_redpacket_rows(
                    rp_stmt.where(
                        MomentPostDB.text.contains(
                            "I am sending red packets via Shamell Pay"
                        )
                    ),
                    moments_redpacket_shares,
                )
                _add_redpacket_rows(
                    rp_stmt.where(MomentPostDB.text.contains("حزمة حمراء")),
                    moments_redpacket_shares,
                )

                # Red-packet related Moments shares in the last 30 days
                rp_30_stmt = rp_stmt.where(MomentPostDB.created_at >= since_30d)
                _add_redpacket_rows(
                    rp_30_stmt.where(MomentPostDB.text.contains("Red packet")),
                    moments_redpacket_shares_30d,
                )
                _add_redpacket_rows(
                    rp_30_stmt.where(
                        MomentPostDB.text.contains(
                            "I am sending red packets via Shamell Pay"
                        )
                    ),
                    moments_redpacket_shares_30d,
                )
                _add_redpacket_rows(
                    rp_30_stmt.where(MomentPostDB.text.contains("حزمة حمراء")),
                    moments_redpacket_shares_30d,
                )
        except Exception:
            moments_shares = {}
            moments_shares_30d = {}
            moments_unique_sharers = {}
            moments_unique_sharers_30d = {}
            moments_redpacket_shares = {}
            moments_redpacket_shares_30d = {}

        def esc(s: str) -> str:
            return _html.escape(s or "", quote=True)

        rows_html: list[str] = []
        total_followers = 0
        for acc in accounts:
            acc_id = acc.id
            followers = follower_counts.get(acc_id, 0)
            total_followers += followers
            feed_count = feed_counts.get(acc_id, 0)
            last_ts = feed_last_ts.get(acc_id, "")
            share_count = moments_shares.get(acc_id, 0)
            share_30 = moments_shares_30d.get(acc_id, 0)
            # Unique sharers (all time / 30d) for this Official
            uniq_sharers = moments_unique_sharers.get(acc_id, 0)
            uniq_sharers_30 = moments_unique_sharers_30d.get(acc_id, 0)
            rp_share_count = moments_redpacket_shares.get(acc_id, 0)
            rp_share_30 = moments_redpacket_shares_30d.get(acc_id, 0)
            summary_cnt = notif_summary.get(acc_id, 0)
            muted_cnt = notif_muted.get(acc_id, 0)
            shares_per_1k = 0.0
            redpacket_share_ratio_30 = 0.0
            try:
                if followers > 0 and share_count > 0:
                    shares_per_1k = (share_count / float(followers)) * 1000.0
                if share_30 > 0 and rp_share_30 > 0:
                    redpacket_share_ratio_30 = (rp_share_30 / float(share_30)) * 100.0
            except Exception:
                shares_per_1k = 0.0
                redpacket_share_ratio_30 = 0.0
            if share_30 > 0:
                share_30_cell = (
                    f'<a href="/moments/admin/comments/html?official_account_id={esc(acc_id)}">{share_30}</a>'
                )
            else:
                share_30_cell = str(share_30)
            comments_link = (
                f'<a href="/moments/admin/comments/html?official_account_id={esc(acc_id)}">View</a>'
            )
            rows_html.append(
                "<tr>"
                f"<td><code>{esc(acc_id)}</code></td>"
                f"<td>{esc(acc.name or '')}</td>"
                f"<td>{esc(acc.kind or '')}</td>"
                f"<td>{followers}</td>"
                f"<td>{feed_count}</td>"
                f"<td>{esc(last_ts)}</td>"
                f"<td>{share_count}</td>"
                f"<td>{rp_share_count}</td>"
                f"<td>{share_30_cell}</td>"
                f"<td>{rp_share_30}</td>"
                f"<td>{uniq_sharers}</td>"
                f"<td>{uniq_sharers_30}</td>"
                f"<td>{shares_per_1k:.1f}</td>"
                f"<td>{redpacket_share_ratio_30:.1f}%</td>"
                f"<td>{comments_link}</td>"
                f"<td>{summary_cnt}</td>"
                f"<td>{muted_cnt}</td>"
                "</tr>"
            )

        html = f"""
<!doctype html>
<html><head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Official Accounts · Analytics</title>
  <style>
    body{{font-family:sans-serif;margin:20px;max-width:1100px;color:#0f172a;}}
    h1{{margin-bottom:4px;}}
    table{{border-collapse:collapse;width:100%;margin-top:12px;}}
    th,td{{padding:6px 8px;border-bottom:1px solid #e5e7eb;font-size:13px;text-align:left;vertical-align:top;}}
    th{{background:#f9fafb;font-weight:600;}}
    .meta{{color:#6b7280;font-size:12px;margin-top:4px;}}
    code{{background:#f3f4f6;padding:2px 4px;border-radius:3px;font-size:12px;}}
  </style>
</head><body>
  <h1>Official Accounts · Analytics</h1>
  <div class="meta">
    Followers total: {total_followers} · Accounts: {len(accounts)}.
    Data based on Official DB and Moments shares (incl. red-packet mentions); event hooks (follow/feed) go to Redis/logs.
  </div>
  <div class="meta">
    Unique sharers = distinct users who shared this account in Moments (all time / last 30 days). Shares / 1k followers = Moments shares per 1,000 followers (engagement intensity, normalised for follower size).
  </div>
  <p class="meta">
    <a href="/admin/officials">Zurück zur Official-Admin-Konsole</a>
  </p>
  <table>
    <thead>
      <tr>
        <th>ID</th>
        <th>Name</th>
        <th>Kind</th>
        <th>Followers</th>
        <th>Feed items</th>
        <th>Last feed TS</th>
        <th>Moments shares</th>
        <th>Red-packet shares</th>
        <th>Moments (30d)</th>
        <th>Red-packet (30d)</th>
        <th>Unique sharers</th>
        <th>Unique sharers (30d)</th>
        <th>Shares / 1k followers</th>
        <th>Red-packet share rate (30d)</th>
        <th>Moments comments (QA)</th>
        <th>Notif summary</th>
        <th>Notif muted</th>
      </tr>
    </thead>
    <tbody>
      {''.join(rows_html) if rows_html else '<tr><td colspan="17">No Official accounts configured.</td></tr>'}
    </tbody>
  </table>
</body></html>
"""
        return HTMLResponse(content=html)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/admin/channels/analytics", response_class=HTMLResponse)
def admin_channels_analytics(request: Request) -> HTMLResponse:
    """
    Lightweight HTML-Analytics für Channels – WeChat-ähnlicher Überblick.

    Aggregiert pro Official-Account:
      - Anzahl Clips
      - Gesamt-Views, Likes, Comments
      - Einfacher Engagement-Score und "Hot in Moments"-Flag (basierend auf
        der gleichen Heuristik wie /channels/feed).
    """
    _require_admin_v2(request)
    try:
        with _officials_session() as s:
            rows = (
                s.execute(
                    _sa_select(
                        OfficialFeedItemDB.id,
                        OfficialFeedItemDB.account_id,
                        OfficialFeedItemDB.type,
                        OfficialAccountDB.name,
                        OfficialAccountDB.city,
                        OfficialAccountDB.category,
                    )
                    .join(
                        OfficialAccountDB,
                        OfficialFeedItemDB.account_id == OfficialAccountDB.id,
                    )
                )
                .all()
            )
            if not rows:
                html_empty = """
<!doctype html>
<html><head>
  <meta charset="utf-8" />
  <title>Channels · Analytics</title>
  <style>
    body{font-family:sans-serif;margin:20px;max-width:960px;color:#0f172a;}
  </style>
</head><body>
  <h1>Channels · Analytics</h1>
  <p>No Channels clips found.</p>
</body></html>
"""
                return HTMLResponse(content=html_empty)

            item_ids: list[str] = []
            acc_ids: set[str] = set()
            for fid, acc_id, ftype, name, city, category in rows:
                try:
                    item_ids.append(str(fid))
                except Exception:
                    continue
                if acc_id is not None:
                    acc_ids.add(str(acc_id))

            likes_map: dict[str, int] = {}
            views_map: dict[str, int] = {}
            comments_map: dict[str, int] = {}

            if item_ids:
                try:
                    like_rows = (
                        s.execute(
                            _sa_select(
                                ChannelLikeDB.item_id,
                                _sa_func.count(ChannelLikeDB.id),
                            )
                            .where(ChannelLikeDB.item_id.in_(item_ids))
                            .group_by(ChannelLikeDB.item_id)
                        )
                        .all()
                    )
                    for iid, cnt in like_rows:
                        try:
                            likes_map[str(iid)] = int(cnt or 0)
                        except Exception:
                            continue
                except Exception:
                    likes_map = {}
                try:
                    view_rows = (
                        s.execute(
                            _sa_select(
                                ChannelViewDB.item_id,
                                ChannelViewDB.views,
                            ).where(ChannelViewDB.item_id.in_(item_ids))
                        )
                        .all()
                    )
                    for iid, views in view_rows:
                        try:
                            views_map[str(iid)] = int(views or 0)
                        except Exception:
                            continue
                except Exception:
                    views_map = {}
                try:
                    comment_rows = (
                        s.execute(
                            _sa_select(
                                ChannelCommentDB.item_id,
                                _sa_func.count(ChannelCommentDB.id),
                            )
                            .where(ChannelCommentDB.item_id.in_(item_ids))
                            .group_by(ChannelCommentDB.item_id)
                        )
                        .all()
                    )
                    for iid, cnt in comment_rows:
                        try:
                            comments_map[str(iid)] = int(cnt or 0)
                        except Exception:
                            continue
                except Exception:
                    comments_map = {}

            hot_accounts: set[str] = set()
            try:
                if acc_ids:
                    with _moments_session() as ms:
                        agg_rows = (
                            ms.execute(
                                _sa_select(
                                    MomentPostDB.origin_official_account_id,
                                    _sa_func.count(MomentPostDB.id),
                                )
                                .where(
                                    MomentPostDB.origin_official_account_id.in_(
                                        list(acc_ids)
                                    )
                                )
                                .group_by(MomentPostDB.origin_official_account_id)
                            )
                            .all()
                        )
                        for acc_id, cnt in agg_rows:
                            try:
                                if int(cnt or 0) >= 10:
                                    hot_accounts.add(str(acc_id))
                            except Exception:
                                continue
            except Exception:
                hot_accounts = set()

            per_acc: dict[str, dict[str, Any]] = {}
            for fid, acc_id, ftype, name, city, category in rows:
                acc_key = str(acc_id) if acc_id is not None else ""
                if not acc_key:
                    continue
                acc = per_acc.setdefault(
                    acc_key,
                    {
                        "id": acc_key,
                        "name": name or "",
                        "city": city or "",
                        "category": category or "",
                        "clips": 0,
                        "views": 0,
                        "likes": 0,
                        "comments": 0,
                        "campaign_clips": 0,
                        "hot_in_moments": acc_key in hot_accounts,
                    },
                )
                acc["clips"] += 1
                item_id = str(fid)
                acc["views"] += views_map.get(item_id, 0)
                acc["likes"] += likes_map.get(item_id, 0)
                acc["comments"] += comments_map.get(item_id, 0)
                f_type = (ftype or "").strip().lower()
                if f_type in {"campaign", "promo"}:
                    acc["campaign_clips"] += 1

        rows_list: list[dict[str, Any]] = list(per_acc.values())
        for acc in rows_list:
            try:
                clips = int(acc.get("clips", 0) or 0)
                views = int(acc.get("views", 0) or 0)
                likes = int(acc.get("likes", 0) or 0)
                comments = int(acc.get("comments", 0) or 0)
            except Exception:
                clips = views = likes = comments = 0
            score = 0.0
            if clips > 0:
                try:
                    score = (views / max(clips, 1)) * 0.1 + (likes * 0.5) + (comments * 1.0)
                except Exception:
                    score = 0.0
            if acc.get("hot_in_moments"):
                score += 5.0
            acc["score"] = score

        rows_list.sort(key=lambda x: float(x.get("score") or 0.0), reverse=True)

        def esc(s: str) -> str:
            return _html.escape(s or "", quote=True)

        rows_html: list[str] = []
        for acc in rows_list:
            aid = str(acc.get("id", ""))
            name = str(acc.get("name", ""))
            city = str(acc.get("city", ""))
            category = str(acc.get("category", ""))
            clips = int(acc.get("clips", 0) or 0)
            views = int(acc.get("views", 0) or 0)
            likes = int(acc.get("likes", 0) or 0)
            comments = int(acc.get("comments", 0) or 0)
            campaigns = int(acc.get("campaign_clips", 0) or 0)
            score = float(acc.get("score", 0.0) or 0.0)
            hot = bool(acc.get("hot_in_moments", False))
            rows_html.append(
                "<tr>"
                f"<td><code>{esc(aid)}</code></td>"
                f"<td>{esc(name)}</td>"
                f"<td>{esc(city)}</td>"
                f"<td>{esc(category)}</td>"
                f"<td>{clips}</td>"
                f"<td>{campaigns}</td>"
                f"<td>{views}</td>"
                f"<td>{likes}</td>"
                f"<td>{comments}</td>"
                f"<td>{score:.1f}</td>"
                f"<td>{'✅' if hot else ''}</td>"
                "</tr>"
            )

        html = f"""
<!doctype html>
<html><head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Channels · Analytics</title>
  <style>
    body{{font-family:sans-serif;margin:20px;max-width:1080px;color:#0f172a;}}
    h1{{margin-bottom:4px;}}
    table{{border-collapse:collapse;width:100%;margin-top:12px;}}
    th,td{{padding:6px 8px;border-bottom:1px solid #e5e7eb;font-size:13px;text-align:left;vertical-align:top;}}
    th{{background:#f9fafb;font-weight:600;}}
    .meta{{color:#6b7280;font-size:12px;margin-top:2px;}}
    code{{background:#f3f4f6;padding:2px 4px;border-radius:3px;font-size:12px;}}
  </style>
</head><body>
  <h1>Channels · Analytics</h1>
  <div class="meta">
    Per-Account-Übersicht der Channels-Performance (Clips, Views, Likes, Comments) mit
    einfachem Engagement-Score und einem "Hot in Moments"-Flag – angelehnt an WeChat Channels.
  </div>
  <p class="meta">
    <a href="/admin/officials/analytics">Zurück zu Official-Analytics</a>
  </p>
  <table>
    <thead>
      <tr>
        <th>Account ID</th>
        <th>Name</th>
        <th>City</th>
        <th>Category</th>
        <th>Clips</th>
        <th>Campaigns</th>
        <th>Views</th>
        <th>Likes</th>
        <th>Comments</th>
        <th>Engagement score</th>
        <th>Hot in Moments</th>
      </tr>
    </thead>
    <tbody>
      {''.join(rows_html) if rows_html else '<tr><td colspan="11">No data.</td></tr>'}
    </tbody>
  </table>
</body></html>
"""
        return HTMLResponse(content=html)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/admin/redpacket_campaigns/analytics", response_class=HTMLResponse)
def admin_redpacket_campaigns_analytics(request: Request) -> HTMLResponse:
    """
    Lightweight HTML analytics for Red‑Packet campaigns.

    Aggregates Moments shares per campaign (based on origin_official_item_id)
    to provide WeChat‑ähnliche KPIs pro Kampagne.
    """
    _require_admin_v2(request)
    try:
        with _officials_session() as s:
            campaigns = (
                s.execute(
                    _sa_select(RedPacketCampaignDB).order_by(
                        RedPacketCampaignDB.created_at.desc()
                    )
                )
                .scalars()
                .all()
            )
            accounts_by_id: dict[str, OfficialAccountDB] = {}
            if campaigns:
                acc_ids = {c.account_id for c in campaigns}
                acc_rows = (
                    s.execute(
                        _sa_select(OfficialAccountDB).where(
                            OfficialAccountDB.id.in_(list(acc_ids))
                        )
                    )
                    .scalars()
                    .all()
                )
                for acc in acc_rows:
                    accounts_by_id[acc.id] = acc

        # Aggregate Moments metrics per campaign (keyed by origin_official_item_id)
        moments_total: dict[str, int] = {}
        moments_30d: dict[str, int] = {}
        uniq_total: dict[str, int] = {}
        uniq_30d: dict[str, int] = {}
        last_ts: dict[str, str] = {}
        try:
            with _moments_session() as ms:
                since_30d = datetime.now(timezone.utc) - timedelta(days=30)
                base_stmt = _sa_select(
                    MomentPostDB.origin_official_item_id,
                    _sa_func.count(MomentPostDB.id),
                ).where(MomentPostDB.origin_official_item_id.is_not(None))
                # All-time totals
                rows = ms.execute(
                    base_stmt.group_by(MomentPostDB.origin_official_item_id)
                ).all()
                for cid, cnt in rows:
                    if not cid:
                        continue
                    moments_total[str(cid)] = int(cnt or 0)
                # Last 30 days totals
                rows_30 = ms.execute(
                    base_stmt.where(MomentPostDB.created_at >= since_30d).group_by(
                        MomentPostDB.origin_official_item_id
                    )
                ).all()
                for cid, cnt in rows_30:
                    if not cid:
                        continue
                    moments_30d[str(cid)] = int(cnt or 0)
                # Unique sharers (all time)
                uniq_stmt = _sa_select(
                    MomentPostDB.origin_official_item_id,
                    _sa_func.count(_sa_func.distinct(MomentPostDB.user_key)),
                ).where(MomentPostDB.origin_official_item_id.is_not(None))
                u_rows = ms.execute(
                    uniq_stmt.group_by(MomentPostDB.origin_official_item_id)
                ).all()
                for cid, cnt in u_rows:
                    if not cid:
                        continue
                    uniq_total[str(cid)] = int(cnt or 0)
                # Unique sharers (30d)
                u_rows_30 = ms.execute(
                    uniq_stmt.where(MomentPostDB.created_at >= since_30d).group_by(
                        MomentPostDB.origin_official_item_id
                    )
                ).all()
                for cid, cnt in u_rows_30:
                    if not cid:
                        continue
                    uniq_30d[str(cid)] = int(cnt or 0)
                # Last post timestamp per campaign
                ts_rows = ms.execute(
                    _sa_select(
                        MomentPostDB.origin_official_item_id,
                        _sa_func.max(MomentPostDB.created_at),
                    )
                    .where(MomentPostDB.origin_official_item_id.is_not(None))
                    .group_by(MomentPostDB.origin_official_item_id)
                ).all()
                for cid, ts in ts_rows:
                    if not cid or ts is None:
                        continue
                    try:
                        ts_str = ts.isoformat().replace("+00:00", "Z")
                    except Exception:
                        ts_str = str(ts)
                    last_ts[str(cid)] = ts_str
        except Exception:
            moments_total = {}
            moments_30d = {}
            uniq_total = {}
            uniq_30d = {}
            last_ts = {}

        # Optional Payments KPIs per campaign (best-effort via PAYMENTS_BASE)
        payments_stats: dict[str, dict[str, Any]] = {}
        try:
            if PAYMENTS_BASE and campaigns:
                base = PAYMENTS_BASE.rstrip("/")
                for camp in campaigns:
                    cid = camp.id
                    try:
                        url = f"{base}/admin/redpacket_campaigns/payments_analytics"
                        r = httpx.get(
                            url,
                            headers=_payments_headers(),
                            params={"campaign_id": cid},
                            timeout=5.0,
                        )
                        if (
                            r.status_code == 200
                            and r.headers.get("content-type", "").startswith("application/json")
                        ):
                            data = r.json()
                            if isinstance(data, dict):
                                payments_stats[cid] = data
                    except Exception:
                        # Soft-fail; payments KPIs are optional
                        continue
        except Exception:
            payments_stats = {}

        def esc(s: str) -> str:
            return _html.escape(s or "", quote=True)

        rows_html: list[str] = []
        for camp in campaigns:
            cid = camp.id
            acc = accounts_by_id.get(camp.account_id)
            cname = camp.title or ""
            aname = acc.name if acc else camp.account_id
            kind = acc.kind if acc else ""
            total = moments_total.get(cid, 0)
            total_30 = moments_30d.get(cid, 0)
            utotal = uniq_total.get(cid, 0)
            u30 = uniq_30d.get(cid, 0)
            ts_str = last_ts.get(cid, "")
            status = "active" if getattr(camp, "active", True) else "inactive"
            ps = payments_stats.get(cid) or {}
            try:
                issued = int(ps.get("total_packets_issued", 0) or 0)
            except Exception:
                issued = 0
            try:
                claimed = int(ps.get("total_packets_claimed", 0) or 0)
            except Exception:
                claimed = 0
            try:
                amt_total = int(ps.get("total_amount_cents", 0) or 0)
            except Exception:
                amt_total = 0
            try:
                amt_claimed = int(ps.get("claimed_amount_cents", 0) or 0)
            except Exception:
                amt_claimed = 0
            try:
                def_amt = int(getattr(camp, "default_amount_cents", 0) or 0)
            except Exception:
                def_amt = 0
            try:
                def_count = int(getattr(camp, "default_count", 0) or 0)
            except Exception:
                def_count = 0
            rows_html.append(
                "<tr>"
                f"<td><a href=\"/admin/redpacket_campaigns/detail?campaign_id={esc(cid)}\"><code>{esc(cid)}</code></a></td>"
                f"<td>{esc(cname)}</td>"
                f"<td>{esc(aname or '')}</td>"
                f"<td>{esc(kind or '')}</td>"
                f"<td>{status}</td>"
                f"<td>{total}</td>"
                f"<td>{total_30}</td>"
                f"<td>{utotal}</td>"
                f"<td>{u30}</td>"
                f"<td><span class=\"meta\">{esc(ts_str)}</span></td>"
                f"<td>{issued}</td>"
                f"<td>{claimed}</td>"
                f"<td>{amt_total}</td>"
                f"<td>{amt_claimed}</td>"
                f"<td>{def_amt if def_amt > 0 else ''}</td>"
                f"<td>{def_count if def_count > 0 else ''}</td>"
                "</tr>"
            )

        html = f"""
<!doctype html>
<html><head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Red‑Packet Campaigns · Analytics</title>
  <style>
    body{{font-family:sans-serif;margin:20px;max-width:1100px;color:#0f172a;}}
    h1{{margin-bottom:4px;}}
    table{{border-collapse:collapse;width:100%;margin-top:12px;}}
    th,td{{padding:6px 8px;border-bottom:1px solid #e5e7eb;font-size:13px;text-align:left;vertical-align:top;}}
    th{{background:#f9fafb;font-weight:600;}}
    .meta{{color:#6b7280;font-size:12px;margin-top:2px;}}
    code{{background:#f3f4f6;padding:2px 4px;border-radius:3px;font-size:12px;}}
  </style>
</head><body>
  <h1>Red‑Packet Campaigns · Analytics</h1>
  <div class="meta">
    Based on Moments posts tagged with shamell://official/&lt;account&gt;/&lt;campaign_id&gt;
    (origin_official_item_id = campaign_id). Best-effort, WeChat‑ähnliche Kampagnen-Sicht.
  </div>
  <p class="meta">
    <a href="/admin/officials">Zurück zur Official-Admin-Konsole</a>
  </p>
  <table>
    <thead>
      <tr>
        <th>Campaign ID</th>
        <th>Title</th>
        <th>Account</th>
        <th>Kind</th>
        <th>Status</th>
        <th>Moments shares</th>
        <th>Moments (30d)</th>
        <th>Unique sharers</th>
        <th>Unique sharers (30d)</th>
        <th>Last share TS</th>
        <th>Packets issued</th>
        <th>Packets claimed</th>
        <th>Amount (total cents)</th>
        <th>Amount (claimed cents)</th>
        <th>Default amount (cents)</th>
        <th>Default count</th>
      </tr>
    </thead>
    <tbody>
      {''.join(rows_html) if rows_html else '<tr><td colspan="16">No Red‑Packet campaigns configured.</td></tr>'}
    </tbody>
  </table>
</body></html>
"""
        return HTMLResponse(content=html)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/admin/redpacket_campaigns/detail", response_class=HTMLResponse)
def admin_redpacket_campaign_detail(
    request: Request, campaign_id: str
) -> HTMLResponse:
    """
    Detailansicht für eine einzelne Red‑Packet‑Kampagne.

    Kombiniert Stammdaten, Moments‑KPI und Payments‑KPI – WeChat‑ähnlich.
    """
    _require_admin_v2(request)
    try:
        # Load campaign + owning Official account
        with _officials_session() as s:
            camp = s.get(RedPacketCampaignDB, campaign_id)
            if not camp:
                raise HTTPException(status_code=404, detail="campaign not found")
            acc = s.get(OfficialAccountDB, camp.account_id)

        # Moments metrics for this campaign (origin_official_item_id == campaign_id)
        moments_total = 0
        moments_30d = 0
        uniq_total = 0
        uniq_30d = 0
        last_share_ts = ""
        posts: list[MomentPostDB] = []
        likes_map: dict[int, int] = {}
        comments_map: dict[int, int] = {}
        try:
            since_30d = datetime.now(timezone.utc) - timedelta(days=30)
            with _moments_session() as ms:
                moments_total = (
                    ms.execute(
                        _sa_select(_sa_func.count(MomentPostDB.id)).where(
                            MomentPostDB.origin_official_item_id == campaign_id
                        )
                    )
                    .scalar()
                    or 0
                )
                moments_30d = (
                    ms.execute(
                        _sa_select(_sa_func.count(MomentPostDB.id)).where(
                            MomentPostDB.origin_official_item_id == campaign_id,
                            MomentPostDB.created_at >= since_30d,
                        )
                    )
                    .scalar()
                    or 0
                )
                uniq_total = (
                    ms.execute(
                        _sa_select(
                            _sa_func.count(
                                _sa_func.distinct(MomentPostDB.user_key)
                            )
                        ).where(
                            MomentPostDB.origin_official_item_id
                            == campaign_id
                        )
                    )
                    .scalar()
                    or 0
                )
                uniq_30d = (
                    ms.execute(
                        _sa_select(
                            _sa_func.count(
                                _sa_func.distinct(MomentPostDB.user_key)
                            )
                        ).where(
                            MomentPostDB.origin_official_item_id
                            == campaign_id,
                            MomentPostDB.created_at >= since_30d,
                        )
                    )
                    .scalar()
                    or 0
                )
                last_row = (
                    ms.execute(
                        _sa_select(_sa_func.max(MomentPostDB.created_at)).where(
                            MomentPostDB.origin_official_item_id == campaign_id
                        )
                    )
                    .scalar()
                    or None
                )
                if last_row is not None:
                    try:
                        last_share_ts = (
                            last_row.isoformat().replace("+00:00", "Z")
                            if isinstance(last_row, datetime)
                            else str(last_row)
                        )
                    except Exception:
                        last_share_ts = str(last_row)
                # Latest posts for QA table
                posts = (
                    ms.execute(
                        _sa_select(MomentPostDB)
                        .where(MomentPostDB.origin_official_item_id == campaign_id)
                        .order_by(
                            MomentPostDB.created_at.desc(), MomentPostDB.id.desc()
                        )
                        .limit(100)
                    )
                    .scalars()
                    .all()
                )
                post_ids = [p.id for p in posts]
                if post_ids:
                    likes_rows = (
                        ms.execute(
                            _sa_select(
                                MomentLikeDB.post_id,
                                _sa_func.count(MomentLikeDB.id),
                            ).where(MomentLikeDB.post_id.in_(post_ids))
                            .group_by(MomentLikeDB.post_id)
                        )
                        .all()
                    )
                    for pid, cnt in likes_rows:
                        likes_map[int(pid)] = int(cnt or 0)
                    comments_rows = (
                        ms.execute(
                            _sa_select(
                                MomentCommentDB.post_id,
                                _sa_func.count(MomentCommentDB.id),
                            ).where(MomentCommentDB.post_id.in_(post_ids))
                            .group_by(MomentCommentDB.post_id)
                        )
                        .all()
                    )
                    for pid, cnt in comments_rows:
                        comments_map[int(pid)] = int(cnt or 0)
        except Exception:
            moments_total = 0
            moments_30d = 0
            uniq_total = 0
            uniq_30d = 0
            last_share_ts = ""
            posts = []
            likes_map = {}
            comments_map = {}

        # Optional Payments metrics via PAYMENTS_BASE
        payments_data: dict[str, Any] = {}
        try:
            if PAYMENTS_BASE:
                base = PAYMENTS_BASE.rstrip("/")
                url = f"{base}/admin/redpacket_campaigns/payments_analytics"
                r = httpx.get(
                    url, headers=_payments_headers(), params={"campaign_id": campaign_id}, timeout=5.0
                )
                if (
                    r.status_code == 200
                    and r.headers.get("content-type", "").startswith(
                        "application/json"
                    )
                ):
                    data = r.json()
                    if isinstance(data, dict):
                        payments_data = data
        except Exception:
            payments_data = {}

        def esc(s: str) -> str:
            return _html.escape(s or "", quote=True)

        def_amt = getattr(camp, "default_amount_cents", None) or 0
        def_count = getattr(camp, "default_count", None) or 0
        note = getattr(camp, "note", "") or ""
        status = "active" if getattr(camp, "active", True) else "inactive"
        acc_name = acc.name if acc else camp.account_id
        acc_kind = acc.kind if acc else ""

        total_packets_issued = int(payments_data.get("total_packets_issued", 0) or 0)
        total_packets_claimed = int(
            payments_data.get("total_packets_claimed", 0) or 0
        )
        total_amount_cents = int(
            payments_data.get("total_amount_cents", 0) or 0
        )
        claimed_amount_cents = int(
            payments_data.get("claimed_amount_cents", 0) or 0
        )

        rows_html: list[str] = []
        for p in posts:
            pts = p.created_at
            pts_str = (
                pts.isoformat().replace("+00:00", "Z")
                if isinstance(pts, datetime)
                else datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
            )
            likes = likes_map.get(p.id, 0)
            comments = comments_map.get(p.id, 0)
            text = (p.text or "")[:260]
            rows_html.append(
                "<tr>"
                f"<td>{p.id}</td>"
                f"<td><pre>{esc(p.user_key or '')}</pre></td>"
                f"<td><span class=\"meta\">{esc(pts_str)}</span></td>"
                f"<td>{likes}</td>"
                f"<td>{comments}</td>"
                f"<td><pre>{esc(text)}</pre></td>"
                f"<td><a href=\"/moments/admin/comments/html?post_id={p.id}"
                + (
                    f"&official_account_id={esc(camp.account_id)}"
                    if camp.account_id
                    else ""
                )
                + "\">Comments</a></td>"
                "</tr>"
            )

        html = f"""
<!doctype html>
<html><head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Red‑Packet Campaign · {esc(campaign_id)}</title>
  <style>
    body{{font-family:sans-serif;margin:20px;max-width:1100px;color:#0f172a;}}
    h1{{margin-bottom:4px;}}
    h2{{margin-top:20px;margin-bottom:6px;}}
    table{{border-collapse:collapse;width:100%;margin-top:8px;}}
    th,td{{padding:6px 8px;border-bottom:1px solid #e5e7eb;font-size:13px;text-align:left;vertical-align:top;}}
    th{{background:#f9fafb;font-weight:600;}}
    .meta{{color:#6b7280;font-size:12px;margin-top:2px;}}
    code{{background:#f3f4f6;padding:2px 4px;border-radius:3px;font-size:12px;}}
  </style>
</head><body>
  <h1>Red‑Packet Campaign · <code>{esc(campaign_id)}</code></h1>
  <p class="meta">
    <a href="/admin/redpacket_campaigns/analytics">Zurück zur Kampagnen-Übersicht</a>
    · <a href="/admin/officials">Official-Admin-Konsole</a>
  </p>

  <h2>Stammdaten</h2>
  <table>
    <tbody>
      <tr><th>Campaign ID</th><td><code>{esc(campaign_id)}</code></td></tr>
      <tr><th>Title</th><td>{esc(camp.title or "")}</td></tr>
      <tr><th>Account</th><td>{esc(acc_name or "")} <span class="meta">({esc(camp.account_id)})</span></td></tr>
      <tr><th>Kind</th><td>{esc(acc_kind or "")}</td></tr>
      <tr><th>Status</th><td>{status}</td></tr>
      <tr><th>Default amount (cents)</th><td>{def_amt if def_amt else ''}</td></tr>
      <tr><th>Default count</th><td>{def_count if def_count else ''}</td></tr>
      <tr><th>Note</th><td>{esc(note)}</td></tr>
    </tbody>
  </table>

  <h2>Moments · Social Impact</h2>
  <table>
    <tbody>
      <tr><th>Moments shares (all time)</th><td>{moments_total}</td></tr>
      <tr><th>Moments shares (30d)</th><td>{moments_30d}</td></tr>
      <tr><th>Unique sharers (all time)</th><td>{uniq_total}</td></tr>
      <tr><th>Unique sharers (30d)</th><td>{uniq_30d}</td></tr>
      <tr><th>Last share TS</th><td><span class="meta">{esc(last_share_ts)}</span></td></tr>
    </tbody>
  </table>
  <p class="meta">
    QA‑Links:
    <a href="/moments/admin/html?campaign_id={esc(campaign_id)}&limit=200">Moments Admin (nur diese Kampagne)</a>
    · <a href="/moments/admin/html?redpacket_only=1">Alle Red‑Packet‑Moments</a>
  </p>

  <h2>Payments · Red‑Packets</h2>
  <table>
    <tbody>
      <tr><th>Packets issued</th><td>{total_packets_issued}</td></tr>
      <tr><th>Packets claimed</th><td>{total_packets_claimed}</td></tr>
      <tr><th>Amount total (cents)</th><td>{total_amount_cents}</td></tr>
      <tr><th>Amount claimed (cents)</th><td>{claimed_amount_cents}</td></tr>
    </tbody>
  </table>

  <h2>Moments · Letzte Posts (QA)</h2>
  <table>
    <thead>
      <tr>
        <th>ID</th>
        <th>User</th>
        <th>Created</th>
        <th>Likes</th>
        <th>Comments</th>
        <th>Text (truncated)</th>
        <th>Actions</th>
      </tr>
    </thead>
    <tbody>
      {''.join(rows_html) if rows_html else '<tr><td colspan="7">No Moments posts for this campaign yet.</td></tr>'}
    </tbody>
  </table>
</body></html>
"""
        return HTMLResponse(content=html)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get(
    "/official_accounts/{account_id}/campaigns/{campaign_id}/top_moments",
    response_class=JSONResponse,
)
def official_campaign_top_moments(
    account_id: str, campaign_id: str, limit: int = 5
) -> dict[str, Any]:
    """
    Returns top Moments posts for a single Red‑Packet campaign.

    This powers a WeChat‑style in‑app ranking of the most engaging
    Red‑Packet Moments per campaign (based on likes, comments and
    recency) in merchant UIs.
    """
    cid = (campaign_id or "").strip()
    if not cid:
        raise HTTPException(status_code=400, detail="campaign_id required")
    try:
        with _officials_session() as s:
            camp = s.get(RedPacketCampaignDB, cid)
            if not camp or camp.account_id != account_id:
                raise HTTPException(status_code=404, detail="campaign not found")
        try:
            limit_val = max(1, min(limit, 20))
        except Exception:
            limit_val = 5
        items: list[RedPacketCampaignTopMomentOut] = []
        try:
            with _moments_session() as ms:
                posts = (
                    ms.execute(
                        _sa_select(MomentPostDB)
                        .where(MomentPostDB.origin_official_item_id == cid)
                        .order_by(
                            MomentPostDB.created_at.desc(),
                            MomentPostDB.id.desc(),
                        )
                        .limit(100)
                    )
                    .scalars()
                    .all()
                )
                if posts:
                    post_ids = [p.id for p in posts]
                    likes_map: dict[int, int] = {}
                    comments_map: dict[int, int] = {}
                    try:
                        likes_rows = (
                            ms.execute(
                                _sa_select(
                                    MomentLikeDB.post_id,
                                    _sa_func.count(MomentLikeDB.id),
                                )
                                .where(MomentLikeDB.post_id.in_(post_ids))
                                .group_by(MomentLikeDB.post_id)
                            )
                            .all()
                        )
                        for pid, cnt in likes_rows:
                            try:
                                likes_map[int(pid)] = int(cnt or 0)
                            except Exception:
                                continue
                    except Exception:
                        likes_map = {}
                    try:
                        comments_rows = (
                            ms.execute(
                                _sa_select(
                                    MomentCommentDB.post_id,
                                    _sa_func.count(MomentCommentDB.id),
                                )
                                .where(MomentCommentDB.post_id.in_(post_ids))
                                .group_by(MomentCommentDB.post_id)
                            )
                            .all()
                        )
                        for pid, cnt in comments_rows:
                            try:
                                comments_map[int(pid)] = int(cnt or 0)
                            except Exception:
                                continue
                    except Exception:
                        comments_map = {}
                    now = datetime.now(timezone.utc)
                    scored: list[tuple[float, RedPacketCampaignTopMomentOut]] = []
                    for p in posts:
                        try:
                            pid = int(p.id)
                        except Exception:
                            continue
                        likes = likes_map.get(pid, 0)
                        comments = comments_map.get(pid, 0)
                        ts = getattr(p, "created_at", None)
                        if isinstance(ts, datetime):
                            ts_str = ts.isoformat().replace("+00:00", "Z")
                            age_days = max(0.0, (now - ts).total_seconds() / 86400.0)
                        else:
                            ts_str = None
                            age_days = 0.0
                        # Simple engagement score: likes & comments with
                        # a mild recency boost (newer posts slightly ahead).
                        score = float(likes * 2 + comments * 3)
                        try:
                            if age_days > 0.0:
                                score = score + max(0.0, 5.0 - age_days)
                        except Exception:
                            pass
                        text = (getattr(p, "text", "") or "")[:140]
                        scored.append(
                            (
                                score,
                                RedPacketCampaignTopMomentOut(
                                    post_id=pid,
                                    text=text,
                                    ts=ts_str,
                                    likes=likes,
                                    comments=comments,
                                    score=score,
                                ),
                            )
                        )
                    if scored:
                        scored.sort(key=lambda t: t[0], reverse=True)
                        for _, item in scored[:limit_val]:
                            items.append(item)
        except Exception:
            items = []
        return {"items": [i.dict() for i in items]}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/official_accounts", response_class=JSONResponse)
async def list_official_accounts(request: Request, kind: str | None = None, followed_only: bool = True):
    ck = _official_cookie_key(request)
    try:
        with _officials_session() as s:
            stmt = _sa_select(OfficialAccountDB).where(OfficialAccountDB.enabled == True)  # type: ignore[comparison-overlap]
            if kind:
                stmt = stmt.where(OfficialAccountDB.kind == kind)
            accounts = list(s.execute(stmt).scalars().all())
            # Active Red‑Packet campaigns per Official (for badges in directory / search).
            campaign_counts: dict[str, int] = {}
            try:
                acc_ids_campaign = [acc.id for acc in accounts]
                if acc_ids_campaign:
                    camp_rows = (
                        s.execute(
                            _sa_select(
                                RedPacketCampaignDB.account_id,
                                _sa_func.count(RedPacketCampaignDB.id),
                            )
                            .where(
                                RedPacketCampaignDB.account_id.in_(acc_ids_campaign),
                                RedPacketCampaignDB.active.is_(True),
                            )
                            .group_by(RedPacketCampaignDB.account_id)
                        )
                        .all()
                    )
                    for acc_id, cnt in camp_rows:
                        try:
                            campaign_counts[str(acc_id)] = int(cnt or 0)
                        except Exception:
                            continue
            except Exception:
                campaign_counts = {}
            # Best-effort Moments share counts per Official (global, all users).
            moments_shares: dict[str, int] = {}
            try:
                acc_ids = [acc.id for acc in accounts]
                if acc_ids:
                    with _moments_session() as ms:
                        mrows = (
                            ms.execute(
                                _sa_select(
                                    MomentPostDB.origin_official_account_id,
                                    _sa_func.count(MomentPostDB.id),
                                )
                                .where(
                                    MomentPostDB.origin_official_account_id.in_(
                                        acc_ids
                                    )
                                )
                                .group_by(MomentPostDB.origin_official_account_id)
                            )
                            .all()
                        )
                        for acc_id, cnt in mrows:
                            try:
                                moments_shares[str(acc_id)] = int(cnt or 0)
                            except Exception:
                                continue
            except Exception:
                moments_shares = {}
            notif_modes: dict[str, str] = {}
            try:
                notif_rows = (
                    s.execute(
                        _sa_select(OfficialNotificationDB).where(
                            OfficialNotificationDB.user_key == ck
                        )
                    )
                    .scalars()
                    .all()
                )
                for row in notif_rows:
                    if row.mode:
                        notif_modes[row.account_id] = row.mode
            except Exception:
                notif_modes = {}
            followed_ids = set(
                s.execute(
                    _sa_select(OfficialFollowDB.account_id).where(OfficialFollowDB.user_key == ck)
                ).scalars().all()
            )
            if not followed_ids and accounts:
                for acc in accounts:
                    s.add(OfficialFollowDB(user_key=ck, account_id=acc.id))
                s.commit()
                followed_ids = {acc.id for acc in accounts}
            items: list[dict[str, Any]] = []
            for acc in accounts:
                is_followed = acc.id in followed_ids
                if followed_only and not is_followed:
                    continue
                last_item_dict: dict[str, Any] | None = None
                try:
                    fi_stmt = (
                        _sa_select(OfficialFeedItemDB)
                        .where(OfficialFeedItemDB.account_id == acc.id)
                        .order_by(OfficialFeedItemDB.ts.desc(), OfficialFeedItemDB.id.desc())
                        .limit(1)
                    )
                    fi = s.execute(fi_stmt).scalars().first()
                except Exception:
                    fi = None
                if fi is not None:
                    try:
                        deeplink = _json.loads(fi.deeplink_json) if fi.deeplink_json else None
                    except Exception:
                        deeplink = None
                    last_item_dict = {
                        "id": fi.slug or str(fi.id),
                        "type": fi.type,
                        "title": fi.title,
                        "snippet": fi.snippet,
                        "thumb_url": fi.thumb_url,
                        "ts": fi.ts.isoformat() if getattr(fi, "ts", None) else None,
                        "deeplink": deeplink,
                    }
                data = {
                    "id": acc.id,
                    "kind": acc.kind,
                    "name": acc.name,
                    "name_ar": acc.name_ar,
                    "avatar_url": acc.avatar_url,
                    "verified": acc.verified,
                    "mini_app_id": acc.mini_app_id,
                    "description": acc.description,
                    "chat_peer_id": getattr(acc, "chat_peer_id", None),
                    "category": getattr(acc, "category", None),
                    "city": getattr(acc, "city", None),
                    "address": getattr(acc, "address", None),
                    "opening_hours": getattr(acc, "opening_hours", None),
                    "website_url": getattr(acc, "website_url", None),
                    "qr_payload": getattr(acc, "qr_payload", None),
                    "featured": getattr(acc, "featured", False),
                    "unread_count": 0,
                    "last_item": last_item_dict,
                    "followed": is_followed,
                }
                # Include global Moments share count for this Official as a
                # lightweight "hotness" indicator (used in Moments filters).
                try:
                    data["moments_total_shares"] = int(
                        moments_shares.get(acc.id, 0)
                    )
                except Exception:
                    data["moments_total_shares"] = 0
                try:
                    data["campaigns_active"] = int(
                        campaign_counts.get(acc.id, 0)
                    )
                except Exception:
                    data["campaigns_active"] = 0
                if acc.id in notif_modes:
                    data["notif_mode"] = notif_modes[acc.id]
                menu_items = _official_menu_items_for(acc)
                if menu_items:
                    data["menu_items"] = menu_items
                items.append(data)
        try:
            emit_event(
                "officials",
                "accounts_listed",
                {
                    "user_key": ck,
                    "kind": kind,
                    "followed_only": followed_only,
                    "count": len(items),
                },
            )
        except Exception:
            pass
        return {"accounts": items}
    except HTTPException:
        raise
    except Exception:
        followed = _OFFICIAL_FOLLOWS.get(ck) or set(_OFFICIAL_ACCOUNTS.keys())
        fallback_items: list[dict[str, Any]] = []
        for acc in _OFFICIAL_ACCOUNTS.values():
            if kind and acc.kind != kind:
                continue
            is_followed = acc.id in followed
            if followed_only and not is_followed:
                continue
            data = acc.dict()
            data["followed"] = is_followed
            fallback_items.append(data)
        try:
            emit_event(
                "officials",
                "accounts_listed",
                {
                    "user_key": ck,
                    "kind": kind,
                    "followed_only": followed_only,
                    "count": len(fallback_items),
                    "mode": "fallback",
                },
            )
        except Exception:
            pass
        return {"accounts": fallback_items}


@app.post("/official_accounts/self_register", response_class=JSONResponse)
def official_account_self_register(
    request: Request, body: OfficialAccountSelfRegisterIn
) -> dict[str, Any]:
    """
    Self‑service registration endpoint for Official accounts.

    A logged‑in merchant can propose a new WeChat‑style Official
    account. The request is stored separately and can later be
    reviewed and approved by ops before an OfficialAccountDB row is
    created.
    """
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="auth required")
    account_id = (body.account_id or "").strip()
    if not account_id:
        raise HTTPException(status_code=400, detail="account_id required")
    # Simple slug validation similar to Mini‑Programs.
    for ch in account_id:
        if not (ch.islower() or ch.isdigit() or ch in {"_", "-"}):
            raise HTTPException(
                status_code=400,
                detail="account_id may only contain lowercase letters, digits, '_' or '-'",
            )
    kind = (body.kind or "service").strip().lower()
    if kind not in {"service", "subscription"}:
        raise HTTPException(status_code=400, detail="kind must be 'service' or 'subscription'")
    name = (body.name or "").strip()
    if not name:
        raise HTTPException(status_code=400, detail="name required")
    owner_name = (body.owner_name or "").strip()
    if not owner_name:
        owner_name = f"Merchant {phone}"
    contact_phone = (body.contact_phone or "").strip()
    if not contact_phone:
        contact_phone = phone
    contact_email = (body.contact_email or "").strip() or None
    try:
        with _officials_session() as s:
            # Prevent registering an ID that already exists as an Official.
            existing_acc = s.get(OfficialAccountDB, account_id)
            if existing_acc:
                raise HTTPException(status_code=409, detail="official account with this id already exists")
            # Allow the same requester to update their latest request; others must use a different id.
            existing_req = (
                s.execute(
                    _sa_select(OfficialAccountRequestDB)
                    .where(
                        OfficialAccountRequestDB.account_id == account_id,
                        OfficialAccountRequestDB.requester_phone == phone,
                    )
                    .order_by(OfficialAccountRequestDB.id.desc())
                )
                .scalars()
                .first()
            )
            if existing_req:
                existing_req.kind = kind
                existing_req.name = name
                if body.name_ar is not None:
                    existing_req.name_ar = body.name_ar
                if body.description is not None:
                    existing_req.description = body.description
                if body.category is not None:
                    existing_req.category = body.category
                if body.city is not None:
                    existing_req.city = body.city
                if body.address is not None:
                    existing_req.address = body.address
                if body.opening_hours is not None:
                    existing_req.opening_hours = body.opening_hours
                if body.website_url is not None:
                    existing_req.website_url = body.website_url
                if body.mini_app_id is not None:
                    existing_req.mini_app_id = body.mini_app_id
                existing_req.owner_name = owner_name
                existing_req.contact_phone = contact_phone
                existing_req.contact_email = contact_email
                row = existing_req
            else:
                row = OfficialAccountRequestDB(
                    account_id=account_id,
                    kind=kind,
                    name=name,
                    name_ar=body.name_ar,
                    description=body.description,
                    category=body.category,
                    city=body.city,
                    address=body.address,
                    opening_hours=body.opening_hours,
                    website_url=body.website_url,
                    mini_app_id=body.mini_app_id,
                    owner_name=owner_name,
                    contact_phone=contact_phone,
                    contact_email=contact_email,
                    requester_phone=phone,
                    status="submitted",
                )
                s.add(row)
            s.commit()
            s.refresh(row)
            try:
                emit_event(
                    "officials",
                    "self_register",
                    {
                        "account_id": row.account_id,
                        "request_id": row.id,
                        "requester_phone": row.requester_phone,
                        "status": row.status,
                    },
                )
            except Exception:
                pass
            out = OfficialAccountRequestOut(
                id=row.id,
                account_id=row.account_id,
                kind=row.kind,
                name=row.name,
                name_ar=row.name_ar,
                description=row.description,
                category=row.category,
                city=row.city,
                address=row.address,
                opening_hours=row.opening_hours,
                website_url=row.website_url,
                mini_app_id=row.mini_app_id,
                owner_name=row.owner_name,
                contact_phone=row.contact_phone,
                contact_email=row.contact_email,
                requester_phone=row.requester_phone,
                status=row.status,
                created_at=row.created_at,
                updated_at=row.updated_at,
            )
            return out.dict()
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/me/official_account_requests", response_class=JSONResponse)
def me_official_account_requests(request: Request) -> dict[str, Any]:
    """
    Lists Official account registration requests for the current user.

    This gives a WeChat‑like overview of pending/approved/rejected
    Official account applications owned by the caller (based on phone).
    """
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="auth required")
    try:
        with _officials_session() as s:
            rows = (
                s.execute(
                    _sa_select(OfficialAccountRequestDB)
                    .where(OfficialAccountRequestDB.requester_phone == phone)
                    .order_by(OfficialAccountRequestDB.created_at.desc())
                )
                .scalars()
                .all()
            )
            items: list[dict[str, Any]] = []
            for row in rows:
                items.append(
                    OfficialAccountRequestOut(
                        id=row.id,
                        account_id=row.account_id,
                        kind=row.kind,
                        name=row.name,
                        name_ar=row.name_ar,
                        description=row.description,
                        category=row.category,
                        city=row.city,
                        address=row.address,
                        opening_hours=row.opening_hours,
                        website_url=row.website_url,
                        mini_app_id=row.mini_app_id,
                        owner_name=row.owner_name,
                        contact_phone=row.contact_phone,
                        contact_email=row.contact_email,
                        requester_phone=row.requester_phone,
                        status=row.status,
                        created_at=row.created_at,
                        updated_at=row.updated_at,
                    ).dict()
                )
        return {"requests": items}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/me/official_template_messages", response_class=JSONResponse)
def me_official_template_messages(
    request: Request, unread_only: bool = False, limit: int = 50
) -> dict[str, Any]:
    """
    Returns Official template messages for the current user (WeChat-like one-time service messages).
    """
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="auth required")
    limit_val = max(1, min(limit, 200))
    try:
        with _officials_session() as s:
            stmt = _sa_select(OfficialTemplateMessageDB).where(
                OfficialTemplateMessageDB.user_phone == phone
            )
            if unread_only:
                stmt = stmt.where(OfficialTemplateMessageDB.read_at.is_(None))
            stmt = stmt.order_by(
                OfficialTemplateMessageDB.created_at.desc()
            ).limit(limit_val)
            rows = s.execute(stmt).scalars().all()
            items: list[dict[str, Any]] = []
            for row in rows:
                try:
                    deeplink = (
                        _json.loads(row.deeplink_json)
                        if row.deeplink_json
                        else None
                    )
                except Exception:
                    deeplink = None
                out = OfficialTemplateMessageOut(
                    id=row.id,
                    account_id=row.account_id,
                    title=row.title,
                    body=row.body,
                    deeplink_json=deeplink,
                    created_at=row.created_at,
                    read_at=row.read_at,
                )
                items.append(out.dict())
        return {"messages": items}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post(
    "/me/official_template_messages/{message_id}/read",
    response_class=JSONResponse,
)
def me_official_template_messages_mark_read(
    message_id: int, request: Request
) -> dict[str, Any]:
    """
    Marks a single Official template message as read for the current user.
    """
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="auth required")
    try:
        with _officials_session() as s:
            row = s.get(OfficialTemplateMessageDB, message_id)
            if not row or row.user_phone != phone:
                raise HTTPException(status_code=404, detail="message not found")
            if row.read_at is None:
                row.read_at = datetime.now(timezone.utc)
                s.add(row)
                s.commit()
                s.refresh(row)
                try:
                    emit_event(
                        "officials",
                        "template_message_read",
                        {
                            "account_id": row.account_id,
                            "user_phone": row.user_phone,
                            "message_id": row.id,
                        },
                    )
                except Exception:
                    pass
            try:
                deeplink = (
                    _json.loads(row.deeplink_json)
                    if row.deeplink_json
                    else None
                )
            except Exception:
                deeplink = None
            out = OfficialTemplateMessageOut(
                id=row.id,
                account_id=row.account_id,
                title=row.title,
                body=row.body,
                deeplink_json=deeplink,
                created_at=row.created_at,
                read_at=row.read_at,
            )
            return out.dict()
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/mini_programs", response_class=JSONResponse)
def mini_program_create(request: Request, body: MiniProgramAdminIn) -> dict[str, Any]:
    """
    Legt einen neuen Mini‑Program‑Eintrag an (admin only).

    Dies bildet die WeChat‑ähnliche Mini‑Program‑Registry ab, getrennt
    von den konkreten App‑Versionen.
    """
    _require_admin_v2(request)
    app_id = (body.app_id or "").strip()
    if not app_id:
        raise HTTPException(status_code=400, detail="app_id required")
    title_en = (body.title_en or "").strip()
    if not title_en:
        raise HTTPException(status_code=400, detail="title_en required")
    try:
        with _officials_session() as s:
            existing = (
                s.execute(
                    _sa_select(MiniProgramDB).where(MiniProgramDB.app_id == app_id)
                )
                .scalars()
                .first()
            )
            if existing:
                raise HTTPException(status_code=409, detail="mini-program already exists")
            actions_json: str | None = None
            if body.actions:
                try:
                    actions_json = _json.dumps([a.dict() for a in body.actions])
                except Exception:
                    actions_json = None
            scopes_json: str | None = None
            if body.scopes:
                try:
                    scopes = [str(s).strip() for s in body.scopes if str(s).strip()]
                    if scopes:
                        scopes_json = _json.dumps(scopes)
                except Exception:
                    scopes_json = None
            row = MiniProgramDB(
                app_id=app_id,
                title_en=title_en,
                title_ar=body.title_ar,
                description_en=body.description_en,
                description_ar=body.description_ar,
                owner_name=body.owner_name,
                owner_contact=body.owner_contact,
                actions_json=actions_json,
                 scopes_json=scopes_json,
                status="draft",
                review_status="draft",
            )
            s.add(row)
            s.commit()
            s.refresh(row)
            actions_out: list[dict[str, Any]] = []
            if body.actions:
                for a in body.actions:
                    actions_out.append(
                        {
                            "id": a.id,
                            "label_en": a.label_en,
                            "label_ar": a.label_ar,
                            "kind": a.kind,
                            "mod_id": a.mod_id,
                            "url": a.url,
                        }
                    )
            scopes_out: list[str] | None = None
            if scopes_json:
                try:
                    val = _json.loads(scopes_json)
                    if isinstance(val, list):
                        scopes_out = [str(s) for s in val if str(s).strip()]
                except Exception:
                    scopes_out = None
            return {
                "app_id": row.app_id,
                "title_en": row.title_en,
                "title_ar": row.title_ar,
                "description_en": row.description_en,
                "description_ar": row.description_ar,
                "owner_name": row.owner_name,
                "owner_contact": row.owner_contact,
                "status": row.status,
                "review_status": getattr(row, "review_status", "draft"),
                "scopes": scopes_out,
                "actions": actions_out,
                "created_at": getattr(row, "created_at", None),
                "updated_at": getattr(row, "updated_at", None),
            }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/mini_programs/self_register", response_class=JSONResponse)
def mini_program_self_register(
    request: Request, body: MiniProgramSelfRegisterIn
) -> dict[str, Any]:
    """
    Self‑service registration endpoint for third‑party Mini‑Programs.

    A logged‑in developer can create or update basic metadata for a
    Mini‑Program. New entries are created with status "draft"; ops can
    later review and activate them via the admin console.
    """
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="auth required")
    app_id = (body.app_id or "").strip()
    if not app_id:
        raise HTTPException(status_code=400, detail="app_id required")
    title_en = (body.title_en or "").strip()
    if not title_en:
        raise HTTPException(status_code=400, detail="title_en required")
    # Very simple app_id sanity-check to avoid surprising IDs.
    for ch in app_id:
        if not (ch.islower() or ch.isdigit() or ch in {"_", "-"}):
            raise HTTPException(
                status_code=400,
                detail="app_id may only contain lowercase letters, digits, '_' or '-'",
            )
    owner_name = (body.owner_name or "").strip()
    if not owner_name:
        owner_name = f"Developer {phone}"
    owner_contact = (body.owner_contact or "").strip()
    if not owner_contact:
        owner_contact = phone
    try:
        with _officials_session() as s:
            existing = (
                s.execute(
                    _sa_select(MiniProgramDB).where(MiniProgramDB.app_id == app_id)
                )
                .scalars()
                .first()
            )
            scopes_json: str | None = None
            if body.scopes:
                try:
                    scopes = [str(s).strip() for s in body.scopes if str(s).strip()]
                    if scopes:
                        scopes_json = _json.dumps(scopes)
                except Exception:
                    scopes_json = None
            if existing:
                # Only allow the original owner (based on owner_contact) to update.
                try:
                    existing_contact = (existing.owner_contact or "").strip()
                except Exception:
                    existing_contact = ""
                if existing_contact and existing_contact != phone:
                    raise HTTPException(
                        status_code=403,
                        detail="mini-program already exists and is owned by a different contact",
                    )
                existing.title_en = title_en
                existing.title_ar = body.title_ar or existing.title_ar
                existing.description_en = (
                    body.description_en or existing.description_en
                )
                existing.description_ar = (
                    body.description_ar or existing.description_ar
                )
                existing.owner_name = owner_name
                existing.owner_contact = owner_contact
                if scopes_json is not None:
                    existing.scopes_json = scopes_json
                s.add(existing)
                row = existing
            else:
                row = MiniProgramDB(
                    app_id=app_id,
                    title_en=title_en,
                    title_ar=body.title_ar,
                    description_en=body.description_en,
                    description_ar=body.description_ar,
                    owner_name=owner_name,
                    owner_contact=owner_contact,
                    scopes_json=scopes_json,
                    status="draft",
                    review_status="draft",
                )
                s.add(row)
            s.commit()
            s.refresh(row)
            try:
                emit_event(
                    "miniprograms",
                    "self_register",
                    {
                        "app_id": row.app_id,
                        "owner_contact": row.owner_contact,
                        "status": row.status,
                    },
                )
            except Exception:
                pass
            return {
                "app_id": row.app_id,
                "title_en": row.title_en,
                "title_ar": row.title_ar,
                "description_en": row.description_en,
                "description_ar": row.description_ar,
                "owner_name": row.owner_name,
                "owner_contact": row.owner_contact,
                "status": row.status,
                "review_status": getattr(row, "review_status", "draft"),
                "scopes": (
                    [
                        str(s)
                        for s in (
                            (_json.loads(row.scopes_json or "[]"))
                            if getattr(row, "scopes_json", None)
                            else []
                        )
                        if str(s).strip()
                    ]
                    if getattr(row, "scopes_json", None)
                    else []
                ),
                "created_at": getattr(row, "created_at", None),
                "updated_at": getattr(row, "updated_at", None),
            }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post(
    "/mini_programs/{app_id}/submit_review",
    response_class=JSONResponse,
)
def mini_program_submit_review(request: Request, app_id: str) -> dict[str, Any]:
    """
    Developer-facing endpoint to submit a Mini‑Program for review.

    Only the original owner (based on owner_contact/phone) may call this.
    Sets review_status="submitted" but does not change the status field;
    ops can then approve the Mini‑Program in the admin Review‑Center.
    """
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="auth required")
    app_id_clean = (app_id or "").strip()
    if not app_id_clean:
        raise HTTPException(status_code=400, detail="app_id required")
    try:
        with _officials_session() as s:
            prog = (
                s.execute(
                    _sa_select(MiniProgramDB).where(
                        MiniProgramDB.app_id == app_id_clean
                    )
                )
                .scalars()
                .first()
            )
            if not prog:
                raise HTTPException(status_code=404, detail="mini-program not found")
            try:
                owner_contact = (prog.owner_contact or "").strip()
            except Exception:
                owner_contact = ""
            if owner_contact and owner_contact != phone:
                raise HTTPException(
                    status_code=403,
                    detail="only the original owner can submit this mini-program for review",
                )
            current_review = (getattr(prog, "review_status", "draft") or "").strip().lower()
            if current_review == "approved":
                # Already approved; nothing to do.
                return {
                    "app_id": prog.app_id,
                    "status": prog.status,
                    "review_status": current_review,
                }
            prog.review_status = "submitted"
            s.add(prog)
            s.commit()
            s.refresh(prog)
            try:
                emit_event(
                    "miniprograms",
                    "submit_review",
                    {
                        "app_id": prog.app_id,
                        "owner_contact": prog.owner_contact,
                        "status": prog.status,
                        "review_status": prog.review_status,
                    },
                )
            except Exception:
                pass
            return {
                "app_id": prog.app_id,
                "status": prog.status,
                "review_status": getattr(prog, "review_status", "submitted"),
            }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/mini_programs", response_class=JSONResponse)
def mini_program_list() -> dict[str, Any]:
    """
    Öffentlicher JSON‑Katalog für registrierte Mini‑Programme.

    Dient als Basis für spätere Developer‑Portale und den
    Mini‑Program‑Runtime, ähnlich zu WeChat.
    """
    try:
        with _officials_session() as s:
            programs = (
                s.execute(
                    _sa_select(MiniProgramDB).order_by(MiniProgramDB.app_id)
                )
                .scalars()
                .all()
            )
            if MINI_CATALOG_ALLOWLIST:
                programs = [
                    p
                    for p in programs
                    if str(getattr(p, "app_id", "") or "").strip().lower()
                    in MINI_CATALOG_ALLOWLIST
                ]
            app_ids = [p.app_id for p in programs]
            ratings_map: dict[str, tuple[float, int]] = {}
            if app_ids:
                try:
                    agg_rows = (
                        s.execute(
                            _sa_select(
                                MiniProgramRatingDB.app_id,
                                _sa_func.avg(MiniProgramRatingDB.rating),
                                _sa_func.count(MiniProgramRatingDB.id),
                            ).where(MiniProgramRatingDB.app_id.in_(app_ids))
                            .group_by(MiniProgramRatingDB.app_id)
                        )
                        .all()
                    )
                    for app_id, avg_val, cnt in agg_rows:
                        try:
                            ratings_map[str(app_id)] = (
                                float(avg_val or 0.0),
                                int(cnt or 0),
                            )
                        except Exception:
                            continue
                except Exception:
                    ratings_map = {}
            # Best-effort Moments share counts per Mini-Program based on
            # shamell://mini_program/<id> deep-links in Moments posts.
            # So können Directory & Suche später "hot last 30 days"
            # ähnlich zu WeChat markieren.
            moments_shares: dict[str, int] = {}
            moments_shares_30d: dict[str, int] = {}
            try:
                if app_ids:
                    with _moments_session() as ms:
                        since_30d = datetime.now(timezone.utc) - timedelta(days=30)
                        for app_id in app_ids:
                            try:
                                pattern = f"shamell://mini_program/{app_id}"
                                base_stmt = _sa_select(
                                    _sa_func.count(MomentPostDB.id)
                                ).where(MomentPostDB.text.contains(pattern))
                                cnt_all = ms.execute(base_stmt).scalar() or 0
                                cnt_30 = (
                                    ms.execute(
                                        base_stmt.where(
                                            MomentPostDB.created_at >= since_30d
                                        )
                                    ).scalar()
                                    or 0
                                )
                                moments_shares[str(app_id)] = int(cnt_all or 0)
                                moments_shares_30d[str(app_id)] = int(cnt_30 or 0)
                            except Exception:
                                continue
            except Exception:
                moments_shares = {}
                moments_shares_30d = {}

            items: list[dict[str, Any]] = []
            for prog in programs:
                released_version: str | None = None
                released_channel: str | None = None
                usage_score_val = 0
                try:
                    usage_score_val = int(
                        getattr(prog, "usage_score", 0) or 0
                    )
                except Exception:
                    usage_score_val = 0
                try:
                    avg_rating, rating_count = ratings_map.get(
                        prog.app_id,
                        (
                            float(getattr(prog, "rating", 0.0) or 0.0),
                            0,
                        ),
                    )
                except Exception:
                    avg_rating, rating_count = 0.0, 0
                try:
                    rel = (
                        s.execute(
                            _sa_select(MiniProgramReleaseDB)
                            .where(MiniProgramReleaseDB.program_id == prog.id)
                            .order_by(
                                MiniProgramReleaseDB.created_at.desc(),
                                MiniProgramReleaseDB.id.desc(),
                            )
                            .limit(1)
                        )
                        .scalars()
                        .first()
                    )
                except Exception:
                    rel = None
                if rel is not None:
                    released_channel = rel.channel
                    try:
                        ver = s.get(MiniProgramVersionDB, rel.version_id)
                        if ver is not None:
                            released_version = ver.version
                    except Exception:
                        released_version = None
                scopes_list: list[str] = []
                try:
                    raw_scopes = getattr(prog, "scopes_json", None)
                    if raw_scopes:
                        val = _json.loads(raw_scopes)
                        if isinstance(val, list):
                            scopes_list = [
                                str(s).strip() for s in val if str(s).strip()
                            ]
                except Exception:
                    scopes_list = []
                try:
                    moments_count = int(
                        moments_shares.get(prog.app_id, 0)
                        or getattr(prog, "moments_shares", 0)
                        or 0
                    )
                except Exception:
                    moments_count = 0
                try:
                    moments_30 = int(
                        moments_shares_30d.get(prog.app_id, 0) or 0
                    )
                except Exception:
                    moments_30 = 0
                items.append(
                    {
                        "app_id": prog.app_id,
                        "title_en": prog.title_en,
                        "title_ar": prog.title_ar,
                        "description_en": getattr(prog, "description_en", None),
                        "description_ar": getattr(prog, "description_ar", None),
                        "owner_name": prog.owner_name,
                        "owner_contact": prog.owner_contact,
                        "status": prog.status,
                        "review_status": getattr(prog, "review_status", "draft"),
                        "scopes": scopes_list,
                        "usage_score": usage_score_val,
                        "rating": float(avg_rating),
                        "rating_count": int(rating_count),
                        "released_version": released_version,
                        "released_channel": released_channel,
                        "moments_shares": moments_count,
                        "moments_shares_30d": moments_30,
                    }
                )
        return {"programs": items}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/mini_programs/{app_id}", response_class=JSONResponse)
def mini_program_detail(app_id: str) -> dict[str, Any]:
    """
    Detailansicht eines Mini‑Program‑Eintrags inkl. Versionen.
    """
    app_id_clean = (app_id or "").strip()
    if not app_id_clean:
        raise HTTPException(status_code=400, detail="app_id required")
    if MINI_CATALOG_ALLOWLIST and app_id_clean.lower() not in MINI_CATALOG_ALLOWLIST:
        raise HTTPException(status_code=404, detail="mini-program not found")
    try:
        with _officials_session() as s:
            prog = (
                s.execute(
                    _sa_select(MiniProgramDB).where(
                        MiniProgramDB.app_id == app_id_clean
                    )
                )
                .scalars()
                .first()
            )
            if not prog:
                raise HTTPException(status_code=404, detail="mini-program not found")
            versions = (
                s.execute(
                    _sa_select(MiniProgramVersionDB).where(
                        MiniProgramVersionDB.program_id == prog.id
                    )
                    .order_by(
                        MiniProgramVersionDB.created_at.desc(),
                        MiniProgramVersionDB.id.desc(),
                    )
                )
                .scalars()
                .all()
            )
            avg_rating = 0.0
            rating_count = 0
            try:
                row = (
                    s.execute(
                        _sa_select(
                            _sa_func.avg(MiniProgramRatingDB.rating),
                            _sa_func.count(MiniProgramRatingDB.id),
                        ).where(MiniProgramRatingDB.app_id == app_id_clean)
                    )
                    .first()
                )
                if row:
                    avg_rating = float(row[0] or 0.0)
                    rating_count = int(row[1] or 0)
            except Exception:
                avg_rating = 0.0
                rating_count = 0
            vers_items: list[dict[str, Any]] = []
            for v in versions:
                vers_items.append(
                    {
                        "id": v.id,
                        "version": v.version,
                        "bundle_url": v.bundle_url,
                        "changelog_en": v.changelog_en,
                        "changelog_ar": v.changelog_ar,
                        "created_at": getattr(v, "created_at", None),
                    }
                )
            actions: list[dict[str, Any]] = []
            raw_actions = getattr(prog, "actions_json", None)
            if raw_actions:
                try:
                    val = _json.loads(raw_actions)
                    if isinstance(val, list):
                        for item in val:
                            if not isinstance(item, dict):
                                continue
                            try:
                                aid = str(item.get("id") or "").strip()
                                if not aid:
                                    continue
                                actions.append(
                                    {
                                        "id": aid,
                                        "label_en": item.get("label_en") or "",
                                        "label_ar": item.get("label_ar") or "",
                                        "kind": item.get("kind") or "open_mod",
                                        "mod_id": item.get("mod_id"),
                                        "url": item.get("url"),
                                    }
                                )
                            except Exception:
                                continue
                except Exception:
                    actions = []
            scopes_list: list[str] = []
            try:
                raw_scopes = getattr(prog, "scopes_json", None)
                if raw_scopes:
                    val = _json.loads(raw_scopes)
                    if isinstance(val, list):
                        scopes_list = [
                            str(s).strip() for s in val if str(s).strip()
                        ]
            except Exception:
                scopes_list = []
            return {
                "app_id": prog.app_id,
                "title_en": prog.title_en,
                "title_ar": prog.title_ar,
                "description_en": getattr(prog, "description_en", None),
                "description_ar": getattr(prog, "description_ar", None),
                "owner_name": prog.owner_name,
                "owner_contact": prog.owner_contact,
                "status": prog.status,
                "review_status": getattr(prog, "review_status", "draft"),
                "scopes": scopes_list,
                "rating": avg_rating,
                "rating_count": rating_count,
                "versions": vers_items,
                "actions": actions,
            }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/mini_programs/{app_id}/versions", response_class=JSONResponse)
def mini_program_add_version(
    app_id: str, request: Request, body: MiniProgramVersionIn
) -> dict[str, Any]:
    """
    Registriert eine neue Version für ein Mini‑Programm (admin only).
    """
    _require_admin_v2(request)
    app_id_clean = (app_id or "").strip()
    if not app_id_clean:
        raise HTTPException(status_code=400, detail="app_id required")
    version = (body.version or "").strip()
    if not version:
        raise HTTPException(status_code=400, detail="version required")
    try:
        with _officials_session() as s:
            prog = (
                s.execute(
                    _sa_select(MiniProgramDB).where(
                        MiniProgramDB.app_id == app_id_clean
                    )
                )
                .scalars()
                .first()
            )
            if not prog:
                raise HTTPException(status_code=404, detail="mini-program not found")
            existing = (
                s.execute(
                    _sa_select(MiniProgramVersionDB).where(
                        MiniProgramVersionDB.program_id == prog.id,
                        MiniProgramVersionDB.version == version,
                    )
                )
                .scalars()
                .first()
            )
            if existing:
                raise HTTPException(status_code=409, detail="version already exists")
            row = MiniProgramVersionDB(
                program_id=prog.id,
                version=version,
                bundle_url=body.bundle_url,
                changelog_en=body.changelog_en,
                changelog_ar=body.changelog_ar,
            )
            s.add(row)
            s.commit()
            s.refresh(row)
            return {
                "app_id": prog.app_id,
                "version": row.version,
                "bundle_url": row.bundle_url,
                "changelog_en": row.changelog_en,
                "changelog_ar": row.changelog_ar,
                "created_at": getattr(row, "created_at", None),
            }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/mini_programs/{app_id}/versions/self_register", response_class=JSONResponse)
def mini_program_add_version_self(
    app_id: str, request: Request, body: MiniProgramSelfVersionIn
) -> dict[str, Any]:
    """
    Developer self‑service endpoint to propose a new Mini‑Program version.

    The version is recorded but not automatically released; ops can
    later create a Release via the admin API.
    """
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="auth required")
    app_id_clean = (app_id or "").strip()
    if not app_id_clean:
        raise HTTPException(status_code=400, detail="app_id required")
    version = (body.version or "").strip()
    if not version:
        raise HTTPException(status_code=400, detail="version required")
    bundle_url = (body.bundle_url or "").strip()
    if not bundle_url:
        raise HTTPException(status_code=400, detail="bundle_url required")
    try:
        with _officials_session() as s:
            prog = (
                s.execute(
                    _sa_select(MiniProgramDB).where(
                        MiniProgramDB.app_id == app_id_clean
                    )
                )
                .scalars()
                .first()
            )
            if not prog:
                raise HTTPException(status_code=404, detail="mini-program not found")
            # Only allow owner (based on owner_contact) to add versions.
            try:
                existing_contact = (prog.owner_contact or "").strip()
            except Exception:
                existing_contact = ""
            if existing_contact and existing_contact != phone:
                raise HTTPException(
                    status_code=403,
                    detail="mini-program is owned by a different contact",
                )
            existing = (
                s.execute(
                    _sa_select(MiniProgramVersionDB).where(
                        MiniProgramVersionDB.program_id == prog.id,
                        MiniProgramVersionDB.version == version,
                    )
                )
                .scalars()
                .first()
            )
            if existing:
                raise HTTPException(status_code=409, detail="version already exists")
            row = MiniProgramVersionDB(
                program_id=prog.id,
                version=version,
                bundle_url=bundle_url,
                changelog_en=body.changelog_en,
                changelog_ar=body.changelog_ar,
            )
            s.add(row)
            s.commit()
            s.refresh(row)
            try:
                emit_event(
                    "miniprograms",
                    "self_version",
                    {"app_id": prog.app_id, "version": row.version},
                )
            except Exception:
                pass
            return {
                "app_id": prog.app_id,
                "version": row.version,
                "bundle_url": row.bundle_url,
                "changelog_en": row.changelog_en,
                "changelog_ar": row.changelog_ar,
                "created_at": getattr(row, "created_at", None),
            }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/mini_programs/{app_id}/releases", response_class=JSONResponse)
def mini_program_release(
    app_id: str, request: Request, body: MiniProgramReleaseIn
) -> dict[str, Any]:
    """
    Markiert eine Version als freigegeben (admin only).

    Für das MVP hängt der Client nicht direkt an Releases – die Daten
    dienen in erster Linie als WeChat‑ähnliches Backoffice‑Tracking.
    """
    _require_admin_v2(request)
    app_id_clean = (app_id or "").strip()
    if not app_id_clean:
        raise HTTPException(status_code=400, detail="app_id required")
    version_str = (body.version or "").strip()
    if not version_str:
        raise HTTPException(status_code=400, detail="version required")
    channel = (body.channel or "prod").strip() or "prod"
    try:
        with _officials_session() as s:
            prog = (
                s.execute(
                    _sa_select(MiniProgramDB).where(
                        MiniProgramDB.app_id == app_id_clean
                    )
                )
                .scalars()
                .first()
            )
            if not prog:
                raise HTTPException(status_code=404, detail="mini-program not found")
            ver = (
                s.execute(
                    _sa_select(MiniProgramVersionDB).where(
                        MiniProgramVersionDB.program_id == prog.id,
                        MiniProgramVersionDB.version == version_str,
                    )
                )
                .scalars()
                .first()
            )
            if not ver:
                raise HTTPException(status_code=404, detail="version not found")
            rel = MiniProgramReleaseDB(
                program_id=prog.id,
                version_id=ver.id,
                channel=channel,
                status="active",
            )
            s.add(rel)
            try:
                prog.status = "active"
                s.add(prog)
            except Exception:
                pass
            s.commit()
            s.refresh(rel)
            return {
                "app_id": prog.app_id,
                "version": ver.version,
                "channel": rel.channel,
                "status": rel.status,
            }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/mini_programs/{app_id}/track_open", response_class=JSONResponse)
async def mini_program_track_open(app_id: str, request: Request) -> dict[str, Any]:
    """
    Lightweight Tracking-Endpoint für Mini-Program-Opens (WeChat-like analytics).

    Erhöht usage_score für die gegebene app_id – wird vom Client bei
    jedem Öffnen eines Mini-Programms best-effort aufgerufen.
    """
    app_id_clean = (app_id or "").strip()
    if not app_id_clean:
        raise HTTPException(status_code=400, detail="app_id required")
    try:
        with _officials_session() as s:
            row = (
                s.execute(
                    _sa_select(MiniProgramDB).where(
                        MiniProgramDB.app_id == app_id_clean
                    )
                )
                .scalars()
                .first()
            )
            if not row:
                # Unknown app_id – silently ignore so Client-Aufrufe nicht brechen.
                return {"status": "ignored"}
            try:
                current = int(getattr(row, "usage_score", 0) or 0)
            except Exception:
                current = 0
            row.usage_score = current + 1
            s.add(row)
            s.commit()
        try:
            emit_event(
                "miniprograms",
                "open",
                {"app_id": app_id_clean},
            )
        except Exception:
            pass
        return {"status": "ok"}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/mini_programs/{app_id}/moments_stats", response_class=JSONResponse)
def mini_program_moments_stats(app_id: str) -> dict[str, Any]:
    """
    Moments-Analytics für ein einzelnes Mini‑Program auf App‑Ebene.

    Liefert Gesamt‑Shares, 30‑Tage‑Shares, Unique‑Sharers und eine
    einfache Tageskurve für die letzten 30 Tage – WeChat‑ähnlich.
    """
    app_id_clean = (app_id or "").strip()
    if not app_id_clean:
        raise HTTPException(status_code=400, detail="app_id required")
    try:
        # Sicherstellen, dass das Mini‑Program existiert – so können wir
        # 404 für Tippfehler liefern statt leere Stats.
        with _officials_session() as s:
            prog = (
                s.execute(
                    _sa_select(MiniProgramDB).where(
                        MiniProgramDB.app_id == app_id_clean
                    )
                )
                .scalars()
                .first()
            )
            if not prog:
                raise HTTPException(status_code=404, detail="mini-program not found")

        pattern = f"shamell://mini_program/{app_id_clean}"
        total = 0
        total_30d = 0
        uniq_total = 0
        uniq_30d = 0
        series_30d: list[dict[str, Any]] = []
        try:
            since_30d = datetime.now(timezone.utc) - timedelta(days=30)
            with _moments_session() as ms:
                base_filter = MomentPostDB.text.contains(pattern)
                # All-time total shares
                total = (
                    ms.execute(
                        _sa_select(_sa_func.count(MomentPostDB.id)).where(
                            base_filter
                        )
                    )
                    .scalar()
                    or 0
                )
                # 30d shares
                total_30d = (
                    ms.execute(
                        _sa_select(_sa_func.count(MomentPostDB.id)).where(
                            base_filter, MomentPostDB.created_at >= since_30d
                        )
                    )
                    .scalar()
                    or 0
                )
                # Unique sharers all-time
                uniq_total = (
                    ms.execute(
                        _sa_select(
                            _sa_func.count(
                                _sa_func.distinct(MomentPostDB.user_key)
                            )
                        ).where(base_filter)
                    )
                    .scalar()
                    or 0
                )
                # Unique sharers 30d
                uniq_30d = (
                    ms.execute(
                        _sa_select(
                            _sa_func.count(
                                _sa_func.distinct(MomentPostDB.user_key)
                            )
                        ).where(
                            base_filter, MomentPostDB.created_at >= since_30d
                        )
                    )
                    .scalar()
                    or 0
                )
                # Daily curve for last 30 days
                rows = (
                    ms.execute(
                        _sa_select(
                            _sa_func.date(MomentPostDB.created_at),
                            _sa_func.count(MomentPostDB.id),
                        )
                        .where(base_filter, MomentPostDB.created_at >= since_30d)
                        .group_by(_sa_func.date(MomentPostDB.created_at))
                        .order_by(_sa_func.date(MomentPostDB.created_at))
                    )
                    .all()
                )
                for d, cnt in rows:
                    try:
                        if isinstance(d, datetime):
                            date_str = d.date().isoformat()
                        else:
                            date_str = str(d)
                    except Exception:
                        date_str = str(d)
                    series_30d.append(
                        {
                            "date": date_str,
                            "shares": int(cnt or 0),
                        }
                    )
        except Exception:
            total = 0
            total_30d = 0
            uniq_total = 0
            uniq_30d = 0
            series_30d = []

        return {
            "app_id": app_id_clean,
            "shares_total": int(total or 0),
            "shares_30d": int(total_30d or 0),
            "unique_sharers_total": int(uniq_total or 0),
            "unique_sharers_30d": int(uniq_30d or 0),
            "series_30d": series_30d,
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/mini_programs/{app_id}/rate", response_class=JSONResponse)
async def mini_program_rate(
    app_id: str, request: Request, body: MiniProgramRatingIn
) -> dict[str, Any]:
    """
    Simple rating endpoint for Mini‑Programs (1–5 stars per user).

    Spiegelbild zu /mini_apps/{id}/rate, nutzt sa_cookie
    als user_key und hält MiniProgramDB.rating synchron.
    """
    app_id_clean = (app_id or "").strip()
    if not app_id_clean:
        raise HTTPException(status_code=400, detail="app_id required")
    user_key = _official_cookie_key(request)
    try:
        val = int(body.rating)
    except Exception:
        val = 0
    if val < 1:
        val = 1
    if val > 5:
        val = 5
    try:
        with _officials_session() as s:
            prog_row = (
                s.execute(
                    _sa_select(MiniProgramDB).where(
                        MiniProgramDB.app_id == app_id_clean
                    )
                )
                .scalars()
                .first()
            )
            if not prog_row:
                raise HTTPException(status_code=404, detail="mini-program not found")
            existing = (
                s.execute(
                    _sa_select(MiniProgramRatingDB).where(
                        MiniProgramRatingDB.app_id == app_id_clean,
                        MiniProgramRatingDB.user_key == user_key,
                    )
                )
                .scalars()
                .first()
            )
            if existing:
                existing.rating = val
                s.add(existing)
            else:
                rec = MiniProgramRatingDB(
                    app_id=app_id_clean, user_key=user_key, rating=val
                )
                s.add(rec)
            s.commit()
            avg_rating = 0.0
            rating_count = 0
            try:
                avg_row = (
                    s.execute(
                        _sa_select(
                            _sa_func.avg(MiniProgramRatingDB.rating),
                            _sa_func.count(MiniProgramRatingDB.id),
                        ).where(MiniProgramRatingDB.app_id == app_id_clean)
                    )
                    .first()
                )
                if avg_row:
                    avg_rating = float(avg_row[0] or 0.0)
                    rating_count = int(avg_row[1] or 0)
            except Exception:
                avg_rating = 0.0
                rating_count = 0
            try:
                prog_row.rating = avg_rating
                s.add(prog_row)
                s.commit()
            except Exception:
                s.rollback()
        try:
            emit_event(
                "miniprograms",
                "rate",
                {"app_id": app_id_clean, "user_key": user_key, "rating": val},
            )
        except Exception:
            pass
        return {"status": "ok", "rating": avg_rating, "count": rating_count}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/mini_apps", response_class=JSONResponse)
async def list_mini_apps() -> dict[str, Any]:
    """
    Öffentlicher JSON-Katalog für Mini-Apps (Mini-Programme).

    Wird vom Flutter-Client genutzt, um dynamische Mini-Apps (inkl. Partner)
    anzuzeigen – analog zum statischen `kMiniApps`-Registry in der App.
    """
    try:
        with _officials_session() as s:
            rows = (
                s.execute(
                    _sa_select(MiniAppDB).where(MiniAppDB.enabled == True)  # type: ignore[comparison-overlap]
                )
                .scalars()
                .all()
            )
            if MINI_CATALOG_ALLOWLIST:
                rows = [
                    r
                    for r in rows
                    if str(getattr(r, "app_id", "") or "").strip().lower()
                    in MINI_CATALOG_ALLOWLIST
                ]
            app_ids = [row.app_id for row in rows]
            ratings_map: dict[str, tuple[float, int]] = {}
            if app_ids:
                agg_rows = (
                    s.execute(
                        _sa_select(
                            MiniAppRatingDB.app_id,
                            _sa_func.avg(MiniAppRatingDB.rating),
                            _sa_func.count(MiniAppRatingDB.id),
                        )
                        .where(MiniAppRatingDB.app_id.in_(app_ids))
                        .group_by(MiniAppRatingDB.app_id)
                    )
                    .all()
                )
                for app_id, avg_val, cnt_val in agg_rows:
                    try:
                        ratings_map[str(app_id)] = (
                            float(avg_val or 0.0),
                            int(cnt_val or 0),
                        )
                    except Exception:
                        continue
            # Best-effort Moments share counts per Mini-App based on
            # shamell://miniapp/<id> deep-links in Moments posts.
            moments_shares: dict[str, int] = {}
            try:
                if app_ids:
                    with _moments_session() as ms:
                        for app_id in app_ids:
                            try:
                                pattern = f"shamell://miniapp/{app_id}"
                                cnt = (
                                    ms.execute(
                                        _sa_select(
                                            _sa_func.count(MomentPostDB.id)
                                        ).where(
                                            MomentPostDB.text.contains(
                                                pattern
                                            )
                                        )
                                    )
                                    .scalar()
                                    or 0
                                )
                                moments_shares[str(app_id)] = int(cnt or 0)
                            except Exception:
                                continue
            except Exception:
                moments_shares = {}

            apps: list[dict[str, Any]] = []
            for row in rows:
                avg_rating, rating_count = ratings_map.get(
                    row.app_id, (float(getattr(row, "rating", 0.0) or 0.0), 0)
                )
                try:
                    moments_count = int(
                        moments_shares.get(row.app_id, 0)
                        or getattr(row, "moments_shares", 0)
                        or 0
                    )
                except Exception:
                    moments_count = 0
                apps.append(
                    {
                        "id": row.app_id,
                        "title_en": row.title_en,
                        "title_ar": row.title_ar,
                        "category_en": row.category_en,
                        "category_ar": row.category_ar,
                        "description": row.description,
                        "icon": row.icon,
                        "official": bool(getattr(row, "official", False)),
                        "beta": bool(getattr(row, "beta", False)),
                        "runtime_app_id": getattr(row, "runtime_app_id", None),
                        "rating": float(avg_rating),
                        "rating_count": int(rating_count),
                        "usage_score": int(
                            getattr(row, "usage_score", 0) or 0
                        ),
                        "moments_shares": moments_count,
                    }
                )
        return {"apps": apps}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/mini_apps/developer", response_class=HTMLResponse)
def mini_apps_developer_landing(request: Request) -> HTMLResponse:
    """
    Lightweight Developer-Landing für Mini-Apps (Mini-Programme).

    Beschreibt kurz das Mini-Program-Ökosystem von Shamell und
    verweist auf die Admin-Konsole für Registrierung & Partner-Setup.
    """
    base = request.base_url._url.rstrip("/")  # type: ignore[attr-defined]
    html = f"""
<!doctype html>
<html><head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Shamell · Mini‑Apps developer</title>
  <style>
    body{{font-family:sans-serif;margin:20px;max-width:880px;color:#0f172a;line-height:1.5;}}
    h1{{margin-bottom:4px;}}
    h2{{margin-top:20px;margin-bottom:6px;}}
    p{{margin:4px 0;}}
    code{{background:#f3f4f6;padding:2px 4px;border-radius:3px;font-size:12px;}}
    .muted{{color:#6b7280;font-size:13px;}}
    ul{{padding-left:20px;}}
  </style>
</head><body>
  <h1>Mini‑Apps · Developer overview</h1>
  <p class="muted">
    Shamell Mini‑Apps sind WeChat‑ähnliche Mini‑Programme, die direkt im
    Super‑App‑Shell laufen (Discover‑Strip, Chat, Moments).
  </p>

  <h2>Ökosystem</h2>
  <ul>
    <li><strong>Katalog &amp; Suche:</strong> <code>/mini_apps</code> liefert einen öffentlichen JSON‑Katalog.</li>
    <li><strong>Trending &amp; Analytics:</strong> <code>usage_score</code>, <code>rating</code> und
      <code>moments_shares</code> steuern die Sortierung im Mini‑Apps‑Tab.</li>
    <li><strong>Moments‑Integration:</strong> Mini‑Apps lassen sich direkt in Moments teilen
      (Deep‑Links <code>shamell://miniapp/&lt;id&gt;</code>, Hashtags wie <code>#ShamellMiniApp</code>).</li>
  </ul>

  <h2>Drittanbieter‑Registrierung</h2>
  <p>
    Die eigentliche Anlage und Pflege von Mini‑Apps erfolgt über die
    Admin‑Konsole (nur für Ops/Partner‑Team zugänglich):
  </p>
  <ul>
    <li><code>{base}/admin/miniapps</code> – JSON &amp; HTML Konsole für Anlage/Bearbeitung.</li>
    <li><code>{base}/admin/miniapps/analytics</code> – einfache Analytics‑Übersicht.</li>
  </ul>
  <p class="muted">
    In Produktionsumgebungen sollte die Konsole nur über VPN/Backoffice erreichbar sein.
  </p>

  <h2>Client‑Integration</h2>
  <p>Ein Mini‑App Eintrag besteht typischerweise aus:</p>
  <ul>
    <li><code>app_id</code> (z.B. <code>bus</code>)</li>
    <li><code>title_en</code>, <code>title_ar</code></li>
    <li><code>category_en</code>, <code>category_ar</code></li>
    <li>optional: <code>icon</code>, <code>official</code>, <code>beta</code></li>
  </ul>
  <p>
    Die Flutter‑Shell mappt <code>app_id</code> auf konkrete Routen (z.B. Bus,
    Wallet) und ruft beim Öffnen best‑effort
    <code>POST /mini_apps/&lt;id&gt;/track_open</code> auf.
  </p>

  <p class="muted">
    Hinweis: Diese Seite ist rein informativ. Schreibende Aktionen (Anlage,
    Editieren, Deaktivieren) laufen ausschließlich über die Admin‑Konsole.
  </p>
</body></html>
"""
    return HTMLResponse(content=html)


@app.get("/mini_programs/developer", response_class=HTMLResponse)
def mini_programs_developer_landing(request: Request) -> HTMLResponse:
    """
    Lightweight Developer-Landing für Mini-Programs.

    Spiegelt die Mini-Apps-Developer-Seite, beschreibt aber
    explizit das API-basierte Mini-Program-Ökosystem.
    """
    base = request.base_url._url.rstrip("/")  # type: ignore[attr-defined]
    phone = _auth_phone(request)
    if not phone:
        return RedirectResponse(url="/login", status_code=303)
    html = f"""
<!doctype html>
<html><head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Shamell · Mini‑programs developer</title>
  <style>
    body{{font-family:sans-serif;margin:20px;max-width:880px;color:#0f172a;line-height:1.5;}}
    h1{{margin-bottom:4px;}}
    h2{{margin-top:20px;margin-bottom:6px;}}
    p{{margin:4px 0;}}
    code{{background:#f3f4f6;padding:2px 4px;border-radius:3px;font-size:12px;}}
    .muted{{color:#6b7280;font-size:13px;}}
    ul{{padding-left:20px;}}
    table{{border-collapse:collapse;width:100%;margin-top:8px;font-size:13px;}}
    th,td{{border:1px solid #e5e7eb;padding:4px 6px;text-align:left;vertical-align:top;}}
    th{{background:#f9fafb;font-weight:600;}}
    .pill{{display:inline-block;padding:1px 6px;border-radius:999px;font-size:11px;}}
    .pill-status-active{{background:#dcfce7;color:#166534;}}
    .pill-status-draft{{background:#fef3c7;color:#92400e;}}
    .pill-status-disabled{{background:#fee2e2;color:#991b1b;}}
    .pill-trending{{background:#eff6ff;color:#1d4ed8;margin-left:4px;}}
    .small{{font-size:12px;}}
  </style>
</head><body>
  <h1>Mini‑Programs · Developer overview</h1>
  <p class="muted">
    Shamell Mini‑Programs sind WeChat‑ähnliche Mini‑Apps, die per Manifest
    über <code>/mini_programs/&lt;id&gt;</code> beschrieben werden und im Shamell‑Shell
    laufen (Discover‑Strip, Mini‑Apps‑Kacheln, Deep‑Links).
  </p>

  <h2>Ökosystem</h2>
  <ul>
    <li><strong>Katalog &amp; Suche:</strong> <code>/mini_programs</code> liefert einen öffentlichen JSON‑Katalog mit
      <code>app_id</code>, Titel, Owner, Status, <code>usage_score</code> und Rating.</li>
    <li><strong>Trending &amp; Analytics:</strong> <code>usage_score</code> (Track via
      <code>POST /mini_programs/&lt;id&gt;/track_open</code>) und Rating steuern Sortierung
      in Suche und Directory; HTML‑Analytics: <code>{base}/admin/mini_programs/analytics</code>.</li>
    <li><strong>Runtime‑Manifest:</strong> <code>/mini_programs/&lt;id&gt;</code> liefert Titel,
      Beschreibungen und Actions‑Liste (Buttons) für die Flutter‑Runtime.</li>
  </ul>

  <h2>Drittanbieter‑Registrierung (Self‑Service)</h2>
  <p>
    Als eingeloggter Entwickler (<code>{phone}</code>) kannst du eigene Mini‑Programme
    registrieren. Neue Einträge starten immer im Status <code>draft</code> und
    können später vom Shamell‑Team geprüft und aktiviert werden.
  </p>
  <h3>Eigene Mini‑Programs</h3>
  <p class="muted">
    JSON‑Übersicht deiner Einträge:
    <code>{base}/mini_programs/developer_json</code>
  </p>
  <div id="dev_flash" class="muted"></div>
  <table>
    <thead>
      <tr>
        <th>App‑ID</th>
        <th>Title</th>
        <th>Status</th>
        <th>Review</th>
        <th>Scopes</th>
        <th>Rating</th>
        <th>Usage</th>
        <th>Last version</th>
        <th>Links</th>
      </tr>
    </thead>
    <tbody id="dev_programs_body">
      <tr><td colspan="9" class="small">Lade deine Mini‑Programs…</td></tr>
    </tbody>
  </table>

  <h3>Neues Mini‑Program registrieren</h3>
  <p>Minimaler JSON‑Call (z.B. via <code>curl</code>):</p>
  <pre><code>POST {base}/mini_programs/self_register
Content-Type: application/json
sa_cookie: &lt;your_sa_session&gt;

{{
  "app_id": "my_cool_app",
  "title_en": "My cool Mini‑Program",
  "title_ar": "تطبيقي المصغر الرائع",
  "description_en": "Short description of my service",
  "owner_name": "Your company",
  "owner_contact": "{phone}"
}}</code></pre>
  <p class="muted">
    Hinweis: <code>owner_contact</code> wird automatisch mit deiner Telefonnummer
    vorbelegt, wenn du keinen Wert angibst. Nur dieser Kontakt darf das
    Mini‑Program später per Self‑Service aktualisieren.
  </p>

  <h3>Versionen vorschlagen</h3>
  <p>
    Optional kannst du eine oder mehrere Versionen mit Bundles registrieren.
    Die Veröffentlichung (Release) erfolgt weiterhin über das Ops‑Team.
  </p>
  <pre><code>POST {base}/mini_programs/my_cool_app/versions/self_register
Content-Type: application/json
sa_cookie: &lt;your_sa_session&gt;

{{
  "version": "1.0.0",
  "bundle_url": "https://example.com/bundles/my_cool_app-1.0.0.zip",
  "changelog_en": "Initial public version"
}}</code></pre>

  <p class="muted">
    Für produktive Freischaltung kann das Ops‑Team später einen Release
    über <code>/mini_programs/&lt;id&gt;/releases</code> anlegen (Admin‑Konsole /
    Backoffice‑APIs).
  </p>

  <h2>Client‑Integration</h2>
  <p>Ein Mini‑Program‑Eintrag besteht typischerweise aus:</p>
  <ul>
    <li><code>app_id</code> (z.B. <code>demo_program</code>)</li>
    <li><code>title_en</code>, <code>title_ar</code></li>
    <li>optional: <code>description_en</code>, <code>description_ar</code></li>
    <li>Owner‑Metadaten: <code>owner_name</code>, <code>owner_contact</code></li>
    <li>optionale <code>actions</code> (Buttons) mit <code>kind=open_mod|open_url|close</code>.</li>
  </ul>
  <p>
    Die Flutter‑Shell lädt das Manifest aus <code>/mini_programs/&lt;id&gt;</code> und rendert
    Buttons, die entweder interne Module (<code>open_mod</code>) oder externe URLs
    (<code>open_url</code>) öffnen – ähnlich zu WeChat Mini‑Programs.
  </p>

  <p class="muted">
    Hinweis: Diese Seite kombiniert Self‑Service‑Calls für Entwickler mit
    klassischen Admin‑Konsole‑Flows. In Produktionsumgebungen sollte die
    Admin‑Konsole weiterhin nur über VPN/Backoffice erreichbar sein.
  </p>
  <script>
    async function loadDeveloperPrograms() {{
      const tbody = document.getElementById('dev_programs_body');
      const flash = document.getElementById('dev_flash');
      if (!tbody) return;
      tbody.innerHTML = '<tr><td colspan="7" class="small">Lade deine Mini‑Programs…</td></tr>';
      flash.textContent = '';
      try {{
        const r = await fetch('/mini_programs/developer_json');
        if (!r.ok) {{
          tbody.innerHTML = '<tr><td colspan="7" class="small">Konnte Mini‑Programs nicht laden (HTTP ' + r.status + ').</td></tr>';
          return;
        }}
        const data = await r.json();
        const items = Array.isArray(data.programs) ? data.programs : [];
        if (!items.length) {{
          tbody.innerHTML = '<tr><td colspan="7" class="small">Noch keine eigenen Mini‑Programs registriert.</td></tr>';
          return;
        }}
        tbody.innerHTML = '';
        for (const p of items) {{
          const tr = document.createElement('tr');
          const appId = (p.app_id || '').toString();
          const titleEn = (p.title_en || '').toString();
          const titleAr = (p.title_ar || '').toString();
          const status = (p.status || '').toString();
          const reviewStatus = (p.review_status || 'draft').toString();
          const scopes = Array.isArray(p.scopes) ? p.scopes : [];
          const rating = typeof p.rating === 'number' ? p.rating : 0;
          const usage = typeof p.usage_score === 'number' ? p.usage_score : 0;
          const lastVersion = (p.last_version || '').toString();
          const lastBundle = (p.last_bundle_url || '').toString();
          let statusClass = '';
          if (status === 'active') {{
            statusClass = 'pill-status-active';
          }} else if (status === 'draft') {{
            statusClass = 'pill-status-draft';
          }} else if (status === 'disabled') {{
            statusClass = 'pill-status-disabled';
          }}
          let trending = false;
          if (status === 'active') {{
            if (usage >= 50 || rating >= 4.5) {{
              trending = true;
            }}
          }}
          // App‑ID
          const tdId = document.createElement('td');
          tdId.textContent = appId || '–';
          tr.appendChild(tdId);
          // Title
          const tdTitle = document.createElement('td');
          tdTitle.textContent = titleEn || titleAr || '–';
          tr.appendChild(tdTitle);
          let reviewClass = 'pill-status-draft';
          const rs = reviewStatus.toLowerCase();
          if (rs === 'approved') reviewClass = 'pill-status-active';
          else if (rs === 'rejected' || rs === 'suspended') reviewClass = 'pill-status-disabled';
          // Status + trending
          const tdStatus = document.createElement('td');
          if (status) {{
            const span = document.createElement('span');
            span.className = 'pill ' + statusClass;
            span.textContent = status;
            tdStatus.appendChild(span);
          }} else {{
            tdStatus.textContent = '–';
          }}
          if (trending) {{
            const spanTr = document.createElement('span');
            spanTr.className = 'pill pill-trending';
            spanTr.textContent = 'Trending';
            tdStatus.appendChild(spanTr);
          }}
          tr.appendChild(tdStatus);
          const tdReview = document.createElement('td');
          const spanRv = document.createElement('span');
          spanRv.className = 'pill ' + reviewClass;
          spanRv.textContent = reviewStatus;
          tdReview.appendChild(spanRv);
          tr.appendChild(tdReview);
          // Rating
          const tdRating = document.createElement('td');
          if (rating > 0) {{
            tdRating.textContent = rating.toFixed(1) + ' ★';
          }} else {{
            tdRating.textContent = '–';
          }}
          tr.appendChild(tdRating);
          // Usage
          const tdUsage = document.createElement('td');
          tdUsage.textContent = usage > 0 ? String(usage) : '–';
          tr.appendChild(tdUsage);
          // Scopes
          const tdScopes = document.createElement('td');
          if (scopes.length) {{
            tdScopes.className = 'small';
            tdScopes.innerHTML = scopes.map(s => '<code>' + String(s) + '</code>').join(' ');
          }} else {{
            tdScopes.innerHTML = '<span class="small muted">–</span>';
          }}
          tr.appendChild(tdScopes);
          // Last version
          const tdVer = document.createElement('td');
          if (lastVersion) {{
            tdVer.textContent = lastVersion;
          }} else {{
            tdVer.textContent = '–';
          }}
          tr.appendChild(tdVer);
          // Links
          const tdLinks = document.createElement('td');
          tdLinks.className = 'small';
          if (appId) {{
            const aManifest = document.createElement('a');
            aManifest.href = '{base}/mini_programs/' + encodeURIComponent(appId);
            aManifest.textContent = 'Manifest';
            aManifest.target = '_blank';
            tdLinks.appendChild(aManifest);
          }}
          if (lastBundle) {{
            const spanSep = document.createTextNode(' · ');
            tdLinks.appendChild(spanSep);
            const aBundle = document.createElement('a');
            aBundle.href = lastBundle;
            aBundle.textContent = 'Bundle';
            aBundle.target = '_blank';
            tdLinks.appendChild(aBundle);
          }}
          tr.appendChild(tdLinks);
          tbody.appendChild(tr);
        }}
      }} catch (e) {{
        tbody.innerHTML = '<tr><td colspan=\"7\" class=\"small\">Fehler beim Laden deiner Mini‑Programs.</td></tr>';
        flash.textContent = String(e);
      }}
    }}
    document.addEventListener('DOMContentLoaded', loadDeveloperPrograms);
  </script>
</body></html>
"""
    return HTMLResponse(content=html)


@app.get("/mini_programs/developer_json", response_class=JSONResponse)
def mini_programs_developer_json(request: Request) -> dict[str, Any]:
    """
    JSON‑Übersicht aller Mini‑Programs, die dem eingeloggten Entwickler gehören.

    Ownership wird über MiniProgramDB.owner_contact (Telefonnummer) abgebildet.
    """
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="auth required")
    contact = phone.strip()
    try:
        with _officials_session() as s:
            stmt = _sa_select(MiniProgramDB).order_by(MiniProgramDB.app_id)
            if contact:
                stmt = stmt.where(MiniProgramDB.owner_contact == contact)
            rows = s.execute(stmt).scalars().all()
            if not rows:
                return {"programs": []}
            prog_ids = [r.id for r in rows if getattr(r, "id", None) is not None]
            versions_map: dict[int, list[MiniProgramVersionDB]] = {}
            if prog_ids:
                try:
                    v_rows = (
                        s.execute(
                            _sa_select(MiniProgramVersionDB)
                            .where(MiniProgramVersionDB.program_id.in_(prog_ids))
                            .order_by(
                                MiniProgramVersionDB.program_id.asc(),
                                MiniProgramVersionDB.created_at.desc(),
                                MiniProgramVersionDB.id.desc(),
                            )
                        )
                        .scalars()
                        .all()
                    )
                    for v in v_rows:
                        pid = getattr(v, "program_id", None)
                        if pid is None:
                            continue
                        versions_map.setdefault(int(pid), []).append(v)
                except Exception:
                    versions_map = {}
            # Best-effort Moments share counts per Mini-Program based on
            # shamell://mini_program/<id> deep-links in Moments posts.
            moments_shares: dict[str, int] = {}
            moments_shares_30d: dict[str, int] = {}
            try:
                app_ids = [r.app_id for r in rows]
                if app_ids:
                    with _moments_session() as ms:
                        since_30d = datetime.now(timezone.utc) - timedelta(days=30)
                        for app_id in app_ids:
                            try:
                                pattern = f"shamell://mini_program/{app_id}"
                                base_stmt = _sa_select(
                                    _sa_func.count(MomentPostDB.id)
                                ).where(MomentPostDB.text.contains(pattern))
                                cnt_all = ms.execute(base_stmt).scalar() or 0
                                cnt_30 = (
                                    ms.execute(
                                        base_stmt.where(
                                            MomentPostDB.created_at >= since_30d
                                        )
                                    ).scalar()
                                    or 0
                                )
                                moments_shares[str(app_id)] = int(cnt_all or 0)
                                moments_shares_30d[str(app_id)] = int(cnt_30 or 0)
                            except Exception:
                                continue
            except Exception:
                moments_shares = {}
                moments_shares_30d = {}

            items: list[dict[str, Any]] = []
            for prog in rows:
                scopes_list: list[str] = []
                try:
                    raw_scopes = getattr(prog, "scopes_json", None)
                    if raw_scopes:
                        val = _json.loads(raw_scopes)
                        if isinstance(val, list):
                            scopes_list = [
                                str(s).strip() for s in val if str(s).strip()
                            ]
                except Exception:
                    scopes_list = []
                pid = getattr(prog, "id", None)
                vers = versions_map.get(int(pid)) if pid is not None else None
                last_ver: MiniProgramVersionDB | None = vers[0] if vers else None
                last_version = getattr(last_ver, "version", None) if last_ver else None
                last_bundle_url = getattr(last_ver, "bundle_url", None) if last_ver else None
                try:
                    moments_count = int(
                        moments_shares.get(prog.app_id, 0)
                        or getattr(prog, "moments_shares", 0)
                        or 0
                    )
                except Exception:
                    moments_count = 0
                try:
                    moments_30 = int(
                        moments_shares_30d.get(prog.app_id, 0) or 0
                    )
                except Exception:
                    moments_30 = 0
                items.append(
                    {
                        "app_id": prog.app_id,
                        "title_en": prog.title_en,
                        "title_ar": prog.title_ar,
                        "description_en": getattr(prog, "description_en", None),
                        "description_ar": getattr(prog, "description_ar", None),
                        "owner_name": prog.owner_name,
                        "owner_contact": prog.owner_contact,
                        "status": prog.status,
                        "usage_score": int(getattr(prog, "usage_score", 0) or 0),
                        "rating": float(getattr(prog, "rating", 0.0) or 0.0),
                        "moments_shares": moments_count,
                        "moments_shares_30d": moments_30,
                        "review_status": getattr(prog, "review_status", "draft"),
                        "scopes": scopes_list,
                        "last_version": last_version,
                        "last_bundle_url": last_bundle_url,
                        "created_at": getattr(prog, "created_at", None),
                        "updated_at": getattr(prog, "updated_at", None),
                    }
                )
        return {"programs": items}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/mini_apps/{app_id}/track_open", response_class=JSONResponse)
async def mini_app_track_open(app_id: str, request: Request) -> dict[str, Any]:
    """
    Lightweight Tracking-Endpoint für Mini-App-Opens (WeChat-like analytics).

    Erhöht usage_score für die gegebene app_id – wird vom Client bei
    jedem Öffnen einer Mini-App (Mini-Program) best-effort aufgerufen.
    """
    app_id_clean = (app_id or "").strip()
    if not app_id_clean:
        raise HTTPException(status_code=400, detail="app_id required")
    try:
        with _officials_session() as s:
            row = (
                s.execute(
                    _sa_select(MiniAppDB).where(MiniAppDB.app_id == app_id_clean)
                )
                .scalars()
                .first()
            )
            if not row:
                # Unknown app_id – silently ignore so Client-Aufrufe nicht brechen.
                return {"status": "ignored"}
            try:
                current = int(getattr(row, "usage_score", 0) or 0)
            except Exception:
                current = 0
            row.usage_score = current + 1
            s.add(row)
            s.commit()
        try:
            emit_event(
                "miniapps",
                "open",
                {"app_id": app_id_clean},
            )
        except Exception:
            pass
        return {"status": "ok"}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/mini_apps/{app_id}/rate", response_class=JSONResponse)
async def mini_app_rate(app_id: str, request: Request, body: MiniAppRatingIn) -> dict[str, Any]:
    """
    Simple rating endpoint for Mini-Apps (1–5 stars per user).

    Persists a per-user rating (sa_cookie-based) and updates the
    aggregated rating on the MiniAppDB row, similar to WeChat
    Mini-Program ratings.
    """
    app_id_clean = (app_id or "").strip()
    if not app_id_clean:
        raise HTTPException(status_code=400, detail="app_id required")
    user_key = _official_cookie_key(request)
    try:
        val = int(body.rating)
    except Exception:
        val = 0
    if val < 1:
        val = 1
    if val > 5:
        val = 5
    try:
        with _officials_session() as s:
            app_row = (
                s.execute(
                    _sa_select(MiniAppDB).where(MiniAppDB.app_id == app_id_clean)
                )
                .scalars()
                .first()
            )
            if not app_row or not bool(getattr(app_row, "enabled", True)):
                raise HTTPException(status_code=404, detail="mini-app not found")
            existing = (
                s.execute(
                    _sa_select(MiniAppRatingDB).where(
                        MiniAppRatingDB.app_id == app_id_clean,
                        MiniAppRatingDB.user_key == user_key,
                    )
                )
                .scalars()
                .first()
            )
            if existing:
                existing.rating = val
                s.add(existing)
            else:
                rec = MiniAppRatingDB(app_id=app_id_clean, user_key=user_key, rating=val)
                s.add(rec)
            s.commit()
            avg_rating = 0.0
            rating_count = 0
            try:
                avg_row = (
                    s.execute(
                        _sa_select(
                            _sa_func.avg(MiniAppRatingDB.rating),
                            _sa_func.count(MiniAppRatingDB.id),
                        ).where(MiniAppRatingDB.app_id == app_id_clean)
                    )
                    .first()
                )
                if avg_row:
                    avg_rating = float(avg_row[0] or 0.0)
                    rating_count = int(avg_row[1] or 0)
            except Exception:
                avg_rating = 0.0
                rating_count = 0
            try:
                app_row.rating = avg_rating
                s.add(app_row)
                s.commit()
            except Exception:
                s.rollback()
        try:
            emit_event(
                "miniapps",
                "rate",
                {"app_id": app_id_clean, "user_key": user_key, "rating": val},
            )
        except Exception:
            pass
        return {"status": "ok", "rating": avg_rating, "count": rating_count}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/admin/miniapps/analytics", response_class=HTMLResponse)
def admin_miniapps_analytics(request: Request) -> HTMLResponse:
    """
    Lightweight HTML analytics für Mini-Apps (Mini-Programme).

    Nutzt usage_score und rating als einfache KPIs – ähnlich zu WeChat
    Mini-Program "popular" / "top" Rankings.
    """
    _require_admin_v2(request)
    try:
      with _officials_session() as s:
          rows = (
              s.execute(
                  _sa_select(MiniAppDB).order_by(
                      MiniAppDB.usage_score.desc(), MiniAppDB.rating.desc()
                  )
              )
              .scalars()
              .all()
          )
      total_usage = 0
      for row in rows:
          try:
              total_usage += int(getattr(row, "usage_score", 0) or 0)
          except Exception:
              continue

      def esc(s: str) -> str:
          return _html.escape(s or "", quote=True)

      rows_html: list[str] = []
      for row in rows:
          app_id = row.app_id
          title_en = row.title_en or ""
          title_ar = row.title_ar or ""
          cat = " / ".join(
              [
                  c
                  for c in [
                      getattr(row, "category_en", None) or "",
                      getattr(row, "category_ar", None) or "",
                  ]
                  if c
              ]
          )
          official = bool(getattr(row, "official", False))
          enabled = bool(getattr(row, "enabled", True))
          beta = bool(getattr(row, "beta", False))
          try:
              rating = float(getattr(row, "rating", 0.0) or 0.0)
          except Exception:
              rating = 0.0
          try:
              usage = int(getattr(row, "usage_score", 0) or 0)
          except Exception:
              usage = 0
          share = 0.0
          if total_usage > 0 and usage > 0:
              try:
                  share = (usage / float(total_usage)) * 100.0
              except Exception:
                  share = 0.0
          status_bits: list[str] = []
          if official:
              status_bits.append("official")
          if beta:
              status_bits.append("beta")
          if not enabled:
              status_bits.append("disabled")
          status = ", ".join(status_bits) if status_bits else ""
          rows_html.append(
              "<tr>"
              f"<td><code>{esc(app_id)}</code></td>"
              f"<td>{esc(title_en)}<br/><span class=\"meta\">{esc(title_ar)}</span></td>"
              f"<td>{esc(cat)}</td>"
              f"<td>{esc(status)}</td>"
              f"<td>{rating:.1f}</td>"
              f"<td>{usage}</td>"
              f"<td>{share:.1f}%</td>"
              "</tr>"
          )

      html = f"""
<!doctype html>
<html><head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Mini-Apps · Analytics</title>
  <style>
    body{{font-family:sans-serif;margin:20px;max-width:960px;color:#0f172a;}}
    h1{{margin-bottom:4px;}}
    table{{border-collapse:collapse;width:100%;margin-top:12px;}}
    th,td{{padding:6px 8px;border-bottom:1px solid #e5e7eb;font-size:13px;text-align:left;vertical-align:top;}}
    th{{background:#f9fafb;font-weight:600;}}
    .meta{{color:#6b7280;font-size:12px;margin-top:2px;}}
    code{{background:#f3f4f6;padding:2px 4px;border-radius:3px;font-size:12px;}}
  </style>
</head><body>
  <h1>Mini-Apps · Analytics</h1>
  <div class="meta">
    Basierend auf usage_score (Open-Events via /mini_apps/&lt;id&gt;/track_open) und Rating.<br/>
    Dient als einfache WeChat‑ähnliche Übersicht der beliebtesten Mini-Programme.
  </div>
  <p class="meta">
    <a href="/admin/miniapps">Zurück zur Mini-Apps-Konsole</a>
  </p>
  <table>
    <thead>
      <tr>
        <th>App ID</th>
        <th>Title</th>
        <th>Category</th>
        <th>Status</th>
        <th>Rating</th>
        <th>Usage score</th>
        <th>Share of usage</th>
      </tr>
    </thead>
    <tbody>
      {''.join(rows_html) if rows_html else '<tr><td colspan="7">No Mini-Apps registered yet.</td></tr>'}
    </tbody>
  </table>
</body></html>
"""
      return HTMLResponse(content=html)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/admin/mini_apps", response_class=JSONResponse)
def admin_mini_apps_list(request: Request) -> dict[str, Any]:
    """
    JSON-Admin-Listing für registrierte Mini-Apps (Mini-Programme).

    Dient als Basis für ein Developer-Portal oder einfache Ops-Verwaltung.
    """
    _require_admin_v2(request)
    with _officials_session() as s:
        rows = (
            s.execute(
                _sa_select(MiniAppDB).order_by(MiniAppDB.app_id)
            )
            .scalars()
            .all()
        )
        apps: list[dict[str, Any]] = []
        for row in rows:
            apps.append(
                {
                    "app_id": row.app_id,
                    "title_en": row.title_en,
                    "title_ar": row.title_ar,
                    "category_en": row.category_en,
                    "category_ar": row.category_ar,
                    "description": row.description,
                    "icon": row.icon,
                    "official": bool(getattr(row, "official", False)),
                    "enabled": bool(getattr(row, "enabled", True)),
                    "beta": bool(getattr(row, "beta", False)),
                    "runtime_app_id": getattr(row, "runtime_app_id", None),
                    "rating": float(getattr(row, "rating", 0.0) or 0.0),
                    "usage_score": int(getattr(row, "usage_score", 0) or 0),
                    "created_at": getattr(row, "created_at", None),
                    "updated_at": getattr(row, "updated_at", None),
                }
            )
    return {"apps": apps}


@app.post("/admin/mini_apps", response_class=JSONResponse)
def admin_mini_apps_create(request: Request, body: MiniAppAdminIn) -> dict[str, Any]:
    """
    Legt eine neue Mini-App an (admin only).
    """
    _require_admin_v2(request)
    data = body
    app_id = (data.app_id or "").strip()
    if not app_id:
        raise HTTPException(status_code=400, detail="app_id required")
    with _officials_session() as s:
        existing = (
            s.execute(
                _sa_select(MiniAppDB).where(MiniAppDB.app_id == app_id)
            )
            .scalars()
            .first()
        )
        if existing:
            raise HTTPException(status_code=409, detail="mini-app already exists")
        row = MiniAppDB(
            app_id=app_id,
            title_en=data.title_en,
            title_ar=data.title_ar,
            category_en=data.category_en,
            category_ar=data.category_ar,
            description=data.description,
            icon=data.icon,
            official=data.official,
            enabled=data.enabled,
            beta=data.beta,
            runtime_app_id=data.runtime_app_id,
            rating=data.rating,
            usage_score=data.usage_score or 0,
        )
        s.add(row)
        s.commit()
        s.refresh(row)
        return {
            "app_id": row.app_id,
            "title_en": row.title_en,
            "title_ar": row.title_ar,
            "category_en": row.category_en,
            "category_ar": row.category_ar,
            "description": row.description,
            "icon": row.icon,
            "official": bool(row.official),
            "enabled": bool(row.enabled),
            "beta": bool(row.beta),
            "rating": float(row.rating or 0.0),
            "usage_score": int(row.usage_score or 0),
        }


@app.patch("/admin/mini_apps/{app_id}", response_class=JSONResponse)
def admin_mini_apps_update(
    app_id: str, request: Request, body: dict[str, Any]
) -> dict[str, Any]:
    """
    Aktualisiert Felder einer Mini-App (admin only).
    """
    _require_admin_v2(request)
    if not isinstance(body, dict):
        body = {}
    allowed_fields = {
        "title_en",
        "title_ar",
        "category_en",
        "category_ar",
        "description",
        "icon",
        "official",
        "enabled",
        "beta",
        "runtime_app_id",
        "rating",
        "usage_score",
    }
    app_id_clean = (app_id or "").strip()
    if not app_id_clean:
        raise HTTPException(status_code=400, detail="app_id required")
    with _officials_session() as s:
        row = (
            s.execute(
                _sa_select(MiniAppDB).where(MiniAppDB.app_id == app_id_clean)
            )
            .scalars()
            .first()
        )
        if not row:
            raise HTTPException(status_code=404, detail="mini-app not found")
        for k, v in body.items():
            if k in allowed_fields:
                setattr(row, k, v)
        s.add(row)
        s.commit()
        s.refresh(row)
        return {
            "app_id": row.app_id,
            "title_en": row.title_en,
            "title_ar": row.title_ar,
            "category_en": row.category_en,
            "category_ar": row.category_ar,
            "description": row.description,
            "icon": row.icon,
            "official": bool(row.official),
            "enabled": bool(row.enabled),
            "beta": bool(row.beta),
            "rating": float(row.rating or 0.0),
            "usage_score": int(row.usage_score or 0),
        }


@app.delete("/admin/mini_apps/{app_id}", response_class=JSONResponse)
def admin_mini_apps_delete(app_id: str, request: Request) -> dict[str, Any]:
    """
    Deaktiviert eine Mini-App (soft delete via enabled=False).
    """
    _require_admin_v2(request)
    app_id_clean = (app_id or "").strip()
    if not app_id_clean:
        raise HTTPException(status_code=400, detail="app_id required")
    with _officials_session() as s:
        row = (
            s.execute(
                _sa_select(MiniAppDB).where(MiniAppDB.app_id == app_id_clean)
            )
            .scalars()
            .first()
        )
        if not row:
            raise HTTPException(status_code=404, detail="mini-app not found")
        row.enabled = False
        s.add(row)
        s.commit()
    return {"status": "ok"}


@app.get("/official_accounts/{account_id}/feed", response_class=JSONResponse)
async def official_account_feed(request: Request, account_id: str, limit: int = 20):
    try:
        limit_val = max(1, min(limit, 200))
        user_key = _official_cookie_key(request)
        with _officials_session() as s:
            acc = s.get(OfficialAccountDB, account_id)
            if not acc or not acc.enabled:
                raise HTTPException(status_code=404, detail="unknown official account")
            stmt = (
                _sa_select(OfficialFeedItemDB)
                .where(OfficialFeedItemDB.account_id == account_id)
                .order_by(OfficialFeedItemDB.ts.desc(), OfficialFeedItemDB.id.desc())
                .limit(limit_val)
            )
            rows = s.execute(stmt).scalars().all()
            items: list[dict[str, Any]] = []
            for row in rows:
                try:
                    deeplink = _json.loads(row.deeplink_json) if row.deeplink_json else None
                except Exception:
                    deeplink = None
                items.append(
                    OfficialFeedItemOut(
                        id=row.slug or str(row.id),
                        type=row.type,
                        title=row.title,
                        snippet=row.snippet,
                        thumb_url=row.thumb_url,
                        ts=row.ts.isoformat() if getattr(row, "ts", None) else None,
                        deeplink=deeplink,
                    ).dict()
                )
        try:
            emit_event(
                "officials",
                "feed_view",
                {"user_key": user_key, "account_id": account_id, "limit": limit_val, "returned": len(items)},
            )
        except Exception:
            pass
        return {"items": items}
    except HTTPException:
        raise
    except Exception:
        if account_id not in _OFFICIAL_ACCOUNTS:
            raise HTTPException(status_code=404, detail="unknown official account")
        acc = _OFFICIAL_ACCOUNTS[account_id]
        seed = _OFFICIAL_FEED_SEED.get(acc.id, [])
        base_items: list[OfficialFeedItemOut] = []
        for item in seed[: max(0, min(limit, len(seed)))]:
            base_items.append(
                OfficialFeedItemOut(
                    id=item.get("id", ""),
                    type=item.get("type", "promo"),
                    title=item.get("title"),
                    snippet=item.get("snippet"),
                    thumb_url=item.get("thumb_url"),
                    ts=item.get("ts"),
                    deeplink=item.get("deeplink"),
                )
            )
        items_out = [i.dict() for i in base_items]
        try:
            emit_event(
                "officials",
                "feed_view",
                {"user_key": user_key, "account_id": account_id, "limit": limit, "returned": len(items_out), "mode": "fallback"},
            )
        except Exception:
            pass
        return {"items": items_out}


@app.get("/official_accounts/{account_id}/moments_stats", response_class=JSONResponse)
def official_account_moments_stats(account_id: str) -> dict[str, Any]:
    """
    Aggregate Moments "social impact" stats for a single Official account.

    Returns total Moments shares with origin_official_account_id = account_id,
    how many of those mention red packets in the last 30 days, plus basic
    "social impact" KPIs used in merchant UIs.
    """
    try:
        total = 0
        shares_30 = 0
        uniq_total = 0
        uniq_30 = 0
        rp_30 = 0
        comments_total = 0
        comments_30 = 0
        followers = 0
        with _moments_session() as s:
            total = (
                s.execute(
                    _sa_select(_sa_func.count(MomentPostDB.id)).where(
                        MomentPostDB.origin_official_account_id == account_id
                    )
                )
                .scalar()
                or 0
            )
            since = datetime.now(timezone.utc) - timedelta(days=30)

            try:
                shares_30 = (
                    s.execute(
                        _sa_select(_sa_func.count(MomentPostDB.id)).where(
                            MomentPostDB.origin_official_account_id
                            == account_id,
                            MomentPostDB.created_at >= since,
                        )
                    )
                    .scalar()
                    or 0
                )
            except Exception:
                shares_30 = 0

            # Unique sharers (all time)
            try:
                uniq_total = (
                    s.execute(
                        _sa_select(
                            _sa_func.count(
                                _sa_func.distinct(MomentPostDB.user_key)
                            )
                        ).where(
                            MomentPostDB.origin_official_account_id
                            == account_id
                        )
                    )
                    .scalar()
                    or 0
                )
                uniq_30 = (
                    s.execute(
                        _sa_select(
                            _sa_func.count(
                                _sa_func.distinct(MomentPostDB.user_key)
                            )
                        ).where(
                            MomentPostDB.origin_official_account_id
                            == account_id,
                            MomentPostDB.created_at >= since,
                        )
                    )
                    .scalar()
                    or 0
                )
            except Exception:
                uniq_total = 0
                uniq_30 = 0

            # Red-packet related shares in the last 30 days
            try:
                rp1 = (
                    s.execute(
                        _sa_select(_sa_func.count(MomentPostDB.id)).where(
                            MomentPostDB.origin_official_account_id
                            == account_id,
                            MomentPostDB.created_at >= since,
                            MomentPostDB.text.contains("Red packet"),
                        )
                    )
                    .scalar()
                    or 0
                )
                rp2 = (
                    s.execute(
                        _sa_select(_sa_func.count(MomentPostDB.id)).where(
                            MomentPostDB.origin_official_account_id
                            == account_id,
                            MomentPostDB.created_at >= since,
                            MomentPostDB.text.contains(
                                "I am sending red packets via Shamell Pay"
                            ),
                        )
                    )
                    .scalar()
                    or 0
                )
                rp3 = (
                    s.execute(
                        _sa_select(_sa_func.count(MomentPostDB.id)).where(
                            MomentPostDB.origin_official_account_id
                            == account_id,
                            MomentPostDB.created_at >= since,
                            MomentPostDB.text.contains("حزمة حمراء"),
                        )
                    )
                    .scalar()
                    or 0
                )
                rp_30 = int((rp1 or 0) + (rp2 or 0) + (rp3 or 0))
            except Exception:
                rp_30 = 0

            # Comment volume (all time / last 30 days) for posts of this Official
            try:
                comments_total = (
                    s.execute(
                        _sa_select(_sa_func.count(MomentCommentDB.id))
                        .select_from(MomentCommentDB)
                        .join(
                            MomentPostDB,
                            MomentCommentDB.post_id == MomentPostDB.id,
                        )
                        .where(
                            MomentPostDB.origin_official_account_id
                            == account_id
                        )
                    )
                    .scalar()
                    or 0
                )
                comments_30 = (
                    s.execute(
                        _sa_select(_sa_func.count(MomentCommentDB.id))
                        .select_from(MomentCommentDB)
                        .join(
                            MomentPostDB,
                            MomentCommentDB.post_id == MomentPostDB.id,
                        )
                        .where(
                            MomentPostDB.origin_official_account_id
                            == account_id,
                            MomentCommentDB.created_at >= since,
                        )
                    )
                    .scalar()
                    or 0
                )
            except Exception:
                comments_total = 0
                comments_30 = 0

        # Follower count for this Official (for per-1k metric)
        try:
            with _officials_session() as osess:
                followers = (
                    osess.execute(
                        _sa_select(_sa_func.count(OfficialFollowDB.id)).where(
                            OfficialFollowDB.account_id == account_id
                        )
                    )
                    .scalar()
                    or 0
                )
        except Exception:
            followers = 0

        shares_per_1k = 0.0
        try:
            if followers and total:
                shares_per_1k = (float(total) / float(followers)) * 1000.0
        except Exception:
            shares_per_1k = 0.0

        return {
            "total_shares": int(total or 0),
            "shares_30d": int(shares_30 or 0),
            "redpacket_shares_30d": int(rp_30 or 0),
            "unique_sharers_total": int(uniq_total or 0),
            "unique_sharers_30d": int(uniq_30 or 0),
            "followers": int(followers or 0),
            "shares_per_1k_followers": shares_per_1k,
            "comments_total": int(comments_total or 0),
            "comments_30d": int(comments_30 or 0),
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/channels/feed", response_class=JSONResponse)
def channels_feed(
    request: Request,
    limit: int = 50,
    official_account_id: str | None = None,
) -> dict[str, Any]:
    """
    Lightweight "Channels" feed built from Official feed items.

    This is a WeChat‑like short feed that surfaces recent
    Official promotions and content in a unified view, with
    simple likes and view counters.
    """
    user_key = _official_cookie_key(request)
    try:
        limit_val = max(1, min(limit, 100))
        with _officials_session() as s:
            stmt = _sa_select(
                OfficialFeedItemDB,
                OfficialAccountDB.name,
                OfficialAccountDB.avatar_url,
                OfficialAccountDB.city,
                OfficialAccountDB.category,
            ).join(
                OfficialAccountDB,
                OfficialFeedItemDB.account_id == OfficialAccountDB.id,
            ).where(
                OfficialAccountDB.enabled == True  # type: ignore[comparison-overlap]
            )
            if official_account_id:
                stmt = stmt.where(
                    OfficialFeedItemDB.account_id == official_account_id
                )
            stmt = stmt.order_by(
                OfficialFeedItemDB.ts.desc(), OfficialFeedItemDB.id.desc()
            ).limit(limit_val)
            rows = s.execute(stmt).all()
            item_ids = [str(feed_row.id) for feed_row, _, _, _, _ in rows]
            likes_map: dict[str, int] = {}
            liked_by_me: set[str] = set()
            views_map: dict[str, int] = {}
            comments_map: dict[str, int] = {}
            if item_ids:
                like_rows = (
                    s.execute(
                        _sa_select(
                            ChannelLikeDB.item_id,
                            _sa_func.count(ChannelLikeDB.id),
                        )
                        .where(ChannelLikeDB.item_id.in_(item_ids))
                        .group_by(ChannelLikeDB.item_id)
                    )
                    .all()
                )
                for iid, cnt in like_rows:
                    likes_map[str(iid)] = int(cnt or 0)
                my_like_rows = (
                    s.execute(
                        _sa_select(ChannelLikeDB.item_id).where(
                            ChannelLikeDB.item_id.in_(item_ids),
                            ChannelLikeDB.user_key == user_key,
                        )
                    )
                    .scalars()
                    .all()
                )
                liked_by_me.update(str(iid) for iid in my_like_rows)
                view_rows = (
                    s.execute(
                        _sa_select(
                            ChannelViewDB.item_id,
                            ChannelViewDB.views,
                        ).where(ChannelViewDB.item_id.in_(item_ids))
                    )
                    .all()
                )
                for iid, views in view_rows:
                    try:
                        views_map[str(iid)] = int(views or 0)
                    except Exception:
                        continue
                comment_rows = (
                    s.execute(
                        _sa_select(
                            ChannelCommentDB.item_id,
                            _sa_func.count(ChannelCommentDB.id),
                        )
                        .where(ChannelCommentDB.item_id.in_(item_ids))
                        .group_by(ChannelCommentDB.item_id)
                    )
                    .all()
                )
                for iid, cnt in comment_rows:
                    try:
                        comments_map[str(iid)] = int(cnt or 0)
                    except Exception:
                        continue
        # Compute "hot in Moments" per Official based on total Moments shares,
        # a dedicated follower graph for Channels based on ChannelFollowDB,
        # and simple gift/coin stats per clip from ChannelGiftDB.
        hot_accounts: set[str] = set()
        channel_followers: dict[str, int] = {}
        channel_followed_by_me: set[str] = set()
        gift_totals: dict[str, int] = {}
        gift_by_me: dict[str, int] = {}
        try:
            acc_ids: set[str] = set()
            for feed_row, _, _, _, _ in rows:
                acc_id_val = getattr(feed_row, "account_id", None)
                if acc_id_val:
                    acc_ids.add(str(acc_id_val))
            if acc_ids:
                # Moments-derived "hot" flag.
                with _moments_session() as ms:
                    agg_rows = (
                        ms.execute(
                            _sa_select(
                                MomentPostDB.origin_official_account_id,
                                _sa_func.count(MomentPostDB.id),
                            )
                            .where(
                                MomentPostDB.origin_official_account_id.in_(
                                    list(acc_ids)
                                )
                            )
                            .group_by(MomentPostDB.origin_official_account_id)
                        )
                        .all()
                    )
                    for acc_id, cnt in agg_rows:
                        try:
                            if int(cnt or 0) >= 10:
                                hot_accounts.add(str(acc_id))
                        except Exception:
                            continue
                # Follower counts and "followed by me" for these channels.
                try:
                    with _officials_session() as osess:
                        f_rows = (
                            osess.execute(
                                _sa_select(
                                    ChannelFollowDB.account_id,
                                    _sa_func.count(ChannelFollowDB.id),
                                )
                                .where(ChannelFollowDB.account_id.in_(list(acc_ids)))
                                .group_by(ChannelFollowDB.account_id)
                            )
                            .all()
                        )
                        for acc_id, cnt in f_rows:
                            try:
                                channel_followers[str(acc_id)] = int(cnt or 0)
                            except Exception:
                                continue
                        my_rows = osess.execute(
                            _sa_select(ChannelFollowDB.account_id).where(
                                ChannelFollowDB.account_id.in_(list(acc_ids)),
                                ChannelFollowDB.user_key == user_key,
                            )
                        ).scalars().all()
                        channel_followed_by_me.update(str(aid) for aid in my_rows)
                    # Gift/coin stats per clip.
                    try:
                        g_rows = (
                            osess.execute(
                                _sa_select(
                                    ChannelGiftDB.item_id,
                                    _sa_func.sum(ChannelGiftDB.coins),
                                ).group_by(ChannelGiftDB.item_id)
                            )
                            .all()
                        )
                        for iid, total in g_rows:
                            try:
                                gift_totals[str(iid)] = int(total or 0)
                            except Exception:
                                continue
                        my_gift_rows = (
                            osess.execute(
                                _sa_select(
                                    ChannelGiftDB.item_id,
                                    _sa_func.sum(ChannelGiftDB.coins),
                                )
                                .where(ChannelGiftDB.user_key == user_key)
                                .group_by(ChannelGiftDB.item_id)
                            )
                            .all()
                        )
                        for iid, total in my_gift_rows:
                            try:
                                gift_by_me[str(iid)] = int(total or 0)
                            except Exception:
                                continue
                    except Exception:
                        gift_totals = {}
                        gift_by_me = {}
                except Exception:
                    channel_followers = {}
                    channel_followed_by_me = set()
                    gift_totals = {}
                    gift_by_me = {}
        except Exception:
            hot_accounts = set()
            channel_followers = {}
            channel_followed_by_me = set()
            gift_totals = {}
            gift_by_me = {}

        # Compute a simple WeChat-like ranking score per clip
        # based on engagement and how "hot" the originating
        # Official account is in Moments – similar to the
        # /search heuristics for Channels.
        scored_rows: list[
            tuple[
                float,
                Any,
                Any,
                Any,
                Any,
                Any,
            ]
        ] = []
        for feed_row, acc_name, acc_avatar, acc_city, acc_category in rows:
            item_id = str(getattr(feed_row, "id", ""))
            likes = likes_map.get(item_id, 0)
            views = views_map.get(item_id, 0)
            comments = comments_map.get(item_id, 0)
            f_type = (getattr(feed_row, "type", "") or "").strip().lower()
            acc_id_val = getattr(feed_row, "account_id", None)
            acc_id_str = str(acc_id_val) if acc_id_val is not None else ""
            score = 20.0
            # WeChat-like boost for special content types – live items
            # should surface very prominently, followed by campaigns.
            if f_type == "live":
                score += 15.0
            elif f_type in {"campaign", "promo"}:
                score += 10.0
            if acc_id_str in hot_accounts:
                score += 5.0
            try:
                if views > 0:
                    score += min(views, 5000) / 200.0
            except Exception:
                pass
            try:
                if likes > 0:
                    score += min(likes, 500) * 0.5
            except Exception:
                pass
            try:
                if comments > 0:
                    score += min(comments, 100) * 1.0
            except Exception:
                pass
            scored_rows.append(
                (score, feed_row, acc_name, acc_avatar, acc_city, acc_category)
            )
        scored_rows.sort(key=lambda t: t[0], reverse=True)

        items: list[dict[str, Any]] = []
        for score, feed_row, acc_name, acc_avatar, acc_city, acc_category in scored_rows:
            ts_val = getattr(feed_row, "ts", None)
            if isinstance(ts_val, datetime):
                ts_str = ts_val.isoformat().replace("+00:00", "Z")
            else:
                ts_str = None
            item_id = str(getattr(feed_row, "id", ""))
            acc_id_val = getattr(feed_row, "account_id", None)
            acc_id_str = str(acc_id_val) if acc_id_val is not None else ""
            items.append(
                ChannelItemOut(
                    id=item_id,
                    title=getattr(feed_row, "title", None),
                    snippet=getattr(feed_row, "snippet", None),
                    thumb_url=getattr(feed_row, "thumb_url", None),
                    ts=ts_str,
                    item_type=getattr(feed_row, "type", None),
                    official_account_id=acc_id_val,
                    official_name=str(acc_name or "")
                    if acc_name is not None
                    else None,
                    official_avatar_url=str(acc_avatar or "")
                    if acc_avatar is not None
                    else None,
                    official_city=str(acc_city or "") if acc_city is not None else None,
                    official_category=str(acc_category or "")
                    if acc_category is not None
                    else None,
                    likes=likes_map.get(item_id, 0),
                    liked_by_me=item_id in liked_by_me,
                    views=views_map.get(item_id, 0),
                    comments=comments_map.get(item_id, 0),
                    official_is_hot=acc_id_str in hot_accounts,
                    channel_followers=channel_followers.get(acc_id_str, 0),
                    channel_followed_by_me=acc_id_str in channel_followed_by_me,
                    gifts=gift_totals.get(item_id, 0),
                    gifts_by_me=gift_by_me.get(item_id, 0),
                    score=score,
                ).dict()
            )
        return {"items": items}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/channels/{item_id}/moments_stats", response_class=JSONResponse)
def channels_item_moments_stats(item_id: str) -> dict[str, Any]:
    """
    Moments-Analytics für einen einzelnen Channels-Clip.

    Nutzt shamell://official/<account>/<item_id>-Deeplinks in
    Moments-Posts, um WeChat-ähnliche Kennzahlen zu liefern:
    Gesamt-Shares, 30d-Shares, Unique-Sharer und einfache 30d-Kurve.
    """
    clean_id = (item_id or "").strip()
    if not clean_id:
        raise HTTPException(status_code=400, detail="item_id required")
    try:
        # Resolve owning Official account and optional slug for this feed item.
        acc_id: str | None = None
        slug: str | None = None
        with _officials_session() as s:
            row = s.get(OfficialFeedItemDB, clean_id)
            if row is None:
                # Some deployments may use slug-based IDs – try slug lookup.
                feed_row = (
                    s.execute(
                        _sa_select(OfficialFeedItemDB).where(
                            OfficialFeedItemDB.slug == clean_id
                        )
                    )
                    .scalars()
                    .first()
                )
                row = feed_row
            if row is None:
                raise HTTPException(status_code=404, detail="channels item not found")
            try:
                acc_val = getattr(row, "account_id", None)
                if acc_val is not None:
                    acc_id = str(acc_val)
            except Exception:
                acc_id = None
            try:
                slug_val = getattr(row, "slug", None)
                if slug_val:
                    slug = str(slug_val)
            except Exception:
                slug = None

        if not acc_id:
            raise HTTPException(status_code=404, detail="channels item not linked to account")

        # Build possible deeplink patterns as seen in Moments posts.
        patterns: list[str] = []
        # Primary pattern used by client when sharing Channels to Moments.
        patterns.append(f"shamell://official/{acc_id}/{clean_id}")
        if slug and slug != clean_id:
            patterns.append(f"shamell://official/{acc_id}/{slug}")

        def _base_filter() -> Any:
            cond = None
            for p in patterns:
                if not p:
                    continue
                expr = MomentPostDB.text.contains(p)
                cond = expr if cond is None else (cond | expr)
            return cond

        total = 0
        total_30d = 0
        uniq_total = 0
        uniq_30d = 0
        series_30d: list[dict[str, Any]] = []
        try:
            with _moments_session() as ms:
                since_30d = datetime.now(timezone.utc) - timedelta(days=30)
                cond = _base_filter()
                if cond is None:
                    return {
                        "item_id": clean_id,
                        "official_account_id": acc_id,
                        "shares_total": 0,
                        "shares_30d": 0,
                        "unique_sharers_total": 0,
                        "unique_sharers_30d": 0,
                        "series_30d": [],
                    }
                # All-time total shares.
                total = (
                    ms.execute(
                        _sa_select(_sa_func.count(MomentPostDB.id)).where(cond)
                    )
                    .scalar()
                    or 0
                )
                # 30d shares.
                total_30d = (
                    ms.execute(
                        _sa_select(_sa_func.count(MomentPostDB.id)).where(
                            cond, MomentPostDB.created_at >= since_30d
                        )
                    )
                    .scalar()
                    or 0
                )
                # Unique sharers all-time.
                uniq_total = (
                    ms.execute(
                        _sa_select(
                            _sa_func.count(
                                _sa_func.distinct(MomentPostDB.user_key)
                            )
                        ).where(cond)
                    )
                    .scalar()
                    or 0
                )
                # Unique sharers 30d.
                uniq_30d = (
                    ms.execute(
                        _sa_select(
                            _sa_func.count(
                                _sa_func.distinct(MomentPostDB.user_key)
                            )
                        ).where(
                            cond, MomentPostDB.created_at >= since_30d
                        )
                    )
                    .scalar()
                    or 0
                )
                # Daily curve for last 30 days.
                rows = (
                    ms.execute(
                        _sa_select(
                            _sa_func.date(MomentPostDB.created_at),
                            _sa_func.count(MomentPostDB.id),
                        )
                        .where(cond, MomentPostDB.created_at >= since_30d)
                        .group_by(_sa_func.date(MomentPostDB.created_at))
                        .order_by(_sa_func.date(MomentPostDB.created_at))
                    )
                    .all()
                )
                for d, cnt in rows:
                    try:
                        if isinstance(d, datetime):
                            date_str = d.date().isoformat()
                        else:
                            date_str = str(d)
                    except Exception:
                        date_str = str(d)
                    series_30d.append(
                        {"date": date_str, "shares": int(cnt or 0)}
                    )
        except Exception:
            total = 0
            total_30d = 0
            uniq_total = 0
            uniq_30d = 0
            series_30d = []

        return {
            "item_id": clean_id,
            "official_account_id": acc_id,
            "shares_total": int(total or 0),
            "shares_30d": int(total_30d or 0),
            "unique_sharers_total": int(uniq_total or 0),
            "unique_sharers_30d": int(uniq_30d or 0),
            "series_30d": series_30d,
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/stickers/my", response_class=JSONResponse)
def stickers_my(request: Request) -> dict[str, Any]:
    """
    Returns the IDs of sticker packs owned by the current user.

    This supports cross-device sync so the Sticker‑Store can show a
    WeChat‑like \"Owned\" state.
    """
    phone = _auth_phone(request)
    if not phone:
        # Anonymous users simply have no server‑side purchases.
        return {"packs": []}
    try:
        with _stickers_session() as s:
            rows = (
                s.execute(
                    _sa_select(StickerPurchaseDB.pack_id).where(
                        StickerPurchaseDB.user_phone == phone
                    )
                )
                .scalars()
                .all()
            )
        return {"packs": [str(pid) for pid in rows]}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/stickers/purchase", response_class=JSONResponse)
async def stickers_purchase(request: Request) -> dict[str, Any]:
    """
    Mark a sticker pack as owned for the current user (idempotent).

    All packs are currently free; the endpoint only records ownership so the
    client can sync \"Owned\" across devices.
    """
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    try:
        body = await request.json()
    except Exception:
        body = {}
    if not isinstance(body, dict):
        body = {}
    pack_id = (body.get("pack_id") or "").strip()
    if not pack_id:
        raise HTTPException(status_code=400, detail="pack_id required")

    # Resolve pack metadata from catalog.
    packs = _sticker_packs_config()
    pack_meta: dict[str, Any] | None = None
    for p in packs:
        try:
            if (p.get("id") or "").strip() == pack_id:
                pack_meta = p
                break
        except Exception:
            continue
    if not pack_meta:
        raise HTTPException(status_code=404, detail="unknown sticker pack")

    price_raw = pack_meta.get("price_cents") or 0
    try:
        price_cents = int(price_raw)
    except Exception:
        price_cents = 0
    currency = (pack_meta.get("currency") or DEFAULT_CURRENCY).strip() or DEFAULT_CURRENCY

    try:
        with _stickers_session() as s:
            # Idempotent per user/pack: if we already have a record, do not duplicate.
            existing = (
                s.execute(
                    _sa_select(StickerPurchaseDB).where(
                        StickerPurchaseDB.user_phone == phone,
                        StickerPurchaseDB.pack_id == pack_id,
                    )
                )
                .scalars()
                .first()
            )
            if existing:
                return {
                    "status": "ok",
                    "pack_id": pack_id,
                    "owned": True,
                    "price_cents": existing.amount_cents,
                    "currency": existing.currency,
                }

            rec = StickerPurchaseDB(
                user_phone=phone,
                pack_id=pack_id,
                amount_cents=price_cents,
                currency=currency,
            )
            s.add(rec)
            s.commit()
            return {
                "status": "ok",
                "pack_id": pack_id,
                "owned": True,
                "price_cents": price_cents,
                "currency": currency,
            }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/stickers/packs", response_class=JSONResponse)
def stickers_packs(request: Request) -> dict[str, Any]:
    """
    Server‑side sticker pack catalog for the Sticker‑Store.

    Returns a small list of packs with IDs that mirror the
    built‑in Flutter packs so that the client can render a
    WeChat‑like online sticker marketplace.

    When the user is authenticated, each pack includes an
    \"owned\" flag based on StickerPurchaseDB so the client
    can show a WeChat‑like \"Owned\" state.
    """
    try:
        packs = _sticker_packs_config()
        phone = _auth_phone(request)
        owned_ids: set[str] = set()
        if phone:
            try:
                with _stickers_session() as s:
                    rows = (
                        s.execute(
                            _sa_select(StickerPurchaseDB.pack_id).where(
                                StickerPurchaseDB.user_phone == phone
                            )
                        )
                        .scalars()
                        .all()
                    )
                    owned_ids = {str(pid) for pid in rows}
            except Exception:
                owned_ids = set()
        out_packs: list[dict[str, Any]] = []
        for p in packs:
            try:
                m = dict(p)
            except Exception:
                continue
            pid = (m.get("id") or "").strip()
            m["owned"] = bool(pid and pid in owned_ids)
            out_packs.append(m)
        return {"packs": out_packs}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/channels/{item_id}/like", response_class=JSONResponse)
def channels_like(item_id: str, request: Request) -> dict[str, Any]:
    """
    Toggle like for a Channels item (idempotent per user).
    """
    user_key = _official_cookie_key(request)
    clean_id = (item_id or "").strip()
    if not clean_id:
        raise HTTPException(status_code=400, detail="item_id required")
    try:
        with _officials_session() as s:
            existing = (
                s.execute(
                    _sa_select(ChannelLikeDB).where(
                        ChannelLikeDB.item_id == clean_id,
                        ChannelLikeDB.user_key == user_key,
                    )
                )
                .scalars()
                .first()
            )
            liked = False
            if existing:
                s.delete(existing)
                liked = False
            else:
                s.add(
                    ChannelLikeDB(
                        item_id=clean_id,
                        user_key=user_key,
                    )
                )
                liked = True
            s.commit()
            likes = (
                s.execute(
                    _sa_select(_sa_func.count(ChannelLikeDB.id)).where(
                        ChannelLikeDB.item_id == clean_id
                    )
                )
                .scalar()
                or 0
            )
        try:
            emit_event(
                "channels",
                "like",
                {"user_key": user_key, "item_id": clean_id, "liked": liked},
            )
        except Exception:
            pass
        return {"likes": int(likes or 0), "liked": liked}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/channels/{item_id}/comments", response_class=JSONResponse)
def channels_comments(item_id: str, request: Request, limit: int = 50) -> dict[str, Any]:
    """
    Returns latest comments for a Channels item.

    Lightweight, per-item thread similar to WeChat Channels comments.
    """
    _ = _official_cookie_key(request)
    clean_id = (item_id or "").strip()
    if not clean_id:
        raise HTTPException(status_code=400, detail="item_id required")
    try:
        limit_val = max(1, min(limit, 200))
        with _officials_session() as s:
            rows = (
                s.execute(
                    _sa_select(ChannelCommentDB)
                    .where(ChannelCommentDB.item_id == clean_id)
                    .order_by(
                        ChannelCommentDB.created_at.asc(),
                        ChannelCommentDB.id.asc(),
                    )
                    .limit(limit_val)
                )
                .scalars()
                .all()
            )
            items: list[dict[str, Any]] = []
            for row in rows:
                created = getattr(row, "created_at", None)
                try:
                    created_str = (
                        created.isoformat().replace("+00:00", "Z")
                        if isinstance(created, datetime)
                        else None
                    )
                except Exception:
                    created_str = str(created) if created is not None else None
                user_key = getattr(row, "user_key", "") or ""
                author_kind = "official" if user_key.startswith("official:") else "user"
                items.append(
                    {
                        "id": row.id,
                        "item_id": row.item_id,
                        "text": row.text,
                        "created_at": created_str,
                        "author_kind": author_kind,
                    }
                )
        return {"items": items}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


class ChannelGiftIn(BaseModel):
    account_id: str
    coins: int = 1
    gift_kind: str | None = None


@app.post("/channels/{item_id}/gift", response_class=JSONResponse)
def channels_item_gift(item_id: str, request: Request, body: ChannelGiftIn) -> dict[str, Any]:
    """
    Send a lightweight gift / coin to a Channels clip.

    This records engagement in ChannelGiftDB without moving real
    funds; coin-based payouts can be implemented separately via
    the payments layer.
    """
    clean_id = (item_id or "").strip()
    if not clean_id:
        raise HTTPException(status_code=400, detail="item_id required")
    account_id = (body.account_id or "").strip()
    if not account_id:
        raise HTTPException(status_code=400, detail="account_id required")
    coins = int(body.coins or 0)
    if coins <= 0:
        raise HTTPException(status_code=400, detail="coins must be > 0")
    # Soft cap per request to avoid accidental huge numbers.
    if coins > 1000:
        coins = 1000
    user_key = _channels_user_key(request)
    gift_kind = (body.gift_kind or "coin").strip().lower() or "coin"
    try:
        with _officials_session() as s:
            # Ensure the Channels item exists and belongs to the given account.
            feed_row = s.get(OfficialFeedItemDB, clean_id)
            if feed_row is None:
                # Some deployments may expose slug-based IDs.
                feed_row = (
                    s.execute(
                        _sa_select(OfficialFeedItemDB).where(
                            OfficialFeedItemDB.slug == clean_id
                        )
                    )
                    .scalars()
                    .first()
                )
            if feed_row is None:
                raise HTTPException(
                    status_code=404, detail="channels item not found"
                )
            acc_val = getattr(feed_row, "account_id", None)
            if not acc_val or str(acc_val) != account_id:
                raise HTTPException(
                    status_code=400, detail="account_id does not match clip"
                )
            s.add(
                ChannelGiftDB(
                    user_key=user_key,
                    account_id=account_id,
                    item_id=str(getattr(feed_row, "id", clean_id)),
                    gift_kind=gift_kind,
                    coins=coins,
                )
            )
            s.commit()
        try:
            emit_event(
                "channels",
                "gift",
                {
                    "user_key": user_key,
                    "account_id": account_id,
                    "item_id": clean_id,
                    "coins": coins,
                    "gift_kind": gift_kind,
                },
            )
        except Exception:
            pass
        return {"status": "ok"}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/channels/{item_id}/comments", response_class=JSONResponse)
def channels_add_comment(
    item_id: str, request: Request, body: ChannelCommentIn
) -> dict[str, Any]:
    """
    Adds a new comment to a Channels item for the current user.
    """
    user_key = _official_cookie_key(request)
    clean_id = (item_id or "").strip()
    if not clean_id:
        raise HTTPException(status_code=400, detail="item_id required")
    text = (body.text or "").strip()
    if not text:
        raise HTTPException(status_code=400, detail="text required")
    try:
        with _officials_session() as s:
            # Best-effort validation that the target feed item exists.
            try:
                fid = int(clean_id)
            except Exception:
                raise HTTPException(status_code=404, detail="unknown channel item")
            feed = s.get(OfficialFeedItemDB, fid)
            if not feed:
                raise HTTPException(status_code=404, detail="unknown channel item")
            row = ChannelCommentDB(item_id=clean_id, user_key=user_key, text=text)
            s.add(row)
            s.commit()
            s.refresh(row)
            created = getattr(row, "created_at", None)
            try:
                created_str = (
                    created.isoformat().replace("+00:00", "Z")
                    if isinstance(created, datetime)
                    else None
                )
            except Exception:
                created_str = str(created) if created is not None else None
        try:
            emit_event(
                "channels",
                "comment",
                {"user_key": user_key, "item_id": clean_id, "comment_id": row.id},
            )
        except Exception:
            pass
        return {
            "id": row.id,
            "item_id": row.item_id,
            "text": row.text,
            "created_at": created_str,
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/channels/{item_id}/view", response_class=JSONResponse)
def channels_view(item_id: str, request: Request) -> dict[str, Any]:
    """
    Increment view counter for a Channels item.
    """
    _ = _official_cookie_key(request)
    clean_id = (item_id or "").strip()
    if not clean_id:
        raise HTTPException(status_code=400, detail="item_id required")
    try:
        with _officials_session() as s:
            row = (
                s.execute(
                    _sa_select(ChannelViewDB).where(
                        ChannelViewDB.item_id == clean_id
                    )
                )
                .scalars()
                .first()
            )
            if row is None:
                row = ChannelViewDB(item_id=clean_id, views=1)
                s.add(row)
            else:
                try:
                    current = int(getattr(row, "views", 0) or 0)
                except Exception:
                    current = 0
                row.views = current + 1
                s.add(row)
            s.commit()
            views = int(getattr(row, "views", 0) or 0)
        try:
            emit_event(
                "channels",
                "view",
                {"item_id": clean_id, "views": views},
            )
        except Exception:
            pass
        return {"views": views}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/channels/upload", response_class=JSONResponse)
def channels_upload(request: Request, body: ChannelUploadIn) -> dict[str, Any]:
    """
    Creator-style upload endpoint for Channels clips.

    Authenticated users can attach a short clip to a specific Official
    account. The item is stored as OfficialFeedItemDB with type "clip"
    so it appears in Channels feed and the Official's feed.
    """
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="auth required")
    acc_id = (body.official_account_id or "").strip()
    if not acc_id:
        raise HTTPException(status_code=400, detail="official_account_id required")
    title = (body.title or "").strip() or None
    snippet = (body.snippet or "").strip() or None
    thumb_url = (body.thumb_url or "").strip() or None
    # Basic live/clip switch – when is_live is true we store the
    # item as type "live", otherwise as a normal "clip". This keeps
    # existing clients compatible while enabling WeChat-style live
    # entries in Channels.
    row_type = "live" if bool(body.is_live) else "clip"
    try:
        with _officials_session() as s:
            acc = s.get(OfficialAccountDB, acc_id)
            if not acc or not acc.enabled:
                raise HTTPException(status_code=404, detail="unknown official account")
            slug = _uuid.uuid4().hex
            now = datetime.now(timezone.utc)
            deeplink_json = (
                _json.dumps(body.deeplink) if body.deeplink is not None else None
            )
            row = OfficialFeedItemDB(
                account_id=acc_id,
                slug=slug,
                type=row_type,
                title=title,
                snippet=snippet,
                thumb_url=thumb_url,
                ts=now,
                deeplink_json=deeplink_json,
            )
            s.add(row)
            s.commit()
            s.refresh(row)
            ts_str = (
                row.ts.isoformat().replace("+00:00", "Z")
                if isinstance(row.ts, datetime)
                else None
            )
        try:
            emit_event(
                "channels",
                "upload",
                {
                    "user_phone": phone,
                    "account_id": acc_id,
                    "slug": slug,
                    "has_thumb": bool(thumb_url),
                },
            )
        except Exception:
            pass
        return {
            "id": row.id,
            "slug": row.slug,
            "official_account_id": row.account_id,
            "type": row.type,
            "title": row.title,
            "snippet": row.snippet,
            "thumb_url": row.thumb_url,
            "ts": ts_str,
            "is_live": row.type == "live",
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/channels/live/{item_id}/stop", response_class=JSONResponse)
def channels_live_stop(request: Request, item_id: str) -> dict[str, Any]:
    """
    Lightweight "stop live" endpoint for Channels.

    For now this simply flips the underlying OfficialFeedItemDB.type
    from "live" back to "clip" so that the feed no longer highlights
    it as a live session, roughly matching WeChat Channels behaviour
    where ended streams turn into normal VOD entries.
    """

    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="auth required")
    clean_id = (item_id or "").strip()
    if not clean_id:
        raise HTTPException(status_code=400, detail="item_id required")
    try:
        with _officials_session() as s:
            row = s.get(OfficialFeedItemDB, clean_id)
            if row is None:
                raise HTTPException(status_code=404, detail="unknown feed item")
            try:
                current_type = (row.type or "").strip().lower()
            except Exception:
                current_type = ""
            # If it's not live anymore, we simply return the current state.
            if current_type != "live":
                ts_str: str | None
                ts_val = getattr(row, "ts", None)
                if isinstance(ts_val, datetime):
                    ts_str = ts_val.isoformat().replace("+00:00", "Z")
                else:
                    ts_str = None
                return {
                    "id": row.id,
                    "slug": row.slug,
                    "official_account_id": row.account_id,
                    "type": row.type,
                    "title": row.title,
                    "snippet": row.snippet,
                    "thumb_url": row.thumb_url,
                    "ts": ts_str,
                    "is_live": False,
                    "changed": False,
                }
            row.type = "clip"
            s.add(row)
            s.commit()
            s.refresh(row)
            ts_val = getattr(row, "ts", None)
            if isinstance(ts_val, datetime):
                ts_str = ts_val.isoformat().replace("+00:00", "Z")
            else:
                ts_str = None
        try:
            emit_event(
                "channels",
                "live_stop",
                {
                    "user_phone": phone,
                    "item_id": clean_id,
                    "account_id": row.account_id,
                },
            )
        except Exception:
            pass
        return {
            "id": row.id,
            "slug": row.slug,
            "official_account_id": row.account_id,
            "type": row.type,
            "title": row.title,
            "snippet": row.snippet,
            "thumb_url": row.thumb_url,
            "ts": ts_str,
            "is_live": False,
            "changed": True,
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/search", response_class=JSONResponse)
async def global_search(
    request: Request,
    q: str,
    kind: str | None = None,
    limit: int = 20,
) -> dict[str, Any]:
    """
    Einfache globale Suche über Mini-Apps, Mini-Programs, Official-Accounts,
    Moments und Channels – WeChat-ähnlicher Discover-Einstieg.
    """
    term = (q or "").strip()
    if not term:
        raise HTTPException(status_code=400, detail="q required")
    kind_clean = (kind or "").strip().lower()
    limit_val = max(1, min(limit, 50))
    needle = term.lower()
    phone = _auth_phone(request)
    contact = (phone or "").strip()

    results: list[dict[str, Any]] = []

    def _score_from_extra(extra: dict[str, Any] | None) -> float:
        if not extra:
            return 0.0
        val = extra.get("score")
        if isinstance(val, (int, float)):
            try:
                return float(val)
            except Exception:
                return 0.0
        return 0.0

    def _want(target: str) -> bool:
        if not kind_clean or kind_clean == "all":
            return True
        return kind_clean == target

    # Mini-Apps & Mini-Programs & Official / Channels all aus Official-DB.
    try:
        with _officials_session() as s:
            if _want("mini_app"):
                try:
                    stmt = (
                        _sa_select(MiniAppDB)
                        .where(MiniAppDB.enabled == True)  # type: ignore[comparison-overlap]
                        .limit(limit_val)
                    )
                    if needle:
                        stmt = stmt.where(
                            _sa_func.lower(MiniAppDB.title_en).contains(needle)
                            | _sa_func.lower(MiniAppDB.title_ar).contains(needle)
                            | _sa_func.lower(MiniAppDB.category_en).contains(needle)
                            | _sa_func.lower(MiniAppDB.category_ar).contains(needle)
                            | _sa_func.lower(MiniAppDB.description).contains(needle)
                        )
                    for row in s.execute(stmt).scalars().all():
                        try:
                            rating_val = float(
                                getattr(row, "rating", 0.0) or 0.0
                            )
                        except Exception:
                            rating_val = 0.0
                        try:
                            usage_val = int(
                                getattr(row, "usage_score", 0) or 0
                            )
                        except Exception:
                            usage_val = 0
                        try:
                            moments_val = int(
                                getattr(row, "moments_shares", 0) or 0
                            )
                        except Exception:
                            moments_val = 0
                        badges: list[str] = []
                        if bool(getattr(row, "official", False)):
                            badges.append("official")
                        if bool(getattr(row, "beta", False)):
                            badges.append("beta")
                        # Very simple "trending" heuristic – usage + social signal.
                        if usage_val >= 50 or moments_val >= 5:
                            badges.append("trending")
                        if moments_val >= 10:
                            badges.append("hot_in_moments")
                        # WeChat-like: usage + social + rating as core score,
                        # plus a modest type boost so Mini-Apps surface
                        # vor Moments/Channels in der "All"-Suche.
                        score = (
                            float(usage_val)
                            + float(moments_val * 5)
                            + (rating_val * 10.0)
                            + 40.0
                        )
                        results.append(
                            {
                                "kind": "mini_app",
                                "id": row.app_id,
                                "title": row.title_en,
                                "title_ar": row.title_ar,
                                "snippet": row.description,
                                "extra": {
                                    "category_en": row.category_en,
                                    "category_ar": row.category_ar,
                                    "runtime_app_id": getattr(row, "runtime_app_id", None),
                                    "rating": rating_val,
                                    "usage_score": usage_val,
                                    "moments_shares": moments_val,
                                    "official": bool(
                                        getattr(row, "official", False)
                                    ),
                                    "beta": bool(getattr(row, "beta", False)),
                                    "score": score,
                                    "badges": badges,
                                },
                            }
                        )
                except Exception:
                    pass

            if _want("mini_program"):
                try:
                    stmt = _sa_select(MiniProgramDB).limit(limit_val)
                    if needle:
                        stmt = stmt.where(
                            _sa_func.lower(MiniProgramDB.title_en).contains(needle)
                            | _sa_func.lower(MiniProgramDB.title_ar).contains(needle)
                            | _sa_func.lower(MiniProgramDB.description_en).contains(
                                needle
                            )
                            | _sa_func.lower(MiniProgramDB.description_ar).contains(
                                needle
                            )
                        )
                    rows = s.execute(stmt).scalars().all()
                    # Best-effort Moments shares pro Mini-Program für die Suche,
                    # damit "Hot in Moments" / 30‑Tage‑Aktivität WeChat‑ähnlich
                    # berücksichtigt werden kann.
                    mp_moments_30d: dict[str, int] = {}
                    try:
                        app_ids = [
                            (getattr(r, "app_id", "") or "").strip()
                            for r in rows
                        ]
                        app_ids = [a for a in app_ids if a]
                        if app_ids:
                            with _moments_session() as ms:
                                since_30d = datetime.now(timezone.utc) - timedelta(
                                    days=30
                                )
                                for app_id in app_ids:
                                    try:
                                        pattern = f"shamell://mini_program/{app_id}"
                                        stmt_m = _sa_select(
                                            _sa_func.count(MomentPostDB.id)
                                        ).where(
                                            MomentPostDB.text.contains(pattern),
                                            MomentPostDB.created_at >= since_30d,
                                        )
                                        cnt = ms.execute(stmt_m).scalar() or 0
                                        mp_moments_30d[app_id] = int(cnt or 0)
                                    except Exception:
                                        continue
                    except Exception:
                        mp_moments_30d = {}
                    for row in rows:
                        status = (row.status or "draft").strip().lower()
                        owner_name = (row.owner_name or "").strip()
                        owner_contact = (
                            getattr(row, "owner_contact", "") or ""
                        ).strip()
                        try:
                            usage_val = int(
                                getattr(row, "usage_score", 0) or 0
                            )
                        except Exception:
                            usage_val = 0
                        try:
                            rating_val = float(
                                getattr(row, "rating", 0.0) or 0.0
                            )
                        except Exception:
                            rating_val = 0.0
                        try:
                            moments_30 = int(
                                mp_moments_30d.get(row.app_id or "", 0) or 0
                            )
                        except Exception:
                            moments_30 = 0
                        # Lightweight category heuristic, ähnlich zu
                        # MiniProgramsDirectoryPage im Flutter-Client.
                        category_key: str | None = None
                        try:
                            hay = " ".join(
                                [
                                    (row.title_en or ""),
                                    (row.title_ar or ""),
                                    getattr(row, "description_en", "") or "",
                                    getattr(row, "description_ar", "") or "",
                                    row.app_id or "",
                                ]
                            ).lower()
                            if any(
                                k in hay
                                for k in ["bus", "ride", "transport", "mobility"]
                            ):
                                category_key = "transport"
                            elif any(
                                k in hay
                                for k in ["wallet", "pay ", "payment", "payments"]
                            ):
                                category_key = "wallet"
                        except Exception:
                            category_key = None
                        badges: list[str] = []
                        if status == "active":
                            badges.append("active")
                        elif status:
                            badges.append(status)
                        if owner_name:
                            badges.append("owner")
                        if contact and owner_contact and contact == owner_contact:
                            badges.append("mine")
                        if moments_30 >= 5:
                            badges.append("hot_in_moments")
                        # WeChat-like: aktive und häufig genutzte Mini-Programme
                        # werden deutlich vor anderen Content-Arten priorisiert.
                        # Zusätzlich einfaches "Trending"-Signal und Rating-
                        # Einbindung für die Suche – analog zur Mini-Apps-
                        # Heuristik und dem Mini-Programs-Katalog.
                        if (
                            usage_val >= 50
                            or rating_val >= 4.5
                            or moments_30 >= 5
                        ):
                            badges.append("trending")
                        if status == "active":
                            score = (
                                60.0
                                + float(usage_val)
                                + (rating_val * 5.0)
                                + (float(moments_30) * 3.0)
                            )
                        else:
                            score = (
                                30.0
                                + float(usage_val * 0.5)
                                + (rating_val * 2.5)
                                + (float(moments_30) * 1.5)
                            )
                        results.append(
                            {
                                "kind": "mini_program",
                                "id": row.app_id,
                                "title": row.title_en,
                                "title_ar": row.title_ar,
                                "snippet": getattr(row, "description_en", None),
                                "extra": {
                                    "status": row.status,
                                    "owner_name": row.owner_name,
                                    "usage_score": usage_val,
                                    "rating": rating_val,
                                    "moments_shares_30d": moments_30,
                                    "category": category_key,
                                    "score": score,
                                    "badges": badges,
                                },
                            }
                        )
                except Exception:
                    pass

            if _want("official"):
                try:
                    stmt = (
                        _sa_select(OfficialAccountDB)
                        .where(OfficialAccountDB.enabled == True)  # type: ignore[comparison-overlap]
                    )
                    if needle:
                        stmt = stmt.where(
                            _sa_func.lower(OfficialAccountDB.name).contains(needle)
                            | _sa_func.lower(OfficialAccountDB.name_ar).contains(
                                needle
                            )
                            | _sa_func.lower(OfficialAccountDB.city).contains(needle)
                            | _sa_func.lower(OfficialAccountDB.category).contains(
                                needle
                            )
                            | _sa_func.lower(OfficialAccountDB.description).contains(
                                needle
                            )
                        )
                    rows = s.execute(stmt.limit(limit_val)).scalars().all()
                    if rows:
                        acc_ids = [str(getattr(r, "id", "")) for r in rows if getattr(r, "id", None)]
                        followers: dict[str, int] = {}
                        campaign_counts: dict[str, int] = {}
                        if acc_ids:
                            try:
                                f_rows = (
                                    s.execute(
                                        _sa_select(
                                            OfficialFollowDB.account_id,
                                            _sa_func.count(OfficialFollowDB.id),
                                        ).where(OfficialFollowDB.account_id.in_(acc_ids))
                                        .group_by(OfficialFollowDB.account_id)
                                    )
                                    .all()
                                )
                                for acc_id, cnt in f_rows:
                                    try:
                                        followers[str(acc_id)] = int(cnt or 0)
                                    except Exception:
                                        continue
                            except Exception:
                                followers = {}
                            # Active Red‑Packet campaigns per Official for badges in search.
                            try:
                                camp_rows = (
                                    s.execute(
                                        _sa_select(
                                            RedPacketCampaignDB.account_id,
                                            _sa_func.count(RedPacketCampaignDB.id),
                                        )
                                        .where(
                                            RedPacketCampaignDB.account_id.in_(acc_ids),
                                            RedPacketCampaignDB.active.is_(True),
                                        )
                                        .group_by(RedPacketCampaignDB.account_id)
                                    )
                                    .all()
                                )
                                for acc_id, cnt in camp_rows:
                                    try:
                                        campaign_counts[str(acc_id)] = int(cnt or 0)
                                    except Exception:
                                        continue
                            except Exception:
                                campaign_counts = {}
                        # Moments shares in the last 30 days for these officials.
                        shares_30d: dict[str, int] = {}
                        if acc_ids:
                            try:
                                since_30 = datetime.now(timezone.utc) - timedelta(days=30)
                            except Exception:
                                since_30 = None  # type: ignore[assignment]
                            if since_30 is not None:
                                try:
                                    with _moments_session() as ms:
                                        m_rows = (
                                            ms.execute(
                                                _sa_select(
                                                    MomentPostDB.origin_official_account_id,
                                                    _sa_func.count(MomentPostDB.id),
                                                )
                                                .where(
                                                    MomentPostDB.origin_official_account_id.in_(acc_ids),
                                                    MomentPostDB.created_at >= since_30,
                                                )
                                                .group_by(MomentPostDB.origin_official_account_id)
                                            )
                                            .all()
                                        )
                                        for acc_id, cnt in m_rows:
                                            if not acc_id:
                                                continue
                                            try:
                                                shares_30d[str(acc_id)] = int(cnt or 0)
                                            except Exception:
                                                continue
                                except Exception:
                                    shares_30d = {}
                        for row in rows:
                            acc_id = str(getattr(row, "id", ""))
                            kind_val = (getattr(row, "kind", "") or "").strip().lower()
                            badges: list[str] = []
                            if kind_val == "service":
                                badges.append("service")
                            elif kind_val == "subscription":
                                badges.append("subscription")
                            featured = bool(getattr(row, "featured", False))
                            verified = bool(getattr(row, "verified", False))
                            if featured:
                                badges.append("featured")
                            if verified:
                                badges.append("verified")
                            followers_cnt = followers.get(acc_id, 0)
                            campaigns_active = campaign_counts.get(acc_id, 0)
                            if campaigns_active > 0:
                                badges.append("campaign")
                            shares_cnt = shares_30d.get(acc_id, 0)
                            if shares_cnt >= 3:
                                badges.append("hot_in_moments")
                            # Simple WeChat-like prominence: featured/verified,
                            # follower size (log-ish) and recent Moments shares,
                            # plus ein klarer Typ-Boost gegenüber Moments/Channels.
                            score = 80.0
                            if featured:
                                score += 20.0
                            if verified:
                                score += 5.0
                            if followers_cnt > 0:
                                try:
                                    score += min(followers_cnt, 50000) / 1000.0
                                except Exception:
                                    pass
                            if shares_cnt > 0:
                                score += shares_cnt * 2.0
                            results.append(
                                {
                                    "kind": "official",
                                    "id": row.id,
                                    "title": row.name,
                                    "title_ar": row.name_ar,
                                    "snippet": row.description,
                                    "extra": {
                                        "city": getattr(row, "city", None),
                                        "category": getattr(row, "category", None),
                                        "kind": kind_val or None,
                                        "followers": followers_cnt,
                                        "shares_30d": shares_cnt,
                                        "campaigns_active": campaigns_active,
                                        "score": score,
                                        "badges": badges,
                                    },
                                }
                            )
                except Exception:
                    pass

            if _want("channel"):
                try:
                    c_stmt = (
                        _sa_select(
                            OfficialFeedItemDB,
                            OfficialAccountDB.name,
                        )
                        .join(
                            OfficialAccountDB,
                            OfficialFeedItemDB.account_id == OfficialAccountDB.id,
                        )
                        .order_by(
                            OfficialFeedItemDB.ts.desc(),
                            OfficialFeedItemDB.id.desc(),
                        )
                        .limit(limit_val)
                    )
                    if needle:
                        c_stmt = c_stmt.where(
                            _sa_func.lower(OfficialFeedItemDB.title).contains(needle)
                            | _sa_func.lower(OfficialFeedItemDB.snippet).contains(
                                needle
                            )
                        )
                    rows = s.execute(c_stmt).all()
                    # Preload simple engagement metrics for these items to strengthen
                    # ranking heuristics (likes, views, comments).
                    item_ids: list[str] = []
                    for feed_row, _ in rows:
                        try:
                            item_ids.append(str(getattr(feed_row, "id", "")))
                        except Exception:
                            continue
                    likes_map: dict[str, int] = {}
                    views_map: dict[str, int] = {}
                    comments_map: dict[str, int] = {}
                    if item_ids:
                        try:
                            like_rows = (
                                s.execute(
                                    _sa_select(
                                        ChannelLikeDB.item_id,
                                        _sa_func.count(ChannelLikeDB.id),
                                    )
                                    .where(ChannelLikeDB.item_id.in_(item_ids))
                                    .group_by(ChannelLikeDB.item_id)
                                )
                                .all()
                            )
                            for iid, cnt in like_rows:
                                try:
                                    likes_map[str(iid)] = int(cnt or 0)
                                except Exception:
                                    continue
                        except Exception:
                            likes_map = {}
                        try:
                            view_rows = (
                                s.execute(
                                    _sa_select(
                                        ChannelViewDB.item_id,
                                        ChannelViewDB.views,
                                    ).where(ChannelViewDB.item_id.in_(item_ids))
                                )
                                .all()
                            )
                            for iid, views in view_rows:
                                try:
                                    views_map[str(iid)] = int(views or 0)
                                except Exception:
                                    continue
                        except Exception:
                            views_map = {}
                        try:
                            comment_rows = (
                                s.execute(
                                    _sa_select(
                                        ChannelCommentDB.item_id,
                                        _sa_func.count(ChannelCommentDB.id),
                                    )
                                    .where(ChannelCommentDB.item_id.in_(item_ids))
                                    .group_by(ChannelCommentDB.item_id)
                                )
                                .all()
                            )
                            for iid, cnt in comment_rows:
                                try:
                                    comments_map[str(iid)] = int(cnt or 0)
                                except Exception:
                                    continue
                        except Exception:
                            comments_map = {}
                    hot_accounts: set[str] = set()
                    try:
                        acc_ids: set[str] = set()
                        for feed_row, _ in rows:
                            acc_id_val = getattr(feed_row, "account_id", None)
                            if acc_id_val:
                                acc_ids.add(str(acc_id_val))
                        if acc_ids:
                            with _moments_session() as ms:
                                agg_rows = (
                                    ms.execute(
                                        _sa_select(
                                            MomentPostDB.origin_official_account_id,
                                            _sa_func.count(MomentPostDB.id),
                                        )
                                        .where(
                                            MomentPostDB.origin_official_account_id.in_(
                                                list(acc_ids)
                                            )
                                        )
                                        .group_by(
                                            MomentPostDB.origin_official_account_id
                                        )
                                    )
                                    .all()
                                )
                                for acc_id, cnt in agg_rows:
                                    try:
                                        if int(cnt or 0) >= 10:
                                            hot_accounts.add(str(acc_id))
                                    except Exception:
                                        continue
                    except Exception:
                        hot_accounts = set()
                    for feed_row, acc_name in rows:
                        f_type = (getattr(feed_row, "type", "") or "").strip().lower()
                        badges: list[str] = []
                        if f_type:
                            badges.append(f_type)
                        item_id_str = str(getattr(feed_row, "id", ""))
                        likes = likes_map.get(item_id_str, 0)
                        views = views_map.get(item_id_str, 0)
                        comments = comments_map.get(item_id_str, 0)
                        if likes >= 10 or views >= 100:
                            badges.append("popular_clip")
                        if comments >= 3:
                            badges.append("discussed")
                        acc_id_val = getattr(feed_row, "account_id", None)
                        acc_id_str = str(acc_id_val) if acc_id_val is not None else ""
                        if acc_id_str in hot_accounts:
                            badges.append("hot_in_moments")
                        # WeChat-like: Campaign/Promo-Clips und Clips von
                        # besonders aktiven Official-Accounts leicht bevorzugen.
                        # Zusätzlich werden Clips mit hoher Interaktion (Likes/Views/
                        # Comments) stärker gewichtet, bleiben aber unter
                        # Official/Mini-Program-Ergebnissen. Live-Items werden
                        # zusätzlich hervorgehoben.
                        score = 20.0
                        if f_type == "live":
                            score += 15.0
                            if "live" not in badges:
                                badges.append("live")
                        elif f_type in {"campaign", "promo"}:
                            score += 10.0
                        if acc_id_str in hot_accounts:
                            score += 5.0
                        try:
                            if views > 0:
                                score += min(views, 5000) / 200.0
                        except Exception:
                            pass
                        try:
                            if likes > 0:
                                score += min(likes, 500) * 0.5
                        except Exception:
                            pass
                        try:
                            if comments > 0:
                                score += min(comments, 100) * 1.0
                        except Exception:
                            pass
                        results.append(
                            {
                                "kind": "channel",
                                "id": getattr(feed_row, "slug", None)
                                or str(getattr(feed_row, "id", "")),
                                "title": getattr(feed_row, "title", None),
                                "title_ar": None,
                                "snippet": getattr(feed_row, "snippet", None),
                                "extra": {
                                    "official_account_id": acc_id_val,
                                    "official_name": acc_name,
                                    "likes": likes,
                                    "views": views,
                                    "comments": comments,
                                    "score": score,
                                    "badges": badges,
                                    "type": f_type or None,
                                },
                            }
                        )
                except Exception:
                    pass
    except HTTPException:
        raise
    except Exception:
        # ignore and fall back to other sources
        pass

    # Moments search via Moments DB.
    if _want("moment"):
        try:
            with _moments_session() as ms:
                m_stmt = (
                    _sa_select(MomentPostDB)
                    .where(_sa_func.lower(MomentPostDB.text).contains(needle))
                    .order_by(
                        MomentPostDB.created_at.desc(),
                        MomentPostDB.id.desc(),
                    )
                    .limit(limit_val)
                )
                for row in ms.execute(m_stmt).scalars().all():
                    text = getattr(row, "text", "") or ""
                    is_redpacket = False
                    try:
                        t_low = text.lower()
                        if "red packet" in t_low or "red packets" in t_low:
                            is_redpacket = True
                        if "i am sending red packets via shamell pay" in t_low:
                            is_redpacket = True
                        if "حزمة حمراء" in text or "حزمًا حمراء" in text:
                            is_redpacket = True
                    except Exception:
                        is_redpacket = False
                    badges: list[str] = []
                    if is_redpacket:
                        badges.append("redpacket")
                    results.append(
                        {
                            "kind": "moment",
                            "id": getattr(row, "id", None),
                            "title": None,
                            "title_ar": None,
                            "snippet": text,
                            "extra": {
                                "created_at": getattr(row, "created_at", None),
                                "author_id": getattr(row, "user_id", None),
                                "score": 0.0,
                                "badges": badges,
                            },
                        }
                    )
        except Exception:
            pass

    # Sort by score for WeChat-like "trending" behaviour where available.
    if not kind_clean or kind_clean == "all":
        results.sort(
            key=lambda r: _score_from_extra(
                r.get("extra") if isinstance(r.get("extra"), dict) else None
            ),
            reverse=True,
        )
    elif kind_clean in {"mini_app", "mini_program", "official"}:
        results.sort(
            key=lambda r: _score_from_extra(
                r.get("extra") if isinstance(r.get("extra"), dict) else None
            ),
            reverse=True,
        )

    if len(results) > limit_val:
        results = results[:limit_val]
    return {"results": results}


@app.get("/official_accounts/{account_id}/campaigns", response_class=JSONResponse)
def official_account_campaigns(account_id: str) -> dict[str, Any]:
    """
    Public, read-only list of active red-packet campaigns for a single Official.

    Used by the client to prefill campaign-specific red-packet issuing UIs.
    """
    try:
        with _officials_session() as s:
            rows = (
                s.execute(
                    _sa_select(RedPacketCampaignDB).where(
                        RedPacketCampaignDB.account_id == account_id,
                        RedPacketCampaignDB.active.is_(True),
                    )
                )
                .scalars()
                .all()
            )
            items: list[dict[str, Any]] = []
            for row in rows:
                created = getattr(row, "created_at", None)
                created_str = None
                try:
                    created_str = (
                        created.isoformat().replace("+00:00", "Z")
                        if created
                        else None
                    )
                except Exception:
                    created_str = str(created) if created is not None else None
                items.append(
                    {
                        "id": row.id,
                        "account_id": row.account_id,
                        "title": row.title,
                        "default_amount_cents": getattr(
                            row, "default_amount_cents", None
                        ),
                        "default_count": getattr(row, "default_count", None),
                        "active": bool(getattr(row, "active", True)),
                        "created_at": created_str,
                        "note": getattr(row, "note", None),
                    }
                )
        return {"campaigns": items}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get(
    "/official_accounts/{account_id}/campaigns/{campaign_id}/stats",
    response_class=JSONResponse,
)
def official_account_campaign_stats(
    account_id: str,
    campaign_id: str,
) -> dict[str, Any]:
    """
    Lightweight JSON KPIs for a single Red‑Packet campaign – WeChat‑style.

    Exposes aggregated Moments shares (all time / 30d, unique sharers) and
    Red‑Packet payments KPIs (issued/claimed packets and amounts) so that
    merchant UIs can render a compact in‑app dashboard.
    """
    cid = (campaign_id or "").strip()
    if not cid:
        raise HTTPException(status_code=400, detail="campaign_id required")
    try:
        # Resolve campaign and ensure it belongs to the given Official.
        with _officials_session() as s:
            camp = s.get(RedPacketCampaignDB, cid)
            if not camp or camp.account_id != account_id:
                raise HTTPException(status_code=404, detail="campaign not found")

        # Moments metrics for this campaign (origin_official_item_id == campaign_id)
        moments_total = 0
        moments_30d = 0
        uniq_total = 0
        uniq_30d = 0
        last_share_ts: str | None = None
        try:
            since_30d = datetime.now(timezone.utc) - timedelta(days=30)
            with _moments_session() as ms:
                moments_total = int(
                    (
                        ms.execute(
                            _sa_select(_sa_func.count(MomentPostDB.id)).where(
                                MomentPostDB.origin_official_item_id == cid
                            )
                        ).scalar()
                        or 0
                    )
                )
                moments_30d = int(
                    (
                        ms.execute(
                            _sa_select(_sa_func.count(MomentPostDB.id)).where(
                                MomentPostDB.origin_official_item_id == cid,
                                MomentPostDB.created_at >= since_30d,
                            )
                        ).scalar()
                        or 0
                    )
                )
                uniq_total = int(
                    (
                        ms.execute(
                            _sa_select(
                                _sa_func.count(
                                    _sa_func.distinct(MomentPostDB.user_key)
                                )
                            ).where(MomentPostDB.origin_official_item_id == cid)
                        ).scalar()
                        or 0
                    )
                )
                uniq_30d = int(
                    (
                        ms.execute(
                            _sa_select(
                                _sa_func.count(
                                    _sa_func.distinct(MomentPostDB.user_key)
                                )
                            ).where(
                                MomentPostDB.origin_official_item_id == cid,
                                MomentPostDB.created_at >= since_30d,
                            )
                        ).scalar()
                        or 0
                    )
                )
                last_row = (
                    ms.execute(
                        _sa_select(_sa_func.max(MomentPostDB.created_at)).where(
                            MomentPostDB.origin_official_item_id == cid
                        )
                    ).scalar()
                    or None
                )
                if last_row is not None:
                    try:
                        last_share_ts = (
                            last_row.isoformat().replace("+00:00", "Z")
                            if isinstance(last_row, datetime)
                            else str(last_row)
                        )
                    except Exception:
                        last_share_ts = str(last_row)
        except Exception:
            moments_total = 0
            moments_30d = 0
            uniq_total = 0
            uniq_30d = 0
            last_share_ts = None

        # Optional Payments KPIs via internal Payments service or PAYMENTS_BASE.
        payments_total_packets_issued = 0
        payments_total_packets_claimed = 0
        payments_total_amount_cents = 0
        payments_claimed_amount_cents = 0
        payments_unique_creators = 0
        payments_unique_claimants = 0
        try:
            data: dict[str, Any] | None = None
            data_30d: dict[str, Any] | None = None
            since_30d_pay = datetime.now(timezone.utc) - timedelta(days=30)
            # Prefer internal Payments integration when available; fall back to HTTP.
            if _use_pay_internal() and _pay_main is not None:
                from apps.payments.app.main import (  # type: ignore[import]
                    redpacket_campaign_payments_analytics,
                )

                with _pay_internal_session() as ps:  # type: ignore[name-defined]
                    stats = redpacket_campaign_payments_analytics(
                        campaign_id=cid,
                        from_iso=None,
                        to_iso=None,
                        s=ps,
                        admin_ok=True,  # bypass external admin checks for internal call
                    )
                    data = stats.dict() if hasattr(stats, "dict") else stats  # type: ignore[assignment]
                    stats_30 = redpacket_campaign_payments_analytics(
                        campaign_id=cid,
                        from_iso=since_30d_pay.isoformat(),
                        to_iso=None,
                        s=ps,
                        admin_ok=True,
                    )
                    data_30d = stats_30.dict() if hasattr(stats_30, "dict") else stats_30  # type: ignore[assignment]
            elif PAYMENTS_BASE:
                base = PAYMENTS_BASE.rstrip("/")
                url = f"{base}/admin/redpacket_campaigns/payments_analytics"
                r = httpx.get(
                    url,
                    headers=_payments_headers(),
                    params={"campaign_id": cid},
                    timeout=5.0,
                )
                if (
                    r.status_code == 200
                    and r.headers.get("content-type", "").startswith(
                        "application/json"
                    )
                ):
                    body = r.json()
                    if isinstance(body, dict):
                        data = body
                try:
                    r30 = httpx.get(
                        url,
                        headers=_payments_headers(),
                        params={"campaign_id": cid, "from_iso": since_30d_pay.isoformat()},
                        timeout=5.0,
                    )
                    if (
                        r30.status_code == 200
                        and r30.headers.get("content-type", "").startswith(
                            "application/json"
                        )
                    ):
                        body_30 = r30.json()
                        if isinstance(body_30, dict):
                            data_30d = body_30
                except Exception:
                    data_30d = data_30d
            if isinstance(data, dict):
                try:
                    payments_total_packets_issued = int(
                        data.get("total_packets_issued", 0) or 0
                    )
                except Exception:
                    payments_total_packets_issued = 0
                try:
                    payments_total_packets_claimed = int(
                        data.get("total_packets_claimed", 0) or 0
                    )
                except Exception:
                    payments_total_packets_claimed = 0
                try:
                    payments_total_amount_cents = int(
                        data.get("total_amount_cents", 0) or 0
                    )
                except Exception:
                    payments_total_amount_cents = 0
                try:
                    payments_claimed_amount_cents = int(
                        data.get("claimed_amount_cents", 0) or 0
                    )
                except Exception:
                    payments_claimed_amount_cents = 0
                try:
                    payments_unique_creators = int(
                        data.get("unique_creators", 0) or 0
                    )
                except Exception:
                    payments_unique_creators = 0
                try:
                    payments_unique_claimants = int(
                        data.get("unique_claimants", 0) or 0
                    )
                except Exception:
                    payments_unique_claimants = 0

            payments_total_packets_issued_30d = 0
            payments_total_packets_claimed_30d = 0
            payments_total_amount_cents_30d = 0
            payments_claimed_amount_cents_30d = 0
            payments_unique_creators_30d = 0
            payments_unique_claimants_30d = 0
            if isinstance(data_30d, dict):
                try:
                    payments_total_packets_issued_30d = int(
                        data_30d.get("total_packets_issued", 0) or 0
                    )
                except Exception:
                    payments_total_packets_issued_30d = 0
                try:
                    payments_total_packets_claimed_30d = int(
                        data_30d.get("total_packets_claimed", 0) or 0
                    )
                except Exception:
                    payments_total_packets_claimed_30d = 0
                try:
                    payments_total_amount_cents_30d = int(
                        data_30d.get("total_amount_cents", 0) or 0
                    )
                except Exception:
                    payments_total_amount_cents_30d = 0
                try:
                    payments_claimed_amount_cents_30d = int(
                        data_30d.get("claimed_amount_cents", 0) or 0
                    )
                except Exception:
                    payments_claimed_amount_cents_30d = 0
                try:
                    payments_unique_creators_30d = int(
                        data_30d.get("unique_creators", 0) or 0
                    )
                except Exception:
                    payments_unique_creators_30d = 0
                try:
                    payments_unique_claimants_30d = int(
                        data_30d.get("unique_claimants", 0) or 0
                    )
                except Exception:
                    payments_unique_claimants_30d = 0
        except Exception:
            payments_total_packets_issued = 0
            payments_total_packets_claimed = 0
            payments_total_amount_cents = 0
            payments_claimed_amount_cents = 0
            payments_unique_creators = 0
            payments_unique_claimants = 0
            payments_total_packets_issued_30d = 0
            payments_total_packets_claimed_30d = 0
            payments_total_amount_cents_30d = 0
            payments_claimed_amount_cents_30d = 0
            payments_unique_creators_30d = 0
            payments_unique_claimants_30d = 0

        return {
            "campaign_id": cid,
            "account_id": account_id,
            "moments_shares_total": moments_total,
            "moments_shares_30d": moments_30d,
            "moments_unique_sharers_total": uniq_total,
            "moments_unique_sharers_30d": uniq_30d,
            "moments_last_share_ts": last_share_ts,
            "payments_total_packets_issued": payments_total_packets_issued,
            "payments_total_packets_claimed": payments_total_packets_claimed,
            "payments_total_amount_cents": payments_total_amount_cents,
            "payments_claimed_amount_cents": payments_claimed_amount_cents,
            "payments_unique_creators": payments_unique_creators,
            "payments_unique_claimants": payments_unique_claimants,
            "payments_total_packets_issued_30d": payments_total_packets_issued_30d,
            "payments_total_packets_claimed_30d": payments_total_packets_claimed_30d,
            "payments_total_amount_cents_30d": payments_total_amount_cents_30d,
            "payments_claimed_amount_cents_30d": payments_claimed_amount_cents_30d,
            "payments_unique_creators_30d": payments_unique_creators_30d,
            "payments_unique_claimants_30d": payments_unique_claimants_30d,
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/official_accounts/notifications", response_class=JSONResponse)
def official_notifications(request: Request):
    """
    Returns per-account notification modes for the current user.
    """
    user_key = _official_cookie_key(request)
    try:
        with _officials_session() as s:
            rows = (
                s.execute(
                    _sa_select(OfficialNotificationDB).where(
                        OfficialNotificationDB.user_key == user_key
                    )
                )
                .scalars()
                .all()
            )
            modes = {row.account_id: row.mode for row in rows if row.mode}
        return {"modes": modes}
    except HTTPException:
        raise
    except Exception:
        # Soft-fail: empty map if notifications table is unavailable.
        return {"modes": {}}


@app.post(
    "/official_accounts/{account_id}/notification_mode",
    response_class=JSONResponse,
)
def official_set_notification_mode(
    account_id: str,
    request: Request,
    body: OfficialNotificationIn,
):
    """
    Sets or clears per-user notification mode for a single official account.
    Modes: full, summary, muted. Omitting or "full" clears the override.
    """
    user_key = _official_cookie_key(request)
    raw_mode = body.mode
    if raw_mode is None:
        norm_mode: str | None = None
    else:
        m = raw_mode.strip().lower()
        if m not in {"full", "summary", "muted"}:
            raise HTTPException(status_code=400, detail="invalid mode")
        norm_mode = m
    try:
        with _officials_session() as s:
            acc = s.get(OfficialAccountDB, account_id)
            if not acc or not acc.enabled:
                raise HTTPException(status_code=404, detail="unknown official account")
            stmt = _sa_select(OfficialNotificationDB).where(
                OfficialNotificationDB.user_key == user_key,
                OfficialNotificationDB.account_id == account_id,
            )
            existing = s.execute(stmt).scalars().first()
            if norm_mode is None or norm_mode == "full":
                if existing is not None:
                    s.delete(existing)
                    s.commit()
                result_mode = "full"
            else:
                if existing is None:
                    existing = OfficialNotificationDB(
                        user_key=user_key,
                        account_id=account_id,
                        mode=norm_mode,
                    )
                    s.add(existing)
                else:
                    existing.mode = norm_mode
                s.commit()
                result_mode = norm_mode
        try:
            emit_event(
                "officials",
                "notif_mode_set",
                {
                    "user_key": user_key,
                    "account_id": account_id,
                    "mode": result_mode,
                },
            )
        except Exception:
            pass
        return {"account_id": account_id, "mode": result_mode}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get(
    "/official_accounts/{account_id}/auto_replies",
    response_class=JSONResponse,
)
def official_auto_replies(account_id: str, request: Request) -> dict[str, Any]:
    """
    Returns enabled auto‑reply rules for a single Official account.

    The main consumer is the Shamell chat client, which can use the
    first "welcome" rule to display a WeChat‑style greeting bubble
    when a user first opens a conversation with an Official account.
    """

    try:
        _ = _official_cookie_key(request)
    except Exception:
        # Treat missing cookie the same as anonymous; auto‑replies are
        # public metadata and do not leak sensitive state.
        pass
    try:
        with _officials_session() as s:
            acc = s.get(OfficialAccountDB, account_id)
            if not acc or not acc.enabled:
                raise HTTPException(status_code=404, detail="unknown official account")
            stmt = _sa_select(OfficialAutoReplyDB).where(
                OfficialAutoReplyDB.account_id == account_id,
                OfficialAutoReplyDB.enabled.is_(True),
            ).order_by(OfficialAutoReplyDB.id.asc())
            rows = s.execute(stmt).scalars().all()
            rules: list[dict[str, Any]] = []
            for row in rows:
                rules.append(
                    {
                        "id": row.id,
                        "account_id": row.account_id,
                        "kind": row.kind,
                        "keyword": row.keyword,
                        "text": row.text,
                        "enabled": bool(row.enabled),
                    }
                )
        return {"rules": rules}
    except HTTPException:
        raise
    except Exception:
        # Soft‑fail for deployments that have not yet migrated the
        # auto‑replies table.
        return {"rules": []}


@app.get("/official_accounts/{account_id}/locations", response_class=JSONResponse)
async def official_account_locations(request: Request, account_id: str, limit: int = 50):
    try:
        limit_val = max(1, min(limit, 200))
        _ = _official_cookie_key(request)
        with _officials_session() as s:
            acc = s.get(OfficialAccountDB, account_id)
            if not acc or not acc.enabled:
                raise HTTPException(status_code=404, detail="unknown official account")
            stmt = (
                _sa_select(OfficialLocationDB)
                .where(OfficialLocationDB.account_id == account_id)
                .order_by(OfficialLocationDB.id.asc())
                .limit(limit_val)
            )
            rows = s.execute(stmt).scalars().all()
            items: list[dict[str, Any]] = []
            for row in rows:
                items.append(
                    OfficialLocationOut(
                        id=row.id,
                        name=row.name,
                        city=row.city,
                        address=row.address,
                        lat=row.lat,
                        lon=row.lon,
                        phone=row.phone,
                        opening_hours=row.opening_hours,
                    ).dict()
                )
        return {"locations": items}
    except HTTPException:
        raise
    except Exception:
        # No fallback locations configured; behave like empty list or 404.
        raise HTTPException(status_code=404, detail="locations not available")


@app.post("/official_accounts/{account_id}/follow", response_class=JSONResponse)
async def follow_official_account(account_id: str, request: Request):
    ck = _official_cookie_key(request)
    try:
        with _officials_session() as s:
            acc = s.get(OfficialAccountDB, account_id)
            if not acc or not acc.enabled:
                raise HTTPException(status_code=404, detail="unknown official account")
            existing = s.execute(
                _sa_select(OfficialFollowDB).where(
                    OfficialFollowDB.user_key == ck,
                    OfficialFollowDB.account_id == account_id,
                )
            ).scalars().first()
            if not existing:
                s.add(OfficialFollowDB(user_key=ck, account_id=account_id))
                s.commit()
        try:
            emit_event(
                "officials",
                f"follow_{account_id}",
                {"user_key": ck},
            )
        except Exception:
            pass
        return {"status": "ok", "followed": True}
    except HTTPException:
        raise
    except Exception:
        if account_id not in _OFFICIAL_ACCOUNTS:
            raise HTTPException(status_code=404, detail="unknown official account")
        s = _OFFICIAL_FOLLOWS.setdefault(ck, set(_OFFICIAL_ACCOUNTS.keys()))
        s.add(account_id)
        return {"status": "ok", "followed": True}


@app.post("/official_accounts/{account_id}/unfollow", response_class=JSONResponse)
async def unfollow_official_account(account_id: str, request: Request):
    ck = _official_cookie_key(request)
    try:
        with _officials_session() as s:
            acc = s.get(OfficialAccountDB, account_id)
            if not acc or not acc.enabled:
                raise HTTPException(status_code=404, detail="unknown official account")
            row = s.execute(
                _sa_select(OfficialFollowDB).where(
                    OfficialFollowDB.user_key == ck,
                    OfficialFollowDB.account_id == account_id,
                )
            ).scalars().first()
            if row:
                s.delete(row)
                s.commit()
        try:
            emit_event(
                "officials",
                f"unfollow_{account_id}",
                {"user_key": ck},
            )
        except Exception:
            pass
        return {"status": "ok", "followed": False}
    except HTTPException:
        raise
    except Exception:
        if account_id not in _OFFICIAL_ACCOUNTS:
            raise HTTPException(status_code=404, detail="unknown official account")
        s = _OFFICIAL_FOLLOWS.setdefault(ck, set(_OFFICIAL_ACCOUNTS.keys()))
        if account_id in s:
            s.remove(account_id)
        return {"status": "ok", "followed": False}


@app.post("/channels/accounts/{account_id}/follow", response_class=JSONResponse)
async def channels_follow_account(account_id: str, request: Request):
    """
    Follow a Channel for the given Official account.

    This is intentionally separate from OfficialFollowDB so users can
    follow a service as a channel without affecting their Official
    subscriptions, similar to WeChat's Channels follower graph.
    """
    user_key = _channels_user_key(request)
    try:
      with _officials_session() as s:
          acc = s.get(OfficialAccountDB, account_id)
          if not acc or not acc.enabled:
              raise HTTPException(
                  status_code=404, detail="unknown official account"
              )
          existing = s.execute(
              _sa_select(ChannelFollowDB).where(
                  ChannelFollowDB.user_key == user_key,
                  ChannelFollowDB.account_id == account_id,
              )
          ).scalars().first()
          if not existing:
              s.add(
                  ChannelFollowDB(
                      user_key=user_key,
                      account_id=account_id,
                  )
              )
              s.commit()
      try:
          emit_event(
              "channels",
              "follow",
              {"user_key": user_key, "account_id": account_id},
          )
      except Exception:
          pass
      return {"status": "ok", "followed": True}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/channels/accounts/{account_id}/unfollow", response_class=JSONResponse)
async def channels_unfollow_account(account_id: str, request: Request):
    """
    Unfollow a Channel for the given Official account.
    """
    user_key = _channels_user_key(request)
    try:
      with _officials_session() as s:
          acc = s.get(OfficialAccountDB, account_id)
          if not acc or not acc.enabled:
              raise HTTPException(
                  status_code=404, detail="unknown official account"
              )
          row = s.execute(
              _sa_select(ChannelFollowDB).where(
                  ChannelFollowDB.user_key == user_key,
                  ChannelFollowDB.account_id == account_id,
              )
          ).scalars().first()
          if row:
              s.delete(row)
              s.commit()
      try:
          emit_event(
              "channels",
              "unfollow",
              {"user_key": user_key, "account_id": account_id},
          )
      except Exception:
          pass
      return {"status": "ok", "followed": False}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
