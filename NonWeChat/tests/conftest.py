import os
from typing import Dict, List

import pytest
from fastapi.testclient import TestClient

os.environ.setdefault("ENV", "test")
os.environ.setdefault("MONOLITH_MODE", "1")


@pytest.fixture(scope="session")
def app():
    """
    Import the monolith FastAPI app once per test session.
    """
    from apps.monolith.app.main import app as monolith_app

    return monolith_app


@pytest.fixture()
def client(app):
    """
    Synchronous TestClient for calling the BFF/monolith.
    """
    return TestClient(app)


class _DummyAuth:
    """
    Helper to simulate authenticated requests by injecting a phone header.
    """

    def __init__(self, phone: str):
        self.phone = phone

    def headers(self) -> Dict[str, str]:
        # For tests we use a dedicated header that is only
        # respected when ENV=test inside the BFF.
        return {"X-Test-Phone": self.phone}


@pytest.fixture()
def user_auth() -> _DummyAuth:
    """
    End-user auth helper (no special roles).
    """

    return _DummyAuth(phone="+491700000001")


@pytest.fixture()
def admin_auth() -> _DummyAuth:
    """
    Admin / superadmin auth helper.

    In tests we drive permissions mostly through env-based mappings
    (e.g. BFF_ADMINS, BFF_SUPERADMINS, etc.), so we can reconfigure roles
    per test without changing Payments state.
    """

    return _DummyAuth(phone="+491700000099")


@pytest.fixture()
def operator_taxi_auth() -> _DummyAuth:
    """
    Taxi-Operator auth helper (used together with role-mocking).
    """

    return _DummyAuth(phone="+491700000010")


@pytest.fixture(autouse=True)
def _reset_role_envs(monkeypatch):
    """
    Ensure role-related environment variables are clean for every test.

    Individual tests can override them via monkeypatch.setenv.
    """
    for key in [
        "BFF_ADMINS",
        "BFF_TOPUP_SELLERS",
        "BFF_SUPERADMINS",
    ]:
        monkeypatch.delenv(key, raising=False)
    # Also reset global BFF role sets so tests do not share state between cases.
    try:
        from apps.bff.app import main as bff  # type: ignore[import]

        try:
            bff.BFF_ADMINS.clear()
        except Exception:
            pass
        try:
            bff.BFF_TOPUP_SELLERS.clear()
        except Exception:
            pass
    except Exception:
        # If the module is not needed in a given test an import error is harmless.
        pass
