import assert from "node:assert/strict";
import { accessSync, constants, statSync } from "node:fs";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { createServer } from "node:net";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { spawn } from "node:child_process";

export const CDP_COMMAND_TIMEOUT_MS = 15_000;
export const CDP_EVENT_TIMEOUT_MS = 30_000;
export const CHROME_START_TIMEOUT_MS = 10_000;
export const CHROME_GRACEFUL_SHUTDOWN_TIMEOUT_MS = 2_000;
export const CHROME_FORCE_SHUTDOWN_TIMEOUT_MS = 2_000;
export const PROFILE_CLEANUP_TIMEOUT_MS = 5_000;
export const PAGE_CLOSE_CLEANUP_TIMEOUT_MS = 1_000;
export const SCENARIO_TIMEOUT_MS = 180_000;
export const POLL_INTERVAL_MS = 100;

let currentProgressStage = "initializing";
let outputBroken = false;

export function reportProgress(stage) {
  currentProgressStage = stage;
  if (outputBroken) return;

  try {
    process.stderr.write(`[federation-smoke] ${stage}\n`);
  } catch (error) {
    if (error?.code === "EPIPE") outputBroken = true;
  }
}

export function argValue(args, name) {
  const index = args.indexOf(name);
  return index === -1 ? undefined : args[index + 1];
}

export function requiredArg(args, name) {
  const value = argValue(args, name);
  if (!value) throw new Error(`missing required argument ${name}`);
  return value;
}

export function sleep(milliseconds) {
  return new Promise((resolveSleep) => setTimeout(resolveSleep, milliseconds));
}

export function withTimeout(promise, milliseconds, label, onTimeout) {
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => {
      onTimeout?.();
      reject(new Error(`${label} timed out after ${milliseconds}ms`));
    }, milliseconds);
  });

  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}

export function abortError(signal, fallback = "operation cancelled") {
  return signal?.reason instanceof Error ? signal.reason : new Error(fallback);
}

export function raceWithSignalAndTimeout(
  operation,
  { signal, milliseconds, label, onTimeout } = {},
) {
  const operationPromise = Promise.resolve(operation);
  operationPromise.catch(() => {});

  if (signal?.aborted) return Promise.reject(abortError(signal));

  return new Promise((resolveRace, rejectRace) => {
    let settled = false;
    let timer;

    const finish = (callback, value) => {
      if (settled) return;
      settled = true;
      if (timer) clearTimeout(timer);
      signal?.removeEventListener("abort", onAbort);
      callback(value);
    };

    const onAbort = () => finish(rejectRace, abortError(signal));

    signal?.addEventListener("abort", onAbort, { once: true });
    if (milliseconds) {
      timer = setTimeout(() => {
        const error = new Error(`${label || "operation"} timed out after ${milliseconds}ms`);
        onTimeout?.(error);
        finish(rejectRace, error);
      }, milliseconds);
    }

    operationPromise.then(
      (value) => finish(resolveRace, value),
      (error) => finish(rejectRace, error),
    );
  });
}

export function redactText(value, secrets = []) {
  let text = String(value ?? "");
  for (const secret of secrets) {
    if (typeof secret === "string" && secret.length > 0) {
      text = text.split(secret).join("[REDACTED]");
    }
  }
  return text;
}

export function redactError(error, secrets = []) {
  return redactText(error?.stack || error?.message || error, secrets);
}

function defaultChromeCandidates(platform = process.platform) {
  return platform === "darwin"
    ? [
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        "/Applications/Chromium.app/Contents/MacOS/Chromium",
        "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
      ]
    : [
        "/usr/bin/google-chrome",
        "/usr/bin/google-chrome-stable",
        "/usr/bin/chromium",
        "/usr/bin/chromium-browser",
      ];
}

export function resolveChromeBinary({
  env = process.env,
  platform = process.platform,
  candidates = defaultChromeCandidates(platform),
  fileExists = (candidate) => {
    try {
      const stat = statSync(candidate);
      accessSync(candidate, constants.X_OK);
      return stat.isFile();
    } catch {
      return false;
    }
  },
} = {}) {
  const explicit = env.CHROME_BIN;
  return [explicit, ...candidates]
    .filter((candidate, index, all) => candidate && all.indexOf(candidate) === index)
    .find(fileExists);
}

export function requireChromeBinary(options = {}) {
  const binary = resolveChromeBinary(options);
  if (!binary) {
    throw new Error(
      "Chrome or Chromium is required; set CHROME_BIN to an executable browser binary",
    );
  }
  return binary;
}

export function assertNoPasswordArgument(args) {
  const forbiddenArgument = "--login-" + "password";
  assert.equal(
    args.includes(forbiddenArgument),
    false,
    "the browser gate must receive credentials over structured stdin, not argv",
  );
}

export async function removeUserDataDir(userDataDir, { timeout = PROFILE_CLEANUP_TIMEOUT_MS } = {}) {
  const deadline = Date.now() + timeout;
  let lastError;

  while (Date.now() <= deadline) {
    try {
      await rm(userDataDir, { recursive: true, force: true });
      return;
    } catch (error) {
      lastError = error;
      if (!["ENOTEMPTY", "EBUSY", "EPERM"].includes(error?.code)) throw error;
      await sleep(Math.min(250, Math.max(25, deadline - Date.now())));
    }
  }

  throw new Error(`Chrome profile cleanup timed out: ${lastError?.message || userDataDir}`);
}

function childHasExited(child, spawnError) {
  return Boolean(spawnError || child.exitCode !== null || child.signalCode !== null);
}

export function signalChild(child, signal) {
  if (!child || childHasExited(child, null)) return false;

  if (process.platform !== "win32" && child.pid) {
    try {
      process.kill(-child.pid, signal);
      return true;
    } catch (error) {
      if (error?.code !== "ESRCH") throw error;
    }
  }

  try {
    return child.kill(signal);
  } catch (error) {
    if (error?.code === "ESRCH") return false;
    throw error;
  }
}

export function waitForChildExit(child, timeout, label, spawnErrorRef = { value: null }) {
  if (childHasExited(child, spawnErrorRef.value)) return Promise.resolve();

  return withTimeout(
    new Promise((resolveExit) => {
      const done = () => {
        child.removeListener("exit", done);
        child.removeListener("error", done);
        resolveExit();
      };
      child.once("exit", done);
      child.once("error", done);
    }),
    timeout,
    label,
  );
}

export async function terminateProcess(
  child,
  {
    gracefulTimeout = CHROME_GRACEFUL_SHUTDOWN_TIMEOUT_MS,
    forceTimeout = CHROME_FORCE_SHUTDOWN_TIMEOUT_MS,
    spawnErrorRef = { value: null },
  } = {},
) {
  if (!child || childHasExited(child, spawnErrorRef.value)) return { forced: false };

  signalChild(child, "SIGTERM");
  try {
    await waitForChildExit(child, gracefulTimeout, "graceful Chrome shutdown", spawnErrorRef);
    return { forced: false };
  } catch (gracefulError) {
    signalChild(child, "SIGKILL");
    try {
      await waitForChildExit(child, forceTimeout, "forced Chrome shutdown", spawnErrorRef);
      return { forced: true };
    } catch (forceError) {
      throw new Error(
        `Chrome did not exit after graceful and forced shutdown: ${forceError.message}`,
        { cause: gracefulError },
      );
    }
  }
}

function boundedProcessOutput() {
  let output = "";
  return {
    append(chunk) {
      if (output.length < 64 * 1024) output += chunk.toString().slice(0, 64 * 1024 - output.length);
    },
    value() {
      return output;
    },
  };
}

export async function launchChrome({
  binary,
  env = process.env,
  signal,
  spawnImpl = spawn,
  onRuntime,
} = {}) {
  // Resolve and validate the executable before allocating a profile directory.
  const executable = requireChromeBinary(
    binary ? { env: { ...env, CHROME_BIN: binary }, candidates: [] } : { env },
  );
  const userDataDir = await mkdtemp(resolve(tmpdir(), "cadence-federation-chrome-"));
  const output = boundedProcessOutput();
  const spawnErrorRef = { value: null };
  let spawnReadyResolve;
  const spawnReady = new Promise((resolveSpawn) => {
    spawnReadyResolve = resolveSpawn;
  });
  let child;
  let closePromise;

  const runtime = {
    child: null,
    endpoint: null,
    userDataDir,
    async close() {
      if (closePromise) return closePromise;
      closePromise = (async () => {
        let terminated = false;
        try {
          await spawnReady;
          if (runtime.child) {
            await terminateProcess(runtime.child, { spawnErrorRef });
            terminated = true;
          } else {
            terminated = true;
          }
        } finally {
          // Never remove the profile until the process has been observed exited.
          if (terminated) await removeUserDataDir(userDataDir);
        }
      })();
      return closePromise;
    },
  };

  try {
    try {
      onRuntime?.(runtime);
      if (signal?.aborted) throw abortError(signal);
      child = spawnImpl(
        executable,
        [
          "--headless=new",
          "--disable-gpu",
          "--disable-dev-shm-usage",
          "--no-first-run",
          "--no-default-browser-check",
          "--remote-debugging-port=0",
          `--user-data-dir=${userDataDir}`,
          "about:blank",
        ],
        {
          detached: process.platform !== "win32",
          windowsHide: true,
          stdio: ["ignore", "pipe", "pipe"],
          env,
        },
      );
      runtime.child = child;
    } finally {
      spawnReadyResolve();
    }
    child.stdout?.on("data", (chunk) => output.append(chunk));
    child.stderr?.on("data", (chunk) => output.append(chunk));
    child.once("error", (error) => {
      spawnErrorRef.value = error;
    });

    const endpoint = await raceWithSignalAndTimeout(
      new Promise((resolveEndpoint, rejectEndpoint) => {
        let settled = false;
        const inspect = () => {
          const match = output.value().match(/DevTools listening on (wss?:\/\/[^\s]+)/);
          if (match && !settled) {
            settled = true;
            resolveEndpoint(match[1]);
          }
        };
        const onData = () => inspect();
        const onError = (error) => {
          if (!settled) {
            settled = true;
            rejectEndpoint(new Error(`Chrome failed to start: ${error.message}`));
          }
        };
        const onExit = (code, signalName) => {
          if (!settled) {
            settled = true;
            rejectEndpoint(
              new Error(
                `Chrome exited before CDP startup (${code ?? signalName})\n${output.value()}`,
              ),
            );
          }
        };
        child.stdout?.on("data", onData);
        child.stderr?.on("data", onData);
        child.once("error", onError);
        child.once("exit", onExit);
        inspect();
      }),
      {
        signal,
        milliseconds: CHROME_START_TIMEOUT_MS,
        label: "Chrome CDP startup",
      },
    );

    runtime.endpoint = endpoint;
    return runtime;
  } catch (error) {
    try {
      await runtime.close();
    } catch (cleanupError) {
      throw new AggregateError(
        [error, cleanupError],
        `Chrome startup failed and cleanup failed: ${redactError(cleanupError)}`,
      );
    }
    throw error;
  }
}

export function httpBaseFromWebSocket(endpoint) {
  const url = new URL(endpoint);
  assert.ok(["ws:", "wss:"].includes(url.protocol), `invalid DevTools endpoint scheme ${url.protocol}`);
  return `${url.protocol === "wss:" ? "https" : "http"}://${url.host}`;
}

export function browserUrls({ port, missionId, spacecraftId, host = "127.0.0.1", scheme = "http" }) {
  assert.ok(Number.isInteger(port) && port > 0 && port < 65_536, "browser endpoint port must be valid");
  assert.ok(["http", "https"].includes(scheme), "browser endpoint scheme must be HTTP(S)");
  const baseUrl = `${scheme}://${host}:${port}`;
  return {
    baseUrl,
    loginUrl: `${baseUrl}/sign-in`,
    commsUrl: `${baseUrl}/missions/${encodeURIComponent(missionId)}/comms/federated`,
    telemetryUrl: `${baseUrl}/missions/${encodeURIComponent(missionId)}/spacecraft/${encodeURIComponent(spacecraftId)}/applications/telemetry_decom/packet_bindings/federated`,
  };
}

export async function reserveLoopbackPort() {
  const server = createServer();
  await new Promise((resolveListen, rejectListen) => {
    server.once("error", rejectListen);
    server.listen(0, "127.0.0.1", resolveListen);
  });
  const address = server.address();
  assert.equal(typeof address, "object");
  assert.ok(address?.port, "loopback port reservation did not expose a port");
  return { server, port: address.port };
}

export async function createPage(endpoint, url, { fetcher = fetch, timeout = CDP_COMMAND_TIMEOUT_MS, signal } = {}) {
  assert.equal(url, "about:blank", "the initial CDP page must be about:blank");
  const controller = new AbortController();
  const abort = () => controller.abort(abortError(signal));
  signal?.addEventListener("abort", abort, { once: true });

  try {
    const response = await raceWithSignalAndTimeout(
      fetcher(`${httpBaseFromWebSocket(endpoint)}/json/new?${encodeURIComponent(url)}`, {
        method: "PUT",
        redirect: "manual",
        signal: controller.signal,
      }),
      {
        signal,
        milliseconds: timeout,
        label: "CDP page creation",
        onTimeout: (error) => controller.abort(error),
      },
    );
    assert.equal(response.status, 200, `CDP page creation failed with HTTP ${response.status}`);
    const text = await response.text();
    let target;
    try {
      target = JSON.parse(text);
    } catch (error) {
      throw new Error(`CDP page creation returned invalid JSON: ${error.message}`);
    }
    assert.equal(typeof target.id, "string", "CDP page target did not expose an id");
    assert.match(target.webSocketDebuggerUrl, /^wss?:\/\//, "CDP page target did not expose a WebSocket URL");
    return { id: target.id, webSocketDebuggerUrl: target.webSocketDebuggerUrl };
  } finally {
    signal?.removeEventListener("abort", abort);
  }
}

export async function closePage(endpoint, targetId, { fetcher = fetch, timeout = CDP_COMMAND_TIMEOUT_MS } = {}) {
  if (!endpoint || !targetId) return;
  const controller = new AbortController();
  try {
    const response = await raceWithSignalAndTimeout(
      fetcher(
        `${httpBaseFromWebSocket(endpoint)}/json/close/${encodeURIComponent(targetId)}`,
        { method: "GET", redirect: "manual", signal: controller.signal },
      ),
      {
        milliseconds: timeout,
        label: "CDP page close",
        onTimeout: (error) => controller.abort(error),
      },
    );
    assert.ok([200, 404].includes(response.status), `CDP page close failed with HTTP ${response.status}`);
  } finally {
    controller.abort(new Error("CDP page close finished"));
  }
}

export class CdpClient {
  constructor(endpoint) {
    this.socket = new WebSocket(endpoint);
    this.nextCommandId = 0;
    this.pending = new Map();
    this.listeners = new Map();
    this.closed = false;
    this.ready = new Promise((resolveReady, rejectReady) => {
      this.socket.addEventListener("open", resolveReady, { once: true });
      this.socket.addEventListener("error", rejectReady, { once: true });
      this.socket.addEventListener(
        "close",
        () => rejectReady(new Error("CDP WebSocket closed before opening")),
        { once: true },
      );
    });
    this.ready.catch(() => {});

    this.socket.addEventListener("message", (event) => {
      let message;
      try {
        const raw = typeof event.data === "string" ? event.data : Buffer.from(event.data).toString();
        message = JSON.parse(raw);
      } catch (error) {
        this.rejectPending(new Error(`invalid CDP message: ${error.message}`));
        return;
      }

      if (message.id !== undefined) {
        const callback = this.pending.get(message.id);
        if (!callback) return;
        this.pending.delete(message.id);
        if (message.error) callback.reject(new Error(`${message.error.message} (CDP ${message.id})`));
        else callback.resolve(message.result);
        return;
      }

      const listeners = this.listeners.get(message.method) || new Set();
      for (const listener of listeners) listener(message.params || {});
    });
    this.socket.addEventListener("close", () => this.rejectPending(new Error("CDP WebSocket closed")));
  }

  rejectPending(error) {
    for (const callback of this.pending.values()) callback.reject(error);
    this.pending.clear();
  }

  async send(method, params = {}, timeout = CDP_COMMAND_TIMEOUT_MS) {
    assert.equal(this.closed, false, "CDP client is closed");
    await withTimeout(this.ready, timeout, `CDP connection during ${method}`);
    const id = ++this.nextCommandId;
    const result = new Promise((resolveResult, rejectResult) => {
      this.pending.set(id, { resolve: resolveResult, reject: rejectResult });
    });

    try {
      this.socket.send(JSON.stringify({ id, method, params }));
    } catch (error) {
      this.pending.delete(id);
      throw error;
    }

    return withTimeout(result, timeout, `CDP ${method} during ${currentProgressStage}`).finally(() => {
      this.pending.delete(id);
    });
  }

  on(method, listener) {
    const listeners = this.listeners.get(method) || new Set();
    listeners.add(listener);
    this.listeners.set(method, listeners);
    return () => listeners.delete(listener);
  }

  once(method, timeout = CDP_EVENT_TIMEOUT_MS) {
    return this.waitForEvent(method, () => true, timeout);
  }

  waitForEvent(method, predicate = () => true, timeout = CDP_EVENT_TIMEOUT_MS) {
    return new Promise((resolveEvent, rejectEvent) => {
      let timer;
      const off = this.on(method, (params) => {
        try {
          if (!predicate(params)) return;
          off();
          clearTimeout(timer);
          resolveEvent(params);
        } catch (error) {
          off();
          clearTimeout(timer);
          rejectEvent(error);
        }
      });
      timer = setTimeout(() => {
        off();
        rejectEvent(new Error(`CDP ${method} during ${currentProgressStage} timed out after ${timeout}ms`));
      }, timeout);
    });
  }

  close() {
    if (this.closed) return;
    this.closed = true;
    this.rejectPending(new Error("CDP client closed"));
    try {
      this.socket.close();
    } catch {
      // The socket may already have been closed by Chrome during teardown.
    }
  }
}

export function exceptionMessage(exception) {
  const details = exception?.exceptionDetails || exception;
  return (
    details?.exception?.description ||
    details?.text ||
    details?.exception?.value ||
    JSON.stringify(details)
  );
}

export function isDataUrl(url) {
  return typeof url === "string" && url.startsWith("data:");
}

export function assertHttpUrl(url, expectedOrigin, label = "URL") {
  const parsed = new URL(url);
  assert.ok(["http:", "https:"].includes(parsed.protocol), `${label} must use HTTP(S), got ${parsed.protocol}`);
  if (expectedOrigin) assert.equal(parsed.origin, expectedOrigin, `${label} escaped the expected origin`);
  return parsed;
}

export function isIgnoredFavicon(record, expectedOrigin) {
  if (!record || record.method !== "GET" || typeof record.url !== "string") return false;
  if (isDataUrl(record.url)) return false;
  const url = new URL(record.url);
  return (
    url.origin === expectedOrigin &&
    url.pathname === "/favicon.ico" &&
    url.search === "" &&
    url.hash === "" &&
    record.resourceType === "Image"
  );
}

export function installDiagnostics(client, { expectedOrigin, secrets = [] } = {}) {
  const requests = new Map();
  const consoleErrors = [];
  const logErrors = [];
  const runtimeExceptions = [];
  const requestFailures = [];
  let sequence = 0;

  client.on("Network.requestWillBeSent", ({ requestId, request, type, redirectResponse }) => {
    const prior = requests.get(requestId);
    const redirects = prior?.redirects || [];
    if (redirectResponse) redirects.push({ status: redirectResponse.status, url: redirectResponse.url });
    requests.set(requestId, {
      requestId,
      sequence: ++sequence,
      startedAtMs: Date.now(),
      method: request.method,
      url: request.url,
      request,
      postData: request.postData,
      response: undefined,
      resourceType: type,
      redirects,
      finished: false,
      failed: undefined,
      dataUrl: isDataUrl(request.url),
    });
  });

  client.on("Network.responseReceived", ({ requestId, response, type }) => {
    const record = requests.get(requestId) || {
      requestId,
      sequence: ++sequence,
      startedAtMs: Date.now(),
      method: "?",
      url: response.url,
      request: {},
      redirects: [],
      finished: false,
      failed: undefined,
      dataUrl: isDataUrl(response.url),
    };
    record.response = response;
    record.resourceType = type || record.resourceType;
    requests.set(requestId, record);
    if (response.status >= 400 && !record.dataUrl && !isIgnoredFavicon(record, expectedOrigin)) {
      requestFailures.push(`${response.status} ${record.method} ${response.url}`);
    }
  });

  client.on("Network.loadingFinished", ({ requestId }) => {
    const record = requests.get(requestId);
    if (record) record.finished = true;
  });

  client.on("Network.loadingFailed", ({ requestId, errorText, canceled, blockedReason }) => {
    const record = requests.get(requestId);
    const detail = `${errorText || "request failed"}${canceled ? " (canceled)" : ""}${blockedReason ? ` (${blockedReason})` : ""}`;
    if (!record?.dataUrl && !isIgnoredFavicon(record, expectedOrigin)) {
      requestFailures.push(`${record?.method || "?"} ${record?.url || requestId}: ${detail}`);
    }
    if (record) record.failed = detail;
  });

  client.on("Runtime.consoleAPICalled", ({ type, args, stackTrace }) => {
    if (!["error", "assert"].includes(type)) return;
    const values = (args || []).map((arg) => arg.value ?? arg.description ?? arg.type).join(" ");
    consoleErrors.push(`${values}${stackTrace?.description ? `\n${stackTrace.description}` : ""}`);
  });

  client.on("Log.entryAdded", ({ entry }) => {
    if (["error", "assert"].includes(entry?.level)) {
      logErrors.push(`${entry.text || "browser log error"}${entry.url ? ` (${entry.url})` : ""}`);
    }
  });

  client.on("Runtime.exceptionThrown", (exception) => {
    runtimeExceptions.push(exceptionMessage(exception));
  });

  const describeFailures = (stage) => {
    const failures = [
      ...requestFailures.map((value) => `request failure: ${value}`),
      ...logErrors.map((value) => `log.error: ${value}`),
      ...consoleErrors.map((value) => `console.error/assert: ${value}`),
      ...runtimeExceptions.map((value) => `runtime exception: ${value}`),
      ...[...requests.values()]
        .filter((record) => !record.finished && !record.failed && !record.dataUrl && !isIgnoredFavicon(record, expectedOrigin))
        .map((record) => `outstanding request: ${record.method} ${record.url}`),
    ];
    return failures.length ? `${stage} browser diagnostics failed:\n${failures.join("\n")}` : null;
  };

  return {
    requests,
    consoleErrors,
    logErrors,
    runtimeExceptions,
    requestFailures,
    completed(predicate) {
      return [...requests.values()].filter((record) =>
        record.response && record.finished && !record.failed && predicate(record),
      );
    },
    async drainLateEvents(milliseconds = 250) {
      await sleep(milliseconds);
    },
    assertClean(stage) {
      const failure = describeFailures(stage);
      if (failure) throw new Error(redactText(failure, secrets));
    },
    describe() {
      return redactText(
        JSON.stringify(
          {
            requestFailures,
            logErrors,
            consoleErrors,
            runtimeExceptions,
            requests: [...requests.values()].map((record) => ({
              requestId: record.requestId,
              method: record.method,
              url: record.url,
              postData: record.postData,
              status: record.response?.status,
              resourceType: record.resourceType,
              redirects: record.redirects,
              finished: record.finished,
              failed: record.failed,
            })),
          },
          null,
          2,
        ),
        secrets,
      );
    },
  };
}

export async function evaluate(client, expression, label) {
  const result = await client.send("Runtime.evaluate", {
    expression,
    awaitPromise: true,
    returnByValue: true,
  });
  if (result.exceptionDetails) throw new Error(`${label}: ${exceptionMessage(result)}`);
  return result.result?.value;
}

export async function waitForExpression(client, expression, label, timeout = CDP_EVENT_TIMEOUT_MS) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    if (await evaluate(client, expression, label)) return;
    await sleep(POLL_INTERVAL_MS);
  }

  const state = await evaluate(
    client,
    "({url: location.href, readyState: document.readyState, body: document.body?.innerText?.slice(0, 2000)})",
    `${label} diagnostics`,
  ).catch(() => ({}));
  throw new Error(`${label} timed out: ${JSON.stringify(state)}`);
}

export async function waitForResponse(diagnostics, predicate, label, timeout = CDP_EVENT_TIMEOUT_MS) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    const match = diagnostics.completed(predicate)[0];
    if (match) return match;
    await sleep(POLL_INTERVAL_MS);
  }

  throw new Error(`${label} response was not observed`);
}

export function parseResponseBody(result, label) {
  assert.equal(typeof result, "object", `${label} response body was unavailable`);
  assert.equal(typeof result.body, "string", `${label} response body was unavailable`);
  const body = result.base64Encoded ? Buffer.from(result.body, "base64").toString("utf8") : result.body;
  assert.ok(body.length > 0, `${label} response body was empty`);
  return body;
}

export async function responseJson(client, record, label) {
  const result = await client.send("Network.getResponseBody", { requestId: record.requestId });
  const body = parseResponseBody(result, label);
  try {
    return JSON.parse(body);
  } catch (error) {
    throw new Error(`${label} returned invalid JSON: ${error.message}`);
  }
}

export function parseRequestBody(record, label) {
  assert.equal(typeof record?.postData, "string", `${label} request body was unavailable`);
  try {
    return JSON.parse(record.postData);
  } catch (error) {
    throw new Error(`${label} request body was not JSON: ${error.message}`);
  }
}

function requestHeader(record, name) {
  const headers = record?.request?.headers || {};
  const expected = name.toLowerCase();
  const key = Object.keys(headers).find((candidate) => candidate.toLowerCase() === expected);
  return key ? headers[key] : undefined;
}

export function assertHttpRequestContract(
  record,
  { origin, method, pathname, label, body, headers = {}, requireIdempotencyKey = false },
) {
  assert.ok(record, `${label} request was not observed`);
  const url = assertHttpUrl(record.url, origin, `${label} request URL`);
  assert.equal(url.pathname, pathname, `${label} request path changed`);
  assert.equal(record.method, method, `${label} request method changed`);
  assert.deepEqual(record.redirects, [], `${label} request redirected`);
  assert.ok(record.response, `${label} response was not observed`);
  assert.equal(record.response.status, 200, `${label} response must be HTTP 200`);
  assert.equal(record.finished, true, `${label} response was not finished`);
  assert.equal(record.failed, undefined, `${label} request failed`);

  if (body === undefined) {
    assert.equal(record.postData, undefined, `${label} unexpectedly sent a request body`);
  } else {
    assert.deepEqual(parseRequestBody(record, label), body, `${label} JSON body changed`);
  }

  for (const [name, value] of Object.entries(headers)) {
    assert.equal(requestHeader(record, name), value, `${label} missing or incorrect ${name} header`);
  }
  if (requireIdempotencyKey) {
    const key = requestHeader(record, "idempotency-key");
    assert.match(key || "", /^[0-9a-f-]{16,}$/i, `${label} requires an idempotency key`);
  }
  return record;
}

export function pathMatches(record, method, pathname, origin) {
  if (!record || record.method !== method || isDataUrl(record.url)) return false;
  const url = new URL(record.url);
  return url.origin === origin && url.pathname === pathname;
}

export function assertManifestAssetsRequested(
  manifest,
  manifestUrl,
  records,
  { origin, label = "remote manifest" } = {},
) {
  const manifestLocation = assertHttpUrl(manifestUrl, origin, `${label} URL`);
  const assetStrings = new Set();

  const visit = (value) => {
    if (typeof value === "string" && /\.(?:m?js|css)(?:[?#]|$)/i.test(value)) {
      assetStrings.add(value);
    } else if (Array.isArray(value)) {
      for (const child of value) visit(child);
    } else if (value && typeof value === "object") {
      for (const child of Object.values(value)) visit(child);
    }
  };
  visit(manifest);

  assert.ok(assetStrings.size > 0, `${label} declared no JavaScript or CSS assets`);
  const assets = [...assetStrings].map((asset) =>
    assertHttpUrl(new URL(asset, manifestLocation).href, origin, `${label} asset`),
  );
  for (const asset of assets) {
    const loaded = records.find((record) => {
      if (!record.response || record.failed || !record.finished) return false;
      try {
        return new URL(record.url).href === asset.href;
      } catch {
        return false;
      }
    });
    assert.ok(loaded, `${label} asset was not successfully requested: ${asset.href}`);
    assert.equal(loaded.response.status, 200, `${label} asset was not HTTP 200: ${asset.href}`);
    assert.deepEqual(loaded.redirects, [], `${label} asset redirected: ${asset.href}`);
  }
  return assets.map((asset) => asset.href);
}

export function requirePostActionRefresh(
  records,
  { beforeRequestIds, beforeCount, actionStartedAtMs, pathname, origin, label = "action" },
) {
  const after = records.filter((record) => pathMatches(record, "POST", pathname, origin));
  assert.ok(after.length > beforeCount, `${label} did not produce a new query request`);
  const fresh = after.filter(
    (record) => !beforeRequestIds.has(record.requestId) && record.startedAtMs >= actionStartedAtMs,
  );
  assert.ok(fresh.length > 0, `${label} did not produce a post-action query response`);
  return fresh[fresh.length - 1];
}

export async function navigate(client, url, { expectedOrigin, expectedPath } = {}) {
  const target = assertHttpUrl(url, expectedOrigin, "navigation URL");
  reportProgress(`navigating ${target.href}`);
  // Both listeners are installed before Page.navigate so a fast redirect cannot
  // satisfy the document assertion with an event from the previous page.
  const frameNavigation = client.waitForEvent("Page.frameNavigated", ({ frame }) => !frame.parentId);
  const loadEvent = client.once("Page.loadEventFired");
  const result = await client.send("Page.navigate", { url: target.href });
  assert.ok(!result?.errorText, `Page.navigate failed: ${result?.errorText || "unknown error"}`);
  const frame = await frameNavigation;
  await loadEvent;
  const documentState = await evaluate(
    client,
    "({href: location.href, origin: location.origin, readyState: document.readyState, hasBody: document.body !== null})",
    `${target.href} document validation`,
  );
  assertHttpUrl(documentState.href, expectedOrigin, "resulting document URL");
  assert.equal(documentState.origin, target.origin, "resulting document origin changed");
  if (expectedPath) assert.equal(new URL(documentState.href).pathname, expectedPath, "resulting document path changed");
  assert.equal(documentState.readyState, "complete", "resulting document did not load");
  assert.equal(documentState.hasBody, true, "resulting document has no body");
  assertHttpUrl(frame.frame.url, expectedOrigin, "frame navigation URL");
}

async function submitSignIn(client, loginUrl, email, password, expectedOrigin) {
  const login = assertHttpUrl(loginUrl, expectedOrigin, "sign-in URL");
  await navigate(client, login.href, { expectedOrigin, expectedPath: login.pathname });
  await waitForExpression(
    client,
    "Boolean(document.querySelector('#sign-in-form input[name=\"user[email]\"]') && document.querySelector('#sign-in-form input[name=\"user[password]\"]'))",
    "sign-in form",
  );

  const frameNavigation = client.waitForEvent("Page.frameNavigated", ({ frame }) => !frame.parentId);
  const loadEvent = client.once("Page.loadEventFired");
  const result = await evaluate(
    client,
    `(() => {
      const form = document.querySelector('#sign-in-form');
      const emailInput = form?.querySelector('input[name="user[email]"]');
      const passwordInput = form?.querySelector('input[name="user[password]"]');
      if (!form || !emailInput || !passwordInput) return false;
      emailInput.value = ${JSON.stringify(email)};
      passwordInput.value = ${JSON.stringify(password)};
      emailInput.dispatchEvent(new Event('input', {bubbles: true}));
      passwordInput.dispatchEvent(new Event('input', {bubbles: true}));
      form.submit();
      return true;
    })()`,
    "sign-in submission",
  );
  assert.equal(result, true, "sign-in form was not submitted");
  await frameNavigation;
  await loadEvent;
  const state = await evaluate(client, "({href: location.href, origin: location.origin})", "authenticated redirect");
  assertHttpUrl(state.href, expectedOrigin, "authenticated redirect URL");
  assert.equal(state.origin, expectedOrigin, "authenticated redirect changed origin");
  await waitForExpression(client, "location.pathname !== '/sign-in' && !document.querySelector('#sign-in-form')", "authenticated redirect");
}

function assertCatalog(catalog, applicationKey, surfaceId, expectedScope, expectedOrigin) {
  assert.equal(catalog.schema, "cadence.first-party-frontend-catalog.v1");
  assert.equal(catalog.hostContract, "cadence.application-host.v1");
  assert.ok(!Number.isNaN(Date.parse(catalog.generatedAt)), "catalog generatedAt is not a timestamp");
  assert.equal(catalog.session.context.scope, expectedScope);
  assert.ok(catalog.session.sessionId);
  assert.ok(catalog.session.csrfToken);
  assertHttpUrl(new URL(catalog.session.bridgeBaseUrl, expectedOrigin).href, expectedOrigin, "catalog bridge base URL");
  assert.equal(catalog.applications.length, 1);

  const application = catalog.applications[0];
  assert.equal(application.applicationKey, applicationKey);
  assert.equal(application.applicationVersion, 1);
  assert.equal(application.surface.surfaceId, surfaceId);
  assert.equal(application.surface.version, 1);
  assert.equal(application.release.federation, "module_federation");
  assert.equal(application.release.exposedModule, "./Application");
  assertHttpUrl(application.release.manifestUrl, expectedOrigin, `${applicationKey} manifest URL`);
  return application;
}

function queryBody(application, queryId, queryVersion, scope) {
  return {
    applicationKey: application.applicationKey,
    applicationVersion: application.applicationVersion,
    surfaceId: application.surface.surfaceId,
    surfaceVersion: application.surface.version,
    queryId,
    queryVersion,
    scope,
  };
}

async function assertRemoteSurface({
  client,
  diagnostics,
  url,
  expectedOrigin,
  catalogPath,
  applicationKey,
  surfaceId,
  expectedScope,
  remotePath,
  readyExpression,
  queryPath,
  queryId,
  queryVersion,
}) {
  const surfaceUrl = assertHttpUrl(url, expectedOrigin, `${applicationKey} surface URL`);
  await navigate(client, surfaceUrl.href, { expectedOrigin, expectedPath: surfaceUrl.pathname });
  try {
    await waitForExpression(client, readyExpression, `${applicationKey} REMOTE READY`);
  } catch (error) {
    throw new Error(`${error.message}\n${diagnostics.describe()}`, { cause: error });
  }
  diagnostics.assertClean(`${applicationKey} surface`);

  const catalogRecord = await waitForResponse(
    diagnostics,
    (record) => pathMatches(record, "GET", catalogPath, expectedOrigin),
    `${applicationKey} catalog`,
  );
  assertHttpRequestContract(catalogRecord, {
    origin: expectedOrigin,
    method: "GET",
    pathname: catalogPath,
    label: `${applicationKey} catalog`,
  });
  const catalog = await responseJson(client, catalogRecord, `${applicationKey} catalog`);
  const application = assertCatalog(catalog, applicationKey, surfaceId, expectedScope, expectedOrigin);

  const manifestUrl = assertHttpUrl(application.release.manifestUrl, expectedOrigin, `${applicationKey} manifest URL`);
  const manifestRecord = await waitForResponse(
    diagnostics,
    (record) => pathMatches(record, "GET", manifestUrl.pathname, expectedOrigin),
    `${applicationKey} manifest`,
  );
  assertHttpRequestContract(manifestRecord, {
    origin: expectedOrigin,
    method: "GET",
    pathname: manifestUrl.pathname,
    label: `${applicationKey} manifest`,
  });
  const manifest = await responseJson(client, manifestRecord, `${applicationKey} manifest`);
  assert.equal(typeof manifest, "object");
  assertManifestAssetsRequested(manifest, manifestUrl.href, diagnostics.completed(() => true), {
    origin: expectedOrigin,
    label: `${applicationKey} manifest`,
  });

  const hostRecord = diagnostics.completed(
    (record) => pathMatches(record, "GET", "/assets/application-host/host/host.js", expectedOrigin),
  )[0];
  assertHttpRequestContract(hostRecord, {
    origin: expectedOrigin,
    method: "GET",
    pathname: "/assets/application-host/host/host.js",
    label: "published Phoenix host bundle",
  });
  const hostBody = await client.send("Network.getResponseBody", { requestId: hostRecord.requestId });
  parseResponseBody(hostBody, "published Phoenix host bundle");

  assert.ok(manifestUrl.pathname.startsWith(remotePath), `${applicationKey} manifest escaped its published remote path`);
  const queryRecord = await waitForResponse(
    diagnostics,
    (record) => pathMatches(record, "POST", queryPath, expectedOrigin),
    `${applicationKey} query`,
  );
  const scope = catalog.session.context;
  assertHttpRequestContract(queryRecord, {
    origin: expectedOrigin,
    method: "POST",
    pathname: queryPath,
    label: `${applicationKey} query`,
    headers: {
      "content-type": "application/json",
      "x-cadence-poc-session": catalog.session.sessionId,
      "x-csrf-token": catalog.session.csrfToken,
    },
    body: queryBody(application, queryId, queryVersion, {
      organizationId: scope.organizationId,
      missionId: scope.missionId,
      spacecraftId: scope.spacecraftId,
    }),
  });
  const query = await responseJson(client, queryRecord, `${applicationKey} query`);
  return { catalog, application, manifest, query, queryRecord, queryPath };
}

export async function runScenario(client, diagnostics, args, { secret, signal } = {}) {
  assertNoPasswordArgument(args);
  const commsUrl = requiredArg(args, "--comms-url");
  const telemetryUrl = requiredArg(args, "--telemetry-url");
  const loginUrl = requiredArg(args, "--login-url");
  const email = requiredArg(args, "--login-email");
  const missionId = requiredArg(args, "--mission-id");
  const spacecraftId = requiredArg(args, "--spacecraft-id");
  const expectedApid = Number(requiredArg(args, "--expected-apid"));
  assert.equal(Number.isInteger(expectedApid), true, "--expected-apid must be an integer");
  assert.ok(secret?.password, "structured login secret is required");

  const origin = assertHttpUrl(commsUrl, undefined, "Comms surface URL").origin;
  assertHttpUrl(telemetryUrl, origin, "Telemetry surface URL");
  assertHttpUrl(loginUrl, origin, "sign-in URL");

  reportProgress("authenticating browser session");
  await submitSignIn(client, loginUrl, email, secret.password, origin);
  diagnostics.assertClean("authenticated sign-in");

  const commsQueryPath = `/api/cadence/application-host/v1/missions/${encodeURIComponent(missionId)}/query`;
  const comms = await assertRemoteSurface({
    client,
    diagnostics,
    url: commsUrl,
    expectedOrigin: origin,
    catalogPath: `/api/cadence/application-host/v1/missions/${encodeURIComponent(missionId)}/catalog`,
    applicationKey: "comms_overview",
    surfaceId: "overview",
    expectedScope: "mission",
    remotePath: "/assets/application-host/comms-overview/",
    readyExpression: "Boolean(document.querySelector('.phoenix-host-release')?.textContent.trim() === 'REMOTE READY' && document.querySelector('#comms-overview-application') && document.querySelector('#comms-overview-page') && document.querySelector('#comms-overview-content') && document.querySelector('#comms-transports') && !document.querySelector('#remote-error') && !document.querySelector('#comms-overview-error'))",
    queryPath: commsQueryPath,
    queryId: "cadence.comms.overview",
    queryVersion: 1,
  });
  assert.equal(comms.query.queryVersion, 1);
  assert.equal(comms.query.presentation.root.attrs.id, "comms-overview-page");
  assert.equal(comms.query.presentation.overview.transport.id, "comms-transports");
  assert.equal(comms.query.presentation.overview.transport.count, 1);

  reportProgress("verifying Comms Overview DOM and network contract");
  assert.equal(
    await evaluate(client, "document.querySelector('#comms-transports')?.textContent?.includes('Federation Browser Transport')", "Comms Overview transport"),
    true,
  );

  const telemetryQueryPath = `/api/cadence/application-host/v1/missions/${encodeURIComponent(missionId)}/spacecraft/${encodeURIComponent(spacecraftId)}/query`;
  const telemetry = await assertRemoteSurface({
    client,
    diagnostics,
    url: telemetryUrl,
    expectedOrigin: origin,
    catalogPath: `/api/cadence/application-host/v1/missions/${encodeURIComponent(missionId)}/spacecraft/${encodeURIComponent(spacecraftId)}/catalog`,
    applicationKey: "telemetry_decom",
    surfaceId: "packet_bindings",
    expectedScope: "spacecraft",
    remotePath: "/assets/application-host/telemetry-decom/",
    readyExpression: "Boolean(document.querySelector('.phoenix-host-release')?.textContent.trim() === 'REMOTE READY' && document.querySelector('#telemetry-decom-application') && document.querySelector('#packet-bindings-surface') && document.querySelector('#packet-bindings-form') && document.querySelector('#packet-bindings-submit') && !document.querySelector('#remote-error') && !document.querySelector('#telemetry-decom-error'))",
    queryPath: telemetryQueryPath,
    queryId: "cadence.packet_bindings.manage",
    queryVersion: 1,
  });

  assert.equal(telemetry.query.host.application_key, "telemetry_decom");
  assert.equal(telemetry.query.declarative_surface.packet_bindings.action.action_id, "save_packet_bindings");
  const packetGroup = telemetry.query.application_surface_packet_groups.find(
    (group) => group.apid === expectedApid,
  );
  assert.ok(packetGroup, `telemetry query did not return APID ${expectedApid}`);
  assert.equal(packetGroup.selected, true);
  const packetId = packetGroup.packet_id;

  const telemetryState = await evaluate(
    client,
    `(() => {
      const group = document.querySelector('[data-apid="${expectedApid}"]');
      const checkbox = group?.querySelector('input[type="checkbox"]');
      return {group: Boolean(group), checked: checkbox?.checked === true};
    })()`,
    "Telemetry packet group",
  );
  assert.deepEqual(telemetryState, { group: true, checked: true });

  const queryRecordsBeforeAction = diagnostics.completed(
    (record) => pathMatches(record, "POST", telemetryQueryPath, origin),
  );
  const beforeRequestIds = new Set(queryRecordsBeforeAction.map((record) => record.requestId));
  const beforeCount = queryRecordsBeforeAction.length;
  const actionStartedAtMs = Date.now();

  reportProgress("submitting Telemetry packet-bindings action");
  const clicked = await evaluate(
    client,
    "(() => { const button = document.querySelector('#packet-bindings-submit'); if (!button) return false; button.click(); return true; })()",
    "Telemetry packet-bindings submit",
  );
  assert.equal(clicked, true);

  const actionPath = `/api/cadence/application-host/v1/missions/${encodeURIComponent(missionId)}/spacecraft/${encodeURIComponent(spacecraftId)}/actions`;
  const actionRecord = await waitForResponse(
    diagnostics,
    (record) => pathMatches(record, "POST", actionPath, origin) && record.startedAtMs >= actionStartedAtMs,
    "Telemetry packet-bindings action",
  );
  const telemetryScope = telemetry.catalog.session.context;
  assertHttpRequestContract(actionRecord, {
    origin,
    method: "POST",
    pathname: actionPath,
    label: "Telemetry packet-bindings action",
    headers: {
      "content-type": "application/json",
      "x-cadence-poc-session": telemetry.catalog.session.sessionId,
      "x-csrf-token": telemetry.catalog.session.csrfToken,
    },
    requireIdempotencyKey: true,
    body: {
      applicationKey: "telemetry_decom",
      applicationVersion: 1,
      surfaceId: "packet_bindings",
      surfaceVersion: 1,
      actionId: "save_packet_bindings",
      input: { source_endpoint: "primary", selected_packet_ids: [packetId] },
      scope: {
        organizationId: telemetryScope.organizationId,
        missionId: telemetryScope.missionId,
        spacecraftId: telemetryScope.spacecraftId,
      },
    },
  });
  const receipt = await responseJson(client, actionRecord, "Telemetry packet-bindings action");
  assert.match(receipt.receiptId, /^application-host-receipt-/);
  assert.equal(receipt.result.applicationKey, "telemetry_decom");
  assert.deepEqual(receipt.result.selectedPacketIds, [packetId]);

  const refreshedQueryRecord = await waitForResponse(
    diagnostics,
    (record) =>
      pathMatches(record, "POST", telemetryQueryPath, origin) &&
      !beforeRequestIds.has(record.requestId) &&
      record.startedAtMs >= actionStartedAtMs,
    "Telemetry canonical query refresh",
  );
  assert.equal(
    requirePostActionRefresh(diagnostics.completed(() => true), {
      beforeRequestIds,
      beforeCount,
      actionStartedAtMs,
      pathname: telemetryQueryPath,
      origin,
      label: "Telemetry packet-bindings action",
    }).requestId,
    refreshedQueryRecord.requestId,
  );
  assertHttpRequestContract(refreshedQueryRecord, {
    origin,
    method: "POST",
    pathname: telemetryQueryPath,
    label: "Telemetry refreshed query",
    headers: {
      "content-type": "application/json",
      "x-cadence-poc-session": telemetry.catalog.session.sessionId,
      "x-csrf-token": telemetry.catalog.session.csrfToken,
    },
    body: queryBody(telemetry.application, "cadence.packet_bindings.manage", 1, {
      organizationId: telemetryScope.organizationId,
      missionId: telemetryScope.missionId,
      spacecraftId: telemetryScope.spacecraftId,
    }),
  });
  const refreshedQuery = await responseJson(client, refreshedQueryRecord, "Telemetry refreshed query");
  const refreshedGroup = refreshedQuery.application_surface_packet_groups.find(
    (group) => group.packet_id === packetId,
  );
  assert.ok(refreshedGroup, "refreshed telemetry query dropped the selected packet group");
  assert.equal(refreshedGroup.selected, true);

  await waitForExpression(
    client,
    "Boolean(document.querySelector('#telemetry-decom-action-notice') && document.querySelector('#telemetry-decom-action-notice').textContent.includes('refreshed from the host'))",
    "Telemetry canonical refresh notice",
  );
  assert.equal(
    await evaluate(client, `document.querySelector('[data-apid="${expectedApid}"] input[type="checkbox"]')?.checked === true`, "Telemetry retained selection"),
    true,
  );

  await diagnostics.drainLateEvents();
  diagnostics.assertClean("federation browser gate");
  return {
    origin,
    remotes: [comms.application.release.releaseId, telemetry.application.release.releaseId],
    queryResponses: diagnostics.completed((record) => pathMatches(record, "POST", telemetryQueryPath, origin)).length,
    actionReceipt: receipt.receiptId,
    retainedPacketId: packetId,
  };
}

export async function readStructuredLoginSecret({ stream = process.stdin, signal } = {}) {
  return raceWithSignalAndTimeout(
    new Promise((resolveSecret, rejectSecret) => {
      let buffer = "";
      let finished = false;
      const finish = (callback, value) => {
        if (finished) return;
        finished = true;
        stream.removeListener("data", onData);
        stream.removeListener("end", onEnd);
        stream.removeListener("error", onError);
        callback(value);
      };
      const parse = () => {
        const line = buffer.split("\n", 1)[0].trim();
        if (!line) return;
        try {
          const value = JSON.parse(line);
          if (!value || typeof value.password !== "string" || value.password.length === 0) {
            throw new Error("structured login secret must contain a non-empty password");
          }
          finish(resolveSecret, { password: value.password });
        } catch (error) {
          finish(rejectSecret, error);
        }
      };
      const onData = (chunk) => {
        buffer += chunk.toString();
        if (buffer.length > 64 * 1024) finish(rejectSecret, new Error("structured login secret is too large"));
        else parse();
      };
      const onEnd = () => {
        parse();
        if (!finished) finish(rejectSecret, new Error("structured login secret was not provided"));
      };
      const onError = (error) => finish(rejectSecret, error);
      stream.setEncoding?.("utf8");
      stream.on("data", onData);
      stream.once("end", onEnd);
      stream.once("error", onError);
    }),
    { signal, milliseconds: 5_000, label: "structured login secret" },
  );
}

export function installShutdownGuards({ onAbort }) {
  const initialParentPid = process.ppid;
  let disposed = false;
  let aborting = false;
  let exitCode;

  const abort = (reason, code = 1) => {
    if (disposed || aborting) return;
    aborting = true;
    exitCode = code;
    onAbort(reason);
  };
  const onSignal = (signal) => abort(new Error(`browser gate received ${signal}`), signal === "SIGINT" ? 130 : 128 + (signal === "SIGTERM" ? 15 : 1));
  const onPipeError = (error) => {
    if (error?.code === "EPIPE") {
      outputBroken = true;
      abort(new Error("browser gate output pipe closed"));
    }
  };

  const signalHandlers = {
    SIGINT: () => onSignal("SIGINT"),
    SIGTERM: () => onSignal("SIGTERM"),
    SIGHUP: () => onSignal("SIGHUP"),
  };
  for (const [signal, handler] of Object.entries(signalHandlers)) process.once(signal, handler);
  process.stdout.on("error", onPipeError);
  process.stderr.on("error", onPipeError);
  const orphanTimer = setInterval(() => {
    if (initialParentPid !== 1 && process.ppid === 1) abort(new Error("browser gate parent process disappeared"));
  }, 250);
  orphanTimer.unref();

  return {
    get exitCode() {
      return exitCode;
    },
    dispose() {
      if (disposed) return;
      disposed = true;
      clearInterval(orphanTimer);
      for (const [signal, handler] of Object.entries(signalHandlers)) process.removeListener(signal, handler);
      process.stdout.removeListener("error", onPipeError);
      process.stderr.removeListener("error", onPipeError);
    },
  };
}

export async function runBrowserGate(args = process.argv.slice(2), { env = process.env } = {}) {
  assertNoPasswordArgument(args);
  const controller = new AbortController();
  const state = { runtime: null, client: null, page: null };
  const secrets = [];
  const guards = installShutdownGuards({
    onAbort: (reason) => {
      controller.abort(reason);
      state.client?.close();
      void state.runtime?.close();
    },
  });
  let runError;

  try {
    const secret = argValue(args, "--login-email")
      ? await readStructuredLoginSecret({ signal: controller.signal })
      : null;
    if (secret) secrets.push(secret.password);

    reportProgress("launching bounded Chrome process");
    state.runtime = await launchChrome({
      env,
      signal: controller.signal,
      onRuntime: (runtime) => {
        state.runtime = runtime;
      },
    });
    reportProgress("creating browser target");
    state.page = await createPage(state.runtime.endpoint, "about:blank", { signal: controller.signal });
    state.client = new CdpClient(state.page.webSocketDebuggerUrl);
    await state.client.send("Page.enable");
    await state.client.send("Runtime.enable");
    await state.client.send("Network.enable");
    await state.client.send("Network.setCacheDisabled", { cacheDisabled: true });
    await state.client.send("Log.enable");
    await state.client.send("Emulation.setDeviceMetricsOverride", {
      width: 1440,
      height: 1000,
      deviceScaleFactor: 1,
      mobile: false,
    });

    const commsUrl = requiredArg(args, "--comms-url");
    const diagnostics = installDiagnostics(state.client, { expectedOrigin: new URL(commsUrl).origin, secrets });
    const timeout = Number(argValue(args, "--scenario-timeout-ms") || SCENARIO_TIMEOUT_MS);
    assert.ok(Number.isFinite(timeout) && timeout > 0, "--scenario-timeout-ms must be positive");
    const scenario = runScenario(state.client, diagnostics, args, { secret, signal: controller.signal });
    const result = await raceWithSignalAndTimeout(scenario, {
      signal: controller.signal,
      milliseconds: timeout,
      label: "federation browser scenario",
      onTimeout: (error) => {
        controller.abort(error);
        state.client?.close();
        void state.runtime?.close();
      },
    });
    diagnostics.assertClean("federation browser gate final");
    return result;
  } catch (error) {
    const safe = new Error(redactError(error, secrets));
    safe.exitCode = guards.exitCode;
    runError = safe;
    throw safe;
  } finally {
    guards.dispose();
    reportProgress("cleaning up browser process and profile");
    const cleanupErrors = [];
    try {
      await closePage(state.runtime?.endpoint, state.page?.id, {
        timeout: PAGE_CLOSE_CLEANUP_TIMEOUT_MS,
      });
    } catch (error) {
      cleanupErrors.push(error);
    }
    state.client?.close();
    try {
      await state.runtime?.close();
    } catch (error) {
      cleanupErrors.push(error);
    }
    if (cleanupErrors.length) {
      const message = redactText(cleanupErrors.map(redactError).join("\n"), secrets);
      const combined = new Error(runError ? `${redactError(runError, secrets)}\n${message}` : message);
      combined.exitCode = runError?.exitCode;
      throw combined;
    }
  }
}

const isMain = process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href;
if (isMain) {
  try {
    const result = await runBrowserGate();
    if (!outputBroken) {
      console.log(JSON.stringify(result, null, 2));
      console.log("federation_browser_smoke passed");
    }
  } catch (error) {
    if (!outputBroken) console.error(redactError(error));
    process.exitCode = error?.exitCode || 1;
  }
}
