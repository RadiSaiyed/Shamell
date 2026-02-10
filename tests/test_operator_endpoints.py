import apps.bff.app.main as bff


def test_bus_admin_summary_requires_operator_role(client, user_auth, operator_auth, monkeypatch):
    # Use same helper phone but mapped as bus operator for this test
    resp = client.get("/bus/admin/summary", headers=user_auth.headers())
    assert resp.status_code in (401, 403)

    def fake_roles(phone: str) -> list[str]:
        if phone == operator_auth.phone:
            return ["operator_bus"]
        return []

    monkeypatch.setattr(bff, "_get_effective_roles", fake_roles)

    resp2 = client.get("/bus/admin/summary", headers=operator_auth.headers())
    assert resp2.status_code not in (401, 403)
