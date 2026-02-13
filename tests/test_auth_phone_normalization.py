def test_auth_request_code_rejects_invalid_phone(client):
    r = client.post("/auth/request_code", json={"phone": "not-a-phone"})
    assert r.status_code == 400


def test_auth_request_code_accepts_00_prefix_and_normalizes(client):
    r = client.post("/auth/request_code", json={"phone": "00491700000001"})
    assert r.status_code == 200
    data = r.json()
    assert data.get("phone") == "+491700000001"

