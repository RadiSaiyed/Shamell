#!/usr/bin/env bash
set -euo pipefail

# Seed rich demo listings across property categories for an operator
# Usage:
#   OP_ID=2 TOKEN=xxxxx BASE=http://127.0.0.1:8002 ./ops/dev/seed_stays_categories.sh

BASE=${BASE:-http://127.0.0.1:8002}
PHONE=${PHONE:-0999000001}
NAME=${NAME:-"Demo Stays Hotel"}
CITY=${CITY:-Damascus}
OP_ID=${OP_ID:-}
TOKEN=${TOKEN:-}

hdr_auth(){ [ -n "$TOKEN" ] && printf 'Authorization: Bearer %s' "$TOKEN"; }

ensure_operator(){
  if [ -n "$OP_ID" ] && [ -n "$TOKEN" ]; then return; fi
  echo "[seed] Ensuring operator via OTP for $PHONE"
  local req code body ver
  req=$(curl -fsS -X POST "$BASE/operators/request_code" -H 'content-type: application/json' -d '{"phone":"'"$PHONE"'"}') || true
  code=$(printf '%s' "$req" | sed -n 's/.*"code":"\([0-9][0-9]*\)".*/\1/p')
  [ -z "$code" ] && { echo "[seed] WARN: no code returned"; code=000000; }
  body=$(printf '{"phone":"%s","code":"%s","name":"%s","city":"%s"}' "$PHONE" "$code" "$NAME" "$CITY")
  ver=$(curl -fsS -X POST "$BASE/operators/verify" -H 'content-type: application/json' -d "$body")
  OP_ID=$(printf '%s' "$ver" | sed -n 's/.*"operator_id":\([0-9][0-9]*\).*/\1/p')
  TOKEN=$(printf '%s' "$ver" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
  if [ -z "$OP_ID" ] || [ -z "$TOKEN" ]; then echo "[seed] ERR: failed to get operator/token"; exit 1; fi
}

create_listing(){
  local title="$1" city="$2" price="$3" addr="$4" desc="$5" type="$6" img1="$7" img2="$8"
  local imgs json
  imgs=""; [ -n "$img1" ] && imgs="\"$img1\""; [ -n "$img2" ] && imgs="${imgs:+$imgs, }\"$img2\""
  json=$(printf '{"title":"%s","city":"%s","address":"%s","description":"%s","property_type":"%s","image_urls":[%s],"price_per_night_cents":%s}' \
    "$title" "$city" "$addr" "$desc" "$type" "$imgs" "$price")
  curl -fsS -X POST "$BASE/operators/$OP_ID/listings" -H 'content-type: application/json' -H "$(hdr_auth)" -d "$json" | jq -c . 2>/dev/null || true
}

ensure_operator
echo "[seed] Using operator $OP_ID"

# Populate multiple categories
create_listing "Downtown Hotel" "Damascus" 500000 "Souq" "Central hotel" "Hotels" \
  "https://images.unsplash.com/photo-1551882547-ff40c63fe5fa" ""
create_listing "Old City Apartment" "Aleppo" 300000 "Old City" "Cozy flat" "Apartments" \
  "https://images.unsplash.com/photo-1505691938895-1758d7feb511" ""
create_listing "Beach Resort" "Latakia" 650000 "Corniche" "Seaside resort" "Resorts" \
  "https://images.unsplash.com/photo-1512453979798-5ea266f8880c" ""
create_listing "Palm Villa" "Tartus" 720000 "Harbour" "Private villa" "Villas" \
  "https://images.unsplash.com/photo-1494526585095-c41746248156" ""
create_listing "Mountain Cabin" "Bloudan" 280000 "Hills" "Cozy cabin" "Cabins" \
  "https://images.unsplash.com/photo-1501183638710-841dd1904471" ""
create_listing "Country Cottage" "Hama" 260000 "Countryside" "Charming cottage" "Cottages" \
  "https://images.unsplash.com/photo-1554995207-c18c203602cb" ""
create_listing "Desert Glamping" "Palmyra" 240000 "Camp" "Glamping tents" "Glamping Sites" \
  "https://images.unsplash.com/photo-1500530855697-b586d89ba3ee" ""
create_listing "City Serviced Apt" "Damascus" 350000 "Marjeh" "Serviced apartment" "Serviced Apartments" \
  "https://images.unsplash.com/photo-1505691723518-36a5ac3b2d95" ""
create_listing "Family Vacation Home" "Homs" 320000 "Hamra" "Family home" "Vacation Homes" \
  "https://images.unsplash.com/photo-1518780664697-55e3ad937233" ""
create_listing "Old Town Guest House" "Damascus" 220000 "Bab Sharqi" "Guest house" "Guest Houses" \
  "https://images.unsplash.com/photo-1522708323590-d24dbb6b0267" ""
create_listing "Backpackers Hostel" "Aleppo" 180000 "Citadel" "Hostel" "Hostels" \
  "https://images.unsplash.com/photo-1505691723518-36a5ac3b2d95" ""
create_listing "Highway Motel" "Hama" 160000 "Ring Road" "Motel" "Motels" \
  "https://images.unsplash.com/photo-1528909514045-2fa4ac7a08ba" ""
create_listing "Cozy B&B" "Tartus" 200000 "Old Port" "Bed and Breakfast" "B&Bs" \
  "https://images.unsplash.com/photo-1519710164239-da123dc03ef4" ""
create_listing "Traditional Ryokan" "Damascus" 400000 "Garden" "Japanese inn" "Ryokans" \
  "https://images.unsplash.com/photo-1501183638710-841dd1904471" ""
create_listing "Medina Riad" "Old Damascus" 420000 "Al-Hamidiya" "Moroccan riad style" "Riads" \
  "https://images.unsplash.com/photo-1494526585095-c41746248156" ""
create_listing "Resort Village Suite" "Latakia" 480000 "Village" "Resort village" "Resort Villages" \
  "https://images.unsplash.com/photo-1512453979798-5ea266f8880c" ""
create_listing "Family Homestay" "Homs" 190000 "Neighborhood" "Homestay" "Homestays" \
  "https://images.unsplash.com/photo-1554995207-c18c203602cb" ""
create_listing "Campground Tent" "Palmyra" 90000 "Campground" "Camp site" "Campgrounds" \
  "https://images.unsplash.com/photo-1500530855697-b586d89ba3ee" ""
create_listing "Country House" "Hama" 350000 "Fields" "Country house" "Country Houses" \
  "https://images.unsplash.com/photo-1522708323590-d24dbb6b0267" ""
create_listing "Farm Stay" "Rural" 210000 "Farm" "Farm stay" "Farm Stays" \
  "https://images.unsplash.com/photo-1519710164239-da123dc03ef4" ""
create_listing "Harbor Boat" "Tartus" 330000 "Marina" "Boat lodging" "Boats" \
  "https://images.unsplash.com/photo-1518780664697-55e3ad937233" ""
create_listing "Luxury Tent" "Palmyra" 270000 "Oasis" "Luxury tent" "Luxury Tents" \
  "https://images.unsplash.com/photo-1500530855697-b586d89ba3ee" ""
create_listing "Self-Catering Flat" "Damascus" 310000 "Downtown" "Self-catering" "Self-Catering Accomodations" \
  "https://images.unsplash.com/photo-1505691938895-1758d7feb511" ""
create_listing "Tiny House" "Bloudan" 230000 "Meadow" "Tiny house" "Tiny Houses" \
  "https://images.unsplash.com/photo-1551882547-ff40c63fe5fa" ""

echo "[seed] Completed seeding categories for OP_ID=$OP_ID"

