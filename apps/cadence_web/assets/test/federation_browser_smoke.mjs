import assert from "node:assert/strict";
import { existsSync } from "node:fs";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { resolve } from "node:path";
import { spawn } from "node:child_process";

const CDP_COMMAND_TIMEOUT_MS = 15_000;
const CDP_EVENT_TIMEOUT_MS = 30_000;
const CHROME_START_TIMEOUT_MS = 10_000;
const SCENARIO_TIMEOUT_MS = 180_000;
const POLL_INTERVAL_MS = 100;

let currentProgressStage = "initializing";

function reportProgress(stage) {
  currentProgressStage = stage;
  console.error(`[federation-smoke] ${stage}`);
}

function argValue(args, name) {
  const index = args.indexOf(name);
  return index === -1 ? undefined : args[index + 1];
}

function requiredArg(args, name) {
  const value = argValue(args, name);
  if (!value) throw new Error(`missing required argument ${name}`);
  return value;
}

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function withTimeout(promise, milliseconds, label) {
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(
      () => reject(new Error(`${label} timed out after ${milliseconds}ms`)),
      milliseconds,
    );
  });

  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}

function chromeBinary() {
  const candidates = [
    process.env.CHROME_BIN,
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
    "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
    "/usr/bin/google-chrome",
    "/usr/bin/chromium",
    "/usr/bin/chromium-browser",
  ].filter(Boolean);

  const binary = candidates.find((candidate) => existsSync(candidate));
  if (!binary) {
    throw new Error(
      "Chrome or Chromium is required; set CHROME_BIN or install a supported browser",
    );
  }

  return binary;
}

async function removeUserDataDir(userDataDir) {
  for (let attempt = 0; attempt < 5; attempt += 1) {
    try {
      await rm(userDataDir, { recursive: true, force: true });
      return;
    } catch (error) {
      if (attempt === 4) throw error;
      await sleep(100 * (attempt + 1));
    }
  }
}

async function launchChrome() {
  const userDataDir = await mkdtemp(resolve(tmpdir(), "cadence-federation-chrome-"));
  const child = spawn(
    chromeBinary(),
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
    { stdio: ["ignore", "pipe", "pipe"] },
  );

  const endpoint = await withTimeout(
    new Promise((resolveEndpoint, reject) => {
      let output = "";
      const collect = (chunk) => {
        output += chunk.toString();
        const match = output.match(/DevTools listening on (ws:\/\/[^\s]+)/);
        if (match) resolveEndpoint(match[1]);
      };

      child.stdout.on("data", collect);
      child.stderr.on("data", collect);
      child.once("error", reject);
      child.once("exit", (code, signal) => {
        reject(new Error(`Chrome exited before CDP startup (${code ?? signal})\n${output}`));
      });
    }),
    CHROME_START_TIMEOUT_MS,
    "Chrome CDP startup",
  ).catch(async (error) => {
    child.kill("SIGKILL");
    await removeUserDataDir(userDataDir);
    throw error;
  });

  return {
    child,
    endpoint,
    userDataDir,
    async close() {
      if (!child.killed) child.kill("SIGTERM");
      await withTimeout(
        new Promise((resolveClose) => {
          if (child.exitCode !== null || child.signalCode !== null) return resolveClose();
          child.once("exit", resolveClose);
        }),
        2_000,
        "Chrome shutdown",
      ).catch(() => child.kill("SIGKILL"));
      await removeUserDataDir(userDataDir);
    },
  };
}

function httpBaseFromWebSocket(endpoint) {
  const url = new URL(endpoint);
  return `http://${url.hostname}:${url.port}`;
}

async function createPage(endpoint, url) {
  const response = await fetch(`${httpBaseFromWebSocket(endpoint)}/json/new?${encodeURIComponent(url)}`, {
    method: "PUT",
  });
  if (!response.ok) throw new Error(`CDP page creation failed with HTTP ${response.status}`);
  const target = await response.json();
  if (!target.webSocketDebuggerUrl) throw new Error("CDP page target did not expose a WebSocket URL");
  return target.webSocketDebuggerUrl;
}

class CdpClient {
  constructor(endpoint) {
    this.socket = new WebSocket(endpoint);
    this.nextCommandId = 0;
    this.pending = new Map();
    this.listeners = new Map();
    this.ready = new Promise((resolveReady, rejectReady) => {
      this.socket.addEventListener("open", resolveReady);
      this.socket.addEventListener("error", rejectReady, { once: true });
    });

    this.socket.addEventListener("message", (event) => {
      const raw = typeof event.data === "string" ? event.data : Buffer.from(event.data).toString();
      const message = JSON.parse(raw);
      if (message.id !== undefined) {
        const callback = this.pending.get(message.id);
        if (!callback) return;
        this.pending.delete(message.id);
        if (message.error) callback.reject(new Error(`${message.error.message} (CDP ${message.id})`));
        else callback.resolve(message.result);
        return;
      }

      const listeners = this.listeners.get(message.method) || [];
      for (const listener of listeners) listener(message.params);
    });
  }

  async send(method, params = {}, timeout = CDP_COMMAND_TIMEOUT_MS) {
    await withTimeout(this.ready, timeout, `CDP connection during ${method}`);
    const id = ++this.nextCommandId;
    const result = new Promise((resolveResult, rejectResult) => {
      this.pending.set(id, { resolve: resolveResult, reject: rejectResult });
    });

    this.socket.send(JSON.stringify({ id, method, params }));

    return withTimeout(result, timeout, `CDP ${method} during ${currentProgressStage}`).finally(() => {
      this.pending.delete(id);
    });
  }

  once(method, timeout = CDP_EVENT_TIMEOUT_MS) {
    return withTimeout(
      new Promise((resolveEvent) => {
        const listeners = this.listeners.get(method) || [];
        const listener = (params) => {
          this.listeners.set(method, listeners.filter((item) => item !== listener));
          resolveEvent(params);
        };
        this.listeners.set(method, [...listeners, listener]);
      }),
      timeout,
      `CDP ${method} during ${currentProgressStage}`,
    );
  }

  on(method, listener) {
    const listeners = this.listeners.get(method) || [];
    this.listeners.set(method, [...listeners, listener]);
  }

  close() {
    for (const callback of this.pending.values()) {
      callback.reject(new Error("CDP client closed"));
    }
    this.pending.clear();
    this.socket.close();
  }
}

function exceptionMessage(exception) {
  const details = exception?.exceptionDetails || exception;
  return (
    details?.exception?.description ||
    details?.text ||
    details?.exception?.value ||
    JSON.stringify(details)
  );
}

function ambientBrowserProbe(record) {
  // Phoenix declares favicon.ico as a static path, but this repository does not
  // publish a favicon. Chrome requests it for every document independently of
  // the federation surface; it is not part of this gate's application contract.
  return typeof record?.url === "string" && new URL(record.url).pathname === "/favicon.ico";
}

function installDiagnostics(client) {
  const requests = new Map();
  const consoleErrors = [];
  const runtimeExceptions = [];
  const requestFailures = [];

  client.on("Network.requestWillBeSent", ({ requestId, request }) => {
    requests.set(requestId, {
      requestId,
      method: request.method,
      url: request.url,
      request,
      response: undefined,
      finished: false,
      failed: undefined,
    });
  });

  client.on("Network.responseReceived", ({ requestId, response }) => {
    const record = requests.get(requestId) || { requestId, finished: false };
    record.response = response;
    requests.set(requestId, record);
    if (response.status >= 400 && !ambientBrowserProbe(record)) {
      requestFailures.push(`${response.status} ${response.requestHeadersText || ""} ${response.url}`);
    }
  });

  client.on("Network.loadingFinished", ({ requestId }) => {
    const record = requests.get(requestId);
    if (record) record.finished = true;
  });

  client.on("Network.loadingFailed", ({ requestId, errorText, canceled, blockedReason }) => {
    const record = requests.get(requestId);
    const detail = `${errorText || "request failed"}${canceled ? " (canceled)" : ""}${blockedReason ? ` (${blockedReason})` : ""}`;
    if (!record || !ambientBrowserProbe(record)) {
      requestFailures.push(`${record?.method || "?"} ${record?.url || requestId}: ${detail}`);
    }
    if (record) record.failed = detail;
  });

  client.on("Runtime.consoleAPICalled", ({ type, args, stackTrace }) => {
    if (type !== "error") return;
    const values = (args || []).map((arg) => arg.value ?? arg.description ?? arg.type).join(" ");
    consoleErrors.push(`${values}${stackTrace?.description ? `\n${stackTrace.description}` : ""}`);
  });

  client.on("Runtime.exceptionThrown", (exception) => {
    runtimeExceptions.push(exceptionMessage(exception));
  });

  return {
    requests,
    consoleErrors,
    runtimeExceptions,
    requestFailures,
    completed(predicate) {
      return [...requests.values()].filter((record) =>
        record.response && record.finished && !record.failed && predicate(record),
      );
    },
    assertClean(stage) {
      const failures = [
        ...requestFailures.map((value) => `request failure: ${value}`),
        ...consoleErrors.map((value) => `console.error: ${value}`),
        ...runtimeExceptions.map((value) => `runtime exception: ${value}`),
      ];
      if (failures.length) throw new Error(`${stage} browser diagnostics failed:\n${failures.join("\n")}`);
    },
    describe() {
      return JSON.stringify({
        requestFailures,
        consoleErrors,
        runtimeExceptions,
        requests: [...requests.values()].map((record) => ({
          method: record.method,
          url: record.url,
          status: record.response?.status,
          finished: record.finished,
          failed: record.failed,
        })),
      }, null, 2);
    },
  };
}

async function evaluate(client, expression, label) {
  const result = await client.send("Runtime.evaluate", {
    expression,
    awaitPromise: true,
    returnByValue: true,
  });
  if (result.exceptionDetails) throw new Error(`${label}: ${exceptionMessage(result)}`);
  return result.result?.value;
}

async function waitForExpression(client, expression, label, timeout = CDP_EVENT_TIMEOUT_MS) {
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

async function waitForResponse(diagnostics, predicate, label, timeout = CDP_EVENT_TIMEOUT_MS) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    const match = diagnostics.completed(predicate)[0];
    if (match) return match;
    await sleep(POLL_INTERVAL_MS);
  }

  throw new Error(`${label} response was not observed`);
}

async function responseJson(client, record, label) {
  const result = await client.send("Network.getResponseBody", { requestId: record.requestId });
  const body = result.base64Encoded ? Buffer.from(result.body, "base64").toString("utf8") : result.body;
  try {
    return JSON.parse(body);
  } catch (error) {
    throw new Error(`${label} returned invalid JSON: ${error.message}`);
  }
}

async function navigate(client, url) {
  reportProgress(`navigating ${url}`);
  await client.send("Page.navigate", { url });
  await waitForExpression(
    client,
    "document.readyState !== 'loading' && document.body !== null",
    `${url} document load`,
  );
}

async function submitSignIn(client, loginUrl, email, password) {
  await navigate(client, loginUrl);
  await waitForExpression(
    client,
    "Boolean(document.querySelector('#sign-in-form input[name=\"user[email]\"]') && document.querySelector('#sign-in-form input[name=\"user[password]\"]'))",
    "sign-in form",
  );

  const result = await evaluate(
    client,
    `(() => {
      const form = document.querySelector('#sign-in-form');
      const email = form?.querySelector('input[name="user[email]"]');
      const password = form?.querySelector('input[name="user[password]"]');
      if (!form || !email || !password) return false;
      email.value = ${JSON.stringify(email)};
      password.value = ${JSON.stringify(password)};
      email.dispatchEvent(new Event('input', {bubbles: true}));
      password.dispatchEvent(new Event('input', {bubbles: true}));
      form.submit();
      return true;
    })()`,
    "sign-in submission",
  );
  assert.equal(result, true, "sign-in form was not submitted");
  await waitForExpression(client, "location.pathname !== '/sign-in'", "authenticated redirect");
}

function pathMatches(record, method, pathname) {
  return record.method === method && new URL(record.url).pathname === pathname;
}

function remoteChunkMatches(record, prefix) {
  const pathname = new URL(record.url).pathname;
  return pathname.startsWith(prefix) && pathname.endsWith(".js");
}

function assertCatalog(catalog, applicationKey, surfaceId, expectedScope) {
  assert.equal(catalog.schema, "cadence.first-party-frontend-catalog.v1");
  assert.equal(catalog.hostContract, "cadence.application-host.v1");
  assert.match(catalog.generatedAt, /^20\d\d-/);
  assert.equal(catalog.session.context.scope, expectedScope);
  assert.ok(catalog.session.sessionId);
  assert.ok(catalog.session.csrfToken);
  assert.ok(catalog.session.bridgeBaseUrl);
  assert.equal(catalog.applications.length, 1);

  const application = catalog.applications[0];
  assert.equal(application.applicationKey, applicationKey);
  assert.equal(application.applicationVersion, 1);
  assert.equal(application.surface.surfaceId, surfaceId);
  assert.equal(application.surface.version, 1);
  assert.equal(application.release.federation, "module_federation");
  assert.equal(application.release.exposedModule, "./Application");
  assert.match(application.release.manifestUrl, /\/assets\/application-host\/[^/]+\/mf-manifest\.json$/);
  return application;
}

async function assertRemoteSurface({
  client,
  diagnostics,
  url,
  catalogPath,
  applicationKey,
  surfaceId,
  expectedScope,
  remotePath,
  readyExpression,
  queryPath,
}) {
  await navigate(client, url);
  try {
    await waitForExpression(client, readyExpression, `${applicationKey} REMOTE READY`);
  } catch (error) {
    throw new Error(`${error.message}\n${diagnostics.describe()}`, { cause: error });
  }
  diagnostics.assertClean(`${applicationKey} surface`);

  const catalogRecord = await waitForResponse(
    diagnostics,
    (record) => pathMatches(record, "GET", catalogPath),
    `${applicationKey} catalog`,
  );
  const catalog = await responseJson(client, catalogRecord, `${applicationKey} catalog`);
  const application = assertCatalog(catalog, applicationKey, surfaceId, expectedScope);

  const manifestPath = new URL(application.release.manifestUrl).pathname;
  const manifestRecord = await waitForResponse(
    diagnostics,
    (record) => pathMatches(record, "GET", manifestPath),
    `${applicationKey} manifest`,
  );
  const manifest = await responseJson(client, manifestRecord, `${applicationKey} manifest`);
  assert.equal(typeof manifest, "object");
  assert.ok(JSON.stringify(manifest).includes("./Application"), `${applicationKey} manifest lacks ./Application`);

  const hostRecord = diagnostics.completed((record) => new URL(record.url).pathname.endsWith("/host/host.js"))[0];
  assert.ok(hostRecord, "published Phoenix host bundle was not loaded");
  assert.equal(hostRecord.response.status, 200);

  assert.ok(manifestPath.startsWith(remotePath), `${applicationKey} manifest escaped its published remote path`);
  const remotePrefix = remotePath;
  const chunkRecords = diagnostics.completed((record) => remoteChunkMatches(record, remotePrefix));
  assert.ok(chunkRecords.length > 0, `${applicationKey} published remote chunks were not loaded`);

  const queryRecord = await waitForResponse(
    diagnostics,
    (record) => pathMatches(record, "POST", queryPath),
    `${applicationKey} query`,
  );
  const query = await responseJson(client, queryRecord, `${applicationKey} query`);
  return { catalog, application, manifest, query, queryRecord };
}

async function runScenario(client, diagnostics, args) {
  const commsUrl = requiredArg(args, "--comms-url");
  const telemetryUrl = requiredArg(args, "--telemetry-url");
  const loginUrl = requiredArg(args, "--login-url");
  const email = requiredArg(args, "--login-email");
  const password = requiredArg(args, "--login-password");
  const missionId = requiredArg(args, "--mission-id");
  const spacecraftId = requiredArg(args, "--spacecraft-id");
  const expectedApid = Number(requiredArg(args, "--expected-apid"));
  const origin = new URL(commsUrl).origin;

  reportProgress("authenticating browser session");
  await submitSignIn(client, loginUrl, email, password);
  diagnostics.assertClean("authenticated sign-in");

  const comms = await assertRemoteSurface({
    client,
    diagnostics,
    url: commsUrl,
    catalogPath: `/api/cadence/application-host/v1/missions/${encodeURIComponent(missionId)}/catalog`,
    applicationKey: "comms_overview",
    surfaceId: "overview",
    expectedScope: "mission",
    remotePath: "/assets/application-host/comms-overview/",
    readyExpression: `Boolean(document.querySelector('.phoenix-host-release')?.textContent.trim() === 'REMOTE READY' && document.querySelector('#comms-overview-application') && document.querySelector('#comms-overview-page') && document.querySelector('#comms-overview-content') && document.querySelector('#comms-transports') && !document.querySelector('#remote-error') && !document.querySelector('#comms-overview-error'))`,
    queryPath: `/api/cadence/application-host/v1/missions/${encodeURIComponent(missionId)}/query`,
  });
  assert.equal(comms.query.queryVersion, 1);
  assert.equal(comms.query.presentation.root.attrs.id, "comms-overview-page");
  assert.equal(comms.query.presentation.overview.transport.id, "comms-transports");
  assert.equal(comms.query.presentation.overview.transport.count, 1);

  reportProgress("verifying Comms Overview DOM and network contract");
  const commsTransport = await evaluate(
    client,
    "document.querySelector('#comms-transports')?.textContent?.includes('Federation Browser Transport')",
    "Comms Overview transport",
  );
  assert.equal(commsTransport, true);

  const telemetry = await assertRemoteSurface({
    client,
    diagnostics,
    url: telemetryUrl,
    catalogPath: `/api/cadence/application-host/v1/missions/${encodeURIComponent(missionId)}/spacecraft/${encodeURIComponent(spacecraftId)}/catalog`,
    applicationKey: "telemetry_decom",
    surfaceId: "packet_bindings",
    expectedScope: "spacecraft",
    remotePath: "/assets/application-host/telemetry-decom/",
    readyExpression: `Boolean(document.querySelector('.phoenix-host-release')?.textContent.trim() === 'REMOTE READY' && document.querySelector('#telemetry-decom-application') && document.querySelector('#packet-bindings-surface') && document.querySelector('#packet-bindings-form') && document.querySelector('#packet-bindings-submit') && !document.querySelector('#remote-error') && !document.querySelector('#telemetry-decom-error'))`,
    queryPath: `/api/cadence/application-host/v1/missions/${encodeURIComponent(missionId)}/spacecraft/${encodeURIComponent(spacecraftId)}/query`,
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
    (record) => pathMatches(record, "POST", actionPath),
    "Telemetry packet-bindings action",
  );
  const receipt = await responseJson(client, actionRecord, "Telemetry packet-bindings action");
  assert.match(receipt.receiptId, /^application-host-receipt-/);
  assert.equal(receipt.result.applicationKey, "telemetry_decom");
  assert.deepEqual(receipt.result.selectedPacketIds, [packetId]);

  const refreshedQueryRecords = () =>
    diagnostics.completed(
      (record) =>
        pathMatches(
          record,
          "POST",
          `/api/cadence/application-host/v1/missions/${encodeURIComponent(missionId)}/spacecraft/${encodeURIComponent(spacecraftId)}/query`,
        ),
    );

  const deadline = Date.now() + CDP_EVENT_TIMEOUT_MS;
  while (refreshedQueryRecords().length < 2 && Date.now() < deadline) await sleep(POLL_INTERVAL_MS);
  assert.equal(refreshedQueryRecords().length, 2, "Telemetry action did not trigger canonical query refresh");

  const refreshedQueryRecord = refreshedQueryRecords()[1];
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
  const retainedSelection = await evaluate(
    client,
    `document.querySelector('[data-apid="${expectedApid}"] input[type="checkbox"]')?.checked === true`,
    "Telemetry retained selection",
  );
  assert.equal(retainedSelection, true);

  diagnostics.assertClean("federation browser gate");
  return {
    origin,
    remotes: [comms.application.release.releaseId, telemetry.application.release.releaseId],
    queryResponses: refreshedQueryRecords().length,
    actionReceipt: receipt.receiptId,
    retainedPacketId: packetId,
  };
}

const args = process.argv.slice(2);
let chrome;
let client;

try {
  reportProgress("launching bounded Chrome process");
  chrome = await launchChrome();
  const pageEndpoint = await createPage(chrome.endpoint, "about:blank");
  client = new CdpClient(pageEndpoint);
  await client.send("Page.enable");
  await client.send("Runtime.enable");
  await client.send("Network.enable");
  await client.send("Log.enable");
  await client.send("Emulation.setDeviceMetricsOverride", {
    width: 1440,
    height: 1000,
    deviceScaleFactor: 1,
    mobile: false,
  });

  const diagnostics = installDiagnostics(client);
  const result = await withTimeout(
    runScenario(client, diagnostics, args),
    Number(argValue(args, "--scenario-timeout-ms") || SCENARIO_TIMEOUT_MS),
    "federation browser scenario",
  );
  console.log(JSON.stringify(result, null, 2));
  console.log("federation_browser_smoke passed");
} finally {
  reportProgress("cleaning up browser process and profile");
  client?.close();
  if (chrome) await chrome.close();
}
