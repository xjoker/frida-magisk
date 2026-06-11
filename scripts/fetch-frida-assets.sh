#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${FRIDA_ASSET_DIR:-$ROOT/assets/frida}"
VERSION="${FRIDA_VERSION:-17.9.1}"
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
    *) return 1 ;;
  esac
}

download_one() {
  local name="$1"
  local archive="$OUT/$name"
  local expected=""
  expected="$(sha256_for "$name" 2>/dev/null || true)"

  mkdir -p "$OUT"
  if [[ ! -f "$archive" ]]; then
    curl -L --fail --show-error --output "$archive" "$BASE_URL/$name"
  fi

  if [[ -n "$expected" ]]; then
    actual="$(sha256_file "$archive")"
    if [[ "$actual" != "$expected" ]]; then
      echo "SHA-256 mismatch for $name: expected $expected got $actual" >&2
      exit 1
    fi
  elif [[ "${FRIDA_ALLOW_UNVERIFIED:-}" != "1" ]]; then
    echo "No pinned SHA-256 for $name." >&2
    echo "Set FRIDA_ALLOW_UNVERIFIED=1 to download this Frida version without local checksum pinning." >&2
    exit 1
  fi

  xz -dkf "$archive"
  chmod 0755 "${archive%.xz}"
  echo "${archive%.xz}"
}

for arch in arm arm64 x86 x86_64; do
  download_one "frida-server-$VERSION-android-$arch.xz"
  download_one "frida-gadget-$VERSION-android-$arch.so.xz"
done
