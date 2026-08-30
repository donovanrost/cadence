import assert from "node:assert/strict";
import { createServer } from "node:net";
import { test } from "node:test";
import {
  assertHttpRequestContract,
  assertLiveViewWebSocket,
  assertManifestAssetsRequested,
  assertNoPasswordArgument,
  browserUrls,
  createPage,
  installDiagnostics,
  isDataUrl,
  isIgnoredFavicon,
  parseResponseBody,
  requirePostActionRefresh,
  reserveLoopbackPort,
  redactText,
  resolveChromeBinary,
} from "./federation_browser_smoke.mjs";

const origin = "http://127.0.0.1:43721";

function record({
  url = `${origin}/api/query`,
  method = "POST",
  body = { ok: true },
  status = 200,
  headers = {
    "content-type": "application/json",
    "x-cadence-poc-session": "session-1",
    "x-csrf-token": "csrf-1",
    "idempotency-key": "01234567-89ab-cdef-0123-456789abcdef",
  },
  requestId = "request-1",
  startedAtMs = 10,
  redirects = [],
  resourceType = "XHR",
} = {}) {
  return {
    requestId,
    startedAtMs,
    url,
    method,
    postData: body === undefined ? undefined : JSON.stringify(body),
    request: { headers },
    response: { status },
    redirects,
    resourceType,
    finished: true,
    failed: undefined,
  };
}

function queryBody() {
  return {
    applicationKey: "telemetry_decom",
    applicationVersion: 1,
    surfaceId: "packet_bindings",
    surfaceVersion: 1,
    queryId: "cadence.packet_bindings.manage",
    queryVersion: 1,
    scope: { organizationId: "org-1", missionId: "mission-1", spacecraftId: "spacecraft-1" },
  };
}

test("the browser URL contract uses an actual isolated HTTP endpoint", async () => {
  const prebound = await new Promise((resolveListen) => {
    const server = createServer();
    server.once("error", (error) => {
      if (error.code === "EADDRINUSE") resolveListen(null);
      else throw error;
    });
    server.listen(4101, "127.0.0.1", () => resolveListen(server));
  });

  const first = await reserveLoopbackPort();
  const second = await reserveLoopbackPort();
  try {
    assert.notEqual(first.port, 4101);
    assert.notEqual(second.port, 4101);
    assert.notEqual(first.port, second.port);
    const firstUrls = browserUrls({ port: first.port, missionId: "mission/one", spacecraftId: "sc-1" });
    const secondUrls = browserUrls({ port: second.port, missionId: "mission/one", spacecraftId: "sc-1" });
    assert.notEqual(new URL(firstUrls.commsUrl).origin, new URL(secondUrls.commsUrl).origin);
    assert.equal(
      new URL(firstUrls.commsUrl).pathname,
      "/missions/mission%2Fone/comms/federated",
    );
    assert.match(firstUrls.telemetryUrl, new RegExp(`:${first.port}/`));
  } finally {
    await Promise.all([
      new Promise((resolveClose) => first.server.close(resolveClose)),
      new Promise((resolveClose) => second.server.close(resolveClose)),
    ]);
    await new Promise((resolveClose) => prebound?.close(resolveClose) || resolveClose());
  }
});

test("HTTP bridge contracts require same-origin 200 responses, exact bodies, and security headers", () => {
  const expected = queryBody();
  const base = record({ url: `${origin}/api/cadence/application-host/v1/missions/mission-1/spacecraft/spacecraft-1/query`, body: expected });
  assertHttpRequestContract(base, {
    origin,
    method: "POST",
    pathname: "/api/cadence/application-host/v1/missions/mission-1/spacecraft/spacecraft-1/query",
    label: "query",
    body: expected,
    headers: {
      "content-type": "application/json",
      "x-cadence-poc-session": "session-1",
      "x-csrf-token": "csrf-1",
    },
  });

  for (const invalid of [
    { url: "https://evil.example/api/query" },
    { status: 302 },
    { status: 304 },
    { redirects: [{ status: 302, url: `${origin}/sign-in` }] },
    { body: { ...expected, surfaceVersion: 2 } },
    { method: "GET" },
    { headers: { "content-type": "application/json" } },
  ]) {
    assert.throws(
      () => assertHttpRequestContract({ ...base, ...record(invalid) }, {
        origin,
        method: "POST",
        pathname: "/api/cadence/application-host/v1/missions/mission-1/spacecraft/spacecraft-1/query",
        label: "adversarial query",
        body: expected,
        headers: {
          "content-type": "application/json",
          "x-cadence-poc-session": "session-1",
          "x-csrf-token": "csrf-1",
        },
      }),
      /escaped|path|HTTP 200|redirected|JSON body|method|header/,
    );
  }

  assert.throws(() => parseResponseBody({}, "missing body"), /body was unavailable/);
  assert.throws(() => parseResponseBody({ body: "" }, "empty body"), /body was empty/);
  assertHttpRequestContract(record({ url: `${origin}/actions`, body: { ok: true } }), {
    origin,
    method: "POST",
    pathname: "/actions",
    label: "action",
    body: { ok: true },
    headers: {},
    requireIdempotencyKey: true,
  });
  assert.throws(
    () => assertHttpRequestContract(record({ headers: { "content-type": "application/json" } }), {
      origin,
      method: "POST",
      pathname: "/api/query",
      label: "action without idempotency",
      body: { ok: true },
      headers: {},
      requireIdempotencyKey: true,
    }),
    /idempotency key/,
  );
});

test("manifest validation follows every declared transitive JavaScript and CSS asset", () => {
  const manifestUrl = `${origin}/assets/application-host/telemetry-decom/mf-manifest.json`;
  const manifest = {
    metaData: { remoteEntry: { name: "remoteEntry.js" }, ssrRemoteEntry: { name: "remoteEntry.ssr.js" } },
    entry: "remoteEntry.js",
    files: ["chunks/Application-1.js", "styles/Application.css"],
    exposes: [
      { path: "./Application", assets: { js: { sync: ["chunks/Application-1.js"] } } },
      { path: "./Failure", assets: { js: { sync: ["chunks/Failure.js"] } } },
    ],
  };
  const assets = [
    record({ url: `${origin}/assets/application-host/telemetry-decom/remoteEntry.js`, method: "GET", body: undefined, resourceType: "Script" }),
    record({ url: `${origin}/assets/application-host/telemetry-decom/chunks/Application-1.js`, method: "GET", body: undefined, resourceType: "Script" }),
    record({ url: `${origin}/assets/application-host/telemetry-decom/styles/Application.css`, method: "GET", body: undefined, resourceType: "Stylesheet" }),
  ];
  assert.equal(
    assertManifestAssetsRequested(manifest, manifestUrl, assets, {
      origin,
      label: "telemetry manifest",
      requiredExposedModule: "./Application",
    }).length,
    3,
  );
  assert.throws(
    () => assertManifestAssetsRequested(manifest, manifestUrl, assets.slice(0, 2), { origin, label: "missing asset manifest" }),
    /was not successfully requested.*Application\.css/,
  );
  assert.throws(
    () => assertManifestAssetsRequested(manifest, manifestUrl, [
      ...assets.slice(0, 2),
      record({ url: `${origin}/assets/application-host/telemetry-decom/styles/Application.css`, method: "GET", body: undefined, status: 404 }),
    ], { origin, label: "404 asset manifest" }),
    /was not successfully requested|HTTP 200/,
  );
  assert.throws(
    () => assertManifestAssetsRequested({ entry: "https://evil.example/remote.js" }, manifestUrl, [], { origin, label: "foreign asset manifest" }),
    /escaped the expected origin/,
  );
});

test("refresh causality rejects a duplicate pre-action query and accepts only a new post-action query", () => {
  const pathname = "/api/query";
  const initial = record({ url: `${origin}${pathname}`, requestId: "query-1", startedAtMs: 10 });
  const duplicateBeforeAction = record({ url: `${origin}${pathname}`, requestId: "query-2", startedAtMs: 20 });
  assert.throws(
    () => requirePostActionRefresh([initial, duplicateBeforeAction], {
      beforeRequestIds: new Set(["query-1", "query-2"]),
      beforeCount: 2,
      actionStartedAtMs: 30,
      pathname,
      origin,
      label: "duplicate-only action",
    }),
    /new query request|post-action query/,
  );
  const refreshed = record({ url: `${origin}${pathname}`, requestId: "query-3", startedAtMs: 40 });
  assert.equal(
    requirePostActionRefresh([initial, duplicateBeforeAction, refreshed], {
      beforeRequestIds: new Set(["query-1", "query-2"]),
      beforeCount: 2,
      actionStartedAtMs: 30,
      pathname,
      origin,
    }).requestId,
    "query-3",
  );
});

test("data URLs and favicon exclusion are explicit and narrowly scoped", () => {
  assert.equal(isDataUrl("data:text/javascript,alert(1)"), true);
  assert.equal(isDataUrl(`${origin}/assets/app.js`), false);
  assert.equal(isIgnoredFavicon(record({ url: `${origin}/favicon.ico`, method: "GET", body: undefined, resourceType: "Image" }), origin), true);
  assert.equal(isIgnoredFavicon(record({ url: `${origin}/favicon.ico?foreign=1`, method: "GET", body: undefined, resourceType: "Image" }), origin), false);
  assert.equal(isIgnoredFavicon(record({ url: "https://evil.example/favicon.ico", method: "GET", body: undefined, resourceType: "Image" }), origin), false);
  assert.equal(isIgnoredFavicon(record({ url: `${origin}/favicon.ico`, method: "POST", body: undefined, resourceType: "Image" }), origin), false);
  assert.equal(isIgnoredFavicon(record({ url: `${origin}/favicon.ico`, method: "GET", body: undefined, resourceType: "Other" }), origin), true);
});

test("favicon log errors are ignored only with the matching browser request contract", () => {
  const diagnosticClient = () => {
    const listeners = new Map();
    return {
      on(method, listener) {
        const methodListeners = listeners.get(method) || new Set();
        methodListeners.add(listener);
        listeners.set(method, methodListeners);
        return () => methodListeners.delete(listener);
      },
      emit(method, event) {
        for (const listener of listeners.get(method) || []) listener(event);
      },
      listenerCount() {
        return [...listeners.values()].reduce((count, methodListeners) => count + methodListeners.size, 0);
      },
    };
  };
  const client = diagnosticClient();
  const diagnostics = installDiagnostics(client, { expectedOrigin: origin });
  const favicon = `${origin}/favicon.ico`;

  client.emit("Network.requestWillBeSent", {
    requestId: "favicon-1",
    request: { url: favicon, method: "GET" },
    type: "Other",
  });
  client.emit("Network.responseReceived", {
    requestId: "favicon-1",
    response: { url: favicon, status: 404 },
    type: "Other",
  });
  client.emit("Network.loadingFinished", { requestId: "favicon-1" });
  client.emit("Log.entryAdded", { entry: { level: "error", text: "favicon missing", url: favicon } });
  assert.doesNotThrow(() => diagnostics.assertClean("favicon"));
  assert.ok(client.listenerCount() > 0);
  diagnostics.dispose();
  assert.equal(client.listenerCount(), 0, "diagnostics did not unsubscribe all CDP listeners");

  const foreignClient = diagnosticClient();
  const foreignLog = installDiagnostics(foreignClient, { expectedOrigin: origin });
  foreignClient.emit("Log.entryAdded", {
    entry: { level: "error", text: "favicon missing", url: `${origin}/favicon.ico?query=1` },
  });
  assert.throws(() => foreignLog.assertClean("foreign favicon"), /browser diagnostics failed/);
  foreignLog.dispose();
  assert.equal(foreignClient.listenerCount(), 0);
});

test("LiveView requires a same-origin websocket handshake and rejects longpoll fallback", () => {
  const connected = {
    requestId: "live-ws-1",
    url: `${origin.replace("http:", "ws:")}/live/websocket?vsn=2.0.0`,
    handshakeRequest: { headers: { Origin: origin } },
    handshake: { status: 101 },
    error: undefined,
  };
  const diagnostics = {
    webSockets: new Map([
      ["live-ws-old", { ...connected, requestId: "live-ws-old" }],
      [connected.requestId, connected],
    ]),
    webSocketFailures: [],
    requests: new Map(),
    consoleErrors: [],
    logErrors: [],
  };
  assert.equal(
    assertLiveViewWebSocket(diagnostics, origin, { beforeRequestIds: new Set(["live-ws-old"]) }),
    connected,
  );

  for (const invalid of [
    { ...connected, url: "wss://evil.example/live/websocket?vsn=2.0.0" },
    { ...connected, handshake: { status: 403 } },
    { ...connected, handshakeRequest: { headers: { Origin: "http://127.0.0.1:4101" } } },
    { ...connected, error: "WebSocket handshake failed" },
  ]) {
    assert.throws(
      () => assertLiveViewWebSocket({ ...diagnostics, webSockets: new Map([[invalid.requestId, invalid]]) }, origin),
      /same-origin HTTP 101 handshake/,
    );
  }

  assert.throws(
    () => assertLiveViewWebSocket({
      ...diagnostics,
      requests: new Map([[
        "longpoll-1",
        { url: `${origin}/live/longpoll?vsn=2.0.0` },
      ]]),
    }, origin),
    /longpoll transport/,
  );
  assert.throws(
    () => assertLiveViewWebSocket({ ...diagnostics, webSocketFailures: ["origin rejected"] }, origin),
    /websocket transport failed/,
  );
});

test("binary admission and diagnostics redact secrets without argv or environment transport", () => {
  assert.equal(resolveChromeBinary({ env: { CHROME_BIN: "/missing" }, candidates: ["/also-missing"], fileExists: () => false }), undefined);
  assert.throws(() => assertNoPasswordArgument(["--login-email", "operator@example.test", "--login-password", "secret"]), /structured stdin/);
  const secret = "correct-horse-battery-staple";
  assert.equal(redactText(`argv=[] failure=${secret}`, [secret]).includes(secret), false);
});

test("raw CDP target creation is abortable and time-bounded", async () => {
  await assert.rejects(
    createPage("ws://127.0.0.1:9222/devtools/browser/test", "about:blank", {
      fetcher: () => new Promise(() => {}),
      timeout: 20,
    }),
    /timed out/,
  );

  const controller = new AbortController();
  const pending = createPage("ws://127.0.0.1:9222/devtools/browser/test", "about:blank", {
    fetcher: () => new Promise(() => {}),
    timeout: 1_000,
    signal: controller.signal,
  });
  controller.abort(new Error("test CDP cancellation"));
  await assert.rejects(pending, /test CDP cancellation/);
});
