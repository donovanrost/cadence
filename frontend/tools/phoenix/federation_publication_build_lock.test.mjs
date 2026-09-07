import assert from "node:assert/strict";
import { mkdir, mkdtemp, readFile, rename, rm, utimes, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import {
  acquireLock,
  claimStaleLock,
  isStaleLock,
  releaseLock,
} from "./run_federation_publication_build.mjs";

async function temporaryLock() {
  const directory = await mkdtemp(join(tmpdir(), "cadence-publication-lock-test-"));
  return { directory, lockPath: join(directory, "publication.lock") };
}

test("atomic stale claims serialize two contenders without deleting the replacement lock", async () => {
  const { directory, lockPath } = await temporaryLock();
  const processAlive = (pid) => pid === process.pid;
  try {
    await mkdir(lockPath);
    await writeFile(join(lockPath, "owner"), `${process.pid + 1_000_000}:dead-owner\n`, {
      mode: 0o600,
    });

    const contenderA = acquireLock(lockPath, { processAlive, pollMs: 5, timeout: 1_000 });
    const contenderB = acquireLock(lockPath, { processAlive, pollMs: 5, timeout: 1_000 });
    const firstRelease = await Promise.race([contenderA, contenderB]);
    assert.equal(await firstRelease(), true);

    const releases = await Promise.all([contenderA, contenderB]);
    const releaseResults = await Promise.all(releases.map((release) => release()));
    assert.equal(releaseResults.filter(Boolean).length, 1);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("an old lock owned by a live PID is never stale and cannot be released by another token", async () => {
  const { directory, lockPath } = await temporaryLock();
  try {
    await mkdir(lockPath);
    await writeFile(join(lockPath, "owner"), `${process.pid}:live-owner\n`, { mode: 0o600 });
    const old = new Date(Date.now() - 60 * 60 * 1000);
    await utimes(lockPath, old, old);

    assert.equal(await isStaleLock(lockPath, { processAlive: () => true }), false);
    await assert.rejects(
      acquireLock(lockPath, { processAlive: () => true, pollMs: 5, timeout: 30 }),
      /timed out waiting for federation publication build lock/,
    );
    assert.equal(await releaseLock(lockPath, "wrong-owner-token"), false);
    assert.equal(await readFile(join(lockPath, "owner"), "utf8"), `${process.pid}:live-owner\n`);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("a dead owner is atomically claimed and only the claimant can release the new lock", async () => {
  const { directory, lockPath } = await temporaryLock();
  try {
    await mkdir(lockPath);
    await writeFile(join(lockPath, "owner"), `${process.pid + 1_000_000}:dead-owner\n`, {
      mode: 0o600,
    });

    const release = await acquireLock(lockPath, {
      processAlive: () => false,
      timeout: 100,
      pollMs: 5,
    });
    assert.match(await readFile(join(lockPath, "owner"), "utf8"), new RegExp(`^${process.pid}:`));
    assert.equal(await releaseLock(lockPath, "not-the-claimant"), false);
    assert.equal(await release(), true);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("a delayed stale rename keeps replacement generations behind the mutation gate", async () => {
  const { directory, lockPath } = await temporaryLock();
  const processAlive = (pid) => pid === process.pid;
  let renameStarted;
  let continueRename;
  const renameStartedPromise = new Promise((resolveRenameStarted) => {
    renameStarted = resolveRenameStarted;
  });
  const continueRenamePromise = new Promise((resolveContinueRename) => {
    continueRename = resolveContinueRename;
  });
  let delayed = false;

  try {
    await mkdir(lockPath);
    await writeFile(join(lockPath, "owner"), `${process.pid + 1_000_000}:dead-owner\n`, {
      mode: 0o600,
    });

    const claim = claimStaleLock(lockPath, {
      processAlive,
      pollMs: 5,
      timeout: 1_000,
      renameFn: async (source, destination) => {
        await rename(source, destination);
        if (!delayed && source === lockPath && destination.includes(".stale-")) {
          delayed = true;
          renameStarted();
          await continueRenamePromise;
        }
      },
    });
    await renameStartedPromise;

    const replacement = acquireLock(lockPath, { processAlive, pollMs: 5, timeout: 1_000 });
    assert.equal(
      await Promise.race([
        replacement.then(() => true),
        new Promise((resolveRace) => setTimeout(() => resolveRace(false), 25)),
      ]),
      false,
    );

    continueRename();
    assert.equal(await claim, true);
    const release = await replacement;
    assert.equal(await release(), true);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});
