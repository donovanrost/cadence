import assert from "node:assert/strict";
import { chmod, mkdtemp, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawn } from "node:child_process";
import { EventEmitter } from "node:events";
import { PassThrough } from "node:stream";
import { test } from "node:test";
import {
  activeResourceNames,
  CdpClient,
  launchChrome,
  readStructuredLoginSecret,
  reserveLoopbackPort,
  runBrowserGate,
  sleep,
  terminateProcess,
  waitForExpression,
} from "./federation_browser_smoke.mjs";

const node = process.execPath;
const smokeScript = new URL("./federation_browser_smoke.mjs", import.meta.url);

test("graceful and forced child-exit timeouts remove every exit and error waiter", async () => {
  const child = new EventEmitter();
  child.exitCode = null;
  child.signalCode = null;
  child.kill = () => true;

  await assert.rejects(
    terminateProcess(child, { gracefulTimeout: 5, forceTimeout: 5 }),
    /graceful and forced shutdown/,
  );
  assert.equal(child.listenerCount("exit"), 0, "child exit timeout left an exit listener");
  assert.equal(child.listenerCount("error"), 0, "child exit timeout left an error listener");
});

test("launchChrome removes owned output and child listeners when process death is unproven", async () => {
  const fake = await fixture("sleep 30");
  const child = new EventEmitter();
  child.exitCode = null;
  child.signalCode = null;
  child.stdout = new PassThrough();
  child.stderr = new PassThrough();
  child.kill = () => true;
  let runtime;

  try {
    runtime = await launchChrome({
      binary: fake.path,
      spawnImpl: () => {
        queueMicrotask(() =>
          child.stdout.write("DevTools listening on ws://127.0.0.1:9/devtools/browser/fake\n"),
        );
        return child;
      },
      gracefulShutdownTimeout: 5,
      forceShutdownTimeout: 5,
    });
    const profile = runtime.userDataDir;

    await assert.rejects(runtime.close(), /graceful and forced shutdown/);
    assert.equal(child.stdout.listenerCount("data"), 0, "Chrome stdout listener survived timeout");
    assert.equal(child.stderr.listenerCount("data"), 0, "Chrome stderr listener survived timeout");
    assert.equal(child.listenerCount("error"), 0, "Chrome error listener survived timeout");
    await assert.doesNotReject(async () => readdir(profile));
    await rm(profile, { recursive: true, force: true });
    child.stdout.destroy();
    child.stderr.destroy();
  } finally {
    child.stdout.destroy();
    child.stderr.destroy();
    if (runtime?.userDataDir) {
      await rm(runtime.userDataDir, { recursive: true, force: true });
    }
    await rm(fake.directory, { recursive: true, force: true });
  }
});

function assertSecretStreamStopped(stream) {
  assert.equal(stream.listenerCount("data"), 0, "secret reader left a data listener active");
  assert.equal(stream.listenerCount("end"), 0, "secret reader left an end listener active");
  assert.equal(stream.listenerCount("error"), 0, "secret reader left an error listener active");
  assert.equal(stream.isPaused(), true, "secret reader did not pause the owned input stream");
}

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
    child.stdout.on("data", (chunk) => {
      stdout += chunk;
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk;
    });
    child.once("exit", (code, signal) => resolveRun({ code, signal, stdout, stderr }));
    child.stdin.end(input);
  });
}

class FakeWebSocket {
  constructor() {
    this.listeners = new Map();
    queueMicrotask(() => this.dispatch("open"));
  }

  addEventListener(type, listener) {
    const listeners = this.listeners.get(type) || new Set();
    listeners.add(listener);
    this.listeners.set(type, listeners);
  }

  removeEventListener(type, listener) {
    this.listeners.get(type)?.delete(listener);
  }

  dispatch(type, event = {}) {
    for (const listener of this.listeners.get(type) || []) listener(event);
  }

  send(payload) {
    const { id, method } = JSON.parse(payload);
    queueMicrotask(() => {
      const result = method === "Runtime.evaluate" ? { result: { value: false } } : {};
      this.dispatch("message", { data: JSON.stringify({ id, result }) });
    });
  }

  close() {
    this.dispatch("close");
  }
}

test("scenario timeout aborts polling and CDP event waiters before gate cleanup returns", async () => {
  const client = new CdpClient("ws://fake", { webSocketImpl: FakeWebSocket });
  const args = [
    "--comms-url",
    "http://127.0.0.1:43721/missions/mission-1/applications/comms_overview/federated",
  ];
  let activePollTimers = 0;
  let runtimeClosed = 0;
  const timerCountBefore = activeResourceNames().filter((name) => name === "Timeout").length;
  const trackedSleep = (milliseconds, signal) => {
    activePollTimers += 1;
    return sleep(milliseconds, signal).finally(() => {
      activePollTimers -= 1;
    });
  };

  const startedAt = Date.now();
  await assert.rejects(
    runBrowserGate(args.concat(["--scenario-timeout-ms", "25"]), {
      launchChromeImpl: async ({ onRuntime }) => {
        let closed = false;
        const runtime = {
          endpoint: "ws://fake",
          child: null,
          close: async () => {
            if (closed) return;
            closed = true;
            runtimeClosed += 1;
          },
        };
        onRuntime?.(runtime);
        return runtime;
      },
      createPageImpl: async () => ({ webSocketDebuggerUrl: "ws://fake-page" }),
      createClientImpl: () => client,
      runScenarioImpl: async (scenarioClient, _diagnostics, _args, { signal }) => {
        const eventWait = scenarioClient.waitForEvent(
          "Page.neverFired",
          () => true,
          60_000,
          signal,
        );
        eventWait.catch(() => {});
        await Promise.all([
          eventWait,
          waitForExpression(scenarioClient, "false", "deliberately non-resolving wait", {
            timeout: 60_000,
            signal,
            sleepFn: trackedSleep,
          }),
        ]);
      },
    }),
    /federation browser scenario timed out after 25ms/,
  );

  assert.ok(Date.now() - startedAt < 1_000, "gate cleanup exceeded its bounded lifecycle budget");
  assert.equal(client.eventWaiters.size, 0, "abort left a CDP event waiter active");
  assert.equal(client.pending.size, 0, "abort left a CDP command active");
  assert.equal(activePollTimers, 0, "abort left a polling timer active");
  assert.equal(runtimeClosed, 1, "runtime cleanup was not idempotently completed");
  await new Promise((resolveImmediate) => setImmediate(resolveImmediate));
  assert.equal(
    activeResourceNames().filter((name) => name === "Timeout").length,
    timerCountBefore,
    "scenario abort left a real Timer resource active",
  );
});

test("structured secret cleanup pauses real streams on success, parse error, end, abort, and timeout", async () => {
  const successStream = new PassThrough();
  const success = readStructuredLoginSecret({ stream: successStream });
  successStream.end(JSON.stringify({ password: "test-secret" }));
  assert.deepEqual(await success, { password: "test-secret" });
  assertSecretStreamStopped(successStream);

  const parseStream = new PassThrough();
  const parseError = readStructuredLoginSecret({ stream: parseStream });
  parseStream.end(JSON.stringify({ password: "" }));
  await assert.rejects(parseError, /non-empty password/);
  assertSecretStreamStopped(parseStream);

  const endStream = new PassThrough();
  const endError = readStructuredLoginSecret({ stream: endStream });
  endStream.end();
  await assert.rejects(endError, /secret was not provided/);
  assertSecretStreamStopped(endStream);

  const abortStream = new PassThrough();
  const controller = new AbortController();
  const aborted = readStructuredLoginSecret({ stream: abortStream, signal: controller.signal });
  controller.abort(new Error("secret read cancelled"));
  await assert.rejects(aborted, /secret read cancelled/);
  assertSecretStreamStopped(abortStream);

  const timeoutStream = new PassThrough();
  const timedOut = readStructuredLoginSecret({ stream: timeoutStream, timeout: 20 });
  await assert.rejects(timedOut, /structured login secret timed out after 20ms/);
  assertSecretStreamStopped(timeoutStream);
});

test("an open child stdin pipe is unrefed after the one-shot secret read", async () => {
  const source = [
    `import { readStructuredLoginSecret } from ${JSON.stringify(smokeScript.href)};`,
    `const secret = await readStructuredLoginSecret();`,
    `if (secret.password !== "test-secret") throw new Error("unexpected secret");`,
  ].join("\n");
  const child = spawn(node, ["--input-type=module", "-e", source], {
    stdio: ["pipe", "ignore", "pipe"],
  });
  let timer;
  try {
    child.stdin.write(`${JSON.stringify({ password: "test-secret" })}\n`);
    const result = await new Promise((resolveChild, rejectChild) => {
      timer = setTimeout(() => {
        child.kill("SIGKILL");
        rejectChild(new Error("spawned secret-reader process did not exit within 1s"));
      }, 1_000);
      child.once("error", rejectChild);
      child.once("exit", (code, signal) => resolveChild({ code, signal }));
    });
    assert.equal(result.code, 0);
    assert.equal(result.signal, null);
  } finally {
    clearTimeout(timer);
    child.stdin.destroy();
    if (child.exitCode === null && child.signalCode === null) child.kill("SIGKILL");
  }
});

test("missing Chrome is rejected before profile allocation", async () => {
  const before = await profileNames();
  await assert.rejects(
    launchChrome({ binary: join(tmpdir(), "cadence-chrome-does-not-exist") }),
    /Chrome or Chromium is required/,
  );
  assert.deepEqual(await profileNames(), before);
});

test("concurrent browser launches keep profiles and endpoints isolated", async () => {
  const fake = await fixture(
    ["printf 'DevTools listening on ws://127.0.0.1:9/devtools/browser/fake\\n'", "sleep 30"].join(
      "\n",
    ),
  );
  const firstPort = await reserveLoopbackPort();
  const secondPort = await reserveLoopbackPort();
  const before = await profileNames();
  let runtimes;
  try {
    const results = await Promise.allSettled([
      launchChrome({ binary: fake.path }),
      launchChrome({ binary: fake.path }),
    ]);
    runtimes = results.flatMap((result) => (result.status === "fulfilled" ? [result.value] : []));
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

  const fake = await fixture(
    [
      "trap '' TERM",
      "printf 'DevTools listening on ws://127.0.0.1:9/devtools/browser/fake\\n'",
      "sleep 30",
    ].join("\n"),
  );
  let runtime;
  try {
    await assert.rejects(
      launchChrome({
        binary: fake.path,
        onRuntime: () => {
          throw new Error("runtime callback failure");
        },
      }),
      /runtime callback failure/,
    );
    assert.deepEqual(await profileNames(), before);

    runtime = await launchChrome({ binary: fake.path });
    const profile = runtime.userDataDir;
    const result = await runtime.close();
    assert.equal(result, undefined);
    assert.equal(
      await (async () => {
        try {
          await readdir(profile);
          return true;
        } catch (error) {
          return error.code !== "ENOENT";
        }
      })(),
      false,
    );
  } finally {
    await runtime?.close();
    await rm(fake.directory, { recursive: true, force: true });
  }
  assert.deepEqual(await profileNames(), before);
});

test("SIGTERM cancellation cleans the Chrome profile and never leaks the login secret", async () => {
  const fake = await fixture(["trap '' TERM", "sleep 30"].join("\n"));
  const before = await profileNames();
  const child = spawn(node, [smokeScript.pathname, "--scenario-timeout-ms", "1000"], {
    env: { ...process.env, CHROME_BIN: fake.path },
    stdio: ["ignore", "pipe", "pipe"],
  });
  let stderr = "";
  let startupTimer;
  const exited = new Promise((resolveExit) =>
    child.once("exit", (code, signal) => resolveExit({ code, signal })),
  );
  const started = new Promise((resolveStarted, rejectStarted) => {
    startupTimer = setTimeout(
      () => rejectStarted(new Error("browser gate did not reach the cancellation boundary")),
      10_000,
    );
    child.stderr.on("data", (chunk) => {
      stderr += chunk;
      if (stderr.includes("launching bounded Chrome process")) resolveStarted();
    });
    child.once("error", rejectStarted);
  });
  try {
    await started;
    clearTimeout(startupTimer);
    child.kill("SIGTERM");
    const result = await exited;
    assert.equal(result.code, 143);
    assert.equal(result.signal, null);
    assert.deepEqual(await profileNames(), before);
    assert.equal(stderr.includes("correct-horse-battery-staple"), false);
  } finally {
    clearTimeout(startupTimer);
    await terminateProcess(child);
    await rm(fake.directory, { recursive: true, force: true });
  }
});

test("credential failure output is redacted and the password has no argv or environment transport", async () => {
  const fake = await fixture(
    ["printf 'DevTools listening on ws://127.0.0.1:9/devtools/browser/fake\\n'", "sleep 30"].join(
      "\n",
    ),
  );
  const secret = "correct-horse-battery-staple";
  try {
    const result = await runNode(
      [
        "--comms-url",
        "http://127.0.0.1:43721/comms",
        "--telemetry-url",
        "http://127.0.0.1:43721/telemetry",
        "--login-url",
        "http://127.0.0.1:43721/sign-in",
        "--login-email",
        "operator@example.test",
        "--mission-id",
        "mission-1",
        "--spacecraft-id",
        "spacecraft-1",
        "--expected-apid",
        "42",
        "--scenario-timeout-ms",
        "1000",
      ],
      { input: `${JSON.stringify({ password: secret })}\n`, env: { CHROME_BIN: fake.path } },
    );
    assert.equal(result.code, 1);
    assert.equal(`${result.stdout}\n${result.stderr}`.includes(secret), false);
  } finally {
    await rm(fake.directory, { recursive: true, force: true });
  }
});

test("forced termination remains bounded", async () => {
  const fake = await fixture(
    [
      "trap '' TERM",
      "printf 'DevTools listening on ws://127.0.0.1:9/devtools/browser/fake\\n'",
      "sleep 30",
    ].join("\n"),
  );
  const runtime = await launchChrome({ binary: fake.path });
  try {
    await assert.doesNotReject(
      terminateProcess(runtime.child, {
        gracefulTimeout: 10,
        forceTimeout: 1_000,
      }),
    );
  } finally {
    await runtime.close();
    await rm(fake.directory, { recursive: true, force: true });
  }
});
