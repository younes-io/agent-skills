#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT

fixture_root="$tmp_root/repo"
mkdir -p "$fixture_root"

rsync \
  --archive \
  --exclude '.git' \
  "$repo_root/" \
  "$fixture_root/"

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
marketplace_path = root / ".claude-plugin" / "marketplace.json"
plugin_path = root / "plugins" / "tla-workbenches" / ".claude-plugin" / "plugin.json"

with open(marketplace_path, "r", encoding="utf-8") as f:
    marketplace = json.load(f)
with open(plugin_path, "r", encoding="utf-8") as f:
    plugin = json.load(f)

with open(root / "VERSION", "r", encoding="utf-8") as f:
    expected = f.read().strip()

assert marketplace["metadata"]["version"] == expected
assert marketplace["plugins"][0]["version"] == expected
assert plugin["version"] == expected
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

REPO_ROOT="$fixture_root" "$fixture_root/scripts/sync_version.sh"
REPO_ROOT="$fixture_root" "$fixture_root/scripts/validate_claude_plugin.sh"

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
marketplace_path = root / ".claude-plugin" / "marketplace.json"
plugin_path = root / "plugins" / "tla-workbenches" / ".claude-plugin" / "plugin.json"

with open(marketplace_path, "r", encoding="utf-8") as f:
    marketplace = json.load(f)
with open(plugin_path, "r", encoding="utf-8") as f:
    plugin = json.load(f)

with open(root / "VERSION", "r", encoding="utf-8") as f:
    expected = f.read().strip()

assert marketplace["metadata"]["version"] == expected
assert marketplace["plugins"][0]["version"] == expected
assert plugin["version"] == expected
PY
