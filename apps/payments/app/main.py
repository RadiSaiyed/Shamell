from fastapi import FastAPI
import os


def _env_or(key: str, default: str) -> str:
    v = os.getenv(key)
    return v if v is not None else default


app = FastAPI(title="Payments API (placeholder)", version="0.0.1")


@app.get("/health")
def health():
    return {"status": "ok", "env": _env_or("ENV", "dev")}

