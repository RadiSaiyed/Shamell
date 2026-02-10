from __future__ import annotations

import uuid

import apps.bff.app.main as bff  # type: ignore[import]


def _hdr(phone: str) -> dict[str, str]:
    return {"X-Test-Phone": phone}


def test_channels_creator_endpoints_require_owner_or_admin(client):
    owner_phone = "+491700000123"
    other_phone = "+491700000124"
    admin_phone = "+491700000199"

    account_id = f"merchant_test_{uuid.uuid4().hex}"

    # Seed an Official account with an explicit owner.
    with bff._officials_session() as s:  # type: ignore[attr-defined]
        row = bff.OfficialAccountDB(  # type: ignore[attr-defined]
            id=account_id,
            kind="service",
            name="Merchant Test",
            enabled=True,
            verified=True,
            official=False,
            owner_phone=owner_phone,
        )
        s.add(row)
        s.commit()

    payload = {
        "official_account_id": account_id,
        "title": "t",
        "snippet": "hello",
        "is_live": True,
    }

    # Non-owner/non-admin must be blocked from publishing.
    r0 = client.post("/channels/upload", headers=_hdr(other_phone), json=payload)
    assert r0.status_code == 403

    # Owner can publish.
    r1 = client.post("/channels/upload", headers=_hdr(owner_phone), json=payload)
    assert r1.status_code == 200
    j1 = r1.json()
    assert j1.get("official_account_id") == account_id
    item_id = str(j1.get("id") or "").strip()
    assert item_id

    # Non-owner/non-admin must be blocked from ending live.
    r2 = client.post(f"/channels/live/{item_id}/stop", headers=_hdr(other_phone), json={})
    assert r2.status_code == 403

    # Owner can end live.
    r3 = client.post(f"/channels/live/{item_id}/stop", headers=_hdr(owner_phone), json={})
    assert r3.status_code == 200

    # Admin can publish/stop regardless of ownership.
    bff.BFF_ADMINS.add(admin_phone)  # type: ignore[attr-defined]
    r4 = client.post("/channels/upload", headers=_hdr(admin_phone), json=payload)
    assert r4.status_code == 200
    item_id2 = str(r4.json().get("id") or "").strip()
    assert item_id2
    r5 = client.post(f"/channels/live/{item_id2}/stop", headers=_hdr(admin_phone), json={})
    assert r5.status_code == 200


def test_official_moments_stats_require_owner_or_admin(client):
    owner_phone = "+491700000223"
    other_phone = "+491700000224"
    admin_phone = "+491700000299"
    account_id = f"merchant_stats_{uuid.uuid4().hex}"

    with bff._officials_session() as s:  # type: ignore[attr-defined]
        row = bff.OfficialAccountDB(  # type: ignore[attr-defined]
            id=account_id,
            kind="service",
            name="Merchant Stats",
            enabled=True,
            verified=True,
            official=False,
            owner_phone=owner_phone,
        )
        s.add(row)
        s.commit()

    # No auth -> 401
    r0 = client.get(f"/official_accounts/{account_id}/moments_stats")
    assert r0.status_code == 401

    # Non-owner -> 403
    r1 = client.get(f"/official_accounts/{account_id}/moments_stats", headers=_hdr(other_phone))
    assert r1.status_code == 403

    # Owner -> 200
    r2 = client.get(f"/official_accounts/{account_id}/moments_stats", headers=_hdr(owner_phone))
    assert r2.status_code == 200
    j2 = r2.json()
    assert "total_shares" in j2
    assert "followers" in j2

    # Admin -> 200
    bff.BFF_ADMINS.add(admin_phone)  # type: ignore[attr-defined]
    r3 = client.get(f"/official_accounts/{account_id}/moments_stats", headers=_hdr(admin_phone))
    assert r3.status_code == 200
