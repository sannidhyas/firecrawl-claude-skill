#!/usr/bin/env node
// Thin shim: exec the bash fc script so `npm install -g` wires up the `fireclaude` binary.
const { execFileSync } = require("child_process");
const path = require("path");
const fc = path.join(__dirname, "fc");
try {
  execFileSync("/usr/bin/env", ["bash", fc, ...process.argv.slice(2)], {
    stdio: "inherit",
    env: process.env,
  });
} catch (e) {
  process.exit(e.status || 1);
}
