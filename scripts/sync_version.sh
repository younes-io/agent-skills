#!/usr/bin/env bash
set -euo pipefail

repo_root="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
version="$("$repo_root/scripts/read_version.sh")"
claude_marketplace_json="$repo_root/.claude-plugin/marketplace.json"
claude_plugin_json="$repo_root/plugins/tla-workbenches/.claude-plugin/plugin.json"
codex_plugin_json="$repo_root/plugins/tla-workbenches/.codex-plugin/plugin.json"

python3 - "$claude_marketplace_json" "$claude_plugin_json" "$codex_plugin_json" "$version" <<'PY'
import json
import sys

claude_marketplace_path, claude_plugin_path, codex_plugin_path, version = sys.argv[1:5]

with open(claude_marketplace_path, "r", encoding="utf-8") as f:
    claude_marketplace = json.load(f)

with open(claude_plugin_path, "r", encoding="utf-8") as f:
    claude_plugin = json.load(f)

with open(codex_plugin_path, "r", encoding="utf-8") as f:
    codex_plugin = json.load(f)

metadata = claude_marketplace.setdefault("metadata", {})
metadata["version"] = version

plugins = claude_marketplace.get("plugins")
if not isinstance(plugins, list) or len(plugins) != 1:
    raise SystemExit("Claude marketplace must contain exactly one plugin entry")

plugins[0]["version"] = version
claude_plugin["version"] = version
codex_plugin["version"] = version

for path, payload in (
    (claude_marketplace_path, claude_marketplace),
    (claude_plugin_path, claude_plugin),
    (codex_plugin_path, codex_plugin),
):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2)
        f.write("\n")
PY
