#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
errors=0

fail() {
  echo "[FAIL] $1" >&2
  errors=1
}

ok() {
  echo "[OK]   $1"
}

compose_files=()
while IFS= read -r rel; do
  compose_files+=("$rel")
done < <(cd "$ROOT" && find . -type f \( -name 'docker-compose*.yml' -o -name 'docker-compose*.yaml' \) | sort)

if (( ${#compose_files[@]} == 0 )); then
  fail "no docker-compose files found"
fi

for rel in "${compose_files[@]}"; do
  file="$ROOT/$rel"

  while IFS= read -r row; do
    lineno="${row%%:*}"
    line="${row#*:}"
    trimmed="${line#${line%%[![:space:]]*}}"
    [[ -z "$trimmed" || "$trimmed" == \#* ]] && continue

    if [[ "$line" =~ 808([123]):808\1 ]]; then
      port="${BASH_REMATCH[1]}"
      if [[ "$line" =~ (127\.0\.0\.1|localhost|\[::1\]|::1|\$\{[^}]*127\.0\.0\.1[^}]*\}).*808${port}:808${port} ]]; then
        :
      else
        fail "$rel:$lineno exposes 808${port} without explicit localhost binding"
      fi
    fi
  done < <(nl -ba "$file" | sed 's/^ *//')

  while IFS= read -r row; do
    lineno="${row%%:*}"
    port="$(echo "$row" | sed -E 's/.*target:[[:space:]]*(808[123]).*/\1/')"
    block="$(sed -n "${lineno},$((lineno+8))p" "$file")"
    if echo "$block" | rg -Eq 'host_ip:[[:space:]]*(127\.0\.0\.1|localhost|::1|\[::1\]|\$\{[^}]*127\.0\.0\.1[^}]*\})'; then
      :
    else
      fail "$rel:$lineno long-syntax mapping for ${port} missing localhost host_ip"
    fi
  done < <(nl -ba "$file" | sed 's/^ *//' | rg 'target:[[:space:]]*808[123]\b' || true)
done

# On the API host compose files, LiveKit RTC ports should not default to public
# bind addresses. Public RTC should run on a dedicated host (ops/livekit).
for rel in "./ops/pi/docker-compose.yml" "./ops/pi/docker-compose.postgres.yml"; do
  file="$ROOT/$rel"
  [[ -f "$file" ]] || continue
  if rg -n --quiet '\$\{LIVEKIT_RTC_PUBLISH_ADDR:-0\.0\.0\.0\}' "$file"; then
    fail "$rel defaults LIVEKIT_RTC_PUBLISH_ADDR to 0.0.0.0; keep API host RTC local by default"
  fi
done

if (( errors != 0 )); then
  exit 1
fi

echo "Internal port exposure guard passed."
