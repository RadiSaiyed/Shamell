#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v python3 >/dev/null 2>&1; then
  echo "[FAIL] python3 is required for Android manifest exported-surface checks" >&2
  exit 1
fi

manifest_path="${SHAMELL_ANDROID_MANIFEST_PATH:-}"
if [[ -z "$manifest_path" ]]; then
  if [[ -d "$ROOT/clients/shamell_flutter/build" ]]; then
    manifest_path="$(find "$ROOT/clients/shamell_flutter/build" -type f -name AndroidManifest.xml \
      | grep -E '/merged(_|/)?manifest(s)?/|/merged_manifests/' \
      | grep -E '/userRelease/' \
      | head -n 1 || true)"
  fi
fi

if [[ -z "$manifest_path" ]]; then
  if [[ -d "$ROOT/clients/shamell_flutter/android/app/build" ]]; then
    manifest_path="$(find "$ROOT/clients/shamell_flutter/android/app/build" -type f -name AndroidManifest.xml \
      | grep -E '/merged(_|/)?manifest(s)?/|/merged_manifests/' \
      | grep -E '/userRelease/' \
      | head -n 1 || true)"
  fi
fi

if [[ -z "$manifest_path" ]]; then
  manifest_path="$ROOT/clients/shamell_flutter/android/app/src/main/AndroidManifest.xml"
fi

if [[ ! -f "$manifest_path" ]]; then
  echo "[FAIL] Android manifest not found: $manifest_path" >&2
  exit 1
fi

default_allowlist="online.shamell.app.MainActivity,io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingReceiver,com.google.firebase.iid.FirebaseInstanceIdReceiver,androidx.work.impl.background.systemjob.SystemJobService"
extra_allowlist="${SHAMELL_ANDROID_ALLOWED_EXPORTED_COMPONENTS:-}"
allowlist_csv="$default_allowlist"
if [[ -n "$extra_allowlist" ]]; then
  allowlist_csv="${allowlist_csv},${extra_allowlist}"
fi

python3 - "$manifest_path" "$allowlist_csv" <<'PY'
import csv
import sys
import xml.etree.ElementTree as ET

manifest_path = sys.argv[1]
allowlist_csv = sys.argv[2]

ANDROID_NS = "{http://schemas.android.com/apk/res/android}"
TAGS = ("activity", "activity-alias", "service", "receiver", "provider")

allowlist = {
    item.strip() for item in next(csv.reader([allowlist_csv])) if item.strip()
}

tree = ET.parse(manifest_path)
root = tree.getroot()
package_name = (root.get("package") or "").strip()
if not package_name:
    package_name = "online.shamell.app"

application = root.find("application")
if application is None:
    raise SystemExit("[FAIL] manifest is missing <application>")

def to_fqcn(name: str) -> str:
    name = (name or "").strip()
    if not name:
        return ""
    if name.startswith("."):
        return f"{package_name}{name}"
    if "." not in name:
        return f"{package_name}.{name}"
    return name

exported_true = []
missing_exported_with_intent_filter = []

for element in application:
    tag = element.tag.split("}")[-1]
    if tag not in TAGS:
        continue
    name = to_fqcn(element.get(f"{ANDROID_NS}name", ""))
    exported = (element.get(f"{ANDROID_NS}exported") or "").strip().lower()
    has_intent_filter = any(
        child.tag.split("}")[-1] == "intent-filter" for child in list(element)
    )
    if exported == "true":
        exported_true.append((tag, name))
    if not exported and has_intent_filter and tag in {"activity", "activity-alias", "service", "receiver"}:
        missing_exported_with_intent_filter.append((tag, name))

if missing_exported_with_intent_filter:
    lines = ["[FAIL] manifest components with intent-filter must set android:exported explicitly:"]
    for tag, name in missing_exported_with_intent_filter:
        lines.append(f"  - {tag}: {name or '<missing-name>'}")
    raise SystemExit("\n".join(lines))

unexpected = [(tag, name) for (tag, name) in exported_true if name not in allowlist]
if unexpected:
    lines = [
        "[FAIL] unexpected exported Android components found",
        f"manifest: {manifest_path}",
        "allowed:",
    ]
    for allowed in sorted(allowlist):
        lines.append(f"  - {allowed}")
    lines.append("unexpected:")
    for tag, name in unexpected:
        lines.append(f"  - {tag}: {name or '<missing-name>'}")
    raise SystemExit("\n".join(lines))

required_main = "online.shamell.app.MainActivity"
if required_main not in {name for _, name in exported_true}:
    raise SystemExit(
        "[FAIL] release entrypoint must remain explicitly exported: "
        f"{required_main}"
    )

print(f"[OK]   Android exported-component surface is allowlisted ({manifest_path})")
PY
