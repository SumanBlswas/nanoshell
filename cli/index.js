#!/usr/bin/env node
const { spawnSync } = require('child_process');
const path = require('path');
const fs = require('fs');

const pkgDir = path.join(__dirname, '..');
const pkg = require(path.join(pkgDir, 'package.json'));

// ── Auto-Update Cached NPX Check ─────────────────────────────────────────────
// Prevents users from running stale cached versions of npx nanoshell
if (!process.env.NANOSHELL_NO_UPDATE_CHECK) {
    try {
        const latestVersion = spawnSync('npm', ['show', 'nanoshell', 'version'], {
            encoding: 'utf8',
            timeout: 2000,
            shell: true
        }).stdout?.trim();

        if (latestVersion && latestVersion !== pkg.version) {
            console.log(`\x1b[36m⚡ [NanoShell] Outdated npx cache detected (v${pkg.version}). Auto-updating to latest (v${latestVersion})...\x1b[0m\n`);
            const updateResult = spawnSync('npx', ['-y', 'nanoshell@latest', ...process.argv.slice(2)], {
                stdio: 'inherit',
                shell: true,
                env: { ...process.env, NANOSHELL_NO_UPDATE_CHECK: '1' }
            });
            process.exit(updateResult.status || 0);
        }
    } catch (e) {
        // Ignore timeout or network errors silently
    }
}
// ─────────────────────────────────────────────────────────────────────────────

let exePath = path.join(pkgDir, 'zig-out', 'bin', 'nanoshell.exe');
if (!fs.existsSync(exePath)) {
    exePath = path.join(pkgDir, 'bin', 'nanoshell.exe');
}

const readline = require('readline');

let args = process.argv.slice(2);

// If no arguments provided (e.g. npm create nanoshell), prompt interactively for app name
if (args.length === 0) {
    const rl = readline.createInterface({
        input: process.stdin,
        output: process.stdout
    });

    console.log(`\x1b[36m\x1b[1m
  ⚡ NanoShell Native Desktop Framework Scaffolder (v${pkg.version})
  Created & Engineered by Suman Biswas
\x1b[0m`);

    const defaultAppName = 'my-nanoshell-app';
    rl.question(`? Project name: \x1b[36m(${defaultAppName})\x1b[0m `, (answer) => {
        rl.close();
        const appName = answer.trim() || defaultAppName;
        console.log(`\n🚀 Scaffolding new NanoShell project in .\\${appName}...\n`);
        
        // Re-invoke self with the project name argument
        const execRes = spawnSync(process.execPath, [__filename, appName], { stdio: 'inherit' });
        process.exit(execRes.status || 0);
    });
    return;
}

// Handle "package" command directly in JS CLI runner
if (args.length > 0 && (args[0] === 'package' || args[0] === 'installer')) {
    console.log("⚡ [NanoShell] Packaging application...");
    console.log("1. Building production binary (ReleaseFast)...");
    const buildRes = spawnSync('zig', ['build', '-Doptimize=ReleaseFast'], { stdio: 'inherit', shell: true });
    if (buildRes.status !== 0) {
        console.error("❌ Build failed.");
        process.exit(buildRes.status || 1);
    }

    console.log("\n2. Generating Windows Installer setup script & compiling setup.exe...");
    const packageResult = spawnSync(exePath, args, { stdio: 'inherit', shell: true });
    process.exit(packageResult.status || 0);
}

// Run the Zig CLI binary for other commands
const result = spawnSync(exePath, args, { stdio: 'inherit', shell: true });

// If a new app directory was scaffolded (e.g. npx nanoshell my-app), copy runtime binaries from the npm package directory
if (args.length > 0 && !args[0].startsWith('-') && args[0] !== 'package' && args[0] !== 'build' && args[0] !== 'start') {
    const targetDirName = args[0];
    const targetDir = path.resolve(process.cwd(), targetDirName);
    const targetBinDir = path.join(targetDir, 'bin');
    const targetResourcesDir = path.join(targetBinDir, 'resources');

    if (fs.existsSync(targetDir)) {
        if (!fs.existsSync(targetBinDir)) fs.mkdirSync(targetBinDir, { recursive: true });
        if (!fs.existsSync(targetResourcesDir)) fs.mkdirSync(targetResourcesDir, { recursive: true });

        // Search locations for runtime binaries
        const binDirs = [
            path.join(pkgDir, 'zig-out', 'bin'),
            path.join(pkgDir, 'vendor', 'bin'),
            path.join(pkgDir, 'bin')
        ];

        let foundExe = null;
        for (const dir of binDirs) {
            const p = path.join(dir, 'example_app.exe');
            if (fs.existsSync(p)) {
                foundExe = p;
                break;
            }
        }

        if (foundExe) {
            fs.copyFileSync(foundExe, path.join(targetBinDir, `${targetDirName}.exe`));
        }

        // Copy DLLs
        const dlls = ['AppCore.dll', 'Ultralight.dll', 'UltralightCore.dll', 'WebCore.dll', 'vcruntime140.dll', 'msvcp140.dll', 'vcruntime140_1.dll'];
        for (const dll of dlls) {
            for (const dir of binDirs) {
                const src = path.join(dir, dll);
                if (fs.existsSync(src)) {
                    fs.copyFileSync(src, path.join(targetBinDir, dll));
                    break;
                }
            }
        }

        // Copy ICU dat & cacert.pem into bin and bin/resources
        const resDirs = [
            path.join(pkgDir, 'vendor', 'resources'),
            path.join(pkgDir, 'zig-out', 'bin', 'resources'),
            path.join(pkgDir, 'resources')
        ];

        const resFiles = ['icudt67l.dat', 'cacert.pem'];
        for (const file of resFiles) {
            for (const dir of resDirs) {
                const src = path.join(dir, file);
                if (fs.existsSync(src)) {
                    fs.copyFileSync(src, path.join(targetBinDir, file));
                    fs.copyFileSync(src, path.join(targetResourcesDir, file));
                    break;
                }
            }
        }

        // Copy full NanoShell Master Control Center UI dashboard into target app/ folder
        const pkgAppDir = path.join(pkgDir, 'app');
        const targetAppDir = path.join(targetDir, 'app');
        if (fs.existsSync(pkgAppDir)) {
            if (!fs.existsSync(targetAppDir)) fs.mkdirSync(targetAppDir, { recursive: true });
            const appFiles = fs.readdirSync(pkgAppDir);
            for (const file of appFiles) {
                const srcFile = path.join(pkgAppDir, file);
                if (fs.statSync(srcFile).isFile()) {
                    fs.copyFileSync(srcFile, path.join(targetAppDir, file));
                }
            }
        }

        // Generate package.json inside scaffolded app directory for npm start / npm run package
        const appPkgPath = path.join(targetDir, 'package.json');
        if (!fs.existsSync(appPkgPath)) {
            const appPkgContent = {
                name: targetDirName,
                version: "1.0.0",
                description: "A NanoShell native desktop application",
                main: "app/index.html",
                scripts: {
                    "start": `.\\bin\\${targetDirName}.exe --dev`,
                    "build": `.\\bin\\${targetDirName}.exe --build`,
                    "package": `.\\bin\\${targetDirName}.exe --package`
                },
                keywords: ["nanoshell", "desktop", "native"],
                author: "",
                license: "MIT"
            };
            fs.writeFileSync(appPkgPath, JSON.stringify(appPkgContent, null, 2));
        }
    }
}

process.exit(result.status || 0);
