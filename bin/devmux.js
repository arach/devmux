#!/usr/bin/env node

import { execSync } from "node:child_process";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { basename, resolve } from "node:path";

const args = process.argv.slice(2);
const command = args[0];

// ── Helpers ──────────────────────────────────────────────────────────

function run(cmd, opts = {}) {
  return execSync(cmd, { encoding: "utf8", ...opts }).trim();
}

function runQuiet(cmd) {
  try {
    return run(cmd, { stdio: "pipe" });
  } catch {
    return null;
  }
}

function hasTmux() {
  return runQuiet("which tmux") !== null;
}

function isInsideTmux() {
  return !!process.env.TMUX;
}

function sessionExists(name) {
  return runQuiet(`tmux has-session -t "${name}" 2>&1`) !== null;
}

function toSessionName(dir) {
  return basename(dir).replace(/[^a-zA-Z0-9_-]/g, "-");
}

function esc(str) {
  return str.replace(/'/g, "'\\''");
}

// ── Config ───────────────────────────────────────────────────────────

function readConfig(dir) {
  const configPath = resolve(dir, ".devmux.json");
  if (!existsSync(configPath)) return null;
  try {
    const raw = readFileSync(configPath, "utf8");
    return JSON.parse(raw);
  } catch (e) {
    console.warn(`Warning: invalid .devmux.json — ${e.message}`);
    return null;
  }
}

// ── Detect dev command ───────────────────────────────────────────────

function detectPackageManager(dir) {
  if (existsSync(resolve(dir, "pnpm-lock.yaml"))) return "pnpm";
  if (existsSync(resolve(dir, "bun.lockb")) || existsSync(resolve(dir, "bun.lock")))
    return "bun";
  if (existsSync(resolve(dir, "yarn.lock"))) return "yarn";
  return "npm";
}

function detectDevCommand(dir) {
  const pkgPath = resolve(dir, "package.json");
  if (!existsSync(pkgPath)) return null;

  let pkg;
  try {
    pkg = JSON.parse(readFileSync(pkgPath, "utf8"));
  } catch {
    return null;
  }

  const scripts = pkg.scripts || {};
  const pm = detectPackageManager(dir);
  const run = pm === "npm" ? "npm run" : pm;

  if (scripts.dev) return `${run} dev`;
  if (scripts.start) return `${run} start`;
  if (scripts.serve) return `${run} serve`;
  if (scripts.watch) return `${run} watch`;
  return null;
}

// ── Session creation ─────────────────────────────────────────────────

function resolvePane(panes, dir) {
  // Resolve any "auto" or missing commands
  return panes.map((p) => ({
    name: p.name || "",
    cmd: p.cmd || undefined,
    size: p.size || undefined,
  }));
}

function createSession(dir) {
  const name = toSessionName(dir);
  const config = readConfig(dir);
  const d = esc(dir);

  let panes;
  if (config?.panes?.length) {
    panes = resolvePane(config.panes, dir);
    console.log(`Using .devmux.json (${panes.length} panes)`);
  } else {
    // Default: claude + dev server
    const devCmd = detectDevCommand(dir);
    panes = [
      { name: "claude", cmd: "claude", size: 60 },
      { name: "server", cmd: devCmd || undefined },
    ];
    if (devCmd) console.log(`Detected: ${devCmd}`);
  }

  // Create session with first pane
  run(`tmux new-session -d -s "${name}" -c '${d}' -x 200 -y 50`);

  if (panes.length === 1) {
    // Single pane
    if (panes[0].cmd) {
      run(`tmux send-keys -t "${name}":0.0 '${esc(panes[0].cmd)}' Enter`);
    }
  } else if (panes.length === 2) {
    // Two panes: simple horizontal split
    const mainSize = panes[0].size || 60;
    run(
      `tmux split-window -h -t "${name}":0.0 -c '${d}' -p ${100 - mainSize}`
    );
    if (panes[0].cmd)
      run(
        `tmux send-keys -t "${name}":0.0 '${esc(panes[0].cmd)}' Enter`
      );
    if (panes[1].cmd)
      run(
        `tmux send-keys -t "${name}":0.1 '${esc(panes[1].cmd)}' Enter`
      );
  } else {
    // 3+ panes: main-vertical layout (first pane left, rest stacked right)
    const mainSize = panes[0].size || 60;

    // Create additional panes by splitting
    for (let i = 1; i < panes.length; i++) {
      run(`tmux split-window -t "${name}":0 -c '${d}'`);
    }

    // Apply main-vertical layout
    runQuiet(
      `tmux set-option -t "${name}" -w main-pane-width '${mainSize}%'`
    );
    run(`tmux select-layout -t "${name}":0 main-vertical`);

    // Send commands to each pane
    for (let i = 0; i < panes.length; i++) {
      if (panes[i].cmd) {
        run(
          `tmux send-keys -t "${name}":0.${i} '${esc(panes[i].cmd)}' Enter`
        );
      }
    }
  }

  // Name the window
  run(`tmux rename-window -t "${name}":0 "dev"`);

  // Focus the main (first) pane
  run(`tmux select-pane -t "${name}":0.0`);

  return name;
}

// ── Commands ─────────────────────────────────────────────────────────

function printUsage() {
  console.log(`devmux — Claude Code + dev server in tmux

Usage:
  devmux              Create session (or reattach) for current project
  devmux init         Generate .devmux.json config for this project
  devmux ls           List active tmux sessions
  devmux kill [name]  Kill a session (defaults to current project)
  devmux help         Show this help

Config (.devmux.json):
  Place in your project root to customize the layout:

  {
    "panes": [
      { "name": "claude", "cmd": "claude", "size": 60 },
      { "name": "server", "cmd": "pnpm dev" },
      { "name": "tests",  "cmd": "pnpm test --watch" }
    ]
  }

  size    Width % for the first pane (default: 60)
  cmd     Command to run in the pane
  name    Label (for your reference)

Layouts:
  2 panes  →  side-by-side split
  3+ panes →  main-vertical (first pane left, rest stacked right)

  ┌──────────┬─────────┐    ┌──────────┬─────────┐
  │  claude   │ server  │    │  claude   │ server  │
  │  (60%)   │ (40%)   │    │  (60%)   ├─────────┤
  └──────────┴─────────┘    │          │ tests   │
                             └──────────┴─────────┘
`);
}

function initConfig() {
  const dir = process.cwd();
  const configPath = resolve(dir, ".devmux.json");

  if (existsSync(configPath)) {
    console.log(".devmux.json already exists.");
    return;
  }

  const devCmd = detectDevCommand(dir);
  const config = {
    panes: [
      { name: "claude", cmd: "claude", size: 60 },
      { name: "server", cmd: devCmd || "echo 'no dev server detected'" },
    ],
  };

  writeFileSync(configPath, JSON.stringify(config, null, 2) + "\n");
  console.log("Created .devmux.json");
  console.log(JSON.stringify(config, null, 2));
}

function listSessions() {
  const out = runQuiet(
    "tmux list-sessions -F '#{session_name}  (#{session_windows} windows, created #{session_created_string})'"
  );
  if (!out) {
    console.log("No active tmux sessions.");
    return;
  }
  console.log("Sessions:\n");
  console.log(out);
}

function killSession(name) {
  if (!name) name = toSessionName(process.cwd());
  if (!sessionExists(name)) {
    console.log(`No session "${name}".`);
    return;
  }
  run(`tmux kill-session -t "${name}"`);
  console.log(`Killed "${name}".`);
}

function createOrAttach() {
  const dir = process.cwd();
  const name = toSessionName(dir);

  if (sessionExists(name)) {
    console.log(`Reattaching to "${name}"...`);
    attach(name);
    return;
  }

  console.log(`Creating "${name}"...`);
  createSession(dir);
  attach(name);
}

function attach(name) {
  if (isInsideTmux()) {
    execSync(`tmux switch-client -t "${name}"`, { stdio: "inherit" });
  } else {
    execSync(`tmux attach -t "${name}"`, { stdio: "inherit" });
  }
}

// ── Main ─────────────────────────────────────────────────────────────

if (!hasTmux()) {
  console.error("tmux is not installed. Install with: brew install tmux");
  process.exit(1);
}

switch (command) {
  case "init":
    initConfig();
    break;
  case "ls":
  case "list":
    listSessions();
    break;
  case "kill":
  case "rm":
    killSession(args[1]);
    break;
  case "-h":
  case "--help":
  case "help":
    printUsage();
    break;
  default:
    createOrAttach();
}
