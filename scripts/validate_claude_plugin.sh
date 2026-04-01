#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
marketplace_json="$repo_root/.claude-plugin/marketplace.json"
plugin_root="$repo_root/plugins/tla-workbenches"
plugin_json="$plugin_root/.claude-plugin/plugin.json"
source_skills="$repo_root/skills"
generated_skills="$plugin_root/skills"

for required_path in "$marketplace_json" "$plugin_json" "$source_skills" "$generated_skills"; do
  if [[ ! -e "$required_path" ]]; then
    echo "Missing required path: $required_path" >&2
    exit 1
  fi
done

python3 - "$marketplace_json" "$plugin_json" <<'PY'
import json
import sys

marketplace_path, plugin_path = sys.argv[1:3]

with open(marketplace_path, "r", encoding="utf-8") as f:
    marketplace = json.load(f)

with open(plugin_path, "r", encoding="utf-8") as f:
    plugin = json.load(f)

expected_marketplace = {
    "name": "younes-agent-skills",
    "owner_name": "younes-io",
    "plugin_name": "tla-workbenches",
    "plugin_source": "./plugins/tla-workbenches",
    "plugin_version": "0.1.1",
    "skills": ["./skills/tla-check", "./skills/tla-proof"],
}

if marketplace.get("name") != expected_marketplace["name"]:
    raise SystemExit("Unexpected marketplace name")

if marketplace.get("owner", {}).get("name") != expected_marketplace["owner_name"]:
    raise SystemExit("Unexpected marketplace owner name")

plugins = marketplace.get("plugins")
if not isinstance(plugins, list) or len(plugins) != 1:
    raise SystemExit("Marketplace must contain exactly one plugin entry")

entry = plugins[0]
if entry.get("name") != expected_marketplace["plugin_name"]:
    raise SystemExit("Unexpected plugin name in marketplace")

if entry.get("source") != expected_marketplace["plugin_source"]:
    raise SystemExit("Unexpected plugin source path in marketplace")

if entry.get("version") != expected_marketplace["plugin_version"]:
    raise SystemExit("Unexpected plugin version in marketplace")

if plugin.get("name") != expected_marketplace["plugin_name"]:
    raise SystemExit("Unexpected plugin manifest name")

if plugin.get("author", {}).get("name") != expected_marketplace["owner_name"]:
    raise SystemExit("Unexpected plugin manifest author")

if plugin.get("version") != expected_marketplace["plugin_version"]:
    raise SystemExit("Unexpected plugin manifest version")

if plugin.get("skills") != expected_marketplace["skills"]:
    raise SystemExit("Plugin manifest must register tla-check and tla-proof")
PY

if find "$generated_skills" -type l | grep -q .; then
  echo "Generated Claude plugin skills must not contain symlinks" >&2
  exit 1
fi

diff -ru --exclude '.DS_Store' "$source_skills" "$generated_skills"
