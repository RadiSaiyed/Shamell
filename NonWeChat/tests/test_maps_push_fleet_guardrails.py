from __future__ import annotations

import apps.bff.app.main as bff  # type: ignore[import]


def _auth(phone: str = "+491700000001") -> dict[str, str]:
    return {"X-Test-Phone": phone}


def test_push_register_blocks_private_endpoints(client):
    """
    UnifiedPush endpoints are user-controlled callback URLs and must not allow
    localhost/private targets (SSRF guardrail).
    """
    r = client.post(
        "/push/register",
        headers=_auth(),
        json={
            "device_id": "dev1",
            "type": "unifiedpush",
            "endpoint": "https://127.0.0.1/callback",
        },
    )
    assert r.status_code == 403


def test_osm_geocode_batch_requires_auth(client):
    r0 = client.post("/osm/geocode_batch", json={"queries": ["damascus"], "max_per_query": 1})
    assert r0.status_code == 401

    r1 = client.post("/osm/geocode_batch", headers=_auth(), json={"queries": ["damascus"], "max_per_query": 1})
    assert r1.status_code == 200
    j = r1.json()
    assert "results" in j
    assert isinstance(j["results"], list)


def test_fleet_optimize_requires_auth_and_caps_input(client):
    r0 = client.post(
        "/fleet/optimize_stops",
        json={"origin": {"lat": 33.5, "lon": 36.3}, "stops": [{"id": "s1", "lat": 33.51, "lon": 36.31}]},
    )
    assert r0.status_code == 401

    too_many = [{"id": f"s{i}", "lat": 33.5, "lon": 36.3} for i in range(bff.FLEET_MAX_STOPS + 1)]
    r1 = client.post(
        "/fleet/optimize_stops",
        headers=_auth(),
        json={"origin": {"lat": 33.5, "lon": 36.3}, "stops": too_many},
    )
    assert r1.status_code == 413

