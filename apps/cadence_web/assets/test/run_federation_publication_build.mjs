import { createHash } from "node:crypto";
import { mkdir, readFile, rm, stat, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { resolve } from "node:path";
import { spawn } from "node:child_process";

const LOCK_TIMEOUT_MS = 10 * 60 * 1000;
const STALE_LOCK_MS = 15 * 60 * 1000;
const POLL_MS = 250;
const appRoot = resolve(import.meta.dirname, "../..");
const lockName = createHash("sha256").update(appRoot).digest("hex").slice(0, 16);
const lockDirectory = resolve(tmpdir(), `cadence-federation-publication-${lockName}.lock`);

function sleep(milliseconds) {
  return new Promise((resolveSleep) => setTimeout(resolveSleep, milliseconds));
}

function processIsAlive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return error?.code === "EPERM";
  }
}

async function staleLock() {
  try {
    const lockStat = await stat(lockDirectory);
    if (Date.now() - lockStat.mtimeMs > STALE_LOCK_MS) return true;
    const owner = Number((await readFile(`${lockDirectory}/owner`, "utf8")).trim());
    return Number.isInteger(owner) && owner > 0 && !processIsAlive(owner);
  } catch (error) {
    return false;
  }
}

async function acquireLock() {
  const deadline = Date.now() + LOCK_TIMEOUT_MS;
  while (Date.now() < deadline) {
    try {
      await mkdir(lockDirectory);
      await writeFile(`${lockDirectory}/owner`, `${process.pid}\n`, { mode: 0o600 });
      return async () => rm(lockDirectory, { recursive: true, force: true });
    } catch (error) {
      if (error?.code !== "EEXIST") throw error;
      if (await staleLock()) await rm(lockDirectory, { recursive: true, force: true });
      else await sleep(POLL_MS);
    }
  }
  throw new Error(`timed out waiting for federation publication build lock: ${lockDirectory}`);
}

function runMixTask(taskArgs) {
  return new Promise((resolveRun, rejectRun) => {
    const child = spawn(process.env.MIX || "mix", taskArgs, {
      cwd: appRoot,
      env: process.env,
      stdio: "inherit",
    });
    const onSignal = (signal) => child.kill(signal);
    process.once("SIGINT", onSignal);
    process.once("SIGTERM", onSignal);
    child.once("error", (error) => {
      process.removeListener("SIGINT", onSignal);
      process.removeListener("SIGTERM", onSignal);
      rejectRun(error);
    });
    child.once("exit", (code, signal) => {
      process.removeListener("SIGINT", onSignal);
      process.removeListener("SIGTERM", onSignal);
      resolveRun(code ?? 128 + (signal ? 1 : 0));
    });
  });
}

const release = await acquireLock();
try {
  process.exitCode = await runMixTask(process.argv.slice(2));
} finally {
  await release();
}
