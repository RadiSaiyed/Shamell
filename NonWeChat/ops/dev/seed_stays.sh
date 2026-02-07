#!/usr/bin/env bash
set -euo pipefail

BASE=${BASE:-http://127.0.0.1:8001}

seed() {
  local title="$1" city="$2" price="$3" owner="$4" key
  key="seed-$(echo -n "$title|$city|$price|$owner" | shasum | awk '{print $1}')"
  curl -fsS -X POST "$BASE/listings" \
    -H 'content-type: application/json' \
    -H "Idempotency-Key: $key" \
    --data "{\"title\":\"$title\",\"city\":\"$city\",\"price_per_night_cents\":$price,\"owner_wallet_id\":\"$owner\"}" >/dev/null || true
}

echo "[seed] Adding sample stays listings to $BASE..."
seed "Old Damascus Boutique" "Damascus" 450000 "WLT-DMS-001"
seed "Seaside Apartment" "Latakia" 300000 "WLT-LTK-101"
seed "Aleppo Heritage House" "Aleppo" 380000 "WLT-ALP-207"
seed "Palmyra Desert Camp" "Palmyra" 220000 "WLT-PAL-310"
echo "[seed] Done. Try: curl -s $BASE/listings | jq -c '.[0]'"

