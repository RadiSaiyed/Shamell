import apps.bff.app.main as bff


def test_internal_auto_mode_disabled_in_prod(monkeypatch):
    # In prod/staging, *_INTERNAL_MODE=auto must not silently fall back to
    # internal implementations when BASE_URLs are missing.
    monkeypatch.setenv("ENV", "prod")
    monkeypatch.setattr(bff, "FORCE_INTERNAL_DOMAINS", False, raising=False)

    monkeypatch.setenv("PAYMENTS_INTERNAL_MODE", "auto")
    monkeypatch.setattr(bff, "PAYMENTS_BASE", "", raising=False)
    monkeypatch.setattr(bff, "_PAY_INTERNAL_AVAILABLE", True, raising=False)
    assert bff._use_pay_internal() is False

    monkeypatch.setenv("BUS_INTERNAL_MODE", "auto")
    monkeypatch.setattr(bff, "BUS_BASE", "", raising=False)
    monkeypatch.setattr(bff, "_BUS_INTERNAL_AVAILABLE", True, raising=False)
    assert bff._use_bus_internal() is False

    monkeypatch.setenv("CHAT_INTERNAL_MODE", "auto")
    monkeypatch.setattr(bff, "CHAT_BASE", "", raising=False)
    monkeypatch.setattr(bff, "_CHAT_INTERNAL_AVAILABLE", True, raising=False)
    assert bff._use_chat_internal() is False

