# Shamell Internal E2E Report (Backend + Frontend + DB)

Date: 2026-03-07  
Environment: local dev (127.0.0.1)  
Script: `scripts/e2e_internal.sh --with-frontend`

## Run Summary

Status: **PASS**

- Backend health checks: `chat`, `payments`, `bus`, `bff` all healthy
- 2 test accounts created successfully
- Chat device registration + invite redeem + direct message flow succeeded
- Payments topup + transfer flow succeeded
- DB row counts and balances matched expected outcomes
- Flutter `analyze` and full `flutter test` suite passed

## Executed Command

```bash
./scripts/e2e_internal.sh --with-frontend
```

## Concrete Results (2026-03-07 Run)

### Accounts
- Account A shamell_id: `SBHDQ53V`
- Account B shamell_id: `ZVTX56KA`

### Wallets
- Wallet A: `3565febe-083a-4af6-96b2-a2e545088f0a`
- Wallet B: `302dc0ac-565b-4d5a-ac3f-5d9757150369`

### API Checks
- `account_create(A/B)`: `200 / 200`
- `chat_inbox_count(B)`: `1`
- `payments_topup(A)`: `200`
- `payments_transfer(A->B)`: `200`

### DB Summaries
- `core (accounts|sessions|chat_devices|invites|contacts)`: `2|2|2|1|2`
- `chat (devices|messages)`: `2|1`
- `chat last (sender|recipient|sealed)`: `deva964b|devb964b|true`
- `payments (users|wallets|txns|idempotency)`: `2|2|2|2`
- Wallet balances:
  - `302dc0ac-565b-4d5a-ac3f-5d9757150369:1200`
  - `3565febe-083a-4af6-96b2-a2e545088f0a:3800`

### Log Location
- `/tmp/shamell-e2e-run-20260307-231447`

## Release Checklist (Reusable)

Use this as the minimal pre-release internal smoke gate.

1. Start with clean local dependencies:
   - PostgreSQL reachable on `127.0.0.1:5432`
   - Required tools installed: `curl`, `jq`, `openssl`, `psql`, `createdb`, `pg_isready`
2. Run full internal E2E with frontend:
   - `./scripts/e2e_internal.sh --with-frontend`
   - or `make e2e-internal` (exports artifacts to `.artifacts/e2e`)
3. Verify script exits with code `0`.
4. Confirm in output:
   - all service health checks are `ok`
   - both account creations are `200`
   - inbox count for account B is `>= 1`
   - payments topup and transfer are `200`
5. Confirm DB summaries are coherent:
   - `auth_accounts >= 2`
   - `chat messages >= 1`
   - `payments txns >= 2` and idempotency rows present
6. Confirm Flutter quality gate:
   - `flutter analyze` has no issues
   - `flutter test` passes fully
7. Archive the generated `/tmp/shamell-e2e-run-*` logs if this run is used as a release evidence artifact.

## Fast Triage If Failing

1. Open script-generated service logs in the reported `/tmp/shamell-e2e-run-*` folder.
2. Re-run backend-only smoke first:
   - `./scripts/e2e_internal.sh`
3. If backend passes, isolate frontend:
   - `cd clients/shamell_flutter && flutter analyze && flutter test`
4. If DB bootstrap fails, validate role/db setup:
   - role `shamell` exists
   - databases `shamell_core`, `shamell_chat`, `shamell_payments`, `shamell_bus` exist
