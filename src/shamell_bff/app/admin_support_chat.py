from __future__ import annotations

import base64
import uuid
from datetime import datetime
from typing import Any

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from sqlalchemy import or_
from sqlalchemy.orm import Session

from .core_main.auth_helpers.admin import _require_admin
from .core_main.config import OFFICIAL_CHAT_PRIVATE_KEY_B64, OFFICIAL_CHAT_PUBLIC_KEY_B64
from .core_main.integrations import _use_chat_internal
from .core_main.optional_services import chat_main

router = APIRouter()

try:
    from nacl.exceptions import CryptoError  # type: ignore[import-not-found]
    from nacl.public import Box, PrivateKey, PublicKey  # type: ignore[import-not-found]
except Exception:  # pragma: no cover - optional in lightweight envs
    CryptoError = Exception  # type: ignore[assignment]
    Box = None  # type: ignore[assignment]
    PrivateKey = None  # type: ignore[assignment]
    PublicKey = None  # type: ignore[assignment]


def _require_pynacl() -> None:
    if Box is None or PrivateKey is None or PublicKey is None:
        raise HTTPException(
            status_code=503,
            detail="PyNaCl not installed; admin support chat crypto disabled",
        )


def _iso(value: Any) -> str | None:
    try:
        if isinstance(value, datetime):
            return value.isoformat()
        return str(value) if value is not None else None
    except Exception:
        return None


def _require_chat_internal() -> None:
    if not (_use_chat_internal() and chat_main):
        raise HTTPException(status_code=503, detail="chat service not available in-process")


def _decode_key_b64(value: str, *, expected_len: int) -> bytes:
    raw = base64.b64decode((value or "").strip())
    if len(raw) != expected_len:
        raise ValueError("invalid key length")
    return raw


def _official_private_key() -> PrivateKey:
    _require_pynacl()
    key_b64 = (OFFICIAL_CHAT_PRIVATE_KEY_B64 or "").strip()
    if not key_b64:
        raise HTTPException(
            status_code=500,
            detail="OFFICIAL_CHAT_PRIVATE_KEY_B64 not configured (cannot decrypt official/support messages)",
        )
    try:
        return PrivateKey(_decode_key_b64(key_b64, expected_len=32))
    except Exception:
        raise HTTPException(
            status_code=500,
            detail="OFFICIAL_CHAT_PRIVATE_KEY_B64 invalid (expected base64-encoded 32 bytes)",
        )


def _decrypt_text(
    *,
    my_sk: PrivateKey,
    peer_public_key_b64: str,
    nonce_b64: str,
    box_b64: str,
) -> str | None:
    _require_pynacl()
    peer_pk_raw = (peer_public_key_b64 or "").strip()
    if not peer_pk_raw:
        return None
    try:
        box = Box(my_sk, PublicKey(_decode_key_b64(peer_pk_raw, expected_len=32)))
        plain = box.decrypt(
            base64.b64decode((box_b64 or "").strip()),
            nonce=base64.b64decode((nonce_b64 or "").strip()),
        )
        return plain.decode("utf-8")
    except (CryptoError, ValueError):
        pass
    except UnicodeDecodeError:
        pass
    except Exception:
        pass
    # legacy fallback: some payloads are stored as base64 plaintext
    try:
        return base64.b64decode((box_b64 or "").strip()).decode("utf-8")
    except UnicodeDecodeError:
        return None
    except Exception:
        return None


def _encrypt_text(
    *,
    my_sk: PrivateKey,
    peer_public_key_b64: str,
    plain_text: str,
) -> tuple[str, str]:
    _require_pynacl()
    peer_pk_raw = (peer_public_key_b64 or "").strip()
    if not peer_pk_raw:
        raise HTTPException(status_code=400, detail="peer public key missing")
    try:
        box = Box(my_sk, PublicKey(_decode_key_b64(peer_pk_raw, expected_len=32)))
    except Exception:
        raise HTTPException(status_code=400, detail="peer public key invalid")
    enc = box.encrypt(plain_text.encode("utf-8"))
    return (
        base64.b64encode(enc.nonce).decode("utf-8"),
        base64.b64encode(enc.ciphertext).decode("utf-8"),
    )


def _device_public_key_b64(s: Session, device_id: str) -> str:
    did = (device_id or "").strip()
    if not did:
        return ""
    row = s.get(chat_main.Device, did)  # type: ignore[arg-type]
    return (row.public_key or "").strip() if row else ""


@router.get("/admin/support/chat/threads", response_class=JSONResponse)
def admin_support_threads(
    request: Request,
    device_id: str = "shamell",
    limit: int = 200,
) -> dict[str, Any]:
    _require_admin(request)
    _require_chat_internal()
    did = (device_id or "").strip() or "shamell"
    limit_val = max(1, min(int(limit or 200), 500))
    my_sk = _official_private_key()

    with Session(chat_main.engine) as s:  # type: ignore[arg-type]
        Message = chat_main.Message  # type: ignore[attr-defined]
        rows = (
            s.query(Message)
            .filter(or_(Message.sender_id == did, Message.recipient_id == did))
            .order_by(Message.created_at.desc())
            .limit(limit_val)
            .all()
        )

        threads: list[dict[str, Any]] = []
        seen: set[str] = set()
        for m in rows:
            peer = m.sender_id if m.sender_id != did else m.recipient_id
            peer = (peer or "").strip()
            if not peer or peer == did or peer in seen:
                continue
            seen.add(peer)
            peer_pk = ""
            if m.sender_id == did:
                peer_pk = _device_public_key_b64(s, peer)
            else:
                peer_pk = (m.sender_pubkey or "").strip() or _device_public_key_b64(s, peer)
            preview = None
            if not getattr(m, "sealed_sender", False):
                preview = _decrypt_text(
                    my_sk=my_sk,
                    peer_public_key_b64=peer_pk,
                    nonce_b64=m.nonce_b64,
                    box_b64=m.box_b64,
                )
            threads.append(
                {
                    "peer_id": peer,
                    "last_message_id": m.id,
                    "last_at": _iso(m.created_at),
                    "last_direction": "out" if m.sender_id == did else "in",
                    "last_preview": preview or "<encrypted>",
                }
            )

        return {"device_id": did, "threads": threads}


@router.get("/admin/support/chat/thread/{peer_id}", response_class=JSONResponse)
def admin_support_thread(
    peer_id: str,
    request: Request,
    device_id: str = "shamell",
    limit: int = 200,
) -> dict[str, Any]:
    _require_admin(request)
    _require_chat_internal()
    did = (device_id or "").strip() or "shamell"
    pid = (peer_id or "").strip()
    if not pid:
        raise HTTPException(status_code=400, detail="peer_id required")
    limit_val = max(1, min(int(limit or 200), 500))
    my_sk = _official_private_key()

    with Session(chat_main.engine) as s:  # type: ignore[arg-type]
        Message = chat_main.Message  # type: ignore[attr-defined]
        rows = (
            s.query(Message)
            .filter(
                or_(
                    (Message.sender_id == did) & (Message.recipient_id == pid),
                    (Message.sender_id == pid) & (Message.recipient_id == did),
                )
            )
            .order_by(Message.created_at.asc())
            .limit(limit_val)
            .all()
        )
        peer_pk = _device_public_key_b64(s, pid)
        out: list[dict[str, Any]] = []
        for m in rows:
            direction = "out" if m.sender_id == did else "in"
            effective_peer_pk = peer_pk if m.sender_id == did else ((m.sender_pubkey or "").strip() or peer_pk)
            text = None
            if not getattr(m, "sealed_sender", False):
                text = _decrypt_text(
                    my_sk=my_sk,
                    peer_public_key_b64=effective_peer_pk,
                    nonce_b64=m.nonce_b64,
                    box_b64=m.box_b64,
                )
            out.append(
                {
                    "id": m.id,
                    "sender_id": m.sender_id,
                    "recipient_id": m.recipient_id,
                    "created_at": _iso(m.created_at),
                    "direction": direction,
                    "text": text or "<encrypted>",
                    "sealed_sender": bool(getattr(m, "sealed_sender", False)),
                }
            )
        return {"device_id": did, "peer_id": pid, "messages": out}


class _SupportSendIn(BaseModel):
    text: str


@router.post("/admin/support/chat/thread/{peer_id}/send", response_class=JSONResponse)
def admin_support_send(
    peer_id: str,
    body: _SupportSendIn,
    request: Request,
    device_id: str = "shamell",
) -> dict[str, Any]:
    _require_admin(request)
    _require_chat_internal()
    did = (device_id or "").strip() or "shamell"
    pid = (peer_id or "").strip()
    text = (body.text or "").strip()
    if not pid:
        raise HTTPException(status_code=400, detail="peer_id required")
    if not text:
        raise HTTPException(status_code=400, detail="text required")
    sender_pub = (OFFICIAL_CHAT_PUBLIC_KEY_B64 or "").strip()
    if not sender_pub:
        raise HTTPException(status_code=500, detail="OFFICIAL_CHAT_PUBLIC_KEY_B64 not configured")
    my_sk = _official_private_key()

    with Session(chat_main.engine) as s:  # type: ignore[arg-type]
        peer_pk = _device_public_key_b64(s, pid)
        if not peer_pk:
            raise HTTPException(status_code=404, detail="unknown peer device")
        nonce_b64, box_b64 = _encrypt_text(my_sk=my_sk, peer_public_key_b64=peer_pk, plain_text=text)
        mid = str(uuid.uuid4())
        Message = chat_main.Message  # type: ignore[attr-defined]
        m = Message(
            id=mid,
            sender_id=did,
            recipient_id=pid,
            sender_pubkey=sender_pub,
            nonce_b64=nonce_b64,
            box_b64=box_b64,
            sealed_sender=False,
        )
        s.add(m)
        s.commit()
        try:
            s.refresh(m)
        except Exception:
            pass
        return {
            "ok": True,
            "id": m.id,
            "sender_id": m.sender_id,
            "recipient_id": m.recipient_id,
            "created_at": _iso(getattr(m, "created_at", None)),
        }
