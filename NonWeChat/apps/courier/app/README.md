Courier-lite (Urbify-like)
===========================

Simplified courier/delivery service inspired by Urbify:

- Orders with same-day/next-day service_type, delivery windows, PIN handover, failed-attempts/return flow
- Quote includes window, ETA, CO₂ estimate
- Reschedule endpoint, contact log
- Public tracking by token; PIN required for delivery status
- WebSocket `/courier/ws` for driver/order updates (dev-only in-memory broadcast)

Env:
- `COURIER_DB_URL` (default sqlite at /tmp)

Run:
```
uvicorn apps.courier.app.main:app --reload
```
