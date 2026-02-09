from __future__ import annotations

from pathlib import Path

# The repository contains additional domain services under `NonWeChat/apps/*`.
# Keep them importable as `apps.*` so tests and internal-mode imports can work
# without duplicating code or requiring external services.
try:
    _here = Path(__file__).resolve().parent
    _nonwechat_apps = _here.parent / "NonWeChat" / "apps"
    if _nonwechat_apps.exists():
        __path__.append(str(_nonwechat_apps))  # type: ignore[name-defined]
except Exception:
    # Import-time path tweaks must never break the app.
    pass
