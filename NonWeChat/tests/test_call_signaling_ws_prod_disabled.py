import pytest
from starlette.websockets import WebSocketDisconnect


def test_call_signaling_ws_disabled_in_prod(client, monkeypatch):
    # The VoIP signaling stub is intentionally disabled in production by default.
    monkeypatch.setenv("ENV", "prod")
    monkeypatch.delenv("CALL_SIGNALING_ENABLED", raising=False)
    with pytest.raises(WebSocketDisconnect):
        with client.websocket_connect("/ws/call/signaling?device_id=dev1234"):
            pass


def test_call_signaling_ws_enabled_in_test(client, monkeypatch):
    # In tests/dev the stub remains available for local iteration.
    monkeypatch.setenv("ENV", "test")
    monkeypatch.delenv("CALL_SIGNALING_ENABLED", raising=False)
    with client.websocket_connect("/ws/call/signaling?device_id=dev1234") as ws:
        ws.close()

