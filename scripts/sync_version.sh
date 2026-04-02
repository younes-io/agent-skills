#!/usr/bin/env bash
set -euo pipefail

repo_root="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
version="$("$repo_root/scripts/read_version.sh")"
marketplace_json="$repo_root/.claude-plugin/marketplace.json"
plugin_json="$repo_root/plugins/tla-workbenches/.claude-plugin/plugin.json"

python3 - "$marketplace_json" "$plugin_json" "$version" <<'PY'
import json
import sys

marketplace_path, plugin_path, version = sys.argv[1:4]

with open(marketplace_path, "r", encoding="utf-8") as f:
    marketplace = json.load(f)

with open(plugin_path, "r", encoding="utf-8") as f:
    plugin = json.load(f)

metadata = marketplace.setdefault("metadata", {})
metadata["version"] = version

plugins = marketplace.get("plugins")
if not isinstance(plugins, list) or len(plugins) != 1:
    raise SystemExit("Marketplace must contain exactly one plugin entry")

plugins[0]["version"] = version
plugin["version"] = version

for path, payload in ((marketplace_path, marketplace), (plugin_path, plugin)):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2)
        f.write("\n")
PY
