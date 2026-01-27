import apps.bff.app.main as bff


def test_taxi_admin_summary_requires_operator_role(client, user_auth, operator_taxi_auth, monkeypatch):
    # Unprivileged user must not access taxi admin summary
    resp = client.get("/taxi/admin/summary", headers=user_auth.headers())
    assert resp.status_code in (401, 403)

    # Configure taxi-operator via Rollenfunktion
    def fake_roles(phone: str) -> list[str]:
        if phone == operator_taxi_auth.phone:
            return ["operator_taxi"]
        return []

    monkeypatch.setattr(bff, "_get_effective_roles", fake_roles)

    resp2 = client.get("/taxi/admin/summary", headers=operator_taxi_auth.headers())
    # BFF must allow, domain may still respond with an error if DB empty
    assert resp2.status_code not in (401, 403)


def test_bus_admin_summary_requires_operator_role(client, user_auth, operator_taxi_auth, monkeypatch):
    # Use same helper phone but mapped as bus operator for this test
    resp = client.get("/bus/admin/summary", headers=user_auth.headers())
    assert resp.status_code in (401, 403)

    def fake_roles(phone: str) -> list[str]:
        if phone == operator_taxi_auth.phone:
            return ["operator_bus"]
        return []

    monkeypatch.setattr(bff, "_get_effective_roles", fake_roles)

    resp2 = client.get("/bus/admin/summary", headers=operator_taxi_auth.headers())
    assert resp2.status_code not in (401, 403)


def test_commerce_create_product_requires_operator_commerce(client, user_auth, operator_taxi_auth, monkeypatch):
    # Unprivileged user must not be allowed to create commerce products.
    resp = client.post(
        "/commerce/products",
        headers=user_auth.headers(),
        json={"name": "Test Material", "price_cents": 1000},
    )
    assert resp.status_code in (401, 403)

    def fake_roles(phone: str) -> list[str]:
        if phone == operator_taxi_auth.phone:
            return ["operator_commerce"]
        return []

    monkeypatch.setattr(bff, "_get_effective_roles", fake_roles)

    resp2 = client.post(
        "/commerce/products",
        headers=operator_taxi_auth.headers(),
        json={"name": "Test Material", "price_cents": 1000},
    )
    # BFF must accept; domain may still validate body.
    assert resp2.status_code not in (401, 403)
