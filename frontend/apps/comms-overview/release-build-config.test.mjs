import assert from "node:assert/strict";
import { lstat, mkdtemp, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { spawn } from "node:child_process";
import test from "node:test";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const appRoot = resolve(import.meta.dirname);
const vitePlusEntry = resolve(appRoot, "node_modules/vite-plus/bin/vp");

async function withTemporaryDirectory(callback) {
  const directory = await mkdtemp(join(tmpdir(), "cadence-comms-release-config-"));
  try {
    return await callback(directory);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
}

function runVite(argumentsList, environment = {}) {
  return new Promise((resolveResult, reject) => {
    const child = spawn(process.execPath, [vitePlusEntry, ...argumentsList], {
      cwd: appRoot,
      env: {
        ...process.env,
        ...environment,
        PATH: `${resolve(process.execPath, "..")}:${process.env.PATH ?? ""}`,
      },
      stdio: ["ignore", "pipe", "pipe"],
    });
    const stdout = [];
    const stderr = [];
    child.stdout.on("data", (chunk) => stdout.push(chunk));
    child.stderr.on("data", (chunk) => stderr.push(chunk));
    child.once("error", reject);
    child.once("close", (code, signal) =>
      resolveResult({
        code,
        signal,
        stdout: Buffer.concat(stdout).toString("utf8"),
        stderr: Buffer.concat(stderr).toString("utf8"),
      }),
    );
  });
}

async function outputFiles(root) {
  const entries = await readdir(root, { withFileTypes: true });
  const files = [];
  for (const entry of entries.sort((left, right) => left.name.localeCompare(right.name))) {
    const path = join(root, entry.name);
    if (entry.isDirectory()) files.push(...(await outputFiles(path)));
    else if (entry.isFile()) files.push(path);
  }
  return files;
}

function releaseArguments(output) {
  return [
    "build",
    "--config",
    resolve(appRoot, "vite.config.ts"),
    "--mode",
    "release",
    "--outDir",
    output,
  ];
}

void test("emits only the federation graph in release mode", async () => {
  await withTemporaryDirectory(async (root) => {
    const output = join(root, "release");
    const secondOutput = join(root, "second-release");
    const result = await runVite(releaseArguments(output), {
      CADENCE_RELEASE_OUTPUT_DIR: output,
    });

    assert.equal(result.code, 0, result.stderr);
    assert.equal((await lstat(join(output, "index.html")).catch(() => null)) === null, true);
    assert.equal((await lstat(join(output, ".vite")).catch(() => null)) === null, true);
    assert.deepEqual(
      (await outputFiles(output))
        .map((path) => path.slice(output.length + 1))
        .filter((path) => path.startsWith("assets/index-")),
      [],
    );
    for (const required of ["mf-manifest.json", "mf-stats.json", "remoteEntry.js"]) {
      assert.notEqual(await lstat(join(output, required)).catch(() => null), null, required);
    }

    const emittedPaths = (await outputFiles(output)).map((path) => path.slice(output.length + 1));
    const stats = JSON.parse(await readFile(join(output, "mf-stats.json"), "utf8"));
    assert.equal(Object.hasOwn(stats, "assetAnalysis"), false);
    const secondResult = await runVite(releaseArguments(secondOutput), {
      CADENCE_RELEASE_OUTPUT_DIR: secondOutput,
    });
    assert.equal(secondResult.code, 0, secondResult.stderr);
    assert.deepEqual(
      emittedPaths,
      (await outputFiles(secondOutput)).map((path) => path.slice(secondOutput.length + 1)),
    );

    const stalePath = join(secondOutput, "assets", "stale-release.js");
    await writeFile(stalePath, "export const stale = true;\n");
    const rebuiltResult = await runVite(releaseArguments(secondOutput), {
      CADENCE_RELEASE_OUTPUT_DIR: secondOutput,
    });
    assert.equal(rebuiltResult.code, 0, rebuiltResult.stderr);
    assert.equal(
      await lstat(stalePath).catch(() => null),
      null,
      "stale output survived the release rebuild",
    );
  });
});

void test("keeps the standalone entry available outside release mode", async () => {
  await withTemporaryDirectory(async (root) => {
    const output = join(root, "standalone");
    const result = await runVite([
      "build",
      "--config",
      resolve(appRoot, "vite.config.ts"),
      "--mode",
      "development",
      "--outDir",
      output,
    ]);

    assert.equal(result.code, 0, result.stderr);
    assert.notEqual(await lstat(join(output, "index.html")).catch(() => null), null);
  });
});
