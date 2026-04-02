#!/usr/bin/env bash
set -euo pipefail

repo_root="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
version_file="$repo_root/VERSION"

if [[ ! -f "$version_file" ]]; then
  echo "Missing VERSION file: $version_file" >&2
  exit 1
fi

version="$(tr -d '[:space:]' < "$version_file")"
if [[ -z "$version" ]]; then
  echo "VERSION file is empty" >&2
  exit 1
fi

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "VERSION must be strict semver in the form X.Y.Z" >&2
  exit 1
fi

printf '%s\n' "$version"
