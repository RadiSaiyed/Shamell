from __future__ import annotations

import base64
import hashlib
import hmac
import json

import apps.bff.app.main as bff  # type: ignore[import]

def _otp_login(client, phone: str) -> str:
    r0 = client.post("/auth/request_code", json={"phone": phone})
    assert r0.status_code == 200
    code = r0.json().get("code")
    assert isinstance(code, str) and code

    r1 = client.post("/auth/verify", json={"phone": phone, "code": code})
    assert r1.status_code == 200
    sid = r1.json().get("session")
    assert isinstance(sid, str) and sid
    return sid


def _b64url_decode(s: str) -> bytes:
    pad = "=" * (-len(s) % 4)
    return base64.urlsafe_b64decode(s + pad)


def _b64url_encode(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).decode("ascii").rstrip("=")


def test_livekit_token_minted_and_signed(client, monkeypatch):
    # Patch module-level config (env vars are read at import time).
    monkeypatch.setattr(bff, "LIVEKIT_TOKEN_ENDPOINT_ENABLED", True, raising=False)
    monkeypatch.setattr(bff, "LIVEKIT_PUBLIC_URL", "wss://livekit.example", raising=False)
    monkeypatch.setattr(bff, "LIVEKIT_API_KEY", "testkey", raising=False)
    monkeypatch.setattr(bff, "LIVEKIT_API_SECRET", "testsecret", raising=False)
    monkeypatch.setattr(bff, "LIVEKIT_TOKEN_TTL_SECS_DEFAULT", 300, raising=False)
    monkeypatch.setattr(bff, "LIVEKIT_TOKEN_MAX_TTL_SECS", 3600, raising=False)

    phone = "+491700999920"
    sid = _otp_login(client, phone)
    headers = {"sa_cookie": f"sa_session={sid}"}

    r = client.post("/livekit/token", json={"room": "call_testroom", "ttl_secs": 300}, headers=headers)
    assert r.status_code == 200
    j = r.json()
    assert j.get("ok") is True
    assert j.get("url") == "wss://livekit.example"
    assert j.get("room") == "call_testroom"

    tok = j.get("token")
    assert isinstance(tok, str) and tok.count(".") == 2
    h, p, s = tok.split(".", 2)

    header = json.loads(_b64url_decode(h))
    payload = json.loads(_b64url_decode(p))

    assert header.get("alg") == "HS256"
    assert payload.get("iss") == "testkey"
    assert isinstance(payload.get("sub"), str) and payload["sub"].startswith("u_")
    assert payload.get("video", {}).get("room") == "call_testroom"
    assert payload.get("video", {}).get("roomJoin") is True

    msg = f"{h}.{p}".encode("utf-8")
    expected_sig = _b64url_encode(hmac.new(b"testsecret", msg, hashlib.sha256).digest())
    assert s == expected_sig
