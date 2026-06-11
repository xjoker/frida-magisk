#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/module/native/zygisk"
OUT="${FRIDA_ASSET_DIR:-$ROOT/assets/frida}/zygisk"
BUILD_ROOT="$ROOT/build/zygisk"

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

for abi in "${abis[@]}"; do
  build_dir="$BUILD_ROOT/$abi"
  cmake -S "$SRC" -B "$build_dir" \
    -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI="$abi" \
    -DANDROID_PLATFORM=android-23 \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_LIBRARY_OUTPUT_DIRECTORY="$build_dir/out"
  cmake --build "$build_dir" --config Release
  cp "$build_dir/out/libfrida_magisk_zygisk.so" "$OUT/$abi.so"
  if [[ -x "$STRIP" ]]; then
    "$STRIP" --strip-unneeded "$OUT/$abi.so"
  fi
  echo "$OUT/$abi.so"
done
