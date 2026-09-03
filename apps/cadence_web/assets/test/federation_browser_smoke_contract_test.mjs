import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createServer } from "node:net";
import { test } from "node:test";
import {
  assertHttpRequestContract,
  assertImmutableArtifactResponse,
  assertImmutableReleaseCacheReuse,
  assertLiveViewWebSocket,
  assertManifestAssetsRequested,
  assertNoPasswordArgument,
  assertReleaseArtifactUrl,
  assertSignInUrl,
  browserUrls,
  createPage,
  installDiagnostics,
  isDataUrl,
  isIgnoredFavicon,
  matchesSignInNavigationRequest,
  parseResponseBody,
  requirePostActionRefresh,
  reserveLoopbackPort,
  redactText,
  releaseArtifactPrefix,
  resolveChromeBinary,
  runScenario,
  waitForPageNavigation,
  waitForResponse,
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
  sequence = startedAtMs,
  redirects = [],
  resourceType = "XHR",
  responseHeaders = {},
  fromDiskCache = false,
  fromMemoryCache = false,
  fromServiceWorker = false,
  fromPrefetchCache = false,
  servedFromCache = false,
} = {}) {
  return {
    requestId,
    sequence,
    startedAtMs,
    url,
    method,
    postData: body === undefined ? undefined : JSON.stringify(body),
    request: { headers },
    response: {
      status,
      headers: responseHeaders,
      fromDiskCache,
      fromMemoryCache,
      fromServiceWorker,
      fromPrefetchCache,
    },
    servedFromCache,
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
      "/missions/mission%2Fone/applications/comms_overview/federated",
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
  const releaseId = `sha256:${"a".repeat(64)}`;
  const releasePrefix = releaseArtifactPrefix("telemetry_decom", releaseId);
  const manifestUrl = `${origin}${releasePrefix}mf-manifest.json`;
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
    record({ url: `${origin}${releasePrefix}remoteEntry.js`, method: "GET", body: undefined, resourceType: "Script" }),
    record({ url: `${origin}${releasePrefix}chunks/Application-1.js`, method: "GET", body: undefined, resourceType: "Script" }),
    record({ url: `${origin}${releasePrefix}styles/Application.css`, method: "GET", body: undefined, resourceType: "Stylesheet" }),
  ];
  const releaseOptions = {
    origin,
    applicationKey: "telemetry_decom",
    releaseId,
    requiredExposedModule: "./Application",
  };
  assert.equal(
    assertManifestAssetsRequested(manifest, manifestUrl, assets, {
      label: "telemetry manifest",
      ...releaseOptions,
    }).length,
    3,
  );
  assert.doesNotThrow(() => assertManifestAssetsRequested(manifest, manifestUrl, [
    ...assets.slice(0, 2),
    record({
      url: `${origin}${releasePrefix}styles/Application.css`,
      method: "GET",
      body: undefined,
      status: 404,
      sequence: 20,
    }),
    record({
      url: `${origin}${releasePrefix}styles/Application.css`,
      method: "GET",
      body: undefined,
      status: 200,
      sequence: 21,
    }),
  ], {
    label: "newest duplicate manifest",
    ...releaseOptions,
  }));
  assert.throws(
    () => assertManifestAssetsRequested(manifest, manifestUrl, assets.slice(0, 2), { ...releaseOptions, label: "missing asset manifest" }),
    /was not successfully requested.*Application\.css/,
  );
  assert.throws(
    () => assertManifestAssetsRequested(manifest, manifestUrl, [
      ...assets.slice(0, 2),
      record({ url: `${origin}${releasePrefix}styles/Application.css`, method: "GET", body: undefined, status: 404 }),
    ], { ...releaseOptions, label: "404 asset manifest" }),
    /was not successfully requested|HTTP 200/,
  );
  assert.throws(
    () => assertManifestAssetsRequested({ entry: "https://evil.example/remote.js" }, manifestUrl, [], {
      ...releaseOptions,
      requiredExposedModule: undefined,
      label: "foreign asset manifest",
    }),
    /escaped the expected origin|escaped its expected release path/,
  );

  for (const invalidUrl of [
    `${origin}/assets/application-host/telemetry-decom/mf-manifest.json`,
    `${origin}/releases/comms_overview/${releaseId}/artifacts/mf-manifest.json`,
    `${origin}/releases/telemetry_decom/sha256:${"b".repeat(64)}/artifacts/mf-manifest.json`,
    `${origin}${releasePrefix}remoteEntry.js`,
  ]) {
    assert.throws(
      () => assertReleaseArtifactUrl(invalidUrl, origin, {
        applicationKey: "telemetry_decom",
        releaseId,
        artifactPath: "mf-manifest.json",
        label: "invalid release manifest",
      }),
      /escaped its expected release path|path changed/,
      `invalid manifest URL was accepted: ${invalidUrl}`,
    );
  }

  for (const invalidAsset of [
    `${origin}/assets/application-host/telemetry-decom/remoteEntry.js`,
    `${origin}/releases/comms_overview/${releaseId}/artifacts/remoteEntry.js`,
    `${origin}/releases/telemetry_decom/sha256:${"b".repeat(64)}/artifacts/remoteEntry.js`,
  ]) {
    assert.throws(
      () => assertManifestAssetsRequested(
        { entry: new URL(invalidAsset).href },
        manifestUrl,
        [],
        { ...releaseOptions, requiredExposedModule: undefined, label: "invalid release asset" },
      ),
      /escaped its expected release path/,
      `invalid asset URL was accepted: ${invalidAsset}`,
    );
  }
});

test("immutable release artifacts advertise safe reuse and reject opaque cache sources", () => {
  const releaseId = `sha256:${"a".repeat(64)}`;
  const artifact = record({
    url: `${origin}${releaseArtifactPrefix("telemetry_decom", releaseId)}mf-manifest.json`,
    method: "GET",
    body: undefined,
    resourceType: "Fetch",
    responseHeaders: {
      "cache-control": "public, max-age=31536000, immutable",
      etag: `"${releaseId}"`,
    },
    servedFromCache: true,
  });
  assert.doesNotThrow(() => assertImmutableArtifactResponse(artifact, "cached manifest"));
  assert.equal(
    assertImmutableReleaseCacheReuse(
      [artifact],
      [{ applicationKey: "telemetry_decom", releaseId }],
      "cached release",
    ).length,
    1,
  );

  for (const invalid of [
    { responseHeaders: { "cache-control": "public, max-age=60" } },
    { responseHeaders: { "cache-control": "public, max-age=31536000, immutable", etag: "W/\"weak\"" } },
    { fromServiceWorker: true },
    { fromPrefetchCache: true },
  ]) {
    const invalidRecord = {
      ...artifact,
      response: {
        ...artifact.response,
        headers: invalid.responseHeaders || artifact.response.headers,
        fromServiceWorker: invalid.fromServiceWorker || false,
        fromPrefetchCache: invalid.fromPrefetchCache || false,
      },
    };
    assert.throws(
      () => assertImmutableArtifactResponse(invalidRecord, "invalid cached manifest"),
      /immutable|ETag|service worker|prefetch/,
    );
  }
});

test("conditional 304 cancellation is accepted only with exact ExtraInfo evidence", () => {
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
    };
  };
  const url = `${origin}/releases/telemetry_decom/${`sha256:${"a".repeat(64)}`}/artifacts/mf-manifest.json`;
  const etag = `"sha256:${"a".repeat(64)}"`;
  const client = diagnosticClient();
  const diagnostics = installDiagnostics(client, { expectedOrigin: origin });
  const generation = diagnostics.beginRequestGeneration("conditional manifest revalidation");

  client.emit("Network.requestWillBeSent", {
    requestId: "conditional-304",
    request: { url, method: "GET", headers: { "If-None-Match": etag } },
    type: "Fetch",
  });
  client.emit("Network.requestWillBeSentExtraInfo", {
    requestId: "conditional-304",
    headers: { "If-None-Match": etag },
  });
  client.emit("Network.responseReceived", {
    requestId: "conditional-304",
    response: { url, status: 304 },
    type: "Fetch",
  });
  client.emit("Network.responseReceivedExtraInfo", {
    requestId: "conditional-304",
    statusCode: 304,
    headers: { etag },
  });
  client.emit("Network.loadingFailed", {
    requestId: "conditional-304",
    errorText: "net::ERR_ABORTED",
    canceled: true,
  });

  const accepted = diagnostics.requests.get("conditional-304");
  assert.equal(accepted.generation, generation.id);
  assert.equal(accepted.finished, false);
  assert.equal(accepted.failed, "net::ERR_ABORTED (canceled)");
  assert.equal(accepted.requestExtra.headers["If-None-Match"], etag);
  assert.equal(accepted.responseExtra.statusCode, 304);
  assert.doesNotThrow(() => diagnostics.assertClean("conditional 304"));
  diagnostics.dispose();

  const rejectedClient = diagnosticClient();
  const rejectedDiagnostics = installDiagnostics(rejectedClient, { expectedOrigin: origin });
  rejectedClient.emit("Network.requestWillBeSent", {
    requestId: "conditional-200",
    request: { url, method: "GET", headers: { "If-None-Match": etag } },
    type: "Fetch",
  });
  rejectedClient.emit("Network.responseReceivedExtraInfo", {
    requestId: "conditional-200",
    statusCode: 200,
    headers: { etag },
  });
  rejectedClient.emit("Network.loadingFailed", {
    requestId: "conditional-200",
    errorText: "net::ERR_ABORTED",
    canceled: true,
  });
  assert.throws(() => rejectedDiagnostics.assertClean("non-304 cancellation"), /browser diagnostics failed/);
  rejectedDiagnostics.dispose();
});

test("the cache-enabled federation browser gate never disables Chrome cache", async () => {
  const source = await readFile(new URL("./federation_browser_smoke.mjs", import.meta.url), "utf8");
  assert.equal(source.includes("Network.setCacheDisabled"), false);
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
    generation: 2,
    boundToRequest: true,
    causalRequestId: "auth-request",
    observedSequence: 1,
    url: `${origin.replace("http:", "ws:")}/live/websocket?vsn=2.0.0`,
    handshakeRequest: { headers: { Origin: origin } },
    handshake: { status: 101 },
    error: undefined,
  };
  const diagnostics = {
    webSockets: new Map([
      ["live-ws-old", { ...connected, requestId: "live-ws-old", generation: 1 }],
      [connected.requestId, connected],
    ]),
    webSocketFailures: [],
    requests: new Map(),
    consoleErrors: [],
    logErrors: [],
  };
  assert.equal(
    assertLiveViewWebSocket(diagnostics, origin, {
      beforeRequestIds: new Set(["live-ws-old"]),
      generation: { id: 2, causalRequestId: "auth-request", causalRequestSequence: 1 },
    }),
    connected,
  );
  const secureConnected = {
    ...connected,
    requestId: "live-wss-1",
    url: `${origin.replace("http:", "wss:")}/live/websocket?vsn=2.0.0`,
    handshakeRequest: { headers: { Origin: origin.replace("http:", "https:") } },
  };
  assert.equal(
    assertLiveViewWebSocket(
      { ...diagnostics, webSockets: new Map([[secureConnected.requestId, secureConnected]]) },
      origin.replace("http:", "https:"),
      { generation: { id: 2, causalRequestId: "auth-request", causalRequestSequence: 1 } },
    ),
    secureConnected,
  );

  for (const invalid of [
    { ...connected, url: "wss://evil.example/live/websocket?vsn=2.0.0" },
    { ...connected, url: `${origin}/live/websocket?vsn=2.0.0` },
    { ...connected, handshake: { status: 403 } },
    { ...connected, handshakeRequest: { headers: { Origin: "http://127.0.0.1:4101" } } },
    { ...connected, error: "WebSocket handshake failed" },
    { ...connected, closed: true },
  ]) {
    assert.throws(
      () => assertLiveViewWebSocket({ ...diagnostics, webSockets: new Map([[invalid.requestId, invalid]]) }, origin),
      /same-origin HTTP 101 handshake|did not create a websocket transport/,
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

test("delayed websocket events without a request-boundary record fail closed", () => {
  const listeners = new Map();
  const client = {
    on(method, listener) {
      const methodListeners = listeners.get(method) || new Set();
      methodListeners.add(listener);
      listeners.set(method, methodListeners);
      return () => methodListeners.delete(listener);
    },
    emit(method, event) {
      for (const listener of listeners.get(method) || []) listener(event);
    },
  };
  const diagnostics = installDiagnostics(client, { expectedOrigin: origin });
  const requestId = "delayed-live-ws";
  const url = `${origin.replace("http:", "ws:")}/live/websocket?vsn=2.0.0`;
  const responseOnlySocketId = "delayed-live-ws-response-only";

  // The socket was observed before the authenticated generation boundary, but
  // its queued events are delivered after that boundary.
  client.emit("Network.webSocketCreated", { requestId, url });
  client.emit("Network.responseReceived", {
    requestId: responseOnlySocketId,
    response: { url, status: 101 },
    type: "WebSocket",
  });
  client.emit("Network.webSocketCreated", { requestId: responseOnlySocketId, url });
  const generation = diagnostics.beginRequestGeneration("authenticated sign-in");
  client.emit("Network.webSocketWillSendHandshakeRequest", {
    requestId,
    request: { url, headers: { Origin: origin } },
  });
  client.emit("Network.webSocketHandshakeResponseReceived", {
    requestId,
    response: { url, status: 101 },
  });

  assert.equal(diagnostics.webSockets.get(requestId).boundToRequest, false);
  assert.throws(
    () => assertLiveViewWebSocket(diagnostics, origin, { generation }),
    /did not create a websocket transport/,
  );

  client.emit("Network.requestWillBeSent", {
    requestId,
    request: { url, method: "GET", headers: {} },
    type: "WebSocket",
  });
  assert.equal(diagnostics.webSockets.get(requestId).boundToRequest, false);
  assert.throws(
    () => assertLiveViewWebSocket(diagnostics, origin, { generation }),
    /did not create a websocket transport/,
  );
  client.emit("Network.requestWillBeSent", {
    requestId: responseOnlySocketId,
    request: { url, method: "GET", headers: {} },
    type: "WebSocket",
  });
  assert.equal(diagnostics.webSockets.get(responseOnlySocketId).boundToRequest, false);

  // A socket first observed after the generation boundary is also not enough:
  // it must follow the exact authenticated navigation request.
  const observedOnlyId = "observed-after-boundary-only";
  client.emit("Network.webSocketCreated", { requestId: observedOnlyId, url });
  client.emit("Network.webSocketWillSendHandshakeRequest", {
    requestId: observedOnlyId,
    request: { url, headers: { Origin: origin } },
  });
  client.emit("Network.webSocketHandshakeResponseReceived", {
    requestId: observedOnlyId,
    response: { url, status: 101 },
  });
  assert.equal(diagnostics.webSockets.get(observedOnlyId).boundToRequest, false);

  client.emit("Network.requestWillBeSent", {
    requestId: "auth-request",
    request: { url: `${origin}/sign-in`, method: "POST", headers: {} },
    type: "Document",
    frameId: "main-frame",
    loaderId: "auth-loader",
  });
  const authRequest = diagnostics.requests.get("auth-request");
  diagnostics.bindRequestGeneration(generation, authRequest);
  assert.equal(diagnostics.webSockets.get(requestId).boundToRequest, false);
  assert.equal(diagnostics.webSockets.get(observedOnlyId).boundToRequest, false);

  const boundRequestId = "causally-bound-live-ws";
  client.emit("Network.webSocketCreated", { requestId: boundRequestId, url });
  client.emit("Network.webSocketWillSendHandshakeRequest", {
    requestId: boundRequestId,
    request: { url, headers: { Origin: origin } },
  });
  client.emit("Network.webSocketHandshakeResponseReceived", {
    requestId: boundRequestId,
    response: { url, status: 101 },
  });
  assert.equal(diagnostics.webSockets.get(boundRequestId).boundToRequest, true);
  assert.equal(
    assertLiveViewWebSocket(diagnostics, origin, { generation }).requestId,
    boundRequestId,
  );

  const responseOnlyId = "delayed-response-without-request";
  client.emit("Network.responseReceived", {
    requestId: responseOnlyId,
    response: { url: `${origin}/api/current-generation`, status: 200 },
    type: "XHR",
  });
  client.emit("Network.loadingFinished", { requestId: responseOnlyId });
  assert.deepEqual(
    diagnostics.completed(() => true, { generation }),
    [],
    "response without a causally bound request was admitted to the generation",
  );
  diagnostics.dispose();
});

test("authenticated navigation causality requires the exact sign-in pathname", () => {
  const base = {
    method: "POST",
    resourceType: "Document",
    frameId: "main-frame",
    loaderId: "auth-loader",
  };

  for (const [pathname, expected] of [
    ["/sign-in", true],
    ["/sign-in?return_to=%2Fmissions#form", true],
    ["/sign-in/", false],
    ["/sign-in-extra", false],
    ["/sign-in/extra", false],
    ["/users/log_in", false],
  ]) {
    assert.equal(
      matchesSignInNavigationRequest({ ...base, url: `${origin}${pathname}` }, { expectedOrigin: origin }),
      expected,
      `sign-in request pathname ${pathname} admission mismatch`,
    );
  }
  assert.equal(
    matchesSignInNavigationRequest({ ...base, url: "https://evil.example/sign-in" }, { expectedOrigin: origin }),
    false,
    "a cross-origin document POST must not bind authenticated navigation",
  );
  assert.equal(
    matchesSignInNavigationRequest({ ...base, url: "not-a-url" }, { expectedOrigin: origin }),
    false,
    "malformed request URLs must fail closed",
  );
  assert.equal(
    matchesSignInNavigationRequest(
      { ...base, url: `${origin}/sign-in` },
      { expectedOrigin: origin, pathname: "/sign-in-extra" },
    ),
    true,
    "a caller-supplied pathname cannot redefine the literal sign-in path",
  );
  assert.equal(
    matchesSignInNavigationRequest(
      { ...base, url: `${origin}/sign-in-extra` },
      { expectedOrigin: origin, pathname: "/sign-in-extra" },
    ),
    false,
    "a caller-supplied alternate pathname cannot admit that request",
  );
});

test("sign-in URL validation allows only query/hash variation and runs before navigation", async () => {
  for (const url of [
    `${origin}/sign-in`,
    `${origin}/sign-in?return_to=%2Fmissions#form`,
  ]) {
    assert.equal(assertSignInUrl(url, origin).pathname, "/sign-in");
  }

  for (const url of [
    `${origin}/sign-in/`,
    `${origin}/sign-in-extra`,
    `${origin}/sign-in/extra`,
    `${origin}/users/log_in`,
    "https://evil.example/sign-in",
    "not-a-url",
  ]) {
    assert.throws(
      () => assertSignInUrl(url, origin),
      /exact \/sign-in pathname|escaped the expected origin|Invalid URL/,
      `invalid sign-in URL was accepted: ${url}`,
    );
  }

  let clientAccessed = false;
  const client = new Proxy({}, {
    get() {
      clientAccessed = true;
      throw new Error("browser navigation was reached before sign-in URL validation");
    },
  });
  await assert.rejects(
    runScenario(client, {}, [
      "--comms-url", `${origin}/missions/mission-1/applications/comms_overview/federated`,
      "--telemetry-url", `${origin}/missions/mission-1/telemetry/federated`,
      "--login-url", `${origin}/sign-in-extra`,
      "--login-email", "operator@example.test",
      "--mission-id", "mission-1",
      "--spacecraft-id", "spacecraft-1",
      "--catalog-revision-id", "catalog-1",
      "--source-endpoint-id", "source-1",
      "--expected-apid", "42",
    ], { secret: { password: "secret" } }),
    /exact \/sign-in pathname/,
  );
  assert.equal(clientAccessed, false, "invalid sign-in URL reached browser navigation");
});

test("binary admission and diagnostics redact secrets without argv or environment transport", () => {
  assert.equal(resolveChromeBinary({ env: { CHROME_BIN: "/missing" }, candidates: ["/also-missing"], fileExists: () => false }), undefined);
  for (const args of [
    ["--login-email", "operator@example.test", "--login-password", "secret"],
    ["--login-email", "operator@example.test", "--login-password=secret"],
    ["--login-password", "inline-secret-without-an-argv-leak"],
  ]) {
    assert.throws(
      () => assertNoPasswordArgument(args),
      (error) => /structured stdin/.test(error.message) && !error.message.includes("secret"),
    );
  }
  const secret = "correct-horse-battery-staple";
  assert.equal(redactText(`argv=[] failure=${secret}`, [secret]).includes(secret), false);
});

test("waitForResponse selects the newest completed response in the requested generation", async () => {
  const generation = { id: 9 };
  const stale = record({ requestId: "query-stale", sequence: 10 });
  const newest = record({ requestId: "query-newest", sequence: 11 });
  const seenOptions = [];
  const diagnostics = {
    completed(predicate, options) {
      seenOptions.push(options);
      return [stale, newest].filter(predicate);
    },
  };

  const result = await waitForResponse(diagnostics, () => true, "duplicate query", { generation });
  assert.equal(result.requestId, "query-newest");
  assert.deepEqual(seenOptions, [{ generation }]);
});

test("navigation completion discards queued prior-page events and requires the exact loader", async () => {
  const listeners = new Map();
  const client = {
    on(method, listener) {
      const methodListeners = listeners.get(method) || new Set();
      methodListeners.add(listener);
      listeners.set(method, methodListeners);
      return () => methodListeners.delete(listener);
    },
    emit(method, event) {
      for (const listener of listeners.get(method) || []) listener(event);
    },
  };
  const oldFrame = { id: "frame-1", loaderId: "loader-old", url: `${origin}/old` };
  const currentFrame = { id: "frame-1", loaderId: "loader-new", url: `${origin}/current` };

  const completed = await waitForPageNavigation(
    client,
    async () => {
      client.emit("Page.frameNavigated", { frame: oldFrame });
      client.emit("Page.loadEventFired", { timestamp: 1 });
      client.emit("Page.lifecycleEvent", {
        frameId: oldFrame.id,
        loaderId: oldFrame.loaderId,
        name: "load",
        timestamp: 1,
      });
      await Promise.resolve();
      client.emit("Page.frameNavigated", { frame: currentFrame });
      // Page.loadEventFired has no loader/frame provenance. A queued old-page
      // event after the new frame must not satisfy this navigation.
      client.emit("Page.loadEventFired", { timestamp: 1 });
      client.emit("Page.lifecycleEvent", {
        frameId: currentFrame.id,
        loaderId: currentFrame.loaderId,
        name: "load",
        timestamp: 2,
      });
      client.emit("Page.loadEventFired", { frameId: currentFrame.id, timestamp: 2 });
      return { frameId: currentFrame.id, loaderId: currentFrame.loaderId };
    },
    { timeout: 100 },
  );

  assert.equal(completed.result.loaderId, "loader-new");
  assert.equal(completed.frame.loaderId, "loader-new");
  assert.equal(completed.load.frameId, "frame-1");

  await assert.rejects(
    waitForPageNavigation(
      client,
      async () => {
        client.emit("Page.frameNavigated", { frame: oldFrame });
        client.emit("Page.loadEventFired", {});
        client.emit("Page.lifecycleEvent", {
          frameId: oldFrame.id,
          loaderId: oldFrame.loaderId,
          name: "load",
          timestamp: 1,
        });
        return { frameId: oldFrame.id, loaderId: "loader-new" };
      },
      { timeout: 10 },
    ),
    /completion timed out/,
  );
});

test("navigation ignores an equal-timestamp Page.loadEventFired until exact lifecycle proof", async () => {
  const listeners = new Map();
  const client = {
    on(method, listener) {
      const methodListeners = listeners.get(method) || new Set();
      methodListeners.add(listener);
      listeners.set(method, methodListeners);
      return () => methodListeners.delete(listener);
    },
    emit(method, event) {
      for (const listener of listeners.get(method) || []) listener(event);
    },
  };
  const currentFrame = { id: "main-frame", loaderId: "loader-current", url: `${origin}/current` };
  const lifecycleLoad = {
    frameId: currentFrame.id,
    loaderId: currentFrame.loaderId,
    name: "load",
    timestamp: 7,
  };
  let settledBeforeLifecycle = false;

  const navigation = waitForPageNavigation(
    client,
    async () => {
      client.emit("Page.frameNavigated", { frame: currentFrame });
      // Page.loadEventFired has no loader provenance. Its equal timestamp is
      // deliberately queued before the exact lifecycle proof.
      client.emit("Page.loadEventFired", { timestamp: lifecycleLoad.timestamp });
      await new Promise((resolveImmediate) => setImmediate(resolveImmediate));
      assert.equal(
        settledBeforeLifecycle,
        false,
        "an unproven Page.loadEventFired must not settle navigation",
      );
      client.emit("Page.lifecycleEvent", lifecycleLoad);
      return { frameId: currentFrame.id, loaderId: currentFrame.loaderId };
    },
    { timeout: 100 },
  );
  navigation.then(
    () => { settledBeforeLifecycle = true; },
    () => { settledBeforeLifecycle = true; },
  );

  const completed = await navigation;
  assert.equal(
    settledBeforeLifecycle,
    true,
    "navigation did not settle after the exact lifecycle proof",
  );
  assert.deepEqual(
    completed.load,
    lifecycleLoad,
    "navigation evidence must come from the exact frame/loader lifecycle event",
  );
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
