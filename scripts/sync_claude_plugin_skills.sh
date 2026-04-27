#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src_dir="$repo_root/skills"
dest_dir="$repo_root/plugins/tla-workbenches/skills"

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required to sync plugin skills" >&2
  exit 1
fi

python3 - "$src_dir" "$dest_dir" <<'PY'
import shutil
import sys
from pathlib import Path

src_dir = Path(sys.argv[1])
dest_dir = Path(sys.argv[2])

if not src_dir.is_dir():
    raise SystemExit(f"Missing source skills directory: {src_dir}")

if dest_dir.exists():
    shutil.rmtree(dest_dir)

def ignore_ds_store(_directory, names):
    return {name for name in names if name == ".DS_Store"}

shutil.copytree(src_dir, dest_dir, ignore=ignore_ds_store)

for path in dest_dir.rglob("*"):
    if path.is_dir():
        path.chmod(0o755)
    elif path.is_file():
        path.chmod(0o755 if path.suffix == ".sh" else 0o644)
PY
