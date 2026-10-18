import { createHash, randomUUID } from "node:crypto";
import { mkdir, readFile, rename, rm, stat, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { spawn } from "node:child_process";

export const LOCK_TIMEOUT_MS = 10 * 60 * 1000;
export const STALE_LOCK_MS = 15 * 60 * 1000;
export const POLL_MS = 250;

const appRoot = resolve(import.meta.dirname, "../../../apps/cadence_web");

export function lockDirectoryFor(root = appRoot) {
  const lockName = createHash("sha256").update(root).digest("hex").slice(0, 16);
  return resolve(tmpdir(), `cadence-federation-publication-${lockName}.lock`);
}

const lockDirectory = lockDirectoryFor();

/** @param {number} milliseconds @returns {Promise<void>} */
function sleep(milliseconds) {
  return new Promise((resolveSleep) => setTimeout(resolveSleep, milliseconds));
}

/** @param {string} lockPath */
function mutationDirectoryFor(lockPath) {
  return `${lockPath}.mutation`;
}

/** @param {number} pid */
export function processIsAlive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return errorCode(error) === "EPERM";
  }
}

/** @param {string} value */
function parseOwner(value) {
  const [pidText, token] = value.trim().split(":", 2);
  const pid = Number(pidText);
  if (!Number.isInteger(pid) || pid <= 0 || !token) return null;
  return { pid, token };
}

/** @param {string} lockPath */
async function lockState(lockPath, { statFn = stat, readFileFn = readFile } = {}) {
  let lockStat;
  try {
    lockStat = await statFn(lockPath);
  } catch (error) {
    if (errorCode(error) === "ENOENT") return null;
    throw error;
  }

  let owner = null;
  try {
    owner = parseOwner(await readFileFn(join(lockPath, "owner"), "utf8"));
  } catch (error) {
    if (errorCode(error) !== "ENOENT") throw error;
  }

  return { mtimeMs: lockStat.mtimeMs, owner };
}

/** @param {string} lockPath */
async function acquireMutation(
  lockPath,
  {
    timeout = LOCK_TIMEOUT_MS,
    pollMs = POLL_MS,
    processAlive = processIsAlive,
    sleepFn = sleep,
    randomId = randomUUID,
    mkdirFn = mkdir,
    writeFileFn = writeFile,
    rmFn = rm,
    statFn = stat,
    readFileFn = readFile,
  } = {},
) {
  const mutationPath = mutationDirectoryFor(lockPath);
  const deadline = Date.now() + timeout;
  const token = randomId();
  let invalidOwnerObserved = false;

  while (Date.now() < deadline) {
    let created = false;
    try {
      await mkdirFn(mutationPath);
      created = true;
      await writeFileFn(join(mutationPath, "owner"), `${process.pid}:${token}\n`, { mode: 0o600 });
      return () => releaseMutation(mutationPath, token, { rmFn, statFn, readFileFn });
    } catch (error) {
      if (created) await rmFn(mutationPath, { recursive: true, force: true });
      if (errorCode(error) !== "EEXIST") throw error;

      const state = await lockState(mutationPath, { statFn, readFileFn });
      if (state?.owner?.pid && !processAlive(state.owner.pid)) {
        throw new Error(
          `publication lock mutation gate has a dead owner; recover ${mutationPath} manually`,
        );
      }
      invalidOwnerObserved ||= !state?.owner;
      await sleepFn(pollMs);
    }
  }

  if (invalidOwnerObserved) {
    throw new Error(
      `publication lock mutation gate has no valid owner; recover ${mutationPath} manually`,
    );
  }
  throw new Error(`timed out waiting for publication lock mutation gate: ${mutationPath}`);
}

/** @param {string} mutationPath @param {string} token */
async function releaseMutation(
  mutationPath,
  token,
  { rmFn = rm, statFn = stat, readFileFn = readFile } = {},
) {
  const state = await lockState(mutationPath, { statFn, readFileFn });
  if (!state?.owner || state.owner.token !== token) return false;
  await rmFn(mutationPath, { recursive: true, force: true });
  return true;
}

/** @param {string} lockPath */
export async function isStaleLock(
  lockPath,
  {
    now = Date.now,
    staleAfter = STALE_LOCK_MS,
    processAlive = processIsAlive,
    statFn = stat,
    readFileFn = readFile,
  } = {},
) {
  const state = await lockState(lockPath, { statFn, readFileFn });
  if (!state) return false;

  // A live owner is never stale merely because its directory is old.
  if (state.owner?.pid && processAlive(state.owner.pid)) return false;
  if (state.owner?.pid) return true;
  return now() - state.mtimeMs > staleAfter;
}

/** @param {string} lockPath */
export async function claimStaleLock(
  lockPath,
  {
    now = Date.now,
    staleAfter = STALE_LOCK_MS,
    processAlive = processIsAlive,
    randomId = randomUUID,
    timeout = LOCK_TIMEOUT_MS,
    pollMs = POLL_MS,
    sleepFn = sleep,
    mkdirFn = mkdir,
    writeFileFn = writeFile,
    renameFn = rename,
    rmFn = rm,
    statFn = stat,
    readFileFn = readFile,
  } = {},
) {
  const releaseMutationLock = await acquireMutation(lockPath, {
    timeout,
    pollMs,
    processAlive,
    sleepFn,
    randomId,
    mkdirFn,
    writeFileFn,
    rmFn,
    statFn,
    readFileFn,
  });
  const claimPath = `${lockPath}.stale-${process.pid}-${randomId()}`;
  let moved = false;
  try {
    if (!(await isStaleLock(lockPath, { now, staleAfter, processAlive, statFn, readFileFn }))) {
      return false;
    }

    // All protocol participants hold the mutation gate, so this rename cannot move a
    // replacement generation that was created after the stale state was observed.
    try {
      await renameFn(lockPath, claimPath);
      moved = true;
    } catch (error) {
      if (["ENOENT", "EEXIST", "ENOTEMPTY"].some((code) => code === errorCode(error))) return false;
      throw error;
    }

    const claimed = await lockState(claimPath, { statFn, readFileFn });
    if (claimed?.owner?.pid && processAlive(claimed.owner.pid)) {
      if (await lockState(lockPath, { statFn, readFileFn })) {
        throw new Error(
          `publication lock generation changed during stale recovery; recover ${lockPath} manually`,
        );
      }
      await renameFn(claimPath, lockPath);
      moved = false;
      return false;
    }

    await rmFn(claimPath, { recursive: true, force: true });
    moved = false;
    return true;
  } catch (error) {
    if (moved) {
      try {
        if (!(await lockState(lockPath, { statFn, readFileFn }))) {
          await renameFn(claimPath, lockPath);
          moved = false;
        }
      } catch (restoreError) {
        throw new Error("could not restore the publication lock after stale recovery failed", {
          cause: restoreError,
        });
      }
    }
    throw error;
  } finally {
    await releaseMutationLock();
  }
}

/** @param {string} lockPath @param {string} token */
export async function releaseLock(
  lockPath,
  token,
  {
    renameFn = rename,
    rmFn = rm,
    statFn = stat,
    readFileFn = readFile,
    randomId = randomUUID,
    timeout = LOCK_TIMEOUT_MS,
    pollMs = POLL_MS,
    sleepFn = sleep,
    mkdirFn = mkdir,
    writeFileFn = writeFile,
  } = {},
) {
  const releaseMutationLock = await acquireMutation(lockPath, {
    timeout,
    pollMs,
    sleepFn,
    randomId,
    mkdirFn,
    writeFileFn,
    rmFn,
    statFn,
    readFileFn,
  });
  const releasePath = `${lockPath}.release-${process.pid}-${randomId()}`;
  let moved = false;
  try {
    // Move the generation first. Ownership is verified in the moved generation,
    // before it can ever be recursively removed.
    try {
      await renameFn(lockPath, releasePath);
      moved = true;
    } catch (error) {
      if (errorCode(error) === "ENOENT") return false;
      throw error;
    }

    const movedState = await lockState(releasePath, { statFn, readFileFn });
    if (!movedState?.owner || movedState.owner.token !== token) {
      await renameFn(releasePath, lockPath);
      moved = false;
      return false;
    }

    await rmFn(releasePath, { recursive: true, force: true });
    moved = false;
    return true;
  } catch (error) {
    if (moved) {
      try {
        if (!(await lockState(lockPath, { statFn, readFileFn }))) {
          await renameFn(releasePath, lockPath);
          moved = false;
        }
      } catch (restoreError) {
        throw new Error("could not restore the publication lock after release failed", {
          cause: restoreError,
        });
      }
    }
    throw error;
  } finally {
    await releaseMutationLock();
  }
}

export async function acquireLock(
  lockPath = lockDirectory,
  {
    timeout = LOCK_TIMEOUT_MS,
    pollMs = POLL_MS,
    staleAfter = STALE_LOCK_MS,
    processAlive = processIsAlive,
    sleepFn = sleep,
    randomId = randomUUID,
    mkdirFn = mkdir,
    writeFileFn = writeFile,
    rmFn = rm,
    statFn = stat,
    readFileFn = readFile,
    renameFn = rename,
  } = {},
) {
  const deadline = Date.now() + timeout;
  const token = randomId();

  while (Date.now() < deadline) {
    const releaseMutationLock = await acquireMutation(lockPath, {
      timeout: Math.max(1, deadline - Date.now()),
      pollMs,
      processAlive,
      sleepFn,
      randomId,
      mkdirFn,
      writeFileFn,
      rmFn,
      statFn,
      readFileFn,
    });
    let created = false;
    try {
      await mkdirFn(lockPath);
      created = true;
      await writeFileFn(join(lockPath, "owner"), `${process.pid}:${token}\n`, { mode: 0o600 });
      await releaseMutationLock();
      return () =>
        releaseLock(lockPath, token, {
          renameFn,
          rmFn,
          statFn,
          readFileFn,
          randomId,
          timeout,
          pollMs,
          sleepFn,
          mkdirFn,
          writeFileFn,
        });
    } catch (error) {
      try {
        if (created) await rmFn(lockPath, { recursive: true, force: true });
      } finally {
        await releaseMutationLock();
      }
      if (errorCode(error) !== "EEXIST") throw error;
      if (
        await claimStaleLock(lockPath, {
          staleAfter,
          processAlive,
          randomId,
          timeout: Math.max(1, deadline - Date.now()),
          pollMs,
          sleepFn,
          mkdirFn,
          writeFileFn,
          renameFn,
          rmFn,
          statFn,
          readFileFn,
        })
      ) {
        continue;
      }
      await sleepFn(pollMs);
    }
  }

  throw new Error(`timed out waiting for federation publication build lock: ${lockPath}`);
}

/** @param {string[]} taskArgs @returns {Promise<number>} */
function runMixTask(taskArgs) {
  return new Promise((resolveRun, rejectRun) => {
    const child = spawn(process.env.MIX || "mix", taskArgs, {
      cwd: appRoot,
      env: process.env,
      stdio: "inherit",
    });
    /** @param {NodeJS.Signals} signal */
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

const isMain = process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href;
if (isMain) {
  const release = await acquireLock();
  try {
    process.exitCode = await runMixTask(process.argv.slice(2));
  } finally {
    await release();
  }
}

/** @param {unknown} error */
function errorCode(error) {
  return error instanceof Error && "code" in error && typeof error.code === "string"
    ? error.code
    : undefined;
}
