#!/usr/bin/env node
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawn, spawnSync } = require("child_process");

const codexPath = "/Applications/Codex.app/Contents/Resources/codex";
const outDir = "/Applications/TokenOut.app/Contents/Resources";
const outFile = path.join(outDir, "snapshot.json");
const stateDir = path.join(os.homedir(), "Library", "Application Support", "TokenOut");
const baselineFile = path.join(stateDir, "daily-baseline.json");
const reloadAppPath = "/Applications/TokenOut.app/Contents/MacOS/TokenOut";

function number(value) {
  if (typeof value === "number") return Number.isFinite(value) ? value : undefined;
  if (typeof value === "string" && value.trim() !== "") {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : undefined;
  }
  return undefined;
}

function parseSnapshot(text) {
  for (const line of text.split(/\r?\n/)) {
    if (!line.trim()) continue;
    let root;
    try {
      root = JSON.parse(line);
    } catch {
      continue;
    }
    if (root.id !== 2 || !root.result) continue;
    const codex = root.result.rateLimitsByLimitId?.codex ?? root.result.rateLimits;
    if (!codex) continue;
    const weekly = codex.secondary ?? {};
    const short = codex.primary ?? {};
    return {
      weeklyUsed: number(weekly.usedPercent) ?? 0,
      fiveHourUsed: number(short.usedPercent) ?? 0,
      weeklyResetAt: number(weekly.resetsAt),
      weeklyDurationMins: number(weekly.windowDurationMins),
      planType: codex.planType ?? "codex",
      fetchedAt: new Date().toISOString(),
    };
  }
  throw new Error("Codex CLI returned no rate limit snapshot");
}

function localDayKey(date = new Date()) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function readPreviousSnapshot() {
  try {
    return JSON.parse(fs.readFileSync(outFile, "utf8"));
  } catch {
    return null;
  }
}

function readBaselineState() {
  try {
    return JSON.parse(fs.readFileSync(baselineFile, "utf8"));
  } catch {
    return null;
  }
}

function snapshotDayKey(snapshot) {
  if (!snapshot?.fetchedAt) return undefined;
  const date = new Date(snapshot.fetchedAt);
  if (Number.isNaN(date.getTime())) return undefined;
  return localDayKey(date);
}

function baselineFrom(source, dayKey) {
  if (source?.dayKey === dayKey && typeof source.todayStartWeeklyUsed === "number") {
    return source.todayStartWeeklyUsed;
  }
  return undefined;
}

function attachDailyBaseline(snapshot, previous, baselineState) {
  const dayKey = localDayKey();
  const previousBaseline =
    baselineFrom(baselineState, dayKey) ??
    baselineFrom(previous, dayKey) ??
    (snapshotDayKey(previous) === dayKey && typeof previous?.weeklyUsed === "number"
      ? previous.weeklyUsed
      : undefined);

  snapshot.dayKey = dayKey;
  snapshot.todayStartWeeklyUsed = previousBaseline ?? snapshot.weeklyUsed;

  if (snapshot.weeklyUsed < snapshot.todayStartWeeklyUsed) {
    snapshot.todayStartWeeklyUsed = snapshot.weeklyUsed;
  }

  return snapshot;
}

function saveBaselineState(snapshot) {
  fs.mkdirSync(stateDir, { recursive: true });
  fs.writeFileSync(
    baselineFile,
    JSON.stringify(
      {
        dayKey: snapshot.dayKey,
        todayStartWeeklyUsed: snapshot.todayStartWeeklyUsed,
        updatedAt: snapshot.fetchedAt,
      },
      null,
      2
    )
  );
}

async function main() {
  if (!fs.existsSync(codexPath)) throw new Error("Codex CLI not found");

  const child = spawn(codexPath, ["app-server", "--stdio"], {
    stdio: ["pipe", "pipe", "pipe"],
  });

  let stdout = "";
  let stderr = "";
  child.stdin.on("error", () => {});
  child.stdout.on("data", (data) => {
    stdout += data.toString("utf8");
  });
  child.stderr.on("data", (data) => {
    stderr += data.toString("utf8");
  });

  const messages = [
    {
      id: 1,
      method: "initialize",
      params: {
        clientInfo: { name: "codex-quota-agent", version: "0.1" },
        capabilities: {},
      },
    },
    { method: "initialized" },
    { id: 2, method: "account/rateLimits/read", params: null },
  ];

  for (const message of messages) {
    child.stdin.write(JSON.stringify(message) + "\n");
  }

  const snapshot = await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      child.kill("SIGTERM");
      reject(new Error(`Codex CLI timed out. ${stderr}`));
    }, 15000);

    child.stdout.on("data", () => {
      try {
        const parsed = parseSnapshot(stdout);
        clearTimeout(timeout);
        child.kill("SIGTERM");
        resolve(parsed);
      } catch {
      }
    });

    child.on("error", (error) => {
      clearTimeout(timeout);
      reject(error);
    });
    child.on("exit", () => {
      try {
        const parsed = parseSnapshot(stdout);
        clearTimeout(timeout);
        resolve(parsed);
      } catch (error) {
        clearTimeout(timeout);
        reject(error);
      }
    });
  });

  attachDailyBaseline(snapshot, readPreviousSnapshot(), readBaselineState());

  fs.mkdirSync(outDir, { recursive: true });
  const tmpFile = `${outFile}.tmp`;
  fs.writeFileSync(tmpFile, JSON.stringify(snapshot, null, 2));
  fs.renameSync(tmpFile, outFile);
  saveBaselineState(snapshot);

  if (fs.existsSync(reloadAppPath)) {
    spawnSync(reloadAppPath, ["--reload-widget"], { stdio: "ignore", timeout: 5000 });
  }

  console.log(`[TokenOut] updated ${snapshot.fetchedAt}`);
}

main().catch((error) => {
  console.error(`[TokenOut] ${error.message}`);
  process.exit(1);
});
