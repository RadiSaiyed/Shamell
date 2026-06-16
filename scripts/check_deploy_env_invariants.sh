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

file_mode_octal() {
  local path="$1"
  if mode="$(stat -f '%Lp' "$path" 2>/dev/null)"; then
    printf '%s\n' "$mode"
    return 0
  fi
  if mode="$(stat -c '%a' "$path" 2>/dev/null)"; then
    printf '%s\n' "$mode"
    return 0
  fi
  return 1
}

check_env_template() {
  local rel="$1"
  local file="$ROOT/$rel"
  if ! require_file "$file"; then
    return
  fi

  require_regex "$file" '^BFF_REQUIRE_INTERNAL_SECRET=true$' 'BFF_REQUIRE_INTERNAL_SECRET=true'
  require_regex "$file" '^SHAMELL_DEPLOYMENT_PROFILE=ops-pi$' 'SHAMELL_DEPLOYMENT_PROFILE=ops-pi'
  require_regex "$file" '^CHAT_REQUIRE_INTERNAL_SECRET=true$' 'CHAT_REQUIRE_INTERNAL_SECRET=true'
  require_regex "$file" '^CHAT_ENFORCE_DEVICE_AUTH=true$' 'CHAT_ENFORCE_DEVICE_AUTH=true'
  require_regex "$file" '^PAYMENTS_REQUIRE_INTERNAL_SECRET=true$' 'PAYMENTS_REQUIRE_INTERNAL_SECRET=true'
  require_regex "$file" '^BUS_REQUIRE_INTERNAL_SECRET=true$' 'BUS_REQUIRE_INTERNAL_SECRET=true'
  require_regex "$file" '^BFF_ENFORCE_ROUTE_AUTHZ=true$' 'BFF_ENFORCE_ROUTE_AUTHZ=true'
  require_regex "$file" '^CSRF_GUARD_ENABLED=true$' 'CSRF_GUARD_ENABLED=true'
  require_regex "$file" '^AUTH_ACCEPT_LEGACY_SESSION_COOKIE=false$' 'AUTH_ACCEPT_LEGACY_SESSION_COOKIE=false'
  require_regex "$file" '^AUTH_DEVICE_LOGIN_WEB_ENABLED=false$' 'AUTH_DEVICE_LOGIN_WEB_ENABLED=false'
  require_absent "$file" '^AUTH_ALLOW_HEADER_SESSION_AUTH=' 'AUTH_ALLOW_HEADER_SESSION_AUTH'
  require_absent "$file" '^AUTH_BLOCK_BROWSER_HEADER_SESSION=' 'AUTH_BLOCK_BROWSER_HEADER_SESSION'
  require_regex "$file" '^AUTH_ACCOUNT_CREATE_ENABLED=true$' 'AUTH_ACCOUNT_CREATE_ENABLED=true'
  require_regex "$file" '^AUTH_ACCOUNT_CREATE_POW_ENABLED=true$' 'AUTH_ACCOUNT_CREATE_POW_ENABLED=true'
  require_regex "$file" '^AUTH_ACCOUNT_CREATE_POW_TTL_SECS=[0-9]+$' 'AUTH_ACCOUNT_CREATE_POW_TTL_SECS set'
  require_regex "$file" '^AUTH_ACCOUNT_CREATE_POW_DIFFICULTY_BITS=[0-9]+$' 'AUTH_ACCOUNT_CREATE_POW_DIFFICULTY_BITS set'
  require_regex "$file" '^AUTH_ACCOUNT_CREATE_POW_SECRET=.+$' 'AUTH_ACCOUNT_CREATE_POW_SECRET set'
  require_regex "$file" '^AUTH_ACCOUNT_CREATE_HARDWARE_ATTESTATION_ENABLED=true$' 'AUTH_ACCOUNT_CREATE_HARDWARE_ATTESTATION_ENABLED=true'
  require_regex "$file" '^AUTH_ACCOUNT_CREATE_REQUIRE_HARDWARE_ATTESTATION=true$' 'AUTH_ACCOUNT_CREATE_REQUIRE_HARDWARE_ATTESTATION=true'
  require_regex "$file" '^AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_TEAM_ID=.+$' 'AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_TEAM_ID set'
  require_regex "$file" '^AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_KEY_ID=.+$' 'AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_KEY_ID set'
  require_regex "$file" '^AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_PRIVATE_KEY_P8_B64=.+$' 'AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_PRIVATE_KEY_P8_B64 set'
  require_regex "$file" '^AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON_B64=.+$' 'AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON_B64 set'
  require_regex "$file" '^AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_ALLOWED_PACKAGE_NAMES=.+$' 'AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_ALLOWED_PACKAGE_NAMES set'
  require_regex "$file" '^AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_STRONG_INTEGRITY=true$' 'AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_STRONG_INTEGRITY=true'
  require_regex "$file" '^AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_PLAY_RECOGNIZED=true$' 'AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_PLAY_RECOGNIZED=true'
  require_regex "$file" '^AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_LICENSED=false$' 'AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_LICENSED=false'
  require_regex "$file" '^AUTH_ACCOUNT_CREATE_CHALLENGE_WINDOW_SECS=[0-9]+$' 'AUTH_ACCOUNT_CREATE_CHALLENGE_WINDOW_SECS set'
  require_regex "$file" '^AUTH_ACCOUNT_CREATE_CHALLENGE_MAX_PER_IP=[0-9]+$' 'AUTH_ACCOUNT_CREATE_CHALLENGE_MAX_PER_IP set'
  require_regex "$file" '^AUTH_ACCOUNT_CREATE_CHALLENGE_MAX_PER_DEVICE=[0-9]+$' 'AUTH_ACCOUNT_CREATE_CHALLENGE_MAX_PER_DEVICE set'
  require_regex "$file" '^AUTH_BIOMETRIC_TOKEN_TTL_SECS=[0-9]+$' 'AUTH_BIOMETRIC_TOKEN_TTL_SECS set'
  require_regex "$file" '^AUTH_BIOMETRIC_LOGIN_WINDOW_SECS=[0-9]+$' 'AUTH_BIOMETRIC_LOGIN_WINDOW_SECS set'
  require_regex "$file" '^AUTH_BIOMETRIC_LOGIN_MAX_PER_IP=[0-9]+$' 'AUTH_BIOMETRIC_LOGIN_MAX_PER_IP set'
  require_regex "$file" '^AUTH_BIOMETRIC_LOGIN_MAX_PER_DEVICE=[0-9]+$' 'AUTH_BIOMETRIC_LOGIN_MAX_PER_DEVICE set'
  require_regex "$file" '^CSP_ENABLED=true$' 'CSP_ENABLED=true'
  require_regex "$file" '^AUTH_CHAT_REGISTER_WINDOW_SECS=[0-9]+$' 'AUTH_CHAT_REGISTER_WINDOW_SECS set'
  require_regex "$file" '^AUTH_CHAT_REGISTER_MAX_PER_IP=[0-9]+$' 'AUTH_CHAT_REGISTER_MAX_PER_IP set'
  require_regex "$file" '^AUTH_CHAT_REGISTER_MAX_PER_DEVICE=[0-9]+$' 'AUTH_CHAT_REGISTER_MAX_PER_DEVICE set'
  require_regex "$file" '^AUTH_CHAT_GET_DEVICE_WINDOW_SECS=[0-9]+$' 'AUTH_CHAT_GET_DEVICE_WINDOW_SECS set'
  require_regex "$file" '^AUTH_CHAT_GET_DEVICE_MAX_PER_IP=[0-9]+$' 'AUTH_CHAT_GET_DEVICE_MAX_PER_IP set'
  require_regex "$file" '^AUTH_CHAT_GET_DEVICE_MAX_PER_DEVICE=[0-9]+$' 'AUTH_CHAT_GET_DEVICE_MAX_PER_DEVICE set'
  require_regex "$file" '^AUTH_CONTACT_INVITE_TTL_SECS=[0-9]+$' 'AUTH_CONTACT_INVITE_TTL_SECS set'
  require_regex "$file" '^AUTH_CONTACT_INVITE_WINDOW_SECS=[0-9]+$' 'AUTH_CONTACT_INVITE_WINDOW_SECS set'
  require_regex "$file" '^AUTH_CONTACT_INVITE_CREATE_MAX_PER_IP=[0-9]+$' 'AUTH_CONTACT_INVITE_CREATE_MAX_PER_IP set'
  require_regex "$file" '^AUTH_CONTACT_INVITE_CREATE_MAX_PER_PHONE=[0-9]+$' 'AUTH_CONTACT_INVITE_CREATE_MAX_PER_PHONE set'
  require_regex "$file" '^AUTH_CONTACT_INVITE_REDEEM_MAX_PER_IP=[0-9]+$' 'AUTH_CONTACT_INVITE_REDEEM_MAX_PER_IP set'
  require_regex "$file" '^AUTH_CONTACT_INVITE_REDEEM_MAX_PER_PHONE=[0-9]+$' 'AUTH_CONTACT_INVITE_REDEEM_MAX_PER_PHONE set'
  require_regex "$file" '^AUTH_CONTACT_INVITE_REDEEM_MAX_PER_TOKEN=[0-9]+$' 'AUTH_CONTACT_INVITE_REDEEM_MAX_PER_TOKEN set'
  require_regex "$file" '^CHAT_PROTOCOL_V2_ENABLED=true$' 'CHAT_PROTOCOL_V2_ENABLED=true'
  require_regex "$file" '^CHAT_PROTOCOL_V1_WRITE_ENABLED=false$' 'CHAT_PROTOCOL_V1_WRITE_ENABLED=false'
  require_regex "$file" '^CHAT_PROTOCOL_V1_READ_ENABLED=false$' 'CHAT_PROTOCOL_V1_READ_ENABLED=false'
  require_regex "$file" '^CHAT_PROTOCOL_REQUIRE_V2_FOR_GROUPS=true$' 'CHAT_PROTOCOL_REQUIRE_V2_FOR_GROUPS=true'
  require_regex "$file" '^PAYMENTS_MAX_BODY_BYTES=[0-9]+$' 'PAYMENTS_MAX_BODY_BYTES set'
  require_regex "$file" '^BUS_MAX_BODY_BYTES=[0-9]+$' 'BUS_MAX_BODY_BYTES set'
  require_absent "$file" '^ALLOWED_HOSTS=.*(localhost|127\.0\.0\.1)' 'loopback ALLOWED_HOSTS entries'
  require_absent "$file" '^ALLOWED_ORIGINS=.*\*' 'wildcard ALLOWED_ORIGINS entries'
  require_regex "$file" '^ALLOWED_ORIGINS=https://[^,[:space:]]+(,https://[^,[:space:]]+)*$' 'ALLOWED_ORIGINS https-only list'
  require_absent "$file" '^CHAT_ALLOW_LEGACY_AUTH_BOOTSTRAP=' 'CHAT_ALLOW_LEGACY_AUTH_BOOTSTRAP'
  require_absent "$file" '^AUTH_EXPOSE_CODES=' 'AUTH_EXPOSE_CODES'
  require_absent "$file" '^AUTH_REQUEST_CODE_' 'AUTH_REQUEST_CODE_*'
  require_absent "$file" '^AUTH_VERIFY_' 'AUTH_VERIFY_*'
  require_absent "$file" '^AUTH_OTP_' 'AUTH_OTP_*'
  require_absent "$file" '^AUTH_RESOLVE_PHONE_' 'AUTH_RESOLVE_PHONE_*'
}

check_compose_defaults() {
  local rel="$1"
  local file="$ROOT/$rel"
  if ! require_file "$file"; then
    return
  fi

  require_regex "$file" 'BFF_REQUIRE_INTERNAL_SECRET:[[:space:]]*"\$\{BFF_REQUIRE_INTERNAL_SECRET:-true\}"' 'BFF_REQUIRE_INTERNAL_SECRET default true'
  require_regex "$file" 'SHAMELL_DEPLOYMENT_PROFILE:[[:space:]]*"\$\{SHAMELL_DEPLOYMENT_PROFILE:-ops-pi\}"' 'SHAMELL_DEPLOYMENT_PROFILE default ops-pi'
  require_regex "$file" 'CHAT_REQUIRE_INTERNAL_SECRET:[[:space:]]*"\$\{CHAT_REQUIRE_INTERNAL_SECRET:-true\}"' 'CHAT_REQUIRE_INTERNAL_SECRET default true'
  require_regex "$file" 'CHAT_ENFORCE_DEVICE_AUTH:[[:space:]]*"\$\{CHAT_ENFORCE_DEVICE_AUTH:-true\}"' 'CHAT_ENFORCE_DEVICE_AUTH default true'
  require_regex "$file" 'PAYMENTS_REQUIRE_INTERNAL_SECRET:[[:space:]]*"\$\{PAYMENTS_REQUIRE_INTERNAL_SECRET:-true\}"' 'PAYMENTS_REQUIRE_INTERNAL_SECRET default true'
  require_regex "$file" 'BUS_REQUIRE_INTERNAL_SECRET:[[:space:]]*"\$\{BUS_REQUIRE_INTERNAL_SECRET:-true\}"' 'BUS_REQUIRE_INTERNAL_SECRET default true'
  require_regex "$file" 'BFF_ENFORCE_ROUTE_AUTHZ:[[:space:]]*"\$\{BFF_ENFORCE_ROUTE_AUTHZ:-true\}"' 'BFF_ENFORCE_ROUTE_AUTHZ default true'
  require_regex "$file" 'CSRF_GUARD_ENABLED:[[:space:]]*"\$\{CSRF_GUARD_ENABLED:-true\}"' 'CSRF_GUARD_ENABLED default true'
  require_regex "$file" 'AUTH_ACCEPT_LEGACY_SESSION_COOKIE:[[:space:]]*"\$\{AUTH_ACCEPT_LEGACY_SESSION_COOKIE:-false\}"' 'AUTH_ACCEPT_LEGACY_SESSION_COOKIE default false'
  require_regex "$file" 'AUTH_DEVICE_LOGIN_WEB_ENABLED:[[:space:]]*"\$\{AUTH_DEVICE_LOGIN_WEB_ENABLED:-false\}"' 'AUTH_DEVICE_LOGIN_WEB_ENABLED default false'
  require_absent "$file" 'AUTH_ALLOW_HEADER_SESSION_AUTH' 'AUTH_ALLOW_HEADER_SESSION_AUTH'
  require_absent "$file" 'AUTH_BLOCK_BROWSER_HEADER_SESSION' 'AUTH_BLOCK_BROWSER_HEADER_SESSION'
  require_regex "$file" 'AUTH_ACCOUNT_CREATE_ENABLED:[[:space:]]*"\$\{AUTH_ACCOUNT_CREATE_ENABLED:-true\}"' 'AUTH_ACCOUNT_CREATE_ENABLED default true'
  require_regex "$file" 'AUTH_ACCOUNT_CREATE_POW_ENABLED:[[:space:]]*"\$\{AUTH_ACCOUNT_CREATE_POW_ENABLED:-true\}"' 'AUTH_ACCOUNT_CREATE_POW_ENABLED default true'
  require_regex "$file" 'AUTH_ACCOUNT_CREATE_POW_TTL_SECS:[[:space:]]*"\$\{AUTH_ACCOUNT_CREATE_POW_TTL_SECS:-300\}"' 'AUTH_ACCOUNT_CREATE_POW_TTL_SECS default'
  require_regex "$file" 'AUTH_ACCOUNT_CREATE_POW_DIFFICULTY_BITS:[[:space:]]*"\$\{AUTH_ACCOUNT_CREATE_POW_DIFFICULTY_BITS:-18\}"' 'AUTH_ACCOUNT_CREATE_POW_DIFFICULTY_BITS default'
  require_regex "$file" 'AUTH_ACCOUNT_CREATE_POW_SECRET:[[:space:]]*"\$\{AUTH_ACCOUNT_CREATE_POW_SECRET:-\}"' 'AUTH_ACCOUNT_CREATE_POW_SECRET wired'
  require_regex "$file" 'AUTH_ACCOUNT_CREATE_HARDWARE_ATTESTATION_ENABLED:[[:space:]]*"\$\{AUTH_ACCOUNT_CREATE_HARDWARE_ATTESTATION_ENABLED:-true\}"' 'AUTH_ACCOUNT_CREATE_HARDWARE_ATTESTATION_ENABLED default true'
  require_regex "$file" 'AUTH_ACCOUNT_CREATE_REQUIRE_HARDWARE_ATTESTATION:[[:space:]]*"\$\{AUTH_ACCOUNT_CREATE_REQUIRE_HARDWARE_ATTESTATION:-true\}"' 'AUTH_ACCOUNT_CREATE_REQUIRE_HARDWARE_ATTESTATION default true'
  require_regex "$file" 'AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_TEAM_ID:[[:space:]]*"\$\{AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_TEAM_ID:-\}"' 'AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_TEAM_ID wired'
  require_regex "$file" 'AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_KEY_ID:[[:space:]]*"\$\{AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_KEY_ID:-\}"' 'AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_KEY_ID wired'
  require_regex "$file" 'AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_PRIVATE_KEY_P8_B64:[[:space:]]*"\$\{AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_PRIVATE_KEY_P8_B64:-\}"' 'AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_PRIVATE_KEY_P8_B64 wired'
  require_regex "$file" 'AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON_B64:[[:space:]]*"\$\{AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON_B64:-\}"' 'AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON_B64 wired'
  require_regex "$file" 'AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_ALLOWED_PACKAGE_NAMES:[[:space:]]*"\$\{AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_ALLOWED_PACKAGE_NAMES:-\}"' 'AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_ALLOWED_PACKAGE_NAMES wired'
  require_regex "$file" 'AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_STRONG_INTEGRITY:[[:space:]]*"\$\{AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_STRONG_INTEGRITY:-true\}"' 'AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_STRONG_INTEGRITY default true'
  require_regex "$file" 'AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_PLAY_RECOGNIZED:[[:space:]]*"\$\{AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_PLAY_RECOGNIZED:-true\}"' 'AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_PLAY_RECOGNIZED default true'
  require_regex "$file" 'AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_LICENSED:[[:space:]]*"\$\{AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_LICENSED:-false\}"' 'AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_LICENSED default false'
  require_regex "$file" 'AUTH_ACCOUNT_CREATE_CHALLENGE_WINDOW_SECS:[[:space:]]*"\$\{AUTH_ACCOUNT_CREATE_CHALLENGE_WINDOW_SECS:-300\}"' 'AUTH_ACCOUNT_CREATE_CHALLENGE_WINDOW_SECS default'
  require_regex "$file" 'AUTH_ACCOUNT_CREATE_CHALLENGE_MAX_PER_IP:[[:space:]]*"\$\{AUTH_ACCOUNT_CREATE_CHALLENGE_MAX_PER_IP:-2000\}"' 'AUTH_ACCOUNT_CREATE_CHALLENGE_MAX_PER_IP default'
  require_regex "$file" 'AUTH_ACCOUNT_CREATE_CHALLENGE_MAX_PER_DEVICE:[[:space:]]*"\$\{AUTH_ACCOUNT_CREATE_CHALLENGE_MAX_PER_DEVICE:-60\}"' 'AUTH_ACCOUNT_CREATE_CHALLENGE_MAX_PER_DEVICE default'
  require_regex "$file" 'AUTH_BIOMETRIC_TOKEN_TTL_SECS:[[:space:]]*"\$\{AUTH_BIOMETRIC_TOKEN_TTL_SECS:-31536000\}"' 'AUTH_BIOMETRIC_TOKEN_TTL_SECS default'
  require_regex "$file" 'AUTH_BIOMETRIC_LOGIN_WINDOW_SECS:[[:space:]]*"\$\{AUTH_BIOMETRIC_LOGIN_WINDOW_SECS:-300\}"' 'AUTH_BIOMETRIC_LOGIN_WINDOW_SECS default'
  require_regex "$file" 'AUTH_BIOMETRIC_LOGIN_MAX_PER_IP:[[:space:]]*"\$\{AUTH_BIOMETRIC_LOGIN_MAX_PER_IP:-60\}"' 'AUTH_BIOMETRIC_LOGIN_MAX_PER_IP default'
  require_regex "$file" 'AUTH_BIOMETRIC_LOGIN_MAX_PER_DEVICE:[[:space:]]*"\$\{AUTH_BIOMETRIC_LOGIN_MAX_PER_DEVICE:-30\}"' 'AUTH_BIOMETRIC_LOGIN_MAX_PER_DEVICE default'
  require_regex "$file" 'CSP_ENABLED:[[:space:]]*"\$\{CSP_ENABLED:-true\}"' 'CSP_ENABLED default true'
  require_regex "$file" 'AUTH_CHAT_REGISTER_WINDOW_SECS:[[:space:]]*"\$\{AUTH_CHAT_REGISTER_WINDOW_SECS:-300\}"' 'AUTH_CHAT_REGISTER_WINDOW_SECS default'
  require_regex "$file" 'AUTH_CHAT_REGISTER_MAX_PER_IP:[[:space:]]*"\$\{AUTH_CHAT_REGISTER_MAX_PER_IP:-40\}"' 'AUTH_CHAT_REGISTER_MAX_PER_IP default'
  require_regex "$file" 'AUTH_CHAT_REGISTER_MAX_PER_DEVICE:[[:space:]]*"\$\{AUTH_CHAT_REGISTER_MAX_PER_DEVICE:-20\}"' 'AUTH_CHAT_REGISTER_MAX_PER_DEVICE default'
  require_regex "$file" 'AUTH_CHAT_GET_DEVICE_WINDOW_SECS:[[:space:]]*"\$\{AUTH_CHAT_GET_DEVICE_WINDOW_SECS:-300\}"' 'AUTH_CHAT_GET_DEVICE_WINDOW_SECS default'
  require_regex "$file" 'AUTH_CHAT_GET_DEVICE_MAX_PER_IP:[[:space:]]*"\$\{AUTH_CHAT_GET_DEVICE_MAX_PER_IP:-80\}"' 'AUTH_CHAT_GET_DEVICE_MAX_PER_IP default'
  require_regex "$file" 'AUTH_CHAT_GET_DEVICE_MAX_PER_DEVICE:[[:space:]]*"\$\{AUTH_CHAT_GET_DEVICE_MAX_PER_DEVICE:-40\}"' 'AUTH_CHAT_GET_DEVICE_MAX_PER_DEVICE default'
  require_regex "$file" 'AUTH_CONTACT_INVITE_TTL_SECS:[[:space:]]*"\$\{AUTH_CONTACT_INVITE_TTL_SECS:-86400\}"' 'AUTH_CONTACT_INVITE_TTL_SECS default'
  require_regex "$file" 'AUTH_CONTACT_INVITE_WINDOW_SECS:[[:space:]]*"\$\{AUTH_CONTACT_INVITE_WINDOW_SECS:-300\}"' 'AUTH_CONTACT_INVITE_WINDOW_SECS default'
  require_regex "$file" 'AUTH_CONTACT_INVITE_CREATE_MAX_PER_IP:[[:space:]]*"\$\{AUTH_CONTACT_INVITE_CREATE_MAX_PER_IP:-40\}"' 'AUTH_CONTACT_INVITE_CREATE_MAX_PER_IP default'
  require_regex "$file" 'AUTH_CONTACT_INVITE_CREATE_MAX_PER_PHONE:[[:space:]]*"\$\{AUTH_CONTACT_INVITE_CREATE_MAX_PER_PHONE:-20\}"' 'AUTH_CONTACT_INVITE_CREATE_MAX_PER_PHONE default'
  require_regex "$file" 'AUTH_CONTACT_INVITE_REDEEM_MAX_PER_IP:[[:space:]]*"\$\{AUTH_CONTACT_INVITE_REDEEM_MAX_PER_IP:-200\}"' 'AUTH_CONTACT_INVITE_REDEEM_MAX_PER_IP default'
  require_regex "$file" 'AUTH_CONTACT_INVITE_REDEEM_MAX_PER_PHONE:[[:space:]]*"\$\{AUTH_CONTACT_INVITE_REDEEM_MAX_PER_PHONE:-80\}"' 'AUTH_CONTACT_INVITE_REDEEM_MAX_PER_PHONE default'
  require_regex "$file" 'AUTH_CONTACT_INVITE_REDEEM_MAX_PER_TOKEN:[[:space:]]*"\$\{AUTH_CONTACT_INVITE_REDEEM_MAX_PER_TOKEN:-10\}"' 'AUTH_CONTACT_INVITE_REDEEM_MAX_PER_TOKEN default'
  require_regex "$file" 'CHAT_PROTOCOL_V2_ENABLED:[[:space:]]*"\$\{CHAT_PROTOCOL_V2_ENABLED:-true\}"' 'CHAT_PROTOCOL_V2_ENABLED default true'
  require_regex "$file" 'CHAT_PROTOCOL_V1_WRITE_ENABLED:[[:space:]]*"\$\{CHAT_PROTOCOL_V1_WRITE_ENABLED:-false\}"' 'CHAT_PROTOCOL_V1_WRITE_ENABLED default false'
  require_regex "$file" 'CHAT_PROTOCOL_V1_READ_ENABLED:[[:space:]]*"\$\{CHAT_PROTOCOL_V1_READ_ENABLED:-false\}"' 'CHAT_PROTOCOL_V1_READ_ENABLED default false'
  require_regex "$file" 'CHAT_PROTOCOL_REQUIRE_V2_FOR_GROUPS:[[:space:]]*"\$\{CHAT_PROTOCOL_REQUIRE_V2_FOR_GROUPS:-true\}"' 'CHAT_PROTOCOL_REQUIRE_V2_FOR_GROUPS default true'
  require_regex "$file" 'PAYMENTS_MAX_BODY_BYTES:[[:space:]]*"\$\{PAYMENTS_MAX_BODY_BYTES:-1048576\}"' 'PAYMENTS_MAX_BODY_BYTES default'
  require_regex "$file" 'BUS_MAX_BODY_BYTES:[[:space:]]*"\$\{BUS_MAX_BODY_BYTES:-1048576\}"' 'BUS_MAX_BODY_BYTES default'
  require_regex "$file" 'ALLOWED_HOSTS:[[:space:]]*"\$\{ALLOWED_HOSTS:-api\.shamell\.online,online\.shamell\.online\}"' 'ALLOWED_HOSTS default production-only hostnames'
  require_regex "$file" 'ALLOWED_ORIGINS:[[:space:]]*"\$\{ALLOWED_ORIGINS:-https://online\.shamell\.online,https://shamell\.online\}"' 'ALLOWED_ORIGINS default https-only hostnames'
  require_absent "$file" 'CHAT_ALLOW_LEGACY_AUTH_BOOTSTRAP' 'CHAT_ALLOW_LEGACY_AUTH_BOOTSTRAP'
  require_absent "$file" 'AUTH_EXPOSE_CODES' 'AUTH_EXPOSE_CODES'
  require_absent "$file" 'AUTH_REQUEST_CODE_' 'AUTH_REQUEST_CODE_*'
  require_absent "$file" 'AUTH_VERIFY_' 'AUTH_VERIFY_*'
  require_absent "$file" 'AUTH_OTP_' 'AUTH_OTP_*'
  require_absent "$file" 'AUTH_RESOLVE_PHONE_' 'AUTH_RESOLVE_PHONE_*'
}

check_root_env_example() {
  local rel="$1"
  local file="$ROOT/$rel"
  if ! require_file "$file"; then
    return
  fi

  # Root .env.example should include the biometric auth guardrails.
  require_regex "$file" '^BFF_REQUIRE_INTERNAL_SECRET=true$' 'BFF_REQUIRE_INTERNAL_SECRET=true'
  require_regex "$file" '^SHAMELL_DEPLOYMENT_PROFILE=root-dev$' 'SHAMELL_DEPLOYMENT_PROFILE=root-dev'
  require_regex "$file" '^CHAT_REQUIRE_INTERNAL_SECRET=(true|false)$' 'CHAT_REQUIRE_INTERNAL_SECRET set'
  require_regex "$file" '^PAYMENTS_REQUIRE_INTERNAL_SECRET=(true|false)$' 'PAYMENTS_REQUIRE_INTERNAL_SECRET set'
  require_regex "$file" '^BUS_REQUIRE_INTERNAL_SECRET=(true|false)$' 'BUS_REQUIRE_INTERNAL_SECRET set'
  require_regex "$file" '^BFF_ENFORCE_ROUTE_AUTHZ=(true|false)$' 'BFF_ENFORCE_ROUTE_AUTHZ set'
  require_regex "$file" '^CSRF_GUARD_ENABLED=(true|false)$' 'CSRF_GUARD_ENABLED set'
  require_regex "$file" '^AUTH_ACCEPT_LEGACY_SESSION_COOKIE=(true|false)$' 'AUTH_ACCEPT_LEGACY_SESSION_COOKIE set'
  require_regex "$file" '^AUTH_DEVICE_LOGIN_WEB_ENABLED=(true|false)$' 'AUTH_DEVICE_LOGIN_WEB_ENABLED set'
  require_regex "$file" '^ALLOWED_ORIGINS=http://localhost:5173,http://127\.0\.0\.1:5173$' 'ALLOWED_ORIGINS local-dev defaults'
  require_absent "$file" '^AUTH_ALLOW_HEADER_SESSION_AUTH=' 'AUTH_ALLOW_HEADER_SESSION_AUTH'
  require_absent "$file" '^AUTH_BLOCK_BROWSER_HEADER_SESSION=' 'AUTH_BLOCK_BROWSER_HEADER_SESSION'
  require_regex "$file" '^AUTH_ACCOUNT_CREATE_ENABLED=(true|false)$' 'AUTH_ACCOUNT_CREATE_ENABLED set'
  require_regex "$file" '^AUTH_ACCOUNT_CREATE_POW_ENABLED=(true|false)$' 'AUTH_ACCOUNT_CREATE_POW_ENABLED set'
  require_regex "$file" '^AUTH_ACCOUNT_CREATE_POW_TTL_SECS=[0-9]+$' 'AUTH_ACCOUNT_CREATE_POW_TTL_SECS set'
  require_regex "$file" '^AUTH_ACCOUNT_CREATE_POW_DIFFICULTY_BITS=[0-9]+$' 'AUTH_ACCOUNT_CREATE_POW_DIFFICULTY_BITS set'
  require_regex "$file" '^AUTH_ACCOUNT_CREATE_POW_SECRET=.+$' 'AUTH_ACCOUNT_CREATE_POW_SECRET set'
  require_regex "$file" '^AUTH_ACCOUNT_CREATE_HARDWARE_ATTESTATION_ENABLED=(true|false)$' 'AUTH_ACCOUNT_CREATE_HARDWARE_ATTESTATION_ENABLED set'
  require_regex "$file" '^AUTH_ACCOUNT_CREATE_REQUIRE_HARDWARE_ATTESTATION=(true|false)$' 'AUTH_ACCOUNT_CREATE_REQUIRE_HARDWARE_ATTESTATION set'
  require_regex "$file" '^AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_TEAM_ID=.*$' 'AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_TEAM_ID present'
  require_regex "$file" '^AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_KEY_ID=.*$' 'AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_KEY_ID present'
  require_regex "$file" '^AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_PRIVATE_KEY_P8_B64=.*$' 'AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_PRIVATE_KEY_P8_B64 present'
  require_regex "$file" '^AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON_B64=.*$' 'AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON_B64 present'
  require_regex "$file" '^AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_ALLOWED_PACKAGE_NAMES=.+$' 'AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_ALLOWED_PACKAGE_NAMES set'
  require_regex "$file" '^AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_STRONG_INTEGRITY=(true|false)$' 'AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_STRONG_INTEGRITY set'
  require_regex "$file" '^AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_PLAY_RECOGNIZED=(true|false)$' 'AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_PLAY_RECOGNIZED set'
  require_regex "$file" '^AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_LICENSED=(true|false)$' 'AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_LICENSED set'
  require_regex "$file" '^AUTH_ACCOUNT_CREATE_CHALLENGE_WINDOW_SECS=[0-9]+$' 'AUTH_ACCOUNT_CREATE_CHALLENGE_WINDOW_SECS set'
  require_regex "$file" '^AUTH_ACCOUNT_CREATE_CHALLENGE_MAX_PER_IP=[0-9]+$' 'AUTH_ACCOUNT_CREATE_CHALLENGE_MAX_PER_IP set'
  require_regex "$file" '^AUTH_ACCOUNT_CREATE_CHALLENGE_MAX_PER_DEVICE=[0-9]+$' 'AUTH_ACCOUNT_CREATE_CHALLENGE_MAX_PER_DEVICE set'
  require_regex "$file" '^AUTH_BIOMETRIC_TOKEN_TTL_SECS=[0-9]+$' 'AUTH_BIOMETRIC_TOKEN_TTL_SECS set'
  require_regex "$file" '^AUTH_BIOMETRIC_LOGIN_WINDOW_SECS=[0-9]+$' 'AUTH_BIOMETRIC_LOGIN_WINDOW_SECS set'
  require_regex "$file" '^AUTH_BIOMETRIC_LOGIN_MAX_PER_IP=[0-9]+$' 'AUTH_BIOMETRIC_LOGIN_MAX_PER_IP set'
  require_regex "$file" '^AUTH_BIOMETRIC_LOGIN_MAX_PER_DEVICE=[0-9]+$' 'AUTH_BIOMETRIC_LOGIN_MAX_PER_DEVICE set'
  require_regex "$file" '^AUTH_CONTACT_INVITE_TTL_SECS=[0-9]+$' 'AUTH_CONTACT_INVITE_TTL_SECS set'
  require_regex "$file" '^AUTH_CONTACT_INVITE_WINDOW_SECS=[0-9]+$' 'AUTH_CONTACT_INVITE_WINDOW_SECS set'
  require_regex "$file" '^AUTH_CONTACT_INVITE_CREATE_MAX_PER_IP=[0-9]+$' 'AUTH_CONTACT_INVITE_CREATE_MAX_PER_IP set'
  require_regex "$file" '^AUTH_CONTACT_INVITE_CREATE_MAX_PER_PHONE=[0-9]+$' 'AUTH_CONTACT_INVITE_CREATE_MAX_PER_PHONE set'
  require_regex "$file" '^AUTH_CONTACT_INVITE_REDEEM_MAX_PER_IP=[0-9]+$' 'AUTH_CONTACT_INVITE_REDEEM_MAX_PER_IP set'
  require_regex "$file" '^AUTH_CONTACT_INVITE_REDEEM_MAX_PER_PHONE=[0-9]+$' 'AUTH_CONTACT_INVITE_REDEEM_MAX_PER_PHONE set'
  require_regex "$file" '^AUTH_CONTACT_INVITE_REDEEM_MAX_PER_TOKEN=[0-9]+$' 'AUTH_CONTACT_INVITE_REDEEM_MAX_PER_TOKEN set'
  require_absent "$file" '^AUTH_EXPOSE_CODES=' 'AUTH_EXPOSE_CODES'
  require_absent "$file" '^AUTH_REQUEST_CODE_' 'AUTH_REQUEST_CODE_*'
  require_absent "$file" '^AUTH_VERIFY_' 'AUTH_VERIFY_*'
  require_absent "$file" '^AUTH_OTP_' 'AUTH_OTP_*'
  require_absent "$file" '^AUTH_RESOLVE_PHONE_' 'AUTH_RESOLVE_PHONE_*'
}

check_root_compose_defaults() {
  local rel="$1"
  local file="$ROOT/$rel"
  if ! require_file "$file"; then
    return
  fi

  # Root docker-compose defaults should include biometric auth guardrails and
  # require internal-secret enforcement by default.
  require_regex "$file" 'BFF_REQUIRE_INTERNAL_SECRET:[[:space:]]*"\$\{BFF_REQUIRE_INTERNAL_SECRET:-true\}"' 'BFF_REQUIRE_INTERNAL_SECRET default true'
  require_regex "$file" 'SHAMELL_DEPLOYMENT_PROFILE:[[:space:]]*"\$\{SHAMELL_DEPLOYMENT_PROFILE:-root-dev\}"' 'SHAMELL_DEPLOYMENT_PROFILE default root-dev'
  require_regex "$file" 'CHAT_REQUIRE_INTERNAL_SECRET:[[:space:]]*"\$\{CHAT_REQUIRE_INTERNAL_SECRET:-true\}"' 'CHAT_REQUIRE_INTERNAL_SECRET default true'
  require_regex "$file" 'PAYMENTS_REQUIRE_INTERNAL_SECRET:[[:space:]]*"\$\{PAYMENTS_REQUIRE_INTERNAL_SECRET:-true\}"' 'PAYMENTS_REQUIRE_INTERNAL_SECRET default true'
  require_regex "$file" 'BUS_REQUIRE_INTERNAL_SECRET:[[:space:]]*"\$\{BUS_REQUIRE_INTERNAL_SECRET:-true\}"' 'BUS_REQUIRE_INTERNAL_SECRET default true'
  require_regex "$file" 'BFF_ENFORCE_ROUTE_AUTHZ:[[:space:]]*"\$\{BFF_ENFORCE_ROUTE_AUTHZ:-false\}"' 'BFF_ENFORCE_ROUTE_AUTHZ default false'
  require_regex "$file" 'AUTH_DEVICE_LOGIN_WEB_ENABLED:[[:space:]]*"\$\{AUTH_DEVICE_LOGIN_WEB_ENABLED:-true\}"' 'AUTH_DEVICE_LOGIN_WEB_ENABLED default true'
  require_regex "$file" 'ALLOWED_ORIGINS:[[:space:]]*"\$\{ALLOWED_ORIGINS:-http://localhost:5173,http://127\.0\.0\.1:5173\}"' 'ALLOWED_ORIGINS local-dev defaults'
  require_regex "$file" 'AUTH_ACCOUNT_CREATE_ENABLED:[[:space:]]*"\$\{AUTH_ACCOUNT_CREATE_ENABLED:-true\}"' 'AUTH_ACCOUNT_CREATE_ENABLED default true'
  require_regex "$file" 'AUTH_ACCOUNT_CREATE_POW_ENABLED:[[:space:]]*"\$\{AUTH_ACCOUNT_CREATE_POW_ENABLED:-false\}"' 'AUTH_ACCOUNT_CREATE_POW_ENABLED default false'
  require_regex "$file" 'AUTH_ACCOUNT_CREATE_POW_TTL_SECS:[[:space:]]*"\$\{AUTH_ACCOUNT_CREATE_POW_TTL_SECS:-300\}"' 'AUTH_ACCOUNT_CREATE_POW_TTL_SECS default'
  require_regex "$file" 'AUTH_ACCOUNT_CREATE_POW_DIFFICULTY_BITS:[[:space:]]*"\$\{AUTH_ACCOUNT_CREATE_POW_DIFFICULTY_BITS:-18\}"' 'AUTH_ACCOUNT_CREATE_POW_DIFFICULTY_BITS default'
  require_regex "$file" 'AUTH_ACCOUNT_CREATE_POW_SECRET:[[:space:]]*"\$\{AUTH_ACCOUNT_CREATE_POW_SECRET:-\}"' 'AUTH_ACCOUNT_CREATE_POW_SECRET wired'
  require_regex "$file" 'AUTH_ACCOUNT_CREATE_HARDWARE_ATTESTATION_ENABLED:[[:space:]]*"\$\{AUTH_ACCOUNT_CREATE_HARDWARE_ATTESTATION_ENABLED:-false\}"' 'AUTH_ACCOUNT_CREATE_HARDWARE_ATTESTATION_ENABLED default false'
  require_regex "$file" 'AUTH_ACCOUNT_CREATE_REQUIRE_HARDWARE_ATTESTATION:[[:space:]]*"\$\{AUTH_ACCOUNT_CREATE_REQUIRE_HARDWARE_ATTESTATION:-false\}"' 'AUTH_ACCOUNT_CREATE_REQUIRE_HARDWARE_ATTESTATION default false'
  require_regex "$file" 'AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_TEAM_ID:[[:space:]]*"\$\{AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_TEAM_ID:-\}"' 'AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_TEAM_ID wired'
  require_regex "$file" 'AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_KEY_ID:[[:space:]]*"\$\{AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_KEY_ID:-\}"' 'AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_KEY_ID wired'
  require_regex "$file" 'AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_PRIVATE_KEY_P8_B64:[[:space:]]*"\$\{AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_PRIVATE_KEY_P8_B64:-\}"' 'AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_PRIVATE_KEY_P8_B64 wired'
  require_regex "$file" 'AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON_B64:[[:space:]]*"\$\{AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON_B64:-\}"' 'AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON_B64 wired'
  require_regex "$file" 'AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_ALLOWED_PACKAGE_NAMES:[[:space:]]*"\$\{AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_ALLOWED_PACKAGE_NAMES:-\}"' 'AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_ALLOWED_PACKAGE_NAMES wired'
  require_regex "$file" 'AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_STRONG_INTEGRITY:[[:space:]]*"\$\{AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_STRONG_INTEGRITY:-false\}"' 'AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_STRONG_INTEGRITY default false'
  require_regex "$file" 'AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_PLAY_RECOGNIZED:[[:space:]]*"\$\{AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_PLAY_RECOGNIZED:-false\}"' 'AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_PLAY_RECOGNIZED default false'
  require_regex "$file" 'AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_LICENSED:[[:space:]]*"\$\{AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_LICENSED:-false\}"' 'AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_LICENSED default false'
  require_regex "$file" 'AUTH_ACCOUNT_CREATE_CHALLENGE_WINDOW_SECS:[[:space:]]*"\$\{AUTH_ACCOUNT_CREATE_CHALLENGE_WINDOW_SECS:-300\}"' 'AUTH_ACCOUNT_CREATE_CHALLENGE_WINDOW_SECS default'
  require_regex "$file" 'AUTH_ACCOUNT_CREATE_CHALLENGE_MAX_PER_IP:[[:space:]]*"\$\{AUTH_ACCOUNT_CREATE_CHALLENGE_MAX_PER_IP:-2000\}"' 'AUTH_ACCOUNT_CREATE_CHALLENGE_MAX_PER_IP default'
  require_regex "$file" 'AUTH_ACCOUNT_CREATE_CHALLENGE_MAX_PER_DEVICE:[[:space:]]*"\$\{AUTH_ACCOUNT_CREATE_CHALLENGE_MAX_PER_DEVICE:-60\}"' 'AUTH_ACCOUNT_CREATE_CHALLENGE_MAX_PER_DEVICE default'
  require_regex "$file" 'AUTH_BIOMETRIC_TOKEN_TTL_SECS:[[:space:]]*"\$\{AUTH_BIOMETRIC_TOKEN_TTL_SECS:-31536000\}"' 'AUTH_BIOMETRIC_TOKEN_TTL_SECS default'
  require_regex "$file" 'AUTH_BIOMETRIC_LOGIN_WINDOW_SECS:[[:space:]]*"\$\{AUTH_BIOMETRIC_LOGIN_WINDOW_SECS:-300\}"' 'AUTH_BIOMETRIC_LOGIN_WINDOW_SECS default'
  require_regex "$file" 'AUTH_BIOMETRIC_LOGIN_MAX_PER_IP:[[:space:]]*"\$\{AUTH_BIOMETRIC_LOGIN_MAX_PER_IP:-60\}"' 'AUTH_BIOMETRIC_LOGIN_MAX_PER_IP default'
  require_regex "$file" 'AUTH_BIOMETRIC_LOGIN_MAX_PER_DEVICE:[[:space:]]*"\$\{AUTH_BIOMETRIC_LOGIN_MAX_PER_DEVICE:-30\}"' 'AUTH_BIOMETRIC_LOGIN_MAX_PER_DEVICE default'
  require_regex "$file" 'AUTH_CONTACT_INVITE_TTL_SECS:[[:space:]]*"\$\{AUTH_CONTACT_INVITE_TTL_SECS:-86400\}"' 'AUTH_CONTACT_INVITE_TTL_SECS default'
  require_regex "$file" 'AUTH_CONTACT_INVITE_WINDOW_SECS:[[:space:]]*"\$\{AUTH_CONTACT_INVITE_WINDOW_SECS:-300\}"' 'AUTH_CONTACT_INVITE_WINDOW_SECS default'
  require_regex "$file" 'AUTH_CONTACT_INVITE_CREATE_MAX_PER_IP:[[:space:]]*"\$\{AUTH_CONTACT_INVITE_CREATE_MAX_PER_IP:-120\}"' 'AUTH_CONTACT_INVITE_CREATE_MAX_PER_IP default'
  require_regex "$file" 'AUTH_CONTACT_INVITE_CREATE_MAX_PER_PHONE:[[:space:]]*"\$\{AUTH_CONTACT_INVITE_CREATE_MAX_PER_PHONE:-60\}"' 'AUTH_CONTACT_INVITE_CREATE_MAX_PER_PHONE default'
  require_regex "$file" 'AUTH_CONTACT_INVITE_REDEEM_MAX_PER_IP:[[:space:]]*"\$\{AUTH_CONTACT_INVITE_REDEEM_MAX_PER_IP:-500\}"' 'AUTH_CONTACT_INVITE_REDEEM_MAX_PER_IP default'
  require_regex "$file" 'AUTH_CONTACT_INVITE_REDEEM_MAX_PER_PHONE:[[:space:]]*"\$\{AUTH_CONTACT_INVITE_REDEEM_MAX_PER_PHONE:-120\}"' 'AUTH_CONTACT_INVITE_REDEEM_MAX_PER_PHONE default'
  require_regex "$file" 'AUTH_CONTACT_INVITE_REDEEM_MAX_PER_TOKEN:[[:space:]]*"\$\{AUTH_CONTACT_INVITE_REDEEM_MAX_PER_TOKEN:-10\}"' 'AUTH_CONTACT_INVITE_REDEEM_MAX_PER_TOKEN default'
  require_absent "$file" 'AUTH_EXPOSE_CODES' 'AUTH_EXPOSE_CODES'
  require_absent "$file" 'AUTH_ALLOW_HEADER_SESSION_AUTH' 'AUTH_ALLOW_HEADER_SESSION_AUTH'
  require_absent "$file" 'AUTH_BLOCK_BROWSER_HEADER_SESSION' 'AUTH_BLOCK_BROWSER_HEADER_SESSION'
  require_absent "$file" 'AUTH_REQUEST_CODE_' 'AUTH_REQUEST_CODE_*'
  require_absent "$file" 'AUTH_VERIFY_' 'AUTH_VERIFY_*'
  require_absent "$file" 'AUTH_OTP_' 'AUTH_OTP_*'
  require_absent "$file" 'AUTH_RESOLVE_PHONE_' 'AUTH_RESOLVE_PHONE_*'
}

check_runtime_env_file() {
  local rel="$1"
  local file="$ROOT/$rel"
  if [[ ! -f "$file" ]]; then
    ok "$rel: runtime env file not present (skipped)"
    return
  fi

  local mode
  if mode="$(file_mode_octal "$file")"; then
    local mode3="${mode: -3}"
    if [[ "$mode3" =~ ^[0-7]{3}$ ]]; then
      local group="${mode3:1:1}"
      local other="${mode3:2:1}"
      if [[ "$group" != "0" || "$other" != "0" ]]; then
        fail "$rel: permissions too broad ($mode); expected owner-only access (e.g. 600)"
      else
        ok "$rel: owner-only permissions ($mode)"
      fi
    else
      fail "$rel: could not parse file mode '$mode'"
    fi
  else
    fail "$rel: unable to read file mode"
  fi

  local env_name
  env_name="$(awk -F= '/^ENV=/{print tolower($2); exit}' "$file" | tr -d '[:space:]')"
  if [[ "$env_name" =~ ^(prod|production|staging)$ ]]; then
    require_regex "$file" '^SHAMELL_DEPLOYMENT_PROFILE=ops-pi$' 'SHAMELL_DEPLOYMENT_PROFILE=ops-pi'
    require_absent "$file" '^ALLOWED_HOSTS=.*(localhost|127\.0\.0\.1)' 'loopback ALLOWED_HOSTS entries'
    require_absent "$file" '^ALLOWED_ORIGINS=.*\*' 'wildcard ALLOWED_ORIGINS entries'
    if rg -n --quiet '^ALLOWED_ORIGINS=' "$file"; then
      require_regex "$file" '^ALLOWED_ORIGINS=https://[^,[:space:]]+(,https://[^,[:space:]]+)*$' 'ALLOWED_ORIGINS https-only list'
    else
      ok "$file: ALLOWED_ORIGINS unset (secure compose default applies)"
    fi
    # Fail on explicit insecure runtime overrides. Missing keys are allowed when
    # compose defaults are already secure.
    require_absent "$file" '^BFF_REQUIRE_INTERNAL_SECRET=false$' 'BFF_REQUIRE_INTERNAL_SECRET=false'
    require_absent "$file" '^CHAT_REQUIRE_INTERNAL_SECRET=false$' 'CHAT_REQUIRE_INTERNAL_SECRET=false'
    require_absent "$file" '^CHAT_ENFORCE_DEVICE_AUTH=false$' 'CHAT_ENFORCE_DEVICE_AUTH=false'
    require_absent "$file" '^PAYMENTS_REQUIRE_INTERNAL_SECRET=false$' 'PAYMENTS_REQUIRE_INTERNAL_SECRET=false'
    require_absent "$file" '^BUS_REQUIRE_INTERNAL_SECRET=false$' 'BUS_REQUIRE_INTERNAL_SECRET=false'
    require_absent "$file" '^BFF_ENFORCE_ROUTE_AUTHZ=false$' 'BFF_ENFORCE_ROUTE_AUTHZ=false'
    require_absent "$file" '^CSRF_GUARD_ENABLED=false$' 'CSRF_GUARD_ENABLED=false'
    require_absent "$file" '^AUTH_ACCEPT_LEGACY_SESSION_COOKIE=true$' 'AUTH_ACCEPT_LEGACY_SESSION_COOKIE=true'
    require_absent "$file" '^AUTH_DEVICE_LOGIN_WEB_ENABLED=true$' 'AUTH_DEVICE_LOGIN_WEB_ENABLED=true'
    require_absent "$file" '^CHAT_PROTOCOL_V1_WRITE_ENABLED=true$' 'CHAT_PROTOCOL_V1_WRITE_ENABLED=true'
    require_absent "$file" '^CHAT_PROTOCOL_V1_READ_ENABLED=true$' 'CHAT_PROTOCOL_V1_READ_ENABLED=true'
    require_absent "$file" '^CHAT_PROTOCOL_REQUIRE_V2_FOR_GROUPS=false$' 'CHAT_PROTOCOL_REQUIRE_V2_FOR_GROUPS=false'
    if rg -n --quiet '^PAYMENTS_MAX_BODY_BYTES=' "$file"; then
      require_regex "$file" '^PAYMENTS_MAX_BODY_BYTES=[0-9]+$' 'PAYMENTS_MAX_BODY_BYTES numeric'
    else
      ok "$file: PAYMENTS_MAX_BODY_BYTES unset (secure compose default applies)"
    fi
    if rg -n --quiet '^BUS_MAX_BODY_BYTES=' "$file"; then
      require_regex "$file" '^BUS_MAX_BODY_BYTES=[0-9]+$' 'BUS_MAX_BODY_BYTES numeric'
    else
      ok "$file: BUS_MAX_BODY_BYTES unset (secure compose default applies)"
    fi
    if rg -n --quiet '^AUTH_ACCOUNT_CREATE_ENABLED=true$' "$file"; then
      require_regex "$file" '^AUTH_ACCOUNT_CREATE_HARDWARE_ATTESTATION_ENABLED=true$' 'AUTH_ACCOUNT_CREATE_HARDWARE_ATTESTATION_ENABLED=true when account-create enabled'
      require_regex "$file" '^AUTH_ACCOUNT_CREATE_REQUIRE_HARDWARE_ATTESTATION=true$' 'AUTH_ACCOUNT_CREATE_REQUIRE_HARDWARE_ATTESTATION=true when account-create enabled'
      if rg -n --quiet '^AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_TEAM_ID=.+$' "$file" \
        || rg -n --quiet '^AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON_B64=.+$' "$file"; then
        ok "$file: hardware attestation provider material configured"
      else
        fail "$file: AUTH_ACCOUNT_CREATE_ENABLED=true requires Apple/Google attestation provider material"
      fi
    else
      ok "$file: AUTH_ACCOUNT_CREATE_ENABLED not set to true (attestation provider check skipped)"
    fi
  else
    ok "$file: ENV is not prod/staging (runtime strict checks skipped)"
  fi
}

check_env_template "ops/pi/env.prod.example"
check_env_template "ops/pi/env.staging.example"
check_compose_defaults "ops/pi/docker-compose.yml"
check_compose_defaults "ops/pi/docker-compose.postgres.yml"
check_root_env_example ".env.example"
check_root_compose_defaults "docker-compose.yml"
check_runtime_env_file "ops/pi/.env"

if (( errors != 0 )); then
  exit 1
fi

echo "Deployment env invariants check passed."
