#!/usr/bin/env bash
set -euo pipefail

zip_path="${1:-}"
if [[ -z "$zip_path" || ! -f "$zip_path" ]]; then
  echo "Usage: $0 <frida-magisk-antidetect.zip>" >&2
  exit 2
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/frida-magisk-verify.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

unzip -q "$zip_path" package.env -d "$tmp"

read_env_value() {
  local key="$1"
  awk -F= -v key="$key" '
    $1 == key {
      sub(/^[^=]*=/, "")
      print
      exit
    }
  ' "$tmp/package.env"
}

package_flavor="$(read_env_value FRIDA_MAGISK_PACKAGE_FLAVOR)"
if [[ "$package_flavor" != "antidetect" ]]; then
  echo "Package is not marked as antidetect: $zip_path" >&2
  exit 1
fi

module_id="$(read_env_value FRIDA_MAGISK_MODULE_ID)"
module_name="$(read_env_value FRIDA_MAGISK_MODULE_NAME)"
server_name="$(read_env_value FRIDA_SERVER_BASENAME)"
gadget_name="$(read_env_value GADGET_BASENAME)"
runtime_dir="$(read_env_value FRIDA_RUNTIME_DIR)"
gadget_config_name="$(read_env_value GADGET_CONFIG_BASENAME)"
mode="$(read_env_value FRIDA_MODE)"
server_listen="$(read_env_value FRIDA_LISTEN)"
gadget_listen="$(read_env_value GADGET_LISTEN)"
gadget_on_load="$(read_env_value GADGET_ON_LOAD)"
gadget_runtime="$(read_env_value GADGET_RUNTIME)"
gadget_include_children="$(read_env_value GADGET_INCLUDE_CHILDREN)"
package_abi="$(read_env_value FRIDA_MAGISK_PACKAGE_ABI)"
package_abi="${package_abi:-universal}"

for value in "$module_id" "$module_name" "$server_name" "$gadget_name" "$runtime_dir" \
             "$gadget_config_name" "$mode" "$server_listen" "$gadget_listen" \
             "$gadget_on_load" "$gadget_runtime" "$gadget_include_children"; do
  if [[ -z "$value" ]]; then
    echo "Missing surface profile value in package.env" >&2
    exit 1
  fi
done

reject_public_or_placeholder() {
  local label="$1"
  local value="$2"
  local lower
  lower="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    *replace_me*|*changeme*|*change_me*|*placeholder*|*example*|*sample*|*todo*)
      echo "Antidetect $label uses a placeholder-like value." >&2
      exit 1
      ;;
  esac
  case "$value" in
    frida_magisk|frida-server|Frida\ Magisk|\
    /data/local/tmp/frida_magisk|/data/adb/modules/frida_magisk|\
    127.0.0.1:27042|127.0.0.1:27043|\
    libfrida-gadget.so|libfrida-gadget.config.so)
      echo "Antidetect $label still uses a public default value." >&2
      exit 1
      ;;
  esac
}

reject_public_or_placeholder MODULE_ID "$module_id"
reject_public_or_placeholder MODULE_NAME "$module_name"
reject_public_or_placeholder FRIDA_SERVER_BASENAME "$server_name"
reject_public_or_placeholder FRIDA_RUNTIME_DIR "$runtime_dir"
reject_public_or_placeholder FRIDA_LISTEN "$server_listen"
reject_public_or_placeholder GADGET_BASENAME "$gadget_name"
reject_public_or_placeholder GADGET_CONFIG_BASENAME "$gadget_config_name"
reject_public_or_placeholder GADGET_LISTEN "$gadget_listen"

if [[ "$mode" != "hybrid" ]]; then
  echo "Antidetect package must keep both server and Gadget available by default." >&2
  exit 1
fi
if [[ "$server_listen" == "127.0.0.1:27042" || "$gadget_listen" == "127.0.0.1:27043" ]]; then
  echo "Default Frida listen ports are still present in package.env." >&2
  exit 1
fi
if [[ "$server_listen" == "$gadget_listen" ]]; then
  echo "Server and Gadget listen addresses must be different." >&2
  exit 1
fi
if [[ "$runtime_dir" == "/data/local/tmp/frida_magisk" ||
      "$gadget_config_name" == "libfrida-gadget.config.so" ]]; then
  echo "Default runtime or Gadget config surface is still present in package.env." >&2
  exit 1
fi
if [[ "$gadget_on_load" != "resume" || "$gadget_include_children" != "no" ]]; then
  echo "Unsafe default Gadget policy in package.env." >&2
  exit 1
fi
if [[ "$gadget_runtime" != "qjs" && "$gadget_runtime" != "v8" ]]; then
  echo "Invalid Gadget runtime in package.env." >&2
  exit 1
fi

unzip -Z1 "$zip_path" > "$tmp/entries.txt"
unzip -p "$zip_path" action.sh customize.sh > "$tmp/scripts.txt"
unzip -p "$zip_path" module.prop README.md webroot/app.js webroot/index.html action.sh customize.sh > "$tmp/static-surfaces.txt"

if grep -Eq '^(FRIDA_RUNTIME_DIR=/data/local/tmp/frida_magisk|FRIDA_LISTEN=127\.0\.0\.1:27042|GADGET_CONFIG_BASENAME=libfrida-gadget\.config\.so|GADGET_LISTEN=127\.0\.0\.1:27043|GADGET_ON_LOAD=wait)$' "$tmp/scripts.txt"; then
  echo "Default runtime profile values are still present in packaged scripts." >&2
  exit 1
fi
if grep -Eq 'frida-server|libfrida-gadget(\.config)?\.so|/data/local/tmp/frida_magisk|/data/adb/modules/frida_magisk|127\.0\.0\.1:27042|127\.0\.0\.1:27043|Frida Magisk' "$tmp/static-surfaces.txt"; then
  echo "Default static module surfaces are still present in packaged text files." >&2
  exit 1
fi
if grep -Eiq 'replace_me|changeme|change_me' "$tmp/static-surfaces.txt"; then
  echo "Placeholder-like values are still present in packaged text files." >&2
  exit 1
fi

if grep -Eq '^bin/[^/]+/frida-server$|^bin/frida-server$' "$tmp/entries.txt"; then
  echo "Default server basename is still present in ZIP entries." >&2
  exit 1
fi
if grep -Eq '^gadget/[^/]+/libfrida-gadget\.so$|^gadget/[^/]+/libfrida-gadget\.config\.so$' "$tmp/entries.txt"; then
  echo "Default Gadget basename is still present in ZIP entries." >&2
  exit 1
fi

expected_abis=(arm64-v8a armeabi-v7a x86 x86_64)
if [[ "$package_abi" != "universal" ]]; then
  expected_abis=("$package_abi")
fi

for abi in "${expected_abis[@]}"; do
  grep -qx "bin/$abi/$server_name" "$tmp/entries.txt" || {
    echo "Missing profiled server entry for $abi." >&2
    exit 1
  }
  grep -qx "gadget/$abi/$gadget_name" "$tmp/entries.txt" || {
    echo "Missing profiled Gadget entry for $abi." >&2
    exit 1
  }
  grep -qx "zygisk/$abi.so" "$tmp/entries.txt" || {
    echo "Missing Zygisk injector entry for $abi." >&2
    exit 1
  }
  unzip -p "$zip_path" "zygisk/$abi.so" > "$tmp/zygisk-$abi.so"
  if grep -aEq 'FridaMagiskZygisk|FridaToolboxInjector|frida_magisk_zygisk|/data/adb/modules/frida_magisk|/data/local/tmp/frida_magisk|libfrida-gadget\.so|missing gadget|loaded gadget' "$tmp/zygisk-$abi.so"; then
    echo "Default native Zygisk surfaces are still present for $abi." >&2
    exit 1
  fi
  if grep -aEiq 'replace_me|changeme|change_me' "$tmp/zygisk-$abi.so"; then
    echo "Placeholder-like native Zygisk value is still present for $abi." >&2
    exit 1
  fi
done

echo "Verified antidetect package surface: $zip_path"
