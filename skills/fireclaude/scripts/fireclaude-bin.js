#!/usr/bin/env node
// fireclaude-bin.js — visual-layer wrapper around the bash `fc` script.
// Prints ASCII splash, wraps long ops in ora spinners (when TTY), degrades
// gracefully in non-TTY / NO_COLOR / --no-animate environments.
"use strict";

const { spawn } = require("child_process");
const path = require("path");
const fs = require("fs");

const fc = path.join(__dirname, "fc");
const logoAscii = path.join(__dirname, "../../../assets/logo-ascii.txt");

const args = process.argv.slice(2);
const subcommand = args[0] || "";

// ── TTY / colour detection ────────────────────────────────────────────────────
const noAnimate =
  !process.stdout.isTTY ||
  process.env.NO_COLOR === "1" ||
  args.includes("--no-animate");

// Long-running subcommands that benefit from spinner wrapping
const LONG_OPS = new Set(["setup", "start", "upgrade"]);

// Subcommands that print the splash header
const SPLASH_CMDS = new Set(["setup", "--help", "-h", "help", ""]);

// ── Splash printer ────────────────────────────────────────────────────────────
function printSplash() {
  if (noAnimate) {
    // Plain text fallback
    if (fs.existsSync(logoAscii)) {
      process.stdout.write(fs.readFileSync(logoAscii, "utf8") + "\n");
    } else {
      process.stdout.write("fireclaude\n\n");
    }
    return;
  }
  try {
    // Try to load optional deps; tolerate absence.
    const chalk = loadOptional("chalk");
    const gradient = loadOptional("gradient-string");

    let ascii = fs.existsSync(logoAscii)
      ? fs.readFileSync(logoAscii, "utf8")
      : "fireclaude\n";

    if (gradient) {
      // Fire gradient: orange → yellow, then purple wordmark line
      const lines = ascii.split("\n");
      const colored = lines
        .map((l) => {
          if (l.includes("fireclaude") && gradient) {
            return gradient(["#f97316", "#8b5cf6"])(l);
          }
          return gradient(["#f97316", "#fde047"])(l);
        })
        .join("\n");
      process.stdout.write(colored + "\n");
    } else if (chalk) {
      process.stdout.write(chalk.yellow(ascii) + "\n");
    } else {
      process.stdout.write(ascii + "\n");
    }
  } catch (_) {
    if (fs.existsSync(logoAscii)) {
      process.stdout.write(fs.readFileSync(logoAscii, "utf8") + "\n");
    }
  }
}

function loadOptional(name) {
  try {
    return require(name);
  } catch (_) {
    return null;
  }
}

// ── Plain passthrough (no animation) ─────────────────────────────────────────
function runPlain(extraArgs) {
  const proc = spawn("/usr/bin/env", ["bash", fc, ...extraArgs], {
    stdio: "inherit",
    env: process.env,
  });
  proc.on("exit", (code) => process.exit(code || 0));
  proc.on("error", (e) => {
    process.stderr.write("fireclaude: " + e.message + "\n");
    process.exit(1);
  });
}

// ── Spinner-wrapped run ───────────────────────────────────────────────────────
function runWithSpinner(extraArgs) {
  let ora;
  try {
    ora = require("ora");
  } catch (_) {
    // ora not available — fall back to plain
    return runPlain(extraArgs);
  }

  const spinner = ora({ text: "fireclaude: starting…", stream: process.stderr }).start();
  const startTs = Date.now();

  // Stage label map (emitted by install.sh as "@stage: <name>" on stderr)
  const STAGE_LABELS = {
    "deps-check": "Checking dependencies",
    "ollama-mode": "Resolving ollama mode",
    clone: "Cloning firecrawl",
    patches: "Applying patches",
    build: "Building Docker images",
    up: "Starting stack",
    health: "Waiting for API health",
    pull: "Pulling ollama models",
    smoke: "Running smoke tests",
  };

  const proc = spawn("/usr/bin/env", ["bash", fc, ...extraArgs], {
    stdio: ["inherit", "inherit", "pipe"],
    env: process.env,
  });

  let stderrBuf = "";
  proc.stderr.on("data", (chunk) => {
    const text = chunk.toString();
    stderrBuf += text;
    // Scan for @stage: lines
    let lines = stderrBuf.split("\n");
    stderrBuf = lines.pop(); // keep incomplete last line
    for (const line of lines) {
      const m = line.match(/^@stage:\s*(.+)$/);
      if (m) {
        const label = STAGE_LABELS[m[1].trim()] || m[1].trim();
        const elapsed = ((Date.now() - startTs) / 1000).toFixed(0);
        spinner.text = `${label}… (${elapsed}s)`;
      } else if (line.trim()) {
        // Pass non-stage stderr through after spinner clears
        spinner.clear();
        process.stderr.write(line + "\n");
      }
    }
  });

  proc.on("exit", (code) => {
    if (stderrBuf.trim()) process.stderr.write(stderrBuf + "\n");
    if (code === 0) {
      spinner.succeed("fireclaude: done.");
    } else {
      spinner.fail("fireclaude: exited with code " + code);
    }
    process.exit(code || 0);
  });

  proc.on("error", (e) => {
    spinner.fail("fireclaude: " + e.message);
    process.exit(1);
  });
}

// ── Main ──────────────────────────────────────────────────────────────────────

if (SPLASH_CMDS.has(subcommand)) {
  printSplash();
}

if (!noAnimate && LONG_OPS.has(subcommand)) {
  runWithSpinner(args);
} else {
  runPlain(args);
}
