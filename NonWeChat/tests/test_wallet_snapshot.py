from typing import Any, Dict

import apps.bff.app.main as bff


def test_wallet_snapshot_structure_for_unknown_wallet(client, user_auth, monkeypatch):
    # Stub Payments dependency (internal/external) for this test
    # so we can validate the aggregation logic in isolation.
    def fake_get_wallet(wallet_id: str) -> Dict[str, Any]:
        return {"id": wallet_id, "balance_cents": 123, "currency": "SYP"}

    def fake_payments_txns(
        wallet_id: str,
        limit: int = 20,
        dir: str = "",
        kind: str = "",
        from_iso: str = "",
        to_iso: str = "",
    ):
        return [
            {
                "id": "txn1",
                "wallet_id": wallet_id,
                "amount_cents": 100,
                "kind": "test",
                "created_at": "2024-01-01T00:00:00Z",
            }
        ]

    monkeypatch.setattr(bff, "get_wallet", fake_get_wallet)
    monkeypatch.setattr(bff, "payments_txns", fake_payments_txns)

    wallet_id = "test-wallet-unknown"
    resp = client.get(f"/wallets/{wallet_id}/snapshot", headers=user_auth.headers())
    assert resp.status_code == 200
    data: Dict[str, Any] = resp.json()

    assert data.get("wallet_id") == wallet_id
    # txns is always present as a list
    assert "txns" in data
    assert isinstance(data["txns"], list)
    assert data["txns"][0]["wallet_id"] == wallet_id
    # wallet may not be null in this stubbed scenario
    assert "wallet" in data
    assert isinstance(data["wallet"], dict)
