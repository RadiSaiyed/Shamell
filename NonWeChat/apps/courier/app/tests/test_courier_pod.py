from datetime import datetime, timedelta

from sqlalchemy import create_engine
from sqlalchemy.orm import Session

import apps.courier.app.main as courier  # type: ignore[import]


def _engine():
    return create_engine("sqlite+pysqlite:///:memory:", connect_args={"check_same_thread": False}, future=True)


def test_pod_photo_and_pin_enforced():
    engine = _engine()
    courier.Base.metadata.create_all(engine)
    with Session(engine) as s:
        od = courier.create_order(
            req=courier.OrderCreate(
                pickup_lat=0.0, pickup_lng=0.0, drop_lat=0.01, drop_lng=0.01,
                customer_name="PoD", customer_phone="+491700001234",
            ),
            s=s,
        )
        # wrong PIN -> fail
        try:
            courier.update_status(od.id, courier.StatusUpdate(status="delivered", pin="0000", pod_photo_url="https://pod"), s=s)
            assert False, "expected PIN failure"
        except courier.HTTPException:
            pass
        # correct PIN with PoD photo
        upd = courier.StatusUpdate(status="delivered", pin=od.pin_code, pod_photo_url="https://pod")
        od2 = courier.update_status(od.id, upd, s=s)
        assert od2.status == "delivered"


def test_pod_webhook_payload(monkeypatch):
    engine = _engine()
    courier.Base.metadata.create_all(engine)
    calls = {}
    monkeypatch.setattr(courier, "WEBHOOK_URL", "http://webhook")

    def fake_post(url, json=None, timeout=None):
        calls["json"] = json
        class Resp: pass
        return Resp()
    monkeypatch.setattr(courier.httpx, "post", fake_post)
    with Session(engine) as s:
        od = courier.create_order(
            req=courier.OrderCreate(
                pickup_lat=0.0, pickup_lng=0.0, drop_lat=0.01, drop_lng=0.01,
                customer_name="PoD2", customer_phone="+491700001235",
            ),
            s=s,
        )
        courier.update_status(od.id, courier.StatusUpdate(status="delivering"), s=s)
        assert calls["json"]["status"] == "delivering"
        courier.update_status(od.id, courier.StatusUpdate(status="delivered", pin=od.pin_code, pod_photo_url="https://pod2", scanned_barcode="BR"), s=s)
        assert calls["json"]["pod_photo_url"] == "https://pod2"
        assert calls["json"]["barcode"] == "BR"
