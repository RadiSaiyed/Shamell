import uuid
from datetime import datetime, timedelta

import pytest
from fastapi import HTTPException

from sqlalchemy import create_engine
from sqlalchemy.orm import Session

import apps.courier.app.main as courier  # type: ignore[import]


def _engine():
    return create_engine("sqlite+pysqlite:///:memory:", connect_args={"check_same_thread": False}, future=True)


def _setup_driver(session: Session):
    d = courier.Driver(name="Drv", phone="+491700000900", status="idle", lat=0.0, lng=0.0, battery_pct=80)
    session.add(d); session.commit(); session.refresh(d)
    return d


def test_create_order_populates_tracking_and_window():
    engine = _engine()
    courier.Base.metadata.create_all(engine)
    with Session(engine) as s:
        req = courier.OrderCreate(
            pickup_lat=0.0,
            pickup_lng=0.0,
            drop_lat=0.1,
            drop_lng=0.1,
            customer_name="Test",
            customer_phone="+491700001111",
            service_type="same_day",
        )
        od = courier.create_order(req=req, s=s)
        assert od.tracking_token
        assert od.pin_code
        assert od.window_start and od.window_end
        assert od.service_type in ("same_day", "next_day")


def test_failed_then_retry_then_return():
    engine = _engine()
    courier.Base.metadata.create_all(engine)
    with Session(engine) as s:
        d = _setup_driver(s)
        req = courier.OrderCreate(
            pickup_lat=0.0,
            pickup_lng=0.0,
            drop_lat=0.01,
            drop_lng=0.01,
            customer_name="Test",
            customer_phone="+491700001112",
        )
        od = courier.create_order(req=req, s=s)
        # assign driver manually
        od.driver_id = d.id
        s.add(od); s.commit(); s.refresh(od)

        # first fail -> retry scheduled
        upd = courier.StatusUpdate(status="failed")
        od = courier.update_status(od.id, upd, s=s)
        assert od.status == "retry"
        assert od.retry_window_start is not None

        # second fail -> return
        upd2 = courier.StatusUpdate(status="failed")
        od = courier.update_status(od.id, upd2, s=s)
        assert od.status == "return"
        assert od.return_required is True


def test_driver_location_broadcast_includes_battery():
    engine = _engine()
    courier.Base.metadata.create_all(engine)
    with Session(engine) as s:
        d = _setup_driver(s)
        loc = courier.DriverLocation(lat=1.0, lng=1.0, status="busy", battery_pct=50)
        out = courier.update_driver_location(d.id, loc, s=s)
        assert out.battery_pct == 50
        assert out.status == "busy"


def test_pin_is_enforced_on_delivery():
    engine = _engine()
    courier.Base.metadata.create_all(engine)
    with Session(engine) as s:
        req = courier.OrderCreate(
            pickup_lat=0.0,
            pickup_lng=0.0,
            drop_lat=0.02,
            drop_lng=0.0,
            customer_name="Pin Test",
            customer_phone="+491700009999",
        )
        od = courier.create_order(req=req, s=s)
        wrong_pin = "0000" if od.pin_code != "0000" else "0001"
        with pytest.raises(HTTPException) as excinfo:
            courier.update_status(od.id, courier.StatusUpdate(status="delivered", pin=wrong_pin), s=s)
        assert excinfo.value.status_code == 403


def test_public_tracking_masks_pin_and_adds_branding():
    engine = _engine()
    courier.Base.metadata.create_all(engine)
    courier.BFF_BASE_URL = "https://bff.example"
    with Session(engine) as s:
        partner = courier.Partner(id="p1", name="Retailer", brand_text="Hello", logo_url="https://logo", carrier="urbify")
        s.add(partner); s.commit()
        req = courier.OrderCreate(
            pickup_lat=0.0,
            pickup_lng=0.0,
            drop_lat=0.05,
            drop_lng=0.05,
            customer_name="Track",
            customer_phone="+491700000222",
            partner_id=partner.id,
        )
        od = courier.create_order(req=req, s=s)
        track_full = courier.track(od.id, s=s)
        track_public = courier.track_public(od.tracking_token, s=s)
        assert track_full.pin_code is not None
        assert track_public.pin_code is None
        assert track_public.partner_name == partner.name
        assert track_public.partner_brand_text == partner.brand_text
        assert track_public.partner_logo_url == partner.logo_url
        assert track_public.bff_tracking_url.endswith(f"/courier/track/{od.tracking_token}")


def test_reschedule_sets_window_and_short_term_storage():
    engine = _engine()
    courier.Base.metadata.create_all(engine)
    with Session(engine) as s:
        req = courier.OrderCreate(
            pickup_lat=0.0,
            pickup_lng=0.0,
            drop_lat=0.03,
            drop_lng=0.0,
            customer_name="Resched",
            customer_phone="+491700000333",
        )
        od = courier.create_order(req=req, s=s)
        start = (datetime.utcnow() + timedelta(hours=2)).replace(minute=0, second=0, microsecond=0)
        end = start + timedelta(hours=1)
        upd = courier.RescheduleReq(window_start=start, window_end=end, short_term_storage=True)
        od2 = courier.reschedule_order(od.id, upd, s=s)
        assert od2.window_start == start
        assert od2.window_end == end
        assert od2.short_term_storage is True


def test_scans_and_proofs_are_tracked():
    engine = _engine()
    courier.Base.metadata.create_all(engine)
    with Session(engine) as s:
        req = courier.OrderCreate(
            pickup_lat=0.0,
            pickup_lng=0.0,
            drop_lat=0.02,
            drop_lng=0.01,
            customer_name="Scan",
            customer_phone="+491700000444",
        )
        od = courier.create_order(req=req, s=s)
        upd = courier.StatusUpdate(status="pickup", scanned_barcode="PKG123", proof_url="https://proof", barcode="PKG123", signature="sig")
        od2 = courier.update_status(od.id, upd, s=s)
        assert od2.last_scan_code == "PKG123"
        track = courier.track(od.id, s=s)
        assert any(ev["barcode"] == "PKG123" for ev in track.events)


def test_contact_creates_event():
    engine = _engine()
    courier.Base.metadata.create_all(engine)
    with Session(engine) as s:
        req = courier.OrderCreate(
            pickup_lat=0.0,
            pickup_lng=0.0,
            drop_lat=0.01,
            drop_lng=0.02,
            customer_name="Contact",
            customer_phone="+491700000555",
        )
        od = courier.create_order(req=req, s=s)
        courier.contact_support(od.id, courier.ContactReq(message="please call me"), s=s)
        track = courier.track(od.id, s=s)
        assert any(ev["status"] == "contact" for ev in track.events)


def test_slots_endpoint_returns_slots():
    slots = courier.available_slots(service_type="same_day")
    assert slots["service_type"] == "same_day"
    assert slots["slots"]


def test_stats_counts_on_promise_and_filters():
    engine = _engine()
    courier.Base.metadata.create_all(engine)
    with Session(engine) as s:
        req1 = courier.OrderCreate(
            pickup_lat=0.0, pickup_lng=0.0, drop_lat=0.01, drop_lng=0.0,
            customer_name="A", customer_phone="+491700000666", carrier="urbify", partner_id="p1",
        )
        req2 = courier.OrderCreate(
            pickup_lat=0.0, pickup_lng=0.0, drop_lat=0.02, drop_lng=0.0,
            customer_name="B", customer_phone="+491700000667", carrier="other", partner_id="p2",
        )
        od1 = courier.create_order(req=req1, s=s)
        od2 = courier.create_order(req=req2, s=s)
        # mark first delivered on time, second return/out-of-promise
        od1.status = "delivered"; od1.on_promise = True
        od2.status = "return"; od2.on_promise = False; od2.return_required = True
        s.add_all([od1, od2]); s.commit()

        stats_all = courier.stats(s=s)
        assert stats_all.total == 2
        assert stats_all.delivered == 1
        assert stats_all.return_required == 1
        assert stats_all.on_promise == 1

        stats_filtered = courier.stats(carrier="urbify", s=s)
        assert stats_filtered.total == 1
        assert stats_filtered.on_promise == 1


def test_reschedule_rejects_delivered_and_tz_aware():
    engine = _engine()
    courier.Base.metadata.create_all(engine)
    with Session(engine) as s:
        req = courier.OrderCreate(
            pickup_lat=0.0,
            pickup_lng=0.0,
            drop_lat=0.01,
            drop_lng=0.01,
            customer_name="ReschedFail",
            customer_phone="+491700000777",
        )
        od = courier.create_order(req=req, s=s)
        od.status = "delivered"
        s.add(od); s.commit(); s.refresh(od)
        start = datetime.utcnow() + timedelta(hours=2)
        end = start + timedelta(hours=1)
        with pytest.raises(HTTPException):
            courier.reschedule_order(od.id, courier.RescheduleReq(window_start=start, window_end=end), s=s)

        # tz-aware should be rejected
        aware_start = datetime.now().astimezone()
        aware_end = aware_start + timedelta(hours=1)
        od.status = "assigned"
        s.add(od); s.commit(); s.refresh(od)
        with pytest.raises(HTTPException):
            courier.reschedule_order(od.id, courier.RescheduleReq(window_start=aware_start, window_end=aware_end), s=s)


def test_address_validate_falls_back_to_stub():
    res = courier.validate_address(lat=1.23, lng=4.56, address=None)
    assert res["validated_lat"] == 1.23
    assert res["validated_lng"] == 4.56
    assert res["address_confidence"] is None


def test_next_day_slots_are_hourly():
    slots = courier.available_slots(service_type="next_day")["slots"]
    assert len(slots) >= 1
    for slot in slots:
        ws = datetime.fromisoformat(slot["start"])
        we = datetime.fromisoformat(slot["end"])
        assert (we - ws).seconds == 3600


def test_same_day_cutoff_rolls_to_next_day(monkeypatch):
    engine = _engine()
    courier.Base.metadata.create_all(engine)
    # set cutoff to midnight, so current time is always past cutoff
    monkeypatch.setattr(courier, "SAME_DAY_CUTOFF_HOUR", 0)
    monkeypatch.setattr(courier, "SAME_DAY_CUTOFF_MINUTE", 0)
    with Session(engine) as s:
        od = courier.create_order(
            req=courier.OrderCreate(
                pickup_lat=0.0,
                pickup_lng=0.0,
                drop_lat=0.1,
                drop_lng=0.1,
                customer_name="Cutoff",
                customer_phone="+491700000888",
                service_type="same_day",
            ),
            s=s,
        )
        assert od.service_type == "next_day"
        assert od.window_start.hour >= 16


def test_on_promise_turns_false_when_delivered_late():
    engine = _engine()
    courier.Base.metadata.create_all(engine)
    with Session(engine) as s:
        od = courier.create_order(
            req=courier.OrderCreate(
                pickup_lat=0.0,
                pickup_lng=0.0,
                drop_lat=0.01,
                drop_lng=0.0,
                customer_name="Late",
                customer_phone="+491700000889",
            ),
            s=s,
        )
        # force window end in the past
        past_end = datetime.utcnow() - timedelta(hours=1)
        od.window_end = past_end
        s.add(od); s.commit(); s.refresh(od)
        upd = courier.StatusUpdate(status="delivered", pin=od.pin_code)
        od2 = courier.update_status(od.id, upd, s=s)
        assert od2.on_promise is False


def test_reschedule_window_must_be_one_hour():
    engine = _engine()
    courier.Base.metadata.create_all(engine)
    with Session(engine) as s:
        od = courier.create_order(
            req=courier.OrderCreate(
                pickup_lat=0.0,
                pickup_lng=0.0,
                drop_lat=0.02,
                drop_lng=0.02,
                customer_name="ReschedLen",
                customer_phone="+491700000890",
            ),
            s=s,
        )
        start = datetime.utcnow() + timedelta(hours=2)
        with pytest.raises(HTTPException):
            courier.reschedule_order(
                od.id,
                courier.RescheduleReq(window_start=start, window_end=start + timedelta(hours=2)),
                s=s,
            )


def test_apply_become_courier_and_admin_list():
    engine = _engine()
    courier.Base.metadata.create_all(engine)
    with Session(engine) as s:
        app = courier.courier_apply(courier.CourierApply(name="Courier", phone="+491700000321", city="Berlin", vehicle_type="bike", experience_years=2), s=s)
        assert app.status == "pending"
        apps = courier.list_courier_applications(s=s)
        assert len(apps) == 1
        assert apps[0].phone == "+491700000321"


def test_asap_service_type_sets_quick_window(monkeypatch):
    engine = _engine()
    courier.Base.metadata.create_all(engine)
    with Session(engine) as s:
        req = courier.OrderCreate(
            pickup_lat=0.0,
            pickup_lng=0.0,
            drop_lat=0.01,
            drop_lng=0.0,
            customer_name="ASAP",
            customer_phone="+491700000111",
            service_type="asap",
        )
        od = courier.create_order(req=req, s=s)
        assert od.service_type == "asap"
        assert (od.window_start - datetime.utcnow()) < timedelta(hours=1)
        assert (od.window_end - od.window_start) == timedelta(hours=1)


def test_webhook_called_on_status(monkeypatch):
    engine = _engine()
    courier.Base.metadata.create_all(engine)
    calls = {}
    monkeypatch.setattr(courier, "WEBHOOK_URL", "http://webhook")

    def fake_post(url, json=None, timeout=None):
        calls["url"] = url; calls["json"] = json
        class Resp: pass
        return Resp()
    monkeypatch.setattr(courier.httpx, "post", fake_post)
    with Session(engine) as s:
        od = courier.create_order(
            req=courier.OrderCreate(
                pickup_lat=0.0,
                pickup_lng=0.0,
                drop_lat=0.01,
                drop_lng=0.0,
                customer_name="Hook",
                customer_phone="+491700000112",
            ),
            s=s,
        )
        courier.update_status(od.id, courier.StatusUpdate(status="pickup"), s=s)
        assert calls["url"] == "http://webhook"
        assert calls["json"]["event"] == "order_status"
        courier.contact_support(od.id, courier.ContactReq(message="hi"), s=s)
        assert calls["json"]["event"] == "contact"
        ws = (datetime.utcnow() + timedelta(hours=1)).replace(minute=0, second=0, microsecond=0)
        courier.reschedule_order(od.id, courier.RescheduleReq(window_start=ws, window_end=ws + timedelta(hours=1)), s=s)
        assert calls["json"]["event"] == "rescheduled"


def test_partner_kpis_filter_and_rate():
    engine = _engine()
    courier.Base.metadata.create_all(engine)
    with Session(engine) as s:
        # Partner p1 on-promise, p2 return
        o1 = courier.create_order(
            req=courier.OrderCreate(
                pickup_lat=0.0,
                pickup_lng=0.0,
                drop_lat=0.01,
                drop_lng=0.01,
                customer_name="P1",
                customer_phone="+491700000911",
                partner_id="p1",
                service_type="same_day",
            ),
            s=s,
        )
        now = datetime.utcnow()
        o1.status = "delivered"; o1.on_promise = True; o1.window_start = now; o1.window_end = now + timedelta(minutes=30)
        o2 = courier.create_order(
            req=courier.OrderCreate(
                pickup_lat=0.0,
                pickup_lng=0.0,
                drop_lat=0.02,
                drop_lng=0.02,
                customer_name="P2",
                customer_phone="+491700000912",
                partner_id="p2",
                service_type="next_day",
            ),
            s=s,
        )
        o2.status = "return"; o2.on_promise = False; o2.return_required = True; o2.window_start = now; o2.window_end = now + timedelta(minutes=30)
        s.add_all([o1, o2]); s.commit()

        start = (datetime.utcnow() - timedelta(hours=1)).isoformat()
        end = (datetime.utcnow() + timedelta(hours=1)).isoformat()
        kpis = courier.kpis_partners(start_iso=start, end_iso=end, s=s)
        assert any(k.partner_id == "p1" and k.on_promise_rate == 1.0 for k in kpis)
        assert any(k.partner_id == "p2" and k.return_required == 1 for k in kpis)


def test_idempotency_returns_same_order_and_rejects_mismatch():
    engine = _engine()
    courier.Base.metadata.create_all(engine)
    with Session(engine) as s:
        req = courier.OrderCreate(
            pickup_lat=0.0,
            pickup_lng=0.0,
            drop_lat=0.05,
            drop_lng=0.0,
            customer_name="Idem",
            customer_phone="+491700000901",
        )
        od1 = courier.create_order(req=req, idempotency_key="idem-1", s=s)
        # same payload, same key -> returns original
        od2 = courier.create_order(req=req, idempotency_key="idem-1", s=s)
        assert od1.id == od2.id
        # changed payload -> 409
        req2 = courier.OrderCreate(
            pickup_lat=0.1,
            pickup_lng=0.1,
            drop_lat=0.2,
            drop_lng=0.2,
            customer_name="Idem2",
            customer_phone="+491700000902",
        )
        with pytest.raises(HTTPException):
            courier.create_order(req=req2, idempotency_key="idem-1", s=s)
