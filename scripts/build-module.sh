#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULE_SRC="$ROOT/module"
BINARY_DIR="${FRIDA_ASSET_DIR:-$ROOT/assets/frida}"
OUT_DIR="$ROOT/dist"
MODULE_ABI="${1:-${MODULE_ABI:-universal}}"
SUPPORTED_ABIS=(arm64-v8a armeabi-v7a x86 x86_64)

android_to_module_abi() {
  case "$1" in
    arm64) echo "arm64-v8a" ;;
    arm) echo "armeabi-v7a" ;;
    x86) echo "x86" ;;
    x86_64) echo "x86_64" ;;
    *) return 1 ;;
  esac
}

is_supported_abi() {
  local abi="$1"
  [[ "$abi" == "universal" ]] && return 0
  local supported
  for supported in "${SUPPORTED_ABIS[@]}"; do
    [[ "$abi" == "$supported" ]] && return 0
  done
  return 1
}

should_include_abi() {
  local abi="$1"
  [[ "$MODULE_ABI" == "universal" || "$MODULE_ABI" == "$abi" ]]
}

package_suffix() {
  if [[ "$MODULE_ABI" == "universal" ]]; then
    echo "universal"
  else
    echo "$MODULE_ABI"
  fi
}

if ! is_supported_abi "$MODULE_ABI"; then
  echo "Unsupported MODULE_ABI=$MODULE_ABI" >&2
  echo "Expected one of: universal ${SUPPORTED_ABIS[*]}" >&2
  exit 1
fi

server_binaries=()
while IFS= read -r path; do
  server_binaries+=("$path")
done < <(find "$BINARY_DIR" -maxdepth 1 -type f -name 'frida-server-*-android-*' ! -name '*.xz' | sort -V)

if [[ "${#server_binaries[@]}" -eq 0 ]]; then
  echo "No frida-server binaries found under $BINARY_DIR" >&2
  exit 1
fi

base="$(basename "${server_binaries[0]}")"
version="${base#frida-server-}"
version="${version%-android-*}"
IFS=. read -r major minor patch _ <<< "$version"
major="${major:-0}"
minor="${minor:-0}"
patch="${patch:-0}"
version_code=$((10#$major * 10000 + 10#$minor * 100 + 10#$patch))

tmp="$(mktemp -d "${TMPDIR:-/tmp}/frida-magisk-module.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin" "$tmp/gadget" "$tmp/zygisk" "$OUT_DIR"
cp -R "$MODULE_SRC"/. "$tmp"/
rm -rf "$tmp/native"

for binary in "${server_binaries[@]}"; do
  base="$(basename "$binary")"
  binary_version="${base#frida-server-}"
  android_arch="${binary_version##*-android-}"
  binary_version="${binary_version%-android-*}"
  if [[ "$binary_version" != "$version" ]]; then
    echo "Mixed frida-server versions are not supported: $base vs $version" >&2
    exit 1
  fi
  abi="$(android_to_module_abi "$android_arch")"
  should_include_abi "$abi" || continue
  mkdir -p "$tmp/bin/$abi"
  cp "$binary" "$tmp/bin/$abi/frida-server"
done

while IFS= read -r gadget; do
  base="$(basename "$gadget")"
  gadget_version="${base#frida-gadget-}"
  android_arch="${gadget_version##*-android-}"
  android_arch="${android_arch%.so}"
  gadget_version="${gadget_version%-android-*}"
  [[ "$gadget_version" == "$version" ]] || continue
  abi="$(android_to_module_abi "$android_arch")"
  should_include_abi "$abi" || continue
  mkdir -p "$tmp/gadget/$abi"
  cp "$gadget" "$tmp/gadget/$abi/libfrida-gadget.so"
done < <(find "$BINARY_DIR" -maxdepth 1 -type f -name 'frida-gadget-*-android-*.so' | sort -V)

if [[ -d "$BINARY_DIR/zygisk" ]]; then
  while IFS= read -r injector; do
    abi="$(basename "$injector" .so)"
    should_include_abi "$abi" || continue
    cp "$injector" "$tmp/zygisk/$abi.so"
  done < <(find "$BINARY_DIR/zygisk" -maxdepth 1 -type f -name '*.so' | sort)
fi

if [[ ! -d "$tmp/bin/$MODULE_ABI" && "$MODULE_ABI" != "universal" ]]; then
  echo "Missing frida-server for MODULE_ABI=$MODULE_ABI under $BINARY_DIR" >&2
  exit 1
fi

if [[ "$MODULE_ABI" == "universal" ]]; then
  for abi in "${SUPPORTED_ABIS[@]}"; do
    if [[ ! -d "$tmp/bin/$abi" ]]; then
      echo "Missing frida-server for universal package ABI=$abi under $BINARY_DIR" >&2
      exit 1
    fi
  done
fi

{
  echo "FRIDA_MAGISK_PACKAGE_ABI=$MODULE_ABI"
  echo "FRIDA_MAGISK_VERSION=$version"
} > "$tmp/package.env"

chmod 0755 "$tmp/action.sh" "$tmp/service.sh" "$tmp/customize.sh" "$tmp/uninstall.sh"
find "$tmp/bin" -type f -name frida-server -exec chmod 0755 {} +
find "$tmp/gadget" "$tmp/zygisk" -type f -name '*.so' -exec chmod 0644 {} +
chmod 0644 "$tmp/module.prop" "$tmp/README.md" "$tmp/package.env"

sed -i.bak \
  -e "s/^version=.*/version=$version/" \
  -e "s/^versionCode=.*/versionCode=$version_code/" \
  "$tmp/module.prop"
rm -f "$tmp/module.prop.bak"

suffix="$(package_suffix)"
out="$OUT_DIR/frida-magisk-$version-$suffix.zip"
rm -f "$out"
(
  cd "$tmp"
  zip -qr "$out" .
)

if command -v shasum >/dev/null 2>&1; then
  (cd "$OUT_DIR" && shasum -a 256 "$(basename "$out")" > "$(basename "$out").sha256")
elif command -v sha256sum >/dev/null 2>&1; then
  (cd "$OUT_DIR" && sha256sum "$(basename "$out")" > "$(basename "$out").sha256")
fi

echo "$out"
