#!/usr/bin/env bash
# Local harness: simulate Magisk customize.sh fresh-install vs upgrade for
# official and antidetect packages, including an Action write_config round-trip.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/frida-config-upgrade.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
PASS=0
FAIL=0

assert_eq() {
  local label="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then
    echo "  PASS  $label ($got)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL  $label: got '$got' want '$want'" >&2
    FAIL=$((FAIL + 1))
  fi
}

config_get() {
  sed -n "s|^$2=||p" "$1" 2>/dev/null | tail -n 1
}

# Magisk stubs used by customize.sh
ui_print() { :; }
abort() { echo "abort: $*" >&2; exit 1; }
set_perm() { :; }
set_perm_recursive() { :; }

run_customize() {
  local work="$1"
  local flavor="$2"
  local prev_modules="${3:-}"
  local modpath="$work/new"
  local modules_root="$work/modules"
  mkdir -p "$modpath/bin/arm64-v8a" "$modules_root"
  # Minimal files customize.sh expects
  : > "$modpath/action.sh"
  : > "$modpath/service.sh"
  : > "$modpath/uninstall.sh"
  : > "$modpath/bin/arm64-v8a/PLACEHOLDER"
  if [[ "$flavor" == "antidetect" ]]; then
    cat > "$modpath/package.env" <<'PE'
FRIDA_MAGISK_PACKAGE_FLAVOR=antidetect
FRIDA_SERVER_BASENAME=tamayad
FRIDA_PID_BASENAME=tamayad
FRIDA_RUNTIME_DIR=/data/local/tmp/.tamaya
FRIDA_MODE=hybrid
FRIDA_LISTEN=127.0.0.1:37642
GADGET_BASENAME=libtamaya.so
GADGET_CONFIG_BASENAME=libtamaya.config.so
GADGET_LISTEN=127.0.0.1:37643
GADGET_ON_LOAD=resume
GADGET_RUNTIME=qjs
GADGET_INCLUDE_CHILDREN=no
PE
    # Antidetect packaging rewrites these defaults into customize.sh / action.sh.
    # Emulate that by exporting the package.env values before sourcing.
    # shellcheck disable=SC1090
    set -a
    # shellcheck disable=SC1091
    . "$modpath/package.env"
    set +a
    mv "$modpath/bin/arm64-v8a/PLACEHOLDER" "$modpath/bin/arm64-v8a/tamayad"
  else
    cat > "$modpath/package.env" <<'PE'
FRIDA_MAGISK_PACKAGE_FLAVOR=official
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
PE
    set -a
    # shellcheck disable=SC1091
    . "$modpath/package.env"
    set +a
    mv "$modpath/bin/arm64-v8a/PLACEHOLDER" "$modpath/bin/arm64-v8a/frida-server"
  fi

  if [[ -n "$prev_modules" && -d "$prev_modules" ]]; then
    local prev_id
    prev_id="$(sed -n 's/^FRIDA_MAGISK_MODULE_ID=//p' "$prev_modules/package.env" 2>/dev/null || true)"
    [[ -z "$prev_id" ]] && prev_id=$( [[ "$flavor" == antidetect ]] && echo tamaya_bridge || echo frida_magisk )
    mkdir -p "$modules_root/$prev_id"
    cp -a "$prev_modules/." "$modules_root/$prev_id/"
  fi

  (
    cd "$modpath"
    export MODPATH="$modpath"
    export ARCH=arm64
    export IS64BIT=true
    export API=34
    # MODID used when copying previous config
    if [[ "$flavor" == "antidetect" ]]; then
      export MODID=tamaya_bridge
    else
      export MODID=frida_magisk
    fi
    # Redirect /data/adb/modules lookups: customize uses absolute path.
    # Patch a copy of customize.sh to use our modules_root.
    sed "s|/data/adb/modules|$modules_root|g" "$ROOT/module/customize.sh" > "$work/customize.sh"
    # shellcheck disable=SC1090
    . "$work/customize.sh"
  )
  echo "$modpath"
}

# Simulate action.sh write_config against an installed module tree.
run_write_config() {
  local modpath="$1"
  local listen="$2"
  (
    export MODDIR="$modpath"
    # shellcheck disable=SC1091
    . "$modpath/package.env" 2>/dev/null || true
    # shellcheck disable=SC1091
    . "$modpath/config.env"
    FRIDA_LISTEN="$listen"
    CONFIG="$modpath/config.env"
    # Inline the fixed write_config body from action.sh
    # shellcheck disable=SC1090
    eval "$(sed -n '/^write_config() {/,/^}/p' "$ROOT/module/action.sh")"
    write_config
  )
}

echo "== 1. Official fresh install =="
W1="$TMP/official-fresh"
mkdir -p "$W1"
M1="$(run_customize "$W1" official)"
assert_eq "flavor" "$(config_get "$M1/config.env" FRIDA_MAGISK_PACKAGE_FLAVOR)" "official"
assert_eq "listen" "$(config_get "$M1/config.env" FRIDA_LISTEN)" "127.0.0.1:27042"

echo "== 2. Official Action write_config keeps flavor =="
run_write_config "$M1" "127.0.0.1:28080"
assert_eq "flavor after write" "$(config_get "$M1/config.env" FRIDA_MAGISK_PACKAGE_FLAVOR)" "official"
assert_eq "listen after write" "$(config_get "$M1/config.env" FRIDA_LISTEN)" "127.0.0.1:28080"

echo "== 3. Official upgrade preserves user listen =="
W3="$TMP/official-up"
mkdir -p "$W3"
# Previous install tree = M1 (with custom listen, with flavor)
cp -a "$M1/." "$W3/prev/"
# Ensure package.env has module id for copy path
echo "FRIDA_MAGISK_MODULE_ID=frida_magisk" >> "$W3/prev/package.env"
M3="$(run_customize "$W3" official "$W3/prev")"
assert_eq "flavor" "$(config_get "$M3/config.env" FRIDA_MAGISK_PACKAGE_FLAVOR)" "official"
assert_eq "listen preserved" "$(config_get "$M3/config.env" FRIDA_LISTEN)" "127.0.0.1:28080"

echo "== 4. Antidetect fresh install applies package defaults =="
W4="$TMP/anti-fresh"
mkdir -p "$W4"
M4="$(run_customize "$W4" antidetect)"
assert_eq "flavor" "$(config_get "$M4/config.env" FRIDA_MAGISK_PACKAGE_FLAVOR)" "antidetect"
assert_eq "listen" "$(config_get "$M4/config.env" FRIDA_LISTEN)" "127.0.0.1:37642"
assert_eq "server basename" "$(config_get "$M4/config.env" FRIDA_SERVER_BASENAME)" "tamayad"

echo "== 5. Antidetect Action write_config keeps flavor (the P1 regression) =="
run_write_config "$M4" "127.0.0.1:39999"
assert_eq "flavor after write" "$(config_get "$M4/config.env" FRIDA_MAGISK_PACKAGE_FLAVOR)" "antidetect"
assert_eq "listen after write" "$(config_get "$M4/config.env" FRIDA_LISTEN)" "127.0.0.1:39999"

echo "== 6. Antidetect upgrade preserves user listen =="
W6="$TMP/anti-up"
mkdir -p "$W6"
cp -a "$M4/." "$W6/prev/"
echo "FRIDA_MAGISK_MODULE_ID=tamaya_bridge" >> "$W6/prev/package.env"
M6="$(run_customize "$W6" antidetect "$W6/prev")"
assert_eq "flavor" "$(config_get "$M6/config.env" FRIDA_MAGISK_PACKAGE_FLAVOR)" "antidetect"
assert_eq "listen preserved" "$(config_get "$M6/config.env" FRIDA_LISTEN)" "127.0.0.1:39999"
assert_eq "mode preserved" "$(config_get "$M6/config.env" FRIDA_MODE)" "hybrid"

echo "== 7. Antidetect upgrade when flavor was dropped (legacy Action) still preserves =="
W7="$TMP/anti-legacy"
mkdir -p "$W7"
cp -a "$M4/." "$W7/prev/"
# Simulate pre-fix write_config that omitted flavor but kept antidetect basenames + user listen
grep -v '^FRIDA_MAGISK_PACKAGE_FLAVOR=' "$W7/prev/config.env" > "$W7/prev/config.env.tmp"
mv "$W7/prev/config.env.tmp" "$W7/prev/config.env"
# Ensure user listen still there
grep -q 'FRIDA_LISTEN=127.0.0.1:39999' "$W7/prev/config.env"
echo "FRIDA_MAGISK_MODULE_ID=tamaya_bridge" >> "$W7/prev/package.env"
M7="$(run_customize "$W7" antidetect "$W7/prev")"
assert_eq "flavor restored" "$(config_get "$M7/config.env" FRIDA_MAGISK_PACKAGE_FLAVOR)" "antidetect"
assert_eq "listen preserved" "$(config_get "$M7/config.env" FRIDA_LISTEN)" "127.0.0.1:39999"

echo "== 8. Official→antidetect profile switch resets listen =="
W8="$TMP/switch"
mkdir -p "$W8"
# Start from official install with custom listen
cp -a "$M1/." "$W8/prev/"
# Same module id path used by antidetect in this harness would differ; force copy by id
echo "FRIDA_MAGISK_MODULE_ID=tamaya_bridge" >> "$W8/prev/package.env"
# Official basenames still in config
M8="$(run_customize "$W8" antidetect "$W8/prev")"
assert_eq "flavor" "$(config_get "$M8/config.env" FRIDA_MAGISK_PACKAGE_FLAVOR)" "antidetect"
assert_eq "listen reset to package default" "$(config_get "$M8/config.env" FRIDA_LISTEN)" "127.0.0.1:37642"

echo
echo "Result: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
