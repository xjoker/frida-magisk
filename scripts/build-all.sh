#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT/scripts/fetch-frida-assets.sh"
"$ROOT/scripts/build-zygisk-injector.sh"

module_abis=(${MODULE_ABIS:-universal arm64-v8a armeabi-v7a x86 x86_64})
for abi in "${module_abis[@]}"; do
  MODULE_ABI="$abi" "$ROOT/scripts/build-module.sh"
done
