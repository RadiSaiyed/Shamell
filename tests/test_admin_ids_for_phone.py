from __future__ import annotations

import apps.bff.app.main as bff  # type: ignore[import]


def test_admin_ids_for_phone_shape_does_not_crash(client, monkeypatch):
    """
    Regression test: /admin/ids_for_phone must not reference removed verticals
    and must never crash with NameError after cleanups.
    """

    caller = "+491700000099"
    target = "+491700000001"

    def fake_roles(phone: str) -> list[str]:
        if phone == caller:
            return ["superadmin"]
        return []

    monkeypatch.setattr(bff, "_get_effective_roles", fake_roles, raising=False)
    # Avoid touching Payments/Bus internals in this unit test.
    monkeypatch.setattr(bff, "_use_pay_internal", lambda: False, raising=False)
    monkeypatch.setattr(bff, "PAYMENTS_BASE", "", raising=False)
    monkeypatch.setattr(bff, "_use_bus_internal", lambda: False, raising=False)
    monkeypatch.setattr(bff, "BUS_BASE", "", raising=False)

    resp = client.get(
        "/admin/ids_for_phone",
        params={"phone": target},
        headers={"X-Test-Phone": caller},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data.get("phone") == target
    assert "roles" in data
    assert "bus_operator_ids" in data
    assert "stays_operator_ids" in data
    assert data["stays_operator_ids"] == []

