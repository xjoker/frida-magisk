#!/system/bin/sh

MODDIR=${0%/*}
MODID=frida_magisk
CONFIG="$MODDIR/config.env"
RUNDIR="$MODDIR/run"
GADGET_DIR="$MODDIR/gadget"

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

if [ -f "$CONFIG" ]; then
  [ -f "$MODDIR/package.env" ] && . "$MODDIR/package.env"
  . "$CONFIG"
elif [ -f "$MODDIR/package.env" ]; then
  . "$MODDIR/package.env"
fi

BIN="$MODDIR/bin/$FRIDA_SERVER_BASENAME"
PIDFILE="$RUNDIR/$FRIDA_PID_BASENAME.pid"
WATCHDOG_PIDFILE="$RUNDIR/$FRIDA_PID_BASENAME.watchdog.pid"
STATE="$RUNDIR/$FRIDA_PID_BASENAME.status.env"
MANUAL_STOP="$RUNDIR/$FRIDA_PID_BASENAME.manual_stop"
GADGET_PROFILE="$GADGET_DIR/profile.json"
RUNTIME_DIR="$FRIDA_RUNTIME_DIR"
RUNTIME_GADGET_DIR="$RUNTIME_DIR/gadget"

ensure_rundir() {
  [ -d "$RUNDIR" ] || mkdir -p "$RUNDIR"
}

now_epoch() {
  date +%s 2>/dev/null || echo 0
}

now_text() {
  date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || now_epoch
}

is_alive() {
  [ -n "$1" ] && [ -d "/proc/$1" ]
}

read_file() {
  [ -f "$1" ] && cat "$1"
}

pid_cmdline() {
  tr '\000' ' ' < "/proc/$1/cmdline" 2>/dev/null
}

is_frida_pid() {
  is_alive "$1" && pid_cmdline "$1" | grep -q "$FRIDA_SERVER_BASENAME"
}

find_frida_pid() {
  local pid
  pid=$(read_file "$PIDFILE")
  if is_frida_pid "$pid"; then
    echo "$pid"
    return 0
  fi

  for pid in $(pidof "$FRIDA_SERVER_BASENAME" 2>/dev/null); do
    if is_frida_pid "$pid"; then
      echo "$pid"
      return 0
    fi
  done

  return 1
}

write_state() {
  local status="$1"
  local message="$2"
  local pid="$3"
  local restarts="$4"
  local tmp="$STATE.tmp.$$"
  ensure_rundir
  {
    echo "STATUS=$status"
    echo "MESSAGE=$message"
    echo "PID=$pid"
    echo "LISTEN=$FRIDA_LISTEN"
    echo "RESTARTS=$restarts"
    echo "UPDATED_AT=$(now_epoch)"
    echo "UPDATED_TEXT=$(now_text)"
  } > "$tmp"
  mv "$tmp" "$STATE"
}

start_frida() {
  local pid
  if [ "$FRIDA_MODE" = "gadget" ]; then
    write_state "disabled" "server disabled by gadget mode" "" "${1:-0}"
    return 2
  fi

  if [ -f "$MANUAL_STOP" ]; then
    write_state "stopped" "manual stop flag exists" "" "${1:-0}"
    return 2
  fi

  if [ ! -x "$BIN" ]; then
    chmod 0755 "$BIN" 2>/dev/null
  fi
  if [ ! -x "$BIN" ]; then
    write_state "failed" "server binary is missing or not executable" "" "${1:-0}"
    return 1
  fi

  pid=$(find_frida_pid)
  if [ -n "$pid" ]; then
    ensure_rundir
    echo "$pid" > "$PIDFILE"
    write_state "running" "already running" "$pid" "${1:-0}"
    return 0
  fi

  ensure_rundir
  "$BIN" -l "$FRIDA_LISTEN" >/dev/null 2>&1 &
  pid=$!
  echo "$pid" > "$PIDFILE"
  sleep 1

  if is_frida_pid "$pid"; then
    write_state "running" "started" "$pid" "${1:-0}"
    return 0
  fi

  write_state "failed" "process exited after start" "$pid" "${1:-0}"
  return 1
}

stop_frida() {
  local pid="$1"
  [ -n "$pid" ] || pid=$(find_frida_pid)
  if [ -n "$pid" ]; then
    kill "$pid" 2>/dev/null
    sleep 1
    if is_alive "$pid"; then
      kill -9 "$pid" 2>/dev/null
    fi
  fi
  rm -f "$PIDFILE"
  write_state "stopped" "stopped by action" "" "${2:-0}"
}

watchdog_alive() {
  local pid
  pid=$(read_file "$WATCHDOG_PIDFILE")
  is_alive "$pid"
}

daemon_loop() {
  local restarts=0
  local failures=0
  local sleep_seconds="$WATCHDOG_INTERVAL"
  local pid

  if watchdog_alive; then
    exit 0
  fi
  ensure_rundir
  echo "$$" > "$WATCHDOG_PIDFILE"
  stage_gadget_runtime

  while true; do
    if [ -f "$MODDIR/disable" ] || [ -f "$MODDIR/remove" ]; then
      stop_frida "" "$restarts"
      rm -f "$WATCHDOG_PIDFILE"
      exit 0
    fi

    if [ -f "$MANUAL_STOP" ]; then
      write_state "stopped" "manual stop flag exists" "" "$restarts"
      sleep "$WATCHDOG_INTERVAL"
      continue
    fi

    if [ "$FRIDA_MODE" = "gadget" ]; then
      stop_frida "" "$restarts"
      write_state "disabled" "server disabled by gadget mode" "" "$restarts"
      sleep "$WATCHDOG_INTERVAL"
      continue
    fi

    pid=$(find_frida_pid)
    if [ -n "$pid" ]; then
      echo "$pid" > "$PIDFILE"
      failures=0
      sleep_seconds="$WATCHDOG_INTERVAL"
      write_state "running" "watchdog heartbeat" "$pid" "$restarts"
    else
      restarts=$((restarts + 1))
      if start_frida "$restarts"; then
        failures=0
        sleep_seconds="$WATCHDOG_INTERVAL"
      else
        failures=$((failures + 1))
        sleep_seconds=$((WATCHDOG_INTERVAL + failures * 5))
        [ "$sleep_seconds" -gt 60 ] && sleep_seconds=60
      fi
    fi

    sleep "$sleep_seconds"
  done
}

start_watchdog() {
  if watchdog_alive; then
    echo "Watchdog: running pid=$(read_file "$WATCHDOG_PIDFILE")"
    return 0
  fi
  sh "$MODDIR/action.sh" daemon >/dev/null 2>&1 &
  echo "Watchdog: started"
}

stop_watchdog() {
  local pid
  pid=$(read_file "$WATCHDOG_PIDFILE")
  if is_alive "$pid"; then
    kill "$pid" 2>/dev/null
  fi
  rm -f "$WATCHDOG_PIDFILE"
}

valid_listen() {
  local value="$1"
  local host="${value%:*}"
  local port="${value##*:}"

  echo "$host" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$' || return 1
  echo "$port" | grep -Eq '^[0-9]{1,5}$' || return 1
  [ "$port" -ge 1 ] 2>/dev/null && [ "$port" -le 65535 ] 2>/dev/null
}

valid_mode() {
  [ "$1" = "server" ] || [ "$1" = "gadget" ] || [ "$1" = "hybrid" ]
}

valid_package() {
  [ -n "$1" ] && echo "$1" | grep -Eq '^[A-Za-z0-9_.-]+$'
}

valid_on_load() {
  [ "$1" = "wait" ] || [ "$1" = "resume" ]
}

valid_runtime() {
  [ "$1" = "qjs" ] || [ "$1" = "v8" ]
}

valid_yes_no() {
  [ "$1" = "yes" ] || [ "$1" = "no" ]
}

device_abi() {
  local abi
  abi=$(getprop ro.product.cpu.abi 2>/dev/null)
  case "$abi" in
    arm64-v8a|armeabi-v7a|x86|x86_64)
      echo "$abi"
      ;;
    *)
      echo "unknown"
      ;;
  esac
}

current_gadget_library() {
  echo "$GADGET_DIR/$(device_abi)/$GADGET_BASENAME"
}

current_gadget_config() {
  echo "$GADGET_DIR/$(device_abi)/$GADGET_CONFIG_BASENAME"
}

runtime_gadget_library() {
  echo "$RUNTIME_GADGET_DIR/$(device_abi)/$GADGET_BASENAME"
}

runtime_gadget_config() {
  echo "$RUNTIME_GADGET_DIR/$(device_abi)/$GADGET_CONFIG_BASENAME"
}

stage_gadget_runtime() {
  local abi
  local src_dir
  local dst_dir
  local src_so
  local dst_so
  local tmp_so
  local src_config
  local dst_config
  local tmp_config
  abi=$(device_abi)
  src_dir="$GADGET_DIR/$abi"
  dst_dir="$RUNTIME_GADGET_DIR/$abi"
  src_so="$src_dir/$GADGET_BASENAME"
  dst_so="$dst_dir/$GADGET_BASENAME"
  src_config="$src_dir/$GADGET_CONFIG_BASENAME"
  dst_config="$dst_dir/$GADGET_CONFIG_BASENAME"
  tmp_so="$dst_so.tmp.$$"
  tmp_config="$dst_config.tmp.$$"

  [ -f "$src_so" ] || return 0
  mkdir -p "$dst_dir" || return 0
  chmod 0755 "$RUNTIME_DIR" "$RUNTIME_GADGET_DIR" "$dst_dir" 2>/dev/null || true
  chcon u:object_r:apk_data_file:s0 "$RUNTIME_DIR" "$RUNTIME_GADGET_DIR" "$dst_dir" 2>/dev/null || true

  if [ ! -f "$dst_so" ] || ! cmp -s "$src_so" "$dst_so" 2>/dev/null; then
    cp -f "$src_so" "$tmp_so" 2>/dev/null || {
      rm -f "$tmp_so" 2>/dev/null || true
      return 0
    }
    chmod 0755 "$tmp_so" 2>/dev/null || true
    chcon u:object_r:apk_data_file:s0 "$tmp_so" 2>/dev/null || true
    mv -f "$tmp_so" "$dst_so" 2>/dev/null || rm -f "$tmp_so" 2>/dev/null || true
  fi

  if [ -f "$src_config" ]; then
    if [ ! -f "$dst_config" ] || ! cmp -s "$src_config" "$dst_config" 2>/dev/null; then
      cp -f "$src_config" "$tmp_config" 2>/dev/null || true
      if [ -f "$tmp_config" ]; then
        chmod 0644 "$tmp_config" 2>/dev/null || true
        chcon u:object_r:apk_data_file:s0 "$tmp_config" 2>/dev/null || true
        mv -f "$tmp_config" "$dst_config" 2>/dev/null || rm -f "$tmp_config" 2>/dev/null || true
      fi
    fi
  fi
  chmod 0755 "$dst_so" 2>/dev/null || true
  chmod 0644 "$dst_config" 2>/dev/null || true
  chcon u:object_r:apk_data_file:s0 "$dst_so" "$dst_config" 2>/dev/null || true
}

write_config() {
  local tmp="$CONFIG.tmp.$$"
  {
    echo "# Frida Magisk runtime config."
    echo "FRIDA_MODE=$FRIDA_MODE"
    echo "FRIDA_LISTEN=$FRIDA_LISTEN"
    echo "WATCHDOG_INTERVAL=$WATCHDOG_INTERVAL"
    echo "FRIDA_SERVER_BASENAME=$FRIDA_SERVER_BASENAME"
    echo "FRIDA_PID_BASENAME=$FRIDA_PID_BASENAME"
    echo "FRIDA_RUNTIME_DIR=$FRIDA_RUNTIME_DIR"
    echo "GADGET_BASENAME=$GADGET_BASENAME"
    echo "GADGET_CONFIG_BASENAME=$GADGET_CONFIG_BASENAME"
    echo "GADGET_TARGET_PACKAGE=$GADGET_TARGET_PACKAGE"
    echo "GADGET_LISTEN=$GADGET_LISTEN"
    echo "GADGET_ON_LOAD=$GADGET_ON_LOAD"
    echo "GADGET_RUNTIME=$GADGET_RUNTIME"
    echo "GADGET_INCLUDE_CHILDREN=$GADGET_INCLUDE_CHILDREN"
  } > "$tmp"
  mv "$tmp" "$CONFIG"
  chmod 0644 "$CONFIG"
}

gadget_backend_status() {
  local abi
  abi=$(device_abi)
  if [ -f "$MODDIR/zygisk/$abi.so" ] && [ -f "$GADGET_DIR/$abi/$GADGET_BASENAME" ]; then
    echo "internal"
    return 0
  fi
  echo "missing"
}

write_gadget_config() {
  local address="${GADGET_LISTEN%:*}"
  local port="${GADGET_LISTEN##*:}"
  local abi_dir
  local config_path
  local profile_tmp="$GADGET_PROFILE.tmp.$$"
  local config_tmp

  mkdir -p "$GADGET_DIR"
  {
    echo "{"
    echo "  \"target_package\": \"$GADGET_TARGET_PACKAGE\","
    echo "  \"listen\": \"$GADGET_LISTEN\","
    echo "  \"on_load\": \"$GADGET_ON_LOAD\","
    echo "  \"runtime\": \"$GADGET_RUNTIME\","
    echo "  \"include_children\": \"$GADGET_INCLUDE_CHILDREN\","
    echo "  \"backend\": \"$(gadget_backend_status)\""
    echo "}"
  } > "$profile_tmp"
  mv "$profile_tmp" "$GADGET_PROFILE"

  for abi_dir in "$GADGET_DIR"/*; do
    [ -d "$abi_dir" ] || continue
    [ -f "$abi_dir/$GADGET_BASENAME" ] || continue
    config_path="$abi_dir/$GADGET_CONFIG_BASENAME"
    config_tmp="$config_path.tmp.$$"
    {
      echo "{"
      echo "  \"interaction\": {"
      echo "    \"type\": \"listen\","
      echo "    \"address\": \"$address\","
      echo "    \"port\": $port,"
      echo "    \"on_load\": \"$GADGET_ON_LOAD\""
      echo "  },"
      echo "  \"runtime\": \"$GADGET_RUNTIME\""
      echo "}"
    } > "$config_tmp"
    mv "$config_tmp" "$config_path"
    chmod 0644 "$config_path"
  done
  chmod 0644 "$GADGET_PROFILE"
  stage_gadget_runtime
}

set_listen() {
  local listen="$1"
  if ! valid_listen "$listen"; then
    echo "Invalid listen address. Expected IPv4:port with port 1-65535." >&2
    return 2
  fi

  FRIDA_LISTEN="$listen"
  write_config
  ensure_rundir
  rm -f "$MANUAL_STOP"
  stop_watchdog
  stop_frida
  start_frida
  start_watchdog
}

set_mode() {
  local mode="$1"
  if ! valid_mode "$mode"; then
    echo "Invalid mode. Expected server, gadget, or hybrid." >&2
    return 2
  fi

  FRIDA_MODE="$mode"
  write_config
  write_gadget_config
  ensure_rundir

  if [ "$FRIDA_MODE" = "gadget" ]; then
    touch "$MANUAL_STOP"
    stop_watchdog
    stop_frida
    write_state "disabled" "server disabled by gadget mode" "" "0"
    return 0
  fi

  rm -f "$MANUAL_STOP"
  stop_watchdog
  start_frida
  start_watchdog
}

set_gadget() {
  local target="$1"
  local listen="$2"
  local on_load="$3"
  local runtime="$4"
  local include_children="${5:-no}"

  valid_package "$target" || {
    echo "Invalid package name." >&2
    return 2
  }
  valid_listen "$listen" || {
    echo "Invalid Gadget listen address." >&2
    return 2
  }
  valid_on_load "$on_load" || {
    echo "Invalid on_load. Expected wait or resume." >&2
    return 2
  }
  valid_runtime "$runtime" || {
    echo "Invalid runtime. Expected qjs or v8." >&2
    return 2
  }
  valid_yes_no "$include_children" || {
    echo "Invalid include_children. Expected yes or no." >&2
    return 2
  }

  GADGET_TARGET_PACKAGE="$target"
  GADGET_LISTEN="$listen"
  GADGET_ON_LOAD="$on_load"
  GADGET_RUNTIME="$runtime"
  GADGET_INCLUDE_CHILDREN="$include_children"
  write_config
  write_gadget_config
}

clear_gadget() {
  GADGET_TARGET_PACKAGE=
  write_config
  write_gadget_config
}

print_status() {
  local pid
  local health="stopped"
  pid=$(find_frida_pid)
  if [ -n "$pid" ]; then
    health="running"
  fi

  echo "== Frida Magisk =="
  grep -E '^(id|name|version|versionCode|description)=' "$MODDIR/module.prop" 2>/dev/null
  echo
  echo "Module dir: $MODDIR"
  echo "Binary: $BIN"
  echo "Mode: $FRIDA_MODE"
  echo "Listen: $FRIDA_LISTEN"
  echo "Device ABI: $(device_abi)"
  echo "Gadget target: ${GADGET_TARGET_PACKAGE:-none}"
  echo "Gadget listen: $GADGET_LISTEN"
  echo "Gadget include children: $GADGET_INCLUDE_CHILDREN"
  echo "Gadget backend: $(gadget_backend_status)"
  echo "Gadget library: $(current_gadget_library)"
  echo "Gadget config: $(current_gadget_config)"
  echo "Runtime Gadget library: $(runtime_gadget_library)"
  echo "Runtime Gadget config: $(runtime_gadget_config)"
  echo "Watchdog interval: ${WATCHDOG_INTERVAL}s"
  echo "Watchdog: $(watchdog_alive && echo running || echo stopped)"
  echo "Manual stop: $([ -f "$MANUAL_STOP" ] && echo yes || echo no)"
  echo "Health: $health"
  echo "PID: ${pid:-none}"
  if [ -n "$pid" ]; then
    echo "Cmdline: $(pid_cmdline "$pid")"
  fi
  echo
  echo "Last state:"
  if [ -f "$STATE" ]; then
    cat "$STATE"
  else
    echo "none"
  fi
}

print_web_status() {
  local pid
  local health="stopped"
  local watchdog="stopped"
  local manual_stop="no"
  local version="unknown"
  local version_code="unknown"
  local message=""
  local restarts="0"
  local updated_text="none"

  pid=$(find_frida_pid)
  [ -n "$pid" ] && health="running"
  watchdog_alive && watchdog="running"
  [ -f "$MANUAL_STOP" ] && manual_stop="yes"
  if [ -f "$STATE" ]; then
    message=$(sed -n 's/^MESSAGE=//p' "$STATE")
    restarts=$(sed -n 's/^RESTARTS=//p' "$STATE")
    updated_text=$(sed -n 's/^UPDATED_TEXT=//p' "$STATE")
  fi
  version=$(sed -n 's/^version=//p' "$MODDIR/module.prop" 2>/dev/null)
  version_code=$(sed -n 's/^versionCode=//p' "$MODDIR/module.prop" 2>/dev/null)

  echo "HEALTH=$health"
  echo "PID=${pid:-none}"
  echo "LISTEN=$FRIDA_LISTEN"
  echo "MODE=$FRIDA_MODE"
  echo "WATCHDOG=$watchdog"
  echo "WATCHDOG_INTERVAL=$WATCHDOG_INTERVAL"
  echo "MANUAL_STOP=$manual_stop"
  echo "VERSION=${version:-unknown}"
  echo "VERSION_CODE=${version_code:-unknown}"
  echo "RESTARTS=$restarts"
  echo "MESSAGE=$message"
  echo "UPDATED_TEXT=$updated_text"
  echo "GADGET_TARGET_PACKAGE=$GADGET_TARGET_PACKAGE"
  echo "GADGET_LISTEN=$GADGET_LISTEN"
  echo "GADGET_ON_LOAD=$GADGET_ON_LOAD"
  echo "GADGET_RUNTIME=$GADGET_RUNTIME"
  echo "GADGET_INCLUDE_CHILDREN=$GADGET_INCLUDE_CHILDREN"
  echo "GADGET_BACKEND=$(gadget_backend_status)"
  echo "GADGET_ABI=$(device_abi)"
  echo "GADGET_LIBRARY=$(current_gadget_library)"
  echo "GADGET_PROFILE=$GADGET_PROFILE"
  echo "GADGET_CONFIG=$(current_gadget_config)"
  echo "GADGET_RUNTIME_LIBRARY=$(runtime_gadget_library)"
  echo "GADGET_RUNTIME_CONFIG=$(runtime_gadget_config)"
}

print_packages() {
  local query="${1:-}"
  local limit="${2:-100}"
  local count=0
  local package

  case "$limit" in
    ''|*[!0-9]*)
      limit=100
      ;;
  esac
  [ "$limit" -gt 0 ] 2>/dev/null || limit=100

  pm list packages 2>/dev/null | sed 's/^package://' | while IFS= read -r package; do
    if [ -n "$query" ] && ! echo "$package" | grep -qi -- "$query"; then
      continue
    fi
    echo "PACKAGE=$package"
    count=$((count + 1))
    [ "$count" -ge "$limit" ] && break
  done
}

interactive_action() {
  print_status
  echo
  echo "Actions: [s]tart  [r]estart  s[t]op  [q]uit"
  printf "Select action: "
  if read -r -t 20 choice; then
    case "$choice" in
      s|S)
        rm -f "$MANUAL_STOP"
        start_watchdog
        start_frida
        ;;
      r|R)
        rm -f "$MANUAL_STOP"
        stop_frida
        start_watchdog
        start_frida
        ;;
      t|T)
        ensure_rundir
        touch "$MANUAL_STOP"
        stop_frida
        ;;
      *)
        echo "No action."
        ;;
    esac
  else
    echo
    echo "No action."
  fi
  echo
  print_status
}

case "$1" in
  daemon)
    daemon_loop
    ;;
  status)
    print_status
    ;;
  web-status)
    print_web_status
    ;;
  packages)
    print_packages "$2" "$3"
    ;;
  start)
    ensure_rundir
    rm -f "$MANUAL_STOP"
    start_watchdog
    start_frida
    ;;
  stop)
    ensure_rundir
    touch "$MANUAL_STOP"
    stop_frida
    ;;
  restart)
    ensure_rundir
    rm -f "$MANUAL_STOP"
    stop_frida
    start_watchdog
    start_frida
    ;;
  set-listen)
    set_listen "$2"
    ;;
  set-mode)
    set_mode "$2"
    ;;
  set-gadget)
    set_gadget "$2" "${3:-$GADGET_LISTEN}" "${4:-$GADGET_ON_LOAD}" "${5:-$GADGET_RUNTIME}" "${6:-$GADGET_INCLUDE_CHILDREN}"
    ;;
  clear-gadget)
    clear_gadget
    ;;
  watchdog-stop)
    stop_watchdog
    ;;
  *)
    interactive_action
    ;;
esac
