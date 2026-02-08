from __future__ import annotations

import pytest
from starlette.websockets import WebSocketDisconnect

import apps.bff.app.main as bff  # type: ignore[import]


def test_wallet_ws_disabled_outside_dev_test(client, monkeypatch):
    monkeypatch.setattr(bff, "_ENV_LOWER", "prod", raising=False)

    with client.websocket_connect("/ws/payments/wallets/w1") as ws:
        with pytest.raises(WebSocketDisconnect) as e:
            ws.receive_text()
    assert e.value.code == 1008

