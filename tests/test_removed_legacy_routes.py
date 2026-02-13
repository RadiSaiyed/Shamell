def test_legacy_non_wechat_routes_are_removed(client):
    """
    Regression test: legacy/non-WeChat verticals must stay removed from the BFF.
    A removed route must return 404 (not 401/403/422/405).
    """

    assert client.post("/courier/quote", json={}).status_code == 404
    assert client.post("/stays/quote", json={}).status_code == 404
    assert client.post("/carrental/book", json={}).status_code == 404

    assert client.get("/commerce/products_cached").status_code == 404
    assert client.get("/agriculture/listings_cached").status_code == 404
    assert client.get("/livestock/listings_cached").status_code == 404
    assert client.get("/building/materials").status_code == 404

    # Legacy modules that must not be exposed by the BFF.
    assert client.get("/pms").status_code == 404
    assert client.get("/payments-debug").status_code == 404
