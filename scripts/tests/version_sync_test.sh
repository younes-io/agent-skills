#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp_parent="$repo_root/.tmp-version-sync-test"
mkdir -p "$tmp_parent"
tmp_root="$(mktemp -d "$tmp_parent/run.XXXXXX")"
trap 'rm -rf "$tmp_root"; rmdir "$tmp_parent" 2>/dev/null || true' EXIT

fixture_root="$tmp_root/repo"
mkdir -p "$fixture_root"

python3 - "$repo_root" "$fixture_root" <<'PY'
import shutil
import sys
from pathlib import Path

repo_root = Path(sys.argv[1])
fixture_root = Path(sys.argv[2])

def ignore_fixture_noise(_directory, names):
    return {name for name in names if name in {".git", ".DS_Store", ".tmp-version-sync-test", ".tmp-tlaps-check-test"}}

shutil.copytree(repo_root, fixture_root, dirs_exist_ok=True, ignore=ignore_fixture_noise)
PY

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  if [[ "$expected" != "$actual" ]]; then
    echo "$message: expected '$expected', got '$actual'" >&2
    exit 1
  fi
}

initial_version="$(
  REPO_ROOT="$fixture_root" \
  "$fixture_root/scripts/read_version.sh"
)"

python3 - "$fixture_root" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
claude_marketplace_path = root / ".claude-plugin" / "marketplace.json"
claude_plugin_path = root / "plugins" / "tla-workbenches" / ".claude-plugin" / "plugin.json"
codex_plugin_path = root / "plugins" / "tla-workbenches" / ".codex-plugin" / "plugin.json"

with open(claude_marketplace_path, "r", encoding="utf-8") as f:
    claude_marketplace = json.load(f)
with open(claude_plugin_path, "r", encoding="utf-8") as f:
    claude_plugin = json.load(f)
with open(codex_plugin_path, "r", encoding="utf-8") as f:
    codex_plugin = json.load(f)

with open(root / "VERSION", "r", encoding="utf-8") as f:
    expected = f.read().strip()

assert claude_marketplace["metadata"]["version"] == expected
assert claude_marketplace["plugins"][0]["version"] == expected
assert claude_plugin["version"] == expected
assert codex_plugin["version"] == expected
PY

next_version="$(
  python3 - "$initial_version" <<'PY'
import sys

major, minor, patch = map(int, sys.argv[1].split("."))
print(f"{major}.{minor}.{patch + 1}")
PY
)"

printf '%s\n' "$next_version" > "$fixture_root/VERSION"

if REPO_ROOT="$fixture_root" "$fixture_root/scripts/validate_claude_plugin.sh" >/dev/null 2>&1; then
  echo "validate_claude_plugin.sh should fail when VERSION and manifests diverge" >&2
  exit 1
fi

if REPO_ROOT="$fixture_root" "$fixture_root/scripts/validate_codex_plugin.sh" >/dev/null 2>&1; then
  echo "validate_codex_plugin.sh should fail when VERSION and manifests diverge" >&2
  exit 1
fi

REPO_ROOT="$fixture_root" "$fixture_root/scripts/sync_version.sh"
REPO_ROOT="$fixture_root" "$fixture_root/scripts/validate_claude_plugin.sh"
REPO_ROOT="$fixture_root" "$fixture_root/scripts/validate_codex_plugin.sh"

synced_version="$(
  REPO_ROOT="$fixture_root" \
  "$fixture_root/scripts/read_version.sh"
)"
assert_eq "$next_version" "$synced_version" "synced VERSION"

python3 - "$fixture_root" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
claude_marketplace_path = root / ".claude-plugin" / "marketplace.json"
claude_plugin_path = root / "plugins" / "tla-workbenches" / ".claude-plugin" / "plugin.json"
codex_plugin_path = root / "plugins" / "tla-workbenches" / ".codex-plugin" / "plugin.json"

with open(claude_marketplace_path, "r", encoding="utf-8") as f:
    claude_marketplace = json.load(f)
with open(claude_plugin_path, "r", encoding="utf-8") as f:
    claude_plugin = json.load(f)
with open(codex_plugin_path, "r", encoding="utf-8") as f:
    codex_plugin = json.load(f)

with open(root / "VERSION", "r", encoding="utf-8") as f:
    expected = f.read().strip()

assert claude_marketplace["metadata"]["version"] == expected
assert claude_marketplace["plugins"][0]["version"] == expected
assert claude_plugin["version"] == expected
assert codex_plugin["version"] == expected
PY
