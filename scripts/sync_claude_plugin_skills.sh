#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src_dir="$repo_root/skills/"
dest_dir="$repo_root/plugins/tla-workbenches/skills"

if ! command -v rsync >/dev/null 2>&1; then
  echo "rsync is required to sync Claude plugin skills" >&2
  exit 1
fi

mkdir -p "$dest_dir"

rsync \
  --archive \
  --delete \
  --exclude '.DS_Store' \
  "$src_dir" \
  "$dest_dir/"
