#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULE_SRC="$ROOT/module"
BINARY_DIR="${FRIDA_ASSET_DIR:-$ROOT/assets/frida}"
OUT_DIR="$ROOT/dist"
MODULE_ABI="${1:-${MODULE_ABI:-universal}}"
PACKAGE_FLAVOR="${FRIDA_PACKAGE_FLAVOR:-official}"
SUPPORTED_ABIS=(arm64-v8a armeabi-v7a x86 x86_64)

apply_antidetect_profile_assignment() {
  local key="$1"
  local value="$2"
  case "$key" in
    ANTIDETECT_PROFILE_NAME|ANTIDETECT_MODULE_ID|ANTIDETECT_MODULE_NAME|ANTIDETECT_MODULE_DESCRIPTION|\
    ANTIDETECT_SERVER_BASENAME|ANTIDETECT_PID_BASENAME|ANTIDETECT_RUNTIME_DIR|\
    ANTIDETECT_FRIDA_MODE|ANTIDETECT_FRIDA_LISTEN|ANTIDETECT_GADGET_BASENAME|\
    ANTIDETECT_GADGET_CONFIG_BASENAME|ANTIDETECT_GADGET_LISTEN|\
    ANTIDETECT_GADGET_ON_LOAD|ANTIDETECT_GADGET_RUNTIME|\
    ANTIDETECT_GADGET_INCLUDE_CHILDREN|ANTIDETECT_ZYGISK_LOG_TAG|\
    ANTIDETECT_ZYGISK_MODULE_CLASS|ANTIDETECT_ZYGISK_MODULE_FALLBACK|\
    ANTIDETECT_ZYGISK_RUNTIME_FALLBACK|ANTIDETECT_ZYGISK_GADGET_FALLBACK|\
    ANTIDETECT_ZYGISK_OUTPUT_NAME)
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
    echo "Set it in ANTIDETECT_PROFILE_FILE or pass it as an environment override." >&2
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

if [[ "$PACKAGE_FLAVOR" == "antidetect" ]]; then
  load_antidetect_profile
fi

MODULE_ID=frida_magisk
PROFILE_NAME=official
MODULE_NAME="Frida Magisk"
MODULE_DESCRIPTION="Run bundled frida-server at boot with watchdog restart and Action status/control entry."
FRIDA_SERVER_BASENAME=frida-server
FRIDA_PID_BASENAME=frida-server
FRIDA_RUNTIME_DIR=/data/local/tmp/frida_magisk
FRIDA_MODE=hybrid
FRIDA_LISTEN=127.0.0.1:27042
GADGET_BASENAME=libfrida-gadget.so
GADGET_CONFIG_BASENAME=libfrida-gadget.config.so
GADGET_LISTEN=127.0.0.1:27043
GADGET_ON_LOAD=wait
GADGET_RUNTIME=qjs
GADGET_INCLUDE_CHILDREN=no

if [[ "$PACKAGE_FLAVOR" == "antidetect" ]]; then
  PROFILE_NAME="${ANTIDETECT_PROFILE_NAME:-tamaya}"
  PROFILE_TOKEN="$(profile_token_from_name "$PROFILE_NAME")"

  MODULE_ID="${ANTIDETECT_MODULE_ID:-${PROFILE_TOKEN}_bridge}"
  MODULE_NAME="${ANTIDETECT_MODULE_NAME:-$PROFILE_NAME}"
  MODULE_DESCRIPTION="${ANTIDETECT_MODULE_DESCRIPTION:-Run bundled $PROFILE_NAME bridge at boot with watchdog restart and Action status/control entry.}"
  FRIDA_SERVER_BASENAME="${ANTIDETECT_SERVER_BASENAME:-${PROFILE_TOKEN}d}"
  FRIDA_PID_BASENAME="${ANTIDETECT_PID_BASENAME:-$FRIDA_SERVER_BASENAME}"
  FRIDA_RUNTIME_DIR="${ANTIDETECT_RUNTIME_DIR:-/data/local/tmp/.${PROFILE_TOKEN}}"
  FRIDA_MODE="${ANTIDETECT_FRIDA_MODE:-hybrid}"
  FRIDA_LISTEN="${ANTIDETECT_FRIDA_LISTEN:-127.0.0.1:37642}"
  GADGET_BASENAME="${ANTIDETECT_GADGET_BASENAME:-lib${PROFILE_TOKEN}.so}"
  GADGET_CONFIG_BASENAME="${ANTIDETECT_GADGET_CONFIG_BASENAME:-lib${PROFILE_TOKEN}.config.so}"
  GADGET_LISTEN="${ANTIDETECT_GADGET_LISTEN:-127.0.0.1:37643}"
  GADGET_ON_LOAD="${ANTIDETECT_GADGET_ON_LOAD:-resume}"
  GADGET_RUNTIME="${ANTIDETECT_GADGET_RUNTIME:-qjs}"
  GADGET_INCLUDE_CHILDREN="${ANTIDETECT_GADGET_INCLUDE_CHILDREN:-no}"
fi

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

included_abis() {
  if [[ "$MODULE_ABI" == "universal" ]]; then
    printf '%s\n' "${SUPPORTED_ABIS[@]}"
  else
    printf '%s\n' "$MODULE_ABI"
  fi
}

package_suffix() {
  if [[ "$MODULE_ABI" == "universal" ]]; then
    echo "universal"
  else
    echo "$MODULE_ABI"
  fi
}

package_prefix() {
  if [[ "$PACKAGE_FLAVOR" == "official" ]]; then
    echo "frida-magisk"
  else
    echo "frida-magisk-$PACKAGE_FLAVOR"
  fi
}

validate_basename() {
  local label="$1"
  local value="$2"
  if [[ ! "$value" =~ ^[A-Za-z0-9._-]+$ || "$value" == "." || "$value" == ".." ]]; then
    echo "Unsupported $label=$value" >&2
    echo "Expected a plain file basename using letters, digits, dot, underscore, or dash." >&2
    exit 1
  fi
}

validate_module_id() {
  local value="$1"
  if [[ ! "$value" =~ ^[A-Za-z][A-Za-z0-9_]*$ ]]; then
    echo "Unsupported module id=$value" >&2
    echo "Expected a letter followed by letters, digits, or underscore." >&2
    exit 1
  fi
}

validate_text_value() {
  local label="$1"
  local value="$2"
  if [[ -z "$value" || "$value" == *$'\n'* || "$value" == *$'\r'* ||
        "$value" == *"|"* || "$value" == *"&"* || "$value" == *"\\"* ]]; then
    echo "Unsupported $label=$value" >&2
    echo "Expected a non-empty single-line value without sed replacement metacharacters." >&2
    exit 1
  fi
}

validate_runtime_dir() {
  local value="$1"
  if [[ ! "$value" =~ ^/data/local/tmp(/[A-Za-z0-9._-]+)+$ ||
        "$value" == *"/../"* ||
        "$value" == */.. ]]; then
    echo "Unsupported FRIDA_RUNTIME_DIR=$value" >&2
    echo "Expected an absolute /data/local/tmp/... path without parent traversal." >&2
    exit 1
  fi
}

validate_listen() {
  local label="$1"
  local value="$2"
  local host="${value%:*}"
  local port="${value##*:}"
  if [[ ! "$host" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ || ! "$port" =~ ^[0-9]{1,5}$ ]]; then
    echo "Unsupported $label=$value" >&2
    echo "Expected IPv4:port with port 1-65535." >&2
    exit 1
  fi
  if (( port < 1 || port > 65535 )); then
    echo "Unsupported $label=$value" >&2
    echo "Expected IPv4:port with port 1-65535." >&2
    exit 1
  fi
}

validate_mode() {
  local value="$1"
  if [[ "$value" != "server" && "$value" != "gadget" && "$value" != "hybrid" ]]; then
    echo "Unsupported FRIDA_MODE=$value" >&2
    echo "Expected server, gadget, or hybrid." >&2
    exit 1
  fi
}

validate_on_load() {
  local value="$1"
  if [[ "$value" != "wait" && "$value" != "resume" ]]; then
    echo "Unsupported GADGET_ON_LOAD=$value" >&2
    echo "Expected wait or resume." >&2
    exit 1
  fi
}

validate_runtime() {
  local value="$1"
  if [[ "$value" != "qjs" && "$value" != "v8" ]]; then
    echo "Unsupported GADGET_RUNTIME=$value" >&2
    echo "Expected qjs or v8." >&2
    exit 1
  fi
}

validate_yes_no() {
  local label="$1"
  local value="$2"
  if [[ "$value" != "yes" && "$value" != "no" ]]; then
    echo "Unsupported $label=$value" >&2
    echo "Expected yes or no." >&2
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
    frida_magisk|frida-server|Frida\ Magisk|\
    /data/local/tmp/frida_magisk|/data/adb/modules/frida_magisk|\
    127.0.0.1:27042|127.0.0.1:27043|\
    libfrida-gadget.so|libfrida-gadget.config.so)
      echo "Antidetect $label still uses a public default value." >&2
      exit 1
      ;;
  esac
}

if ! is_supported_abi "$MODULE_ABI"; then
  echo "Unsupported MODULE_ABI=$MODULE_ABI" >&2
  echo "Expected one of: universal ${SUPPORTED_ABIS[*]}" >&2
  exit 1
fi
if [[ "$PACKAGE_FLAVOR" != "official" && "$PACKAGE_FLAVOR" != "antidetect" ]]; then
  echo "Unsupported FRIDA_PACKAGE_FLAVOR=$PACKAGE_FLAVOR" >&2
  echo "Expected official or antidetect." >&2
  exit 1
fi
validate_module_id "$MODULE_ID"
validate_text_value MODULE_NAME "$MODULE_NAME"
validate_text_value MODULE_DESCRIPTION "$MODULE_DESCRIPTION"
validate_basename FRIDA_MAGISK_PROFILE_NAME "$PROFILE_NAME"
validate_basename FRIDA_SERVER_BASENAME "$FRIDA_SERVER_BASENAME"
validate_basename FRIDA_PID_BASENAME "$FRIDA_PID_BASENAME"
validate_basename GADGET_BASENAME "$GADGET_BASENAME"
validate_basename GADGET_CONFIG_BASENAME "$GADGET_CONFIG_BASENAME"
validate_runtime_dir "$FRIDA_RUNTIME_DIR"
validate_mode "$FRIDA_MODE"
validate_listen FRIDA_LISTEN "$FRIDA_LISTEN"
validate_listen GADGET_LISTEN "$GADGET_LISTEN"
validate_on_load "$GADGET_ON_LOAD"
validate_runtime "$GADGET_RUNTIME"
validate_yes_no GADGET_INCLUDE_CHILDREN "$GADGET_INCLUDE_CHILDREN"

if [[ "$PACKAGE_FLAVOR" == "antidetect" ]]; then
  reject_public_antidetect_value MODULE_ID "$MODULE_ID"
  reject_public_antidetect_value MODULE_NAME "$MODULE_NAME"
  reject_public_antidetect_value MODULE_DESCRIPTION "$MODULE_DESCRIPTION"
  reject_public_antidetect_value FRIDA_SERVER_BASENAME "$FRIDA_SERVER_BASENAME"
  reject_public_antidetect_value FRIDA_PID_BASENAME "$FRIDA_PID_BASENAME"
  reject_public_antidetect_value FRIDA_RUNTIME_DIR "$FRIDA_RUNTIME_DIR"
  reject_public_antidetect_value FRIDA_LISTEN "$FRIDA_LISTEN"
  reject_public_antidetect_value GADGET_BASENAME "$GADGET_BASENAME"
  reject_public_antidetect_value GADGET_CONFIG_BASENAME "$GADGET_CONFIG_BASENAME"
  reject_public_antidetect_value GADGET_LISTEN "$GADGET_LISTEN"
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
  cp "$binary" "$tmp/bin/$abi/$FRIDA_SERVER_BASENAME"
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
  cp "$gadget" "$tmp/gadget/$abi/$GADGET_BASENAME"
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

if [[ "$PACKAGE_FLAVOR" == "antidetect" ]]; then
  while IFS= read -r abi; do
    if [[ ! -f "$tmp/gadget/$abi/$GADGET_BASENAME" ]]; then
      echo "Missing Gadget for antidetect package ABI=$abi under $BINARY_DIR" >&2
      exit 1
    fi
    if [[ ! -f "$tmp/zygisk/$abi.so" ]]; then
      echo "Missing Zygisk injector for antidetect package ABI=$abi under $BINARY_DIR/zygisk" >&2
      exit 1
    fi
  done < <(included_abis)
fi

{
  echo "FRIDA_MAGISK_PACKAGE_ABI=$MODULE_ABI"
  echo "FRIDA_MAGISK_PACKAGE_FLAVOR=$PACKAGE_FLAVOR"
  echo "FRIDA_MAGISK_PROFILE_NAME=$PROFILE_NAME"
  echo "FRIDA_MAGISK_VERSION=$version"
  echo "FRIDA_MAGISK_MODULE_ID=$MODULE_ID"
  echo "FRIDA_MAGISK_MODULE_NAME=$MODULE_NAME"
  echo "FRIDA_SERVER_BASENAME=$FRIDA_SERVER_BASENAME"
  echo "FRIDA_PID_BASENAME=$FRIDA_PID_BASENAME"
  echo "FRIDA_RUNTIME_DIR=$FRIDA_RUNTIME_DIR"
  echo "FRIDA_MODE=$FRIDA_MODE"
  echo "FRIDA_LISTEN=$FRIDA_LISTEN"
  echo "GADGET_BASENAME=$GADGET_BASENAME"
  echo "GADGET_CONFIG_BASENAME=$GADGET_CONFIG_BASENAME"
  echo "GADGET_LISTEN=$GADGET_LISTEN"
  echo "GADGET_ON_LOAD=$GADGET_ON_LOAD"
  echo "GADGET_RUNTIME=$GADGET_RUNTIME"
  echo "GADGET_INCLUDE_CHILDREN=$GADGET_INCLUDE_CHILDREN"
} > "$tmp/package.env"

chmod 0755 "$tmp/action.sh" "$tmp/service.sh" "$tmp/customize.sh" "$tmp/uninstall.sh"
find "$tmp/bin" -type f -name "$FRIDA_SERVER_BASENAME" -exec chmod 0755 {} +
find "$tmp/gadget" "$tmp/zygisk" -type f -name '*.so' -exec chmod 0644 {} +
chmod 0644 "$tmp/module.prop" "$tmp/README.md" "$tmp/package.env"

if [[ "$PACKAGE_FLAVOR" == "antidetect" ]]; then
  for profile_file in "$tmp/action.sh" "$tmp/customize.sh"; do
    sed -i.bak \
    -e "s|Frida Magisk|$MODULE_NAME|g" \
    -e "s|frida-server|$FRIDA_SERVER_BASENAME|g" \
    -e "s|/data/local/tmp/frida_magisk|$FRIDA_RUNTIME_DIR|g" \
    -e "s|127.0.0.1:27042|$FRIDA_LISTEN|g" \
    -e "s|127.0.0.1:27043|$GADGET_LISTEN|g" \
    -e "s|libfrida-gadget.config.so|$GADGET_CONFIG_BASENAME|g" \
    -e "s|libfrida-gadget.so|$GADGET_BASENAME|g" \
    -e "s|^FRIDA_SERVER_BASENAME=.*|FRIDA_SERVER_BASENAME=$FRIDA_SERVER_BASENAME|" \
    -e "s|^FRIDA_PID_BASENAME=.*|FRIDA_PID_BASENAME=$FRIDA_PID_BASENAME|" \
    -e "s|^FRIDA_RUNTIME_DIR=.*|FRIDA_RUNTIME_DIR=$FRIDA_RUNTIME_DIR|" \
    -e "s|^FRIDA_MODE=.*|FRIDA_MODE=$FRIDA_MODE|" \
    -e "s|^FRIDA_LISTEN=.*|FRIDA_LISTEN=$FRIDA_LISTEN|" \
    -e "s|^GADGET_BASENAME=.*|GADGET_BASENAME=$GADGET_BASENAME|" \
    -e "s|^GADGET_CONFIG_BASENAME=.*|GADGET_CONFIG_BASENAME=$GADGET_CONFIG_BASENAME|" \
    -e "s|^GADGET_LISTEN=.*|GADGET_LISTEN=$GADGET_LISTEN|" \
    -e "s|^GADGET_ON_LOAD=.*|GADGET_ON_LOAD=$GADGET_ON_LOAD|" \
    -e "s|^GADGET_RUNTIME=.*|GADGET_RUNTIME=$GADGET_RUNTIME|" \
    -e "s|^GADGET_INCLUDE_CHILDREN=.*|GADGET_INCLUDE_CHILDREN=$GADGET_INCLUDE_CHILDREN|" \
      "$profile_file"
    rm -f "$profile_file.bak"
  done

  module_path="/data/adb/modules/$MODULE_ID"
  gadget_runtime_config="$FRIDA_RUNTIME_DIR/gadget/arm64-v8a/$GADGET_CONFIG_BASENAME"
  module_readme_title="$MODULE_NAME Module"
  sed -i.bak \
    -e "s|^MODID=.*|MODID=$MODULE_ID|" \
    "$tmp/action.sh"
  rm -f "$tmp/action.sh.bak"

  sed -i.bak \
    -e "s|^id=.*|id=$MODULE_ID|" \
    -e "s|^name=.*|name=$MODULE_NAME|" \
    -e "s|^description=.*|description=$MODULE_DESCRIPTION|" \
    "$tmp/module.prop"
  rm -f "$tmp/module.prop.bak"

  sed -i.bak \
    -e "s|Frida Magisk Module|$module_readme_title|g" \
    -e "s|Frida Magisk|$MODULE_NAME|g" \
    -e "s|frida_magisk|$MODULE_ID|g" \
    -e "s|/data/adb/modules/$MODULE_ID|$module_path|g" \
    -e "s|/data/local/tmp/frida_magisk|$FRIDA_RUNTIME_DIR|g" \
    -e "s|frida-server|$FRIDA_SERVER_BASENAME|g" \
    -e "s|Frida Gadget|Gadget backend|g" \
    -e "s|127.0.0.1:27042|$FRIDA_LISTEN|g" \
    -e "s|127.0.0.1:27043|$GADGET_LISTEN|g" \
    -e "s|libfrida-gadget.config.so|$GADGET_CONFIG_BASENAME|g" \
    -e "s|libfrida-gadget.so|$GADGET_BASENAME|g" \
    -e "s|GADGET_ON_LOAD=wait|GADGET_ON_LOAD=$GADGET_ON_LOAD|g" \
    "$tmp/README.md"
  rm -f "$tmp/README.md.bak"

  if [[ -f "$tmp/webroot/app.js" ]]; then
    sed -i.bak \
      -e "s|Frida Magisk|$MODULE_NAME|g" \
      -e "s|frida_magisk|$MODULE_ID|g" \
      -e "s|/data/adb/modules/$MODULE_ID|$module_path|g" \
      -e "s|frida-server|$FRIDA_SERVER_BASENAME|g" \
      -e "s|127.0.0.1:27042|$FRIDA_LISTEN|g" \
      -e "s|127.0.0.1:27043|$GADGET_LISTEN|g" \
      -e "s|/data/local/tmp/frida_magisk|$FRIDA_RUNTIME_DIR|g" \
      -e "s|libfrida-gadget.config.so|$GADGET_CONFIG_BASENAME|g" \
      -e "s|libfrida-gadget.so|$GADGET_BASENAME|g" \
      -e "s|GADGET_CONFIG=$module_path/gadget/arm64-v8a/$GADGET_CONFIG_BASENAME|GADGET_CONFIG=$gadget_runtime_config|g" \
      "$tmp/webroot/app.js"
    rm -f "$tmp/webroot/app.js.bak"
  fi
  if [[ -f "$tmp/webroot/index.html" ]]; then
    sed -i.bak \
      -e "s|Frida Magisk|$MODULE_NAME|g" \
      -e "s|frida-server|$FRIDA_SERVER_BASENAME|g" \
      -e "s|127.0.0.1:27042|$FRIDA_LISTEN|g" \
      -e "s|127.0.0.1:27043|$GADGET_LISTEN|g" \
      "$tmp/webroot/index.html"
    rm -f "$tmp/webroot/index.html.bak"
  fi
fi

sed -i.bak \
  -e "s/^version=.*/version=$version/" \
  -e "s/^versionCode=.*/versionCode=$version_code/" \
  "$tmp/module.prop"
rm -f "$tmp/module.prop.bak"

suffix="$(package_suffix)"
out="$OUT_DIR/$(package_prefix)-$version-$suffix.zip"
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
