from __future__ import annotations

import apps.bff.app.main as bff  # type: ignore[import]


def _auth(phone: str) -> dict[str, str]:
    return {"X-Test-Phone": phone}


def test_topup_print_and_batch_endpoints_are_authz_protected(client, monkeypatch):
    # In ENV=test the BFF historically treats "seller" as superadmin for convenience.
    # For this regression test we force production-like behaviour so we can
    # validate seller ownership checks.
    monkeypatch.setattr(bff, "_is_superadmin", lambda phone: False, raising=False)

    seller1 = "+491700000001"
    seller2 = "+491700000002"

    bff.BFF_TOPUP_SELLERS.clear()
    bff.BFF_TOPUP_SELLERS.update({seller1, seller2})

    # Create a batch as seller1
    r = client.post(
        "/topup/batch_create",
        json={"amount_cents": 1000, "count": 2},
        headers=_auth(seller1),
    )
    assert r.status_code == 200
    batch_id = (r.json() or {}).get("batch_id")
    assert batch_id

    # Unauthenticated access must be blocked.
    assert client.get(f"/topup/print/{batch_id}").status_code == 401
    assert client.get(f"/topup/print_pdf/{batch_id}").status_code == 401
    assert client.get("/topup/batches").status_code == 401
    assert client.get(f"/topup/batches/{batch_id}").status_code == 401

    # Owner seller can access.
    assert client.get(f"/topup/batches/{batch_id}", headers=_auth(seller1)).status_code == 200
    assert client.get(f"/topup/print/{batch_id}", headers=_auth(seller1)).status_code == 200
    pdf = client.get(f"/topup/print_pdf/{batch_id}", headers=_auth(seller1))
    if bff._pdfcanvas is None or bff._qr is None:  # type: ignore[attr-defined]
        assert pdf.status_code == 500
    else:
        assert pdf.status_code == 200

    # Non-owner seller must be blocked (prevents voucher leakage / IDOR).
    assert client.get(f"/topup/batches/{batch_id}", headers=_auth(seller2)).status_code == 403
    assert client.get(f"/topup/print/{batch_id}", headers=_auth(seller2)).status_code == 403
    assert client.get(f"/topup/print_pdf/{batch_id}", headers=_auth(seller2)).status_code == 403

    # Sellers must not list other sellers' batches.
    other = client.get("/topup/batches", params={"seller_id": seller1}, headers=_auth(seller2))
    assert other.status_code == 403

