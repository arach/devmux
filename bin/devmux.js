#!/usr/bin/env node

import { createHash } from "node:crypto";
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

function pathHash(dir) {
  return createHash("sha256").update(resolve(dir)).digest("hex").slice(0, 6);
}

function toSessionName(dir) {
  const base = basename(dir).replace(/[^a-zA-Z0-9_-]/g, "-");
  return `${base}-${pathHash(dir)}`;
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
  return panes.map((p) => ({
    name: p.name || "",
    cmd: p.cmd || undefined,
    size: p.size || undefined,
  }));
}

/** Get ordered pane IDs (e.g. ["%0", "%1"]) for a session */
function getPaneIds(name) {
  const out = runQuiet(
    `tmux list-panes -t "${name}" -F "#{pane_id}"`
  );
  return out ? out.split("\n").filter(Boolean) : [];
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
    const devCmd = detectDevCommand(dir);
    panes = [
      { name: "claude", cmd: "claude", size: 60 },
      { name: "server", cmd: devCmd || undefined },
    ];
    if (devCmd) console.log(`Detected: ${devCmd}`);
  }

  // Create session (targets are config-agnostic — no hardcoded indices)
  run(`tmux new-session -d -s "${name}" -c '${d}'`);

  if (panes.length === 2) {
    const mainSize = panes[0].size || 60;
    run(
      `tmux split-window -h -t "${name}" -c '${d}' -p ${100 - mainSize}`
    );
  } else if (panes.length >= 3) {
    const mainSize = panes[0].size || 60;
    for (let i = 1; i < panes.length; i++) {
      run(`tmux split-window -t "${name}" -c '${d}'`);
    }
    runQuiet(
      `tmux set-option -t "${name}" -w main-pane-width '${mainSize}%'`
    );
    run(`tmux select-layout -t "${name}" main-vertical`);
  }

  // Get actual pane IDs (works regardless of base-index / pane-base-index)
  const paneIds = getPaneIds(name);

  // Send commands and name each pane
  for (let i = 0; i < panes.length && i < paneIds.length; i++) {
    if (panes[i].cmd) {
      run(`tmux send-keys -t "${paneIds[i]}" '${esc(panes[i].cmd)}' Enter`);
    }
    if (panes[i].name) {
      runQuiet(`tmux select-pane -t "${paneIds[i]}" -T "${panes[i].name}"`);
    }
  }

  // Tag the terminal window title so the menu bar app can find it
  // Format: [devmux:session-hash] pane_title: current_command
  runQuiet(`tmux set-option -t "${name}" set-titles on`);
  runQuiet(`tmux set-option -t "${name}" set-titles-string "[devmux:${name}] #{pane_title}"`);

  // Name the tmux window after the project and focus the first pane
  runQuiet(`tmux rename-window -t "${name}" "${basename(dir)}"`);
  if (paneIds.length) {
    run(`tmux select-pane -t "${paneIds[0]}"`);
  }

  return name;
}

/** Check each pane and prefill or restart commands that have exited.
 *  mode: "prefill" types the command without pressing Enter
 *  mode: "ensure" types the command and presses Enter */
function restoreCommands(name, dir, mode) {
  const config = readConfig(dir);
  let panes;
  if (config?.panes?.length) {
    panes = resolvePane(config.panes, dir);
  } else {
    const devCmd = detectDevCommand(dir);
    panes = [
      { name: "claude", cmd: "claude", size: 60 },
      { name: "server", cmd: devCmd || undefined },
    ];
  }

  const paneIds = getPaneIds(name);
  const shells = new Set(["bash", "zsh", "fish", "sh", "dash"]);

  let count = 0;
  for (let i = 0; i < panes.length && i < paneIds.length; i++) {
    if (!panes[i].cmd) continue;
    const cur = runQuiet(
      `tmux display-message -t "${paneIds[i]}" -p "#{pane_current_command}"`
    );
    if (cur && shells.has(cur)) {
      if (mode === "ensure") {
        run(`tmux send-keys -t "${paneIds[i]}" '${esc(panes[i].cmd)}' Enter`);
      } else {
        run(`tmux send-keys -t "${paneIds[i]}" '${esc(panes[i].cmd)}'`);
      }
      count++;
    }
  }
  if (count > 0) {
    const verb = mode === "ensure" ? "Restarted" : "Prefilled";
    console.log(`${verb} ${count} exited command${count > 1 ? "s" : ""}`);
  }
}

// ── Sync / reconcile ────────────────────────────────────────────────

function resolvePanes(dir) {
  const config = readConfig(dir);
  if (config?.panes?.length) {
    return resolvePane(config.panes, dir);
  }
  const devCmd = detectDevCommand(dir);
  return [
    { name: "claude", cmd: "claude", size: 60 },
    { name: "server", cmd: devCmd || undefined },
  ];
}

function syncSession() {
  const dir = process.cwd();
  const name = toSessionName(dir);

  if (!sessionExists(name)) {
    console.log(`No session "${name}" — creating from scratch.`);
    createSession(dir);
    console.log("Session created.");
    return;
  }

  const panes = resolvePanes(dir);
  const actualIds = getPaneIds(name);
  const declared = panes.length;
  const actual = actualIds.length;
  const d = esc(dir);
  const shells = new Set(["bash", "zsh", "fish", "sh", "dash"]);

  console.log(`Session "${name}": ${actual} pane(s) found, ${declared} declared.`);

  // Phase 1: recreate missing panes
  if (actual < declared) {
    const missing = declared - actual;
    console.log(`Recreating ${missing} missing pane(s)...`);
    for (let i = 0; i < missing; i++) {
      run(`tmux split-window -t "${name}" -c '${d}'`);
    }

    // Re-apply layout
    if (declared === 2) {
      const mainSize = panes[0].size || 60;
      // With 2 panes, use horizontal split layout
      run(`tmux select-layout -t "${name}" even-horizontal`);
      runQuiet(
        `tmux set-option -t "${name}" -w main-pane-width '${mainSize}%'`
      );
      run(`tmux select-layout -t "${name}" main-vertical`);
    } else if (declared >= 3) {
      const mainSize = panes[0].size || 60;
      runQuiet(
        `tmux set-option -t "${name}" -w main-pane-width '${mainSize}%'`
      );
      run(`tmux select-layout -t "${name}" main-vertical`);
    }
  }

  // Phase 2: restore commands and labels on all panes
  const freshIds = getPaneIds(name);
  let restored = 0;
  for (let i = 0; i < panes.length && i < freshIds.length; i++) {
    // Set pane title/label
    if (panes[i].name) {
      runQuiet(`tmux select-pane -t "${freshIds[i]}" -T "${panes[i].name}"`);
    }
    // If pane is idle at a shell prompt, send its declared command
    if (panes[i].cmd) {
      const cur = runQuiet(
        `tmux display-message -t "${freshIds[i]}" -p "#{pane_current_command}"`
      );
      if (cur && shells.has(cur)) {
        run(`tmux send-keys -t "${freshIds[i]}" '${esc(panes[i].cmd)}' Enter`);
        restored++;
      }
    }
  }

  // Focus first pane
  if (freshIds.length) {
    run(`tmux select-pane -t "${freshIds[0]}"`);
  }

  if (restored > 0) {
    console.log(`Restarted ${restored} command(s).`);
  }
  console.log("Sync complete.");
}

// ── Restart pane ────────────────────────────────────────────────────

function restartPane(target) {
  const dir = process.cwd();
  const name = toSessionName(dir);

  if (!sessionExists(name)) {
    console.log(`No session "${name}".`);
    return;
  }

  const panes = resolvePanes(dir);
  const paneIds = getPaneIds(name);

  // Resolve target to an index
  let idx;
  if (target === undefined || target === null || target === "") {
    // Default: first pane (claude)
    idx = 0;
  } else if (/^\d+$/.test(target)) {
    idx = parseInt(target, 10);
  } else {
    // Match by name (case-insensitive)
    idx = panes.findIndex(
      (p) => p.name && p.name.toLowerCase() === target.toLowerCase()
    );
    if (idx === -1) {
      console.log(
        `No pane named "${target}". Available: ${panes.map((p, i) => p.name || `[${i}]`).join(", ")}`
      );
      return;
    }
  }

  if (idx < 0 || idx >= paneIds.length) {
    console.log(`Pane index ${idx} is out of range (${paneIds.length} panes).`);
    return;
  }

  const paneId = paneIds[idx];
  const pane = panes[idx] || {};
  const label = pane.name || `pane ${idx}`;

  // Get the PID of the process running in the pane
  const panePid = runQuiet(
    `tmux display-message -t "${paneId}" -p "#{pane_pid}"`
  );

  // Step 1: try C-c to gracefully stop
  console.log(`Stopping ${label}...`);
  run(`tmux send-keys -t "${paneId}" C-c`);

  // Brief pause to let C-c propagate
  execSync("sleep 0.5");

  // Step 2: check if the process is still running (not back to shell)
  const shells = new Set(["bash", "zsh", "fish", "sh", "dash"]);
  const cur = runQuiet(
    `tmux display-message -t "${paneId}" -p "#{pane_current_command}"`
  );

  if (cur && !shells.has(cur)) {
    // Still hung — escalate: kill the child processes of the pane
    console.log(`Process still running (${cur}), sending SIGKILL...`);
    if (panePid) {
      // Kill all children of the pane's shell process
      runQuiet(`pkill -KILL -P ${panePid}`);
      execSync("sleep 0.3");
    }
  }

  // Step 3: send the declared command
  if (pane.cmd) {
    console.log(`Starting: ${pane.cmd}`);
    run(`tmux send-keys -t "${paneId}" '${esc(pane.cmd)}' Enter`);
  } else {
    console.log(`No command declared for ${label} — pane is at shell prompt.`);
  }
}

// ── Commands ─────────────────────────────────────────────────────────

function printUsage() {
  console.log(`devmux — Claude Code + dev server in tmux

Usage:
  devmux                    Create session (or reattach) for current project
  devmux init               Generate .devmux.json config for this project
  devmux ls                 List active tmux sessions
  devmux kill [name]        Kill a session (defaults to current project)
  devmux sync               Reconcile session to match declared config
  devmux restart [pane]     Restart a pane's process (by name or index)
  devmux app                Launch the menu bar companion app
  devmux app build          Rebuild the menu bar app
  devmux app restart        Rebuild and relaunch the menu bar app
  devmux app quit           Stop the menu bar app
  devmux help               Show this help

Config (.devmux.json):
  Place in your project root to customize the layout:

  {
    "ensure": true,
    "panes": [
      { "name": "claude", "cmd": "claude", "size": 60 },
      { "name": "server", "cmd": "pnpm dev" },
      { "name": "tests",  "cmd": "pnpm test --watch" }
    ]
  }

  size      Width % for the first pane (default: 60)
  cmd       Command to run in the pane
  name      Label (for your reference)
  ensure    Auto-restart exited commands on reattach
  prefill   Type commands into idle panes on reattach (you hit Enter)

Recovery:
  devmux sync       Recreates missing panes, restores commands, fixes layout.
                    Use when a pane was killed and you want to get back to the
                    declared state without killing the whole session.

  devmux restart    Kills the process in a pane and re-runs its declared command.
                    Accepts a pane name or 0-based index (default: 0 / first pane).
                    Examples:  devmux restart         (restarts "claude")
                               devmux restart server  (restarts "server" by name)
                               devmux restart 1       (restarts pane at index 1)

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
    ensure: true,
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

// ── Window tiling ────────────────────────────────────────────────────

function getScreenBounds() {
  // Get the visible area (excludes menu bar and dock) in AppleScript coordinates (top-left origin)
  const script = `
    tell application "Finder"
      set db to bounds of window of desktop
    end tell
    -- db = {left, top, right, bottom} of usable desktop
    return (item 1 of db) & "," & (item 2 of db) & "," & (item 3 of db) & "," & (item 4 of db)`;
  const out = runQuiet(`osascript -e '${esc(script)}'`);
  if (!out) return { x: 0, y: 25, w: 1920, h: 1055 };
  const [x, y, right, bottom] = out.split(",").map(s => parseInt(s.trim()));
  return { x, y, w: right - x, h: bottom - y };
}

// Presets return AppleScript bounds: [left, top, right, bottom] within the visible area
const tilePresets = {
  "left":         (s) => [s.x, s.y, s.x + s.w / 2, s.y + s.h],
  "left-half":    (s) => [s.x, s.y, s.x + s.w / 2, s.y + s.h],
  "right":        (s) => [s.x + s.w / 2, s.y, s.x + s.w, s.y + s.h],
  "right-half":   (s) => [s.x + s.w / 2, s.y, s.x + s.w, s.y + s.h],
  "top":          (s) => [s.x, s.y, s.x + s.w, s.y + s.h / 2],
  "top-half":     (s) => [s.x, s.y, s.x + s.w, s.y + s.h / 2],
  "bottom":       (s) => [s.x, s.y + s.h / 2, s.x + s.w, s.y + s.h],
  "bottom-half":  (s) => [s.x, s.y + s.h / 2, s.x + s.w, s.y + s.h],
  "top-left":     (s) => [s.x, s.y, s.x + s.w / 2, s.y + s.h / 2],
  "top-right":    (s) => [s.x + s.w / 2, s.y, s.x + s.w, s.y + s.h / 2],
  "bottom-left":  (s) => [s.x, s.y + s.h / 2, s.x + s.w / 2, s.y + s.h],
  "bottom-right": (s) => [s.x + s.w / 2, s.y + s.h / 2, s.x + s.w, s.y + s.h],
  "maximize":     (s) => [s.x, s.y, s.x + s.w, s.y + s.h],
  "max":          (s) => [s.x, s.y, s.x + s.w, s.y + s.h],
  "center":       (s) => {
    const mw = Math.round(s.w * 0.7);
    const mh = Math.round(s.h * 0.8);
    const mx = s.x + Math.round((s.w - mw) / 2);
    const my = s.y + Math.round((s.h - mh) / 2);
    return [mx, my, mx + mw, my + mh];
  },
};

function tileWindow(position) {
  const preset = tilePresets[position];
  if (!preset) {
    console.log(`Unknown position: ${position}`);
    console.log(`Available: ${Object.keys(tilePresets).filter(k => !k.includes("-half") && k !== "max").join(", ")}`);
    return;
  }
  const screen = getScreenBounds();
  const [x1, y1, x2, y2] = preset(screen).map(Math.round);
  const script = `
    tell application "System Events"
      set frontApp to name of first application process whose frontmost is true
    end tell
    tell application frontApp
      set bounds of front window to {${x1}, ${y1}, ${x2}, ${y2}}
    end tell`;
  runQuiet(`osascript -e '${esc(script)}'`);
  console.log(`Tiled → ${position}`);
}

function createOrAttach() {
  const dir = process.cwd();
  const name = toSessionName(dir);

  if (sessionExists(name)) {
    console.log(`Reattaching to "${name}"...`);
    const config = readConfig(dir);
    if (config?.ensure) {
      restoreCommands(name, dir, "ensure");
    } else if (config?.prefill) {
      restoreCommands(name, dir, "prefill");
    }
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
  case "sync":
  case "reconcile":
    syncSession();
    break;
  case "restart":
  case "respawn":
    restartPane(args[1]);
    break;
  case "tile":
  case "t":
    if (args[1]) {
      tileWindow(args[1]);
    } else {
      console.log("Usage: devmux tile <position>\n");
      console.log("Positions: left, right, top, bottom, top-left, top-right,");
      console.log("           bottom-left, bottom-right, maximize, center");
    }
    break;
  case "app": {
    // Forward to devmux-app script
    const { execFileSync } = await import("node:child_process");
    const { dirname, resolve } = await import("node:path");
    const { fileURLToPath } = await import("node:url");
    const __dirname = dirname(fileURLToPath(import.meta.url));
    const appScript = resolve(__dirname, "devmux-app.js");
    try {
      execFileSync("node", [appScript, ...args.slice(1)], { stdio: "inherit" });
    } catch { /* exit code forwarded */ }
    break;
  }
  case "-h":
  case "--help":
  case "help":
    printUsage();
    break;
  default:
    createOrAttach();
}
