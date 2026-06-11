# Frida Magisk Module

这个目录是 Magisk / KernelSU 兼容模块模板。构建脚本会把官方 Frida server、Frida Gadget 和本项目的 Zygisk injector 复制进此模板，再输出可刷入 ZIP。

## 模块 ID

```text
frida_magisk
```

安装后的模块目录：

```text
/data/adb/modules/frida_magisk
```

Gadget 运行时复制目录：

```text
/data/local/tmp/frida_magisk
```

## 默认行为

- 默认模式为 `hybrid`。
- `service.sh` 在 late_start service 阶段启动普通 `frida-server`。
- 守护循环每 5 秒检查一次 `frida-server`，进程退出后自动重启。
- 默认监听 `127.0.0.1:27042`。
- Zygisk injector 只在 `FRIDA_MODE=hybrid|gadget` 且进程名匹配 `GADGET_TARGET_PACKAGE` 时加载 Gadget。

## 配置

安装后配置文件位于：

```text
/data/adb/modules/frida_magisk/config.env
```

默认配置：

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

## Action 命令

```bash
adb -s <serial> shell su -c 'sh /data/adb/modules/frida_magisk/action.sh status'
adb -s <serial> shell su -c 'sh /data/adb/modules/frida_magisk/action.sh restart'
adb -s <serial> shell su -c 'sh /data/adb/modules/frida_magisk/action.sh stop'
adb -s <serial> shell su -c 'sh /data/adb/modules/frida_magisk/action.sh start'
adb -s <serial> shell su -c 'sh /data/adb/modules/frida_magisk/action.sh set-mode hybrid'
adb -s <serial> shell su -c 'sh /data/adb/modules/frida_magisk/action.sh set-gadget com.example.app 127.0.0.1:27043 wait qjs no'
adb -s <serial> shell su -c 'sh /data/adb/modules/frida_magisk/action.sh clear-gadget'
```

## 风险边界

- Zygisk injector 需要重启设备后生效。
- 不要把 Gadget 目标设置为系统桌面、输入法、权限管理器、WebView、root 管理器或其他核心系统进程。
- `GADGET_ON_LOAD=wait` 会阻塞目标进程直到控制端连接；普通验收建议使用 `resume`。
