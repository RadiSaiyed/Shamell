"""
Compatibility shim.

Historically, the BFF lived in this module and the runtime/test suite imported
`apps.bff.app.main` directly.

The implementation was moved to `apps.bff.app.bff` to keep this entrypoint
small and maintainable, while preserving the import path.
"""

from __future__ import annotations

import sys as _sys

from . import bff as _bff

# Expose the FastAPI app for uvicorn (`apps.bff.app.main:app`).
app = _bff.app

# Make `import apps.bff.app.main as bff` return the real implementation module,
# so tests/monkeypatching continue to work on the same objects.
_sys.modules[__name__] = _bff

