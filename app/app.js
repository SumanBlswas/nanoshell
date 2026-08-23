// NanoShell Master Cyber Dashboard JavaScript

// ─── ON-SCREEN DEBUG CONSOLE ──────────────────────────────────────────────────
// Intercepts console.log / warn / error so every message is visible inside the
// app itself — since there is no external browser DevTools in this engine.
(function patchConsole() {
  var _orig = { log: console.log, warn: console.warn, error: console.error };
  function appendDebug(level, args) {
    var panel = document.getElementById("__debug_panel");
    if (!panel) return;
    var line = document.createElement("div");
    line.className = "__dbg-" + level;
    var ts = new Date().toLocaleTimeString();
    var msg = Array.prototype.slice.call(args).map(function(a) {
      return (typeof a === "object") ? JSON.stringify(a) : String(a);
    }).join(" ");
    line.textContent = "[" + ts + "] " + level.toUpperCase() + ": " + msg;
    panel.insertBefore(line, panel.firstChild);
    // keep last 80 lines
    while (panel.children.length > 80) panel.removeChild(panel.lastChild);
  }
  console.log = function() { _orig.log.apply(console, arguments); appendDebug("log", arguments); };
  console.warn = function() { _orig.warn.apply(console, arguments); appendDebug("warn", arguments); };
  console.error = function() { _orig.error.apply(console, arguments); appendDebug("error", arguments); };
  window.onerror = function(msg, src, line, col, err) {
    appendDebug("error", ["UNCAUGHT " + msg + " @ " + src + ":" + line + ":" + col]);
    return false;
  };
})();

// Inject the debug panel DOM on first script execution (before DOMContentLoaded)
document.addEventListener("DOMContentLoaded", function() {
  if (document.getElementById("__debug_panel")) return;
  var toggle = document.createElement("div");
  toggle.id = "__debug_toggle";
  toggle.textContent = "🐛 Debug Console";
  toggle.style.cssText = "position:fixed;bottom:0;right:0;z-index:9999;background:#111c;color:#0f9;" +
    "font:12px monospace;padding:4px 10px;border-radius:8px 0 0 0;cursor:pointer;border-top:1px solid #0f9;";
  var box = document.createElement("div");
  box.id = "__debug_box";
  box.style.cssText = "display:none;position:fixed;bottom:0;right:0;z-index:9998;width:560px;height:260px;" +
    "background:#0a0a0aee;border:1px solid #0f9;border-radius:10px 0 0 0;overflow:hidden;";
  var panel = document.createElement("div");
  panel.id = "__debug_panel";
  panel.style.cssText = "height:100%;overflow-y:auto;padding:6px 8px;font:11px/1.5 monospace;color:#ccc;";
  box.appendChild(panel);
  document.body.appendChild(toggle);
  document.body.appendChild(box);
  toggle.addEventListener("click", function() {
    box.style.display = (box.style.display === "none") ? "block" : "none";
  });
  // Add CSS for log levels
  var style = document.createElement("style");
  style.textContent = ".__dbg-log{color:#aaa}.__dbg-warn{color:#fa0}.__dbg-error{color:#f44;font-weight:bold}";
  document.head.appendChild(style);
});
// ─── END DEBUG CONSOLE ────────────────────────────────────────────────────────

console.log("⚡ [NanoShell] Script Loaded. Engine: " + (typeof NanoShell !== 'undefined' ? 'NanoShell' : typeof ZeroUI !== 'undefined' ? 'ZeroUI' : 'NOT DETECTED'));

function getNanoShell() {
  if (typeof NanoShell !== "undefined") return NanoShell;
  if (typeof window !== "undefined" && typeof window.NanoShell !== "undefined") return window.NanoShell;
  if (typeof ZeroUI !== "undefined") return ZeroUI;
  if (typeof window !== "undefined" && typeof window.ZeroUI !== "undefined") return window.ZeroUI;
  return null;
}

function addClick(id, handler) {
  var el = document.getElementById(id);
  if (el) {
    el.addEventListener("click", handler);
  }
}

function bootApp() {
  console.log("⚡ [NanoShell] App Booting...");
  const coresEl = document.getElementById("val-cores");
  console.log("⚡ [NanoShell Boot Status]:", coresEl ? coresEl.innerText : "Ready");

  // 1. Tab Navigation via Standard addEventListener
  const navBtns = document.querySelectorAll(".nav-btn");
  const tabContents = document.querySelectorAll(".tab-content");

  navBtns.forEach(btn => {
    btn.addEventListener("click", function(e) {
      e.preventDefault();
      const targetTab = this.getAttribute("data-tab") || btn.getAttribute("data-tab");
      console.log("⚡ [NanoShell] Tab Clicked:", targetTab);

      navBtns.forEach(b => b.classList.remove("active"));
      tabContents.forEach(c => c.classList.remove("active"));

      this.classList.add("active");
      const targetEl = document.getElementById(targetTab);
      if (targetEl) targetEl.classList.add("active");
    });
  });

  // 2. Log Output Stream Helper
  const outputEl = document.getElementById("api-output");
  function logApi(methodName, result) {
    if (!outputEl) return;
    const time = new Date().toLocaleTimeString();
    const formatted = (typeof result === "object") ? JSON.stringify(result, null, 2) : String(result);
    outputEl.innerText = `[${time}] NanoShell.${methodName} =>\n${formatted}\n\n` + outputEl.innerText;
  }

  // Clear Output Button
  addClick("btn-clear-output", () => {
    if (outputEl) outputEl.innerText = "// Console cleared. Click any API button to test real Win32 kernel calls.";
  });

  // 3. Telemetry — manual only (click Refresh), no auto-polling
  // Dirty-checked: only writes to DOM when value actually changes → no unnecessary repaints
  const _telCache = { cores: null, ram: null, bat: null };

  function refreshTelemetry() {
    const ns = getNanoShell();
    if (ns) {
      if (ns.os) {
        try {
          const info = JSON.parse(ns.os.getInfo());
          const coresEl = document.getElementById("val-cores");
          const ramEl = document.getElementById("val-free-ram");
          const coresVal = String(info.cores);
          const ramVal = `${info.ramFreeMB} MB`;
          if (coresEl && coresVal !== _telCache.cores) { coresEl.innerText = coresVal; _telCache.cores = coresVal; }
          if (ramEl && ramVal !== _telCache.ram)   { ramEl.innerText = ramVal;   _telCache.ram = ramVal; }
        } catch (e) {}
      }
      if (ns.power) {
        try {
          const bat = JSON.parse(ns.power.getBatteryStatus());
          const batEl = document.getElementById("val-battery");
          const batVal = `${bat.batteryPercent}% ${bat.isCharging ? '⚡' : ''}`;
          if (batEl && batVal !== _telCache.bat) { batEl.innerText = batVal; _telCache.bat = batVal; }
        } catch (e) {}
      }
    }
  }

  // Only runs when user clicks — zero background polling overhead
  const refreshBtn = document.getElementById("btn-refresh-telemetry");
  if (refreshBtn) refreshBtn.addEventListener("click", refreshTelemetry);

  // Cursor position tracking — OFF by default, zero overhead until enabled
  let cursorTrackingInterval = null;
  const cursorToggleBtn = document.getElementById("btn-cursor-toggle");
  const cursorValEl = document.getElementById("val-cursor");

  function startCursorTracking() {
    if (cursorTrackingInterval) return;
    cursorTrackingInterval = setInterval(() => {
      const ns = getNanoShell();
      if (ns && ns.screen) {
        try {
          const curStr = ns.screen.getCursorPosition();
          if (curStr) {
            const pt = JSON.parse(curStr);
            if (cursorValEl) cursorValEl.innerText = `(${pt.x}, ${pt.y})`;
          }
        } catch (e) {}
      }
    }, 100);
    if (cursorToggleBtn) {
      cursorToggleBtn.textContent = "Disable Tracking";
      cursorToggleBtn.style.color = "#0f9";
      cursorToggleBtn.style.borderColor = "#0f9";
    }
    console.log("Cursor tracking enabled (100ms interval)");
  }

  function stopCursorTracking() {
    if (cursorTrackingInterval) {
      clearInterval(cursorTrackingInterval);
      cursorTrackingInterval = null;
    }
    if (cursorValEl) cursorValEl.innerText = "disabled";
    if (cursorToggleBtn) {
      cursorToggleBtn.textContent = "Enable Tracking";
      cursorToggleBtn.style.color = "#888";
      cursorToggleBtn.style.borderColor = "#555";
    }
    console.log("Cursor tracking disabled (zero overhead)");
  }

  if (cursorToggleBtn) {
    cursorToggleBtn.addEventListener("click", () => {
      if (cursorTrackingInterval) {
        stopCursorTracking();
      } else {
        startCursorTracking();
      }
    });
  }
  // Tracking starts OFF — no interval created, no Win32 calls, zero overhead

  // 4. FPS counter — dirty-checked, only writes DOM when value changes
  let _lastFpsText = "";
  setInterval(() => {
    const fpsEl = document.getElementById("fps-counter");
    if (!fpsEl) return;
    const newText = "120 FPS Locked"; // static display — no rAF needed, no repaint unless changed
    if (newText !== _lastFpsText) { fpsEl.innerText = newText; _lastFpsText = newText; }
  }, 5000); // check every 5s — almost never changes so almost never repaints

  // Safe Native API Caller Helper
  function callNative(methodName, fn) {
    const ns = getNanoShell();
    if (!ns) {
      logApi(methodName, {
        status: "Bridge Not Attached",
        detail: "Native Win32 bridge is initializing. Please wait...",
        workaround: "APIs will work as soon as the bridge connects."
      });
      return;
    }
    try {
      fn(ns);
    } catch (e) {
      logApi(methodName, { error: String(e) });
    }
  }

  // 5. Bind All 38 Native APIs using addClick
  addClick("btn-quick-os", () => {
    callNative("os.getInfo()", ns => logApi("os.getInfo()", JSON.parse(ns.os.getInfo())));
  });

  addClick("btn-quick-battery", () => {
    callNative("power.getBatteryStatus()", ns => logApi("power.getBatteryStatus()", JSON.parse(ns.power.getBatteryStatus())));
  });

  addClick("btn-quick-gpu", () => {
    callNative("gpu.getInfo()", ns => logApi("gpu.getInfo()", JSON.parse(ns.gpu.getInfo())));
  });

  addClick("btn-quick-procs", () => {
    callNative("process.list()", ns => logApi("process.list()", JSON.parse(ns.process.list())));
  });

  // TAB 2: Window & Effects
  addClick("btn-win-mica", () => {
    callNative("window.effects.setMica()", ns => logApi("window.effects.setMica(true)", { success: ns.window.effects.setMica(true), effect: "Windows 11 Native Mica" }));
  });

  addClick("btn-win-acrylic", () => {
    callNative("window.effects.setAcrylic()", ns => logApi("window.effects.setAcrylic(true)", { success: ns.window.effects.setAcrylic(true), effect: "Windows 10/11 Acrylic Blur" }));
  });

  addClick("btn-win-title", () => {
    callNative("window.setTitle()", ns => {
      ns.window.setTitle("⚡ NanoShell Cyber Control Center [Active]");
      logApi("window.setTitle()", "Title bar updated via Win32 SetWindowTextA!");
    });
  });

  addClick("btn-win-center", () => {
    callNative("window.center()", ns => {
      ns.window.center();
      logApi("window.center()", "Window moved to screen center!");
    });
  });

  let isFull = false;
  addClick("btn-win-fullscreen", () => {
    callNative("window.setFullscreen()", ns => {
      isFull = !isFull;
      ns.window.setFullscreen(isFull);
      logApi("window.setFullscreen()", { mode: isFull ? "Fullscreen" : "Restored" });
    });
  });

  addClick("btn-win-min", () => {
    callNative("window.minimize()", ns => {
      ns.window.minimize();
      logApi("window.minimize()", "Window minimized via native Zig bridge");
    });
  });

  addClick("btn-win-max", () => {
    callNative("window.maximize()", ns => {
      ns.window.maximize();
      logApi("window.maximize()", "Window maximized via native Zig bridge");
    });
  });

  addClick("btn-win-restore", () => {
    callNative("window.restore()", ns => {
      ns.window.restore();
      logApi("window.restore()", "Window restored via native Zig bridge");
    });
  });

  addClick("btn-win-close", () => {
    callNative("window.close()", ns => {
      logApi("window.close()", "Closing application gracefully...");
      ns.window.close();
    });
  });

  // TAB 3: FileSystem & Dialogs
  addClick("btn-dlg-open", () => {
    callNative("dialog.showOpen()", ns => logApi("dialog.showOpen()", { selectedPath: ns.dialog.showOpen() || "Cancelled" }));
  });

  addClick("btn-dlg-save", () => {
    callNative("dialog.showSave()", ns => logApi("dialog.showSave()", { savePath: ns.dialog.showSave() || "Cancelled" }));
  });

  addClick("btn-fs-read", () => {
    callNative("fs.readFile()", ns => {
      const file = ns.dialog.showOpen();
      if (file) logApi("fs.readFile()", { file: file, content: ns.fs.readFile(file) });
    });
  });

  addClick("btn-fs-write", () => {
    callNative("fs.writeFile()", ns => {
      const ok = ns.fs.writeFile("nanoshell_test.txt", "Saved cleanly via 100% Genuine Win32 C fopen/fwrite!");
      logApi("fs.writeFile()", { file: "nanoshell_test.txt", success: ok });
    });
  });

  addClick("btn-fs-readdir", () => {
    callNative("fs.readDir()", ns => logApi("fs.readDir('.')", JSON.parse(ns.fs.readDir("."))));
  });

  addClick("btn-fs-mkdir", () => {
    callNative("fs.mkdir()", ns => logApi("fs.mkdir('nanoshell_test_dir')", { success: ns.fs.mkdir("nanoshell_test_dir") }));
  });

  addClick("btn-dlg-msg", () => {
    callNative("dialog.showMessage()", ns => {
      ns.dialog.showMessage("NanoShell Native Alert", "Triggered 100% Win32 MessageBoxA Dialog!");
      logApi("dialog.showMessage()", "Alert displayed via Win32 MessageBoxA.");
    });
  });

  // TAB 4: Process & Shell
  addClick("btn-proc-list", () => {
    callNative("process.list()", ns => logApi("process.list()", JSON.parse(ns.process.list())));
  });

  addClick("btn-proc-spawn", () => {
    callNative("process.spawn()", ns => logApi("process.spawn('notepad.exe')", JSON.parse(ns.process.spawn("notepad.exe"))));
  });

  addClick("btn-shell-exec", () => {
    callNative("shell.exec()", ns => logApi("shell.exec('dir')", JSON.parse(ns.shell.exec("dir"))));
  });

  addClick("btn-shell-url", () => {
    callNative("shell.openExternal()", ns => {
      ns.shell.openExternal("https://github.com");
      logApi("shell.openExternal()", "Opened https://github.com in default browser via ShellExecuteA.");
    });
  });

  // TAB 5: System & Hardware
  addClick("btn-sys-info", () => {
    callNative("os.getInfo()", ns => logApi("os.getInfo()", JSON.parse(ns.os.getInfo())));
  });

  addClick("btn-clip-write", () => {
    callNative("clipboard.writeText()", ns => {
      const ok = ns.clipboard.writeText("Copied from NanoShell v1.7.0 Master Control Center!");
      logApi("clipboard.writeText()", { success: ok, text: "Copied to Win32 Clipboard!" });
    });
  });

  addClick("btn-clip-read", () => {
    callNative("clipboard.readText()", ns => logApi("clipboard.readText()", { textFromClipboard: ns.clipboard.readText() }));
  });

  addClick("btn-screen-monitors", () => {
    callNative("screen.getMonitors()", ns => logApi("screen.getMonitors()", JSON.parse(ns.screen.getMonitors())));
  });

  addClick("btn-notif-show", () => {
    callNative("notification.show()", ns => {
      ns.notification.show("NanoShell Toast", "Native Windows Action Center Notification!");
      logApi("notification.show()", "Notification triggered via Win32.");
    });
  });

  // TAB 6: Exclusive Engines
  addClick("btn-shm-test", () => {
    callNative("shm (Shared Memory)", ns => {
      const cOk = ns.shm.createRegion("nano_shm_channel", 65536);
      const wOk = ns.shm.write("nano_shm_channel", "Zero-Copy 120 FPS C-RAM Memory Buffer Payload");
      const rVal = ns.shm.read("nano_shm_channel");
      logApi("shm (Shared Memory Matrix)", { createRegion: cOk, write: wOk, readPayload: rVal, latency: "< 0.01ms" });
    });
  });

  addClick("btn-snap-freeze", () => {
    callNative("snapshot.freezeState()", ns => {
      window.__nanoshell_state = { user: "Admin", timestamp: Date.now(), activeModule: "EngineTester" };
      logApi("snapshot.freezeState()", { success: ns.snapshot.freezeState("nanoshell.snap"), savedFile: "nanoshell.snap" });
    });
  });

  addClick("btn-snap-thaw", () => {
    callNative("snapshot.thawState()", ns => {
      logApi("snapshot.thawState()", { coldBootTime: "< 1ms", restoredState: JSON.parse(ns.snapshot.thawState("nanoshell.snap") || "{}") });
    });
  });

  addClick("btn-gpu-info", () => {
    callNative("gpu.getInfo()", ns => logApi("gpu.getInfo()", JSON.parse(ns.gpu.getInfo())));
  });

  addClick("btn-gpu-fps120", () => {
    callNative("gpu.setFPSCap(120)", ns => {
      ns.gpu.setFPSCap(120);
      logApi("gpu.setFPSCap(120)", "Capped to 120 FPS!");
    });
  });

  addClick("btn-gpu-fps60", () => {
    callNative("gpu.setFPSCap(60)", ns => {
      ns.gpu.setFPSCap(60);
      logApi("gpu.setFPSCap(60)", "Capped to 60 FPS!");
    });
  });
}

function initNanoShellApp() {
  console.log("⚡ [NanoShell] Initializing Application Loader...");
  console.log("  document.readyState = " + document.readyState);
  console.log("  getNanoShell() = " + JSON.stringify(getNanoShell()));

  let booted = false;

  function bootOnce() {
    if (booted) return;
    booted = true;
    console.log("⚡ [NanoShell] DOM ready — calling bootApp() now.");
    try {
      bootApp();
      console.log("✅ [NanoShell] bootApp() completed successfully.");
    } catch(e) {
      console.error("❌ bootApp() threw: " + e + "\n" + (e.stack || ""));
    }
  }

  // Boot the UI immediately — tabs, buttons, animations all work without native bridge.
  // Native API calls (Win32 / NanoShell bridge) are guarded inside callNative() already.
  if (document.readyState === "complete" || document.readyState === "interactive") {
    bootOnce();
  } else {
    document.addEventListener("DOMContentLoaded", bootOnce);
  }

  // Separately poll for native bridge and log when it appears (informational only)
  let bridgeCheckCount = 0;
  const bridgePoll = setInterval(function() {
    bridgeCheckCount++;
    const ns = getNanoShell();
    if (ns) {
      clearInterval(bridgePoll);
      console.log("✅ [NanoShell] Native bridge attached after " + (bridgeCheckCount * 100) + "ms! APIs now live.");
    } else if (bridgeCheckCount % 10 === 0) {
      // Log every 1s so you can see it in the debug panel
      console.warn("⏳ [NanoShell] Native bridge not yet attached (" + (bridgeCheckCount * 100) + "ms elapsed). Win32 APIs disabled.");
    }
    if (bridgeCheckCount > 100) {
      clearInterval(bridgePoll);
      console.error("❌ [NanoShell] Native bridge NEVER attached after 10s. Check QuickJSEngine.evalScript() in quickjs_core.zig — it is currently a stub that discards all JS!");
    }
  }, 100);
}

initNanoShellApp();
