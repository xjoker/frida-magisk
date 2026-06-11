#!/system/bin/sh

MODDIR=${0%/*}

if [ -x "$MODDIR/action.sh" ]; then
  "$MODDIR/action.sh" watchdog-stop >/dev/null 2>&1
  "$MODDIR/action.sh" stop >/dev/null 2>&1
fi
