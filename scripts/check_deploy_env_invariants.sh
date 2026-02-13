#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
errors=0

ok() {
  echo "[OK]   $1"
}

fail() {
  echo "[FAIL] $1" >&2
  errors=1
}

require_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    fail "Missing file: $path"
    return 1
  fi
  return 0
}

require_regex() {
  local path="$1"
  local pattern="$2"
  local label="$3"
  if rg -n --quiet -e "$pattern" "$path"; then
    ok "$path: $label"
  else
    fail "$path: missing $label"
  fi
}

require_absent() {
  local path="$1"
  local pattern="$2"
  local label="$3"
  if rg -n --quiet -e "$pattern" "$path"; then
    fail "$path: contains forbidden $label"
  else
    ok "$path: no forbidden $label"
  fi
}

check_env_template() {
  local rel="$1"
  local file="$ROOT/$rel"
  if ! require_file "$file"; then
    return
  fi

  require_regex "$file" '^BFF_REQUIRE_INTERNAL_SECRET=true$' 'BFF_REQUIRE_INTERNAL_SECRET=true'
  require_regex "$file" '^BFF_ENFORCE_ROUTE_AUTHZ=true$' 'BFF_ENFORCE_ROUTE_AUTHZ=true'
  require_regex "$file" '^CSRF_GUARD_ENABLED=true$' 'CSRF_GUARD_ENABLED=true'
  require_regex "$file" '^AUTH_ALLOW_HEADER_SESSION_AUTH=false$' 'AUTH_ALLOW_HEADER_SESSION_AUTH=false'
  require_regex "$file" '^AUTH_EXPOSE_CODES=false$' 'AUTH_EXPOSE_CODES=false'
  require_regex "$file" '^CSP_ENABLED=true$' 'CSP_ENABLED=true'
  require_regex "$file" '^AUTH_CHAT_REGISTER_WINDOW_SECS=[0-9]+$' 'AUTH_CHAT_REGISTER_WINDOW_SECS set'
  require_regex "$file" '^AUTH_CHAT_REGISTER_MAX_PER_IP=[0-9]+$' 'AUTH_CHAT_REGISTER_MAX_PER_IP set'
  require_regex "$file" '^AUTH_CHAT_REGISTER_MAX_PER_DEVICE=[0-9]+$' 'AUTH_CHAT_REGISTER_MAX_PER_DEVICE set'
  require_regex "$file" '^AUTH_CHAT_GET_DEVICE_WINDOW_SECS=[0-9]+$' 'AUTH_CHAT_GET_DEVICE_WINDOW_SECS set'
  require_regex "$file" '^AUTH_CHAT_GET_DEVICE_MAX_PER_IP=[0-9]+$' 'AUTH_CHAT_GET_DEVICE_MAX_PER_IP set'
  require_regex "$file" '^AUTH_CHAT_GET_DEVICE_MAX_PER_DEVICE=[0-9]+$' 'AUTH_CHAT_GET_DEVICE_MAX_PER_DEVICE set'
  require_absent "$file" '^CHAT_ALLOW_LEGACY_AUTH_BOOTSTRAP=' 'CHAT_ALLOW_LEGACY_AUTH_BOOTSTRAP'
}

check_compose_defaults() {
  local rel="$1"
  local file="$ROOT/$rel"
  if ! require_file "$file"; then
    return
  fi

  require_regex "$file" 'BFF_REQUIRE_INTERNAL_SECRET:[[:space:]]*"\$\{BFF_REQUIRE_INTERNAL_SECRET:-true\}"' 'BFF_REQUIRE_INTERNAL_SECRET default true'
  require_regex "$file" 'BFF_ENFORCE_ROUTE_AUTHZ:[[:space:]]*"\$\{BFF_ENFORCE_ROUTE_AUTHZ:-true\}"' 'BFF_ENFORCE_ROUTE_AUTHZ default true'
  require_regex "$file" 'AUTH_ALLOW_HEADER_SESSION_AUTH:[[:space:]]*"\$\{AUTH_ALLOW_HEADER_SESSION_AUTH:-false\}"' 'AUTH_ALLOW_HEADER_SESSION_AUTH default false'
  require_regex "$file" 'AUTH_EXPOSE_CODES:[[:space:]]*"\$\{AUTH_EXPOSE_CODES:-false\}"' 'AUTH_EXPOSE_CODES default false'
  require_regex "$file" 'CSP_ENABLED:[[:space:]]*"\$\{CSP_ENABLED:-true\}"' 'CSP_ENABLED default true'
  require_regex "$file" 'AUTH_CHAT_REGISTER_WINDOW_SECS:[[:space:]]*"\$\{AUTH_CHAT_REGISTER_WINDOW_SECS:-300\}"' 'AUTH_CHAT_REGISTER_WINDOW_SECS default'
  require_regex "$file" 'AUTH_CHAT_REGISTER_MAX_PER_IP:[[:space:]]*"\$\{AUTH_CHAT_REGISTER_MAX_PER_IP:-40\}"' 'AUTH_CHAT_REGISTER_MAX_PER_IP default'
  require_regex "$file" 'AUTH_CHAT_REGISTER_MAX_PER_DEVICE:[[:space:]]*"\$\{AUTH_CHAT_REGISTER_MAX_PER_DEVICE:-20\}"' 'AUTH_CHAT_REGISTER_MAX_PER_DEVICE default'
  require_regex "$file" 'AUTH_CHAT_GET_DEVICE_WINDOW_SECS:[[:space:]]*"\$\{AUTH_CHAT_GET_DEVICE_WINDOW_SECS:-300\}"' 'AUTH_CHAT_GET_DEVICE_WINDOW_SECS default'
  require_regex "$file" 'AUTH_CHAT_GET_DEVICE_MAX_PER_IP:[[:space:]]*"\$\{AUTH_CHAT_GET_DEVICE_MAX_PER_IP:-80\}"' 'AUTH_CHAT_GET_DEVICE_MAX_PER_IP default'
  require_regex "$file" 'AUTH_CHAT_GET_DEVICE_MAX_PER_DEVICE:[[:space:]]*"\$\{AUTH_CHAT_GET_DEVICE_MAX_PER_DEVICE:-40\}"' 'AUTH_CHAT_GET_DEVICE_MAX_PER_DEVICE default'
  require_absent "$file" 'CHAT_ALLOW_LEGACY_AUTH_BOOTSTRAP' 'CHAT_ALLOW_LEGACY_AUTH_BOOTSTRAP'
}

check_root_env_example() {
  local rel="$1"
  local file="$ROOT/$rel"
  if ! require_file "$file"; then
    return
  fi

  # Root .env.example should fail-safe by default for auth hardening.
  require_regex "$file" '^BFF_REQUIRE_INTERNAL_SECRET=true$' 'BFF_REQUIRE_INTERNAL_SECRET=true'
  require_regex "$file" '^AUTH_EXPOSE_CODES=false$' 'AUTH_EXPOSE_CODES=false'
}

check_root_compose_defaults() {
  local rel="$1"
  local file="$ROOT/$rel"
  if ! require_file "$file"; then
    return
  fi

  # Root docker-compose defaults must not expose auth codes and must
  # require internal-secret enforcement by default.
  require_regex "$file" 'BFF_REQUIRE_INTERNAL_SECRET:[[:space:]]*"\$\{BFF_REQUIRE_INTERNAL_SECRET:-true\}"' 'BFF_REQUIRE_INTERNAL_SECRET default true'
  require_regex "$file" 'AUTH_EXPOSE_CODES:[[:space:]]*"\$\{AUTH_EXPOSE_CODES:-false\}"' 'AUTH_EXPOSE_CODES default false'
}

check_env_template "ops/pi/env.prod.example"
check_env_template "ops/pi/env.staging.example"
check_compose_defaults "ops/pi/docker-compose.yml"
check_compose_defaults "ops/pi/docker-compose.postgres.yml"
check_root_env_example ".env.example"
check_root_compose_defaults "docker-compose.yml"

if (( errors != 0 )); then
  exit 1
fi

echo "Deployment env invariants check passed."
