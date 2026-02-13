def _assert_endpoint_exists(resp) -> None:
    # For this initial smoke test we only check
    # that the route exists (no 404/405). Details of the
    # backend configuration (DB, services) are not validated here.
    assert resp.status_code not in (404, 405)


def test_bus_cities_cached_reachable(client):
    resp = client.get("/bus/cities_cached")
    _assert_endpoint_exists(resp)
