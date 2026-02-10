import apps.bff.app.main as bff


def test_admin_roles_list_requires_admin(client, user_auth, admin_auth, monkeypatch):
    # Unprivileged user must not see roles
    resp = client.get("/admin/roles", headers=user_auth.headers())
    assert resp.status_code in (401, 403)

    # Simulate admin role for admin_auth.phone via role function
    def fake_roles(phone: str) -> list[str]:
        if phone == admin_auth.phone:
            return ["admin"]
        return []

    monkeypatch.setattr(bff, "_get_effective_roles", fake_roles)

    resp2 = client.get("/admin/roles", headers=admin_auth.headers())
    # Depending on underlying Payments setup this may be 200 with data or 502 if upstream missing,
    # but it must not be a 401/403 at the BFF layer.
    assert resp2.status_code not in (401, 403)


def test_superadmin_required_for_role_mutation(client, admin_auth, monkeypatch):
    payload = {"phone": "+491700000055", "role": "operator_bus"}

    # Erst nur Admin-Rolle simulieren -> kein Superadmin: Request muss scheitern
    def admin_only_roles(phone: str) -> list[str]:
        if phone == admin_auth.phone:
            return ["admin"]
        return []

    monkeypatch.setattr(bff, "_get_effective_roles", admin_only_roles)

    resp = client.post("/admin/roles", json=payload, headers=admin_auth.headers())
    assert resp.status_code in (401, 403)

    # Jetzt Superadmin-Rolle simulieren
    def superadmin_roles(phone: str) -> list[str]:
        if phone == admin_auth.phone:
            return ["superadmin"]
        return []

    monkeypatch.setattr(bff, "_get_effective_roles", superadmin_roles)
    resp2 = client.post("/admin/roles", json=payload, headers=admin_auth.headers())

    # Underlying Payments may still fail (e.g. DB not seeded), but access
    # control at BFF layer must pass.
    assert resp2.status_code not in (401, 403)


def test_admin_metrics_requires_admin(client, user_auth, admin_auth, monkeypatch):
    # Ohne Admin-Rolle: kein Zugriff auf /admin/metrics
    resp = client.get("/admin/metrics", headers=user_auth.headers())
    assert resp.status_code in (401, 403)

    def fake_roles(phone: str) -> list[str]:
        if phone == admin_auth.phone:
            return ["admin"]
        return []

    monkeypatch.setattr(bff, "_get_effective_roles", fake_roles)

    resp2 = client.get("/admin/metrics", headers=admin_auth.headers())
    # Admin darf die HTML-Ansicht sehen
    assert resp2.status_code not in (401, 403)


def test_auth_request_code_rate_limited_by_phone(client, monkeypatch):
    """
    Ensure that /auth/request_code returns HTTP 429 when there are too many
    requests per phone number within the time window.
    """

    phone = "+491700001234"

    # Reduce thresholds significantly for this test
    monkeypatch.setattr(bff, "AUTH_MAX_PER_PHONE", 2, raising=False)
    monkeypatch.setattr(bff, "AUTH_MAX_PER_IP", 100, raising=False)
    monkeypatch.setattr(bff, "_AUTH_RATE_PHONE", {}, raising=False)
    monkeypatch.setattr(bff, "_AUTH_RATE_IP", {}, raising=False)

    for i in range(2):
        r = client.post("/auth/request_code", json={"phone": phone})
        assert r.status_code == 200
    # Third request in the same window must be blocked
    r3 = client.post("/auth/request_code", json={"phone": phone})
    assert r3.status_code == 429


def test_admin_info_requires_admin_and_returns_basic_structure(client, user_auth, admin_auth, monkeypatch):
    # Ohne Admin-Rolle: kein Zugriff
    resp = client.get("/admin/info", headers=user_auth.headers())
    assert resp.status_code in (401, 403)

    def fake_roles(phone: str) -> list[str]:
        if phone == admin_auth.phone:
            return ["admin"]
        return []

    monkeypatch.setattr(bff, "_get_effective_roles", fake_roles)

    resp2 = client.get("/admin/info", headers=admin_auth.headers())
    assert resp2.status_code == 200
    data = resp2.json()
    assert "env" in data
    assert "internal_mode" in data
    assert "domains" in data
    assert isinstance(data["domains"], dict)


def test_auth_request_code_hides_code_when_expose_disabled(client, monkeypatch):
    """
    When AUTH_EXPOSE_CODES is disabled, the OTP code must not
    appear in the response body.
    """

    phone = "+491700001999"
    # Ensure no stale rate-limit entries interfere
    monkeypatch.setattr(bff, "_AUTH_RATE_PHONE", {}, raising=False)
    monkeypatch.setattr(bff, "_AUTH_RATE_IP", {}, raising=False)
    monkeypatch.setattr(bff, "AUTH_EXPOSE_CODES", False, raising=False)

    resp = client.post("/auth/request_code", json={"phone": phone})
    assert resp.status_code == 200
    data = resp.json()
    assert data.get("phone") == phone
    assert "ttl" in data
    # Code must not appear in the body
    assert "code" not in data


def test_auth_verify_respects_rate_limit(client, monkeypatch):
    """
    Verify endpoint uses the same rate limiter as request_code.
    """

    phone = "+491700002222"
    monkeypatch.setattr(bff, "_AUTH_RATE_PHONE", {}, raising=False)
    monkeypatch.setattr(bff, "_AUTH_RATE_IP", {}, raising=False)
    monkeypatch.setattr(bff, "AUTH_MAX_PER_PHONE", 2, raising=False)
    monkeypatch.setattr(bff, "AUTH_MAX_PER_IP", 100, raising=False)
    # Expose codes so tests can read them
    monkeypatch.setattr(bff, "AUTH_EXPOSE_CODES", True, raising=False)

    # First obtain a valid code
    r1 = client.post("/auth/request_code", json={"phone": phone})
    assert r1.status_code == 200
    code = r1.json().get("code")
    assert code

    # First verify attempt: either 200 (correct) or 400 (if code already invalidated)
    v1 = client.post("/auth/verify", json={"phone": phone, "code": code})
    assert v1.status_code in (200, 400)

    # Second verify attempt: rate limiter should kick in
    v2 = client.post("/auth/verify", json={"phone": phone, "code": code})
    assert v2.status_code == 429
