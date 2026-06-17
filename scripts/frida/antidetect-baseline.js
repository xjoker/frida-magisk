'use strict';

/*
 * Optional observe-only runtime probe for authorized testing.
 *
 * This script intentionally does not hide or rewrite /proc output by default.
 * Use it to learn which detection surfaces a target actually reads, then keep
 * any target-specific bypass logic outside default module behavior.
 */

const state = {
  enabled: false,
  targetPackage: '',
  allowGlobal: false,
  observeProc: false,
  observeLoads: true,
  logBacktrace: false,
};

const installed = {
  proc: false,
  loads: false,
};

function log(event, fields) {
  const body = Object.assign({ event, pid: Process.id }, fields || {});
  send(body);
}

function readCString(pointerValue) {
  if (pointerValue.isNull()) return '';
  try {
    return pointerValue.readCString() || '';
  } catch (_) {
    return '';
  }
}

function currentPackageName() {
  if (!Java.available) return '';
  let packageName = '';
  Java.perform(function () {
    try {
      const ActivityThread = Java.use('android.app.ActivityThread');
      const app = ActivityThread.currentApplication();
      if (app) packageName = app.getPackageName();
    } catch (_) {
      packageName = '';
    }
  });
  return packageName;
}

function shouldRunForCurrentProcess() {
  if (!state.enabled) return false;
  if (!state.targetPackage) return state.allowGlobal === true;
  return currentPackageName() === state.targetPackage;
}

function maybeBacktrace(context) {
  if (!state.logBacktrace) return undefined;
  try {
    return Thread.backtrace(context, Backtracer.ACCURATE)
      .map(DebugSymbol.fromAddress)
      .map(String);
  } catch (_) {
    return undefined;
  }
}

function observePathCall(exportName, pathArgIndex) {
  const address = Module.findGlobalExportByName(exportName);
  if (!address) return;
  Interceptor.attach(address, {
    onEnter(args) {
      if (!shouldRunForCurrentProcess() || !state.observeProc) return;
      const path = readCString(args[pathArgIndex]);
      if (path.indexOf('/proc/') === -1) return;
      log('proc_path_read', {
        api: exportName,
        path,
        backtrace: maybeBacktrace(this.context),
      });
    },
  });
}

function observeLibraryLoad(exportName) {
  const address = Module.findGlobalExportByName(exportName);
  if (!address) return;
  Interceptor.attach(address, {
    onEnter(args) {
      if (!shouldRunForCurrentProcess() || !state.observeLoads) return;
      const path = readCString(args[0]);
      if (!path) return;
      log('library_load', {
        api: exportName,
        path,
        backtrace: maybeBacktrace(this.context),
      });
    },
  });
}

function installProcObservers() {
  if (installed.proc) return;
  installed.proc = true;
  observePathCall('open', 0);
  observePathCall('open64', 0);
  observePathCall('openat', 1);
  observePathCall('fopen', 0);
  observePathCall('fopen64', 0);
  observePathCall('access', 0);
  observePathCall('readlink', 0);
  observePathCall('readlinkat', 1);
}

function installLoadObservers() {
  if (installed.loads) return;
  installed.loads = true;
  observeLibraryLoad('android_dlopen_ext');
}

function applyObserverProfile() {
  if (!state.enabled) return;
  if (!shouldRunForCurrentProcess()) return;
  if (state.observeLoads) installLoadObservers();
  if (state.observeProc) installProcObservers();
}

rpc.exports = {
  configure(config) {
    const next = config || {};
    state.enabled = next.enabled === true;
    state.targetPackage = String(next.targetPackage || '');
    state.allowGlobal = next.allowGlobal === true;
    state.observeProc = next.observeProc === true;
    state.observeLoads = next.observeLoads !== false;
    state.logBacktrace = next.logBacktrace === true;
    applyObserverProfile();
    return Object.assign({}, state, {
      currentPackage: currentPackageName(),
      installed: Object.assign({}, installed),
    });
  },
  status() {
    return Object.assign({}, state, {
      currentPackage: currentPackageName(),
      installed: Object.assign({}, installed),
    });
  },
};

log('antidetect_baseline_loaded', { enabled: state.enabled });
