#!/system/bin/sh

ui_print "- Frida Magisk"
ui_print "- Bundled frida-server watchdog module"
ui_print "- ARCH=$ARCH IS64BIT=$IS64BIT API=$API"

if [ -f "$MODPATH/package.env" ]; then
  . "$MODPATH/package.env"
fi
ui_print "- Package ABI: ${FRIDA_MAGISK_PACKAGE_ABI:-universal}"

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

if [ ! -f "$MODPATH/bin/$MODULE_ABI/frida-server" ]; then
  abort "Missing frida-server for ABI=$MODULE_ABI."
fi
cp -f "$MODPATH/bin/$MODULE_ABI/frida-server" "$MODPATH/bin/frida-server"

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
GADGET_TARGET_PACKAGE=
GADGET_LISTEN=127.0.0.1:27043
GADGET_ON_LOAD=wait
GADGET_RUNTIME=qjs
GADGET_INCLUDE_CHILDREN=no
EOF
fi

set_perm_recursive "$MODPATH/bin" 0 0 0755 0644
[ -d "$MODPATH/gadget" ] && set_perm_recursive "$MODPATH/gadget" 0 0 0755 0644
[ -d "$MODPATH/zygisk" ] && set_perm_recursive "$MODPATH/zygisk" 0 0 0755 0644
set_perm "$MODPATH/bin/frida-server" 0 0 0755
set_perm "$MODPATH/bin/$MODULE_ABI/frida-server" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
[ -f "$MODPATH/uninstall.sh" ] && set_perm "$MODPATH/uninstall.sh" 0 0 0755
set_perm "$MODPATH/config.env" 0 0 0644

ui_print "- Selected ABI: $MODULE_ABI"
ui_print "- Default listen: 127.0.0.1:27042"
if [ -f "$MODPATH/zygisk/$MODULE_ABI.so" ] && [ -f "$MODPATH/gadget/$MODULE_ABI/libfrida-gadget.so" ]; then
  ui_print "- Gadget backend: bundled for $MODULE_ABI"
else
  ui_print "- Gadget backend: not bundled for $MODULE_ABI"
fi
ui_print "- Use module Action to view status or restart frida-server"
ui_print "- Reboot is required for automatic start"
