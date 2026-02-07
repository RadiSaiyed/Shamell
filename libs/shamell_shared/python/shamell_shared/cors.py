from __future__ import annotations

from fastapi.middleware.cors import CORSMiddleware


def configure_cors(app, allowed: str | None):
    raw_origins = [o.strip() for o in (allowed or "").split(",") if o.strip()]
    if not raw_origins:
        # Safe local default for development when ALLOWED_ORIGINS is missing.
        raw_origins = ["http://localhost:5173", "http://127.0.0.1:5173"]

    if "*" in raw_origins:
        # Wildcard origins must not be combined with credentialed requests.
        origins = ["*"]
        allow_credentials = False
    else:
        origins = raw_origins
        allow_credentials = True

    app.add_middleware(
        CORSMiddleware,
        allow_origins=origins,
        allow_credentials=allow_credentials,
        allow_methods=["*"],
        allow_headers=["*"],
    )
