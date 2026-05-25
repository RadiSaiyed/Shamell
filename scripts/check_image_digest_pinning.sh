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

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

strip_quotes() {
  local s
  s="$(trim "$1")"
  s="${s%\"}"
  s="${s#\"}"
  s="${s%\'}"
  s="${s#\'}"
  printf '%s' "$s"
}

to_lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

is_local_project_image() {
  local image="$1"
  [[ "$image" == shamell-* ]]
}

check_compose_file() {
  local rel="$1"
  local file="$ROOT/$rel"
  if [[ ! -f "$file" ]]; then
    fail "Missing compose file: $rel"
    return
  fi

  local found=0
  local line_no=0
  while IFS= read -r line; do
    ((line_no += 1))
    if [[ ! "$line" =~ ^[[:space:]]*image:[[:space:]]*(.+)$ ]]; then
      continue
    fi
    found=1
    local raw="${BASH_REMATCH[1]}"
    raw="${raw%%#*}"
    local image
    image="$(strip_quotes "$raw")"
    if [[ -z "$image" ]]; then
      fail "$rel:$line_no empty image reference"
      continue
    fi
    if is_local_project_image "$image"; then
      continue
    fi
    if [[ "$image" =~ @sha256:[a-f0-9]{64}$ ]]; then
      ok "$rel:$line_no pinned image digest"
    else
      fail "$rel:$line_no unpinned external image: $image"
    fi
  done <"$file"

  if (( found == 0 )); then
    fail "$rel contains no image references"
  fi
}

check_dockerfile() {
  local rel="$1"
  local file="$ROOT/$rel"
  if [[ ! -f "$file" ]]; then
    fail "Missing Dockerfile: $rel"
    return
  fi

  local -a stage_aliases=()
  local found=0
  local line_no=0

  while IFS= read -r line; do
    ((line_no += 1))
    local body
    body="$(trim "${line%%#*}")"
    [[ -n "$body" ]] || continue
    if [[ "$(to_lower "$body")" != from* ]]; then
      continue
    fi
    found=1

    # shellcheck disable=SC2206
    local parts=($body)
    if (( ${#parts[@]} < 2 )); then
      fail "$rel:$line_no malformed FROM line"
      continue
    fi

    local idx=1
    while (( idx < ${#parts[@]} )) && [[ "${parts[idx]}" == --* ]]; do
      ((idx += 1))
    done
    if (( idx >= ${#parts[@]} )); then
      fail "$rel:$line_no malformed FROM line (missing image token)"
      continue
    fi

    local image="${parts[idx]}"
    local is_stage_ref=0
    for alias in "${stage_aliases[@]-}"; do
      if [[ "$image" == "$alias" ]]; then
        is_stage_ref=1
        break
      fi
    done

    local alias_name=""
    local j=$((idx + 1))
    while (( j + 1 < ${#parts[@]} )); do
      if [[ "$(to_lower "${parts[j]}")" == "as" ]]; then
        alias_name="${parts[j + 1]}"
        break
      fi
      ((j += 1))
    done
    if [[ -n "$alias_name" ]]; then
      stage_aliases+=("$alias_name")
    fi

    if (( is_stage_ref )); then
      continue
    fi

    if [[ "$image" =~ @sha256:[a-f0-9]{64}$ ]]; then
      ok "$rel:$line_no pinned base image digest"
    else
      fail "$rel:$line_no unpinned base image: $image"
    fi
  done <"$file"

  if (( found == 0 )); then
    fail "$rel contains no FROM directives"
  fi
}

check_compose_file "docker-compose.yml"
check_compose_file "ops/pi/docker-compose.yml"
check_compose_file "ops/pi/docker-compose.postgres.yml"
check_compose_file "ops/livekit/docker-compose.yml"

while IFS= read -r dockerfile; do
  check_dockerfile "$dockerfile"
done < <(cd "$ROOT" && find services_rs crates_rs -name Dockerfile -type f | sort)

check_dashboard_proxy_script() {
  local rel="$1"
  local file="$ROOT/$rel"
  if [[ ! -f "$file" ]]; then
    fail "Missing dashboard proxy script: $rel"
    return
  fi
  if rg -n --quiet 'DASHBOARD_PROXY_NGINX_IMAGE:-nginx:1\.27-alpine@sha256:[a-f0-9]{64}' "$file"; then
    ok "$rel default nginx image digest is pinned"
  else
    fail "$rel missing digest-pinned DASHBOARD_PROXY_NGINX_IMAGE default"
  fi
  if rg -n --quiet 'DASHBOARD_PROXY_NGINX_IMAGE must be digest-pinned' "$file"; then
    ok "$rel runtime digest enforcement present"
  else
    fail "$rel missing runtime digest enforcement message"
  fi
}

check_dashboard_proxy_script "scripts/start_dashboard_dev_proxy.sh"
check_dashboard_proxy_script "scripts/start_all_dashboard_proxies.sh"

check_ci_workflow_actionlint_image() {
  local rel=".github/workflows/ci.yml"
  local file="$ROOT/$rel"
  if [[ ! -f "$file" ]]; then
    fail "Missing workflow file: $rel"
    return
  fi

  if rg -n --quiet 'rhysd/actionlint:1\.7\.8@sha256:[a-f0-9]{64}' "$file"; then
    ok "$rel actionlint docker image digest is pinned"
  else
    fail "$rel missing digest-pinned actionlint docker image"
  fi

  if rg -n --quiet 'rhysd/actionlint:1\.7\.8([[:space:]]|$)' "$file"; then
    fail "$rel contains unpinned actionlint docker image reference"
  else
    ok "$rel has no unpinned actionlint docker image reference"
  fi
}

check_ci_workflow_actionlint_image

if (( errors != 0 )); then
  exit 1
fi

echo "Image digest pinning guard passed."
