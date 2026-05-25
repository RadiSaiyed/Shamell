#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! grep -qxF ".secrets-local/" "$repo_root/.gitignore"; then
  echo "Root .gitignore must ignore .secrets-local/ to avoid accidental local secret commits." >&2
  exit 1
fi

if git -C "$repo_root" ls-files | grep -q '^\.secrets-local/'; then
  echo ".secrets-local/ must remain untracked; tracked local secret artifacts were found." >&2
  exit 1
fi
