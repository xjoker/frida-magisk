const MODULE_DIR = "/data/adb/modules/frida_magisk";
const ACTION = `sh ${MODULE_DIR}/action.sh`;
const AUTO_REFRESH_MS = 3000;
const MAX_PACKAGE_OPTIONS = 500;
const LANGUAGE_KEY = "frida-magisk-language";
const DEFAULT_LANGUAGE = "en";

const translations = {
  en: {
    autoRefreshOn: "Auto refresh: on",
    autoRefreshPaused: "Auto refresh: paused",
    languageLabel: "Language",
    refreshStatus: "Refresh status",
    runningStatus: "Running Status",
    healthCheck: "Service Health",
    checking: "Checking",
    currentMode: "Current Mode",
    restartCount: "Restart Count",
    gadgetBackend: "Gadget Backend",
    deviceAbi: "Device ABI",
    serviceActions: "Service actions",
    loading: "Loading",
    checkingServerDetail: "Checking frida-server and watchdog status",
    startService: "Start Service",
    stopService: "Stop Service",
    restart: "Restart",
    modeSwitch: "Mode Switch",
    runtimeMode: "Runtime mode",
    modeServer: "Server",
    modeServerLabel: "Server",
    modeHybrid: "Hybrid",
    modeHybridLabel: "Hybrid",
    gadgetMissingWarning: "The current ABI does not have a bundled Gadget backend. Regular frida-server still works in hybrid mode, but Zygisk Gadget injection will not take effect.",
    modeHint: "Hybrid mode keeps regular frida-server available and enables the bundled Zygisk native injector. Gadget mode stops regular frida-server and relies only on the Gadget listen endpoint.",
    basicInfo: "Basic Info",
    moduleConnection: "Module And Connection",
    moduleVersion: "Module Version",
    listenAddress: "Listen Address",
    checkInterval: "Check Interval",
    lastStatus: "Last Status",
    updatedAt: "Updated At",
    connectionSettings: "Connection Settings",
    commonMode: "Preset",
    presetUsb: "USB direct · 127.0.0.1:27042",
    presetForward: "ADB forward · 127.0.0.1:65000",
    presetLan: "LAN · 0.0.0.0:65000",
    custom: "Custom",
    ipv4Port: "IPv4:port",
    listenHint: "Saving restarts frida-server immediately. LAN mode exposes the debugging port to the same network.",
    saveListen: "Save Listen Address",
    gadgetConfig: "Gadget Config",
    targetInjection: "Target Injection",
    targetPackage: "Target Package",
    installedApps: "Installed Apps",
    loadPackagesFirst: "Load package list first",
    loadList: "Load List",
    gadgetListen: "Gadget Listen Address",
    onLoad: "On Load",
    runtime: "Runtime",
    gadgetHint: "This writes Frida Gadget config for every bundled ABI. Restart the target app process after changing the target package to trigger early injection.",
    saveGadget: "Save Gadget Config",
    healthRunning: "Healthy",
    healthStopped: "Stopped",
    running: "Running",
    stopped: "Stopped",
    serverStarted: "frida-server is running",
    serverStopped: "frida-server is stopped",
    gadgetModeDetail: "Regular frida-server stays stopped in Gadget mode",
    runningWithWatchdog: "Listening on {listen}; watchdog is active",
    runningWithoutWatchdog: "Listening on {listen}; watchdog is not running",
    manualStopDetail: "Stopped manually. Starting service restores watchdog supervision.",
    noServerProcess: "No frida-server process detected",
    internalBackend: "Bundled injector",
    missingBackend: "Missing",
    unknown: "unknown",
    none: "none",
    seconds: "{value} seconds",
    noMessage: "None",
    gadgetMissingFeedback: "Current ABI is missing the bundled Gadget backend. Settings will be saved, but early injection will not take effect.",
    commandFailed: "Command failed: {code}",
    refreshReading: "Reading service status...",
    refreshDone: "Status refreshed",
    readFailed: "Read failed",
    actionRunning: "{label}...",
    actionDone: "{label} completed",
    saveRestart: "Save and restart",
    switchMode: "Switch to {mode}",
    clearGadget: "Clear Gadget target",
    invalidListen: "Listen address must be IPv4:port",
    invalidPackage: "Target package may contain only letters, numbers, underscores, dots, and hyphens",
    invalidGadgetListen: "Gadget listen address must be IPv4:port",
    loadingPackages: "Reading installed package list...",
    packagesLoaded: "Loaded {count} package names",
    selectPackage: "Select package",
    selectPackageLimited: "Select package (showing first {count})",
    localPreview: "Local preview data",
  },
  "zh-CN": {
    autoRefreshOn: "自动刷新：开启",
    autoRefreshPaused: "自动刷新：暂停",
    languageLabel: "语言",
    refreshStatus: "刷新状态",
    runningStatus: "运行状态",
    healthCheck: "服务健康检查",
    checking: "检查中",
    currentMode: "当前模式",
    restartCount: "自动重启次数",
    gadgetBackend: "Gadget 后端",
    deviceAbi: "设备 ABI",
    serviceActions: "服务操作",
    loading: "读取中",
    checkingServerDetail: "正在检查 frida-server 和 watchdog 状态",
    startService: "开启服务",
    stopService: "关闭服务",
    restart: "重启",
    modeSwitch: "模式切换",
    runtimeMode: "运行模式",
    modeServer: "普通 Server",
    modeServerLabel: "普通 Server",
    modeHybrid: "混合",
    modeHybridLabel: "混合",
    gadgetMissingWarning: "当前 ABI 缺少内置 Gadget 后端；混合模式下普通 frida-server 仍会运行，Zygisk Gadget 注入暂不生效。",
    modeHint: "混合模式会保持普通 frida-server 可用，并启用内置 Zygisk native injector。纯 Gadget 模式会停止普通 frida-server，只依赖 Gadget 监听入口。",
    basicInfo: "基础信息",
    moduleConnection: "模块与连接",
    moduleVersion: "模块版本",
    listenAddress: "监听地址",
    checkInterval: "检查间隔",
    lastStatus: "最近状态",
    updatedAt: "更新时间",
    connectionSettings: "连接设置",
    commonMode: "常用模式",
    presetUsb: "USB 直连 · 127.0.0.1:27042",
    presetForward: "ADB 转发 · 127.0.0.1:65000",
    presetLan: "局域网 · 0.0.0.0:65000",
    custom: "自定义",
    ipv4Port: "IPv4:端口",
    listenHint: "保存后会立即重启 frida-server。局域网模式会把调试端口暴露给同一网络。",
    saveListen: "保存监听地址",
    gadgetConfig: "Gadget 配置",
    targetInjection: "目标注入配置",
    targetPackage: "目标包名",
    installedApps: "已安装应用",
    loadPackagesFirst: "先读取应用列表",
    loadList: "读取列表",
    gadgetListen: "Gadget 监听地址",
    onLoad: "加载策略",
    runtime: "运行时",
    gadgetHint: "这里会为每个已内置 ABI 写入 Frida Gadget 配置；修改目标包名后，需要重启目标 App 进程才会触发早期注入。",
    saveGadget: "保存 Gadget 配置",
    healthRunning: "运行正常",
    healthStopped: "服务已停止",
    running: "运行中",
    stopped: "已停止",
    serverStarted: "frida-server 已开启",
    serverStopped: "frida-server 已关闭",
    gadgetModeDetail: "Gadget 模式下普通 frida-server 会保持关闭",
    runningWithWatchdog: "监听 {listen}，watchdog 正在守护",
    runningWithoutWatchdog: "监听 {listen}，watchdog 未运行",
    manualStopDetail: "已手动关闭，开启后会恢复 watchdog 守护",
    noServerProcess: "未检测到 frida-server 进程",
    internalBackend: "内置注入器",
    missingBackend: "未安装",
    unknown: "未知",
    none: "无",
    seconds: "{value} 秒",
    noMessage: "无",
    gadgetMissingFeedback: "当前 ABI 缺少内置 Gadget 后端：配置会保存，但早期注入不会生效。",
    commandFailed: "命令失败: {code}",
    refreshReading: "正在读取服务状态...",
    refreshDone: "状态已刷新",
    readFailed: "读取失败",
    actionRunning: "{label}中...",
    actionDone: "{label}完成",
    saveRestart: "保存并重启",
    switchMode: "切换到{mode}",
    clearGadget: "清空 Gadget 目标",
    invalidListen: "监听地址格式必须是 IPv4:端口",
    invalidPackage: "目标包名只能包含字母、数字、下划线、点和短横线",
    invalidGadgetListen: "Gadget 监听地址格式必须是 IPv4:端口",
    loadingPackages: "正在读取已安装应用列表...",
    packagesLoaded: "已读取 {count} 个包名",
    selectPackage: "选择包名",
    selectPackageLimited: "选择包名（显示前 {count} 个）",
    localPreview: "本地预览数据",
  },
};

let language = loadLanguage();
let currentStatus = {};
let refreshInFlight = false;
let actionInFlight = false;
let packageList = [];

const elements = {
  language: document.querySelector("#language"),
  refresh: document.querySelector("#refresh"),
  autoRefresh: document.querySelector("#auto-refresh"),
  serviceToggle: document.querySelector("#service-toggle"),
  restart: document.querySelector("#restart"),
  modeButtons: Array.from(document.querySelectorAll(".mode-button")),
  listenPreset: document.querySelector("#listen-preset"),
  listenInput: document.querySelector("#listen-input"),
  saveListen: document.querySelector("#save-listen"),
  gadgetPackage: document.querySelector("#gadget-package"),
  packageSelect: document.querySelector("#package-select"),
  loadPackages: document.querySelector("#load-packages"),
  gadgetListen: document.querySelector("#gadget-listen"),
  gadgetOnLoad: document.querySelector("#gadget-on-load"),
  gadgetRuntime: document.querySelector("#gadget-runtime"),
  saveGadget: document.querySelector("#save-gadget"),
  healthBadge: document.querySelector("#health-badge"),
  modeStatus: document.querySelector("#mode-status"),
  serverStatus: document.querySelector("#server-status"),
  serverDot: document.querySelector("#server-dot"),
  serverStateTitle: document.querySelector("#server-state-title"),
  serverStateDetail: document.querySelector("#server-state-detail"),
  watchdogStatus: document.querySelector("#watchdog-status"),
  gadgetBackend: document.querySelector("#gadget-backend"),
  gadgetAbi: document.querySelector("#gadget-abi"),
  gadgetWarning: document.querySelector("#gadget-warning"),
  pid: document.querySelector("#pid"),
  restarts: document.querySelector("#restarts"),
  version: document.querySelector("#version"),
  listen: document.querySelector("#listen"),
  interval: document.querySelector("#interval"),
  message: document.querySelector("#message"),
  updated: document.querySelector("#updated"),
  gadgetProfile: document.querySelector("#gadget-profile"),
  gadgetConfig: document.querySelector("#gadget-config"),
  feedback: document.querySelector("#feedback"),
};

function loadLanguage() {
  try {
    const stored = localStorage.getItem(LANGUAGE_KEY);
    return translations[stored] ? stored : DEFAULT_LANGUAGE;
  } catch (_) {
    return DEFAULT_LANGUAGE;
  }
}

function saveLanguage(value) {
  try {
    localStorage.setItem(LANGUAGE_KEY, value);
  } catch (_) {
    // Ignore storage errors in restricted WebUI containers.
  }
}

function t(key, values = {}) {
  let value = translations[language]?.[key] ?? translations.en[key] ?? key;
  for (const [name, replacement] of Object.entries(values)) {
    value = value.replaceAll(`{${name}}`, String(replacement));
  }
  return value;
}

function applyTranslations(options = {}) {
  const rerender = options.rerender !== false;
  document.documentElement.lang = language;
  elements.language.value = language;

  for (const element of document.querySelectorAll("[data-i18n]")) {
    element.textContent = t(element.dataset.i18n);
  }
  for (const element of document.querySelectorAll("[data-i18n-title]")) {
    element.title = t(element.dataset.i18nTitle);
  }
  for (const element of document.querySelectorAll("[data-i18n-aria]")) {
    element.setAttribute("aria-label", t(element.dataset.i18nAria));
  }

  if (packageList.length > 0) {
    renderPackageOptions(packageList);
  }
  if (rerender && Object.keys(currentStatus).length > 0) {
    render(currentStatus);
  }
  updateAutoRefreshText();
}

function setLanguage(value) {
  if (!translations[value]) return;
  language = value;
  saveLanguage(value);
  applyTranslations();
}

function parseKeyValues(text) {
  return Object.fromEntries(
    String(text)
      .split("\n")
      .map(line => line.trim())
      .filter(line => line.includes("="))
      .map(line => {
        const index = line.indexOf("=");
        return [line.slice(0, index), line.slice(index + 1)];
      }),
  );
}

function parsePackages(text) {
  return String(text)
    .split("\n")
    .map(line => line.trim())
    .filter(line => line.startsWith("PACKAGE="))
    .map(line => line.slice("PACKAGE=".length))
    .filter(value => /^[A-Za-z0-9_.-]+$/.test(value))
    .sort((left, right) => left.localeCompare(right));
}

function canUpdateField(element) {
  return document.activeElement !== element;
}

function exec(command) {
  if (window.ksu?.exec) {
    return new Promise((resolve, reject) => {
      const callback = `frida_magisk_${Date.now()}_${Math.random().toString(16).slice(2)}`;
      window[callback] = (errno, stdout, stderr) => {
        delete window[callback];
        errno === 0 ? resolve({ stdout, stderr }) : reject(new Error(stderr || t("commandFailed", { code: errno })));
      };
      try {
        window.ksu.exec(command, "{}", callback);
      } catch (error) {
        delete window[callback];
        reject(error);
      }
    });
  }

  return Promise.resolve({
    stdout: [
      "HEALTH=running",
      "MODE=hybrid",
      "PID=2791",
      "LISTEN=127.0.0.1:27042",
      "WATCHDOG=running",
      "WATCHDOG_INTERVAL=5",
      "MANUAL_STOP=no",
      "VERSION=17.9.1",
      "VERSION_CODE=170901",
      "RESTARTS=0",
      `MESSAGE=${t("localPreview")}`,
      "UPDATED_TEXT=2026-06-10 16:12:00",
      "GADGET_TARGET_PACKAGE=com.example.app",
      "GADGET_LISTEN=127.0.0.1:27043",
      "GADGET_ON_LOAD=wait",
      "GADGET_RUNTIME=qjs",
      "GADGET_BACKEND=internal",
      "GADGET_ABI=arm64-v8a",
      "GADGET_PROFILE=/data/adb/modules/frida_magisk/gadget/profile.json",
      "GADGET_CONFIG=/data/adb/modules/frida_magisk/gadget/arm64-v8a/libfrida-gadget.config.so",
    ].join("\n"),
    stderr: "",
  });
}

function setBusy(busy) {
  for (const button of [
    elements.refresh,
    elements.serviceToggle,
    elements.restart,
    elements.saveListen,
    elements.saveGadget,
    elements.loadPackages,
    ...elements.modeButtons,
  ]) {
    button.disabled = busy;
  }
  elements.listenPreset.disabled = busy;
  elements.listenInput.disabled = busy;
  elements.gadgetPackage.disabled = busy;
  elements.packageSelect.disabled = busy;
  elements.gadgetListen.disabled = busy;
  elements.gadgetOnLoad.disabled = busy;
  elements.gadgetRuntime.disabled = busy;
  if (!busy) {
    applyControlState(currentStatus);
  }
}

function render(status) {
  currentStatus = status;
  const mode = status.MODE || "server";
  const running = status.HEALTH === "running";
  const gadgetReady = status.GADGET_BACKEND === "internal";
  const watchdogRunning = status.WATCHDOG === "running";

  elements.healthBadge.textContent = running ? t("healthRunning") : t("healthStopped");
  elements.healthBadge.className = `badge ${running ? "ok" : "error"}`;
  elements.modeStatus.textContent = modeLabel(mode);
  elements.serverStatus.textContent = running ? t("running") : t("stopped");
  elements.serverDot.className = `state-dot ${running ? "running" : "stopped"}`;
  elements.serverStateTitle.textContent = running ? t("serverStarted") : t("serverStopped");
  elements.serverStateDetail.textContent = serviceDetail(status, running, watchdogRunning, mode);
  elements.serviceToggle.textContent = running ? t("stopService") : t("startService");
  elements.serviceToggle.className = running ? "danger" : "primary";
  applyControlState(status);
  elements.watchdogStatus.textContent = watchdogRunning ? t("running") : t("stopped");
  elements.gadgetBackend.textContent = gadgetBackendLabel(status.GADGET_BACKEND);
  elements.gadgetBackend.className = status.GADGET_BACKEND === "missing" ? "status-warning" : "";
  elements.gadgetAbi.textContent = status.GADGET_ABI || t("unknown");
  elements.gadgetWarning.hidden = status.GADGET_BACKEND !== "missing";
  elements.pid.textContent = status.PID || t("none");
  elements.restarts.textContent = status.RESTARTS || "0";
  elements.version.textContent = `${status.VERSION || t("unknown")} (${status.VERSION_CODE || t("unknown")})`;
  elements.listen.textContent = status.LISTEN || t("unknown");
  elements.interval.textContent = t("seconds", { value: status.WATCHDOG_INTERVAL || t("unknown") });
  elements.message.textContent = status.MESSAGE || t("noMessage");
  elements.updated.textContent = status.UPDATED_TEXT || t("none");
  if (canUpdateField(elements.gadgetPackage)) {
    elements.gadgetPackage.value = status.GADGET_TARGET_PACKAGE || "";
  }
  if (canUpdateField(elements.gadgetListen)) {
    elements.gadgetListen.value = status.GADGET_LISTEN || "127.0.0.1:27043";
  }
  if (canUpdateField(elements.gadgetOnLoad)) {
    elements.gadgetOnLoad.value = status.GADGET_ON_LOAD || "wait";
  }
  if (canUpdateField(elements.gadgetRuntime)) {
    elements.gadgetRuntime.value = status.GADGET_RUNTIME || "qjs";
  }
  elements.gadgetProfile.textContent = status.GADGET_PROFILE || "-";
  elements.gadgetConfig.textContent = status.GADGET_CONFIG || "-";
  if (canUpdateField(elements.listenInput)) {
    elements.listenInput.value = status.LISTEN || "127.0.0.1:27042";
  }
  const preset = Array.from(elements.listenPreset.options).some(option => option.value === status.LISTEN)
    ? status.LISTEN
    : "custom";
  if (canUpdateField(elements.listenPreset)) {
    elements.listenPreset.value = preset;
  }
  if (packageList.length > 0 && canUpdateField(elements.packageSelect)) {
    elements.packageSelect.value = elements.gadgetPackage.value;
  }
  for (const button of elements.modeButtons) {
    button.classList.toggle("active", button.dataset.mode === mode);
  }
  if (mode !== "server" && !gadgetReady) {
    elements.feedback.textContent = t("gadgetMissingFeedback");
  }
}

function applyControlState(status) {
  elements.restart.disabled = status.HEALTH !== "running" || status.MODE === "gadget";
}

function serviceDetail(status, running, watchdogRunning, mode) {
  if (mode === "gadget") {
    return t("gadgetModeDetail");
  }
  if (running && watchdogRunning) {
    return t("runningWithWatchdog", { listen: status.LISTEN || t("unknown") });
  }
  if (running) {
    return t("runningWithoutWatchdog", { listen: status.LISTEN || t("unknown") });
  }
  if (status.MANUAL_STOP === "yes") {
    return t("manualStopDetail");
  }
  return t("noServerProcess");
}

function modeLabel(mode) {
  return {
    server: t("modeServerLabel"),
    gadget: "Gadget",
    hybrid: t("modeHybridLabel"),
  }[mode] || mode;
}

function gadgetBackendLabel(value) {
  return {
    internal: t("internalBackend"),
    missing: t("missingBackend"),
  }[value] || t("unknown");
}

async function refreshStatus(feedback = "", options = {}) {
  const quiet = options.quiet === true;
  if (quiet && (refreshInFlight || actionInFlight)) {
    return;
  }
  refreshInFlight = true;
  if (!quiet) {
    setBusy(true);
    elements.feedback.textContent = feedback || t("refreshReading");
  }
  try {
    const result = await exec(`${ACTION} web-status`);
    render(parseKeyValues(result.stdout));
    if (!quiet) {
      elements.feedback.textContent = feedback || t("refreshDone");
    }
  } catch (error) {
    if (!quiet) {
      elements.healthBadge.textContent = t("readFailed");
      elements.healthBadge.className = "badge error";
      elements.feedback.textContent = String(error.message || error);
    }
  } finally {
    refreshInFlight = false;
    if (!quiet) {
      setBusy(false);
    }
  }
}

async function runAction(action, label) {
  actionInFlight = true;
  setBusy(true);
  elements.feedback.textContent = t("actionRunning", { label });
  try {
    await exec(`${ACTION} ${action}`);
    await new Promise(resolve => setTimeout(resolve, 900));
    await refreshStatus(t("actionDone", { label }));
  } catch (error) {
    elements.feedback.textContent = String(error.message || error);
    setBusy(false);
  } finally {
    actionInFlight = false;
  }
}

async function saveListen() {
  const listen = elements.listenInput.value.trim();
  if (!/^(\d{1,3}\.){3}\d{1,3}:\d{1,5}$/.test(listen)) {
    elements.feedback.textContent = t("invalidListen");
    return;
  }
  await runAction(`set-listen ${listen}`, t("saveRestart"));
}

async function setMode(mode) {
  await runAction(`set-mode ${mode}`, t("switchMode", { mode: modeLabel(mode) }));
}

async function toggleService() {
  const running = currentStatus.HEALTH === "running";
  await runAction(running ? "stop" : "start", running ? t("stopService") : t("startService"));
}

async function saveGadget() {
  const target = elements.gadgetPackage.value.trim();
  const listen = elements.gadgetListen.value.trim();
  const onLoad = elements.gadgetOnLoad.value;
  const runtime = elements.gadgetRuntime.value;

  if (target === "") {
    await runAction("clear-gadget", t("clearGadget"));
    return;
  }
  if (!/^[A-Za-z0-9_.-]+$/.test(target)) {
    elements.feedback.textContent = t("invalidPackage");
    return;
  }
  if (!/^(\d{1,3}\.){3}\d{1,3}:\d{1,5}$/.test(listen)) {
    elements.feedback.textContent = t("invalidGadgetListen");
    return;
  }
  await runAction(`set-gadget ${target} ${listen} ${onLoad} ${runtime}`, t("saveGadget"));
}

async function loadPackages() {
  actionInFlight = true;
  setBusy(true);
  elements.feedback.textContent = t("loadingPackages");
  try {
    const result = await exec(`${ACTION} packages`);
    packageList = parsePackages(result.stdout);
    renderPackageOptions(packageList);
    elements.feedback.textContent = t("packagesLoaded", { count: packageList.length });
  } catch (error) {
    elements.feedback.textContent = String(error.message || error);
  } finally {
    actionInFlight = false;
    setBusy(false);
  }
}

function renderPackageOptions(packages) {
  const selected = elements.gadgetPackage.value.trim();
  const visiblePackages = packages.slice(0, MAX_PACKAGE_OPTIONS);
  elements.packageSelect.replaceChildren();

  const placeholder = document.createElement("option");
  placeholder.value = "";
  placeholder.textContent = packages.length > MAX_PACKAGE_OPTIONS
    ? t("selectPackageLimited", { count: MAX_PACKAGE_OPTIONS })
    : t("selectPackage");
  elements.packageSelect.appendChild(placeholder);

  for (const packageName of visiblePackages) {
    const option = document.createElement("option");
    option.value = packageName;
    option.textContent = packageName;
    option.selected = packageName === selected;
    elements.packageSelect.appendChild(option);
  }
}

function updateAutoRefreshText() {
  const visible = document.visibilityState === "visible";
  elements.autoRefresh.textContent = visible ? t("autoRefreshOn") : t("autoRefreshPaused");
}

elements.language.addEventListener("change", () => setLanguage(elements.language.value));
elements.refresh.addEventListener("click", () => refreshStatus());
elements.serviceToggle.addEventListener("click", toggleService);
elements.restart.addEventListener("click", () => runAction("restart", t("restart")));
for (const button of elements.modeButtons) {
  button.addEventListener("click", () => setMode(button.dataset.mode));
}
elements.listenPreset.addEventListener("change", () => {
  if (elements.listenPreset.value !== "custom") {
    elements.listenInput.value = elements.listenPreset.value;
  }
});
elements.loadPackages.addEventListener("click", loadPackages);
elements.packageSelect.addEventListener("change", () => {
  if (elements.packageSelect.value) {
    elements.gadgetPackage.value = elements.packageSelect.value;
  }
});
elements.saveListen.addEventListener("click", saveListen);
elements.saveGadget.addEventListener("click", saveGadget);
document.addEventListener("visibilitychange", () => {
  updateAutoRefreshText();
  if (document.visibilityState === "visible") {
    refreshStatus("", { quiet: true });
  }
});

applyTranslations({ rerender: false });
refreshStatus();
setInterval(() => {
  if (document.visibilityState === "visible") {
    refreshStatus("", { quiet: true });
  }
}, AUTO_REFRESH_MS);
