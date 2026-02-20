#!/usr/bin/env node

import { execSync, spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const appDir = resolve(__dirname, "../app");
const bundlePath = resolve(appDir, "DevmuxApp.app");
const binaryPath = resolve(bundlePath, "Contents/MacOS/DevmuxApp");
const buildOutput = resolve(appDir, ".build/release/DevmuxApp");

function hasSwift() {
  try {
    execSync("which swift", { stdio: "pipe" });
    return true;
  } catch {
    return false;
  }
}

function isRunning() {
  try {
    execSync("pgrep -f DevmuxApp.app", { stdio: "pipe" });
    return true;
  } catch {
    return false;
  }
}

function build() {
  if (!hasSwift()) {
    console.error("Swift is required to build the devmux menu bar app.");
    console.error("Install Xcode or Xcode Command Line Tools:");
    console.error("  xcode-select --install");
    process.exit(1);
  }

  console.log("Building devmux menu bar app...");
  try {
    execSync("swift build -c release", {
      cwd: appDir,
      stdio: "inherit",
    });
  } catch {
    console.error("Build failed.");
    process.exit(1);
  }

  // Copy binary into .app bundle
  execSync(`cp '${buildOutput}' '${binaryPath}'`);
  console.log("Build complete.");
}

function launch() {
  if (isRunning()) {
    console.log("devmux app is already running.");
    return;
  }

  spawn("open", [bundlePath], { detached: true, stdio: "ignore" }).unref();
  console.log("devmux app launched.");
}

// --- Main ---

const cmd = process.argv[2];

if (cmd === "build") {
  build();
} else if (cmd === "quit") {
  try {
    execSync("pkill -f DevmuxApp.app", { stdio: "pipe" });
    console.log("devmux app stopped.");
  } catch {
    console.log("devmux app is not running.");
  }
} else {
  // Default: build if needed, then launch
  if (!existsSync(binaryPath)) {
    build();
  }
  launch();
}
