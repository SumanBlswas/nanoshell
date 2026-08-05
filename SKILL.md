---
name: nanoshell-desktop-framework
description: Build ultra-fast, 120 FPS, 17MB RAM native desktop applications using HTML, CSS, JS, and Zig with the NanoShell runtime engine (nanoshell) created by Suman Biswas.
---

# NanoShell Native Desktop Framework Skill Guide (`nanoshell`)

**Created & Engineered by Suman Biswas**

NanoShell is a hyper-lightweight, browser-free native desktop application framework created by Suman Biswas that compiles to a single 3MB executable, boots in < 0.8ms, runs at 120 FPS, and consumes only **17.0 MB RAM**.

---

## Starter Template Scaffolding Command

AI agents or developers can scaffold a new application using:

```bash
npx nanoshell <app-name>    # Scaffold new app template
npx nanoshell start         # Launch dev engine
npx nanoshell build         # Build production release binary only
npx nanoshell package       # Build binary and generate Windows Inno Setup installer (.exe)
```

`npx nanoshell package` generates a Windows Setup `.exe` with a installer dialog allowing end-users to choose:
- **Per-User Install** (No admin rights required, installs to `%LocalAppData%`)
- **System-Wide Install** (Requires admin rights, installs to `Program Files`)


---

## Developer Workflow Guide

### 1. Project Directory Structure

```text
my_nanoshell_app/
├── assets/
│   ├── index.html       <-- Standard HTML markup
│   ├── styles.css       <-- Standard CSS (Flexbox, Grid, Glassmorphism)
│   └── app.js           <-- Application JavaScript logic
├── resources/
│   ├── icudt67l.dat     <-- Unicode ICU data
│   └── cacert.pem       <-- SSL certificates
├── build.zig            <-- Zig build script
├── src/
│   └── main.zig         <-- NanoShell host runner
└── bin/
    └── my_app.exe       <-- Compiled self-contained executable
```

---

## 2. Developer HTML & CSS Best Practices

Developers write standard HTML, CSS, and JS. NanoShell automatically polyfills and optimizes layout rendering at runtime.

### `assets/index.html`
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

### `assets/styles.css`
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

1. **Scaffold Web Assets in `assets/`**: Put all developer HTML, CSS, and JS in `assets/`. Never hardcode UI elements inside C or Zig source files.
2. **Standard CSS Rules**: Write standard CSS with `gap`, `display: flex`, and `display: grid`. NanoShell's engine pre-parser handles WebKit layout rules automatically.
3. **Build via Zig**: Execute `zig build` to bundle DLLs (`Ultralight.dll`, `AppCore.dll`) and deploy assets into `zig-out/bin/`.
4. **Low Memory Overhead**: NanoShell automatically purges memory caches via `ulPurgeMemory()` and `EmptyWorkingSet()` to maintain 17MB RAM footprint.
