#!/usr/bin/env bash
set -euo pipefail

# Run the payments_service live-DB integration tests against an ephemeral
# Postgres. Mirrors `scripts/run_bff_integration_tests.sh`.
#
# payments_service/src/handlers.rs carries ~52 #[ignore]'d tests gated on
# SHAMELL_PAYMENTS_TEST_DB_URL (with a fallback to SHAMELL_AUTH_TEST_DB_URL —
# both honoured by `live_postgres_admin_url` in handlers.rs). Each test
# calls `provision_from_env` which CREATEs a fresh per-test database,
# applies the payments schema, runs the test, then DROPs the DB on cleanup.
#
# Why --test-threads=1 by default: several tests use process-global
# `tokio::sync::Notify` hooks (e.g. CreateUserBeforeAccountClaimHook) to
# coordinate the test with the spawned `create_user` task. With parallel
# tests, the second test's hook overwrites the first's — production code
# from test A notifies test B's hook, test A waits on its own forever.
# Serializing the suite sidesteps the issue. Override with
# PAYMENTS_INTEGRATION_TEST_THREADS=N if you've cleaned up the hook design.
#
# Known issues at time of writing (see triage report 2026-05-24):
#   * live_db_create_user_claims_phone_only_user_reuses_wallet_and_backfills_legacy_roles
#       FAILS — production no longer claims a legacy phone-only wallet on
#       create_user; instead creates a fresh UUID wallet. Test pins the
#       claim semantic; intentional change vs regression is undecided.
#   * live_db_create_user_reuses_competing_wallet_created_before_insert
#       HANGS — same hook-without-timeout anti-pattern as the
#       already-fixed `_fails_closed_if_account_id_is_claimed_…` test,
#       but production code path takes a different early-return so the
#       SYP currency fix did not free it.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONTAINER_NAME="${PAYMENTS_INTEGRATION_DB_CONTAINER:-shamell-payments-test-db}"
HOST_PORT="${PAYMENTS_INTEGRATION_DB_PORT:-55435}"
POSTGRES_IMAGE="${PAYMENTS_INTEGRATION_DB_IMAGE:-postgres:16-alpine}"
POSTGRES_PASSWORD="payments-integration-test"
POSTGRES_USER="postgres"
ADMIN_DB="postgres"

cleanup() {
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT
cleanup

echo "[payments-it] starting ephemeral Postgres on :$HOST_PORT ($POSTGRES_IMAGE)"
docker run \
  --rm \
  --detach \
  --name "$CONTAINER_NAME" \
  --publish "127.0.0.1:${HOST_PORT}:5432" \
  --env "POSTGRES_PASSWORD=${POSTGRES_PASSWORD}" \
  --health-cmd "pg_isready -U ${POSTGRES_USER}" \
  --health-interval 1s \
  --health-retries 30 \
  --health-timeout 2s \
  "$POSTGRES_IMAGE" >/dev/null

echo "[payments-it] waiting for postgres to accept connections"
for attempt in $(seq 1 60); do
  state="$(docker inspect --format '{{.State.Health.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo missing)"
  case "$state" in
    healthy)
      break
      ;;
    unhealthy|missing)
      echo "[payments-it] postgres container is $state, aborting" >&2
      docker logs "$CONTAINER_NAME" >&2 || true
      exit 1
      ;;
  esac
  sleep 1
  if [[ "$attempt" == "60" ]]; then
    echo "[payments-it] postgres did not become healthy within 60s" >&2
    docker logs "$CONTAINER_NAME" >&2 || true
    exit 1
  fi
done

export SHAMELL_PAYMENTS_TEST_DB_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@127.0.0.1:${HOST_PORT}/${ADMIN_DB}"
echo "[payments-it] SHAMELL_PAYMENTS_TEST_DB_URL=$SHAMELL_PAYMENTS_TEST_DB_URL"

echo "[payments-it] running #[ignore]'d integration tests"
# Default to single-threaded for the hook-collision reason documented in
# the header. Operators can opt back into parallel with the env var.
test_threads="${PAYMENTS_INTEGRATION_TEST_THREADS:-1}"
cargo test \
  -p shamell_payments_service \
  --lib \
  -- --ignored "--test-threads=${test_threads}"

echo "[payments-it] payments_service integration tests passed"
