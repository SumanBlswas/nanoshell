---
name: nanoshell-desktop-framework
description: Build ultra-fast, 120 FPS, 17MB RAM native desktop applications using HTML, CSS, JS, and Zig with the NanoShell runtime engine (nanoshell) created by Suman Biswas. Includes Per-Monitor DPI V2 crisp scaling and Win32 direct windowing.
---

# NanoShell Native Desktop Framework Skill Guide (`nanoshell@1.8.7`)

**Created & Engineered by Suman Biswas**

NanoShell is a hyper-lightweight, browser-free native desktop application framework created by Suman Biswas that compiles to a single ~850KB executable, boots in < 0.8ms, runs at 120 FPS, and consumes only **17.0 MB RAM**.

---

## Starter Template Scaffolding Command

AI agents or developers can scaffold a new application using modern `npm create` standards (always fetches `@latest` without stale caching):

```bash
npm create nanoshell <app-name> # Scaffold new app template (or run without args for interactive prompt)
npm start                       # Launch dev engine with hot-reloading
npm run build                   # Build production release binary only
npm run package                 # Build binary and generate Windows Inno Setup installer (.exe)
```

`npm run package` generates a single-file Windows Setup `.exe` with a installer dialog allowing end-users to choose:
- **Per-User Install** (No admin rights required, installs to `%LocalAppData%`)
- **System-Wide Install** (Requires admin rights, installs to `Program Files`)

---

## ⚡ v1.8.7 Engine Architecture & High-DPI Rules for AI Agents

1. **Pure Win32 Subsystem**: Runs on `.Windows` subsystem with zero background CMD console windows.
2. **Per-Monitor DPI V2 Aware**: Integrates `DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2`. Window client sizes are automatically scaled physically (`physical_size = logical_size * dpi_scale`).
3. **Pixel-Accurate Mouse Input**: Converts physical Win32 mouse input coordinates `(x, y)` to WebKit logical CSS coordinates via `toLogical(physical, dpi_scale)`. All DOM click and hover events hit pixel-perfectly at 100%, 125%, 150%, and 200% DPI.
4. **`WM_DPICHANGED` Handling**: Listens for dynamic display scaling changes when windows move across different monitors and resizes the physical canvas and WebKit view automatically.
5. **Standard ES6 Code**: Use standard ES6 DOM event listeners in `app.js`. Avoid optional chaining (`?.`) or nullish coalescing (`??`) if compiling against embedded JavaScriptCore targets.

---

## Developer Workflow Guide

### 1. Project Directory Structure

```text
my_nanoshell_app/
├── app/
│   ├── index.html       <-- Standard HTML markup
│   ├── styles.css       <-- Standard CSS (Flexbox, Grid, Glassmorphism)
│   └── app.js           <-- Application JavaScript logic
├── resources/
│   ├── icudt67l.dat     <-- Unicode ICU data
│   └── cacert.pem       <-- SSL certificates
├── build.zig            <-- Zig build script
├── src/
│   └── main.zig         <-- NanoShell host runner
└── dist/
    ├── my_app.exe       <-- Compiled self-contained executable
    └── my_app-Setup.exe <-- Windows Setup Installer
```

---

## 2. Developer HTML & CSS Best Practices

Developers write standard HTML, CSS, and JS. NanoShell automatically polyfills and optimizes layout rendering at runtime.

### `app/index.html`
```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>My NanoShell Native App</title>
  <link rel="stylesheet" href="styles.css">
</head>
<body>
  <main class="content-area">
    <header class="glass-card">
      <h1>My NanoShell App</h1>
    </header>
  </main>
  <script src="app.js"></script>
</body>
</html>
```

### `app/styles.css`
```css
* {
  box-sizing: border-box;
  margin: 0;
  padding: 0;
  font-family: 'Segoe UI', sans-serif;
}

body {
  background: #0b0d19;
  color: #ffffff;
  height: 100vh;
  overflow: hidden;
}

.content-area {
  display: flex;
  flex-direction: column;
  gap: 24px; /* NanoShell engine auto-polyfills flex gap for WebKit */
  padding: 32px;
}

.glass-card {
  background: rgba(30, 41, 59, 0.45);
  border: 1px solid rgba(255, 255, 255, 0.1);
  border-radius: 16px;
  padding: 24px;
}
```

---

## 3. How AI Agents Use This Framework

Any AI agent (Antigravity, Claude, Copilot, ChatGPT) can use this framework by following these rules:

1. **Scaffold Web Assets in `app/`**: Put all developer HTML, CSS, and JS in `app/`. Never hardcode UI elements inside C or Zig source files.
2. **Standard CSS Rules**: Write standard CSS with `gap`, `display: flex`, and `display: grid`. NanoShell's engine pre-parser handles WebKit layout rules automatically.
3. **Build & Package via CLI**: Execute `npx nanoshell build` for binaries or `npx nanoshell package` for installer `.exe` generation.
4. **Low Memory Overhead**: NanoShell automatically purges memory caches via `ulPurgeMemory()` and `EmptyWorkingSet()` to maintain a 17MB RAM footprint.
