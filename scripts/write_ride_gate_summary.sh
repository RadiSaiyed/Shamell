#!/usr/bin/env bash
set -euo pipefail

ARTIFACT_DIR="${1:-.artifacts/ride-e2e}"

human_size() {
  local bytes="$1"
  awk -v value="$bytes" '
    function human(v) {
      split("B KiB MiB GiB TiB", units, " ")
      idx = 1
      while (v >= 1024 && idx < 5) {
        v /= 1024
        idx++
      }
      if (idx == 1) {
        return sprintf("%d %s", v, units[idx])
      }
      return sprintf("%.1f %s", v, units[idx])
    }
    BEGIN { print human(value) }
  '
}

latest_run=""
source_path=""
if [[ -f "${ARTIFACT_DIR}/latest_run.txt" ]]; then
  latest_run="$(tr -d '\r' < "${ARTIFACT_DIR}/latest_run.txt")"
fi
if [[ -f "${ARTIFACT_DIR}/source_path.txt" ]]; then
  source_path="$(tr -d '\r' < "${ARTIFACT_DIR}/source_path.txt")"
fi

run_dir=""
if [[ -n "$latest_run" && -d "${ARTIFACT_DIR}/${latest_run}" ]]; then
  run_dir="${ARTIFACT_DIR}/${latest_run}"
fi

console_log=""
if [[ -f "${ARTIFACT_DIR}/ride-gate-console.log" ]]; then
  console_log="${ARTIFACT_DIR}/ride-gate-console.log"
elif [[ -n "$run_dir" && -f "${run_dir}/ride-gate-console.log" ]]; then
  console_log="${run_dir}/ride-gate-console.log"
fi

printf '## Ride Gate Summary\n\n'

if [[ -z "$run_dir" ]]; then
  printf 'No captured ride gate run directory was found in `%s`.\n' "$ARTIFACT_DIR"
  if [[ -n "$console_log" ]]; then
    printf '\n### Console tail\n\n```text\n'
    tail -n 40 "$console_log"
    printf '\n```\n'
  fi
  exit 0
fi

printf '| Field | Value |\n'
printf '| --- | --- |\n'
printf '| Artifact root | `%s` |\n' "$ARTIFACT_DIR"
printf '| Latest run | `%s` |\n' "$latest_run"
if [[ -n "$source_path" ]]; then
  printf '| Source path | `%s` |\n' "$source_path"
fi
printf '\n'

printf '### Captured files\n\n'
printf '| File | Size |\n'
printf '| --- | ---: |\n'
while IFS= read -r file_path; do
  rel_path="${file_path#${ARTIFACT_DIR}/}"
  file_size="$(wc -c < "$file_path" | tr -d ' ')"
  printf '| `%s` | %s |\n' "$rel_path" "$(human_size "$file_size")"
done < <(find "$run_dir" -maxdepth 1 -type f | sort)
if [[ -n "$console_log" ]]; then
  file_size="$(wc -c < "$console_log" | tr -d ' ')"
  printf '| `%s` | %s |\n' "${console_log#${ARTIFACT_DIR}/}" "$(human_size "$file_size")"
fi
printf '\n'

if [[ -n "$console_log" ]]; then
  printf '### Key lines\n\n```text\n'
  grep -E '^(\[ride-e2e\]|\[ride-e2e\]\[error\]|ride-report:|health (bff|payments|chat): ok)' "$console_log" | tail -n 80 || true
  printf '\n```\n'
fi
