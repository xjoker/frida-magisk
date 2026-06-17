#!/system/bin/sh

ui_print "- Frida Magisk"
ui_print "- Bundled frida-server watchdog module"
ui_print "- ARCH=$ARCH IS64BIT=$IS64BIT API=$API"

if [ -f "$MODPATH/package.env" ]; then
  . "$MODPATH/package.env"
fi
ui_print "- Package ABI: ${FRIDA_MAGISK_PACKAGE_ABI:-universal}"

FRIDA_SERVER_BASENAME=${FRIDA_SERVER_BASENAME:-frida-server}
FRIDA_PID_BASENAME=${FRIDA_PID_BASENAME:-frida-server}
FRIDA_RUNTIME_DIR=${FRIDA_RUNTIME_DIR:-/data/local/tmp/frida_magisk}
FRIDA_MODE=${FRIDA_MODE:-hybrid}
FRIDA_LISTEN=${FRIDA_LISTEN:-127.0.0.1:27042}
GADGET_BASENAME=${GADGET_BASENAME:-libfrida-gadget.so}
GADGET_CONFIG_BASENAME=${GADGET_CONFIG_BASENAME:-libfrida-gadget.config.so}
GADGET_LISTEN=${GADGET_LISTEN:-127.0.0.1:27043}
GADGET_ON_LOAD=${GADGET_ON_LOAD:-wait}
GADGET_RUNTIME=${GADGET_RUNTIME:-qjs}
GADGET_INCLUDE_CHILDREN=${GADGET_INCLUDE_CHILDREN:-no}

case "$ARCH" in
  arm64)
    MODULE_ABI=arm64-v8a
    ;;
  arm)
    MODULE_ABI=armeabi-v7a
    ;;
  x64)
    MODULE_ABI=x86_64
    ;;
  x86)
    MODULE_ABI=x86
    ;;
  *)
    abort "Unsupported ARCH=$ARCH."
    ;;
esac

if [ ! -f "$MODPATH/bin/$MODULE_ABI/$FRIDA_SERVER_BASENAME" ]; then
  abort "Missing frida-server for ABI=$MODULE_ABI."
fi
cp -f "$MODPATH/bin/$MODULE_ABI/$FRIDA_SERVER_BASENAME" "$MODPATH/bin/$FRIDA_SERVER_BASENAME"

mkdir -p "$MODPATH/run"
touch "$MODPATH/skip_mount"

if [ -f "/data/adb/modules/$MODID/config.env" ]; then
  cp -f "/data/adb/modules/$MODID/config.env" "$MODPATH/config.env"
fi

if [ ! -f "$MODPATH/config.env" ]; then
cat > "$MODPATH/config.env" <<'EOF'
# Frida Magisk runtime config.
# Frida default USB port. Use frida-ps -U after Android finishes booting.
FRIDA_MODE=hybrid
FRIDA_LISTEN=127.0.0.1:27042
WATCHDOG_INTERVAL=5
FRIDA_SERVER_BASENAME=frida-server
FRIDA_PID_BASENAME=frida-server
FRIDA_RUNTIME_DIR=/data/local/tmp/frida_magisk
GADGET_BASENAME=libfrida-gadget.so
GADGET_CONFIG_BASENAME=libfrida-gadget.config.so
GADGET_TARGET_PACKAGE=
GADGET_LISTEN=127.0.0.1:27043
GADGET_ON_LOAD=wait
GADGET_RUNTIME=qjs
GADGET_INCLUDE_CHILDREN=no
EOF
fi

set_config_value() {
  local key="$1"
  local value="$2"
  local tmp="$MODPATH/config.env.tmp.$$"
  if grep -q "^$key=" "$MODPATH/config.env" 2>/dev/null; then
    sed "s|^$key=.*|$key=$value|" "$MODPATH/config.env" > "$tmp"
    mv "$tmp" "$MODPATH/config.env"
  else
    echo "$key=$value" >> "$MODPATH/config.env"
  fi
}

config_value() {
  local key="$1"
  sed -n "s|^$key=||p" "$MODPATH/config.env" 2>/dev/null | tail -n 1
}

set_config_if_default() {
  local key="$1"
  local value="$2"
  local default_value="$3"
  local current
  current="$(config_value "$key")"
  if [ -z "$current" ] || [ "$current" = "$default_value" ]; then
    set_config_value "$key" "$value"
  fi
}

PACKAGE_FLAVOR_CURRENT=${FRIDA_MAGISK_PACKAGE_FLAVOR:-official}
PACKAGE_FLAVOR_PREVIOUS=$(config_value FRIDA_MAGISK_PACKAGE_FLAVOR)
PACKAGE_PROFILE_CHANGED=no
if [ -n "$PACKAGE_FLAVOR_PREVIOUS" ] && [ "$PACKAGE_FLAVOR_PREVIOUS" != "$PACKAGE_FLAVOR_CURRENT" ]; then
  PACKAGE_PROFILE_CHANGED=yes
fi
if [ -z "$PACKAGE_FLAVOR_PREVIOUS" ] && [ "$PACKAGE_FLAVOR_CURRENT" != "official" ]; then
  PACKAGE_PROFILE_CHANGED=yes
fi
if [ -z "$PACKAGE_FLAVOR_PREVIOUS" ] && [ "$PACKAGE_FLAVOR_CURRENT" = "official" ]; then
  previous_server_basename=$(config_value FRIDA_SERVER_BASENAME)
  previous_gadget_basename=$(config_value GADGET_BASENAME)
  if { [ -n "$previous_server_basename" ] && [ "$previous_server_basename" != "frida-server" ]; } ||
     { [ -n "$previous_gadget_basename" ] && [ "$previous_gadget_basename" != "libfrida-gadget.so" ]; }; then
    PACKAGE_PROFILE_CHANGED=yes
  fi
fi

set_config_value FRIDA_SERVER_BASENAME "$FRIDA_SERVER_BASENAME"
set_config_value FRIDA_PID_BASENAME "$FRIDA_PID_BASENAME"
set_config_value FRIDA_RUNTIME_DIR "$FRIDA_RUNTIME_DIR"
set_config_value GADGET_BASENAME "$GADGET_BASENAME"
set_config_value GADGET_CONFIG_BASENAME "$GADGET_CONFIG_BASENAME"
set_config_value FRIDA_MAGISK_PACKAGE_FLAVOR "$PACKAGE_FLAVOR_CURRENT"

if [ "$PACKAGE_PROFILE_CHANGED" = "yes" ]; then
  set_config_value FRIDA_MODE "$FRIDA_MODE"
  set_config_value FRIDA_LISTEN "$FRIDA_LISTEN"
  set_config_value GADGET_LISTEN "$GADGET_LISTEN"
  set_config_value GADGET_ON_LOAD "$GADGET_ON_LOAD"
  set_config_value GADGET_RUNTIME "$GADGET_RUNTIME"
  set_config_value GADGET_INCLUDE_CHILDREN "$GADGET_INCLUDE_CHILDREN"
else
  set_config_if_default FRIDA_MODE "$FRIDA_MODE" "hybrid"
  set_config_if_default FRIDA_LISTEN "$FRIDA_LISTEN" "127.0.0.1:27042"
  set_config_if_default GADGET_LISTEN "$GADGET_LISTEN" "127.0.0.1:27043"
  set_config_if_default GADGET_ON_LOAD "$GADGET_ON_LOAD" "wait"
  set_config_if_default GADGET_RUNTIME "$GADGET_RUNTIME" "qjs"
  set_config_if_default GADGET_INCLUDE_CHILDREN "$GADGET_INCLUDE_CHILDREN" "no"
fi

set_perm_recursive "$MODPATH/bin" 0 0 0755 0644
[ -d "$MODPATH/gadget" ] && set_perm_recursive "$MODPATH/gadget" 0 0 0755 0644
[ -d "$MODPATH/zygisk" ] && set_perm_recursive "$MODPATH/zygisk" 0 0 0755 0644
set_perm "$MODPATH/bin/$FRIDA_SERVER_BASENAME" 0 0 0755
set_perm "$MODPATH/bin/$MODULE_ABI/$FRIDA_SERVER_BASENAME" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
[ -f "$MODPATH/uninstall.sh" ] && set_perm "$MODPATH/uninstall.sh" 0 0 0755
set_perm "$MODPATH/config.env" 0 0 0644

ui_print "- Selected ABI: $MODULE_ABI"
ui_print "- Default listen: $FRIDA_LISTEN"
if [ -f "$MODPATH/zygisk/$MODULE_ABI.so" ] && [ -f "$MODPATH/gadget/$MODULE_ABI/$GADGET_BASENAME" ]; then
  ui_print "- Gadget backend: bundled for $MODULE_ABI"
else
  ui_print "- Gadget backend: not bundled for $MODULE_ABI"
fi
ui_print "- Use module Action to view status or restart frida-server"
ui_print "- Reboot is required for automatic start"
