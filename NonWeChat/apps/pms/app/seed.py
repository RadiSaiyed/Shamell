import argparse
from datetime import date, timedelta

from sqlalchemy.orm import Session

from apps.pms.app.main import (
    Base,
    Charge,
    DailyRate,
    Folio,
    Guest,
    Property,
    RatePlan,
    Reservation,
    ReservationRoom,
    Room,
    RoomType,
    engine,
)


def seed_demo(reset: bool = False):
    if reset:
        Base.metadata.drop_all(engine)
    Base.metadata.create_all(engine)

    today = date.today()
    with Session(engine) as s:
        prop = s.query(Property).first()
        if not prop:
            prop = Property(name="Shamell Demo Hotel", city="Berlin", timezone="Europe/Berlin", currency="EUR")
            s.add(prop)
            s.flush()

        rt_std = s.query(RoomType).filter_by(property_id=prop.id, code="STD-QUEEN").first()
        if not rt_std:
            rt_std = RoomType(
                property_id=prop.id,
                code="STD-QUEEN",
                name="Standard Queen",
                base_occupancy=1,
                max_occupancy=2,
            )
            s.add(rt_std)
            s.flush()

        rt_dlx = s.query(RoomType).filter_by(property_id=prop.id, code="DLX-KING").first()
        if not rt_dlx:
            rt_dlx = RoomType(
                property_id=prop.id,
                code="DLX-KING",
                name="Deluxe King",
                base_occupancy=2,
                max_occupancy=3,
            )
            s.add(rt_dlx)
            s.flush()

        rooms = [
            (rt_std.id, "101"),
            (rt_std.id, "102"),
            (rt_dlx.id, "201"),
            (rt_dlx.id, "202"),
        ]
        for rt_id, num in rooms:
            if not s.query(Room).filter_by(property_id=prop.id, number=num).first():
                s.add(Room(property_id=prop.id, room_type_id=rt_id, number=num))

        rp_bar = s.query(RatePlan).filter_by(property_id=prop.id, code="BAR").first()
        if not rp_bar:
            rp_bar = RatePlan(
                property_id=prop.id,
                code="BAR",
                name="Best Available Rate",
                room_type_id=None,
                base_rate_cents=12000,
                currency=prop.currency,
                is_public=True,
            )
            s.add(rp_bar)
            s.flush()

        # Seed daily rates for the next 30 days for both room types
        for offset in range(0, 30):
            d = today + timedelta(days=offset)
            for rt_id in (rt_std.id, rt_dlx.id):
                amount = rp_bar.base_rate_cents + (1500 if rt_id == rt_dlx.id else 0)
                s.merge(
                    DailyRate(
                        property_id=prop.id,
                        rate_plan_id=rp_bar.id,
                        room_type_id=rt_id,
                        date=d,
                        amount_cents=amount,
                        currency=rp_bar.currency,
                    )
                )

        guest = s.query(Guest).filter_by(property_id=prop.id, email="guest@example.com").first()
        if not guest:
            guest = Guest(property_id=prop.id, first_name="Demo", last_name="Guest", email="guest@example.com")
            s.add(guest)
            s.flush()

        res = s.query(Reservation).first()
        if not res:
            res = Reservation(
                property_id=prop.id,
                guest_id=guest.id,
                status="confirmed",
                source="direct",
                check_in_date=today + timedelta(days=1),
                check_out_date=today + timedelta(days=4),
                adults=2,
                children=0,
                room_type_id=rt_std.id,
                rate_plan_id=rp_bar.id,
                total_amount_cents=rp_bar.base_rate_cents * 3,
                currency=rp_bar.currency,
            )
            s.add(res)
            s.flush()
            s.add(
                ReservationRoom(
                    reservation_id=res.id,
                    room_id=s.query(Room).filter_by(property_id=prop.id, room_type_id=rt_std.id).first().id,  # type: ignore[arg-type]
                    arrival_date=res.check_in_date,
                    departure_date=res.check_out_date,
                    status="assigned",
                )
            )
            folio = Folio(reservation_id=res.id, is_master=True, name="Guest")
            s.add(folio)
            s.flush()
            s.add(
                Charge(
                    folio_id=folio.id,
                    post_date=res.check_in_date,
                    description="Lodging",
                    amount_cents=res.total_amount_cents,
                    currency=res.currency,
                    kind="charge",
                    tax_included=True,
                )
            )

        s.commit()


def main():
    parser = argparse.ArgumentParser(description="Seed demo PMS data.")
    parser.add_argument("--reset", action="store_true", help="Drop and recreate schema before seeding.")
    args = parser.parse_args()
    seed_demo(reset=args.reset)
    print("PMS demo data seeded.")


if __name__ == "__main__":
    main()
