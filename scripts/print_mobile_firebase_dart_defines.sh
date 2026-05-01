#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
android_app_dir="$repo_root/clients/shamell_flutter/android/app"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/print_mobile_firebase_dart_defines.sh

Reads local Android flavor configs from:
  clients/shamell_flutter/android/app/src/<flavor>/google-services.json

Outputs shell-safe Flutter --dart-define flags for the current local Firebase
setup. Requires valid non-placeholder config files for:
  user, ride, driver, operator
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

python3 - "$android_app_dir" <<'PY'
import json
import shlex
import sys
from pathlib import Path

android_app_dir = Path(sys.argv[1])

flavors = {
    "user": {
        "package_name": "online.shamell.app",
        "app_id_key": "SHAMELL_FIREBASE_ANDROID_APP_ID_SUPERAPP",
    },
    "ride": {
        "package_name": "online.shamell.ride",
        "app_id_key": "SHAMELL_FIREBASE_ANDROID_APP_ID_RIDE",
    },
    "driver": {
        "package_name": "online.shamell.driver",
        "app_id_key": "SHAMELL_FIREBASE_ANDROID_APP_ID_DRIVER",
    },
    "operator": {
        "package_name": "online.shamell.operator",
        "app_id_key": "SHAMELL_FIREBASE_ANDROID_APP_ID_OPERATOR",
    },
}


def fail(message: str) -> None:
    print(f"[FAIL] {message}", file=sys.stderr)
    raise SystemExit(1)


def load_config(path: Path) -> dict:
    if not path.is_file():
        fail(f"missing config: {path}")
    raw = path.read_text()
    if (
        "REPLACE_WITH_FIREBASE_API_KEY" in raw
        or "000000000000-placeholder" in raw
        or '"project_number": "000000000000"' in raw
        or "1:000000000000:android:" in raw
    ):
        fail(f"placeholder Firebase values detected in {path}")
    try:
        return json.loads(raw)
    except json.JSONDecodeError as exc:
        fail(f"invalid JSON in {path}: {exc}")


def extract_client(config: dict, package_name: str, source: Path) -> dict:
    for client in config.get("client", []):
        candidate = (
            client.get("client_info", {})
            .get("android_client_info", {})
            .get("package_name", "")
            .strip()
        )
        if candidate == package_name:
            return client
    fail(f"{source} does not contain package_name {package_name}")


configs = {}
shared_values = {
    "SHAMELL_FIREBASE_API_KEY": None,
    "SHAMELL_FIREBASE_MESSAGING_SENDER_ID": None,
    "SHAMELL_FIREBASE_PROJECT_ID": None,
    "SHAMELL_FIREBASE_STORAGE_BUCKET": None,
    "SHAMELL_FIREBASE_AUTH_DOMAIN": None,
}

for flavor, meta in flavors.items():
    path = android_app_dir / "src" / flavor / "google-services.json"
    config = load_config(path)
    client = extract_client(config, meta["package_name"], path)

    app_id = client.get("client_info", {}).get("mobilesdk_app_id", "").strip()
    api_keys = client.get("api_key", [])
    api_key = api_keys[0].get("current_key", "").strip() if api_keys else ""
    project_number = config.get("project_info", {}).get("project_number", "").strip()
    project_id = config.get("project_info", {}).get("project_id", "").strip()
    storage_bucket = config.get("project_info", {}).get("storage_bucket", "").strip()

    if not app_id:
        fail(f"missing mobilesdk_app_id in {path}")
    if not api_key:
        fail(f"missing api_key.current_key in {path}")
    if not project_number:
        fail(f"missing project_info.project_number in {path}")
    if not project_id:
        fail(f"missing project_info.project_id in {path}")
    if not storage_bucket:
        fail(f"missing project_info.storage_bucket in {path}")

    configs[meta["app_id_key"]] = app_id

    flavor_shared_values = {
        "SHAMELL_FIREBASE_API_KEY": api_key,
        "SHAMELL_FIREBASE_MESSAGING_SENDER_ID": project_number,
        "SHAMELL_FIREBASE_PROJECT_ID": project_id,
        "SHAMELL_FIREBASE_STORAGE_BUCKET": storage_bucket,
        "SHAMELL_FIREBASE_AUTH_DOMAIN": f"{project_id}.firebaseapp.com",
    }
    for key, value in flavor_shared_values.items():
        current = shared_values[key]
        if current is None:
            shared_values[key] = value
        elif current != value:
            fail(
                f"{key} is inconsistent across flavor configs; "
                f"current={current!r}, {flavor}={value!r}"
            )

defines = {**shared_values, **configs}
for key, value in defines.items():
    if value is None or not value:
        fail(f"missing derived value for {key}")
    flag = f"--dart-define={key}={value}"
    print(shlex.quote(flag))
PY
