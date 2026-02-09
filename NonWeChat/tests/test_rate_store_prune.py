from __future__ import annotations

import time

import apps.bff.app.main as bff  # type: ignore[import]


def test_prune_rate_store_caps_keys():
    store: dict[str, list[int]] = {}
    now = int(time.time())
    for i in range(50):
        store[f"k{i}"] = [now]
    bff._prune_rate_store(store, max_keys=10, window_secs=60)
    assert len(store) <= 10


def test_prune_rate_store_can_clear_when_disabled():
    store: dict[str, list[int]] = {"a": [1], "b": [2]}
    bff._prune_rate_store(store, max_keys=0, window_secs=60)
    assert store == {}

