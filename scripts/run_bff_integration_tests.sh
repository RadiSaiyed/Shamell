#!/usr/bin/env bash
set -euo pipefail

# Run the bff_gateway live-DB integration tests against an ephemeral Postgres.
#
# bff_gateway/src/auth.rs carries ~30 #[ignore]'d tests gated on
# SHAMELL_AUTH_TEST_DB_URL. Each one calls `LiveAuthTestDb::provision_from_env`
# which CREATEs a fresh isolated database per test, applies the versioned
# auth migrations, runs the test, then DROPs the DB on cleanup. So the
# env var needs to point at an ADMIN-level URL (a database the connecting
# role can CREATE/DROP from) — typically the `postgres` superuser DB.
#
# Mirrors `scripts/run_hotels_integration_tests.sh` in shape and intent:
# self-contained, parallel-safe, container teardown via trap.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONTAINER_NAME="${BFF_INTEGRATION_DB_CONTAINER:-shamell-bff-test-db}"
HOST_PORT="${BFF_INTEGRATION_DB_PORT:-55433}"
POSTGRES_IMAGE="${BFF_INTEGRATION_DB_IMAGE:-postgres:16-alpine}"
POSTGRES_PASSWORD="bff-integration-test"
# Connect as `postgres` superuser to the default `postgres` admin DB
# so the per-test framework can CREATE / DROP databases freely.
POSTGRES_USER="postgres"
ADMIN_DB="postgres"

cleanup() {
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT
cleanup

echo "[bff-it] starting ephemeral Postgres on :$HOST_PORT ($POSTGRES_IMAGE)"
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

echo "[bff-it] waiting for postgres to accept connections"
for attempt in $(seq 1 60); do
  state="$(docker inspect --format '{{.State.Health.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo missing)"
  case "$state" in
    healthy)
      break
      ;;
    unhealthy|missing)
      echo "[bff-it] postgres container is $state, aborting" >&2
      docker logs "$CONTAINER_NAME" >&2 || true
      exit 1
      ;;
  esac
  sleep 1
  if [[ "$attempt" == "60" ]]; then
    echo "[bff-it] postgres did not become healthy within 60s" >&2
    docker logs "$CONTAINER_NAME" >&2 || true
    exit 1
  fi
done

export SHAMELL_AUTH_TEST_DB_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@127.0.0.1:${HOST_PORT}/${ADMIN_DB}"
echo "[bff-it] SHAMELL_AUTH_TEST_DB_URL=$SHAMELL_AUTH_TEST_DB_URL"

# The bff_gateway lib test suite is the largest in the repo (~1200
# non-ignored tests). `--ignored` runs ONLY the gated ones; everything
# else is already covered by plain `cargo test`.
# `--test-threads` is left at the default — each test provisions its
# own isolated database so they parallelize cleanly. If a flake shows
# up, set BFF_INTEGRATION_TEST_THREADS to a smaller number.
echo "[bff-it] running #[ignore]'d integration tests"
test_threads_arg=()
if [[ -n "${BFF_INTEGRATION_TEST_THREADS:-}" ]]; then
  test_threads_arg=("--test-threads=${BFF_INTEGRATION_TEST_THREADS}")
fi
cargo test \
  -p shamell_bff_gateway \
  --lib \
  -- --ignored ${test_threads_arg[@]+"${test_threads_arg[@]}"}

echo "[bff-it] bff_gateway integration tests passed"
