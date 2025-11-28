"""
Convenience entrypoint to run the Shamell monolith with uvicorn.

Example:
  python -m apps.monolith --reload
"""
import uvicorn
import os


def main() -> None:
    reload = os.getenv("MONOLITH_RELOAD", "false").lower() == "true"
    host = os.getenv("MONOLITH_HOST", "0.0.0.0")
    port = int(os.getenv("MONOLITH_PORT", "8000"))
    uvicorn.run(
        "apps.monolith.app.main:app",
        host=host,
        port=port,
        reload=reload,
        reload_dirs=["apps"] if reload else None,
    )


if __name__ == "__main__":
    main()
