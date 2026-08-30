import assert from "node:assert/strict";
import { chmod, mkdtemp, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawn } from "node:child_process";
import { test } from "node:test";
import {
  launchChrome,
  reserveLoopbackPort,
  terminateProcess,
} from "./federation_browser_smoke.mjs";

const node = process.execPath;
const smokeScript = new URL("./federation_browser_smoke.mjs", import.meta.url);

async function profileNames() {
  return (await readdir(tmpdir())).filter((name) => name.startsWith("cadence-federation-chrome-"));
}

async function fixture(script) {
  const directory = await mkdtemp(join(tmpdir(), "cadence-federation-fixture-"));
  const path = join(directory, "fake-chrome.sh");
  await writeFile(path, `#!/bin/sh\n${script}\n`);
  await chmod(path, 0o700);
  return { directory, path };
}

function runNode(args, { input = "", env = {} } = {}) {
  return new Promise((resolveRun) => {
    const child = spawn(node, [smokeScript.pathname, ...args], {
      env: { ...process.env, ...env },
      stdio: ["pipe", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.once("exit", (code, signal) => resolveRun({ code, signal, stdout, stderr }));
    child.stdin.end(input);
  });
}

test("missing Chrome is rejected before profile allocation", async () => {
  const before = await profileNames();
  await assert.rejects(
    launchChrome({ binary: join(tmpdir(), "cadence-chrome-does-not-exist") }),
    /Chrome or Chromium is required/,
  );
  assert.deepEqual(await profileNames(), before);
});

test("concurrent browser launches keep profiles and endpoints isolated", async () => {
  const fake = await fixture([
    "printf 'DevTools listening on ws://127.0.0.1:9/devtools/browser/fake\\n'",
    "sleep 30",
  ].join("\n"));
  const firstPort = await reserveLoopbackPort();
  const secondPort = await reserveLoopbackPort();
  const before = await profileNames();
  let runtimes;
  try {
    const results = await Promise.allSettled([
      launchChrome({ binary: fake.path }),
      launchChrome({ binary: fake.path }),
    ]);
    runtimes = results.flatMap((result) =>
      result.status === "fulfilled" ? [result.value] : [],
    );
    const rejected = results.find((result) => result.status === "rejected");
    if (rejected) throw rejected.reason;
    assert.notEqual(runtimes[0].userDataDir, runtimes[1].userDataDir);
    assert.notEqual(runtimes[0].child.pid, runtimes[1].child.pid);
    assert.notEqual(firstPort.port, secondPort.port);
  } finally {
    await Promise.all((runtimes || []).map((runtime) => runtime.close()));
    await Promise.all([
      new Promise((resolveClose) => firstPort.server.close(resolveClose)),
      new Promise((resolveClose) => secondPort.server.close(resolveClose)),
    ]);
    await rm(fake.directory, { recursive: true, force: true });
  }
  assert.deepEqual(await profileNames(), before);
});

test("cancellation before spawn still removes the allocated profile", async () => {
  const fake = await fixture("sleep 30");
  const controller = new AbortController();
  controller.abort(new Error("test cancellation"));
  const before = await profileNames();
  let spawnCalled = false;
  try {
    await assert.rejects(
      launchChrome({
        binary: fake.path,
        signal: controller.signal,
        spawnImpl: () => {
          spawnCalled = true;
          throw new Error("spawn must not run after cancellation");
        },
      }),
      /test cancellation/,
    );
    assert.equal(spawnCalled, false);
  } finally {
    await rm(fake.directory, { recursive: true, force: true });
  }
  assert.deepEqual(await profileNames(), before);
});

test("spawn failure and forced shutdown await exit before removing the profile", async () => {
  const before = await profileNames();
  await assert.rejects(launchChrome({ binary: "/usr/bin/false" }), /exited before CDP startup/);
  assert.deepEqual(await profileNames(), before);

  const fake = await fixture([
    "trap '' TERM",
    "printf 'DevTools listening on ws://127.0.0.1:9/devtools/browser/fake\\n'",
    "sleep 30",
  ].join("\n"));
  let runtime;
  try {
    await assert.rejects(
      launchChrome({ binary: fake.path, onRuntime: () => { throw new Error("runtime callback failure"); } }),
      /runtime callback failure/,
    );
    assert.deepEqual(await profileNames(), before);

    runtime = await launchChrome({ binary: fake.path });
    const profile = runtime.userDataDir;
    const result = await runtime.close();
    assert.equal(result, undefined);
    assert.equal(await (async () => {
      try {
        await readdir(profile);
        return true;
      } catch (error) {
        return error.code !== "ENOENT";
      }
    })(), false);
  } finally {
    await runtime?.close();
    await rm(fake.directory, { recursive: true, force: true });
  }
  assert.deepEqual(await profileNames(), before);
});

test("SIGTERM cancellation cleans the Chrome profile and never leaks the login secret", async () => {
  const fake = await fixture([
    "trap '' TERM",
    "sleep 30",
  ].join("\n"));
  const before = await profileNames();
  const child = spawn(node, [smokeScript.pathname, "--scenario-timeout-ms", "1000"], {
    env: { ...process.env, CHROME_BIN: fake.path },
    stdio: ["ignore", "pipe", "pipe"],
  });
  let stderr = "";
  let startedResolve;
  const started = new Promise((resolveStarted) => { startedResolve = resolveStarted; });
  child.stderr.on("data", (chunk) => { stderr += chunk; });
  child.stderr.on("data", (chunk) => {
    if (chunk.toString().includes("launching bounded Chrome process")) startedResolve();
  });
  await Promise.race([started, new Promise((resolveStarted) => setTimeout(resolveStarted, 1_000))]);
  child.kill("SIGTERM");
  const result = await new Promise((resolveRun) => child.once("exit", (code, signal) => resolveRun({ code, signal })));
  await new Promise((resolveWait) => setTimeout(resolveWait, 100));
  try {
    assert.equal(result.code, 143);
    assert.equal(result.signal, null);
    assert.deepEqual(await profileNames(), before);
    assert.equal(stderr.includes("correct-horse-battery-staple"), false);
  } finally {
    await rm(fake.directory, { recursive: true, force: true });
  }
});

test("credential failure output is redacted and the password has no argv or environment transport", async () => {
  const fake = await fixture([
    "printf 'DevTools listening on ws://127.0.0.1:9/devtools/browser/fake\\n'",
    "sleep 30",
  ].join("\n"));
  const secret = "correct-horse-battery-staple";
  try {
    const result = await runNode([
      "--comms-url", "http://127.0.0.1:43721/comms",
      "--telemetry-url", "http://127.0.0.1:43721/telemetry",
      "--login-url", "http://127.0.0.1:43721/sign-in",
      "--login-email", "operator@example.test",
      "--mission-id", "mission-1",
      "--spacecraft-id", "spacecraft-1",
      "--expected-apid", "42",
      "--scenario-timeout-ms", "1000",
    ], { input: `${JSON.stringify({ password: secret })}\n`, env: { CHROME_BIN: fake.path } });
    assert.equal(result.code, 1);
    assert.equal(`${result.stdout}\n${result.stderr}`.includes(secret), false);
  } finally {
    await rm(fake.directory, { recursive: true, force: true });
  }
});

test("forced termination remains bounded", async () => {
  const fake = await fixture([
    "trap '' TERM",
    "printf 'DevTools listening on ws://127.0.0.1:9/devtools/browser/fake\\n'",
    "sleep 30",
  ].join("\n"));
  const runtime = await launchChrome({ binary: fake.path });
  try {
    await assert.doesNotReject(terminateProcess(runtime.child, {
      gracefulTimeout: 10,
      forceTimeout: 1_000,
    }));
  } finally {
    await runtime.close();
    await rm(fake.directory, { recursive: true, force: true });
  }
});
