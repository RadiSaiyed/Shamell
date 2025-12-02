# Doctors – booking flow quickstart

Minimal steps to exercise the Doctolib-style flow (search → slot → book → reschedule/cancel).

## Start (monolith or service)
- Monolith: `uvicorn apps.monolith.app.main:app --reload --port 8080`
- Doctors only: `uvicorn apps.doctors.app.main:app --reload --port 18080`

Ensure the DB is clean if you were on the old schema (delete `/tmp/doctors.db` or migrate the new columns).

Optional: seed demo doctors for local testing by setting `DOCTORS_DEMO_SEED=1` (only seeds when the doctors table is empty).

## Create a doctor
```bash
curl -X POST http://localhost:8080/doctors/doctors \
  -H 'Content-Type: application/json' \
  -d '{"name":"Dr. Müller","speciality":"Allgemeinmedizin","city":"Berlin","timezone":"Europe/Berlin"}'
```
This seeds default availability (Mon–Fri, 09:00–17:00, 20-min slots).

## List doctors
```bash
curl 'http://localhost:8080/doctors/doctors?q=müller&city=berlin'
```

## Adjust availability (optional)
```bash
curl -X PUT http://localhost:8080/doctors/doctors/1/availability \
  -H 'Content-Type: application/json' \
  -d '[{"weekday":0,"start_time":"09:00","end_time":"12:00","slot_minutes":20},
       {"weekday":0,"start_time":"14:00","end_time":"17:00","slot_minutes":20}]'
```

## Fetch slots
```bash
curl 'http://localhost:8080/doctors/slots?doctor_id=1&days=7'
```

## Book an appointment
```bash
curl -X POST http://localhost:8080/doctors/appointments \
  -H 'Content-Type: application/json' \
  -d '{"doctor_id":1,"patient_name":"Alice","patient_phone":"+491234","patient_email":"alice@example.com","reason":"Fever","ts_iso":"2024-10-01T09:20:00+02:00","duration_minutes":20}'
```
Response includes `id` for later actions.

## Reschedule
```bash
curl -X POST http://localhost:8080/doctors/appointments/<ID>/reschedule \
  -H 'Content-Type: application/json' \
  -d '{"ts_iso":"2024-10-01T10:00:00+02:00","duration_minutes":20}'
```

## Cancel
```bash
curl -X POST http://localhost:8080/doctors/appointments/<ID>/cancel
```

## Operator web UI
- Open `http://localhost:8080/doctors` (monolith) to use the embedded booking console: search doctors, select slot, book, reschedule, cancel. Raw JSON output is shown on the page for debugging.
