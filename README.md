# frida-magisk

English | [Simplified Chinese](README.zh-CN.md)

Standalone Magisk / KernelSU module for packaging official Frida Android server binaries, official Frida Gadget binaries, and a bundled Zygisk injector into a flashable ZIP.

This README is written to be automation-friendly. An AI agent should be able to build the module, deploy it to a known Android device, and operate the module interface by following the command contracts below.

## Quick Facts

- Module ID: `frida_magisk`
- Installed module path: `/data/adb/modules/frida_magisk`
- Runtime Gadget staging path: `/data/local/tmp/frida_magisk`
- Default server mode: `hybrid`
- Default `frida-server` listen address: `127.0.0.1:27042`
- Default Gadget listen address: `127.0.0.1:27043`
- Supported ABIs: `arm64-v8a`, `armeabi-v7a`, `x86`, `x86_64`
- Main device interface: `sh /data/adb/modules/frida_magisk/action.sh ...`
- WebUI entry: `module/webroot/index.html`, executed by KernelSU / SukiSU through `ksu.exec`

## Repository Layout

```text
module/                         Magisk / KernelSU module template
module/native/zygisk/           Zygisk injector source
module/action.sh                Stable on-device command interface
module/service.sh               late_start service entry
module/customize.sh             install-time setup script
module/webroot/                 KernelSU / SukiSU WebUI
scripts/fetch-frida-assets.sh   Download official Frida Android assets
scripts/build-zygisk-injector.sh Build injector for all supported ABIs
scripts/build-module.sh         Package the flashable ZIP
scripts/build-all.sh            Full build entry
.github/workflows/build.yml     CI, scheduled latest checks, and releases
```

## Build

Full local build:

```bash
scripts/build-all.sh
```

Equivalent explicit steps:

```bash
scripts/fetch-frida-assets.sh
scripts/build-zygisk-injector.sh
scripts/build-module.sh
```

Build a specific Frida version:

```bash
FRIDA_VERSION=17.9.1 scripts/build-all.sh
```

`scripts/build-all.sh` builds the universal package and all per-ABI packages by default. To build only selected package targets:

```bash
MODULE_ABIS="arm64-v8a" scripts/build-all.sh
MODULE_ABIS="universal arm64-v8a" scripts/build-all.sh
```

`scripts/fetch-frida-assets.sh` contains pinned SHA-256 checks for known versions. To build a Frida version that is not pinned locally, opt in explicitly:

```bash
FRIDA_VERSION=18.0.0 FRIDA_ALLOW_UNVERIFIED=1 scripts/build-all.sh
```

Outputs:

```text
dist/frida-magisk-<frida-version>-universal.zip
dist/frida-magisk-<frida-version>-arm64-v8a.zip
dist/frida-magisk-<frida-version>-armeabi-v7a.zip
dist/frida-magisk-<frida-version>-x86.zip
dist/frida-magisk-<frida-version>-x86_64.zip
dist/*.sha256
```

Download guidance:

- Use `arm64-v8a` for most modern Android phones.
- Use `universal` only when the target ABI is unknown or one package must support multiple devices.
- Installing a package for the wrong ABI fails during module installation because `customize.sh` requires a matching `bin/<abi>/frida-server`.

## GitHub Actions And Releases

Workflow: `.github/workflows/build.yml`

Supported triggers:

- `push` to `main` or `master`: builds and uploads workflow artifacts.
- `push` tag `v*`: builds the version from the tag, then creates or updates the matching GitHub Release.
- `workflow_dispatch`: accepts `frida_version`, `allow_unverified`, and `publish_release`.
- `schedule`: runs daily at `00:00 UTC`, checks the latest upstream Frida release, and creates a release only when this repository does not already have `v<latest-version>`.

Manual build examples:

```bash
gh workflow run build.yml -f frida_version=17.9.1 -f allow_unverified=false -f publish_release=false
gh workflow run build.yml -f frida_version=latest -f allow_unverified=true -f publish_release=true
```

Release rule:

- Scheduled latest build publishes `v<frida-version>` automatically if missing.
- Tag build publishes the pushed tag.
- Manual build publishes only when `publish_release=true`.

## Device Deployment

All ADB commands must include `-s <serial>`. Do not use implicit default devices.

Confirm the device first:

```bash
adb devices
adb -s <serial> shell getprop ro.product.model
adb -s <serial> shell getprop ro.build.version.release
adb -s <serial> shell su -c id
```

Install with KernelSU / SukiSU:

```bash
adb -s <serial> push dist/frida-magisk-17.9.1.zip /data/local/tmp/frida-magisk.zip
adb -s <serial> shell su -c '/data/adb/ksud module install /data/local/tmp/frida-magisk.zip'
adb -s <serial> reboot
```

Install with Magisk CLI when available:

```bash
adb -s <serial> push dist/frida-magisk-17.9.1.zip /data/local/tmp/frida-magisk.zip
adb -s <serial> shell su -c 'magisk --install-module /data/local/tmp/frida-magisk.zip'
adb -s <serial> reboot
```

After reboot:

```bash
adb -s <serial> shell su -c 'sh /data/adb/modules/frida_magisk/action.sh status'
adb -s <serial> forward tcp:27042 tcp:27042
frida-ps -H 127.0.0.1:27042
```

## Module Configuration

Runtime config file:

```text
/data/adb/modules/frida_magisk/config.env
```

Default values:

```sh
FRIDA_MODE=hybrid
FRIDA_LISTEN=127.0.0.1:27042
WATCHDOG_INTERVAL=5
GADGET_TARGET_PACKAGE=
GADGET_LISTEN=127.0.0.1:27043
GADGET_ON_LOAD=wait
GADGET_RUNTIME=qjs
GADGET_INCLUDE_CHILDREN=no
```

Modes:

- `server`: run only regular `frida-server`.
- `hybrid`: run regular `frida-server` and allow Gadget injection for the configured target package.
- `gadget`: disable regular `frida-server`; use Gadget only.

## Stable On-Device Interface

Command prefix:

```bash
adb -s <serial> shell su -c 'sh /data/adb/modules/frida_magisk/action.sh <command> [args...]'
```

Supported commands:

```text
status
web-status
packages [query] [limit]
start
stop
restart
set-listen <ipv4:port>
set-mode <server|hybrid|gadget>
set-gadget <package> <ipv4:port> <wait|resume> <qjs|v8> [yes|no]
clear-gadget
watchdog-stop
```

Automation-friendly status:

```bash
adb -s <serial> shell su -c 'sh /data/adb/modules/frida_magisk/action.sh web-status'
```

`web-status` prints `KEY=value` lines. Important keys:

```text
HEALTH=running|stopped
PID=<pid|none>
LISTEN=<ipv4:port>
MODE=server|hybrid|gadget
WATCHDOG=running|stopped
VERSION=<frida-version>
GADGET_TARGET_PACKAGE=<package|empty>
GADGET_LISTEN=<ipv4:port>
GADGET_ON_LOAD=wait|resume
GADGET_RUNTIME=qjs|v8
GADGET_INCLUDE_CHILDREN=yes|no
GADGET_BACKEND=internal|missing
GADGET_ABI=arm64-v8a|armeabi-v7a|x86|x86_64|unknown
```

List installed packages:

```bash
adb -s <serial> shell su -c 'sh /data/adb/modules/frida_magisk/action.sh packages xingin 50'
```

Output format:

```text
PACKAGE=com.example.app
```

Change server listen address:

```bash
adb -s <serial> shell su -c 'sh /data/adb/modules/frida_magisk/action.sh set-listen 127.0.0.1:27042'
```

Switch modes:

```bash
adb -s <serial> shell su -c 'sh /data/adb/modules/frida_magisk/action.sh set-mode server'
adb -s <serial> shell su -c 'sh /data/adb/modules/frida_magisk/action.sh set-mode hybrid'
adb -s <serial> shell su -c 'sh /data/adb/modules/frida_magisk/action.sh set-mode gadget'
```

Configure Gadget for one app:

```bash
adb -s <serial> shell su -c 'sh /data/adb/modules/frida_magisk/action.sh set-gadget com.example.app 127.0.0.1:27043 resume qjs no'
adb -s <serial> forward tcp:27043 tcp:27043
adb -s <serial> shell am force-stop com.example.app
adb -s <serial> shell monkey -p com.example.app 1
frida-ps -H 127.0.0.1:27043
```

Clear Gadget target:

```bash
adb -s <serial> shell su -c 'sh /data/adb/modules/frida_magisk/action.sh clear-gadget'
```

## WebUI Interface

The WebUI is packaged under:

```text
/data/adb/modules/frida_magisk/webroot/
```

KernelSU / SukiSU launches `webroot/index.html`. The page calls the same on-device `action.sh` interface through `ksu.exec`. It does not depend on external web assets. The UI defaults to English and includes a language switcher for Simplified Chinese.

## Safe Operating Procedure For AI Agents

1. Identify exactly one target device with `adb devices`.
2. Confirm model, Android version, and root shell with `adb -s <serial> ...`.
3. Install the module ZIP.
4. Reboot only after the user has allowed the reboot or when the task explicitly requires module activation.
5. After reboot, call `web-status`.
6. Use `set-gadget` only for a regular test application package, not a system process.
7. After Gadget testing, call `clear-gadget` and restore `set-mode hybrid`.

## Safety Notes

- Zygisk injector changes require a device reboot.
- Do not set `GADGET_TARGET_PACKAGE` to a launcher, input method, permission manager, WebView, root manager, payment component, account service, or other core system process.
- `GADGET_ON_LOAD=wait` blocks the target process until a Frida client connects. For smoke tests, use `resume`.
- `GADGET_INCLUDE_CHILDREN=no` is the default to avoid child processes competing for the same Gadget listen port.
- Binding Frida to `0.0.0.0:<port>` exposes the debugging port to the network. Only do this in a trusted, isolated network.
