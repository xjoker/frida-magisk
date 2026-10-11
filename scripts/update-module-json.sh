#!/usr/bin/env bash
# Rewrite update/official.json + changelog for a published release.
# Usage: scripts/update-module-json.sh <frida-version> <release-tag> <owner/repo>
# Exits 0 without changes when the version is not newer than the current one
# (e.g. re-publishing an older tag), so update.json never goes backwards.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$1"
TAG="$2"
REPO="$3"
JSON="$ROOT/update/official.json"
CHANGELOG="$ROOT/update/official-changelog.md"

if [[ ! "$VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "Unsupported version: $VERSION" >&2
  exit 1
fi
code=$((10#${BASH_REMATCH[1]} * 10000 + 10#${BASH_REMATCH[2]} * 100 + 10#${BASH_REMATCH[3]}))

current=0
if [[ -f "$JSON" ]]; then
  current="$(python3 -c 'import json,sys; print(int(json.load(open(sys.argv[1]))["versionCode"]))' "$JSON")"
fi
if (( code <= current )); then
  echo "update.json already at versionCode $current >= $code; leaving it unchanged."
  exit 0
fi

python3 - "$JSON" "$VERSION" "$code" "$TAG" "$REPO" <<'PY'
import json, sys
path, version, code, tag, repo = sys.argv[1:]
data = {
    "version": version,
    "versionCode": int(code),
    "zipUrl": f"https://github.com/{repo}/releases/download/{tag}/frida-magisk-{version}-universal.zip",
    "changelog": f"https://raw.githubusercontent.com/{repo}/main/update/official-changelog.md",
}
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY

cat > "$CHANGELOG" <<MD
# Frida Magisk $VERSION

Automated build for Frida $VERSION.

Release: https://github.com/$REPO/releases/tag/$TAG
MD
echo "update.json -> $VERSION ($code)"
