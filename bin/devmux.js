#!/usr/bin/env node

import { execSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
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

function sessionName(dir) {
  return basename(dir).replace(/[^a-zA-Z0-9_-]/g, "-");
}

function shellEscape(str) {
  return str.replace(/'/g, "'\\''");
}

// ── Detect dev command ───────────────────────────────────────────────

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

  // Detect package manager
  let pm = "npm run";
  if (existsSync(resolve(dir, "pnpm-lock.yaml"))) pm = "pnpm";
  else if (existsSync(resolve(dir, "bun.lockb")) || existsSync(resolve(dir, "bun.lock"))) pm = "bun run";
  else if (existsSync(resolve(dir, "yarn.lock"))) pm = "yarn";

  // Detect dev script (in priority order)
  if (scripts.dev) return `${pm} dev`;
  if (scripts.start) return `${pm} start`;
  if (scripts.serve) return `${pm} serve`;
  if (scripts.watch) return `${pm} watch`;

  return null;
}

// ── Commands ─────────────────────────────────────────────────────────

function printUsage() {
  console.log(`devmux — Claude Code + dev server in tmux

Usage:
  devmux            Create session (or reattach) for current project
  devmux ls         List active devmux sessions
  devmux kill       Kill current project's session
  devmux kill <name>  Kill a specific session

The session is named after your project directory, so running
\`devmux\` from the same folder always gets you back in.

Layout:
  ┌─────────────────┬──────────────┐
  │  Claude Code     │  Dev Server  │
  │  (60%)          │  (40%)       │
  └─────────────────┴──────────────┘
`);
}

function listSessions() {
  const out = runQuiet("tmux list-sessions -F '#{session_name} (#{session_windows} windows, created #{session_created_string})'");
  if (!out) {
    console.log("No active tmux sessions.");
    return;
  }
  console.log("Active tmux sessions:\n");
  console.log(out);
}

function killSession(name) {
  if (!name) {
    name = sessionName(process.cwd());
  }
  if (!sessionExists(name)) {
    console.log(`No session named "${name}".`);
    return;
  }
  run(`tmux kill-session -t "${name}"`);
  console.log(`Killed session "${name}".`);
}

function createOrAttach() {
  const dir = process.cwd();
  const name = sessionName(dir);
  const escapedDir = shellEscape(dir);

  // If session already exists, just attach/switch
  if (sessionExists(name)) {
    console.log(`Reattaching to session "${name}"...`);
    attach(name);
    return;
  }

  const devCmd = detectDevCommand(dir);

  console.log(`Creating session "${name}"...`);
  if (devCmd) {
    console.log(`Detected dev command: ${devCmd}`);
  } else {
    console.log("No dev server detected (no package.json or dev script found).");
    console.log("Right pane will be a shell.");
  }

  // Create session with first pane (will become the left/claude pane)
  run(`tmux new-session -d -s "${name}" -c '${escapedDir}' -x 200 -y 50`);

  // Split horizontally: creates right pane (dev server)
  // -p 40 gives the new (right) pane 40% width, leaving 60% for claude
  run(`tmux split-window -h -t "${name}":0.0 -c '${escapedDir}' -p 40`);

  // Name the window
  run(`tmux rename-window -t "${name}":0 "dev"`);

  // Right pane (0.1): start dev server or leave as shell
  if (devCmd) {
    run(`tmux send-keys -t "${name}":0.1 '${shellEscape(devCmd)}' Enter`);
  }

  // Left pane (0.0): start claude
  run(`tmux send-keys -t "${name}":0.0 'claude' Enter`);

  // Focus the left (claude) pane
  run(`tmux select-pane -t "${name}":0.0`);

  attach(name);
}

function attach(name) {
  if (isInsideTmux()) {
    // Already inside tmux — switch client instead of nesting
    execSync(`tmux switch-client -t "${name}"`, { stdio: "inherit" });
  } else {
    execSync(`tmux attach -t "${name}"`, { stdio: "inherit" });
  }
}

// ── Main ─────────────────────────────────────────────────────────────

if (!hasTmux()) {
  console.error("Error: tmux is not installed. Install it with: brew install tmux");
  process.exit(1);
}

switch (command) {
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
