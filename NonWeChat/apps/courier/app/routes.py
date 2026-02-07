from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from .ws import active_sockets, queue, broadcast

router_ws = APIRouter()


@router_ws.websocket("/courier/ws")
async def courier_ws(ws: WebSocket):
    await ws.accept()
    active_sockets.append(ws)
    try:
        while True:
            await ws.receive_text()
    except WebSocketDisconnect:
        pass
    except Exception:
        pass
    finally:
        try:
            active_sockets.remove(ws)
        except Exception:
            pass


async def drain_queue_forever():
    while True:
        msg = await queue.get()
        await broadcast(msg)
