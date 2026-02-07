from __future__ import annotations

from fastapi.middleware.cors import CORSMiddleware


def configure_cors(app, allowed: str | None):
    origins = [o.strip() for o in (allowed or "").split(",") if o.strip()] or ["*"]
    app.add_middleware(
        CORSMiddleware,
        allow_origins=origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
