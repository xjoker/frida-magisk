#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT/scripts/fetch-frida-assets.sh"
"$ROOT/scripts/build-zygisk-injector.sh"
"$ROOT/scripts/build-module.sh"
