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

require_contains() {
  local path="$1"
  local needle="$2"
  local label="$3"
  if rg -F --quiet -- "$needle" "$path"; then
    ok "$path: $label"
  else
    fail "$path: missing $label"
  fi
}

require_count_at_least() {
  local path="$1"
  local needle="$2"
  local min_count="$3"
  local label="$4"
  local count
  count="$(rg -F -o -- "$needle" "$path" | wc -l | tr -d '[:space:]')"
  if [[ "$count" =~ ^[0-9]+$ ]] && (( count >= min_count )); then
    ok "$path: $label ($count)"
  else
    fail "$path: expected >= $min_count occurrences of $label, found ${count:-0}"
  fi
}

require_internal_block() {
  local path="$1"
  if rg -U --quiet 'location\s+\^~\s+/internal/\s*\{[^}]*return\s+404;' "$path"; then
    ok "$path: blocks public /internal/* routes"
  else
    fail "$path: missing public /internal/* 404 block"
  fi
}

require_docs_openapi_allowlist() {
  local path="$1"
  if rg -U --quiet 'location\s+=\s+/openapi\.json\s*\{[^}]*include\s+/etc/nginx/snippets/shamell_docs_allowlist\.local\.conf;[^}]*deny\s+all;' "$path"; then
    ok "$path: /openapi.json uses local allowlist + deny-all"
  else
    fail "$path: missing strict /openapi.json local allowlist + deny-all"
  fi

  if rg -U --quiet 'location\s+=\s+/docs\s*\{[^}]*include\s+/etc/nginx/snippets/shamell_docs_allowlist\.local\.conf;[^}]*deny\s+all;' "$path"; then
    ok "$path: /docs uses local allowlist + deny-all"
  else
    fail "$path: missing strict /docs local allowlist + deny-all"
  fi
}

edge_snippet="$ROOT/ops/hetzner/nginx/snippets/shamell_bff_edge_hardening.conf"
log_formats="$ROOT/ops/hetzner/nginx/conf.d/shamell_log_formats.conf"
local_example="$ROOT/ops/hetzner/nginx/snippets/shamell_bff_role_attestation.local.conf.example"
internal_example="$ROOT/ops/hetzner/nginx/snippets/shamell_bff_internal_auth.local.conf.example"
docs_allowlist_example="$ROOT/ops/hetzner/nginx/snippets/shamell_docs_allowlist.local.conf.example"

if require_file "$edge_snippet"; then
  require_contains "$edge_snippet" 'proxy_set_header X-Internal-Secret "";' 'strip X-Internal-Secret'
  require_contains "$edge_snippet" 'include /etc/nginx/snippets/shamell_bff_internal_auth.local.conf;' 'include host-local internal auth snippet'
  require_contains "$edge_snippet" 'proxy_set_header X-Internal-Service-Id "edge";' 'set trusted edge caller id'
  require_contains "$edge_snippet" 'proxy_set_header X-Shamell-Client-IP $remote_addr;' 'set edge-attested client ip header'
  require_contains "$edge_snippet" 'proxy_set_header X-Auth-Roles "";' 'strip X-Auth-Roles'
  require_contains "$edge_snippet" 'proxy_set_header X-Roles "";' 'strip X-Roles'
  require_contains "$edge_snippet" 'proxy_set_header X-Role-Auth "";' 'strip X-Role-Auth'
  require_contains "$edge_snippet" 'include /etc/nginx/snippets/shamell_bff_role_attestation.local.conf;' 'include host-local attestation snippet'
fi

if require_file "$log_formats"; then
  require_contains "$log_formats" "log_format shamell_noquery" "defines no-query access log format"
  require_contains "$log_formats" '$uri' "omits query strings via \$uri"
fi

if [[ -f "$local_example" ]]; then
  ok "$local_example: present"
else
  fail "Missing file: $local_example"
fi

if [[ -f "$internal_example" ]]; then
  ok "$internal_example: present"
else
  fail "Missing file: $internal_example"
fi

if [[ -f "$docs_allowlist_example" ]]; then
  ok "$docs_allowlist_example: present"
else
  fail "Missing file: $docs_allowlist_example"
fi

include_line='include /etc/nginx/snippets/shamell_bff_edge_hardening.conf;'
access_log_line='access_log /var/log/nginx/access.log shamell_noquery;'

check_vhost() {
  local rel="$1"
  local min_count="$2"
  local path="$ROOT/$rel"
  if ! require_file "$path"; then
    return
  fi
  require_count_at_least "$path" "$include_line" "$min_count" 'edge hardening include'
}

check_vhost "ops/hetzner/nginx/sites-available/api.shamell.online" 1
check_vhost "ops/hetzner/nginx/sites-available/staging-api.shamell.online" 1
check_vhost "ops/hetzner/nginx/sites-available/online.shamell.online" 2
check_vhost "ops/hetzner/nginx/sites-available/shamell.online" 2

# Access logs must omit query strings to avoid leaking secrets in URLs.
require_count_at_least "$ROOT/ops/hetzner/nginx/sites-available/api.shamell.online" "$access_log_line" 2 "no-query access_log"
require_count_at_least "$ROOT/ops/hetzner/nginx/sites-available/staging-api.shamell.online" "$access_log_line" 2 "no-query access_log"
require_count_at_least "$ROOT/ops/hetzner/nginx/sites-available/online.shamell.online" "$access_log_line" 2 "no-query access_log"
require_count_at_least "$ROOT/ops/hetzner/nginx/sites-available/shamell.online" "$access_log_line" 2 "no-query access_log"
require_count_at_least "$ROOT/ops/hetzner/nginx/sites-available/media.shamell.online" "$access_log_line" 2 "no-query access_log"
require_count_at_least "$ROOT/ops/hetzner/nginx/sites-available/livekit.shamell.online" "$access_log_line" 2 "no-query access_log"

require_internal_block "$ROOT/ops/hetzner/nginx/sites-available/api.shamell.online"
require_internal_block "$ROOT/ops/hetzner/nginx/sites-available/staging-api.shamell.online"
require_docs_openapi_allowlist "$ROOT/ops/hetzner/nginx/sites-available/api.shamell.online"
require_docs_openapi_allowlist "$ROOT/ops/hetzner/nginx/sites-available/staging-api.shamell.online"
require_docs_openapi_allowlist "$ROOT/ops/hetzner/nginx/sites-available/online.shamell.online"
require_docs_openapi_allowlist "$ROOT/ops/hetzner/nginx/sites-available/shamell.online"

if (( errors != 0 )); then
  exit 1
fi

echo "Nginx edge hardening check passed."
