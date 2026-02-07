from __future__ import annotations

import json
import os
import time
from typing import Any, Dict

import logging

_log = logging.getLogger("shamell.events")

try:
  import redis  # type: ignore[import]
except Exception:  # pragma: no cover
  redis = None  # type: ignore[assignment]


class EventPublisher:
  """
  Lightweight event publisher for domain events (chat, payments, etc.).

  In prod this pushes JSON payloads to Redis Pub/Sub; when Redis is not
  available, it degrades to structured logging so the rest of the system
  does not break.
  """

  def __init__(self) -> None:
    url = os.getenv("EVENTS_REDIS_URL", "redis://localhost:6379/0")
    self._enabled = bool(os.getenv("EVENTS_ENABLED", "false").lower() == "true" and redis is not None)  # type: ignore[truthy-function]
    self._url = url
    self._client = None
    if self._enabled and redis is not None:  # type: ignore[truthy-function]
      try:
        self._client = redis.from_url(url)  # type: ignore[call-arg]
      except Exception as e:  # pragma: no cover
        _log.warning("events: failed to connect to redis '%s': %s", url, e)
        self._enabled = False

  def publish(self, domain: str, event_type: str, payload: Dict[str, Any]) -> None:
    ts_ms = int(time.time() * 1000)
    data = {
      "domain": domain,
      "type": event_type,
      "ts_ms": ts_ms,
      "payload": payload,
    }
    if self._enabled and self._client is not None:  # pragma: no cover
      try:
        channel = f"events:{domain}"
        self._client.publish(channel, json.dumps(data))  # type: ignore[call-arg]
        return
      except Exception as e:
        _log.warning("events: redis publish failed: %s", e)
    # Fallback: structured log
    try:
      _log.info("event", extra={"event": data})
    except Exception:
      _log.info("event %s", data)


_publisher = EventPublisher()


def emit_event(domain: str, event_type: str, payload: Dict[str, Any]) -> None:
  """
  Convenience helper used across BFF: best-effort event emission.
  """
  try:
    _publisher.publish(domain, event_type, payload)
  except Exception:
    # Never break main code path because of events.
    return

