from __future__ import annotations

"""
App services live under `apps/*` (namespace package).

This repository previously contained legacy services under `NonWeChat/apps/*`
and extended `apps.__path__` to keep them importable as `apps.*`.
Those legacy modules were removed; keep this package minimal and explicit.
"""
