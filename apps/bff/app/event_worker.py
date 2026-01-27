from __future__ import annotations

import json
import logging
import os
import sys
import time

try:
    import redis  # type: ignore[import]
except Exception:  # pragma: no cover
    redis = None  # type: ignore[assignment]


log = logging.getLogger("shamell.event_worker")
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)


def main() -> int:
    """
    Minimal blocking worker that subscribes to BFF domain events
    (chat, payments, …) via Redis Pub/Sub and logs them.

    This is intentionally simple so it can run as a sidecar or
    a separate process for debugging/analytics.
    """
    if redis is None:
        log.error("redis library not available; cannot start event worker")
        return 1

    url = os.getenv("EVENTS_REDIS_URL", "redis://localhost:6379/0")
    channels = os.getenv("EVENTS_CHANNELS", "events:chat,events:payments").split(",")
    channels = [c.strip() for c in channels if c.strip()]

    if not channels:
        log.error("no channels configured for event worker")
        return 1

    log.info("connecting to redis at %s", url)
    try:
        client = redis.from_url(url)  # type: ignore[call-arg]
    except Exception as e:  # pragma: no cover
        log.error("failed to connect to redis: %s", e)
        return 1

    pubsub = client.pubsub(ignore_subscribe_messages=True)  # type: ignore[call-arg]
    pubsub.subscribe(*channels)
    log.info("subscribed to channels: %s", ", ".join(channels))

    try:
        for msg in pubsub.listen():  # type: ignore[assignment]
            if not msg:
                continue
            if msg.get("type") != "message":
                continue
            raw = msg.get("data")
            try:
                if isinstance(raw, bytes):
                    raw = raw.decode("utf-8", "replace")
                data = json.loads(raw)
            except Exception:
                log.warning("received non-JSON event on %s: %r", msg.get("channel"), raw)
                continue
            # Log in a structured way so downstream collectors can parse it.
            log.info("event", extra={"event": data})
    except KeyboardInterrupt:
        log.info("event worker interrupted, shutting down")
    except Exception as e:  # pragma: no cover
        log.error("event worker crashed: %s", e)
        time.sleep(1)
        return 1
    finally:
        try:
            pubsub.close()
        except Exception:
            pass

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

