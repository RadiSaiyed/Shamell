import pytest
from starlette.websockets import WebSocketDisconnect


def test_chat_ws_requires_device_id(client):
    # Without a device_id the BFF should close the WS quickly to avoid
    # useless long-lived connections that only generate backend load.
    with client.websocket_connect("/ws/chat/inbox") as ws:
        with pytest.raises(WebSocketDisconnect) as e:
            ws.receive_text()
        assert e.value.code == 4400


def test_chat_ws_limits_concurrent_connections_per_device(monkeypatch, client):
    from apps.bff.app import main as bff  # type: ignore[import]

    # Keep the test deterministic: hard cap to 1 active WS per device_id.
    monkeypatch.setattr(bff, "CHAT_WS_MAX_ACTIVE_PER_DEVICE", 1)
    monkeypatch.setattr(bff, "CHAT_WS_MAX_ACTIVE_PER_IP", 0)  # irrelevant for this test
    monkeypatch.setattr(bff, "CHAT_WS_CONNECT_MAX_PER_IP", 0)  # irrelevant for this test
    bff._CHAT_WS_ACTIVE_DEVICE.clear()
    bff._CHAT_WS_ACTIVE_IP.clear()
    bff._CHAT_WS_CONNECT_RATE_IP.clear()

    did = "dev_1234"
    with client.websocket_connect(f"/ws/chat/inbox?device_id={did}") as ws1:
        with client.websocket_connect(f"/ws/chat/inbox?device_id={did}") as ws2:
            # Second connection should be rejected (best-effort close).
            with pytest.raises(WebSocketDisconnect) as e:
                ws2.receive_text()
            assert e.value.code == 1013
        # Keep ws1 alive for the duration of the assertion window.
        try:
            ws1.send_text("ping")
        except Exception:
            pass

