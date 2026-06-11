# AGENTS.md

本仓库是独立的 Frida Magisk / KernelSU 模块项目。

## 基本规则

- 主要使用简体中文沟通和写说明。
- 不提交 Frida server、Frida Gadget、Zygisk injector 等构建产物。
- 不硬编码设备序列号、token、私有服务地址或调试代理。
- 多设备场景下所有 ADB 命令必须显式使用 `adb -s <serial>`。
- 修改模块行为前先确认目标 Android ABI、Root 管理器类型和安装模块 ID。

## 项目结构

- `module/`：Magisk / KernelSU 模块模板。
- `module/native/zygisk/`：自研 Zygisk injector 源码。
- `scripts/fetch-frida-assets.sh`：下载并校验官方 Frida Android server/gadget。
- `scripts/build-zygisk-injector.sh`：构建 4 ABI injector。
- `scripts/build-module.sh`：打包模块 ZIP。
- `scripts/build-all.sh`：完整构建入口。
- `.github/workflows/build.yml`：GitHub Actions 自动构建。

## 验证

常用命令：

```bash
scripts/fetch-frida-assets.sh
scripts/build-zygisk-injector.sh
scripts/build-module.sh
```

安装或刷入前必须确认目标设备：

```bash
adb devices
adb -s <serial> shell getprop ro.product.model
adb -s <serial> shell getprop ro.build.version.release
```
