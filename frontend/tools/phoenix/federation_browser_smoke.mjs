import assert from "node:assert/strict";
import { accessSync, constants, statSync } from "node:fs";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { createServer } from "node:net";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { spawn } from "node:child_process";
import { types as nodeTypes } from "node:util";

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

export function activeResourceNames() {
  return typeof process.getActiveResourcesInfo === "function"
    ? process.getActiveResourcesInfo()
    : [];
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

export function sleep(milliseconds, signal) {
  if (signal?.aborted) return Promise.reject(abortError(signal));

  return new Promise((resolveSleep, rejectSleep) => {
    let settled = false;
    let timer;
    const onAbort = () => finish(rejectSleep, abortError(signal));
    const finish = (callback, value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      signal?.removeEventListener("abort", onAbort);
      callback(value);
    };

    signal?.addEventListener("abort", onAbort, { once: true });
    if (signal?.aborted) onAbort();
    else timer = setTimeout(() => finish(resolveSleep), milliseconds);
  });
}

function rejectedPromise(error) {
  const rejection = Promise.reject(error);
  rejection.catch(() => {});
  return rejection;
}

function allowedNativePromise(value) {
  if (value === null || typeof value !== "object") return false;
  if (nodeTypes.isProxy(value)) return false;

  try {
    if (Object.getPrototypeOf(value) !== Promise.prototype) return false;
    const brandCheck = Promise.prototype.then.call(
      value,
      () => undefined,
      () => undefined,
    );
    Promise.prototype.then.call(brandCheck, undefined, () => {});
    for (const key of Reflect.ownKeys(value)) {
      if (typeof key === "string") return false;
      const descriptor = Object.getOwnPropertyDescriptor(value, key);
      if (
        !descriptor ||
        !Object.hasOwn(descriptor, "value") ||
        (descriptor.value !== null && typeof descriptor.value === "object") ||
        typeof descriptor.value === "function"
      )
        return false;
    }
    return true;
  } catch {
    return false;
  }
}

function unsafeThenDescriptor(value) {
  if (value === null || (typeof value !== "object" && typeof value !== "function"))
    return undefined;
  if (nodeTypes.isProxy(value)) return "value was a proxy";

  const visited = new Set();
  let prototype = value;
  try {
    while (prototype !== null) {
      if (visited.has(prototype)) return "prototype chain was cyclic";
      visited.add(prototype);
      const descriptor = Object.getOwnPropertyDescriptor(prototype, "then");
      if (
        descriptor &&
        (!Object.hasOwn(descriptor, "value") || typeof descriptor.value === "function")
      ) {
        return "then is an accessor or callable property";
      }
      prototype = Object.getPrototypeOf(prototype);
    }
  } catch (error) {
    return `thenability inspection failed: ${error.message}`;
  }

  return undefined;
}

function validateRaceValue(value, label) {
  if (typeof value === "function") {
    throw new TypeError(`${label} returned a callable value`);
  }
  if (value === null || typeof value !== "object") return;
  if (nodeTypes.isProxy(value)) {
    throw new TypeError(`${label} returned a proxy object`);
  }
  if (allowedNativePromise(value)) return;

  const unsafeThen = unsafeThenDescriptor(value);
  if (unsafeThen) throw new TypeError(`${label} returned an arbitrary thenable: ${unsafeThen}`);
}

function invokeValidated(operation, label) {
  if (typeof operation !== "function" || nodeTypes.isProxy(operation)) {
    return rejectedPromise(new TypeError(`${label} was not a safe callable`));
  }

  try {
    const value = operation();
    validateRaceValue(value, label);
    return value;
  } catch (error) {
    return rejectedPromise(error);
  }
}

function acquisitionAuthority(value, capture) {
  if (allowedNativePromise(value)) {
    try {
      return Promise.prototype.then.call(value, capture, (error) => {
        throw error;
      });
    } catch (error) {
      return rejectedPromise(error);
    }
  }

  return new Promise((resolveAcquisition, rejectAcquisition) => {
    queueMicrotask(() => {
      try {
        resolveAcquisition(capture(value));
      } catch (error) {
        rejectAcquisition(error);
      }
    });
  });
}

function safeDataDescriptors(value) {
  if (value === null || typeof value !== "object") return { error: "was not an object" };
  if (nodeTypes.isProxy(value)) return { error: "was a proxy" };

  let prototype;
  try {
    prototype = Object.getPrototypeOf(value);
  } catch {
    return { error: "prototype inspection failed" };
  }
  if (prototype !== Object.prototype && prototype !== null)
    return { error: "was not an ordinary object" };

  let keys;
  try {
    keys = Reflect.ownKeys(value);
  } catch {
    return { error: "own-key inspection failed" };
  }
  const descriptors = new Map();
  for (const key of keys) {
    if (typeof key !== "string") return { error: "contained an own symbol" };
    let descriptor;
    try {
      descriptor = Object.getOwnPropertyDescriptor(value, key);
    } catch {
      return { error: `could not inspect ${key}` };
    }
    if (!descriptor) return { error: `lost own descriptor for ${key}` };
    if (!Object.hasOwn(descriptor, "value")) return { error: `${key} was an accessor` };
    descriptors.set(key, descriptor);
  }
  return { keys, descriptors };
}

function safeOrdinaryArrayEntries(value) {
  if (value === null || typeof value !== "object") return { error: "was not an array" };
  if (nodeTypes.isProxy(value) || !Array.isArray(value))
    return { error: "was not an ordinary array" };

  let prototype;
  try {
    prototype = Object.getPrototypeOf(value);
  } catch {
    return { error: "prototype inspection failed" };
  }
  if (prototype !== Array.prototype) return { error: "was not an ordinary array" };

  let keys;
  try {
    keys = Reflect.ownKeys(value);
  } catch {
    return { error: "own-key inspection failed" };
  }
  const descriptors = new Map();
  for (const key of keys) {
    let descriptor;
    try {
      descriptor = Object.getOwnPropertyDescriptor(value, key);
    } catch {
      return { error: "array descriptor inspection failed" };
    }
    if (!descriptor || !Object.hasOwn(descriptor, "value"))
      return { error: "array contained an accessor" };
    descriptors.set(key, descriptor);
  }

  const lengthDescriptor = descriptors.get("length");
  if (
    !lengthDescriptor ||
    !Number.isSafeInteger(lengthDescriptor.value) ||
    lengthDescriptor.value < 0
  ) {
    return { error: "array had an invalid length" };
  }
  const length = lengthDescriptor.value;
  for (const key of keys) {
    if (typeof key === "symbol") return { error: "array contained an own symbol" };
    if (key !== "length" && (!arrayIndexKey(key) || Number(key) >= length)) {
      return { error: `array contained an extra own key ${key}` };
    }
  }
  const entries = [];
  for (let index = 0; index < length; index += 1) {
    const descriptor = descriptors.get(String(index));
    if (!descriptor) return { error: `array index ${index} was a hole` };
    entries.push(descriptor.value);
  }
  return { entries };
}

function copyDiagnosticValue(
  value,
  { freeze = false } = {},
  path = "diagnostic value",
  seen = new WeakMap(),
) {
  if (value === null || typeof value === "string" || typeof value === "boolean") return value;
  if (typeof value === "number") return Number.isFinite(value) ? value : null;
  if (value === undefined) return undefined;
  if (typeof value !== "object") throw new TypeError(`${path} contained a non-data value`);
  if (nodeTypes.isProxy(value)) throw new TypeError(`${path} was a proxy`);
  if (seen.has(value)) throw new TypeError(`${path} was cyclic`);

  let prototype;
  try {
    prototype = Object.getPrototypeOf(value);
  } catch {
    throw new TypeError(`${path} prototype inspection failed`);
  }

  const array = Array.isArray(value);
  if (array && prototype !== Array.prototype)
    throw new TypeError(`${path} was not an ordinary array`);
  if (!array && prototype !== Object.prototype && prototype !== null) {
    throw new TypeError(`${path} was not an ordinary object`);
  }

  let keys;
  try {
    keys = Reflect.ownKeys(value);
  } catch {
    throw new TypeError(`${path} own-key inspection failed`);
  }
  const output = array ? [] : prototype === null ? Object.create(null) : {};
  seen.set(value, output);

  for (const key of keys) {
    if (typeof key === "symbol") throw new TypeError(`${path} contained an own symbol`);
    let descriptor;
    try {
      descriptor = Object.getOwnPropertyDescriptor(value, key);
    } catch {
      throw new TypeError(`${path}.${key} descriptor inspection failed`);
    }
    if (!descriptor || !Object.hasOwn(descriptor, "value")) {
      throw new TypeError(`${path}.${key} was an accessor`);
    }
    if (array && key === "length") continue;
    if (array && (!arrayIndexKey(key) || Number(key) >= value.length)) {
      throw new TypeError(`${path} contained an extra own key ${key}`);
    }
    if (!array && !descriptor.enumerable) continue;
    Object.defineProperty(output, key, {
      value: copyDiagnosticValue(descriptor.value, { freeze }, `${path}.${key}`, seen),
      enumerable: descriptor.enumerable,
      configurable: true,
      writable: true,
    });
  }
  if (array) {
    if (!Object.hasOwn(Object.getOwnPropertyDescriptors(value), "length")) {
      throw new TypeError(`${path} had no length`);
    }
    for (let index = 0; index < value.length; index += 1) {
      if (!Object.hasOwn(output, String(index)))
        throw new TypeError(`${path}[${index}] was a hole`);
    }
  }
  seen.delete(value);
  return freeze ? Object.freeze(output) : output;
}

function observationFingerprint(
  value,
  path = "observation",
  seen = new WeakMap(),
  nextId = { value: 0 },
) {
  if (value === null) return "null";
  if (value === undefined) return "undefined";
  if (typeof value === "string") return `string:${JSON.stringify(value)}`;
  if (typeof value === "boolean") return `boolean:${value}`;
  if (typeof value === "number") {
    if (Number.isNaN(value)) return "number:NaN";
    if (Object.is(value, -0)) return "number:-0";
    return `number:${value}`;
  }
  if (typeof value === "bigint") return `bigint:${value.toString()}`;
  if (typeof value === "symbol" || typeof value === "function") {
    return { error: `${path} contained a non-data value` };
  }
  if (nodeTypes.isProxy(value)) return { error: `${path} was a proxy` };
  if (seen.has(value)) return `cycle:${seen.get(value)}`;

  let prototype;
  try {
    prototype = Object.getPrototypeOf(value);
  } catch {
    return { error: `${path} prototype inspection failed` };
  }
  const array = Array.isArray(value);
  if (array && prototype !== Array.prototype) return { error: `${path} was not an ordinary array` };
  if (!array && prototype !== Object.prototype && prototype !== null) {
    return { error: `${path} was not an ordinary object` };
  }

  let keys;
  try {
    keys = Reflect.ownKeys(value);
  } catch {
    return { error: `${path} own-key inspection failed` };
  }
  seen.set(value, nextId.value++);
  const parts = [array ? "array" : prototype === null ? "null-object" : "object"];
  for (const key of keys.sort((left, right) => String(left).localeCompare(String(right)))) {
    if (typeof key === "symbol") return { error: `${path} contained an own symbol` };
    let descriptor;
    try {
      descriptor = Object.getOwnPropertyDescriptor(value, key);
    } catch {
      return { error: `${path}.${key} descriptor inspection failed` };
    }
    if (!descriptor || !Object.hasOwn(descriptor, "value"))
      return { error: `${path}.${key} was an accessor` };
    if (array && key !== "length" && (!arrayIndexKey(key) || Number(key) >= value.length)) {
      return { error: `${path} contained an extra own key ${key}` };
    }
    const nested = observationFingerprint(descriptor.value, `${path}.${key}`, seen, nextId);
    if (typeof nested !== "string") return nested;
    parts.push(
      `${key}[${descriptor.enumerable ? "e" : "n"}${descriptor.configurable ? "c" : "s"}${descriptor.writable ? "w" : "r"}]=${nested}`,
    );
  }
  seen.delete(value);
  return parts.join("|");
}

function checkObservationIntegrity(value, expectedDigest, label) {
  const digest = observationFingerprint(value, label);
  if (typeof digest !== "string") return digest.error;
  return digest === expectedDigest ? undefined : `${label} values changed`;
}

function safeDataProperty(value, key, label) {
  if (value === null || (typeof value !== "object" && typeof value !== "function")) {
    throw new TypeError(`${label} was not an object`);
  }
  if (nodeTypes.isProxy(value)) throw new TypeError(`${label} was a proxy`);

  const visited = new Set();
  let current = value;
  while (current !== null) {
    if (nodeTypes.isProxy(current)) throw new TypeError(`${label} prototype was a proxy`);
    if (visited.has(current)) throw new TypeError(`${label} prototype chain was cyclic`);
    visited.add(current);
    const descriptor = Object.getOwnPropertyDescriptor(current, key);
    if (descriptor) {
      if (!Object.hasOwn(descriptor, "value"))
        throw new TypeError(`${label} ${key} was an accessor`);
      return descriptor.value;
    }
    current = Object.getPrototypeOf(current);
  }
  throw new TypeError(`${label} did not expose ${key}`);
}

function safeCallableProperty(value, key, label) {
  const member = safeDataProperty(value, key, label);
  if (typeof member !== "function" || nodeTypes.isProxy(member)) {
    throw new TypeError(`${label} ${key} was not a safe callable`);
  }
  return member;
}

function safeOptionalDataProperty(value, key, label) {
  try {
    return safeDataProperty(value, key, label);
  } catch (error) {
    if (error instanceof TypeError && error.message === `${label} did not expose ${key}`)
      return undefined;
    throw error;
  }
}

function safeOptionalCallableProperty(value, key, label) {
  try {
    return safeCallableProperty(value, key, label);
  } catch (error) {
    if (error instanceof TypeError && error.message === `${label} did not expose ${key}`)
      return undefined;
    throw error;
  }
}

export function withTimeout(promise, milliseconds, label, onTimeout) {
  try {
    validateRaceValue(promise, label || "operation");
  } catch (error) {
    return rejectedPromise(error);
  }
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
  { signal, milliseconds, label, onTimeout, onCancel } = {},
) {
  try {
    validateRaceValue(operation, label || "operation");
  } catch (error) {
    return rejectedPromise(error);
  }

  if (signal?.aborted) {
    const error = abortError(signal);
    onCancel?.(error);
    return rejectedPromise(error);
  }

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

    const onAbort = () => {
      const error = abortError(signal);
      onCancel?.(error);
      finish(rejectRace, error);
    };

    const settleSuccess = (value) => {
      try {
        validateRaceValue(value, label || "operation");
      } catch (error) {
        finish(rejectRace, error);
        return;
      }
      finish(resolveRace, value);
    };

    signal?.addEventListener("abort", onAbort, { once: true });
    if (milliseconds) {
      timer = setTimeout(() => {
        const error = new Error(`${label || "operation"} timed out after ${milliseconds}ms`);
        onTimeout?.(error);
        onCancel?.(error);
        finish(rejectRace, error);
      }, milliseconds);
    }

    if (allowedNativePromise(operation)) {
      const observedPromise = Promise.prototype.then.call(operation, settleSuccess, (error) =>
        finish(rejectRace, error),
      );
      Promise.prototype.then.call(observedPromise, undefined, () => {});
    } else {
      queueMicrotask(() => settleSuccess(operation));
    }
  });
}

export function redactText(value, secrets = []) {
  let text;
  if (value === null || value === undefined) text = "";
  else if (typeof value === "string") text = value;
  else if (["boolean", "number", "bigint"].includes(typeof value)) text = String(value);
  else text = "[unformattable value]";

  const secretEntries = Array.isArray(secrets)
    ? safeOrdinaryArrayEntries(secrets).entries || []
    : [];
  for (const secret of secretEntries) {
    if (typeof secret === "string" && secret.length > 0) {
      text = text.split(secret).join("[REDACTED]");
    }
  }
  return text;
}

export function redactError(error, secrets = []) {
  let candidate;
  for (const key of ["stack", "message"]) {
    try {
      candidate = safeDataProperty(error, key, "error");
    } catch {
      candidate = undefined;
    }
    if (typeof candidate === "string" && candidate.length > 0) break;
  }
  return redactText(candidate === undefined ? error : candidate, secrets);
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
    args.some(
      (argument) =>
        argument === forbiddenArgument ||
        (typeof argument === "string" && argument.startsWith(`${forbiddenArgument}=`)),
    ),
    false,
    "the browser gate must receive credentials over structured stdin, not argv",
  );
}

export async function removeUserDataDir(
  userDataDir,
  { timeout = PROFILE_CLEANUP_TIMEOUT_MS } = {},
) {
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

  return new Promise((resolveExit, rejectExit) => {
    let settled = false;
    let timer;
    const cleanup = () => {
      child.removeListener("exit", done);
      child.removeListener("error", done);
      clearTimeout(timer);
    };
    const finish = (callback, value) => {
      if (settled) return;
      settled = true;
      cleanup();
      callback(value);
    };
    const done = () => finish(resolveExit);

    child.once("exit", done);
    child.once("error", done);
    timer = setTimeout(
      () => finish(rejectExit, new Error(`${label} timed out after ${timeout}ms`)),
      timeout,
    );
    if (childHasExited(child, spawnErrorRef.value)) done();
  });
}

export async function terminateProcess(
  child,
  {
    gracefulTimeout = CHROME_GRACEFUL_SHUTDOWN_TIMEOUT_MS,
    forceTimeout = CHROME_FORCE_SHUTDOWN_TIMEOUT_MS,
    spawnErrorRef = { value: null },
    diagnostics,
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
      const detail = typeof diagnostics === "function" ? diagnostics() : diagnostics;
      throw new Error(
        `Chrome did not exit after graceful and forced shutdown: ${forceError.message}${detail ? `\n${detail}` : ""}`,
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
  gracefulShutdownTimeout = CHROME_GRACEFUL_SHUTDOWN_TIMEOUT_MS,
  forceShutdownTimeout = CHROME_FORCE_SHUTDOWN_TIMEOUT_MS,
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
  let onSpawnError;
  let onStdoutData;
  let onStderrData;
  let childListenersCleaned = false;

  const cleanupChildListeners = () => {
    if (childListenersCleaned) return;
    childListenersCleaned = true;
    child?.stdout?.removeListener("data", onStdoutData);
    child?.stderr?.removeListener("data", onStderrData);
    child?.removeListener("error", onSpawnError);
  };

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
            await terminateProcess(runtime.child, {
              gracefulTimeout: gracefulShutdownTimeout,
              forceTimeout: forceShutdownTimeout,
              spawnErrorRef,
              diagnostics: () => output.value(),
            });
            terminated = true;
          } else {
            terminated = true;
          }
        } finally {
          // Never remove the profile until the process has been observed exited.
          cleanupChildListeners();
          if (terminated) {
            await removeUserDataDir(userDataDir);
          }
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
    onStdoutData = (chunk) => output.append(chunk);
    onStderrData = (chunk) => output.append(chunk);
    child.stdout?.on("data", onStdoutData);
    child.stderr?.on("data", onStderrData);
    onSpawnError = (error) => {
      spawnErrorRef.value = error;
    };
    child.once("error", onSpawnError);

    let cancelEndpointWait = () => {};
    const endpoint = await raceWithSignalAndTimeout(
      new Promise((resolveEndpoint, rejectEndpoint) => {
        let settled = false;
        let cleanup;
        const finish = (callback, value) => {
          if (settled) return;
          settled = true;
          cleanup();
          callback(value);
        };
        const inspect = () => {
          const match = output.value().match(/DevTools listening on (wss?:\/\/[^\s]+)/);
          if (match) finish(resolveEndpoint, match[1]);
        };
        const onData = () => inspect();
        const onError = (error) => {
          finish(rejectEndpoint, new Error(`Chrome failed to start: ${error.message}`));
        };
        const onExit = (code, signalName) => {
          finish(
            rejectEndpoint,
            new Error(
              `Chrome exited before CDP startup (${code ?? signalName})\n${output.value()}`,
            ),
          );
        };
        cleanup = () => {
          child.stdout?.removeListener("data", onData);
          child.stderr?.removeListener("data", onData);
          child.removeListener("error", onError);
          child.removeListener("exit", onExit);
        };
        cancelEndpointWait = (error) => finish(rejectEndpoint, error);
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
        onCancel: cancelEndpointWait,
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
  assert.ok(
    ["ws:", "wss:"].includes(url.protocol),
    `invalid DevTools endpoint scheme ${url.protocol}`,
  );
  return `${url.protocol === "wss:" ? "https" : "http"}://${url.host}`;
}

export function browserUrls({
  port,
  missionId,
  spacecraftId,
  host = "127.0.0.1",
  scheme = "http",
}) {
  assert.ok(
    Number.isInteger(port) && port > 0 && port < 65_536,
    "browser endpoint port must be valid",
  );
  assert.ok(["http", "https"].includes(scheme), "browser endpoint scheme must be HTTP(S)");
  const baseUrl = `${scheme}://${host}:${port}`;
  return {
    baseUrl,
    loginUrl: `${baseUrl}/sign-in`,
    commsUrl: `${baseUrl}/missions/${encodeURIComponent(missionId)}/applications/comms/federated`,
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

export async function createPage(
  endpoint,
  url,
  { fetcher = fetch, timeout = CDP_COMMAND_TIMEOUT_MS, signal } = {},
) {
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
    assert.match(
      target.webSocketDebuggerUrl,
      /^wss?:\/\//,
      "CDP page target did not expose a WebSocket URL",
    );
    return { id: target.id, webSocketDebuggerUrl: target.webSocketDebuggerUrl };
  } finally {
    signal?.removeEventListener("abort", abort);
  }
}

export async function closePage(
  endpoint,
  targetId,
  { fetcher = fetch, timeout = CDP_COMMAND_TIMEOUT_MS } = {},
) {
  if (!endpoint || !targetId) return;
  const controller = new AbortController();
  try {
    const response = await raceWithSignalAndTimeout(
      fetcher(`${httpBaseFromWebSocket(endpoint)}/json/close/${encodeURIComponent(targetId)}`, {
        method: "GET",
        redirect: "manual",
        signal: controller.signal,
      }),
      {
        milliseconds: timeout,
        label: "CDP page close",
        onTimeout: (error) => controller.abort(error),
      },
    );
    assert.ok(
      [200, 404].includes(response.status),
      `CDP page close failed with HTTP ${response.status}`,
    );
  } finally {
    controller.abort(new Error("CDP page close finished"));
  }
}

export class CdpClient {
  constructor(endpoint, { webSocketImpl = WebSocket } = {}) {
    this.socket = new webSocketImpl(endpoint);
    this.nextCommandId = 0;
    this.pending = new Map();
    this.listeners = new Map();
    this.eventWaiters = new Set();
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
        const raw =
          typeof event.data === "string" ? event.data : Buffer.from(event.data).toString();
        message = JSON.parse(raw);
      } catch (error) {
        this.rejectPending(new Error(`invalid CDP message: ${error.message}`));
        return;
      }

      if (message.id !== undefined) {
        const callback = this.pending.get(message.id);
        if (!callback) return;
        this.pending.delete(message.id);
        if (message.error)
          callback.reject(new Error(`${message.error.message} (CDP ${message.id})`));
        else callback.resolve(message.result);
        return;
      }

      const listeners = this.listeners.get(message.method) || new Set();
      for (const listener of listeners) listener(message.params || {});
    });
    this.socket.addEventListener("close", () => {
      const error = new Error("CDP WebSocket closed");
      this.rejectPending(error);
      this.rejectEventWaiters(error);
    });
  }

  rejectPending(error) {
    for (const callback of this.pending.values()) callback.reject(error);
    this.pending.clear();
  }

  rejectEventWaiters(error) {
    for (const waiter of [...this.eventWaiters]) waiter.reject(error);
  }

  async send(method, params = {}, timeout = CDP_COMMAND_TIMEOUT_MS, signal) {
    assert.equal(this.closed, false, "CDP client is closed");
    await raceWithSignalAndTimeout(this.ready, {
      signal,
      milliseconds: timeout,
      label: `CDP connection during ${method}`,
    });
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

    return raceWithSignalAndTimeout(result, {
      signal,
      milliseconds: timeout,
      label: `CDP ${method} during ${currentProgressStage}`,
    }).finally(() => this.pending.delete(id));
  }

  on(method, listener) {
    const listeners = this.listeners.get(method) || new Set();
    listeners.add(listener);
    this.listeners.set(method, listeners);
    return () => listeners.delete(listener);
  }

  once(method, timeout = CDP_EVENT_TIMEOUT_MS, signal) {
    return this.waitForEvent(method, () => true, timeout, signal);
  }

  waitForEvent(method, predicate = () => true, timeout = CDP_EVENT_TIMEOUT_MS, signal) {
    if (signal?.aborted) return Promise.reject(abortError(signal));

    const eventPromise = new Promise((resolveEvent, rejectEvent) => {
      let timer;
      let settled = false;
      let off;
      let onAbort;
      const waiter = {
        reject: (error) => finish(rejectEvent, error),
      };
      const finish = (callback, value) => {
        if (settled) return;
        settled = true;
        this.eventWaiters.delete(waiter);
        off?.();
        clearTimeout(timer);
        signal?.removeEventListener("abort", onAbort);
        callback(value);
      };
      off = this.on(method, (params) => {
        try {
          if (!predicate(params)) return;
          finish(resolveEvent, params);
        } catch (error) {
          finish(rejectEvent, error);
        }
      });
      this.eventWaiters.add(waiter);
      onAbort = () => finish(rejectEvent, abortError(signal));
      signal?.addEventListener("abort", onAbort, { once: true });
      timer = setTimeout(() => {
        finish(
          rejectEvent,
          new Error(`CDP ${method} during ${currentProgressStage} timed out after ${timeout}ms`),
        );
      }, timeout);
    });
    eventPromise.catch(() => {});
    return eventPromise;
  }

  close() {
    if (this.closed) return;
    this.closed = true;
    this.rejectPending(new Error("CDP client closed"));
    this.rejectEventWaiters(new Error("CDP client closed"));
    try {
      this.socket.close();
    } catch {
      // The socket may already have been closed by Chrome during teardown.
    }
  }
}

export function exceptionMessage(exception) {
  const read = (value, key) => {
    try {
      return safeDataProperty(value, key, "runtime exception");
    } catch {
      return undefined;
    }
  };
  const details = read(exception, "exceptionDetails") || exception;
  const nested = read(details, "exception");
  for (const candidate of [
    read(nested, "description"),
    read(details, "text"),
    read(nested, "value"),
  ]) {
    if (typeof candidate === "string" && candidate.length > 0) return candidate;
  }
  return "runtime exception details unavailable";
}

export function isDataUrl(url) {
  return typeof url === "string" && url.startsWith("data:");
}

export function assertHttpUrl(url, expectedOrigin, label = "URL") {
  assert.equal(typeof url, "string", `${label} must be a string`);
  const parsed = new URL(url);
  assert.ok(
    ["http:", "https:"].includes(parsed.protocol),
    `${label} must use HTTP(S), got ${parsed.protocol}`,
  );
  if (expectedOrigin)
    assert.equal(parsed.origin, expectedOrigin, `${label} escaped the expected origin`);
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
    ["Image", "Other"].includes(record.resourceType)
  );
}

function matchesRequestGeneration(record, generation) {
  if (generation === undefined || generation === null) return true;
  const expectedGeneration = typeof generation === "object" ? generation.id : generation;
  if (record?.generation !== expectedGeneration) return false;
  if (typeof generation !== "object") return true;
  if (generation.requestIds?.has(record.requestId)) return false;
  return !(
    Number.isFinite(record.sequence) &&
    Number.isFinite(generation.requestSequence) &&
    record.sequence <= generation.requestSequence
  );
}

export function installDiagnostics(client, { expectedOrigin, secrets = [] } = {}) {
  const records = new Map();
  const exposedRequests = new Map();
  const requestStateBindings = new WeakMap();
  const consoleErrors = [];
  const confirmedRemoteFailureDiagnostics = new Set();
  const logErrors = [];
  const runtimeExceptions = [];
  const requestFailures = [];
  const webSockets = new Map();
  const webSocketFailures = [];
  const servedFromCacheRequestIds = new Set();
  const exposedConsoleErrors = [];
  const exposedLogErrors = [];
  const exposedRuntimeExceptions = [];
  const exposedRequestFailures = [];
  const exposedWebSockets = new Map();
  const exposedWebSocketFailures = [];
  const exposedServedFromCacheRequestIds = new Set();
  const expectedFailureRegistrations = [];
  const subscriptions = [];
  let sequence = 0;
  let nextGeneration = 0;
  let activeGeneration;
  let disposed = false;
  let disposePromise;
  const generations = new Map();
  const generationBindings = new WeakMap();
  const expectedFailureCleanups = new WeakMap();
  const expectedFailureRecordBindings = new WeakMap();
  const expectedFailureCanonicalBindings = new WeakMap();
  const canonicalEntryBindings = new WeakMap();
  const canonicalEntryDigests = new WeakMap();
  const observationDigests = new WeakMap();

  const appendDiagnostic = (privateValues, exposedValues, value) => {
    Array.prototype.push.call(privateValues, value);
    Array.prototype.push.call(exposedValues, value);
  };

  const refreshObservationDigest = (record) => {
    const digest = observationFingerprint(record.view, "request observation");
    record.viewDigest = typeof digest === "string" ? digest : undefined;
    if (record.viewDigest) observationDigests.set(record.view, record.viewDigest);
  };

  const immutableCopy = (value, label, fallback) => {
    try {
      return copyDiagnosticValue(value, { freeze: true }, label);
    } catch {
      return fallback;
    }
  };

  const writeObservation = (target, key, value) => {
    try {
      const descriptor = Object.getOwnPropertyDescriptor(target, key);
      if (descriptor && (!Object.hasOwn(descriptor, "value") || !descriptor.writable)) return;
      Object.defineProperty(target, key, {
        value,
        enumerable: descriptor?.enumerable ?? true,
        configurable: descriptor?.configurable ?? true,
        writable: true,
      });
    } catch {
      // Exposed observations are untrusted and never affect private state.
    }
  };
  const snapshotCanonicalEntry = (entry) => {
    const snapshot = {
      source: entry.source,
      level: entry.level,
      networkRequestId: entry.networkRequestId,
      url: entry.url,
      text: entry.text,
    };
    canonicalEntryBindings.set(snapshot, entry);
    const digest = observationFingerprint(snapshot, "canonical evidence");
    if (typeof digest === "string") canonicalEntryDigests.set(snapshot, digest);
    return snapshot;
  };
  const snapshotAllowanceView = (allowance, recordView) => ({
    requestId: allowance.requestId,
    url: allowance.url,
    method: allowance.method,
    generation: allowance.generation,
    status: allowance.status,
    consumed: allowance.consumed,
    consumedEntries: allowance.consumedEntries.map(snapshotCanonicalEntry),
    suppressedFailures: [...allowance.suppressedFailures],
    revoked: allowance.revoked,
    finalized: allowance.finalized,
    replayed: allowance.replayed,
    record: recordView,
  });
  const syncAllowanceView = (allowance) => {
    if (allowance.record?.viewDigest) {
      const drift = checkObservationIntegrity(
        allowance.record.view,
        allowance.record.viewDigest,
        "request observation",
      );
      if (drift) allowance.record.observationTampered ||= drift;
    }
    const view = allowance.view;
    writeObservation(view, "requestId", allowance.requestId);
    writeObservation(view, "url", allowance.url);
    writeObservation(view, "method", allowance.method);
    writeObservation(view, "generation", allowance.generation);
    writeObservation(view, "status", allowance.status);
    writeObservation(view, "consumed", allowance.consumed);
    const consumedEntries = allowance.consumedEntries.map(snapshotCanonicalEntry);
    allowance.consumedEntriesView = consumedEntries;
    writeObservation(view, "consumedEntries", consumedEntries);
    allowance.suppressedFailuresView = [...allowance.suppressedFailures];
    writeObservation(view, "suppressedFailures", allowance.suppressedFailuresView);
    writeObservation(view, "revoked", allowance.revoked);
    writeObservation(view, "finalized", allowance.finalized);
    writeObservation(view, "replayed", allowance.replayed);
    writeObservation(view, "record", allowance.record.view);
    if (allowance.record?.view) refreshObservationDigest(allowance.record);
  };
  const writeRecordView = (record, view) => {
    writeObservation(view, "requestId", record.requestId);
    writeObservation(view, "sequence", record.sequence);
    writeObservation(view, "startedAtMs", record.startedAtMs);
    writeObservation(view, "generation", record.generation);
    writeObservation(view, "method", record.method);
    writeObservation(view, "url", record.url);
    writeObservation(view, "request", copyDiagnosticValue(record.request));
    writeObservation(view, "postData", record.postData);
    writeObservation(view, "frameId", record.frameId);
    writeObservation(view, "loaderId", record.loaderId);
    writeObservation(
      view,
      "response",
      record.response === undefined ? undefined : copyDiagnosticValue(record.response),
    );
    writeObservation(
      view,
      "responseExtra",
      record.responseExtra === undefined ? undefined : copyDiagnosticValue(record.responseExtra),
    );
    writeObservation(
      view,
      "requestExtra",
      record.requestExtra === undefined ? undefined : copyDiagnosticValue(record.requestExtra),
    );
    const statusEvidenceView = copyDiagnosticValue(record.statusEvidence);
    if (view === record.view) record.statusEvidenceView = statusEvidenceView;
    writeObservation(view, "statusEvidence", statusEvidenceView);
    writeObservation(view, "statusDisagreement", record.statusDisagreement);
    writeObservation(view, "statusDisagreementReported", record.statusDisagreementReported);
    writeObservation(view, "servedFromCache", record.servedFromCache);
    writeObservation(view, "resourceType", record.resourceType);
    writeObservation(view, "redirects", copyDiagnosticValue(record.redirects));
    writeObservation(view, "webSocket", record.webSocket);
    writeObservation(view, "finished", record.finished);
    writeObservation(view, "failed", record.failed);
    writeObservation(view, "dataUrl", record.dataUrl);
    const pendingExpectedFailureLogView = record.pendingExpectedFailureLog
      ? {
          entry: snapshotCanonicalEntry(record.pendingExpectedFailureLog.entry),
          status: record.pendingExpectedFailureLog.status,
        }
      : undefined;
    if (view === record.view) record.pendingExpectedFailureLogView = pendingExpectedFailureLogView;
    writeObservation(view, "pendingExpectedFailureLog", pendingExpectedFailureLogView);
    const allowanceView = record.expectedFailureAllowance
      ? view === record.view
        ? record.expectedFailureAllowance.view
        : snapshotAllowanceView(record.expectedFailureAllowance, view)
      : undefined;
    writeObservation(
      view,
      "expectedFailureRegistration",
      record.expectedFailureRegistration
        ? view === record.view
          ? record.expectedFailureRegistration.view
          : {}
        : undefined,
    );
    writeObservation(view, "expectedFailureAllowance", allowanceView);
    writeObservation(
      view,
      "finalizedExpectedFailure",
      record.finalizedExpectedFailure
        ? view === record.view
          ? record.finalizedExpectedFailure.view
          : snapshotAllowanceView(record.finalizedExpectedFailure, view)
        : undefined,
    );
  };
  const syncRecordView = (record) => {
    if (record.viewDigest) {
      const drift = checkObservationIntegrity(
        record.view,
        record.viewDigest,
        "request observation",
      );
      if (drift) record.observationTampered ||= drift;
    }
    writeRecordView(record, record.view);
    refreshObservationDigest(record);
  };
  const snapshotRecord = (record) => {
    const view = {};
    writeRecordView(record, view);
    requestStateBindings.set(view, record);
    const digest = observationFingerprint(view, "request observation");
    if (typeof digest === "string") observationDigests.set(view, digest);
    return view;
  };
  const publishRecord = (record) => {
    if (!record.view) {
      record.view = {};
    }
    requestStateBindings.set(record.view, record);
    syncRecordView(record);
    if (!Map.prototype.has.call(exposedRequests, record.requestId)) {
      Map.prototype.set.call(exposedRequests, record.requestId, record.view);
    }
  };
  const socketSnapshot = (socket) => ({
    requestId: socket.requestId,
    url: socket.url,
    generation: socket.generation,
    sequence: socket.sequence,
    boundToRequest: socket.boundToRequest,
    boundByHandshake: socket.boundByHandshake,
    observedGeneration: socket.observedGeneration,
    observedSequence: socket.observedSequence,
    causalRequestId: socket.causalRequestId,
    handshakeRequest:
      socket.handshakeRequest === undefined
        ? undefined
        : copyDiagnosticValue(socket.handshakeRequest),
    handshake: socket.handshake === undefined ? undefined : copyDiagnosticValue(socket.handshake),
    closed: socket.closed,
    error: socket.error,
  });
  const publishSocket = (socket) => {
    Map.prototype.set.call(exposedWebSockets, socket.requestId, socketSnapshot(socket));
  };
  const stateForExposedRecord = (record) => requestStateBindings.get(record);
  const on = (method, listener) => subscriptions.push(client.on(method, listener));
  const logError = (entry) => {
    const text = typeof entry?.text === "string" && entry.text ? entry.text : "browser log error";
    const url = typeof entry?.url === "string" && entry.url ? entry.url : undefined;
    appendDiagnostic(logErrors, exposedLogErrors, `${text}${url ? ` (${url})` : ""}`);
  };
  const observedResponseStatus = (record) => {
    const statuses = [record?.responseStatus, record?.responseExtraStatus].filter((status) =>
      Number.isInteger(status),
    );
    if (!statuses.length || new Set(statuses).size !== 1) return undefined;
    return statuses[0];
  };
  const reportStatusDisagreement = (record) => {
    if (!record.statusDisagreement || record.statusDisagreementReported || record.method === "?")
      return;
    record.statusDisagreementReported = true;
    appendDiagnostic(
      requestFailures,
      exposedRequestFailures,
      `${record.method} ${record.url || record.requestId}: ${record.statusDisagreement}`,
    );
  };
  const replayInvalidatedAllowance = (allowance) => {
    if (allowance.replayed) return;
    allowance.replayed = true;
    const canonicalEvidence = expectedFailureCanonicalBindings.get(allowance);
    if (canonicalEvidence) logError(canonicalEvidence);
    for (const failure of allowance.suppressedFailures || []) {
      appendDiagnostic(requestFailures, exposedRequestFailures, failure);
    }
  };
  const detachExpectedFailureRegistration = (registration, reason, { finalized = false } = {}) => {
    if (!registration || registration.invalidated || registration.finalized) return;
    registration.invalidated = !finalized;
    registration.finalized = finalized;
    registration.active = false;
    registration.invalidatedBy = reason;
    delete registration.pendingRequestId;
    for (const record of records.values()) {
      if (record.expectedFailureRegistration === registration)
        delete record.expectedFailureRegistration;
    }
    const index = expectedFailureRegistrations.indexOf(registration);
    if (index >= 0) expectedFailureRegistrations.splice(index, 1);
    reconcilePendingNetworkLogs();
  };
  const invalidateExpectedFailure = (target, reason, boundAllowance) => {
    const allowance = boundAllowance || target?.expectedFailureAllowance;
    if (allowance) {
      if (allowance.revoked || allowance.finalized) return;
      allowance.revoked = true;
      allowance.invalidatedBy = reason;
      replayInvalidatedAllowance(allowance);
      return;
    }

    const registration = target;
    if (!registration || registration.invalidated || registration.finalized) return;
    for (const registrationAllowance of registration.allowances || []) {
      invalidateExpectedFailure(registration, reason, registrationAllowance);
    }
    detachExpectedFailureRegistration(registration, reason);
  };
  const revokeUnconfirmedExpectedFailures = (reason) => {
    for (const registration of [...expectedFailureRegistrations]) {
      invalidateExpectedFailure(registration, reason);
    }
  };
  const observeStatusEvidence = (record, source, status) => {
    if (!Number.isInteger(status)) return;
    record.statusEvidence = Object.freeze([
      ...(record.statusEvidence || []),
      Object.freeze({ source, status }),
    ]);
    syncRecordView(record);
    const finalizedAllowance = record.finalizedExpectedFailure;
    if (
      finalizedAllowance?.record === record &&
      finalizedAllowance.finalized &&
      finalizedAllowance.status !== status
    ) {
      if (!record.statusDisagreement) {
        record.statusDisagreement = `finalized expected failure status disagreed: expected=${finalizedAllowance.status}, ${source}=${status}`;
      }
      reportStatusDisagreement(record);
      return;
    }
    const allowance = record.expectedFailureAllowance;
    if (!allowance || allowance.revoked) return;
    const hasCrossSourceDisagreement = record.statusEvidence.some(
      (evidence) => evidence.source !== source && evidence.status !== status,
    );
    const hasExpectedStatusDrift = Boolean(
      allowance &&
      !allowance.revoked &&
      allowance.status !== status &&
      record.statusEvidence.some(
        (evidence) => evidence.source === source && evidence.status !== status,
      ),
    );
    if (!hasCrossSourceDisagreement && !hasExpectedStatusDrift) return;
    if (!record.statusDisagreement) {
      record.statusDisagreement = `status evidence disagreed: ${record.statusEvidence
        .map((evidence) => `${evidence.source}=${evidence.status}`)
        .join(", ")}`;
      if (allowance && !allowance.revoked)
        invalidateExpectedFailure(record, record.statusDisagreement);
    }
    reportStatusDisagreement(record);
  };
  const matchesExpectedFailureRegistration = (record, registration) => {
    if (
      !record ||
      !registration?.active ||
      record.method === "?" ||
      typeof record.url !== "string" ||
      record.sequence <= registration.registeredAfterSequence ||
      (registration.requestId && registration.requestId !== record.requestId) ||
      (registration.pendingRequestId && registration.pendingRequestId !== record.requestId)
    )
      return false;
    try {
      return registration.predicate(snapshotRecord(record));
    } catch {
      return false;
    }
  };
  const reserveExpectedFailureRegistration = (record) => {
    const existing = record?.expectedFailureRegistration;
    if (matchesExpectedFailureRegistration(record, existing)) return existing;
    const registration = expectedFailureRegistrations.find((candidate) =>
      matchesExpectedFailureRegistration(record, candidate),
    );
    if (!registration) return undefined;
    registration.pendingRequestId = record.requestId;
    record.expectedFailureRegistration = registration;
    return registration;
  };
  const expectedFailureRegistrationFor = (record) => {
    const status = observedResponseStatus(record);
    if (!Number.isInteger(status)) return undefined;
    const reserved = record?.expectedFailureRegistration;
    if (
      reserved &&
      reserved.expectedStatus === status &&
      matchesExpectedFailureRegistration(record, reserved) &&
      !record.expectedFailureAllowance?.revoked
    )
      return reserved;
    return expectedFailureRegistrations.find(
      (registration) =>
        registration.expectedStatus === status &&
        matchesExpectedFailureRegistration(record, registration) &&
        !record.expectedFailureAllowance?.revoked,
    );
  };
  const validExpectedFailureAllowance = (record) => {
    const allowance = record?.expectedFailureAllowance;
    if (!allowance || allowance.revoked || allowance.finalized || !allowance.registration.active)
      return undefined;
    const boundRecord = expectedFailureRecordBindings.get(allowance);
    if (boundRecord !== record || allowance.record !== record) {
      invalidateExpectedFailure(
        boundRecord || record,
        "expected failure record identity changed",
        allowance,
      );
      return undefined;
    }
    if (allowance.requestId !== record.requestId || allowance.url !== record.url) {
      invalidateExpectedFailure(record, "expected failure request identity changed");
      return undefined;
    }
    if (observedResponseStatus(record) !== allowance.status) {
      invalidateExpectedFailure(record, "expected failure status evidence changed");
      return undefined;
    }
    return allowance;
  };
  const markExpectedFailure = (record) => {
    const existing = record?.expectedFailureAllowance;
    if (existing) return Boolean(validExpectedFailureAllowance(record));
    const registration = expectedFailureRegistrationFor(record);
    if (!registration) return false;
    const status = observedResponseStatus(record);
    if (registration.expectedStatus !== status) return false;
    registration.requestId = record.requestId;
    delete registration.pendingRequestId;
    record.expectedFailureRegistration = registration;
    const allowance = {
      registration,
      record,
      requestId: record.requestId,
      url: record.url,
      method: record.method,
      generation: record.generation,
      status,
      consumed: false,
      consumedEntries: Object.freeze([]),
      suppressedFailures: Object.freeze([]),
      replayed: false,
      view: {},
    };
    expectedFailureRecordBindings.set(allowance, record);
    record.expectedFailureAllowance = allowance;
    syncAllowanceView(allowance);
    registration.allowances.add(allowance);
    syncRecordView(record);
    return true;
  };
  const canonicalNetworkResourceStatus = (entry) => {
    if (
      entry?.source !== "network" ||
      entry?.level !== "error" ||
      typeof entry?.url !== "string" ||
      typeof entry?.text !== "string"
    )
      return undefined;
    const match =
      /^Failed to load resource: the server responded with a status of ([1-5]\d{2}) \([^()\r\n]*\)$/.exec(
        entry.text,
      );
    return match ? Number(match[1]) : undefined;
  };
  const hasNonemptyNetworkRequestId = (entry) =>
    typeof entry?.networkRequestId === "string" && entry.networkRequestId.trim().length > 0;
  const expectedFailureConfirmationFailure = (registration, allowance, reason) => {
    if (allowance && !allowance.revoked && !allowance.finalized) {
      invalidateExpectedFailure(allowance.record, reason, allowance);
      detachExpectedFailureRegistration(registration, reason);
    } else if (registration && !registration.invalidated && !registration.finalized) {
      invalidateExpectedFailure(registration, reason);
    }
    throw new Error(`expected failure confirmation rejected: ${reason}`);
  };
  const canonicalEvidenceMatches = (entry, allowance) =>
    entry?.source === "network" &&
    entry?.level === "error" &&
    hasNonemptyNetworkRequestId(entry) &&
    entry.networkRequestId === allowance.requestId &&
    entry.url === allowance.url &&
    canonicalNetworkResourceStatus(entry) === allowance.status;
  const canonicalEvidenceIsSame = (left, right) => {
    if (left === right) return true;
    if (canonicalEntryBindings.get(left) !== right) return false;
    const digest = canonicalEntryDigests.get(left);
    return (
      typeof digest === "string" && !checkObservationIntegrity(left, digest, "canonical evidence")
    );
  };
  const finalizeExpectedFailure = (allowance) => {
    if (allowance.revoked || allowance.finalized) return false;
    allowance.finalized = true;
    expectedFailureRecordBindings.get(allowance).finalizedExpectedFailure = allowance;
    syncAllowanceView(allowance);
    syncRecordView(allowance.record);
    detachExpectedFailureRegistration(allowance.registration, "expected failure confirmed", {
      finalized: true,
    });
    // Keep the exact record/allowance binding through the bounded late-event
    // drain and final assertion. A finalized request must still attribute
    // contradictory response and ExtraInfo status evidence.
    return true;
  };
  const consumeExpectedFailureLog = (entry, status, registrations) => {
    if (!hasNonemptyNetworkRequestId(entry)) return false;
    const record = records.get(entry.networkRequestId);
    const allowance = validExpectedFailureAllowance(record);
    if (
      !allowance ||
      !allowance.registration.active ||
      (registrations && !registrations.has(allowance.registration)) ||
      allowance.consumed ||
      allowance.requestId !== record.requestId ||
      allowance.url !== entry.url ||
      record.url !== entry.url ||
      record.method === "?" ||
      allowance.status !== status ||
      observedResponseStatus(record) !== status
    )
      return false;
    allowance.consumed = true;
    expectedFailureCanonicalBindings.set(allowance, entry);
    allowance.consumedEntries = Object.freeze([...(allowance.consumedEntries || []), entry]);
    syncAllowanceView(allowance);
    return true;
  };
  const pendingExpectedFailureRegistrationFor = (record, status) => {
    if (
      !record ||
      record.expectedFailureAllowance?.revoked ||
      record.finished ||
      record.failed ||
      record.statusDisagreement ||
      record.method === "?" ||
      record.url === undefined
    )
      return undefined;
    const registration =
      record.expectedFailureRegistration || reserveExpectedFailureRegistration(record);
    if (
      !registration ||
      registration.expectedStatus !== status ||
      !matchesExpectedFailureRegistration(record, registration)
    )
      return undefined;
    const observedStatus = observedResponseStatus(record);
    if (Number.isInteger(observedStatus) && observedStatus !== status) return undefined;
    return registration;
  };
  const holdPendingExpectedFailureLog = (entry, status) => {
    if (!hasNonemptyNetworkRequestId(entry)) return false;
    const record = records.get(entry.networkRequestId);
    if (!record || record.pendingExpectedFailureLog) return false;
    const registration = pendingExpectedFailureRegistrationFor(record, status);
    if (!registration || record.url !== entry.url) return false;
    registration.pendingRequestId = record.requestId;
    record.pendingExpectedFailureLog = { entry, status, registration };
    syncRecordView(record);
    return true;
  };
  const reconcilePendingNetworkLogs = () => {
    for (const record of records.values()) {
      const pending = record.pendingExpectedFailureLog;
      if (!pending) continue;
      const registrations = new Set(
        expectedFailureRegistrations.filter((registration) => registration.active),
      );
      if (consumeExpectedFailureLog(pending.entry, pending.status, registrations)) {
        delete record.pendingExpectedFailureLog;
        syncRecordView(record);
        continue;
      }
      const observedStatus = observedResponseStatus(record);
      const canRemainPending =
        !disposed &&
        !record.finished &&
        !record.failed &&
        !record.statusDisagreement &&
        pending.registration.active &&
        registrations.has(pending.registration) &&
        pending.registration.expectedStatus === pending.status &&
        (!pending.registration.requestId || pending.registration.requestId === record.requestId) &&
        (!Number.isInteger(observedStatus) || observedStatus === pending.status) &&
        record.url === pending.entry.url &&
        matchesExpectedFailureRegistration(record, pending.registration);
      if (!canRemainPending) {
        logError(pending.entry);
        delete record.pendingExpectedFailureLog;
        syncRecordView(record);
      }
    }
  };
  const flushPendingNetworkLogs = () => {
    for (const record of records.values()) {
      const pending = record.pendingExpectedFailureLog;
      if (!pending) continue;
      logError(pending.entry);
      delete record.pendingExpectedFailureLog;
      syncRecordView(record);
    }
  };
  const generationStateFor = (generation) => {
    if (generation === undefined || generation === null) return undefined;
    return typeof generation === "object"
      ? generationBindings.get(generation)
      : generations.get(generation);
  };
  const matchesPrivateRequestGeneration = (record, generation) => {
    if (generation === undefined || generation === null) return true;
    const current = generationStateFor(generation);
    if (!current || record?.generation !== current.id) return false;
    if (typeof generation !== "object") return true;
    if (current.requestIds.has(record.requestId)) return false;
    return !(
      Number.isFinite(record.sequence) &&
      Number.isFinite(current.requestSequence) &&
      record.sequence <= current.requestSequence
    );
  };
  const beginRequestGeneration = (label = "request generation") => {
    const generation = {
      id: ++nextGeneration,
      label,
      requestSequence: sequence,
      requestIds: new Set(records.keys()),
      startedAtMs: Date.now(),
      causalRequestId: undefined,
      causalRequestSequence: undefined,
    };
    const generationState = {
      id: generation.id,
      label,
      requestSequence: generation.requestSequence,
      requestIds: new Set(generation.requestIds),
      startedAtMs: generation.startedAtMs,
      causalRequestId: undefined,
      causalRequestSequence: undefined,
      public: generation,
    };
    generations.set(generation.id, generationState);
    generationBindings.set(generation, generationState);
    activeGeneration = generation.id;
    return generation;
  };

  const bindRequestGeneration = (generation, request, { admitObservedSockets = false } = {}) => {
    const current = generationStateFor(generation);
    assert.ok(current, "request generation is not owned by these diagnostics");
    const requestState = stateForExposedRecord(request);
    const requestDigest = observationDigests.get(request);
    assert.equal(
      requestState?.observationTampered,
      undefined,
      "causal request observation was mutated",
    );
    assert.equal(
      requestDigest &&
        checkObservationIntegrity(request, requestDigest, "causal request observation"),
      undefined,
      "causal request observation was mutated",
    );
    assert.equal(
      requestState?.generation,
      current.id,
      "causal request belongs to another generation",
    );
    assert.ok(requestState?.requestId, "causal request has no request id");
    current.causalRequestId = requestState.requestId;
    current.causalRequestSequence = requestState.sequence;
    writeObservation(current.public, "causalRequestId", current.causalRequestId);
    writeObservation(current.public, "causalRequestSequence", current.causalRequestSequence);
    for (const socket of webSockets.values()) {
      const observedAfterBoundary =
        admitObservedSockets &&
        socket.generation === undefined &&
        socket.observedGeneration === current.id &&
        socket.observedSequence >= requestState.sequence;
      if (
        socket.generation === current.id &&
        (socket.boundToRequest === true || observedAfterBoundary)
      ) {
        socket.generation = current.id;
        socket.boundToRequest = true;
        socket.causalRequestId = requestState.requestId;
        publishSocket(socket);
      }
    }
    return current.public;
  };

  on(
    "Network.requestWillBeSent",
    ({ requestId, request, type, redirectResponse, frameId, loaderId }) => {
      const prior = records.get(requestId);
      const responseOnly = prior?.method === "?";
      const redirects = [
        ...(prior?.redirects || []),
        ...(redirectResponse
          ? [{ status: redirectResponse.status, url: redirectResponse.url }]
          : []),
      ];
      const record = {
        requestId,
        sequence: responseOnly ? prior.sequence : ++sequence,
        startedAtMs: responseOnly ? prior.startedAtMs : Date.now(),
        generation: prior?.generation ?? activeGeneration,
        method: request.method,
        url: request.url,
        request: immutableCopy(request, "Network.requestWillBeSent request", Object.freeze({})),
        postData: typeof request.postData === "string" ? request.postData : undefined,
        frameId: frameId || prior?.frameId,
        loaderId: loaderId || prior?.loaderId,
        response: responseOnly ? prior.response : undefined,
        responseStatus: responseOnly ? prior.responseStatus : undefined,
        responseExtra: prior?.responseExtra,
        responseExtraStatus: prior?.responseExtraStatus,
        requestExtra: prior?.requestExtra,
        statusEvidence: responseOnly
          ? prior?.statusEvidence || Object.freeze([])
          : Object.freeze([]),
        statusDisagreement: responseOnly ? prior?.statusDisagreement : undefined,
        servedFromCache: prior?.servedFromCache || servedFromCacheRequestIds.has(requestId),
        resourceType: type,
        redirects: Object.freeze(redirects.map((redirect) => Object.freeze({ ...redirect }))),
        webSocket: type === "WebSocket",
        finished: false,
        failed: undefined,
        dataUrl: isDataUrl(request.url),
        view: prior?.view,
      };
      records.set(requestId, record);
      publishRecord(record);
      reserveExpectedFailureRegistration(record);
      markExpectedFailure(record);
      reportStatusDisagreement(record);
      reconcilePendingNetworkLogs();
      const socket = webSockets.get(requestId);
      const sameObservedGeneration =
        socket?.observedGeneration !== undefined && socket.observedGeneration === record.generation;
      // Chrome may deliver webSocketCreated before requestWillBeSent. Bind that
      // ordering only when both observations are in the same generation; a
      // socket observed before the boundary is never upgraded by delayed events.
      if (socket?.boundToRequest === true || sameObservedGeneration) {
        socket.generation = record.generation;
        socket.sequence = record.sequence;
        socket.boundToRequest = true;
        socket.causalRequestId = generations.get(record.generation)?.causalRequestId;
        publishSocket(socket);
      }
    },
  );

  on("Network.responseReceived", ({ requestId, response, type, frameId, loaderId }) => {
    const requestRecord = records.get(requestId);
    const record = requestRecord || {
      requestId,
      sequence: ++sequence,
      startedAtMs: Date.now(),
      method: "?",
      url: response.url,
      request: Object.freeze({}),
      frameId,
      loaderId,
      redirects: Object.freeze([]),
      // A response without its request is not causally attributable to the
      // active generation.  A later requestWillBeSent event may bind it.
      generation: undefined,
      webSocket: type === "WebSocket",
      finished: false,
      failed: undefined,
      dataUrl: isDataUrl(response.url),
      statusEvidence: Object.freeze([]),
      responseStatus: undefined,
      responseExtraStatus: undefined,
      view: undefined,
    };
    record.response = immutableCopy(
      response,
      "Network.responseReceived response",
      Object.freeze({}),
    );
    record.responseStatus = response.status;
    record.frameId ||= frameId;
    record.loaderId ||= loaderId;
    record.resourceType = type || record.resourceType;
    if (type === "WebSocket") record.webSocket = true;
    publishRecord(record);
    observeStatusEvidence(record, "response", response.status);
    records.set(requestId, record);
    const expected = markExpectedFailure(record);
    if (
      response.status >= 400 &&
      !record.dataUrl &&
      !isIgnoredFavicon(record, expectedOrigin) &&
      !expected
    ) {
      appendDiagnostic(
        requestFailures,
        exposedRequestFailures,
        `${response.status} ${record.method} ${response.url} (host-session-header=${Boolean(requestHeader(record, "x-cadence-poc-session"))}, csrf-header=${Boolean(requestHeader(record, "x-csrf-token"))})`,
      );
    }
    reconcilePendingNetworkLogs();
  });

  on("Network.requestWillBeSentExtraInfo", ({ requestId, headers, associatedCookies }) => {
    const record = records.get(requestId);
    if (record) {
      record.requestExtra = immutableCopy(
        { headers, associatedCookies },
        "Network.requestWillBeSentExtraInfo",
        Object.freeze({}),
      );
      publishRecord(record);
      reconcilePendingNetworkLogs();
      return;
    }

    records.set(requestId, {
      requestId,
      sequence: ++sequence,
      startedAtMs: Date.now(),
      generation: undefined,
      method: "?",
      url: "",
      request: Object.freeze({}),
      requestExtra: immutableCopy(
        { headers, associatedCookies },
        "Network.requestWillBeSentExtraInfo",
        Object.freeze({}),
      ),
      statusEvidence: Object.freeze([]),
      redirects: Object.freeze([]),
      webSocket: false,
      finished: false,
      failed: undefined,
      dataUrl: false,
      responseStatus: undefined,
      responseExtraStatus: undefined,
      view: undefined,
    });
    publishRecord(records.get(requestId));
  });

  on("Network.responseReceivedExtraInfo", ({ requestId, statusCode, headers, blockedCookies }) => {
    const record = records.get(requestId);
    if (record) {
      record.responseExtra = immutableCopy(
        { statusCode, headers, blockedCookies },
        "Network.responseReceivedExtraInfo",
        Object.freeze({}),
      );
      record.responseExtraStatus = statusCode;
      publishRecord(record);
      observeStatusEvidence(record, "ExtraInfo", statusCode);
      markExpectedFailure(record);
      reconcilePendingNetworkLogs();
      return;
    }

    records.set(requestId, {
      requestId,
      sequence: ++sequence,
      startedAtMs: Date.now(),
      generation: undefined,
      method: "?",
      url: "",
      request: Object.freeze({}),
      responseExtra: immutableCopy(
        { statusCode, headers, blockedCookies },
        "Network.responseReceivedExtraInfo",
        Object.freeze({}),
      ),
      statusEvidence: Object.freeze([]),
      redirects: Object.freeze([]),
      webSocket: false,
      finished: false,
      failed: undefined,
      dataUrl: false,
      responseStatus: undefined,
      responseExtraStatus: statusCode,
      view: undefined,
    });
    publishRecord(records.get(requestId));
    observeStatusEvidence(records.get(requestId), "ExtraInfo", statusCode);
    markExpectedFailure(records.get(requestId));
    reconcilePendingNetworkLogs();
  });

  on("Network.requestServedFromCache", ({ requestId }) => {
    servedFromCacheRequestIds.add(requestId);
    Set.prototype.add.call(exposedServedFromCacheRequestIds, requestId);
    const record = records.get(requestId);
    if (record) {
      record.servedFromCache = true;
      publishRecord(record);
    }
  });

  on("Network.loadingFinished", ({ requestId }) => {
    const record = records.get(requestId);
    if (record) {
      record.finished = true;
      publishRecord(record);
      reconcilePendingNetworkLogs();
    }
  });

  on("Network.loadingFailed", ({ requestId, errorText, canceled, blockedReason }) => {
    const record = records.get(requestId);
    const detail = `${errorText || "request failed"}${canceled ? " (canceled)" : ""}${blockedReason ? ` (${blockedReason})` : ""}`;
    const expectedConditional304Cancellation =
      canceled === true &&
      errorText === "net::ERR_ABORTED" &&
      record?.finished === false &&
      record?.responseExtra?.statusCode === 304;
    const allowance = validExpectedFailureAllowance(record);
    const expected = Boolean(allowance);
    const failure = `${record?.method || "?"} ${record?.url || requestId}: ${detail}`;
    if (
      !expectedConditional304Cancellation &&
      !record?.dataUrl &&
      !isIgnoredFavicon(record, expectedOrigin) &&
      !expected
    ) {
      appendDiagnostic(requestFailures, exposedRequestFailures, failure);
    } else if (expected) {
      allowance.suppressedFailures = Object.freeze([
        ...(allowance.suppressedFailures || []),
        failure,
      ]);
      syncAllowanceView(allowance);
    }
    if (record) {
      record.failed = detail;
      publishRecord(record);
      reconcilePendingNetworkLogs();
    }
  });

  on("Network.webSocketCreated", ({ requestId, url }) => {
    const requestRecord = records.get(requestId);
    const boundRequest =
      requestRecord?.method && requestRecord.method !== "?" ? requestRecord : undefined;
    const observedGeneration = boundRequest?.generation ?? activeGeneration;
    const generation = generations.get(observedGeneration);
    webSockets.set(requestId, {
      requestId,
      url,
      generation: boundRequest?.generation,
      sequence: boundRequest?.sequence,
      boundToRequest: Boolean(boundRequest),
      observedGeneration,
      observedSequence: boundRequest?.sequence ?? sequence,
      causalRequestId: generation?.causalRequestId,
      handshake: undefined,
      error: undefined,
    });
    publishSocket(webSockets.get(requestId));
  });

  on("Network.webSocketWillSendHandshakeRequest", ({ requestId, request }) => {
    const requestRecord = records.get(requestId);
    const boundRequest =
      requestRecord?.method && requestRecord.method !== "?" ? requestRecord : undefined;
    const observedGeneration = boundRequest?.generation ?? activeGeneration;
    const generation = generations.get(observedGeneration);
    const socket = webSockets.get(requestId) || {
      requestId,
      url: request.url,
      generation: boundRequest?.generation,
      sequence: boundRequest?.sequence,
      boundToRequest: Boolean(boundRequest),
      observedGeneration,
      observedSequence: boundRequest?.sequence ?? sequence,
      causalRequestId: generation?.causalRequestId,
    };
    socket.handshakeRequest = immutableCopy(
      request,
      "Network.webSocketWillSendHandshakeRequest",
      Object.freeze({}),
    );
    if (
      socket.boundToRequest !== true &&
      socket.observedGeneration !== undefined &&
      socket.observedGeneration === activeGeneration &&
      generation?.causalRequestId !== undefined &&
      socket.observedSequence >= generation.causalRequestSequence
    ) {
      // Chrome may omit Network.requestWillBeSent for a websocket. The
      // handshake request is the causal network event, but only its original
      // generation may bind the socket; delayed pre-generation events stay
      // unbound.
      socket.generation = activeGeneration;
      socket.boundToRequest = true;
      socket.boundByHandshake = true;
      socket.causalRequestId = generation?.causalRequestId;
    }
    webSockets.set(requestId, socket);
    publishSocket(socket);
  });

  on("Network.webSocketHandshakeResponseReceived", ({ requestId, response }) => {
    const requestRecord = records.get(requestId);
    const boundRequest =
      requestRecord?.method && requestRecord.method !== "?" ? requestRecord : undefined;
    const observedGeneration = boundRequest?.generation ?? activeGeneration;
    const generation = generations.get(observedGeneration);
    const socket = webSockets.get(requestId) || {
      requestId,
      url: response.url,
      generation: boundRequest?.generation,
      sequence: boundRequest?.sequence,
      boundToRequest: Boolean(boundRequest),
      observedGeneration,
      observedSequence: boundRequest?.sequence ?? sequence,
      causalRequestId: generation?.causalRequestId,
    };
    socket.handshake = immutableCopy(
      response,
      "Network.webSocketHandshakeResponseReceived",
      Object.freeze({}),
    );
    webSockets.set(requestId, socket);
    publishSocket(socket);
  });

  on("Network.webSocketFrameError", ({ requestId, errorMessage }) => {
    const socket = webSockets.get(requestId);
    const detail = errorMessage || "websocket frame error";
    if (socket) socket.error = detail;
    appendDiagnostic(
      webSocketFailures,
      exposedWebSocketFailures,
      `${socket?.url || requestId}: ${detail}`,
    );
    if (socket) publishSocket(socket);
  });

  on("Network.webSocketClosed", ({ requestId }) => {
    const socket = webSockets.get(requestId);
    if (socket) socket.closed = true;
    if (socket) publishSocket(socket);
  });

  on("Runtime.consoleAPICalled", ({ type, args, stackTrace }) => {
    if (!["error", "assert"].includes(type)) return;
    const values = (args || []).map((arg) => arg.value ?? arg.description ?? arg.type).join(" ");
    appendDiagnostic(
      consoleErrors,
      exposedConsoleErrors,
      `${values}${stackTrace?.description ? `\n${stackTrace.description}` : ""}`,
    );
  });

  on("Log.entryAdded", ({ entry }) => {
    const diagnosticEntry = immutableCopy(entry, "Log.entryAdded entry", Object.freeze({}));
    if (["error", "assert"].includes(diagnosticEntry?.level)) {
      const matchingFavicon =
        diagnosticEntry.url &&
        [...records.values()].some(
          (record) =>
            record.url === diagnosticEntry.url && isIgnoredFavicon(record, expectedOrigin),
        );
      if (matchingFavicon) return;
      const status = canonicalNetworkResourceStatus(diagnosticEntry);
      if (status === undefined || diagnosticEntry.level !== "error") {
        logError(diagnosticEntry);
        return;
      }
      const registrations = new Set(
        expectedFailureRegistrations.filter((registration) => registration.active),
      );
      if (
        registrations.size &&
        (consumeExpectedFailureLog(diagnosticEntry, status, registrations) ||
          holdPendingExpectedFailureLog(diagnosticEntry, status))
      )
        return;
      logError(diagnosticEntry);
    }
  });

  on("Runtime.exceptionThrown", (exception) => {
    appendDiagnostic(runtimeExceptions, exposedRuntimeExceptions, exceptionMessage(exception));
  });

  const describeFailures = (stage) => {
    const failures = [
      ...requestFailures.map((value) => `request failure: ${value}`),
      ...logErrors.map((value) => `log.error: ${value}`),
      ...consoleErrors.flatMap((value, index) =>
        confirmedRemoteFailureDiagnostics.has(index) ? [] : [`console.error/assert: ${value}`],
      ),
      ...runtimeExceptions.map((value) => `runtime exception: ${value}`),
      ...[...records.values()]
        .filter(
          (record) =>
            record.method !== "?" &&
            !record.webSocket &&
            !record.finished &&
            !record.failed &&
            !record.dataUrl &&
            !isIgnoredFavicon(record, expectedOrigin),
        )
        .map(
          (record) =>
            `outstanding request: requestId=${record.requestId} sequence=${record.sequence} generation=${record.generation} method=${record.method} url=${record.url} responseStatus=${record.responseStatus} responseExtraStatus=${record.responseExtraStatus}`,
        ),
    ];
    return failures.length ? `${stage} browser diagnostics failed:\n${failures.join("\n")}` : null;
  };

  const requestForGeneration = (generation, predicate = () => true) => {
    const candidates = [...records.values()]
      .filter(
        (record) =>
          matchesPrivateRequestGeneration(record, generation) && predicate(snapshotRecord(record)),
      )
      .sort((left, right) => left.sequence - right.sequence);
    const match = candidates.at(-1);
    return match ? snapshotRecord(match) : undefined;
  };

  const assertPrivateLiveViewWebSocket = (
    expectedOriginValue,
    { beforeRequestIds = new Set(), generation } = {},
  ) => {
    const normalizedExpectedOrigin = new URL(expectedOriginValue);
    assert.ok(
      ["http:", "https:"].includes(normalizedExpectedOrigin.protocol),
      `LiveView expected origin must use HTTP(S), got ${normalizedExpectedOrigin.protocol}`,
    );
    const requiresCausalGeneration = generation && typeof generation === "object";
    const currentGeneration = generationStateFor(generation);
    const causalRequestId = requiresCausalGeneration
      ? currentGeneration?.causalRequestId
      : undefined;
    const causalRequestSequence = requiresCausalGeneration
      ? currentGeneration?.causalRequestSequence
      : undefined;
    const liveViewSockets = [...webSockets.values()].filter((socket) => {
      try {
        if (typeof socket.url !== "string") return false;
        const url = new URL(socket.url);
        return (
          ["ws:", "wss:"].includes(url.protocol) &&
          url.pathname === "/live/websocket" &&
          socket.boundToRequest === true &&
          !beforeRequestIds.has(socket.requestId) &&
          matchesPrivateRequestGeneration(
            {
              requestId: socket.requestId,
              generation: socket.generation,
              sequence: socket.sequence,
            },
            generation,
          ) &&
          (!requiresCausalGeneration ||
            (currentGeneration &&
              causalRequestId !== undefined &&
              socket.causalRequestId === causalRequestId &&
              socket.observedSequence >= causalRequestSequence))
        );
      } catch {
        return false;
      }
    });
    assert.ok(
      liveViewSockets.length > 0,
      `LiveView did not create a websocket transport for the current generation: ${JSON.stringify(
        [...webSockets.values()].map((socket) => ({
          requestId: socket.requestId,
          generation: socket.generation,
          observedGeneration: socket.observedGeneration,
          sequence: socket.sequence,
          boundToRequest: socket.boundToRequest,
          observedSequence: socket.observedSequence,
          causalRequestId: socket.causalRequestId,
          url: socket.url,
          closed: socket.closed,
        })),
      )}`,
    );

    const connected = liveViewSockets.find((socket) => {
      const url = new URL(socket.url);
      const originHeader = requestHeader({ request: socket.handshakeRequest }, "origin");
      const socketOrigin = `${url.protocol === "wss:" ? "https" : "http"}://${url.host}`;
      return (
        socketOrigin === normalizedExpectedOrigin.origin &&
        originHeader === normalizedExpectedOrigin.origin &&
        socket.handshake?.status === 101 &&
        socket.closed !== true &&
        !socket.error
      );
    });
    assert.ok(
      connected,
      `LiveView websocket did not complete a same-origin HTTP 101 handshake: ${JSON.stringify(
        liveViewSockets.map((socket) => ({
          url: socket.url,
          origin: requestHeader({ request: socket.handshakeRequest }, "origin"),
          status: socket.handshake?.status,
          error: socket.error,
        })),
      )}`,
    );

    const fallback = [...records.values()].find((record) => {
      try {
        if (typeof record.url !== "string") return false;
        return (
          new URL(record.url).pathname === "/live/longpoll" &&
          !beforeRequestIds.has(record.requestId) &&
          matchesPrivateRequestGeneration(record, generation)
        );
      } catch {
        return false;
      }
    });
    assert.equal(
      fallback,
      undefined,
      `LiveView fell back to longpoll transport: ${fallback?.url || "unknown request"}`,
    );
    assert.deepEqual(
      webSocketFailures,
      [],
      `LiveView websocket transport failed: ${webSocketFailures.join("; ")}`,
    );
    const originDiagnostic = [...consoleErrors, ...logErrors].find((message) =>
      /origin|longpoll/i.test(message),
    );
    assert.equal(
      originDiagnostic,
      undefined,
      `LiveView emitted an origin or transport diagnostic: ${originDiagnostic}`,
    );
    return socketSnapshot(connected);
  };

  const diagnostics = {
    requests: exposedRequests,
    consoleErrors: exposedConsoleErrors,
    logErrors: exposedLogErrors,
    runtimeExceptions: exposedRuntimeExceptions,
    requestFailures: exposedRequestFailures,
    webSockets: exposedWebSockets,
    webSocketFailures: exposedWebSocketFailures,
    servedFromCacheRequestIds: exposedServedFromCacheRequestIds,
    beginRequestGeneration,
    bindRequestGeneration,
    requestForGeneration,
    revokeUnconfirmedExpectedFailures,
    confirmRemoteFailureDiagnostic(referenceId) {
      assert.match(referenceId, /^[0-9a-f-]{36}$/);
      const expected = `Cadence federation failure ${referenceId} Object`;
      const matches = consoleErrors.flatMap((value, index) =>
        value === expected && !confirmedRemoteFailureDiagnostics.has(index) ? [index] : [],
      );
      assert.equal(matches.length, 1, "expected exactly one private remote failure diagnostic");
      confirmedRemoteFailureDiagnostics.add(matches[0]);
    },
    allowExpectedFailure(predicate, { status = 403 } = {}) {
      assert.equal(typeof predicate, "function", "expected failure predicate must be a function");
      assert.equal(Number.isInteger(status), true, "expected failure status must be an integer");
      const registration = {
        predicate,
        expectedStatus: status,
        registeredAfterSequence: sequence,
        requestId: undefined,
        active: true,
        allowances: new Set(),
        view: {},
      };
      expectedFailureRegistrations.push(registration);
      const cleanup = () => {
        invalidateExpectedFailure(registration, "expected failure registration removed");
      };
      expectedFailureCleanups.set(cleanup, registration);
      return cleanup;
    },
    confirmExpectedFailure(cleanup, evidence = {}) {
      const registration = expectedFailureCleanups.get(cleanup);
      if (!registration) {
        return expectedFailureConfirmationFailure(
          undefined,
          undefined,
          "allowance cleanup is not owned by these diagnostics",
        );
      }

      const allowance = [...registration.allowances].find(
        (candidate) => !candidate.revoked && !candidate.finalized,
      );
      if (!allowance) {
        return expectedFailureConfirmationFailure(
          registration,
          undefined,
          "expected failure allowance is not bound",
        );
      }

      const canonicalEntry = expectedFailureCanonicalBindings.get(allowance);
      const evidenceShape = safeDataDescriptors(evidence);
      if (evidenceShape.error) {
        return expectedFailureConfirmationFailure(
          registration,
          allowance,
          `confirmation evidence ${evidenceShape.error}`,
        );
      }
      const allowedEvidenceKeys = new Set([
        "requestId",
        "method",
        "url",
        "generation",
        "status",
        "canonicalEvidence",
        "canonicalEntry",
        "canonical",
        "log",
        "failureEvidence",
        "loadingFailed",
      ]);
      for (const key of evidenceShape.keys) {
        if (!allowedEvidenceKeys.has(key)) {
          return expectedFailureConfirmationFailure(
            registration,
            allowance,
            `confirmation evidence contained an unexpected field ${key}`,
          );
        }
      }
      const evidenceValue = (key) => evidenceShape.descriptors.get(key)?.value;
      const hasEvidenceValue = (key) => evidenceShape.descriptors.has(key);
      const requestId = evidenceValue("requestId");
      const expectedGeneration = evidenceValue("generation");
      const record = typeof requestId === "string" ? records.get(requestId) : undefined;
      const exposedRecord =
        typeof requestId === "string"
          ? Map.prototype.get.call(exposedRequests, requestId)
          : undefined;
      const exposedRecordShape =
        record && exposedRecord === record.view
          ? safeDataDescriptors(exposedRecord)
          : { error: "was not the current request snapshot" };
      const canonicalKeys = ["canonicalEvidence", "canonicalEntry", "canonical", "log"].filter(
        (key) => hasEvidenceValue(key),
      );
      const canonicalEvidence =
        canonicalKeys.length === 1 ? evidenceValue(canonicalKeys[0]) : undefined;
      const failureKeys = ["failureEvidence", "loadingFailed"].filter((key) =>
        hasEvidenceValue(key),
      );
      const suppliedFailures = failureKeys.length === 1 ? evidenceValue(failureKeys[0]) : undefined;

      const mismatches = [];
      const requireEvidence = (condition, reason) => {
        if (!condition) mismatches.push(reason);
      };
      requireEvidence(canonicalKeys.length <= 1, "canonical evidence was supplied more than once");
      requireEvidence(
        failureKeys.length <= 1,
        "loadingFailed evidence was supplied more than once",
      );
      requireEvidence(typeof requestId === "string" && requestId.length > 0, "request id missing");
      requireEvidence(Boolean(record), "request record missing");
      if (record) {
        const exactRecord =
          expectedFailureRecordBindings.get(allowance) === record &&
          allowance.record === record &&
          exposedRecord === record.view &&
          !exposedRecordShape.error;
        requireEvidence(exactRecord, "request record identity changed");
        if (exactRecord) {
          const observationDrift =
            record.observationTampered ||
            checkObservationIntegrity(
              exposedRecord,
              observationDigests.get(exposedRecord),
              "request observation",
            );
          requireEvidence(!observationDrift, observationDrift || "request observation changed");
          const exposedRecordValue = (key) => exposedRecordShape.descriptors.get(key)?.value;
          const exposedAllowance = exposedRecordValue("expectedFailureAllowance");
          const exposedAllowanceShape =
            exposedAllowance === allowance.view
              ? safeDataDescriptors(exposedAllowance)
              : { error: "was not the current allowance snapshot" };
          const exposedAllowanceValue = (key) => exposedAllowanceShape.descriptors?.get(key)?.value;
          requireEvidence(
            exposedRecordValue("requestId") === record.requestId &&
              exposedRecordValue("method") === record.method &&
              exposedRecordValue("url") === record.url &&
              exposedRecordValue("generation") === record.generation &&
              exposedRecordValue("finished") === record.finished &&
              exposedRecordValue("statusEvidence") === record.statusEvidenceView &&
              exposedRecordValue("pendingExpectedFailureLog") ===
                record.pendingExpectedFailureLogView &&
              exposedRecordValue("expectedFailureRegistration") ===
                record.expectedFailureRegistration?.view &&
              exposedRecordValue("expectedFailureAllowance") ===
                record.expectedFailureAllowance?.view &&
              exposedRecordValue("finalizedExpectedFailure") ===
                record.finalizedExpectedFailure?.view,
            "request observation changed",
          );
          requireEvidence(!exposedAllowanceShape.error, "allowance observation changed");
          requireEvidence(
            exposedAllowanceValue("requestId") === allowance.requestId &&
              exposedAllowanceValue("url") === allowance.url &&
              exposedAllowanceValue("method") === allowance.method &&
              exposedAllowanceValue("generation") === allowance.generation &&
              exposedAllowanceValue("status") === allowance.status &&
              exposedAllowanceValue("consumed") === allowance.consumed &&
              exposedAllowanceValue("consumedEntries") === allowance.consumedEntriesView &&
              exposedAllowanceValue("suppressedFailures") === allowance.suppressedFailuresView &&
              exposedAllowanceValue("revoked") === allowance.revoked &&
              exposedAllowanceValue("finalized") === allowance.finalized &&
              exposedAllowanceValue("replayed") === allowance.replayed &&
              exposedAllowanceValue("record") === allowance.record.view,
            "allowance observation changed",
          );
          requireEvidence(
            record.expectedFailureAllowance === allowance,
            "allowance binding changed",
          );
          requireEvidence(allowance.requestId === requestId, "request id changed");
          requireEvidence(record.finished, "request is not terminal");
          requireEvidence(!record.pendingExpectedFailureLog, "canonical evidence is pending");
          requireEvidence(record.method === evidenceValue("method"), "request method changed");
          requireEvidence(record.url === evidenceValue("url"), "request URL changed");
          const generationState = generationStateFor(expectedGeneration);
          const generationMatches =
            record.generation === undefined
              ? expectedGeneration === undefined
              : generationState?.id === record.generation;
          requireEvidence(generationMatches, "request generation changed");
          requireEvidence(allowance.method === evidenceValue("method"), "allowance method changed");
          requireEvidence(allowance.url === evidenceValue("url"), "allowance URL changed");
          requireEvidence(
            allowance.generation === record.generation && generationMatches,
            "allowance generation changed",
          );
          requireEvidence(allowance.status === evidenceValue("status"), "allowance status changed");
          requireEvidence(
            record.responseStatus === evidenceValue("status"),
            "response status changed",
          );
          requireEvidence(
            observedResponseStatus(record) === evidenceValue("status"),
            "status evidence changed",
          );
          requireEvidence(!record.statusDisagreement, "status evidence contradicts");
        }
      }
      requireEvidence(allowance.consumedEntries.length === 1, "canonical evidence count changed");
      requireEvidence(
        allowance.consumedEntries[0] === canonicalEntry,
        "canonical evidence binding changed",
      );
      requireEvidence(
        canonicalEvidenceMatches(canonicalEntry, allowance),
        "canonical evidence changed",
      );
      if (canonicalKeys.length === 1) {
        const boundCanonicalEvidence = canonicalEntryBindings.get(canonicalEvidence);
        requireEvidence(
          boundCanonicalEvidence === canonicalEntry || canonicalEvidence === canonicalEntry,
          "provided canonical evidence identity changed",
        );
        requireEvidence(
          canonicalEvidenceIsSame(canonicalEvidence, canonicalEntry),
          "provided canonical evidence differs",
        );
      }
      if (failureKeys.length === 1 && suppliedFailures !== undefined) {
        const failureValues = Array.isArray(suppliedFailures)
          ? safeOrdinaryArrayEntries(suppliedFailures)
          : { entries: [suppliedFailures] };
        requireEvidence(
          !failureValues.error,
          `loadingFailed evidence ${failureValues.error || "changed"}`,
        );
        const expectedFailures = failureValues.entries || [];
        requireEvidence(
          expectedFailures.length === allowance.suppressedFailures.length &&
            expectedFailures.every(
              (failure, index) => failure === allowance.suppressedFailures[index],
            ),
          "loadingFailed evidence changed",
        );
      }
      if (mismatches.length) {
        return expectedFailureConfirmationFailure(
          registration,
          allowance,
          `terminal request, identity, status, and canonical evidence were not consistent: ${mismatches.join(", ")}`,
        );
      }

      finalizeExpectedFailure(allowance);
      return true;
    },
    async waitForRequest(
      generation,
      predicate,
      label,
      { timeout = CDP_EVENT_TIMEOUT_MS, signal } = {},
    ) {
      const existing = requestForGeneration(generation, predicate);
      if (existing) return existing;

      const event = await client.waitForEvent(
        "Network.requestWillBeSent",
        ({ requestId }) => {
          const record = records.get(requestId);
          return Boolean(
            record &&
            matchesPrivateRequestGeneration(record, generation) &&
            predicate(snapshotRecord(record)),
          );
        },
        timeout,
        signal,
      );
      const record = records.get(event.requestId);
      if (!record) throw new Error(`${label} request was not recorded`);
      return snapshotRecord(record);
    },
    completed(predicate, { generation } = {}) {
      return [...records.values()]
        .filter(
          (record) =>
            record.response &&
            record.finished &&
            !record.failed &&
            matchesPrivateRequestGeneration(record, generation) &&
            predicate(snapshotRecord(record)),
        )
        .sort((left, right) => left.sequence - right.sequence)
        .map((record) => snapshotRecord(record));
    },
    observed(predicate = () => true, { generation } = {}) {
      return [...records.values()]
        .filter(
          (record) =>
            matchesPrivateRequestGeneration(record, generation) &&
            predicate(snapshotRecord(record)),
        )
        .sort((left, right) => left.sequence - right.sequence)
        .map((record) => snapshotRecord(record));
    },
    async drainLateEvents(milliseconds = 250, signal) {
      await sleep(milliseconds, signal);
      reconcilePendingNetworkLogs();
    },
    dispose() {
      if (disposed) return disposePromise;
      disposed = true;
      revokeUnconfirmedExpectedFailures("diagnostics disposed");
      reconcilePendingNetworkLogs();
      flushPendingNetworkLogs();
      const cleanupErrors = [];
      const pending = [];
      while (subscriptions.length) {
        const unsubscribe = subscriptions.pop();
        try {
          if (typeof unsubscribe !== "function" || nodeTypes.isProxy(unsubscribe)) {
            throw new TypeError("diagnostic unsubscribe was not a safe callable");
          }
          const result = Reflect.apply(unsubscribe, undefined, []);
          validateRaceValue(result, "diagnostic unsubscribe");
          if (allowedNativePromise(result)) pending.push(result);
        } catch (error) {
          cleanupErrors.push(error);
        }
      }
      const finish = async () => {
        for (const result of pending) {
          try {
            await Promise.prototype.then.call(
              result,
              () => undefined,
              (error) => {
                throw error;
              },
            );
          } catch (error) {
            cleanupErrors.push(error);
          }
        }
        if (cleanupErrors.length) {
          throw new AggregateError(cleanupErrors, "diagnostic unsubscribe cleanup failed");
        }
      };
      disposePromise = finish();
      disposePromise.catch(() => {});
      return disposePromise;
    },
    assertClean(stage) {
      reconcilePendingNetworkLogs();
      flushPendingNetworkLogs();
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
            webSocketFailures,
            webSockets: [...webSockets.values()].map((socket) => ({
              requestId: socket.requestId,
              url: socket.url,
              generation: socket.generation,
              boundToRequest: socket.boundToRequest,
              boundByHandshake: socket.boundByHandshake,
              observedSequence: socket.observedSequence,
              causalRequestId: socket.causalRequestId,
              status: socket.handshake?.status,
              closed: socket.closed,
              error: socket.error,
            })),
            requests: [...records.values()].map((record) => ({
              requestId: record.requestId,
              generation: record.generation,
              method: record.method,
              url: record.url,
              postData: record.postData,
              frameId: record.frameId,
              loaderId: record.loaderId,
              status: record.response?.status,
              responseExtraStatus: record.responseExtra?.statusCode,
              servedFromCache: record.servedFromCache,
              fromDiskCache: record.response?.fromDiskCache,
              fromServiceWorker: record.response?.fromServiceWorker,
              fromPrefetchCache: record.response?.fromPrefetchCache,
              resourceType: record.resourceType,
              redirects: record.redirects,
              webSocket: record.webSocket,
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
  Object.defineProperty(diagnostics, "assertLiveViewWebSocket", {
    value: assertPrivateLiveViewWebSocket,
    enumerable: false,
    configurable: false,
    writable: false,
  });
  return diagnostics;
}

function assertDetachedLiveViewWebSocket(
  { webSockets, webSocketFailures, requests, consoleErrors = [], logErrors = [] },
  expectedOrigin,
  { beforeRequestIds = new Set(), generation } = {},
) {
  const normalizedExpectedOrigin = new URL(expectedOrigin);
  assert.ok(
    ["http:", "https:"].includes(normalizedExpectedOrigin.protocol),
    `LiveView expected origin must use HTTP(S), got ${normalizedExpectedOrigin.protocol}`,
  );
  const requiresCausalGeneration = generation && typeof generation === "object";
  const causalRequestId = requiresCausalGeneration ? generation.causalRequestId : undefined;
  const causalRequestSequence = requiresCausalGeneration
    ? generation.causalRequestSequence
    : undefined;
  const liveViewSockets = [...webSockets.values()].filter((socket) => {
    try {
      if (typeof socket.url !== "string") return false;
      const url = new URL(socket.url);
      return (
        ["ws:", "wss:"].includes(url.protocol) &&
        url.pathname === "/live/websocket" &&
        socket.boundToRequest === true &&
        !beforeRequestIds.has(socket.requestId) &&
        matchesRequestGeneration(socket, generation) &&
        (!requiresCausalGeneration ||
          (causalRequestId !== undefined &&
            socket.causalRequestId === causalRequestId &&
            socket.observedSequence >= causalRequestSequence))
      );
    } catch {
      return false;
    }
  });
  assert.ok(
    liveViewSockets.length > 0,
    `LiveView did not create a websocket transport for the current generation: ${JSON.stringify(
      [...webSockets.values()].map((socket) => ({
        requestId: socket.requestId,
        generation: socket.generation,
        observedGeneration: socket.observedGeneration,
        sequence: socket.sequence,
        boundToRequest: socket.boundToRequest,
        observedSequence: socket.observedSequence,
        causalRequestId: socket.causalRequestId,
        url: socket.url,
        closed: socket.closed,
      })),
    )}`,
  );

  const connected = liveViewSockets.find((socket) => {
    const url = new URL(socket.url);
    const originHeader = requestHeader({ request: socket.handshakeRequest }, "origin");
    const socketOrigin = `${url.protocol === "wss:" ? "https" : "http"}://${url.host}`;
    return (
      socketOrigin === normalizedExpectedOrigin.origin &&
      originHeader === normalizedExpectedOrigin.origin &&
      socket.handshake?.status === 101 &&
      socket.closed !== true &&
      !socket.error
    );
  });
  assert.ok(
    connected,
    `LiveView websocket did not complete a same-origin HTTP 101 handshake: ${JSON.stringify(
      liveViewSockets.map((socket) => ({
        url: socket.url,
        origin: requestHeader({ request: socket.handshakeRequest }, "origin"),
        status: socket.handshake?.status,
        error: socket.error,
      })),
    )}`,
  );

  const fallback = [...requests.values()].find((record) => {
    try {
      if (typeof record.url !== "string") return false;
      return (
        new URL(record.url).pathname === "/live/longpoll" &&
        !beforeRequestIds.has(record.requestId) &&
        matchesRequestGeneration(record, generation)
      );
    } catch {
      return false;
    }
  });
  assert.equal(
    fallback,
    undefined,
    `LiveView fell back to longpoll transport: ${fallback?.url || "unknown request"}`,
  );
  assert.deepEqual(
    webSocketFailures,
    [],
    `LiveView websocket transport failed: ${webSocketFailures.join("; ")}`,
  );

  const originDiagnostic = [...consoleErrors, ...logErrors].find((message) =>
    /origin|longpoll/i.test(message),
  );
  assert.equal(
    originDiagnostic,
    undefined,
    `LiveView emitted an origin or transport diagnostic: ${originDiagnostic}`,
  );
  return connected;
}

export function assertLiveViewWebSocket(diagnostics, expectedOrigin, options = {}) {
  const privateAssertion = Object.getOwnPropertyDescriptor(
    diagnostics,
    "assertLiveViewWebSocket",
  )?.value;
  if (typeof privateAssertion === "function" && !nodeTypes.isProxy(privateAssertion)) {
    return Reflect.apply(privateAssertion, diagnostics, [expectedOrigin, options]);
  }
  return assertDetachedLiveViewWebSocket(diagnostics, expectedOrigin, options);
}

export async function evaluate(client, expression, label, { signal } = {}) {
  const result = await client.send(
    "Runtime.evaluate",
    {
      expression,
      awaitPromise: true,
      returnByValue: true,
    },
    CDP_COMMAND_TIMEOUT_MS,
    signal,
  );
  if (result.exceptionDetails) throw new Error(`${label}: ${exceptionMessage(result)}`);
  return result.result?.value;
}

export async function waitForExpression(
  client,
  expression,
  label,
  { timeout = CDP_EVENT_TIMEOUT_MS, signal, sleepFn = sleep } = {},
) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    if (await evaluate(client, expression, label, { signal })) return;
    await sleepFn(POLL_INTERVAL_MS, signal);
  }

  const state = await evaluate(
    client,
    "({url: location.href, readyState: document.readyState, body: document.body?.innerText?.slice(0, 2000)})",
    `${label} diagnostics`,
    { signal },
  ).catch((error) => {
    if (signal?.aborted) throw error;
    return {};
  });
  throw new Error(`${label} timed out: ${JSON.stringify(state)}`);
}

export async function waitForResponse(
  diagnostics,
  predicate,
  label,
  { timeout = CDP_EVENT_TIMEOUT_MS, signal, generation } = {},
) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    const match = diagnostics.completed(predicate, { generation }).at(-1);
    if (match) return match;
    await sleep(POLL_INTERVAL_MS, signal);
  }

  throw new Error(`${label} response was not observed`);
}

export async function waitForLatestRequestTerminal(
  diagnostics,
  predicate,
  label,
  { timeout = CDP_EVENT_TIMEOUT_MS, signal, generation } = {},
) {
  let latest = diagnostics.observed(predicate, { generation }).at(-1);
  assert.ok(latest?.requestId, `${label} request was not observed`);
  const deadline = Date.now() + timeout;
  let terminalSnapshotPending = false;

  while (Date.now() < deadline) {
    const requestId = latest.requestId;
    const requestSequence = latest.sequence;
    const current = diagnostics
      .observed((record) => record.requestId === requestId && record.sequence === requestSequence, {
        generation,
      })
      .at(-1);

    if (current?.failed !== undefined) {
      throw new Error(`${label} request ${requestId} failed: ${current.failed}`);
    }

    if (current?.finished === true) {
      const newest = diagnostics.observed(predicate, { generation }).at(-1);
      if (newest && (newest.requestId !== requestId || newest.sequence !== requestSequence)) {
        latest = newest;
        terminalSnapshotPending = false;
        continue;
      }
      if (terminalSnapshotPending) return current;
      terminalSnapshotPending = true;
      await sleep(Math.min(POLL_INTERVAL_MS, Math.max(1, deadline - Date.now())), signal);
      continue;
    }

    terminalSnapshotPending = false;
    await sleep(Math.min(POLL_INTERVAL_MS, Math.max(1, deadline - Date.now())), signal);
  }

  throw new Error(`${label} request ${latest.requestId} did not become terminal`);
}

export function parseResponseBody(result, label) {
  assert.equal(typeof result, "object", `${label} response body was unavailable`);
  assert.equal(typeof result.body, "string", `${label} response body was unavailable`);
  const body = result.base64Encoded
    ? Buffer.from(result.body, "base64").toString("utf8")
    : result.body;
  assert.ok(body.length > 0, `${label} response body was empty`);
  return body;
}

export async function responseJson(client, record, label, { signal } = {}) {
  const result = await client.send(
    "Network.getResponseBody",
    { requestId: record.requestId },
    CDP_COMMAND_TIMEOUT_MS,
    signal,
  );
  const body = parseResponseBody(result, label);
  try {
    return JSON.parse(body);
  } catch (error) {
    throw new Error(`${label} returned invalid JSON: ${error.message}`);
  }
}

async function captureForbiddenQueryEvidence(client, diagnostics, generation, signal) {
  const records = diagnostics.completed(
    (record) => {
      try {
        return (
          record.method === "POST" &&
          record.response?.status === 403 &&
          new URL(record.url).pathname.endsWith("/query")
        );
      } catch {
        return false;
      }
    },
    { generation },
  );

  return Promise.all(
    records.map(async (record) => {
      let body;
      try {
        body = await responseJson(client, record, "forbidden query response", { signal });
      } catch {
        body = { unavailable: true };
      }

      const problem =
        body && typeof body === "object" && body.error && typeof body.error === "object"
          ? body.error
          : body;
      const code = problem && typeof problem.code === "string" ? problem.code : "unknown";
      const sanitizedBody =
        problem && typeof problem === "object"
          ? JSON.stringify({
              code,
              message: typeof problem.message === "string" ? problem.message : undefined,
            })
          : JSON.stringify({ body: typeof problem === "string" ? problem : "unavailable" });

      return {
        requestId: record.requestId,
        url: new URL(record.url).pathname,
        code,
        body: sanitizedBody.slice(0, 512),
      };
    }),
  );
}

export async function assertConditionalEtagRevalidation(
  client,
  diagnostics,
  manifestRecord,
  manifestUrl,
  expectedOrigin,
  { signal, label = "immutable manifest", generation: requestGeneration } = {},
) {
  const expectedEtag = responseHeader(manifestRecord, "etag");
  assert.match(expectedEtag || "", /^"sha256:[0-9a-f]{64}"$/, `${label} has no usable ETag`);
  const parsed = assertHttpUrl(manifestUrl, expectedOrigin, `${label} URL`);
  const generation =
    requestGeneration || diagnostics.beginRequestGeneration(`${label} conditional revalidation`);

  const browserResult = await evaluate(
    client,
    `fetch(${JSON.stringify(parsed.href)}, {cache: "no-cache", headers: {"Cache-Control": "no-cache", "If-None-Match": ${JSON.stringify(expectedEtag)}}}).then((response) => ({status: response.status, ok: response.ok}))`,
    `${label} conditional fetch`,
    { signal },
  );
  assert.ok(
    [200, 304].includes(browserResult.status),
    `${label} conditional fetch was not successful`,
  );

  const deadline = Date.now() + CDP_EVENT_TIMEOUT_MS;
  let record;
  while (Date.now() < deadline) {
    record = diagnostics
      .observed(
        (candidate) =>
          pathMatches(candidate, "GET", parsed.pathname, expectedOrigin) &&
          candidate.url === parsed.href &&
          candidate.responseExtra?.statusCode === 304,
        { generation },
      )
      .at(-1);
    if (record) break;
    await sleep(POLL_INTERVAL_MS, signal);
  }
  assert.ok(record, `${label} conditional response was not observed`);
  assert.equal(
    requestHeader(record, "if-none-match"),
    expectedEtag,
    `${label} did not send the cached ETag`,
  );
  assert.equal(
    record.responseExtra?.statusCode,
    304,
    `${label} did not prove an HTTP 304 revalidation`,
  );
  assert.ok(
    [200, 304].includes(record.response.status),
    `${label} returned an unexpected browser status`,
  );
  assert.ok(
    record.failed === undefined ||
      (record.finished === false && record.failed === "net::ERR_ABORTED (canceled)"),
    `${label} conditional request failed unexpectedly: ${record.failed}`,
  );
  assert.equal(
    responseHeader(record, "etag"),
    expectedEtag,
    `${label} changed its ETag during revalidation`,
  );
  assert.notEqual(
    record.response.fromServiceWorker,
    true,
    `${label} revalidation used a service worker`,
  );
  assert.notEqual(
    record.response.fromPrefetchCache,
    true,
    `${label} revalidation used a prefetch cache`,
  );
  return { browserResult, record, generation };
}

export async function assertMountedRelease(client, releaseId, label, { signal } = {}) {
  await waitForExpression(
    client,
    `document.querySelector('[data-remote-state="ready"]')?.getAttribute('data-mounted-release') === ${JSON.stringify(releaseId)}`,
    `${label} mounted release ${releaseId}`,
    { signal },
  );
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
  const expected = name.toLowerCase();
  for (const headers of [record?.requestExtra?.headers, record?.request?.headers]) {
    const shape = safeDataDescriptors(headers);
    if (shape.error) continue;
    const key = shape.keys.find((candidate) => candidate.toLowerCase() === expected);
    if (key) return shape.descriptors.get(key)?.value;
  }
  return undefined;
}

function responseHeader(record, name) {
  const expected = name.toLowerCase();
  for (const headers of [record?.responseExtra?.headers, record?.response?.headers]) {
    const shape = safeDataDescriptors(headers);
    if (shape.error) continue;
    const key = shape.keys.find((candidate) => candidate.toLowerCase() === expected);
    if (key) return shape.descriptors.get(key)?.value;
  }
  return undefined;
}

export function assertImmutableArtifactResponse(record, label = "release artifact") {
  assert.ok(record, `${label} response was not observed`);
  assert.ok(record.response, `${label} response was not observed`);
  assert.equal(record.response.status, 200, `${label} response must be HTTP 200`);
  assert.equal(record.finished, true, `${label} response was not finished`);
  assert.equal(record.failed, undefined, `${label} request failed`);
  assert.deepEqual(record.redirects, [], `${label} redirected`);
  assert.notEqual(
    record.response.fromServiceWorker,
    true,
    `${label} used a service worker response`,
  );
  assert.notEqual(
    record.response.fromPrefetchCache,
    true,
    `${label} used a prefetch cache response`,
  );
  assert.equal(
    responseHeader(record, "cache-control"),
    "public, max-age=31536000, immutable",
    `${label} did not advertise immutable caching`,
  );
  assert.match(
    responseHeader(record, "etag") || "",
    /^"sha256:[0-9a-f]{64}"$/,
    `${label} did not return a strong digest ETag`,
  );
  return record;
}

export function assertImmutableReleaseCacheReuse(records, releases, label = "release cache reuse") {
  const prefixes = releases.map(({ applicationKey, releaseId }) =>
    releaseArtifactPrefix(applicationKey, releaseId),
  );
  const candidates = records.filter((record) => {
    if (!record?.response || record.response.status !== 200 || record.failed || !record.finished)
      return false;
    if (record.response.fromServiceWorker === true || record.response.fromPrefetchCache === true)
      return false;
    return prefixes.some((prefix) => {
      try {
        return new URL(record.url).pathname.startsWith(prefix);
      } catch {
        return false;
      }
    });
  });
  assert.ok(candidates.length > 0, `${label} observed no immutable release artifacts`);
  assert.ok(
    candidates.some(
      (record) =>
        record.servedFromCache === true ||
        record.response.fromDiskCache === true ||
        record.response.fromMemoryCache === true,
    ),
    `${label} did not observe Chrome cache reuse: ${JSON.stringify(candidates.map((record) => ({ url: record.url, servedFromCache: record.servedFromCache, fromDiskCache: record.response.fromDiskCache })))}`,
  );
  return candidates;
}

export function assertNoReleaseArtifactRequests(records, releases, label = "release isolation") {
  const prefixes = releases.map(({ applicationKey, releaseId }) =>
    releaseArtifactPrefix(applicationKey, releaseId),
  );
  const stale = records.filter((record) => {
    try {
      return prefixes.some((prefix) => new URL(record.url).pathname.startsWith(prefix));
    } catch {
      return false;
    }
  });
  assert.deepEqual(
    stale,
    [],
    `${label} observed forbidden release artifacts: ${JSON.stringify(stale.map((record) => record.url))}`,
  );
}

export function assertHttpRequestContract(
  record,
  {
    origin,
    method,
    pathname,
    label,
    body,
    headers = {},
    responseHeaders = {},
    requireIdempotencyKey = false,
  },
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
    assert.equal(
      requestHeader(record, name),
      value,
      `${label} missing or incorrect ${name} header`,
    );
  }
  for (const [name, value] of Object.entries(responseHeaders)) {
    assert.equal(
      responseHeader(record, name),
      value,
      `${label} missing or incorrect response ${name} header`,
    );
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

export function releaseArtifactPrefix(applicationKey, releaseId) {
  assert.match(
    applicationKey || "",
    /^[a-z][a-z0-9._-]{0,127}$/,
    "release application key is invalid",
  );
  assert.match(releaseId || "", /^sha256:[0-9a-f]{64}$/, "release ID is invalid");
  return `/releases/${applicationKey}/${releaseId}/artifacts/`;
}

export function assertReleaseArtifactUrl(
  url,
  origin,
  { applicationKey, releaseId, artifactPath, label = "release artifact" } = {},
) {
  const parsed = assertHttpUrl(url, origin, `${label} URL`);
  const prefix = releaseArtifactPrefix(applicationKey, releaseId);
  assert.equal(parsed.search, "", `${label} URL must not include a query string`);
  assert.equal(parsed.hash, "", `${label} URL must not include a fragment`);
  assert.ok(parsed.pathname.startsWith(prefix), `${label} escaped its expected release path`);
  if (artifactPath !== undefined) {
    assert.equal(parsed.pathname, `${prefix}${artifactPath}`, `${label} path changed`);
  }
  return parsed;
}

export function assertManifestAssetsRequested(
  manifest,
  manifestUrl,
  records,
  {
    origin,
    applicationKey,
    releaseId,
    label = "remote manifest",
    requiredExposedModule,
    requireImmutableCache = false,
  } = {},
) {
  const manifestLocation = assertReleaseArtifactUrl(manifestUrl, origin, {
    applicationKey,
    releaseId,
    artifactPath: "mf-manifest.json",
    label,
  });
  const releasePrefix = releaseArtifactPrefix(applicationKey, releaseId);
  const assetStrings = new Set();
  const requiredAssetStrings = new Set();

  let selectedExpose;
  if (requiredExposedModule !== undefined) {
    selectedExpose = (manifest.exposes || []).find(
      (candidate) => candidate.path === requiredExposedModule,
    );
    assert.ok(selectedExpose, `${label} does not declare exposed module ${requiredExposedModule}`);
  }

  const visit = (value, key) => {
    if (key === "ssrRemoteEntry") return;
    if (typeof value === "string" && /\.(?:m?js|css)(?:[?#]|$)/i.test(value)) {
      assetStrings.add(value);
    } else if (Array.isArray(value)) {
      for (const child of value) visit(child);
    } else if (value && typeof value === "object") {
      for (const [childKey, child] of Object.entries(value)) visit(child, childKey);
    }
  };
  visit(manifest);

  const visitSynchronousAssets = (value, key) => {
    if (key === "async") {
      return;
    } else if (typeof value === "string" && /\.(?:m?js|css)(?:[?#]|$)/i.test(value)) {
      requiredAssetStrings.add(value);
    } else if (Array.isArray(value)) {
      for (const child of value) visitSynchronousAssets(child);
    } else if (value && typeof value === "object") {
      for (const [childKey, child] of Object.entries(value)) {
        visitSynchronousAssets(child, childKey);
      }
    }
  };

  const runtimeEntry =
    (typeof manifest.entry === "string" && manifest.entry) || manifest.metaData?.remoteEntry?.name;
  if (runtimeEntry) requiredAssetStrings.add(runtimeEntry);
  if (selectedExpose) visitSynchronousAssets(selectedExpose.assets);
  for (const shared of manifest.shared || []) visitSynchronousAssets(shared.assets || shared);

  assert.ok(assetStrings.size > 0, `${label} declared no JavaScript or CSS assets`);
  const assets = [...assetStrings].map((asset) =>
    assertReleaseArtifactUrl(new URL(asset, manifestLocation).href, origin, {
      applicationKey,
      releaseId,
      label: `${label} asset`,
    }),
  );
  assert.ok(
    assets.every((asset) => asset.pathname.startsWith(releasePrefix)),
    `${label} declared an asset outside its release path`,
  );
  const requiredAssetHrefs = new Set(
    [...requiredAssetStrings].map(
      (asset) =>
        assertReleaseArtifactUrl(new URL(asset, manifestLocation).href, origin, {
          applicationKey,
          releaseId,
          label: `${label} required asset`,
        }).href,
    ),
  );
  for (const asset of assets) {
    const observed = (records || [])
      .filter((record) => {
        try {
          return new URL(record.url).href === asset.href;
        } catch {
          return false;
        }
      })
      .sort((left, right) => (left.sequence || 0) - (right.sequence || 0));
    if (!requiredAssetHrefs.has(asset.href) && observed.length === 0) continue;
    const loaded = observed.at(-1);
    assert.ok(
      loaded?.response && loaded.finished && !loaded.failed,
      `${label} asset was not successfully requested: ${asset.href}`,
    );
    assert.equal(loaded.response.status, 200, `${label} asset was not HTTP 200: ${asset.href}`);
    assert.deepEqual(loaded.redirects, [], `${label} asset redirected: ${asset.href}`);
    if (requireImmutableCache) assertImmutableArtifactResponse(loaded, `${label} asset`);
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

export async function waitForPageNavigation(
  client,
  operation,
  { signal, label = "page navigation", timeout = CDP_EVENT_TIMEOUT_MS } = {},
) {
  const events = [];
  let eventSequence = 0;
  let resultReady = false;
  let result;
  let exactFrame;
  let exactLifecycleLoad;
  let resolveCompletion;
  let rejectCompletion;
  let settled = false;
  const completion = new Promise((resolve, reject) => {
    resolveCompletion = resolve;
    rejectCompletion = reject;
  });
  completion.catch(() => {});

  const finish = (value) => {
    if (settled) return;
    settled = true;
    resolveCompletion(value);
  };
  const maybeFinish = () => {
    if (!resultReady || !exactFrame || !exactLifecycleLoad) return;
    finish({ result, frame: exactFrame.frame, load: exactLifecycleLoad.params });
  };
  const considerFrame = (event) => {
    if (!resultReady || exactFrame || !event.params?.frame) return;
    const frame = event.params.frame;
    if (frame.parentId || frame.id !== result.frameId || frame.loaderId !== result.loaderId) return;
    exactFrame = { ...event, frame };
    maybeFinish();
  };
  const considerLifecycle = (event) => {
    const params = event.params;
    if (
      !resultReady ||
      exactLifecycleLoad ||
      !exactFrame ||
      event.sequence <= exactFrame.sequence ||
      params?.name !== "load" ||
      params?.frameId !== result.frameId ||
      params?.loaderId !== result.loaderId
    )
      return;
    exactLifecycleLoad = event;
    maybeFinish();
  };
  const onFrameNavigated = (params) => {
    const event = { kind: "frame", params, sequence: ++eventSequence };
    events.push(event);
    considerFrame(event);
  };
  const onLifecycleEvent = (params) => {
    const event = { kind: "lifecycle", params, sequence: ++eventSequence };
    events.push(event);
    considerLifecycle(event);
  };

  const frameOff = client.on("Page.frameNavigated", onFrameNavigated);
  const lifecycleOff = client.on("Page.lifecycleEvent", onLifecycleEvent);

  try {
    const operationPromise = invokeValidated(operation, `${label} command`);
    operationPromise.catch(() => {});
    result = await raceWithSignalAndTimeout(operationPromise, {
      signal,
      milliseconds: CDP_COMMAND_TIMEOUT_MS,
      label: `${label} command`,
    });
    assert.ok(!result?.errorText, `${label} failed: ${result?.errorText || "unknown error"}`);
    assert.equal(typeof result?.frameId, "string", `${label} did not return a frame id`);
    assert.equal(typeof result?.loaderId, "string", `${label} did not return a loader id`);
    resultReady = true;
    for (const event of [...events]) {
      if (event.kind === "frame") considerFrame(event);
      if (event.kind === "lifecycle") considerLifecycle(event);
    }
    maybeFinish();
    const completed = await raceWithSignalAndTimeout(completion, {
      signal,
      milliseconds: timeout,
      label: `${label} completion`,
    });
    return completed;
  } catch (error) {
    rejectCompletion(error);
    throw error;
  } finally {
    frameOff?.();
    lifecycleOff?.();
  }
}

export async function navigate(
  client,
  url,
  { expectedOrigin, expectedPath, signal, diagnostics } = {},
) {
  const target = assertHttpUrl(url, expectedOrigin, "navigation URL");
  const generation = diagnostics?.beginRequestGeneration(`navigation ${target.pathname}`);
  reportProgress(`navigating ${target.href}`);
  const navigationController = new AbortController();
  const onAbort = () => navigationController.abort(abortError(signal));
  signal?.addEventListener("abort", onAbort, { once: true });
  if (signal?.aborted) onAbort();
  const navigationSignal = navigationController.signal;

  try {
    const navigation = await waitForPageNavigation(
      client,
      () =>
        client.send(
          "Page.navigate",
          { url: target.href },
          CDP_COMMAND_TIMEOUT_MS,
          navigationSignal,
        ),
      { signal: navigationSignal, label: `navigation to ${target.href}` },
    );
    const { result, frame } = navigation;
    if (diagnostics) {
      const navigationRequest = await diagnostics.waitForRequest(
        generation,
        (record) =>
          record.resourceType === "Document" &&
          record.frameId === result.frameId &&
          record.loaderId === result.loaderId,
        `navigation to ${target.href}`,
        { signal: navigationSignal },
      );
      diagnostics.bindRequestGeneration(generation, navigationRequest, {
        admitObservedSockets: true,
      });
    }
    const documentState = await evaluate(
      client,
      "({href: location.href, origin: location.origin, readyState: document.readyState, hasBody: document.body !== null})",
      `${target.href} document validation`,
      { signal: navigationSignal },
    );
    assertHttpUrl(documentState.href, expectedOrigin, "resulting document URL");
    assert.equal(documentState.origin, target.origin, "resulting document origin changed");
    if (expectedPath)
      assert.equal(
        new URL(documentState.href).pathname,
        expectedPath,
        "resulting document path changed",
      );
    assert.equal(documentState.readyState, "complete", "resulting document did not load");
    assert.equal(documentState.hasBody, true, "resulting document has no body");
    assertHttpUrl(frame.url, expectedOrigin, "frame navigation URL");
    return generation;
  } finally {
    signal?.removeEventListener("abort", onAbort);
    navigationController.abort(new Error("navigation wait settled"));
  }
}

export function matchesSignInNavigationRequest(record, { expectedOrigin } = {}) {
  if (
    record?.resourceType !== "Document" ||
    record.method !== "POST" ||
    !record.frameId ||
    !record.loaderId
  )
    return false;

  try {
    const requestUrl = new URL(record.url);
    return requestUrl.origin === expectedOrigin && requestUrl.pathname === "/sign-in";
  } catch {
    return false;
  }
}

export function assertSignInUrl(url, expectedOrigin, label = "sign-in URL") {
  const parsed = assertHttpUrl(url, expectedOrigin, label);
  assert.equal(parsed.pathname, "/sign-in", `${label} must use the exact /sign-in pathname`);
  return parsed;
}

async function assertUnauthenticatedCatalogContained(
  client,
  diagnostics,
  catalogUrl,
  expectedOrigin,
  signal,
) {
  const target = assertHttpUrl(catalogUrl, expectedOrigin, "unauthenticated catalog URL");
  const generation = await navigate(client, target.href, {
    expectedOrigin,
    expectedPath: "/sign-in",
    diagnostics,
    signal,
  });
  await waitForExpression(
    client,
    "Boolean(document.querySelector('#sign-in-form')) && !document.querySelector('#cadence-phoenix-host')",
    "unauthenticated catalog containment",
    { signal },
  );

  const catalogRecord = diagnostics.requestForGeneration(
    generation,
    (record) =>
      record.url === target.href ||
      record.redirects?.some((redirect) => redirect.url === target.href),
  );
  assert.ok(catalogRecord, "unauthenticated catalog request was not observed");
  const catalogRedirect = catalogRecord.redirects?.find((redirect) => redirect.url === target.href);
  const catalogStatus = catalogRedirect?.status ?? catalogRecord.response?.status;
  assert.ok(
    [302, 303, 401, 403].includes(catalogStatus),
    `unauthenticated catalog escaped the auth boundary: ${catalogStatus}`,
  );
  assert.equal(
    diagnostics.completed(
      (record) => {
        try {
          return new URL(record.url).pathname.endsWith("/actions");
        } catch {
          return false;
        }
      },
      { generation },
    ).length,
    0,
    "unauthenticated catalog issued an action",
  );
  assert.equal(
    diagnostics.completed(
      (record) => /\/releases\/[^/]+\/sha256:[0-9a-f]{64}\/artifacts\//.test(record.url),
      { generation },
    ).length,
    0,
    "unauthenticated catalog mounted a release artifact",
  );
  return generation;
}

async function armNextManifestFailure(client, signal) {
  const result = await client.send(
    "Page.addScriptToEvaluateOnNewDocument",
    {
      source: `(() => {
        const nativeFetch = window.fetch.bind(window);
        let failed = false;
        window.fetch = (input, init) => {
          const candidate = typeof input === "string" ? input : input?.url;
          const pathname = candidate ? new URL(candidate, location.href).pathname : "";
          if (!failed && pathname.endsWith("/mf-manifest.json")) {
            failed = true;
            window.fetch = nativeFetch;
            return Promise.reject(new Error("FEDERATION_INTERNAL_MANIFEST_FAILURE"));
          }
          return nativeFetch(input, init);
        };
      })();`,
    },
    CDP_COMMAND_TIMEOUT_MS,
    signal,
  );
  assert.ok(result?.identifier, "manifest failure injection was not installed");
  return result.identifier;
}

async function removeNewDocumentScript(client, identifier, signal) {
  if (!identifier) return;
  await client.send(
    "Page.removeScriptToEvaluateOnNewDocument",
    { identifier },
    CDP_COMMAND_TIMEOUT_MS,
    signal,
  );
}

async function assertContainedRemoteFailureAndRetry({
  client,
  diagnostics,
  signal,
  url,
  expectedOrigin,
  expectedReleaseId,
  readyExpression,
}) {
  const scriptId = await armNextManifestFailure(client, signal);
  let generation;
  try {
    const surfaceUrl = assertHttpUrl(url, expectedOrigin, "remote failure surface URL");
    generation = await navigate(client, surfaceUrl.href, {
      expectedOrigin,
      expectedPath: surfaceUrl.pathname,
      diagnostics,
      signal,
    });
    await waitForExpression(
      client,
      "Boolean(document.querySelector('#remote-error') && document.querySelector('#remote-error-message') && document.querySelector('#remote-error-reference') && !document.querySelector('#comms-application'))",
      "contained manifest failure",
      { signal },
    );
  } finally {
    await removeNewDocumentScript(client, scriptId, signal);
  }

  const errorState = await evaluate(
    client,
    `(() => ({
      message: document.querySelector('#remote-error-message')?.textContent?.trim(),
      reference: document.querySelector('#remote-error-reference')?.textContent?.trim(),
      release: document.querySelector('[data-remote-state="ready"]')?.getAttribute('data-mounted-release') ?? null,
      retry: Boolean(document.querySelector('#retry-remote'))
    }))()`,
    "contained manifest failure state",
    { signal },
  );
  assert.equal(errorState.message, "The approved application release could not be loaded.");
  assert.match(errorState.reference || "", /^Reference ID: [0-9a-f-]{36}$/);
  assert.doesNotMatch(errorState.message || "", /FEDERATION_INTERNAL_MANIFEST_FAILURE/);
  assert.equal(errorState.release, null, "a failed remote must not report a mounted release");
  assert.equal(errorState.retry, true);
  diagnostics.confirmRemoteFailureDiagnostic(errorState.reference.slice("Reference ID: ".length));

  const clicked = await evaluate(
    client,
    "(() => { const button = document.querySelector('#retry-remote'); if (!button) return false; button.click(); return true; })()",
    "approved remote retry",
    { signal },
  );
  assert.equal(clicked, true);
  await waitForExpression(client, readyExpression, "approved remote retry readiness", { signal });
  await assertMountedRelease(client, expectedReleaseId, "approved remote retry", { signal });
  return generation;
}

async function armNextActionCsrfRejection(client, signal) {
  const result = await client.send(
    "Page.addScriptToEvaluateOnNewDocument",
    {
      source: `(() => {
        const nativeFetch = window.fetch.bind(window);
        let rejected = false;
        window.fetch = (input, init) => {
          const candidate = typeof input === "string" ? input : input?.url;
          const pathname = candidate ? new URL(candidate, location.href).pathname : "";
          const method = (init?.method || (typeof input === "object" ? input?.method : "GET")).toUpperCase();
          if (!rejected && method === "POST" && pathname.endsWith("/actions")) {
            rejected = true;
            window.fetch = nativeFetch;
            const headers = new Headers(init?.headers || {});
            headers.set("x-csrf-token", "federation-browser-invalid-csrf");
            return nativeFetch(input, {...init, headers});
          }
          return nativeFetch(input, init);
        };
      })();`,
    },
    CDP_COMMAND_TIMEOUT_MS,
    signal,
  );
  assert.ok(result?.identifier, "CSRF rejection injection was not installed");
  return result.identifier;
}

async function submitSignIn(
  client,
  loginUrl,
  email,
  password,
  expectedOrigin,
  diagnostics,
  signal,
) {
  const login = assertSignInUrl(loginUrl, expectedOrigin);
  const loginGeneration = await navigate(client, login.href, {
    expectedOrigin,
    expectedPath: "/sign-in",
    diagnostics,
    signal,
  });
  await waitForExpression(
    client,
    "Boolean(document.querySelector('#sign-in-form input[name=\"user[email]\"]') && document.querySelector('#sign-in-form input[name=\"user[password]\"]'))",
    "sign-in form",
    { signal },
  );

  const submissionController = new AbortController();
  const onAbort = () => submissionController.abort(abortError(signal));
  signal?.addEventListener("abort", onAbort, { once: true });
  if (signal?.aborted) onAbort();
  const submissionSignal = submissionController.signal;
  const generation = diagnostics?.beginRequestGeneration("authenticated sign-in");
  try {
    const navigationRequest = diagnostics?.waitForRequest(
      generation,
      (record) => matchesSignInNavigationRequest(record, { expectedOrigin: login.origin }),
      "authenticated sign-in navigation",
      { signal: submissionSignal },
    );
    const navigation = waitForPageNavigation(
      client,
      async () => {
        const request = await navigationRequest;
        return { frameId: request.frameId, loaderId: request.loaderId };
      },
      { signal: submissionSignal, label: "authenticated sign-in navigation" },
    );
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
      { signal: submissionSignal },
    );
    assert.equal(result, true, "sign-in form was not submitted");
    const authenticatedRequest = await navigationRequest;
    await navigation;
    diagnostics?.bindRequestGeneration(generation, authenticatedRequest);
    const state = await evaluate(
      client,
      "({href: location.href, origin: location.origin})",
      "authenticated redirect",
      { signal: submissionSignal },
    );
    assertHttpUrl(state.href, expectedOrigin, "authenticated redirect URL");
    assert.equal(state.origin, expectedOrigin, "authenticated redirect changed origin");
    await waitForExpression(
      client,
      "location.pathname !== '/sign-in' && !document.querySelector('#sign-in-form')",
      "authenticated redirect",
      { signal: submissionSignal },
    );
    return generation;
  } finally {
    signal?.removeEventListener("abort", onAbort);
    submissionController.abort(new Error("sign-in wait settled"));
  }
}

function assertCatalog(
  catalog,
  applicationKey,
  surfaceId,
  expectedScope,
  expectedOrigin,
  expectedReleaseId,
) {
  assert.equal(catalog.schema, "cadence.first-party-frontend-catalog.v1");
  assert.equal(catalog.hostContract, "cadence.application-host.v1");
  assert.ok(
    !Number.isNaN(Date.parse(catalog.generatedAt)),
    "catalog generatedAt is not a timestamp",
  );
  assert.equal(catalog.session.context.scope, expectedScope);
  assert.ok(catalog.session.sessionId);
  assert.ok(catalog.session.csrfToken);
  assertHttpUrl(
    new URL(catalog.session.bridgeBaseUrl, expectedOrigin).href,
    expectedOrigin,
    "catalog bridge base URL",
  );
  const expectedApplicationKeys = [applicationKey];
  assert.deepEqual(
    catalog.applications.map((application) => application.applicationKey).sort(),
    expectedApplicationKeys.sort(),
    `${expectedScope} catalog application set changed`,
  );

  const application = catalog.applications.find(
    (candidate) => candidate.applicationKey === applicationKey,
  );
  assert.ok(application, `${applicationKey} was not advertised in the ${expectedScope} catalog`);
  assert.equal(application.applicationKey, applicationKey);
  assert.equal(application.applicationVersion, 1);
  assert.equal(application.surface.surfaceId, surfaceId);
  assert.equal(application.surface.version, 1);
  assert.equal(application.release.federation, "module_federation");
  assert.equal(
    application.release.exposedModule,
    application.surface.renderer.exposedModule,
    `${applicationKey} catalog surface and release exposed modules diverged`,
  );
  if (expectedReleaseId !== undefined) {
    assert.equal(
      application.release.releaseId,
      expectedReleaseId,
      `${applicationKey} catalog release changed`,
    );
  }
  assertReleaseArtifactUrl(application.release.manifestUrl, expectedOrigin, {
    applicationKey,
    releaseId: application.release.releaseId,
    artifactPath: "mf-manifest.json",
    label: `${applicationKey} manifest`,
  });
  return application;
}

function queryBody(application, queryId, queryVersion, scope) {
  const queryScope =
    scope.scope === "organization"
      ? { scope: "organization", organizationId: scope.organizationId }
      : {
          organizationId: scope.organizationId,
          missionId: scope.missionId,
          spacecraftId: scope.spacecraftId,
        };

  return {
    applicationKey: application.applicationKey,
    applicationVersion: application.applicationVersion,
    surfaceId: application.surface.surfaceId,
    surfaceVersion: application.surface.version,
    queryId,
    queryVersion,
    scope: queryScope,
    params: {},
  };
}

async function assertRemoteSurface({
  client,
  diagnostics,
  signal,
  url,
  expectedOrigin,
  catalogPath,
  applicationKey,
  surfaceId,
  expectedScope,
  readyExpression,
  queryPath,
  queryId,
  queryVersion,
  expectedReleaseId,
  readPublishedHostBody = false,
  navigateSurface = true,
  existingGeneration,
}) {
  const surfaceUrl = assertHttpUrl(url, expectedOrigin, `${applicationKey} surface URL`);
  const generation = navigateSurface
    ? await navigate(client, surfaceUrl.href, {
        expectedOrigin,
        expectedPath: surfaceUrl.pathname,
        diagnostics,
        signal,
      })
    : existingGeneration;
  assert.ok(generation, `${applicationKey} existing document generation was not supplied`);
  reportProgress(`${applicationKey} waiting for REMOTE READY`);
  try {
    await waitForExpression(client, readyExpression, `${applicationKey} REMOTE READY`, { signal });
  } catch (error) {
    throw new Error(`${error.message}\n${diagnostics.describe()}`, { cause: error });
  }
  reportProgress(`${applicationKey} REMOTE READY observed`);
  if (expectedReleaseId !== undefined) {
    await assertMountedRelease(client, expectedReleaseId, applicationKey, { signal });
  }

  reportProgress(`${applicationKey} waiting for catalog response`);
  const catalogRecord = await waitForResponse(
    diagnostics,
    (record) => pathMatches(record, "GET", catalogPath, expectedOrigin),
    `${applicationKey} catalog`,
    { generation, signal },
  );
  reportProgress(`${applicationKey} catalog response observed`);
  assertHttpRequestContract(catalogRecord, {
    origin: expectedOrigin,
    method: "GET",
    pathname: catalogPath,
    label: `${applicationKey} catalog`,
    responseHeaders: { "cache-control": "no-store" },
  });
  const catalog = await responseJson(client, catalogRecord, `${applicationKey} catalog`, {
    signal,
  });
  const application = assertCatalog(
    catalog,
    applicationKey,
    surfaceId,
    expectedScope,
    expectedOrigin,
    expectedReleaseId,
  );
  const releaseId = application.release.releaseId;

  const manifestUrl = assertReleaseArtifactUrl(application.release.manifestUrl, expectedOrigin, {
    applicationKey,
    releaseId,
    artifactPath: "mf-manifest.json",
    label: `${applicationKey} manifest`,
  });
  reportProgress(`${applicationKey} waiting for manifest response`);
  const manifestRecord = await waitForResponse(
    diagnostics,
    (record) =>
      pathMatches(record, "GET", manifestUrl.pathname, expectedOrigin) &&
      record.url === manifestUrl.href,
    `${applicationKey} manifest`,
    { generation, signal },
  );
  reportProgress(`${applicationKey} manifest response observed`);
  assertHttpRequestContract(manifestRecord, {
    origin: expectedOrigin,
    method: "GET",
    pathname: manifestUrl.pathname,
    label: `${applicationKey} manifest`,
  });
  assertImmutableArtifactResponse(manifestRecord, `${applicationKey} manifest`);
  assertReleaseArtifactUrl(manifestRecord.url, expectedOrigin, {
    applicationKey,
    releaseId,
    artifactPath: "mf-manifest.json",
    label: `${applicationKey} manifest request`,
  });
  const manifest = await responseJson(client, manifestRecord, `${applicationKey} manifest`, {
    signal,
  });
  assert.equal(typeof manifest, "object");
  assertManifestAssetsRequested(
    manifest,
    manifestUrl.href,
    diagnostics.completed(() => true, { generation }),
    {
      origin: expectedOrigin,
      applicationKey,
      releaseId,
      label: `${applicationKey} manifest`,
      requiredExposedModule: application.release.exposedModule,
      requireImmutableCache: true,
    },
  );
  reportProgress(`${applicationKey} manifest assets asserted`);

  const staticRemotePrefix = {
    comms: "/assets/application-host/comms/",
    telemetry_decom: "/assets/application-host/telemetry-decom/",
    mission_catalog: "/assets/application-host/mission-catalog/",
    ops_console: "/assets/application-host/ops-console/",
    organization_admin: "/assets/application-host/organization-admin/",
    spacecraft: "/assets/application-host/spacecraft/",
  }[applicationKey];
  assert.ok(staticRemotePrefix, `${applicationKey} has no static fallback prefix contract`);
  const staticFallback = diagnostics
    .completed(
      (record) => {
        try {
          const requestUrl = new URL(record.url);
          return (
            pathMatches(record, "GET", requestUrl.pathname, expectedOrigin) &&
            requestUrl.pathname.startsWith(staticRemotePrefix)
          );
        } catch {
          return false;
        }
      },
      { generation },
    )
    .at(-1);
  assert.equal(
    staticFallback,
    undefined,
    `${applicationKey} used a static /assets remote fallback`,
  );

  const hostRecord = await waitForLatestRequestTerminal(
    diagnostics,
    (record) => pathMatches(record, "GET", "/assets/application-host/host/host.js", expectedOrigin),
    "published Phoenix host bundle",
    { generation, signal },
  );
  assert.ok(hostRecord, "published Phoenix host bundle request was not observed");
  assert.ok(hostRecord.response, "published Phoenix host bundle response was not observed");
  assert.ok(
    [200, 304].includes(hostRecord.response.status),
    `published Phoenix host bundle response must be HTTP 200 or 304\n\n${hostRecord.response.status} !== 200 or 304`,
  );
  assert.equal(
    hostRecord.finished,
    true,
    "published Phoenix host bundle response was not finished",
  );
  assert.equal(hostRecord.failed, undefined, "published Phoenix host bundle request failed");
  assert.deepEqual(hostRecord.redirects, [], "published Phoenix host bundle redirected");
  if (readPublishedHostBody) {
    assertHttpRequestContract(hostRecord, {
      origin: expectedOrigin,
      method: "GET",
      pathname: "/assets/application-host/host/host.js",
      label: "published Phoenix host bundle body",
    });
    reportProgress(`${applicationKey} reading published host bundle body`);
    const hostBody = await client.send(
      "Network.getResponseBody",
      { requestId: hostRecord.requestId },
      CDP_COMMAND_TIMEOUT_MS,
      signal,
    );
    parseResponseBody(hostBody, "published Phoenix host bundle body");
    reportProgress(`${applicationKey} published Phoenix host bundle body asserted`);
  }

  reportProgress(`${applicationKey} waiting for query response`);
  const queryRecord = await waitForResponse(
    diagnostics,
    (record) => pathMatches(record, "POST", queryPath, expectedOrigin),
    `${applicationKey} query`,
    { generation, signal },
  );
  reportProgress(`${applicationKey} query response observed`);
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
    body: queryBody(application, queryId, queryVersion, scope),
  });
  const query = await responseJson(client, queryRecord, `${applicationKey} query`, { signal });
  await waitForLatestRequestTerminal(
    diagnostics,
    (record) => pathMatches(record, "GET", "/assets/application-host/host/host.js", expectedOrigin),
    `${applicationKey} Phoenix host bundle completion`,
    { generation, signal },
  );
  const forbiddenQueryEvidence = await captureForbiddenQueryEvidence(
    client,
    diagnostics,
    generation,
    signal,
  );
  if (forbiddenQueryEvidence.length) {
    reportProgress(
      `${applicationKey} 403 query evidence: ${JSON.stringify(forbiddenQueryEvidence)}`,
    );
  }
  diagnostics.assertClean(`${applicationKey} surface`);
  return {
    catalog,
    application,
    manifest,
    manifestRecord,
    manifestUrl: manifestUrl.href,
    query,
    queryRecord,
    queryPath,
    generation,
  };
}

async function assertMissionEntryNavigation(client, diagnostics, missionId, origin, signal) {
  const root = `/missions/${encodeURIComponent(missionId)}`;
  await navigate(client, `${origin}/missions`, {
    expectedOrigin: origin,
    expectedPath: "/missions",
    diagnostics,
    signal,
  });
  await waitForExpression(
    client,
    "Boolean(document.querySelector('#mission-list-table') && window.liveSocket?.isConnected())",
    "core mission directory",
    { signal },
  );
  assert.equal(
    await evaluate(
      client,
      `(() => {
    const shell = document.querySelector('#application-shell');
    if (shell?.dataset.useDiff !== 'true') return false;
    const link = [...document.querySelectorAll('#mission-list-table a')]
      .find(link => new URL(link.href).pathname === ${JSON.stringify(root)});
    if (!link) return false;
    window.__missionEntryShell = shell;
    link.click(); return true;
  })()`,
      "click mission from core directory with incremental props",
      { signal },
    ),
    true,
    "core directory must expose its authorized mission link and incremental host",
  );
  await waitForExpression(
    client,
    `(() => {
    const shell = document.querySelector('#application-shell');
    const nav = shell?.querySelector('[aria-label="Primary navigation"]');
    return location.pathname === ${JSON.stringify(root)} && window.__missionEntryShell === shell &&
      nav?.querySelector('a[href="${root}"][aria-current="page"]') &&
      nav.querySelector('a[href="${root}/spacecraft"]') &&
      nav.querySelector('a[href="${root}/applications"]') &&
      !nav.querySelector('a[href="/missions"]') &&
      document.querySelector('#spacecraft-readiness-section') &&
      document.querySelectorAll('#cadence-federation-root').length === 0 &&
      !document.querySelector('#core-mission-error');
  })()`,
    "core mission overview and authorized mission navigation",
    { signal },
  );
  diagnostics.assertClean("mission entry navigation with production incremental props");
  reportProgress("core mission entry retains the host and updates its authorized sidebar");
}

async function assertPersistentHostNavigation(client, diagnostics, missionId, signal) {
  reportProgress("checking persistent shell navigation and browser history");
  const root = `/missions/${encodeURIComponent(missionId)}`;
  assert.equal(
    await evaluate(
      client,
      `(() => {
    const shell = document.querySelector('#application-shell');
    const sidebar = shell?.querySelector('[data-sidebar-collapsible]');
    if (!shell || !sidebar) return false;
    window.__cadenceNavigationProbe = { shell, sidebar, liveRoot: shell.closest('[data-phx-main]'), phoenixNavigations: 0 };
    window.addEventListener("phx:navigate", () => window.__cadenceNavigationProbe.phoenixNavigations++);
    sidebar.querySelector('button[title="Toggle sidebar"]').click();
    return true;
  })()`,
      "seed persistent shell identity",
      { signal },
    ),
    true,
  );

  const seenQueries = new Set(diagnostics.completed(() => true).map((record) => record.requestId));
  const ready = async (path, application, surface, sidebar = true) => {
    try {
      const coreContent =
        path === "/"
          ? "#organization-home-page"
          : path === `${root}/spacecraft`
            ? "#spacecraft-list-content"
            : path === `${root}/comms`
              ? "#comms-overview-content"
              : path === `${root}/ops/dashboards`
                ? "#dashboard-directory-feature"
                : null;
      if (coreContent) {
        await waitForExpression(
          client,
          `(() => {
          const probe = window.__cadenceNavigationProbe;
          const shell = document.querySelector('#application-shell');
          const header = document.querySelector('#host-page-heading');
          const title = header?.querySelector('h1');
          return location.pathname === ${JSON.stringify(path)} && probe?.shell === shell &&
            probe.phoenixNavigations === 0 && probe.liveRoot === shell?.closest('[data-phx-main]') &&
            ${sidebar ? "probe.sidebar === shell?.querySelector('[data-sidebar-collapsible]') &&" : ""}
            shell.querySelectorAll(${JSON.stringify(coreContent)}).length === 1 &&
            document.querySelectorAll('#cadence-federation-root').length === 0 &&
            header?.dataset.pageHeadingSource === 'application' && title?.textContent.trim() &&
            document.querySelectorAll('h1').length === 1 && getComputedStyle(title).fontSize === '24px';
        })()`,
          `persistent core host navigation to ${path}`,
          { signal },
        );
        return;
      }
      await waitForExpression(
        client,
        `(() => {
      const probe = window.__cadenceNavigationProbe;
      const shell = document.querySelector('#application-shell');
      const mount = document.querySelector('[data-remote-state="ready"]');
      if (document.querySelectorAll("#cadence-federation-root").length !== 1) return false;
      return location.pathname === ${JSON.stringify(path)} && probe?.shell === shell && probe.phoenixNavigations === 0 &&
        probe.liveRoot === shell?.closest('[data-phx-main]') &&
        ${sidebar ? "probe.sidebar === shell?.querySelector('[data-sidebar-collapsible]') &&" : ""}
        mount?.dataset.mountedApplication === ${JSON.stringify(application)} &&
        mount?.dataset.mountedSurface === ${JSON.stringify(surface)} &&
        !document.querySelector('#remote-error') && !document.querySelector('#phoenix-host-error');
    })()`,
        `persistent host navigation to ${path}`,
        { signal },
      );
      const query = await waitForResponse(
        diagnostics,
        (record) => {
          if (
            seenQueries.has(record.requestId) ||
            record.method !== "POST" ||
            !new URL(record.url).pathname.endsWith("/query")
          )
            return false;
          const body = JSON.parse(record.postData ?? "{}");
          return body.applicationKey === application && body.surfaceId === surface;
        },
        `${application} ${surface} navigation query`,
        { signal },
      );
      assert.equal(query.response.status, 200, "navigated screen query succeeds");
      seenQueries.add(query.requestId);
      await waitForExpression(
        client,
        `(() => {
          const header = document.querySelector('#host-page-heading');
          const title = header?.querySelector('h1');
          const body = document.querySelector('#host-page-content');
          return header?.dataset.pageHeadingSource === 'application' && title?.textContent.trim() && document.querySelectorAll('h1').length === 1 &&
            !body?.querySelector('h1') && header.querySelector('nav[aria-label="Breadcrumb"]') &&
            getComputedStyle(title).fontSize === '24px';
        })()`,
        "one host-owned page heading after the remote query",
        { signal },
      );
    } catch (error) {
      throw new Error(`${error.message}\n${diagnostics.describe()}`, { cause: error });
    }
  };
  const click = async (path) => {
    assert.equal(
      await evaluate(
        client,
        `(() => {
      const link = [...document.querySelectorAll('[data-sidebar-collapsible] a, #ops-nav-rail a')]
        .find(link => new URL(link.href).pathname === ${JSON.stringify(path)});
      if (!link) return false;
      link.click(); return true;
    })()`,
        `click host link ${path}`,
        { signal },
      ),
      true,
      `host link ${path} exists`,
    );
  };
  const expand = async (group) => {
    await evaluate(
      client,
      `(() => {
      const button = document.querySelector('button[aria-controls="mission-sidebar-${group}-content"]');
      if (button?.getAttribute('aria-expanded') === 'false') button.click();
    })()`,
      `expand ${group} navigation`,
      { signal },
    );
  };

  const managementReady = async () => {
    await waitForExpression(
      client,
      `(() => {
      const probe = window.__cadenceNavigationProbe;
      const shell = document.querySelector('#application-shell');
      return location.pathname === ${JSON.stringify(`${root}/applications`)} &&
        probe?.shell === shell && probe.phoenixNavigations === 0 && probe.liveRoot === shell?.closest('[data-phx-main]') &&
        probe.sidebar === shell?.querySelector('[data-sidebar-collapsible]') &&
        shell.querySelectorAll('#mission-applications-page').length === 1 &&
        document.querySelectorAll('#host-page-heading h1').length === 1 &&
        document.querySelectorAll('h1').length === 1 &&
        document.querySelectorAll('#cadence-federation-root').length === 0;
    })()`,
      "persistent application management page",
      { signal },
    );
  };

  await click(`${root}/applications`);
  await managementReady();
  await click(`${root}/spacecraft`);
  await ready(`${root}/spacecraft`, "spacecraft", "list");
  await evaluate(client, "history.back()", "back to application management", { signal });
  await managementReady();
  await evaluate(client, "history.forward()", "forward to spacecraft", { signal });
  await ready(`${root}/spacecraft`, "spacecraft", "list");
  reportProgress("Applications and Spacecraft share the shell through clicks and browser history");

  await click("/");
  await ready("/", "organization_admin", "organization_home");
  assert.equal(
    await evaluate(
      client,
      "document.querySelector('[data-sidebar-collapsible]')?.classList.contains('sidebar-collapsed')",
      "sidebar retains local collapsed state",
      { signal },
    ),
    true,
    "sidebar retains collapsed state after navigation",
  );
  await evaluate(client, "history.back()", "return to mission navigation", { signal });
  await ready(`${root}/spacecraft`, "spacecraft", "list");
  await evaluate(
    client,
    "document.querySelector('button[title=\"Toggle sidebar\"]').click()",
    "expand sidebar",
    { signal },
  );
  await expand("comms");
  await click(`${root}/comms`);
  await ready(`${root}/comms`, "comms", "overview");
  await evaluate(client, "history.back()", "host navigation back", { signal });
  await ready(`${root}/spacecraft`, "spacecraft", "list");
  await evaluate(client, "history.forward()", "host navigation forward", { signal });
  await ready(`${root}/comms`, "comms", "overview");
  await expand("ops");
  await click(`${root}/ops/dashboards`);
  await ready(`${root}/ops/dashboards`, "ops_console", "dashboard_directory", false);
  await diagnostics.drainLateEvents(300, signal);
  diagnostics.assertClean("persistent host navigation");
  reportProgress(
    "shell identity, sidebar state, feature navigation, and back/forward navigation retained",
  );
}

async function assertRepresentativeRemoteSurface({
  client,
  diagnostics,
  signal,
  args,
  argName,
  expectedPath,
  applicationKey,
  surfaceId,
  expectedScope,
  readyExpression,
  catalogPath,
  queryPath,
  queryId,
  expectedReleaseId,
  expectedOrigin,
  navigateSurface = true,
  existingGeneration,
}) {
  const url = requiredArg(args, argName);
  const target = assertHttpUrl(url, expectedOrigin, `${applicationKey} representative URL`);
  assert.equal(target.pathname, expectedPath, `${applicationKey} representative route changed`);

  return assertRemoteSurface({
    client,
    diagnostics,
    signal,
    url: target.href,
    expectedOrigin,
    catalogPath,
    applicationKey,
    surfaceId,
    expectedScope,
    readyExpression,
    queryPath,
    queryId,
    queryVersion: 1,
    expectedReleaseId,
    navigateSurface,
    existingGeneration,
  });
}

async function applyReleaseTransition(lifecycleUrl, transition, expectedReleaseIds) {
  const endpoint = assertHttpUrl(
    new URL(`/${transition}`, `${lifecycleUrl.replace(/\/$/, "")}/`).href,
    undefined,
    "release transition URL",
  );
  assert.equal(endpoint.hostname, "127.0.0.1", "release transition must stay on loopback");
  assert.equal(endpoint.pathname, `/${transition}`, "release transition path changed");
  const response = await fetch(endpoint.href, { method: "POST", cache: "no-store" });
  const bodyText = await response.text();
  assert.equal(response.status, 200, `${transition} coordinator response changed: ${bodyText}`);
  const body = JSON.parse(bodyText);
  const expectedTransition = transition === "promote" ? "promotion" : transition;
  assert.equal(body.transition, expectedTransition, `${transition} coordinator transition changed`);
  assert.deepEqual(
    body.releaseIds,
    expectedReleaseIds,
    `${transition} coordinator release IDs changed`,
  );
  return body;
}

export async function runScenario(client, diagnostics, args, { secret, signal } = {}) {
  assertNoPasswordArgument(args);
  const commsUrl = requiredArg(args, "--comms-url");
  const telemetryUrl = requiredArg(args, "--telemetry-url");
  const loginUrl = requiredArg(args, "--login-url");
  const email = requiredArg(args, "--login-email");
  const missionId = requiredArg(args, "--mission-id");
  const spacecraftId = requiredArg(args, "--spacecraft-id");
  const catalogRevisionId = requiredArg(args, "--catalog-revision-id");
  const sourceEndpointId = requiredArg(args, "--source-endpoint-id");
  const expectedApid = Number(requiredArg(args, "--expected-apid"));
  assert.equal(Number.isInteger(expectedApid), true, "--expected-apid must be an integer");
  assert.ok(secret?.password, "structured login secret is required");

  const origin = assertHttpUrl(commsUrl, undefined, "Comms surface URL").origin;
  assert.equal(
    new URL(commsUrl).pathname,
    `/missions/${encodeURIComponent(missionId)}/applications/comms/federated`,
    "Comms surface must use the authenticated federated route",
  );
  assertHttpUrl(telemetryUrl, origin, "Telemetry surface URL");
  assertSignInUrl(loginUrl, origin);
  const lifecycleUrl = requiredArg(args, "--federation-lifecycle-url");
  assertHttpUrl(lifecycleUrl, undefined, "federation lifecycle URL");
  const releases = {
    nMinus1: {
      comms: requiredArg(args, "--n-minus-1-comms-release-id"),
      telemetry_decom: requiredArg(args, "--n-minus-1-telemetry-release-id"),
      mission_catalog: requiredArg(args, "--n-minus-1-mission-catalog-release-id"),
      ops_console: requiredArg(args, "--n-minus-1-ops-console-release-id"),
      organization_admin: requiredArg(args, "--n-minus-1-organization-admin-release-id"),
      spacecraft: requiredArg(args, "--n-minus-1-spacecraft-release-id"),
    },
    n: {
      comms: requiredArg(args, "--n-comms-release-id"),
      telemetry_decom: requiredArg(args, "--n-telemetry-release-id"),
      mission_catalog: requiredArg(args, "--n-mission-catalog-release-id"),
      ops_console: requiredArg(args, "--n-ops-console-release-id"),
      organization_admin: requiredArg(args, "--n-organization-admin-release-id"),
      spacecraft: requiredArg(args, "--n-spacecraft-release-id"),
    },
  };
  for (const releaseIds of Object.values(releases)) {
    for (const [applicationKey, releaseId] of Object.entries(releaseIds)) {
      releaseArtifactPrefix(applicationKey, releaseId);
    }
  }

  const commsQueryPath = `/api/cadence/application-host/v1/missions/${encodeURIComponent(missionId)}/query`;
  const commsCatalogPath = `/api/cadence/application-host/v1/missions/${encodeURIComponent(missionId)}/catalog`;
  reportProgress("proving unauthenticated catalog cannot mount or act");
  await assertUnauthenticatedCatalogContained(
    client,
    diagnostics,
    `${origin}${commsCatalogPath}`,
    origin,
    signal,
  );
  diagnostics.assertClean("unauthenticated catalog containment");
  reportProgress("unauthenticated catalog containment observed");

  reportProgress("authenticating browser session");
  const authenticatedGeneration = await submitSignIn(
    client,
    loginUrl,
    email,
    secret.password,
    origin,
    diagnostics,
    signal,
  );
  reportProgress("authenticated browser session ready");
  await waitForExpression(
    client,
    "window.liveSocket?.isConnected() === true",
    "authenticated LiveView connection",
    { signal },
  );
  diagnostics.assertLiveViewWebSocket(origin, { generation: authenticatedGeneration });
  reportProgress("authenticated LiveView websocket asserted");

  const representativeConfigs = [
    {
      argName: "--organization-admin-url",
      expectedPath: "/applications/organization_admin/organization_home/federated",
      applicationKey: "organization_admin",
      surfaceId: "organization_home",
      expectedScope: "organization",
      readyExpression:
        "Boolean(document.querySelector('#organization-admin-application') && document.querySelector('#organization-home-destination') && !document.querySelector('#organization-admin-error') && !document.querySelector('#remote-error'))",
      catalogPath: "/api/cadence/application-host/v1/catalog",
      queryPath: "/api/cadence/application-host/v1/query",
      queryId: "cadence.organization.home",
      expectedReleaseId: releases.nMinus1.organization_admin,
      readPublishedHostBody: true,
    },
    {
      argName: "--mission-catalog-url",
      expectedPath: "/applications/mission_catalog/mission_list/federated",
      applicationKey: "mission_catalog",
      surfaceId: "mission_list",
      expectedScope: "organization",
      readyExpression:
        "Boolean(document.querySelector('#mission-catalog-application') && document.querySelector('#mission-list-table') && !document.querySelector('#mission-catalog-error') && !document.querySelector('#remote-error'))",
      catalogPath: "/api/cadence/application-host/v1/catalog",
      queryPath: "/api/cadence/application-host/v1/query",
      queryId: "cadence.mission_catalog.mission_list",
      expectedReleaseId: releases.nMinus1.mission_catalog,
    },
    {
      argName: "--ops-url",
      expectedPath: `/missions/${encodeURIComponent(missionId)}/applications/ops_console/dashboard_directory/federated`,
      applicationKey: "ops_console",
      surfaceId: "dashboard_directory",
      expectedScope: "mission",
      readyExpression:
        "Boolean(document.querySelector('#ops-console-application[data-ops-console-surface=\"dashboard_directory\"]') && document.querySelector('#ops-dashboards-page') && !document.querySelector('#ops-console-error') && !document.querySelector('#remote-error'))",
      catalogPath: `/api/cadence/application-host/v1/missions/${encodeURIComponent(missionId)}/catalog`,
      queryPath: `/api/cadence/application-host/v1/missions/${encodeURIComponent(missionId)}/query`,
      queryId: "cadence.ops.dashboard_directory",
      expectedReleaseId: releases.nMinus1.ops_console,
    },
    {
      argName: "--spacecraft-url",
      expectedPath: `/missions/${encodeURIComponent(missionId)}/applications/spacecraft/list/federated`,
      applicationKey: "spacecraft",
      surfaceId: "list",
      expectedScope: "mission",
      readyExpression:
        "Boolean(document.querySelector('#spacecraft-remote-application') && document.querySelector('#spacecraft-list-content') && !document.querySelector('#spacecraft-error') && !document.querySelector('#remote-error'))",
      catalogPath: `/api/cadence/application-host/v1/missions/${encodeURIComponent(missionId)}/catalog`,
      queryPath: `/api/cadence/application-host/v1/missions/${encodeURIComponent(missionId)}/query`,
      queryId: "cadence.spacecraft.list",
      expectedReleaseId: releases.nMinus1.spacecraft,
    },
  ];

  const representatives = [];
  for (const config of representativeConfigs) {
    representatives.push(
      await assertRepresentativeRemoteSurface({
        ...config,
        client,
        diagnostics,
        signal,
        args,
        expectedOrigin: origin,
      }),
    );
  }
  reportProgress("representative mission, ops, organization, and spacecraft remotes mounted");
  await assertMissionEntryNavigation(client, diagnostics, missionId, origin, signal);
  await assertPersistentHostNavigation(client, diagnostics, missionId, signal);

  const comms = await assertRemoteSurface({
    client,
    diagnostics,
    signal,
    url: commsUrl,
    expectedOrigin: origin,
    catalogPath: commsCatalogPath,
    applicationKey: "comms",
    surfaceId: "overview",
    expectedScope: "mission",
    readyExpression:
      "Boolean(document.querySelector('[data-remote-state=\"ready\"]') && document.querySelector('#comms-application') && document.querySelector('#comms-overview-page') && document.querySelector('#comms-transports') && !document.querySelector('#remote-error') && !document.querySelector('#comms-application-error'))",
    queryPath: commsQueryPath,
    queryId: "cadence.comms.overview",
    queryVersion: 1,
    expectedReleaseId: releases.nMinus1.comms,
  });
  assert.equal(
    comms.query.navigation.fallback_href,
    `/missions/${encodeURIComponent(missionId)}/comms`,
  );
  assert.equal(comms.query.trusted_surface.root.attrs.id, "comms-overview-page");
  assert.equal(comms.query.trusted_surface.overview.transport.id, "comms-transports");
  assert.equal(comms.query.trusted_surface.overview.transport.count, 1);

  reportProgress("verifying Comms Overview DOM and network contract");
  assert.equal(
    await evaluate(
      client,
      "document.querySelector('#comms-transports')?.textContent?.includes('Federation Browser Transport')",
      "Comms Overview transport",
      { signal },
    ),
    true,
  );

  reportProgress("proving manifest failure containment and immutable-release retry");
  await assertContainedRemoteFailureAndRetry({
    client,
    diagnostics,
    signal,
    url: commsUrl,
    expectedOrigin: origin,
    expectedReleaseId: releases.nMinus1.comms,
    readyExpression:
      "Boolean(document.querySelector('[data-remote-state=\"ready\"]') && document.querySelector('#comms-application') && document.querySelector('#comms-overview-page') && document.querySelector('#comms-transports') && !document.querySelector('#remote-error') && !document.querySelector('#comms-application-error'))",
  });
  reportProgress("manifest failure containment and immutable-release retry observed");

  const telemetryQueryPath = `/api/cadence/application-host/v1/missions/${encodeURIComponent(missionId)}/spacecraft/${encodeURIComponent(spacecraftId)}/query`;
  const csrfScriptId = await armNextActionCsrfRejection(client, signal);
  const telemetry = await assertRemoteSurface({
    client,
    diagnostics,
    signal,
    url: telemetryUrl,
    expectedOrigin: origin,
    catalogPath: `/api/cadence/application-host/v1/missions/${encodeURIComponent(missionId)}/spacecraft/${encodeURIComponent(spacecraftId)}/catalog`,
    applicationKey: "telemetry_decom",
    surfaceId: "packet_bindings",
    expectedScope: "spacecraft",
    readyExpression:
      "Boolean(document.querySelector('[data-remote-state=\"ready\"]') && document.querySelector('#telemetry-decom-application') && document.querySelector('#telemetry-packet-bindings-page') && document.querySelector('#packet-source-endpoint') && document.querySelector('#save-packet-bindings') && !document.querySelector('#remote-error') && !document.querySelector('#telemetry-decom-error'))",
    queryPath: telemetryQueryPath,
    queryId: "cadence.packet_bindings.manage",
    queryVersion: 1,
    expectedReleaseId: releases.nMinus1.telemetry_decom,
  });

  reportProgress("proving immutable manifest ETag revalidation");
  await assertConditionalEtagRevalidation(
    client,
    diagnostics,
    telemetry.manifestRecord,
    telemetry.manifestUrl,
    origin,
    { signal, generation: telemetry.generation, label: "Telemetry N-1 manifest" },
  );
  reportProgress("immutable manifest ETag revalidation observed");

  assert.equal(telemetry.query.host.application_key, "telemetry_decom");
  const packetDocument = telemetry.query.trusted_surface.data ?? telemetry.query.trusted_surface;
  assert.equal(packetDocument.contract_version, 1);
  assert.equal(packetDocument.configuration.catalog_revision_id, catalogRevisionId);
  assert.match(packetDocument.review_token, /^[a-f0-9]{64}$/);
  const packet = packetDocument.packets.items.find((item) => item.apid === expectedApid);
  assert.ok(packet, `telemetry query did not return APID ${expectedApid}`);
  const packetId = packet.id;
  assert.deepEqual(packetDocument.selection.ids, [packetId]);
  assert.ok(packetDocument.endpoints.items.some((endpoint) => endpoint.id === sourceEndpointId));
  assert.equal(
    await evaluate(
      client,
      `(() => {
      const select = document.querySelector('#packet-source-endpoint');
      if (!select || select.disabled) return false;
      select.value = ${JSON.stringify(sourceEndpointId)};
      select.dispatchEvent(new Event('change', {bubbles: true}));
      return select.value === ${JSON.stringify(sourceEndpointId)};
    })()`,
      "Telemetry source endpoint selection",
      { signal },
    ),
    true,
  );
  await waitForExpression(
    client,
    "document.querySelector('#save-packet-bindings')?.disabled === false",
    "reviewed packet selection ready to save",
    { signal },
  );

  const telemetryState = await evaluate(
    client,
    `(() => {
      const group = document.querySelector('[data-packet-id="${packetId}"]');
      const checkbox = group?.querySelector('input[type="checkbox"]');
      return {group: Boolean(group), checked: checkbox?.checked === true};
    })()`,
    "Telemetry packet group",
    { signal },
  );
  assert.deepEqual(telemetryState, { group: true, checked: true });

  const actionPath = `/api/cadence/application-host/v1/missions/${encodeURIComponent(missionId)}/spacecraft/${encodeURIComponent(spacecraftId)}/actions`;
  const csrfFailureCleanup = diagnostics.allowExpectedFailure((record) =>
    pathMatches(record, "POST", actionPath, origin),
  );
  let csrfFailureConfirmed = false;
  try {
    const csrfActionStartedAtMs = Date.now();
    reportProgress("submitting Telemetry action with a rejected CSRF token");
    const csrfClicked = await evaluate(
      client,
      "(() => { const button = document.querySelector('#save-packet-bindings'); if (!button || button.disabled) return false; button.click(); return true; })()",
      "Telemetry CSRF rejection submit",
      { signal },
    );
    assert.equal(csrfClicked, true);

    const csrfRecord = await waitForResponse(
      diagnostics,
      (record) =>
        pathMatches(record, "POST", actionPath, origin) &&
        record.startedAtMs >= csrfActionStartedAtMs,
      "Telemetry CSRF rejection action",
      { generation: telemetry.generation, signal },
    );
    assert.equal(csrfRecord.response.status, 403, "CSRF rejection did not stop the action");
    await removeNewDocumentScript(client, csrfScriptId, signal);

    const csrfActionRecords = diagnostics.completed(
      (record) => pathMatches(record, "POST", actionPath, origin),
      { generation: telemetry.generation },
    );
    assert.equal(csrfActionRecords.length, 1, "CSRF rejection replayed the mutation");

    const telemetryCatalogPath = `/api/cadence/application-host/v1/missions/${encodeURIComponent(missionId)}/spacecraft/${encodeURIComponent(spacecraftId)}/catalog`;
    const recoveryCatalogRecord = await waitForResponse(
      diagnostics,
      (record) =>
        pathMatches(record, "GET", telemetryCatalogPath, origin) &&
        record.startedAtMs >= csrfActionStartedAtMs,
      "bounded host rebootstrap catalog",
      { generation: telemetry.generation, signal },
    );
    assert.equal(recoveryCatalogRecord.response.status, 200);
    const recoveryCatalog = await responseJson(
      client,
      recoveryCatalogRecord,
      "bounded host rebootstrap catalog",
      { signal },
    );
    const recoveryApplication = assertCatalog(
      recoveryCatalog,
      "telemetry_decom",
      "packet_bindings",
      "spacecraft",
      origin,
      releases.nMinus1.telemetry_decom,
    );
    assert.equal(
      recoveryApplication.release.releaseId,
      telemetry.application.release.releaseId,
      "CSRF rebootstrap changed the approved release identity",
    );
    const recoveryCatalogRecords = diagnostics.completed(
      (record) =>
        pathMatches(record, "GET", telemetryCatalogPath, origin) &&
        record.startedAtMs >= csrfActionStartedAtMs,
      { generation: telemetry.generation },
    );
    assert.equal(
      recoveryCatalogRecords.length,
      1,
      "CSRF rejection triggered more than one rebootstrap",
    );
    telemetry.catalog = recoveryCatalog;
    telemetry.application = recoveryApplication;
    await waitForExpression(
      client,
      "Boolean(document.querySelector('#phoenix-host-action-stopped') && document.querySelector('#phoenix-host-action-stopped').textContent.includes('No automatic retry was attempted.') && document.querySelector('#telemetry-decom-application') && document.querySelector('#telemetry-packet-bindings-page'))",
      "sanitized stopped-action result and recovered host",
      { signal },
    );
    const stoppedAction = await evaluate(
      client,
      `(() => ({text: document.querySelector('#phoenix-host-action-stopped')?.textContent?.trim(), release: document.querySelector('[data-remote-state="ready"]')?.getAttribute('data-mounted-release') ?? null}))()`,
      "sanitized stopped-action state",
      { signal },
    );
    assert.match(stoppedAction.text || "", /No automatic retry was attempted\./);
    assert.match(stoppedAction.text || "", /Reference ID: [0-9a-f-]{36}/);
    assert.doesNotMatch(stoppedAction.text || "", /invalid-csrf|SECRET|token was invalid/i);
    assert.equal(stoppedAction.release, releases.nMinus1.telemetry_decom);
    await diagnostics.drainLateEvents(300, signal);
    assert.equal(
      diagnostics.completed((record) => pathMatches(record, "POST", actionPath, origin), {
        generation: telemetry.generation,
      }).length,
      1,
      "CSRF rejection produced a duplicate action after rebootstrap",
    );
    reportProgress("CSRF rejection produced one stopped action and one bounded rebootstrap");
    diagnostics.confirmExpectedFailure(csrfFailureCleanup, {
      requestId: csrfRecord.requestId,
      method: "POST",
      url: csrfRecord.url,
      generation: telemetry.generation,
      status: 403,
    });
    csrfFailureConfirmed = true;
    reportProgress("CSRF rejection authority confirmed and finalized");

    const queryRecordsBeforeAction = diagnostics.completed(
      (record) => pathMatches(record, "POST", telemetryQueryPath, origin),
      { generation: telemetry.generation },
    );
    const beforeRequestIds = new Set(queryRecordsBeforeAction.map((record) => record.requestId));
    const beforeCount = queryRecordsBeforeAction.length;
    const actionStartedAtMs = Date.now();

    await waitForExpression(
      client,
      "Boolean(document.querySelector('#packet-bindings-pending') && document.querySelector('#recover-packet-save')?.disabled === false && document.querySelector('#save-packet-bindings')?.disabled === true)",
      "unconfirmed save retained for explicit recovery",
      { signal },
    );
    reportProgress("explicitly recovering the same Telemetry packet-bindings save");
    const clicked = await evaluate(
      client,
      "(() => { const button = document.querySelector('#recover-packet-save'); if (!button || button.disabled) return false; button.click(); return true; })()",
      "Telemetry packet-bindings submit",
      { signal },
    );
    assert.equal(clicked, true);

    reportProgress("waiting for Telemetry packet-bindings action response");
    const actionRecord = await waitForResponse(
      diagnostics,
      (record) =>
        pathMatches(record, "POST", actionPath, origin) && record.startedAtMs >= actionStartedAtMs,
      "Telemetry packet-bindings action",
      { generation: telemetry.generation, signal },
    );
    reportProgress("Telemetry packet-bindings action response observed");
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
        params: {
          catalog_revision_id: catalogRevisionId,
          expected_review: packetDocument.review_token,
          expected_configuration_version: packetDocument.configuration.version,
          input_id: "telemetry-fields",
          input_version: 1,
          selected_packet_ids: [packetId],
          source_endpoint_ref: sourceEndpointId,
        },
        scope: {
          organizationId: telemetryScope.organizationId,
          missionId: telemetryScope.missionId,
          spacecraftId: telemetryScope.spacecraftId,
        },
      },
    });
    assert.equal(
      requestHeader(actionRecord, "idempotency-key"),
      requestHeader(csrfRecord, "idempotency-key"),
      "explicit recovery changed the save identity",
    );
    assert.deepEqual(
      parseRequestBody(actionRecord, "recovered save").params,
      parseRequestBody(csrfRecord, "stopped save").params,
      "recovery changed the reviewed intent",
    );
    const receipt = await responseJson(client, actionRecord, "Telemetry packet-bindings action", {
      signal,
    });
    assert.match(receipt.receiptId, /^application-host-receipt-/);
    assert.equal(receipt.result.applicationKey, "telemetry_decom");
    assert.deepEqual(receipt.result.selectedPacketIds, [packetId]);

    reportProgress("waiting for Telemetry canonical query refresh");
    const refreshedQueryRecord = await waitForResponse(
      diagnostics,
      (record) =>
        pathMatches(record, "POST", telemetryQueryPath, origin) &&
        !beforeRequestIds.has(record.requestId) &&
        record.startedAtMs >= actionStartedAtMs,
      "Telemetry canonical query refresh",
      { generation: telemetry.generation, signal },
    );
    reportProgress("Telemetry canonical query refresh observed");
    assert.equal(
      requirePostActionRefresh(
        diagnostics.completed(() => true, { generation: telemetry.generation }),
        {
          beforeRequestIds,
          beforeCount,
          actionStartedAtMs,
          pathname: telemetryQueryPath,
          origin,
          label: "Telemetry packet-bindings action",
        },
      ).requestId,
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
    const refreshedQuery = await responseJson(
      client,
      refreshedQueryRecord,
      "Telemetry refreshed query",
      { signal },
    );
    const refreshedDocument = refreshedQuery.trusted_surface.data ?? refreshedQuery.trusted_surface;
    assert.deepEqual(refreshedDocument.selection.ids, [packetId]);
    assert.equal(refreshedDocument.selection.endpoint.id, sourceEndpointId);
    assert.equal(refreshedDocument.configuration.version, receipt.result.configurationVersion);
    assert.notEqual(refreshedDocument.review_token, packetDocument.review_token);

    await waitForExpression(
      client,
      "Boolean(document.querySelector('#packet-save-receipt') && !document.querySelector('#packet-bindings-pending'))",
      "Telemetry canonical refresh notice",
      { signal },
    );
    reportProgress("Telemetry canonical refresh notice observed");
    assert.equal(
      await evaluate(
        client,
        `document.querySelector('[data-packet-id="${packetId}"] input[type="checkbox"]')?.checked === true`,
        "Telemetry retained selection",
        { signal },
      ),
      true,
    );

    reportProgress("promoting signed federation generation N");
    await applyReleaseTransition(`${lifecycleUrl}/`, "promote", releases.n);
    const promotedComms = await assertRemoteSurface({
      client,
      diagnostics,
      signal,
      url: commsUrl,
      expectedOrigin: origin,
      catalogPath: `/api/cadence/application-host/v1/missions/${encodeURIComponent(missionId)}/catalog`,
      applicationKey: "comms",
      surfaceId: "overview",
      expectedScope: "mission",
      readyExpression:
        "Boolean(document.querySelector('[data-remote-state=\"ready\"]') && document.querySelector('#comms-application') && document.querySelector('#comms-overview-page') && document.querySelector('#comms-transports') && !document.querySelector('#remote-error') && !document.querySelector('#comms-application-error'))",
      queryPath: commsQueryPath,
      queryId: "cadence.comms.overview",
      queryVersion: 1,
      expectedReleaseId: releases.n.comms,
    });
    const promotedTelemetry = await assertRemoteSurface({
      client,
      diagnostics,
      signal,
      url: telemetryUrl,
      expectedOrigin: origin,
      catalogPath: `/api/cadence/application-host/v1/missions/${encodeURIComponent(missionId)}/spacecraft/${encodeURIComponent(spacecraftId)}/catalog`,
      applicationKey: "telemetry_decom",
      surfaceId: "packet_bindings",
      expectedScope: "spacecraft",
      readyExpression:
        "Boolean(document.querySelector('[data-remote-state=\"ready\"]') && document.querySelector('#telemetry-decom-application') && document.querySelector('#telemetry-packet-bindings-page') && document.querySelector('#packet-source-endpoint') && document.querySelector('#save-packet-bindings') && !document.querySelector('#remote-error') && !document.querySelector('#telemetry-decom-error'))",
      queryPath: telemetryQueryPath,
      queryId: "cadence.packet_bindings.manage",
      queryVersion: 1,
      expectedReleaseId: releases.n.telemetry_decom,
    });
    for (const config of representativeConfigs) {
      await assertRepresentativeRemoteSurface({
        ...config,
        client,
        diagnostics,
        signal,
        args,
        expectedOrigin: origin,
        expectedReleaseId: releases.n[config.applicationKey],
        navigateSurface: true,
      });
    }
    assertNoReleaseArtifactRequests(
      diagnostics.completed(() => true, { generation: promotedTelemetry.generation }),
      [
        { applicationKey: "comms", releaseId: releases.nMinus1.comms },
        { applicationKey: "telemetry_decom", releaseId: releases.nMinus1.telemetry_decom },
        { applicationKey: "mission_catalog", releaseId: releases.nMinus1.mission_catalog },
        { applicationKey: "ops_console", releaseId: releases.nMinus1.ops_console },
        { applicationKey: "organization_admin", releaseId: releases.nMinus1.organization_admin },
        { applicationKey: "spacecraft", releaseId: releases.nMinus1.spacecraft },
      ],
      "generation N reload",
    );
    reportProgress("generation N catalog, manifest, and runtime identities observed");

    reportProgress("rolling back signed federation generation N-1");
    await applyReleaseTransition(`${lifecycleUrl}/`, "rollback", releases.nMinus1);
    const rolledBackComms = await assertRemoteSurface({
      client,
      diagnostics,
      signal,
      url: commsUrl,
      expectedOrigin: origin,
      catalogPath: `/api/cadence/application-host/v1/missions/${encodeURIComponent(missionId)}/catalog`,
      applicationKey: "comms",
      surfaceId: "overview",
      expectedScope: "mission",
      readyExpression:
        "Boolean(document.querySelector('[data-remote-state=\"ready\"]') && document.querySelector('#comms-application') && document.querySelector('#comms-overview-page') && document.querySelector('#comms-transports') && !document.querySelector('#remote-error') && !document.querySelector('#comms-application-error'))",
      queryPath: commsQueryPath,
      queryId: "cadence.comms.overview",
      queryVersion: 1,
      expectedReleaseId: releases.nMinus1.comms,
    });
    const rolledBackTelemetry = await assertRemoteSurface({
      client,
      diagnostics,
      signal,
      url: telemetryUrl,
      expectedOrigin: origin,
      catalogPath: `/api/cadence/application-host/v1/missions/${encodeURIComponent(missionId)}/spacecraft/${encodeURIComponent(spacecraftId)}/catalog`,
      applicationKey: "telemetry_decom",
      surfaceId: "packet_bindings",
      expectedScope: "spacecraft",
      readyExpression:
        "Boolean(document.querySelector('[data-remote-state=\"ready\"]') && document.querySelector('#telemetry-decom-application') && document.querySelector('#telemetry-packet-bindings-page') && document.querySelector('#packet-source-endpoint') && document.querySelector('#save-packet-bindings') && !document.querySelector('#remote-error') && !document.querySelector('#telemetry-decom-error'))",
      queryPath: telemetryQueryPath,
      queryId: "cadence.packet_bindings.manage",
      queryVersion: 1,
      expectedReleaseId: releases.nMinus1.telemetry_decom,
    });
    for (const config of representativeConfigs) {
      await assertRepresentativeRemoteSurface({
        ...config,
        client,
        diagnostics,
        signal,
        args,
        expectedOrigin: origin,
        expectedReleaseId: releases.nMinus1[config.applicationKey],
        navigateSurface: true,
      });
    }
    assertNoReleaseArtifactRequests(
      diagnostics.completed(() => true, { generation: rolledBackTelemetry.generation }),
      [
        { applicationKey: "comms", releaseId: releases.n.comms },
        { applicationKey: "telemetry_decom", releaseId: releases.n.telemetry_decom },
        { applicationKey: "mission_catalog", releaseId: releases.n.mission_catalog },
        { applicationKey: "ops_console", releaseId: releases.n.ops_console },
        { applicationKey: "organization_admin", releaseId: releases.n.organization_admin },
        { applicationKey: "spacecraft", releaseId: releases.n.spacecraft },
      ],
      "generation N-1 rollback",
    );
    assertImmutableReleaseCacheReuse(
      diagnostics.completed(() => true, { generation: rolledBackTelemetry.generation }),
      [
        { applicationKey: "comms", releaseId: releases.nMinus1.comms },
        { applicationKey: "telemetry_decom", releaseId: releases.nMinus1.telemetry_decom },
        { applicationKey: "mission_catalog", releaseId: releases.nMinus1.mission_catalog },
        { applicationKey: "ops_console", releaseId: releases.nMinus1.ops_console },
        { applicationKey: "organization_admin", releaseId: releases.nMinus1.organization_admin },
        { applicationKey: "spacecraft", releaseId: releases.nMinus1.spacecraft },
      ],
      "generation N-1 rollback",
    );
    reportProgress("generation N-1 rollback identities and cache reuse observed");

    reportProgress("draining late browser events");
    await diagnostics.drainLateEvents(250, signal);
    reportProgress("late browser events drained");
    diagnostics.assertClean("federation browser gate");
    const result = {
      origin,
      remotes: [
        comms.application.release.releaseId,
        telemetry.application.release.releaseId,
        promotedComms.application.release.releaseId,
        promotedTelemetry.application.release.releaseId,
        rolledBackComms.application.release.releaseId,
        rolledBackTelemetry.application.release.releaseId,
      ],
      queryResponses: diagnostics.completed(
        (record) => pathMatches(record, "POST", telemetryQueryPath, origin),
        { generation: telemetry.generation },
      ).length,
      actionReceipt: receipt.receiptId,
      retainedPacketId: packetId,
    };
    return result;
  } finally {
    if (!csrfFailureConfirmed) csrfFailureCleanup();
  }
}

export async function readStructuredLoginSecret({
  stream = process.stdin,
  signal,
  timeout = 5_000,
} = {}) {
  let cancelReader = () => {};
  const reader = new Promise((resolveSecret, rejectSecret) => {
    let buffer = "";
    let finished = false;
    const finish = (callback, value) => {
      if (finished) return;
      finished = true;
      stream.removeListener("data", onData);
      stream.removeListener("end", onEnd);
      stream.removeListener("error", onError);
      try {
        stream.pause?.();
      } catch {
        // The input may already be closed while cancellation is cleaning it up.
      }
      try {
        stream.unref?.();
      } catch {
        // Some imported test streams do not expose an unref operation.
      }
      callback(value);
    };
    cancelReader = (error) => finish(rejectSecret, error);
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
      if (buffer.length > 64 * 1024)
        finish(rejectSecret, new Error("structured login secret is too large"));
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
  });

  return raceWithSignalAndTimeout(reader, {
    signal,
    milliseconds: timeout,
    label: "structured login secret",
    onCancel: cancelReader,
  });
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
  const onSignal = (signal) =>
    abort(
      new Error(`browser gate received ${signal}`),
      signal === "SIGINT" ? 130 : 128 + (signal === "SIGTERM" ? 15 : 1),
    );
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
    if (initialParentPid !== 1 && process.ppid === 1)
      abort(new Error("browser gate parent process disappeared"));
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
      for (const [signal, handler] of Object.entries(signalHandlers))
        process.removeListener(signal, handler);
      process.stdout.removeListener("error", onPipeError);
      process.stderr.removeListener("error", onPipeError);
    },
  };
}

function conversionFailure(path, reason) {
  throw new Error(`${path} ${reason}`);
}

function descriptorsBeforeRead(value, path) {
  let keys;
  try {
    keys = Reflect.ownKeys(value);
  } catch (error) {
    conversionFailure(path, `could not enumerate own keys: ${error.message}`);
  }

  const descriptors = new Map();
  for (const key of keys) {
    let descriptor;
    try {
      descriptor = Object.getOwnPropertyDescriptor(value, key);
    } catch (error) {
      conversionFailure(path, `could not inspect ${String(key)}: ${error.message}`);
    }
    if (!descriptor) conversionFailure(path, `lost own descriptor for ${String(key)}`);
    if (!Object.hasOwn(descriptor, "value")) {
      conversionFailure(path, `${String(key)} was an accessor`);
    }
    descriptors.set(key, descriptor);
  }
  return { keys, descriptors };
}

function arrayIndexKey(key) {
  if (typeof key !== "string" || key === "") return false;
  if (key !== "0" && (key[0] === "0" || !/^\d+$/.test(key))) return false;
  const index = Number(key);
  return Number.isSafeInteger(index) && index >= 0 && index < 2 ** 32 - 1 && String(index) === key;
}

export function toOrdinarySerializableResult(value, path = "result") {
  if (value === null || typeof value === "string" || typeof value === "boolean") return value;
  if (typeof value === "number") return Number.isFinite(value) ? value : null;
  if (value === undefined) conversionFailure(path, "was not serializable");
  if (typeof value !== "object") conversionFailure(path, "contained a non-serializable capability");
  if (nodeTypes.isProxy(value)) conversionFailure(path, "was a proxy");

  if (Array.isArray(value)) {
    let prototype;
    try {
      prototype = Object.getPrototypeOf(value);
    } catch (error) {
      conversionFailure(path, `prototype inspection failed: ${error.message}`);
    }
    if (prototype !== Array.prototype) conversionFailure(path, "was not an ordinary array");
    if (unsafeThenDescriptor(value))
      conversionFailure(path, "was thenable or exposed an unsafe then property");

    const { keys, descriptors } = descriptorsBeforeRead(value, path);
    const lengthDescriptor = descriptors.get("length");
    if (
      !lengthDescriptor ||
      !Number.isInteger(lengthDescriptor.value) ||
      lengthDescriptor.value < 0
    ) {
      conversionFailure(path, "had an invalid array length");
    }
    const length = lengthDescriptor.value;
    for (const key of keys) {
      if (typeof key === "symbol") conversionFailure(path, "contained an own symbol");
      if (key !== "length" && (!arrayIndexKey(key) || Number(key) >= length)) {
        conversionFailure(path, `contained an extra own key ${key}`);
      }
    }
    for (let index = 0; index < length; index += 1) {
      if (!descriptors.has(String(index))) conversionFailure(`${path}[${index}]`, "was a hole");
    }

    const ordinaryResult = new Array(length);
    for (let index = 0; index < length; index += 1) {
      const descriptor = descriptors.get(String(index));
      const converted =
        descriptor.value === undefined
          ? null
          : toOrdinarySerializableResult(descriptor.value, `${path}[${index}]`);
      Object.defineProperty(ordinaryResult, String(index), {
        value: converted,
        enumerable: true,
        configurable: true,
        writable: true,
      });
    }
    return ordinaryResult;
  }

  let prototype;
  try {
    prototype = Object.getPrototypeOf(value);
  } catch (error) {
    conversionFailure(path, `prototype inspection failed: ${error.message}`);
  }
  if (prototype !== Object.prototype && prototype !== null) {
    conversionFailure(path, "was not an ordinary object");
  }
  if (unsafeThenDescriptor(value))
    conversionFailure(path, "was thenable or exposed an unsafe then property");

  const { keys, descriptors } = descriptorsBeforeRead(value, path);
  const ordinaryResult = {};
  for (const key of keys) {
    if (typeof key !== "string" || !descriptors.get(key).enumerable) continue;
    const descriptor = descriptors.get(key);
    if (descriptor.value === undefined) continue;
    Object.defineProperty(ordinaryResult, key, {
      value: toOrdinarySerializableResult(descriptor.value, `${path}.${key}`),
      enumerable: true,
      configurable: true,
      writable: true,
    });
  }
  return ordinaryResult;
}

export async function runBrowserGate(
  args = process.argv.slice(2),
  {
    env = process.env,
    launchChromeImpl = launchChrome,
    createPageImpl = createPage,
    closePageImpl = closePage,
    createClientImpl = (endpoint) => new CdpClient(endpoint),
    runScenarioImpl = runScenario,
    originUrl,
    clientCreationTimeout = CDP_COMMAND_TIMEOUT_MS,
  } = {},
) {
  assertNoPasswordArgument(args);
  const controller = new AbortController();
  const state = {
    runtime: null,
    runtimeClose: null,
    runtimeEndpoint: undefined,
    client: null,
    clientClose: null,
    page: null,
    pageId: undefined,
    pageEndpoint: undefined,
  };
  const cleanupPromises = new Map();
  let cleanupStarted = false;
  const runOwnedCleanup = (key, operation, label, timeout = CDP_COMMAND_TIMEOUT_MS) => {
    if (cleanupPromises.has(key)) return cleanupPromises.get(key);
    if (typeof operation !== "function") return undefined;
    const promise = raceWithSignalAndTimeout(invokeValidated(operation, label), {
      milliseconds: timeout,
      label,
    });
    cleanupPromises.set(key, promise);
    promise.catch(() => {});
    return promise;
  };
  const triggerOwnedCleanup = (
    key,
    operation,
    label,
    timeout = CDP_COMMAND_TIMEOUT_MS,
    onFailure,
  ) => {
    const cleanup = runOwnedCleanup(key, operation, label, timeout);
    cleanup?.catch((error) => {
      if (!onFailure) return;
      try {
        onFailure(error);
      } catch {
        // Failure observation must not create a second unhandled rejection.
      }
    });
  };
  const secrets = [];
  const LATE_FAILURE_DIAGNOSTIC_LIMIT = 4096;
  const formatBoundedFailure = (error) => {
    let safeMessage;
    try {
      safeMessage = redactError(error, secrets);
    } catch {
      safeMessage = "failure could not be formatted";
    }
    const boundedMessage =
      safeMessage.length > LATE_FAILURE_DIAGNOSTIC_LIMIT
        ? `${safeMessage.slice(0, LATE_FAILURE_DIAGNOSTIC_LIMIT)}...`
        : safeMessage;
    return boundedMessage;
  };
  const reportLateFailure = (resource, kind, error) => {
    const boundedMessage = formatBoundedFailure(error);
    reportProgress(`late ${resource} ${kind} observed after gate failure: ${boundedMessage}`);
  };
  const runtimeCleanupKeys = new Map();
  const pageCleanupKeys = new Map();
  let runtimeCleanupSequence = 0;
  let pageCleanupSequence = 0;
  const triggerRuntimeCleanup = (
    runtime = state.runtime,
    close = state.runtimeClose,
    key = "runtime",
    kind = "cleanup failure",
  ) => {
    if (typeof close !== "function") return;
    triggerOwnedCleanup(
      key,
      () => Reflect.apply(close, runtime, []),
      "Chrome runtime cleanup",
      CDP_COMMAND_TIMEOUT_MS,
      (error) => reportLateFailure("Chrome runtime", kind, error),
    );
  };
  const triggerPageCleanup = (
    endpoint = state.pageEndpoint,
    targetId = state.pageId,
    key = "page",
    kind = "cleanup failure",
  ) => {
    if (!endpoint || !targetId) return;
    triggerOwnedCleanup(
      key,
      () => closePageImpl(endpoint, targetId, { timeout: PAGE_CLOSE_CLEANUP_TIMEOUT_MS }),
      "CDP page close",
      PAGE_CLOSE_CLEANUP_TIMEOUT_MS,
      (error) => reportLateFailure("browser page", kind, error),
    );
  };
  let diagnostics;
  let diagnosticsDispose;
  const guards = installShutdownGuards({
    onAbort: (reason) => {
      controller.abort(reason);
      if (state.pageEndpoint && state.pageId) {
        triggerPageCleanup(state.pageEndpoint, state.pageId, "page", "cleanup failure");
      }
      if (state.clientClose) {
        triggerOwnedCleanup(
          "client",
          () => Reflect.apply(state.clientClose, state.client, []),
          "CDP client cleanup",
          CDP_COMMAND_TIMEOUT_MS,
          (error) => reportLateFailure("CDP client", "cleanup failure", error),
        );
      }
      if (state.runtimeClose) {
        triggerRuntimeCleanup(state.runtime, state.runtimeClose, "runtime", "cleanup failure");
      }
    },
  });
  let runError;

  try {
    const secret = argValue(args, "--login-email")
      ? await readStructuredLoginSecret({ signal: controller.signal })
      : null;
    if (secret) secrets.push(secret.password);

    reportProgress("launching bounded Chrome process");
    const closeDuplicateRuntime = (runtime) => {
      let close;
      try {
        close = safeCallableProperty(runtime, "close", "Chrome runtime");
      } catch (error) {
        reportLateFailure("Chrome runtime", "duplicate capture failure", error);
        return state.runtime;
      }
      let key = runtimeCleanupKeys.get(runtime);
      if (!key) {
        key = `runtime-duplicate-${runtimeCleanupSequence++}`;
        runtimeCleanupKeys.set(runtime, key);
      }
      triggerRuntimeCleanup(runtime, close, key, "duplicate cleanup failure");
      return state.runtime;
    };
    const captureRuntime = (runtime) => {
      validateRaceValue(runtime, "launchChrome implementation");
      if (state.runtime && runtime !== state.runtime) return closeDuplicateRuntime(runtime);
      if (!state.runtime) {
        const runtimeClose = safeCallableProperty(runtime, "close", "Chrome runtime");
        state.runtime = runtime;
        state.runtimeClose = runtimeClose;
      }
      state.runtimeEndpoint = safeDataProperty(runtime, "endpoint", "Chrome runtime");
      if ((controller.signal.aborted || cleanupStarted) && state.runtimeClose) {
        triggerRuntimeCleanup(state.runtime, state.runtimeClose, "runtime", "late cleanup failure");
      }
      return state.runtime;
    };
    const captureRuntimeFromCallback = (runtime) => {
      try {
        return captureRuntime(runtime);
      } catch (error) {
        if (state.runtimeClose) {
          triggerRuntimeCleanup(state.runtime, state.runtimeClose, "runtime", "capture failure");
        }
        if (!controller.signal.aborted && !cleanupStarted) controller.abort(error);
        reportLateFailure("Chrome runtime", "capture failure", error);
        return undefined;
      }
    };
    const launchAuthority = acquisitionAuthority(
      invokeValidated(
        () =>
          launchChromeImpl({
            env,
            signal: controller.signal,
            onRuntime: captureRuntimeFromCallback,
          }),
        "launchChrome implementation",
      ),
      captureRuntime,
    );
    launchAuthority.catch((error) => {
      if (controller.signal.aborted && !state.runtime) {
        reportLateFailure("Chrome runtime", "creation rejection", error);
      }
    });
    await raceWithSignalAndTimeout(launchAuthority, {
      signal: controller.signal,
      milliseconds: CDP_COMMAND_TIMEOUT_MS,
      label: "launchChrome implementation",
    });
    reportProgress("creating browser target");
    let pageWebSocketDebuggerUrl;
    const closeDuplicatePage = (target) => {
      let targetId;
      try {
        targetId = safeOptionalDataProperty(target, "id", "browser page");
      } catch (error) {
        reportLateFailure("browser page", "duplicate capture failure", error);
        return state.page;
      }
      if (!targetId) {
        reportLateFailure(
          "browser page",
          "duplicate capture failure",
          new Error("duplicate browser page did not expose an id"),
        );
        return state.page;
      }
      let key = pageCleanupKeys.get(target);
      if (!key) {
        key = `page-duplicate-${pageCleanupSequence++}`;
        pageCleanupKeys.set(target, key);
      }
      triggerPageCleanup(state.runtimeEndpoint, targetId, key, "duplicate cleanup failure");
      return state.page;
    };
    const capturePageTarget = (target) => {
      validateRaceValue(target, "createPage implementation");
      if (state.page && target !== state.page) return closeDuplicatePage(target);
      if (!state.page) {
        const targetId = safeOptionalDataProperty(target, "id", "browser page");
        if (targetId !== undefined && typeof targetId !== "string") {
          throw new TypeError("browser page id was not a string");
        }
        state.page = target;
        state.pageId = targetId;
        state.pageEndpoint = state.runtimeEndpoint;
      }
      try {
        pageWebSocketDebuggerUrl = safeDataProperty(target, "webSocketDebuggerUrl", "browser page");
      } catch (error) {
        if ((controller.signal.aborted || cleanupStarted) && state.pageEndpoint && state.pageId) {
          triggerPageCleanup(state.pageEndpoint, state.pageId, "page", "capture failure");
        }
        throw error;
      }
      if ((controller.signal.aborted || cleanupStarted) && state.pageEndpoint && state.pageId) {
        triggerPageCleanup(state.pageEndpoint, state.pageId, "page", "late cleanup failure");
      }
      return target;
    };
    const pageAuthority = acquisitionAuthority(
      invokeValidated(
        () => createPageImpl(state.runtimeEndpoint, "about:blank", { signal: controller.signal }),
        "createPage implementation",
      ),
      capturePageTarget,
    );
    pageAuthority.catch((error) => {
      if (controller.signal.aborted && !state.page) {
        reportLateFailure("browser page", "creation rejection", error);
      }
    });
    await raceWithSignalAndTimeout(pageAuthority, {
      signal: controller.signal,
      milliseconds: CDP_COMMAND_TIMEOUT_MS,
      label: "createPage implementation",
      onTimeout: (error) => controller.abort(error),
    });

    let clientTarget;
    let clientSend;
    const captureClientTarget = (target) => {
      validateRaceValue(target, "createClient implementation");
      const clientClose = safeCallableProperty(target, "close", "CDP client");
      clientTarget = target;
      state.client = target;
      state.clientClose = () => Reflect.apply(clientClose, target, []);

      if (controller.signal.aborted || cleanupStarted) {
        triggerOwnedCleanup(
          "client",
          () => Reflect.apply(state.clientClose, state.client, []),
          "CDP client cleanup",
          CDP_COMMAND_TIMEOUT_MS,
          (error) => reportLateFailure("CDP client", "cleanup failure", error),
        );
        return target;
      }

      const clientOn = safeCallableProperty(target, "on", "CDP client");
      clientSend = safeCallableProperty(target, "send", "CDP client");
      const clientWaitForEvent = safeOptionalCallableProperty(target, "waitForEvent", "CDP client");
      const clientEmit = safeOptionalCallableProperty(target, "emit", "CDP client");
      const client = {
        on(...parameters) {
          return Reflect.apply(clientOn, target, parameters);
        },
        send(...parameters) {
          return invokeValidated(
            () => Reflect.apply(clientSend, target, parameters),
            `CDP ${parameters[0] || "client"}`,
          );
        },
        close(...parameters) {
          return Reflect.apply(clientClose, target, parameters);
        },
      };
      if (clientWaitForEvent) {
        client.waitForEvent = (...parameters) =>
          invokeValidated(
            () => Reflect.apply(clientWaitForEvent, target, parameters),
            `CDP ${parameters[0] || "event"}`,
          );
      }
      if (clientEmit) {
        client.emit = (...parameters) => Reflect.apply(clientEmit, target, parameters);
      }
      state.client = client;
      return target;
    };
    const clientCreation = invokeValidated(
      () => createClientImpl(pageWebSocketDebuggerUrl),
      "createClient implementation",
    );
    const clientCreationAuthority = acquisitionAuthority(clientCreation, captureClientTarget);
    clientCreationAuthority.catch((error) => {
      if ((controller.signal.aborted || cleanupStarted) && !state.client) {
        reportLateFailure("CDP client", "creation rejection", error);
      }
    });
    await raceWithSignalAndTimeout(clientCreationAuthority, {
      signal: controller.signal,
      milliseconds: clientCreationTimeout,
      label: "createClient implementation",
      onTimeout: (error) => controller.abort(error),
    });
    const sendCommand = (method, parameters) =>
      raceWithSignalAndTimeout(
        invokeValidated(
          () =>
            Reflect.apply(clientSend, clientTarget, [
              method,
              parameters,
              CDP_COMMAND_TIMEOUT_MS,
              controller.signal,
            ]),
          `CDP ${method}`,
        ),
        {
          signal: controller.signal,
          milliseconds: CDP_COMMAND_TIMEOUT_MS,
          label: `CDP ${method}`,
        },
      );
    await sendCommand("Page.enable", {});
    await sendCommand("Page.setLifecycleEventsEnabled", { enabled: true });
    await sendCommand("Runtime.enable", {});
    await sendCommand("Network.enable", {});
    await sendCommand("Log.enable", {});
    await sendCommand("Emulation.setDeviceMetricsOverride", {
      width: 1440,
      height: 1000,
      deviceScaleFactor: 1,
      mobile: false,
    });

    const diagnosticUrl = originUrl ?? requiredArg(args, "--comms-url");
    diagnostics = installDiagnostics(state.client, {
      expectedOrigin: new URL(diagnosticUrl).origin,
      secrets,
    });
    const diagnosticsRevoke = diagnostics.revokeUnconfirmedExpectedFailures;
    const diagnosticsDrain = diagnostics.drainLateEvents;
    const diagnosticsAssertClean = diagnostics.assertClean;
    diagnosticsDispose = diagnostics.dispose;
    const timeout = Number(argValue(args, "--scenario-timeout-ms") || SCENARIO_TIMEOUT_MS);
    assert.ok(Number.isFinite(timeout) && timeout > 0, "--scenario-timeout-ms must be positive");
    const scenario = invokeValidated(
      () => runScenarioImpl(state.client, diagnostics, args, { secret, signal: controller.signal }),
      "runScenario implementation",
    );
    const result = await raceWithSignalAndTimeout(scenario, {
      signal: controller.signal,
      milliseconds: timeout,
      label: "federation browser scenario",
      onTimeout: (error) => {
        reportProgress(`federation browser scenario timeout after ${timeout}ms`);
        controller.abort(error);
      },
    });
    reportProgress("federation browser scenario settled successfully");
    Reflect.apply(diagnosticsRevoke, diagnostics, ["browser gate final assertion"]);
    await raceWithSignalAndTimeout(
      invokeValidated(
        () => Reflect.apply(diagnosticsDrain, diagnostics, [250, controller.signal]),
        "diagnostics late-event drain",
      ),
      {
        signal: controller.signal,
        milliseconds: CDP_COMMAND_TIMEOUT_MS,
        label: "diagnostics late-event drain",
      },
    );
    Reflect.apply(diagnosticsAssertClean, diagnostics, ["federation browser gate final"]);
    const publicResult = toOrdinarySerializableResult(result);
    reportProgress("browser gate returning successfully");
    return publicResult;
  } catch (error) {
    let safeMessage;
    try {
      safeMessage = redactError(error, secrets);
    } catch {
      safeMessage = "browser gate failed and its error could not be formatted";
    }
    const safe = new Error(safeMessage);
    safe.exitCode = guards.exitCode;
    runError = safe;
    reportProgress("browser gate throwing after run failure");
    throw safe;
  } finally {
    cleanupStarted = true;
    reportProgress("cleaning up browser process and profile");
    const cleanupErrors = [];

    try {
      guards.dispose();
    } catch (error) {
      cleanupErrors.push(error);
    }
    try {
      if (diagnosticsDispose) {
        await runOwnedCleanup(
          "diagnostics",
          () => Reflect.apply(diagnosticsDispose, diagnostics, []),
          "diagnostics cleanup",
        );
      }
    } catch (error) {
      cleanupErrors.push(error);
    }
    try {
      if (state.pageEndpoint && state.pageId) {
        await runOwnedCleanup(
          "page",
          () =>
            closePageImpl(state.pageEndpoint, state.pageId, {
              timeout: PAGE_CLOSE_CLEANUP_TIMEOUT_MS,
            }),
          "CDP page close",
          PAGE_CLOSE_CLEANUP_TIMEOUT_MS,
        );
        reportProgress("browser target close complete");
      }
    } catch (error) {
      cleanupErrors.push(error);
    }
    try {
      if (state.clientClose) {
        await runOwnedCleanup(
          "client",
          () => Reflect.apply(state.clientClose, state.client, []),
          "CDP client cleanup",
        );
      }
    } catch (error) {
      cleanupErrors.push(error);
    }
    try {
      if (state.runtimeClose) {
        await runOwnedCleanup(
          "runtime",
          () => Reflect.apply(state.runtimeClose, state.runtime, []),
          "Chrome runtime cleanup",
        );
      }
      reportProgress("Chrome process and profile cleanup complete");
    } catch (error) {
      cleanupErrors.push(error);
    }
    if (cleanupErrors.length) {
      const message = redactText(
        cleanupErrors
          .map((error) => {
            return formatBoundedFailure(error);
          })
          .join("\n"),
        secrets,
      );
      let primaryMessage = "";
      if (runError) {
        try {
          primaryMessage = redactError(runError, secrets);
        } catch {
          primaryMessage = "browser gate failed and its error could not be formatted";
        }
      }
      const combined = new Error(primaryMessage ? `${primaryMessage}\n${message}` : message);
      combined.exitCode = runError?.exitCode;
      reportProgress(
        `browser gate cleanup finished with errors; active resources: ${JSON.stringify(activeResourceNames())}`,
      );
      throw combined;
    }
    reportProgress(
      `browser gate cleanup finished; active resources: ${JSON.stringify(activeResourceNames())}`,
    );
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
