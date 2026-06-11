#!/system/bin/sh

MODDIR=${0%/*}

if [ -x "$MODDIR/action.sh" ]; then
  (
    until [ "$(getprop sys.boot_completed)" = "1" ]; do
      sleep 2
    done
    sh "$MODDIR/action.sh" daemon >/dev/null 2>&1
  ) &
fi
