#!/usr/bin/env node

import { execSync, spawn } from "node:child_process";
import { existsSync, mkdirSync, chmodSync, createWriteStream } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { get } from "node:https";

const __dirname = dirname(fileURLToPath(import.meta.url));
const appDir = resolve(__dirname, "../app");
const bundlePath = resolve(appDir, "DevmuxApp.app");
const binaryDir = resolve(bundlePath, "Contents/MacOS");
const binaryPath = resolve(binaryDir, "DevmuxApp");

const REPO = "arach/devmux";
const ASSET_NAME = "DevmuxApp-macos-universal";

// ── Helpers ──────────────────────────────────────────────────────────

function isRunning() {
  try {
    execSync("pgrep -f DevmuxApp.app", { stdio: "pipe" });
    return true;
  } catch {
    return false;
  }
}

function hasSwift() {
  try {
    execSync("which swift", { stdio: "pipe" });
    return true;
  } catch {
    return false;
  }
}

function launch() {
  if (isRunning()) {
    console.log("devmux app is already running.");
    return;
  }
  spawn("open", [bundlePath], { detached: true, stdio: "ignore" }).unref();
  console.log("devmux app launched.");
}

// ── Download from GitHub releases ────────────────────────────────────

function httpsGet(url) {
  return new Promise((resolve, reject) => {
    get(url, { headers: { "User-Agent": "devmux" } }, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        return httpsGet(res.headers.location).then(resolve, reject);
      }
      if (res.statusCode !== 200) {
        reject(new Error(`HTTP ${res.statusCode}`));
        res.resume();
        return;
      }
      resolve(res);
    }).on("error", reject);
  });
}

async function download() {
  console.log("Downloading devmux app...");

  try {
    // Get latest release asset URL
    const apiUrl = `https://api.github.com/repos/${REPO}/releases/latest`;
    const apiRes = await httpsGet(apiUrl);
    const chunks = [];
    for await (const chunk of apiRes) chunks.push(chunk);
    const release = JSON.parse(Buffer.concat(chunks).toString());

    const asset = release.assets?.find((a) => a.name === ASSET_NAME);
    if (!asset) throw new Error("Binary not found in release assets");

    // Download the binary
    const dlRes = await httpsGet(asset.browser_download_url);

    mkdirSync(binaryDir, { recursive: true });
    const ws = createWriteStream(binaryPath);
    await new Promise((resolve, reject) => {
      dlRes.pipe(ws);
      ws.on("finish", resolve);
      ws.on("error", reject);
    });

    chmodSync(binaryPath, 0o755);
    console.log("Download complete.");
    return true;
  } catch (e) {
    console.log(`Download failed: ${e.message}`);
    return false;
  }
}

// ── Build from source ────────────────────────────────────────────────

function buildFromSource() {
  if (!hasSwift()) {
    console.error(
      "Cannot download pre-built binary and Swift is not installed.\n" +
      "Either:\n" +
      "  1. Wait for a release with pre-built binaries\n" +
      "  2. Install Xcode CLI tools: xcode-select --install"
    );
    process.exit(1);
  }

  console.log("Building devmux app from source...");
  try {
    execSync("swift build -c release --arch arm64 --arch x86_64", {
      cwd: appDir,
      stdio: "inherit",
    });
  } catch {
    // Fallback: build for current arch only
    try {
      execSync("swift build -c release", {
        cwd: appDir,
        stdio: "inherit",
      });
    } catch {
      console.error("Build failed.");
      process.exit(1);
    }
  }

  // Find the built binary
  const universalPath = resolve(appDir, ".build/apple/Products/Release/DevmuxApp");
  const debugPath = resolve(appDir, ".build/release/DevmuxApp");
  const builtPath = existsSync(universalPath) ? universalPath : debugPath;

  mkdirSync(binaryDir, { recursive: true });
  execSync(`cp '${builtPath}' '${binaryPath}'`);
  console.log("Build complete.");
}

// ── Commands ─────────────────────────────────────────────────────────

async function ensureBinary() {
  if (existsSync(binaryPath)) return;

  // Try download first, fall back to source build
  const downloaded = await download();
  if (!downloaded) {
    buildFromSource();
  }
}

const cmd = process.argv[2];

if (cmd === "build") {
  buildFromSource();
} else if (cmd === "quit") {
  try {
    execSync("pkill -f DevmuxApp.app", { stdio: "pipe" });
    console.log("devmux app stopped.");
  } catch {
    console.log("devmux app is not running.");
  }
} else {
  await ensureBinary();
  launch();
}
