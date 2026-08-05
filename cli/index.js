#!/usr/bin/env node
const { spawnSync } = require('child_process');
const path = require('path');
const fs = require('fs');

const pkgDir = path.join(__dirname, '..');
let exePath = path.join(pkgDir, 'zig-out', 'bin', 'nanoshell.exe');
if (!fs.existsSync(exePath)) {
    exePath = path.join(pkgDir, 'bin', 'nanoshell.exe');
}

const args = process.argv.slice(2);

// Run the Zig CLI binary
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
    }
}

process.exit(result.status || 0);
