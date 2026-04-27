#!/usr/bin/env bash
set -euo pipefail

repo_root="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
marketplace_json="$repo_root/.agents/plugins/marketplace.json"
plugin_root="$repo_root/plugins/tla-workbenches"
plugin_json="$plugin_root/.codex-plugin/plugin.json"
source_skills="$repo_root/skills"
generated_skills="$plugin_root/skills"
version="$("$repo_root/scripts/read_version.sh")"

for required_path in "$marketplace_json" "$plugin_json" "$source_skills" "$generated_skills"; do
  if [[ ! -e "$required_path" ]]; then
    echo "Missing required path: $required_path" >&2
    exit 1
  fi
done

python3 - "$marketplace_json" "$plugin_json" "$version" "$plugin_root" <<'PY'
import json
import pathlib
import re
import sys

marketplace_path, plugin_path, expected_version, plugin_root = sys.argv[1:5]
plugin_root = pathlib.Path(plugin_root)

with open(marketplace_path, "r", encoding="utf-8") as f:
    marketplace = json.load(f)

with open(plugin_path, "r", encoding="utf-8") as f:
    plugin = json.load(f)

expected = {
    "marketplace_name": "younes-agent-skills",
    "plugin_name": "tla-workbenches",
    "plugin_path": "./plugins/tla-workbenches",
    "author_name": "younes-io",
    "version": expected_version,
    "skills": "./skills/",
    "category": "Coding",
}

if marketplace.get("name") != expected["marketplace_name"]:
    raise SystemExit("Unexpected Codex marketplace name")

if marketplace.get("interface", {}).get("displayName") != "Younes Agent Skills":
    raise SystemExit("Codex marketplace must define interface.displayName")

entries = marketplace.get("plugins")
if not isinstance(entries, list) or len(entries) != 1:
    raise SystemExit("Codex marketplace must contain exactly one plugin entry")

entry = entries[0]
if entry.get("name") != expected["plugin_name"]:
    raise SystemExit("Unexpected plugin name in Codex marketplace")

source = entry.get("source")
if source != {"source": "local", "path": expected["plugin_path"]}:
    raise SystemExit("Unexpected Codex marketplace source")

policy = entry.get("policy")
if policy != {"installation": "AVAILABLE", "authentication": "ON_INSTALL"}:
    raise SystemExit("Unexpected Codex marketplace policy")

if entry.get("category") != expected["category"]:
    raise SystemExit("Unexpected Codex marketplace category")

if plugin.get("name") != expected["plugin_name"]:
    raise SystemExit("Unexpected Codex plugin manifest name")

if plugin.get("version") != expected["version"]:
    raise SystemExit("Unexpected Codex plugin manifest version")

if plugin.get("author", {}).get("name") != expected["author_name"]:
    raise SystemExit("Unexpected Codex plugin manifest author")

if plugin.get("repository") != "https://github.com/younes-io/agent-skills":
    raise SystemExit("Codex plugin manifest must include repository URL")

if plugin.get("license") != "MIT":
    raise SystemExit("Codex plugin manifest must include MIT license")

if plugin.get("skills") != expected["skills"]:
    raise SystemExit("Codex plugin manifest must register the ./skills/ directory")

interface = plugin.get("interface")
if not isinstance(interface, dict):
    raise SystemExit("Codex plugin manifest must include interface metadata")

required_interface_fields = [
    "displayName",
    "shortDescription",
    "longDescription",
    "developerName",
    "category",
    "capabilities",
    "websiteURL",
    "privacyPolicyURL",
    "termsOfServiceURL",
    "defaultPrompt",
    "brandColor",
    "composerIcon",
    "logo",
    "screenshots",
]
missing = [field for field in required_interface_fields if field not in interface]
if missing:
    raise SystemExit(f"Codex plugin interface metadata missing fields: {', '.join(missing)}")

if interface["category"] != expected["category"]:
    raise SystemExit("Codex plugin interface category must match marketplace category")

prompts = interface["defaultPrompt"]
if not isinstance(prompts, list) or not 1 <= len(prompts) <= 3:
    raise SystemExit("Codex plugin interface.defaultPrompt must contain 1-3 prompts")

if any(not isinstance(prompt, str) or len(prompt) > 128 for prompt in prompts):
    raise SystemExit("Codex plugin default prompts must be strings of at most 128 characters")

brand_color = interface["brandColor"]
if not isinstance(brand_color, str) or not re.fullmatch(r"#[0-9A-Fa-f]{6}", brand_color):
    raise SystemExit("Codex plugin brandColor must be a #RRGGBB color")

for asset_field in ("composerIcon", "logo"):
    asset_path = interface[asset_field]
    if not isinstance(asset_path, str) or not asset_path.startswith("./"):
        raise SystemExit(f"Codex plugin {asset_field} must be a relative ./ path")
    if not (plugin_root / asset_path[2:]).is_file():
        raise SystemExit(f"Codex plugin asset does not exist: {asset_path}")

screenshots = interface["screenshots"]
if not isinstance(screenshots, list):
    raise SystemExit("Codex plugin screenshots must be a list")

for screenshot in screenshots:
    if not isinstance(screenshot, str) or not screenshot.startswith("./assets/") or not screenshot.endswith(".png"):
        raise SystemExit("Codex plugin screenshots must be PNG paths under ./assets/")
    if not (plugin_root / screenshot[2:]).is_file():
        raise SystemExit(f"Codex plugin screenshot does not exist: {screenshot}")
PY

if find "$generated_skills" -type l | grep -q .; then
  echo "Generated plugin skills must not contain symlinks" >&2
  exit 1
fi

diff -ru --exclude '.DS_Store' "$source_skills" "$generated_skills"
