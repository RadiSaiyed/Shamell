#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT/clients/shamell_flutter"
MARKER="$ROOT/.shamell-canonical"
BASE_URL="${BASE_URL:-http://localhost:8080}"
ANDROID_SERIAL="${ANDROID_SERIAL:-emulator-5554}"
JAVA_HOME="${JAVA_HOME:-/opt/homebrew/Cellar/openjdk@21/21.0.11/libexec/openjdk.jdk/Contents/Home}"
FLUTTER="${FLUTTER:-/Users/radi/flutter-sdk-wrapper/bin/flutter}"
ADB="${ADB:-/Users/radi/Library/Android/sdk/platform-tools/adb}"

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

[[ -f "$MARKER" ]] || fail "canonical marker missing: $MARKER"
grep -q 'Shamell final source workspace' "$MARKER" ||
  fail "canonical marker does not identify the final source workspace"
[[ -f "$APP_DIR/lib/main.dart" ]] || fail "Flutter app not found at $APP_DIR"
[[ -f "$APP_DIR/lib/src/main_shamell.dart" ]] ||
  fail "main_shamell.dart missing; this is not the WeChat-inspired final app"
grep -q "part 'src/main_shamell.dart';" "$APP_DIR/lib/main.dart" ||
  fail "main.dart is not wired to main_shamell.dart"
grep -q 'SHAMELL_DEBUG_SKIP_LOGIN' "$APP_DIR/lib/src/main_bootstrap.dart" ||
  fail "expected final debug skip-login flag not found"

export JAVA_HOME
export PATH="$JAVA_HOME/bin:$PATH"
export FLUTTER_SUPPRESS_ANALYTICS=true

printf 'Using canonical Shamell app: %s\n' "$ROOT"
printf 'Building for %s with BASE_URL=%s\n' "$ANDROID_SERIAL" "$BASE_URL"

cd "$APP_DIR"
"$FLUTTER" --no-version-check build apk \
  --debug \
  --flavor user \
  --dart-define=SHAMELL_DEBUG_SKIP_LOGIN=true \
  --dart-define=BASE_URL="$BASE_URL" \
  --no-pub

"$ADB" -s "$ANDROID_SERIAL" install -r build/app/outputs/flutter-apk/app-user-debug.apk
"$ADB" -s "$ANDROID_SERIAL" shell am force-stop online.shamell.app
"$ADB" -s "$ANDROID_SERIAL" shell am start -n online.shamell.app/.MainActivity

sleep 8
"$ADB" -s "$ANDROID_SERIAL" logcat -d -t 3500 |
  rg -i 'FATAL EXCEPTION|E/flutter|flutter.*exception|NoSuchMethodError|RenderFlex overflow|ANR in online.shamell|Application Not Responding' && {
    fail "startup log contains a fatal Flutter/Android error"
  } || true

printf 'Installed and started canonical Shamell app on %s.\n' "$ANDROID_SERIAL"
