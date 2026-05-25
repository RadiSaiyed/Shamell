#!/usr/bin/env bash
set -euo pipefail

# Run the hotels_service integration tests against an ephemeral Postgres.
#
# These tests are gated on HOTELS_TEST_DB_URL and are #[ignore]'d by
# default — without this script someone has to set the env var by hand
# and manage their own postgres. We spin up a throwaway container on
# a non-default port (so it cannot collide with a docker-compose `db`
# the dev may already be running), wait until it is ready, run the
# tests, then stop the container on exit no matter how the run ended.
#
# Why an ephemeral container instead of reusing the docker-compose
# stack: keeps the test suite self-contained and parallel-safe — the
# dev DB has live mutable data the operator may be debugging against,
# and the test cleanup helpers TRUNCATE-style delete by hotel_id which
# is fine in a sandbox but rude against shared state.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONTAINER_NAME="${HOTELS_INTEGRATION_DB_CONTAINER:-shamell-hotels-test-db}"
HOST_PORT="${HOTELS_INTEGRATION_DB_PORT:-55432}"
POSTGRES_IMAGE="${HOTELS_INTEGRATION_DB_IMAGE:-postgres:16-alpine}"
POSTGRES_PASSWORD="hotels-integration-test"
POSTGRES_DB="hotels_test"

cleanup() {
  # Best-effort container teardown so a failed test does not leak the
  # postgres process. -f silences "no such container" on early aborts.
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# If a previous run left the container around (Ctrl-C during the wait
# loop, kernel kill, ...), wipe it first so the fresh `docker run`
# below does not collide on the name.
cleanup

echo "[hotels-it] starting ephemeral Postgres on :$HOST_PORT ($POSTGRES_IMAGE)"
docker run \
  --rm \
  --detach \
  --name "$CONTAINER_NAME" \
  --publish "127.0.0.1:${HOST_PORT}:5432" \
  --env "POSTGRES_PASSWORD=${POSTGRES_PASSWORD}" \
  --env "POSTGRES_DB=${POSTGRES_DB}" \
  --health-cmd "pg_isready -U postgres" \
  --health-interval 1s \
  --health-retries 30 \
  --health-timeout 2s \
  "$POSTGRES_IMAGE" >/dev/null

echo "[hotels-it] waiting for postgres to accept connections"
for attempt in $(seq 1 60); do
  state="$(docker inspect --format '{{.State.Health.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo missing)"
  case "$state" in
    healthy)
      break
      ;;
    unhealthy|missing)
      echo "[hotels-it] postgres container is $state, aborting" >&2
      docker logs "$CONTAINER_NAME" >&2 || true
      exit 1
      ;;
  esac
  sleep 1
  if [[ "$attempt" == "60" ]]; then
    echo "[hotels-it] postgres did not become healthy within 60s" >&2
    docker logs "$CONTAINER_NAME" >&2 || true
    exit 1
  fi
done

export HOTELS_TEST_DB_URL="postgresql://postgres:${POSTGRES_PASSWORD}@127.0.0.1:${HOST_PORT}/${POSTGRES_DB}"
echo "[hotels-it] HOTELS_TEST_DB_URL=$HOTELS_TEST_DB_URL"

# `--ignored` runs ONLY the #[ignore]'d tests (the integration set);
# the rest of the lib test suite is already covered by plain
# `cargo test`. `--include-ignored` would also pull the lib tests
# back in for no benefit and double the runtime.
#
# `--test-threads=1` is required: hotels uses one shared database (vs
# the per-test-DB pattern bff/chat/payments use), and `apply_migrations`
# does `CREATE TABLE IF NOT EXISTS __hotels_schema_migrations` — when
# two tests race that statement concurrently Postgres explodes with
# `duplicate key value violates unique constraint
# "pg_type_typname_nsp_index"`. Until hotels grows the per-test-DB
# helper, serialize.
echo "[hotels-it] running integration tests"
test_threads="${HOTELS_INTEGRATION_TEST_THREADS:-1}"
cargo test \
  -p shamell_hotels_service \
  --test settlement_payout_idempotency_test \
  -- --ignored --nocapture "--test-threads=${test_threads}"

echo "[hotels-it] integration tests passed"
