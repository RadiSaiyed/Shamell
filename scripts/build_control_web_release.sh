#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLIENT_DIR="${REPO_ROOT}/clients/shamell_flutter"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
OUTPUT_DIR="${OUTPUT_DIR:-${REPO_ROOT}/.artifacts/control-web-release}"
BASE_HREF="${BASE_HREF:-/control/}"

usage() {
  cat <<'EOF'
Usage: scripts/build_control_web_release.sh [--output-dir DIR] [--base-href /control/]

Build the Shamell Control Flutter web bundle from `lib/main_operator.dart`.

Output:
  <output-dir>/
    index.html
    manifest.json
    release-manifest.json
    assets...
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --base-href)
      BASE_HREF="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

require_cmd "$FLUTTER_BIN"
require_cmd python3
require_cmd git

case "$BASE_HREF" in
  /*/)
    ;;
  *)
    echo "--base-href must start and end with '/': $BASE_HREF" >&2
    exit 1
    ;;
esac

append_dart_define_if_set() {
  local key="$1"
  local value="${!key:-}"
  if [[ -n "$value" ]]; then
    dart_defines+=("--dart-define=${key}=${value}")
  fi
}

dart_defines=(
  "--dart-define=APP_MODE=operator"
  "--dart-define=SHAMELL_APP_SURFACE=operator"
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

echo "Building Shamell Control web bundle with base href ${BASE_HREF}"
(
  cd "$CLIENT_DIR"
  "$FLUTTER_BIN" pub get
  "$FLUTTER_BIN" build web \
    --release \
    --no-wasm-dry-run \
    --pwa-strategy=none \
    -t lib/main_operator.dart \
    --base-href "$BASE_HREF" \
    "${dart_defines[@]}"
)

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
cp -a "${CLIENT_DIR}/build/web/." "$OUTPUT_DIR/"

version_name="$(python3 - "${CLIENT_DIR}/pubspec.yaml" <<'PY'
import pathlib
import re
import sys

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

python3 - "$OUTPUT_DIR" "$BASE_HREF" "$version_name" "$release_id" "$built_at_utc" "$commit_sha" <<'PY'
import json
import pathlib
import sys

output_dir = pathlib.Path(sys.argv[1])
base_href = sys.argv[2]
version_name = sys.argv[3]
release_id = sys.argv[4]
built_at_utc = sys.argv[5]
commit_sha = sys.argv[6]

index_path = output_dir / "index.html"
manifest_path = output_dir / "manifest.json"
release_manifest_path = output_dir / "release-manifest.json"
bootstrap_path = output_dir / "flutter_bootstrap.js"
service_worker_path = output_dir / "flutter_service_worker.js"

index_html = index_path.read_text(encoding="utf-8")
index_html = index_html.replace("Shamell Flutter", "Shamell Control")
index_html = index_html.replace(
    'content="A new Flutter project."',
    'content="Shamell Control web console for operations and admin workflows."',
)
cache_cleanup_script = """  <script id="control-cache-cleanup">
    (function () {
      if ('serviceWorker' in navigator) {
        navigator.serviceWorker.getRegistrations().then(function (registrations) {
          registrations.forEach(function (registration) {
            if ((registration.scope || '').indexOf('/control/') !== -1) {
              registration.unregister();
            }
          });
        }).catch(function () {});
      }
      if ('caches' in window) {
        caches.keys().then(function (keys) {
          keys.forEach(function (key) {
            if (key.indexOf('flutter-app-cache') !== -1 ||
                key.indexOf('flutter-temp-cache') !== -1 ||
                key.indexOf('control') !== -1) {
              caches.delete(key);
            }
          });
        }).catch(function () {});
      }
    })();
  </script>
"""
bootstrap_script = f'  <script src="flutter_bootstrap.js?v={release_id}" async=""></script>'
if 'id="control-cache-cleanup"' not in index_html:
    index_html = index_html.replace(
        '  <script src="flutter_bootstrap.js" async=""></script>',
        cache_cleanup_script + bootstrap_script,
    )
    index_html = index_html.replace(
        '  <script src="flutter_bootstrap.js" async></script>',
        cache_cleanup_script + bootstrap_script,
    )
index_html = index_html.replace(
    '  <script src="flutter_bootstrap.js" async=""></script>',
    bootstrap_script,
)
index_html = index_html.replace(
    '  <script src="flutter_bootstrap.js" async></script>',
    bootstrap_script,
)
index_path.write_text(index_html, encoding="utf-8")

if bootstrap_path.exists():
    bootstrap_js = bootstrap_path.read_text(encoding="utf-8")
    bootstrap_js = bootstrap_js.replace(
        '"mainJsPath":"main.dart.js"',
        f'"mainJsPath":"main.dart.js?v={release_id}"',
    )
    bootstrap_path.write_text(bootstrap_js, encoding="utf-8")

service_worker_path.write_text(
    f"""// Kill-switch for older Flutter web service workers under /control/.
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
manifest["name"] = "Shamell Control"
manifest["short_name"] = "Control"
manifest["description"] = "Shamell Control web console for operations and admin workflows."
manifest["start_url"] = base_href
manifest["scope"] = base_href
manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

release_manifest = {
    "title": "Shamell Control",
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

printf 'Built Shamell Control web bundle: %s\n' "$OUTPUT_DIR"
