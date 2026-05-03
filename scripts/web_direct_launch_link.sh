#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/web_direct_launch_link.sh \
    --redirect-url https://online.shamell.online/control/ \
    [--api-origin https://api.shamell.online] \
    [--account-id <64-char-hex>] \
    [--phone <e164>] \
    [--device-id <device-id>] \
    [--expires-in-secs 604800] \
    [--bind-client-cidr 203.0.113.10/32]

Notes:
  - AUTH_WEB_DIRECT_LAUNCH_SIGNING_SECRET must be set in the environment.
  - Provide either --account-id or --phone.
  - Repeat --bind-client-cidr to restrict the link to one or more client CIDRs.
EOF
}

api_origin="${API_ORIGIN:-https://api.shamell.online}"
redirect_url=""
account_id=""
phone=""
device_id=""
expires_in_secs="604800"
declare -a bind_client_cidrs=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --api-origin)
      api_origin="${2:-}"
      shift 2
      ;;
    --redirect-url)
      redirect_url="${2:-}"
      shift 2
      ;;
    --account-id)
      account_id="${2:-}"
      shift 2
      ;;
    --phone)
      phone="${2:-}"
      shift 2
      ;;
    --device-id)
      device_id="${2:-}"
      shift 2
      ;;
    --expires-in-secs)
      expires_in_secs="${2:-}"
      shift 2
      ;;
    --bind-client-cidr)
      bind_client_cidrs+=("${2:-}")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

signing_secret="${AUTH_WEB_DIRECT_LAUNCH_SIGNING_SECRET:-}"
if [[ -z "$signing_secret" ]]; then
  printf 'AUTH_WEB_DIRECT_LAUNCH_SIGNING_SECRET must be set.\n' >&2
  exit 2
fi
if [[ -z "$redirect_url" ]]; then
  printf '--redirect-url is required.\n' >&2
  exit 2
fi
if [[ -z "$account_id" && -z "$phone" ]]; then
  printf 'Either --account-id or --phone is required.\n' >&2
  exit 2
fi

python3 - "$api_origin" "$redirect_url" "$account_id" "$phone" "$device_id" "$expires_in_secs" "$signing_secret" "${bind_client_cidrs[@]:-}" <<'PY'
import base64
import hashlib
import hmac
import json
import sys
import time
import urllib.parse

api_origin, redirect_url, account_id, phone, device_id, expires_in_secs, secret, *cidrs = sys.argv[1:]

def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(2)

try:
    parsed_api_origin = urllib.parse.urlparse(api_origin.strip())
except Exception:
    parsed_api_origin = None
if not parsed_api_origin or parsed_api_origin.scheme not in {"http", "https"} or not parsed_api_origin.netloc:
    fail("API origin must be an absolute http(s) origin.")

try:
    parsed_redirect = urllib.parse.urlparse(redirect_url.strip())
except Exception:
    parsed_redirect = None
if not parsed_redirect or parsed_redirect.scheme not in {"http", "https"} or not parsed_redirect.netloc:
    fail("Redirect URL must be an absolute http(s) URL.")

try:
    expires_in = int(expires_in_secs)
except ValueError:
    fail("--expires-in-secs must be an integer.")
if expires_in < 300 or expires_in > 2592000:
    fail("--expires-in-secs must be between 300 and 2592000.")

payload = {
    "v": 1,
    "redirect": redirect_url.strip(),
    "iat": int(time.time()),
    "exp": int(time.time()) + expires_in,
    "client_cidrs": [value.strip() for value in cidrs if value.strip()],
}
if account_id.strip():
    payload["account_id"] = account_id.strip().lower()
if phone.strip():
    payload["phone"] = phone.strip()
if device_id.strip():
    payload["device_id"] = device_id.strip()

payload_bytes = json.dumps(payload, separators=(",", ":"), ensure_ascii=True).encode("utf-8")
payload_b64 = base64.urlsafe_b64encode(payload_bytes).decode("ascii").rstrip("=")
signature = hmac.new(secret.encode("utf-8"), payload_bytes, hashlib.sha256).digest()
sig_b64 = base64.urlsafe_b64encode(signature).decode("ascii").rstrip("=")
token = f"v1.{payload_b64}.{sig_b64}"
query = urllib.parse.urlencode({"token": token})
launch_url = f"{api_origin.rstrip('/')}/auth/direct-web/launch?{query}"
print(launch_url)
PY
