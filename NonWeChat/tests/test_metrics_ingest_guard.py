from __future__ import annotations

import apps.bff.app.main as bff  # type: ignore[import]


def test_metrics_ingest_disabled_in_prod_without_secret(client, monkeypatch):
    monkeypatch.setattr(bff, "_ENV_LOWER", "prod", raising=False)
    monkeypatch.setattr(bff, "METRICS_INGEST_SECRET", "", raising=False)

    resp = client.post("/metrics", json={"type": "ping"})
    assert resp.status_code == 403


def test_metrics_ingest_requires_secret_when_configured(client, monkeypatch):
    monkeypatch.setattr(bff, "_ENV_LOWER", "prod", raising=False)
    monkeypatch.setattr(bff, "METRICS_INGEST_SECRET", "SENTINEL", raising=False)

    resp = client.post("/metrics", json={"type": "ping"})
    assert resp.status_code == 401

    ok = client.post("/metrics", json={"type": "ping"}, headers={"X-Metrics-Secret": "SENTINEL"})
    assert ok.status_code == 200
    assert ok.json().get("ok") is True


def test_metrics_ingest_rejects_oversize_payload(client, monkeypatch):
    monkeypatch.setattr(bff, "_ENV_LOWER", "prod", raising=False)
    monkeypatch.setattr(bff, "METRICS_INGEST_SECRET", "SENTINEL", raising=False)
    monkeypatch.setattr(bff, "METRICS_INGEST_MAX_BYTES", 10, raising=False)

    resp = client.post(
        "/metrics",
        data=b'{"a":"0123456789"}',
        headers={"X-Metrics-Secret": "SENTINEL", "content-type": "application/json"},
    )
    assert resp.status_code == 413

