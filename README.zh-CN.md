# frida-magisk

[English](README.md) | 简体中文

独立的 Magisk / KernelSU 模块项目，用于把官方 Frida Android server、官方 Frida Gadget 和内置 Zygisk injector 打包成可刷入 ZIP。

本文档按自动化和 AI 代理友好的方式编写。AI 读取后应能根据下面的命令契约完成构建、部署到明确设备，以及调用模块接口。

## 快速信息

- 模块 ID：`frida_magisk`
- 安装后的模块目录：`/data/adb/modules/frida_magisk`
- Gadget 运行时暂存目录：`/data/local/tmp/frida_magisk`
- 默认 server 模式：`hybrid`
- 默认 `frida-server` 监听地址：`127.0.0.1:27042`
- 默认 Gadget 监听地址：`127.0.0.1:27043`
- 支持 ABI：`arm64-v8a`、`armeabi-v7a`、`x86`、`x86_64`
- 主要设备侧接口：`sh /data/adb/modules/frida_magisk/action.sh ...`
- WebUI 入口：`module/webroot/index.html`，由 KernelSU / SukiSU 通过 `ksu.exec` 执行

## 仓库结构

```text
module/                         Magisk / KernelSU 模块模板
module/native/zygisk/           Zygisk injector 源码
module/action.sh                稳定设备侧命令接口
module/service.sh               late_start service 入口
module/customize.sh             安装阶段初始化脚本
module/webroot/                 KernelSU / SukiSU WebUI
scripts/fetch-frida-assets.sh   下载官方 Frida Android assets
scripts/build-zygisk-injector.sh 构建所有 ABI 的 injector
scripts/build-module.sh         打包可刷入 ZIP
scripts/build-all.sh            完整构建入口
.github/workflows/build.yml     CI、每日新版本检查和 release 发布
```

## 构建

完整本地构建：

```bash
scripts/build-all.sh
```

等价分步构建：

```bash
scripts/fetch-frida-assets.sh
scripts/build-zygisk-injector.sh
scripts/build-module.sh
```

指定 Frida 版本：

```bash
FRIDA_VERSION=17.9.1 scripts/build-all.sh
```

`scripts/build-all.sh` 默认构建 universal 包和所有 per-ABI 包。只构建指定包类型：

```bash
MODULE_ABIS="arm64-v8a" scripts/build-all.sh
MODULE_ABIS="universal arm64-v8a" scripts/build-all.sh
```

`scripts/fetch-frida-assets.sh` 对已知版本内置 SHA-256 固定校验。构建未固定校验值的 Frida 版本时需要显式允许：

```bash
FRIDA_VERSION=18.0.0 FRIDA_ALLOW_UNVERIFIED=1 scripts/build-all.sh
```

产物：

```text
dist/frida-magisk-<frida-version>-universal.zip
dist/frida-magisk-<frida-version>-arm64-v8a.zip
dist/frida-magisk-<frida-version>-armeabi-v7a.zip
dist/frida-magisk-<frida-version>-x86.zip
dist/frida-magisk-<frida-version>-x86_64.zip
dist/*.sha256
```

下载建议：

- 大多数现代 Android 真机使用 `arm64-v8a`。
- 只有在不确定目标 ABI，或一个包必须支持多台不同 ABI 设备时才下载 `universal`。
- 刷错 ABI 包会在模块安装阶段失败，因为 `customize.sh` 会检查是否存在匹配的 `bin/<abi>/frida-server`。

## GitHub Actions 和 Release

工作流：`.github/workflows/build.yml`

支持的触发方式：

- 推送到 `main` 或 `master`：构建并上传 workflow artifact。
- 推送 `v*` tag：从 tag 解析版本，构建后创建或更新对应 GitHub Release。
- `workflow_dispatch` 手动触发：支持 `frida_version`、`allow_unverified`、`publish_release`。
- `schedule` 每日触发：每天 `00:00 UTC` 检查 Frida 官方最新 release，仅在本仓库没有 `v<最新版本>` release 时构建并发布。

手动构建示例：

```bash
gh workflow run build.yml -f frida_version=17.9.1 -f allow_unverified=false -f publish_release=false
gh workflow run build.yml -f frida_version=latest -f allow_unverified=true -f publish_release=true
```

Release 规则：

- 每日 latest 构建会在缺少 `v<frida-version>` 时自动发布。
- tag 构建发布推送的 tag。
- 手动构建只有在 `publish_release=true` 时发布。

## 设备部署

所有 ADB 命令必须带 `-s <serial>`，禁止依赖默认设备。

先确认设备：

```bash
adb devices
adb -s <serial> shell getprop ro.product.model
adb -s <serial> shell getprop ro.build.version.release
adb -s <serial> shell su -c id
```

通过 KernelSU / SukiSU 安装：

```bash
adb -s <serial> push dist/frida-magisk-17.9.1.zip /data/local/tmp/frida-magisk.zip
adb -s <serial> shell su -c '/data/adb/ksud module install /data/local/tmp/frida-magisk.zip'
adb -s <serial> reboot
```

通过 Magisk CLI 安装：

```bash
adb -s <serial> push dist/frida-magisk-17.9.1.zip /data/local/tmp/frida-magisk.zip
adb -s <serial> shell su -c 'magisk --install-module /data/local/tmp/frida-magisk.zip'
adb -s <serial> reboot
```

重启后检查：

```bash
adb -s <serial> shell su -c 'sh /data/adb/modules/frida_magisk/action.sh status'
adb -s <serial> forward tcp:27042 tcp:27042
frida-ps -H 127.0.0.1:27042
```

## 模块配置

运行时配置文件：

```text
/data/adb/modules/frida_magisk/config.env
```

默认值：

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

模式：

- `server`：只运行普通 `frida-server`。
- `hybrid`：运行普通 `frida-server`，同时允许对指定目标包注入 Gadget。
- `gadget`：关闭普通 `frida-server`，只使用 Gadget。

## 稳定设备侧接口

命令前缀：

```bash
adb -s <serial> shell su -c 'sh /data/adb/modules/frida_magisk/action.sh <command> [args...]'
```

支持的命令：

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

适合自动化解析的状态接口：

```bash
adb -s <serial> shell su -c 'sh /data/adb/modules/frida_magisk/action.sh web-status'
```

`web-status` 输出 `KEY=value` 行。重要字段：

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

列出已安装包：

```bash
adb -s <serial> shell su -c 'sh /data/adb/modules/frida_magisk/action.sh packages xingin 50'
```

输出格式：

```text
PACKAGE=com.example.app
```

修改 server 监听地址：

```bash
adb -s <serial> shell su -c 'sh /data/adb/modules/frida_magisk/action.sh set-listen 127.0.0.1:27042'
```

切换模式：

```bash
adb -s <serial> shell su -c 'sh /data/adb/modules/frida_magisk/action.sh set-mode server'
adb -s <serial> shell su -c 'sh /data/adb/modules/frida_magisk/action.sh set-mode hybrid'
adb -s <serial> shell su -c 'sh /data/adb/modules/frida_magisk/action.sh set-mode gadget'
```

为单个 App 配置 Gadget：

```bash
adb -s <serial> shell su -c 'sh /data/adb/modules/frida_magisk/action.sh set-gadget com.example.app 127.0.0.1:27043 resume qjs no'
adb -s <serial> forward tcp:27043 tcp:27043
adb -s <serial> shell am force-stop com.example.app
adb -s <serial> shell monkey -p com.example.app 1
frida-ps -H 127.0.0.1:27043
```

清空 Gadget 目标：

```bash
adb -s <serial> shell su -c 'sh /data/adb/modules/frida_magisk/action.sh clear-gadget'
```

## WebUI 接口

WebUI 安装路径：

```text
/data/adb/modules/frida_magisk/webroot/
```

KernelSU / SukiSU 会打开 `webroot/index.html`。页面通过 `ksu.exec` 调用同一个设备侧 `action.sh` 接口，不依赖外部在线资源。界面默认英文，并提供简体中文切换。

## AI 代理安全操作流程

1. 用 `adb devices` 确认唯一目标设备。
2. 用 `adb -s <serial> ...` 确认型号、Android 版本和 root shell。
3. 安装模块 ZIP。
4. 只有在用户允许重启或任务明确要求模块生效时才执行 reboot。
5. 重启后先调用 `web-status`。
6. `set-gadget` 只能用于普通测试 App，不要用于系统进程。
7. Gadget 测试结束后调用 `clear-gadget`，并恢复 `set-mode hybrid`。

## 安全边界

- Zygisk injector 变更需要重启设备后生效。
- 不要把 `GADGET_TARGET_PACKAGE` 设置为系统桌面、输入法、权限管理器、WebView、root 管理器、支付组件、账号服务或其他核心系统进程。
- `GADGET_ON_LOAD=wait` 会阻塞目标进程直到 Frida 客户端连接；冒烟测试建议使用 `resume`。
- 默认 `GADGET_INCLUDE_CHILDREN=no`，避免子进程抢占同一个 Gadget 监听端口。
- 把 Frida 监听地址绑定到 `0.0.0.0:<port>` 会向网络暴露调试端口，只应在可信隔离网络中使用。
