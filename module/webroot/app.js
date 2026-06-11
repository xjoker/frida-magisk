const MODULE_DIR = "/data/adb/modules/frida_magisk";
const ACTION = `sh ${MODULE_DIR}/action.sh`;
const AUTO_REFRESH_MS = 3000;
const MAX_PACKAGE_OPTIONS = 500;
let currentStatus = {};
let refreshInFlight = false;
let actionInFlight = false;
let packageList = [];

const elements = {
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
        errno === 0 ? resolve({ stdout, stderr }) : reject(new Error(stderr || `命令失败: ${errno}`));
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
      "MESSAGE=本地预览数据",
      "UPDATED_TEXT=2026-06-10 16:12:00",
      "GADGET_TARGET_PACKAGE=com.xingin.xhs",
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
  elements.healthBadge.textContent = running ? "运行正常" : "服务已停止";
  elements.healthBadge.className = `badge ${running ? "ok" : "error"}`;
  elements.modeStatus.textContent = modeLabel(mode);
  elements.serverStatus.textContent = running ? "运行中" : "已停止";
  elements.serverDot.className = `state-dot ${running ? "running" : "stopped"}`;
  elements.serverStateTitle.textContent = running ? "frida-server 已开启" : "frida-server 已关闭";
  elements.serverStateDetail.textContent = serviceDetail(status, running, watchdogRunning, mode);
  elements.serviceToggle.textContent = running ? "关闭服务" : "开启服务";
  elements.serviceToggle.className = running ? "danger" : "primary";
  applyControlState(status);
  elements.watchdogStatus.textContent = watchdogRunning ? "运行中" : "已停止";
  elements.gadgetBackend.textContent = gadgetBackendLabel(status.GADGET_BACKEND);
  elements.gadgetBackend.className = status.GADGET_BACKEND === "missing" ? "status-warning" : "";
  elements.gadgetAbi.textContent = status.GADGET_ABI || "unknown";
  elements.gadgetWarning.hidden = status.GADGET_BACKEND !== "missing";
  elements.pid.textContent = status.PID || "none";
  elements.restarts.textContent = status.RESTARTS || "0";
  elements.version.textContent = `${status.VERSION || "unknown"} (${status.VERSION_CODE || "unknown"})`;
  elements.listen.textContent = status.LISTEN || "unknown";
  elements.interval.textContent = `${status.WATCHDOG_INTERVAL || "unknown"} 秒`;
  elements.message.textContent = status.MESSAGE || "无";
  elements.updated.textContent = status.UPDATED_TEXT || "无";
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
    elements.feedback.textContent = "当前 ABI 缺少内置 Gadget 后端：配置会保存，但早期注入不会生效。";
  }
}

function applyControlState(status) {
  elements.restart.disabled = status.HEALTH !== "running" || status.MODE === "gadget";
}

function serviceDetail(status, running, watchdogRunning, mode) {
  if (mode === "gadget") {
    return "Gadget 模式下普通 frida-server 会保持关闭";
  }
  if (running && watchdogRunning) {
    return `监听 ${status.LISTEN || "unknown"}，watchdog 正在守护`;
  }
  if (running) {
    return `监听 ${status.LISTEN || "unknown"}，watchdog 未运行`;
  }
  if (status.MANUAL_STOP === "yes") {
    return "已手动关闭，开启后会恢复 watchdog 守护";
  }
  return "未检测到 frida-server 进程";
}

function modeLabel(mode) {
  return {
    server: "普通 Server",
    gadget: "Gadget",
    hybrid: "混合",
  }[mode] || mode;
}

function gadgetBackendLabel(value) {
  return {
    internal: "内置注入器",
    missing: "未安装",
  }[value] || "未知";
}

async function refreshStatus(feedback = "", options = {}) {
  const quiet = options.quiet === true;
  if (quiet && (refreshInFlight || actionInFlight)) {
    return;
  }
  refreshInFlight = true;
  if (!quiet) {
    setBusy(true);
    elements.feedback.textContent = feedback || "正在读取服务状态...";
  }
  try {
    const result = await exec(`${ACTION} web-status`);
    render(parseKeyValues(result.stdout));
    if (!quiet) {
      elements.feedback.textContent = feedback || "状态已刷新";
    }
  } catch (error) {
    if (!quiet) {
      elements.healthBadge.textContent = "读取失败";
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
  elements.feedback.textContent = `${label}中...`;
  try {
    await exec(`${ACTION} ${action}`);
    await new Promise(resolve => setTimeout(resolve, 900));
    await refreshStatus(`${label}完成`);
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
    elements.feedback.textContent = "监听地址格式必须是 IPv4:端口";
    return;
  }
  await runAction(`set-listen ${listen}`, "保存并重启");
}

async function setMode(mode) {
  await runAction(`set-mode ${mode}`, `切换到${modeLabel(mode)}`);
}

async function toggleService() {
  const running = elements.serviceToggle.textContent === "关闭服务";
  await runAction(running ? "stop" : "start", running ? "关闭服务" : "开启服务");
}

async function saveGadget() {
  const target = elements.gadgetPackage.value.trim();
  const listen = elements.gadgetListen.value.trim();
  const onLoad = elements.gadgetOnLoad.value;
  const runtime = elements.gadgetRuntime.value;

  if (target === "") {
    await runAction("clear-gadget", "清空 Gadget 目标");
    return;
  }
  if (!/^[A-Za-z0-9_.-]+$/.test(target)) {
    elements.feedback.textContent = "目标包名只能包含字母、数字、下划线、点和短横线";
    return;
  }
  if (!/^(\d{1,3}\.){3}\d{1,3}:\d{1,5}$/.test(listen)) {
    elements.feedback.textContent = "Gadget 监听地址格式必须是 IPv4:端口";
    return;
  }
  await runAction(`set-gadget ${target} ${listen} ${onLoad} ${runtime}`, "保存 Gadget 配置");
}

async function loadPackages() {
  actionInFlight = true;
  setBusy(true);
  elements.feedback.textContent = "正在读取已安装应用列表...";
  try {
    const result = await exec(`${ACTION} packages`);
    packageList = parsePackages(result.stdout);
    renderPackageOptions(packageList);
    elements.feedback.textContent = `已读取 ${packageList.length} 个包名`;
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
    ? `选择包名（显示前 ${MAX_PACKAGE_OPTIONS} 个）`
    : "选择包名";
  elements.packageSelect.appendChild(placeholder);

  for (const packageName of visiblePackages) {
    const option = document.createElement("option");
    option.value = packageName;
    option.textContent = packageName;
    option.selected = packageName === selected;
    elements.packageSelect.appendChild(option);
  }
}

elements.refresh.addEventListener("click", () => refreshStatus());
elements.serviceToggle.addEventListener("click", toggleService);
elements.restart.addEventListener("click", () => runAction("restart", "重启"));
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
  const visible = document.visibilityState === "visible";
  elements.autoRefresh.textContent = visible ? "自动刷新：开启" : "自动刷新：暂停";
  if (visible) {
    refreshStatus("", { quiet: true });
  }
});

refreshStatus();
setInterval(() => {
  if (document.visibilityState === "visible") {
    refreshStatus("", { quiet: true });
  }
}, AUTO_REFRESH_MS);
