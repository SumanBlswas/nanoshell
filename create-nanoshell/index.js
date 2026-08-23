#!/usr/bin/env node
const { spawnSync } = require('child_process');
const path = require('path');

// Locate installed nanoshell CLI executable script
let nanoshellCli = null;
try {
    nanoshellCli = require.resolve('nanoshell/cli/index.js');
} catch (e) {
    // Fallback if local
    nanoshellCli = path.join(__dirname, '..', 'cli', 'index.js');
}

const args = process.argv.slice(2);
const result = spawnSync(process.execPath, [nanoshellCli, ...args], { stdio: 'inherit' });
process.exit(result.status || 0);
