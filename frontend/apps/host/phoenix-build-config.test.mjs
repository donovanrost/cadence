import assert from "node:assert/strict";
import { lstat, mkdtemp, readFile, rm } from "node:fs/promises";
import { spawn } from "node:child_process";
import test from "node:test";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const appRoot = resolve(import.meta.dirname);
const vitePlusEntry = resolve(appRoot, "node_modules/vite-plus/bin/vp");

/** @param {(directory: string) => Promise<void>} callback */
async function withTemporaryDirectory(callback) {
  const directory = await mkdtemp(join(tmpdir(), "cadence-host-build-config-"));
  try {
    return await callback(directory);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
}

/** @param {string[]} argumentsList
 * @returns {Promise<{code: number | null, signal: NodeJS.Signals | null, stdout: string, stderr: string}>}
 */
function runVite(argumentsList) {
  return new Promise((resolveResult, reject) => {
    const child = spawn(process.execPath, [vitePlusEntry, ...argumentsList], {
      cwd: appRoot,
      env: { ...process.env, PATH: `${resolve(process.execPath, "..")}:${process.env.PATH ?? ""}` },
      stdio: ["ignore", "pipe", "pipe"],
    });
    /** @type {Buffer[]} */
    const stdout = [];
    /** @type {Buffer[]} */
    const stderr = [];
    child.stdout.on("data", (/** @type {Buffer} */ chunk) => stdout.push(chunk));
    child.stderr.on("data", (/** @type {Buffer} */ chunk) => stderr.push(chunk));
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

void test("Phoenix publication emits only the host runtime and no mutable fallback URL", async () => {
  await withTemporaryDirectory(async (root) => {
    const output = join(root, "host");
    const result = await runVite([
      "build",
      "--config",
      resolve(appRoot, "vite.phoenix.config.ts"),
      "--outDir",
      output,
    ]);

    assert.equal(result.code, 0, result.stderr);
    assert.equal(await lstat(join(output, "index.html")).catch(() => null), null);
    assert.notEqual(await lstat(join(output, "host.js")).catch(() => null), null);
    assert.equal(await lstat(join(output, "plugin-host.css")).catch(() => null), null);
    const source = await readFile(join(output, "host.js"), "utf8");
    for (const forbidden of [
      "http://localhost/",
      "demo-auth-service",
      "contract-probe",
      "sourceMappingURL",
      "import.meta.hot",
      "/@vite/client",
      "process.env.NODE_ENV",
    ]) {
      assert.equal(source.includes(forbidden), false, forbidden);
    }
  });
});

void test("the host standalone entry remains available outside Phoenix publication mode", async () => {
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
