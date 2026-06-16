#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CERT_DIR="${DEV_PROXY_CERT_DIR:-${ROOT}/ops/dev-proxy/certs}"
CERT_FILE="${DEV_PROXY_CERT_FILE:-${CERT_DIR}/cert.pem}"
KEY_FILE="${DEV_PROXY_KEY_FILE:-${CERT_DIR}/key.pem}"

mkdir -p "${CERT_DIR}"

if [[ -s "${CERT_FILE}" && -s "${KEY_FILE}" ]]; then
  exit 0
fi

if command -v mkcert >/dev/null 2>&1; then
  mkcert -cert-file "${CERT_FILE}" -key-file "${KEY_FILE}" localhost 127.0.0.1 ::1 >/dev/null
  chmod 600 "${KEY_FILE}" || true
  exit 0
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "Missing TLS tooling: install 'mkcert' or 'openssl' to generate a local cert." >&2
  exit 1
fi

tmp_cfg="$(mktemp)"
cat >"${tmp_cfg}" <<'EOF'
[ req ]
prompt = no
default_bits = 2048
distinguished_name = dn
x509_extensions = v3_req

[ dn ]
CN = localhost

[ v3_req ]
subjectAltName = @alt_names
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth

[ alt_names ]
DNS.1 = localhost
IP.1 = 127.0.0.1
IP.2 = ::1
EOF

openssl req -x509 -nodes -days 825 -newkey rsa:2048 \
  -keyout "${KEY_FILE}" \
  -out "${CERT_FILE}" \
  -config "${tmp_cfg}"

rm -f "${tmp_cfg}"
chmod 600 "${KEY_FILE}" || true
