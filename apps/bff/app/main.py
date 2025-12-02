from __future__ import annotations

from fastapi import FastAPI, HTTPException, Request
from fastapi import WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse, Response, JSONResponse, StreamingResponse, FileResponse
from starlette.responses import RedirectResponse
from shamell_shared import RequestIDMiddleware, configure_cors, add_standard_health, setup_json_logging
from pydantic import BaseModel
import httpx
import logging
import os
import asyncio, json as _json
import math
from pathlib import Path
import secrets as _secrets
import time, uuid as _uuid
from typing import Any
from io import BytesIO
from urllib.parse import urlparse, parse_qs
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


app = FastAPI(title="Shamell BFF", version="0.1.0")
setup_json_logging()
app.add_middleware(RequestIDMiddleware)
configure_cors(app, os.getenv("ALLOWED_ORIGINS", "*"))
add_standard_health(app)
_HTTPX_CLIENT: httpx.Client | None = None
_HTTPX_ASYNC_CLIENT: httpx.AsyncClient | None = None
# Include PMS router directly for monolith/internal mode so Cloudbeds UI works via BFF.
try:
    from apps.pms.app.main import router as pms_router  # type: ignore
    app.include_router(pms_router, prefix="/pms")  # type: ignore[arg-type]
except Exception:
    pms_router = None  # type: ignore


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
_AUDIT_EVENTS: list[dict[str, Any]] = []
_MAX_AUDIT_EVENTS = 2000


class _AuditInMemoryHandler(logging.Handler):
    """
    Kapselt alle Audit-Logs (logger \"shamell.audit\") in einem kleinen
    In-Memory-Puffer, damit /admin/stats und /admin/guardrails auch
    Domain-Events (z.B. freight/courier) sehen.
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

# Optional in-memory mapping between building orders and courier shipments.
# This keeps coupling lightweight and avoids schema changes in Commerce while
# still allowing the BFF to enforce 2-step confirmation (order + shipment).
_BUILDING_ORDER_SHIPMENTS: dict[int, str] = {}

# Simple background stats (monolith heartbeat etc.)
_BG_STATS: dict[str, Any] = {"last_tick_ms": None}

# Small in-memory caches for frequently used lists
_BUS_CITIES_CACHE: dict[str, Any] = {"ts": 0.0, "data": None}
_COMMERCE_PRODUCTS_CACHE: dict[str, Any] = {"ts": 0.0, "data": None}
_AGRICULTURE_LISTINGS_CACHE: dict[str, Any] = {"ts": 0.0, "data": None}
_LIVESTOCK_LISTINGS_CACHE: dict[str, Any] = {"ts": 0.0, "data": None}
_TAXI_ADMIN_SUMMARY_CACHE: dict[str, Any] = {"ts": 0.0, "data": None}
_OSM_GEOCODE_CACHE: dict[str, tuple[float, Any]] = {}
_OSM_REVERSE_CACHE: dict[tuple[float, float], tuple[float, Any]] = {}
_OSM_TAXI_CACHE: dict[tuple[float, float, float, float], tuple[float, Any]] = {}


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

    response = await call_next(request)
    if SECURITY_HEADERS_ENABLED:
        try:
            headers = response.headers
            headers.setdefault("X-Content-Type-Options", "nosniff")
            headers.setdefault("X-Frame-Options", "DENY")
            headers.setdefault("Referrer-Policy", "strict-origin-when-cross-origin")
            headers.setdefault(
                "Content-Security-Policy",
                "default-src 'self'; img-src 'self' data:; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; connect-src 'self' https:; frame-ancestors 'none'",
            )
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
    try:
        body = await req.json()
    except Exception:
        body = {}
    try:
        dev = req.headers.get("X-Device-ID") or ""
    except Exception:
        dev = ""
    item = {"ts": int(time.time()*1000), "device": dev, **body}
    _METRICS.append(item)
    if len(_METRICS) > 2000:
        del _METRICS[:len(_METRICS)-2000]
    return {"ok": True}

@app.get("/metrics", response_class=JSONResponse)
def metrics_dump(limit: int = 200):
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

    # Build rows for aggregates
    sample_rows: list[str] = []
    for metric, st in sorted(sample_stats.items()):
        cnt = int(st.get("count", 0.0) or 0)
        if cnt <= 0:
            continue
        total = st.get("sum", 0.0) or 0.0
        avg = total / cnt if cnt else 0.0
        vmin = st.get("min", 0.0) or 0.0
        vmax = st.get("max", 0.0) or 0.0
        sample_rows.append(
            f"<tr><td>{metric}</td><td>{cnt}</td><td>{avg:.1f}</td><td>{vmin:.0f}</td><td>{vmax:.0f}</td></tr>"
        )
    if not sample_rows:
        sample_rows.append(
            "<tr><td colspan='5'>No sample metrics yet.</td></tr>"
        )
    sample_html = "\n".join(sample_rows)

    action_rows: list[str] = []
    for label, cnt in sorted(action_counts.items(), key=lambda x: (-x[1], x[0])):
        action_rows.append(f"<tr><td>{label}</td><td>{cnt}</td></tr>")
    if not action_rows:
        action_rows.append("<tr><td colspan='2'>No action metrics yet.</td></tr>")
    action_html = "\n".join(action_rows)

    # Raw event rows
    rows: list[str] = []
    for it in items:
        try:
            ts = it.get("ts", "")
            mtype = it.get("type", "")
            dev_id = it.get("device", "")
            data = it.get("data", {}) or {}
            label = ""
            ms = ""
            if isinstance(data, dict):
                label = str(data.get("label", ""))
                ms_val = data.get("ms")
                if ms_val is not None:
                    ms = str(ms_val)
        except Exception:
            ts = it.get("ts", "")
            mtype = it.get("type", "")
            dev_id = it.get("device", "")
            label = ""
            ms = ""
        rows.append(
            f"<tr><td>{ts}</td><td>{mtype}</td><td>{label}</td><td>{ms}</td><td>{dev_id}</td></tr>"
        )
    rows_html = "\n".join(rows)
    html = f"""
<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <title>Metrics</title>
    <style>
      body {{ font-family: system-ui, -apple-system, BlinkMacSystemFont, sans-serif; background:#ffffff; color:#000000; }}
      table {{ border-collapse: collapse; width: 100%; }}
      th, td {{ border: 1px solid #dddddd; padding: 4px 6px; font-size: 12px; }}
      th {{ background: #f5f5f5; text-align: left; }}
      caption {{ text-align:left; font-weight:bold; margin-bottom:8px; }}
    </style>
  </head>
  <body>
    <h1>Metrics</h1>
    <p>Last {len(items)} entries from /metrics.</p>
    <h2>Aggregates (samples, last {len(items)} events)</h2>
    <table>
      <caption>Samples (value_ms)</caption>
      <thead>
        <tr><th>metric</th><th>count</th><th>avg_ms</th><th>min_ms</th><th>max_ms</th></tr>
      </thead>
      <tbody>
        {sample_html}
      </tbody>
    </table>
    <h2>Action counts</h2>
    <table>
      <caption>Actions</caption>
      <thead>
        <tr><th>label</th><th>count</th></tr>
      </thead>
      <tbody>
        {action_html}
      </tbody>
    </table>
    <h2>Raw events</h2>
    <table>
      <caption>Events</caption>
      <thead>
        <tr><th>ts</th><th>type</th><th>label</th><th>ms</th><th>device</th></tr>
      </thead>
      <tbody>
        {rows_html}
      </tbody>
    </table>
  </body>
</html>
"""
    return HTMLResponse(content=html)


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
    building_counts: dict[str, int] = {}
    freight_guardrail_counts: dict[str, int] = {}
    try:
        # consider only recent audit events
        tail = _AUDIT_EVENTS[-limit:]
        for e in tail:
            action = str(e.get("action", "") or "")
            if not action:
                continue
            if "guardrail" in action:
                guardrail_counts[action] = guardrail_counts.get(action, 0) + 1
                if action.startswith("freight_"):
                    freight_guardrail_counts[action] = freight_guardrail_counts.get(action, 0) + 1
            if action.startswith("building_order_"):
                key = action
                building_counts[key] = building_counts.get(key, 0) + 1
    except Exception:
        guardrail_counts = {}
        building_counts = {}
        freight_guardrail_counts = {}

    return {
        "samples": samples_out,
        "actions": action_counts,
        "total_events": len(items),
        "guardrails": guardrail_counts,
        "freight_guardrails": freight_guardrail_counts,
        "building_orders": building_counts,
    }


@app.get("/admin/finance_stats", response_class=JSONResponse)
def admin_finance_stats(request: Request, from_iso: str | None = None, to_iso: str | None = None):
    """
    Finance statistics over the Payments domain service:
    - total_txns: number of transactions in the period
    - total_fee_cents: total fees charged in the period
    """
    _require_admin_v2(request)

    # For monolithic deployments we rely on internal calls.
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
    for e in guardrails:
        try:
            rows.append(
                f"<tr><td>{e.get('ts_ms','')}</td>"
                f"<td>{e.get('action','')}</td>"
                f"<td>{e.get('phone','') or ''}</td>"
                f"<td><code>{_json.dumps({k:v for k,v in e.items() if k not in ('ts_ms','action','phone')})}</code></td></tr>"
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
    code{{font-size:12px;background:#f3f4f6;padding:2px 4px;border-radius:4px;}}
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
    monolith = bool(_env_or("MONOLITH_MODE", "0") not in ("0", "false", "False"))
    domains: dict[str, dict[str, Any]] = {}
    try:
        domains["payments"] = {
            "internal": _use_pay_internal(),
            "base_url": PAYMENTS_BASE,
        }
    except Exception:
        domains["payments"] = {"internal": False, "base_url": PAYMENTS_BASE}
    try:
        domains["taxi"] = {
            "internal": _use_taxi_internal(),  # type: ignore[name-defined]
            "base_url": TAXI_BASE,
        }
    except Exception:
        domains["taxi"] = {"internal": False, "base_url": TAXI_BASE}
    try:
        domains["bus"] = {
            "internal": _use_bus_internal(),
            "base_url": BUS_BASE,
        }
    except Exception:
        domains["bus"] = {"internal": False, "base_url": BUS_BASE}
    try:
        domains["food"] = {
            "internal": _use_food_internal(),  # type: ignore[name-defined]
            "base_url": None,
        }
    except Exception:
        domains["food"] = {"internal": False, "base_url": None}
    try:
        domains["stays"] = {
            "internal": _use_stays_internal(),  # type: ignore[name-defined]
            "base_url": STAYS_BASE,
        }
    except Exception:
        domains["stays"] = {"internal": False, "base_url": STAYS_BASE}
    try:
        domains["commerce"] = {
            "internal": _use_commerce_internal(),
            "base_url": COMMERCE_BASE,
        }
    except Exception:
        domains["commerce"] = {"internal": False, "base_url": COMMERCE_BASE}
    try:
        domains["doctors"] = {
            "internal": _use_doctors_internal(),
            "base_url": DOCTORS_BASE,
        }
    except Exception:
        domains["doctors"] = {"internal": False, "base_url": DOCTORS_BASE}
    try:
        domains["flights"] = {
            "internal": _use_flights_internal(),
            "base_url": FLIGHTS_BASE,
        }
    except Exception:
        domains["flights"] = {"internal": False, "base_url": FLIGHTS_BASE}
    try:
        domains["agriculture"] = {
            "internal": _use_agriculture_internal(),
            "base_url": AGRICULTURE_BASE,
        }
    except Exception:
        domains["agriculture"] = {"internal": False, "base_url": AGRICULTURE_BASE}
    try:
        domains["livestock"] = {
            "internal": _use_livestock_internal(),
            "base_url": LIVESTOCK_BASE,
        }
    except Exception:
        domains["livestock"] = {"internal": False, "base_url": LIVESTOCK_BASE}
    try:
        domains["equipment"] = {
            "internal": _use_equipment_internal(),
            "base_url": EQUIPMENT_BASE,
        }
    except Exception:
        domains["equipment"] = {"internal": False, "base_url": EQUIPMENT_BASE}

    return {"env": env, "monolith": monolith, "security_headers": SECURITY_HEADERS_ENABLED, "domains": domains}

# --- Wallet WebSocket (dev) ---
@app.websocket("/ws/payments/wallets/{wallet_id}")
async def ws_wallet_events(websocket: WebSocket, wallet_id: str):
    # Simple polling-based wallet credit stream over WS
    await websocket.accept()
    last_key = None
    try:
        while True:
            try:
                # fetch latest txn
                client = _httpx_async_client()
                r = await client.get(_payments_url(f"/txns"), params={"wallet_id": wallet_id, "limit": 1})
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
TAXI_BASE = _env_or("TAXI_BASE_URL", "")
BUS_BASE = _env_or("BUS_BASE_URL", "")
CARMARKET_BASE = _env_or("CARMARKET_BASE_URL", "")
CARRENTAL_BASE = _env_or("CARRENTAL_BASE_URL", "")
REALESTATE_BASE = _env_or("REALESTATE_BASE_URL", "")
STAYS_BASE = _env_or("STAYS_BASE_URL", "")
FREIGHT_BASE = _env_or("FREIGHT_BASE_URL", "")
EQUIPMENT_BASE = _env_or("EQUIPMENT_BASE_URL", "")
COURIER_BASE = _env_or("COURIER_BASE_URL", "")
COURIER_ADMIN_TOKEN = _env_or("COURIER_ADMIN_TOKEN", "")
CHAT_BASE = _env_or("CHAT_BASE_URL", "")
AGRICULTURE_BASE = _env_or("AGRICULTURE_BASE_URL", "")
COMMERCE_BASE = _env_or("COMMERCE_BASE_URL", "")
BUILDING_BASE = _env_or("BUILDING_BASE_URL", "")
DOCTORS_BASE = _env_or("DOCTORS_BASE_URL", "")
FLIGHTS_BASE = _env_or("FLIGHTS_BASE_URL", "")
JOBS_BASE = _env_or("JOBS_BASE_URL", "")
LIVESTOCK_BASE = _env_or("LIVESTOCK_BASE_URL", "")
PAYMENTS_INTERNAL_SECRET = os.getenv("PAYMENTS_INTERNAL_SECRET") or os.getenv("INTERNAL_API_SECRET")
GMAPS_API_KEY = os.getenv("GMAPS_API_KEY", "")
ORS_BASE = _env_or("ORS_BASE_URL", "")
ORS_API_KEY = os.getenv("ORS_API_KEY", "")
TOMTOM_API_KEY = os.getenv("TOMTOM_API_KEY", "")
TOMTOM_BASE = _env_or("TOMTOM_BASE_URL", "https://api.tomtom.com")
NOMINATIM_BASE = _env_or("NOMINATIM_BASE_URL", "")
GOTIFY_BASE = _env_or("GOTIFY_BASE_URL", "")
GOTIFY_APP_TOKEN = os.getenv("GOTIFY_APP_TOKEN", "")
NOMINATIM_USER_AGENT = _env_or("NOMINATIM_USER_AGENT", "shamell-taxi/1.0 (contact@example.com)")
OSRM_BASE = _env_or("OSRM_BASE_URL", "")
OVERPASS_BASE = _env_or("OVERPASS_BASE_URL", "https://overpass-api.de/api/interpreter")

# Force all domains to use internal integrations; ignore external BASE_URLs.
FORCE_INTERNAL_DOMAINS = True


def _force_internal(avail: bool) -> bool:
    return bool(FORCE_INTERNAL_DOMAINS and avail)
OVERPASS_USER_AGENT = _env_or("OVERPASS_USER_AGENT", NOMINATIM_USER_AGENT)
BFF_TOPUP_SELLERS = set(a.strip() for a in os.getenv("BFF_TOPUP_SELLERS", "").split(",") if a.strip())
BFF_TOPUP_ALLOW_ALL = (_env_or("BFF_TOPUP_ALLOW_ALL", "false").lower() == "true")
BFF_ADMINS = set(a.strip() for a in os.getenv("BFF_ADMINS", "").split(",") if a.strip())
SUPERADMIN_PHONE = os.getenv("SUPERADMIN_PHONE", "+963996428955").strip()
TAXI_CANCEL_FEE_SYP = int(_env_or("TAXI_CANCEL_FEE_SYP", "4000"))

# Guardrails for money + mobility flows (best-effort, per-process).
TAXI_PAYOUT_MAX_PER_DRIVER_DAY = int(_env_or("TAXI_PAYOUT_MAX_PER_DRIVER_DAY", "50"))
TAXI_CANCEL_MAX_PER_DRIVER_DAY = int(_env_or("TAXI_CANCEL_MAX_PER_DRIVER_DAY", "50"))
_TAXI_PAYOUT_EVENTS: dict[str, list[int]] = {}
_TAXI_CANCEL_EVENTS: dict[str, list[int]] = {}

# Simple in-memory rate limiting for auth flows (per process).
AUTH_RATE_WINDOW_SECS = int(_env_or("AUTH_RATE_WINDOW_SECS", "60"))
AUTH_MAX_PER_PHONE = int(_env_or("AUTH_MAX_PER_PHONE", "5"))
AUTH_MAX_PER_IP = int(_env_or("AUTH_MAX_PER_IP", "40"))
_AUTH_RATE_PHONE: dict[str, list[int]] = {}
_AUTH_RATE_IP: dict[str, list[int]] = {}

# Global security headers toggle
SECURITY_HEADERS_ENABLED = _env_or("SECURITY_HEADERS_ENABLED", "true").lower() == "true"

_ENV_LOWER = _env_or("ENV", "dev").lower()
_AUTH_EXPOSE_DEFAULT = "true" if _ENV_LOWER in ("dev", "test") else "false"
# Whether auth codes should be returned in responses (for dev/test only).
AUTH_EXPOSE_CODES = _env_or("AUTH_EXPOSE_CODES", _AUTH_EXPOSE_DEFAULT).lower() == "true"

# Global maintenance mode toggle (read-only / outage banner).
MAINTENANCE_MODE_ENABLED = _env_or("MAINTENANCE_MODE", "false").lower() == "true"

# ---- Simple session auth (OTP via code; in-memory storage for demo) ----
AUTH_SESSION_TTL_SECS = int(_env_or("AUTH_SESSION_TTL_SECS", "86400"))
LOGIN_CODE_TTL_SECS = int(_env_or("LOGIN_CODE_TTL_SECS", "300"))
_LOGIN_CODES = {}  # phone -> (code, expires_at)
_SESSIONS = {}     # sid -> (phone, expires_at)
_BLOCKED_PHONES: set[str] = set()
_PUSH_ENDPOINTS: dict[str, list[dict]] = {}
_AUTH_CLEANUP_INTERVAL_SECS = 60
_AUTH_LAST_CLEANUP_TS = 0

def _now() -> int:
    return int(time.time())


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


def _create_session(phone: str) -> str:
    _cleanup_auth_state()
    sid = _uuid.uuid4().hex
    _SESSIONS[sid] = (phone, _now()+AUTH_SESSION_TTL_SECS)
    return sid


def _auth_client_ip(request: Request) -> str:
    """
    Best-effort resolution of the client IP for rate limiting.
    Uses X-Forwarded-For if present, otherwise request.client.host.
    """
    try:
        fwd = request.headers.get("x-forwarded-for") or request.headers.get("X-Forwarded-For")
        if fwd:
            return fwd.split(",")[0].strip()
    except Exception:
        pass
    try:
        if request.client and request.client.host:
            return request.client.host
    except Exception:
        pass
    return "unknown"


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
    except HTTPException:
        # Guardrail intentionally blocking request
        raise
    except Exception:
        # Guardrails must never break normal flows
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
        if len(lst) > AUTH_MAX_PER_PHONE:
            raise HTTPException(status_code=429, detail="rate limited: too many codes for this phone")
    # Limit pro IP
    ip = _auth_client_ip(request)
    if ip:
        lst_ip = _AUTH_RATE_IP.get(ip) or []
        lst_ip = [ts for ts in lst_ip if ts >= now - AUTH_RATE_WINDOW_SECS]
        lst_ip.append(now)
        _AUTH_RATE_IP[ip] = lst_ip
        if len(lst_ip) > AUTH_MAX_PER_IP:
            raise HTTPException(status_code=429, detail="rate limited: too many requests from this ip")

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
            token = raw.strip()
            # Accept either a bare session ID or a cookie-style format
            # like "sa_session=...; path=/; ..."
            if "=" in token:
                for part in token.split(";"):
                    part = part.strip()
                    if part.startswith("sa_session="):
                        token = part.split("=", 1)[1]
                        break
            sid = token or None
    except Exception:
        sid = None

    # 2) Optional: session from query parameter (for deep-linked web consoles).
    if not sid:
        try:
            raw_q = request.query_params.get("sa_session") or request.query_params.get("sa_cookie")
            if raw_q:
                token = raw_q.strip()
                if "=" in token:
                    for part in token.split(";"):
                        part = part.strip()
                        if part.startswith("sa_session="):
                            token = part.split("=", 1)[1]
                            break
                sid = token or None
        except Exception:
            # Ignore query parsing errors and fall back to other mechanisms.
            pass

    # 3) Optional: session propagated via Referer query (for HTML consoles making fetch() calls).
    if not sid:
        try:
            ref = request.headers.get("referer") or request.headers.get("Referer")
            if ref:
                parsed = urlparse(ref)
                qs = parse_qs(parsed.query)
                vals = qs.get("sa_session") or qs.get("sa_cookie") or []
                if vals:
                    token = (vals[0] or "").strip()
                    if token:
                        if "=" in token:
                            for part in token.split(";"):
                                part = part.strip()
                                if part.startswith("sa_session="):
                                    token = part.split("=", 1)[1]
                                    break
                        sid = token or None
        except Exception:
            # Best-effort only; fall back to cookie if anything goes wrong.
            pass

    # 4) Fallback to regular cookie when no header or URL hint is used.
    if not sid:
        sid = request.cookies.get("sa_session")
    if not sid: return None
    rec = _SESSIONS.get(sid)
    if not rec: return None
    phone, exp = rec
    if exp < _now():
        try: del _SESSIONS[sid]
        except Exception: pass
        return None
    return phone


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
    except Exception:
        # Audit must never break normal flows
        pass


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
    # First try dynamic roles via Payments
    if PAYMENTS_BASE and PAYMENTS_INTERNAL_SECRET:
        try:
            url = _payments_url("/admin/roles/check")
            r = httpx.get(url, params={"phone": phone, "role": "seller"}, headers={"X-Internal-Secret": PAYMENTS_INTERNAL_SECRET}, timeout=6)
            if r.json().get("has", False):
                return phone
        except Exception:
            pass
    # Fallback to local env allowlist
    if BFF_TOPUP_ALLOW_ALL or not BFF_TOPUP_SELLERS or phone in BFF_TOPUP_SELLERS:
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
    entries = [e for e in _PUSH_ENDPOINTS.get(phone, []) if e.get("device_id") != device_id]
    entries.append({"device_id": device_id, "endpoint": endpoint, "type": etype})
    _PUSH_ENDPOINTS[phone] = entries
    return {"ok": True, "phone": phone, "device_id": device_id, "type": etype}


@app.get("/osm/route")
def osm_route(start_lat: float, start_lon: float, end_lat: float, end_lon: float, profile: str = "driving-car"):
    """
    Lightweight proxy for OpenRouteService/GraphHopper style routing.

    Returns a simplified polyline and distance/duration so the client can draw
    the route on MapLibre/Google maps without talking to ORS directly.
    """
    if not ORS_BASE and not OSRM_BASE and not TOMTOM_API_KEY:
        raise HTTPException(status_code=400, detail="no routing backend configured")
    try:
        points: list[list[float]] = []
        distance_m = 0.0
        duration_s = 0.0
        # Prefer TomTom Routing API when a key is configured.
        if TOMTOM_API_KEY:
            base = TOMTOM_BASE.rstrip("/")
            # TomTom Routing API expects "lat,lon:lat,lon" order in the path.
            path = f"/routing/1/calculateRoute/{float(start_lat)},{float(start_lon)}:{float(end_lat)},{float(end_lon)}/json"
            # Map generic profile to TomTom travelMode
            p = (profile or "").lower()
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
            coords = [
                [float(start_lon), float(start_lat)],
                [float(end_lon), float(end_lat)],
            ]
            url = ORS_BASE.rstrip("/") + f"/v2/directions/{profile}"
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


@app.get("/osm/geocode")
def osm_geocode(q: str):
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
        _OSM_GEOCODE_CACHE[q] = (now, out)
        return out
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/osm/poi_search")
def osm_poi_search(
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
    limit = max(1, min(limit, 50))
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
    try:
        body = await request.json()
    except Exception:
        body = {}
    if not isinstance(body, dict):
        body = {}
    queries = body.get("queries") or []
    if not isinstance(queries, list):
        raise HTTPException(status_code=400, detail="queries must be a list")
    max_per_query = int(body.get("max_per_query") or 1)
    max_per_query = max(1, min(max_per_query, 10))

    out: list[dict[str, object]] = []
    for raw_q in queries:
        q = str(raw_q or "").strip()
        if not q:
            out.append({"query": q, "hits": []})
            continue
        try:
            # Reuse osm_geocode logic via internal call
            hits = osm_geocode(q)
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
    try:
        o_lat = float(origin.get("lat"))
        o_lon = float(origin.get("lon"))
    except Exception:
        raise HTTPException(status_code=400, detail="invalid origin")
    # Normalise stops
    rem: list[dict[str, Any]] = []
    for s in stops:
        try:
            if not isinstance(s, dict):
                continue
            sid = str(s.get("id") or "")
            lat = float(s.get("lat"))
            lon = float(s.get("lon"))
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
    norm_depots: list[dict[str, Any]] = []
    for d in depots:
        try:
            if not isinstance(d, dict):
                continue
            did = str(d.get("id") or "")
            lat = float(d.get("lat"))
            lon = float(d.get("lon"))
            if not did:
                continue
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
            lat = float(s.get("lat"))
            lon = float(s.get("lon"))
            if not sid:
                continue
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
def osm_reverse(lat: float, lon: float):
    """
    Reverse geocoding proxy backed by Nominatim or TomTom.
    """
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
        _OSM_REVERSE_CACHE[key] = (now, res)
        return res
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/osm/taxi_stands")
def osm_taxi_stands(south: float, west: float, north: float, east: float, response: Response):
    """
    Find taxi stands (amenity=taxi) within a bounding box via Overpass.

    bbox = (south, west, north, east)
    """
    if north <= south or east <= west:
        raise HTTPException(status_code=400, detail="invalid bbox")
    # simple guard: don't allow excessively large boxes
    if (north - south) > 5.0 or (east - west) > 5.0:
        raise HTTPException(status_code=400, detail="bbox too large")
    if not OVERPASS_BASE:
        raise HTTPException(status_code=400, detail="OVERPASS_BASE_URL not configured")
    q = f"""
    [out:json][timeout:25];
    node["amenity"="taxi"]({south},{west},{north},{east});
    out body;
    """
    now = time.time()
    key = (round(south, 3), round(west, 3), round(north, 3), round(east, 3))
    cached = _OSM_TAXI_CACHE.get(key)
    if cached and (now - cached[0] < 60):
        try:
            if response is not None:
                response.headers.setdefault("Cache-Control", "public, max-age=60")
        except Exception:
            pass
        return cached[1]
    try:
        r = _httpx_client().post(
            OVERPASS_BASE,
            data={"data": q},
            headers={"User-Agent": OVERPASS_USER_AGENT},
        )
        if r.status_code >= 400:
            raise HTTPException(status_code=502, detail=f"overpass error: {r.text[:200]}")
        j = r.json()
        elements = j.get("elements") or []
        out = []
        for el in elements:
            try:
                if el.get("type") != "node":
                    continue
                lat = float(el.get("lat"))
                lon = float(el.get("lon"))
                tags = el.get("tags") or {}
                out.append({
                    "id": el.get("id"),
                    "lat": lat,
                    "lon": lon,
                    "name": tags.get("name") or "",
                    "tags": tags,
                })
            except Exception:
                continue
        _OSM_TAXI_CACHE[key] = (now, out)
        try:
            if response is not None:
                response.headers.setdefault("Cache-Control", "public, max-age=60")
        except Exception:
            pass
        return out
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
    except Exception:
        raise HTTPException(status_code=400, detail="invalid body")
    # Optional: also rate-limit verify requests (same limits as request_code)
    if phone:
        _rate_limit_auth(req, phone)
    if not _check_code(phone, code):
        raise HTTPException(status_code=400, detail="invalid code")
    # Ensure a payments wallet exists for this phone (idempotent).
    # Prefer internal Payments wiring in monolith mode; fallback to HTTP
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
            async with httpx.AsyncClient(timeout=10) as client:
                r = await client.post(url, json={"phone": phone})
            if r.headers.get("content-type","" ).startswith("application/json"):
                j = r.json()
                wallet_id = (j.get("wallet_id") or j.get("id")) if isinstance(j, dict) else None  # type: ignore[assignment]
    except HTTPException:
        # Input errors etc.; login should still work.
        wallet_id = None
    except Exception:
        # Payments must not hard-break login.
        wallet_id = None
    # Ensure rider exists in Taxi API
    rider_id = None
    try:
        if TAXI_BASE:
            url = TAXI_BASE.rstrip('/') + '/riders'
            payload = {"phone": phone}
            if name:
                payload["name"] = name
            if wallet_id:
                payload["wallet_id"] = wallet_id
            async with httpx.AsyncClient(timeout=10) as client:
                r = await client.post(url, json=payload)
                if r.headers.get("content-type","" ).startswith("application/json"):
                    j = r.json(); rider_id = j.get("id")
    except Exception:
        rider_id = None
    sid = _create_session(phone)
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
    # Prefer internal Payments wiring in monolith mode; fallback to HTTP only
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
            async with httpx.AsyncClient(timeout=10) as client:
                r = await client.post(url, json={"phone": phone})
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
            async with httpx.AsyncClient(timeout=10) as client:
                r = await client.post(_payments_url("/users"), json={"phone": phone})
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
            txns = payments_txns(wallet_id=str(wallet_id), limit=tx_limit)
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
      - operator KPIs: Taxi and Bus summaries (if operator/admin)
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
        for dom in ("taxi", "bus", "stays", "realestate", "food", "commerce", "freight", "agriculture", "livestock", "carrental", "equipment"):
            try:
                if _is_operator(phone, dom):
                    op_domains.append(dom)
            except Exception:
                continue
        snapshot["operator_domains"] = op_domains
        # Optionally add operator KPIs (best-effort)
        if "taxi" in op_domains:
            try:
                snapshot["taxi_admin_summary"] = taxi_admin_summary(request)
            except HTTPException:
                # Re-raise HTTPException (e.g. 403) so clients see that session/role does not match
                raise
            except Exception as e:
                snapshot["taxi_admin_summary_error"] = str(e)
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
      - mobility history: most recent Taxi and Bus rides via /me/mobility_history
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

@app.post("/auth/logout")
def auth_logout():
    resp = JSONResponse({"ok": True})
    resp.delete_cookie("sa_session", path="/")
    return resp

# --- Simple admin: block/unblock drivers by phone (in-memory) ---
@app.post("/admin/block_driver")
async def admin_block_driver(req: Request):
    _require_admin_v2(req)
    try:
        body = await req.json(); phone = (body.get("phone") or "").strip()
    except Exception:
        raise HTTPException(status_code=400, detail="invalid body")
    if not phone:
        raise HTTPException(status_code=400, detail="phone required")
    _BLOCKED_PHONES.add(phone)
    _audit_from_request(req, "admin_block_driver", target_phone=phone)
    return {"ok": True, "phone": phone, "blocked": True}

@app.post("/admin/unblock_driver")
async def admin_unblock_driver(req: Request):
    _require_admin_v2(req)
    try:
        body = await req.json(); phone = (body.get("phone") or "").strip()
    except Exception:
        raise HTTPException(status_code=400, detail="invalid body")
    if not phone:
        raise HTTPException(status_code=400, detail="phone required")
    try:
        _BLOCKED_PHONES.discard(phone)
    except Exception:
        pass
    _audit_from_request(req, "admin_unblock_driver", target_phone=phone)
    return {"ok": True, "phone": phone, "blocked": False}

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
    html = """
<!doctype html>
<html lang="en"><head>
  <meta name=viewport content="width=device-width, initial-scale=1" />
  <title>SuperApp</title>
  <script src="https://cdn.tailwindcss.com"></script>
  <link rel="icon" href="/favicon.ico" />
  <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" integrity="sha256-p4NxAoJBhIIN+hmNHrzRCf9tD/miZyoHS5obTRR9BMY=" crossorigin="" />
  <link rel="stylesheet" href="https://unpkg.com/leaflet.markercluster@1.5.3/dist/MarkerCluster.css" />
  <link rel="stylesheet" href="https://unpkg.com/leaflet.markercluster@1.5.3/dist/MarkerCluster.Default.css" />
  <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js" integrity="sha256-20nQCchB9co0qIjJZRGuk2/Z9VM+kNiyxNV1lvTlZBo=" crossorigin=""></script>
  <script src="https://unpkg.com/leaflet.markercluster@1.5.3/dist/leaflet.markercluster.js"></script>
  <script src="https://cdn.jsdelivr.net/npm/tweetnacl/nacl-fast.min.js"></script>
  <script src="https://unpkg.com/html5-qrcode@2.3.10/html5-qrcode.min.js"></script>
  <script src="/ds.js"></script>
  %%GMAPS_TAG%%
  <script>
  // --- tiny design system helpers ---
  // Using utility classes inline, plus a few small helper classes
  const DS = {
    btn: 'px-3 py-2 rounded border border-gray-300 bg-gray-100 hover:bg-gray-200 text-gray-900',
    btnPri: 'px-3 py-2 rounded border border-gray-900 bg-gray-900 text-white',
    btnGood: 'px-3 py-2 rounded border border-gray-300 bg-gray-100 text-gray-900',
    btnWarn: 'px-3 py-2 rounded border border-gray-300 bg-gray-100 text-gray-900',
    chip: 'px-2 py-1 rounded-full bg-white border border-gray-300 text-gray-800 text-xs',
    card: 'rounded border border-gray-300 bg-white',
    input: 'px-3 py-2 rounded border border-gray-300 placeholder-gray-400',
  };
    tailwind.config = { darkMode: 'class' }
  </script>
  <style>
    body{background:#ffffff;color:#000000;}
    .active{background-color:#e5e7eb}
    .glass{background:#ffffff;border:1px solid #d1d5db;border-radius:4px}
  </style>
</head>
<body class="min-h-screen">
  <div class="flex h-screen">
    <aside class="w-64 hidden md:block glass border border-white/20">
      <div class="p-4 text-xl font-semibold">SuperApp</div>
      <nav class="px-2 space-y-1" id="nav">
        <button data-mod="payments" class="w-full text-left px-3 py-2 rounded hover:bg-gray-100">Payments</button>
        <button data-mod="merchant" class="w-full text-left px-3 py-2 rounded hover:bg-gray-100">Merchant POS</button>
        <button data-mod="taxi_driver" class="w-full text-left px-3 py-2 rounded hover:bg-gray-100">Taxi Driver</button>
        <button data-mod="taxi_rider" class="w-full text-left px-3 py-2 rounded hover:bg-gray-100">Taxi Rider</button>
        <button data-mod="taxi_admin" class="w-full text-left px-3 py-2 rounded hover:bg-gray-100">Taxi Admin</button>
        <button data-mod="carmarket" class="w-full text-left px-3 py-2 rounded hover:bg-gray-100">Carmarket</button>
        <button data-mod="carrental" class="w-full text-left px-3 py-2 rounded hover:bg-gray-100">Carrental</button>
        <button data-mod="food" class="w-full text-left px-3 py-2 rounded hover:bg-gray-100">Food</button>
        <button data-mod="realestate" class="w-full text-left px-3 py-2 rounded hover:bg-gray-100">RealEstate</button>
        <button data-mod="stays" class="w-full text-left px-3 py-2 rounded hover:bg-gray-100">Stays</button>
        <button data-mod="freight" class="w-full text-left px-3 py-2 rounded hover:bg-gray-100">Courier</button>
        <button data-mod="chat" class="w-full text-left px-3 py-2 rounded hover:bg-gray-100">Chat</button>
        <div class="px-3 pt-3 text-xs uppercase text-gray-500">Admin</div>
        <button data-mod="risk" class="w-full text-left px-3 py-2 rounded hover:bg-gray-100">Risk Admin</button>
        <button data-mod="exports" class="w-full text-left px-3 py-2 rounded hover:bg-gray-100">Exports</button>
      </nav>
    </aside>
    <main class="flex-1 flex flex-col">
      <header class="flex items-center justify-between px-4 h-14 glass border border-white/20">
        <div class="md:hidden">
          <button id="menuBtn" class="p-2 rounded hover:bg-gray-100 dark:hover:bg-gray-800">☰</button>
        </div>
        <div class="font-semibold">Dashboard</div>
        <div class="flex items-center gap-2">
          <button onclick="me_ensureWallet()" class="px-2 py-1 rounded border border-gray-300 bg-gray-100 text-gray-900">Ensure Wallet</button>
          <button id="themeBtn" class="px-2 py-1 rounded border border-gray-300 bg-gray-100 text-gray-900">Theme</button>
          <button onclick="logout()" class="px-2 py-1 rounded border border-gray-300 bg-gray-100 text-gray-900">Logout</button>
        </div>
      </header>
      <div id="mobileNav" class="md:hidden hidden glass p-2 m-2">
        <div class="grid grid-cols-2 gap-2" id="navMobile"></div>
      </div>
      <!-- Quick Actions -->
      <div class="p-4">
        <div class="max-w-5xl mx-auto">
          <div class="glass border border-white/20 p-3 mb-3 rounded-xl flex items-center gap-2 text-white/90">
            <div class="px-2 py-1 rounded bg-gray-100 text-gray-900">Wallet</div>
            <div class="flex-1 truncate"><span class="opacity-80 text-sm">Wallet</span>
              <div id="me_wallet_chip" class="truncate">—</div></div>
            <button onclick="me_copyWallet()" class="px-2 py-1 rounded bg-white/20 hover:bg-white/30">Copy</button>
          </div>
          <div class="flex flex-wrap gap-2">
            <button onclick="quick_scan_pay()" class="px-4 py-2 rounded border border-gray-300 bg-gray-100 text-gray-900">Scan & Pay</button>
            <button onclick="quick_topup()" class="px-4 py-2 rounded border border-gray-300 bg-gray-100 text-gray-900">Topup</button>
            <button onclick="quick_p2p()" class="px-4 py-2 rounded border border-gray-300 bg-gray-100 text-gray-900">P2P</button>
          </div>
        </div>
      </div>
      <section class="flex-1">
        <!-- Native migrated panels -->
        <div id="panel-payments" class="hidden h-full overflow-auto p-4">
          <div class="max-w-5xl mx-auto space-y-6">
            <!-- Scan flash overlay -->
            <div id="pay_flash" class="fixed inset-0 pointer-events-none opacity-0 transition-opacity duration-200 bg-green-300/30"></div>

            <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-4">
              <div class="text-lg font-semibold mb-3">My Wallet</div>
              <div class="flex gap-2 items-center">
                <input id="me_wallet" class="flex-1 px-3 py-2 rounded border border-gray-300 dark:border-gray-700 bg-transparent" placeholder="my wallet id" />
                <button onclick="pay_saveMe()" class="px-3 py-2 rounded bg-blue-600 text-white">Save</button>
                <span id="me_status" class="text-sm text-gray-500"></span>
              </div>
            </div>

            <!-- Wallet hero -->
            <div id="wallet_hero" class="rounded-2xl p-4 text-white shadow hidden">
              <div class="flex items-center gap-3">
                <div class="p-3 rounded-xl bg-white/15">💳</div>
                <div class="flex-1">
                  <div class="text-sm opacity-90">Wallet</div>
                  <div id="wh_wallet" class="font-semibold truncate"></div>
                </div>
                <div class="text-right">
                  <div class="text-sm opacity-90">Saldo</div>
                  <div id="wh_balance" class="font-bold text-lg">—</div>
                  <div id="wh_kyc" class="text-xs opacity-90"></div>
                </div>
                <button onclick="pay_loadWallet()" class="ml-3 px-2 py-1 rounded bg-white/20 hover:bg-white/30">Refresh</button>
              </div>
            </div>

            <div class="grid md:grid-cols-2 gap-4">
              <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-4">
                <div class="text-lg font-semibold mb-3">Favorites</div>
                <div class="flex gap-2 mb-2">
                  <input id="fav_to2" class="flex-1 px-3 py-2 rounded border border-gray-300 dark:border-gray-700 bg-transparent" placeholder="favorite wallet id" />
                  <input id="fav_alias2" class="flex-1 px-3 py-2 rounded border border-gray-300 dark:border-gray-700 bg-transparent" placeholder="alias (optional)" />
                  <button onclick="pay_addFav()" class="px-3 py-2 rounded bg-blue-600 text-white">Add</button>
                </div>
                <div id="fav_list" class="text-sm"></div>
              </div>
              <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-4">
                <div class="text-lg font-semibold mb-3">Quick Pay</div>
                <div class="flex gap-2 mb-2">
                  <input id="qp_to3" class="flex-1 px-3 py-2 rounded border border-gray-300 dark:border-gray-700 bg-transparent" placeholder="To wallet id or @alias" />
                  <input id="qp_amt3" class="w-40 px-3 py-2 rounded border border-gray-300 dark:border-gray-700 bg-transparent" type="number" placeholder="Amount (cents)" />
                  <button onclick="pay_quickPay()" class="px-3 py-2 rounded bg-green-600 text-white">Pay</button>
                  <button onclick="pay_scan()" class="px-3 py-2 rounded border border-gray-300 dark:border-gray-700">Scan</button>
                </div>
                <div id="qp_recent3" class="flex flex-wrap gap-2"></div>
                <div id="scanner3" class="mt-2" style="width:260px;height:220px"></div>
              </div>
            </div>

            <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-4">
              <div class="text-lg font-semibold mb-3">Requests</div>
              <div class="flex flex-wrap gap-2 mb-3">
                <input id="rq_to3" class="flex-1 min-w-64 px-3 py-2 rounded border border-gray-300 dark:border-gray-700 bg-transparent" placeholder="Payer wallet id or @alias" />
                <input id="rq_amt3" class="w-40 px-3 py-2 rounded border border-gray-300 dark:border-gray-700 bg-transparent" type="number" placeholder="Amount (cents)" />
                <input id="rq_msg3" class="flex-1 min-w-40 px-3 py-2 rounded border border-gray-300 dark:border-gray-700 bg-transparent" placeholder="Message (optional)" />
                <button onclick="pay_createReq()" class="px-3 py-2 rounded bg-blue-600 text-white">Request</button>
                <button onclick="pay_loadReqs()" class="px-3 py-2 rounded border border-gray-300 dark:border-gray-700">Refresh</button>
              </div>
              <div class="grid md:grid-cols-2 gap-4">
                <div>
                  <div class="font-medium mb-2">Incoming</div>
                  <div id="rq_in3" class="space-y-2 text-sm"></div>
                </div>
                <div>
                  <div class="font-medium mb-2">Outgoing</div>
                  <div id="rq_out3" class="space-y-2 text-sm"></div>
                </div>
              </div>
            </div>

          </div>
        </div>

        <!-- Merchant panel (migrated) -->
        <div id="panel-merchant" class="hidden h-full overflow-auto p-4">
          <div class="max-w-5xl mx-auto space-y-6">
            <div class="${DS.card}">
              <div class="text-lg font-semibold mb-3">Merchant Wallet</div>
              <div class="flex gap-2 items-center">
                <input id="merch_wallet" class="flex-1 ${DS.input}" placeholder="wallet id" />
                <button onclick="merch_saveWid()" class="${DS.btnPri}">Save</button>
                <span id="merch_status" class="text-sm text-gray-500"></span>
              </div>
            </div>
            <div class="grid md:grid-cols-2 gap-4">
              <div class="${DS.card}">
                <div class="text-lg font-semibold mb-3">PAY QR</div>
                <div class="flex gap-2 mb-2">
                  <input id="merch_amount" class="w-40 ${DS.input}" type="number" placeholder="Amount (cents)" />
                  <button onclick="merch_genPayQR()" class="${DS.btnPri}">Generate</button>
                </div>
                <div id="merch_qr" class="mt-1"></div>
                <pre id="merch_payload" class="text-sm mt-2"></pre>
              </div>
              <div class="${DS.card}">
                <div class="text-lg font-semibold mb-3">Alias QR</div>
                <div class="flex gap-2 mb-2">
                  <input id="merch_alias" class="flex-1 ${DS.input}" placeholder="@alias" />
                  <input id="merch_a_amount" class="w-40 ${DS.input}" type="number" placeholder="Amount (cents)" />
                  <button onclick="merch_genAliasQR()" class="${DS.btnPri}">Generate</button>
                </div>
                <div id="merch_aqr" class="mt-1"></div>
                <pre id="merch_apayload" class="text-sm mt-2"></pre>
              </div>
            </div>
            <div class="grid md:grid-cols-2 gap-4">
              <div class="${DS.card}">
                <div class="text-lg font-semibold mb-3">Balance</div>
                <button onclick="merch_refreshBal()" class="${DS.btn}">Refresh</button>
                <pre id="merch_bal" class="text-sm mt-2"></pre>
              </div>
              <div class="${DS.card}">
                <div class="text-lg font-semibold mb-3">Recent Transactions</div>
                <button onclick="merch_loadTxns()" class="${DS.btn}">Load</button>
                <pre id="merch_txns" class="text-sm mt-2"></pre>
              </div>
            </div>
          </div>
        </div>

        <!-- Taxi Driver panel (migrated) -->
        <div id="panel-taxi-driver" class="hidden h-full overflow-auto p-4">
          <div class="max-w-5xl mx-auto space-y-6">
            <div class="${DS.card}">
              <div class="text-lg font-semibold mb-3">Register Driver</div>
              <div class="grid md:grid-cols-2 gap-2">
                <input id="td_name" class="${DS.input}" placeholder="Name" />
                <input id="td_phone" class="${DS.input}" placeholder="Phone" />
                <input id="td_make" class="${DS.input}" placeholder="Vehicle make" />
                <input id="td_plate" class="${DS.input}" placeholder="Plate" />
              </div>
              <div class="mt-2 flex gap-2">
                <button onclick="td_register()" class="${DS.btnPri}">Register</button>
                <input id="td_driver" class="flex-1 ${DS.input}" placeholder="driver_id" />
                <button onclick="td_save()" class="${DS.btn}">Save</button>
              </div>
              <pre id="td_out" class="text-sm mt-2"></pre>
            </div>
            <div class="grid md:grid-cols-2 gap-4">
              <div class="${DS.card}">
                <div class="text-lg font-semibold mb-3">Driver Controls</div>
                <div class="flex gap-2 mb-2">
                  <input id="td_wallet" class="flex-1 ${DS.input}" placeholder="driver wallet id" />
                  <button onclick="td_setWallet()" class="${DS.btn}">Set wallet</button>
                </div>
                <div class="flex gap-2">
                  <button onclick="td_online(true)" class="${DS.btnGood}">Go online</button>
                  <button onclick="td_online(false)" class="${DS.btn}">Go offline</button>
                </div>
              </div>
              <div class="${DS.card}">
                <div class="text-lg font-semibold mb-3">Location</div>
                <div class="grid grid-cols-2 gap-2 mb-2">
                  <input id="td_lat" class="${DS.input}" placeholder="lat" />
                  <input id="td_lon" class="${DS.input}" placeholder="lon" />
                </div>
                <div class="flex gap-2">
                  <button onclick="td_updateLoc()" class="${DS.btn}">Update</button>
                  <button onclick="td_track()" class="${DS.btn}">Start track</button>
                  <button onclick="td_stopTrack()" class="${DS.btn}">Stop track</button>
                  <button onclick="td_center()" class="${DS.btn}">Center on me</button>
                </div>
                <div id="td_map" class="rounded border border-gray-200 dark:border-gray-700 mt-3" style="height:300px"></div>
              </div>
            </div>
            <div class="${DS.card}">
              <div class="text-lg font-semibold mb-3">Events</div>
              <pre id="td_events" class="text-sm"></pre>
            </div>
          </div>
        </div>

        <!-- Taxi Rider panel (migrated) -->
        <div id="panel-taxi-rider" class="hidden h-full overflow-auto p-4">
          <div class="max-w-5xl mx-auto space-y-6">
            <div class="${DS.card}">
              <div class="text-lg font-semibold mb-3">Request Ride</div>
              <div class="grid md:grid-cols-2 gap-2 mb-2">
                <input id="tr_phone" class="${DS.input}" placeholder="Rider phone (optional)" />
                <input id="tr_wallet" class="${DS.input}" placeholder="Rider wallet (optional)" />
              </div>
              <div class="grid md:grid-cols-2 gap-2 mb-2">
                <input id="tr_plat" class="${DS.input}" placeholder="pickup lat" />
                <input id="tr_plon" class="${DS.input}" placeholder="pickup lon" />
              </div>
              <div class="grid md:grid-cols-2 gap-2 mb-2">
                <input id="tr_dlat" class="${DS.input}" placeholder="drop lat" />
                <input id="tr_dlon" class="${DS.input}" placeholder="drop lon" />
              </div>
              <div class="flex gap-2 mb-2">
                <button onclick="tr_req()" class="${DS.btnPri}">Request</button>
                <button onclick="tr_bookpay()" class="${DS.btnPri}">Book & Pay</button>
                <button onclick="tr_status()" class="${DS.btn}">Status</button>
                <button onclick="tr_cancel()" class="${DS.btn}">Cancel</button>
              </div>
              <input id="tr_ride" class="w-full ${DS.input}" placeholder="ride_id" />
              <div id="tr_map" class="rounded border border-gray-200 dark:border-gray-700 mt-3" style="height:300px"></div>
              <pre id="tr_out" class="text-sm mt-2"></pre>
            </div>
          </div>
        </div>

        <!-- Taxi Admin panel (migrated) -->
        <div id="panel-taxi-admin" class="hidden h-full overflow-auto p-4">
          <div class="max-w-6xl mx-auto space-y-6">
            <div class="${DS.card}">
              <div class="flex items-center justify-between mb-2">
                <div class="text-lg font-semibold">Map</div>
                <div class="flex gap-2">
                  <button onclick="ta_updateBounds()" class="${DS.btn}">Fit All</button>
                  <button onclick="ta_fitDrivers()" class="${DS.btn}">Fit Drivers</button>
                  <button onclick="ta_fitRides()" class="${DS.btn}">Fit Rides</button>
                </div>
              </div>
              <div id="ta_map" class="rounded border border-gray-200 dark:border-gray-700" style="height:360px"></div>
            </div>
            <div class="${DS.card}">
              <div class="flex items-center justify-between mb-2">
                <div class="text-lg font-semibold">Drivers (online)</div>
                <button onclick="ta_loadDrivers()" class="${DS.btn}">Refresh</button>
              </div>
              <div id="ta_drivers" class="text-sm"></div>
            </div>
            <div class="${DS.card}">
              <div class="flex items-center justify-between mb-2">
                <div class="text-lg font-semibold">Rides</div>
                <div class="flex gap-2 items-center">
                  <select id="ta_rstatus" class="${DS.input}">
                    <option value="">any</option>
                    <option value="requested">requested</option>
                    <option value="assigned">assigned</option>
                    <option value="in_progress">in_progress</option>
                    <option value="completed">completed</option>
                    <option value="canceled">canceled</option>
                  </select>
                  <button onclick="ta_loadRides()" class="${DS.btn}">Refresh</button>
                </div>
              </div>
              <div id="ta_rides" class="text-sm"></div>
              <div class="mt-3 flex gap-2 items-center">
                <input id="ta_ride" class="flex-1 ${DS.input}" placeholder="ride_id" />
                <input id="ta_driver_id" class="flex-1 ${DS.input}" placeholder="driver_id" />
                <button onclick="ta_assign()" class="${DS.btnPri}">Assign</button>
              </div>
              <pre id="ta_out" class="text-sm mt-2"></pre>
            </div>
          </div>
        </div>

        <!-- Carmarket panel (migrated) -->
        <div id="panel-carmarket" class="hidden h-full overflow-auto p-4">
          <div class="max-w-6xl mx-auto space-y-6">
            <div class="${DS.card}">
              <div class="flex items-center justify-between mb-2">
                <div class="text-lg font-semibold">Listings</div>
                <div class="flex gap-2 items-center">
                  <input id="cm_q" class="${DS.input}" placeholder="search" />
                  <input id="cm_city" class="${DS.input}" placeholder="city" />
                  <button onclick="cm_load()" class="${DS.btn}">Load</button>
                </div>
              </div>
              <table class="w-full text-sm">
                <thead><tr><th class="text-left">ID</th><th class="text-left">Title</th><th class="text-left">City</th><th class="text-left">Owner</th><th></th></tr></thead>
                <tbody id="cm_list"></tbody>
              </table>
            </div>
            <div class="${DS.card}">
              <div class="text-lg font-semibold mb-2">Create Listing</div>
              <div class="grid md:grid-cols-3 gap-2 mb-2">
                <input id="cm_title" class="${DS.input}" placeholder="Title" />
                <input id="cm_city2" class="${DS.input}" placeholder="City" />
                <input id="cm_owner" class="${DS.input}" placeholder="Owner wallet" />
              </div>
              <div class="grid md:grid-cols-3 gap-2 mb-2">
                <input id="cm_make" class="${DS.input}" placeholder="Make" />
                <input id="cm_model" class="${DS.input}" placeholder="Model" />
                <input id="cm_year" class="${DS.input}" placeholder="Year" />
              </div>
              <div class="grid md:grid-cols-3 gap-2 mb-2">
                <input id="cm_price" class="${DS.input}" placeholder="Price cents" />
                <input id="cm_desc" class="${DS.input}" placeholder="Description (optional)" />
                <button onclick="cm_create()" class="${DS.btnPri}">Create</button>
              </div>
              <pre id="cm_out" class="text-sm mt-2"></pre>
            </div>
            <div class="${DS.card}">
              <div class="text-lg font-semibold mb-2">Inquiry</div>
              <div class="grid md:grid-cols-3 gap-2 mb-2">
                <input id="cm_sel" class="${DS.input}" placeholder="listing id" />
                <input id="cm_iname" class="${DS.input}" placeholder="Your name" />
                <input id="cm_iphone" class="${DS.input}" placeholder="Phone" />
              </div>
              <div class="flex gap-2">
                <input id="cm_imsg" class="flex-1 ${DS.input}" placeholder="Message" />
                <button onclick="cm_inquiry()" class="${DS.btn}">Send</button>
              </div>
              <pre id="cm_iout" class="text-sm mt-2"></pre>
            </div>
          </div>
        </div>

        <!-- Carrental panel (migrated) -->
        <div id="panel-carrental" class="hidden h-full overflow-auto p-4">
          <div class="max-w-6xl mx-auto space-y-6">
            <div class="${DS.card}">
              <div class="flex items-center justify-between mb-2">
                <div class="text-lg font-semibold">Cars</div>
                <div class="flex gap-2 items-center">
                  <input id="cr_q" class="${DS.input}" placeholder="search" />
                  <input id="cr_city" class="${DS.input}" placeholder="city" />
                  <button onclick="cr_loadCars()" class="${DS.btn}">Load</button>
                </div>
              </div>
              <table class="w-full text-sm">
                <thead><tr><th class="text-left">ID</th><th class="text-left">Title</th><th class="text-left">Make/Model</th><th class="text-left">Year</th><th class="text-left">Price d/h</th><th class="text-left">Owner</th></tr></thead>
                <tbody id="cr_cars"></tbody>
              </table>
            </div>
            <div class="${DS.card}">
              <div class="text-lg font-semibold mb-2">Quote & Book</div>
              <div class="grid md:grid-cols-3 gap-2 mb-2">
                <input id="cr_carid" class="${DS.input}" placeholder="car id" />
                <input id="cr_from" class="${DS.input}" placeholder="from ISO" />
                <input id="cr_to" class="${DS.input}" placeholder="to ISO" />
              </div>
              <div class="flex gap-2 mb-2">
                <button onclick="cr_quote()" class="${DS.btn}">Quote</button>
                <pre id="cr_qout" class="text-sm flex-1"></pre>
              </div>
              <div class="grid md:grid-cols-3 gap-2 mb-2">
                <input id="cr_name" class="${DS.input}" placeholder="Renter name" />
                <input id="cr_phone" class="${DS.input}" placeholder="Renter phone" />
                <input id="cr_rw" class="${DS.input}" placeholder="Renter wallet (optional)" />
              </div>
              <label class="inline-flex items-center gap-2"><input id="cr_confirm" type="checkbox" /> Confirm & pay now</label>
              <div class="mt-2 flex gap-2 items-center">
                <button onclick="cr_book()" class="${DS.btnPri}">Book</button>
                <input id="cr_bid" class="flex-1 ${DS.input}" placeholder="booking id" />
                <button onclick="cr_status()" class="${DS.btn}">Status</button>
                <button onclick="cr_cancel()" class="${DS.btn}">Cancel</button>
                <button onclick="cr_confirm()" class="${DS.btn}">Confirm</button>
              </div>
              <pre id="cr_bout" class="text-sm mt-2"></pre>
              <pre id="cr_bstat" class="text-sm mt-2"></pre>
            </div>
          </div>
        </div>

        <!-- RealEstate panel (migrated) -->
        <div id="panel-realestate" class="hidden h-full overflow-auto p-4">
          <div class="max-w-6xl mx-auto space-y-6">
            <div class="${DS.card}">
              <div class="flex items-center justify-between mb-2">
                <div class="text-lg font-semibold">Properties</div>
                <div class="flex gap-2 items-center">
                  <input id="re_q" class="${DS.input}" placeholder="search" />
                  <input id="re_city" class="${DS.input}" placeholder="city" />
                  <input id="re_minp" class="${DS.input}" placeholder="min price" />
                  <input id="re_maxp" class="${DS.input}" placeholder="max price" />
                  <input id="re_minb" class="${DS.input}" placeholder="min beds" />
                  <button onclick="re_loadProps()" class="${DS.btn}">Load</button>
                </div>
              </div>
              <table class="w-full text-sm">
                <thead><tr><th class="text-left">ID</th><th class="text-left">Title</th><th class="text-left">City</th><th class="text-left">Price</th><th class="text-left">Beds</th><th class="text-left">Owner</th><th></th></tr></thead>
                <tbody id="re_props"></tbody>
              </table>
            </div>
            <div class="${DS.card}">
              <div class="text-lg font-semibold mb-2">Create / Update</div>
              <div class="grid md:grid-cols-3 gap-2 mb-2">
                <input id="re_pid" class="${DS.input}" placeholder="id (for update)" />
                <input id="re_title" class="${DS.input}" placeholder="title" />
                <input id="re_price" class="${DS.input}" placeholder="price_cents" />
              </div>
              <div class="grid md:grid-cols-3 gap-2 mb-2">
                <input id="re_city2" class="${DS.input}" placeholder="city" />
                <input id="re_addr" class="${DS.input}" placeholder="address" />
                <input id="re_beds" class="${DS.input}" placeholder="bedrooms" />
              </div>
              <div class="grid md:grid-cols-3 gap-2 mb-2">
                <input id="re_baths" class="${DS.input}" placeholder="bathrooms" />
                <input id="re_area" class="${DS.input}" placeholder="area sqm" />
                <input id="re_owner" class="${DS.input}" placeholder="owner wallet" />
              </div>
              <div class="flex gap-2">
                <button onclick="re_create()" class="${DS.btnPri}">Create</button>
                <button onclick="re_update()" class="${DS.btn}">Update</button>
              </div>
              <pre id="re_out" class="text-sm mt-2"></pre>
            </div>
            <div class="${DS.card}">
              <div class="text-lg font-semibold mb-2">Inquiry / Reserve</div>
              <div class="grid md:grid-cols-3 gap-2 mb-2">
                <input id="re_sel" class="${DS.input}" placeholder="property id" />
                <input id="re_iname" class="${DS.input}" placeholder="name" />
                <input id="re_iphone" class="${DS.input}" placeholder="phone" />
              </div>
              <div class="flex gap-2 mb-2">
                <input id="re_imsg" class="flex-1 ${DS.input}" placeholder="message" />
                <button onclick="re_inquiry()" class="${DS.btn}">Send Inquiry</button>
              </div>
              <div class="grid md:grid-cols-3 gap-2 mb-2">
                <input id="re_buyer" class="${DS.input}" placeholder="buyer wallet" />
                <input id="re_dep" class="${DS.input}" placeholder="deposit cents" />
                <button onclick="re_reserve()" class="${DS.btn}">Reserve</button>
              </div>
              <pre id="re_iout" class="text-sm mt-2"></pre>
            </div>
          </div>
        </div>

        <!-- Food panel (migrated) -->
        <div id="panel-food" class="hidden h-full overflow-auto p-4">
          <div class="max-w-6xl mx-auto space-y-6">
            <div class="${DS.card}">
              <div class="flex items-center justify-between mb-2">
                <div class="text-lg font-semibold">Restaurants</div>
                <div class="flex gap-2 items-center">
                  <input id="f_q" class="${DS.input}" placeholder="search" />
                  <input id="f_city" class="${DS.input}" placeholder="city" />
                  <button onclick="food_loadRests()" class="${DS.btn}">Load</button>
                </div>
              </div>
              <table id="f_rests" class="w-full text-sm">
                <thead><tr><th class="text-left">ID</th><th class="text-left">Name</th><th class="text-left">City</th><th class="text-left">Owner</th><th class="text-left"></th></tr></thead>
                <tbody></tbody>
              </table>
            </div>
            <div class="${DS.card}">
              <div class="text-lg font-semibold mb-2">Menu</div>
              <div class="flex gap-2 mb-2 items-center">
                <input id="f_rid" class="${DS.input}" placeholder="restaurant id" />
                <button onclick="food_loadMenu()" class="${DS.btn}">Load menu</button>
              </div>
              <table id="f_menu" class="w-full text-sm">
                <thead><tr><th class="text-left">ID</th><th class="text-left">Name</th><th class="text-left">Price</th><th class="text-left">Qty</th></tr></thead>
                <tbody></tbody>
              </table>
            </div>
            <div class="${DS.card}">
              <div class="text-lg font-semibold mb-2">Place Order</div>
              <div class="grid md:grid-cols-3 gap-2 mb-2">
                <input id="f_cname" class="${DS.input}" placeholder="Customer name" />
                <input id="f_cphone" class="${DS.input}" placeholder="Customer phone" />
                <input id="f_wallet" class="${DS.input}" placeholder="Wallet (optional)" />
              </div>
              <label class="inline-flex items-center gap-2"><input id="f_confirm" type="checkbox" /> Confirm & pay now</label>
              <div class="mt-2 flex gap-2">
                <button onclick="food_placeOrder()" class="${DS.btnPri}">Place order</button>
                <input id="f_oid" class="flex-1 ${DS.input}" placeholder="order id" />
                <button onclick="food_status()" class="${DS.btn}">Status</button>
                <select id="f_st" class="${DS.input}"><option>new</option><option>confirmed</option><option>preparing</option><option>ready</option><option>delivered</option><option>canceled</option></select>
                <button onclick="food_set()" class="${DS.btn}">Set</button>
              </div>
              <pre id="f_oout" class="text-sm mt-2"></pre>
              <pre id="f_os" class="text-sm mt-2"></pre>
              <div class="mt-4 border-t border-gray-200 pt-3">
                <div class="text-sm font-semibold mb-1">Delivery QR (escrow)</div>
                <p class="text-xs text-gray-600 mb-2">
                  Generate a QR code for the courier. The customer scans it in the app to release the escrow payment to the restaurant.
                </p>
                <div class="flex items-center gap-2 mb-2">
                  <button onclick="food_showQr()" class="${DS.btn}">Show delivery QR</button>
                </div>
                <div id="f_qrwrap" class="mt-1">
                  <img id="f_qr" alt="Delivery QR" class="border rounded" style="max-width:220px;max-height:220px;display:none" />
                </div>
              </div>
            </div>
            <div class="${DS.card}">
              <div class="flex items-center justify-between mb-2">
                <div class="text-lg font-semibold">Today's orders</div>
                <button onclick="food_loadOrdersToday()" class="${DS.btn}">Reload</button>
              </div>
              <table id="f_orders" class="w-full text-sm">
                <thead>
                  <tr>
                    <th class="text-left">ID</th>
                    <th class="text-left">Restaurant</th>
                    <th class="text-left">Total</th>
                    <th class="text-left">Status</th>
                    <th class="text-left">Escrow</th>
                    <th class="text-left"></th>
                  </tr>
                </thead>
                <tbody></tbody>
              </table>
            </div>
          </div>
        </div>

        <!-- Stays panel (migrated) -->
        <div id="panel-stays" class="hidden h-full overflow-auto p-4">
          <div class="max-w-6xl mx-auto space-y-6">
            <div class="${DS.card}">
              <div class="flex items-center justify-between mb-2">
                <div class="text-lg font-semibold">Listings</div>
                <div class="flex gap-2 items-center">
                  <input id="st_q" class="${DS.input}" placeholder="search" />
                  <input id="st_city" class="${DS.input}" placeholder="city" />
                  <button onclick="st_load()" class="${DS.btn}">Load</button>
                </div>
              </div>
              <table class="w-full text-sm">
                <thead><tr><th class="text-left">ID</th><th class="text-left">Title</th><th class="text-left">City</th><th class="text-left">Price/night</th><th class="text-left">Owner</th><th></th></tr></thead>
                <tbody id="st_list"></tbody>
              </table>
            </div>
            <div class="${DS.card}">
              <div class="text-lg font-semibold mb-2">Quote & Book</div>
              <div class="grid md:grid-cols-3 gap-2 mb-2">
                <input id="st_lid" class="${DS.input}" placeholder="listing id" />
                <input id="st_from" class="${DS.input}" placeholder="from ISO" />
                <input id="st_to" class="${DS.input}" placeholder="to ISO" />
              </div>
              <div class="grid md:grid-cols-3 gap-2 mb-2">
                <input id="st_gname" class="${DS.input}" placeholder="Guest name" />
                <input id="st_gphone" class="${DS.input}" placeholder="Guest phone" />
                <input id="st_gw" class="${DS.input}" placeholder="Guest wallet (optional)" />
              </div>
              <label class="inline-flex items-center gap-2"><input id="st_confirm" type="checkbox" /> Confirm & pay now</label>
              <div class="mt-2 flex gap-2 items-center">
                <button onclick="st_quote()" class="${DS.btn}">Quote</button>
                <pre id="st_qout" class="text-sm flex-1"></pre>
              </div>
              <div class="mt-2 flex gap-2 items-center">
                <button onclick="st_book()" class="${DS.btnPri}">Book</button>
                <input id="st_bid" class="flex-1 ${DS.input}" placeholder="booking id" />
                <button onclick="st_status()" class="${DS.btn}">Status</button>
              </div>
              <pre id="st_bout" class="text-sm mt-2"></pre>
              <pre id="st_bst" class="text-sm mt-2"></pre>
            </div>
          </div>
        </div>

        <!-- Courier panel (alias for Freight) -->
        <div id="panel-freight" class="hidden h-full overflow-auto p-4">
          <div class="max-w-6xl mx-auto space-y-6">
            <div class="${DS.card}">
              <div class="text-lg font-semibold mb-3">Quote</div>
              <div class="grid md:grid-cols-2 gap-2 mb-2">
                <input id="fr_title" class="${DS.input}" placeholder="Title" />
                <input id="fr_kg" class="${DS.input}" placeholder="Weight kg" />
              </div>
              <div class="grid md:grid-cols-4 gap-2 mb-2">
                <input id="fr_flat" class="${DS.input}" placeholder="from lat" />
                <input id="fr_flon" class="${DS.input}" placeholder="from lon" />
                <input id="fr_tlat" class="${DS.input}" placeholder="to lat" />
                <input id="fr_tlon" class="${DS.input}" placeholder="to lon" />
              </div>
              <div class="flex gap-2 items-center">
                <button onclick="fr_quote()" class="${DS.btn}">Quote</button>
                <pre id="fr_qout" class="text-sm flex-1"></pre>
              </div>
            </div>
            <div class="${DS.card}">
              <div class="text-lg font-semibold mb-3">Book</div>
              <div class="grid md:grid-cols-3 gap-2 mb-2">
                <input id="fr_payer" class="${DS.input}" placeholder="Payer wallet" />
                <input id="fr_carrier" class="${DS.input}" placeholder="Carrier wallet" />
                <label class="inline-flex items-center gap-2"><input id="fr_confirm" type="checkbox" /> Confirm & pay</label>
              </div>
              <div class="flex gap-2 items-center">
                <button onclick="fr_book()" class="${DS.btnPri}">Book</button>
                <input id="fr_sid" class="flex-1 ${DS.input}" placeholder="shipment id" />
                <button onclick="fr_status()" class="${DS.btn}">Status</button>
                <select id="fr_st" class="${DS.input}"><option>booked</option><option>in_transit</option><option>delivered</option><option>canceled</option></select>
                <button onclick="fr_set()" class="${DS.btn}">Set</button>
              </div>
              <pre id="fr_bout" class="text-sm mt-2"></pre>
              <pre id="fr_sout" class="text-sm mt-2"></pre>
            </div>
          </div>
        </div>

        <!-- Chat panel (migrated) -->
        <div id="panel-chat" class="hidden h-full overflow-auto p-4">
          <div class="max-w-5xl mx-auto space-y-6">
            <div class="${DS.card}">
              <div class="text-lg font-semibold mb-2">Your Identity</div>
              <div class="flex gap-2 mb-2">
                <button onclick="ch_gen()" class="${DS.btn}">Generate keys</button>
                <input id="ch_myid" class="${DS.input}" placeholder="Device ID" />
                <input id="ch_myname" class="${DS.input}" placeholder="Display name" />
                <button onclick="ch_register()" class="${DS.btnPri}">Register</button>
              </div>
              <pre id="ch_me" class="text-sm"></pre>
              <div class="mt-2">
                <div class="font-medium">Share</div>
                <pre id="ch_share" class="text-sm"></pre>
                <div id="ch_qr" class="mt-2"></div>
                <small>My fingerprint: <code id="ch_myfp"></code></small>
              </div>
              <div class="mt-2">
                <button onclick="ch_scanStart()" class="${DS.btn}">Scan Peer QR</button>
                <div id="ch_scanner" style="width:260px;height:220px" class="mt-2"></div>
              </div>
            </div>
            <div class="${DS.card}">
              <div class="text-lg font-semibold mb-2">Contact</div>
              <div class="flex gap-2 mb-2">
                <input id="ch_peerid" class="${DS.input}" placeholder="Peer ID" />
                <button onclick="ch_resolve()" class="${DS.btn}">Fetch peer key</button>
              </div>
              <pre id="ch_peer" class="text-sm"></pre>
              <small>Peer fingerprint: <code id="ch_peerfp"></code> · Verified: <span id="ch_verif">no</span></small>
              <div class="mt-2">
                <button onclick="ch_markVerified()" class="${DS.btn}">Mark verified</button>
              </div>
            </div>
            <div class="${DS.card}">
              <div class="text-lg font-semibold mb-2">Send message</div>
              <textarea id="ch_plain" class="w-full px-3 py-2 rounded border border-gray-300 dark:border-gray-700 bg-transparent" placeholder="Message..."></textarea>
              <button onclick="ch_send()" class="${DS.btnPri} mt-2">Send</button>
              <pre id="ch_sendout" class="text-sm mt-2"></pre>
            </div>
            <div class="${DS.card}">
              <div class="text-lg font-semibold mb-2">Inbox <small>WS: <span id="ch_live">disconnected</span></small></div>
              <div class="flex gap-2 mb-2">
                <button onclick="ch_poll()" class="${DS.btn}">Poll</button>
              </div>
              <pre id="ch_inbox" class="text-sm"></pre>
            </div>
          </div>
        </div>

        <!-- Legacy iframe fallback for non-migrated modules -->
        <iframe id="frame" src="/payments-social" class="w-full h-full"></iframe>
      </section>
    </main>
  </div>
  <script>
  const map = {
    payments:'/payments-social', merchant:'/merchant', taxi_driver:'/taxi/driver', taxi_rider:'/taxi/rider', taxi_admin:'/taxi/admin', carmarket:'/carmarket', carrental:'/carrental', food:'/food', realestate:'/realestate', stays:'/stays', freight:'/freight', chat:'/chat', risk:'/admin/risk', exports:'/admin/exports'
  };
  function setMod(k){ for(const b of document.querySelectorAll('#nav button')){ b.classList.toggle('active', b.dataset.mod===k); }
    if(k==='payments'){
      document.getElementById('panel-payments').classList.remove('hidden');
      document.getElementById('frame').classList.add('hidden');
      pay_init();
    } else if(k==='merchant'){
      document.getElementById('panel-payments').classList.add('hidden');
      document.getElementById('panel-merchant').classList.remove('hidden');
      document.getElementById('panel-taxi-driver').classList.add('hidden');
      document.getElementById('panel-taxi-rider').classList.add('hidden');
      document.getElementById('panel-taxi-admin').classList.add('hidden');
      document.getElementById('panel-carmarket').classList.add('hidden');
      document.getElementById('panel-carrental').classList.add('hidden');
      document.getElementById('panel-realestate').classList.add('hidden');
      document.getElementById('panel-stays').classList.add('hidden');
      document.getElementById('panel-freight').classList.add('hidden');
      document.getElementById('panel-chat').classList.add('hidden');
      document.getElementById('panel-food').classList.add('hidden');
      document.getElementById('frame').classList.add('hidden');
      merch_init();
    } else if(k==='taxi_driver'){
      document.getElementById('panel-payments').classList.add('hidden');
      document.getElementById('panel-merchant').classList.add('hidden');
      document.getElementById('panel-taxi-driver').classList.remove('hidden');
      document.getElementById('panel-taxi-rider').classList.add('hidden');
      document.getElementById('panel-taxi-admin').classList.add('hidden');
      document.getElementById('panel-carmarket').classList.add('hidden');
      document.getElementById('panel-carrental').classList.add('hidden');
      document.getElementById('panel-realestate').classList.add('hidden');
      document.getElementById('panel-stays').classList.add('hidden');
      document.getElementById('panel-freight').classList.add('hidden');
      document.getElementById('panel-chat').classList.add('hidden');
      document.getElementById('panel-food').classList.add('hidden');
      document.getElementById('frame').classList.add('hidden');
      td_mapSetup(); td_init();
    } else if(k==='taxi_rider'){
      document.getElementById('panel-payments').classList.add('hidden');
      document.getElementById('panel-merchant').classList.add('hidden');
      document.getElementById('panel-taxi-driver').classList.add('hidden');
      document.getElementById('panel-taxi-rider').classList.remove('hidden');
      document.getElementById('panel-taxi-admin').classList.add('hidden');
      document.getElementById('panel-carmarket').classList.add('hidden');
      document.getElementById('panel-carrental').classList.add('hidden');
      document.getElementById('panel-realestate').classList.add('hidden');
      document.getElementById('panel-stays').classList.add('hidden');
      document.getElementById('panel-freight').classList.add('hidden');
      document.getElementById('panel-chat').classList.add('hidden');
      document.getElementById('panel-food').classList.add('hidden');
      document.getElementById('frame').classList.add('hidden');
      tr_mapSetup();
    } else if(k==='taxi_admin'){
      document.getElementById('panel-payments').classList.add('hidden');
      document.getElementById('panel-merchant').classList.add('hidden');
      document.getElementById('panel-taxi-driver').classList.add('hidden');
      document.getElementById('panel-taxi-rider').classList.add('hidden');
      document.getElementById('panel-taxi-admin').classList.remove('hidden');
      document.getElementById('panel-carmarket').classList.add('hidden');
      document.getElementById('panel-carrental').classList.add('hidden');
      document.getElementById('panel-realestate').classList.add('hidden');
      document.getElementById('panel-stays').classList.add('hidden');
      document.getElementById('panel-freight').classList.add('hidden');
      document.getElementById('panel-chat').classList.add('hidden');
      document.getElementById('panel-food').classList.add('hidden');
      document.getElementById('frame').classList.add('hidden');
      ta_mapSetup(); ta_loadDrivers(); ta_loadRides();
    } else if(k==='realestate'){
      document.getElementById('panel-payments').classList.add('hidden');
      document.getElementById('panel-merchant').classList.add('hidden');
      document.getElementById('panel-taxi-driver').classList.add('hidden');
      document.getElementById('panel-taxi-rider').classList.add('hidden');
      document.getElementById('panel-taxi-admin').classList.add('hidden');
      document.getElementById('panel-carmarket').classList.add('hidden');
      document.getElementById('panel-carrental').classList.add('hidden');
      document.getElementById('panel-realestate').classList.remove('hidden');
      document.getElementById('panel-stays').classList.add('hidden');
      document.getElementById('panel-freight').classList.add('hidden');
      document.getElementById('panel-chat').classList.add('hidden');
      document.getElementById('panel-food').classList.add('hidden');
      document.getElementById('frame').classList.add('hidden');
      re_init();
    } else if(k==='carmarket'){
      document.getElementById('panel-payments').classList.add('hidden');
      document.getElementById('panel-merchant').classList.add('hidden');
      document.getElementById('panel-taxi-driver').classList.add('hidden');
      document.getElementById('panel-taxi-rider').classList.add('hidden');
      document.getElementById('panel-taxi-admin').classList.add('hidden');
      document.getElementById('panel-carmarket').classList.remove('hidden');
      document.getElementById('panel-carrental').classList.add('hidden');
      document.getElementById('panel-realestate').classList.add('hidden');
      document.getElementById('panel-stays').classList.add('hidden');
      document.getElementById('panel-freight').classList.add('hidden');
      document.getElementById('panel-chat').classList.add('hidden');
      document.getElementById('panel-food').classList.add('hidden');
      document.getElementById('frame').classList.add('hidden');
      cm_init();
    } else if(k==='carrental'){
      document.getElementById('panel-payments').classList.add('hidden');
      document.getElementById('panel-merchant').classList.add('hidden');
      document.getElementById('panel-taxi-driver').classList.add('hidden');
      document.getElementById('panel-taxi-rider').classList.add('hidden');
      document.getElementById('panel-taxi-admin').classList.add('hidden');
      document.getElementById('panel-carmarket').classList.add('hidden');
      document.getElementById('panel-carrental').classList.remove('hidden');
      document.getElementById('panel-realestate').classList.add('hidden');
      document.getElementById('panel-stays').classList.add('hidden');
      document.getElementById('panel-freight').classList.add('hidden');
      document.getElementById('panel-chat').classList.add('hidden');
      document.getElementById('panel-food').classList.add('hidden');
      document.getElementById('frame').classList.add('hidden');
      cr_init();
    } else if(k==='food'){
      document.getElementById('panel-payments').classList.add('hidden');
      document.getElementById('panel-merchant').classList.add('hidden');
      document.getElementById('panel-taxi-driver').classList.add('hidden');
      document.getElementById('panel-taxi-rider').classList.add('hidden');
      document.getElementById('panel-taxi-admin').classList.add('hidden');
      document.getElementById('panel-carmarket').classList.add('hidden');
      document.getElementById('panel-carrental').classList.add('hidden');
      document.getElementById('panel-realestate').classList.add('hidden');
      document.getElementById('panel-stays').classList.add('hidden');
      document.getElementById('panel-freight').classList.add('hidden');
      document.getElementById('panel-chat').classList.add('hidden');
      document.getElementById('panel-food').classList.remove('hidden');
      document.getElementById('frame').classList.add('hidden');
      food_init();
    } else if(k==='stays'){
      document.getElementById('panel-payments').classList.add('hidden');
      document.getElementById('panel-merchant').classList.add('hidden');
      document.getElementById('panel-taxi-driver').classList.add('hidden');
      document.getElementById('panel-taxi-rider').classList.add('hidden');
      document.getElementById('panel-taxi-admin').classList.add('hidden');
      document.getElementById('panel-carmarket').classList.add('hidden');
      document.getElementById('panel-carrental').classList.add('hidden');
      document.getElementById('panel-realestate').classList.add('hidden');
      document.getElementById('panel-stays').classList.remove('hidden');
      document.getElementById('panel-freight').classList.add('hidden');
      document.getElementById('panel-chat').classList.add('hidden');
      document.getElementById('panel-food').classList.add('hidden');
      document.getElementById('frame').classList.add('hidden');
      st_init();
    } else if(k==='freight'){
      document.getElementById('panel-payments').classList.add('hidden');
      document.getElementById('panel-merchant').classList.add('hidden');
      document.getElementById('panel-taxi-driver').classList.add('hidden');
      document.getElementById('panel-taxi-rider').classList.add('hidden');
      document.getElementById('panel-taxi-admin').classList.add('hidden');
      document.getElementById('panel-carmarket').classList.add('hidden');
      document.getElementById('panel-carrental').classList.add('hidden');
      document.getElementById('panel-realestate').classList.add('hidden');
      document.getElementById('panel-stays').classList.add('hidden');
      document.getElementById('panel-freight').classList.remove('hidden');
      document.getElementById('panel-chat').classList.add('hidden');
      document.getElementById('panel-food').classList.add('hidden');
      document.getElementById('frame').classList.add('hidden');
      fr_init();
    } else if(k==='chat'){
      document.getElementById('panel-payments').classList.add('hidden');
      document.getElementById('panel-merchant').classList.add('hidden');
      document.getElementById('panel-taxi-driver').classList.add('hidden');
      document.getElementById('panel-taxi-rider').classList.add('hidden');
      document.getElementById('panel-taxi-admin').classList.add('hidden');
      document.getElementById('panel-carmarket').classList.add('hidden');
      document.getElementById('panel-carrental').classList.add('hidden');
      document.getElementById('panel-realestate').classList.add('hidden');
      document.getElementById('panel-stays').classList.add('hidden');
      document.getElementById('panel-freight').classList.add('hidden');
      document.getElementById('panel-chat').classList.remove('hidden');
      document.getElementById('panel-food').classList.add('hidden');
      document.getElementById('frame').classList.add('hidden');
      ch_init();
    } else {
      document.getElementById('panel-payments').classList.add('hidden');
      document.getElementById('panel-merchant').classList.add('hidden');
      document.getElementById('panel-taxi-driver').classList.add('hidden');
      document.getElementById('panel-taxi-rider').classList.add('hidden');
      document.getElementById('panel-taxi-admin').classList.add('hidden');
      document.getElementById('panel-carmarket').classList.add('hidden');
      document.getElementById('panel-carrental').classList.add('hidden');
      document.getElementById('panel-realestate').classList.add('hidden');
      document.getElementById('panel-stays').classList.add('hidden');
      document.getElementById('panel-freight').classList.add('hidden');
      document.getElementById('panel-chat').classList.add('hidden');
      document.getElementById('panel-food').classList.add('hidden');
      document.getElementById('frame').classList.remove('hidden');
      const url = map[k]||'/payments-social'; document.getElementById('frame').src=url;
    }
  }
  const params = new URLSearchParams(location.search); if(params.get('mod')) setMod(params.get('mod'));
  for(const b of document.querySelectorAll('#nav button')){ b.addEventListener('click', ()=>setMod(b.dataset.mod)); }
  // mobile nav
  const navMobile = document.getElementById('navMobile');
  document.getElementById('menuBtn').addEventListener('click', ()=>{ const el=document.getElementById('mobileNav'); el.classList.toggle('hidden'); });
  for(const k in map){ const a=document.createElement('button'); a.textContent=k.replace('_',' '); a.className='px-2 py-2 rounded border border-gray-300 dark:border-gray-700'; a.onclick=()=>{ setMod(k); document.getElementById('mobileNav').classList.add('hidden'); }; navMobile.appendChild(a); }
  // theme
  const themeBtn=document.getElementById('themeBtn');
  function applyTheme(){ const d=localStorage.getItem('sa_theme')||'light'; document.documentElement.classList.toggle('dark', d==='dark'); themeBtn.textContent = d==='dark'?'☀️':'🌙'; }
  themeBtn.addEventListener('click', ()=>{ const cur=localStorage.getItem('sa_theme')||'light'; localStorage.setItem('sa_theme', cur==='dark'?'light':'dark'); applyTheme(); }); applyTheme();
  async function logout(){ await fetch('/auth/logout',{method:'POST'}); location.href='/login'; }

  // Quick actions
  function quick_scan_pay(){ setMod('payments'); setTimeout(()=>{ try{ pay_scan(); }catch(e){} }, 60); }
  async function quick_topup(){
    try{
      const me = (localStorage.getItem('me_wallet')||'').trim();
      const w = prompt('Wallet ID to top up', me);
      if(!w) return;
      const a = parseInt(prompt('Amount (cents)', '10000')||'0',10);
      if(!(a>0)){ alert('Invalid amount'); return; }
      const r = await fetch('/payments/wallets/'+encodeURIComponent(w)+'/topup', {method:'POST', headers:{'content-type':'application/json','Idempotency-Key':'qa-'+Date.now()}, body: JSON.stringify({amount_cents:a})});
      const t = await r.text();
      alert(r.status+': '+t);
    }catch(e){ alert('Topup error: '+e); }
  }
  function quick_p2p(){ setMod('payments'); setTimeout(()=>{ try{ document.getElementById('qp_to3')?.focus(); }catch(_){ } }, 60); }

  // Payments panel logic (migrated)
  function pay_me(){ const el=document.getElementById('me_wallet'); let v=el.value.trim(); if(!v){ v=localStorage.getItem('me_wallet')||''; el.value=v; } return v; }
  function pay_saveMe(){ const v=document.getElementById('me_wallet').value.trim(); localStorage.setItem('me_wallet', v); document.getElementById('me_status').textContent='Saved'; pay_loadWallet(); pay_loadFavs(); pay_loadReqs(); }
  function pay_recent(){ try{ return JSON.parse(localStorage.getItem('recent_payees')||'[]'); }catch(e){ return []; } }
  function pay_saveRecent(list){ localStorage.setItem('recent_payees', JSON.stringify(list)); pay_renderRecent(); }
  function pay_addRecent(target){ if(!target) return; const list=pay_recent().filter(x=>x!==target); list.unshift(target); while(list.length>5) list.pop(); pay_saveRecent(list); }
  function _hue(s){ let h=0; for(let i=0;i<s.length;i++){ h=(h*31 + s.charCodeAt(i))&0xffffffff; } return Math.abs(h)%360; }
  function avatarHTML(label){ const h=_hue(label.replace('@','')); const c1=`hsl(${h} 90% 55%)`; const c2=`hsl(${(h+24)%360} 85% 65%)`; const init=(label.replace('@','')[0]||'?').toUpperCase(); return `<span class=\"inline-flex items-center justify-center w-7 h-7 rounded-full shadow\" style=\"background:linear-gradient(135deg, ${c1}, ${c2}); color:white; font-weight:700;\">${init}</span>`; }
  function pay_renderRecent(){ const list=pay_recent(); const el=document.getElementById('qp_recent3'); if(!el) return; el.textContent=''; for(const t of list){ const b=document.createElement('button'); b.className='flex items-center gap-2 px-2 py-1 rounded border border-gray-300 dark:border-gray-700 text-sm'; b.innerHTML=avatarHTML(t)+`<span class=\\"truncate max-w-[12rem]\\">${t}</span>`; b.onclick=()=>{ document.getElementById('qp_to3').value=t; }; el.appendChild(b); } }
  async function pay_addFav(){ const o=pay_me(); const to=document.getElementById('fav_to2').value.trim(); const alias=(document.getElementById('fav_alias2').value||'').trim()||null; if(!o||!to){ alert('me/favorite required'); return; } const r=await fetch('/payments/favorites',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({owner_wallet_id:o,favorite_wallet_id:to,alias:alias})}); if(!r.ok){ alert('error'); } pay_loadFavs(); }
  async function pay_loadFavs(){ const o=pay_me(); if(!o){ return; } const r=await fetch('/payments/favorites?owner_wallet_id='+encodeURIComponent(o)); const arr=await r.json(); const box=document.getElementById('fav_list'); box.innerHTML=''; for(const f of arr){ const row=document.createElement('div'); row.className='flex items-center justify-between border-b border-gray-200 dark:border-gray-700 py-1'; const label=(f.alias||''); const id=f.favorite_wallet_id; row.innerHTML=`<div class=\"flex items-center gap-2\">${avatarHTML(label||id)}<span>${label||''} <small class=\"text-gray-500\">${id}</small></span></div>`; const act=document.createElement('div'); const payBtn=document.createElement('button'); payBtn.textContent='Pay'; payBtn.className='px-2 py-1 rounded bg-green-600 text-white text-sm'; payBtn.onclick=()=>pay_payTarget(label?label:id); const delBtn=document.createElement('button'); delBtn.textContent='Delete'; delBtn.className='ml-2 px-2 py-1 rounded border border-gray-300 dark:border-gray-700 text-sm'; delBtn.onclick=async()=>{ await fetch('/payments/favorites/'+f.id,{method:'DELETE'}); pay_loadFavs(); }; act.appendChild(payBtn); act.appendChild(delBtn); row.appendChild(act); box.appendChild(row);} }
  async function pay_payTarget(target){ const from=pay_me(); if(!from){ alert('save my wallet first'); return; } let amt=parseInt(prompt('Amount (cents):','1000')||'0',10); if(!(amt>0)){ return; } const ik='mx-'+Date.now().toString(36)+'-'+Math.random().toString(36).slice(2,6); const body=(target.startsWith('@')? {from_wallet_id:from,to_alias:target,amount_cents:amt}: {from_wallet_id:from,to_wallet_id:target,amount_cents:amt}); const r=await fetch('/payments/transfer',{method:'POST',headers:{'content-type':'application/json','Idempotency-Key':ik},body:JSON.stringify(body)}); if(!r.ok){ alert('pay failed'); } else { pay_addRecent(target); alert('paid'); } }

  // Stays panel logic
  function st_val(id){ return (document.getElementById(id).value||'').trim(); }
  async function st_init(){ try{ await st_load(); }catch(_){ } }
  async function st_load(){ const u=new URLSearchParams(); const q=st_val('st_q'); if(q)u.set('q',q); const c=st_val('st_city'); if(c)u.set('city',c); const r=await fetch('/stays/listings?'+u.toString()); const arr=await r.json(); const tb=document.getElementById('st_list'); tb.innerHTML=''; for(const x of arr){ const tr=document.createElement('tr'); tr.innerHTML = `<td>${x.id}</td><td>${x.title}</td><td>${x.city||''}</td><td>${x.price_per_night_cents}</td><td><small>${x.owner_wallet_id||''}</small></td><td><button class='${DS.btn}' onclick='document.getElementById("st_lid").value=${x.id}'>Select</button></td>`; tb.appendChild(tr);} }
  async function st_quote(){ const body={listing_id: parseInt(st_val('st_lid')||'0',10), from_iso:st_val('st_from'), to_iso:st_val('st_to')}; const r=await fetch('/stays/quote',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)}); document.getElementById('st_qout').textContent = await r.text(); }
  async function st_book(){ const body={listing_id: parseInt(st_val('st_lid')||'0',10), guest_name:st_val('st_gname'), guest_phone:st_val('st_gphone'), guest_wallet_id:st_val('st_gw')||null, from_iso:st_val('st_from'), to_iso:st_val('st_to'), confirm: document.getElementById('st_confirm').checked}; const r=await fetch('/stays/book',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)}); const t=await r.text(); document.getElementById('st_bout').textContent=t; try{ const j=JSON.parse(t); document.getElementById('st_bid').value=j.id; }catch(_){ } }
  async function st_status(){ const id=st_val('st_bid'); if(!id){ alert('set booking id'); return; } const r=await fetch('/stays/bookings/'+encodeURIComponent(id)); document.getElementById('st_bst').textContent = await r.text(); }

  // Freight panel logic
  function fr_val(id){ return (document.getElementById(id).value||'').trim(); }
  async function fr_init(){ }
  async function fr_quote(){ const body={title:fr_val('fr_title'), from_lat:parseFloat(fr_val('fr_flat')), from_lon:parseFloat(fr_val('fr_flon')), to_lat:parseFloat(fr_val('fr_tlat')), to_lon:parseFloat(fr_val('fr_tlon')), weight_kg:parseFloat(fr_val('fr_kg'))}; const r=await fetch('/freight/quote',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)}); document.getElementById('fr_qout').textContent=await r.text(); }
  async function fr_book(){ const body={title:fr_val('fr_title'), from_lat:parseFloat(fr_val('fr_flat')), from_lon:parseFloat(fr_val('fr_flon')), to_lat:parseFloat(fr_val('fr_tlat')), to_lon:parseFloat(fr_val('fr_tlon')), weight_kg:parseFloat(fr_val('fr_kg')), payer_wallet_id:fr_val('fr_payer')||null, carrier_wallet_id:fr_val('fr_carrier')||null, confirm:document.getElementById('fr_confirm').checked}; const r=await fetch('/freight/book',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)}); const t=await r.text(); document.getElementById('fr_bout').textContent=t; try{ const j=JSON.parse(t); document.getElementById('fr_sid').value=j.id; }catch(_){ } }
  async function fr_status(){ const id=fr_val('fr_sid'); if(!id){ alert('set shipment id'); return; } const r=await fetch('/freight/shipments/'+encodeURIComponent(id)); document.getElementById('fr_sout').textContent = await r.text(); }
  async function fr_set(){ const id=fr_val('fr_sid'); if(!id){ alert('set shipment id'); return; } const st=document.getElementById('fr_st').value; const r=await fetch('/freight/shipments/'+encodeURIComponent(id)+'/status',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({status:st})}); document.getElementById('fr_sout').textContent = await r.text(); }

  // Chat panel logic
  let chMy={pk:null, sk:null, id:null, name:null};
  let chPeers={};
  let chWs=null;
  function ch_b64(u8){ return btoa(String.fromCharCode.apply(null, Array.from(u8))); }
  function ch_unb64(s){ return new Uint8Array(atob(s).split('').map(c=>c.charCodeAt(0))); }
  async function ch_sha256(u8){ const buf = await crypto.subtle.digest('SHA-256', u8); return new Uint8Array(buf); }
  function ch_toHex(u8){ return Array.from(u8).map(b=>b.toString(16).padStart(2,'0')).join(''); }
  async function ch_computeFpB64(pkB64){ try{ const u=ch_unb64(pkB64); const d=await ch_sha256(u); if(d){ return ch_toHex(d).slice(0,16); } }catch(_){ } return (pkB64||'').slice(0,16); }
  function ch_isVerified(pid, fp){ try{ return localStorage.getItem('verified_peer_'+pid) === fp; }catch(_){ return false; } }
  function ch_gi(id){ return (document.getElementById(id).value||'').trim(); }
  function ch_init(){ try{ ch_connectWS(); }catch(_){ } }
  function ch_gen(){ const kp=nacl.box.keyPair(); chMy.pk=kp.publicKey; chMy.sk=kp.secretKey; const id=(Math.random().toString(36).slice(2,10)); chMy.id=id; document.getElementById('ch_myid').value=id; document.getElementById('ch_me').textContent='PublicKey(b64)='+ch_b64(chMy.pk); const payload='CHAT|id='+id+'|pk='+ch_b64(chMy.pk); document.getElementById('ch_share').textContent=payload; try{ makeQR(payload); const qr=document.getElementById('ch_qr'); const el=document.getElementById('qr'); if(el&&qr&&el.parentElement!==qr){ qr.appendChild(el.firstChild); } }catch(_){ } ch_updateMyFp(); ch_connectWS(); }
  async function ch_register(){ const id=ch_gi('ch_myid'); chMy.id=id; const name=ch_gi('ch_myname'); chMy.name=name; if(!chMy.pk){ alert('Generate keys'); return; } const body={device_id:id, public_key_b64:ch_b64(chMy.pk), name:name||null}; const r=await fetch('/chat/devices/register',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)}); document.getElementById('ch_me').textContent=await r.text(); ch_connectWS(); }
  async function ch_resolve(){ const id=ch_gi('ch_peerid'); const r=await fetch('/chat/devices/'+encodeURIComponent(id)); const j=await r.json(); chPeers[id]=j.public_key_b64; document.getElementById('ch_peer').textContent=JSON.stringify(j,null,2); ch_updatePeerFp(); }
  async function ch_send(){ const id=ch_gi('ch_peerid'); const pkb64=chPeers[id]; if(!pkb64){ alert('resolve peer first'); return; } const msg=(document.getElementById('ch_plain').value||''); const nonce=nacl.randomBytes(24); const peerPk=ch_unb64(pkb64); const box=nacl.box(new TextEncoder().encode(msg), nonce, peerPk, chMy.sk); const body={sender_id: chMy.id, recipient_id:id, sender_pubkey_b64: ch_b64(chMy.pk), nonce_b64: ch_b64(nonce), box_b64: ch_b64(box)}; const r=await fetch('/chat/messages/send',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)}); document.getElementById('ch_sendout').textContent=await r.text(); }
  async function ch_poll(){ const r=await fetch('/chat/messages/inbox?device_id='+encodeURIComponent(chMy.id)+'&limit=20'); const arr=await r.json(); const out=[]; for(const m of arr.reverse()){ try{ const nonce=ch_unb64(m.nonce_b64); const box=ch_unb64(m.box_b64); const spk=ch_unb64(m.sender_pubkey_b64); const plain=nacl.box.open(box, nonce, spk, chMy.sk); out.push({from:m.sender_id, text:(plain? new TextDecoder().decode(plain):'<decrypt failed>')}); try{ await fetch('/chat/messages/'+encodeURIComponent(m.id)+'/read',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({read:true})}); }catch(_){ } }catch(e){ out.push({from:m.sender_id, text:'<error>'}); } } document.getElementById('ch_inbox').textContent=JSON.stringify(out,null,2); }
  async function ch_scanStart(){ try{ const el=document.getElementById('ch_scanner'); const html5QrCode=new Html5Qrcode(el.id); await html5QrCode.start({ facingMode:'environment' }, { fps:10, qrbox:200 }, (decodedText)=>{ try{ if(decodedText&&decodedText.startsWith('CHAT|')){ const parts=decodedText.split('|'); const map={}; for(const p of parts.slice(1)){ const kv=p.split('='); if(kv.length==2) map[kv[0]]=kv[1]; } if(map['id']&&map['pk']){ chPeers[map['id']]=map['pk']; document.getElementById('ch_peerid').value=map['id']; document.getElementById('ch_peer').textContent=JSON.stringify({device_id:map['id'], public_key_b64:map['pk']},null,2); ch_updatePeerFp(); html5QrCode.stop(); } } }catch(_){ } }); }catch(e){ alert('scan error: '+e); }
  async function ch_updateMyFp(){ try{ const fp=await ch_computeFpB64(ch_b64(chMy.pk)); document.getElementById('ch_myfp').textContent=fp; }catch(_){ } }
  async function ch_updatePeerFp(){ try{ const pid=ch_gi('ch_peerid'); const pkb64=chPeers[pid]; if(!pkb64){ return; } const fp=await ch_computeFpB64(pkb64); document.getElementById('ch_peerfp').textContent=fp; document.getElementById('ch_verif').textContent=(ch_isVerified(pid,fp)?'yes':'no'); }catch(_){ } }
  async function ch_markVerified(){ const pid=ch_gi('ch_peerid'); const pkb64=chPeers[pid]; if(!pid||!pkb64){ alert('resolve/scan peer first'); return; } const fp=await ch_computeFpB64(pkb64); try{ localStorage.setItem('verified_peer_'+pid, fp); document.getElementById('ch_verif').textContent='yes'; }catch(_){ } }
  function ch_connectWS(){ try{ if(!chMy.id){ return; } if(chWs&&(chWs.readyState===1||chWs.readyState===0)){ return; } const base=(location.protocol==='https:'?'wss://':'ws://')+location.host; chWs=new WebSocket(base+'/ws/chat/inbox?device_id='+encodeURIComponent(chMy.id)); const live=document.getElementById('ch_live'); chWs.onopen=()=>{ if(live) live.textContent='connected'; }; chWs.onclose=()=>{ if(live) live.textContent='disconnected'; }; chWs.onerror=()=>{ if(live) live.textContent='error'; }; chWs.onmessage=async (ev)=>{ try{ const msg=JSON.parse(ev.data); if(msg&&msg.type==='inbox'&&Array.isArray(msg.messages)){ const outEl=document.getElementById('ch_inbox'); const out=[]; for(const m of msg.messages){ try{ const nonce=ch_unb64(m.nonce_b64); const box=ch_unb64(m.box_b64); const spk=ch_unb64(m.sender_pubkey_b64); const plain=nacl.box.open(box, nonce, spk, chMy.sk); out.push({from:m.sender_id, text:(plain? new TextDecoder().decode(plain):'<decrypt failed>')}); try{ await fetch('/chat/messages/'+encodeURIComponent(m.id)+'/read',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({read:true})}); }catch(_){ } }catch(e){ out.push({from:m.sender_id, text:'<error>'}); } } try{ const prev=outEl.textContent? JSON.parse(outEl.textContent):[]; outEl.textContent=JSON.stringify(prev.concat(out), null, 2); }catch(_){ outEl.textContent=JSON.stringify(out, null, 2); } } }catch(_){ } };
  }catch(_){ }
  }

  // Carmarket panel logic
  function cm_val(id){ return (document.getElementById(id).value||'').trim(); }
  async function cm_init(){ try{ await cm_load(); }catch(_){ } }
  async function cm_load(){ const u=new URLSearchParams(); const q=cm_val('cm_q'); if(q)u.set('q',q); const c=cm_val('cm_city'); if(c)u.set('city',c); const r=await fetch('/carmarket/listings?'+u.toString()); const arr=await r.json(); const tb=document.getElementById('cm_list'); tb.innerHTML=''; for(const x of arr){ const tr=document.createElement('tr'); tr.innerHTML = `<td>${x.id}</td><td>${x.title}</td><td>${x.city||''}</td><td><small>${x.owner_wallet_id||''}</small></td><td><button class='${DS.btn}' onclick='document.getElementById("cm_sel").value=${x.id}'>Select</button> <button class='${DS.btn}' onclick='cm_del(${x.id})'>Delete</button></td>`; tb.appendChild(tr);} }
  async function cm_create(){ const body={title:cm_val('cm_title'), city:cm_val('cm_city2')||null, make:cm_val('cm_make')||null, model:cm_val('cm_model')||null, year:(cm_val('cm_year')||null), price_cents: parseInt(cm_val('cm_price')||'0',10), description:cm_val('cm_desc')||null, owner_wallet_id:cm_val('cm_owner')||null}; const r=await fetch('/carmarket/listings',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)}); document.getElementById('cm_out').textContent = await r.text(); cm_load(); }
  async function cm_del(id){ if(!confirm('Delete listing '+id+'?')) return; await fetch('/carmarket/listings/'+id,{method:'DELETE'}); cm_load(); }
  async function cm_inquiry(){ const body={listing_id: parseInt(cm_val('cm_sel')||'0',10), name:cm_val('cm_iname'), phone:cm_val('cm_iphone')||null, message:cm_val('cm_imsg')||null}; const r=await fetch('/carmarket/inquiries',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)}); document.getElementById('cm_iout').textContent = await r.text(); }

  // Carrental panel logic
  function cr_val(id){ return (document.getElementById(id).value||'').trim(); }
  async function cr_init(){ try{ await cr_loadCars(); }catch(_){ } }
  async function cr_loadCars(){ const u=new URLSearchParams(); const q=cr_val('cr_q'); if(q)u.set('q',q); const c=cr_val('cr_city'); if(c)u.set('city',c); const r=await fetch('/carrental/cars?'+u.toString()); const arr=await r.json(); const tb=document.getElementById('cr_cars'); tb.innerHTML=''; for(const x of arr){ const tr=document.createElement('tr'); tr.innerHTML = `<td>${x.id}</td><td>${x.title}</td><td>${x.make||''} ${x.model||''}</td><td>${x.year||''}</td><td>${x.price_per_day_cents||''}/${x.price_per_hour_cents||''}</td><td><small>${x.owner_wallet_id||''}</small></td>`; tb.appendChild(tr);} }
  async function cr_quote(){ const body={car_id: parseInt(cr_val('cr_carid')||'0',10), from_iso:cr_val('cr_from'), to_iso:cr_val('cr_to')}; const r=await fetch('/carrental/quote',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)}); document.getElementById('cr_qout').textContent = await r.text(); }
  async function cr_book(){ const body={car_id: parseInt(cr_val('cr_carid')||'0',10), renter_name:cr_val('cr_name'), renter_phone:cr_val('cr_phone'), renter_wallet_id:cr_val('cr_rw')||null, from_iso:cr_val('cr_from'), to_iso:cr_val('cr_to'), confirm: document.getElementById('cr_confirm').checked}; const r=await fetch('/carrental/book',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)}); const t=await r.text(); document.getElementById('cr_bout').textContent=t; try{ const j=JSON.parse(t); document.getElementById('cr_bid').value=j.id; }catch(_){ } }
  async function cr_status(){ const id=cr_val('cr_bid'); if(!id){ alert('set booking id'); return; } const r=await fetch('/carrental/bookings/'+encodeURIComponent(id)); document.getElementById('cr_bstat').textContent = await r.text(); }
  async function cr_cancel(){ const id=cr_val('cr_bid'); if(!id){ alert('set booking id'); return; } const r=await fetch('/carrental/bookings/'+encodeURIComponent(id)+'/cancel',{method:'POST'}); document.getElementById('cr_bstat').textContent = await r.text(); }
  async function cr_confirm(){ const id=cr_val('cr_bid'); if(!id){ alert('set booking id'); return; } const r=await fetch('/carrental/bookings/'+encodeURIComponent(id)+'/confirm',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({confirm:true})}); document.getElementById('cr_bstat').textContent = await r.text(); }

  // RealEstate panel logic
  function re_val(id){ return (document.getElementById(id).value||'').trim(); }
  async function re_init(){ try{ await re_loadProps(); }catch(_){ } }
  async function re_loadProps(){ const u=new URLSearchParams(); const q=re_val('re_q'); if(q)u.set('q',q); const c=re_val('re_city'); if(c)u.set('city',c); const minp=re_val('re_minp'); if(minp)u.set('min_price',minp); const maxp=re_val('re_maxp'); if(maxp)u.set('max_price',maxp); const minb=re_val('re_minb'); if(minb)u.set('min_bedrooms',minb); const r=await fetch('/realestate/properties?'+u.toString()); const arr=await r.json(); const tb=document.getElementById('re_props'); tb.innerHTML=''; for(const p of arr){ const tr=document.createElement('tr'); tr.innerHTML=`<td>${p.id}</td><td>${p.title}</td><td>${p.city||''}</td><td>${p.price_cents}</td><td>${p.bedrooms||''}</td><td><small>${p.owner_wallet_id||''}</small></td><td><button class='${DS.btn}' onclick='document.getElementById("re_sel").value=${p.id}'>Select</button></td>`; tb.appendChild(tr); } }
  async function re_create(){ const body={title:re_val('re_title'), price_cents:parseInt(re_val('re_price')||'0',10), city:re_val('re_city2')||null, address:re_val('re_addr')||null, bedrooms:parseInt(re_val('re_beds')||'0',10)||null, bathrooms:parseInt(re_val('re_baths')||'0',10)||null, area_sqm:parseFloat(re_val('re_area')||'0')||null, owner_wallet_id:re_val('re_owner')||null}; const r=await fetch('/realestate/properties',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)}); document.getElementById('re_out').textContent = await r.text(); re_loadProps(); }
  async function re_update(){ const id=parseInt(re_val('re_pid')||'0',10); if(!id){ alert('set id'); return; } const body={title:re_val('re_title')||undefined, price_cents:(re_val('re_price')?parseInt(re_val('re_price'),10):undefined), city:re_val('re_city2')||undefined, address:re_val('re_addr')||undefined, bedrooms:(re_val('re_beds')?parseInt(re_val('re_beds'),10):undefined), bathrooms:(re_val('re_baths')?parseInt(re_val('re_baths'),10):undefined), area_sqm:(re_val('re_area')?parseFloat(re_val('re_area')):undefined), owner_wallet_id:re_val('re_owner')||undefined}; const r=await fetch('/realestate/properties/'+id,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)}); document.getElementById('re_out').textContent = await r.text(); re_loadProps(); }
  async function re_inquiry(){ const pid=parseInt(re_val('re_sel')||'0',10); const body={property_id:pid, name:re_val('re_iname'), phone:re_val('re_iphone')||null, message:re_val('re_imsg')||null}; const r=await fetch('/realestate/inquiries',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)}); document.getElementById('re_iout').textContent = await r.text(); }
  async function re_reserve(){ const pid=parseInt(re_val('re_sel')||'0',10); const body={property_id:pid, buyer_wallet_id:re_val('re_buyer'), deposit_cents:parseInt(re_val('re_dep')||'0',10)}; const r=await fetch('/realestate/reserve',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)}); document.getElementById('re_iout').textContent = await r.text(); }
  // Food panel logic (migrated)
  function fgi(id){ return (document.getElementById(id).value||'').trim(); }
  async function food_init(){ try{ await food_loadRests(); await food_loadOrdersToday(); }catch(_){ } }
  async function food_loadRests(){ const u=new URLSearchParams(); const q=fgi('f_q'); if(q)u.set('q',q); const c=fgi('f_city'); if(c)u.set('city',c); const r=await fetch('/food/restaurants?'+u.toString()); const arr=await r.json(); const tb=document.querySelector('#f_rests tbody'); tb.innerHTML=''; for(const x of arr){ const tr=document.createElement('tr'); tr.innerHTML = `<td>${x.id}</td><td>${x.name}</td><td>${x.city||''}</td><td><small>${x.owner_wallet_id||''}</small></td><td><button class='${DS.btn}' onclick='food_sel(${x.id})'>Select</button></td>`; tb.appendChild(tr); } }
  async function food_sel(id){ document.getElementById('f_rid').value = id; await food_loadMenu(); }
  async function food_loadMenu(){ const rid=parseInt(fgi('f_rid')||'0',10); if(!rid){ alert('set restaurant id'); return; } const r=await fetch('/food/restaurants/'+rid+'/menu'); const arr=await r.json(); const tb=document.querySelector('#f_menu tbody'); tb.innerHTML=''; for(const m of arr){ const tr=document.createElement('tr'); tr.innerHTML = `<td>${m.id}</td><td>${m.name}</td><td>${m.price_cents}</td><td><input id='fq_${m.id}' class='${DS.input}' value='1' style='width:70px' /></td>`; tb.appendChild(tr); } }
  async function food_placeOrder(){ const rid=parseInt(fgi('f_rid')||'0',10); if(!rid){ alert('choose restaurant'); return; } const qs=Array.from(document.querySelectorAll('#f_menu tbody input')); const items=[]; for(const q of qs){ const id=parseInt(q.id.split('_')[1],10); const qty=parseInt(q.value||'0',10); if(qty>0) items.push({menu_item_id:id, qty:qty}); } if(items.length===0){ alert('choose items'); return; } const body={restaurant_id:rid, customer_name:fgi('f_cname'), customer_phone:fgi('f_cphone'), customer_wallet_id:fgi('f_wallet')||null, items, confirm:document.getElementById('f_confirm').checked}; const r=await fetch('/food/orders',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)}); const t=await r.text(); document.getElementById('f_oout').textContent=t; try{ const j=JSON.parse(t); document.getElementById('f_oid').value=j.id; }catch(_){} }
  async function food_status(){ const id=fgi('f_oid'); if(!id){ alert('set order id'); return; } const r=await fetch('/food/orders/'+encodeURIComponent(id)); document.getElementById('f_os').textContent=await r.text(); }
  async function food_set(){ const id=fgi('f_oid'); if(!id){ alert('set order id'); return; } const st=fgi('f_st'); const r=await fetch('/food/orders/'+encodeURIComponent(id)+'/status',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({status:st})}); document.getElementById('f_os').textContent=await r.text(); }
  function food_showQr(){ const id=fgi('f_oid'); if(!id){ alert('set order id'); return; } const img=document.getElementById('f_qr'); if(!img) return; img.src='/food/orders/'+encodeURIComponent(id)+'/escrow_qr?ts='+Date.now(); img.style.display='block'; }
  async function food_loadOrdersToday(){ try{ const now=new Date(); const start=new Date(now.getFullYear(),now.getMonth(),now.getDate()); const end=new Date(now.getFullYear(),now.getMonth(),now.getDate()+1); const u=new URLSearchParams(); u.set('limit','200'); u.set('from_iso',start.toISOString()); u.set('to_iso',end.toISOString()); const r=await fetch('/food/orders?'+u.toString()); const arr=await r.json(); const tb=document.querySelector('#f_orders tbody'); if(!tb) return; tb.innerHTML=''; for(const o of arr){ const id=(o.id||'').toString(); const rid=(o.restaurant_id||'').toString(); const total=parseInt(o.total_cents||0,10); const status=(o.status||'').toString(); const esc=(o.escrow_status||'none').toString(); const tr=document.createElement('tr'); tr.innerHTML=`<td>${id}</td><td>${rid}</td><td>${total>0?total+' SYP':''}</td><td>${status}</td><td>${esc}</td><td><button class='${DS.btn}' onclick='food_qr("${id}")'>QR</button></td>`; tb.appendChild(tr); } }catch(_){ } }
  function food_qr(id){ if(!id){ alert('set order id'); return; } const img=document.getElementById('f_qr'); if(!img) return; document.getElementById('f_oid').value=id; img.src='/food/orders/'+encodeURIComponent(id)+'/escrow_qr?ts='+Date.now(); img.style.display='block'; }
  async function pay_quickPay(){ const from=pay_me(); const to=document.getElementById('qp_to3').value.trim(); const amt=parseInt(document.getElementById('qp_amt3').value||'0',10); if(!from||!to||(amt<=0)){ alert('fields missing'); return; } const ik='qp-'+Date.now().toString(36)+'-'+Math.random().toString(36).slice(2,6); const body=(to.startsWith('@')? {from_wallet_id:from,to_alias:to,amount_cents:amt}: {from_wallet_id:from,to_wallet_id:to,amount_cents:amt}); const r=await fetch('/payments/transfer',{method:'POST',headers:{'content-type':'application/json','Idempotency-Key':ik},body:JSON.stringify(body)}); if(!r.ok){ alert('pay failed'); } else { try{ if(navigator.vibrate) navigator.vibrate(35);}catch(e){} pay_addRecent(to); pay_loadWallet(); alert('paid'); } }
  function pay_flash(){ const f=document.getElementById('pay_flash'); if(!f) return; f.classList.remove('opacity-0'); f.classList.add('opacity-100'); setTimeout(()=>{ f.classList.add('opacity-0'); f.classList.remove('opacity-100'); }, 380); }
  async function pay_scan(){ try{ const el=document.getElementById('scanner3'); const html5QrCode = new Html5Qrcode(el.id); await html5QrCode.start({ facingMode: 'environment' }, { fps: 10, qrbox: 200 }, (t)=>{ try{ if(t && (t.startsWith('PAY|')||t.startsWith('ALIAS|'))){ const parts=t.split('|'); const m={}; for(const p of parts.slice(1)){ const kv=p.split('='); if(kv.length==2) m[kv[0]]=decodeURIComponent(kv[1]); } if(m['wallet']) document.getElementById('qp_to3').value=m['wallet']; if(m['name']) document.getElementById('qp_to3').value=m['name']; if(m['amount']) document.getElementById('qp_amt3').value=m['amount']; try{ if(navigator.vibrate) navigator.vibrate(20);}catch(e){} pay_flash(); html5QrCode.stop(); } }catch(_){ } }); }catch(e){ alert('scan error: '+e); } }
  function heroGradient(kyc){ const dark=document.documentElement.classList.contains('dark'); if(kyc==='pro') return dark? 'linear-gradient(90deg,#6d28d9,#f59e0b)' : 'linear-gradient(90deg,#7c3aed,#fbbf24)'; if(kyc==='plus') return dark? 'linear-gradient(90deg,#2563eb,#14b8a6)' : 'linear-gradient(90deg,#3b82f6,#22c55e)'; return dark? 'linear-gradient(90deg,#1e3a8a,#0ea5e9)' : 'linear-gradient(90deg,#4f46e5,#60a5fa)'; }
  async function pay_loadWallet(){ const w=pay_me(); const hero=document.getElementById('wallet_hero'); if(!w){ if(hero) hero.classList.add('hidden'); return; } try{ const r=await fetch('/payments/wallets/'+encodeURIComponent(w)); if(!r.ok){ if(hero) hero.classList.add('hidden'); return; } const j=await r.json(); document.getElementById('wh_wallet').textContent=w; const bal=(j.balance_cents||0)+' '+(j.currency||''); document.getElementById('wh_balance').textContent=bal; const kyc=((j.kyc_level||'')+'').toLowerCase()||'basic'; document.getElementById('wh_kyc').textContent='KYC: '+kyc; hero.style.background = heroGradient(kyc); hero.classList.remove('hidden'); }catch(_){ if(hero) hero.classList.add('hidden'); } }
  function pay_init(){ pay_me(); pay_renderRecent(); pay_loadFavs(); pay_loadReqs(); pay_loadWallet(); }

  // Merchant logic
  function merch_w(){ const el=document.getElementById('merch_wallet'); let v=el.value.trim(); if(!v){ v=localStorage.getItem('merchant_wid')||''; el.value=v; } return v; }
  function merch_saveWid(){ const v=document.getElementById('merch_wallet').value.trim(); localStorage.setItem('merchant_wid', v); document.getElementById('merch_status').textContent='Saved'; }
  function makeQR(text){ // small QR engine (GIF)
    function R(o){this.mode=4;this.data=o;this.parsedData=[];for(var r=0,l=this.data.length;r<l;r++){var t=[],h=this.data.charCodeAt(r);h>65536?(t[0]=240|(1835008&h)>>>18,t[1]=128|(258048&h)>>>12,t[2]=128|(4032&h)>>>6,t[3]=128|63&h):h>2048?(t[0]=224|(61440&h)>>>12,t[1]=128|(4032&h)>>>6,t[2]=128|63&h):h>128?(t[0]=192|(1984&h)>>>6,t[1]=128|63&h):t[0]=h,this.parsedData.push(t)}this.parsedData=Array.prototype.concat.apply([],this.parsedData),this.parsedData.length!=this.data.length&&(this.parsedData.unshift(191),this.parsedData.unshift(187),this.parsedData.unshift(239))}
    R.prototype.getLength=function(){return this.parsedData.length}; R.prototype.write=function(o){for(var r=0,l=this.parsedData.length;r<l;r++)o.put(this.parsedData[r],8)};
    function L(o,r){this.typeNumber=o,this.errorCorrectLevel=r,this.modules=null,this.moduleCount=0,this.dataCache=null,this.dataList=[]}
    L.prototype.addData=function(o){this.dataList.push(new R(o)),this.dataCache=null}; L.prototype.isDark=function(o,r){if(o<0||this.moduleCount<=o||r<0||this.moduleCount<=r)throw new Error(o+","+r);return this.modules[o][r]}; L.prototype.getModuleCount=function(){return this.moduleCount}; L.prototype.make=function(){this.makeImpl(!1,this.getBestMaskPattern())}; L.prototype.makeImpl=function(o,r){this.moduleCount=21,this.modules=new Array(this.moduleCount);for(var l=0;l<this.moduleCount;l++){this.modules[l]=new Array(this.moduleCount);for(var n=0;n<this.moduleCount;n++)this.modules[l][n]=null}this.setupPositionProbePattern(0,0),this.setupPositionProbePattern(this.moduleCount-7,0),this.setupPositionProbePattern(0,this.moduleCount-7),this.mapData(this.createData(this.typeNumber,this.errorCorrectLevel,r),r)}; L.prototype.setupPositionProbePattern=function(o,r){for(var l=-1;l<=7;l++)if(!(o+l<=-1||this.moduleCount<=o+l))for(var n=-1;n<=7;n++)r+n<=-1||this.moduleCount<=r+n||(this.modules[o+l][r+n]=l>=0&&l<=6&&(0==n||6==n)||n>=0&&n<=6&&(0==l||6==l)||l>=2&&l<=4&&n>=2&&n<=4)}; L.prototype.getBestMaskPattern=function(){return 0}; L.prototype.createData=function(o,r){for(var l=[],n=0;n<this.dataList.length;n++){var t=this.dataList[n];l.push(4),l.push(t.getLength()),l=l.concat(t.parsedData)}for(l.push(236),l.push(17),l.push(236),l.push(17);l.length<19;)l.push(0);return l.slice(0,19)}; L.prototype.mapData=function(o,r){for(var l=0;l<this.moduleCount;l++)for(var n=0;n<this.moduleCount;n++)if(null===this.modules[l][n]){var t=!((l+n)%3);this.modules[l][n]=t}}; L.prototype.createImgTag=function(o,r){o=o||2,r=r||0;var l=this.getModuleCount()*o+2*r,n=l,t='<img src="'+this.createDataURL(o,r)+'" width="'+l+'" height="'+n+'"/>';return t}; L.prototype.createDataURL=function(o,r){o=o||2,r=r||0;var l=this.getModuleCount()*o+2*r,n=l,t=o,h=r,e=h,i=Math.round(255);for(var a="GIF89a",u=String.fromCharCode,d=a+u(0)+u(0)+u(0)+u(0)+"\x00\x00\xF7\x00\x00",s=0;s<16;s++){var c=s?0:i;d+=u(c)+u(c)+u(c)}d+="\x2C\x00\x00\x00\x00"+u(0)+u(0)+"\x00\x00\x00\x00\x02";for(var f=1;f<l;f++){var g="";for(var p=0;p<n;p++){var m=this.isDark(Math.floor((p-r)/o),Math.floor((f-h)/o))?0:1;g+=m?"\x01":"\x00"}d+=u(g.length)+g}return 'data:image/gif;base64,'+btoa(d)}};
    const qr = new L(1,0); qr.addData(text); qr.make(); return qr.createImgTag(4,2);
  }
  function merch_genPayQR(){ const w=merch_w(); const a=parseInt(document.getElementById('merch_amount').value||'0',10); if(!w){ alert('wallet required'); return; } const p='PAY|wallet='+encodeURIComponent(w)+(a>0?('|amount='+a):''); document.getElementById('merch_payload').textContent=p; const el=document.getElementById('merch_qr'); el.innerHTML=makeQR(p); }
  function merch_genAliasQR(){ const h=document.getElementById('merch_alias').value.trim(); const a=parseInt(document.getElementById('merch_a_amount').value||'0',10); if(!h||!h.startsWith('@')){ alert('alias must start with @'); return; } const p='ALIAS|name='+encodeURIComponent(h)+(a>0?('|amount='+a):''); document.getElementById('merch_apayload').textContent=p; const el=document.getElementById('merch_aqr'); el.innerHTML=makeQR(p); }
  async function merch_refreshBal(){ const w=merch_w(); if(!w) return; const r=await fetch('/payments/wallets/'+encodeURIComponent(w)); document.getElementById('merch_bal').textContent=await r.text(); }
  async function merch_loadTxns(){ const w=merch_w(); if(!w) return; const r=await fetch('/payments/txns?wallet_id='+encodeURIComponent(w)+'&limit=20'); document.getElementById('merch_txns').textContent=await r.text(); }
  function merch_init(){ merch_w(); }

  // Taxi Driver logic
  function td_driver(){ const el=document.getElementById('td_driver'); let v=el.value.trim(); if(!v){ v=localStorage.getItem('td_driver')||''; el.value=v; } return v; }
  function td_save(){ const v=document.getElementById('td_driver').value.trim(); localStorage.setItem('td_driver', v); document.getElementById('td_out').textContent='saved'; }
  async function td_register(){ const body={name:document.getElementById('td_name').value.trim()||null, phone:document.getElementById('td_phone').value.trim()||null, vehicle_make:document.getElementById('td_make').value.trim()||null, vehicle_plate:document.getElementById('td_plate').value.trim()||null}; const r=await fetch('/taxi/drivers',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)}); const t=await r.text(); document.getElementById('td_out').textContent=t; try{ const j=JSON.parse(t); document.getElementById('td_driver').value=j.id; td_save(); }catch(_){ } }
  async function td_online(on){ const id=td_driver(); if(!id) return; const ep=on?'/taxi/drivers/'+encodeURIComponent(id)+'/online':'/taxi/drivers/'+encodeURIComponent(id)+'/offline'; const r=await fetch(ep,{method:'POST'}); document.getElementById('td_out').textContent=await r.text(); }
  async function td_setWallet(){ const id=td_driver(); const w=document.getElementById('td_wallet').value.trim(); if(!id||!w) return; const r=await fetch('/taxi/drivers/'+encodeURIComponent(id)+'/wallet',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({wallet_id:w})}); document.getElementById('td_out').textContent=await r.text(); }
  async function td_updateLoc(){ const id=td_driver(); const lat=parseFloat((document.getElementById('td_lat').value||'0')); const lon=parseFloat((document.getElementById('td_lon').value||'0')); if(!id) return; const r=await fetch('/taxi/drivers/'+encodeURIComponent(id)+'/location',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({lat:lat,lon:lon})}); document.getElementById('td_out').textContent=await r.text(); }
  let _td_tmr=null; async function td_track(){ if(_td_tmr) return; const id=td_driver(); if(!id){ alert('save driver id'); return; } if(!navigator.geolocation){ alert('no geolocation'); return; } _td_tmr=setInterval(()=>{ navigator.geolocation.getCurrentPosition(async (pos)=>{ try{ const lat=pos.coords.latitude, lon=pos.coords.longitude; document.getElementById('td_lat').value=lat.toFixed(6); document.getElementById('td_lon').value=lon.toFixed(6); const r=await fetch('/taxi/drivers/'+encodeURIComponent(id)+'/location',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({lat:lat,lon:lon})}); }catch(_){ } }, (_)=>{}, { enableHighAccuracy:true }); }, 3000); }
  function td_stopTrack(){ if(_td_tmr){ clearInterval(_td_tmr); _td_tmr=null; } }
  let _td_es=null; async function td_init(){ const id=td_driver(); if(id){ try{ _td_es = new EventSource('/taxi/driver/events?driver_id='+encodeURIComponent(id)); _td_es.onmessage = (ev)=>{ try{ const data=JSON.parse(ev.data); const el=document.getElementById('td_events'); el.textContent = (el.textContent + '\n' + JSON.stringify(data)); }catch(_){ } }; }catch(_){ } }
  }

  // Taxi Rider
  async function tr_req(){ const body={rider_phone:(document.getElementById('tr_phone').value||'').trim()||null, rider_wallet_id:(document.getElementById('tr_wallet').value||'').trim()||null, pickup_lat:parseFloat(document.getElementById('tr_plat').value||'0'), pickup_lon:parseFloat(document.getElementById('tr_plon').value||'0'), dropoff_lat:parseFloat(document.getElementById('tr_dlat').value||'0'), dropoff_lon:parseFloat(document.getElementById('tr_dlon').value||'0')}; const r=await fetch('/taxi/rides/request',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)}); const t=await r.text(); document.getElementById('tr_out').textContent=t; try{ const j=JSON.parse(t); document.getElementById('tr_ride').value=j.id||''; }catch(_){ } }
  async function tr_bookpay(){ const body={rider_phone:(document.getElementById('tr_phone').value||'').trim()||null, rider_wallet_id:(document.getElementById('tr_wallet').value||'').trim()||null, pickup_lat:parseFloat(document.getElementById('tr_plat').value||'0'), pickup_lon:parseFloat(document.getElementById('tr_plon').value||'0'), dropoff_lat:parseFloat(document.getElementById('tr_dlat').value||'0'), dropoff_lon:parseFloat(document.getElementById('tr_dlon').value||'0')}; const r=await fetch('/taxi/rides/book_pay',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)}); const t=await r.text(); document.getElementById('tr_out').textContent=t; try{ const j=JSON.parse(t); document.getElementById('tr_ride').value=j.id||''; }catch(_){ } }
  async function tr_status(){ const id=document.getElementById('tr_ride').value.trim(); if(!id){ return; } const r=await fetch('/taxi/rides/'+encodeURIComponent(id)); document.getElementById('tr_out').textContent=await r.text(); }
  async function tr_cancel(){ const id=document.getElementById('tr_ride').value.trim(); if(!id){ return; } const r=await fetch('/taxi/rides/'+encodeURIComponent(id)+'/cancel',{method:'POST'}); document.getElementById('tr_out').textContent=await r.text(); }

  // Taxi Admin
  async function ta_loadDrivers(){ const r=await fetch('/taxi/drivers?status=online&limit=100'); const arr=await r.json(); const box=document.getElementById('ta_drivers'); box.innerHTML=''; for(const d of arr){ const row=document.createElement('div'); row.className='flex items-center justify-between border-b border-gray-200 dark:border-gray-700 py-1'; row.innerHTML=`<span>${d.id} <small class=\"text-gray-500\">${d.name||''} ${d.vehicle_plate||''}</small></span>`; box.appendChild(row); } try{ await ta_renderDriversOnMap(); }catch(_){ } }
  async function ta_loadRides(){ const st=document.getElementById('ta_rstatus').value; const qs=st?('?status='+encodeURIComponent(st)) : ''; const r=await fetch('/taxi/rides'+qs); const arr=await r.json(); const box=document.getElementById('ta_rides'); box.innerHTML=''; for(const rd of arr){ const row=document.createElement('div'); row.className='flex items-center justify-between border-b border-gray-200 dark:border-gray-700 py-1'; const canCenter=(rd.pickup_lat&&rd.pickup_lon); row.innerHTML=`<span>${rd.id} <small class=\"text-gray-500\">${rd.status||''}</small> <span class=\"ml-2\">${(rd.pickup_lat||'')},${(rd.pickup_lon||'')} → ${(rd.dropoff_lat||'')},${(rd.dropoff_lon||'')}</span></span><div>${canCenter?`<button class=\"${DS.btn}\" onclick=\"ta_focus(${rd.pickup_lat},${rd.pickup_lon})\">Center</button>`:''}</div>`; box.appendChild(row); } try{ ta_renderRidesOnMap(arr); ta_updateBounds(); }catch(_){ } }
  function ta_focus(lat, lon){ try{ if(ta_gm){ ta_map.setZoom(14); ta_map.panTo({lat:parseFloat(lat),lng:parseFloat(lon)}); } else { ta_map.setView([parseFloat(lat),parseFloat(lon)],14); } }catch(_){ } }
  async function ta_assign(){ const rid=(document.getElementById('ta_ride').value||'').trim(); const did=(document.getElementById('ta_driver_id').value||'').trim(); if(!rid||!did){ alert('ride_id and driver_id required'); return; } const r=await fetch('/taxi/rides/'+encodeURIComponent(rid)+'/assign?driver_id='+encodeURIComponent(did),{method:'POST'}); document.getElementById('ta_out').textContent=await r.text(); }

  // Taxi Driver map
  let td_map=null, td_gm=false, td_marker=null;
  function td_mapSetup(){ try{ if(td_map) return; const el=document.getElementById('td_map'); if(!el) return; const lat=parseFloat(document.getElementById('td_lat').value||'33.5138')||33.5138; const lon=parseFloat(document.getElementById('td_lon').value||'36.2765')||36.2765; if(window.google && window.google.maps){ td_gm=true; td_map=new google.maps.Map(el,{center:{lat:lat,lng:lon}, zoom:13}); td_marker=new google.maps.Marker({position:{lat:lat,lng:lon}, map:td_map}); } else { td_gm=false; td_map=L.map('td_map').setView([lat,lon],13); L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',{maxZoom:19, attribution:'© OpenStreetMap'}).addTo(td_map); td_marker=L.marker([lat,lon]).addTo(td_map); } }catch(_){ } }
  function td_mapUpdate(lat, lon){ try{ if(td_gm){ td_marker.setPosition({lat:lat,lng:lon}); td_map.setCenter({lat:lat,lng:lon}); } else { td_marker.setLatLng([lat,lon]); td_map.setView([lat,lon]); } }catch(_){ } }
  const __td_updateLoc_orig = td_updateLoc;
  td_updateLoc = async function(){ await __td_updateLoc_orig(); const lat=parseFloat(document.getElementById('td_lat').value||'0'); const lon=parseFloat(document.getElementById('td_lon').value||'0'); if(lat&&lon){ td_mapUpdate(lat,lon); } };
  function td_center(){ try{ const lat=parseFloat(document.getElementById('td_lat').value||'0'); const lon=parseFloat(document.getElementById('td_lon').value||'0'); if(lat&&lon){ td_mapUpdate(lat,lon); } }catch(_){ } }
  const __td_track_orig = td_track;
  td_track = async function(){ await __td_track_orig(); };

  // Taxi Rider map
  let tr_map=null, tr_gm=false, tr_pick=null, tr_drop=null;
  function tr_mapSetup(){ try{ if(tr_map) return; const el=document.getElementById('tr_map'); if(!el) return; const plat=parseFloat(document.getElementById('tr_plat').value||'33.5138')||33.5138; const plon=parseFloat(document.getElementById('tr_plon').value||'36.2765')||36.2765; if(window.google && window.google.maps){ tr_gm=true; tr_map=new google.maps.Map(el,{center:{lat:plat,lng:plon}, zoom:12}); tr_pick=new google.maps.Marker({position:{lat:plat,lng:plon}, map:tr_map, label:'P'}); } else { tr_gm=false; tr_map=L.map('tr_map').setView([plat,plon],12); L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',{maxZoom:19, attribution:'© OpenStreetMap'}).addTo(tr_map); tr_pick=L.marker([plat,plon]).addTo(tr_map); } tr_updateFromInputs(); ['tr_plat','tr_plon','tr_dlat','tr_dlon'].forEach(id=>{ const el=document.getElementById(id); if(el){ el.addEventListener('input', tr_updateFromInputs); } }); }catch(_){ } }
  function tr_updateFromInputs(){ try{ const plat=parseFloat(document.getElementById('tr_plat').value||'0'); const plon=parseFloat(document.getElementById('tr_plon').value||'0'); const dlat=parseFloat(document.getElementById('tr_dlat').value||'0'); const dlon=parseFloat(document.getElementById('tr_dlon').value||'0'); if(plat&&plon){ if(tr_gm){ tr_pick.setPosition({lat:plat,lng:plon}); tr_map.setCenter({lat:plat,lng:plon}); } else { tr_pick.setLatLng([plat,plon]); tr_map.setView([plat,plon]); } } if(dlat&&dlon){ if(!tr_drop){ if(tr_gm){ tr_drop=new google.maps.Marker({position:{lat:dlat,lng:dlon}, map:tr_map, label:'D'}); } else { tr_drop=L.marker([dlat,dlon]).addTo(tr_map); } } else { if(tr_gm){ tr_drop.setPosition({lat:dlat,lng:dlon}); } else { tr_drop.setLatLng([dlat,dlon]); } } } }catch(_){ } }

  // Taxi Admin map helpers
  let ta_map=null, ta_gm=false, ta_drvMarkers=[], ta_rideMarkers=[], ta_drvLayer=null, ta_rideLayer=null;
  function ta_updateBounds(){ try{ const pts=[]; if(ta_gm){ for(const m of ta_drvMarkers){ try{ const p=m.getPosition(); if(p) pts.push({lat:p.lat(), lng:p.lng()}); }catch(_){ } } for(const m of ta_rideMarkers){ try{ const p=m.getPosition(); if(p) pts.push({lat:p.lat(), lng:p.lng()}); }catch(_){ } } if(pts.length>0){ const b=new google.maps.LatLngBounds(); for(const p of pts){ b.extend(p); } ta_map.fitBounds(b); } } else { try{ const d=[], r=[]; if(ta_drvLayer){ ta_drvLayer.eachLayer(l=>{ try{ d.push(l.getLatLng()); }catch(_){ } }); } if(ta_rideLayer){ ta_rideLayer.eachLayer(l=>{ try{ r.push(l.getLatLng()); }catch(_){ } }); } const all=d.concat(r); if(all.length>0){ ta_map.fitBounds(L.latLngBounds(all), {padding:[20,20]}); } }catch(_){ } } }catch(_){ } }
  function ta_mapSetup(){ try{ if(ta_map) return; const el=document.getElementById('ta_map'); if(!el) return; const lat=33.5138, lon=36.2765; if(window.google && window.google.maps){ ta_gm=true; ta_map=new google.maps.Map(el,{center:{lat:lat,lng:lon}, zoom:11, mapTypeControl:false}); try{ const saved=JSON.parse(localStorage.getItem('app_taxi_admin_map')||'null'); if(saved&&saved.lat&&saved.lng&&saved.zoom){ ta_map.setCenter({lat:saved.lat,lng:saved.lng}); ta_map.setZoom(saved.zoom); } }catch(_){ } ta_map.addListener('idle', ta_saveView); } else { ta_gm=false; ta_map=L.map('ta_map').setView([lat,lon],11); L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',{maxZoom:19, attribution:'© OpenStreetMap'}).addTo(ta_map); try{ const saved=JSON.parse(localStorage.getItem('app_taxi_admin_map')||'null'); if(saved&&saved.lat&&saved.lng&&saved.zoom){ ta_map.setView([saved.lat,saved.lng], saved.zoom); } }catch(_){ } if(L.markerClusterGroup){ ta_drvLayer=L.markerClusterGroup(); ta_rideLayer=L.markerClusterGroup(); ta_map.addLayer(ta_drvLayer); ta_map.addLayer(ta_rideLayer); } else { ta_drvLayer=L.layerGroup().addTo(ta_map); ta_rideLayer=L.layerGroup().addTo(ta_map); } try{ ta_map.on('moveend', ta_saveView); }catch(_){ } } }catch(_){ }
  }
  function ta_fitDrivers(){ try{ if(ta_gm){ const b=new google.maps.LatLngBounds(); for(const m of ta_drvMarkers){ try{ const p=m.getPosition(); if(p) b.extend(p); }catch(_){ } } if(!b.isEmpty()) ta_map.fitBounds(b); } else { const pts=[]; if(ta_drvLayer&&ta_drvLayer.eachLayer){ ta_drvLayer.eachLayer(l=>{ try{ pts.push(l.getLatLng()); }catch(_){ } }); } if(pts.length){ ta_map.fitBounds(L.latLngBounds(pts), {padding:[30,30]}); } } }catch(_){ } }
  function ta_fitRides(){ try{ if(ta_gm){ const b=new google.maps.LatLngBounds(); for(const m of ta_rideMarkers){ try{ const p=m.getPosition(); if(p) b.extend(p); }catch(_){ } } if(!b.isEmpty()) ta_map.fitBounds(b); } else { const pts=[]; if(ta_rideLayer&&ta_rideLayer.eachLayer){ ta_rideLayer.eachLayer(l=>{ try{ pts.push(l.getLatLng()); }catch(_){ } }); } if(pts.length){ ta_map.fitBounds(L.latLngBounds(pts), {padding:[30,30]}); } } }catch(_){ } }
  // persist map view across visits
  function ta_saveView(){ try{ if(ta_gm){ const c=ta_map.getCenter(); localStorage.setItem('app_taxi_admin_map', JSON.stringify({lat:c.lat(),lng:c.lng(),zoom:ta_map.getZoom()})); } else { const c=ta_map.getCenter(); localStorage.setItem('app_taxi_admin_map', JSON.stringify({lat:c.lat,lng:c.lng,zoom:ta_map.getZoom()})); } }catch(_){ } }
  async function ta_renderDriversOnMap(){ try{ const r=await fetch('/taxi/drivers?status=online&limit=100'); const arr=await r.json(); if(ta_gm){ for(const m of ta_drvMarkers){ try{ m.setMap(null);}catch(_){}} ta_drvMarkers=[]; for(const d of arr){ if(d.lat && d.lon){ ta_drvMarkers.push(new google.maps.Marker({position:{lat:parseFloat(d.lat), lng:parseFloat(d.lon)}, map:ta_map, title:d.name||('Driver '+d.id)})); } } try{ if(window.markerClusterer && ta_drvMarkers.length){ if(window._ta_gClusterD){ try{ window._ta_gClusterD.clearMarkers(); }catch(_){ } } window._ta_gClusterD = new markerClusterer.MarkerClusterer({map: ta_map, markers: ta_drvMarkers}); } }catch(_){ } } else { try{ if(ta_drvLayer && ta_drvLayer.clearLayers) ta_drvLayer.clearLayers(); }catch(_){ } for(const d of arr){ if(d.lat && d.lon){ if(ta_drvLayer && ta_drvLayer.addLayer){ L.marker([d.lat, d.lon]).addTo(ta_drvLayer); } else { L.marker([d.lat, d.lon]).addTo(ta_map); } } } } }catch(_){ }
  }
  function ta_renderRidesOnMap(arr){ try{ if(ta_gm){ for(const m of ta_rideMarkers){ try{ m.setMap(null);}catch(_){}} ta_rideMarkers=[]; for(const rd of arr){ if(rd.pickup_lat && rd.pickup_lon){ ta_rideMarkers.push(new google.maps.Marker({position:{lat:parseFloat(rd.pickup_lat), lng:parseFloat(rd.pickup_lon)}, map:ta_map, icon:{path:google.maps.SymbolPath.CIRCLE, fillColor:'#06f', fillOpacity:0.9, strokeColor:'#06f', strokeWeight:1, scale:6}, title:'Pickup '+rd.id})); } } try{ if(window.markerClusterer && ta_rideMarkers.length){ if(window._ta_gClusterR){ try{ window._ta_gClusterR.clearMarkers(); }catch(_){ } } window._ta_gClusterR = new markerClusterer.MarkerClusterer({map: ta_map, markers: ta_rideMarkers}); } }catch(_){ } } else { try{ if(ta_rideLayer && ta_rideLayer.clearLayers) ta_rideLayer.clearLayers(); }catch(_){ } for(const rd of arr){ if(rd.pickup_lat && rd.pickup_lon){ if(ta_rideLayer && ta_rideLayer.addLayer){ L.circleMarker([rd.pickup_lat, rd.pickup_lon], {radius:5,color:'#06f'}).addTo(ta_rideLayer); } else { L.circleMarker([rd.pickup_lat, rd.pickup_lon], {radius:5,color:'#06f'}).addTo(ta_map); } } } } }catch(_){ }
  }
  // periodic refresh while panel visible
  setInterval(()=>{ try{ const vis = document.getElementById('panel-taxi-admin') && !document.getElementById('panel-taxi-admin').classList.contains('hidden'); if(vis){ ta_renderDriversOnMap(); } }catch(_){ } }, 5000);
  </script>
</body></html>
"""
    return HTMLResponse(content=html.replace('%%GMAPS_TAG%%', gmaps_tag))


@app.get("/upstreams/health")
def upstreams_health():
    out: dict[str, Any] = {}
    # Food is internal-only in monolith mode; there is no BASE_URL fallback.
    if _use_food_internal() and _FOOD_INTERNAL_AVAILABLE:
        out["food"] = {
            "status_code": 200,
            "body": {"status": "OK (internal)", "internal": True},
            "mode": "internal",
        }
    else:
        out["food"] = {"error": "food internal not available", "mode": "internal", "internal": False}
    for name, base in {
        "payments": PAYMENTS_BASE,
        "taxi": TAXI_BASE,
        "bus": BUS_BASE,
        "carmarket": CARMARKET_BASE,
        "carrental": CARRENTAL_BASE,
        "realestate": REALESTATE_BASE,
        "stays": STAYS_BASE,
        "freight": FREIGHT_BASE,
        "chat": CHAT_BASE,
        "agriculture": AGRICULTURE_BASE,
        "commerce": COMMERCE_BASE,
        "doctors": DOCTORS_BASE,
        "flights": FLIGHTS_BASE,
        "jobs": JOBS_BASE,
        "livestock": LIVESTOCK_BASE,
    }.items():
        if not base:
            if _ENV_LOWER == "test":
                out[name] = {"error": "BASE_URL not set", "mode": "test", "internal": False}
                continue
            internal_ok = False
            mode = "internal"
            try:
                if name == "payments":
                    internal_ok = _use_pay_internal()
                elif name == "taxi":
                    internal_ok = _use_taxi_internal()
                elif name == "bus":
                    internal_ok = _use_bus_internal()
                elif name == "carmarket":
                    internal_ok = _use_carmarket_internal()
                elif name == "carrental":
                    internal_ok = _use_carrental_internal()
                elif name == "stays":
                    internal_ok = _use_stays_internal()
                elif name == "freight":
                    internal_ok = _use_freight_internal()
                elif name == "chat":
                    internal_ok = _use_chat_internal()
                elif name == "commerce":
                    internal_ok = _use_commerce_internal()
                elif name == "doctors":
                    internal_ok = _use_doctors_internal()
                elif name == "flights":
                    internal_ok = _use_flights_internal()
                elif name == "jobs":
                    internal_ok = _use_jobs_internal()
                elif name == "agriculture":
                    internal_ok = _use_agriculture_internal()
                elif name == "livestock":
                    internal_ok = _use_livestock_internal()
            except Exception:
                internal_ok = False

            # In monolith mode, several services are mounted directly even
            # wenn keine eigene BASE_URL konfiguriert ist.
            if name in ("taxi", "realestate", "carmarket", "carrental") and not internal_ok:
                internal_ok = True
                mode = "monolith"
            # If we have a working internal/monolith integration, report this as OK
            # instead of an error so System Status doesn't show everything in red.
            if internal_ok:
                out[name] = {
                    "status_code": 200,
                    "body": {
                        "status": f"OK ({mode})",
                        "internal": True,
                    },
                    "mode": mode,
                }
            else:
                # No BASE_URL and no internal wiring: this upstream is effectively missing.
                detail = "BASE_URL not set"
                out[name] = {"error": detail, "mode": mode, "internal": False}
            continue
        url = base.rstrip("/") + "/health"
        try:
            r = httpx.get(url, timeout=5.0)
            out[name] = {"status_code": r.status_code, "body": r.json() if r.headers.get("content-type", "").startswith("application/json") else r.text}
        except Exception as e:
            out[name] = {"error": str(e)}
    return out


@app.get("/admin/overview", response_class=HTMLResponse)
def admin_overview_page():
    # Legacy Admin HTML overview removed – please use Shamell instead.
    return _legacy_console_removed_page("Shamell · Admin overview")
    html = """
<!doctype html>
<html><head><meta name=viewport content="width=device-width, initial-scale=1" />
<title>Shamell Admin Overview</title>
<link rel="icon" href="/icons/payments.svg" />
<style>
  body{font-family:sans-serif;margin:20px;max-width:960px;color:#0f172a;}
  h1{margin-bottom:4px;}
  table{border-collapse:collapse;width:100%;margin-top:12px;}
  th,td{padding:6px 8px;border-bottom:1px solid #e5e7eb;font-size:13px;text-align:left;}
  th{background:#f9fafb;font-weight:600;}
  .ok{color:#16a34a;font-weight:600;}
  .err{color:#b91c1c;font-weight:600;}
  .tag{display:inline-block;padding:2px 6px;border-radius:999px;font-size:11px;background:#e5e7eb;margin-right:4px;}
  .links a{margin-right:8px;font-size:13px;}
  code{font-size:12px;background:#f3f4f6;padding:2px 4px;border-radius:4px;}
  .muted{color:#6b7280;font-size:12px;}
.pill{display:inline-block;padding:2px 8px;border-radius:999px;font-size:11px;background:#e0f2fe;color:#0369a1;}
</style>
</head><body>
<h1>Shamell Admin Overview</h1>
<div class="muted">Monolith + upstream health, Links zu Admin-UIs.</div>

<div style="margin-top:14px" class="links">
  <span class="pill">Admin-UIs</span>
  <a href="/taxi/admin">Taxi Admin</a>
  <a href="/payments-debug">Payments Debug</a>
  <a href="/merchant">Merchant POS</a>
  <a href="/ops-admin/">Ops Admin (Flutter)</a>
  <a href="/admin/metrics">Metrics</a>
  <a href="/admin/guardrails">Guardrails</a>
  <a href="/admin/quality">Quality</a>
</div>

<div style="margin-top:14px" class="muted">
  Backend-Heartbeat: <code id="bg_tick">n/a</code>
</div>

<table id="tbl">
  <thead><tr><th>Service</th><th>Status</th><th>Details</th></tr></thead>
  <tbody id="tbody"><tr><td colspan="3" class="muted">Lade /upstreams/health ...</td></tr></tbody>
</table>

<script>
async function loadHealth(){
  try{
    const r = await fetch('/upstreams/health');
    const j = await r.json();
    const tbody = document.getElementById('tbody');
    tbody.innerHTML='';
    const names = Object.keys(j).sort();
    if(names.length===0){ tbody.innerHTML='<tr><td colspan=3 class="muted">Keine Upstreams konfiguriert</td></tr>'; return; }
    for(const name of names){
      const row = document.createElement('tr');
      const cellName = document.createElement('td');
      cellName.textContent = name;
      const cellStatus = document.createElement('td');
      const cellDetail = document.createElement('td');
      const val = j[name] || {};
      let ok=false, txt='n/a';
      if('status_code' in val){ ok = (val.status_code>=200 && val.status_code<300); txt = 'HTTP '+val.status_code; }
      else if('error' in val){ ok=false; txt = val.error; }
      const span=document.createElement('span');
      span.textContent = ok? 'OK' : 'ERROR';
      span.className = ok? 'ok' : 'err';
      cellStatus.appendChild(span);
      cellDetail.textContent = txt;
      row.appendChild(cellName);
      row.appendChild(cellStatus);
      row.appendChild(cellDetail);
      tbody.appendChild(row);
    }
  }catch(e){
    const tbody = document.getElementById('tbody');
    tbody.innerHTML='<tr><td colspan=3 class="err">Error while loading: '+e+'</td></tr>';
  }
}
function renderBgTick(){
  fetch('/metrics?limit=1').then(r=>r.json()).then(j=>{
    // BG tick is maintained server-side in _BG_STATS; here we only show time when present.
    // We use /metrics only as a "ping" proxy; the items themselves are optional.
  }).catch(()=>{});
  try{
    const el=document.getElementById('bg_tick');
    el.textContent = (window.__bg_tick || 'active (see server logs)');
  }catch(_){}
}
loadHealth();
renderBgTick();
setInterval(loadHealth, 30000);
</script>
</body></html>
"""
    return HTMLResponse(content=html)


@app.get("/wallets/{wallet_id}")
def get_wallet(wallet_id: str):
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
        r = httpx.get(url, timeout=5.0)
        return r.json() if r.headers.get("content-type", "").startswith("application/json") else {"raw": r.text, "status_code": r.status_code}
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/wallets/{wallet_id}/snapshot")
def wallet_snapshot(
    wallet_id: str,
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
        wallet = get_wallet(wallet_id)
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

from datetime import datetime, timezone


@app.get("/payments/txns")
def payments_txns(wallet_id: str, limit: int = 20, dir: str = "", kind: str = "", from_iso: str = "", to_iso: str = ""):
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
            r = httpx.get(url, timeout=10.0)
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


# --- Chat internal service (monolith mode) ---
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
        register as _chat_register,
        get_device as _chat_get_device,
        send_message as _chat_send_message,
        inbox as _chat_inbox,
        mark_read as _chat_mark_read,
        register_push_token as _chat_register_push,
        set_block as _chat_set_block,
    )
    _CHAT_INTERNAL_AVAILABLE = True
except Exception:
    _ChatSession = None  # type: ignore[assignment]
    _chat_engine = None  # type: ignore[assignment]
    _CHAT_INTERNAL_AVAILABLE = False


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
    return not bool(CHAT_BASE)


def _chat_internal_session():
    if not _CHAT_INTERNAL_AVAILABLE or _ChatSession is None or _chat_engine is None:  # type: ignore[truthy-function]
        raise RuntimeError("Chat internal service not available")
    return _ChatSession(_chat_engine)  # type: ignore[call-arg]


@app.post("/chat/devices/register")
async def chat_register(req: Request):
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
                creq = _ChatRegisterReq(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _chat_internal_session() as s:
                return _chat_register(req=creq, s=s)
        r = httpx.post(_chat_url("/devices/register"), json=body, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/chat/devices/{device_id}")
def chat_get_device(device_id: str):
    try:
        if _use_chat_internal():
            if not _CHAT_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="chat internal not available")
            with _chat_internal_session() as s:
                return _chat_get_device(device_id=device_id, s=s)
        r = httpx.get(_chat_url(f"/devices/{device_id}"), timeout=10)
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
                return _chat_register_push(device_id=device_id, req=preq, s=s)  # type: ignore[arg-type]
        r = httpx.post(_chat_url(f"/devices/{device_id}/push_token"), json=body, timeout=10)
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
                return _chat_set_block(device_id=device_id, req=breq, s=s)  # type: ignore[arg-type]
        r = httpx.post(_chat_url(f"/devices/{device_id}/block"), json=body, timeout=10)
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
                return _chat_send_message(req=sreq, s=s)
        r = httpx.post(_chat_url("/messages/send"), json=body, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/chat/messages/inbox")
def chat_inbox(device_id: str, since_iso: str = "", limit: int = 50):
    params = {"device_id": device_id, "limit": max(1, min(limit, 200))}
    if since_iso:
        params["since_iso"] = since_iso
    try:
        if _use_chat_internal():
            if not _CHAT_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="chat internal not available")
            with _chat_internal_session() as s:
                sin = since_iso or None
                return _chat_inbox(device_id=device_id, since_iso=sin, limit=limit, s=s)
        r = httpx.get(_chat_url("/messages/inbox"), params=params, timeout=10)
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
                return _chat_mark_read(mid=mid, req=rreq, s=s)
        r = httpx.post(_chat_url(f"/messages/{mid}/read"), json=body, timeout=10)
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
        did = params.get("device_id")
        since_iso = params.get("since_iso") or ""
        last_iso = since_iso
        while True:
            try:
                if _use_chat_internal():
                    if not _CHAT_INTERNAL_AVAILABLE:
                        raise RuntimeError("chat internal not available")
                    q_since = last_iso or None
                    with _chat_internal_session() as s:
                        arr = _chat_inbox(device_id=did, since_iso=q_since, limit=100, s=s)
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
                    r = httpx.get(_chat_url("/messages/inbox"), params=qparams, timeout=10)
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
    except WebSocketDisconnect:
        return


# ---- Freight / Courier proxies ----
def _freight_url(path: str) -> str:
    if not FREIGHT_BASE:
        raise HTTPException(status_code=500, detail="FREIGHT_BASE_URL not configured")
    return FREIGHT_BASE.rstrip("/") + path


def _courier_url(path: str) -> str:
    if not COURIER_BASE:
        raise HTTPException(status_code=500, detail="COURIER_BASE_URL not configured")
    return COURIER_BASE.rstrip("/") + path


# --- Freight internal service (monolith mode) ---
_FREIGHT_INTERNAL_AVAILABLE = False
try:
    from sqlalchemy.orm import Session as _FreightSession  # type: ignore[import]
    from apps.freight.app import main as _freight_main  # type: ignore[import]
    from apps.freight.app.main import (  # type: ignore[import]
        engine as _freight_engine,
        get_session as _freight_get_session,
        QuoteReq as _FreightQuoteReq,
        BookReq as _FreightBookReq,
        ShipmentOut as _FreightShipmentOut,
        StatusReq as _FreightStatusReq,
        quote as _freight_quote,
        book as _freight_book,
        get_shipment as _freight_get_shipment,
        set_status as _freight_set_status,
    )
    _FREIGHT_INTERNAL_AVAILABLE = True
except Exception:
    _FreightSession = None  # type: ignore[assignment]
    _freight_engine = None  # type: ignore[assignment]
    _FREIGHT_INTERNAL_AVAILABLE = False


def _use_freight_internal() -> bool:
    if _force_internal(_FREIGHT_INTERNAL_AVAILABLE):
        return True
    mode = os.getenv("FREIGHT_INTERNAL_MODE", "auto").lower()
    if mode == "off":
        return False
    if not _FREIGHT_INTERNAL_AVAILABLE:
        return False
    if mode == "on":
        return True
    return not bool(FREIGHT_BASE)


def _freight_internal_session():
    if not _FREIGHT_INTERNAL_AVAILABLE or _FreightSession is None or _freight_engine is None:  # type: ignore[truthy-function]
        raise RuntimeError("Freight internal service not available")
    return _FreightSession(_freight_engine)  # type: ignore[call-arg]


@app.post("/freight/quote")
async def freight_quote(req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        if _use_freight_internal():
            if not _FREIGHT_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="freight internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                qreq = _FreightQuoteReq(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            # quote() has no DB, so no need for session
            return _freight_quote(req=qreq)
        r = httpx.post(_freight_url("/quote"), json=body, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/courier/quote")
async def courier_quote(req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        r = httpx.post(_courier_url("/quote"), json=body, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/freight/book")
async def freight_book(request: Request):
    try:
        body = await request.json()
    except Exception:
        body = None
    headers: dict[str, str] = {}
    try:
        ikey = request.headers.get("Idempotency-Key")
    except Exception:
        ikey = None
    if ikey:
        headers["Idempotency-Key"] = ikey
    try:
        if _use_freight_internal():
            if not _FREIGHT_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="freight internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                breq = _FreightBookReq(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _freight_internal_session() as s:
                return _freight_book(request=request, req=breq, idempotency_key=ikey, s=s)
        r = httpx.post(_freight_url("/book"), json=body, headers=headers, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/courier/book")
async def courier_book(req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    headers: dict[str, str] = {}
    try:
        ikey = req.headers.get("Idempotency-Key")
    except Exception:
        ikey = None
    if ikey:
        headers["Idempotency-Key"] = ikey
    try:
        r = httpx.post(_courier_url("/orders"), json=body, headers=headers, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/freight/shipments/{sid}")
def freight_get_shipment(sid: str):
    try:
        if _use_freight_internal():
            if not _FREIGHT_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="freight internal not available")
            with _freight_internal_session() as s:
                return _freight_get_shipment(sid=sid, s=s)
        r = httpx.get(_freight_url(f"/shipments/{sid}"), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/courier/shipments/{sid}")
def courier_get_shipment(sid: str):
    try:
        r = httpx.get(_courier_url(f"/track/{sid}"), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/freight/shipments/{sid}/status")
async def freight_set_status(sid: str, req: Request):
    _require_operator(req, "freight")
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        if _use_freight_internal():
            if not _FREIGHT_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="freight internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                sreq = _FreightStatusReq(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _freight_internal_session() as s:
                return _freight_set_status(sid=sid, req=sreq, s=s)
        r = httpx.post(_freight_url(f"/shipments/{sid}/status"), json=body, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/courier/shipments/{sid}/status")
async def courier_set_status(sid: str, req: Request):
    _require_operator(req, "freight")
    try:
        body = await req.json()
    except Exception:
        body = None
    headers: dict[str, str] = {}
    try:
        ikey = req.headers.get("Idempotency-Key")
    except Exception:
        ikey = None
    if ikey:
        headers["Idempotency-Key"] = ikey
    try:
        r = httpx.post(_courier_url(f"/orders/{sid}/status"), json=body, headers=headers, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/courier/track/{token}")
def courier_track_public(token: str):
    try:
        r = httpx.get(_courier_url(f"/track/public/{token}"), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/courier/orders/{oid}/contact")
async def courier_contact(oid: str, req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        r = httpx.post(_courier_url(f"/orders/{oid}/contact"), json=body, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/courier/orders/{oid}/reschedule")
async def courier_reschedule(oid: str, req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        r = httpx.post(_courier_url(f"/orders/{oid}/reschedule"), json=body, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/courier/stats")
def courier_stats(carrier: str | None = None, partner_id: str | None = None, service_type: str | None = None):
    params = {}
    if carrier:
        params["carrier"] = carrier
    if partner_id:
        params["partner_id"] = partner_id
    if service_type:
        params["service_type"] = service_type
    headers = {}
    if COURIER_ADMIN_TOKEN:
        headers["X-Admin-Token"] = COURIER_ADMIN_TOKEN
    try:
        r = httpx.get(_courier_url("/stats"), params=params, headers=headers, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/courier/stats/export")
def courier_stats_export(carrier: str | None = None, partner_id: str | None = None, service_type: str | None = None):
    params = {}
    if carrier:
        params["carrier"] = carrier
    if partner_id:
        params["partner_id"] = partner_id
    if service_type:
        params["service_type"] = service_type
    headers = {}
    if COURIER_ADMIN_TOKEN:
        headers["X-Admin-Token"] = COURIER_ADMIN_TOKEN
    try:
        r = httpx.get(_courier_url("/stats/export"), params=params, headers=headers, timeout=10)
        resp = Response(content=r.content, media_type="text/csv")
        cd = r.headers.get("Content-Disposition")
        if cd:
            resp.headers["Content-Disposition"] = cd
        return resp
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/courier/kpis/partners")
def courier_partner_kpis(start_iso: str | None = None, end_iso: str | None = None, carrier: str | None = None, service_type: str | None = None):
    params = {}
    if start_iso:
        params["start_iso"] = start_iso
    if end_iso:
        params["end_iso"] = end_iso
    if carrier:
        params["carrier"] = carrier
    if service_type:
        params["service_type"] = service_type
    headers = {}
    if COURIER_ADMIN_TOKEN:
        headers["X-Admin-Token"] = COURIER_ADMIN_TOKEN
    try:
        r = httpx.get(_courier_url("/kpis/partners"), params=params, headers=headers, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/courier/kpis/partners/export")
def courier_partner_kpis_export(start_iso: str | None = None, end_iso: str | None = None, carrier: str | None = None, service_type: str | None = None):
    params = {}
    if start_iso:
        params["start_iso"] = start_iso
    if end_iso:
        params["end_iso"] = end_iso
    if carrier:
        params["carrier"] = carrier
    if service_type:
        params["service_type"] = service_type
    headers = {}
    if COURIER_ADMIN_TOKEN:
        headers["X-Admin-Token"] = COURIER_ADMIN_TOKEN
    try:
        r = httpx.get(_courier_url("/kpis/partners/export"), params=params, headers=headers, timeout=10)
        resp = Response(content=r.content, media_type="text/csv")
        cd = r.headers.get("Content-Disposition")
        if cd:
            resp.headers["Content-Disposition"] = cd
        return resp
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/courier/address/validate")
def courier_validate_address(lat: float, lng: float, address: str | None = None):
    try:
        r = httpx.get(_courier_url("/address/validate"), params={"lat": lat, "lng": lng, "address": address or ""}, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/courier/slots")
def courier_slots(service_type: str = "same_day"):
    try:
        r = httpx.get(_courier_url("/slots"), params={"service_type": service_type}, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/courier/partners", response_model=dict)
def courier_create_partner(body: dict):
    try:
        r = httpx.post(_courier_url("/partners"), json=body, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/courier/partners")
def courier_list_partners():
    try:
        r = httpx.get(_courier_url("/partners"), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/courier/apply", response_model=dict)
def courier_apply(body: dict):
    try:
        r = httpx.post(_courier_url("/apply"), json=body, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/courier/admin/applications")
def courier_admin_applications(status: str | None = None):
    params = {}
    if status:
        params["status"] = status
    headers = {}
    if COURIER_ADMIN_TOKEN:
        headers["X-Admin-Token"] = COURIER_ADMIN_TOKEN
    try:
        r = httpx.get(_courier_url("/admin/applications"), params=params, headers=headers, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


# ---- Stays proxies ----
def _stays_url(path: str) -> str:
    if not STAYS_BASE:
        raise HTTPException(status_code=500, detail="STAYS_BASE_URL not configured")
    return STAYS_BASE.rstrip("/") + path


# --- Stays internal service (monolith mode) ---
_STAYS_INTERNAL_AVAILABLE = False
try:
    from sqlalchemy.orm import Session as _StaysSession  # type: ignore[import]
    from apps.stays.app import main as _stays_main  # type: ignore[import]
    from apps.stays.app.main import (  # type: ignore[import]
        engine as _stays_engine,
        get_session as _stays_get_session,
        ListingCreate as _StaysListingCreate,
        ListingUpdate as _StaysListingUpdate,
        ListingsPage as _StaysListingsPage,
        QuoteReq as _StaysQuoteReq,
        BookReq as _StaysBookReq,
        BookingOut as _StaysBookingOut,
        OperatorCreate as _StaysOperatorCreate,
        OperatorOut as _StaysOperatorOut,
        OperatorLoginReq as _StaysOperatorLoginReq,
        OperatorLoginOut as _StaysOperatorLoginOut,
        OperatorCodeReq as _StaysOperatorCodeReq,
        OperatorVerifyReq as _StaysOperatorVerifyReq,
        RoomTypeCreate as _StaysRoomTypeCreate,
        RoomTypeUpdate as _StaysRoomTypeUpdate,
        RoomTypeOut as _StaysRoomTypeOut,
        RoomCreate as _StaysRoomCreate,
        RoomUpdate as _StaysRoomUpdate,
        RoomOut as _StaysRoomOut,
        PropertyCreate as _StaysPropertyCreate,
        PropertyOut as _StaysPropertyOut,
        StaffCreate as _StaysStaffCreate,
        StaffUpdate as _StaysStaffUpdate,
        StaffOut as _StaysStaffOut,
        DayRatesUpsert as _StaysDayRatesUpsert,
        DayRatesPage as _StaysDayRatesPage,
        BookingsPage as _StaysBookingsPage,
        BookingStatusUpdate as _StaysBookingStatusUpdate,
        create_listing as _stays_create_listing,
        list_listings as _stays_list_listings,
        list_listings_search as _stays_list_listings_search,
        quote as _stays_quote,
        book as _stays_book,
        get_booking as _stays_get_booking,
        create_operator as _stays_create_operator,
        get_operator as _stays_get_operator,
        operator_listings as _stays_operator_listings,
        operator_bookings as _stays_operator_bookings,
        operator_login as _stays_operator_login,
        operators_request_code as _stays_operators_request_code,
        operators_verify as _stays_operators_verify,
        operator_create_listing as _stays_operator_create_listing,
        operator_update_listing as _stays_operator_update_listing,
        operator_delete_listing as _stays_operator_delete_listing,
        create_room_type as _stays_create_room_type,
        list_room_types as _stays_list_room_types,
        update_room_type as _stays_update_room_type,
        create_room as _stays_create_room,
        list_rooms as _stays_list_rooms,
        update_room as _stays_update_room,
        create_property as _stays_create_property,
        list_properties as _stays_list_properties,
        create_staff as _stays_create_staff,
        list_staff as _stays_list_staff,
        update_staff as _stays_update_staff,
        deactivate_staff as _stays_deactivate_staff,
        get_room_type_rates as _stays_get_room_type_rates,
        upsert_room_type_rates as _stays_upsert_room_type_rates,
        operator_listings_search as _stays_operator_listings_search,
        operator_bookings_search as _stays_operator_bookings_search,
        operator_update_booking_status as _stays_operator_update_booking_status,
    )
    _STAYS_INTERNAL_AVAILABLE = True
except Exception:
    _StaysSession = None  # type: ignore[assignment]
    _stays_engine = None  # type: ignore[assignment]
    _STAYS_INTERNAL_AVAILABLE = False


def _use_stays_internal() -> bool:
    if _force_internal(_STAYS_INTERNAL_AVAILABLE):
        return True
    mode = os.getenv("STAYS_INTERNAL_MODE", "auto").lower()
    if mode == "off":
        return False
    if not _STAYS_INTERNAL_AVAILABLE:
        return False
    if mode == "on":
        return True
    return not bool(STAYS_BASE)


def _stays_internal_session():
    if not _STAYS_INTERNAL_AVAILABLE or _StaysSession is None or _stays_engine is None:  # type: ignore[truthy-function]
        raise RuntimeError("Stays internal service not available")
    return _StaysSession(_stays_engine)  # type: ignore[call-arg]


# ---- Operator health-only proxies for additional apps ----
@app.get("/agriculture/health")
def agriculture_health():
    try:
        if _use_agriculture_internal():
            return {"status": "ok", "source": "internal", "service": "agriculture"}
        r = httpx.get(_agriculture_url("/health"), timeout=5)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/commerce/health")
def commerce_health():
    try:
        if _use_commerce_internal():
            # Internal Commerce app already exposes /health via shamell_shared
            return {"status": "ok", "source": "internal", "service": "commerce"}
        r = httpx.get(_commerce_url("/health"), timeout=5)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/doctors/health")
def doctors_health():
    try:
        if _use_doctors_internal():
            return {"status": "ok", "source": "internal", "service": "doctors"}
        r = httpx.get(_doctors_url("/health"), timeout=5)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/flights/health")
def flights_health():
    try:
        if _use_flights_internal():
            return {"status": "ok", "source": "internal", "service": "flights"}
        r = httpx.get(_flights_url("/health"), timeout=5)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/jobs/health")
def jobs_health():
    try:
        if _use_jobs_internal():
            return {"status": "ok", "source": "internal", "service": "jobs"}
        r = httpx.get(_jobs_url("/health"), timeout=5)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/livestock/health")
def livestock_health():
    try:
        if _use_livestock_internal():
            return {"status": "ok", "source": "internal", "service": "livestock"}
        r = httpx.get(_livestock_url("/health"), timeout=5)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))

# ---- Additional upstream helpers (health-only until APIs exist) ----
def _agriculture_url(path: str) -> str:
    if not AGRICULTURE_BASE:
        raise HTTPException(status_code=500, detail="AGRICULTURE_BASE_URL not configured")
    return AGRICULTURE_BASE.rstrip("/") + path

def _commerce_url(path: str) -> str:
    if not COMMERCE_BASE:
        raise HTTPException(status_code=500, detail="COMMERCE_BASE_URL not configured")
    return COMMERCE_BASE.rstrip("/") + path

def _doctors_url(path: str) -> str:
    if not DOCTORS_BASE:
        raise HTTPException(status_code=500, detail="DOCTORS_BASE_URL not configured")
    return DOCTORS_BASE.rstrip("/") + path

def _flights_url(path: str) -> str:
    if not FLIGHTS_BASE:
        raise HTTPException(status_code=500, detail="FLIGHTS_BASE_URL not configured")
    return FLIGHTS_BASE.rstrip("/") + path


# --- Commerce/Doctors/Flights/Jobs/Agriculture/Livestock internal services (monolith mode) ---
_COMMERCE_INTERNAL_AVAILABLE = False
_DOCTORS_INTERNAL_AVAILABLE = False
_FLIGHTS_INTERNAL_AVAILABLE = False
_JOBS_INTERNAL_AVAILABLE = False
_AGRICULTURE_INTERNAL_AVAILABLE = False
_LIVESTOCK_INTERNAL_AVAILABLE = False
try:
    from sqlalchemy.orm import Session as _CommerceSession  # type: ignore[import]
    from apps.commerce.app import main as _commerce_main  # type: ignore[import]
    from apps.commerce.app.main import (  # type: ignore[import]
        engine as _commerce_engine,
        ProductCreate as _CommerceProductCreate,
        OrderCreate as _CommerceOrderCreate,
        OrderStatusUpdate as _CommerceOrderStatusUpdate,
        create_product as _commerce_create_product,
        list_products as _commerce_list_products,
        get_product as _commerce_get_product,
        create_order as _commerce_create_order,
        list_orders as _commerce_list_orders,
        get_order as _commerce_get_order,
        update_order_status as _commerce_update_order_status,
    )
    _COMMERCE_INTERNAL_AVAILABLE = True
except Exception:
    _CommerceSession = None  # type: ignore[assignment]
    _commerce_engine = None  # type: ignore[assignment]
    _COMMERCE_INTERNAL_AVAILABLE = False

try:
    from sqlalchemy.orm import Session as _DoctorsSession  # type: ignore[import]
    from apps.doctors.app import main as _doctors_main  # type: ignore[import]
    from apps.doctors.app.main import (  # type: ignore[import]
        engine as _doctors_engine,
        DoctorCreate as _DoctorsDoctorCreate,
        AppointmentCreate as _DoctorsAppointmentCreate,
        AppointmentReschedule as _DoctorsAppointmentReschedule,
        AvailabilityBlock as _DoctorsAvailabilityBlock,
        create_doctor as _doctors_create_doctor,
        list_doctors as _doctors_list_doctors,
        get_doctor as _doctors_get_doctor,
        get_doctor_availability as _doctors_get_doctor_availability,
        set_doctor_availability as _doctors_set_doctor_availability,
        create_appt as _doctors_create_appt,
        list_appts as _doctors_list_appts,
        list_slots as _doctors_list_slots,
        cancel_appointment as _doctors_cancel_appointment,
        reschedule_appointment as _doctors_reschedule_appointment,
    )
    _DOCTORS_INTERNAL_AVAILABLE = True
except Exception:
    _DoctorsSession = None  # type: ignore[assignment]
    _doctors_engine = None  # type: ignore[assignment]
    _DOCTORS_INTERNAL_AVAILABLE = False

try:
    from sqlalchemy.orm import Session as _FlightsSession  # type: ignore[import]
    from apps.flights.app import main as _flights_main  # type: ignore[import]
    from apps.flights.app.main import (  # type: ignore[import]
        engine as _flights_engine,
        FlightCreate as _FlightsFlightCreate,
        BookingCreate as _FlightsBookingCreate,
        create_flight as _flights_create_flight,
        list_flights as _flights_list_flights,
        create_booking as _flights_create_booking,
        get_booking as _flights_get_booking,
    )
    _FLIGHTS_INTERNAL_AVAILABLE = True
except Exception:
    _FlightsSession = None  # type: ignore[assignment]
    _flights_engine = None  # type: ignore[assignment]
    _FLIGHTS_INTERNAL_AVAILABLE = False

try:
    from sqlalchemy.orm import Session as _JobsSession  # type: ignore[import]
    from apps.jobs.app import main as _jobs_main  # type: ignore[import]
    from apps.jobs.app.main import (  # type: ignore[import]
        engine as _jobs_engine,
        get_session as _jobs_get_session,
    )
    _JOBS_INTERNAL_AVAILABLE = True
except Exception:
    _JobsSession = None  # type: ignore[assignment]
    _jobs_engine = None  # type: ignore[assignment]
    _JOBS_INTERNAL_AVAILABLE = False

try:
    from sqlalchemy.orm import Session as _AgricultureSession  # type: ignore[import]
    from apps.agriculture.app import main as _agriculture_main  # type: ignore[import]
    from apps.agriculture.app.main import (  # type: ignore[import]
        engine as _agriculture_engine,
        get_session as _agriculture_get_session,
        ListingCreate as _AgricultureListingCreate,
        ListingUpdate as _AgricultureListingUpdate,
        ListingOut as _AgricultureListingOut,
        RFQCreate as _AgricultureRFQCreate,
        RFQReplyCreate as _AgricultureRFQReplyCreate,
        RFQOut as _AgricultureRFQOut,
        RFQReplyOut as _AgricultureRFQReplyOut,
        OrderCreate as _AgricultureOrderCreate,
        OrderOut as _AgricultureOrderOut,
        OrderUpdate as _AgricultureOrderUpdate,
        create_listing as _agriculture_create_listing,
        list_listings as _agriculture_list_listings,
        get_listing as _agriculture_get_listing,
        update_listing as _agriculture_update_listing,
        create_rfq as _agriculture_create_rfq,
        list_rfqs as _agriculture_list_rfqs,
        get_rfq as _agriculture_get_rfq,
        reply_rfq as _agriculture_reply_rfq,
        list_rfq_replies as _agriculture_list_rfq_replies,
        create_order as _agriculture_create_order,
        list_orders as _agriculture_list_orders,
        update_order as _agriculture_update_order,
    )
    _AGRICULTURE_INTERNAL_AVAILABLE = True
except Exception:
    _AgricultureSession = None  # type: ignore[assignment]
    _agriculture_engine = None  # type: ignore[assignment]
    _AGRICULTURE_INTERNAL_AVAILABLE = False

try:
    from sqlalchemy.orm import Session as _LivestockSession  # type: ignore[import]
    from apps.livestock.app import main as _livestock_main  # type: ignore[import]
    from apps.livestock.app.main import (  # type: ignore[import]
        engine as _livestock_engine,
        get_session as _livestock_get_session,
        ListingCreate as _LivestockListingCreate,
        ListingOut as _LivestockListingOut,
        ListingUpdate as _LivestockListingUpdate,
        OfferCreate as _LivestockOfferCreate,
        OfferUpdate as _LivestockOfferUpdate,
        create_listing as _livestock_create_listing,
        list_listings as _livestock_list_listings,
        get_listing as _livestock_get_listing,
        update_listing as _livestock_update_listing,
        create_offer as _livestock_create_offer,
        list_offers as _livestock_list_offers,
        update_offer as _livestock_update_offer,
    )
    _LIVESTOCK_INTERNAL_AVAILABLE = True
except Exception:
    _LivestockSession = None  # type: ignore[assignment]
    _livestock_engine = None  # type: ignore[assignment]
    _LIVESTOCK_INTERNAL_AVAILABLE = False


def _use_commerce_internal() -> bool:
    if _force_internal(_COMMERCE_INTERNAL_AVAILABLE):
        return True
    mode = os.getenv("COMMERCE_INTERNAL_MODE", "auto").lower()
    if mode == "off":
        return False
    if not _COMMERCE_INTERNAL_AVAILABLE:
        return False
    if mode == "on":
        return True
    return not bool(COMMERCE_BASE)


def _use_doctors_internal() -> bool:
    if _force_internal(_DOCTORS_INTERNAL_AVAILABLE):
        return True
    mode = os.getenv("DOCTORS_INTERNAL_MODE", "auto").lower()
    if mode == "off":
        return False
    if not _DOCTORS_INTERNAL_AVAILABLE:
        return False
    if mode == "on":
        return True
    return not bool(DOCTORS_BASE)


def _use_flights_internal() -> bool:
    if _force_internal(_FLIGHTS_INTERNAL_AVAILABLE):
        return True
    mode = os.getenv("FLIGHTS_INTERNAL_MODE", "auto").lower()
    if mode == "off":
        return False
    if not _FLIGHTS_INTERNAL_AVAILABLE:
        return False
    if mode == "on":
        return True
    return not bool(FLIGHTS_BASE)


def _use_jobs_internal() -> bool:
    if _force_internal(_JOBS_INTERNAL_AVAILABLE):
        return True
    mode = os.getenv("JOBS_INTERNAL_MODE", "auto").lower()
    if mode == "off":
        return False
    if not _JOBS_INTERNAL_AVAILABLE:
        return False
    if mode == "on":
        return True
    return not bool(JOBS_BASE)


def _use_agriculture_internal() -> bool:
    if _force_internal(_AGRICULTURE_INTERNAL_AVAILABLE):
        return True
    mode = os.getenv("AGRICULTURE_INTERNAL_MODE", "auto").lower()
    if mode == "off":
        return False
    if not _AGRICULTURE_INTERNAL_AVAILABLE:
        return False
    if mode == "on":
        return True
    return not bool(AGRICULTURE_BASE)


def _use_livestock_internal() -> bool:
    if _force_internal(_LIVESTOCK_INTERNAL_AVAILABLE):
        return True
    mode = os.getenv("LIVESTOCK_INTERNAL_MODE", "auto").lower()
    if mode == "off":
        return False
    if not _LIVESTOCK_INTERNAL_AVAILABLE:
        return False
    if mode == "on":
        return True
    return not bool(LIVESTOCK_BASE)


def _commerce_internal_session():
    if not _COMMERCE_INTERNAL_AVAILABLE or _CommerceSession is None or _commerce_engine is None:  # type: ignore[truthy-function]
        raise RuntimeError("Commerce internal service not available")
    return _CommerceSession(_commerce_engine)  # type: ignore[call-arg]


def _doctors_internal_session():
    if not _DOCTORS_INTERNAL_AVAILABLE or _DoctorsSession is None or _doctors_engine is None:  # type: ignore[truthy-function]
        raise RuntimeError("Doctors internal service not available")
    return _DoctorsSession(_doctors_engine)  # type: ignore[call-arg]


def _flights_internal_session():
    if not _FLIGHTS_INTERNAL_AVAILABLE or _FlightsSession is None or _flights_engine is None:  # type: ignore[truthy-function]
        raise RuntimeError("Flights internal service not available")
    return _FlightsSession(_flights_engine)  # type: ignore[call-arg]


def _jobs_internal_session():
    if not _JOBS_INTERNAL_AVAILABLE or _JobsSession is None or _jobs_engine is None:  # type: ignore[truthy-function]
        raise RuntimeError("Jobs internal service not available")
    return _JobsSession(_jobs_engine)  # type: ignore[call-arg]


def _agriculture_internal_session():
    if not _AGRICULTURE_INTERNAL_AVAILABLE or _AgricultureSession is None or _agriculture_engine is None:  # type: ignore[truthy-function]
        raise RuntimeError("Agriculture internal service not available")
    return _AgricultureSession(_agriculture_engine)  # type: ignore[call-arg]


def _livestock_internal_session():
    if not _LIVESTOCK_INTERNAL_AVAILABLE or _LivestockSession is None or _livestock_engine is None:  # type: ignore[truthy-function]
        raise RuntimeError("Livestock internal service not available")
    return _LivestockSession(_livestock_engine)  # type: ignore[call-arg]


def _jobs_url(path: str) -> str:
    if not JOBS_BASE:
        raise HTTPException(status_code=500, detail="JOBS_BASE_URL not configured")
    return JOBS_BASE.rstrip("/") + path


def _livestock_url(path: str) -> str:
    if not LIVESTOCK_BASE:
        raise HTTPException(status_code=500, detail="LIVESTOCK_BASE_URL not configured")
    return LIVESTOCK_BASE.rstrip("/") + path

def _building_url(path: str) -> str:
    if not BUILDING_BASE:
        raise HTTPException(status_code=500, detail="BUILDING_BASE_URL not configured")
    return BUILDING_BASE.rstrip("/") + path

# ---- Commerce proxies ----
@app.get("/commerce/products")
def commerce_products(q: str = "", limit: int = 50):
    params = {"limit": max(1, min(limit, 200))}
    if q:
        params["q"] = q
    try:
        if _use_commerce_internal():
            if not _COMMERCE_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="commerce internal not available")
            with _commerce_internal_session() as s:
                return _commerce_list_products(q=q, limit=limit, s=s)
        r = httpx.get(_commerce_url("/products"), params=params, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/commerce/products_cached")
def commerce_products_cached(limit: int = 50, response: Response = None):  # type: ignore[assignment]
    """
    Small cache for the product list without search parameters.
    For q/filter please continue to use /commerce/products directly.
    """
    global _COMMERCE_PRODUCTS_CACHE
    if limit <= 0:
        limit = 50
    # Cache only for standard list without filters
    if _COMMERCE_PRODUCTS_CACHE.get("data") is not None:
        try:
            ts = float(_COMMERCE_PRODUCTS_CACHE.get("ts") or 0.0)
        except Exception:
            ts = 0.0
        if time.time() - ts < 30.0:
            data = _COMMERCE_PRODUCTS_CACHE.get("data")
            try:
                if response is not None:
                    response.headers.setdefault("Cache-Control", "public, max-age=30")
            except Exception:
                pass
            return data
    data = commerce_products(q="", limit=limit)
    _COMMERCE_PRODUCTS_CACHE = {"ts": time.time(), "data": data}
    try:
        if response is not None:
            response.headers.setdefault("Cache-Control", "public, max-age=30")
    except Exception:
        pass
    return data


@app.post("/commerce/products")
async def commerce_create_product(req: Request):
    _require_operator(req, "commerce")
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        if _use_commerce_internal():
            if not _COMMERCE_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="commerce internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                preq = _CommerceProductCreate(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _commerce_internal_session() as s:
                return _commerce_create_product(req=preq, s=s)
        r = httpx.post(_commerce_url("/products"), json=body, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/commerce/products/{pid}")
def commerce_get_product(pid: int):
    try:
        if _use_commerce_internal():
            if not _COMMERCE_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="commerce internal not available")
            with _commerce_internal_session() as s:
                return _commerce_get_product(pid=pid, s=s)
        r = httpx.get(_commerce_url(f"/products/{pid}"), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/building/materials")
def building_materials(q: str = "", limit: int = 50):
    """
    Building Materials catalog endpoint.

    - If BUILDING_BASE_URL is configured, calls the dedicated Building
      service at /materials (recommended for production).
    - Otherwise falls back to /commerce/products, preserving the existing
      behaviour and avoiding client changes.
    """
    # dedicated Building upstream (optional)
    if BUILDING_BASE:
      params = {"limit": max(1, min(limit, 200))}
      if q:
          params["q"] = q
      try:
          r = httpx.get(_building_url("/materials"), params=params, timeout=10)
          return r.json()
      except httpx.HTTPStatusError as e:
          raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
      except Exception as e:
          raise HTTPException(status_code=502, detail=str(e))
    # Fallback: reuse Commerce products as before
    return commerce_products(q=q, limit=limit)


def _building_transfer(
    request: Request,
    from_wallet_id: str,
    to_wallet_id: str,
    amount_cents: int,
    reference: str,
) -> Any:
    """
    Helper to perform a guarded transfer for Building Materials flows.

    Mirrors the logic in /payments/transfer:
      - normalises amounts
      - applies _check_payment_guardrails
      - uses internal Payments when available, otherwise HTTP fallback.
    """
    if amount_cents <= 0:
        raise HTTPException(status_code=400, detail="amount must be > 0")
    try:
        dev = request.headers.get("X-Device-ID") if hasattr(request, "headers") else None
        _check_payment_guardrails(from_wallet_id, amount_cents, dev)
    except HTTPException:
        raise
    except Exception:
        # Guardrails are best-effort; never break payment execution.
        pass

    body: dict[str, Any] = {
        "from_wallet_id": from_wallet_id,
        "to_wallet_id": to_wallet_id,
        "amount_cents": amount_cents,
        "reference": reference,
    }
    body = _normalize_amount(body)

    # Forward selected headers for risk / idempotency
    headers: dict[str, str] = {}
    try:
        ikey = request.headers.get("Idempotency-Key") if hasattr(request, "headers") else None
        dev = request.headers.get("X-Device-ID") if hasattr(request, "headers") else None
        ua = request.headers.get("User-Agent") if hasattr(request, "headers") else None
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
                    return _pay_transfer(req_model, request=request, s=s)
            except HTTPException:
                raise
            except Exception as e:
                raise HTTPException(status_code=502, detail=str(e))
        if not PAYMENTS_BASE:
            raise HTTPException(status_code=500, detail="PAYMENTS_BASE_URL not configured")
        r = httpx.post(_payments_url("/transfer"), json=body, headers=headers, timeout=10)
        if r.headers.get("content-type", "").startswith("application/json"):
            return r.json()
        return {"status_code": r.status_code, "raw": r.text}
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/building/orders")
async def building_create_order(request: Request):
    """
    Create a Building Materials order with escrow:

      - validates product and quantity via Commerce,
      - charges buyer_wallet_id -> ESCROW_WALLET_ID via Payments,
      - creates a Commerce order with status 'paid_escrow'.

    This endpoint assumes the caller is an authenticated end user; the
    wallet ownership checks are enforced on the client side by only offering
    the user’s own wallet for selection.
    """
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    if not ESCROW_WALLET_ID:
        raise HTTPException(status_code=500, detail="ESCROW_WALLET_ID not configured")

    try:
        body = await request.json()
    except Exception:
        body = {}
    if not isinstance(body, dict):
        body = {}

    try:
        product_id = int(body.get("product_id") or 0)
    except Exception:
        product_id = 0
    try:
        quantity = int(body.get("quantity") or 1)
    except Exception:
        quantity = 1
    buyer_wallet_id = (body.get("buyer_wallet_id") or "").strip()

    if product_id <= 0:
        raise HTTPException(status_code=400, detail="product_id required")
    if quantity <= 0:
        raise HTTPException(status_code=400, detail="quantity must be > 0")
    if not buyer_wallet_id:
        raise HTTPException(status_code=400, detail="buyer_wallet_id required")

    # Look up product details via Commerce
    try:
        if _use_commerce_internal():
            if not _COMMERCE_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="commerce internal not available")
            with _commerce_internal_session() as s:
                pobj = _commerce_get_product(pid=product_id, s=s)
                if hasattr(pobj, "model_dump"):
                    product = pobj.model_dump()  # type: ignore[assignment]
                elif hasattr(pobj, "dict"):
                    product = pobj.dict()  # type: ignore[assignment]
                else:
                    # SQLAlchemy ORM object – build a minimal dict view.
                    try:
                        product = {
                            "id": getattr(pobj, "id", None),
                            "name": getattr(pobj, "name", ""),
                            "price_cents": getattr(pobj, "price_cents", 0),
                            "currency": getattr(pobj, "currency", "SYP"),
                            "sku": getattr(pobj, "sku", None),
                            "merchant_wallet_id": getattr(pobj, "merchant_wallet_id", None),
                        }  # type: ignore[assignment]
                    except Exception:
                        product = {}  # type: ignore[assignment]
        else:
            r = httpx.get(_commerce_url(f"/products/{product_id}"), timeout=10)
            product = r.json()
    except HTTPException:
        raise
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))

    if not isinstance(product, dict):
        raise HTTPException(status_code=502, detail="invalid product payload")
    price_cents = product.get("price_cents") or 0
    try:
        price_cents = int(price_cents)
    except Exception:
        price_cents = 0
    currency = (product.get("currency") or "SYP").strip()
    if price_cents <= 0:
        raise HTTPException(status_code=400, detail="product has no price")
    amount_cents = int(price_cents) * int(quantity)
    if amount_cents <= 0:
        raise HTTPException(status_code=400, detail="amount must be > 0")

    # Move funds buyer -> escrow (best-effort, but failures are surfaced).
    ref = f"building product {product_id}"
    _building_transfer(
        request=request,
        from_wallet_id=buyer_wallet_id,
        to_wallet_id=ESCROW_WALLET_ID,
        amount_cents=amount_cents,
        reference=ref,
    )

    # Create order record in Commerce (internal preferred).
    order_payload = {
        "product_id": product_id,
        "quantity": quantity,
        "buyer_wallet_id": buyer_wallet_id,
    }
    try:
        if _use_commerce_internal():
            if not _COMMERCE_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="commerce internal not available")
            try:
                oreq = _CommerceOrderCreate(**order_payload)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _commerce_internal_session() as s:
                o = _commerce_create_order(req=oreq, s=s)
                if hasattr(o, "model_dump"):
                    out = o.model_dump()  # type: ignore[assignment]
                elif hasattr(o, "dict"):
                    out = o.dict()  # type: ignore[assignment]
                else:
                    out = o  # type: ignore[assignment]
        else:
            r = httpx.post(_commerce_url("/orders"), json=order_payload, timeout=10)
            out = r.json()
    except HTTPException:
        raise
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))

    try:
        _audit_from_request(
            request,
            "building_order_create",
            product_id=product_id,
            amount_cents=amount_cents,
            currency=currency,
        )
    except Exception:
        # Audit must never break the main flow
        pass

    return out


@app.get("/building/orders")
def building_list_orders(
    request: Request,
    buyer_wallet_id: str = "",
    seller_wallet_id: str = "",
    limit: int = 50,
):
    """
    List Building Materials orders for a given wallet.

    For now this uses simple wallet-based filters; clients decide whether
    to pass buyer_wallet_id (end user) or seller_wallet_id (operator).
    """
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    limit = max(1, min(limit, 200))
    try:
        if _use_commerce_internal():
            if not _COMMERCE_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="commerce internal not available")
            with _commerce_internal_session() as s:
                raw = _commerce_list_orders(
                    buyer_wallet_id=buyer_wallet_id,
                    seller_wallet_id=seller_wallet_id,
                    limit=limit,
                    s=s,
                )
                out: list[Any] = []
                for it in raw:
                    if hasattr(it, "model_dump"):
                        row = it.model_dump()  # type: ignore[union-attr]
                    elif hasattr(it, "dict"):
                        row = it.dict()  # type: ignore[union-attr]
                    else:
                        row = it
                    out.append(row)
                return out
        params = {"limit": limit}
        if buyer_wallet_id:
            params["buyer_wallet_id"] = buyer_wallet_id
        if seller_wallet_id:
            params["seller_wallet_id"] = seller_wallet_id
        r = httpx.get(_commerce_url("/orders"), params=params, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/building/orders/{order_id}")
def building_get_order(request: Request, order_id: int):
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    try:
        if _use_commerce_internal():
            if not _COMMERCE_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="commerce internal not available")
            with _commerce_internal_session() as s:
                o = _commerce_get_order(oid=order_id, s=s)
                if hasattr(o, "model_dump"):
                    return o.model_dump()  # type: ignore[union-attr]
                if hasattr(o, "dict"):
                    return o.dict()  # type: ignore[union-attr]
                return o
        r = httpx.get(_commerce_url(f"/orders/{order_id}"), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/building/orders/{order_id}/attach_shipment")
async def building_attach_shipment(request: Request, order_id: int):
    """
    Link a Building Materials order to a courier shipment.

    This is used to enforce stronger guardrails on escrow release:
      - If an order is linked to a shipment, the BFF can optionally require
        that the shipment has reached \"delivered\" before allowing `released`.

    For now this endpoint simply stores the link in an in-memory map; it is
    intended for operator/admin tools rather than end users.
    """
    _require_operator(request, "freight")
    try:
        body = await request.json()
    except Exception:
        body = {}
    if not isinstance(body, dict):
        body = {}
    shipment_id = str(body.get("shipment_id") or "").strip()
    if not shipment_id:
        raise HTTPException(status_code=400, detail="shipment_id required")

    # Verify order exists (best-effort)
    try:
        _ = building_get_order(request, order_id)
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(status_code=502, detail="failed to load order")

    # Verify shipment exists (best-effort)
    try:
        if _use_freight_internal():
            if not _FREIGHT_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="freight internal not available")
            with _freight_internal_session() as s:
                _freight_get_shipment(sid=shipment_id, s=s)
        else:
            _ = httpx.get(_freight_url(f"/shipments/{shipment_id}"), timeout=10)
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))

    # Store mapping in-memory
    try:
        _BUILDING_ORDER_SHIPMENTS[int(order_id)] = shipment_id
    except Exception:
        _BUILDING_ORDER_SHIPMENTS[order_id] = shipment_id  # type: ignore[index]

    try:
        _audit_from_request(
            request,
            "building_order_attach_shipment",
            order_id=order_id,
            shipment_id=shipment_id,
        )
    except Exception:
        pass

    return {"order_id": order_id, "shipment_id": shipment_id}


@app.post("/building/orders/{order_id}/status")
async def building_update_order_status(request: Request, order_id: int):
    """
    Update the status of a Building Materials order.

    Role model (enforced at BFF level):
      - shipped:   operator (commerce)
      - delivered: any authenticated end user (typically the buyer)
      - disputed:  any authenticated end user (typically the buyer)
      - released:  admin/superadmin (payout from escrow to seller may follow)
      - refunded:  admin/superadmin (refund from escrow to buyer may follow)

    For now, payout/refund legs are not executed here; this endpoint
    focuses on consistent status transitions and audit logging. Money
    remains safely held in ESCROW until a separate settlement routine
    is invoked.
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

    new_status = str(body.get("status") or "").strip().lower()
    if not new_status:
        raise HTTPException(status_code=400, detail="status required")

    # Load current order to validate transitions.
    try:
        if _use_commerce_internal():
            if not _COMMERCE_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="commerce internal not available")
            with _commerce_internal_session() as s:
                o = _commerce_get_order(oid=order_id, s=s)
                if hasattr(o, "model_dump"):
                    order = o.model_dump()  # type: ignore[assignment]
                elif hasattr(o, "dict"):
                    order = o.dict()  # type: ignore[assignment]
                else:
                    order = {
                        "id": getattr(o, "id", order_id),
                        "status": getattr(o, "status", ""),
                        "buyer_wallet_id": getattr(o, "buyer_wallet_id", None),
                        "seller_wallet_id": getattr(o, "seller_wallet_id", None),
                        "amount_cents": getattr(o, "amount_cents", 0),
                    }  # type: ignore[assignment]
        else:
            r = httpx.get(_commerce_url(f"/orders/{order_id}"), timeout=10)
            order = r.json()
    except HTTPException:
        raise
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))

    if not isinstance(order, dict):
        raise HTTPException(status_code=502, detail="invalid order payload")

    current_status = str(order.get("status") or "").strip().lower()

    # Simple transition rules: only allow forward progress.
    allowed_from: dict[str, set[str]] = {
        "shipped": {"paid_escrow"},
        # delivered can follow shipped or, in simpler flows without explicit
        # shipment tracking, directly from paid_escrow.
        "delivered": {"paid_escrow", "shipped"},
        "disputed": {"paid_escrow", "shipped", "delivered"},
        "released": {"delivered"},
        "refunded": {"paid_escrow", "shipped", "disputed"},
    }
    allowed_prev = allowed_from.get(new_status)
    if allowed_prev is None:
        raise HTTPException(status_code=400, detail="unsupported status")
    if current_status and current_status not in allowed_prev:
        raise HTTPException(status_code=400, detail="invalid status transition")

    # Role checks per target status.
    if new_status == "shipped":
        _require_operator(request, "commerce")
    elif new_status in ("released", "refunded"):
        _require_admin_v2(request)
    else:
        # delivered / disputed: any authenticated user is allowed.
        pass

    # Settlement for money-moving statuses (released/refunded).
    # We run transfers before persisting the new status so that, on failure,
    # the order state stays unchanged.
    try:
        amount_cents = int(order.get("amount_cents") or 0)
    except Exception:
        amount_cents = 0
    buyer_wallet_id = (order.get("buyer_wallet_id") or "").strip()
    seller_wallet_id = (order.get("seller_wallet_id") or "").strip()
    if new_status in ("released", "refunded"):
        if not ESCROW_WALLET_ID:
            raise HTTPException(status_code=500, detail="ESCROW_WALLET_ID not configured")
        if amount_cents <= 0:
            raise HTTPException(status_code=400, detail="order amount invalid for settlement")
        if new_status == "released":
            if not seller_wallet_id:
                raise HTTPException(status_code=400, detail="order has no seller wallet")
            # If a shipment has been linked via /building/orders/{id}/attach_shipment,
            # require that the shipment has reached delivered state before
            # releasing escrow. This enforces courier confirmation in addition
            # to buyer/order confirmation for the payout leg.
            shipment_id = ""
            try:
                shipment_id = _BUILDING_ORDER_SHIPMENTS.get(int(order_id)) or ""  # type: ignore[arg-type]
            except Exception:
                shipment_id = ""
            shipment_id = shipment_id.strip()
            if shipment_id:
                try:
                    if _use_freight_internal():
                        if not _FREIGHT_INTERNAL_AVAILABLE:
                            raise HTTPException(status_code=500, detail="freight internal not available")
                        with _freight_internal_session() as s:
                            sh = _freight_get_shipment(sid=shipment_id, s=s)
                            if hasattr(sh, "model_dump"):
                                sh_row = sh.model_dump()  # type: ignore[assignment]
                            elif hasattr(sh, "dict"):
                                sh_row = sh.dict()  # type: ignore[assignment]
                            else:
                                sh_row = {
                                    "id": getattr(sh, "id", shipment_id),
                                    "status": getattr(sh, "status", ""),
                                }  # type: ignore[assignment]
                    else:
                        r = httpx.get(_freight_url(f"/shipments/{shipment_id}"), timeout=10)
                        sh_row = r.json()
                except HTTPException:
                    raise
                except httpx.HTTPStatusError as e:
                    raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
                except Exception as e:
                    raise HTTPException(status_code=502, detail=str(e))
                sh_status = str(sh_row.get("status") or "").strip().lower()
                if sh_status != "delivered":
                    raise HTTPException(status_code=400, detail="shipment not delivered yet")
            # Escrow -> seller payout
            _building_transfer(
                request=request,
                from_wallet_id=ESCROW_WALLET_ID,
                to_wallet_id=seller_wallet_id,
                amount_cents=amount_cents,
                reference=f"building order {order_id} release",
            )
        elif new_status == "refunded":
            if not buyer_wallet_id:
                raise HTTPException(status_code=400, detail="order has no buyer wallet")
            # Escrow -> buyer refund
            _building_transfer(
                request=request,
                from_wallet_id=ESCROW_WALLET_ID,
                to_wallet_id=buyer_wallet_id,
                amount_cents=amount_cents,
                reference=f"building order {order_id} refund",
            )

    # Persist status via Commerce.
    payload = {"status": new_status}
    try:
        if _use_commerce_internal():
            if not _COMMERCE_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="commerce internal not available")
            try:
                sreq = _CommerceOrderStatusUpdate(**payload)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _commerce_internal_session() as s:
                o2 = _commerce_update_order_status(oid=order_id, req=sreq, s=s)
                if hasattr(o2, "model_dump"):
                    updated = o2.model_dump()  # type: ignore[assignment]
                elif hasattr(o2, "dict"):
                    updated = o2.dict()  # type: ignore[assignment]
                else:
                    updated = updated = {
                        "id": getattr(o2, "id", order_id),
                        "status": getattr(o2, "status", new_status),
                        "buyer_wallet_id": getattr(o2, "buyer_wallet_id", None),
                        "seller_wallet_id": getattr(o2, "seller_wallet_id", None),
                        "amount_cents": getattr(o2, "amount_cents", 0),
                    }  # type: ignore[assignment]
        else:
            r = httpx.post(_commerce_url(f"/orders/{order_id}/status"), json=payload, timeout=10)
            updated = r.json()
    except HTTPException:
        raise
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))

    # Audit for observability.
    try:
        _audit_from_request(
            request,
            "building_order_status_update",
            order_id=order_id,
            from_status=current_status or None,
            to_status=new_status,
        )
    except Exception:
        pass

    return updated


# ---- Doctors proxies ----
@app.get("/doctors/doctors")
def doctors_list(q: str = "", city: str = "", speciality: str = "", limit: int = 50):
    params = {"limit": max(1, min(limit, 200))}
    if q:
        params["q"] = q
    if city:
        params["city"] = city
    if speciality:
        params["speciality"] = speciality
    try:
        if _use_doctors_internal():
            if not _DOCTORS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="doctors internal not available")
            with _doctors_internal_session() as s:
                return _doctors_list_doctors(q=q, city=city, speciality=speciality, limit=limit, s=s)
        r = httpx.get(_doctors_url("/doctors"), params=params, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/doctors/doctors")
async def doctors_create(req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        ikey = None
        try:
            ikey = req.headers.get("Idempotency-Key")
        except Exception:
            ikey = None
        if _use_doctors_internal():
            if not _DOCTORS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="doctors internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                dreq = _DoctorsDoctorCreate(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _doctors_internal_session() as s:
                return _doctors_create_doctor(req=dreq, idempotency_key=ikey, s=s)
        headers: dict[str, str] = {}
        if ikey:
            headers["Idempotency-Key"] = ikey
        r = httpx.post(_doctors_url("/doctors"), json=body, headers=headers, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/doctors/doctors/{doctor_id}")
def doctors_get(doctor_id: int):
    try:
        if _use_doctors_internal():
            if not _DOCTORS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="doctors internal not available")
            with _doctors_internal_session() as s:
                return _doctors_get_doctor(doctor_id=doctor_id, s=s)
        r = httpx.get(_doctors_url(f"/doctors/{doctor_id}"), timeout=10)
        r.raise_for_status()
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/doctors/doctors/{doctor_id}/availability")
def doctors_get_availability(doctor_id: int):
    try:
        if _use_doctors_internal():
            if not _DOCTORS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="doctors internal not available")
            with _doctors_internal_session() as s:
                return _doctors_get_doctor_availability(doctor_id=doctor_id, s=s)
        r = httpx.get(_doctors_url(f"/doctors/{doctor_id}/availability"), timeout=10)
        r.raise_for_status()
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.put("/doctors/doctors/{doctor_id}/availability")
async def doctors_set_availability(doctor_id: int, req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        if _use_doctors_internal():
            if not _DOCTORS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="doctors internal not available")
            data = body or []
            if not isinstance(data, list):
                raise HTTPException(status_code=400, detail="body must be a list")
            blocks = []
            for item in data:
                if not isinstance(item, dict):
                    raise HTTPException(status_code=400, detail="invalid availability block")
                try:
                    blocks.append(_DoctorsAvailabilityBlock(**item))
                except Exception as e:
                    raise HTTPException(status_code=400, detail=str(e))
            with _doctors_internal_session() as s:
                return _doctors_set_doctor_availability(doctor_id=doctor_id, blocks=blocks, s=s)
        r = httpx.put(_doctors_url(f"/doctors/{doctor_id}/availability"), json=body, timeout=10)
        r.raise_for_status()
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/doctors/appointments")
def doctors_list_appointments(doctor_id: int | None = None, limit: int = 50):
    params: dict[str, object] = {"limit": max(1, min(limit, 200))}
    if doctor_id is not None:
        params["doctor_id"] = doctor_id
    try:
        if _use_doctors_internal():
            if not _DOCTORS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="doctors internal not available")
            with _doctors_internal_session() as s:
                return _doctors_list_appts(doctor_id=doctor_id, limit=limit, s=s)
        r = httpx.get(_doctors_url("/appointments"), params=params, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/doctors/slots")
def doctors_slots(doctor_id: int, start_date: str | None = None, days: int = 7):
    days_clamped = max(1, min(days, 31))
    params: dict[str, object] = {"doctor_id": doctor_id, "days": days_clamped}
    if start_date:
        params["start_date"] = start_date
    try:
        if _use_doctors_internal():
            if not _DOCTORS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="doctors internal not available")
            with _doctors_internal_session() as s:
                return _doctors_list_slots(doctor_id=doctor_id, start_date=start_date, days=days_clamped, s=s)
        r = httpx.get(_doctors_url("/slots"), params=params, timeout=10)
        r.raise_for_status()
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/doctors/appointments")
async def doctors_create_appointment(req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        ikey = None
        try:
            ikey = req.headers.get("Idempotency-Key")
        except Exception:
            ikey = None
        if _use_doctors_internal():
            if not _DOCTORS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="doctors internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                areq = _DoctorsAppointmentCreate(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _doctors_internal_session() as s:
                return _doctors_create_appt(req=areq, idempotency_key=ikey, s=s)
        headers: dict[str, str] = {}
        if ikey:
            headers["Idempotency-Key"] = ikey
        r = httpx.post(_doctors_url("/appointments"), json=body, headers=headers, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/doctors/appointments/{appt_id}/cancel")
async def doctors_cancel_appointment(appt_id: str):
    try:
        if _use_doctors_internal():
            if not _DOCTORS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="doctors internal not available")
            with _doctors_internal_session() as s:
                return _doctors_cancel_appointment(appt_id=appt_id, s=s)
        r = httpx.post(_doctors_url(f"/appointments/{appt_id}/cancel"), timeout=10)
        r.raise_for_status()
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/doctors/appointments/{appt_id}/reschedule")
async def doctors_reschedule_appointment(appt_id: str, req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        if _use_doctors_internal():
            if not _DOCTORS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="doctors internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                areq = _DoctorsAppointmentReschedule(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _doctors_internal_session() as s:
                return _doctors_reschedule_appointment(appt_id=appt_id, req=areq, s=s)
        r = httpx.post(_doctors_url(f"/appointments/{appt_id}/reschedule"), json=body, timeout=10)
        r.raise_for_status()
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


# ---- Flights proxies ----
@app.get("/flights/flights")
def flights_list(q: str = "", frm: str = "", to: str = "", limit: int = 50):
    params = {"limit": max(1, min(limit, 200))}
    if q:
        params["q"] = q
    if frm:
        params["frm"] = frm
    if to:
        params["to"] = to
    try:
        if _use_flights_internal():
            if not _FLIGHTS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="flights internal not available")
            with _flights_internal_session() as s:
                return _flights_list_flights(q=q, frm=frm, to=to, limit=limit, s=s)
        r = httpx.get(_flights_url("/flights"), params=params, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/flights/flights")
async def flights_create(req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        ikey = None
        try:
            ikey = req.headers.get("Idempotency-Key")
        except Exception:
            ikey = None
        if _use_flights_internal():
            if not _FLIGHTS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="flights internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                freq = _FlightsFlightCreate(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _flights_internal_session() as s:
                return _flights_create_flight(req=freq, idempotency_key=ikey, s=s)
        headers: dict[str, str] = {}
        if ikey:
            headers["Idempotency-Key"] = ikey
        r = httpx.post(_flights_url("/flights"), json=body, headers=headers, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/flights/bookings")
async def flights_create_booking(req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        ikey = None
        try:
            ikey = req.headers.get("Idempotency-Key")
        except Exception:
            ikey = None
        if _use_flights_internal():
            if not _FLIGHTS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="flights internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                breq = _FlightsBookingCreate(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _flights_internal_session() as s:
                return _flights_create_booking(req=breq, idempotency_key=ikey, s=s)
        headers: dict[str, str] = {}
        if ikey:
            headers["Idempotency-Key"] = ikey
        r = httpx.post(_flights_url("/bookings"), json=body, headers=headers, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/flights/bookings/{bid}")
def flights_get_booking(bid: str):
    try:
        if _use_flights_internal():
            if not _FLIGHTS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="flights internal not available")
            with _flights_internal_session() as s:
                return _flights_get_booking(bid=bid, s=s)
        r = httpx.get(_flights_url(f"/bookings/{bid}"), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/stays/listings")
def stays_listings(q: str = "", city: str = "", limit: int = 50, offset: int = 0):
    params = {"limit": max(1, min(limit, 200)), "offset": max(0, offset)}
    if q:
        params["q"] = q
    if city:
        params["city"] = city
    try:
        if _use_stays_internal():
            if not _STAYS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="stays internal not available")
            with _stays_internal_session() as s:
                return _stays_list_listings(q=q, city=city, limit=limit, offset=offset, s=s)
        r = httpx.get(_stays_url("/listings"), params=params, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


# ---- Agriculture proxies ----
@app.get("/agriculture/listings")
def agriculture_listings(q: str = "", city: str = "", category: str = "", status: str = "", limit: int = 50):
    params = {"limit": max(1, min(limit, 200))}
    if q:
        params["q"] = q
    if city:
        params["city"] = city
    if category:
        params["category"] = category
    if status:
        params["status"] = status
    # status optional
    # allow status via query
    # we won't add a dedicated param here to keep backward compat; users can pass ?status=
    # from req.query_params
    # but to ease usage, read from request? not available here; so accept status param:
    # signature extended above if needed
    try:
        if _use_agriculture_internal():
            if not _AGRICULTURE_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="agriculture internal not available")
            with _agriculture_internal_session() as s:
                return _agriculture_list_listings(q=q, city=city, category=category, status=status, limit=limit, s=s)
        r = httpx.get(_agriculture_url("/listings"), params=params, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/agriculture/listings_cached")
def agriculture_listings_cached(limit: int = 50, response: Response = None):  # type: ignore[assignment]
    """
    Cache for a simple agriculture listing list without filters.
    For q/city/category please continue to use /agriculture/listings.
    """
    global _AGRICULTURE_LISTINGS_CACHE
    if limit <= 0:
        limit = 50
    if _AGRICULTURE_LISTINGS_CACHE.get("data") is not None:
        try:
            ts = float(_AGRICULTURE_LISTINGS_CACHE.get("ts") or 0.0)
        except Exception:
            ts = 0.0
        if time.time() - ts < 30.0:
            data = _AGRICULTURE_LISTINGS_CACHE.get("data")
            try:
                if response is not None:
                    response.headers.setdefault("Cache-Control", "public, max-age=30")
            except Exception:
                pass
            return data
    data = agriculture_listings(q="", city="", category="", limit=limit)
    _AGRICULTURE_LISTINGS_CACHE = {"ts": time.time(), "data": data}
    try:
        if response is not None:
            response.headers.setdefault("Cache-Control", "public, max-age=30")
    except Exception:
        pass
    return data


@app.post("/agriculture/listings")
async def agriculture_create_listing(req: Request):
    _require_operator(req, "agriculture")
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        if _use_agriculture_internal():
            if not _AGRICULTURE_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="agriculture internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                lreq = _AgricultureListingCreate(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _agriculture_internal_session() as s:
                return _agriculture_create_listing(req=lreq, s=s)
        r = httpx.post(_agriculture_url("/listings"), json=body, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/agriculture/listings/{lid}")
def agriculture_get_listing(lid: int):
    try:
        if _use_agriculture_internal():
            if not _AGRICULTURE_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="agriculture internal not available")
            with _agriculture_internal_session() as s:
                return _agriculture_get_listing(lid=lid, s=s)
        r = httpx.get(_agriculture_url(f"/listings/{lid}"), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.patch("/agriculture/listings/{lid}")
async def agriculture_update_listing(lid: int, req: Request):
    _require_operator(req, "agriculture")
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        if _use_agriculture_internal():
            if not _AGRICULTURE_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="agriculture internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                lreq = _AgricultureListingUpdate(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _agriculture_internal_session() as s:
                return _agriculture_update_listing(lid=lid, req=lreq, s=s)
        r = httpx.patch(_agriculture_url(f"/listings/{lid}"), json=body, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/agriculture/rfqs")
async def agriculture_create_rfq(req: Request):
    # allow buyers without auth; keep simple
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        if _use_agriculture_internal():
            if not _AGRICULTURE_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="agriculture internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                rreq = _AgricultureRFQCreate(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _agriculture_internal_session() as s:
                return _agriculture_create_rfq(req=rreq, s=s)
        r = httpx.post(_agriculture_url("/rfqs"), json=body, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/agriculture/rfqs")
def agriculture_list_rfqs(status: str = "", city: str = "", limit: int = 100):
    params = {"limit": max(1, min(limit, 200))}
    if status:
        params["status"] = status
    if city:
        params["city"] = city
    try:
        if _use_agriculture_internal():
            if not _AGRICULTURE_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="agriculture internal not available")
            with _agriculture_internal_session() as s:
                return _agriculture_list_rfqs(status=status, city=city, limit=limit, s=s)
        r = httpx.get(_agriculture_url("/rfqs"), params=params, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/agriculture/rfqs/{rid}/reply")
async def agriculture_reply_rfq(rid: int, req: Request):
    _require_operator(req, "agriculture")
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        if _use_agriculture_internal():
            if not _AGRICULTURE_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="agriculture internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                rreq = _AgricultureRFQReplyCreate(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _agriculture_internal_session() as s:
                return _agriculture_reply_rfq(rid=rid, req=rreq, s=s)
        r = httpx.post(_agriculture_url(f"/rfqs/{rid}/reply"), json=body, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/agriculture/rfqs/{rid}/replies")
def agriculture_list_rfq_replies(rid: int):
    try:
        if _use_agriculture_internal():
            if not _AGRICULTURE_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="agriculture internal not available")
            with _agriculture_internal_session() as s:
                return _agriculture_list_rfq_replies(rid=rid, s=s)
        r = httpx.get(_agriculture_url(f"/rfqs/{rid}/replies"), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/agriculture/orders")
async def agriculture_create_order(req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        if _use_agriculture_internal():
            if not _AGRICULTURE_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="agriculture internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                oreq = _AgricultureOrderCreate(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _agriculture_internal_session() as s:
                return _agriculture_create_order(req=oreq, s=s)
        r = httpx.post(_agriculture_url("/orders"), json=body, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/agriculture/orders")
def agriculture_list_orders(status: str = "", limit: int = 100):
    params = {"limit": max(1, min(limit, 200))}
    if status:
        params["status"] = status
    try:
        if _use_agriculture_internal():
            if not _AGRICULTURE_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="agriculture internal not available")
            with _agriculture_internal_session() as s:
                return _agriculture_list_orders(status=status, limit=limit, s=s)
        r = httpx.get(_agriculture_url("/orders"), params=params, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.patch("/agriculture/orders/{oid}")
async def agriculture_update_order(oid: int, req: Request):
    _require_operator(req, "agriculture")
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        if _use_agriculture_internal():
            if not _AGRICULTURE_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="agriculture internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                oreq = _AgricultureOrderUpdate(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _agriculture_internal_session() as s:
                return _agriculture_update_order(oid=oid, req=oreq, s=s)
        r = httpx.patch(_agriculture_url(f"/orders/{oid}"), json=body, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


# ---- Livestock proxies ----
@app.get("/livestock/listings")
def livestock_listings(
    q: str = "",
    city: str = "",
    species: str = "",
    breed: str = "",
    status: str = "",
    limit: int = 50,
    offset: int = 0,
    min_price: int = None,
    max_price: int = None,
    sex: str = "",
    order: str = "",
    min_weight: float = None,
    max_weight: float = None,
    negotiable: bool = None,
):
    params = {"limit": max(1, min(limit, 200))}
    if offset and offset > 0:
        params["offset"] = max(0, offset)
    if q:
        params["q"] = q
    if city:
        params["city"] = city
    if species:
        params["species"] = species
    if breed:
        params["breed"] = breed
    if status:
        params["status"] = status
    if min_price is not None:
        params["min_price"] = min_price
    if max_price is not None:
        params["max_price"] = max_price
    if min_weight is not None:
        params["min_weight"] = min_weight
    if max_weight is not None:
        params["max_weight"] = max_weight
    if min_power is not None:
        params["min_power"] = min_power
    if max_power is not None:
        params["max_power"] = max_power
    if sex:
        params["sex"] = sex
    if order:
        params["order"] = order
    if min_weight is not None:
        params["min_weight"] = min_weight
    if max_weight is not None:
        params["max_weight"] = max_weight
    if negotiable is not None:
        params["negotiable"] = negotiable
    try:
        if _use_livestock_internal():
            if not _LIVESTOCK_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="livestock internal not available")
            with _livestock_internal_session() as s:
                return _livestock_list_listings(
                    q=q,
                    city=city,
                    species=species,
                    breed=breed,
                    status=status,
                    limit=limit,
                    offset=offset,
                    min_price=min_price,
                    max_price=max_price,
                    sex=sex,
                    order=order,
                    min_weight=min_weight,
                    max_weight=max_weight,
                    negotiable=negotiable,
                    s=s,
                )
        r = httpx.get(_livestock_url("/listings"), params=params, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/livestock/listings_cached")
def livestock_listings_cached(limit: int = 50, response: Response = None):  # type: ignore[assignment]
    """
    Cache for a simple livestock listing list without filters.
    For q/city/species please continue to use /livestock/listings.
    """
    global _LIVESTOCK_LISTINGS_CACHE
    if limit <= 0:
        limit = 50
    if _LIVESTOCK_LISTINGS_CACHE.get("data") is not None:
        try:
            ts = float(_LIVESTOCK_LISTINGS_CACHE.get("ts") or 0.0)
        except Exception:
            ts = 0.0
        if time.time() - ts < 30.0:
            data = _LIVESTOCK_LISTINGS_CACHE.get("data")
            try:
                if response is not None:
                    response.headers.setdefault("Cache-Control", "public, max-age=30")
            except Exception:
                pass
            return data
    data = livestock_listings(q="", city="", species="", limit=limit)
    _LIVESTOCK_LISTINGS_CACHE = {"ts": time.time(), "data": data}
    try:
        if response is not None:
            response.headers.setdefault("Cache-Control", "public, max-age=30")
    except Exception:
        pass
    return data


@app.post("/livestock/listings")
async def livestock_create_listing(req: Request):
    _require_operator(req, "livestock")
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        if _use_livestock_internal():
            if not _LIVESTOCK_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="livestock internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                lreq = _LivestockListingCreate(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _livestock_internal_session() as s:
                return _livestock_create_listing(req=lreq, s=s)
        r = httpx.post(_livestock_url("/listings"), json=body, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/livestock/listings/{lid}")
def livestock_get_listing(lid: int):
    try:
        if _use_livestock_internal():
            if not _LIVESTOCK_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="livestock internal not available")
            with _livestock_internal_session() as s:
                return _livestock_get_listing(lid=lid, s=s)
        r = httpx.get(_livestock_url(f"/listings/{lid}"), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.patch("/livestock/listings/{lid}")
async def livestock_update_listing(lid: int, req: Request):
    _require_operator(req, "livestock")
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        if _use_livestock_internal():
            if not _LIVESTOCK_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="livestock internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                lreq = _LivestockListingUpdate(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _livestock_internal_session() as s:
                return _livestock_update_listing(lid=lid, req=lreq, s=s)
        r = httpx.patch(_livestock_url(f"/listings/{lid}"), json=body, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/livestock/listings/{lid}/offers")
async def livestock_create_offer(lid: int, req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        if _use_livestock_internal():
            if not _LIVESTOCK_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="livestock internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            data["listing_id"] = lid
            try:
                oreq = _LivestockOfferCreate(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _livestock_internal_session() as s:
                return _livestock_create_offer(lid=lid, req=oreq, s=s)
        r = httpx.post(_livestock_url(f"/listings/{lid}/offers"), json=body, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/livestock/listings/{lid}/offers")
def livestock_list_offers(lid: int, req: Request):
    _require_operator(req, "livestock")
    try:
        if _use_livestock_internal():
            if not _LIVESTOCK_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="livestock internal not available")
            with _livestock_internal_session() as s:
                return _livestock_list_offers(lid=lid, s=s)
        r = httpx.get(_livestock_url(f"/listings/{lid}/offers"), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.patch("/livestock/offers/{oid}")
async def livestock_update_offer(oid: int, req: Request):
    _require_operator(req, "livestock")
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        if _use_livestock_internal():
            if not _LIVESTOCK_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="livestock internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                oreq = _LivestockOfferUpdate(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _livestock_internal_session() as s:
                return _livestock_update_offer(oid=oid, req=oreq, s=s)
        r = httpx.patch(_livestock_url(f"/offers/{oid}"), json=body, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/stays/listings/search")
def stays_listings_search(q: str = "", city: str = "", type: str = "", limit: int = 50, offset: int = 0, sort_by: str = "created_at", order: str = "desc"):
    params = {"limit": max(1, min(limit, 200)), "offset": max(0, offset), "sort_by": sort_by, "order": order}
    if q:
        params["q"] = q
    if city:
        params["city"] = city
    if type:
        params["type"] = type
    try:
        if _use_stays_internal():
            if not _STAYS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="stays internal not available")
            with _stays_internal_session() as s:
                return _stays_list_listings_search(q=q, city=city, type=type, limit=limit, offset=offset, sort_by=sort_by, order=order, s=s)
        r = httpx.get(_stays_url("/listings/search"), params=params, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/stays/listings")
async def stays_create_listing(req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        if _use_stays_internal():
            if not _STAYS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="stays internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                lreq = _StaysListingCreate(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            ikey = None
            try:
                ikey = req.headers.get("Idempotency-Key")
            except Exception:
                ikey = None
            with _stays_internal_session() as s:
                return _stays_create_listing(req=lreq, idempotency_key=ikey, s=s)
        r = httpx.post(_stays_url("/listings"), json=body, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/stays/quote")
async def stays_quote(req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        if _use_stays_internal():
            if not _STAYS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="stays internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                qreq = _StaysQuoteReq(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _stays_internal_session() as s:
                return _stays_quote(req=qreq, s=s)
        r = httpx.post(_stays_url("/quote"), json=body, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/stays/book")
async def stays_book(req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    headers: dict[str, str] = {}
    try:
        ikey = req.headers.get("Idempotency-Key")
    except Exception:
        ikey = None
    if ikey:
        headers["Idempotency-Key"] = ikey
    try:
        if _use_stays_internal():
            if not _STAYS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="stays internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                breq = _StaysBookReq(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _stays_internal_session() as s:
                return _stays_book(req=breq, idempotency_key=ikey, s=s)
        r = httpx.post(_stays_url("/book"), json=body, headers=headers, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/stays/bookings/{bid}")
def stays_get_booking(bid: str):
    try:
        if _use_stays_internal():
            if not _STAYS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="stays internal not available")
            with _stays_internal_session() as s:
                return _stays_get_booking(booking_id=bid, s=s)
        r = httpx.get(_stays_url(f"/bookings/{bid}"), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


# -- Stays operators (hotels)
@app.post("/stays/operators")
async def stays_create_operator(req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    headers: dict[str, str] = {}
    try:
        ikey = req.headers.get("Idempotency-Key")
    except Exception:
        ikey = None
    if ikey:
        headers["Idempotency-Key"] = ikey
    try:
        if _use_stays_internal():
            if not _STAYS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="stays internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                oreq = _StaysOperatorCreate(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _stays_internal_session() as s:
                return _stays_create_operator(req=oreq, idempotency_key=ikey, s=s)
        r = httpx.post(_stays_url("/operators"), json=body, headers=headers, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/stays/operators/{op_id}")
def stays_get_operator(op_id: int):
    try:
        if _use_stays_internal():
            if not _STAYS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="stays internal not available")
            with _stays_internal_session() as s:
                return _stays_get_operator(op_id=op_id, s=s)
        r = httpx.get(_stays_url(f"/operators/{op_id}"), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/stays/operators/{op_id}/listings")
def stays_operator_listings(op_id: int, req: Request, limit: int = 50, offset: int = 0, q: str = "", city: str = ""):
    try:
        params = {"limit": max(1, min(limit, 200)), "offset": max(0, offset)}
        if q:
            params["q"] = q
        if city:
            params["city"] = city
        if _use_stays_internal():
            if not _STAYS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="stays internal not available")
            property_id = None
            try:
                pid = req.query_params.get("property_id")
                if pid:
                    property_id = int(pid)
            except Exception:
                property_id = None
            with _stays_internal_session() as s:
                return _stays_operator_listings(
                    op_id=op_id,
                    request=req,
                    limit=limit,
                    offset=offset,
                    q=q,
                    city=city,
                    property_id=property_id,
                    s=s,
                )
        headers: dict[str, str] = {}
        try:
            auth = req.headers.get("authorization")
            if auth:
                headers["Authorization"] = auth
        except Exception:
            pass
        r = httpx.get(_stays_url(f"/operators/{op_id}/listings"), params=params, headers=headers, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/stays/operators/{op_id}/listings")
async def stays_operator_create_listing(op_id: int, req: Request):
    _require_operator(req, "stays")
    try:
        body = await req.json()
    except Exception:
        body = {}
    body = body or {}
    body.setdefault("operator_id", op_id)
    try:
        headers: dict[str, str] = {}
        try:
            auth = req.headers.get("authorization")
            if auth:
                headers["Authorization"] = auth
        except Exception:
            pass
        if _use_stays_internal():
            if not _STAYS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="stays internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                lreq = _StaysListingCreate(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _stays_internal_session() as s:
                return _stays_operator_create_listing(op_id=op_id, req=lreq, request=req, s=s)
        r = httpx.post(_stays_url(f"/operators/{op_id}/listings"), json=body, headers=headers, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.patch("/stays/operators/{op_id}/listings/{lid}")
async def stays_operator_update_listing(op_id: int, lid: int, req: Request):
    _require_operator(req, "stays")
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        headers: dict[str, str] = {}
        try:
            auth = req.headers.get("authorization")
            if auth:
                headers["Authorization"] = auth
        except Exception:
            pass
        if _use_stays_internal():
            if not _STAYS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="stays internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                ureq = _StaysListingUpdate(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _stays_internal_session() as s:
                return _stays_operator_update_listing(op_id=op_id, lid=lid, req=ureq, request=req, s=s)
        r = httpx.patch(_stays_url(f"/operators/{op_id}/listings/{lid}"), json=body, headers=headers, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.delete("/stays/operators/{op_id}/listings/{lid}")
def stays_operator_delete_listing(op_id: int, lid: int, req: Request):
    _require_operator(req, "stays")
    try:
        if _use_stays_internal():
            if not _STAYS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="stays internal not available")
            with _stays_internal_session() as s:
                return _stays_operator_delete_listing(op_id=op_id, lid=lid, request=req, s=s)
        headers: dict[str, str] = {}
        try:
            auth = req.headers.get("authorization")
            if auth:
                headers["Authorization"] = auth
        except Exception:
            pass
        r = httpx.delete(_stays_url(f"/operators/{op_id}/listings/{lid}"), headers=headers, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/stays/operators/{op_id}/bookings")
def stays_operator_bookings(op_id: int, req: Request, limit: int = 50, offset: int = 0):
    _require_operator(req, "stays")
    try:
        headers: dict[str, str] = {}
        try:
            auth = req.headers.get("authorization")
            if auth:
                headers["Authorization"] = auth
        except Exception:
            pass
        params = {"limit": max(1, min(limit, 200)), "offset": max(0, offset)}
        if _use_stays_internal():
            if not _STAYS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="stays internal not available")
            with _stays_internal_session() as s:
                return _stays_operator_bookings(op_id=op_id, request=req, limit=limit, offset=offset, s=s)
        r = httpx.get(_stays_url(f"/operators/{op_id}/bookings"), params=params, headers=headers, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))
@app.get("/stays/operators/{op_id}/bookings/search")
def stays_operator_bookings_search(op_id: int, req: Request, limit: int = 50, offset: int = 0, sort_by: str = "created_at", order: str = "desc", status: str = "", from_iso: str = "", to_iso: str = ""):
    _require_operator(req, "stays")
    try:
        headers: dict[str, str] = {}
        try:
            auth = req.headers.get("authorization")
            if auth:
                headers["Authorization"] = auth
        except Exception:
            pass
        params = {"limit": max(1, min(limit, 200)), "offset": max(0, offset), "sort_by": sort_by, "order": order}
        if status:
            params["status"] = status
        if from_iso:
            params["from_iso"] = from_iso
        if to_iso:
            params["to_iso"] = to_iso
        if _use_stays_internal():
            if not _STAYS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="stays internal not available")
            property_id = None
            try:
                pid = req.query_params.get("property_id")
                if pid:
                    property_id = int(pid)
            except Exception:
                property_id = None
            with _stays_internal_session() as s:
                return _stays_operator_bookings_search(
                    op_id=op_id,
                    request=req,
                    limit=limit,
                    offset=offset,
                    sort_by=sort_by,
                    order=order,
                    status=status,
                    from_iso=from_iso,
                    to_iso=to_iso,
                    s=s,
                )
        try:
            pid = req.query_params.get("property_id")
            if pid:
                params["property_id"] = pid
        except Exception:
            pass
        r = httpx.get(_stays_url(f"/operators/{op_id}/bookings/search"), params=params, headers=headers, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/stays/operators/{op_id}/bookings/{bid}/status")
async def stays_operator_update_booking_status(op_id: int, bid: str, req: Request):
    _require_operator(req, "stays")
    try:
        try:
            body = await req.json()
        except Exception:
            body = None
        headers: dict[str, str] = {}
        try:
            auth = req.headers.get("authorization")
            if auth:
                headers["Authorization"] = auth
        except Exception:
            pass
        if _use_stays_internal():
            if not _STAYS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="stays internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                sreq = _StaysBookingStatusUpdate(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _stays_internal_session() as s:
                return _stays_operator_update_booking_status(op_id=op_id, bid=bid, req=sreq, request=req, s=s)
        r = httpx.post(_stays_url(f"/operators/{op_id}/bookings/{bid}/status"), json=body, headers=headers, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


# ---- RealEstate proxies ----
def _re_url(path: str) -> str:
    if not REALESTATE_BASE:
        raise HTTPException(status_code=500, detail="REALESTATE_BASE_URL not configured")
    return REALESTATE_BASE.rstrip("/") + path


# --- RealEstate internal service (monolith mode) ---
_RE_INTERNAL_AVAILABLE = False
try:
    from sqlalchemy.orm import Session as _ReSession  # type: ignore[import]
    from apps.realestate.app import main as _re_main  # type: ignore[import]
    from apps.realestate.app.main import (  # type: ignore[import]
        engine as _re_engine,
        PropertyCreate as _RePropertyCreate,
        PropertyUpdate as _RePropertyUpdate,
        PropertyOut as _RePropertyOut,
        InquiryCreate as _ReInquiryCreate,
        ReserveReq as _ReReserveReq,
        create_property as _re_create_property,
        list_properties as _re_list_properties,
        get_property as _re_get_property,
        update_property as _re_update_property,
        delete_property as _re_delete_property,
        create_inquiry as _re_create_inquiry,
        reserve as _re_reserve,
    )
    _RE_INTERNAL_AVAILABLE = True
except Exception:
    _ReSession = None  # type: ignore[assignment]
    _re_engine = None  # type: ignore[assignment]
    _RE_INTERNAL_AVAILABLE = False


def _use_re_internal() -> bool:
    if _force_internal(_RE_INTERNAL_AVAILABLE):
        return True
    mode = os.getenv("REALESTATE_INTERNAL_MODE", "auto").lower()
    if mode == "off":
        return False
    if not _RE_INTERNAL_AVAILABLE:
        return False
    if mode == "on":
        return True
    return not bool(REALESTATE_BASE)


def _re_internal_session():
    if not _RE_INTERNAL_AVAILABLE or _ReSession is None or _re_engine is None:  # type: ignore[truthy-function]
        raise RuntimeError("RealEstate internal service not available")
    return _ReSession(_re_engine)  # type: ignore[call-arg]


@app.get("/realestate/properties")
def re_list_properties(q: str = "", city: str = "", min_price: str = "", max_price: str = "", min_bedrooms: str = "", limit: int = 20):
    params = {"limit": max(1, min(limit, 100))}
    if q: params["q"] = q
    if city: params["city"] = city
    def _to_int(val: str) -> Optional[int]:
        try:
            if val is None or val == "":
                return None
            return int(val)
        except Exception:
            return None
    min_p_in = _to_int(min_price)
    max_p_in = _to_int(max_price)
    min_beds_in = _to_int(min_bedrooms)
    if min_p_in is not None: params["min_price"] = min_p_in
    if max_p_in is not None: params["max_price"] = max_p_in
    if min_beds_in is not None: params["min_bedrooms"] = min_beds_in
    try:
        if _use_re_internal():
            if not _RE_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="realestate internal not available")
            # convert sentinel 0 to None for optional filters
            min_p = None if not min_p_in or min_p_in <= 0 else min_p_in
            max_p = None if not max_p_in or max_p_in <= 0 else max_p_in
            min_beds = None if not min_beds_in or min_beds_in <= 0 else min_beds_in
            with _re_internal_session() as s:
                return _re_list_properties(q=q, city=city, min_price=min_p, max_price=max_p, min_bedrooms=min_beds, limit=limit, s=s)
        r = httpx.get(_re_url("/properties"), params=params, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/realestate/properties")
async def re_create_property(req: Request):
    _require_operator(req, "realestate")
    try:
        body = await req.json()
    except Exception:
        body = None
    headers: dict[str, str] = {}
    try:
        ikey = req.headers.get("Idempotency-Key")
    except Exception:
        ikey = None
    if ikey:
        headers["Idempotency-Key"] = ikey
    try:
        if _use_re_internal():
            if not _RE_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="realestate internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                preq = _RePropertyCreate(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _re_internal_session() as s:
                return _re_create_property(req=preq, idempotency_key=ikey, s=s)
        r = httpx.post(_re_url("/properties"), json=body, headers=headers, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/realestate/properties/{pid}")
def re_get_property(pid: int):
    try:
        if _use_re_internal():
            if not _RE_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="realestate internal not available")
            with _re_internal_session() as s:
                return _re_get_property(pid=pid, s=s)
        r = httpx.get(_re_url(f"/properties/{pid}"), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/realestate/properties/{pid}")
async def re_update_property(pid: int, req: Request):
    _require_operator(req, "realestate")
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        if _use_re_internal():
            if not _RE_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="realestate internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                ureq = _RePropertyUpdate(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _re_internal_session() as s:
                return _re_update_property(pid=pid, req=ureq, s=s)
        r = httpx.patch(_re_url(f"/properties/{pid}"), json=body, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/realestate/inquiries")
async def re_create_inquiry(req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    headers: dict[str, str] = {}
    try:
        ikey = req.headers.get("Idempotency-Key")
    except Exception:
        ikey = None
    if ikey:
        headers["Idempotency-Key"] = ikey
    try:
        if _use_re_internal():
            if not _RE_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="realestate internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                ireq = _ReInquiryCreate(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _re_internal_session() as s:
                return _re_create_inquiry(req=ireq, idempotency_key=ikey, s=s)
        r = httpx.post(_re_url("/inquiries"), json=body, headers=headers, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/realestate/reserve")
async def re_reserve(req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    headers: dict[str, str] = {}
    try:
        ikey = req.headers.get("Idempotency-Key")
    except Exception:
        ikey = None
    if ikey:
        headers["Idempotency-Key"] = ikey
    try:
        if _use_re_internal():
            if not _RE_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="realestate internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                rreq = _ReReserveReq(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _re_internal_session() as s:
                return _re_reserve(req=rreq, idempotency_key=ikey, s=s)
        r = httpx.post(_re_url("/reserve"), json=body, headers=headers, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


# ---- Food proxies (internal-only) ----
# --- Food internal service (monolith mode) ---
_FOOD_INTERNAL_AVAILABLE = False
try:
    from sqlalchemy.orm import Session as _FoodSession  # type: ignore[import]
    from apps.food.app import main as _food_main  # type: ignore[import]
    from apps.food.app.main import (  # type: ignore[import]
        engine as _food_engine,
        get_session as _food_get_session,
        RestaurantCreate as _FoodRestaurantCreate,
        MenuItemCreate as _FoodMenuItemCreate,
        OrderCreate as _FoodOrderCreate,
        StatusReq as _FoodStatusReq,
        RestaurantOut as _FoodRestaurantOut,
        OrderOut as _FoodOrderOut,
        create_restaurant as _food_create_restaurant,
        list_restaurants as _food_list_restaurants,
        get_restaurant as _food_get_restaurant,
        get_menu as _food_get_menu,
        create_menu_item as _food_create_menuitem,
        create_order as _food_create_order,
        get_order as _food_get_order,
        set_status as _food_set_status,
        list_orders as _food_list_orders,
        EscrowReleaseReq as _FoodEscrowReleaseReq,
        escrow_release as _food_escrow_release,
    )
    _FOOD_INTERNAL_AVAILABLE = True
except Exception:
    _FoodSession = None  # type: ignore[assignment]
    _food_main = None  # type: ignore[assignment]
    _food_engine = None  # type: ignore[assignment]
    _FOOD_INTERNAL_AVAILABLE = False


def _use_food_internal() -> bool:
    if _force_internal(_FOOD_INTERNAL_AVAILABLE):
        return True
    if not _FOOD_INTERNAL_AVAILABLE:
        return False
    mode = os.getenv("FOOD_INTERNAL_MODE", "on").lower()
    return mode != "off"


def _food_internal_session():
    if not _FOOD_INTERNAL_AVAILABLE or _FoodSession is None or _food_engine is None:  # type: ignore[truthy-function]
        raise RuntimeError("Food internal service not available")
    return _FoodSession(_food_engine)  # type: ignore[call-arg]


@app.get("/food/restaurants")
def food_restaurants(q: str = "", city: str = "", limit: int = 50):
    params = {"limit": max(1, min(limit,200))}
    if q: params["q"] = q
    if city: params["city"] = city
    if not _use_food_internal() or not _FOOD_INTERNAL_AVAILABLE:
        raise HTTPException(status_code=500, detail="food internal not available")
    with _food_internal_session() as s:
        return _food_list_restaurants(q=q, city=city, limit=limit, s=s)  # type: ignore[arg-type]


@app.post("/food/restaurants")
async def food_create_restaurant(req: Request):
    _require_operator(req, "food")
    try:
        body = await req.json()
    except Exception:
        body = None
    if not _use_food_internal() or not _FOOD_INTERNAL_AVAILABLE:
        raise HTTPException(status_code=500, detail="food internal not available")
    data = body or {}
    if not isinstance(data, dict):
        data = {}
    try:
        rc = _FoodRestaurantCreate(**data)
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))
    with _food_internal_session() as s:
        return _food_create_restaurant(req=rc, s=s)


@app.get("/food/restaurants/{rid}")
def food_get_restaurant(rid: int):
    if not _use_food_internal() or not _FOOD_INTERNAL_AVAILABLE:
        raise HTTPException(status_code=500, detail="food internal not available")
    with _food_internal_session() as s:
        return _food_get_restaurant(rid=rid, s=s)


@app.get("/food/restaurants/{rid}/menu")
def food_get_menu(rid: int):
    if not _use_food_internal() or not _FOOD_INTERNAL_AVAILABLE:
        raise HTTPException(status_code=500, detail="food internal not available")
    with _food_internal_session() as s:
        return _food_get_menu(rid=rid, s=s)


@app.post("/food/menuitems")
async def food_create_menuitem(req: Request):
    _require_operator(req, "food")
    try:
        body = await req.json()
    except Exception:
        body = None
    if not _use_food_internal() or not _FOOD_INTERNAL_AVAILABLE:
        raise HTTPException(status_code=500, detail="food internal not available")
    data = body or {}
    if not isinstance(data, dict):
        data = {}
    try:
        mi = _FoodMenuItemCreate(**data)
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))
    with _food_internal_session() as s:
        return _food_create_menuitem(req=mi, s=s)


@app.post("/food/orders")
async def food_create_order(req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    headers = {}
    try:
        ikey = req.headers.get("Idempotency-Key")
    except Exception:
        ikey = None
    if ikey:
        headers["Idempotency-Key"] = ikey
    if not _use_food_internal() or not _FOOD_INTERNAL_AVAILABLE:
        raise HTTPException(status_code=500, detail="food internal not available")
    data = body or {}
    if not isinstance(data, dict):
        data = {}
    try:
        oc = _FoodOrderCreate(**data)
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))
    with _food_internal_session() as s:
        return _food_create_order(req=oc, idempotency_key=ikey, s=s)


@app.get("/food/orders")
def food_list_orders(phone: str = "", limit: int = 50, status: str = "", from_iso: str = "", to_iso: str = ""):
    if not _use_food_internal() or not _FOOD_INTERNAL_AVAILABLE:
        raise HTTPException(status_code=500, detail="food internal not available")
    with _food_internal_session() as s:
        return _food_list_orders(phone=phone, status=status, from_iso=from_iso, to_iso=to_iso, limit=limit, s=s)


@app.get("/food/orders/{oid}")
def food_get_order(oid: str):
    if not _use_food_internal() or not _FOOD_INTERNAL_AVAILABLE:
        raise HTTPException(status_code=500, detail="food internal not available")
    with _food_internal_session() as s:
        return _food_get_order(oid=oid, s=s)


@app.post("/food/orders/{oid}/status")
async def food_set_status(oid: str, req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    if not _use_food_internal() or not _FOOD_INTERNAL_AVAILABLE:
        raise HTTPException(status_code=500, detail="food internal not available")
    data = body or {}
    if not isinstance(data, dict):
        data = {}
    try:
        sreq = _FoodStatusReq(**data)
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))
    with _food_internal_session() as s:
        return _food_set_status(oid=oid, req=sreq, s=s)


@app.post("/food/orders/{oid}/escrow_release")
async def food_escrow_release(oid: str, req: Request):
    """
    Proxy for releasing escrow on a Food order after the customer
    has scanned the courier's delivery QR code.
    """
    try:
        body = await req.json()
    except Exception:
        body = None
    if not _use_food_internal() or not _FOOD_INTERNAL_AVAILABLE:
        raise HTTPException(status_code=500, detail="food internal not available")
    data = body or {}
    if not isinstance(data, dict):
        data = {}
    try:
        ereq = _FoodEscrowReleaseReq(**data)
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))
    with _food_internal_session() as s:
        return _food_escrow_release(oid=oid, req=ereq, s=s)


@app.get("/food/orders/{oid}/escrow_qr")
def food_escrow_qr(oid: str):
    """
    Generate a QR code (PNG) for a Food order escrow token.
    The QR payload is a compact text format consumed by the
    Shamell app: FOOD_ESCROW|order_id=...|token=...
    """
    if not _use_food_internal() or not _FOOD_INTERNAL_AVAILABLE:
        raise HTTPException(status_code=500, detail="food internal not available")
    with _food_internal_session() as s:
        o = _food_get_order(oid=oid, s=s)
        try:
            od = o.dict() if hasattr(o, "dict") else o  # type: ignore[assignment]
        except Exception:
            od = {}

    if not isinstance(od, dict):
        raise HTTPException(status_code=502, detail="invalid order payload from food service")
    token = (od.get("escrow_token") or "").strip()
    if not token:
        raise HTTPException(status_code=400, detail="order has no escrow token")
    try:
        from urllib.parse import quote

        payload = "FOOD_ESCROW|order_id=" + oid + "|token=" + quote(token, safe="")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"failed to build QR payload: {e}")
    # Reuse generic QR PNG endpoint.
    return qr_png(payload)


# ---- Carrental proxies ----
def _carrental_url(path: str) -> str:
    if not CARRENTAL_BASE:
        raise HTTPException(status_code=500, detail="CARRENTAL_BASE_URL not configured")
    return CARRENTAL_BASE.rstrip("/") + path


# --- Carrental internal service (monolith mode) ---
_CARRENTAL_INTERNAL_AVAILABLE = False
try:
    from sqlalchemy.orm import Session as _CarrentalSession  # type: ignore[import]
    from apps.carrental.app import main as _carrental_main  # type: ignore[import]
    from apps.carrental.app.main import (  # type: ignore[import]
        engine as _carrental_engine,
        get_session as _carrental_get_session,
        CarCreate as _CarrentalCarCreate,
        CarUpdate as _CarrentalCarUpdate,
        CarOut as _CarrentalCarOut,
        QuoteReq as _CarrentalQuoteReq,
        QuoteOut as _CarrentalQuoteOut,
        BookReq as _CarrentalBookReq,
        BookingOut as _CarrentalBookingOut,
        ConfirmReq as _CarrentalConfirmReq,
        create_car as _carrental_create_car,
        list_cars as _carrental_list_cars,
        get_car as _carrental_get_car,
        update_car as _carrental_update_car,
        delete_car as _carrental_delete_car,
        quote as _carrental_quote,
        book as _carrental_book,
        get_booking as _carrental_get_booking,
        list_bookings as _carrental_list_bookings,
        confirm_booking as _carrental_confirm_booking,
        cancel_booking as _carrental_cancel_booking,
        admin_cars_export as _carrental_admin_cars_export,
        admin_bookings_export as _carrental_admin_bookings_export,
    )
    _CARRENTAL_INTERNAL_AVAILABLE = True
except Exception:
    _CarrentalSession = None  # type: ignore[assignment]
    _carrental_engine = None  # type: ignore[assignment]
    _CARRENTAL_INTERNAL_AVAILABLE = False


def _use_carrental_internal() -> bool:
    if _force_internal(_CARRENTAL_INTERNAL_AVAILABLE):
        return True
    mode = os.getenv("CARRENTAL_INTERNAL_MODE", "auto").lower()
    if mode == "off":
        return False
    if not _CARRENTAL_INTERNAL_AVAILABLE:
        return False
    if mode == "on":
        return True
    return not bool(CARRENTAL_BASE)


def _carrental_internal_session():
    if not _CARRENTAL_INTERNAL_AVAILABLE or _CarrentalSession is None or _carrental_engine is None:  # type: ignore[truthy-function]
        raise RuntimeError("Carrental internal service not available")
    return _CarrentalSession(_carrental_engine)  # type: ignore[call-arg]


@app.get("/carrental/cars")
def cr_list_cars(
    q: str = "",
    city: str = "",
    dropoff_city: str = "",
    make: str = "",
    transmission: str = "",
    fuel: str = "",
    car_class: str = "",
    max_price: int = None,
    min_seats: int = None,
    free_cancel: bool = None,
    unlimited_mileage: bool = None,
    limit: int = 20,
):
    params = {"limit": max(1, min(limit, 100))}
    if q:
        params["q"] = q
    if city:
        params["city"] = city
    if dropoff_city:
        params["dropoff_city"] = dropoff_city
    if make:
        params["make"] = make
    if transmission:
        params["transmission"] = transmission
    if fuel:
        params["fuel"] = fuel
    if car_class:
        params["car_class"] = car_class
    if max_price is not None:
        params["max_price"] = max_price
    if min_seats is not None:
        params["min_seats"] = min_seats
    if free_cancel is not None:
        params["free_cancel"] = free_cancel
    if unlimited_mileage is not None:
        params["unlimited_mileage"] = unlimited_mileage
    try:
        if _use_carrental_internal():
            if not _CARRENTAL_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="carrental internal not available")
            with _carrental_internal_session() as s:
                return _carrental_list_cars(
                    q=q,
                    city=city,
                    dropoff_city=dropoff_city,
                    make=make,
                    transmission=transmission,
                    fuel=fuel,
                    car_class=car_class,
                    max_price=max_price,
                    min_seats=min_seats,
                    free_cancel=free_cancel,
                    unlimited_mileage=unlimited_mileage,
                    limit=limit,
                    s=s,
                )
        r = httpx.get(_carrental_url("/cars"), params=params, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/carrental/cars")
async def cr_create_car(req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        if _use_carrental_internal():
            if not _CARRENTAL_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="carrental internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                creq = _CarrentalCarCreate(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _carrental_internal_session() as s:
                return _carrental_create_car(req=creq, s=s)
        r = httpx.post(_carrental_url("/cars"), json=body, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/carrental/cars/{car_id}")
def cr_get_car(car_id: int):
    try:
        if _use_carrental_internal():
            if not _CARRENTAL_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="carrental internal not available")
            with _carrental_internal_session() as s:
                return _carrental_get_car(car_id=car_id, s=s)
        r = httpx.get(_carrental_url(f"/cars/{car_id}"), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/carrental/quote")
async def cr_quote(req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        if _use_carrental_internal():
            if not _CARRENTAL_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="carrental internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                qreq = _CarrentalQuoteReq(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _carrental_internal_session() as s:
                return _carrental_quote(req=qreq, s=s)
        r = httpx.post(_carrental_url("/quote"), json=body, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/carrental/book")
async def cr_book(req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    headers: dict[str, str] = {}
    try:
        ikey = req.headers.get("Idempotency-Key")
    except Exception:
        ikey = None
    if ikey:
        headers["Idempotency-Key"] = ikey
    try:
        if _use_carrental_internal():
            if not _CARRENTAL_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="carrental internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                breq = _CarrentalBookReq(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _carrental_internal_session() as s:
                return _carrental_book(req=breq, idempotency_key=ikey, s=s)
        r = httpx.post(_carrental_url("/book"), json=body, headers=headers, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/carrental/bookings/{booking_id}")
def cr_get_booking(booking_id: str):
    try:
        if _use_carrental_internal():
            if not _CARRENTAL_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="carrental internal not available")
            with _carrental_internal_session() as s:
                return _carrental_get_booking(booking_id=booking_id, s=s)
        r = httpx.get(_carrental_url(f"/bookings/{booking_id}"), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/carrental/bookings/{booking_id}/cancel")
def cr_cancel_booking(booking_id: str):
    try:
        if _use_carrental_internal():
            if not _CARRENTAL_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="carrental internal not available")
            with _carrental_internal_session() as s:
                return _carrental_cancel_booking(booking_id=booking_id, s=s)
        r = httpx.post(_carrental_url(f"/bookings/{booking_id}/cancel"), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/carrental/bookings/{booking_id}/confirm")
async def cr_confirm_booking(booking_id: str, req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        if _use_carrental_internal():
            if not _CARRENTAL_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="carrental internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                creq = _CarrentalConfirmReq(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _carrental_internal_session() as s:
                return _carrental_confirm_booking(booking_id=booking_id, req=creq, s=s)
        r = httpx.post(_carrental_url(f"/bookings/{booking_id}/confirm"), json=body, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/carrental/bookings")
def cr_list_bookings(status: str = "", limit: int = 100):
    params = {"limit": max(1, min(limit, 500))}
    if status:
        params["status"] = status
    try:
        if _use_carrental_internal():
            if not _CARRENTAL_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="carrental internal not available")
            with _carrental_internal_session() as s:
                return _carrental_list_bookings(status=status, limit=limit, s=s)
        r = httpx.get(_carrental_url("/bookings"), params=params, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/carrental/admin/cars/export")
def cr_export_cars(request: Request):
    _require_operator(request, "carrental")
    try:
        if _use_carrental_internal():
            if not _CARRENTAL_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="carrental internal not available")
            with _carrental_internal_session() as s:
                return _carrental_admin_cars_export(s=s)
        r = httpx.get(_carrental_url("/admin/cars/export"), timeout=None)
        disp = r.headers.get("content-disposition", "attachment; filename=cars.csv")
        return Response(content=r.content, media_type="text/csv", headers={"Content-Disposition": disp})
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/carrental/admin/bookings/export")
def cr_export_bookings(request: Request, status: str = "", limit: int = 1000):
    _require_operator(request, "carrental")
    params = {"limit": max(1, min(limit, 5000))}
    if status:
        params["status"] = status
    try:
        if _use_carrental_internal():
            if not _CARRENTAL_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="carrental internal not available")
            with _carrental_internal_session() as s:
                return _carrental_admin_bookings_export(status=status, limit=limit, s=s)
        r = httpx.get(_carrental_url("/admin/bookings/export"), params=params, timeout=None)
        disp = r.headers.get("content-disposition", "attachment; filename=bookings.csv")
        return Response(content=r.content, media_type="text/csv", headers={"Content-Disposition": disp})
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


# ---- Equipment proxies ----
def _equipment_url(path: str) -> str:
    if not EQUIPMENT_BASE:
        raise HTTPException(status_code=500, detail="EQUIPMENT_BASE_URL not configured")
    return EQUIPMENT_BASE.rstrip("/") + path


_EQUIPMENT_INTERNAL_AVAILABLE = False
try:
    from sqlalchemy.orm import Session as _EquipmentSession  # type: ignore[import]
    from apps.equipment.app import main as _equipment_main  # type: ignore[import]
    from apps.equipment.app.main import (  # type: ignore[import]
        engine as _equipment_engine,
        get_session as _equipment_get_session,
        EquipmentCreate as _EquipmentCreate,
        EquipmentUpdate as _EquipmentUpdate,
        EquipmentOut as _EquipmentOut,
        QuoteReq as _EquipmentQuoteReq,
        QuoteOut as _EquipmentQuoteOut,
        BookReq as _EquipmentBookReq,
        BookingOut as _EquipmentBookingOut,
        BookingStatusUpdate as _EquipmentStatusUpdate,
        TaskUpdate as _EquipmentTaskUpdate,
        create_asset as _equipment_create_asset,
        list_assets as _equipment_list_assets,
        get_asset as _equipment_get_asset,
        update_asset as _equipment_update_asset,
        delete_asset as _equipment_delete_asset,
        quote as _equipment_quote,
        book as _equipment_book,
        list_bookings as _equipment_list_bookings,
        get_booking as _equipment_get_booking,
        update_booking_status as _equipment_update_booking_status,
        update_logistics as _equipment_update_logistics,
        analytics_summary as _equipment_analytics,
        dashboard as _equipment_dashboard,
    )
    _EQUIPMENT_INTERNAL_AVAILABLE = True
except Exception:
    _EquipmentSession = None  # type: ignore[assignment]
    _equipment_engine = None  # type: ignore[assignment]
    _EQUIPMENT_INTERNAL_AVAILABLE = False


def _use_equipment_internal() -> bool:
    if _force_internal(_EQUIPMENT_INTERNAL_AVAILABLE):
        return True
    mode = os.getenv("EQUIPMENT_INTERNAL_MODE", "auto").lower()
    if mode == "off":
        return False
    if not _EQUIPMENT_INTERNAL_AVAILABLE:
        return False
    if mode == "on":
        return True
    return not bool(EQUIPMENT_BASE)


def _equipment_internal_session():
    if not _EQUIPMENT_INTERNAL_AVAILABLE or _EquipmentSession is None or _equipment_engine is None:  # type: ignore[truthy-function]
        raise RuntimeError("Equipment internal service not available")
    return _EquipmentSession(_equipment_engine)  # type: ignore[call-arg]


@app.get("/equipment/assets")
def equipment_list_assets(
    q: str = "",
    city: str = "",
    category: str = "",
    subcategory: str = "",
    tag: str = "",
    status: str = "",
    available_only: bool = False,
    from_iso: str = "",
    to_iso: str = "",
    min_price: int = None,
    max_price: int = None,
    min_weight: float = None,
    max_weight: float = None,
    min_power: float = None,
    max_power: float = None,
    order: str = "newest",
    near_lat: float = None,
    near_lon: float = None,
    max_distance_km: float = None,
    limit: int = 50,
):
    params = {"limit": max(1, min(limit, 200))}
    if q:
        params["q"] = q
    if city:
        params["city"] = city
    if category:
        params["category"] = category
    if subcategory:
        params["subcategory"] = subcategory
    if tag:
        params["tag"] = tag
    if status:
        params["status"] = status
    if available_only:
        params["available_only"] = available_only
    if from_iso:
        params["from_iso"] = from_iso
    if to_iso:
        params["to_iso"] = to_iso
    if min_price is not None:
        params["min_price"] = min_price
    if max_price is not None:
        params["max_price"] = max_price
    if order:
        params["order"] = order
    if near_lat is not None:
        params["near_lat"] = near_lat
    if near_lon is not None:
        params["near_lon"] = near_lon
    if max_distance_km is not None:
        params["max_distance_km"] = max_distance_km
    try:
        if _use_equipment_internal():
            if not _EQUIPMENT_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="equipment internal not available")
            with _equipment_internal_session() as s:
                return _equipment_list_assets(
                    q=q,
                    city=city,
                    category=category,
                    subcategory=subcategory,
                    tag=tag,
                    status=status,
                    available_only=available_only,
                    from_iso=from_iso,
                    to_iso=to_iso,
                    min_price=min_price,
                    max_price=max_price,
                    min_weight=min_weight,
                    max_weight=max_weight,
                    min_power=min_power,
                    max_power=max_power,
                    order=order,
                    near_lat=near_lat,
                    near_lon=near_lon,
                    max_distance_km=max_distance_km,
                    limit=limit,
                    s=s,
                )
        r = httpx.get(_equipment_url("/assets"), params=params, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/equipment/assets")
async def equipment_create_asset(req: Request):
    _require_operator(req, "equipment")
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        if _use_equipment_internal():
            if not _EQUIPMENT_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="equipment internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                creq = _EquipmentCreate(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _equipment_internal_session() as s:
                return _equipment_create_asset(req=creq, s=s)
        r = httpx.post(_equipment_url("/assets"), json=body, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.patch("/equipment/assets/{equipment_id}")
async def equipment_update_asset(equipment_id: int, req: Request):
    _require_operator(req, "equipment")
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        if _use_equipment_internal():
            if not _EQUIPMENT_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="equipment internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                ureq = _EquipmentUpdate(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _equipment_internal_session() as s:
                return _equipment_update_asset(equipment_id=equipment_id, req=ureq, s=s)
        r = httpx.patch(_equipment_url(f"/assets/{equipment_id}"), json=body, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/equipment/assets/{equipment_id}")
def equipment_get_asset(equipment_id: int):
    try:
        if _use_equipment_internal():
            if not _EQUIPMENT_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="equipment internal not available")
            with _equipment_internal_session() as s:
                return _equipment_get_asset(equipment_id=equipment_id, s=s)
        r = httpx.get(_equipment_url(f"/assets/{equipment_id}"), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.delete("/equipment/assets/{equipment_id}")
def equipment_delete_asset(equipment_id: int, request: Request):
    _require_operator(request, "equipment")
    try:
        if _use_equipment_internal():
            if not _EQUIPMENT_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="equipment internal not available")
            with _equipment_internal_session() as s:
                return _equipment_delete_asset(equipment_id=equipment_id, s=s)
        r = httpx.delete(_equipment_url(f"/assets/{equipment_id}"), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/equipment/quote")
async def equipment_quote(req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        if _use_equipment_internal():
            if not _EQUIPMENT_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="equipment internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                qreq = _EquipmentQuoteReq(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _equipment_internal_session() as s:
                return _equipment_quote(req=qreq, s=s)
        r = httpx.post(_equipment_url("/quote"), json=body, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/equipment/book")
async def equipment_book(req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    headers: dict[str, str] = {}
    try:
        ikey = req.headers.get("Idempotency-Key")
    except Exception:
        ikey = None
    if ikey:
        headers["Idempotency-Key"] = ikey
    try:
        if _use_equipment_internal():
            if not _EQUIPMENT_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="equipment internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                breq = _EquipmentBookReq(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _equipment_internal_session() as s:
                return _equipment_book(req=breq, idempotency_key=ikey, s=s)
        r = httpx.post(_equipment_url("/book"), json=body, headers=headers, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/equipment/bookings/{booking_id}")
def equipment_get_booking(booking_id: str):
    try:
        if _use_equipment_internal():
            if not _EQUIPMENT_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="equipment internal not available")
            with _equipment_internal_session() as s:
                return _equipment_get_booking(booking_id=booking_id, s=s)
        r = httpx.get(_equipment_url(f"/bookings/{booking_id}"), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/equipment/bookings")
def equipment_list_bookings(request: Request, status: str = "", renter_wallet_id: str = "", equipment_id: int | None = None, upcoming_only: bool = False, limit: int = 100):
    params = {"limit": max(1, min(limit, 300))}
    if status:
        params["status"] = status
    if renter_wallet_id:
        params["renter_wallet_id"] = renter_wallet_id
    if equipment_id is not None:
        params["equipment_id"] = equipment_id
    if upcoming_only:
        params["upcoming_only"] = upcoming_only
    # Basic guardrail: non-operators must filter by renter_wallet_id
    try:
        phone = _auth_phone(request)
    except Exception:
        phone = None
    is_op = False
    try:
        if phone:
            is_op = _is_operator(phone, "equipment")
    except Exception:
        is_op = False
    if not is_op and not renter_wallet_id:
        raise HTTPException(status_code=403, detail="renter_wallet_id required")
    try:
        if _use_equipment_internal():
            if not _EQUIPMENT_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="equipment internal not available")
            with _equipment_internal_session() as s:
                return _equipment_list_bookings(
                    status=status,
                    renter_wallet_id=renter_wallet_id,
                    equipment_id=equipment_id,
                    upcoming_only=upcoming_only,
                    limit=limit,
                    s=s,
                )
        r = httpx.get(_equipment_url("/bookings"), params=params, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/equipment/bookings/{booking_id}/status")
async def equipment_update_booking_status(booking_id: str, req: Request):
    _require_operator(req, "equipment")
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        if _use_equipment_internal():
            if not _EQUIPMENT_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="equipment internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                sreq = _EquipmentStatusUpdate(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _equipment_internal_session() as s:
                return _equipment_update_booking_status(booking_id=booking_id, req=sreq, s=s)
        r = httpx.post(_equipment_url(f"/bookings/{booking_id}/status"), json=body, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/equipment/bookings/{booking_id}/logistics")
async def equipment_update_logistics(booking_id: str, req: Request):
    _require_operator(req, "equipment")
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        if _use_equipment_internal():
            if not _EQUIPMENT_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="equipment internal not available")
            data = body or []
            if not isinstance(data, list):
                data = []
            updates: list[_EquipmentTaskUpdate] = []
            for item in data:
                try:
                    updates.append(_EquipmentTaskUpdate(**item))
                except Exception:
                    continue
            with _equipment_internal_session() as s:
                return _equipment_update_logistics(booking_id=booking_id, updates=updates, s=s)
        r = httpx.post(_equipment_url(f"/bookings/{booking_id}/logistics"), json=body, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/equipment/analytics/summary")
def equipment_analytics(request: Request):
    _require_operator(request, "equipment")
    try:
        if _use_equipment_internal():
            if not _EQUIPMENT_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="equipment internal not available")
            with _equipment_internal_session() as s:
                return _equipment_analytics(s=s)
        r = httpx.get(_equipment_url("/analytics/summary"), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/equipment/dashboard")
def equipment_dashboard(request: Request, renter_wallet_id: str = "", owner_wallet_id: str = ""):
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    params = {}
    if renter_wallet_id:
        params["renter_wallet_id"] = renter_wallet_id
    if owner_wallet_id:
        params["owner_wallet_id"] = owner_wallet_id
    try:
        if _use_equipment_internal():
            if not _EQUIPMENT_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="equipment internal not available")
            with _equipment_internal_session() as s:
                return _equipment_dashboard(renter_wallet_id=renter_wallet_id, owner_wallet_id=owner_wallet_id, s=s)
        r = httpx.get(_equipment_url("/dashboard"), params=params, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/equipment/availability/{equipment_id}")
def equipment_availability(equipment_id: int):
    try:
        if _use_equipment_internal():
            if not _EQUIPMENT_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="equipment internal not available")
            with _equipment_internal_session() as s:
                return _equipment_main.availability(equipment_id=equipment_id, s=s)  # type: ignore[attr-defined]
        r = httpx.get(_equipment_url(f"/availability/{equipment_id}"), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/equipment/calendar/{equipment_id}")
def equipment_calendar(equipment_id: int, month: str):
    try:
        if _use_equipment_internal():
            if not _EQUIPMENT_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="equipment internal not available")
            with _equipment_internal_session() as s:
                return _equipment_main.calendar(equipment_id=equipment_id, month=month, s=s)  # type: ignore[attr-defined]
        r = httpx.get(_equipment_url(f"/calendar/{equipment_id}"), params={"month": month}, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/equipment/availability/{equipment_id}")
async def equipment_add_block(equipment_id: int, req: Request):
    _require_operator(req, "equipment")
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        if _use_equipment_internal():
            if not _EQUIPMENT_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="equipment internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                breq = _equipment_main.AvailabilityReq(**data)  # type: ignore[attr-defined]
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _equipment_internal_session() as s:
                return _equipment_main.create_block(equipment_id=equipment_id, req=breq, s=s)  # type: ignore[attr-defined]
        r = httpx.post(_equipment_url(f"/availability/{equipment_id}"), json=body, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.delete("/equipment/availability/{block_id}")
def equipment_delete_block(block_id: str, request: Request):
    _require_operator(request, "equipment")
    try:
        if _use_equipment_internal():
            if not _EQUIPMENT_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="equipment internal not available")
            with _equipment_internal_session() as s:
                return _equipment_main.delete_block(block_id=block_id, s=s)  # type: ignore[attr-defined]
        r = httpx.delete(_equipment_url(f"/availability/{block_id}"), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


# ---- Taxi proxies ----
def _taxi_url(path: str) -> str:
    if not TAXI_BASE:
        raise HTTPException(status_code=500, detail="TAXI_BASE_URL not configured")
    return TAXI_BASE.rstrip("/") + path

INTERNAL_API_SECRET = os.getenv("INTERNAL_API_SECRET", "")
def _taxi_headers() -> dict:
    return ({"X-Internal-Secret": INTERNAL_API_SECRET} if INTERNAL_API_SECRET else {})

TAXI_QR_TOPUP_PEPPER = os.getenv("TAXI_QR_TOPUP_PEPPER", "")

def _taxi_topup_sig(driver_id: str, amount_cents: int) -> str:
    import hashlib, hmac
    key = (TAXI_QR_TOPUP_PEPPER or INTERNAL_API_SECRET or "taxi-topup").encode()
    msg = f"{driver_id}|{int(amount_cents)}".encode()
    return hmac.new(key, msg, hashlib.sha256).hexdigest()


# --- Taxi internal service (monolith mode) ---
_TAXI_INTERNAL_AVAILABLE = False
try:  # Optional: only available when Taxi app and SQLAlchemy are installed
    from sqlalchemy.orm import Session as _TaxiSession  # type: ignore[import]
    from apps.taxi.app import main as _taxi_main  # type: ignore[import]
    from apps.taxi.app.main import (  # type: ignore[import]
        engine as _taxi_engine,
        DriverRegisterReq as _TaxiDriverRegisterReq,
        LocationReq as _TaxiLocationReq,
        SetWalletReq as _TaxiSetWalletReq,
        RideRequest as _TaxiRideRequest,
        BalanceSetReq as _TaxiBalanceSetReq,
        BalanceIdentityReq as _TaxiBalanceIdentityReq,
        TaxiSettingsUpdate as _TaxiSettingsUpdate,
        RideRatingReq as _TaxiRideRatingReq,
        TaxiTopupQrLogOut as _TaxiTopupQrLogOut,
        TaxiTopupQrRedeemIn as _TaxiTopupQrRedeemIn,
        PreQuoteReq as _TaxiPreQuoteReq,
        register_driver as _taxi_register_driver,
        driver_online as _taxi_driver_online,
        driver_offline as _taxi_driver_offline,
        driver_location as _taxi_driver_location,
        driver_set_wallet as _taxi_driver_set_wallet,
        driver_push_token as _taxi_driver_push_token,
        get_driver as _taxi_get_driver,
        driver_rides as _taxi_driver_rides,
        driver_delete as _taxi_driver_delete,
        driver_block as _taxi_driver_block,
        driver_unblock as _taxi_driver_unblock,
        driver_balance as _taxi_driver_balance,
        driver_balance_by_identity as _taxi_driver_balance_by_identity,
        driver_lookup as _taxi_driver_lookup,
        request_ride as _taxi_request_ride,
        list_drivers as _taxi_list_drivers,
        list_rides as _taxi_list_rides,
        create_topup_qr_log as _taxi_create_topup_qr_log,
        mark_topup_qr_redeemed as _taxi_mark_topup_qr_redeemed,
        list_topup_qr_logs as _taxi_list_topup_qr_logs,
        get_settings as _taxi_get_settings,
        update_settings as _taxi_update_settings,
        rate_ride as _taxi_rate_ride,
        taxi_admin_summary as _taxi_admin_summary,
        driver_stats as _taxi_driver_stats,
        pre_quote as _taxi_pre_quote,
        book_and_pay as _taxi_book_and_pay,
        get_ride as _taxi_get_ride,
        accept_ride as _taxi_accept_ride,
        assign_ride as _taxi_assign_ride,
        start_ride as _taxi_start_ride,
        complete_ride as _taxi_complete_ride,
        cancel_ride as _taxi_cancel_ride,
    )
    _TAXI_INTERNAL_AVAILABLE = True
except Exception:
    _TaxiSession = None  # type: ignore[assignment]
    _taxi_main = None  # type: ignore[assignment]
    _taxi_engine = None  # type: ignore[assignment]
    _TAXI_INTERNAL_AVAILABLE = False


class _TaxiInternalRequestShim:
    """
    Minimal shim to satisfy Taxi service endpoint signatures when calling
    them directly in-process. It only exposes the attributes actually used:
    - headers: mapping with X-Internal-Secret
    - json(): async method returning a pre-parsed body (for driver_push_token)
    """

    __slots__ = ("headers", "_body")

    def __init__(self, headers: dict[str, str], body: Any | None = None):
        self.headers = headers
        self._body = body

    async def json(self) -> Any:
        return self._body


def _use_taxi_internal() -> bool:
    """
    Decide whether to use in-process Taxi calls instead of HTTP.

    Modes (env: TAXI_INTERNAL_MODE):
      - "on"   -> always use internal when available
      - "off"  -> always use HTTP
      - "auto" -> default; use internal if Taxi is importable and TAXI_BASE_URL is empty
    """
    if _force_internal(_TAXI_INTERNAL_AVAILABLE):
        return True
    mode = os.getenv("TAXI_INTERNAL_MODE", "auto").lower()
    if mode == "off":
        return False
    if not _TAXI_INTERNAL_AVAILABLE:
        return False
    if mode == "on":
        return True
    # auto: prefer internal wiring when no explicit upstream base is configured
    return not bool(TAXI_BASE)


def _taxi_internal_session():
    if not _TAXI_INTERNAL_AVAILABLE or _TaxiSession is None or _taxi_engine is None:  # type: ignore[truthy-function]
        raise RuntimeError("Taxi internal service not available")
    return _TaxiSession(_taxi_engine)  # type: ignore[call-arg]


def _call_taxi(fn, *, need_session: bool, request_body: Any | None = None,
               inject_internal: bool = False, **kwargs):
    """
    Call a synchronous Taxi endpoint function directly in-process.
    """
    if not _use_taxi_internal():
        raise RuntimeError("Taxi internal not enabled")
    req_obj: _TaxiInternalRequestShim | None = None
    if inject_internal:
        req_obj = _TaxiInternalRequestShim(_taxi_headers(), request_body)
    try:
        if need_session:
            with _taxi_internal_session() as s:
                if req_obj is not None:
                    kwargs.setdefault("request", req_obj)
                kwargs.setdefault("s", s)
                return fn(**kwargs)
        else:
            if req_obj is not None:
                kwargs.setdefault("request", req_obj)
            return fn(**kwargs)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


async def _call_taxi_async(fn, *, need_session: bool, request_body: Any | None = None,
                           inject_internal: bool = False, **kwargs):
    """
    Call an async Taxi endpoint function (currently driver_push_token) in-process.
    """
    if not _use_taxi_internal():
        raise RuntimeError("Taxi internal not enabled")
    req_obj: _TaxiInternalRequestShim | None = None
    if inject_internal:
        req_obj = _TaxiInternalRequestShim(_taxi_headers(), request_body)
    try:
        if need_session:
            with _taxi_internal_session() as s:
                if req_obj is not None:
                    kwargs.setdefault("request", req_obj)
                kwargs.setdefault("s", s)
                return await fn(**kwargs)
        else:
            if req_obj is not None:
                kwargs.setdefault("request", req_obj)
            return await fn(**kwargs)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


# --- Payments internal service (monolith mode) ---
_PAY_INTERNAL_AVAILABLE = False
try:
    from sqlalchemy.orm import Session as _PaySession  # type: ignore[import]
    from apps.payments.app import main as _pay_main  # type: ignore[import]
    from apps.payments.app.main import (  # type: ignore[import]
        engine as _pay_engine,
        CreateUserReq as _PayCreateUserReq,
        TransferReq as _PayTransferReq,
        PaymentRequestCreate as _PayRequestCreate,
        _accept_request_core as _pay_accept_request_core,
        TopupReq as _PayTopupReq,
        CashCreateReq as _PayCashCreateReq,
        CashRedeemReq as _PayCashRedeemReq,
        CashCancelReq as _PayCashCancelReq,
        SonicIssueReq as _PaySonicIssueReq,
        SonicRedeemReq as _PaySonicRedeemReq,
        AliasRequest as _PayAliasRequest,
        AliasVerifyReq as _PayAliasVerifyReq,
        RoleUpsert as _PayRoleUpsert,
        RiskDenyReq as _PayRiskDenyReq,
        TopupBatchCreateReq as _PayTopupBatchCreateReq,
        TopupRedeemReq as _PayTopupRedeemReq,
        create_user as _pay_create_user,
        get_wallet as _pay_get_wallet,
        list_txns as _pay_list_txns,
        transfer as _pay_transfer,
        create_request as _pay_create_request,
        list_requests as _pay_list_requests,
        cancel_request as _pay_cancel_request,
        accept_request as _pay_accept_request,
        resolve_phone as _pay_resolve_phone,
        cash_create as _pay_cash_create,
        cash_redeem as _pay_cash_redeem,
        cash_cancel as _pay_cash_cancel,
        cash_status as _pay_cash_status,
        sonic_issue as _pay_sonic_issue,
        sonic_redeem as _pay_sonic_redeem,
        idempotency_status as _pay_idempotency_status,
        alias_request as _pay_alias_request,
        alias_verify as _pay_alias_verify,
        alias_resolve as _pay_alias_resolve,
        roles_list as _pay_roles_list,
        roles_add as _pay_roles_add,
        roles_remove as _pay_roles_remove,
        roles_check as _pay_roles_check,
        admin_risk_deny_add as _pay_admin_risk_deny_add,
        admin_risk_deny_remove as _pay_admin_risk_deny_remove,
        admin_risk_deny_list as _pay_admin_risk_deny_list,
        admin_risk_events as _pay_admin_risk_events,
        admin_risk_metrics as _pay_admin_risk_metrics,
        topup as _pay_wallet_topup,
        topup_batch_create as _pay_topup_batch_create,
        topup_batches as _pay_topup_batches,
        topup_batch_detail as _pay_topup_batch_detail,
        topup_voucher_void as _pay_topup_voucher_void,
        topup_redeem as _pay_topup_redeem,
        fees_summary as _pay_fees_summary,
        admin_txns_count as _pay_admin_txns_count,
    )
    _PAY_INTERNAL_AVAILABLE = True
except Exception:
    _PaySession = None  # type: ignore[assignment]
    _pay_main = None  # type: ignore[assignment]
    _pay_engine = None  # type: ignore[assignment]
    _PAY_INTERNAL_AVAILABLE = False


def _use_pay_internal() -> bool:
    """
    PAYMENTS_INTERNAL_MODE / PAY_INTERNAL_MODE:
      - on   -> immer intern
      - off  -> immer HTTP
      - auto -> intern, wenn importierbar und PAYMENTS_BASE_URL leer
    """
    if _force_internal(_PAY_INTERNAL_AVAILABLE):
        return True
    mode = (os.getenv("PAYMENTS_INTERNAL_MODE") or os.getenv("PAY_INTERNAL_MODE") or "auto").lower()
    if mode == "off":
        return False
    if not _PAY_INTERNAL_AVAILABLE:
        return False
    if mode == "on":
        return True
    return not bool(PAYMENTS_BASE)


def _pay_internal_session():
    if not _PAY_INTERNAL_AVAILABLE or _PaySession is None or _pay_engine is None:  # type: ignore[truthy-function]
        raise RuntimeError("Payments internal service not available")
    return _PaySession(_pay_engine)  # type: ignore[call-arg]


async def _send_driver_push(phone: str, title: str, body: str, data: dict | None = None) -> None:
    endpoints = list(_PUSH_ENDPOINTS.get(phone) or [])
    if not endpoints:
        return
    try:
        async with httpx.AsyncClient(timeout=6) as client:
            for ep in endpoints:
                etype = (ep.get("type") or "").lower()
                if etype == "gotify" and GOTIFY_BASE and GOTIFY_APP_TOKEN:
                    try:
                        await client.post(
                            GOTIFY_BASE.rstrip("/") + "/message",
                            params={"token": GOTIFY_APP_TOKEN},
                            json={
                                "title": title,
                                "message": body,
                                "priority": 5,
                                "extras": {"custom": data or {}},
                            },
                        )
                    except Exception:
                        continue
                elif etype == "unifiedpush":
                    url = (ep.get("endpoint") or "").strip()
                    if not url:
                        continue
                    try:
                        await client.post(url, json=data or {})
                    except Exception:
                        continue
    except Exception:
        return


async def _maybe_send_driver_push_for_ride(ride: dict) -> None:
    try:
        driver_id = (ride.get("driver_id") or "").strip()
        ride_id = (ride.get("id") or "").strip()
        if not driver_id or not ride_id:
            return
        pickup_lat = ride.get("pickup_lat")
        pickup_lon = ride.get("pickup_lon")
        rider_phone = (ride.get("rider_phone") or "").strip()
        driver_phone = ""
        try:
            if _use_taxi_internal():
                try:
                    d = _call_taxi(_taxi_get_driver, need_session=True, driver_id=driver_id)
                    driver_phone = (getattr(d, "phone", "") or "").strip()
                except HTTPException:
                    driver_phone = ""
            else:
                r = httpx.get(_taxi_url(f"/drivers/{driver_id}"), headers=_taxi_headers(), timeout=10)
                if r.headers.get("content-type", "").startswith("application/json"):
                    dj = r.json()
                    if isinstance(dj, dict):
                        driver_phone = (dj.get("phone") or "").strip()
        except Exception:
            driver_phone = ""
        if not driver_phone:
            return
        parts = []
        try:
            if isinstance(pickup_lat, (int, float)) and isinstance(pickup_lon, (int, float)):
                parts.append(f"Pickup: {pickup_lat:.4f},{pickup_lon:.4f}")
        except Exception:
            pass
        if rider_phone:
            parts.append(f"Rider: {rider_phone}")
        body = " · ".join(parts) if parts else f"Ride {ride_id}"
        await _send_driver_push(
            driver_phone,
            "New taxi ride request",
            body,
            {
                "ride_id": ride_id,
                "pickup_lat": str(pickup_lat or ""),
                "pickup_lon": str(pickup_lon or ""),
                "rider_phone": rider_phone,
            },
        )
    except Exception:
        return

@app.post("/taxi/drivers")
async def taxi_driver_register(req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None

    # Extract phone early so we can create a payments user/wallet idempotently.
    phone = ""
    try:
        if isinstance(body, dict):
            phone = (body.get("phone") or "").strip()
    except Exception:
        phone = ""

    # First: register driver in Taxi service.
    try:
        if _use_taxi_internal():
            try:
                data = body or {}
                if not isinstance(data, dict):
                    data = {}
                req_model = _TaxiDriverRegisterReq(**data)
                driver = _call_taxi(_taxi_register_driver, need_session=True, req=req_model)
            except HTTPException:
                raise
            except Exception as e:
                raise HTTPException(status_code=502, detail=str(e))
        else:
            r = httpx.post(_taxi_url("/drivers"), json=body, headers=_taxi_headers(), timeout=10)
            try:
                driver = r.json() if r.headers.get("content-type", "").startswith("application/json") else {}
            except Exception:
                driver = {}
            if r.status_code >= 400:
                # Surface taxi error to caller; do not attempt wallet creation.
                raise HTTPException(status_code=r.status_code, detail=r.text)
    except HTTPException:
        raise
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))

    # Second: ensure Payments user + wallet for this driver's phone (best-effort, idempotent).
    try:
        if phone:
            payload = {"phone": phone}
            if _use_pay_internal():
                if _PAY_INTERNAL_AVAILABLE:
                    req_model = _PayCreateUserReq(**payload)
                    with _pay_internal_session() as s:
                        _pay_create_user(req_model, s=s)
            elif PAYMENTS_BASE:
                httpx.post(_payments_url("/users"), json=payload, timeout=8)
    except Exception:
        # Wallet creation is best-effort; driver registration must still succeed.
        pass

    return driver


@app.post("/taxi/drivers/{driver_id}/online")
def taxi_driver_online(driver_id: str):
    if _use_taxi_internal():
        try:
            return _call_taxi(_taxi_driver_online, need_session=True, inject_internal=True, driver_id=driver_id)
        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(status_code=502, detail=str(e))
    try:
        r = httpx.post(_taxi_url(f"/drivers/{driver_id}/online"), headers=_taxi_headers(), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/taxi/drivers/{driver_id}/offline")
def taxi_driver_offline(driver_id: str):
    if _use_taxi_internal():
        try:
            return _call_taxi(_taxi_driver_offline, need_session=True, inject_internal=True, driver_id=driver_id)
        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(status_code=502, detail=str(e))
    try:
        r = httpx.post(_taxi_url(f"/drivers/{driver_id}/offline"), headers=_taxi_headers(), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/taxi/drivers/{driver_id}/location")
async def taxi_driver_location(driver_id: str, req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    if _use_taxi_internal():
        try:
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            req_model = _TaxiLocationReq(**data)
            return _call_taxi(
                _taxi_driver_location,
                need_session=True,
                request_body=data,
                inject_internal=True,
                driver_id=driver_id,
                req=req_model,
            )
        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(status_code=502, detail=str(e))
    try:
        r = httpx.post(_taxi_url(f"/drivers/{driver_id}/location"), json=body, headers=_taxi_headers(), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/taxi/drivers/{driver_id}/wallet")
async def taxi_driver_set_wallet(driver_id: str, req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    if _use_taxi_internal():
        try:
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            req_model = _TaxiSetWalletReq(**data)
            return _call_taxi(
                _taxi_driver_set_wallet,
                need_session=True,
                request_body=data,
                inject_internal=True,
                driver_id=driver_id,
                req=req_model,
            )
        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(status_code=502, detail=str(e))
    try:
        r = httpx.post(_taxi_url(f"/drivers/{driver_id}/wallet"), json=body, headers=_taxi_headers(), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/taxi/drivers/{driver_id}/push_token")
async def taxi_driver_push_token(driver_id: str, req: Request):
    try:
        try:
            body = await req.json()
        except Exception:
            body = None
        if _use_taxi_internal():
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            return await _call_taxi_async(
                _taxi_driver_push_token,
                need_session=True,
                request_body=data,
                inject_internal=True,
                driver_id=driver_id,
            )
        r = httpx.post(_taxi_url(f"/drivers/{driver_id}/push_token"), json=body, headers=_taxi_headers(), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/taxi/drivers/{driver_id}")
def taxi_get_driver(driver_id: str):
    if _use_taxi_internal():
        try:
            return _call_taxi(_taxi_get_driver, need_session=True, driver_id=driver_id)
        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(status_code=502, detail=str(e))
    try:
        r = httpx.get(_taxi_url(f"/drivers/{driver_id}"), headers=_taxi_headers(), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/taxi/drivers/{driver_id}/rides")
def taxi_driver_rides(driver_id: str, status: str = "", limit: int = 10):
    params = {"status": status, "limit": max(1, min(limit, 50))}
    if _use_taxi_internal():
        try:
            return _call_taxi(
                _taxi_driver_rides,
                need_session=True,
                driver_id=driver_id,
                status=status,
                limit=max(1, min(limit, 50)),
            )
        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(status_code=502, detail=str(e))
    try:
        r = httpx.get(_taxi_url(f"/drivers/{driver_id}/rides"), params=params, headers=_taxi_headers(), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/fleet/nearest_driver")
def fleet_nearest_driver(lat: float, lon: float, status: str = "online", limit: int = 200):
    """
    Returns the nearest taxi driver to a given location (approximate, by distance).

    Uses Taxi drivers list (status filter) and a simple Haversine distance.
    """
    # Load candidate drivers
    params = {"status": status, "limit": max(1, min(limit, 500))}
    drivers: list[Any] = []
    try:
        if _use_taxi_internal():
            if not _TAXI_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="taxi internal not available")
            drivers = _call_taxi(
                _taxi_list_drivers,
                need_session=True,
                status=status,
                limit=max(1, min(limit, 500)),
            )
        else:
            if not TAXI_BASE:
                raise HTTPException(status_code=500, detail="TAXI_BASE_URL not configured")
            r = httpx.get(_taxi_url("/drivers"), params=params, headers=_taxi_headers(), timeout=10)
            if not r.headers.get("content-type", "").startswith("application/json"):
                raise HTTPException(status_code=502, detail="unexpected taxi drivers payload")
            arr = r.json()
            if isinstance(arr, list):
                drivers = arr
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))

    best: dict[str, Any] | None = None
    best_km = float("inf")
    total = 0

    for d in drivers or []:
        try:
            if hasattr(d, "__dict__"):
                # Internal Taxi driver object
                did = str(getattr(d, "id", "") or "")
                plat = getattr(d, "lat", None)
                plon = getattr(d, "lon", None)
                phone = str(getattr(d, "phone", "") or "")
            else:
                m = d if isinstance(d, dict) else {}
                did = str(m.get("id") or "")
                plat = m.get("lat")
                plon = m.get("lon")
                phone = str(m.get("phone") or "")
            if not did:
                continue
            if plat is None or plon is None:
                continue
            plat_f = float(plat)
            plon_f = float(plon)
            total += 1
            dist_km = _haversine_km(lat, lon, plat_f, plon_f)
            if dist_km < best_km:
                best_km = dist_km
                best = {
                    "driver_id": did,
                    "phone": phone,
                    "lat": plat_f,
                    "lon": plon_f,
                    "distance_km": dist_km,
                }
        except Exception:
            continue

    if not best:
        return {"ok": True, "found": False, "drivers_checked": total}
    return {"ok": True, "found": True, "drivers_checked": total, "nearest": best}


@app.delete("/taxi/drivers/{driver_id}")
def taxi_delete_driver(driver_id: str):
    if _use_taxi_internal():
        try:
            result = _call_taxi(_taxi_driver_delete, need_session=True, inject_internal=True, driver_id=driver_id)
            return result
        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(status_code=502, detail=str(e))
    try:
        r = httpx.delete(_taxi_url(f"/drivers/{driver_id}"), headers=_taxi_headers(), timeout=10)
        if r.headers.get("content-type","" ).startswith("application/json"):
            return r.json()
        return {"status_code": r.status_code, "raw": r.text}
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/taxi/drivers/{driver_id}/block")
def taxi_block_driver(driver_id: str):
    if _use_taxi_internal():
        try:
            return _call_taxi(_taxi_driver_block, need_session=True, inject_internal=True, driver_id=driver_id)
        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(status_code=502, detail=str(e))
    try:
        r = httpx.post(_taxi_url(f"/drivers/{driver_id}/block"), headers=_taxi_headers(), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/taxi/drivers/{driver_id}/unblock")
def taxi_unblock_driver(driver_id: str):
    if _use_taxi_internal():
        try:
            return _call_taxi(_taxi_driver_unblock, need_session=True, inject_internal=True, driver_id=driver_id)
        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(status_code=502, detail=str(e))
    try:
        r = httpx.post(_taxi_url(f"/drivers/{driver_id}/unblock"), headers=_taxi_headers(), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/taxi/drivers/{driver_id}/balance")
async def taxi_set_balance(driver_id: str, req: Request):
    try:
        try:
            body = await req.json()
        except Exception:
            body = None
        if _use_taxi_internal():
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                req_model = _TaxiBalanceSetReq(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            return _call_taxi(
                _taxi_driver_balance,
                need_session=True,
                request_body=data,
                inject_internal=True,
                driver_id=driver_id,
                req=req_model,
            )
        r = httpx.post(_taxi_url(f"/drivers/{driver_id}/balance"), json=body, headers=_taxi_headers(), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/taxi/rides/request")
async def taxi_request_ride(req: Request):
    # Backend-side enrichment: rider phone from session; rider wallet via Payments
    try:
        body = await req.json()
    except Exception:
        body = {}
    if not isinstance(body, dict):
        body = {}
    # Fill rider phone from session if absent
    try:
        rider_phone = (body.get('rider_phone') or '').strip()
    except Exception:
        rider_phone = ''
    if not rider_phone:
        sess_phone = _auth_phone(req)
        if sess_phone:
            body['rider_phone'] = sess_phone
            rider_phone = sess_phone
    # Fill rider wallet id via Payments if absent
    try:
        rider_wallet = (body.get('rider_wallet_id') or '').strip()
    except Exception:
        rider_wallet = ''
    if not rider_wallet and rider_phone and PAYMENTS_BASE:
        try:
            url = PAYMENTS_BASE.rstrip('/') + '/users'
            async with httpx.AsyncClient(timeout=10) as client:
                rr = await client.post(url, json={"phone": rider_phone})
                if rr.headers.get('content-type','').startswith('application/json'):
                    j = rr.json()
                    wid = j.get('wallet_id') or j.get('id')
                    if wid:
                        body['rider_wallet_id'] = wid
        except Exception:
            pass
    try:
        if _use_taxi_internal():
            try:
                req_model = _TaxiRideRequest(**body)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            ride_obj = _call_taxi(
                _taxi_request_ride,
                need_session=True,
                request_body=body,
                inject_internal=True,
                req=req_model,
                idempotency_key=None,
            )
            # Fire-and-forget push notification using a serializable view of the ride
            try:
                if hasattr(ride_obj, "dict"):
                    ride_dict = ride_obj.dict()  # type: ignore[call-arg]
                else:
                    ride_dict = ride_obj
                if isinstance(ride_dict, dict):
                    await _maybe_send_driver_push_for_ride(ride_dict)
            except Exception:
                pass
            return ride_obj
        r = httpx.post(_taxi_url("/rides/request"), json=body, headers=_taxi_headers(), timeout=10)
        j = r.json()
        try:
            if isinstance(j, dict):
                await _maybe_send_driver_push_for_ride(j)
        except Exception:
            pass
        return j
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))

# NOTE: Place book_pay BEFORE the dynamic /taxi/rides/{ride_id} to avoid 405
## moved earlier to avoid conflict with /taxi/rides/{ride_id}


@app.get("/taxi/drivers")
def taxi_list_drivers(status: str = "", limit: int = 50):
    params = {"status": status, "limit": max(1, min(limit, 200))}
    if _use_taxi_internal():
        try:
            return _call_taxi(
                _taxi_list_drivers,
                need_session=True,
                status=status,
                limit=max(1, min(limit, 200)),
            )
        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(status_code=502, detail=str(e))
    try:
        r = httpx.get(_taxi_url("/drivers"), params=params, headers=_taxi_headers(), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/taxi/drivers")
async def taxi_register_driver(request: Request):
    """
    Admin / SuperAdmin endpoint to register a new taxi driver.

    Expected JSON body (forwarded to Taxi service):
      - name: string (optional but recommended)
      - phone: string (E.164, required)
      - vehicle_make / vehicle_plate / vehicle_class / vehicle_color: optional

    The Taxi service will:
      - create the Driver record
      - auto-create a unique payments wallet for the driver (wallet_id) based on phone
    """
    _require_operator(request, "taxi")
    try:
        try:
            body = await request.json()
        except Exception:
            body = {}
        if not isinstance(body, dict):
            body = {}
        # Minimal validation: phone required
        phone = (body.get("phone") or "").strip()
        if not phone:
            raise HTTPException(status_code=400, detail="phone required")

        # Prefer in-process Taxi integration in monolith mode
        if _use_taxi_internal():
            if not _TAXI_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="taxi internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                req_model = _TaxiDriverRegisterReq(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            try:
                result = _call_taxi(
                    _taxi_register_driver,
                    need_session=True,
                    request_body=data,
                    inject_internal=True,
                    req=req_model,
                )
                _audit_from_request(request, "taxi_register_driver", driver_phone=phone)
                return result
            except HTTPException:
                raise
            except Exception as e:
                raise HTTPException(status_code=502, detail=str(e))

        # Fallback: HTTP call to external Taxi API
        r = httpx.post(_taxi_url("/drivers"), json=body, headers=_taxi_headers(), timeout=10)
        if r.headers.get("content-type", "").startswith("application/json"):
            result = r.json()
        else:
            # Propagate non-JSON error bodies instead of causing JSON decode errors
            raise HTTPException(status_code=r.status_code, detail=r.text)
        _audit_from_request(request, "taxi_register_driver", driver_phone=phone)
        return result
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/taxi/rides")
def taxi_list_rides(status: str = "", limit: int = 50):
    params = {"status": status, "limit": max(1, min(limit, 200))}
    if _use_taxi_internal():
        try:
            return _call_taxi(
                _taxi_list_rides,
                need_session=True,
                status=status,
                limit=max(1, min(limit, 200)),
            )
        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(status_code=502, detail=str(e))
    try:
        r = httpx.get(_taxi_url("/rides"), params=params, headers=_taxi_headers(), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/me/taxi_history")
def me_taxi_history(request: Request, status: str = "", limit: int = 50, response: Response = None):  # type: ignore[assignment]
    """
    Aggregated Taxi ride history for the logged-in user.

    Filters Taxi rides by rider_phone == own phone number,
    optionally restricted by status. Uses the existing Taxi list
    and encapsulates filtering logic in the BFF.
    """
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    limit = max(1, min(limit, 200))
    try:
        # Fetch a slightly larger set and filter per client afterwards.
        raw = taxi_list_rides(status=status, limit=limit * 2)
        items: list[Any] = []
        if isinstance(raw, list):
            for it in raw:
                try:
                    rider_phone = ""
                    if isinstance(it, dict):
                        rider_phone = (str(it.get("rider_phone") or "")).strip()
                    else:
                        rider_phone = (str(getattr(it, "rider_phone", "") or "")).strip()
                except Exception:
                    continue
                if rider_phone != phone:
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
async def me_mobility_history(
    request: Request,
    status: str = "",
    taxi_limit: int = 50,
    bus_limit: int = 50,
    response: Response = None,  # type: ignore[assignment]
):
    """
    Combined mobility history (Taxi + Bus) for the logged-in user.

    Wraps the existing aggregate endpoints /me/taxi_history and
    /me/bus_history into a single response so clients can query both
    domains with one request.
    """
    # Auth is re-checked in the underlying handlers; here we only
    # ensure that a session exists.
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")

    taxi_limit = max(1, min(taxi_limit, 200))
    bus_limit = max(1, min(bus_limit, 200))

    taxi_items: list[dict[str, Any]] = []
    bus_items: list[dict[str, Any]] = []
    try:
        try:
            taxi_items = me_taxi_history(request, status=status, limit=taxi_limit)  # type: ignore[assignment]
        except HTTPException:
            raise
        except Exception as e:
            taxi_items = [{"error": str(e)}]
        try:
            bus_items = me_bus_history(request, status=status, limit=bus_limit)  # type: ignore[assignment]
        except HTTPException:
            raise
        except Exception as e:
            bus_items = [{"error": str(e)}]
        out = {"taxi": taxi_items, "bus": bus_items}
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


@app.post("/taxi/topup_qr/create")
async def taxi_topup_qr_create(request: Request):
    """
    Admin/SuperAdmin: create a QR payload for taxi-driver topup.

    Body:
      - driver_phone: string (E.164)
      - amount_cents: int (>0)

    Returns:
      - payload: string to encode as QR (TAXI_TOPUP|...)
      - driver_id, amount_cents
    """
    _require_operator(request, "taxi")
    try:
        try:
            body = await request.json()
        except Exception:
            body = {}
        if not isinstance(body, dict):
            body = {}
        # Accept driver_phone or phone
        phone = (body.get("driver_phone") or body.get("phone") or "").strip()
        if not phone:
            raise HTTPException(status_code=400, detail="driver_phone required")
        # Normalize amount: allow amount_syp/amount (SYP) or amount_cents
        body = _normalize_amount(body) or {}
        amount_cents = int(body.get("amount_cents") or 0)
        if amount_cents <= 0:
            raise HTTPException(status_code=400, detail="amount must be > 0")
        # Resolve driver by phone via Taxi service
        if _use_taxi_internal():
            try:
                driver = _call_taxi(
                    _taxi_driver_lookup,
                    need_session=True,
                    request_body=None,
                    inject_internal=True,
                    phone=phone,
                )
            except HTTPException:
                raise
            except Exception as e:
                raise HTTPException(status_code=502, detail=str(e))
            driver_id = str(getattr(driver, "id", "") or "").strip()
            if not driver_id:
                raise HTTPException(status_code=502, detail="driver id missing")
        else:
            try:
                r = httpx.get(_taxi_url("/drivers/lookup"), params={"phone": phone}, headers=_taxi_headers(), timeout=10)
                r.raise_for_status()
                driver = r.json() if r.headers.get("content-type", "").startswith("application/json") else {}
            except httpx.HTTPStatusError as e:
                if e.response.status_code == 404:
                    raise HTTPException(status_code=404, detail="driver not found for phone")
                raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
            except Exception as e:
                raise HTTPException(status_code=502, detail=str(e))
            driver_id = str(driver.get("id") or "").strip()
            if not driver_id:
                raise HTTPException(status_code=502, detail="driver id missing")
        sig = _taxi_topup_sig(driver_id, amount_cents)
        payload = f"TAXI_TOPUP|driver_id={driver_id}|amount={amount_cents}|sig={sig}"
        # Log for Superadmin audit inside Taxi service (persistent)
        admin_phone = ""
        try:
            admin_phone = _auth_phone(request)
        except Exception:
            admin_phone = ""
        try:
            if _use_taxi_internal():
                log_req = _TaxiTopupQrLogOut(
                    id=str(_uuid.uuid4()),
                    driver_id=driver_id,
                    driver_phone=phone,
                    amount_cents=amount_cents,
                    created_by=admin_phone,
                    payload=payload,
                    created_at=None,
                    redeemed=False,
                    redeemed_at=None,
                    redeemed_by=None,
                )
                _call_taxi(
                    _taxi_create_topup_qr_log,
                    need_session=True,
                    request_body=None,
                    inject_internal=True,
                    req=log_req,
                )
            else:
                rlog = httpx.post(
                    _taxi_url("/topup_qr_log"),
                    json={
                        "id": str(_uuid.uuid4()),
                        "driver_id": driver_id,
                        "driver_phone": phone,
                        "amount_cents": amount_cents,
                        "created_by": admin_phone,
                        "payload": payload,
                        "created_at": None,
                        "redeemed": False,
                        "redeemed_at": None,
                        "redeemed_by": None,
                    },
                    headers=_taxi_headers(),
                    timeout=6,
                )
                rlog.raise_for_status()
        except HTTPException:
            raise
        except httpx.HTTPStatusError as e:
            raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
        except Exception as e:
            raise HTTPException(status_code=502, detail=str(e))
        _audit_from_request(request, "taxi_topup_qr_create", driver_id=driver_id, driver_phone=phone, amount_cents=amount_cents)
        return {"payload": payload, "driver_id": driver_id, "amount_cents": amount_cents, "driver_phone": phone}
    except HTTPException:
        raise
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/taxi/topup_qr/redeem")
async def taxi_topup_qr_redeem(request: Request):
    """
    Driver: redeem a taxi topup QR payload to increase driver balance.

    Body:
      - payload: string scanned from QR (TAXI_TOPUP|...)
    """
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    try:
        try:
            body = await request.json()
        except Exception:
            body = {}
        if not isinstance(body, dict):
            body = {}
        payload = (body.get("payload") or "").strip()
        if not payload or not payload.startswith("TAXI_TOPUP|"):
            raise HTTPException(status_code=400, detail="invalid payload")
        parts = payload.split("|")
        kv = {}
        for p in parts[1:]:
            if "=" in p:
                k, v = p.split("=", 1)
                kv[k] = v
        driver_id = (kv.get("driver_id") or "").strip()
        amount_raw = (kv.get("amount") or "").strip()
        sig = (kv.get("sig") or "").strip()
        if not driver_id or not amount_raw or not sig:
            raise HTTPException(status_code=400, detail="missing fields in payload")
        try:
            amount_cents = int(amount_raw)
        except Exception:
            raise HTTPException(status_code=400, detail="invalid amount")
        expected = _taxi_topup_sig(driver_id, amount_cents)
        if sig.lower() != expected.lower():
            raise HTTPException(status_code=403, detail="invalid signature")
        # Redeem and deposit in Taxi service (single-use enforced there).
        redeem_balance = None
        redeem_driver_id = driver_id
        if _use_taxi_internal():
            try:
                redeem_req = _TaxiTopupQrRedeemIn(payload=payload, driver_phone=phone, driver_id=driver_id)
                log = _call_taxi(
                    _taxi_mark_topup_qr_redeemed,
                    need_session=True,
                    request_body={"payload": payload, "driver_phone": phone, "driver_id": driver_id},
                    inject_internal=True,
                    req=redeem_req,
                )
                try:
                    redeem_balance = getattr(log, "driver_balance_cents", None)
                    redeem_driver_id = str(getattr(log, "driver_id", driver_id) or driver_id)
                except Exception:
                    redeem_driver_id = driver_id
            except HTTPException as e:
                if e.status_code == 404:
                    raise HTTPException(status_code=410, detail="QR already redeemed or invalid")
                raise
            except Exception as e:
                raise HTTPException(status_code=502, detail=str(e))
        else:
            rb = httpx.post(
                _taxi_url("/topup_qr_log/redeem"),
                json={"payload": payload, "driver_phone": phone, "driver_id": driver_id},
                headers=_taxi_headers(),
                timeout=10,
            )
            if rb.status_code == 404:
                raise HTTPException(status_code=410, detail="QR already redeemed or invalid")
            if rb.status_code >= 400:
                raise HTTPException(status_code=rb.status_code, detail=rb.text)
            try:
                bal = rb.json() if rb.headers.get("content-type", "").startswith("application/json") else {}
            except Exception:
                bal = {}
            redeem_balance = bal.get("driver_balance_cents")
            redeem_driver_id = bal.get("driver_id") or driver_id
        return {
            "ok": True,
            "amount_cents": amount_cents,
            "balance_cents": redeem_balance,
            "driver_id": redeem_driver_id,
        }
    except HTTPException:
        raise
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/taxi/topup_qr/logs")
def taxi_topup_qr_logs(limit: int = 200, request: Request = None):
    """
    Superadmin/Admin audit view of all taxi topup QRs created via the BFF.
    """
    _require_admin(request)
    try:
        if _use_taxi_internal():
            logs = _call_taxi(
                _taxi_list_topup_qr_logs,
                need_session=True,
                request_body=None,
                inject_internal=True,
                limit=max(1, min(limit, 1000)),
            )
            return {"items": logs}
        r = httpx.get(_taxi_url("/topup_qr_logs"), params={"limit": max(1, min(limit, 1000))}, headers=_taxi_headers(), timeout=10)
        arr = r.json() if r.headers.get("content-type","").startswith("application/json") else []
        if not isinstance(arr, list):
            return {"items": []}
        return {"items": arr}
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/taxi/settings")
def taxi_get_settings():
    if _use_taxi_internal():
        try:
            return _call_taxi(_taxi_get_settings, need_session=True)
        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(status_code=502, detail=str(e))
    try:
        r = httpx.get(_taxi_url("/settings"), headers=_taxi_headers(), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/taxi/settings")
async def taxi_update_settings(req: Request):
    try:
        try:
            body = await req.json()
        except Exception:
            body = None
        if _use_taxi_internal():
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                req_model = _TaxiSettingsUpdate(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            return _call_taxi(
                _taxi_update_settings,
                need_session=True,
                request_body=data,
                inject_internal=True,
                req=req_model,
            )
        r = httpx.post(_taxi_url("/settings"), json=body, headers=_taxi_headers(), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/taxi/rides/{ride_id}/rating")
async def taxi_rate_ride(ride_id: str, req: Request):
    try:
        try:
            body = await req.json()
        except Exception:
            body = None
        if _use_taxi_internal():
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                req_model = _TaxiRideRatingReq(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            return _call_taxi(
                _taxi_rate_ride,
                need_session=True,
                request_body=data,
                inject_internal=True,
                ride_id=ride_id,
                req=req_model,
            )
        r = httpx.post(_taxi_url(f"/rides/{ride_id}/rating"), json=body, headers=_taxi_headers(), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/taxi/drivers/{driver_id}/stats")
def taxi_driver_stats(driver_id: str, period: str = "today"):
    if _use_taxi_internal():
        try:
            return _call_taxi(
                _taxi_driver_stats,
                need_session=True,
                driver_id=driver_id,
                period=period,
            )
        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(status_code=502, detail=str(e))
    try:
        r = httpx.get(_taxi_url(f"/drivers/{driver_id}/stats"), params={"period": period}, headers=_taxi_headers(), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/taxi/admin/summary")
def taxi_admin_summary(request: Request):
    _require_operator(request, "taxi")
    if _use_taxi_internal():
        try:
            return _call_taxi(_taxi_admin_summary, need_session=True)
        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(status_code=502, detail=str(e))
    try:
        r = httpx.get(_taxi_url("/admin/summary"), headers=_taxi_headers(), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/taxi/admin/summary_cached")
def taxi_admin_summary_cached():
    """
    Small cached variant for the Taxi admin summary.
    Reduces dashboard load when polled frequently.
    """
    global _TAXI_ADMIN_SUMMARY_CACHE
    try:
        ts = float(_TAXI_ADMIN_SUMMARY_CACHE.get("ts") or 0.0)
    except Exception:
        ts = 0.0
    # 10s TTL: reasonably fresh but reduces burst load
    if _TAXI_ADMIN_SUMMARY_CACHE.get("data") is not None and (time.time() - ts) < 10.0:
        return _TAXI_ADMIN_SUMMARY_CACHE.get("data")
    data = taxi_admin_summary()
    _TAXI_ADMIN_SUMMARY_CACHE = {"ts": time.time(), "data": data}
    return data


@app.post("/taxi/drivers/balance_by_identity")
async def taxi_balance_by_identity(req: Request):
    # Only admins/superadmins may adjust driver balances.
    _require_admin_v2(req)
    try:
        try:
            body = await req.json()
        except Exception:
            body = None
        if _use_taxi_internal():
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                req_model = _TaxiBalanceIdentityReq(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            bal = _call_taxi(
                _taxi_driver_balance_by_identity,
                need_session=True,
                request_body=data,
                inject_internal=True,
                req=req_model,
            )
        else:
            r = httpx.post(_taxi_url("/drivers/balance_by_identity"), json=body, headers=_taxi_headers(), timeout=10)
            bal = r.json()
        phone = ""
        delta = None
        try:
            if isinstance(body, dict):
                phone = (body.get("phone") or "").strip()
                delta = body.get("set_cents") or body.get("delta_cents")
        except Exception:
            pass
        _audit_from_request(req, "taxi_balance_by_identity", target_phone=phone, delta_cents=delta)
        return bal
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/taxi/drivers/{driver_id}/block")
def taxi_block_driver(driver_id: str, request: Request):
    """
    Temporarily block a taxi driver (Taxi service flag only).
    Admin/SuperAdmin only.
    """
    _require_admin(request)
    try:
        r = httpx.post(_taxi_url(f"/drivers/{driver_id}/block"), headers=_taxi_headers(), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/taxi/drivers/{driver_id}/unblock")
def taxi_unblock_driver(driver_id: str, request: Request):
    """
    Unblock a taxi driver (Taxi service flag only).
    Admin/SuperAdmin only.
    """
    _require_admin(request)
    try:
        r = httpx.post(_taxi_url(f"/drivers/{driver_id}/unblock"), headers=_taxi_headers(), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.delete("/taxi/drivers/{driver_id}")
def taxi_delete_driver(driver_id: str, request: Request):
    """
    Permanently delete a taxi driver record.
    Admin/SuperAdmin only.
    """
    _require_admin(request)
    try:
        r = httpx.delete(_taxi_url(f"/drivers/{driver_id}"), headers=_taxi_headers(), timeout=10)
        # Taxi service returns {"ok": True} on success; forward JSON or basic status.
        return r.json() if r.headers.get("content-type","").startswith("application/json") else {"status_code": r.status_code, "raw": r.text}
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/taxi/rides/{ride_id}/assign")
def taxi_assign_ride(ride_id: str, driver_id: str):
    if _use_taxi_internal():
        try:
            return _call_taxi(
                _taxi_assign_ride,
                need_session=True,
                request_body=None,
                inject_internal=True,
                ride_id=ride_id,
                driver_id=driver_id,
            )
        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(status_code=502, detail=str(e))
    try:
        r = httpx.post(_taxi_url(f"/rides/{ride_id}/assign"), params={"driver_id": driver_id}, headers=_taxi_headers(), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/taxi/rides/{ride_id}")
def taxi_get_ride(ride_id: str):
    if _use_taxi_internal():
        try:
            return _call_taxi(_taxi_get_ride, need_session=True, ride_id=ride_id)
        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(status_code=502, detail=str(e))
    try:
        r = httpx.get(_taxi_url(f"/rides/{ride_id}"), headers=_taxi_headers(), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/taxi/rides/{ride_id}/accept")
def taxi_accept_ride(ride_id: str, driver_id: str):
    if _use_taxi_internal():
        try:
            return _call_taxi(
                _taxi_accept_ride,
                need_session=True,
                request_body=None,
                inject_internal=True,
                ride_id=ride_id,
                driver_id=driver_id,
            )
        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(status_code=502, detail=str(e))
    try:
        r = httpx.post(_taxi_url(f"/rides/{ride_id}/accept"), params={"driver_id": driver_id}, headers=_taxi_headers(), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/taxi/rides/{ride_id}/start")
def taxi_start_ride(ride_id: str, driver_id: str):
    if _use_taxi_internal():
        try:
            return _call_taxi(
                _taxi_start_ride,
                need_session=True,
                request_body=None,
                inject_internal=True,
                ride_id=ride_id,
                driver_id=driver_id,
            )
        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(status_code=502, detail=str(e))
    try:
        r = httpx.post(_taxi_url(f"/rides/{ride_id}/start"), params={"driver_id": driver_id}, headers=_taxi_headers(), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/taxi/rides/{ride_id}/complete")
def taxi_complete_ride(ride_id: str, driver_id: str):
    try:
        if _use_taxi_internal():
            result_obj = _call_taxi(
                _taxi_complete_ride,
                need_session=True,
                request_body=None,
                inject_internal=True,
                ride_id=ride_id,
                driver_id=driver_id,
            )
            result = result_obj
            try:
                rd = result_obj.dict() if hasattr(result_obj, "dict") else result_obj  # type: ignore[call-arg]
            except Exception:
                rd = {}
        else:
            r = httpx.post(_taxi_url(f"/rides/{ride_id}/complete"), params={"driver_id": driver_id}, headers=_taxi_headers(), timeout=10)
            result = r.json() if r.headers.get('content-type','').startswith('application/json') else {"raw": r.text, "status_code": r.status_code}
            # Fetch ride details to determine amount and rider wallet
            rd = httpx.get(_taxi_url(f"/rides/{ride_id}"), headers=_taxi_headers(), timeout=10).json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))

    # Best-effort escrow settlement (rider -> escrow -> driver) with guardrail.
    try:
        price_cents = None
        rider_wallet = None
        driver_wallet = None
        driver_id = driver_id  # for guardrail closure
        try:
            price_cents = int(rd.get("price_cents")) if rd and isinstance(rd, dict) else None
        except Exception:
            price_cents = getattr(result_obj, "price_cents", None) if "result_obj" in locals() else None  # type: ignore[arg-type]
        try:
            rider_wallet = (rd.get("rider_wallet_id") if isinstance(rd, dict) else None) or getattr(result_obj, "rider_wallet_id", None)  # type: ignore[arg-type]
            driver_wallet = (rd.get("driver_wallet_id") if isinstance(rd, dict) else None) or getattr(result_obj, "driver_wallet_id", None)  # type: ignore[arg-type]
        except Exception:
            rider_wallet = getattr(result_obj, "rider_wallet_id", None) if "result_obj" in locals() else None  # type: ignore[arg-type]
            driver_wallet = getattr(result_obj, "driver_wallet_id", None) if "result_obj" in locals() else None  # type: ignore[arg-type]
        if ESCROW_WALLET_ID and PAYMENTS_BASE and price_cents and rider_wallet and driver_wallet and price_cents > 0:
            now = int(time.time())
            lst = _TAXI_PAYOUT_EVENTS.get(driver_id, [])
            lst = [ts for ts in lst if ts >= now - 86400]
            if len(lst) < TAXI_PAYOUT_MAX_PER_DRIVER_DAY:
                lst.append(now)
                _TAXI_PAYOUT_EVENTS[driver_id] = lst
                url = _payments_url("/transfer")
                headers = {"Content-Type": "application/json"}
                leg1 = {"from_wallet_id": rider_wallet, "to_wallet_id": ESCROW_WALLET_ID, "amount_cents": price_cents}
                leg2 = {"from_wallet_id": ESCROW_WALLET_ID, "to_wallet_id": driver_wallet, "amount_cents": price_cents}
                headers1 = headers | {"Idempotency-Key": f"tx-escrow-r-{ride_id}-{price_cents}"}
                headers2 = headers | {"Idempotency-Key": f"tx-escrow-d-{ride_id}-{price_cents}"}
                httpx.post(url, json=leg1, headers=headers1, timeout=10)
                httpx.post(url, json=leg2, headers=headers2, timeout=10)
            else:
                _TAXI_PAYOUT_EVENTS[driver_id] = lst
    except Exception:
        # Settlement is best-effort; ride completion result still returned.
        pass

    return result


@app.post("/taxi/rides/{ride_id}/cancel")
def taxi_cancel_ride(ride_id: str):
    try:
        if _use_taxi_internal():
            result_obj = _call_taxi(
                _taxi_cancel_ride,
                need_session=True,
                request_body=None,
                inject_internal=True,
                ride_id=ride_id,
            )
            result = result_obj
        else:
            r = httpx.post(_taxi_url(f"/rides/{ride_id}/cancel"), headers=_taxi_headers(), timeout=10)
            # Base response from Taxi service (ride object or raw payload)
            result = r.json() if r.headers.get("content-type",""
                     ).startswith("application/json") else {"raw": r.text, "status_code": r.status_code}
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))

    # Best-effort cancellation fee charge (4000 SYP by default).
    # Guardrail: basic per-driver daily limit; never breaks cancellation.
    try:
        fee_syp = max(0, TAXI_CANCEL_FEE_SYP)
        if not PAYMENTS_BASE or fee_syp <= 0:
            return result
        # Fetch latest ride details to resolve wallets/phone/driver
        if _use_taxi_internal():
            ride_obj = _call_taxi(_taxi_get_ride, need_session=True, ride_id=ride_id)
            try:
                ride = ride_obj.dict() if hasattr(ride_obj, "dict") else ride_obj  # type: ignore[call-arg]
            except Exception:
                ride = {}
        else:
            rd = httpx.get(_taxi_url(f"/rides/{ride_id}"), headers=_taxi_headers(), timeout=10)
            ride = rd.json() if rd.headers.get("content-type",""
                         ).startswith("application/json") else {}
        if not isinstance(ride, dict):
            return result
        driver_id = (ride.get("driver_id") or "").strip()
        if not driver_id:
            # No assigned driver -> no cancellation fee
            return result
        amount_cents = int(fee_syp * 100)
        if amount_cents <= 0:
            return result
        # Resolve driver wallet (prefer field from ride, then driver lookup)
        driver_wallet = (ride.get("driver_wallet_id") or "").strip()
        if not driver_wallet and driver_id:
            try:
                dj = httpx.get(_taxi_url(f"/drivers/{driver_id}"), headers=_taxi_headers(), timeout=10)
                if dj.headers.get("content-type",""
                         ).startswith("application/json"):
                    d = dj.json()
                    if isinstance(d, dict):
                        driver_wallet = (d.get("wallet_id") or "").strip()
            except Exception:
                driver_wallet = ""
        if not driver_wallet:
            return result
        # Resolve rider wallet (prefer wallet_id, then resolve by phone)
        rider_wallet = (ride.get("rider_wallet_id") or "").strip()
        if not rider_wallet:
            phone = (ride.get("rider_phone") or "").strip()
            if phone:
                try:
                    rr = httpx.get(_payments_url(f"/resolve/phone/{phone}"), timeout=10)
                    if rr.headers.get("content-type",""
                             ).startswith("application/json"):
                        j = rr.json()
                        if isinstance(j, dict):
                            rider_wallet = (j.get("wallet_id") or "").strip()
                except Exception:
                    rider_wallet = ""
        if not rider_wallet:
            return result
        # Per-driver guardrail for cancellation fee transfers
        try:
            now = _now()
            events = _TAXI_CANCEL_EVENTS.get(driver_id) or []
            events = [ts for ts in events if ts >= now - 86400]
            if len(events) >= max(1, TAXI_CANCEL_MAX_PER_DRIVER_DAY):
                _TAXI_CANCEL_EVENTS[driver_id] = events
                _audit("taxi_cancel_guardrail", driver_id=driver_id, ride_id=ride_id, amount_cents=amount_cents)
                return result
            events.append(now)
            _TAXI_CANCEL_EVENTS[driver_id] = events
        except Exception:
            pass
        ikey = f"tx-taxi-cancel-{ride_id}-{amount_cents}"
        headers = {"content-type": "application/json", "Idempotency-Key": ikey}
        body = {
            "from_wallet_id": rider_wallet,
            "to_wallet_id": driver_wallet,
            "amount_cents": amount_cents,
            "reference": f"taxi {ride_id} cancel fee",
        }
        httpx.post(_payments_url("/transfer"), json=body, headers=headers, timeout=10)
    except Exception:
        # Best-effort: never break cancellation result on fee issues
        return result

    return result


@app.post("/taxi/rides/{ride_id}/deny")
def taxi_deny_ride(ride_id: str):
    """Driver denies current ride request: cancel and re-request to allow next nearest driver to receive it.
    This assumes upstream Taxi service matches to nearest available driver on request.
    """
    try:
        # Fetch original ride to extract pickup/dropoff
        if _use_taxi_internal():
            try:
                orig_obj = _call_taxi(_taxi_get_ride, need_session=True, ride_id=ride_id)
                orig = orig_obj.dict() if hasattr(orig_obj, "dict") else orig_obj  # type: ignore[call-arg]
            except Exception:
                orig = {}
            try:
                _call_taxi(
                    _taxi_cancel_ride,
                    need_session=True,
                    request_body=None,
                    inject_internal=True,
                    ride_id=ride_id,
                )
            except Exception:
                pass
        else:
            r0 = httpx.get(_taxi_url(f"/rides/{ride_id}"), headers=_taxi_headers(), timeout=10)
            orig = r0.json() if r0.headers.get("content-type",""
                     ).startswith("application/json") else {}
            # Cancel existing ride (ignore errors)
            try:
                httpx.post(_taxi_url(f"/rides/{ride_id}/cancel"), headers=_taxi_headers(), timeout=10)
            except Exception:
                pass
    except Exception:
        orig = {}
    # Build new request from original coordinates if available
    body = {}
    def _to_f(v):
        try:
            if v is None:
                return None
            if isinstance(v, (int, float)):
                return float(v)
            return float(str(v))
        except Exception:
            return None
    pickup = orig.get('pickup') if isinstance(orig, dict) else None
    dropoff = orig.get('dropoff') if isinstance(orig, dict) else None
    body['pickup_lat'] = _to_f(orig.get('pickup_lat') or (pickup or {}).get('lat')) or 0.0
    body['pickup_lon'] = _to_f(orig.get('pickup_lon') or (pickup or {}).get('lon') or (pickup or {}).get('lng')) or 0.0
    dl = _to_f(orig.get('dropoff_lat') or (dropoff or {}).get('lat'))
    dlo = _to_f(orig.get('dropoff_lon') or (dropoff or {}).get('lon') or (dropoff or {}).get('lng'))
    if dl is not None and dlo is not None:
        body['dropoff_lat'] = dl
        body['dropoff_lon'] = dlo
    try:
        if _use_taxi_internal():
            try:
                req_model = _TaxiRideRequest(**body)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            result = _call_taxi(
                _taxi_request_ride,
                need_session=True,
                request_body=body,
                inject_internal=True,
                req=req_model,
                idempotency_key=None,
            )
            return result
        r = httpx.post(_taxi_url("/rides/request"), json=body, headers=_taxi_headers(), timeout=10)
        return r.json() if r.headers.get("content-type",""
                 ).startswith("application/json") else {"raw": r.text, "status_code": r.status_code}
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


# ---- Payments proxy helpers ----
def _payments_url(path: str) -> str:
    if not PAYMENTS_BASE:
        raise HTTPException(status_code=500, detail="PAYMENTS_BASE_URL not configured")
    return PAYMENTS_BASE.rstrip("/") + path

# ---- Bus proxy helpers ----
def _bus_url(path: str) -> str:
    if not BUS_BASE:
        raise HTTPException(status_code=500, detail="BUS_BASE_URL not configured")
    return BUS_BASE.rstrip("/") + path


# --- Bus internal service (monolith mode) ---
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
        quote as _bus_quote,
        book_trip as _bus_book_trip,
        booking_status as _bus_booking_status,
        booking_tickets as _bus_booking_tickets,
        booking_search as _bus_booking_search,
        cancel_booking as _bus_cancel_booking,
        ticket_board as _bus_ticket_board,
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
            r = httpx.get(_payments_url(f"/resolve/phone/{phone}"), timeout=6)
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
            r = httpx.get(_bus_url("/operators"), timeout=10)
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
            r = httpx.get(_bus_url("/operators"), timeout=10)
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
            r = httpx.get(_bus_url("/routes"), timeout=10)
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
            r = httpx.get(_bus_url(f"/trips/{tid}"), timeout=10)
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
    Bus health: prefer the internal Bus service when running in monolith
    mode; otherwise proxy to an external BUS_BASE_URL if configured.
    """
    # Internal Bus (monolith mode)
    if _use_bus_internal():
        if not _BUS_INTERNAL_AVAILABLE:
            raise HTTPException(status_code=500, detail="bus internal not available")
        # For now we keep the check simple: if the internal bus service is
        # importable we report a light-weight OK marker. Detailed DB/route
        # checks are handled via /bus/admin/summary.
        return {"status": "ok", "mode": "internal"}
    # External bus-api
    try:
        r = httpx.get(_bus_url("/health"), timeout=10)
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
        headers = {}
        if PAYMENTS_INTERNAL_SECRET:
            headers["X-Internal-Secret"] = PAYMENTS_INTERNAL_SECRET
        r = httpx.post(_payments_url("/topup/batch_create"), json=body, headers=headers, timeout=20)
        return r.json() if r.headers.get('content-type','').startswith('application/json') else {"raw": r.text, "status_code": r.status_code}
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/topup/batches")
def topup_batches(request: Request, seller_id: str = "", limit: int = 50):
    # Default to current seller unless allow_all or explicit seller_id provided
    if not seller_id:
        try:
            seller_id = _require_seller(request)
        except HTTPException:
            seller_id = ""
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
        r = httpx.get(_payments_url("/topup/batches"), params=params, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/topup/batches/{batch_id}")
def topup_batch_detail(request: Request, batch_id: str):
    # Ensure seller is authenticated; payments returns full list, BFF only exposes via auth
    _require_seller(request)
    try:
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            with _pay_internal_session() as s:
                return _pay_topup_batch_detail(batch_id=batch_id, s=s, admin_ok=True)
        r = httpx.get(_payments_url(f"/topup/batches/{batch_id}"), timeout=15)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
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
            r = httpx.post(_payments_url(f"/topup/vouchers/{code}/void"), headers={"X-Internal-Secret": PAYMENTS_INTERNAL_SECRET}, timeout=10)
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
                return _pay_topup_redeem(treq, s=s)
        r = httpx.post(_payments_url("/topup/redeem"), json=body, headers=headers, timeout=12)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/topup/print/{batch_id}", response_class=HTMLResponse)
def topup_print(batch_id: str):
    """
    Printable QR sheet for a topup batch.

    In monolith/internal mode this uses the Payments domain directly;
    otherwise it falls back to the external PAYMENTS_BASE_URL.
    """
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
                        arr.append(it.dict())  # type: ignore[call-arg]
                    except Exception:
                        arr.append({
                            "code": getattr(it, "code", ""),
                            "amount_cents": getattr(it, "amount_cents", 0),
                            "payload": getattr(it, "payload", ""),
                        })
        else:
            r = httpx.get(_payments_url(f"/topup/batches/{batch_id}"), timeout=15)
            arr = r.json() if r.headers.get('content-type','').startswith('application/json') else []
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"fetch batch failed: {e}")
    title = f"Topup Batch {batch_id}"
    rows = []
    for v in arr:
        payload = v.get('payload','')
        code = v.get('code','')
        amt = int(v.get('amount_cents',0))
        rows.append(f"<div class=\"card\"><img src=\"/qr.png?data={_json.dumps(payload)[1:-1]}\" /><div class=\"meta\"><b>{code}</b><br/><small>{amt} SYP</small></div></div>")
    html = f"""
<!doctype html>
<html><head><meta charset=utf-8 /><meta name=viewport content='width=device-width, initial-scale=1' />
<title>{title}</title>
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
  <h1>{title}</h1>
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
        r = httpx.get(_payments_url("/admin/roles"), params=params, headers={"X-Internal-Secret": PAYMENTS_INTERNAL_SECRET} if PAYMENTS_INTERNAL_SECRET else {}, timeout=10)
        return r.json()
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/admin/ids_for_phone")
def admin_ids_for_phone(request: Request, phone: str):
    """
    Superadmin helper: returns core IDs associated with a phone number.

    - payments user_id / wallet_id
    - taxi driver_id(s)
    - bus operator_id(s) (matched by wallet_id)
    - stays operator_id(s) (matched by phone)
    - effective roles + admin/superadmin flags
    """
    _require_superadmin(request)
    phone = (phone or "").strip()
    if not phone:
        raise HTTPException(status_code=400, detail="phone required")

    user_id: str | None = None
    wallet_id: str | None = None
    roles: list[str] = []
    driver_ids: list[str] = []
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
            r = httpx.get(_payments_url(f"/resolve/phone/{phone}"), timeout=6)
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

    # Taxi: find drivers by phone
    try:
        if _use_taxi_internal():
            if not _TAXI_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="taxi internal not available")
            drivers = _call_taxi(  # type: ignore[arg-type]
                _taxi_list_drivers,  # type: ignore[name-defined]
                need_session=True,
                status="",
                limit=500,
            )
            for d in drivers or []:
                try:
                    ph = str(getattr(d, "phone", "") or "").strip()
                    if ph != phone:
                        continue
                    did = str(getattr(d, "id", "") or "").strip()
                    if did and did not in driver_ids:
                        driver_ids.append(did)
                except Exception:
                    continue
        elif TAXI_BASE:
            params = {"status": "", "limit": 500}
            r = httpx.get(_taxi_url("/drivers"), params=params, headers=_taxi_headers(), timeout=10)
            if r.headers.get("content-type", "").startswith("application/json"):
                arr = r.json()
                if isinstance(arr, list):
                    for d in arr:
                        try:
                            ph = str((d.get("phone") or "")).strip()
                            if ph != phone:
                                continue
                            did = str(d.get("id") or "").strip()
                            if did and did not in driver_ids:
                                driver_ids.append(did)
                        except Exception:
                            continue
    except HTTPException:
        raise
    except Exception:
        driver_ids = driver_ids or []

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
                r = httpx.get(_bus_url("/operators"), timeout=10)
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

    # Stays operators: match by phone (internal only for now)
    try:
        if _use_stays_internal():
            if not _STAYS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="stays internal not available")
            from apps.stays.app.main import Operator as _StaysOperator  # type: ignore[import]
            with _stays_internal_session() as s:  # type: ignore[name-defined]
                try:
                    rows = s.execute(
                        select(_StaysOperator).where(_StaysOperator.phone == phone)
                    ).scalars().all()
                except Exception:
                    rows = []
                for op in rows or []:
                    try:
                        oid = str(getattr(op, "id", "") or "").strip()
                        if oid and oid not in stays_operator_ids:
                            stays_operator_ids.append(oid)
                    except Exception:
                        continue
    except HTTPException:
        raise
    except Exception:
        stays_operator_ids = stays_operator_ids or []

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
        "driver_ids": driver_ids,
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
        r = httpx.post(_payments_url("/admin/roles"), json=body, headers={"X-Internal-Secret": PAYMENTS_INTERNAL_SECRET} if PAYMENTS_INTERNAL_SECRET else {}, timeout=10)
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
            r = httpx.get(_payments_url(f"/resolve/phone/{phone}"), timeout=10)
            if r.status_code == 404:
                # Create user then resolve again.
                r_create = httpx.post(_payments_url("/users"), json={"phone": phone}, timeout=10)
                if r_create.status_code >= 400:
                    raise HTTPException(status_code=r_create.status_code, detail=r_create.text)
                r = httpx.get(_payments_url(f"/resolve/phone/{phone}"), timeout=10)
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
            headers = {"X-Internal-Secret": PAYMENTS_INTERNAL_SECRET} if PAYMENTS_INTERNAL_SECRET else {}  # noqa: E501
            r = client.post(
                _payments_url("/admin/roles"),
                json={"phone": phone, "role": "operator_bus"},
                headers=headers,
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
        r = httpx.delete(_payments_url("/admin/roles"), json=body, headers={"X-Internal-Secret": PAYMENTS_INTERNAL_SECRET} if PAYMENTS_INTERNAL_SECRET else {}, timeout=10)
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

    # Static demo accounts covering the main domains.
    demo_accounts: list[dict[str, Any]] = [
        {
            "phone": "+963000000001",
            "label": "Enduser demo (wallet only)",
            "roles": [],
        },
        {
            "phone": "+963000000002",
            "label": "Taxi operator demo",
            "roles": ["operator_taxi"],
        },
        {
            "phone": "+963000000003",
            "label": "Bus operator demo",
            "roles": ["operator_bus"],
        },
        {
            "phone": "+963000000004",
            "label": "Food operator demo",
            "roles": ["operator_food"],
        },
        {
            "phone": "+963000000005",
            "label": "Hotels & Stays operator demo",
            "roles": ["operator_stays"],
        },
        {
            "phone": "+963000000006",
            "label": "Realestate operator demo",
            "roles": ["operator_realestate"],
        },
        {
            "phone": "+963000000007",
            "label": "Building Materials / Commerce operator demo",
            "roles": ["operator_commerce"],
        },
        {
            "phone": "+963000000008",
            "label": "Courier & Transport operator demo",
            "roles": ["operator_freight"],
        },
        {
            "phone": "+963000000009",
            "label": "Carrental & Carmarket operator demo",
            "roles": ["operator_carrental"],
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
                    r = httpx.post(_payments_url("/users"), json={"phone": ph}, timeout=10)
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
                        headers: dict[str, str] = {}
                        if PAYMENTS_INTERNAL_SECRET:
                            headers["X-Internal-Secret"] = PAYMENTS_INTERNAL_SECRET
                        httpx.post(_payments_url("/admin/roles"), json=body, headers=headers, timeout=10)
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
    html = """
<!doctype html>
<html><head><meta name=viewport content='width=device-width, initial-scale=1' />
<title>Topup Sellers</title>
<style>body{font-family:sans-serif;margin:20px;max-width:760px}</style>
</head><body>
<h1>Topup Sellers</h1>
<p>Manage seller roles (phone E.164). Requires server internal secret.</p>
<div>
  <input id=phone placeholder='+963...' />
  <button onclick='add()'>Add Seller</button>
  <button onclick='del()'>Remove Seller</button>
</div>
<p><button onclick='load()'>Reload</button></p>
<pre id=out></pre>
<script>
async function add(){ const p=document.getElementById('phone').value.trim(); const r=await fetch('/admin/roles',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({phone:p,role:'seller'})}); out.textContent=await r.text(); }
async function del(){ const p=document.getElementById('phone').value.trim(); const r=await fetch('/admin/roles',{method:'DELETE',headers:{'content-type':'application/json'},body:JSON.stringify({phone:p,role:'seller'})}); out.textContent=await r.text(); }
async function load(){ const r=await fetch('/admin/roles?role=seller&limit=500'); out.textContent=await r.text(); }
load();
</script>
</body></html>
"""
    return HTMLResponse(content=html)


@app.get("/me/roles")
def me_roles(request: Request):
    phone = _auth_phone(request)
    if not phone:
        raise HTTPException(status_code=401, detail="unauthorized")
    roles = _get_effective_roles(phone)
    return {"phone": phone, "roles": roles}


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
def topup_print_pdf(batch_id: str):
    if _pdfcanvas is None or _qr is None:
        raise HTTPException(status_code=500, detail="PDF/QR library not available")
    # Fetch vouchers
    try:
        r = httpx.get(_payments_url(f"/topup/batches/{batch_id}"), timeout=15)
        arr = r.json() if r.headers.get('content-type','').startswith('application/json') else []
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"fetch batch failed: {e}")
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
        payload = v.get('payload','')
        code = v.get('code','')
        amt = int(v.get('amount_cents',0))
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
        r = httpx.post(_payments_url("/users"), json=body, timeout=10)
        return r.json()
    except HTTPException:
        # Already a structured HTTP error from upstream helper.
        raise
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/payments/wallets/{wallet_id}")
def payments_wallet(wallet_id: str):
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
        r = httpx.get(_payments_url(f"/wallets/{wallet_id}"), timeout=10)
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
                    return _pay_transfer(req_model, request=req, s=s)
            except HTTPException:
                raise
            except Exception as e:
                raise HTTPException(status_code=502, detail=str(e))
        r = httpx.post(_payments_url("/transfer"), json=body, headers=headers, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        # Guardrail or validation errors should be passed through directly
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/payments/wallets/{wallet_id}/topup")
async def payments_topup(wallet_id: str, req: Request):
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
        # Prefer internal Payments integration in monolith mode to avoid
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
        r = httpx.post(_payments_url(f"/wallets/{wallet_id}/topup"), json=body, headers=headers, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


# ---- Cash Mandate proxies ----
@app.post("/payments/cash/create")
async def payments_cash_create(req: Request):
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
        r = httpx.post(_payments_url("/cash/create"), json=body, headers=headers, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


# ---- Favorites & Requests proxies ----
@app.post("/payments/favorites")
async def payments_fav_create(req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        r = httpx.post(_payments_url("/favorites"), json=body, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/payments/favorites")
def payments_fav_list(owner_wallet_id: str):
    try:
        r = httpx.get(_payments_url("/favorites"), params={"owner_wallet_id": owner_wallet_id}, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.delete("/payments/favorites/{fid}")
def payments_fav_delete(fid: str):
    try:
        r = httpx.delete(_payments_url(f"/favorites/{fid}"), timeout=10)
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
        r = httpx.get(_bus_url("/cities"), params={"q": q, "limit": limit}, timeout=10)
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
        r = httpx.get(_bus_url("/trips/search"), params=params, timeout=10)
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
        r = httpx.get(_bus_url(f"/trips/{trip_id}"), timeout=10)
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
        r = httpx.post(_bus_url(f"/trips/{trip_id}/book"), json=body, headers=headers, timeout=15)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        # Let FastAPI propagate existing HTTPException (status + detail)
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/bus/bookings/{booking_id}")
def bus_booking_status(booking_id: str):
    try:
        if _use_bus_internal():
            if not _BUS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="bus internal not available")
            with _bus_internal_session() as s:
                return _bus_booking_status(booking_id=booking_id, s=s)
        r = httpx.get(_bus_url(f"/bookings/{booking_id}"), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/bus/bookings/{booking_id}/tickets")
def bus_booking_tickets(booking_id: str):
    try:
        if _use_bus_internal():
            if not _BUS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="bus internal not available")
            with _bus_internal_session() as s:
                return _bus_booking_tickets(booking_id=booking_id, s=s)
        r = httpx.get(_bus_url(f"/bookings/{booking_id}/tickets"), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
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
        r_status = httpx.get(_bus_url(f"/bookings/{booking_id}"), timeout=10)
        r_status.raise_for_status()
        booking = r_status.json()
        if isinstance(booking, dict):
            wid = (booking.get("wallet_id") or "").strip()
            if wid and wid != wallet_id:
                raise HTTPException(status_code=403, detail="booking does not belong to caller wallet")
        r = httpx.post(_bus_url(f"/bookings/{booking_id}/cancel"), timeout=15)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/bus/bookings/search")
def bus_booking_search(wallet_id: str | None = None, phone: str | None = None, limit: int = 20):
    params: dict[str, str | int] = {"limit": limit}
    if wallet_id:
        params["wallet_id"] = wallet_id
    if phone:
        params["phone"] = phone
    try:
        if _use_bus_internal():
            if not _BUS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="bus internal not available")
            with _bus_internal_session() as s:
                return _bus_booking_search(wallet_id=wallet_id, phone=phone, limit=limit, s=s)
        r = httpx.get(_bus_url("/bookings/search"), params=params, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
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
        r = httpx.post(_bus_url("/tickets/board"), json=body, timeout=10)
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
                rb = httpx.get(_bus_url(f"/bookings/{booking_id}"), timeout=10)
                if rb.headers.get("content-type", "").startswith("application/json"):
                    booking = rb.json()
                rtks = httpx.get(_bus_url(f"/bookings/{booking_id}/tickets"), timeout=10)
                if rtks.headers.get("content-type", "").startswith("application/json"):
                    tickets = rtks.json()
            if trip_id:
                rt = httpx.get(_bus_url(f"/trips/{trip_id}"), timeout=10)
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
        r = httpx.post(_bus_url("/cities"), json=body, timeout=10)
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
        r = httpx.post(_bus_url("/operators"), json=body, timeout=10)
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
        r = httpx.post(_bus_url("/routes"), json=body, timeout=10)
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
        r = httpx.get(_bus_url("/routes"), params=params or None, timeout=10)
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
        r = httpx.get(_bus_url("/operators"), timeout=10)
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
def bus_operator_online(operator_id: str):
    """
    Toggle a Bus operator online. In monolith/internal mode this hits the
    Bus domain in‑process; otherwise it proxies to BUS_BASE_URL.
    """
    try:
        if _use_bus_internal():
            if not _BUS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="bus internal not available")
            with _bus_internal_session() as s:  # type: ignore[name-defined]
                return _bus_operator_online(operator_id=operator_id, s=s)  # type: ignore[name-defined]  # noqa: E501
        r = httpx.post(_bus_url(f"/operators/{operator_id}/online"), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/bus/operators/{operator_id}/offline")
def bus_operator_offline(operator_id: str):
    """
    Toggle a Bus operator offline. In monolith/internal mode this hits the
    Bus domain in‑process; otherwise it proxies to BUS_BASE_URL.
    """
    try:
        if _use_bus_internal():
            if not _BUS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="bus internal not available")
            with _bus_internal_session() as s:  # type: ignore[name-defined]
                return _bus_operator_offline(operator_id=operator_id, s=s)  # type: ignore[name-defined]  # noqa: E501
        r = httpx.post(_bus_url(f"/operators/{operator_id}/offline"), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/bus/operators/{operator_id}/online")
def bus_operator_online(operator_id: str, request: Request):
    _require_admin_or_superadmin(request)
    try:
        if _use_bus_internal():
            if not _BUS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="bus internal not available")
            with _bus_internal_session() as s:
                return _bus_operator_online(operator_id=operator_id, s=s)
        r = httpx.post(_bus_url(f"/operators/{operator_id}/online"), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/bus/operators/{operator_id}/offline")
def bus_operator_offline(operator_id: str, request: Request):
    _require_admin_or_superadmin(request)
    try:
        if _use_bus_internal():
            if not _BUS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="bus internal not available")
            with _bus_internal_session() as s:
                return _bus_operator_offline(operator_id=operator_id, s=s)
        r = httpx.post(_bus_url(f"/operators/{operator_id}/offline"), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))

@app.get("/bus/operators/{operator_id}/stats")
def bus_operator_stats(operator_id: str, period: str = "today"):
    try:
        if _use_bus_internal():
            if not _BUS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="bus internal not available")
            with _bus_internal_session() as s:
                return _bus_operator_stats(operator_id=operator_id, period=period, s=s)
        r = httpx.get(_bus_url(f"/operators/{operator_id}/stats"), params={"period": period}, timeout=10)
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
        r = httpx.post(_bus_url("/trips"), json=body, timeout=10)
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
        r = httpx.post(_bus_url(f"/trips/{trip_id}/publish"), timeout=10)
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
        r = httpx.get(_bus_url("/admin/summary"), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/payments/requests")
async def payments_req_create(req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            data = body or {}
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
        r = httpx.post(_payments_url("/requests"), json=body, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/payments/requests")
def payments_req_list(wallet_id: str, kind: str = "", limit: int = 100):
    params = {"wallet_id": wallet_id}
    if kind: params["kind"] = kind
    params["limit"] = max(1, min(limit, 500))
    try:
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            try:
                with _pay_internal_session() as s:
                    return _pay_list_requests(wallet_id=wallet_id, kind=kind, limit=max(1, min(limit, 500)), s=s)
            except HTTPException:
                raise
            except Exception as e:
                raise HTTPException(status_code=502, detail=str(e))
        r = httpx.get(_payments_url("/requests"), params=params, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/payments/resolve/phone/{phone}")
def payments_resolve_phone(phone: str):
    try:
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            try:
                with _pay_internal_session() as s:
                    return _pay_resolve_phone(phone=phone, s=s)
            except HTTPException:
                raise
            except Exception as e:
                raise HTTPException(status_code=502, detail=str(e))
        r = httpx.get(_payments_url(f"/resolve/phone/{phone}"), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/payments/requests/by_phone")
async def payments_req_by_phone(req: Request):
    # body: {from_wallet_id, to_phone, amount_cents, message?, expires_in_secs?}
    try:
        body = await req.json()
    except Exception:
        body = {}
    to_phone = (body or {}).get("to_phone")
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
                payload = {k: v for k, v in body.items() if k != "to_phone"}
                payload["to_wallet_id"] = to_wallet
                try:
                    req_model = _PayRequestCreate(**payload)
                except Exception as e:
                    raise HTTPException(status_code=400, detail=str(e))
                pr = _pay_create_request(req_model, s=s)
            # SMS Notify bleibt wie bisher
            try:
                amt = body.get("amount_cents")
                msg = body.get("message") or ""
                if os.getenv("SMS_NOTIFY_URL"):
                    httpx.post(os.getenv("SMS_NOTIFY_URL"), json={"to": to_phone, "text": f"Payment request: {amt}. {msg}"}, timeout=5)
            except Exception:
                pass
            return pr
        # HTTP-Fallback
        rr = httpx.get(_payments_url(f"/resolve/phone/{to_phone}"), timeout=10)
        to_wallet = rr.json().get("wallet_id") if rr.status_code == 200 else None
        if not to_wallet:
            raise HTTPException(status_code=404, detail="phone not found")
        payload = {k: v for k, v in body.items() if k != "to_phone"}
        payload["to_wallet_id"] = to_wallet
        r = httpx.post(_payments_url("/requests"), json=payload, timeout=10)
        try:
            j = r.json()
        except Exception:
            j = {"status_code": r.status_code, "raw": r.text}
        if r.status_code == 200:
            try:
                amt = body.get("amount_cents")
                msg = body.get("message") or ""
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
    try:
        try:
            body = await req.json() if hasattr(req, "json") else {}
        except Exception:
            body = {}
        if not isinstance(body, dict):
            body = {}
        to_wallet_id = body.get("to_wallet_id")
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            ikey = req.headers.get("Idempotency-Key") if hasattr(req, "headers") else None
            with _pay_internal_session() as s:
                if _pay_accept_request_core:  # type: ignore[truthy-function]
                    return _pay_accept_request_core(rid=rid, ikey=ikey, s=s, to_wallet_id=to_wallet_id)  # type: ignore[arg-type]
                return _pay_accept_request(rid=rid, s=s)
        r = httpx.post(_payments_url(f"/requests/{rid}/accept"), json={"to_wallet_id": to_wallet_id}, timeout=10)
        return r.json()
    except HTTPException:
        raise
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/payments/requests/{rid}/cancel")
def payments_req_cancel(rid: str):
    try:
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            try:
                with _pay_internal_session() as s:
                    return _pay_cancel_request(rid=rid, s=s)
            except HTTPException:
                raise
            except Exception as e:
                raise HTTPException(status_code=502, detail=str(e))
        r = httpx.post(_payments_url(f"/requests/{rid}/cancel"), timeout=10)
        return r.json() if r.headers.get("content-type", "").startswith("application/json") else {"raw": r.text}
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/payments/cash/redeem")
async def payments_cash_redeem(req: Request):
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
        r = httpx.post(_payments_url("/cash/redeem"), json=body, headers=headers, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/payments/cash/cancel")
async def payments_cash_cancel(req: Request):
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
        r = httpx.post(_payments_url("/cash/cancel"), json=body, headers=headers, timeout=10)
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
        r = httpx.get(_payments_url(f"/cash/status/{code}"), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


# ---- Sonic Pay proxies ----
@app.post("/payments/sonic/issue")
async def payments_sonic_issue(req: Request):
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
        r = httpx.post(_payments_url("/sonic/issue"), json=body, headers=headers, timeout=10)
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
        r = httpx.post(_payments_url("/sonic/redeem"), json=body, headers=headers, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/payments/idempotency/{ikey}")
def payments_idempotency(ikey: str):
    try:
        r = httpx.get(_payments_url(f"/idempotency/{ikey}"), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


# ---- Alias proxies ----
@app.post("/payments/alias/request")
async def payments_alias_request(req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            data = body or {}
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
        r = httpx.post(_payments_url("/alias/request"), json=body, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


# ---- EV / Charging helpers (TomTom) ----


@app.get("/ev/stations")
def ev_stations(
    lat: float,
    lon: float,
    radius_m: int = 5000,
    connector: str | None = None,
    min_kw: float | None = None,
    provider: str | None = None,
    limit: int = 20,
):
    """
    Nearby EV charging stations with optional live availability (TomTom).

    Query params:
      - lat, lon: center point
      - radius_m: search radius (default 5000)
      - connector: optional connector type filter (e.g. 'ccs', 'type2')
      - min_kw: minimum connector power (kW)
      - provider: substring to match operator/brand
      - limit: max stations to return (<= 50)
    """
    if not TOMTOM_API_KEY:
        raise HTTPException(status_code=400, detail="TOMTOM_API_KEY not configured")
    base = TOMTOM_BASE.rstrip("/")
    radius_m = max(500, min(radius_m, 50000))
    limit = max(1, min(limit, 50))
    # TomTom categorySearch for EV charging locations
    from urllib.parse import quote

    category = "electric.vehicle.charging.location"
    path = f"/search/2/categorySearch/{quote(category)}.json"
    params: dict[str, object] = {
        "key": TOMTOM_API_KEY,
        "lat": float(lat),
        "lon": float(lon),
        "radius": radius_m,
        "limit": limit,
        # Request charging availability extension when enabled in account.
        "extensions": "chargingAvailability",
    }
    try:
        r = _httpx_client().get(base + path, params=params)
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"ev upstream error: {e}")
    if r.status_code >= 400:
        raise HTTPException(status_code=502, detail=f"ev upstream error: {r.text[:200]}")
    try:
        j = r.json()
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"invalid ev json: {e}")
    results = j.get("results") or []
    out: list[dict[str, Any]] = []
    connector_filter = (connector or "").strip().lower()
    provider_filter = (provider or "").strip().lower()
    for item in results:
        try:
            if not isinstance(item, dict):
                continue
            pos = item.get("position") or {}
            plat = float(pos.get("lat") or pos.get("latitude") or 0.0)
            plon = float(pos.get("lon") or pos.get("longitude") or 0.0)
            poi = item.get("poi") or {}
            name = ""
            brand = ""
            cats = []
            if isinstance(poi, dict):
                name = (poi.get("name") or "") or ""
                brand = (poi.get("brand") or poi.get("operator") or "") or ""
                cats = poi.get("categories") or []
            addr_str = ""
            address = item.get("address") or {}
            if isinstance(address, dict):
                addr_str = (address.get("freeformAddress") or "") or ""
            # Charging park / connectors
            park = item.get("chargingPark") or {}
            connectors_raw = []
            if isinstance(park, dict):
                connectors_raw = park.get("connectors") or park.get("connectorSet") or []
            connectors_out: list[dict[str, Any]] = []
            max_power_kw: float | None = None
            has_connector_match = False if connector_filter else True
            has_power_match = False if min_kw is not None else True
            for c in connectors_raw or []:
                if not isinstance(c, dict):
                    continue
                raw_type = c.get("type") or c.get("connectorType") or ""
                ctype = str(raw_type)
                try:
                    pkw = float(c.get("maxPowerKW") or c.get("powerKW") or 0.0)
                except Exception:
                    pkw = 0.0
                connectors_out.append({"type": ctype, "power_kw": pkw})
                if max_power_kw is None or pkw > max_power_kw:
                    max_power_kw = pkw
                if connector_filter and ctype.lower().find(connector_filter) >= 0:
                    has_connector_match = True
                if min_kw is not None and pkw >= float(min_kw):
                    has_power_match = True
            # Filters
            if connector_filter and not has_connector_match:
                continue
            if min_kw is not None and not has_power_match:
                continue
            if provider_filter:
                provider_text = f"{name} {brand}".lower()
                if provider_filter not in provider_text:
                    continue
            availability = item.get("chargingAvailability") or {}
            out.append(
                {
                    "lat": plat,
                    "lon": plon,
                    "name": name,
                    "address": addr_str,
                    "brand": brand,
                    "categories": cats,
                    "connectors": connectors_out,
                    "max_power_kw": max_power_kw,
                    "availability": availability,
                }
            )
        except Exception:
            continue
    return {"ok": True, "count": len(out), "stations": out}


# ---- Carmarket proxies ----
def _carmarket_url(path: str) -> str:
    if not CARMARKET_BASE:
        raise HTTPException(status_code=500, detail="CARMARKET_BASE_URL not configured")
    return CARMARKET_BASE.rstrip("/") + path


# --- Carmarket internal service (monolith mode) ---
_CARMARKET_INTERNAL_AVAILABLE = False
try:
    from sqlalchemy.orm import Session as _CarmarketSession  # type: ignore[import]
    from apps.carmarket.app import main as _carmarket_main  # type: ignore[import]
    from apps.carmarket.app.main import (  # type: ignore[import]
        engine as _carmarket_engine,
        get_session as _carmarket_get_session,
        ListingCreate as _CarmarketListingCreate,
        ListingUpdate as _CarmarketListingUpdate,
        ListingOut as _CarmarketListingOut,
        InquiryCreate as _CarmarketInquiryCreate,
        create_listing as _carmarket_create_listing,
        list_listings as _carmarket_list_listings,
        get_listing as _carmarket_get_listing,
        update_listing as _carmarket_update_listing,
        delete_listing as _carmarket_delete_listing,
        create_inquiry as _carmarket_create_inquiry,
    )
    _CARMARKET_INTERNAL_AVAILABLE = True
except Exception:
    _CarmarketSession = None  # type: ignore[assignment]
    _carmarket_engine = None  # type: ignore[assignment]
    _CARMARKET_INTERNAL_AVAILABLE = False


def _use_carmarket_internal() -> bool:
    if _force_internal(_CARMARKET_INTERNAL_AVAILABLE):
        return True
    mode = os.getenv("CARMARKET_INTERNAL_MODE", "auto").lower()
    if mode == "off":
        return False
    if not _CARMARKET_INTERNAL_AVAILABLE:
        return False
    if mode == "on":
        return True
    return not bool(CARMARKET_BASE)


def _carmarket_internal_session():
    if not _CARMARKET_INTERNAL_AVAILABLE or _CarmarketSession is None or _carmarket_engine is None:  # type: ignore[truthy-function]
        raise RuntimeError("Carmarket internal service not available")
    return _CarmarketSession(_carmarket_engine)  # type: ignore[call-arg]


@app.get("/carmarket/listings")
def car_listings(q: str = "", city: str = "", make: str = "", min_price: int = 0, max_price: int = 0, limit: int = 20):
    params: dict[str, object] = {}
    if q:
        params["q"] = q
    if city:
        params["city"] = city
    if make:
        params["make"] = make
    if min_price:
        params["min_price"] = min_price
    if max_price:
        params["max_price"] = max_price
    params["limit"] = max(1, min(limit, 50))
    try:
        if _use_carmarket_internal():
            if not _CARMARKET_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="carmarket internal not available")
            min_p = None if min_price <= 0 else min_price
            max_p = None if max_price <= 0 else max_price
            with _carmarket_internal_session() as s:
                return _carmarket_list_listings(q=q, city=city, make=make, min_price=min_p, max_price=max_p, limit=limit, s=s)
        r = httpx.get(_carmarket_url("/listings"), params=params, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/carmarket/listings/{lid}")
def car_get_listing(lid: int):
    try:
        if _use_carmarket_internal():
            if not _CARMARKET_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="carmarket internal not available")
            with _carmarket_internal_session() as s:
                return _carmarket_get_listing(listing_id=lid, s=s)
        r = httpx.get(_carmarket_url(f"/listings/{lid}"), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/carmarket/listings")
async def car_create_listing(req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    headers: dict[str, str] = {}
    try:
        ikey = req.headers.get("Idempotency-Key")
    except Exception:
        ikey = None
    if ikey:
        headers["Idempotency-Key"] = ikey
    try:
        if _use_carmarket_internal():
            if not _CARMARKET_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="carmarket internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                lreq = _CarmarketListingCreate(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _carmarket_internal_session() as s:
                return _carmarket_create_listing(req=lreq, idempotency_key=ikey, s=s)
        r = httpx.post(_carmarket_url("/listings"), json=body, headers=headers, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.patch("/carmarket/listings/{lid}")
async def car_update_listing(lid: int, req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        if _use_carmarket_internal():
            if not _CARMARKET_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="carmarket internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                ureq = _CarmarketListingUpdate(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _carmarket_internal_session() as s:
                return _carmarket_update_listing(listing_id=lid, req=ureq, s=s)
        r = httpx.patch(_carmarket_url(f"/listings/{lid}"), json=body, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.delete("/carmarket/listings/{lid}")
def car_delete_listing(lid: int):
    try:
        if _use_carmarket_internal():
            if not _CARMARKET_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="carmarket internal not available")
            with _carmarket_internal_session() as s:
                return _carmarket_delete_listing(listing_id=lid, s=s)
        r = httpx.delete(_carmarket_url(f"/listings/{lid}"), timeout=10)
        return r.json() if r.headers.get("content-type", "").startswith("application/json") else {"raw": r.text, "status_code": r.status_code}
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/carmarket/inquiries")
async def car_create_inquiry(req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    headers: dict[str, str] = {}
    try:
        ikey = req.headers.get("Idempotency-Key")
    except Exception:
        ikey = None
    if ikey:
        headers["Idempotency-Key"] = ikey
    try:
        if _use_carmarket_internal():
            if not _CARMARKET_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="carmarket internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                ireq = _CarmarketInquiryCreate(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _carmarket_internal_session() as s:
                return _carmarket_create_inquiry(req=ireq, idempotency_key=ikey, s=s)
        r = httpx.post(_carmarket_url("/inquiries"), json=body, headers=headers, timeout=10)
        return r.json() if r.headers.get("content-type", "").startswith("application/json") else {"raw": r.text, "status_code": r.status_code}
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/payments/alias/verify")
async def payments_alias_verify(req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                req_model = _PayAliasVerifyReq(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            try:
                with _pay_internal_session() as s:
                    return _pay_alias_verify(req_model, s=s)
            except HTTPException:
                raise
            except Exception as e:
                raise HTTPException(status_code=502, detail=str(e))
        r = httpx.post(_payments_url("/alias/verify"), json=body, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/payments/alias/resolve/{handle}")
def payments_alias_resolve(handle: str):
    try:
        if _use_pay_internal():
            if not _PAY_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="payments internal not available")
            try:
                with _pay_internal_session() as s:
                    return _pay_alias_resolve(handle=handle, s=s)
            except HTTPException:
                raise
            except Exception as e:
                raise HTTPException(status_code=502, detail=str(e))
        r = httpx.get(_payments_url(f"/alias/resolve/{handle}"), timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


# ---- Admin alias moderation proxies ----
@app.post("/payments/admin/alias/block")
async def payments_admin_alias_block(req: Request):
    if not PAYMENTS_INTERNAL_SECRET:
        raise HTTPException(status_code=403, detail="Server not configured for admin alias")
    try:
        body = await req.json()
    except Exception:
        body = None
    headers = {"X-Internal-Secret": PAYMENTS_INTERNAL_SECRET}
    try:
        r = httpx.post(_payments_url("/admin/alias/block"), json=body, headers=headers, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/payments/admin/alias/rename")
async def payments_admin_alias_rename(req: Request):
    if not PAYMENTS_INTERNAL_SECRET:
        raise HTTPException(status_code=403, detail="Server not configured for admin alias")
    try:
        body = await req.json()
    except Exception:
        body = None
    headers = {"X-Internal-Secret": PAYMENTS_INTERNAL_SECRET}
    try:
        r = httpx.post(_payments_url("/admin/alias/rename"), json=body, headers=headers, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/payments/admin/alias/search")
def payments_admin_alias_search(handle: str = "", status: str = "", user_id: str = "", limit: int = 50):
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
        r = httpx.get(_payments_url("/admin/alias/search"), headers=headers, params=params, timeout=10)
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
            r = httpx.get(_payments_url("/admin/risk/metrics"), headers=headers, params=params, timeout=10)
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
        with httpx.stream("GET", _payments_url("/admin/txns/export_by_merchant"), headers=headers, params=params, timeout=None) as r:
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
            r = httpx.get(_payments_url("/admin/risk/events"), headers=headers, params=params, timeout=10)
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
            r = httpx.post(_payments_url("/admin/risk/deny/add"), json=body, headers=headers, timeout=10)
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
            r = httpx.post(_payments_url("/admin/risk/deny/remove"), json=body, headers=headers, timeout=10)
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
            r = httpx.get(_payments_url("/admin/risk/deny/list"), headers=headers, params=params, timeout=10)
            result = r.json()
        _audit_from_request(request, "risk_deny_list", kind=kind or None, limit=limit)
        return result
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/payments-debug", response_class=HTMLResponse)
def payments_debug_page():
    # Legacy Debug-UI – bitte Shamell bzw. API-Clients verwenden.
    return _legacy_console_removed_page("Shamell · Payments debug")
    # Simple in-page tool to create user, show wallet, topup (server) and transfer
    html = """
<!doctype html>
<html><head><meta name=viewport content="width=device-width, initial-scale=1" />
<title>Payments Debug</title>
<link rel="icon" href="/icons/payments.svg" />
<meta name="apple-mobile-web-app-capable" content="yes" />
<meta name="apple-mobile-web-app-status-bar-style" content="default" />
<link rel="manifest" href="/payments-debug/manifest.json" />
<link rel="apple-touch-icon" href="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAQAAACqK7W/AAAAKUlEQVR42u3BAQ0AAADCoPdPbQ43oAAAAAAAAAAAAAAAAAAAAAAAPQkqtwAAbkQwXgAAAABJRU5ErkJggg==" />
<script src="/ds.js"></script>
<style>
  body{font-family:sans-serif;margin:20px;max-width:720px;background:#ffffff;color:#000000;}
  input,button{font-size:16px;padding:8px;margin:4px 0}
  code{background:#f5f5f5;padding:2px 4px;border-radius:4px}
  .btn{padding:8px 12px;border-radius:4px;border:1px solid #cccccc;background:#f3f4f6;color:#000000}
  .btnPri{padding:8px 12px;border-radius:4px;background:#2563eb;color:#ffffff;border:0}
  .card{border-radius:4px;border:1px solid #dddddd;padding:12px;background:#ffffff}
  .topbar{position:sticky;top:0;z-index:10;background:#ffffff;padding:8px 10px;border-bottom:1px solid #dddddd;margin:0 0 8px 0}
  .row{display:flex;align-items:center;gap:8px}
</style>
</head><body>
<div class="topbar row"><div style="flex:1;font-weight:600">Payments Debug</div><button id=db_refresh>Refresh Wallet</button></div>
<h1 style="display:none">Payments Debug</h1>
<p>Base: <code>/payments/*</code> via BFF</p>
<div id=dbg_flash style="position:fixed;inset:0;background:#e5e7eb;opacity:0;pointer-events:none;transition:opacity .2s;"></div>
<div class="card" data-ds="card">
  <h3>Create User</h3>
  <input id=phone placeholder="Phone e.g. +9637000000xx" />
  <button onclick="createUser()">Create/Fetch</button>
  <div id=user></div>
</div>
<div class="card" data-ds="card">
  <h3>Wallet</h3>
  <input id=wallet placeholder="Wallet ID" />
  <button onclick="getWallet()">Refresh</button>
  <div id=wout></div>
</div>
<div id=dbg_hero class="card" data-ds="card" style="display:none;border:0">
  <div style="display:flex;align-items:center;gap:12px">
    <div style="padding:10px;border-radius:4px;border:1px solid #dddddd">Wallet</div>
    <div style="flex:1">
      <div style="opacity:.9;font-size:13px">Wallet</div>
      <div id=dh_wallet style="font-weight:600;overflow:hidden;text-overflow:ellipsis;white-space:nowrap"></div>
    </div>
    <div style="text-align:right">
      <div style="opacity:.9;font-size:13px">Saldo</div>
      <div id=dh_balance style="font-weight:700;font-size:18px">—</div>
      <div id=dh_kyc style="opacity:.9;font-size:12px"></div>
    </div>
    <button onclick="getWallet()" style="margin-left:8px;padding:6px 10px;border-radius:4px;border:1px solid #cccccc;background:#f3f4f6">Refresh</button>
  </div>
  
</div>
<div class="card" data-ds="card">
  <h3>Admin Topup (server)</h3>
  <input id=amt value=100000 />
  <button onclick="topup()">Topup</button>
  <div id=topout></div>
</div>
<div class="card" data-ds="card">
  <h3>Transfer</h3>
  <input id=to placeholder="To wallet id or @alias" />
  <input id=tamt value=25000 />
  <button onclick="transfer()">Send</button>
  <div id=xout></div>
</div>
  <div class="card" data-ds="card">
    <h3>Quick Pay</h3>
    <input id=qp_to2 placeholder="To wallet id or @alias" />
    <input id=qp_amt2 type=number placeholder="Amount (cents)" />
    <button onclick="quickPayDbg()">Pay</button>
    <small>Alias supported (@name). Uses Idempotency-Key.</small>
    <div id=qp_out2></div>
  </div>
  <div class="card" data-ds="card">
    <h3>Scan to Pay</h3>
    <button onclick="scanStartPayDbg()">Scan PAY QR</button>
    <div id=scannerDbg style="width:260px;height:220px"></div>
  </div>
  <div class="card" data-ds="card">
    <h3>Alias QR</h3>
    <input id=aq_handle_dbg placeholder="@yourname" />
    <input id=aq_amount_dbg type=number placeholder="Amount (cents, optional)" />
    <button onclick="aliasQRDbg()">Generate Alias QR</button>
    <div id=aqr_dbg></div>
    <pre id=apayload_dbg></pre>
    <small>Format: ALIAS|name=@...|amount=...</small>
  </div>
<div class="card" data-ds="card">
  <h3>My QR</h3>
  <input id=qr_amt2 type=number placeholder="Amount (cents, optional)" />
  <button onclick="genMyQR()">Generate My QR</button>
  <div id=qr2></div>
  <pre id=qrp2></pre>
  <p><small>Scannable payload: PAY|wallet=&lt;wallet&gt;|amount=&lt;cents&gt;</small></p>
</div>
<div class="card" data-ds="card">
  <h3>Topup QR</h3>
  <p><small>Generate a QR for app Topup scan. Format: TOPUP|wallet=&lt;wallet&gt;|amount=&lt;cents&gt;.</small></p>
  <div class=row>
    <input id=t_wallet_dbg placeholder="Wallet (defaults to Wallet field above)" />
    <input id=t_amt_dbg type=number placeholder="Amount (cents)" />
    <button onclick="topupQRDbg()">Generate</button>
  </div>
  <div id=tqr_dbg></div>
  <pre id=tpayload_dbg></pre>
</div>
<div class="card" data-ds="card">
  <h3>Offline Queue</h3>
  <button onclick="syncQueued()">Sync Now</button>
  <pre id=qout></pre>
</div>
<hr/>
<div class="card" data-ds="card">
  <h2>Sonic‑Pay (Token)</h2>
  <h3>Payer: Issue Token</h3>
  <input id=sp_amt value=10000 />
  <button onclick="sonicIssue()">Issue</button>
  <pre id=sp_issue></pre>
  <h3>Payee: Redeem Token</h3>
  <input id=sp_token placeholder="paste token here" />
  <button onclick="sonicRedeem()">Redeem</button>
  <pre id=sp_redeem></pre>
  <p><small>Note: Token is HMAC-signed and short-lived; ideally it is transmitted acoustically/Bluetooth. For testing, copy/paste it here.</small></p>
  <script>
  async function sonicIssue(){
    const wid=document.getElementById('wallet').value;
    const amt=parseInt(document.getElementById('sp_amt').value||'0',10);
    const r=await fetch('/payments/sonic/issue',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({from_wallet_id:wid,amount_cents:amt})});
    const j=await r.json();
    document.getElementById('sp_issue').textContent=JSON.stringify(j,null,2);
    try{ await navigator.clipboard.writeText(j.token);}catch(e){}
  }
  async function sonicRedeem(){
    const tok=document.getElementById('sp_token').value.trim();
    const wid=document.getElementById('wallet').value;
    try{
      const r=await fetch('/payments/sonic/redeem',{method:'POST',headers:{'content-type':'application/json','Idempotency-Key':'srx-'+Date.now()},body:JSON.stringify({token:tok,to_wallet_id:wid})});
      const j=await r.json();
      document.getElementById('sp_redeem').textContent=JSON.stringify(j,null,2);
    }catch(e){document.getElementById('sp_redeem').textContent='Error '+e}
  }
  </script>
<script src="https://unpkg.com/html5-qrcode@2.3.10/html5-qrcode.min.js"></script>
<script>
  // Unify DS with /app glass tokens
  const DS = { btn: 'btn', btnPri: 'btnPri', card: 'card', input: 'input' };
  function applyDS(){
    try{ document.getElementById('db_refresh').className = DS.btnPri; }catch(_){ }
    document.querySelectorAll('[data-ds="card"]').forEach(el=> el.className = DS.card);
    document.querySelectorAll('input').forEach(el=> el.className = DS.input);
    document.querySelectorAll('button').forEach(el=>{ if(!el.className){ el.className=DS.btn; } });
  }
  // --- Ensure wallet helpers ---
  async function me_ensureWallet(){ try{
    const r = await fetch('/me/wallet'); const j = await r.json();
    if(j && j.wallet_id){
      try{ document.getElementById('me_wallet_chip').textContent = j.wallet_id; }catch(_){ }
      try{ const el=document.getElementById('me_wallet'); if(el){ el.value=j.wallet_id; } }catch(_){ }
      try{ const el2=document.getElementById('wh_wallet'); if(el2){ el2.textContent=j.wallet_id; document.getElementById('wallet_hero').classList.remove('hidden'); } }catch(_){ }
    }
  }catch(_){ }
  }
  function me_copyWallet(){ try{ const t=document.getElementById('me_wallet_chip').textContent||''; if(t && navigator.clipboard){ navigator.clipboard.writeText(t); } }catch(_){ }
  }
  document.addEventListener('DOMContentLoaded', ()=>{ try{ me_ensureWallet(); }catch(_){ } });
  document.addEventListener('DOMContentLoaded', applyDS);
  function heroGradient(kyc){ if(kyc==='pro') return 'linear-gradient(90deg,#7c3aed,#fbbf24)'; if(kyc==='plus') return 'linear-gradient(90deg,#3b82f6,#22c55e)'; return 'linear-gradient(90deg,#4f46e5,#60a5fa)'; }
  async function scanStartPayDbg(){
    try{
      const el = document.getElementById('scannerDbg');
      const html5QrCode = new Html5Qrcode(el.id);
      await html5QrCode.start({ facingMode: "environment" }, { fps: 10, qrbox: 200 }, (decodedText)=>{
        try{
          if(decodedText && (decodedText.startsWith('PAY|') || decodedText.startsWith('ALIAS|'))){
            const parts = decodedText.split('|');
            const map={}; for(const p of parts.slice(1)){ const kv=p.split('='); if(kv.length==2) map[kv[0]]=decodeURIComponent(kv[1]); }
            if(map['wallet']){ document.getElementById('qp_to2').value = map['wallet']; }
            if(map['name']){ document.getElementById('qp_to2').value = map['name']; }
            if(map['amount']){ document.getElementById('qp_amt2').value = map['amount']; }
            try{ if(navigator.vibrate) navigator.vibrate(20);}catch(e){}
            (function(){ const f=document.getElementById('dbg_flash'); if(f){ f.style.opacity='1'; setTimeout(()=>{ f.style.opacity='0'; }, 380);} })();
            html5QrCode.stop();
          }
        }catch(_){ }
      });
    }catch(e){ alert('scan error: '+e); }
  }
  </script>
</div>
<hr/>
<div>
  <h2>Favorites & Requests</h2>
  <div class="card">
    <h3>Favorites</h3>
    <div class=row>
      <input id=fv_to placeholder="favorite wallet id" />
      <input id=fv_alias placeholder="alias (optional)" />
      <button class="btnPri" onclick="fvAdd()">Add</button>
      <button class="btn" onclick="fvLoad()">Load</button>
    </div>
    <div id=fv_list_dbg></div>
  </div>
  <div class="card">
    <h3>Requests</h3>
    <div class=row>
      <input id=rq_to placeholder="Payer wallet id or @alias" />
      <input id=rq_amt type=number placeholder="Amount (cents)" />
      <button class="btnPri" onclick="rqCreate()">Request</button>
      <button class="btn" onclick="rqIncoming()">Incoming</button>
      <button class="btn" onclick="rqOutgoing()">Outgoing</button>
    </div>
    <div id=rq_out class="card" style="white-space:pre-wrap"></div>
  </div>
  <div class="card">
    <h3>Payments Roles (Admin)</h3>
    <div class=row>
      <input id=role_phone placeholder="+963..." />
      <select id=role_sel>
        <option value="merchant">merchant</option>
        <option value="qr_seller">qr_seller</option>
        <option value="cashout_operator">cashout_operator</option>
      </select>
      <button class="btnPri" onclick="roleAdd()">Add</button>
      <button class="btn" onclick="roleRemove()">Remove</button>
      <button class="btn" onclick="roleList()">List</button>
    </div>
    <div id=role_out class="card" style="white-space:pre-wrap"></div>
  </div>
</div>
<div>
  <h2>Alias‑Admin</h2>
  <h3>Blockieren</h3>
  <input id=ab_handle placeholder="@name" />
  <button onclick="ablock()">Block</button>
  <pre id=ab_out></pre>
  <h3>Umbenennen</h3>
  <input id=ar_from placeholder="@alt" /> → <input id=ar_to placeholder="@neu" />
  <button onclick="arename()">Rename</button>
  <pre id=ar_out></pre>
  <h3>Suchen</h3>
  <input id=as_handle placeholder="contains" /> Status: <input id=as_status placeholder="active/pending/blocked" />
  <button onclick="asearch()">Search</button>
  <pre id=as_out></pre>
  <script>
  async function ablock(){ const h=document.getElementById('ab_handle').value; const r=await fetch('/payments/admin/alias/block',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({handle:h})}); document.getElementById('ab_out').textContent=await r.text(); }
  async function arename(){ const f=document.getElementById('ar_from').value; const t=document.getElementById('ar_to').value; const r=await fetch('/payments/admin/alias/rename',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({from_handle:f,to_handle:t})}); document.getElementById('ar_out').textContent=await r.text(); }
  async function asearch(){ const h=document.getElementById('as_handle').value; const s=document.getElementById('as_status').value; const u=new URLSearchParams(); if(h)u.set('handle',h); if(s)u.set('status',s); const r=await fetch('/payments/admin/alias/search?'+u.toString()); document.getElementById('as_out').textContent=await r.text(); }
  </script>
</div>
<script>
if ('serviceWorker' in navigator) { try { navigator.serviceWorker.register('/payments-debug/sw.js'); } catch(e) {} }
function _queue(){ try{return JSON.parse(localStorage.getItem('offline_txns')||'[]')}catch(e){return []} }
function _hue2(s){ let h=0; for(let i=0;i<s.length;i++){ h=(h*31 + s.charCodeAt(i))&0xffffffff; } return Math.abs(h)%360; }
function avatar2(label){ const h=_hue2((label||'').replace('@','')); const c1=`hsl(${h} 90% 55%)`; const c2=`hsl(${(h+24)%360} 85% 65%)`; const init=((label||'').replace('@','')[0]||'?').toUpperCase(); return `<span style="display:inline-flex;align-items:center;justify-content:center;width:28px;height:28px;border-radius:9999px;background:linear-gradient(135deg, ${c1}, ${c2});color:#fff;font-weight:700;box-shadow:0 2px 6px rgba(0,0,0,.18)">${init}</span>`; }
function _saveQueue(q){ localStorage.setItem('offline_txns', JSON.stringify(q)); renderQueue(); }
function _genIKey(){ return 'sr-'+Date.now().toString(36)+'-'+Math.random().toString(36).slice(2,8) }
function _codeFromIKey(k){ const s=k.replace(/[^a-z0-9]/gi,'').slice(-6).toUpperCase(); return 'SR-'+s.slice(0,3)+'-'+s.slice(3) }
// Minimal QR (GIF data URL) generator
!function(o){function r(o){this.mode=n.MODE_8BIT_BYTE,this.data=o,this.parsedData=[];for(var r=0,l=this.data.length;r<l;r++){var t=[],h=this.data.charCodeAt(r);h>65536?(t[0]=240|(1835008&h)>>>18,t[1]=128|(258048&h)>>>12,t[2]=128|(4032&h)>>>6,t[3]=128|63&h):h>2048?(t[0]=224|(61440&h)>>>12,t[1]=128|(4032&h)>>>6,t[2]=128|63&h):h>128?(t[0]=192|(1984&h)>>>6,t[1]=128|63&h):t[0]=h,this.parsedData.push(t)}this.parsedData=Array.prototype.concat.apply([],this.parsedData),this.parsedData.length!=this.data.length&&(this.parsedData.unshift(191),this.parsedData.unshift(187),this.parsedData.unshift(239))}function l(o,r){this.typeNumber=o,this.errorCorrectLevel=r,this.modules=null,this.moduleCount=0,this.dataCache=null,this.dataList=[]}var n={PAD0:236,PAD1:17,MODE_8BIT_BYTE:4};r.prototype={getLength:function(){return this.parsedData.length},write:function(o){for(var r=0,l=this.parsedData.length;r<l;r++)o.put(this.parsedData[r],8)}},l.prototype={addData:function(o){this.dataList.push(new r(o)),this.dataCache=null},isDark:function(o,r){if(o<0||this.moduleCount<=o||r<0||this.moduleCount<=r)throw new Error(o+","+r);return this.modules[o][r]},getModuleCount:function(){return this.moduleCount},make:function(){this.makeImpl(!1,this.getBestMaskPattern())},makeImpl:function(o,r){this.moduleCount=21,this.modules=new Array(this.moduleCount);for(var l=0;l<this.moduleCount;l++){this.modules[l]=new Array(this.moduleCount);for(var n=0;n<this.moduleCount;n++)this.modules[l][n]=null}this.setupPositionProbePattern(0,0),this.setupPositionProbePattern(this.moduleCount-7,0),this.setupPositionProbePattern(0,this.moduleCount-7),this.mapData(this.createData(this.typeNumber,this.errorCorrectLevel,r),r)},setupPositionProbePattern:function(o,r){for(var l=-1;l<=7;l++)if(!(o+l<=-1||this.moduleCount<=o+l))for(var n=-1;n<=7;n++)r+n<=-1||this.moduleCount<=r+n||(this.modules[o+l][r+n]=l>=0&&l<=6&&(0==n||6==n)||n>=0&&n<=6&&(0==l||6==l)||l>=2&&l<=4&&n>=2&&n<=4)},getBestMaskPattern:function(){return 0},createData:function(o,r){for(var l=[],n=0;n<this.dataList.length;n++){var t=this.dataList[n];l.push(4),l.push(t.getLength()),l=l.concat(t.parsedData)}for(l.push(236),l.push(17),l.push(236),l.push(17);l.length<19;)l.push(0);return l.slice(0,19)},mapData:function(o,r){for(var l=0;l<this.moduleCount;l++)for(var n=0;n<this.moduleCount;n++)if(null===this.modules[l][n]){var t=!((l+n)%3);this.modules[l][n]=t}},createImgTag:function(o,r){o=o||2,r=r||0;var l=this.getModuleCount()*o+2*r,n=l,t='<img src="'+this.createDataURL(o,r)+'" width="'+l+'" height="'+n+'"/>';return t},createDataURL:function(o,r){o=o||2,r=r||0;var l=this.getModuleCount()*o+2*r,n=l,t=o,h=r,e=h,i=Math.round(255);for(var a="GIF89a",u=String.fromCharCode,d=a+u(0)+u(0)+u(0)+u(0)+"\x00\x00\xF7\x00\x00",s=0;s<16;s++){var c=s?0:i;d+=u(c)+u(c)+u(c)}d+="\x2C\x00\x00\x00\x00"+u(0)+u(0)+"\x00\x00\x00\x00\x02";for(var f=1;f<l;f++){var g="";for(var p=0;p<n;p++){var m=this.isDark(Math.floor((p-r)/o),Math.floor((f-h)/o))?0:1;g+=m?"\x01":"\x00"}d+=u(g.length)+g}return 'data:image/gif;base64,'+btoa(d)}};
function _makeQR2(text){ const qr = new l(1,0); qr.addData(text); qr.make(); const el=document.getElementById('qr2'); el.innerHTML=qr.createImgTag(4,2); }
function genMyQR(){ const w=document.getElementById('wallet').value.trim(); if(!w){ alert('Wallet required'); return; } const a=parseInt(document.getElementById('qr_amt2').value||'0',10); const p='PAY|wallet='+encodeURIComponent(w)+(a>0?('|amount='+a):''); document.getElementById('qrp2').textContent=p; _makeQR2(p); }
  async function createUser(){
  const phone = document.getElementById('phone').value;
  const r = await fetch('/payments/users', {method:'POST', headers:{'content-type':'application/json'}, body: JSON.stringify({phone})});
  const j = await r.json();
  document.getElementById('user').textContent = JSON.stringify(j);
  if(j.wallet_id){ localStorage.setItem('wallet_id', j.wallet_id); document.getElementById('wallet').value = j.wallet_id; }
}
async function getWallet(){
  const wid = document.getElementById('wallet').value;
  const r = await fetch('/payments/wallets/'+wid);
  const j = await r.json();
  document.getElementById('wout').textContent = JSON.stringify(j);
  try{
    const k=(j.kyc_level||'').toLowerCase();
    const hero=document.getElementById('dbg_hero');
    if(wid){ hero.style.display='block'; document.getElementById('dh_wallet').textContent=wid; document.getElementById('dh_balance').textContent=(j.balance_cents||0)+' '+(j.currency||''); document.getElementById('dh_kyc').textContent='KYC: '+(k||'basic'); hero.style.background=heroGradient(k||'basic'); }
  }catch(_){ }
}
async function topup(){
  const wid = document.getElementById('wallet').value;
  const amt = parseInt(document.getElementById('amt').value||'0',10);
  const r = await fetch('/payments/wallets/'+wid+'/topup', {method:'POST', headers:{'content-type':'application/json','Idempotency-Key':'dbg-'+Date.now()}, body: JSON.stringify({amount_cents: amt})});
  const j = await r.json();
  document.getElementById('topout').textContent = JSON.stringify(j);
}
async function transfer(){
  const from = document.getElementById('wallet').value;
  const to = document.getElementById('to').value;
  const amt = parseInt(document.getElementById('tamt').value||'0',10);
  const ikey=_genIKey();
  const isAlias = (to||'').trim().startsWith('@');
  const payload = isAlias ? {from_wallet_id: from, to_alias: to.trim(), amount_cents: amt} : {from_wallet_id: from, to_wallet_id: to, amount_cents: amt};
  try{
    const r = await fetch('/payments/transfer', {method:'POST', headers:{'content-type':'application/json','Idempotency-Key':ikey}, body: JSON.stringify(payload)});
    if(!r.ok){ throw new Error('status '+r.status) }
    const j = await r.json();
    document.getElementById('xout').textContent = JSON.stringify(j);
  }catch(e){
    // offline fallback: queue
    const rec={ikey, code:_codeFromIKey(ikey), from_wallet_id:from, to_wallet_id:to, amount_cents:amt, created_at: new Date().toISOString()};
    const q=_queue(); q.push(rec); _saveQueue(q);
    document.getElementById('xout').textContent = 'Offline receipt code: '+rec.code+' (queued)';
    try{ navigator.share && navigator.share({text:'Payment '+rec.code+' '+amt+'c to '+to}); }catch(_){ }
  }
  async function resolveMaybe(v){ if(v&&v.startsWith('@')){ const r=await fetch('/payments/alias/resolve/'+encodeURIComponent(v)); const j=await r.json(); return j.wallet_id||null; } return v; }
  async function quickPayDbg(){ const from=gi('wallet'); let to=gi('qp_to2'); const amt=parseInt(document.getElementById('qp_amt2').value||'0',10); if(!from||!to||!(amt>0)){ alert('missing'); return; } const ik='dbg-'+Date.now().toString(36)+'-'+Math.random().toString(36).slice(2,6); const body=(to.startsWith('@')? {from_wallet_id:from,to_alias:to,amount_cents:amt}: {from_wallet_id:from,to_wallet_id:to,amount_cents:amt}); const r=await fetch('/payments/transfer',{method:'POST',headers:{'content-type':'application/json','Idempotency-Key':ik},body:JSON.stringify(body)}); document.getElementById('qp_out2').textContent=await r.text(); }
  function aliasQRDbg(){ const h=document.getElementById('aq_handle_dbg').value.trim(); const a=parseInt(document.getElementById('aq_amount_dbg').value||'0',10); if(!h||!h.startsWith('@')){ alert('alias must start with @'); return; } const p='ALIAS|name='+encodeURIComponent(h)+(a>0?('|amount='+a):''); document.getElementById('apayload_dbg').textContent=p; const el=document.getElementById('aqr_dbg'); const tmp=el.id; el.id='qr'; try{ makeQR(p); } finally { el.id=tmp; } }
async function fvAdd(){ const o=gi('wallet'); const to=gi('fv_to'); const alias=gi('fv_alias')||null; if(!o||!to){ alert('missing'); return; } const r=await fetch('/payments/favorites',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({owner_wallet_id:o,favorite_wallet_id:to,alias:alias})}); try{ await r.text(); }catch(_){ } await fvLoad(); }
async function fvLoad(){ const o=gi('wallet'); if(!o){ alert('wallet'); return; } const r=await fetch('/payments/favorites?owner_wallet_id='+encodeURIComponent(o)); const arr=await r.json(); const box=document.getElementById('fv_list_dbg'); box.innerHTML=''; for(const f of arr){ const label=(f.alias||''); const id=f.favorite_wallet_id; const row=document.createElement('div'); row.className='row'; row.innerHTML=avatar2(label||id)+`<div style="flex:1">${label||''}<div style="color:#6b7280;font-size:12px">${id}</div></div>`; const pay=document.createElement('button'); pay.className='btnPri'; pay.textContent='Pay'; pay.onclick=()=>{ document.getElementById('qp_to2').value = label||id; }; row.appendChild(pay); box.appendChild(row);} }
  async function rqCreate(){ const from=gi('wallet'); let to=gi('rq_to'); const amt=parseInt(document.getElementById('rq_amt').value||'0',10); to=await resolveMaybe(to); if(!from||!to||!(amt>0)){ alert('missing'); return; } const r=await fetch('/payments/requests',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({from_wallet_id:from,to_wallet_id:to,amount_cents:amt})}); document.getElementById('rq_out').textContent=await r.text(); }
  function avatar2(label){ const h=[...label].reduce((a,c)=>((a*31+c.charCodeAt(0))>>>0),0)%360; const c1=`hsl(${h} 90% 55%)`; const c2=`hsl(${(h+24)%360} 85% 65%)`; const init=(label.replace('@','')[0]||'?').toUpperCase(); return `<span style="display:inline-flex;align-items:center;justify-content:center;width:28px;height:28px;border-radius:9999px;background:linear-gradient(135deg, ${c1}, ${c2});color:#fff;font-weight:700;box-shadow:0 2px 6px rgba(0,0,0,.18)">${init}</span>`; }
  function rqRender(arr, incoming){ const box=document.getElementById('rq_out'); box.innerHTML=''; for(const e of arr){ const from=e.from_wallet_id||''; const to=e.to_wallet_id||''; const who=incoming? from : to; const row=document.createElement('div'); row.style.display='flex'; row.style.alignItems='center'; row.style.gap='10px'; row.style.borderBottom='1px solid #e5e7eb'; row.style.padding='6px 0'; row.innerHTML=avatar2(who)+`<div style=\"flex:1\"><div style=\"font-weight:600\">${e.amount_cents||0} </div><div style=\"color:#6b7280;font-size:12px\">${incoming?'from ':'to '}${who}</div></div>`; if(incoming){ const a=document.createElement('button'); a.textContent='Pay'; a.className='btnPri'; a.onclick=async()=>{ await fetch('/payments/requests/'+e.id+'/accept',{method:'POST'}); rqIncoming(); }; const c=document.createElement('button'); c.textContent='Decline'; c.className='btn'; c.onclick=async()=>{ await fetch('/payments/requests/'+e.id+'/cancel',{method:'POST'}); rqIncoming(); }; row.appendChild(a); row.appendChild(c); } else { const c=document.createElement('button'); c.textContent='Cancel'; c.className='btn'; c.onclick=async()=>{ await fetch('/payments/requests/'+e.id+'/cancel',{method:'POST'}); rqOutgoing(); }; row.appendChild(c); } box.appendChild(row);} }
  async function rqIncoming(){ const w=gi('wallet'); const r=await fetch('/payments/requests?wallet_id='+encodeURIComponent(w)+'&kind=incoming'); const arr=await r.json(); rqRender(arr,true); }
  async function rqOutgoing(){ const w=gi('wallet'); const r=await fetch('/payments/requests?wallet_id='+encodeURIComponent(w)+'&kind=outgoing'); const arr=await r.json(); rqRender(arr,false); }
  async function roleAdd(){ try{ const ph=gi('role_phone').value.trim(); const ro=gi('role_sel').value; const r=await fetch('/admin/roles',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({phone:ph,role:ro})}); gi('role_out').textContent=await r.text(); }catch(e){ gi('role_out').textContent='Error '+e; } }
  async function roleRemove(){ try{ const ph=gi('role_phone').value.trim(); const ro=gi('role_sel').value; const r=await fetch('/admin/roles',{method:'DELETE',headers:{'content-type':'application/json'},body:JSON.stringify({phone:ph,role:ro})}); gi('role_out').textContent=await r.text(); }catch(e){ gi('role_out').textContent='Error '+e; } }
  async function roleList(){ try{ const ro=gi('role_sel').value; const r=await fetch('/admin/roles?role='+encodeURIComponent(ro)+'&limit=200'); gi('role_out').textContent=await r.text(); }catch(e){ gi('role_out').textContent='Error '+e; } }
}
async function refreshBal(){ const wid=_wid(); if(!wid){return;} const r=await fetch('/payments/wallets/'+wid); const j=await r.json(); document.getElementById('bal').textContent = JSON.stringify(j,null,2); try{ const hero=document.getElementById('mp_hero'); hero.style.display='block'; document.getElementById('mh_wallet').textContent=wid; document.getElementById('mh_balance').textContent=(j.balance_cents||0)+' '+(j.currency||''); }catch(_){ } }
async function syncQueued(){
  const q=_queue(); if(q.length===0){ document.getElementById('qout').textContent='No pending txns'; return; }
  const rem=[]; const results=[];
  for(const rec of q){
    try{
      const r=await fetch('/payments/transfer', {method:'POST', headers:{'content-type':'application/json','Idempotency-Key':rec.ikey}, body: JSON.stringify({from_wallet_id: rec.from_wallet_id, to_wallet_id: rec.to_wallet_id, amount_cents: rec.amount_cents})});
      if(r.ok){ results.push({code:rec.code, ok:true}); } else { results.push({code:rec.code, ok:false, status:r.status}); rem.push(rec); }
    }catch(err){ rem.push(rec); }
  }
  _saveQueue(rem);
  document.getElementById('qout').textContent = JSON.stringify({synced: results}, null, 2);
}
function renderQueue(){ const q=_queue(); document.getElementById('qout').textContent = JSON.stringify(q,null,2); }
window.addEventListener('online', ()=>{ try{syncQueued()}catch(e){} });
renderQueue();
// init
document.getElementById('wallet').value = localStorage.getItem('wallet_id')||'';
</script>
</body></html>
"""
    return HTMLResponse(content=html)


@app.get("/payments-social", response_class=HTMLResponse)
def payments_social_page(request: Request):
    if not _auth_phone(request):
        return RedirectResponse(url="/login", status_code=303)
    return _legacy_console_removed_page("Shamell · Payments")
    html = """
<!doctype html>
<html><head><meta name=viewport content="width=device-width, initial-scale=1" />
<title>Payments – Favorites & Requests</title>
<style>body{font-family:sans-serif;margin:20px;max-width:900px} input,button{font-size:14px;padding:6px;margin:4px 0} table{border-collapse:collapse;width:100%} th,td{border:1px solid #ddd;padding:6px} pre{background:#f4f4f4;padding:8px;white-space:pre-wrap} small{color:#666}</style>
</head><body>
<h1>Favorites & Requests</h1>

<section>
  <h2>My Wallet</h2>
  <input id=me placeholder="my wallet id" />
  <button onclick="saveMe()">Save</button>
  <small id=mes></small>
</section>

<section>
  <h2>Favorites</h2>
  <div>
    <input id=fav_to placeholder="favorite wallet id" />
    <input id=fav_alias placeholder="alias (optional)" />
    <button onclick="addFav()">Add Favorite</button>
  </div>
  <table id=favs><thead><tr><th>Alias</th><th>Wallet</th><th>Actions</th></tr></thead><tbody></tbody></table>
</section>

<section>
  <h2>Quick Pay</h2>
  <div>
    <input id=qp_to placeholder="To wallet id or @alias" />
    <input id=qp_amt type=number placeholder="Amount (cents)" />
    <button onclick="quickPay()">Pay</button>
    <button onclick="scanStartPay()">Scan PAY QR</button>
  </div>
  <small>Uses /payments/transfer with Idempotency-Key and alias support.</small>
  <div>
    <h3>Recent</h3>
    <div id=qp_recent></div>
  </div>
  <div id=scanner2 style="width:260px;height:220px"></div>
</section>

<section>
  <h2>Request Money</h2>
  <div>
    <label>From (requester) = Me</label>
    <input id=req_to placeholder="Payer wallet id" />
    <input id=req_amt type=number placeholder="Amount (cents)" />
    <input id=req_msg placeholder="Message (optional)" />
    <button onclick="createReq()">Request</button>
  </div>
  <div>
    <h3>Incoming</h3>
    <table id=incoming><thead><tr><th>ID</th><th>From</th><th>Amount</th><th>Status</th><th>Actions</th></tr></thead><tbody></tbody></table>
  </div>
  <div>
    <h3>Outgoing</h3>
    <table id=outgoing><thead><tr><th>ID</th><th>To</th><th>Amount</th><th>Status</th><th>Actions</th></tr></thead><tbody></tbody></table>
  </div>
</section>

<section>
  <h2>Alias</h2>
  <div>
    <input id=al_handle placeholder="@yourname" />
    <button onclick="alRequest()">Request Link</button>
    <input id=al_code placeholder="123456" />
    <button onclick="alVerify()">Verify</button>
    <button onclick="alResolve()">Resolve</button>
    <pre id=al_out></pre>
  </div>
</section>

<section>
  <h2>Split Bill</h2>
  <p><small>Creates requests from Me (payee) to each participant (payer) with equal shares.</small></p>
  <div>
    <input id=sb_total type=number placeholder="Total amount (cents)" />
  </div>
  <div>
    <textarea id=sb_participants placeholder="Participant wallet IDs (comma or newline separated)" style="width:100%;height:80px"></textarea>
  </div>
  <button onclick="splitBill()">Create Requests</button>
  <pre id=sb_out></pre>
</section>

  <section>
    <h2>My QR</h2>
    <div>
      <input id=qr_amt type=number placeholder="Amount (cents, optional)" />
      <button onclick="genQR()">Generate QR</button>
      <div id=qr></div>
      <pre id=qrp></pre>
      <small>Scannable payload: PAY|wallet=&lt;me&gt;|amount=&lt;cents&gt;</small>
    </div>
  </section>

  <section>
    <h2>Alias QR</h2>
    <div>
      <input id=aq_handle placeholder="@yourname" />
      <input id=aq_amount type=number placeholder="Amount (cents, optional)" />
      <button onclick="aliasQRSocial()">Generate Alias QR</button>
      <div id=aqr></div>
      <pre id=apayload></pre>
      <small>Format: ALIAS|name=@...|amount=...</small>
    </div>
  </section>

<script src="https://unpkg.com/html5-qrcode@2.3.10/html5-qrcode.min.js"></script>
<script>
function saveMe(){ const v=gi('me'); localStorage.setItem('me_wallet', v); qs('#mes').textContent='saved'; loadFavs(); loadReqs(); }
function me(){ let v=gi('me'); if(!v){ v=localStorage.getItem('me_wallet')||''; si('me',v); } return v; }
function gi(id){ return (document.getElementById(id).value||'').trim(); }
function si(id,v){ document.getElementById(id).value=v; }
function qs(s){ return document.querySelector(s); }
function td(v){ const x=document.createElement('td'); x.textContent=v; return x; }

async function addFav(){ const o=me(); const to=gi('fav_to'); const alias=gi('fav_alias')||null; if(!o||!to){ alert('me and favorite required'); return; }
  const r=await fetch('/payments/favorites',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({owner_wallet_id:o,favorite_wallet_id:to,alias:alias})});
  if(!r.ok){ alert('error adding favorite'); return; } loadFavs(); }

async function delFav(id){ await fetch('/payments/favorites/'+id,{method:'DELETE'}); loadFavs(); }

async function loadFavs(){ const o=me(); if(!o){ return; } const r=await fetch('/payments/favorites?owner_wallet_id='+encodeURIComponent(o)); const arr=await r.json(); const tb=document.querySelector('#favs tbody'); tb.innerHTML=''; for(const f of arr){ const tr=document.createElement('tr'); tr.appendChild(td(f.alias||'')); tr.appendChild(td(f.favorite_wallet_id)); const act=document.createElement('td'); act.innerHTML='<button onclick="payFav(\''+(f.alias?f.alias:(''+f.favorite_wallet_id))+'\')">Pay</button> <button onclick="delFav(\''+f.id+'\')">Delete</button>'; tr.appendChild(act); tb.appendChild(tr);} }

function _recent(){ try{ return JSON.parse(localStorage.getItem('recent_payees')||'[]'); }catch(e){ return []; } }
function _saveRecent(list){ localStorage.setItem('recent_payees', JSON.stringify(list)); renderRecent(); }
function addRecent(target){ if(!target) return; const list=_recent().filter(x=>x!==target); list.unshift(target); while(list.length>5) list.pop(); _saveRecent(list); }
function renderRecent(){ const list=_recent(); const el=document.getElementById('qp_recent'); if(!el) return; if(list.length===0){ el.textContent='(none)'; return; } el.innerHTML=''; for(const t of list){ const b=document.createElement('button'); b.textContent=t; b.onclick=()=>{ document.getElementById('qp_to').value=t; }; el.appendChild(b); el.appendChild(document.createTextNode(' ')); } }

async function payFav(target){ const from=me(); if(!from){ alert('save my wallet first'); return; } let amt=parseInt(prompt('Amount (cents):','1000')||'0',10); if(!(amt>0)){ return; } const ik='pv-'+Date.now().toString(36)+'-'+Math.random().toString(36).slice(2,6); let body; if(target.startsWith('@')){ body={from_wallet_id:from,to_alias:target,amount_cents:amt}; } else { body={from_wallet_id:from,to_wallet_id:target,amount_cents:amt}; } const r=await fetch('/payments/transfer',{method:'POST',headers:{'content-type':'application/json','Idempotency-Key':ik},body:JSON.stringify(body)}); if(!r.ok){ alert('pay failed'); } else { addRecent(target); alert('paid'); }
}

async function quickPay(){ const from=me(); const to=gi('qp_to'); const amt=parseInt(gi('qp_amt')||'0',10); if(!from||!to||(amt<=0)){ alert('fields missing'); return; } const ik='qp-'+Date.now().toString(36)+'-'+Math.random().toString(36).slice(2,6); const body=(to.startsWith('@')? {from_wallet_id:from,to_alias:to,amount_cents:amt}: {from_wallet_id:from,to_wallet_id:to,amount_cents:amt}); const r=await fetch('/payments/transfer',{method:'POST',headers:{'content-type':'application/json','Idempotency-Key':ik},body:JSON.stringify(body)}); if(!r.ok){ alert('pay failed'); } else { addRecent(to); alert('paid'); }
}

async function resolveAliasMaybe(v){ if(v && v.startsWith('@')){ const h=v; const r=await fetch('/payments/alias/resolve/'+encodeURIComponent(h)); const j=await r.json(); return j.wallet_id||null; } return v; }
async function createReq(){ const from=me(); let to=gi('req_to'); const amt=parseInt(gi('req_amt')||'0',10); const message=gi('req_msg')||null; if(!from||!to||amt<=0){ alert('fields missing'); return; } to = await resolveAliasMaybe(to); if(!to){ alert('could not resolve recipient'); return; } const body={from_wallet_id:from,to_wallet_id:to,amount_cents:amt,message:message}; const r=await fetch('/payments/requests',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)}); if(!r.ok){ alert('error'); return; } loadReqs(); }
async function loadReqs(){ const w=me(); if(!w){ return; }
  const inc=await (await fetch('/payments/requests?wallet_id='+encodeURIComponent(w)+'&kind=incoming')).json();
  const out=await (await fetch('/payments/requests?wallet_id='+encodeURIComponent(w)+'&kind=outgoing')).json();
  const tin=document.querySelector('#incoming tbody'); tin.innerHTML='';
  for(const r of inc){ const tr=document.createElement('tr'); tr.appendChild(td(r.id)); tr.appendChild(td(r.from_wallet_id)); tr.appendChild(td(r.amount_cents)); tr.appendChild(td(r.status)); const act=document.createElement('td'); act.innerHTML='<button onclick="acc(\''+r.id+'\')">Pay</button> <button onclick="can(\''+r.id+'\')">Decline</button>'; tr.appendChild(act); tin.appendChild(tr); }
  const tout=document.querySelector('#outgoing tbody'); tout.innerHTML='';
  for(const r of out){ const tr=document.createElement('tr'); tr.appendChild(td(r.id)); tr.appendChild(td(r.to_wallet_id)); tr.appendChild(td(r.amount_cents)); tr.appendChild(td(r.status)); const act=document.createElement('td'); act.innerHTML='<button onclick="can(\''+r.id+'\')">Cancel</button>'; tr.appendChild(act); tout.appendChild(tr); }
}
async function acc(id){ const r=await fetch('/payments/requests/'+id+'/accept',{method:'POST'}); if(!r.ok){ alert('accept failed'); } loadReqs(); }
async function can(id){ const r=await fetch('/payments/requests/'+id+'/cancel',{method:'POST'}); if(!r.ok){ alert('cancel failed'); } loadReqs(); }

async function splitBill(){
  const from=me(); const total=parseInt(gi('sb_total')||'0',10); const list=(document.getElementById('sb_participants').value||'').split(/[\n,]+/).map(x=>x.trim()).filter(x=>x);
  if(!from||!(total>0)||list.length===0){ alert('fill all fields'); return; }
  const n=list.length; const base=Math.floor(total/n); let rem=total - base*n; const created=[];
  for(let i=0;i<n;i++){
    let to=list[i]; const amt=base + (rem>0?1:0); if(rem>0) rem--; const toWallet = await resolveAliasMaybe(to); if(!toWallet){ created.push({to, error:'resolve failed'}); continue; }
    const body={from_wallet_id:from,to_wallet_id:toWallet,amount_cents:amt,message:'split-bill'};
    const r=await fetch('/payments/requests',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)});
    const t=await r.text(); created.push({to, status:r.status, body:t});
  }
  document.getElementById('sb_out').textContent=JSON.stringify(created,null,2);
  loadReqs();
}

// Minimal QR generator (reuse from Merchant)
!function(o){function r(o){this.mode=n.MODE_8BIT_BYTE,this.data=o,this.parsedData=[];for(var r=0,l=this.data.length;r<l;r++){var t=[],h=this.data.charCodeAt(r);h>65536?(t[0]=240|(1835008&h)>>>18,t[1]=128|(258048&h)>>>12,t[2]=128|(4032&h)>>>6,t[3]=128|63&h):h>2048?(t[0]=224|(61440&h)>>>12,t[1]=128|(4032&h)>>>6,t[2]=128|63&h):h>128?(t[0]=192|(1984&h)>>>6,t[1]=128|63&h):t[0]=h,this.parsedData.push(t)}this.parsedData=Array.prototype.concat.apply([],this.parsedData),this.parsedData.length!=this.data.length&&(this.parsedData.unshift(191),this.parsedData.unshift(187),this.parsedData.unshift(239))}function l(o,r){this.typeNumber=o,this.errorCorrectLevel=r,this.modules=null,this.moduleCount=0,this.dataCache=null,this.dataList=[]}var n={PAD0:236,PAD1:17,MODE_8BIT_BYTE:4};r.prototype={getLength:function(){return this.parsedData.length},write:function(o){for(var r=0,l=this.parsedData.length;r<l;r++)o.put(this.parsedData[r],8)}},l.prototype={addData:function(o){this.dataList.push(new r(o)),this.dataCache=null},isDark:function(o,r){if(o<0||this.moduleCount<=o||r<0||this.moduleCount<=r)throw new Error(o+","+r);return this.modules[o][r]},getModuleCount:function(){return this.moduleCount},make:function(){this.makeImpl(!1,this.getBestMaskPattern())},makeImpl:function(o,r){this.moduleCount=21,this.modules=new Array(this.moduleCount);for(var l=0;l<this.moduleCount;l++){this.modules[l]=new Array(this.moduleCount);for(var n=0;n<this.moduleCount;n++)this.modules[l][n]=null}this.setupPositionProbePattern(0,0),this.setupPositionProbePattern(this.moduleCount-7,0),this.setupPositionProbePattern(0,this.moduleCount-7),this.mapData(this.createData(this.typeNumber,this.errorCorrectLevel,r),r)},setupPositionProbePattern:function(o,r){for(var l=-1;l<=7;l++)if(!(o+l<=-1||this.moduleCount<=o+l))for(var n=-1;n<=7;n++)r+n<=-1||this.moduleCount<=r+n||(this.modules[o+l][r+n]=l>=0&&l<=6&&(0==n||6==n)||n>=0&&n<=6&&(0==l||6==l)||l>=2&&l<=4&&n>=2&&n<=4)},getBestMaskPattern:function(){return 0},createData:function(o,r){for(var l=[],n=0;n<this.dataList.length;n++){var t=this.dataList[n];l.push(4),l.push(t.getLength()),l=l.concat(t.parsedData)}for(l.push(236),l.push(17),l.push(236),l.push(17);l.length<19;)l.push(0);return l.slice(0,19)},mapData:function(o,r){for(var l=0;l<this.moduleCount;l++)for(var n=0;n<this.moduleCount;n++)if(null===this.modules[l][n]){var t=!((l+n)%3);this.modules[l][n]=t}},createImgTag:function(o,r){o=o||2,r=r||0;var l=this.getModuleCount()*o+2*r,n=l,t='<img src="'+this.createDataURL(o,r)+'" width="'+l+'" height="'+n+'"/>';return t},createDataURL:function(o,r){o=o||2,r=r||0;var l=this.getModuleCount()*o+2*r,n=l,t=o,h=r,e=h,i=Math.round(255);for(var a=\"GIF89a\",u=String.fromCharCode,d=a+u(0)+u(0)+u(0)+u(0)+\"\\x00\\x00\\xF7\\x00\\x00\",s=0;s<16;s++){var c=s?0:i;d+=u(c)+u(c)+u(c)}d+=\"\\x2C\\x00\\x00\\x00\\x00\"+u(0)+u(0)+\"\\x00\\x00\\x00\\x00\\x02\";for(var f=1;f<l;f++){var g=\"\";for(var p=0;p<n;p++){var m=this.isDark(Math.floor((p-r)/o),Math.floor((f-h)/o))?0:1;g+=m?\"\\x01\":\"\\x00\"}d+=u(g.length)+g}return 'data:image/gif;base64,'+btoa(d)}};
function makeQR(text){ const qr = new l(1,0); qr.addData(text); qr.make(); const el=document.getElementById('qr'); el.innerHTML=qr.createImgTag(4,2); }
function genQR(){ const w=me(); const a=parseInt(gi('qr_amt')||'0',10); if(!w){ alert('save my wallet first'); return; } const p='PAY|wallet='+encodeURIComponent(w)+(a>0?('|amount='+a):''); document.getElementById('qrp').textContent=p; makeQR(p); }
function aliasQRSocial(){ const h=gi('aq_handle'); const a=parseInt(gi('aq_amount')||'0',10); if(!h||!h.startsWith('@')){ alert('alias must start with @'); return; } const p='ALIAS|name='+encodeURIComponent(h)+(a>0?('|amount='+a):''); document.getElementById('apayload').textContent=p; const qrEl=document.getElementById('aqr'); const tmp=qrEl.id; qrEl.id='qr'; try{ makeQR(p); } finally { qrEl.id=tmp; } }
function topupQRDbg(){ const w=(document.getElementById('t_wallet_dbg').value||document.getElementById('wallet').value||'').trim(); const a=parseInt(document.getElementById('t_amt_dbg').value||'0',10); if(!w){ alert('wallet required'); return; } const p='TOPUP|wallet='+encodeURIComponent(w)+(a>0?('|amount='+a):''); document.getElementById('tpayload_dbg').textContent=p; const el=document.getElementById('tqr_dbg'); const tmp=el.id; el.id='qr'; try{ makeQR(p); } finally { el.id=tmp; } }

// init
si('me', localStorage.getItem('me_wallet')||''); loadFavs(); loadReqs(); renderRecent();

async function scanStartPay(){
  try{
    const el = document.getElementById('scanner2');
    const html5QrCode = new Html5Qrcode(el.id);
    await html5QrCode.start({ facingMode: "environment" }, { fps: 10, qrbox: 200 }, (decodedText)=>{
      try{
        if(decodedText && (decodedText.startsWith('PAY|') || decodedText.startsWith('ALIAS|'))){
          const parts = decodedText.split('|');
          const map={}; for(const p of parts.slice(1)){ const kv=p.split('='); if(kv.length==2) map[kv[0]]=decodeURIComponent(kv[1]); }
          if(map['wallet']){ document.getElementById('qp_to').value = map['wallet']; }
          if(map['name']){ document.getElementById('qp_to').value = map['name']; }
          if(map['amount']){ document.getElementById('qp_amt').value = map['amount']; }
          html5QrCode.stop();
        }
      }catch(_){ }
    });
  }catch(e){ alert('scan error: '+e); }
}

async function alRequest(){ const h=gi('al_handle'); const w=me(); if(!h||!w){ alert('handle and me required'); return; } const r=await fetch('/payments/alias/request',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({handle:h,wallet_id:w})}); document.getElementById('al_out').textContent=await r.text(); }
async function alVerify(){ const h=gi('al_handle'); const c=gi('al_code'); if(!h||!c){ alert('handle+code'); return; } const r=await fetch('/payments/alias/verify',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({handle:h,code:c})}); document.getElementById('al_out').textContent=await r.text(); }
async function alResolve(){ const h=gi('al_handle'); if(!h){ return; } const r=await fetch('/payments/alias/resolve/'+encodeURIComponent(h)); document.getElementById('al_out').textContent=await r.text(); }
</script>
</body></html>
"""
    return HTMLResponse(content=html)


@app.get("/payments-debug/manifest.json")
def payments_debug_manifest():
    manifest = {
        "name": "SuperApp Payments Debug",
        "short_name": "Payments",
        "start_url": "/payments-debug",
        "display": "standalone",
        "background_color": "#0f172a",
        "theme_color": "#0f172a",
        "icons": [
            {"src": "/icons/payments-192.png", "sizes": "192x192", "type": "image/png"},
            {"src": "/icons/payments-512.png", "sizes": "512x512", "type": "image/png"},
            {"src": "/icons/payments.svg", "sizes": "any", "type": "image/svg+xml"}
        ]
    }
    return JSONResponse(content=manifest)


@app.get("/payments-debug/sw.js")
def payments_debug_sw():
    js = """
    self.addEventListener('install', (event) => {
      self.skipWaiting();
    });
    self.addEventListener('activate', (event) => {
      event.waitUntil(self.clients.claim());
    });
    self.addEventListener('fetch', (event) => {
      return; // network-first
    });
    """
    return Response(content=js, media_type="application/javascript")


# --- PWA manifests for operator/stub modules ---
def _manifest_for(module: str, title: str, start_url: str):
    return {
        "name": f"SuperApp {title}",
        "short_name": title,
        "start_url": start_url,
        "display": "standalone",
        "background_color": "#0f172a",
        "theme_color": "#0f172a",
        "icons": [
            {"src": f"/icons/{module}-192.png", "sizes": "192x192", "type": "image/png"},
            {"src": f"/icons/{module}-512.png", "sizes": "512x512", "type": "image/png"},
            {"src": f"/icons/{module}.svg", "sizes": "any", "type": "image/svg+xml"},
        ],
    }


@app.get("/agriculture/manifest.json")
def agriculture_manifest():
    return JSONResponse(content=_manifest_for("agriculture", "Agriculture", "/agriculture"))


@app.get("/commerce/manifest.json")
def commerce_manifest():
    return JSONResponse(content=_manifest_for("commerce", "Commerce", "/commerce"))


@app.get("/doctors/manifest.json")
def doctors_manifest():
    return JSONResponse(content=_manifest_for("doctors", "Doctors", "/doctors"))


@app.get("/flights/manifest.json")
def flights_manifest():
    return JSONResponse(content=_manifest_for("flights", "Flights", "/flights"))


@app.get("/jobs/manifest.json")
def jobs_manifest():
    return JSONResponse(content=_manifest_for("jobs", "Jobs", "/jobs"))


@app.get("/livestock/manifest.json")
def livestock_manifest():
    return JSONResponse(content=_manifest_for("livestock", "Livestock", "/livestock"))


@app.get("/bus/manifest.json")
def bus_manifest():
    # Start to admin page by default
    return JSONResponse(content=_manifest_for("bus", "Bus", "/bus/admin"))


@app.get("/merchant", response_class=HTMLResponse)
def merchant_page(request: Request):
    if not _auth_phone(request):
        return RedirectResponse(url="/login", status_code=303)
    return _legacy_console_removed_page("Shamell · Merchant POS")
    html = """
<!doctype html>
<html><head><meta name=viewport content="width=device-width, initial-scale=1" />
<title>Merchant POS</title>
<link rel="icon" href="/icons/merchant.svg" />
<meta name="apple-mobile-web-app-capable" content="yes" />
<meta name="apple-mobile-web-app-status-bar-style" content="default" />
<link rel="manifest" href="/merchant/manifest.json" />
<script src="/ds.js"></script>
<style>
  body{font-family:sans-serif;margin:20px;max-width:720px;background:#ffffff;color:#000000;}
  input,button{font-size:16px;padding:8px;margin:4px 0}
  input{background:#ffffff;border:1px solid #cccccc;border-radius:4px;color:#000000}
  button{border:1px solid #cccccc;background:#f3f4f6;border-radius:4px;color:#000000;box-shadow:none}
  #qr{margin-top:10px}
  pre{background:rgba(255,255,255,.08);padding:8px;white-space:pre-wrap;border-radius:12px;border:1px solid rgba(255,255,255,.2);backdrop-filter:blur(10px)}
</style>
</head><body>
<h1>Merchant POS</h1>
<p>Generate a QR for customers to scan and pay.</p>
<div>
  <label>Wallet ID</label>
  <input id=wallet placeholder="wallet id" />
  <button onclick="saveWid()">Save</button>
</div>
<div id=mp_hero style="display:none;margin:12px 0;padding:14px;border-radius:4px;border:1px solid #dddddd">
  <div style="display:flex;align-items:center;gap:12px">
    <div style="padding:10px;border-radius:4px;border:1px solid #dddddd">Wallet</div>
    <div style="flex:1">
      <div style="opacity:.9;font-size:13px">Merchant Wallet</div>
      <div id=mh_wallet style="font-weight:600;overflow:hidden;text-overflow:ellipsis;white-space:nowrap"></div>
    </div>
    <div style="text-align:right">
      <div style="opacity:.9;font-size:13px">Saldo</div>
      <div id=mh_balance style="font-weight:700;font-size:18px">—</div>
    </div>
    <button onclick="refreshBal()" style="margin-left:8px;padding:6px 10px;border-radius:4px;border:1px solid #cccccc;background:#f3f4f6">Refresh</button>
  </div>
</div>
<hr/>
<div id=alias_pay_section>
  <h2>Alias‑Pay (@name)</h2>
  <h3>Alias reservieren</h3>
  <input id=a_handle placeholder="@deinname" />
  <button onclick="aliasRequest()">Anfordern</button>
  <pre id=a_req></pre>
  <h3>Alias verifizieren</h3>
  <input id=a_code placeholder="123456" />
  <button onclick="aliasVerify()">Verifizieren</button>
  <pre id=a_ver></pre>
  <script>
  async function aliasRequest(){
    const h=document.getElementById('a_handle').value;
    const wid=document.getElementById('wallet').value;
    const r=await fetch('/payments/alias/request',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({handle:h,wallet_id:wid})});
    const j=await r.json();
    document.getElementById('a_req').textContent=JSON.stringify(j,null,2);
  }
  async function aliasVerify(){
    const h=document.getElementById('a_handle').value;
    const c=document.getElementById('a_code').value;
    const r=await fetch('/payments/alias/verify',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({handle:h,code:c})});
    const j=await r.json();
    document.getElementById('a_ver').textContent=JSON.stringify(j,null,2);
  }
  </script>
</div>
<div>
  <label>Amount (cents)</label>
  <input id=amount value=25000 />
  <button onclick="genQR()">Generate QR</button>
  <div id=qr></div>
  <pre id=payload></pre>
</div>
<div id=alias_qr_section>
  <h2>Alias QR</h2>
  <label>@Alias</label>
  <input id=aq_handle placeholder="@kunde" />
  <label>Amount (cents)</label>
  <input id=aq_amount value=25000 />
  <button onclick="aliasQR()">Generate Alias QR</button>
  <div id=aqr></div>
  <pre id=apayload></pre>
  <p style="color:#666">Format: <code>ALIAS|name=@...|amount=...</code></p>
  <p style="color:#666">Clients can scan this to prefill a transfer to the alias.</p>
  <hr/>
</div>
<div>
  <h2>Scan to Pay</h2>
  <div id=mp_flash style="position:fixed;inset:0;background:#e5e7eb;opacity:0;pointer-events:none;transition:opacity .2s;"></div>
  <button onclick="scanStartMerch()">Scan PAY/ALIAS QR</button>
  <div id=scannerMerch style="width:260px;height:220px"></div>
  <pre id=scanout></pre>
</div>
<div>
  <h3>Balance</h3>
  <button onclick="refreshBal()">Refresh Balance</button>
  <pre id=bal></pre>
</div>
<div>
  <h3>Recent Transactions</h3>
  <button onclick="loadTxns()">Load</button>
  <pre id=txns></pre>
</div>
<div>
  <h3>Offline Codes (Verify Later)</h3>
  <input id=code placeholder="SR-ABC-123" />
  <button onclick="verifyCode()">Verify</button>
  <pre id=ver></pre>
</div>
<script>
function saveWid(){ const v = document.getElementById('wallet').value; localStorage.setItem('merchant_wid', v); }
function _wid(){ let v = document.getElementById('wallet').value; if(!v){ v = localStorage.getItem('merchant_wid')||''; document.getElementById('wallet').value = v; } return v; }
function genQR(){
  const wid=_wid(); const amt=parseInt(document.getElementById('amount').value||'0',10);
  if(!wid){ alert('wallet required'); return; }
  const p = 'PAY|wallet='+wid + (amt>0?('|amount='+amt):'');
  document.getElementById('payload').textContent = p;
  makeQR(p);
}
function aliasQR(){
  const handle=(document.getElementById('aq_handle').value||'').trim();
  const amt=parseInt(document.getElementById('aq_amount').value||'0',10);
  if(!handle || !handle.startsWith('@')){ alert('alias must start with @'); return; }
  const p = 'ALIAS|name='+encodeURIComponent(handle) + (amt>0?('|amount='+amt):'');
  document.getElementById('apayload').textContent = p;
  // render into separate container
  const qrEl=document.getElementById('aqr');
  // reuse makeQR by temporarily swapping target id
  const old = document.getElementById('qr');
  const tmpId = qrEl.id;
  qrEl.id = 'qr';
  try { makeQR(p); } finally { qrEl.id = tmpId; }
}
async function refreshBal(){ const wid=_wid(); if(!wid){return;} const r=await fetch('/payments/wallets/'+wid); const j=await r.json(); document.getElementById('bal').textContent = JSON.stringify(j,null,2); try{ const hero=document.getElementById('mp_hero'); hero.style.display='block'; document.getElementById('mh_wallet').textContent=wid; document.getElementById('mh_balance').textContent=(j.balance_cents||0)+' '+(j.currency||''); }catch(_){ } }
async function loadTxns(){ const wid=_wid(); if(!wid){return;} const r=await fetch('/payments/txns?wallet_id='+encodeURIComponent(wid)+'&limit=20'); const j=await r.json(); document.getElementById('txns').textContent = JSON.stringify(j,null,2); }
// Minimal QR generator (qrcode.js MIT - reduced)
/* eslint-disable */
!function(o){function r(o){this.mode=n.MODE_8BIT_BYTE,this.data=o,this.parsedData=[];for(var r=0,l=this.data.length;r<l;r++){var t=[],h=this.data.charCodeAt(r);h>65536?(t[0]=240|(1835008&h)>>>18,t[1]=128|(258048&h)>>>12,t[2]=128|(4032&h)>>>6,t[3]=128|63&h):h>2048?(t[0]=224|(61440&h)>>>12,t[1]=128|(4032&h)>>>6,t[2]=128|63&h):h>128?(t[0]=192|(1984&h)>>>6,t[1]=128|63&h):t[0]=h,this.parsedData.push(t)}this.parsedData=Array.prototype.concat.apply([],this.parsedData),this.parsedData.length!=this.data.length&&(this.parsedData.unshift(191),this.parsedData.unshift(187),this.parsedData.unshift(239))}function l(o,r){this.typeNumber=o,this.errorCorrectLevel=r,this.modules=null,this.moduleCount=0,this.dataCache=null,this.dataList=[]}var n={PAD0:236,PAD1:17,MODE_8BIT_BYTE:4};r.prototype={getLength:function(){return this.parsedData.length},write:function(o){for(var r=0,l=this.parsedData.length;r<l;r++)o.put(this.parsedData[r],8)}},l.prototype={addData:function(o){this.dataList.push(new r(o)),this.dataCache=null},isDark:function(o,r){if(o<0||this.moduleCount<=o||r<0||this.moduleCount<=r)throw new Error(o+","+r);return this.modules[o][r]},getModuleCount:function(){return this.moduleCount},make:function(){this.makeImpl(!1,this.getBestMaskPattern())},makeImpl:function(o,r){this.moduleCount=21,this.modules=new Array(this.moduleCount);for(var l=0;l<this.moduleCount;l++){this.modules[l]=new Array(this.moduleCount);for(var n=0;n<this.moduleCount;n++)this.modules[l][n]=null}this.setupPositionProbePattern(0,0),this.setupPositionProbePattern(this.moduleCount-7,0),this.setupPositionProbePattern(0,this.moduleCount-7),this.mapData(this.createData(this.typeNumber,this.errorCorrectLevel,r),r)},setupPositionProbePattern:function(o,r){for(var l=-1;l<=7;l++)if(!(o+l<=-1||this.moduleCount<=o+l))for(var n=-1;n<=7;n++)r+n<=-1||this.moduleCount<=r+n||(this.modules[o+l][r+n]=l>=0&&l<=6&&(0==n||6==n)||n>=0&&n<=6&&(0==l||6==l)||l>=2&&l<=4&&n>=2&&n<=4)},getBestMaskPattern:function(){return 0},createData:function(o,r){for(var l=[],n=0;n<this.dataList.length;n++){var t=this.dataList[n];l.push(4),l.push(t.getLength()),l=l.concat(t.parsedData)}for(l.push(236),l.push(17),l.push(236),l.push(17);l.length<19;)l.push(0);return l.slice(0,19)},mapData:function(o,r){for(var l=0;l<this.moduleCount;l++)for(var n=0;n<this.moduleCount;n++)if(null===this.modules[l][n]){var t=!((l+n)%3);this.modules[l][n]=t}},createImgTag:function(o,r){o=o||2,r=r||0;var l=this.getModuleCount()*o+2*r,n=l,t='<img src="'+this.createDataURL(o,r)+'" width="'+l+'" height="'+n+'"/>';return t},createDataURL:function(o,r){o=o||2,r=r||0;var l=this.getModuleCount()*o+2*r,n=l,t=o,h=r,e=h,i=Math.round(255);for(var a="GIF89a",u=String.fromCharCode,d=a+u(0)+u(0)+u(0)+u(0)+"\x00\x00\xF7\x00\x00",s=0;s<16;s++){var c=s?0:i;d+=u(c)+u(c)+u(c)}d+="\x2C\x00\x00\x00\x00"+u(0)+u(0)+"\x00\x00\x00\x00\x02";for(var f=1;f<l;f++){var g="";for(var p=0;p<n;p++){var m=this.isDark(Math.floor((p-r)/o),Math.floor((f-h)/o))?0:1;g+=m?"\x01":"\x00"}d+=u(g.length)+g}return 'data:image/gif;base64,'+btoa(d)}};
function makeQR(text){ const qr = new l(1,0); qr.addData(text); qr.make(); const el=document.getElementById('qr'); el.innerHTML=qr.createImgTag(4,2); }
document.getElementById('wallet').value = localStorage.getItem('merchant_wid')||'';
async function verifyCode(){
  const c=document.getElementById('code').value.trim();
  const ikey=c.replace(/[^a-z0-9]/gi,'');
  try{ const r=await fetch('/payments/idempotency/'+ikey); const j=await r.json(); document.getElementById('ver').textContent = JSON.stringify(j,null,2); }catch(e){ document.getElementById('ver').textContent='Error: '+e; }
}
</script>
<script src="https://unpkg.com/html5-qrcode@2.3.10/html5-qrcode.min.js"></script>
<script>
async function scanStartMerch(){
  try{
    const el = document.getElementById('scannerMerch');
    const html5QrCode = new Html5Qrcode(el.id);
    await html5QrCode.start({ facingMode: "environment" }, { fps: 10, qrbox: 200 }, (decodedText)=>{
      try{
        if(decodedText && (decodedText.startsWith('PAY|') || decodedText.startsWith('ALIAS|'))){
          const parts = decodedText.split('|');
          const map={}; for(const p of parts.slice(1)){ const kv=p.split('='); if(kv.length==2) map[kv[0]]=decodeURIComponent(kv[1]); }
          let info='';
          if(map['wallet']){ info+='wallet='+map['wallet']+'\n'; }
          if(map['name']){ info+='alias='+map['name']+'\n'; document.getElementById('aq_handle').value = map['name']; }
          if(map['amount']){ info+='amount='+map['amount']+'\n'; document.getElementById('amount').value = map['amount']; document.getElementById('aq_amount').value = map['amount']; }
          document.getElementById('scanout').textContent=info || decodedText;
          try{ if(navigator.vibrate) navigator.vibrate(20);}catch(e){}
          (function(){ const f=document.getElementById('mp_flash'); if(f){ f.style.opacity='1'; setTimeout(()=>{ f.style.opacity='0'; }, 380);} })();
          html5QrCode.stop();
        }
      }catch(_){ }
    });
  }catch(e){ alert('scan error: '+e); }
}
// Optional Alias toggle (default hidden unless ?alias=1)
(function(){ try{ const p=new URLSearchParams(location.search); const on=p.get('alias')==='1'; if(!on){ const a=document.getElementById('alias_pay_section'); if(a) a.style.display='none'; const b=document.getElementById('alias_qr_section'); if(b) b.style.display='none'; } }catch(_){ } })();
</script>
</body></html>
"""
    return HTMLResponse(content=html)


@app.get("/merchant/manifest.json")
def merchant_manifest():
    manifest = {
        "name": "SuperApp Merchant",
        "short_name": "Merchant",
        "start_url": "/merchant",
        "display": "standalone",
        "background_color": "#ffffff",
        "theme_color": "#111111",
        "icons": [
            {"src": "/icons/merchant-192.png", "sizes": "192x192", "type": "image/png"},
            {"src": "/icons/merchant-512.png", "sizes": "512x512", "type": "image/png"},
            {"src": "/icons/merchant.svg", "sizes": "any", "type": "image/svg+xml"}
        ]
    }
    return JSONResponse(content=manifest)


@app.get("/admin/risk", response_class=HTMLResponse)
def admin_risk_page(request: Request):
    if not _auth_phone(request):
        return RedirectResponse(url="/login", status_code=303)
    return _legacy_console_removed_page("Shamell · Risk admin")
    html = """
<!doctype html>
<html><head><meta name=viewport content="width=device-width, initial-scale=1" />
<title>Risk Admin</title>
<link rel="icon" href="/icons/payments.svg" />
<script src="/ds.js"></script>
<style>
  body{font-family:sans-serif;margin:20px;max-width:960px;background:#ffffff;color:#000000;}
  input,button,select{font-size:14px;padding:6px;margin:4px 0}
  pre{background:#f5f5f5;padding:8px;white-space:pre-wrap;border-radius:4px;border:1px solid #dddddd}
  .card{border-radius:4px;border:1px solid #dddddd;padding:12px;background:#ffffff}
  .topbar{position:sticky;top:0;z-index:10;background:#ffffff;padding:8px 10px;border-bottom:1px solid #dddddd;margin:0 0 8px 0}
</style>
</head><body>
<div class="topbar"><div style="display:flex;align-items:center;gap:8px"><div style="flex:1;font-weight:600">Risk Admin</div><button onclick="loadMetrics()" class="px-3 py-2 rounded bg-blue-600/90 text-white">Refresh</button></div></div>

<section class="card">
  <h2>Metrics</h2>
  <label>Minutes</label> <input id=m_minutes type=number value=5 />
  <label>Top</label> <input id=m_top type=number value=10 />
  <button onclick="loadMetrics()">Load</button>
  <pre id=m_out></pre>
</section>

<section class="card" style="margin-top:12px">
  <h2>Events</h2>
  <label>Minutes</label> <input id=e_minutes type=number value=5 />
  <label>To Wallet</label> <input id=e_to />
  <label>Device</label> <input id=e_dev />
  <label>IP</label> <input id=e_ip />
  <label>Limit</label> <input id=e_limit type=number value=100 />
  <button onclick="loadEvents()">Load</button>
  <pre id=e_out></pre>
</section>

<section class="card" style="margin-top:12px">
  <h2>Denylist</h2>
  <label>Kind</label>
  <select id=d_kind><option value="device">device</option><option value="ip">ip</option></select>
  <label>Value</label> <input id=d_val />
  <button onclick="denyAdd()">Add</button>
  <button onclick="denyRemove()">Remove</button>
  <button onclick="denyList()">List</button>
  <pre id=d_out></pre>
</section>

<script>
async function loadMetrics(){
  const u=new URLSearchParams({minutes:document.getElementById('m_minutes').value, top:document.getElementById('m_top').value});
  const r=await fetch('/payments/admin/risk/metrics?'+u.toString());
  document.getElementById('m_out').textContent = await r.text();
}
async function loadEvents(){
  const u=new URLSearchParams();
  const mins=document.getElementById('e_minutes').value; if(mins)u.set('minutes', mins);
  const to=document.getElementById('e_to').value; if(to)u.set('to_wallet_id', to);
  const dev=document.getElementById('e_dev').value; if(dev)u.set('device_id', dev);
  const ip=document.getElementById('e_ip').value; if(ip)u.set('ip', ip);
  const lim=document.getElementById('e_limit').value; if(lim)u.set('limit', lim);
  const r=await fetch('/payments/admin/risk/events?'+u.toString());
  document.getElementById('e_out').textContent = await r.text();
}
async function denyAdd(){
  const k=document.getElementById('d_kind').value; const v=document.getElementById('d_val').value;
  const r=await fetch('/payments/admin/risk/deny/add',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({kind:k,value:v})});
  document.getElementById('d_out').textContent = await r.text();
}
async function denyRemove(){
  const k=document.getElementById('d_kind').value; const v=document.getElementById('d_val').value;
  const r=await fetch('/payments/admin/risk/deny/remove',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({kind:k,value:v})});
  document.getElementById('d_out').textContent = await r.text();
}
async function denyList(){
  const k=document.getElementById('d_kind').value; const r=await fetch('/payments/admin/risk/deny/list?kind='+encodeURIComponent(k));
  document.getElementById('d_out').textContent = await r.text();
}
</script>
</body></html>
"""
    return HTMLResponse(content=html)


@app.get("/admin/exports", response_class=HTMLResponse)
def admin_exports_page(request: Request):
    if not _auth_phone(request):
        return RedirectResponse(url="/login", status_code=303)
    return _legacy_console_removed_page("Shamell · Admin exports")


@app.get("/carmarket", response_class=HTMLResponse)
def carmarket_page(request: Request):
    if not _auth_phone(request):
        return RedirectResponse(url="/login", status_code=303)
    return _legacy_console_removed_page("Shamell · Carmarket")
    html = """
<!doctype html>
<html><head><meta name=viewport content="width=device-width, initial-scale=1" />
<title>Carmarket</title>
<link rel="icon" href="/icons/carmarket.svg" />
<script src="/ds.js"></script>
<style>
  body{font-family:sans-serif;margin:20px;max-width:900px;background:#ffffff;color:#000000;}
  .card{border-radius:4px;border:1px solid #dddddd;padding:12px;background:#ffffff}
  .topbar{position:sticky;top:0;z-index:10;background:#ffffff;padding:8px 10px;border-bottom:1px solid #dddddd;margin:0 0 12px 0}
  table{border-collapse:collapse;width:100%}
  th,td{border:1px solid #dddddd;padding:6px}
</style>
</head><body>
<div class="topbar"><div style="display:flex;align-items:center;gap:8px"><div style="flex:1;font-weight:600">Carmarket</div><button onclick="loadList()" class="px-3 py-2 rounded bg-blue-600/90 text-white">Refresh</button></div></div>
<section class="card">
  <h2>Browse</h2>
  <div style="display:flex;gap:8px;flex-wrap:wrap">
    <input id=q placeholder="Search" class="px-3 py-2 rounded border border-gray-300" />
    <input id=city placeholder="City" class="px-3 py-2 rounded border border-gray-300" />
    <input id=make placeholder="Make" class="px-3 py-2 rounded border border-gray-300" />
    <button onclick="loadList()" class="px-3 py-2 rounded bg-blue-600 text-white">Search</button>
  </div>
  <table id=list><thead><tr><th>ID</th><th>Title</th><th>Price</th><th>City</th><th>Make</th><th>Actions</th></tr></thead><tbody></tbody></table>
</section>
<section class="card" style="margin-top:12px">
  <h2>Post Listing</h2>
  <div style="display:flex;gap:8px;flex-wrap:wrap">
    <input id=title placeholder="Title" class="px-3 py-2 rounded border border-gray-300" />
    <input id=price type=number placeholder="Price (cents)" class="px-3 py-2 rounded border border-gray-300" />
    <input id=pmake placeholder="Make" class="px-3 py-2 rounded border border-gray-300" />
    <input id=pmodel placeholder="Model" class="px-3 py-2 rounded border border-gray-300" />
    <input id=year type=number placeholder="Year" class="px-3 py-2 rounded border border-gray-300" />
    <input id=pcity placeholder="City" class="px-3 py-2 rounded border border-gray-300" />
    <input id=phone placeholder="Contact phone" class="px-3 py-2 rounded border border-gray-300" />
    <input id=desc placeholder="Description" class="px-3 py-2 rounded border border-gray-300" />
    <button onclick="postListing()" class="px-3 py-2 rounded bg-green-600 text-white">Create</button>
  </div>
  <pre id=post_out></pre>
</section>
<section class="card" style="margin-top:12px">
  <h2>Inquiry</h2>
  <div style="display:flex;gap:8px;flex-wrap:wrap">
    <input id=ilid type=number placeholder="Listing ID" class="px-3 py-2 rounded border border-gray-300" />
    <input id=iname placeholder="Your name" class="px-3 py-2 rounded border border-gray-300" />
    <input id=iphone placeholder="Phone" class="px-3 py-2 rounded border border-gray-300" />
    <input id=imsg placeholder="Message" class="px-3 py-2 rounded border border-gray-300" />
    <button onclick="postInquiry()" class="px-3 py-2 rounded bg-blue-600 text-white">Send</button>
  </div>
  <pre id=iout></pre>
</section>
<script>
async function loadList(){
  const u=new URLSearchParams(); const q=document.getElementById('q').value; if(q)u.set('q',q); const c=document.getElementById('city').value; if(c)u.set('city',c); const m=document.getElementById('make').value; if(m)u.set('make',m);
  const r=await fetch('/carmarket/listings?'+u.toString()); const arr=await r.json();
  const tb=document.querySelector('#list tbody'); tb.innerHTML='';
  for(const l of arr){
    const tr=document.createElement('tr');
    tr.innerHTML=`<td>${l.id}</td><td>${l.title}</td><td>${l.price_cents}</td><td>${l.city||''}</td><td>${l.make||''}</td><td><button onclick=del(${l.id})>Delete</button></td>`;
    tb.appendChild(tr);
  }
}
async function postListing(){
  const body={title:gi('title'), price_cents:pi('price'), make:gi('pmake')||null, model:gi('pmodel')||null, year:pi('year')||null, city:gi('pcity')||null, contact_phone:gi('phone')||null, description:gi('desc')||null};
  const r=await fetch('/carmarket/listings',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)});
  const j=await r.json(); document.getElementById('post_out').textContent=JSON.stringify(j,null,2); loadList();
}
async function del(id){ await fetch('/carmarket/listings/'+id,{method:'DELETE'}); loadList(); }
async function postInquiry(){
  const body={listing_id:pi('ilid'), name:gi('iname'), phone:gi('iphone')||null, message:gi('imsg')||null};
  const r=await fetch('/carmarket/inquiries',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)}); document.getElementById('iout').textContent=await r.text();
}
function gi(id){ return (document.getElementById(id).value||'').trim(); }
function pi(id){ const v=parseInt(document.getElementById(id).value||'0',10); return isNaN(v)?0:v; }
loadList();
</script>
</body></html>
"""
    return HTMLResponse(content=html)


@app.get("/carrental", response_class=HTMLResponse)
def carrental_page(request: Request):
    if not _auth_phone(request):
        return RedirectResponse(url="/login", status_code=303)
    return _legacy_console_removed_page("Shamell · Carrental")
    html = """
<!doctype html>
<html><head><meta name=viewport content="width=device-width, initial-scale=1" />
<title>Car Rental</title>
<link rel="icon" href="/icons/carrental.svg" />
<script src="/ds.js"></script>
<style>
  body{font-family:sans-serif;margin:20px;max-width:960px;background:#ffffff;color:#000000;}
  .card{border-radius:4px;border:1px solid #dddddd;padding:12px;background:#ffffff}
  .topbar{position:sticky;top:0;z-index:10;background:#ffffff;padding:8px 10px;border-bottom:1px solid #dddddd;margin:0 0 12px 0}
  table{border-collapse:collapse;width:100%}
  th,td{border:1px solid #dddddd;padding:6px}
</style>
</head><body>
<div class="topbar"><div style="display:flex;align-items:center;gap:8px"><div style="flex:1;font-weight:600">Car Rental</div><button onclick="loadCars()" class="px-3 py-2 rounded bg-blue-600/90 text-white">Refresh</button></div></div>
<section class="card">
  <h2>Cars</h2>
  <div style="display:flex;gap:8px;flex-wrap:wrap">
    <input id=q placeholder="Search" class="px-3 py-2 rounded border border-gray-300" />
    <input id=city placeholder="City" class="px-3 py-2 rounded border border-gray-300" />
    <button onclick="loadCars()" class="px-3 py-2 rounded bg-blue-600 text-white">Search</button>
  </div>
  <table id=cars><thead><tr><th>ID</th><th>Title</th><th>Make</th><th>Year</th><th>Day/Hour</th><th>Owner Wallet</th></tr></thead><tbody></tbody></table>
</section>
<section class="card" style="margin-top:12px">
  <h2>Quote & Book</h2>
  <div style="display:flex;gap:8px;flex-wrap:wrap">
    <label>Car ID</label> <input id=carid class="px-3 py-2 rounded border border-gray-300" />
    <label>From (ISO)</label> <input id=from class="px-3 py-2 rounded border border-gray-300" />
    <label>To (ISO)</label> <input id=to class="px-3 py-2 rounded border border-gray-300" />
    <button onclick="quote()" class="px-3 py-2 rounded bg-blue-600 text-white">Quote</button>
  </div>
  <pre id=qout></pre>
  <h3>Book</h3>
  <div style="display:flex;gap:8px;flex-wrap:wrap">
    <input id=name placeholder="Your name" class="px-3 py-2 rounded border border-gray-300" />
    <input id=phone placeholder="Phone" class="px-3 py-2 rounded border border-gray-300" />
    <input id=rw placeholder="Renter wallet (optional)" class="px-3 py-2 rounded border border-gray-300" />
    <label><input type=checkbox id=confirm /> Pay now (confirm)</label>
    <button onclick="book()" class="px-3 py-2 rounded bg-green-600 text-white">Book</button>
  </div>
  <pre id=bout></pre>
</section>
<section>
  <h2>Booking status</h2>
  <input id=bid placeholder="booking_id" />
  <button onclick="bstatus()">Status</button>
  <button onclick="bcancel()">Cancel</button>
  <button onclick="bconfirm()">Confirm (pay)</button>
  <pre id=bstat></pre>
</section>
<section>
  <h2>Admin</h2>
  <div>
    <button onclick="loadCars()">Refresh Cars</button>
    <button onclick="dlex('cars')">Export Cars CSV</button>
  </div>
  <div>
    <button onclick="loadBookings()">Refresh Bookings</button>
    <select id=bst><option value="">any</option><option>requested</option><option>confirmed</option><option>canceled</option><option>completed</option></select>
    <button onclick="dlex('bookings')">Export Bookings CSV</button>
    <pre id=blist></pre>
  </div>
</section>
<script>
async function loadCars(){ const u=new URLSearchParams(); const q=document.getElementById('q').value; if(q)u.set('q',q); const c=document.getElementById('city').value; if(c)u.set('city',c); const r=await fetch('/carrental/cars?'+u.toString()); const arr=await r.json(); const tb=document.querySelector('#cars tbody'); tb.innerHTML=''; for(const x of arr){ const tr=document.createElement('tr'); tr.innerHTML = `<td>${x.id}</td><td>${x.title}</td><td>${x.make||''} ${x.model||''}</td><td>${x.year||''}</td><td>${x.price_per_day_cents||''}/${x.price_per_hour_cents||''}</td><td>${x.owner_wallet_id||''}</td>`; tb.appendChild(tr);} }
async function quote(){ const body={car_id:parseInt(document.getElementById('carid').value||'0',10), from_iso:document.getElementById('from').value, to_iso:document.getElementById('to').value}; const r=await fetch('/carrental/quote',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)}); document.getElementById('qout').textContent=await r.text(); }
async function book(){ const body={car_id:parseInt(document.getElementById('carid').value||'0',10), renter_name:document.getElementById('name').value, renter_phone:document.getElementById('phone').value, renter_wallet_id:document.getElementById('rw').value||null, from_iso:document.getElementById('from').value, to_iso:document.getElementById('to').value, confirm:document.getElementById('confirm').checked}; const r=await fetch('/carrental/book',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)}); document.getElementById('bout').textContent=await r.text(); try{ const j=await r.clone().json(); document.getElementById('bid').value=j.id; }catch(_){ } }
async function bstatus(){ const id=document.getElementById('bid').value; const r=await fetch('/carrental/bookings/'+id); document.getElementById('bstat').textContent=await r.text(); }
async function bcancel(){ const id=document.getElementById('bid').value; const r=await fetch('/carrental/bookings/'+id+'/cancel',{method:'POST'}); document.getElementById('bstat').textContent=await r.text(); }
async function bconfirm(){ const id=document.getElementById('bid').value; const r=await fetch('/carrental/bookings/'+id+'/confirm',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({confirm:true})}); document.getElementById('bstat').textContent=await r.text(); }
async function loadBookings(){ const st=document.getElementById('bst').value; const u=new URLSearchParams(); if(st)u.set('status',st); const r=await fetch('/carrental/bookings?'+u.toString()); document.getElementById('blist').textContent=await r.text(); }
function dlex(kind){ if(kind==='cars'){ window.location.href='/carrental/admin/cars/export'; } else { const st=document.getElementById('bst').value; window.location.href='/carrental/admin/bookings/export'+(st?('?status='+encodeURIComponent(st)):''); } }
loadCars();
</script>
</body></html>
"""
    return HTMLResponse(content=html)


@app.get("/food", response_class=HTMLResponse)
def food_page(request: Request):
    if not _auth_phone(request):
        return RedirectResponse(url="/login", status_code=303)
    return _legacy_console_removed_page("Shamell · Food")
    html = """
<!doctype html>
<html><head><meta name=viewport content="width=device-width, initial-scale=1" />
<title>Food</title>
<link rel="icon" href="/icons/food.svg" />
<script src="/ds.js"></script>
<style>
  body{font-family:sans-serif;margin:20px;max-width:1000px;background:#ffffff;color:#000000;}
  .card{border-radius:4px;border:1px solid #dddddd;padding:12px;background:#ffffff}
  .topbar{position:sticky;top:0;z-index:10;background:#ffffff;padding:8px 10px;border-bottom:1px solid #dddddd;margin:0 0 12px 0}
  table{border-collapse:collapse;width:100%}
  th,td{border:1px solid #dddddd;padding:6px}
</style>
</head><body>
<div class="topbar"><div style="display:flex;align-items:center;gap:8px"><div style="flex:1;font-weight:600">Food Ordering</div><button onclick="loadRests()" class="px-3 py-2 rounded bg-blue-600/90 text-white">Refresh</button></div></div>
<section class="card">
  <h2>Restaurants</h2>
  <div style="display:flex;gap:8px;flex-wrap:wrap"><input id=frq placeholder="Search" class="px-3 py-2 rounded border border-gray-300" />
  <input id=frcity placeholder="City" class="px-3 py-2 rounded border border-gray-300" />
  <button onclick="loadRests()" class="px-3 py-2 rounded bg-blue-600 text-white">Search</button></div>
  <table id=rests><thead><tr><th>ID</th><th>Name</th><th>City</th><th>Owner Wallet</th><th>Menu</th></tr></thead><tbody></tbody></table>
</section>
<section class="card" style="margin-top:12px">
  <h2>Menu & Order</h2>
  <div style="display:flex;gap:8px;flex-wrap:wrap"><label>Restaurant</label> <input id=rid class="px-3 py-2 rounded border border-gray-300" />
  <button onclick="loadMenu()" class="px-3 py-2 rounded bg-blue-600 text-white">Load Menu</button></div>
  <table id=menu><thead><tr><th>ID</th><th>Name</th><th>Price</th><th>Qty</th></tr></thead><tbody></tbody></table>
  <div>
    <label>Customer</label> <input id=cname placeholder="Name" class="px-3 py-2 rounded border border-gray-300" /> <input id=cphone placeholder="Phone" class="px-3 py-2 rounded border border-gray-300" />
    <input id=wallet placeholder="Customer wallet (optional)" class="px-3 py-2 rounded border border-gray-300" />
    <label><input type=checkbox id=confirm /> Pay now (confirm)</label>
    <button onclick="placeOrder()" class="px-3 py-2 rounded bg-green-600 text-white">Place Order</button>
    <pre id=oout></pre>
  </div>
</section>
<section>
  <h2>Order status</h2>
  <input id=oid placeholder="order_id" />
  <button onclick="ostatus()">Status</button>
  <select id=st><option>accepted</option><option>preparing</option><option>ready</option><option>completed</option><option>canceled</option></select>
  <button onclick="oset()">Set</button>
  <pre id=os></pre>
</section>
<script>
async function loadRests(){ const u=new URLSearchParams(); const q=document.getElementById('frq').value; if(q)u.set('q',q); const c=document.getElementById('frcity').value; if(c)u.set('city',c); const r=await fetch('/food/restaurants?'+u.toString()); const arr=await r.json(); const tb=document.querySelector('#rests tbody'); tb.innerHTML=''; for(const x of arr){ const tr=document.createElement('tr'); tr.innerHTML = `<td>${x.id}</td><td>${x.name}</td><td>${x.city||''}</td><td>${x.owner_wallet_id||''}</td><td><button onclick=sel(${x.id})>Select</button></td>`; tb.appendChild(tr);} }
function sel(id){ document.getElementById('rid').value=id; loadMenu(); }
async function loadMenu(){ const rid=document.getElementById('rid').value; const r=await fetch('/food/restaurants/'+rid+'/menu'); const arr=await r.json(); const tb=document.querySelector('#menu tbody'); tb.innerHTML=''; for(const m of arr){ const tr=document.createElement('tr'); tr.innerHTML = `<td>${m.id}</td><td>${m.name}</td><td>${m.price_cents}</td><td><input id='q_${m.id}' value='1' /></td>`; tb.appendChild(tr);} }
async function placeOrder(){ const rid=parseInt(document.getElementById('rid').value||'0',10); const qs=Array.from(document.querySelectorAll('#menu tbody input')); const items=[]; for(const q of qs){ const id=parseInt(q.id.split('_')[1],10); const qty=parseInt(q.value||'0',10); if(qty>0) items.push({menu_item_id:id, qty:qty}); } if(items.length===0){ alert('choose items'); return; } const body={restaurant_id:rid, customer_name:document.getElementById('cname').value, customer_phone:document.getElementById('cphone').value, customer_wallet_id:document.getElementById('wallet').value||null, items, confirm:document.getElementById('confirm').checked}; const r=await fetch('/food/orders',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)}); const t=await r.text(); document.getElementById('oout').textContent=t; try{ const j=JSON.parse(t); document.getElementById('oid').value=j.id; }catch(_){} }
async function ostatus(){ const id=document.getElementById('oid').value; const r=await fetch('/food/orders/'+id); document.getElementById('os').textContent=await r.text(); }
async function oset(){ const id=document.getElementById('oid').value; const st=document.getElementById('st').value; const r=await fetch('/food/orders/'+id+'/status',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({status:st})}); document.getElementById('os').textContent=await r.text(); }
loadRests();
</script>
</body></html>
"""
    return HTMLResponse(content=html)


@app.get("/realestate", response_class=HTMLResponse)
def realestate_page(request: Request):
    if not _auth_phone(request):
        return RedirectResponse(url="/login", status_code=303)
    return _legacy_console_removed_page("Shamell · Realestate")
    html = """
<!doctype html>
<html><head><meta name=viewport content="width=device-width, initial-scale=1" />
<title>RealEstate</title>
<link rel="icon" href="/icons/realestate.svg" />
<style>
  body{font-family:sans-serif;margin:20px;max-width:1100px;background:#ffffff;color:#000000;}
  header{position:sticky;top:0;z-index:10;background:#ffffff;padding:8px 10px;border-bottom:1px solid #dddddd;margin:0 0 12px 0;display:flex;align-items:center;gap:8px}
  header h1{flex:1;font-size:20px;margin:0}
  button{font-size:14px;padding:6px 10px;border-radius:4px;border:1px solid #cccccc;background:#f3f4f6;color:#000000}
  input{font-size:14px;padding:6px 8px;border-radius:4px;border:1px solid #cccccc}
  table{border-collapse:collapse;width:100%}
  th,td{border:1px solid #dddddd;padding:6px}
  .card{border-radius:4px;border:1px solid #dddddd;padding:12px;background:#ffffff;margin-top:12px}
  pre{background:#f5f5f5;padding:8px;white-space:pre-wrap;border-radius:4px;border:1px solid #dddddd}
</style>
</head><body>
<header>
  <h1>Real Estate</h1>
  <button id=re_refresh onclick="loadP()">Refresh</button>
</header>
<section class="card">
  <h2>Browse</h2>
  <div style="display:flex;flex-wrap:wrap;gap:8px;align-items:center">
    <input id=q placeholder="Search" />
    <input id=city placeholder="City" />
    <input id=minp placeholder="Min price" />
    <input id=maxp placeholder="Max price" />
    <input id=minb placeholder="Min bedrooms" />
    <button onclick="loadP()">Search</button>
  </div>
  <div style="overflow:auto;margin-top:12px">
    <table id=props><thead><tr><th>ID</th><th>Title</th><th>City</th><th>Price</th><th>Beds</th><th>Owner</th></tr></thead><tbody></tbody></table>
  </div>
  <div id=pcnt style="margin-top:4px;font-size:12px;color:#666666"></div>
</section>
<section class="card">
  <h2>Create / Update</h2>
  <div style="display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:8px">
    <input id=pid placeholder="id (for update)" />
    <input id=ptitle placeholder="Title" />
    <input id=pprice placeholder="Price (cents)" />
    <input id=pcity placeholder="City" />
    <input id=paddr placeholder="Address" />
    <input id=pbeds placeholder="Bedrooms" />
    <input id=pbaths placeholder="Bathrooms" />
    <input id=parea placeholder="Area sqm" />
    <input id=powner placeholder="Owner wallet (optional)" />
  </div>
  <div style="margin-top:8px;display:flex;gap:8px">
    <button onclick="createP()">Create</button>
    <button onclick="updateP()">Update</button>
  </div>
  <pre id=pout style="margin-top:8px;font-size:12px"></pre>
</section>
<section class="card">
  <h2>Inquiry / Reserve</h2>
  <div style="display:flex;flex-wrap:wrap;gap:8px;align-items:center">
    <input id=selpid placeholder="property_id" />
    <input id=iname placeholder="Your name" />
    <input id=iphone placeholder="Phone" />
    <input id=imsg placeholder="Message" />
    <button onclick="inquiry()">Send Inquiry</button>
  </div>
  <div style="display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin-top:8px">
    <input id=buyer placeholder="Buyer wallet id" />
    <input id=dep placeholder="Deposit (cents)" />
    <button onclick="reserve()">Reserve (pay)</button>
  </div>
  <pre id=iout style="margin-top:8px;font-size:12px"></pre>
</section>
<script>
  async function loadP(){ const u=new URLSearchParams(); const q=document.getElementById('q').value; if(q)u.set('q',q); const c=document.getElementById('city').value; if(c)u.set('city',c); const minp=document.getElementById('minp').value; if(minp)u.set('min_price',minp); const maxp=document.getElementById('maxp').value; if(maxp)u.set('max_price',maxp); const minb=document.getElementById('minb').value; if(minb)u.set('min_bedrooms',minb); const r=await fetch('/realestate/properties?'+u.toString()); const arr=await r.json(); const tb=document.querySelector('#props tbody'); tb.innerHTML=''; for(const p of arr){ const tr=document.createElement('tr'); tr.innerHTML=`<td class='p-2'>${p.id}</td><td class='p-2'>${p.title}</td><td class='p-2'>${p.city||''}</td><td class='p-2'>${p.price_cents}</td><td class='p-2'>${p.bedrooms||''}</td><td class='p-2'>${p.owner_wallet_id||''}</td>`; tb.appendChild(tr); } document.getElementById('pcnt').textContent = arr.length+' results'; }
  async function createP(){ const body={title:gi('ptitle'), price_cents:parseInt(gi('pprice')||'0',10), city:gi('pcity')||null, address:gi('paddr')||null, bedrooms:parseInt(gi('pbeds')||'0',10)||null, bathrooms:parseInt(gi('pbaths')||'0',10)||null, area_sqm:parseFloat(gi('parea')||'0')||null, owner_wallet_id:gi('powner')||null}; const r=await fetch('/realestate/properties',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)}); document.getElementById('pout').textContent=await r.text(); }
  async function updateP(){ const id=parseInt(gi('pid')||'0',10); const body={title:gi('ptitle')||undefined, price_cents: (gi('pprice')?parseInt(gi('pprice'),10):undefined), city:gi('pcity')||undefined, address:gi('paddr')||undefined, bedrooms: (gi('pbeds')?parseInt(gi('pbeds'),10):undefined), bathrooms: (gi('pbaths')?parseInt(gi('pbaths'),10):undefined), area_sqm: (gi('parea')?parseFloat(gi('parea')):undefined), owner_wallet_id:gi('powner')||undefined}; const r=await fetch('/realestate/properties/'+id,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)}); document.getElementById('pout').textContent=await r.text(); }
  async function inquiry(){ const pid=parseInt(gi('selpid')||'0',10); const body={property_id:pid, name:gi('iname'), phone:gi('iphone')||null, message:gi('imsg')||null}; const r=await fetch('/realestate/inquiries',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)}); document.getElementById('iout').textContent=await r.text(); }
  async function reserve(){ const pid=parseInt(gi('selpid')||'0',10); const dep=parseInt(gi('dep')||'0',10); const body={property_id:pid, buyer_wallet_id:gi('buyer'), deposit_cents:dep}; const r=await fetch('/realestate/reserve',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)}); document.getElementById('iout').textContent=await r.text(); }
  function gi(id){ return (document.getElementById(id).value||'').trim(); }
  loadP();
</script>
</body></html>
"""
    return HTMLResponse(content=html)


@app.get("/stays", response_class=HTMLResponse)
def stays_page(request: Request):
    if not _auth_phone(request):
        return RedirectResponse(url="/login", status_code=303)
    return _legacy_console_removed_page("Shamell · Stays")
    html = """
<!doctype html>
<html><head><meta name=viewport content="width=device-width, initial-scale=1" />
<title>Stays</title>
<link rel="icon" href="/icons/stays.svg" />
<style>
  body{font-family:sans-serif;margin:20px;max-width:1000px;background:#ffffff;color:#000000;}
  header{position:sticky;top:0;z-index:10;background:#ffffff;padding:8px 10px;border-bottom:1px solid #dddddd;margin:0 0 12px 0;display:flex;align-items:center;gap:8px}
  header h1{flex:1;font-size:20px;margin:0}
  button{font-size:14px;padding:6px 10px;border-radius:4px;border:1px solid #cccccc;background:#f3f4f6;color:#000000}
  input{font-size:14px;padding:6px 8px;border-radius:4px;border:1px solid #cccccc}
  table{border-collapse:collapse;width:100%}
  th,td{border:1px solid #dddddd;padding:6px}
  .card{border-radius:4px;border:1px solid #dddddd;padding:12px;background:#ffffff;margin-top:12px}
  pre{background:#f5f5f5;padding:8px;white-space:pre-wrap;border-radius:4px;border:1px solid #dddddd}
</style>
</head><body>
<header>
  <h1>Stays</h1>
  <button id=st_refresh onclick="loadL()">Refresh</button>
</header>
<section class="card">
  <h2>Listings</h2>
  <div style="display:flex;flex-wrap:wrap;gap:8px;align-items:center">
    <input id=q placeholder="Search" />
    <input id=city placeholder="City" />
    <button onclick="loadL()">Search</button>
  </div>
  <div style="overflow:auto;margin-top:12px">
    <table id=ls><thead><tr><th>ID</th><th>Title</th><th>City</th><th>Price/Night</th><th>Owner</th></tr></thead><tbody></tbody></table>
  </div>
</section>
<section class="card">
  <h2>Create / Quote / Book</h2>
  <div style="display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:8px">
    <input id=title placeholder="Title" />
    <input id=lcity placeholder="City" />
    <input id=addr placeholder="Address" />
    <input id=ppn placeholder="Price per night (cents)" />
    <input id=ow placeholder="Owner wallet" />
  </div>
  <div style="margin-top:8px;display:flex;gap:8px">
    <button onclick="createL()">Create</button>
  </div>
  <div style="margin-top:8px">
    <div style="display:flex;flex-wrap:wrap;gap:8px;align-items:center">
      <input id=lid placeholder="listing_id" />
      <input id=from placeholder="YYYY-MM-DD" />
      <input id=to placeholder="YYYY-MM-DD" />
      <button onclick="quote()">Quote</button>
    </div>
    <pre id=qout style="margin-top:8px;font-size:12px"></pre>
  </div>
  <div style="margin-top:8px">
    <div style="display:flex;flex-wrap:wrap;gap:8px;align-items:center">
      <input id=gname placeholder="Guest name" />
      <input id=gphone placeholder="Phone" />
      <input id=gw placeholder="Guest wallet (optional)" />
      <label><input type=checkbox id=confirm /> Pay now (confirm)</label>
      <button onclick="book()">Book</button>
    </div>
    <pre id=bout style="margin-top:8px;font-size:12px"></pre>
  </div>
</section>
<section class="card">
  <h2>Booking status</h2>
  <div style="display:flex;flex-wrap:wrap;gap:8px;align-items:center">
    <input id=bid placeholder="booking_id" />
    <button onclick="bstatus()">Status</button>
  </div>
  <pre id=bst style="margin-top:8px;font-size:12px"></pre>
</section>
<script>
  async function loadL(){ const u=new URLSearchParams(); const q=document.getElementById('q').value; if(q)u.set('q',q); const c=document.getElementById('city').value; if(c)u.set('city',c); const r=await fetch('/stays/listings?'+u.toString()); const arr=await r.json(); const tb=document.querySelector('#ls tbody'); tb.innerHTML=''; for(const x of arr){ const tr=document.createElement('tr'); tr.innerHTML=`<td class='p-2'>${x.id}</td><td class='p-2'>${x.title}</td><td class='p-2'>${x.city||''}</td><td class='p-2'>${x.price_per_night_cents}</td><td class='p-2'>${x.owner_wallet_id||''}</td>`; tb.appendChild(tr);} }
  async function createL(){ const body={title:gi('title'), city:gi('lcity')||null, address:gi('addr')||null, price_per_night_cents:parseInt(gi('ppn')||'0',10), owner_wallet_id:gi('ow')||null}; const r=await fetch('/stays/listings',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)}); alert(await r.text()); loadL(); }
  async function quote(){ const body={listing_id:parseInt(gi('lid')||'0',10), from_iso:gi('from'), to_iso:gi('to')}; const r=await fetch('/stays/quote',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)}); document.getElementById('qout').textContent=await r.text(); }
  async function book(){ const body={listing_id:parseInt(gi('lid')||'0',10), guest_name:gi('gname'), guest_phone:gi('gphone'), guest_wallet_id:gi('gw')||null, from_iso:gi('from'), to_iso:gi('to'), confirm:document.getElementById('confirm').checked}; const r=await fetch('/stays/book',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)}); document.getElementById('bout').textContent=await r.text(); try{ const j=await r.clone().json(); document.getElementById('bid').value=j.id; }catch(_){ } }
  async function bstatus(){ const id=gi('bid'); const r=await fetch('/stays/bookings/'+id); document.getElementById('bst').textContent=await r.text(); }
  function gi(id){ return (document.getElementById(id).value||'').trim(); }
  loadL();
</script>
</body></html>
"""
    return HTMLResponse(content=html)


@app.get("/courier_console", response_class=HTMLResponse)
def courier_console(request: Request):
    if not _auth_phone(request):
        return RedirectResponse(url="/login", status_code=303)
    html = """
<!doctype html>
<html><head><meta name=viewport content="width=device-width, initial-scale=1" />
<title>Courier</title>
<style>
  body{font-family:sans-serif;margin:20px;max-width:1000px;background:#ffffff;color:#000000;}
  .card{border:1px solid #dddddd;border-radius:6px;padding:12px;margin-bottom:12px;}
  button{padding:6px 10px;border-radius:4px;border:1px solid #cccccc;background:#2563eb;color:#ffffff;}
  input,select{padding:6px 8px;border-radius:4px;border:1px solid #cccccc;}
  label{font-size:12px;color:#555;}
  pre{background:#f5f5f5;padding:8px;border-radius:4px;border:1px solid #e5e7eb;white-space:pre-wrap;}
</style>
</head><body>
<h1>Courier Console</h1>
<section class="card">
  <h3>Track shipment</h3>
  <div style="display:flex;gap:8px;flex-wrap:wrap">
    <input id=oid placeholder="Order ID" />
    <input id=token placeholder="Public token" />
    <button onclick="track()">Track</button>
  </div>
  <pre id=trackout></pre>
</section>
<section class="card">
  <h3>Contact / Reschedule</h3>
  <div style="display:flex;gap:8px;flex-wrap:wrap">
    <input id=cid placeholder="Order ID" />
    <input id=cmsg placeholder="Message for support" />
    <button onclick="contact()">Send</button>
  </div>
  <div style="display:flex;gap:8px;flex-wrap:wrap;margin-top:8px">
    <input id=ws type=datetime-local />
    <input id=we type=datetime-local />
    <label><input type=checkbox id=sts /> Short-term storage</label>
    <button onclick="resched()">Reschedule</button>
  </div>
  <pre id=contactout></pre>
</section>
<section class="card">
  <h3>Status / Scan / Proof</h3>
  <div style="display:flex;gap:8px;flex-wrap:wrap">
    <input id=sid placeholder="Order ID" />
    <select id=sstatus>
      <option value="assigned">assigned</option>
      <option value="pickup">pickup</option>
      <option value="delivering">delivering</option>
      <option value="delivered">delivered</option>
      <option value="failed">failed</option>
      <option value="retry">retry</option>
      <option value="return">return</option>
    </select>
    <input id=spin placeholder="PIN (for delivered)" />
    <input id=sproof placeholder="Proof URL" />
    <input id=sbarcode placeholder="Barcode / Scan" />
    <input id=ssign placeholder="Signature (text stub)" />
    <button onclick="setStatus()">Update</button>
  </div>
  <pre id=statusout></pre>
</section>
<section class="card">
  <h3>Partner KPIs</h3>
  <div style="display:flex;gap:8px;flex-wrap:wrap">
    <input id=pkpi_start type=datetime-local />
    <input id=pkpi_end type=datetime-local />
    <input id=pkpi_carrier placeholder="Carrier" />
    <select id=pkpi_service>
      <option value="">any</option>
      <option value="same_day">same_day</option>
      <option value="next_day">next_day</option>
    </select>
    <button onclick="loadKPI()">Load KPIs</button>
  </div>
  <pre id=kpiout></pre>
</section>
<section class="card">
  <h3>Stats & CO₂</h3>
  <div style="display:flex;gap:8px;flex-wrap:wrap">
    <input id=stat_carrier placeholder="Carrier" />
    <input id=stat_partner placeholder="Partner ID" />
    <select id=stat_service>
      <option value="">any</option>
      <option value="same_day">same_day</option>
      <option value="next_day">next_day</option>
    </select>
    <button onclick="loadStats()">Load stats</button>
  </div>
  <pre id=statout></pre>
</section>
<script>
async function track(){
  const oid=document.getElementById('oid').value;
  const token=document.getElementById('token').value;
  const url = oid?('/courier/shipments/'+encodeURIComponent(oid)):(token?('/courier/track/'+encodeURIComponent(token)):null);
  if(!url){ alert('Provide order id or token'); return; }
  const r=await fetch(url); document.getElementById('trackout').textContent=await r.text();
}
async function contact(){
  const oid=document.getElementById('cid').value;
  const msg=document.getElementById('cmsg').value;
  if(!oid||!msg){ alert('Order id and message required'); return; }
  const r=await fetch('/courier/orders/'+encodeURIComponent(oid)+'/contact',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({message:msg})});
  document.getElementById('contactout').textContent=await r.text();
}
async function resched(){
  const oid=document.getElementById('cid').value;
  const ws=document.getElementById('ws').value;
  const we=document.getElementById('we').value;
  if(!oid||!ws||!we){ alert('Order id and both windows required'); return; }
  const body={window_start:ws, window_end:we, short_term_storage:document.getElementById('sts').checked};
  const r=await fetch('/courier/orders/'+encodeURIComponent(oid)+'/reschedule',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)});
  document.getElementById('contactout').textContent=await r.text();
}
async function loadKPI(){
  const params=new URLSearchParams();
  const s=document.getElementById('pkpi_start').value; const e=document.getElementById('pkpi_end').value;
  const c=document.getElementById('pkpi_carrier').value; const svc=document.getElementById('pkpi_service').value;
  if(s)params.set('start_iso',s); if(e)params.set('end_iso',e); if(c)params.set('carrier',c); if(svc)params.set('service_type',svc);
  const r=await fetch('/courier/kpis/partners?'+params.toString()); document.getElementById('kpiout').textContent=await r.text();
}
async function loadStats(){
  const params=new URLSearchParams();
  const c=document.getElementById('stat_carrier').value;
  const p=document.getElementById('stat_partner').value;
  const svc=document.getElementById('stat_service').value;
  if(c)params.set('carrier',c); if(p)params.set('partner_id',p); if(svc)params.set('service_type',svc);
  const r=await fetch('/courier/stats?'+params.toString()); document.getElementById('statout').textContent=await r.text();
}
async function setStatus(){
  const oid=document.getElementById('sid').value;
  if(!oid){ alert('Order id required'); return; }
  const body={
    status:document.getElementById('sstatus').value,
    pin:document.getElementById('spin').value||undefined,
    proof_url:document.getElementById('sproof').value||undefined,
    scanned_barcode:document.getElementById('sbarcode').value||undefined,
    signature:document.getElementById('ssign').value||undefined
  };
  const r=await fetch('/courier/shipments/'+encodeURIComponent(oid)+'/status',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)});
  document.getElementById('statusout').textContent=await r.text();
}
</script>
</body></html>
"""
    return HTMLResponse(content=html)


@app.get("/courier/track_page", response_class=HTMLResponse)
def courier_track_page(request: Request):
    if not _auth_phone(request):
        return RedirectResponse(url="/login", status_code=303)
    try:
        with open(Path(__file__).parent / "courier_tracking.html", "r") as f:
            content = f.read()
    except Exception:
        return HTMLResponse(content="tracking UI not found", status_code=500)
    return HTMLResponse(content=content)


@app.get("/courier/driver_page", response_class=HTMLResponse)
def courier_driver_page(request: Request):
    if not _auth_phone(request):
        return RedirectResponse(url="/login", status_code=303)
    try:
        with open(Path(__file__).parent / "courier_driver.html", "r") as f:
            content = f.read()
    except Exception:
        return HTMLResponse(content="driver UI not found", status_code=500)
    return HTMLResponse(content=content)


@app.get("/courier/sla_page", response_class=HTMLResponse)
def courier_sla_page(request: Request):
    if not _auth_phone(request):
        return RedirectResponse(url="/login", status_code=303)
    try:
        with open(Path(__file__).parent / "courier_sla.html", "r") as f:
            content = f.read()
    except Exception:
        return HTMLResponse(content="sla UI not found", status_code=500)
    return HTMLResponse(content=content)


@app.get("/freight", response_class=HTMLResponse)
def freight_page(request: Request):
    if not _auth_phone(request):
        return RedirectResponse(url="/login", status_code=303)
    return _legacy_console_removed_page("Shamell · Freight")
    html = """
<!doctype html>
<html><head><meta name=viewport content="width=device-width, initial-scale=1" />
<title>Freight</title>
<link rel="icon" href="/icons/freight.svg" />
<style>
  body{font-family:sans-serif;margin:20px;max-width:1000px;background:#ffffff;color:#000000;}
  header{position:sticky;top:0;z-index:10;background:#ffffff;padding:8px 10px;border-bottom:1px solid #dddddd;margin:0 0 12px 0;display:flex;align-items:center;gap:8px}
  header h1{flex:1;font-size:20px;margin:0}
  button{font-size:14px;padding:6px 10px;border-radius:4px;border:1px solid #cccccc;background:#f3f4f6;color:#000000}
  input,select{font-size:14px;padding:6px 8px;border-radius:4px;border:1px solid #cccccc}
  table{border-collapse:collapse;width:100%}
  th,td{border:1px solid #dddddd;padding:6px}
  .card{border-radius:4px;border:1px solid #dddddd;padding:12px;background:#ffffff;margin-top:12px}
  pre{background:#f5f5f5;padding:8px;white-space:pre-wrap;border-radius:4px;border:1px solid #dddddd}
</style>
</head><body>
<header>
  <h1>Freight</h1>
  <button id=fr_refresh onclick="noop()">Refresh</button>
</header>
<section class="card">
  <h2>Quote</h2>
  <div style="display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:8px">
    <input id=title placeholder="Title" />
    <input id=flat placeholder="from lat" />
    <input id=flon placeholder="from lon" />
    <input id=tlat placeholder="to lat" />
    <input id=tlon placeholder="to lon" />
    <input id=kg placeholder="weight kg" />
  </div>
  <div style="margin-top:8px;display:flex;gap:8px">
    <button onclick="quote()">Quote</button>
  </div>
  <pre id=qout style="margin-top:8px;font-size:12px"></pre>
</section>
<section class="card">
  <h2>Book</h2>
  <div style="display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:8px">
    <input id=payer placeholder="Payer wallet id" />
    <input id=carrier placeholder="Carrier wallet id" />
    <label><input type=checkbox id=confirm /> Pay now (confirm)</label>
  </div>
  <div style="margin-top:8px;display:flex;gap:8px">
    <button onclick="book()">Book</button>
  </div>
  <pre id=bout style="margin-top:8px;font-size:12px"></pre>
</section>
<section class="card">
  <h2>Shipment status</h2>
  <div style="display:flex;flex-wrap:wrap;gap:8px;align-items:center">
    <input id=sid placeholder="shipment id" />
    <button onclick="sstatus()">Status</button>
    <select id=st>
      <option>booked</option>
      <option>in_transit</option>
      <option>delivered</option>
      <option>canceled</option>
    </select>
    <button onclick="sset()">Set status</button>
  </div>
  <pre id=sout style="margin-top:8px;font-size:12px"></pre>
</section>
<script>
  function noop(){ /* placeholder for top refresh; per-section actions provided */ }
  let lastReq=null;
  async function quote(){ const body={title:gi('title'), from_lat:parseFloat(gi('flat')), from_lon:parseFloat(gi('flon')), to_lat:parseFloat(gi('tlat')), to_lon:parseFloat(gi('tlon')), weight_kg:parseFloat(gi('kg'))}; lastReq=body; const r=await fetch('/freight/quote',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)}); document.getElementById('qout').textContent=await r.text(); }
  async function book(){ const req=lastReq||{title:gi('title'), from_lat:parseFloat(gi('flat')), from_lon:parseFloat(gi('flon')), to_lat:parseFloat(gi('tlat')), to_lon:parseFloat(gi('tlon')), weight_kg:parseFloat(gi('kg'))}; const body=Object.assign({}, req, {payer_wallet_id:gi('payer')||null, carrier_wallet_id:gi('carrier')||null, confirm:document.getElementById('confirm').checked}); const r=await fetch('/freight/book',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)}); const t=await r.text(); document.getElementById('bout').textContent=t; try{ const j=JSON.parse(t); document.getElementById('sid').value=j.id; }catch(_){} }
  async function sstatus(){ const id=gi('sid'); const r=await fetch('/freight/shipments/'+id); document.getElementById('sout').textContent=await r.text(); }
  async function sset(){ const id=gi('sid'); const st=document.getElementById('st').value; const r=await fetch('/freight/shipments/'+id+'/status',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({status:st})}); document.getElementById('sout').textContent=await r.text(); }
  function gi(id){ return (document.getElementById(id).value||'').trim(); }
</script>
</body></html>
"""
    return HTMLResponse(content=html)


@app.get("/bus/admin", response_class=HTMLResponse)
def bus_admin_page(request: Request):
    if not _auth_phone(request):
        return RedirectResponse(url="/login", status_code=303)
    # In production the legacy Bus HTML console remains disabled; in
    # dev/test we still expose it to make operator setup and debugging
    # easier (cities, operators, routes, trips, tickets).
    if _ENV_LOWER not in ("dev", "test"):
        return _legacy_console_removed_page("Shamell · Bus admin")

    html = """
<!doctype html>
<html><head><meta name=viewport content="width=device-width, initial-scale=1" />
<title>Bus Admin</title>
<link rel="icon" href="/icons/bus.svg" />
<link rel="manifest" href="/bus/manifest.json" />
<style>
  body{font-family:sans-serif;margin:20px;max-width:980px;background:#ffffff;color:#000000;}
  input,button,select{font-size:14px;padding:6px;margin:4px 0}
  input,select{background:#ffffff;border:1px solid #cccccc;border-radius:4px;color:#000000}
  button{border:1px solid #cccccc;background:#f3f4f6;border-radius:4px;color:#000000;box-shadow:none}
  pre{background:#f5f5f5;padding:8px;white-space:pre-wrap;border-radius:4px;border:1px solid #dddddd}
  .grid{display:grid;grid-template-columns:repeat(2,minmax(280px,1fr));gap:16px}
  .full{grid-column:1/-1}
  h2{margin-top:18px}
  small{opacity:.8}
  .row{display:flex;gap:8px;align-items:center}
  label{display:block;font-size:12px;opacity:.8;margin-top:6px}
  .muted{opacity:.7}
  .ok{color:#15803d}
  .warn{color:#b45309}
</style>
</head><body>
<h1>Bus Admin</h1>

<div class="grid">
  <div data-ds="card">
    <h2>Health</h2>
    <button onclick="health()">Check /bus/health</button>
    <pre id=health_out></pre>
  </div>

  <div data-ds="card">
    <h2>Cities</h2>
    <label>Name</label><input id=city_name placeholder="Damascus" />
    <label>Country</label><input id=city_country placeholder="Syria" />
    <div class=row>
      <button onclick="addCity()">Add City</button>
      <button onclick="listCities()">List</button>
    </div>
    <pre id=cities_out></pre>
  </div>

  <div data-ds="card">
    <h2>Operators</h2>
    <label>Name</label><input id=op_name placeholder="Shuttle Co." />
    <label>Wallet ID</label><input id=op_wallet placeholder="wallet-uuid" />
    <div class=row>
      <button onclick="addOperator()">Add Operator</button>
      <button onclick="listOperators()">List</button>
    </div>
    <div id=ops_out class="text-sm whitespace-pre-wrap"></div>
  </div>

  <div data-ds="card">
    <h2>Routes</h2>
    <label>Origin City ID</label><input id=rt_origin placeholder="city-id" />
    <label>Destination City ID</label><input id=rt_dest placeholder="city-id" />
    <label>Operator ID</label><input id=rt_op placeholder="operator-id" />
    <div class=row>
      <button onclick="addRoute()">Create Route</button>
      <button onclick="listRoutes()">List</button>
    </div>
    <pre id=routes_out></pre>
  </div>

  <div class="full" data-ds="card">
    <h2>Trips</h2>
    <div class=row>
      <div style="flex:1">
        <label>Route ID</label><input id=trip_route placeholder="route-id" />
      </div>
      <div>
        <label>Price (cents)</label><input id=trip_price placeholder="8000" />
      </div>
      <div>
        <label>Seats</label><input id=trip_seats placeholder="40" />
      </div>
    </div>
    <div class=row>
      <div style="flex:1">
        <label>Depart at (ISO)</label><input id=trip_dep placeholder="2025-11-20T08:00:00+00:00" />
      </div>
      <div style="flex:1">
        <label>Arrive at (ISO)</label><input id=trip_arr placeholder="2025-11-20T10:00:00+00:00" />
      </div>
    </div>
    <div class=row>
      <button onclick="addTrip()">Create Trip</button>
    </div>
    <div class=row>
      <div>
        <label>Search: Origin City</label><input id=s_origin placeholder="city-id" />
      </div>
      <div>
        <label>Dest City</label><input id=s_dest placeholder="city-id" />
      </div>
      <div>
        <label>Date (YYYY-MM-DD)</label><input id=s_date placeholder="2025-11-20" />
      </div>
      <button onclick="searchTrips()">Search</button>
    </div>
    <pre id=trips_out></pre>
  </div>

  <div data-ds="card">
    <h2>Booking</h2>
    <label>Trip ID</label><input id=b_trip placeholder="trip-id" />
    <label>Seats</label><input id=b_seats value="1" />
    <label>Wallet ID (optional)</label><input id=b_wallet placeholder="payer wallet" />
    <label>Customer Phone (optional)</label><input id=b_phone placeholder="+963..." />
    <div class=row>
      <button onclick="bookTrip()">Book</button>
    </div>
    <pre id=book_out></pre>
  </div>

  <div data-ds="card">
    <h2>Tickets / Boarding</h2>
    <label>Booking ID</label><input id=t_booking placeholder="booking-id" />
    <div class=row>
      <button onclick="loadTickets()">Load Tickets</button>
    </div>
    <label>Ticket Payload (QR)</label><input id=t_payload placeholder="TICKET|id=...|b=...|trip=...|seat=...|sig=..." />
    <div class=row>
      <button onclick="boardTicket()">Board</button>
    </div>
    <div id=tick_qrs style="display:grid;grid-template-columns:repeat(auto-fill,minmax(160px,1fr));gap:12px"></div>
    <pre id=tick_out></pre>
  </div>

  <div class="full muted">
    <small>Tip: Use /payments/users + /payments/wallets/{id}/topup (Admin) to create and top up wallets. Set Operator.wallet_id so payments can be processed.</small>
  </div>
</div>

<script>
function gi(id){ return (document.getElementById(id).value||'').trim(); }
async function health(){ const r=await fetch('/bus/health'); document.getElementById('health_out').textContent = await r.text(); }
async function addCity(){ const body={name:gi('city_name'), country:gi('city_country')||null}; const r=await fetch('/bus/cities',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)}); document.getElementById('cities_out').textContent=await r.text(); }
async function listCities(){ const r=await fetch('/bus/cities'); document.getElementById('cities_out').textContent=await r.text(); }
async function addOperator(){ const body={name:gi('op_name'), wallet_id:gi('op_wallet')||null}; const r=await fetch('/bus/operators',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)}); document.getElementById('ops_out').textContent=await r.text(); }
async function listOperators(){
  const box=document.getElementById('ops_out');
  box.textContent='Loading...';
  const r=await fetch('/bus/operators');
  try{
    const arr=await r.json();
    if(!Array.isArray(arr)){ box.textContent=JSON.stringify(arr,null,2); return; }
    box.innerHTML='';
    for(const op of arr){
      const row=document.createElement('div');
      row.className='flex items-center gap-2 border-b border-gray-200 py-1';
      const status = op.is_online ? 'Online' : 'Offline';
      row.innerHTML = `<span class="flex-1">${op.id} <small class="text-gray-500">${op.name||''}</small> <small class="text-gray-500">${status}</small></span>`;
      const btnOn = document.createElement('button');
      btnOn.textContent = 'Online';
      btnOn.onclick = async ()=>{ await fetch('/bus/operators/'+encodeURIComponent(op.id)+'/online',{method:'POST'}); listOperators(); };
      const btnOff = document.createElement('button');
      btnOff.textContent = 'Offline';
      btnOff.onclick = async ()=>{ await fetch('/bus/operators/'+encodeURIComponent(op.id)+'/offline',{method:'POST'}); listOperators(); };
      btnOn.className='px-2 py-1 border rounded text-xs';
      btnOff.className='px-2 py-1 border rounded text-xs';
      row.appendChild(btnOn); row.appendChild(btnOff);
      box.appendChild(row);
    }
  }catch(_){
    box.textContent=await r.text();
  }
}
async function addRoute(){ const body={origin_city_id:gi('rt_origin'), dest_city_id:gi('rt_dest'), operator_id:gi('rt_op')}; const r=await fetch('/bus/routes',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)}); document.getElementById('routes_out').textContent=await r.text(); }
async function listRoutes(){ const oc=gi('rt_origin'); const dc=gi('rt_dest'); const url = '/bus/routes'+((oc||dc)? ('?'+new URLSearchParams({origin_city_id:oc||'', dest_city_id:dc||''})) : ''); const r=await fetch(url); document.getElementById('routes_out').textContent=await r.text(); }
async function addTrip(){ const body={route_id:gi('trip_route'), depart_at_iso:gi('trip_dep'), arrive_at_iso:gi('trip_arr'), price_cents:parseInt(gi('trip_price')||'0'), currency:'SYP', seats_total:parseInt(gi('trip_seats')||'40')}; const r=await fetch('/bus/trips',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)}); document.getElementById('trips_out').textContent=await r.text(); }
async function searchTrips(){ const oc=gi('s_origin'), dc=gi('s_dest'), d=gi('s_date'); const r=await fetch('/bus/trips/search?'+new URLSearchParams({origin_city_id:oc,dest_city_id:dc,date:d})); const t=await r.text(); document.getElementById('trips_out').textContent=t; try{ const arr=JSON.parse(t); if(arr && arr.length>0 && arr[0].trip && arr[0].trip.id){ document.getElementById('b_trip').value=arr[0].trip.id; } }catch(_){ }
}
async function bookTrip(){ const body={seats:parseInt(gi('b_seats')||'1'), wallet_id:gi('b_wallet')||null, customer_phone:gi('b_phone')||null}; const id=gi('b_trip'); const r=await fetch('/bus/trips/'+encodeURIComponent(id)+'/book',{method:'POST',headers:{'content-type':'application/json','Idempotency-Key':'ui-'+Date.now()},body:JSON.stringify(body)}); const t=await r.text(); document.getElementById('book_out').textContent=t; try{ const j=JSON.parse(t); if(j && j.id){ document.getElementById('t_booking').value=j.id; } }catch(_){ }
}
async function loadTickets(){
  const id=gi('t_booking');
  const r=await fetch('/bus/bookings/'+encodeURIComponent(id)+'/tickets');
  const t=await r.text();
  document.getElementById('tick_out').textContent=t;
  try{
    const arr = JSON.parse(t);
    const box = document.getElementById('tick_qrs');
    if(Array.isArray(arr)){
      box.innerHTML = '';
      arr.forEach((tk)=>{
        const payload = (tk && tk.payload)||'';
        const seat = tk && tk.seat_no;
        const id = tk && tk.id;
        const div = document.createElement('div');
        div.style.padding='8px'; div.style.border='1px solid #dddddd'; div.style.borderRadius='4px';
        const img = document.createElement('img');
        img.alt = 'QR'; img.style.width='100%'; img.style.background='#fff'; img.style.borderRadius='8px';
        img.src = '/qr.png?'+new URLSearchParams({data: payload});
        const label = document.createElement('div'); label.style.marginTop='6px'; label.style.fontSize='12px'; label.style.opacity='.85';
        label.textContent = 'Seat: '+(seat||'?')+'  ·  '+(id||'');
        const small = document.createElement('div'); small.style.fontSize='11px'; small.style.opacity='.75'; small.textContent = payload.substring(0,80) + (payload.length>80?'…':'');
        div.appendChild(img); div.appendChild(label); div.appendChild(small);
        box.appendChild(div);
      });
    }
  }catch(_){ }
}
async function boardTicket(){ const body={payload:gi('t_payload')}; const r=await fetch('/bus/tickets/board',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)}); document.getElementById('tick_out').textContent=await r.text(); }
</script>
</body></html>
"""
    return HTMLResponse(content=html)


@app.get("/ds.js")
def ds_js():
    js = """
(function(){
  if (window.__dsInjected) return; window.__dsInjected = true;
  var css = `:root{--ds-c1:#6366f1;--ds-c2:#22d3ee;--ds-c3:#22c55e;--ds-glow:rgba(34,211,238,.5)}
  @keyframes ds-shift{0%{background-position:0% 50%}50%{background-position:100% 50%}100%{background-position:0% 50%}}
  @keyframes ds-sheen{0%{transform:translateX(-120%) skewX(-15deg);opacity:.0}30%{opacity:.6}70%{opacity:.6}100%{transform:translateX(140%) skewX(-15deg);opacity:0}}
  .ds-btn, .ds-btnPri{position:relative;display:inline-flex;align-items:center;gap:10px;padding:12px 18px;border-radius:20px;color:#f6fbff;
    border:1.2px solid rgba(255,255,255,.32);
    background: radial-gradient(120% 140% at 0% 0%, rgba(255,255,255,.34), rgba(255,255,255,.14)), rgba(255,255,255,.10);
    box-shadow: inset 0 1px 1px rgba(255,255,255,.30), inset 0 -8px 22px rgba(0,0,0,.42), 0 14px 36px rgba(0,0,0,.65), 0 0 0 1px rgba(255,255,255,.10), 0 0 28px var(--ds-glow);
    backdrop-filter: blur(16px) saturate(150%);
    transition: transform .12s ease, box-shadow .22s ease, background .22s ease, filter .22s ease;
    transform: translateZ(0);
    text-shadow: 0 1px 1px rgba(0,0,0,.45), 0 0 12px rgba(255,255,255,.20);
  }
  .ds-btn:before, .ds-btnPri:before{content:"";position:absolute;inset:0;border-radius:20px;background:
    radial-gradient(80% 100% at 12% 8%, rgba(255,255,255,.58), rgba(255,255,255,0) 60%),
    radial-gradient(60% 60% at 85% 10%, rgba(255,255,255,.22), rgba(255,255,255,0) 60%);
    pointer-events:none;mix-blend-mode:screen}
  .ds-btn:after, .ds-btnPri:after{content:"";position:absolute;top:-20%;bottom:-20%;width:28%;left:0;border-radius:20px;
    background: linear-gradient(90deg, rgba(255,255,255,0), rgba(255,255,255,.65), rgba(255,255,255,0));
    filter: blur(4px);opacity:0;pointer-events:none}
  .ds-btn:hover, .ds-btnPri:hover{transform:translateY(-2px);box-shadow: inset 0 1px 1px rgba(255,255,255,.35), inset 0 -8px 20px rgba(0,0,0,.38), 0 18px 40px rgba(0,0,0,.7), 0 0 0 1px rgba(255,255,255,.12), 0 0 30px var(--ds-glow)}
  .ds-btn:hover:after, .ds-btnPri:hover:after{animation: ds-sheen .9s ease forwards}
  .ds-btn:active, .ds-btnPri:active{transform:translateY(0) scale(.985);filter:saturate(175%);box-shadow: inset 0 1px 1px rgba(255,255,255,.34), inset 0 -12px 22px rgba(0,0,0,.45), 0 12px 28px rgba(0,0,0,.6), 0 0 0 1px rgba(255,255,255,.12)}
  .ds-btnPri{background-image: linear-gradient(120deg, var(--ds-c1), var(--ds-c2), var(--ds-c3)); background-size: 220% 220%; animation: ds-shift 5s linear infinite;}
  .ds-btnSec{position:relative;display:inline-flex;align-items:center;gap:10px;padding:12px 18px;border-radius:20px;color:#f6fbff;
    border:1.2px solid rgba(255,255,255,.28);
    background: rgba(255,255,255,.08);
    box-shadow: inset 0 1px 1px rgba(255,255,255,.22), 0 10px 26px rgba(0,0,0,.35);
    backdrop-filter: blur(12px) saturate(140%);
    transition: transform .12s ease, box-shadow .22s ease;
  }
  .ds-btnGhost{display:inline-flex;align-items:center;gap:10px;padding:10px 14px;border-radius:16px;color:#f6fbff;border:1px solid transparent;background:transparent}
  .ds-chip{display:inline-flex;align-items:center;gap:6px;padding:6px 10px;border-radius:999px;background:rgba(255,255,255,.12);border:1px solid rgba(255,255,255,.28);backdrop-filter:blur(10px);color:#fff;font-size:12px}
  .ds-card{border-radius:20px;border:1px solid rgba(255,255,255,.22);background:rgba(255,255,255,.09);backdrop-filter:blur(18px);box-shadow:0 10px 26px rgba(0,0,0,.25)}
  .ds-input{padding:10px 12px;border-radius:14px;border:1px solid rgba(255,255,255,.22);background:rgba(255,255,255,.08);color:#f6fbff;backdrop-filter:blur(12px)}
  .ds-input::placeholder{color:rgba(255,255,255,.65)}
  body{font-synthesis-weight:none;-webkit-font-smoothing:antialiased;-moz-osx-font-smoothing:grayscale}
  `;
  try{ var st=document.createElement('style'); st.id='ds-style'; st.textContent=css; document.head.appendChild(st);
       var st2=document.createElement('style'); st2.id='ds-simple'; st2.textContent = `
         :root{--bg:#0f172a;--fg:#f8fafc;--muted:#94a3b8;--border:#1f2937;--card:rgba(255,255,255,.06);--accent:#6366f1;--accent-contrast:#ffffff}
         .dark:root{--bg:#0f172a;--fg:#f8fafc;--muted:#94a3b8;--border:#1f2937;--card:rgba(255,255,255,.06);--accent:#6366f1;--accent-contrast:#ffffff}
         .ds-btn{display:inline-flex;align-items:center;justify-content:center;gap:8px;padding:12px 16px;border-radius:16px;border:1px solid rgba(255,255,255,.22);background:rgba(255,255,255,.08);color:#fff;backdrop-filter:blur(10px)}
         .ds-btn:hover{filter:brightness(1.02)} .ds-btn:active{transform:translateY(1px)}
         .ds-btnPri{display:inline-flex;align-items:center;justify-content:center;gap:8px;padding:12px 16px;border-radius:16px;border:1px solid rgba(255,255,255,.24);background:linear-gradient(120deg, #6366f1, #22d3ee, #22c55e);background-size:220% 220%;color:#fff;box-shadow:0 8px 20px rgba(0,0,0,.35)}
         .ds-btnSec{display:inline-flex;align-items:center;justify-content:center;gap:8px;padding:12px 16px;border-radius:16px;border:1px solid rgba(255,255,255,.22);background:rgba(255,255,255,.08);color:#fff}
         .ds-btnGhost{display:inline-flex;align-items:center;justify-content:center;gap:8px;padding:10px 12px;border-radius:14px;border:1px solid transparent;background:transparent;color:#fff}
         .ds-input{padding:10px 12px;border-radius:12px;border:1.5px solid rgba(255,255,255,.28);background:rgba(255,255,255,.08);color:#f8fafc}
         .ds-input::placeholder{color:#cbd5e1}
         .ds-input:focus{background:rgba(255,255,255,.10)}
         .ds-card{border:1px solid rgba(255,255,255,.22);border-radius:18px;background:rgba(255,255,255,.06);backdrop-filter:blur(12px);box-shadow:0 6px 16px rgba(0,0,0,.25);padding:12px}
      `; document.head.appendChild(st2);
  }catch(_){ }
  function setAccent(name){
    var palette={ payments:'#2563eb', merchant:'#7c3aed', taxi:'#f59e0b', food:'#ef4444', realestate:'#10b981', stays:'#14b8a6', freight:'#f59e0b', carmarket:'#3b82f6', carrental:'#3b82f6', chat:'#06b6d4', agriculture:'#10b981', commerce:'#0ea5e9', doctors:'#f43f5e', flights:'#38bdf8', jobs:'#8b5cf6', livestock:'#84cc16', default:'#2563eb'}; var a = palette[name] || palette.default; var root=document.documentElement; root.style.setProperty('--accent', a);
  }
  function apply(){
    try{ document.querySelectorAll('.btnPri').forEach(function(el){ el.classList.add('ds-btnPri');}); }catch(_){ }
    try{ document.querySelectorAll('.btnSec').forEach(function(el){ el.classList.add('ds-btnSec');}); }catch(_){ }
    try{ document.querySelectorAll('.btnGhost').forEach(function(el){ el.classList.add('ds-btnGhost');}); }catch(_){ }
    try{ document.querySelectorAll('button').forEach(function(el){ if(!el.classList.contains('ds-btnPri') && !el.classList.contains('ds-btnSec') && !el.classList.contains('ds-btnGhost')) el.classList.add('ds-btn');}); }catch(_){ }
    try{ document.querySelectorAll('[data-chip], .chip').forEach(function(el){ el.classList.add('ds-chip');}); }catch(_){ }
    try{ document.querySelectorAll('[data-ds="card"]').forEach(function(el){ el.classList.add('ds-card');}); }catch(_){ }
    try{ document.querySelectorAll('input, textarea, select').forEach(function(el){ el.classList.add('ds-input');}); }catch(_){ }
  }
  function applyBG(){
    try{
      var enforce = (document.body && document.body.getAttribute('data-bg') === 'simple');
      if(!enforce) return; // do not override page-specific gradients unless explicitly requested
      var st=document.getElementById('ds-bg');
      if(!st){ st=document.createElement('style'); st.id='ds-bg'; document.head.appendChild(st); }
      st.textContent = 'body{background:var(--bg)!important;color:var(--fg)!important}';
    }catch(_){ }
  }
  window.DS = window.DS || {};
  window.DS.setAccent = setAccent;
  window.DS.apply = apply;
  window.DS.applyBG = applyBG;
  // Auto-accent from body data-accent
  try{ var acc=document.body && document.body.getAttribute('data-accent'); if(acc) setAccent(acc); }catch(_){ }
  applyBG();
  apply();
})();
"""
    return Response(content=js, media_type="application/javascript")

@app.get("/agriculture", response_class=HTMLResponse)
def agriculture_page():
    return _legacy_console_removed_page("Shamell · Agriculture")
    html = """
<!doctype html>
<html><head><meta name=viewport content="width=device-width, initial-scale=1" />
<title>Agriculture Operator</title>
<link rel="icon" href="/icons/agriculture.svg" />
<link rel="manifest" href="/agriculture/manifest.json" />
<style>
  body{font-family:sans-serif;margin:20px;max-width:820px;background:#ffffff;color:#000000;}
  input,button{font-size:14px;padding:6px;margin:4px 0}
  input{background:#ffffff;border:1px solid #cccccc;border-radius:4px;color:#000000}
  button{border:1px solid #cccccc;background:#f3f4f6;border-radius:4px;color:#000000;box-shadow:none}
  pre{background:#f5f5f5;padding:8px;white-space:pre-wrap;border-radius:4px;border:1px solid #dddddd}
</style>
</head><body>
<div style="position:sticky;top:0;z-index:10;background:#ffffff;padding:8px 10px;border-bottom:1px solid #dddddd;margin:0 0 12px 0;display:flex;align-items:center;gap:8px"><div style="flex:1;font-weight:600">Agriculture (Operator)</div></div>
<p>Stub dashboard. When the API is available this page will surface listings/orders/quotes.</p>
<div>
  <button onclick="health()">Check Health</button>
  <pre id=out></pre>
</div>
<script>
async function health(){ try{ const r=await fetch('/agriculture/health'); document.getElementById('out').textContent=await r.text(); }catch(e){ document.getElementById('out').textContent='Error: '+e; } }
</script>
</body></html>
"""
    return HTMLResponse(content=html)


@app.get("/commerce", response_class=HTMLResponse)
def commerce_page():
    return _legacy_console_removed_page("Shamell · Commerce")
    html = """
<!doctype html>
<html><head><meta name=viewport content="width=device-width, initial-scale=1" />
<title>Commerce Operator</title>
<link rel="icon" href="/icons/commerce.svg" />
<link rel="manifest" href="/commerce/manifest.json" />
<style>
  body{font-family:sans-serif;margin:20px;max-width:820px;background:#ffffff;color:#000000;}
  input,button{font-size:14px;padding:6px;margin:4px 0}
  input{background:#ffffff;border:1px solid #cccccc;border-radius:4px;color:#000000}
  button{border:1px solid #cccccc;background:#f3f4f6;border-radius:4px;color:#000000;box-shadow:none}
  pre{background:#f5f5f5;padding:8px;white-space:pre-wrap;border-radius:4px;border:1px solid #dddddd}
</style>
</head><body>
<div style="position:sticky;top:0;z-index:10;background:#ffffff;padding:8px 10px;border-bottom:1px solid #dddddd;margin:0 0 12px 0;display:flex;align-items:center;gap:8px"><div style="flex:1;font-weight:600">Commerce (Operator)</div></div>
<p>Stub dashboard. Planned modules: catalog, carts, orders, payouts.</p>
<div>
  <button onclick="health()">Check Health</button>
  <pre id=out></pre>
</div>
<script>
async function health(){ try{ const r=await fetch('/commerce/health'); document.getElementById('out').textContent=await r.text(); }catch(e){ document.getElementById('out').textContent='Error: '+e; } }
</script>
</body></html>
"""
    return HTMLResponse(content=html)


@app.get("/doctors", response_class=HTMLResponse)
def doctors_page():
    html = """
<!doctype html>
<html><head><meta name=viewport content="width=device-width, initial-scale=1" />
<title>Doctors · Booking</title>
<link rel="icon" href="/icons/doctors.svg" />
<style>
  :root { --accent:#f43f5e; --bg:#0b1520; --panel:#111c29; --muted:#9fb0c7; --border:#1e2a38; --card:#0e1926; }
  *{box-sizing:border-box;}
  body{margin:0;padding:24px;font-family:"Inter",-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;background:linear-gradient(135deg,#0b1520 0%,#0d1b2b 45%,#0f2238 100%);color:#e8f0ff;}
  h1,h2{margin:0 0 10px 0;font-weight:700;letter-spacing:-0.01em;}
  p{margin:6px 0 14px 0;color:var(--muted);}
  .shell{max-width:1080px;margin:0 auto;}
  .grid{display:grid;grid-template-columns:1fr 1fr;gap:16px;align-items:start;}
  .card{background:var(--panel);border:1px solid var(--border);border-radius:14px;padding:16px;box-shadow:0 18px 40px rgba(0,0,0,0.35);}
  label{display:block;font-size:13px;color:var(--muted);margin-bottom:4px;}
  input,select,button,textarea{width:100%;border-radius:10px;border:1px solid var(--border);background:var(--card);color:#e8f0ff;font-size:14px;padding:10px;}
  button{background:var(--accent);border-color:transparent;font-weight:600;cursor:pointer;transition:transform .08s ease, box-shadow .12s ease;}
  button:hover{transform:translateY(-1px);box-shadow:0 10px 25px rgba(244,63,94,0.35);}
  .row{display:flex;gap:8px;}
  .row > *{flex:1;}
  .list{display:flex;flex-direction:column;gap:10px;}
  .item{padding:12px;border:1px solid var(--border);border-radius:12px;background:var(--card);}
  .pill{display:inline-flex;align-items:center;padding:3px 8px;border-radius:999px;border:1px solid var(--border);font-size:12px;color:var(--muted);}
  .slots{display:flex;flex-wrap:wrap;gap:8px;}
  .slot{padding:10px 12px;border-radius:10px;border:1px solid var(--border);background:var(--card);cursor:pointer;transition:all .1s ease;}
  .slot:hover{border-color:var(--accent);color:#fff;}
  .muted{color:var(--muted);}
  pre{white-space:pre-wrap;word-break:break-word;}
  @media(max-width:900px){ .grid{grid-template-columns:1fr;} body{padding:14px;} }
</style>
</head><body>
<div class="shell">
  <div style="display:flex;align-items:center;gap:12px;margin-bottom:16px;">
    <div style="width:38px;height:38px;border-radius:10px;background:rgba(244,63,94,0.12);border:1px solid rgba(244,63,94,0.3);display:grid;place-items:center;font-weight:700;color:#fff;">DR</div>
    <div>
      <h1 style="margin:0;">Doctors</h1>
      <p style="margin:0;">Search, pick a slot, book, reschedule or cancel — Doctolib-style.</p>
    </div>
    <div style="flex:1;"></div>
    <button style="width:auto;padding:10px 14px;" onclick="health()">Health</button>
  </div>

  <div class="grid">
    <div class="card">
      <h2>Search doctors</h2>
      <div class="row">
        <div>
          <label>Name</label>
          <input id="q" placeholder="e.g. Müller" />
        </div>
        <div>
          <label>Speciality</label>
          <input id="speciality" placeholder="e.g. Allgemeinmedizin" />
        </div>
      </div>
      <div class="row">
        <div>
          <label>City</label>
          <input id="city" placeholder="e.g. Berlin" />
        </div>
        <div style="align-self:flex-end;">
          <button onclick="loadDoctors()">Search</button>
        </div>
      </div>
      <div id="doctors" class="list" style="margin-top:10px;"></div>
    </div>

    <div class="card">
      <h2>Book appointment</h2>
      <label>Selected doctor</label>
      <div id="selectedDoctor" class="pill">None</div>
      <div style="margin-top:10px;">
        <label>Slot</label>
        <div id="slots" class="slots"></div>
      </div>
      <div class="row" style="margin-top:10px;">
        <div><label>Patient name</label><input id="pname" /></div>
        <div><label>Phone</label><input id="pphone" /></div>
      </div>
      <div class="row">
        <div><label>Email</label><input id="pemail" /></div>
        <div><label>Reason</label><input id="preason" placeholder="optional" /></div>
      </div>
      <div class="row">
        <div><label>Duration (min)</label><input id="pduration" type="number" value="20" /></div>
        <div style="align-self:flex-end;"><button onclick="book()">Book</button></div>
      </div>
      <div id="bookResult" class="muted" style="margin-top:10px;"></div>
    </div>
  </div>

  <div class="card" style="margin-top:16px;">
    <h2>Manage existing appointment</h2>
    <div class="row">
      <div><label>Appointment ID</label><input id="apptId" placeholder="hex id returned on booking" /></div>
      <div><label>New slot (ISO)</label><input id="rescheduleTs" placeholder="2024-10-01T09:20:00+02:00" /></div>
      <div><label>New duration (min)</label><input id="rescheduleDur" type="number" /></div>
    </div>
    <div class="row" style="margin-top:8px;">
      <button onclick="reschedule()">Reschedule</button>
      <button onclick="cancelAppt()" style="background:#0f2238;border:1px solid var(--border);">Cancel</button>
    </div>
    <div id="apptResult" class="muted" style="margin-top:10px;"></div>
  </div>

  <div class="card" style="margin-top:16px;">
    <h2>Raw output</h2>
    <pre id="out">Ready</pre>
  </div>
</div>

<script>
let currentDoctor=null;
async function health(){ try{ const r=await fetch('/doctors/health'); document.getElementById('out').textContent=await r.text(); }catch(e){ document.getElementById('out').textContent='Error: '+e; } }

function renderDoctors(list){
  const el=document.getElementById('doctors'); el.innerHTML='';
  if(!list.length){ el.innerHTML='<div class="muted">No doctors found.</div>'; return; }
  list.forEach(d=>{
    const div=document.createElement('div'); div.className='item';
    div.innerHTML=\`
      <div style="display:flex;justify-content:space-between;align-items:center;gap:8px;">
        <div>
          <div style="font-weight:700">\${d.name}</div>
          <div class="muted">\${d.speciality||'—'} · \${d.city||'—'} · \${d.timezone}</div>
        </div>
        <button style="width:auto;padding:8px 12px;" onclick='selectDoctor(\${d.id}, "\${d.name.replace(/"/g,'')}" )'>Select</button>
      </div>\`;
    el.appendChild(div);
  });
}

async function loadDoctors(){
  const q=document.getElementById('q').value.trim();
  const city=document.getElementById('city').value.trim();
  const sp=document.getElementById('speciality').value.trim();
  const params=new URLSearchParams({limit:50});
  if(q) params.set('q',q);
  if(city) params.set('city',city);
  if(sp) params.set('speciality',sp);
  try{
    const r=await fetch('/doctors/doctors?'+params.toString());
    const data=await r.json();
    renderDoctors(data);
    document.getElementById('out').textContent=JSON.stringify(data,null,2);
  }catch(e){ document.getElementById('out').textContent='Error: '+e; }
}

async function selectDoctor(id,name){
  currentDoctor=id;
  document.getElementById('selectedDoctor').textContent=name+' (#'+id+')';
  document.getElementById('slots').innerHTML='<div class="muted">Loading slots…</div>';
  try{
    const r=await fetch('/doctors/slots?doctor_id='+id+'&days=7');
    const slots=await r.json();
    renderSlots(slots);
    document.getElementById('out').textContent=JSON.stringify(slots,null,2);
  }catch(e){ document.getElementById('slots').innerHTML='<div class="muted">Error loading slots</div>'; }
}

function renderSlots(slots){
  const el=document.getElementById('slots'); el.innerHTML='';
  if(!slots.length){ el.innerHTML='<div class="muted">No upcoming slots</div>'; return; }
  slots.slice(0,60).forEach(s=>{
    const div=document.createElement('div'); div.className='slot';
    const t=new Date(s.ts_iso);
    div.textContent=t.toLocaleString(undefined,{weekday:'short', month:'short', day:'numeric', hour:'2-digit', minute:'2-digit'});
    div.onclick=()=>{ document.getElementById('slots').querySelectorAll('.slot').forEach(n=>n.style.borderColor='var(--border)'); div.style.borderColor='var(--accent)'; div.dataset.selected='1'; document.getElementById('bookResult').textContent='Selected '+s.ts_iso; document.getElementById('bookResult').dataset.ts=s.ts_iso; document.getElementById('pduration').value=s.duration_minutes; };
    el.appendChild(div);
  });
}

async function book(){
  if(!currentDoctor){ document.getElementById('bookResult').textContent='Select a doctor first'; return; }
  const ts=document.getElementById('bookResult').dataset.ts;
  if(!ts){ document.getElementById('bookResult').textContent='Select a slot first'; return; }
  const body={
    doctor_id: currentDoctor,
    patient_name: document.getElementById('pname').value || null,
    patient_phone: document.getElementById('pphone').value || null,
    patient_email: document.getElementById('pemail').value || null,
    reason: document.getElementById('preason').value || null,
    ts_iso: ts,
    duration_minutes: parseInt(document.getElementById('pduration').value||'20',10)
  };
  try{
    const r=await fetch('/doctors/appointments',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
    const data=await r.json();
    document.getElementById('bookResult').textContent='Booked: '+data.id;
    document.getElementById('apptId').value=data.id;
    document.getElementById('out').textContent=JSON.stringify(data,null,2);
  }catch(e){ document.getElementById('bookResult').textContent='Error '+e; }
}

async function cancelAppt(){
  const id=document.getElementById('apptId').value.trim();
  if(!id){ document.getElementById('apptResult').textContent='Enter appointment id'; return; }
  try{
    const r=await fetch('/doctors/appointments/'+id+'/cancel',{method:'POST'});
    const data=await r.json();
    document.getElementById('apptResult').textContent='Canceled';
    document.getElementById('out').textContent=JSON.stringify(data,null,2);
  }catch(e){ document.getElementById('apptResult').textContent='Error '+e; }
}

async function reschedule(){
  const id=document.getElementById('apptId').value.trim();
  if(!id){ document.getElementById('apptResult').textContent='Enter appointment id'; return; }
  const ts=document.getElementById('rescheduleTs').value.trim();
  if(!ts){ document.getElementById('apptResult').textContent='Enter new ts_iso'; return; }
  const dur=document.getElementById('rescheduleDur').value.trim();
  const body={ ts_iso: ts };
  if(dur){ body.duration_minutes=parseInt(dur,10); }
  try{
    const r=await fetch('/doctors/appointments/'+id+'/reschedule',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
    const data=await r.json();
    document.getElementById('apptResult').textContent='Rescheduled';
    document.getElementById('out').textContent=JSON.stringify(data,null,2);
  }catch(e){ document.getElementById('apptResult').textContent='Error '+e; }
}

loadDoctors();
</script>
</body></html>
"""
    return HTMLResponse(content=html)


@app.get("/flights", response_class=HTMLResponse)
def flights_page():
    return _legacy_console_removed_page("Shamell · Flights")
    html = """
<!doctype html>
<html><head><meta name=viewport content="width=device-width, initial-scale=1" />
<title>Flights Operator</title>
<link rel="icon" href="/icons/flights.svg" />
<link rel="manifest" href="/flights/manifest.json" />
<style>
  body{font-family:sans-serif;margin:20px;max-width:820px;background:#ffffff;color:#000000;}
  input,button{font-size:14px;padding:6px;margin:4px 0}
  input{background:#ffffff;border:1px solid #cccccc;border-radius:4px;color:#000000}
  button{border:1px solid #cccccc;background:#f3f4f6;border-radius:4px;color:#000000;box-shadow:none}
  pre{background:#f5f5f5;padding:8px;white-space:pre-wrap;border-radius:4px;border:1px solid #dddddd}
</style>
</head><body>
<div style="position:sticky;top:0;z-index:10;background:#ffffff;padding:8px 10px;border-bottom:1px solid #dddddd;margin:0 0 12px 0;display:flex;align-items:center;gap:8px"><div style="flex:1;font-weight:600">Flights (Operator)</div></div>
<p>Stub dashboard. Planned modules: flights, quotes, bookings, tickets.</p>
<div>
  <button onclick="health()">Check Health</button>
  <pre id=out></pre>
</div>
<script>
async function health(){ try{ const r=await fetch('/flights/health'); document.getElementById('out').textContent=await r.text(); }catch(e){ document.getElementById('out').textContent='Error: '+e; } }
</script>
</body></html>
"""
    return HTMLResponse(content=html)


@app.get("/jobs", response_class=HTMLResponse)
def jobs_page():
    return _legacy_console_removed_page("Shamell · Jobs")
    html = """
<!doctype html>
<html><head><meta name=viewport content="width=device-width, initial-scale=1" />
<title>Jobs Operator</title>
<link rel="icon" href="/icons/jobs.svg" />
<link rel="manifest" href="/jobs/manifest.json" />
<style>
  body{font-family:sans-serif;margin:20px;max-width:820px;background:#ffffff;color:#000000;}
  input,button{font-size:14px;padding:6px;margin:4px 0}
  input{background:#ffffff;border:1px solid #cccccc;border-radius:4px;color:#000000}
  button{border:1px solid #cccccc;background:#f3f4f6;border-radius:4px;color:#000000;box-shadow:none}
  pre{background:#f5f5f5;padding:8px;white-space:pre-wrap;border-radius:4px;border:1px solid #dddddd}
</style>
</head><body>
<div style="position:sticky;top:0;z-index:10;background:#ffffff;padding:8px 10px;border-bottom:1px solid #dddddd;margin:0 0 12px 0;display:flex;align-items:center;gap:8px"><div style="flex:1;font-weight:600">Jobs (Operator)</div></div>
<p>Stub dashboard. Planned modules: jobs, candidates, applications.</p>
<div>
  <button onclick="health()">Check Health</button>
  <pre id=out></pre>
</div>
<script>
async function health(){ try{ const r=await fetch('/jobs/health'); document.getElementById('out').textContent=await r.text(); }catch(e){ document.getElementById('out').textContent='Error: '+e; } }
</script>
</body></html>
"""
    return HTMLResponse(content=html)


@app.get("/livestock", response_class=HTMLResponse)
def livestock_page():
    return _legacy_console_removed_page("Shamell · Livestock")
    html = """
<!doctype html>
<html><head><meta name=viewport content="width=device-width, initial-scale=1" />
<title>Livestock Operator</title>
<link rel="icon" href="/icons/livestock.svg" />
<link rel="manifest" href="/livestock/manifest.json" />
<style>
  body{font-family:sans-serif;margin:20px;max-width:820px;background:#ffffff;color:#000000;}
  input,button{font-size:14px;padding:6px;margin:4px 0}
  input{background:#ffffff;border:1px solid #cccccc;border-radius:4px;color:#000000}
  button{border:1px solid #cccccc;background:#f3f4f6;border-radius:4px;color:#000000;box-shadow:none}
  pre{background:#f5f5f5;padding:8px;white-space:pre-wrap;border-radius:4px;border:1px solid #dddddd}
</style>
</head><body>
<div style="position:sticky;top:0;z-index:10;background:#ffffff;padding:8px 10px;border-bottom:1px solid #dddddd;margin:0 0 12px 0;display:flex;align-items:center;gap:8px"><div style="flex:1;font-weight:600">Livestock (Operator)</div></div>
<p>Stub dashboard. Planned modules: listings, quotes, shipments.</p>
<div>
  <button onclick="health()">Check Health</button>
  <pre id=out></pre>
</div>
<script>
async function health(){ try{ const r=await fetch('/livestock/health'); document.getElementById('out').textContent=await r.text(); }catch(e){ document.getElementById('out').textContent='Error: '+e; } }
</script>
</body></html>
"""
    return HTMLResponse(content=html)


@app.get("/chat", response_class=HTMLResponse)
def chat_page():
    return _legacy_console_removed_page("Shamell · Chat")
    html = """
<!doctype html>
<html><head><meta name=viewport content="width=device-width, initial-scale=1" />
<title>Chat (E2E)</title>
<script src="https://cdn.jsdelivr.net/npm/tweetnacl/nacl-fast.min.js"></script>
<style>body{font-family:sans-serif;margin:20px;max-width:800px} input,button,textarea{font-size:14px;padding:6px;margin:4px 0} textarea{width:100%;height:80px} pre{background:#f4f4f4;padding:8px;white-space:pre-wrap}</style>
</head><body>
<h1>Chat (Threema‑style E2E)</h1>
<section>
  <h2>Your Identity</h2>
  <div>
    <button onclick="gen()">Generate Keys</button>
    <input id=myid placeholder="Your ID (e.g. 8-12 chars)" />
    <input id=myname placeholder="Display name" />
    <button onclick="registerDev()">Register</button>
    <pre id=me></pre>
  </div>
  <div>
    <h3>Share</h3>
    <pre id=share></pre>
    <div id=qr></div>
    <div>
      <small>My fingerprint: <code id=myfp></code></small>
    </div>
    <button onclick="scanStart()">Scan Peer QR</button>
    <div id=scanner style="width:260px;height:220px"></div>
  </div>
</section>
<section>
  <h2>Contact</h2>
  <input id=peerid placeholder="Peer ID" />
  <button onclick="resolvePeer()">Fetch peer key</button>
  <pre id=peer></pre>
  <div>
    <small>Peer fingerprint: <code id=peerfp></code> · Verified: <span id=verif>no</span></small>
    <div><button onclick="markVerified()">Mark verified</button></div>
  </div>
</section>
<section>
  <h2>Send message</h2>
  <textarea id=plain placeholder="Message..."></textarea>
  <button onclick="sendMsg()">Send</button>
  <pre id=sendout></pre>
</section>
<section>
  <h2>Inbox</h2>
  <button onclick="poll()">Poll</button>
  <small>WS: <span id=live>disconnected</span></small>
  <pre id=inbox></pre>
</section>
<script src="https://unpkg.com/html5-qrcode@2.3.10/html5-qrcode.min.js"></script>
<script>
let my = {pk:null, sk:null, id:null, name:null};
let peers = {}; // id -> pk (base64)
let ws = null;

function b64(u8){ return btoa(String.fromCharCode.apply(null, Array.from(u8))); }
function unb64(s){ return new Uint8Array(atob(s).split('').map(c=>c.charCodeAt(0))); }

function gen(){
  const kp = nacl.box.keyPair();
  my.pk = kp.publicKey; my.sk = kp.secretKey;
  document.getElementById('me').textContent = 'PublicKey(b64)=' + b64(my.pk);
  const id = (Math.random().toString(36).slice(2,10));
  document.getElementById('myid').value = id; my.id = id;
  const payload = 'CHAT|id='+id+'|pk='+b64(my.pk);
  document.getElementById('share').textContent = payload;
  makeQR(payload);
  updateMyFp();
  connectWS();
}

async function registerDev(){
  const id = (document.getElementById('myid').value||'').trim(); my.id=id;
  const name = (document.getElementById('myname').value||'').trim(); my.name=name;
  if(!my.pk){ alert('Generate keys'); return; }
  const body = {device_id:id, public_key_b64:b64(my.pk), name:name||null};
  const r = await fetch('/chat/devices/register',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)});
  document.getElementById('me').textContent = await r.text();
  // connect WS after registration
  connectWS();
}

async function resolvePeer(){
  const id = (document.getElementById('peerid').value||'').trim();
  const r = await fetch('/chat/devices/'+encodeURIComponent(id));
  const j = await r.json(); peers[id] = j.public_key_b64; document.getElementById('peer').textContent = JSON.stringify(j,null,2);
  updatePeerFp();
}

async function sendMsg(){
  const id = (document.getElementById('peerid').value||'').trim(); const pkb64 = peers[id]; if(!pkb64){ alert('resolve peer first'); return; }
  const msg = (document.getElementById('plain').value||'');
  const nonce = nacl.randomBytes(24);
  const peerPk = unb64(pkb64);
  const box = nacl.box(new TextEncoder().encode(msg), nonce, peerPk, my.sk);
  const body = {sender_id: my.id, recipient_id: id, sender_pubkey_b64: b64(my.pk), nonce_b64: b64(nonce), box_b64: b64(box)};
  const r = await fetch('/chat/messages/send',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)});
  document.getElementById('sendout').textContent = await r.text();
}

async function poll(){
  const r = await fetch('/chat/messages/inbox?device_id='+encodeURIComponent(my.id)+'&limit=20');
  const arr = await r.json();
  const out=[];
  for(const m of arr.reverse()){
    try{
      const nonce = unb64(m.nonce_b64); const box = unb64(m.box_b64); const spk = unb64(m.sender_pubkey_b64);
      const plain = nacl.box.open(box, nonce, spk, my.sk);
      out.push({from:m.sender_id, text:(plain? new TextDecoder().decode(plain):'<decrypt failed>')});
      try{ await fetch('/chat/messages/'+encodeURIComponent(m.id)+'/read',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({read:true})}); }catch(_){ }
    }catch(e){ out.push({from:m.sender_id, text:'<error>'}); }
  }
  document.getElementById('inbox').textContent = JSON.stringify(out,null,2);
}
// Graphical QR (same mini generator used on Merchant page)
/* eslint-disable */
!function(o){function r(o){this.mode=n.MODE_8BIT_BYTE,this.data=o,this.parsedData=[];for(var r=0,l=this.data.length;r<l;r++){var t=[],h=this.data.charCodeAt(r);h>65536?(t[0]=240|(1835008&h)>>>18,t[1]=128|(258048&h)>>>12,t[2]=128|(4032&h)>>>6,t[3]=128|63&h):h>2048?(t[0]=224|(61440&h)>>>12,t[1]=128|(4032&h)>>>6,t[2]=128|63&h):h>128?(t[0]=192|(1984&h)>>>6,t[1]=128|63&h):t[0]=h,this.parsedData.push(t)}this.parsedData=Array.prototype.concat.apply([],this.parsedData),this.parsedData.length!=this.data.length&&(this.parsedData.unshift(191),this.parsedData.unshift(187),this.parsedData.unshift(239))}function l(o,r){this.typeNumber=o,this.errorCorrectLevel=r,this.modules=null,this.moduleCount=0,this.dataCache=null,this.dataList=[]}var n={PAD0:236,PAD1:17,MODE_8BIT_BYTE:4};r.prototype={getLength:function(){return this.parsedData.length},write:function(o){for(var r=0,l=this.parsedData.length;r<l;r++)o.put(this.parsedData[r],8)}},l.prototype={addData:function(o){this.dataList.push(new r(o)),this.dataCache=null},isDark:function(o,r){if(o<0||this.moduleCount<=o||r<0||this.moduleCount<=r)throw new Error(o+","+r);return this.modules[o][r]},getModuleCount:function(){return this.moduleCount},make:function(){this.makeImpl(!1,this.getBestMaskPattern())},makeImpl:function(o,r){this.moduleCount=21,this.modules=new Array(this.moduleCount);for(var l=0;l<this.moduleCount;l++){this.modules[l]=new Array(this.moduleCount);for(var n=0;n<this.moduleCount;n++)this.modules[l][n]=null}this.setupPositionProbePattern(0,0),this.setupPositionProbePattern(this.moduleCount-7,0),this.setupPositionProbePattern(0,this.moduleCount-7),this.mapData(this.createData(this.typeNumber,this.errorCorrectLevel,r),r)},setupPositionProbePattern:function(o,r){for(var l=-1;l<=7;l++)if(!(o+l<=-1||this.moduleCount<=o+l))for(var n=-1;n<=7;n++)r+n<=-1||this.moduleCount<=r+n||(this.modules[o+l][r+n]=l>=0&&l<=6&&(0==n||6==n)||n>=0&&n<=6&&(0==l||6==l)||l>=2&&l<=4&&n>=2&&n<=4)},getBestMaskPattern:function(){return 0},createData:function(o,r){for(var l=[],n=0;n<this.dataList.length;n++){var t=this.dataList[n];l.push(4),l.push(t.getLength()),l=l.concat(t.parsedData)}for(l.push(236),l.push(17),l.push(236),l.push(17);l.length<19;)l.push(0);return l.slice(0,19)},mapData:function(o,r){for(var l=0;l<this.moduleCount;l++)for(var n=0;n<this.moduleCount;n++)if(null===this.modules[l][n]){var t=!((l+n)%3);this.modules[l][n]=t}},createImgTag:function(o,r){o=o||2,r=r||0;var l=this.getModuleCount()*o+2*r,n=l,t='<img src="'+this.createDataURL(o,r)+'" width="'+l+'" height="'+n+'"/>';return t},createDataURL:function(o,r){o=o||2,r=r||0;var l=this.getModuleCount()*o+2*r,n=l,t=o,h=r,e=h,i=Math.round(255);for(var a="GIF89a",u=String.fromCharCode,d=a+u(0)+u(0)+u(0)+u(0)+"\x00\x00\xF7\x00\x00",s=0;s<16;s++){var c=s?0:i;d+=u(c)+u(c)+u(c)}d+="\x2C\x00\x00\x00\x00"+u(0)+u(0)+"\x00\x00\x00\x00\x02";for(var f=1;f<l;f++){var g="";for(var p=0;p<n;p++){var m=this.isDark(Math.floor((p-r)/o),Math.floor((f-h)/o))?0:1;g+=m?"\x01":"\x00"}d+=u(g.length)+g}return 'data:image/gif;base64,'+btoa(d)}};
function makeQR(text){ const qr = new l(1,0); qr.addData(text); qr.make(); const el=document.getElementById('qr'); el.innerHTML=qr.createImgTag(4,2); }
/* eslint-enable */
async function scanStart(){
  try{
    const el = document.getElementById('scanner');
    const html5QrCode = new Html5Qrcode(el.id);
    await html5QrCode.start({ facingMode: "environment" }, { fps: 10, qrbox: 200 }, (decodedText)=>{
      try{
        if(decodedText && decodedText.startsWith('CHAT|')){
          const parts = decodedText.split('|');
          const map={}; for(const p of parts.slice(1)){ const kv=p.split('='); if(kv.length==2) map[kv[0]]=kv[1]; }
          if(map['id'] && map['pk']){ peers[map['id']] = map['pk']; document.getElementById('peerid').value = map['id']; document.getElementById('peer').textContent = JSON.stringify({device_id:map['id'], public_key_b64:map['pk']},null,2); updatePeerFp(); html5QrCode.stop(); }
        }
      }catch(_){ }
    });
  }catch(e){ alert('scan error: '+e); }
}

// Fingerprints and verification
async function sha256(b){
  try{ const d = await crypto.subtle.digest('SHA-256', (b instanceof Uint8Array)? b : new TextEncoder().encode(b)); return new Uint8Array(d); }catch(_){ return null; }
}
function toHex(u8){ return Array.from(u8).map(x=>x.toString(16).padStart(2,'0')).join(''); }
async function computeFpB64(pkB64){ try{ const u = unb64(pkB64); const d = await sha256(u); if(d){ return toHex(d).slice(0,16); } }catch(_){ } return (pkB64||'').slice(0,16); }
async function updateMyFp(){ try{ const fp = await computeFpB64(b64(my.pk)); document.getElementById('myfp').textContent = fp; }catch(_){ } }
async function updatePeerFp(){ try{ const pid=(document.getElementById('peerid').value||'').trim(); const pkb64=peers[pid]; if(!pkb64){ return; } const fp=await computeFpB64(pkb64); document.getElementById('peerfp').textContent = fp; document.getElementById('verif').textContent = (isVerified(pid,fp)?'yes':'no'); }catch(_){ } }
function isVerified(pid, fp){ try{ return localStorage.getItem('verified_peer_'+pid) === fp; }catch(_){ return false; } }
async function markVerified(){ const pid=(document.getElementById('peerid').value||'').trim(); const pkb64=peers[pid]; if(!pid||!pkb64){ alert('resolve/scan peer first'); return; } const fp=await computeFpB64(pkb64); try{ localStorage.setItem('verified_peer_'+pid, fp); document.getElementById('verif').textContent='yes'; }catch(_){ } }

// WebSocket live inbox
function connectWS(){ try{ if(!my.id){ return; } if(ws && (ws.readyState===1||ws.readyState===0)){ return; }
  const base = (location.protocol==='https:'?'wss://':'ws://')+location.host;
  ws = new WebSocket(base+'/ws/chat/inbox?device_id='+encodeURIComponent(my.id));
  const live = document.getElementById('live');
  ws.onopen = ()=>{ if(live) live.textContent='connected'; };
  ws.onclose = ()=>{ if(live) live.textContent='disconnected'; };
  ws.onerror = ()=>{ if(live) live.textContent='error'; };
  ws.onmessage = async (ev)=>{
    try{
      const msg = JSON.parse(ev.data);
      if(msg && msg.type==='inbox' && Array.isArray(msg.messages)){
        const outEl = document.getElementById('inbox');
        const out = [];
        for(const m of msg.messages){
          try{
            const nonce = unb64(m.nonce_b64); const box = unb64(m.box_b64); const spk = unb64(m.sender_pubkey_b64);
            const plain = nacl.box.open(box, nonce, spk, my.sk);
            out.push({from:m.sender_id, text:(plain? new TextDecoder().decode(plain):'<decrypt failed>')});
            try{ await fetch('/chat/messages/'+encodeURIComponent(m.id)+'/read',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({read:true})}); }catch(_){ }
          }catch(e){ out.push({from:m.sender_id, text:'<error>'}); }
        }
        // append to existing
        try{ const prev = outEl.textContent? JSON.parse(outEl.textContent):[]; outEl.textContent = JSON.stringify(prev.concat(out), null, 2); }catch(_){ outEl.textContent = JSON.stringify(out, null, 2); }
      }
    }catch(_){ }
  };
}catch(_){ }
}
</script>
</body></html>
"""
    return HTMLResponse(content=html)


@app.get("/taxi/driver", response_class=HTMLResponse)
def taxi_driver_page():
    return _legacy_console_removed_page("Shamell · Taxi driver")
    html = """
<!doctype html>
<html><head><meta name=viewport content="width=device-width, initial-scale=1" />
<title>Taxi Driver Console</title>
<link rel="icon" href="/icons/taxi.svg" />
<style>
  body{font-family:sans-serif;margin:20px;max-width:760px;background:#ffffff;color:#000000;}
  input,button{font-size:14px;padding:6px;margin:4px 0}
  input{background:#ffffff;border:1px solid #cccccc;border-radius:4px;color:#000000}
  button{border:1px solid #cccccc;background:#f3f4f6;border-radius:4px;color:#000000;box-shadow:none}
  pre{background:#f5f5f5;padding:8px;white-space:pre-wrap;border-radius:4px;border:1px solid #dddddd}
</style>
</head><body>
<div style="position:sticky;top:0;z-index:10;background:#ffffff;padding:8px 10px;border-bottom:1px solid #dddddd;margin:0 0 12px 0;display:flex;align-items:center;gap:8px"><div style="flex:1;font-weight:600">Taxi Driver</div><small style="opacity:.8">Standalone</small></div>
<div>
  <h3>Register</h3>
  <input id=name placeholder="Name" />
  <input id=phone placeholder="Phone" />
  <input id=make placeholder="Vehicle make" />
  <input id=plate placeholder="Plate" />
  <button onclick="register()">Register</button>
  <pre id=regout></pre>
</div>
<div>
  <h3>Driver</h3>
  <input id=driver placeholder="driver_id" />
  <button onclick="saveDriver()">Save</button>
  <div>
    <input id=dwallet placeholder="driver wallet id" />
    <button onclick="setWallet()">Set wallet</button>
  </div>
  <button onclick="online()">Go online</button>
  <button onclick="offline()">Go offline</button>
  <pre id=dout></pre>
</div>
<div>
  <h3>Location</h3>
  <input id=lat placeholder="lat" />
  <input id=lon placeholder="lon" />
  <button onclick="updateLoc()">Update</button>
  <pre id=lout></pre>
</div>
<div>
  <h3>Active rides</h3>
  <button onclick="loadRides()">Refresh</button>
  <div>Live events: <span id=live>disconnected</span></div>
  <pre id=rides></pre>
</div>
<div>
  <h3>Ride Actions</h3>
  <input id=ride placeholder="ride_id" />
  <button onclick="accept()">Accept</button>
  <button onclick="start()">Start</button>
  <button onclick="complete()">Complete</button>
  <pre id=rout></pre>
</div>
<script>
function _did(){ let v=document.getElementById('driver').value; if(!v){ v=localStorage.getItem('driver_id')||''; document.getElementById('driver').value=v; } return v; }
function saveDriver(){ const v=document.getElementById('driver').value; localStorage.setItem('driver_id', v); }
async function register(){
  const body={name:gi('name'), phone:gi('phone'), vehicle_make:gi('make'), vehicle_plate:gi('plate')};
  const r=await fetch('/taxi/drivers',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)}); const j=await r.json(); document.getElementById('regout').textContent=JSON.stringify(j,null,2); document.getElementById('driver').value=j.id; saveDriver(); }
async function online(){ const id=_did(); const r=await fetch('/taxi/drivers/'+id+'/online',{method:'POST'}); document.getElementById('dout').textContent=await r.text(); }
async function setWallet(){ const id=_did(); const w=gi('dwallet'); const r=await fetch('/taxi/drivers/'+id+'/wallet',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({wallet_id:w})}); document.getElementById('dout').textContent=await r.text(); }
async function offline(){ const id=_did(); const r=await fetch('/taxi/drivers/'+id+'/offline',{method:'POST'}); document.getElementById('dout').textContent=await r.text(); }
async function updateLoc(){ const id=_did(); const body={lat:parseFloat(gi('lat')),lon:parseFloat(gi('lon'))}; const r=await fetch('/taxi/drivers/'+id+'/location',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)}); document.getElementById('lout').textContent=await r.text(); }
async function loadRides(){ const id=_did(); const r=await fetch('/taxi/drivers/'+id+'/rides?limit=10'); const j=await r.json(); document.getElementById('rides').textContent=JSON.stringify(j,null,2); }
async function accept(){ const id=_did(); const ride=gi('ride'); const r=await fetch('/taxi/rides/'+ride+'/accept?driver_id='+encodeURIComponent(id),{method:'POST'}); document.getElementById('rout').textContent=await r.text(); }
async function start(){ const id=_did(); const ride=gi('ride'); const r=await fetch('/taxi/rides/'+ride+'/start?driver_id='+encodeURIComponent(id),{method:'POST'}); document.getElementById('rout').textContent=await r.text(); }
async function complete(){ const id=_did(); const ride=gi('ride'); const r=await fetch('/taxi/rides/'+ride+'/complete?driver_id='+encodeURIComponent(id),{method:'POST'}); document.getElementById('rout').textContent=await r.text(); }
function gi(id){ return (document.getElementById(id).value||'').trim(); }
document.getElementById('driver').value=localStorage.getItem('driver_id')||'';
try{
  const drv = localStorage.getItem('driver_id')||'';
  if(drv){
    const es = new EventSource('/taxi/driver/events?driver_id='+encodeURIComponent(drv));
    es.onopen = ()=>{ document.getElementById('live').textContent='connected'; };
    es.onmessage = (ev)=>{
      try{ const j=JSON.parse(ev.data||'{}'); if(j.type==='rides'){ document.getElementById('rides').textContent = JSON.stringify(j.rides,null,2); } }catch(_){ }
    };
    es.onerror = ()=>{ document.getElementById('live').textContent='reconnecting'; };
  }
}catch(_){ }
</script>
</body></html>
"""
    return HTMLResponse(content=html)


@app.get("/taxi/rider", response_class=HTMLResponse)
def taxi_rider_page():
    return _legacy_console_removed_page("Shamell · Taxi rider")
    html = """
<!doctype html>
<html><head><meta name=viewport content="width=device-width, initial-scale=1" />
<title>Taxi Rider Console</title>
<link rel="icon" href="/icons/taxi.svg" />
<style>
  body{font-family:sans-serif;margin:20px;max-width:760px;background:#ffffff;color:#000000;}
  input,button{font-size:14px;padding:6px;margin:4px 0}
  input{background:#ffffff;border:1px solid #cccccc;border-radius:4px;color:#000000}
  button{border:1px solid #cccccc;background:#f3f4f6;border-radius:4px;color:#000000;box-shadow:none}
  pre{background:#f5f5f5;padding:8px;white-space:pre-wrap;border-radius:4px;border:1px solid #dddddd}
</style>
</head><body>
<div style="position:sticky;top:-12px;z-index:10;backdrop-filter:blur(12px);background:rgba(255,255,255,.08);padding:8px 10px;border-radius:14px;border:1px solid rgba(255,255,255,.2);margin:-8px 0 12px 0;display:flex;align-items:center;gap:8px"><div style="flex:1;font-weight:600">Taxi Rider</div><small style="opacity:.8">Standalone</small></div>
<div>
  <h3>Request ride</h3>
  <input id=phone placeholder="Phone (optional)" />
  <input id=rwallet placeholder="Rider wallet id (optional)" />
  <input id=plat placeholder="pickup lat" />
  <input id=plon placeholder="pickup lon" />
  <input id=dlat placeholder="drop lat" />
  <input id=dlon placeholder="drop lon" />
  <div>
    <button onclick="quoteRide()">Quote (fare/ETA)</button>
    <pre id=qout></pre>
  </div>
  <button onclick="req()">Request</button>
  <button onclick="bookpay()">Book & Pay</button>
  <pre id=reqout></pre>
</div>
<div>
  <h3>Ride status</h3>
  <input id=ride placeholder="ride_id" />
  <button onclick="status()">Status</button>
  <button onclick="cancel()">Cancel</button>
  <pre id=rout></pre>
</div>
<script>
async function req(){
  const body={rider_phone:gi('phone')||null, rider_wallet_id:gi('rwallet')||null, pickup_lat:parseFloat(gi('plat')), pickup_lon:parseFloat(gi('plon')), dropoff_lat:parseFloat(gi('dlat')), dropoff_lon:parseFloat(gi('dlon'))};
  const r=await fetch('/taxi/rides/request',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)}); const j=await r.json(); document.getElementById('reqout').textContent=JSON.stringify(j,null,2); document.getElementById('ride').value=j.id; }
async function quoteRide(){
  const body={pickup_lat:parseFloat(gi('plat')), pickup_lon:parseFloat(gi('plon')), dropoff_lat:parseFloat(gi('dlat')), dropoff_lon:parseFloat(gi('dlon'))};
  const r=await fetch('/taxi/rides/quote',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)});
  document.getElementById('qout').textContent=await r.text();
}
async function bookpay(){
  const body={rider_phone:gi('phone')||null, rider_wallet_id:gi('rwallet')||null, pickup_lat:parseFloat(gi('plat')), pickup_lon:parseFloat(gi('plon')), dropoff_lat:parseFloat(gi('dlat')), dropoff_lon:parseFloat(gi('dlon'))};
  const r=await fetch('/taxi/rides/book_pay',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)});
  const t=await r.text(); document.getElementById('reqout').textContent=t; try{ const j=JSON.parse(t); document.getElementById('ride').value=j.id; }catch(_){ }
}
async function status(){ const id=gi('ride'); const r=await fetch('/taxi/rides/'+id); document.getElementById('rout').textContent=await r.text(); }
async function cancel(){ const id=gi('ride'); const r=await fetch('/taxi/rides/'+id+'/cancel',{method:'POST'}); document.getElementById('rout').textContent=await r.text(); }
function gi(id){ return (document.getElementById(id).value||'').trim(); }
</script>
</body></html>
"""
    return HTMLResponse(content=html)


@app.post("/taxi/rides/quote")
async def taxi_quote(req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        if _use_taxi_internal():
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                req_model = _TaxiPreQuoteReq(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            return _call_taxi(
                _taxi_pre_quote,
                need_session=False,
                request_body=None,
                inject_internal=False,
                req=req_model,
            )
        r = httpx.post(_taxi_url("/rides/quote"), json=body, timeout=10)
        return r.json() if r.headers.get("content-type",""
        ).startswith("application/json") else {"raw": r.text, "status_code": r.status_code}
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/taxi/rides/book_pay")
async def taxi_book_pay(req: Request):
    phone = _auth_phone(req)
    env_test = _ENV_LOWER == "test"
    # Backend-side enrichment: rider phone from session; rider wallet via Payments
    try:
        body = await req.json()
    except Exception:
        body = {}
    if not isinstance(body, dict):
        body = {}
    # Add idempotency header passthrough
    headers = {}
    try:
        ikey = req.headers.get("Idempotency-Key")
    except Exception:
        ikey = None
    if ikey:
        headers["Idempotency-Key"] = ikey
    # Fill rider phone from session if absent (or, in ENV=test, accept it from body)
    try:
        rider_phone = (body.get('rider_phone') or '').strip()
    except Exception:
        rider_phone = ''
    if not rider_phone:
        if not phone and env_test:
            # In test mode allow phone to come solely from payload
            raise HTTPException(status_code=400, detail="rider_phone required in body")
        if not phone:
            raise HTTPException(status_code=401, detail="unauthorized")
        body['rider_phone'] = phone
        rider_phone = phone
    # Fill rider wallet id via Payments if absent
    # In ENV=test we also allow resolving via rider_phone when no session phone is present.
    lookup_phone = phone or rider_phone
    user_wallet = _resolve_wallet_id_for_phone(lookup_phone)
    if not user_wallet:
        raise HTTPException(status_code=400, detail="wallet not found for user")
    try:
        rider_wallet = (body.get('rider_wallet_id') or '').strip()
    except Exception:
        rider_wallet = ''
    if rider_wallet and rider_wallet != user_wallet:
        raise HTTPException(status_code=403, detail="wallet does not belong to user")
    body['rider_wallet_id'] = user_wallet
    try:
        if _use_taxi_internal():
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                req_model = _TaxiRideRequest(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            return _call_taxi(
                _taxi_book_and_pay,
                need_session=True,
                request_body=None,
                inject_internal=True,
                req=req_model,
                idempotency_key=ikey,
            )
        r = httpx.post(_taxi_url("/rides/book_pay"), json=body, headers=headers, timeout=15)
        return r.json() if r.headers.get("content-type",""
        ).startswith("application/json") else {"raw": r.text, "status_code": r.status_code}
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/taxi/admin", response_class=HTMLResponse)
def taxi_admin_page():
    # Legacy HTML admin console for Taxi has been removed.
    return _legacy_console_removed_page("Shamell · Taxi admin")


@app.get("/taxi/events")
async def taxi_events(request: Request):
    async def gen():
        while True:
            if await request.is_disconnected():
                break
            try:
                drivers = []
                rides = []
                if TAXI_BASE:
                    dr = httpx.get(_taxi_url("/drivers"), params={"status": "online", "limit": 200}, timeout=10)
                    rr = httpx.get(_taxi_url("/rides"), params={"status": "requested", "limit": 200}, timeout=10)
                    drivers = dr.json() if dr.status_code == 200 else []
                    rides = rr.json() if rr.status_code == 200 else []
                payload = {"type": "snapshot", "drivers": drivers, "rides": rides, "ts": int(asyncio.get_event_loop().time()*1000)}
                yield f"data: {_json.dumps(payload)}\n\n"
            except Exception as e:
                err = {"type": "error", "error": str(e)}
                yield f"data: {_json.dumps(err)}\n\n"
            await asyncio.sleep(5)
    return StreamingResponse(gen(), media_type="text/event-stream")


@app.get("/taxi/driver/events")
async def taxi_driver_events(driver_id: str, request: Request):
    async def gen():
        last_ids = set()
        while True:
            if await request.is_disconnected():
                break
            try:
                rides = []
                if TAXI_BASE:
                    rr = httpx.get(_taxi_url(f"/drivers/{driver_id}/rides"), params={"limit": 20}, timeout=10)
                    rides = rr.json() if rr.status_code == 200 else []
                # only emit if changed
                ids = {r.get('id') for r in rides if r.get('status') in ('assigned','accepted','on_trip')}
                if ids != last_ids:
                    payload = {"type":"rides","driver_id":driver_id,"active_ids":list(ids),"rides":rides}
                    yield f"data: {_json.dumps(payload)}\n\n"
                    last_ids = ids
            except Exception as e:
                err = {"type":"error","error":str(e)}
                yield f"data: {_json.dumps(err)}\n\n"
            await asyncio.sleep(5)
    return StreamingResponse(gen(), media_type="text/event-stream")


@app.websocket("/ws/taxi/driver")
async def taxi_driver_ws(ws: WebSocket):
    await ws.accept()
    try:
        params = dict(ws.query_params)
        driver_id = params.get('driver_id')
        last_ids = set()
        while True:
            try:
                rides = []
                if TAXI_BASE and driver_id:
                    rr = httpx.get(_taxi_url(f"/drivers/{driver_id}/rides"), params={"limit": 20}, timeout=10)
                    rides = rr.json() if rr.status_code == 200 else []
                ids = {r.get('id') for r in rides if r.get('status') in ('assigned','accepted','on_trip')}
                if ids != last_ids:
                    await ws.send_json({"type":"rides","driver_id":driver_id,"active_ids":list(ids),"rides":rides})
                    last_ids = ids
                await asyncio.sleep(5)
            except Exception as e:
                await ws.send_json({"type":"error","error":str(e)})
                await asyncio.sleep(5)
    except WebSocketDisconnect:
        return
@app.get("/favicon.ico")
def favicon():
    svg = """
<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64'>
  <defs>
    <linearGradient id='g' x1='0' y1='0' x2='1' y2='1'>
      <stop offset='0%' stop-color='#60a5fa'/>
      <stop offset='100%' stop-color='#10b981'/>
    </linearGradient>
    <filter id='f' x='-50%' y='-50%' width='200%' height='200%'>
      <feGaussianBlur stdDeviation='2' />
    </filter>
  </defs>
  <rect x='6' y='6' width='52' height='52' rx='14' fill='url(#g)'/>
  <circle cx='32' cy='20' r='10' fill='white' fill-opacity='.35' filter='url(#f)'/>
  <text x='32' y='40' font-size='16' text-anchor='middle' fill='white' font-family='sans-serif' font-weight='700'>SH꩜</text>
</svg>
"""
    return Response(content=svg, media_type="image/svg+xml")


_BRAND_DIR = Path(__file__).resolve().parent / "branding"


@app.get("/brand/shamell.svg")
def brand_shamell_svg():
    path = _BRAND_DIR / "shamell-logo.svg"
    if not path.exists():
        raise HTTPException(status_code=404, detail="logo not found")
    return FileResponse(path, media_type="image/svg+xml")


@app.get("/brand/shamell.png")
def brand_shamell_png():
    path = _BRAND_DIR / "shamell-logo.png"
    if not path.exists():
        raise HTTPException(status_code=404, detail="logo not found")
    return FileResponse(path, media_type="image/png")


@app.get("/icons/{name}.svg")
def module_icon(name: str):
    name = (name or "").lower()
    # Choose gradient colors and label per module
    gradients = {
        "payments": ("#6366f1", "#22c55e", "PA"),
        "merchant": ("#8b5cf6", "#06b6d4", "ME"),
        "taxi": ("#f59e0b", "#ef4444", "TX"),
        "bus": ("#0ea5e9", "#22d3ee", "BU"),
        "carmarket": ("#3b82f6", "#22d3ee", "CM"),
        "carrental": ("#3b82f6", "#22c55e", "CR"),
        "food": ("#ef4444", "#f59e0b", "FD"),
        "realestate": ("#10b981", "#06b6d4", "RE"),
        "stays": ("#14b8a6", "#6366f1", "ST"),
        "freight": ("#f59e0b", "#84cc16", "FR"),
        "chat": ("#06b6d4", "#8b5cf6", "CH"),
        "agriculture": ("#10b981", "#84cc16", "AG"),
        "commerce": ("#0ea5e9", "#6366f1", "CO"),
        "doctors": ("#f43f5e", "#06b6d4", "DR"),
        "flights": ("#38bdf8", "#22d3ee", "FL"),
        "jobs": ("#8b5cf6", "#0ea5e9", "JB"),
        "livestock": ("#84cc16", "#22c55e", "LS"),
        "default": ("#60a5fa", "#10b981", "SH꩜"),
    }
    c1, c2, label = gradients.get(name, gradients["default"])
    svg = f"""
<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64'>
  <defs>
    <linearGradient id='g' x1='0' y1='0' x2='1' y2='1'>
      <stop offset='0%' stop-color='{c1}'/>
      <stop offset='100%' stop-color='{c2}'/>
    </linearGradient>
    <filter id='f' x='-50%' y='-50%' width='200%' height='200%'>
      <feGaussianBlur stdDeviation='2' />
    </filter>
  </defs>
  <rect x='6' y='6' width='52' height='52' rx='14' fill='url(#g)'/>
  <circle cx='24' cy='20' r='8' fill='white' fill-opacity='.35' filter='url(#f)'/>
  <text x='32' y='40' font-size='16' text-anchor='middle' fill='white' font-family='sans-serif' font-weight='700'>{label}</text>
  <title>{name}</title>
  <desc>SuperApp icon for {name}</desc>
  <metadata>module:{name}</metadata>
  <style>@media(prefers-color-scheme:dark){{text{{fill:#fff}}}}</style>
  <rect width='64' height='64' fill='transparent'/>
</svg>
"""
    return Response(content=svg, media_type="image/svg+xml")


@app.get("/icons/{name}-{size}.png")
def module_icon_png(name: str, size: int):
    if Image is None:
        raise HTTPException(status_code=500, detail="Pillow not available")
    name = (name or "").lower()
    sizes_allowed = {192, 512}
    if size not in sizes_allowed:
        raise HTTPException(status_code=400, detail="size must be 192 or 512")
    gradients = {
        "payments": ("#6366f1", "#22c55e", "PA"),
        "merchant": ("#8b5cf6", "#06b6d4", "ME"),
        "taxi": ("#f59e0b", "#ef4444", "TX"),
        "bus": ("#0ea5e9", "#22d3ee", "BU"),
        "carmarket": ("#3b82f6", "#22d3ee", "CM"),
        "carrental": ("#3b82f6", "#22c55e", "CR"),
        "food": ("#ef4444", "#f59e0b", "FD"),
        "realestate": ("#10b981", "#06b6d4", "RE"),
        "stays": ("#14b8a6", "#6366f1", "ST"),
        "freight": ("#f59e0b", "#84cc16", "FR"),
        "chat": ("#06b6d4", "#8b5cf6", "CH"),
        "agriculture": ("#10b981", "#84cc16", "AG"),
        "commerce": ("#0ea5e9", "#6366f1", "CO"),
        "doctors": ("#f43f5e", "#06b6d4", "DR"),
        "flights": ("#38bdf8", "#22d3ee", "FL"),
        "jobs": ("#8b5cf6", "#0ea5e9", "JB"),
        "livestock": ("#84cc16", "#22c55e", "LS"),
        "default": ("#60a5fa", "#10b981", "SH꩜"),
    }
    c1, c2, label = gradients.get(name, gradients["default"])
    # Build gradient background clipped to rounded rect
    s = size
    grad = Image.new("RGBA", (s, s))
    # simple diagonal gradient
    p1 = tuple(int(c1.strip('#')[i:i+2],16) for i in (0,2,4))
    p2 = tuple(int(c2.strip('#')[i:i+2],16) for i in (0,2,4))
    for y in range(s):
        t = y/(s-1)
        r = int(p1[0]*(1-t) + p2[0]*t)
        g = int(p1[1]*(1-t) + p2[1]*t)
        b = int(p1[2]*(1-t) + p2[2]*t)
        Image.Draw = ImageDraw.Draw  # type: ignore
        ImageDraw.Draw(grad).line([(0,y),(s,y)], fill=(r,g,b,255))
    mask = Image.new("L", (s, s), 0)
    drawm = ImageDraw.Draw(mask)
    rr = int(0.22*s)
    drawm.rounded_rectangle([int(0.09*s), int(0.09*s), int(0.91*s), int(0.91*s)], radius=rr, fill=255)
    out = Image.new("RGBA", (s, s), (0,0,0,0))
    out = Image.composite(grad, out, mask)
    # highlight circle
    draw = ImageDraw.Draw(out)
    cx, cy = int(0.38*s), int(0.32*s)
    r = int(0.16*s)
    draw.ellipse([cx-r, cy-r, cx+r, cy+r], fill=(255,255,255,90))
    # label
    try:
        font_path = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
        font_size = int(0.28*s)
        font = ImageFont.truetype(font_path, font_size)
        tw, th = draw.textsize(label, font=font)
        draw.text(( (s-tw)//2, int(0.62*s)-th//2 ), label, font=font, fill=(255,255,255,255))
    except Exception:
        pass
    buf = BytesIO()
    out.save(buf, format="PNG")
    return Response(content=buf.getvalue(), media_type="image/png")
@app.post("/stays/operators/login")
async def stays_operator_login(req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        if _use_stays_internal():
            if not _STAYS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="stays internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                lreq = _StaysOperatorLoginReq(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _stays_internal_session() as s:
                return _stays_operator_login(req=lreq, s=s)
        r = httpx.post(_stays_url("/operators/login"), json=body, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/stays/operators/request_code")
async def stays_operator_request_code(req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        if _use_stays_internal():
            if not _STAYS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="stays internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                creq = _StaysOperatorCodeReq(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            return _stays_operators_request_code(req=creq)
        r = httpx.post(_stays_url("/operators/request_code"), json=body, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/stays/operators/verify")
async def stays_operator_verify(req: Request):
    try:
        body = await req.json()
    except Exception:
        body = None
    try:
        if _use_stays_internal():
            if not _STAYS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="stays internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                vreq = _StaysOperatorVerifyReq(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _stays_internal_session() as s:
                return _stays_operators_verify(req=vreq, s=s)
        r = httpx.post(_stays_url("/operators/verify"), json=body, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))

# --- Stays Operator PMS proxies ---
@app.post("/stays/operators/{op_id}/room_types")
async def stays_operator_create_room_type(op_id: int, req: Request):
    try:
        try: body = await req.json()
        except Exception: body = None
        headers = {}
        try:
            auth = req.headers.get('authorization')
            if auth: headers['Authorization'] = auth
        except Exception: pass
        r = httpx.post(_stays_url(f"/operators/{op_id}/room_types"), json=body, headers=headers, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))

@app.get("/stays/operators/{op_id}/room_types")
def stays_operator_list_room_types(op_id: int, req: Request):
    try:
        headers = {}
        try:
            auth = req.headers.get('authorization')
            if auth: headers['Authorization'] = auth
        except Exception: pass
        params = {}
        try:
            pid = req.query_params.get('property_id')
            if pid: params['property_id']=pid
        except Exception:
            pass
        r = httpx.get(_stays_url(f"/operators/{op_id}/room_types"), params=params, headers=headers, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))

@app.patch("/stays/operators/{op_id}/room_types/{rtid}")
async def stays_operator_update_room_type(op_id: int, rtid: int, req: Request):
    try:
        try: body = await req.json()
        except Exception: body = None
        headers = {}
        try:
            auth = req.headers.get('authorization')
            if auth: headers['Authorization'] = auth
        except Exception: pass
        r = httpx.patch(_stays_url(f"/operators/{op_id}/room_types/{rtid}"), json=body, headers=headers, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))

@app.post("/stays/operators/{op_id}/rooms")
async def stays_operator_create_room(op_id: int, req: Request):
    try:
        try: body = await req.json()
        except Exception: body = None
        headers = {}
        try:
            auth = req.headers.get('authorization')
            if auth: headers['Authorization'] = auth
        except Exception: pass
        r = httpx.post(_stays_url(f"/operators/{op_id}/rooms"), json=body, headers=headers, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))

@app.get("/stays/operators/{op_id}/rooms")
def stays_operator_list_rooms(op_id: int, req: Request):
    try:
        headers = {}
        try:
            auth = req.headers.get('authorization')
            if auth: headers['Authorization'] = auth
        except Exception: pass
        params = {}
        try:
            pid = req.query_params.get('property_id')
            if pid: params['property_id']=pid
        except Exception:
            pass
        r = httpx.get(_stays_url(f"/operators/{op_id}/rooms"), params=params, headers=headers, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))

@app.patch("/stays/operators/{op_id}/rooms/{rid}")
async def stays_operator_update_room(op_id: int, rid: int, req: Request):
    try:
        try: body = await req.json()
        except Exception: body = None
        headers = {}
        try:
            auth = req.headers.get('authorization')
            if auth: headers['Authorization'] = auth
        except Exception: pass
        r = httpx.patch(_stays_url(f"/operators/{op_id}/rooms/{rid}"), json=body, headers=headers, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))

@app.get("/stays/operators/{op_id}/room_types/{rtid}/rates")
def stays_operator_get_room_type_rates(op_id: int, rtid: int, req: Request, frm: str, to: str):
    try:
        headers: dict[str, str] = {}
        try:
            auth = req.headers.get('authorization')
            if auth:
                headers['Authorization'] = auth
        except Exception:
            pass
        params = {"frm": frm, "to": to}
        if _use_stays_internal():
            if not _STAYS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="stays internal not available")
            with _stays_internal_session() as s:
                return _stays_get_room_type_rates(op_id=op_id, rtid=rtid, request=req, frm=frm, to=to, s=s)
        r = httpx.get(_stays_url(f"/operators/{op_id}/room_types/{rtid}/rates"), params=params, headers=headers, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))

@app.post("/stays/operators/{op_id}/room_types/{rtid}/rates")
async def stays_operator_upsert_room_type_rates(op_id: int, rtid: int, req: Request):
    try:
        try:
            body = await req.json()
        except Exception:
            body = None
        headers: dict[str, str] = {}
        try:
            auth = req.headers.get('authorization')
            if auth:
                headers['Authorization'] = auth
        except Exception:
            pass
        if _use_stays_internal():
            if not _STAYS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="stays internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                dreq = _StaysDayRatesUpsert(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _stays_internal_session() as s:
                return _stays_upsert_room_type_rates(op_id=op_id, rtid=rtid, req=dreq, request=req, s=s)
        r = httpx.post(_stays_url(f"/operators/{op_id}/room_types/{rtid}/rates"), json=body, headers=headers, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))
@app.get("/stays/operators/{op_id}/listings/search")
def stays_operator_listings_search(op_id: int, req: Request, limit: int = 50, offset: int = 0, q: str = "", city: str = "", type: str = "", sort_by: str = "created_at", order: str = "desc"):
    try:
        headers: dict[str, str] = {}
        try:
            auth = req.headers.get('authorization')
            if auth:
                headers['Authorization'] = auth
        except Exception:
            pass
        params = {"limit": max(1, min(limit, 200)), "offset": max(0, offset), "sort_by": sort_by, "order": order}
        if q:
            params['q'] = q
        if city:
            params['city'] = city
        if type:
            params['type'] = type
        property_id = None
        try:
            pid = req.query_params.get('property_id')
            if pid:
                params['property_id'] = pid
                property_id = int(pid)
        except Exception:
            property_id = None
        if _use_stays_internal():
            if not _STAYS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="stays internal not available")
            with _stays_internal_session() as s:
                return _stays_operator_listings_search(
                    op_id=op_id,
                    request=req,
                    limit=limit,
                    offset=offset,
                    q=q,
                    city=city,
                    type=type,
                    property_id=property_id,
                    sort_by=sort_by,
                    order=order,
                    s=s,
                )
        r = httpx.get(_stays_url(f"/operators/{op_id}/listings/search"), params=params, headers=headers, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))

# --- Stays: Properties & Staff ---
@app.get("/stays/operators/{op_id}/properties")
def stays_list_properties(op_id: int, req: Request):
    try:
        headers: dict[str, str] = {}
        try:
            auth = req.headers.get('authorization')
            if auth:
                headers['Authorization'] = auth
        except Exception:
            pass
        if _use_stays_internal():
            if not _STAYS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="stays internal not available")
            with _stays_internal_session() as s:
                return _stays_list_properties(op_id=op_id, request=req, s=s)
        r = httpx.get(_stays_url(f"/operators/{op_id}/properties"), headers=headers, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))

@app.post("/stays/operators/{op_id}/properties")
async def stays_create_property(op_id: int, req: Request):
    try:
        try:
            body = await req.json()
        except Exception:
            body = None
        headers: dict[str, str] = {}
        try:
            auth = req.headers.get('authorization')
            if auth:
                headers['Authorization'] = auth
        except Exception:
            pass
        if _use_stays_internal():
            if not _STAYS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="stays internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                preq = _StaysPropertyCreate(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _stays_internal_session() as s:
                return _stays_create_property(op_id=op_id, req=preq, request=req, s=s)
        r = httpx.post(_stays_url(f"/operators/{op_id}/properties"), json=body, headers=headers, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))

@app.get("/stays/operators/{op_id}/staff")
def stays_list_staff(op_id: int, req: Request):
    try:
        headers: dict[str, str] = {}
        try:
            auth = req.headers.get('authorization')
            if auth:
                headers['Authorization'] = auth
        except Exception:
            pass
        params: dict[str, object] = {}
        active = None
        try:
            a = req.query_params.get('active')
            if a is not None:
                params['active'] = a
                active = int(a)
        except Exception:
            active = None
        q = ""
        try:
            q = req.query_params.get('q') or ""
            if q:
                params['q'] = q
        except Exception:
            q = ""
        role = ""
        try:
            role = req.query_params.get('role') or ""
            if role:
                params['role'] = role
        except Exception:
            role = ""
        if _use_stays_internal():
            if not _STAYS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="stays internal not available")
            with _stays_internal_session() as s:
                return _stays_list_staff(op_id=op_id, request=req, active=active, q=q, role=role, s=s)
        r = httpx.get(_stays_url(f"/operators/{op_id}/staff"), params=params, headers=headers, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))

@app.post("/stays/operators/{op_id}/staff")
async def stays_create_staff(op_id: int, req: Request):
    try:
        try:
            body = await req.json()
        except Exception:
            body = None
        headers: dict[str, str] = {}
        try:
            auth = req.headers.get('authorization')
            if auth:
                headers['Authorization'] = auth
        except Exception:
            pass
        if _use_stays_internal():
            if not _STAYS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="stays internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                sreq = _StaysStaffCreate(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _stays_internal_session() as s:
                return _stays_create_staff(op_id=op_id, req=sreq, request=req, s=s)
        r = httpx.post(_stays_url(f"/operators/{op_id}/staff"), json=body, headers=headers, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))

@app.patch("/stays/operators/{op_id}/staff/{sid}")
async def stays_update_staff(op_id: int, sid: int, req: Request):
    try:
        try:
            body = await req.json()
        except Exception:
            body = None
        headers: dict[str, str] = {}
        try:
            auth = req.headers.get('authorization')
            if auth:
                headers['Authorization'] = auth
        except Exception:
            pass
        if _use_stays_internal():
            if not _STAYS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="stays internal not available")
            data = body or {}
            if not isinstance(data, dict):
                data = {}
            try:
                ureq = _StaysStaffUpdate(**data)
            except Exception as e:
                raise HTTPException(status_code=400, detail=str(e))
            with _stays_internal_session() as s:
                return _stays_update_staff(op_id=op_id, sid=sid, req=ureq, request=req, s=s)
        r = httpx.patch(_stays_url(f"/operators/{op_id}/staff/{sid}"), json=body, headers=headers, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))

@app.delete("/stays/operators/{op_id}/staff/{sid}")
def stays_deactivate_staff(op_id: int, sid: int, req: Request):
    try:
        headers: dict[str, str] = {}
        try:
            auth = req.headers.get('authorization')
            if auth:
                headers['Authorization'] = auth
        except Exception:
            pass
        if _use_stays_internal():
            if not _STAYS_INTERNAL_AVAILABLE:
                raise HTTPException(status_code=500, detail="stays internal not available")
            with _stays_internal_session() as s:
                return _stays_deactivate_staff(op_id=op_id, sid=sid, request=req, s=s)
        r = httpx.delete(_stays_url(f"/operators/{op_id}/staff/{sid}"), headers=headers, timeout=10)
        return r.json()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))
def _to_cents(x) -> int:
    try:
        if isinstance(x, (int, float)):
            return round(float(x) * 100)
        s = str(x).strip().replace(',', '.')
        # strip non-numeric except dot and minus
        keep = ''.join(ch for ch in s if (ch.isdigit() or ch in '.-'))
        return round(float(keep) * 100)
    except Exception:
        return 0

def _normalize_amount(body: dict | None) -> dict | None:
    if not isinstance(body, dict):
        return body
    # Accept amount in SYP major units and convert to amount_cents for upstream
    if 'amount_cents' not in body:
        if 'amount' in body and body['amount'] not in (None, ''):
            body['amount_cents'] = _to_cents(body['amount'])
        elif 'amount_syp' in body and body['amount_syp'] not in (None, ''):
            body['amount_cents'] = _to_cents(body['amount_syp'])
    return body
