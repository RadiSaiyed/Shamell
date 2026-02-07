#!/usr/bin/env bash
set -euo pipefail

# Simple helper to sync the local Shamell repo to the Raspberry Pi.
# Usage:
#   cd ~/Shamell
#   ops/deploy_pi.sh
#
# You can override defaults via env:
#   PI_HOST=raspi5.local PI_USER=radi PI_PATH=/home/radi/Shamell ops/deploy_pi.sh

PI_HOST="${PI_HOST:-raspi5.local}"
PI_USER="${PI_USER:-radi}"
PI_PATH="${PI_PATH:-/home/${PI_USER}/Shamell}"

echo "Deploying Shamell to ${PI_USER}@${PI_HOST}:${PI_PATH} ..."

rsync -av --delete \
  --exclude '.git' \
  --exclude '.venv*' \
  --exclude '__pycache__' \
  --exclude '.dart_tool' \
  --exclude 'build' \
  ./ "${PI_USER}@${PI_HOST}:${PI_PATH}/"

echo "Sync complete."

