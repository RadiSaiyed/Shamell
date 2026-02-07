import os
from fastapi import FastAPI


def add_standard_health(app: FastAPI, env_key: str = "ENV"):
    @app.get("/health")
    def _health():
        return {
            "status": "ok",
            "env": os.getenv(env_key, "dev"),
            "service": app.title,
            "version": getattr(app, "version", None),
        }

