#!/usr/bin/env bash
set -euo pipefail

HOST_ALIAS="${1:-shamell}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CF_SNIPPET="${REPO_ROOT}/ops/hetzner/nginx/snippets/shamell_cloudflare_realip.conf"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

require_cmd ssh
require_cmd scp
require_cmd awk

if [[ ! -f "${CF_SNIPPET}" ]]; then
  echo "Missing Cloudflare snippet: ${CF_SNIPPET}" >&2
  exit 1
fi

tmp_local="$(mktemp)"
trap 'rm -f "${tmp_local}"' EXIT

# Source of truth: the Nginx Real-IP snippet lists the trusted Cloudflare CIDRs.
awk '/^set_real_ip_from[[:space:]]+/ {gsub(/;/, "", $2); print $2}' "${CF_SNIPPET}" >"${tmp_local}"

cidr_count="$(wc -l <"${tmp_local}" | tr -d ' ')"
if [[ "${cidr_count}" -lt 10 ]]; then
  echo "Parsed too few Cloudflare CIDRs (${cidr_count}) from ${CF_SNIPPET}" >&2
  exit 1
fi

tmp_remote="/tmp/shamell-ufw-sync-$$"

echo "Copying Cloudflare CIDR list to ${HOST_ALIAS}:${tmp_remote}"
ssh "${HOST_ALIAS}" "mkdir -p '${tmp_remote}'"
scp "${tmp_local}" "${HOST_ALIAS}:${tmp_remote}/cloudflare_cidrs.txt"

echo "Applying UFW policy on ${HOST_ALIAS}"
ssh -tt "${HOST_ALIAS}" "
  set -euo pipefail

  if ! command -v ufw >/dev/null 2>&1; then
    echo 'ufw not installed on host' >&2
    exit 1
  fi

  # Safety gate: if SSH is not over Tailscale, do not mutate SSH rules.
  client_ip=''
  if [[ -n \"\${SSH_CONNECTION:-}\" ]]; then
    client_ip=\"\$(echo \"\$SSH_CONNECTION\" | awk '{print \$1}')\"
  fi
  is_tailscale_client=0
  if [[ -n \"\$client_ip\" ]]; then
    # python is present on Ubuntu by default; this keeps the CIDR check correct.
    is_tailscale_client=\"\$(CLIENT_IP=\"\$client_ip\" python3 - <<'PY'
import ipaddress, os, sys
raw = os.environ.get('CLIENT_IP','').strip()
try:
    ip = ipaddress.ip_address(raw)
    print(1 if ip in ipaddress.ip_network('100.64.0.0/10') else 0)
except Exception:
    print(0)
PY
)\"
  fi

  sudo ufw default deny incoming >/dev/null
  sudo ufw default allow outgoing >/dev/null

  # SSH: allow only over Tailscale. If the current session is not on Tailscale,
  # we refuse to change SSH rules to avoid locking you out.
  if [[ \"\$is_tailscale_client\" == \"1\" ]]; then
    if ip link show tailscale0 >/dev/null 2>&1; then
      # Best practice: allow SSH only from the current admin device's
      # Tailscale IP, not from the entire tailnet.
      sudo ufw allow in on tailscale0 proto tcp from \"\$client_ip\" to any port 22 >/dev/null || true
    else
      sudo ufw allow proto tcp from \"\$client_ip\" to any port 22 >/dev/null || true
    fi
  else
    echo 'WARNING: SSH client IP is not in 100.64.0.0/10 (Tailscale). Skipping SSH rule changes.' >&2
  fi

  # HTTP/HTTPS: allow only Cloudflare ranges to hit the origin.
  # Port 80 is useful for HTTP->HTTPS redirects and ACME HTTP-01 renewals when
  # the DNS record is proxied through Cloudflare.
  while IFS= read -r cidr; do
    [[ -z \"\$cidr\" ]] && continue
    sudo ufw allow proto tcp from \"\$cidr\" to any port 80 >/dev/null || true
    sudo ufw allow proto tcp from \"\$cidr\" to any port 443 >/dev/null || true
  done <'${tmp_remote}/cloudflare_cidrs.txt'

  # Remove unsafe / confusing rules (best-effort).
  # - Generic 443 allows defeat the Cloudflare-only origin lockdown.
  # - A generic v6 deny can shadow later allow rules depending on ordering.
  # - A self-referential SSH allow (from the server's own Tailscale IP) is useless.
  tailscale_ip=''
  if ip -brief address show dev tailscale0 >/dev/null 2>&1; then
    tailscale_ip=\"\$(ip -brief address show dev tailscale0 | awk '{print \$3}' | head -n1 | cut -d/ -f1)\"
  fi

  nums_to_delete=\"\$(sudo ufw status numbered | awk -v ts_ip=\"\$tailscale_ip\" -v allow_ssh=\"\$is_tailscale_client\" '
    /^\\[/ {
      num=\$2; gsub(/[^0-9]/, \"\", num)
      line=\$0
      sub(/^\\[[^]]+\\][[:space:]]*/, \"\", line)
      # 1) delete any generic allow of 80/443 from Anywhere
      if (line ~ /^80\\/tcp/ && line ~ /ALLOW IN/ && line ~ /Anywhere/) print num
      if (line ~ /^443\\/tcp/ && line ~ /ALLOW IN/ && line ~ /Anywhere/) print num
      # 2) delete generic deny rules for 80/443 from Anywhere (ordering hazard; default policy is deny)
      if (line ~ /^80\\/tcp/ && line ~ /DENY IN/ && line ~ /Anywhere/) print num
      if (line ~ /^443\\/tcp/ && line ~ /DENY IN/ && line ~ /Anywhere/) print num
      if (allow_ssh == 1) {
        # 3) delete any public SSH allow (SSH should be Tailscale-only)
        if (line ~ /^22\\/tcp/ && line ~ /ALLOW IN/ && line ~ /Anywhere/) print num
        # 4) delete broad tailnet SSH allow (prefer per-admin-device allow)
        if (line ~ /^22\\/tcp/ && line ~ /ALLOW IN/ && line ~ /100\\.64\\.0\\.0\\/10/) print num
        # 5) delete an SSH allow from the server's own tailscale IP (useless)
        if (ts_ip != \"\" && line ~ /^22\\/tcp/ && line ~ /ALLOW IN/ && index(line, ts_ip) > 0) print num
      }
    }
  ' | sort -rn | uniq)\"

  if [[ -n \"\$nums_to_delete\" ]]; then
    while IFS= read -r n; do
      [[ -z \"\$n\" ]] && continue
      sudo ufw --force delete \"\$n\" >/dev/null || true
    done <<<\"\$nums_to_delete\"
  fi

  sudo ufw --force enable >/dev/null
  sudo ufw status verbose

  rm -rf '${tmp_remote}'
"

echo "UFW sync complete."
