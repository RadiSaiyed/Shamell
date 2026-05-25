#!/usr/bin/env bash
set -euo pipefail

# Run the chat_service live-DB integration tests against an ephemeral Postgres.
#
# Mirrors `scripts/run_bff_integration_tests.sh`. chat_service/src/handlers.rs
# carries ~44 #[ignore]'d tests gated on SHAMELL_CHAT_TEST_DB_URL (with a
# fallback to SHAMELL_AUTH_TEST_DB_URL — both honoured by
# `live_postgres_admin_url` in handlers.rs). Each test calls
# `provision_from_env` which CREATEs a fresh per-test database, applies the
# chat schema, runs the test, then DROPs the DB on cleanup.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONTAINER_NAME="${CHAT_INTEGRATION_DB_CONTAINER:-shamell-chat-test-db}"
HOST_PORT="${CHAT_INTEGRATION_DB_PORT:-55434}"
POSTGRES_IMAGE="${CHAT_INTEGRATION_DB_IMAGE:-postgres:16-alpine}"
POSTGRES_PASSWORD="chat-integration-test"
POSTGRES_USER="postgres"
ADMIN_DB="postgres"

cleanup() {
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT
cleanup

echo "[chat-it] starting ephemeral Postgres on :$HOST_PORT ($POSTGRES_IMAGE)"
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

echo "[chat-it] waiting for postgres to accept connections"
for attempt in $(seq 1 60); do
  state="$(docker inspect --format '{{.State.Health.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo missing)"
  case "$state" in
    healthy)
      break
      ;;
    unhealthy|missing)
      echo "[chat-it] postgres container is $state, aborting" >&2
      docker logs "$CONTAINER_NAME" >&2 || true
      exit 1
      ;;
  esac
  sleep 1
  if [[ "$attempt" == "60" ]]; then
    echo "[chat-it] postgres did not become healthy within 60s" >&2
    docker logs "$CONTAINER_NAME" >&2 || true
    exit 1
  fi
done

export SHAMELL_CHAT_TEST_DB_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@127.0.0.1:${HOST_PORT}/${ADMIN_DB}"
echo "[chat-it] SHAMELL_CHAT_TEST_DB_URL=$SHAMELL_CHAT_TEST_DB_URL"

echo "[chat-it] running #[ignore]'d integration tests"
test_threads_arg=()
if [[ -n "${CHAT_INTEGRATION_TEST_THREADS:-}" ]]; then
  test_threads_arg=("--test-threads=${CHAT_INTEGRATION_TEST_THREADS}")
fi
cargo test \
  -p shamell_chat_service \
  --lib \
  -- --ignored ${test_threads_arg[@]+"${test_threads_arg[@]}"}

echo "[chat-it] chat_service integration tests passed"
