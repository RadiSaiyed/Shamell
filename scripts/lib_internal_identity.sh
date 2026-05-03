#!/usr/bin/env bash

internal_identity_normalize_service_id() {
  local raw="${1:-}"
  local caller
  caller="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
  caller="${caller#"${caller%%[![:space:]]*}"}"
  caller="${caller%"${caller##*[![:space:]]}"}"
  if [[ -z "$caller" || "${#caller}" -gt 64 || ! "$caller" =~ ^[a-z0-9._-]+$ ]]; then
    echo "service id must be 1..64 [A-Za-z0-9-_.]" >&2
    return 1
  fi
  printf '%s' "$caller"
}

internal_identity_normalize_audience() {
  internal_identity_normalize_service_id "$1"
}

internal_identity_require_signing_tools() {
  local cmd
  for cmd in openssl xxd; do
    command -v "$cmd" >/dev/null 2>&1 || {
      echo "Missing required command: $cmd" >&2
      return 1
    }
  done
}

internal_identity_url_path_query() {
  local url="$1"
  local rest="${url#*://}"
  if [[ "$rest" == */* ]]; then
    printf '/%s' "${rest#*/}"
  else
    printf '/'
  fi
}

internal_identity_b64_nopad_file() {
  local file="$1"
  openssl base64 -A -in "$file" | tr -d '='
}

internal_identity_seed_b64_to_pem() {
  local seed_b64="$1"
  local pem_out="$2"
  local tmp_dir seed_hex
  tmp_dir="$(mktemp -d)"
  seed_hex="$(
    printf '%s' "$seed_b64" |
      openssl base64 -d -A 2>/dev/null |
      xxd -p -c 256 |
      tr -d '\n'
  )"
  if [[ "${#seed_hex}" != "64" ]]; then
    rm -rf "$tmp_dir"
    echo "internal identity seed must decode to 32 bytes" >&2
    return 1
  fi
  printf '302e020100300506032b657004220420%s' "$seed_hex" | xxd -r -p > "${tmp_dir}/key.der"
  if ! openssl pkey -inform DER -in "${tmp_dir}/key.der" -out "$pem_out" >/dev/null 2>&1; then
    rm -rf "$tmp_dir"
    echo "failed to convert internal identity seed to PEM" >&2
    return 1
  fi
  rm -rf "$tmp_dir"
}

internal_identity_build_curl_headers() {
  local seed_b64="$1"
  local service_id="$2"
  local audience="$3"
  local method="$4"
  local url="$5"
  local body_file="$6"
  local tmp_dir pem_file msg_v1_file msg_v2_file sig_v1_file sig_v2_file digest_file
  local path_and_query timestamp nonce body_hash sig_v1_b64 sig_v2_b64

  if [[ -z "$seed_b64" || -z "$service_id" || -z "$audience" || -z "$method" || -z "$url" ]]; then
    echo "internal identity signing requires seed, service_id, audience, method, and url" >&2
    return 1
  fi
  if [[ ! -f "$body_file" ]]; then
    echo "internal identity body file missing: $body_file" >&2
    return 1
  fi

  internal_identity_require_signing_tools || return 1
  service_id="$(internal_identity_normalize_service_id "$service_id")" || return 1
  audience="$(internal_identity_normalize_audience "$audience")" || return 1

  tmp_dir="$(mktemp -d)"
  pem_file="${tmp_dir}/key.pem"
  msg_v1_file="${tmp_dir}/msg.v1"
  msg_v2_file="${tmp_dir}/msg.v2"
  sig_v1_file="${tmp_dir}/sig.v1"
  sig_v2_file="${tmp_dir}/sig.v2"
  digest_file="${tmp_dir}/body.sha256"

  internal_identity_seed_b64_to_pem "$seed_b64" "$pem_file" || {
    rm -rf "$tmp_dir"
    return 1
  }

  path_and_query="$(internal_identity_url_path_query "$url")"
  timestamp="$(date +%s)"
  nonce="$(openssl rand -hex 16)"
  openssl dgst -binary -sha256 "$body_file" > "$digest_file"
  body_hash="$(internal_identity_b64_nopad_file "$digest_file")"

  printf 'shamell-internal-v1\n%s\n%s\n%s\n%s\n%s\n%s' \
    "$service_id" \
    "$(printf '%s' "$method" | tr '[:lower:]' '[:upper:]')" \
    "$path_and_query" \
    "$timestamp" \
    "$nonce" \
    "$body_hash" > "$msg_v1_file"

  printf 'shamell-internal-v2\n%s\n%s\n%s\n%s\n%s\n%s\n%s' \
    "$service_id" \
    "$audience" \
    "$(printf '%s' "$method" | tr '[:lower:]' '[:upper:]')" \
    "$path_and_query" \
    "$timestamp" \
    "$nonce" \
    "$body_hash" > "$msg_v2_file"

  openssl pkeyutl -sign -rawin -inkey "$pem_file" -in "$msg_v1_file" -out "$sig_v1_file" >/dev/null 2>&1 || {
    rm -rf "$tmp_dir"
    echo "failed to sign internal identity v1 payload" >&2
    return 1
  }
  openssl pkeyutl -sign -rawin -inkey "$pem_file" -in "$msg_v2_file" -out "$sig_v2_file" >/dev/null 2>&1 || {
    rm -rf "$tmp_dir"
    echo "failed to sign internal identity v2 payload" >&2
    return 1
  }

  sig_v1_b64="$(internal_identity_b64_nopad_file "$sig_v1_file")"
  sig_v2_b64="$(internal_identity_b64_nopad_file "$sig_v2_file")"

  printf '%s\n' "X-Internal-Service-Id: ${service_id}"
  printf '%s\n' "X-Internal-Identity-Sig: ${sig_v1_b64}"
  printf '%s\n' "X-Internal-Audience: ${audience}"
  printf '%s\n' "X-Internal-Identity-Ts: ${timestamp}"
  printf '%s\n' "X-Internal-Identity-Nonce: ${nonce}"
  printf '%s\n' "X-Internal-Identity-Sig-V2: ${sig_v2_b64}"

  rm -rf "$tmp_dir"
}
