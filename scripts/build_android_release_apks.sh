#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLIENT_DIR="${REPO_ROOT}/clients/shamell_flutter"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
OUTPUT_DIR="${OUTPUT_DIR:-${REPO_ROOT}/.artifacts/android-apk-release}"
SPLIT_DEBUG_INFO_DIR="${SHAMELL_ANDROID_APK_SPLIT_DEBUG_INFO_DIR:-${REPO_ROOT}/.artifacts/android-apk-split-debug-info}"
TRUSTED_TLS_CERTIFICATES_DER_BASE64="${TRUSTED_TLS_CERTIFICATES_DER_BASE64:-}"
REQUIRE_PRODUCTION_SIGNING="${REQUIRE_PRODUCTION_SIGNING:-true}"
SHAMELL_ALLOW_DEBUG_RELEASE_SIGNING="${SHAMELL_ALLOW_DEBUG_RELEASE_SIGNING:-false}"
KEEP_OUTPUT="${KEEP_OUTPUT:-false}"
REQUESTED_FLAVORS_RAW=""

usage() {
  cat <<'EOF'
Usage: scripts/build_android_release_apks.sh [--output-dir DIR] [--split-debug-info-dir DIR] [--flavors user,ride,...]

Build a signed universal release APK bundle for:
  - Shamell
  - Shamell Ride
  - Shamell Driver
  - Shamell Control

Environment:
  REQUIRE_PRODUCTION_SIGNING=true|false
  SHAMELL_ALLOW_DEBUG_RELEASE_SIGNING=true|false
  TRUSTED_TLS_CERTIFICATES_DER_BASE64=...
  SHAMELL_RELEASE_STORE_FILE / SHAMELL_RELEASE_STORE_BASE64 / ...
  SHAMELL_PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER=...

Output:
  <output-dir>/
    index.html
    release-manifest.json
    shamell-*.apk

Options:
  --flavors LIST   Comma-separated subset of: user, ride, driver, operator
EOF
}

metadata_json=""
release_dart_defines_file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --split-debug-info-dir)
      SPLIT_DEBUG_INFO_DIR="$2"
      shift 2
      ;;
    --flavors)
      REQUESTED_FLAVORS_RAW="$2"
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

resolve_apksigner() {
  if command -v apksigner >/dev/null 2>&1; then
    command -v apksigner
    return 0
  fi
  local sdk_root="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-${HOME:-}/Library/Android/sdk}}"
  if [[ -d "$sdk_root/build-tools" ]]; then
    python3 - "$sdk_root" <<'PY'
import pathlib
import sys

sdk_root = pathlib.Path(sys.argv[1])
candidates = sorted(sdk_root.glob('build-tools/*/apksigner'))
if candidates:
    print(candidates[-1])
PY
  fi
}

verify_apk_signature() {
  local apk_path="$1"
  local apksigner_path=""
  apksigner_path="$(resolve_apksigner)"
  if [[ -n "$apksigner_path" ]]; then
    "$apksigner_path" verify --print-certs "$apk_path" >/dev/null
    return
  fi
  if command -v jarsigner >/dev/null 2>&1; then
    jarsigner -verify -verbose -certs "$apk_path" >/dev/null
    return
  fi
  echo "WARNING: neither apksigner nor jarsigner found; skipping APK signature verification for $apk_path" >&2
}

sha256_file() {
  local path="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
  else
    shasum -a 256 "$path" | awk '{print $1}'
  fi
}

lowercase() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

resolve_absolute_path() {
  python3 - "$1" <<'PY'
import pathlib
import sys

print(pathlib.Path(sys.argv[1]).expanduser().resolve())
PY
}

resolve_pubspec_version() {
  python3 - "${CLIENT_DIR}/pubspec.yaml" <<'PY'
import pathlib
import re
import sys

text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
match = re.search(r"(?m)^version:\s*([^\s#]+)", text)
if not match:
    raise SystemExit("Could not find pubspec version")
print(match.group(1))
PY
}

render_bundle_metadata() {
  local manifest_path="$1"
  local html_path="$2"
  local metadata_path="$3"
  python3 - "$manifest_path" "$html_path" "$metadata_path" <<'PY'
import datetime as dt
import html
import json
import pathlib
import sys

manifest_path = pathlib.Path(sys.argv[1])
html_path = pathlib.Path(sys.argv[2])
metadata_path = pathlib.Path(sys.argv[3])
payload = json.loads(metadata_path.read_text(encoding="utf-8"))

manifest_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

apps = payload["apps"]
version = payload["version_name"]
release_id = payload["release_id"]
built_at = payload["built_at_utc"]

cards = []
for app in apps:
    cards.append(
        f"""
        <article class="card">
          <h2>{html.escape(app['title'])}</h2>
          <p class="package">{html.escape(app['package_name'])}</p>
          <p>{html.escape(app['summary'])}</p>
          <a class="button" href="{html.escape(app['file_name'])}">Download APK</a>
          <dl>
            <div><dt>Version</dt><dd>{html.escape(version)}</dd></div>
            <div><dt>Size</dt><dd>{html.escape(app['size_mb'])} MB</dd></div>
            <div><dt>SHA-256</dt><dd><code>{html.escape(app['sha256'])}</code></dd></div>
          </dl>
        </article>
        """
    )

html_path.write_text(
    f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Shamell Android APK Downloads</title>
  <style>
    :root {{
      color-scheme: light;
      --bg: #f3efe6;
      --ink: #1d1d1b;
      --muted: #635f59;
      --panel: #fffdf8;
      --line: #d7d0c5;
      --accent: #c34a36;
      --accent-ink: #fff8f0;
    }}
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0;
      font-family: "Iowan Old Style", "Palatino Linotype", serif;
      background:
        radial-gradient(circle at top left, rgba(195, 74, 54, 0.10), transparent 30rem),
        linear-gradient(180deg, #f7f2e9 0%, var(--bg) 100%);
      color: var(--ink);
    }}
    main {{
      max-width: 72rem;
      margin: 0 auto;
      padding: 3rem 1.25rem 4rem;
    }}
    h1 {{
      margin: 0;
      font-size: clamp(2.2rem, 5vw, 4rem);
      line-height: 0.95;
      letter-spacing: -0.03em;
    }}
    .lede {{
      margin: 1rem 0 2rem;
      max-width: 42rem;
      color: var(--muted);
      font-size: 1.1rem;
    }}
    .meta {{
      display: flex;
      flex-wrap: wrap;
      gap: 0.75rem 1.5rem;
      margin-bottom: 2rem;
      color: var(--muted);
      font-size: 0.95rem;
    }}
    .steps, .cards {{
      display: grid;
      gap: 1rem;
    }}
    .steps {{
      grid-template-columns: repeat(auto-fit, minmax(14rem, 1fr));
      margin-bottom: 2rem;
    }}
    .step, .card {{
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 1.25rem;
      padding: 1.1rem 1rem 1rem;
      box-shadow: 0 0.75rem 2rem rgba(29, 29, 27, 0.06);
    }}
    .step strong {{
      display: block;
      margin-bottom: 0.35rem;
      font-size: 1rem;
    }}
    .cards {{
      grid-template-columns: repeat(auto-fit, minmax(16rem, 1fr));
    }}
    .card h2 {{
      margin: 0 0 0.35rem;
      font-size: 1.35rem;
    }}
    .package {{
      margin: 0 0 0.85rem;
      color: var(--muted);
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      font-size: 0.9rem;
    }}
    .button {{
      display: inline-block;
      margin: 0.25rem 0 1rem;
      padding: 0.7rem 0.95rem;
      border-radius: 999px;
      background: var(--accent);
      color: var(--accent-ink);
      text-decoration: none;
      font-weight: 700;
    }}
    dl {{
      margin: 0;
      display: grid;
      gap: 0.45rem;
    }}
    dl div {{
      display: grid;
      gap: 0.15rem;
    }}
    dt {{
      color: var(--muted);
      font-size: 0.8rem;
      text-transform: uppercase;
      letter-spacing: 0.08em;
    }}
    dd {{
      margin: 0;
      word-break: break-word;
    }}
    code {{
      font-size: 0.84rem;
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    }}
    .footer {{
      margin-top: 2rem;
      color: var(--muted);
      font-size: 0.95rem;
    }}
  </style>
</head>
<body>
  <main>
    <h1>Shamell Android APK Downloads</h1>
    <p class="lede">
      Direct signed APK installs for production devices. This is the release path when
      Play Store distribution is not used.
    </p>
    <div class="meta">
      <span>Release: <strong>{html.escape(release_id)}</strong></span>
      <span>Version: <strong>{html.escape(version)}</strong></span>
      <span>Built UTC: <strong>{html.escape(built_at)}</strong></span>
      <span><a href="release-manifest.json">Release manifest JSON</a></span>
    </div>
    <section class="steps" aria-label="Install steps">
      <div class="step">
        <strong>1. Download</strong>
        Open one of the APK links below from the Android device that should install it.
      </div>
      <div class="step">
        <strong>2. Allow APK installs</strong>
        If Android blocks installation, enable <em>Install unknown apps</em> for the
        browser or file manager that opened the APK.
      </div>
      <div class="step">
        <strong>3. Verify package</strong>
        Confirm the app name and SHA-256 hash before installation when distributing to staff.
      </div>
      <div class="step">
        <strong>4. Install</strong>
        Re-open the downloaded APK from Downloads or the browser notification tray and proceed.
      </div>
    </section>
    <section class="cards" aria-label="APK downloads">
      {''.join(cards)}
    </section>
    <p class="footer">
      These APKs are signed production artifacts intended for direct installation.
      Keep old APK links private when rotating releases.
    </p>
  </main>
</body>
</html>
""",
        encoding="utf-8",
    )
PY
}

require_cmd "$FLUTTER_BIN"
require_cmd python3

OUTPUT_DIR="$(resolve_absolute_path "$OUTPUT_DIR")"
SPLIT_DEBUG_INFO_DIR="$(resolve_absolute_path "$SPLIT_DEBUG_INFO_DIR")"

if [[ -z "$TRUSTED_TLS_CERTIFICATES_DER_BASE64" ]]; then
  echo "Missing TRUSTED_TLS_CERTIFICATES_DER_BASE64 for release APK build." >&2
  exit 1
fi

signing_env_out="$(mktemp "${TMPDIR:-/tmp}/shamell-android-signing-env.XXXXXX")"
release_dart_defines_file="$(mktemp "${TMPDIR:-/tmp}/shamell-android-dart-defines.XXXXXX")"
trap 'rm -f "${metadata_json:-}" "${signing_env_out:-}" "${release_dart_defines_file:-}"' EXIT
SHAMELL_ANDROID_SIGNING_ENV_OUT="$signing_env_out" \
  bash "${REPO_ROOT}/scripts/check_android_release_signing_env.sh"
# Reuse the validated signing fingerprint (and decoded keystore path when the
# source came from base64) in the later Gradle invocations of this same shell.
set -a
# shellcheck disable=SC1090  # signing_env_out is generated at runtime by check_android_release_signing_env.sh
source "$signing_env_out"
set +a
printf 'TRUSTED_TLS_CERTIFICATES_DER_BASE64=%s\n' \
  "$TRUSTED_TLS_CERTIFICATES_DER_BASE64" > "$release_dart_defines_file"
export SHAMELL_EXTRA_DART_DEFINES
SHAMELL_EXTRA_DART_DEFINES="$(cat "$release_dart_defines_file")"
bash "${REPO_ROOT}/scripts/check_mobile_firebase_flavors.sh"

mkdir -p "$OUTPUT_DIR" "$SPLIT_DEBUG_INFO_DIR"
if [[ "$(lowercase "$KEEP_OUTPUT")" != "true" ]]; then
  find "$OUTPUT_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
fi

pushd "$CLIENT_DIR" >/dev/null
"$FLUTTER_BIN" pub get
popd >/dev/null

version_name="$(resolve_pubspec_version)"
release_stamp="$(date -u +"%Y%m%dT%H%M%SZ")"
release_id="android-apk-${version_name//[^0-9A-Za-z._-]/-}-${release_stamp}"

all_flavors=(user ride driver operator)
flavors=()
if [[ -z "${REQUESTED_FLAVORS_RAW// }" ]]; then
  flavors=("${all_flavors[@]}")
else
  normalized_requested="${REQUESTED_FLAVORS_RAW//,/ }"
  for flavor in $normalized_requested; do
    case "$flavor" in
      user|ride|driver|operator)
        case " ${flavors[*]-} " in
          *" $flavor "*) ;;
          *)
            flavors+=("$flavor")
            ;;
        esac
        ;;
      *)
        echo "Unknown flavor in --flavors: $flavor" >&2
        usage >&2
        exit 1
        ;;
    esac
  done
  if [[ "${#flavors[@]}" -eq 0 ]]; then
    echo "--flavors did not resolve to any supported Android app flavor." >&2
    exit 1
  fi
fi

target_for_flavor() {
  case "$1" in
    user) printf '%s\n' "lib/main.dart" ;;
    ride) printf '%s\n' "lib/main_ride.dart" ;;
    driver) printf '%s\n' "lib/main_driver.dart" ;;
    operator) printf '%s\n' "lib/main_operator.dart" ;;
    *) return 1 ;;
  esac
}

title_for_flavor() {
  case "$1" in
    user) printf '%s\n' "Shamell" ;;
    ride) printf '%s\n' "Shamell Ride" ;;
    driver) printf '%s\n' "Shamell Driver" ;;
    operator) printf '%s\n' "Shamell Control" ;;
    *) return 1 ;;
  esac
}

summary_for_flavor() {
  case "$1" in
    user) printf '%s\n' "Superapp shell for the main Shamell client." ;;
    ride) printf '%s\n' "Rider app for booking and tracking rides." ;;
    driver) printf '%s\n' "Driver app for dispatch, navigation, and trip execution." ;;
    operator) printf '%s\n' "Operations console for live ride supervision." ;;
    *) return 1 ;;
  esac
}

package_for_flavor() {
  case "$1" in
    user) printf '%s\n' "online.shamell.app" ;;
    ride) printf '%s\n' "online.shamell.ride" ;;
    driver) printf '%s\n' "online.shamell.driver" ;;
    operator) printf '%s\n' "online.shamell.operator" ;;
    *) return 1 ;;
  esac
}

metadata_json="$(mktemp "${TMPDIR:-/tmp}/shamell-android-apk-metadata.XXXXXX.json")"

python3 - "$metadata_json" "$version_name" "$release_id" "$release_stamp" <<'PY'
import json
import sys
from pathlib import Path

Path(sys.argv[1]).write_text(
    json.dumps(
        {
            "version_name": sys.argv[2],
            "release_id": sys.argv[3],
            "built_at_utc": sys.argv[4],
            "apps": [],
        }
    ),
    encoding="utf-8",
)
PY

for flavor in "${flavors[@]}"; do
  target="$(target_for_flavor "$flavor")"
  title="$(title_for_flavor "$flavor")"
  summary="$(summary_for_flavor "$flavor")"
  package_name="$(package_for_flavor "$flavor")"
  split_dir="${SPLIT_DEBUG_INFO_DIR}/${flavor}"
  mkdir -p "$split_dir"
  build_args=(
    "$FLUTTER_BIN" build apk --release
    --flavor "$flavor"
    -t "$target"
    --no-pub
    --obfuscate
    "--split-debug-info=${split_dir}"
    "--dart-define-from-file=${release_dart_defines_file}"
  )
  printf '==> %s\n' "Building ${title} (${flavor})"
  (
    cd "$CLIENT_DIR"
    FLUTTER_BUILD_ARGS="${build_args[*]}" \
      bash "${REPO_ROOT}/scripts/check_mobile_release_security_env.sh"
    "${build_args[@]}"
  )

  source_apk="${CLIENT_DIR}/build/app/outputs/flutter-apk/app-${flavor}-release.apk"
  if [[ ! -f "$source_apk" ]]; then
    echo "Built APK missing for flavor ${flavor}: ${source_apk}" >&2
    exit 1
  fi

  target_apk="${OUTPUT_DIR}/shamell-${flavor}-${version_name}.apk"
  cp "$source_apk" "$target_apk"
  chmod 0644 "$target_apk"
  verify_apk_signature "$target_apk"

  sha256="$(sha256_file "$target_apk")"
  size_bytes="$(wc -c < "$target_apk" | tr -d ' ')"
  size_mb="$(python3 - "$size_bytes" <<'PY'
import sys
print(f"{int(sys.argv[1]) / (1024 * 1024):.2f}")
PY
)"

  python3 - "$metadata_json" \
    "$title" \
    "$package_name" \
    "$summary" \
    "$(basename "$target_apk")" \
    "$sha256" \
    "$size_bytes" \
    "$size_mb" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload = json.loads(path.read_text(encoding="utf-8"))
payload["apps"].append(
    {
        "title": sys.argv[2],
        "package_name": sys.argv[3],
        "summary": sys.argv[4],
        "file_name": sys.argv[5],
        "sha256": sys.argv[6],
        "size_bytes": int(sys.argv[7]),
        "size_mb": sys.argv[8],
    }
)
path.write_text(json.dumps(payload), encoding="utf-8")
PY
done

render_bundle_metadata \
  "${OUTPUT_DIR}/release-manifest.json" \
  "${OUTPUT_DIR}/index.html" \
  "$metadata_json"

printf 'Android APK bundle ready: %s\n' "$OUTPUT_DIR"
