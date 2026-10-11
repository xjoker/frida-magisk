#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${FRIDA_ASSET_DIR:-$ROOT/assets/frida}"
VERSION="${FRIDA_VERSION:-17.23.3}"
BASE_URL="https://github.com/frida/frida/releases/download/$VERSION"

sha256_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    echo "Neither shasum nor sha256sum is available." >&2
    return 1
  fi
}

sha256_for() {
  case "$1" in
    frida-server-17.9.1-android-arm.xz) echo "5f9e16f93d8dd7b1745e1e328835113a92d9e0795030d1c3069a234a6077c696" ;;
    frida-server-17.9.1-android-arm64.xz) echo "9200b4f31a6cf2aa8e847201e70ffa2c9621f5990d7a3fd96d5ed627c6f2d396" ;;
    frida-server-17.9.1-android-x86.xz) echo "c5bab5aa2272d74e0d1fc3d24772e27824284ec0b41ebb87539a36261343a65a" ;;
    frida-server-17.9.1-android-x86_64.xz) echo "f5f1205ffb3cb145de9264a8c6aa7aa8724a2e33df319d476f2ef67cac453c5f" ;;
    frida-gadget-17.9.1-android-arm.so.xz) echo "90f271810fbbf0e6fef6cdea761a105f8ae1630a1dd4f8133ea67c27104fa829" ;;
    frida-gadget-17.9.1-android-arm64.so.xz) echo "6ebc1cb0eb5fa539bb8084e8683530084788781fd201291a965c886718f0af1f" ;;
    frida-gadget-17.9.1-android-x86.so.xz) echo "49509f6866026869b78acb071493854a9b5c8bce022043a24c7a21a962682e43" ;;
    frida-gadget-17.9.1-android-x86_64.so.xz) echo "9bbc68bb28bd34d1b98a2a75bb403660f8d367f8649d17aa54ca1c3e08cf9195" ;;
    frida-server-17.23.3-android-arm.xz) echo "9d0aac3654d0fa0086c77ae3da9e66548f8f827ab4c20d94ac529de19a2ba44a" ;;
    frida-server-17.23.3-android-arm64.xz) echo "f61e98db10dc1692be1cfe209e4ec32f5381759c722ab1a3f79db36730e6234e" ;;
    frida-server-17.23.3-android-x86.xz) echo "7825046c19fa6e505eb19df57f4903a127011cbaa9f65fc85cf8ef9d99754968" ;;
    frida-server-17.23.3-android-x86_64.xz) echo "5413e802fc2edbbd7f933352542e517d8ecd55aacd5f403fe51d8170bfeaa9b6" ;;
    frida-gadget-17.23.3-android-arm.so.xz) echo "f01ce2f982a34d95c7f9a44ba787b6577d844bc14015da6e41289dbf80af2d23" ;;
    frida-gadget-17.23.3-android-arm64.so.xz) echo "aeb3109844d69f5745438597667841a9141e8701a174341999e1479a4c97925f" ;;
    frida-gadget-17.23.3-android-x86.so.xz) echo "b9646fdb044f55ccf30bb13828ed2effd17c25bdec88c4c3041b45955319beff" ;;
    frida-gadget-17.23.3-android-x86_64.so.xz) echo "31c0210da61880ed7c4cb614e0e118b9d83e7a27768bdd393ffaa9520e7d20bb" ;;
    *) return 1 ;;
  esac
}

release_digests=""

# Resolve the expected SHA-256 from the GitHub releases API `digest` field
# (computed by GitHub at upload time). Used for every version that is not
# pinned locally above. There is no unverified fallback.
#
# Runs in the calling shell so `release_digests` is fetched once per run, not
# once per asset. A command substitution would isolate it in a subshell.
load_release_digests() {
  if [[ -n "$release_digests" ]]; then
    return 0
  fi
  local api="https://api.github.com/repos/frida/frida/releases/tags/$VERSION"
  local auth=()
  if [[ -n "${GITHUB_TOKEN:-${GH_TOKEN:-}}" ]]; then
    auth=(-H "Authorization: Bearer ${GITHUB_TOKEN:-${GH_TOKEN:-}}")
  fi
  release_digests="$(curl -fsSL --retry 3 \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "${auth[@]}" "$api" \
    | python3 -c 'import json, sys
for a in json.load(sys.stdin).get("assets", []):
    d = a.get("digest") or ""
    if d.startswith("sha256:"):
        print(a["name"], d[len("sha256:"):])')" || {
    echo "Failed to query $api for asset digests." >&2
    return 1
  }
  [[ -n "$release_digests" ]]
}

download_one() {
  local name="$1"
  local archive="$OUT/$name"
  local expected="" actual=""
  if ! expected="$(sha256_for "$name")"; then
    if ! load_release_digests ||
       ! expected="$(awk -v n="$name" '$1 == n { print $2; found = 1 } END { exit !found }' <<<"$release_digests")" ||
       [[ ! "$expected" =~ ^[0-9a-f]{64}$ ]]; then
      echo "No SHA-256 available for $name (not pinned locally and no digest from the GitHub releases API)." >&2
      exit 1
    fi
  fi

  mkdir -p "$OUT"
  if [[ ! -f "$archive" ]]; then
    curl -L --fail --show-error --retry 3 --output "$archive.part" "$BASE_URL/$name"
    mv "$archive.part" "$archive"
  fi

  actual="$(sha256_file "$archive")"
  if [[ "$actual" != "$expected" ]]; then
    echo "SHA-256 mismatch for $name: expected $expected got $actual" >&2
    rm -f "$archive"
    exit 1
  fi
  echo "Verified $name sha256=$actual" >&2

  xz -dkf "$archive"
  chmod 0755 "${archive%.xz}"
  echo "${archive%.xz}"
}

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Unsupported FRIDA_VERSION=$VERSION (expected X.Y.Z)." >&2
  exit 1
fi

for arch in arm arm64 x86 x86_64; do
  download_one "frida-server-$VERSION-android-$arch.xz"
  download_one "frida-gadget-$VERSION-android-$arch.so.xz"
done
