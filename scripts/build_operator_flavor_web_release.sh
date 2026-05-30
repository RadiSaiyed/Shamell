#!/usr/bin/env bash
set -euo pipefail

# Build a Flutter web bundle for one of the standalone operator
# flavors (carrier / busOperator / hotelOperator / taxiOperator).
# Sibling to build_control_web_release.sh which is hard-coded to the
# legacy `operator` flavor → /control/ — we keep the two scripts split
# so a regression here can't take /control/ down.
#
# Usage:
#   scripts/build_operator_flavor_web_release.sh \
#       --flavor carrier \
#       --output-dir .artifacts/carrier-web-release
#
# Defaults derive base-href from the flavor:
#   carrier        → /carrier/
#   busOperator    → /bus-control/
#   hotelOperator  → /hotels-admin/
#   taxiOperator   → /taxi-control/

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLIENT_DIR="${REPO_ROOT}/clients/shamell_flutter"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
FLAVOR=""
OUTPUT_DIR=""
BASE_HREF=""

usage() {
  cat <<'EOF'
Usage: scripts/build_operator_flavor_web_release.sh --flavor FLAVOR [--output-dir DIR] [--base-href /carrier/]

Build a Flutter web bundle for a standalone operator flavor.

Required:
  --flavor FLAVOR    One of: carrier, busOperator, hotelOperator, taxiOperator

Optional:
  --output-dir DIR   Default: .artifacts/<flavor>-web-release
  --base-href PATH   Default: derived from flavor (must start/end with '/')
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --flavor) FLAVOR="$2"; shift 2 ;;
    --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
    --base-href) BASE_HREF="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ -z "$FLAVOR" ]]; then
  echo "--flavor is required" >&2
  usage >&2
  exit 1
fi

# Per-flavor derivations. Kept here as a single switch so a new flavor
# is one bash block + one workflow matrix entry away.
case "$FLAVOR" in
  carrier)
    entry="lib/main_carrier.dart"
    surface="carrier"
    title="Shamell Carrier"
    short_name="Carrier"
    description="Shamell Carrier web console: freight org, fleet, drivers, certificates, load offers."
    slug="carrier"
    cache_scope="/carrier/"
    ;;
  busOperator|bus_operator|bus)
    FLAVOR="busOperator"
    entry="lib/main_bus_operator.dart"
    surface="bus_operator"
    title="Shamell Bus Control"
    short_name="BusControl"
    description="Shamell Bus Control web console: coach dispatch, boarding, settlement, payouts."
    slug="bus-control"
    cache_scope="/bus-control/"
    ;;
  hotelOperator|hotel_operator|hotel)
    FLAVOR="hotelOperator"
    entry="lib/main_hotel_operator.dart"
    surface="hotel_operator"
    title="Shamell Hotels Admin"
    short_name="HotelsAdmin"
    description="Shamell Hotels Admin web console: bookings, room-service orders, settlement."
    slug="hotels-admin"
    cache_scope="/hotels-admin/"
    ;;
  taxiOperator|taxi_operator|taxi)
    FLAVOR="taxiOperator"
    entry="lib/main_taxi_operator.dart"
    surface="taxi_operator"
    title="Shamell Taxi Control"
    short_name="TaxiControl"
    description="Shamell Taxi Control web console: live trips, driver dispatch, support queue, payouts."
    slug="taxi-control"
    cache_scope="/taxi-control/"
    ;;
  *)
    echo "Unknown --flavor: $FLAVOR (allowed: carrier, busOperator, hotelOperator, taxiOperator)" >&2
    exit 1
    ;;
esac

if [[ -z "$OUTPUT_DIR" ]]; then
  OUTPUT_DIR="${REPO_ROOT}/.artifacts/${slug}-web-release"
fi
if [[ -z "$BASE_HREF" ]]; then
  BASE_HREF="/${slug}/"
fi

case "$BASE_HREF" in
  /*/) ;;
  *) echo "--base-href must start and end with '/': $BASE_HREF" >&2; exit 1 ;;
esac

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

require_cmd "$FLUTTER_BIN"
require_cmd python3
require_cmd git

append_dart_define_if_set() {
  local key="$1"
  local value="${!key:-}"
  if [[ -n "$value" ]]; then
    dart_defines+=("--dart-define=${key}=${value}")
  fi
}

dart_defines=(
  "--dart-define=APP_MODE=${surface}"
  "--dart-define=SHAMELL_APP_SURFACE=${surface}"
)

for key in \
  BASE_URL \
  TRUSTED_API_ORIGINS \
  TRUSTED_TLS_CERTIFICATES_DER_BASE64 \
  SHAMELL_CONTROL_WEB_DIRECT_DASHBOARD_HOSTS \
  SHAMELL_WEB_DIRECT_APP_HOSTS \
  SHAMELL_FIREBASE_API_KEY \
  SHAMELL_FIREBASE_MESSAGING_SENDER_ID \
  SHAMELL_FIREBASE_PROJECT_ID \
  SHAMELL_FIREBASE_STORAGE_BUCKET \
  SHAMELL_FIREBASE_AUTH_DOMAIN \
  SHAMELL_FIREBASE_MEASUREMENT_ID \
  SHAMELL_FIREBASE_WEB_APP_ID; do
  append_dart_define_if_set "$key"
done

echo "Building ${title} web bundle (flavor=${FLAVOR}, base-href=${BASE_HREF})"
(
  cd "$CLIENT_DIR"
  "$FLUTTER_BIN" pub get
  "$FLUTTER_BIN" build web \
    --release \
    --no-wasm-dry-run \
    --pwa-strategy=none \
    -t "$entry" \
    --base-href "$BASE_HREF" \
    "${dart_defines[@]}"
)

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
cp -a "${CLIENT_DIR}/build/web/." "$OUTPUT_DIR/"

version_name="$(python3 - "${CLIENT_DIR}/pubspec.yaml" <<'PY'
import pathlib, re, sys
text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
match = re.search(r"(?m)^version:\s*([^\s#]+)", text)
if not match:
    raise SystemExit("Could not find pubspec version")
print(match.group(1))
PY
)"

commit_sha="$(git -C "$REPO_ROOT" rev-parse --short=12 HEAD)"
release_id="$(date -u +%Y%m%d%H%M%S)-${commit_sha}"
built_at_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

python3 - "$OUTPUT_DIR" "$BASE_HREF" "$version_name" "$release_id" "$built_at_utc" "$commit_sha" "$title" "$short_name" "$description" "$cache_scope" <<'PY'
import json, pathlib, sys
output_dir = pathlib.Path(sys.argv[1])
base_href, version_name, release_id, built_at_utc, commit_sha = sys.argv[2:7]
title, short_name, description, cache_scope = sys.argv[7:11]

index_path = output_dir / "index.html"
manifest_path = output_dir / "manifest.json"
release_manifest_path = output_dir / "release-manifest.json"
bootstrap_path = output_dir / "flutter_bootstrap.js"
service_worker_path = output_dir / "flutter_service_worker.js"

# Replace Flutter's default title/description in index.html with the
# flavor-specific values. The pubspec-generated index can carry either
# "Shamell Flutter" or "SyrChat" (depending on flavor-config ordering),
# so we rewrite the literal <title>…</title> element via regex too.
import re
index_html = index_path.read_text(encoding="utf-8")
index_html = re.sub(
    r"<title>[^<]*</title>",
    f"<title>{title}</title>",
    index_html,
    count=1,
)
# Legacy fallbacks in case the regex above missed a custom variant.
index_html = index_html.replace("Shamell Flutter", title)
index_html = index_html.replace(
    'content="A new Flutter project."',
    f'content="{description}"',
)

# Older Flutter-web service workers cache the bundle aggressively. The
# cleanup script below unregisters any stale SW + drops caches that
# share the same base scope so a fresh release lands on next page-load.
cache_cleanup_script = f"""  <script id="operator-flavor-cache-cleanup">
    (function () {{
      if ('serviceWorker' in navigator) {{
        navigator.serviceWorker.getRegistrations().then(function (registrations) {{
          registrations.forEach(function (registration) {{
            if ((registration.scope || '').indexOf('{cache_scope}') !== -1) {{
              registration.unregister();
            }}
          }});
        }}).catch(function () {{}});
      }}
      if ('caches' in window) {{
        caches.keys().then(function (keys) {{
          keys.forEach(function (key) {{
            if (key.indexOf('flutter-app-cache') !== -1 ||
                key.indexOf('flutter-temp-cache') !== -1) {{
              caches.delete(key);
            }}
          }});
        }}).catch(function () {{}});
      }}
    }})();
  </script>
"""
bootstrap_script = f'  <script src="flutter_bootstrap.js?v={release_id}" async=""></script>'
if 'id="operator-flavor-cache-cleanup"' not in index_html:
    index_html = index_html.replace(
        '  <script src="flutter_bootstrap.js" async=""></script>',
        cache_cleanup_script + bootstrap_script,
    )
    index_html = index_html.replace(
        '  <script src="flutter_bootstrap.js" async></script>',
        cache_cleanup_script + bootstrap_script,
    )
# Belt-and-braces: also fingerprint any remaining default bootstrap tags.
index_html = index_html.replace(
    '  <script src="flutter_bootstrap.js" async=""></script>',
    bootstrap_script,
)
index_html = index_html.replace(
    '  <script src="flutter_bootstrap.js" async></script>',
    bootstrap_script,
)
index_path.write_text(index_html, encoding="utf-8")

# Same cache-busting trick on the bootstrap JS itself so main.dart.js
# is re-fetched after a release rather than re-used from the SW cache.
if bootstrap_path.exists():
    bootstrap_js = bootstrap_path.read_text(encoding="utf-8")
    bootstrap_js = bootstrap_js.replace(
        '"mainJsPath":"main.dart.js"',
        f'"mainJsPath":"main.dart.js?v={release_id}"',
    )
    bootstrap_path.write_text(bootstrap_js, encoding="utf-8")

# Fingerprint the preload hint so it matches the cache-busted URL the
# bootstrap actually fetches. Without this, the browser would treat
# the preload as unrelated to the real request and download main.dart.js
# twice (the preload would also surface as a console warning).
index_html = index_path.read_text(encoding="utf-8")
index_html = index_html.replace(
    '<link rel="preload" href="main.dart.js" as="script" crossorigin>',
    f'<link rel="preload" href="main.dart.js?v={release_id}" as="script" crossorigin>',
)
index_path.write_text(index_html, encoding="utf-8")

# Kill-switch SW: any cached pre-release SW for this scope is replaced
# with one that unregisters itself on activate.
service_worker_path.write_text(
    f"""// Kill-switch for older Flutter web service workers under {cache_scope}.
// Release: {release_id}
self.addEventListener('install', function (event) {{
  self.skipWaiting();
  event.waitUntil(
    caches.keys().then(function (keys) {{
      return Promise.all(keys.map(function (key) {{
        return caches.delete(key);
      }}));
    }})
  );
}});

self.addEventListener('activate', function (event) {{
  event.waitUntil((async function () {{
    await self.registration.unregister();
    var clientsList = await self.clients.matchAll({{
      type: 'window',
      includeUncontrolled: true
    }});
    for (var i = 0; i < clientsList.length; i += 1) {{
      clientsList[i].navigate(clientsList[i].url);
    }}
  }})());
}});

self.addEventListener('fetch', function () {{}});
""",
    encoding="utf-8",
)

manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
manifest["name"] = title
manifest["short_name"] = short_name
manifest["description"] = description
manifest["start_url"] = base_href
manifest["scope"] = base_href
manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

release_manifest = {
    "title": title,
    "release_id": release_id,
    "version_name": version_name,
    "built_at_utc": built_at_utc,
    "commit_sha": commit_sha,
    "base_href": base_href,
    "entrypoint": "index.html",
}
release_manifest_path.write_text(
    json.dumps(release_manifest, indent=2) + "\n",
    encoding="utf-8",
)
PY

printf 'Built %s web bundle: %s\n' "$title" "$OUTPUT_DIR"
