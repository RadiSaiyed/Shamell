import asyncio
import json
from typing import Any, Dict, List

from fastapi import WebSocket

# Lightweight in-memory broadcast queue for dev/demo use.
active_sockets: List[WebSocket] = []
queue: asyncio.Queue[Dict[str, Any]] = asyncio.Queue()


async def broadcast(msg: Dict[str, Any]) -> None:
    text = json.dumps(msg)
    for ws in list(active_sockets):
        try:
            await ws.send_text(text)
        except Exception:
            try:
                active_sockets.remove(ws)
            except Exception:
                pass


def queue_broadcast(msg: Dict[str, Any]) -> None:
    try:
        queue.put_nowait(msg)
    except Exception:
        pass
