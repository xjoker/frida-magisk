#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/module/native/zygisk"
OUT="${FRIDA_ASSET_DIR:-$ROOT/assets/frida}/zygisk"
BUILD_ROOT="$ROOT/build/zygisk"
PACKAGE_FLAVOR="${FRIDA_PACKAGE_FLAVOR:-official}"

apply_antidetect_profile_assignment() {
  local key="$1"
  local value="$2"
  case "$key" in
    ANTIDETECT_PROFILE_NAME|ANTIDETECT_MODULE_ID|ANTIDETECT_RUNTIME_DIR|ANTIDETECT_GADGET_BASENAME|\
    ANTIDETECT_ZYGISK_LOG_TAG|ANTIDETECT_ZYGISK_MODULE_CLASS|\
    ANTIDETECT_ZYGISK_MODULE_FALLBACK|ANTIDETECT_ZYGISK_RUNTIME_FALLBACK|\
    ANTIDETECT_ZYGISK_GADGET_FALLBACK|ANTIDETECT_ZYGISK_OUTPUT_NAME|\
    ANTIDETECT_MODULE_NAME|ANTIDETECT_MODULE_DESCRIPTION|\
    ANTIDETECT_SERVER_BASENAME|ANTIDETECT_PID_BASENAME|\
    ANTIDETECT_FRIDA_MODE|ANTIDETECT_FRIDA_LISTEN|\
    ANTIDETECT_GADGET_CONFIG_BASENAME|ANTIDETECT_GADGET_LISTEN|\
    ANTIDETECT_GADGET_ON_LOAD|ANTIDETECT_GADGET_RUNTIME|\
    ANTIDETECT_GADGET_INCLUDE_CHILDREN)
      ;;
    *)
      echo "Unsupported key in antidetect profile: $key" >&2
      exit 1
      ;;
  esac
  if [[ -z "${!key+x}" ]]; then
    export "$key=$value"
  fi
}

load_antidetect_profile() {
  local profile="${ANTIDETECT_PROFILE_FILE:-}"
  [[ -z "$profile" ]] && return 0
  if [[ ! -f "$profile" ]]; then
    echo "ANTIDETECT_PROFILE_FILE does not exist: $profile" >&2
    exit 1
  fi
  local line key value
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    if [[ ! "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
      echo "Invalid antidetect profile line: $line" >&2
      exit 1
    fi
    key="${line%%=*}"
    value="${line#*=}"
    apply_antidetect_profile_assignment "$key" "$value"
  done < "$profile"
}

require_antidetect_value() {
  local key="$1"
  if [[ -z "${!key:-}" ]]; then
    echo "Missing required antidetect profile value: $key" >&2
    exit 1
  fi
}

profile_token_from_name() {
  local value="$1"
  value="${value//-/_}"
  value="${value//./_}"
  value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  if [[ ! "$value" =~ ^[A-Za-z_] ]]; then
    value="p_$value"
  fi
  echo "$value"
}

validate_identifier() {
  local label="$1"
  local value="$2"
  if [[ ! "$value" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    echo "Unsupported $label=$value" >&2
    echo "Expected a C/C++ identifier." >&2
    exit 1
  fi
}

validate_basename() {
  local label="$1"
  local value="$2"
  if [[ ! "$value" =~ ^[A-Za-z0-9._-]+$ || "$value" == "." || "$value" == ".." ]]; then
    echo "Unsupported $label=$value" >&2
    exit 1
  fi
}

validate_cmake_string() {
  local label="$1"
  local value="$2"
  if [[ -z "$value" || "$value" == *$'\n'* || "$value" == *$'\r'* ||
        "$value" == *'"'* || "$value" == *"\\"* || "$value" == *";"* ]]; then
    echo "Unsupported $label=$value" >&2
    echo "Expected a non-empty single-line value without quotes, backslashes, or semicolons." >&2
    exit 1
  fi
}

reject_public_antidetect_value() {
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
    FridaMagiskZygisk|FridaToolboxInjector|\
    /data/adb/modules/frida_magisk|/data/local/tmp/frida_magisk|\
    libfrida-gadget.so|frida_magisk_zygisk)
      echo "Antidetect $label still uses a public default value." >&2
      exit 1
      ;;
  esac
}

find_ndk() {
  if [[ -n "${ANDROID_NDK_HOME:-}" && -f "$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake" ]]; then
    echo "$ANDROID_NDK_HOME"
    return 0
  fi
  if [[ -n "${ANDROID_NDK_ROOT:-}" && -f "$ANDROID_NDK_ROOT/build/cmake/android.toolchain.cmake" ]]; then
    echo "$ANDROID_NDK_ROOT"
    return 0
  fi
  local sdk_ndk
  for sdk_ndk in \
    "${ANDROID_HOME:-}/ndk" \
    "${ANDROID_SDK_ROOT:-}/ndk" \
    "$HOME/Library/Android/sdk/ndk" \
    "$HOME/Android/Sdk/ndk" \
    "/usr/local/lib/android/sdk/ndk"; do
    if [[ -d "$sdk_ndk" ]]; then
      find "$sdk_ndk" -mindepth 4 -maxdepth 4 -path '*/build/cmake/android.toolchain.cmake' -type f \
        | sed 's#/build/cmake/android.toolchain.cmake$##' \
        | sort -V \
        | tail -n 1
      return 0
    fi
  done
  return 1
}

ndk_host_tag() {
  case "$(uname -s)" in
    Darwin)
      if [[ -d "$NDK/toolchains/llvm/prebuilt/darwin-x86_64" ]]; then
        echo "darwin-x86_64"
        return 0
      fi
      ;;
    Linux)
      echo "linux-x86_64"
      return 0
      ;;
  esac
  return 1
}

NDK="$(find_ndk)"
if [[ -z "$NDK" || ! -f "$NDK/build/cmake/android.toolchain.cmake" ]]; then
  echo "Android NDK not found. Set ANDROID_NDK_HOME or ANDROID_NDK_ROOT." >&2
  exit 1
fi
HOST_TAG="$(ndk_host_tag)"
STRIP="$NDK/toolchains/llvm/prebuilt/$HOST_TAG/bin/llvm-strip"

mkdir -p "$OUT"
abis=(${ZYGISK_ABIS:-arm64-v8a armeabi-v7a x86 x86_64})

zygisk_log_tag="FridaMagiskZygisk"
zygisk_module_fallback="/data/adb/modules/frida_magisk"
zygisk_runtime_fallback="/data/local/tmp/frida_magisk"
zygisk_gadget_fallback="libfrida-gadget.so"
zygisk_module_class="FridaToolboxInjector"
zygisk_output_name="frida_magisk_zygisk"

if [[ "$PACKAGE_FLAVOR" == "antidetect" ]]; then
  load_antidetect_profile
  profile_name="${ANTIDETECT_PROFILE_NAME:-tamaya}"
  profile_token="$(profile_token_from_name "$profile_name")"
  module_id="${ANTIDETECT_MODULE_ID:-${profile_token}_bridge}"
  runtime_dir="${ANTIDETECT_RUNTIME_DIR:-/data/local/tmp/.${profile_token}}"
  gadget_basename="${ANTIDETECT_GADGET_BASENAME:-lib${profile_token}.so}"
  zygisk_log_tag="${ANTIDETECT_ZYGISK_LOG_TAG:-${profile_token}_zygisk}"
  zygisk_module_fallback="${ANTIDETECT_ZYGISK_MODULE_FALLBACK:-/data/adb/modules/$module_id}"
  zygisk_runtime_fallback="${ANTIDETECT_ZYGISK_RUNTIME_FALLBACK:-$runtime_dir}"
  zygisk_gadget_fallback="${ANTIDETECT_ZYGISK_GADGET_FALLBACK:-$gadget_basename}"
  zygisk_module_class="${ANTIDETECT_ZYGISK_MODULE_CLASS:-${profile_token}_zygisk}"
  zygisk_output_name="${ANTIDETECT_ZYGISK_OUTPUT_NAME:-${profile_token}_zygisk}"
fi

validate_cmake_string ZYGISK_LOG_TAG "$zygisk_log_tag"
validate_cmake_string ZYGISK_MODULE_FALLBACK "$zygisk_module_fallback"
validate_cmake_string ZYGISK_RUNTIME_FALLBACK "$zygisk_runtime_fallback"
validate_cmake_string ZYGISK_GADGET_FALLBACK "$zygisk_gadget_fallback"
validate_identifier ZYGISK_MODULE_CLASS "$zygisk_module_class"
validate_basename ZYGISK_OUTPUT_NAME "$zygisk_output_name"

if [[ "$PACKAGE_FLAVOR" == "antidetect" ]]; then
  reject_public_antidetect_value ZYGISK_LOG_TAG "$zygisk_log_tag"
  reject_public_antidetect_value ZYGISK_MODULE_FALLBACK "$zygisk_module_fallback"
  reject_public_antidetect_value ZYGISK_RUNTIME_FALLBACK "$zygisk_runtime_fallback"
  reject_public_antidetect_value ZYGISK_GADGET_FALLBACK "$zygisk_gadget_fallback"
  reject_public_antidetect_value ZYGISK_MODULE_CLASS "$zygisk_module_class"
  reject_public_antidetect_value ZYGISK_OUTPUT_NAME "$zygisk_output_name"
fi

for abi in "${abis[@]}"; do
  build_dir="$BUILD_ROOT/$abi"
  cmake -S "$SRC" -B "$build_dir" \
    -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI="$abi" \
    -DANDROID_PLATFORM=android-23 \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_LIBRARY_OUTPUT_DIRECTORY="$build_dir/out" \
    -DZYGISK_LOG_TAG="$zygisk_log_tag" \
    -DZYGISK_MODULE_FALLBACK="$zygisk_module_fallback" \
    -DZYGISK_RUNTIME_FALLBACK="$zygisk_runtime_fallback" \
    -DZYGISK_GADGET_FALLBACK="$zygisk_gadget_fallback" \
    -DZYGISK_MODULE_CLASS="$zygisk_module_class" \
    -DZYGISK_OUTPUT_NAME="$zygisk_output_name"
  cmake --build "$build_dir" --config Release
  cp "$build_dir/out/lib$zygisk_output_name.so" "$OUT/$abi.so"
  if [[ -x "$STRIP" ]]; then
    "$STRIP" --strip-unneeded "$OUT/$abi.so"
  fi
  echo "$OUT/$abi.so"
done
