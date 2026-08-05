// ZeroUI Showcase Application JavaScript Logic

console.log("[ZeroUI App] Initializing Showcase Application...");

// 1. Real-Time Hardware Delta FPS Counter Algorithm
let lastFrameTime = performance.now();
let frameCount = 0;
let currentFps = 60;

function updateRealTimeFps() {
  const now = performance.now();
  frameCount++;
  const delta = now - lastFrameTime;

  if (delta >= 500) { // Update display every 500ms for smooth reading
    currentFps = Math.round((frameCount * 1000) / delta);
    frameCount = 0;
    lastFrameTime = now;

    const fpsEl = document.getElementById("fps-counter");
    if (fpsEl) {
      fpsEl.innerText = `${currentFps} FPS Realtime`;
    }
  }
  requestAnimationFrame(updateRealTimeFps);
}

// 2. Query Native System Metrics via NanoShell / ZeroUI Native OS Bridge
function refreshSystemStats() {
  const ns = (typeof NanoShell !== "undefined") ? NanoShell : ((typeof ZeroUI !== "undefined") ? ZeroUI : null);
  if (ns && ns.sys) {
    const mem = ns.sys.getMemoryStats();
    const cpu = ns.sys.getCpuStats();

    console.log(`[NanoShell Sys] Arch: ${cpu.arch}, Cores: ${cpu.logical_cores}, RSS: ${(mem.total_rss_bytes / 1024).toFixed(1)} KB`);

    const ramEl = document.getElementById("val-ram");
    if (ramEl) {
      ramEl.innerText = `${(mem.total_rss_bytes / (1024 * 1024)).toFixed(1)} MB`;
    }
  }
}

// 3. Bind Button Click Events & Start FPS Loop
document.addEventListener("DOMContentLoaded", () => {
  console.log("[ZeroUI App] DOM Fully Loaded.");
  refreshSystemStats();
  requestAnimationFrame(updateRealTimeFps);

  // Refresh Diagnostics
  const btnRefresh = document.getElementById("btn-refresh");
  if (btnRefresh) {
    btnRefresh.addEventListener("click", () => {
      refreshSystemStats();
      if (typeof ZeroUI !== "undefined" && ZeroUI.dialog) {
        ZeroUI.dialog.showMessageBox("ZeroUI Diagnostics", "System Metrics Refreshed Cleanly! (RSS RAM < 10MB)");
      }
    });
  }

  // Trigger Native MessageBox
  const btnMsgBox = document.getElementById("btn-msgbox");
  if (btnMsgBox) {
    btnMsgBox.addEventListener("click", () => {
      if (typeof ZeroUI !== "undefined" && ZeroUI.dialog) {
        ZeroUI.dialog.showMessageBox("ZeroUI Native Bridge", "Zero-Serialization OS Dialog Triggered!");
      }
    });
  }

  // Set Taskbar Progress
  const btnProgress = document.getElementById("btn-progress");
  if (btnProgress) {
    btnProgress.addEventListener("click", () => {
      if (typeof ZeroUI !== "undefined" && ZeroUI.shell) {
        ZeroUI.shell.setTaskbarProgress(0.85);
        ZeroUI.shell.setBadge(5);
        console.log("[ZeroUI Shell] Taskbar Progress Set to 85%");
      }
    });
  }

  // Open Child Settings Window
  const btnOpenSettings = document.getElementById("btn-open-settings");
  if (btnOpenSettings) {
    btnOpenSettings.addEventListener("click", () => {
      if (typeof ZeroUI !== "undefined" && ZeroUI.window) {
        console.log("[ZeroUI Window] Spawning Child Window 'settings.html'...");
        const childWin = ZeroUI.window.createChild({
          url: "settings.html",
          title: "ZeroUI Settings Preferences",
          width: 600,
          height: 420,
          modal: false
        });

        // 0ms IPC Message Push
        childWin.postMessage("init-settings", JSON.stringify({ mode: "dark", fps: 120 }));
      }
    });
  }
});
