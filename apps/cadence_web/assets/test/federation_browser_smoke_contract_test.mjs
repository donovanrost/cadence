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

function makeDiagnosticClient() {
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
    waitForEvent(method, predicate = () => true, timeout = 30_000) {
      return new Promise((resolveEvent, rejectEvent) => {
        let settled = false;
        let off;
        const finish = (callback, value) => {
          if (settled) return;
          settled = true;
          clearTimeout(timer);
          off?.();
          callback(value);
        };
        const timer = setTimeout(
          () => finish(rejectEvent, new Error(`synthetic ${method} timed out after ${timeout}ms`)),
          timeout,
        );
        off = this.on(method, (event) => {
          if (predicate(event)) finish(resolveEvent, event);
        });
      });
    },
  };
}

function emitCanonicalNetworkResourceError(client, url, requestId = "expected-403", status = 403) {
  client.emit("Log.entryAdded", {
    entry: {
      source: "network",
      level: "error",
      text: `Failed to load resource: the server responded with a status of ${status} (Forbidden)`,
      url,
      networkRequestId: requestId,
    },
  });
}

function emitExpectedActionRequest(client, requestId, url) {
  client.emit("Network.requestWillBeSent", {
    requestId,
    request: { url, method: "POST", headers: {} },
    type: "XHR",
  });
}

function emitActionResponse(client, requestId, url, status) {
  client.emit("Network.responseReceived", {
    requestId,
    response: { url, status },
    type: "XHR",
  });
}

function emitActionExtraInfo(client, requestId, statusCode) {
  client.emit("Network.responseReceivedExtraInfo", {
    requestId,
    statusCode,
    headers: {},
  });
}

function emitActionLoadingFailed(client, requestId, errorText) {
  client.emit("Network.loadingFailed", { requestId, errorText });
}

function assertDirty(diagnostics, label) {
  let failure;
  assert.throws(
    () => diagnostics.assertClean(label),
    (error) => {
      failure = error;
      return /browser diagnostics failed/.test(error.message);
    },
  );
  return failure.message;
}

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

test("one canonical delayed Chrome network resource error is attributed to one exact expected 403", () => {
  const client = makeDiagnosticClient();
  const diagnostics = installDiagnostics(client, { expectedOrigin: origin });
  const url = `${origin}/api/cadence/application-host/v1/missions/mission-1/spacecraft/spacecraft-1/actions`;
  const removeAllowance = diagnostics.allowExpectedFailure(
    (candidate) => candidate.method === "POST" && candidate.url === url,
    { status: 403 },
  );

  client.emit("Network.requestWillBeSent", {
    requestId: "expected-403",
    request: { url, method: "POST", headers: {} },
    type: "XHR",
  });
  client.emit("Network.responseReceived", {
    requestId: "expected-403",
    response: { url, status: 403 },
    type: "XHR",
  });
  client.emit("Network.loadingFinished", { requestId: "expected-403" });
  emitCanonicalNetworkResourceError(client, url);
  assert.doesNotThrow(() => diagnostics.assertClean("expected CSRF rejection"));
  removeAllowance();
  diagnostics.dispose();
});

test("cleanup replays one consumed canonical log exactly once after a finished expected request", () => {
  const client = makeDiagnosticClient();
  const diagnostics = installDiagnostics(client, { expectedOrigin: origin });
  const url = `${origin}/api/cadence/application-host/v1/missions/mission-1/spacecraft/spacecraft-1/actions`;
  const removeAllowance = diagnostics.allowExpectedFailure(
    (candidate) => candidate.method === "POST" && candidate.url === url,
    { status: 403 },
  );

  emitExpectedActionRequest(client, "cleanup-consumed-log", url);
  emitActionResponse(client, "cleanup-consumed-log", url, 403);
  emitCanonicalNetworkResourceError(client, url, "cleanup-consumed-log");
  client.emit("Network.loadingFinished", { requestId: "cleanup-consumed-log" });
  assert.doesNotThrow(() => diagnostics.assertClean("finished expected 403 baseline"));

  removeAllowance();
  removeAllowance();
  const failure = assertDirty(diagnostics, "cleanup replayed canonical log");
  assert.equal(diagnostics.logErrors.length, 1);
  assert.equal((failure.match(/Failed to load resource/g) || []).length, 1);
  diagnostics.dispose();
  diagnostics.dispose();
  assert.equal(diagnostics.logErrors.length, 1);
});

test("cleanup replays one suppressed loadingFailed evidence exactly once after a finished expected request", () => {
  const client = makeDiagnosticClient();
  const diagnostics = installDiagnostics(client, { expectedOrigin: origin });
  const url = `${origin}/api/cadence/application-host/v1/missions/mission-1/spacecraft/spacecraft-1/actions`;
  const removeAllowance = diagnostics.allowExpectedFailure(
    (candidate) => candidate.method === "POST" && candidate.url === url,
    { status: 403 },
  );

  emitExpectedActionRequest(client, "cleanup-suppressed-failure", url);
  emitActionResponse(client, "cleanup-suppressed-failure", url, 403);
  emitActionLoadingFailed(client, "cleanup-suppressed-failure", "net::ERR_EXPECTED_FAILURE");
  assert.doesNotThrow(() => diagnostics.assertClean("finished expected 403 failure baseline"));

  removeAllowance();
  const failure = assertDirty(diagnostics, "cleanup replayed loading failure");
  assert.equal(diagnostics.requestFailures.length, 1);
  assert.match(failure, /ERR_EXPECTED_FAILURE/);
  removeAllowance();
  diagnostics.dispose();
  diagnostics.dispose();
  assert.equal(diagnostics.requestFailures.length, 1);
});

test("dispose replays consumed canonical log evidence exactly once", () => {
  const client = makeDiagnosticClient();
  const diagnostics = installDiagnostics(client, { expectedOrigin: origin });
  const url = `${origin}/api/cadence/application-host/v1/missions/mission-1/spacecraft/spacecraft-1/actions`;
  diagnostics.allowExpectedFailure(
    (candidate) => candidate.method === "POST" && candidate.url === url,
    { status: 403 },
  );

  emitExpectedActionRequest(client, "dispose-consumed-log", url);
  emitActionResponse(client, "dispose-consumed-log", url, 403);
  emitCanonicalNetworkResourceError(client, url, "dispose-consumed-log");
  client.emit("Network.loadingFinished", { requestId: "dispose-consumed-log" });
  assert.doesNotThrow(() => diagnostics.assertClean("dispose consumed log baseline"));

  diagnostics.dispose();
  const failure = assertDirty(diagnostics, "dispose replayed canonical log");
  assert.equal(diagnostics.logErrors.length, 1);
  assert.equal((failure.match(/Failed to load resource/g) || []).length, 1);
  diagnostics.dispose();
  assert.equal(diagnostics.logErrors.length, 1);
});

test("dispose replays suppressed loadingFailed evidence exactly once", () => {
  const client = makeDiagnosticClient();
  const diagnostics = installDiagnostics(client, { expectedOrigin: origin });
  const url = `${origin}/api/cadence/application-host/v1/missions/mission-1/spacecraft/spacecraft-1/actions`;
  diagnostics.allowExpectedFailure(
    (candidate) => candidate.method === "POST" && candidate.url === url,
    { status: 403 },
  );

  emitExpectedActionRequest(client, "dispose-suppressed-failure", url);
  emitActionResponse(client, "dispose-suppressed-failure", url, 403);
  emitActionLoadingFailed(client, "dispose-suppressed-failure", "net::ERR_DISPOSED_EXPECTED_FAILURE");
  assert.doesNotThrow(() => diagnostics.assertClean("dispose loading failure baseline"));

  diagnostics.dispose();
  const failure = assertDirty(diagnostics, "dispose replayed loading failure");
  assert.equal(diagnostics.requestFailures.length, 1);
  assert.match(failure, /ERR_DISPOSED_EXPECTED_FAILURE/);
  diagnostics.dispose();
  assert.equal(diagnostics.requestFailures.length, 1);
});

test("a waitForRequest timeout does not discard consumed evidence before cleanup", async () => {
  const client = makeDiagnosticClient();
  const diagnostics = installDiagnostics(client, { expectedOrigin: origin });
  const url = `${origin}/api/cadence/application-host/v1/missions/mission-1/spacecraft/spacecraft-1/actions`;
  const removeAllowance = diagnostics.allowExpectedFailure(
    (candidate) => candidate.method === "POST" && candidate.url === url,
    { status: 403 },
  );
  const generation = diagnostics.beginRequestGeneration("synthetic timeout");

  emitExpectedActionRequest(client, "wait-timeout-consumed", url);
  emitActionResponse(client, "wait-timeout-consumed", url, 403);
  emitCanonicalNetworkResourceError(client, url, "wait-timeout-consumed");
  client.emit("Network.loadingFinished", { requestId: "wait-timeout-consumed" });
  assert.doesNotThrow(() => diagnostics.assertClean("wait timeout baseline"));

  await assert.rejects(
    diagnostics.waitForRequest(generation, () => false, "synthetic waitForRequest", { timeout: 1 }),
    /timed out/,
  );
  removeAllowance();
  const failure = assertDirty(diagnostics, "wait timeout cleanup replay");
  assert.equal(diagnostics.logErrors.length, 1);
  assert.equal((failure.match(/Failed to load resource/g) || []).length, 1);
  diagnostics.dispose();
});

test("repeated cleanup and dispose combinations replay consumed and suppressed evidence once", () => {
  const client = makeDiagnosticClient();
  const diagnostics = installDiagnostics(client, { expectedOrigin: origin });
  const url = `${origin}/api/cadence/application-host/v1/missions/mission-1/spacecraft/spacecraft-1/actions`;
  const removeAllowance = diagnostics.allowExpectedFailure(
    (candidate) => candidate.method === "POST" && candidate.url === url,
    { status: 403 },
  );

  emitExpectedActionRequest(client, "repeated-invalidation", url);
  emitActionResponse(client, "repeated-invalidation", url, 403);
  emitCanonicalNetworkResourceError(client, url, "repeated-invalidation");
  emitActionLoadingFailed(client, "repeated-invalidation", "net::ERR_REPEATED_INVALIDATION");
  assert.doesNotThrow(() => diagnostics.assertClean("repeated invalidation baseline"));

  removeAllowance();
  diagnostics.dispose();
  removeAllowance();
  diagnostics.dispose();
  const failure = assertDirty(diagnostics, "repeated invalidation replay");
  assert.equal(diagnostics.logErrors.length, 1);
  assert.equal(diagnostics.requestFailures.length, 1);
  assert.equal((failure.match(/Failed to load resource/g) || []).length, 1);
  assert.equal((failure.match(/ERR_REPEATED_INVALIDATION/g) || []).length, 1);
});

test("a canonical network resource error without networkRequestId remains visible", () => {
  const client = makeDiagnosticClient();
  const diagnostics = installDiagnostics(client, { expectedOrigin: origin });
  const url = `${origin}/api/cadence/application-host/v1/missions/mission-1/spacecraft/spacecraft-1/actions`;
  const removeAllowance = diagnostics.allowExpectedFailure(
    (candidate) => candidate.method === "POST" && candidate.url === url,
    { status: 403 },
  );

  emitExpectedActionRequest(client, "expected-403", url);
  emitActionResponse(client, "expected-403", url, 403);
  client.emit("Log.entryAdded", {
    entry: {
      source: "network",
      level: "error",
      text: "Failed to load resource: the server responded with a status of 403 (Forbidden)",
      url,
    },
  });

  assert.match(assertDirty(diagnostics, "missing network request ID"), /Failed to load resource/);
  removeAllowance();
  diagnostics.dispose();
});

test("unmatched canonical logs are visible immediately without pending retention", () => {
  const client = makeDiagnosticClient();
  const diagnostics = installDiagnostics(client, { expectedOrigin: origin });
  const url = `${origin}/api/cadence/application-host/v1/missions/mission-1/spacecraft/spacecraft-1/actions`;
  const removeAllowance = diagnostics.allowExpectedFailure(
    (candidate) => candidate.method === "POST" && candidate.url === url,
    { status: 403 },
  );

  for (let index = 0; index < 10_000; index += 1) {
    emitCanonicalNetworkResourceError(client, url, `unmatched-${index}`);
  }

  assert.equal(diagnostics.logErrors.length, 10_000);
  assert.equal(diagnostics.requests.size, 0);
  removeAllowance();
  diagnostics.dispose();
});

test("one exact active expected request holds at most one canonical log", () => {
  const client = makeDiagnosticClient();
  const diagnostics = installDiagnostics(client, { expectedOrigin: origin });
  const url = `${origin}/api/cadence/application-host/v1/missions/mission-1/spacecraft/spacecraft-1/actions`;
  const removeAllowance = diagnostics.allowExpectedFailure(
    (candidate) => candidate.method === "POST" && candidate.url === url,
    { status: 403 },
  );

  emitExpectedActionRequest(client, "held-403", url);
  emitCanonicalNetworkResourceError(client, url, "held-403");
  assert.equal(
    diagnostics.requests.get("held-403").pendingExpectedFailureLog.entry.networkRequestId,
    "held-403",
  );
  for (let index = 0; index < 9_999; index += 1) {
    emitCanonicalNetworkResourceError(client, url, "held-403");
  }
  assert.equal(diagnostics.logErrors.length, 9_999);
  assert.ok(diagnostics.requests.get("held-403").pendingExpectedFailureLog);

  emitActionResponse(client, "held-403", url, 403);
  client.emit("Network.loadingFinished", { requestId: "held-403" });
  assert.equal(diagnostics.requests.get("held-403").pendingExpectedFailureLog, undefined);
  assert.equal(diagnostics.logErrors.length, 9_999);
  const failure = assertDirty(diagnostics, "duplicate held canonical logs");
  assert.equal((failure.match(/Failed to load resource/g) || []).length, 9_999);
  removeAllowance();
  diagnostics.dispose();
});

test("a held canonical log surfaces when cleanup completes without a valid allowance", () => {
  const client = makeDiagnosticClient();
  const diagnostics = installDiagnostics(client, { expectedOrigin: origin });
  const url = `${origin}/api/cadence/application-host/v1/missions/mission-1/spacecraft/spacecraft-1/actions`;
  const removeAllowance = diagnostics.allowExpectedFailure(
    (candidate) => candidate.method === "POST" && candidate.url === url,
    { status: 403 },
  );

  emitExpectedActionRequest(client, "unfinished-403", url);
  emitCanonicalNetworkResourceError(client, url, "unfinished-403");
  assert.equal(diagnostics.logErrors.length, 0);
  assert.ok(diagnostics.requests.get("unfinished-403").pendingExpectedFailureLog);
  diagnostics.dispose();
  assert.equal(diagnostics.logErrors.length, 1);
  assert.equal(diagnostics.requests.get("unfinished-403").pendingExpectedFailureLog, undefined);
  removeAllowance();
});

test("a held canonical log surfaces when request completion precedes valid evidence", () => {
  const client = makeDiagnosticClient();
  const diagnostics = installDiagnostics(client, { expectedOrigin: origin });
  const url = `${origin}/api/cadence/application-host/v1/missions/mission-1/spacecraft/spacecraft-1/actions`;
  const removeAllowance = diagnostics.allowExpectedFailure(
    (candidate) => candidate.method === "POST" && candidate.url === url,
    { status: 403 },
  );

  emitExpectedActionRequest(client, "completed-without-status", url);
  emitCanonicalNetworkResourceError(client, url, "completed-without-status");
  client.emit("Network.loadingFinished", { requestId: "completed-without-status" });
  assert.equal(diagnostics.logErrors.length, 1);
  assert.equal(diagnostics.requests.get("completed-without-status").pendingExpectedFailureLog, undefined);
  removeAllowance();
  diagnostics.dispose();
});

test("a consumed canonical log is restored exactly once after response status contradiction", () => {
  const client = makeDiagnosticClient();
  const diagnostics = installDiagnostics(client, { expectedOrigin: origin });
  const url = `${origin}/api/cadence/application-host/v1/missions/mission-1/spacecraft/spacecraft-1/actions`;
  const removeAllowance = diagnostics.allowExpectedFailure(
    (candidate) => candidate.method === "POST" && candidate.url === url,
    { status: 403 },
  );

  emitExpectedActionRequest(client, "response-contradiction", url);
  emitActionResponse(client, "response-contradiction", url, 403);
  emitCanonicalNetworkResourceError(client, url, "response-contradiction");
  client.emit("Network.loadingFinished", { requestId: "response-contradiction" });
  emitActionExtraInfo(client, "response-contradiction", 500);

  const first = assertDirty(diagnostics, "response status contradiction");
  assert.equal((first.match(/Failed to load resource/g) || []).length, 1);
  emitActionExtraInfo(client, "response-contradiction", 501);
  removeAllowance();
  removeAllowance();
  const second = assertDirty(diagnostics, "repeated response status contradiction");
  assert.equal((second.match(/Failed to load resource/g) || []).length, 1);
  diagnostics.dispose();
});

test("a consumed canonical log is restored exactly once after ExtraInfo status contradiction", () => {
  const client = makeDiagnosticClient();
  const diagnostics = installDiagnostics(client, { expectedOrigin: origin });
  const url = `${origin}/api/cadence/application-host/v1/missions/mission-1/spacecraft/spacecraft-1/actions`;
  const removeAllowance = diagnostics.allowExpectedFailure(
    (candidate) => candidate.method === "POST" && candidate.url === url,
    { status: 403 },
  );

  emitExpectedActionRequest(client, "extra-info-contradiction", url);
  emitActionExtraInfo(client, "extra-info-contradiction", 403);
  emitCanonicalNetworkResourceError(client, url, "extra-info-contradiction");
  emitActionResponse(client, "extra-info-contradiction", url, 500);
  client.emit("Network.loadingFinished", { requestId: "extra-info-contradiction" });

  const failure = assertDirty(diagnostics, "ExtraInfo status contradiction");
  assert.equal((failure.match(/Failed to load resource/g) || []).length, 1);
  removeAllowance();
  diagnostics.dispose();
});

test("contradiction after a consumed canonical log and loadingFailed restores both diagnostics", () => {
  const client = makeDiagnosticClient();
  const diagnostics = installDiagnostics(client, { expectedOrigin: origin });
  const url = `${origin}/api/cadence/application-host/v1/missions/mission-1/spacecraft/spacecraft-1/actions`;
  const removeAllowance = diagnostics.allowExpectedFailure(
    (candidate) => candidate.method === "POST" && candidate.url === url,
    { status: 403 },
  );

  emitExpectedActionRequest(client, "loading-failed-contradiction", url);
  emitActionResponse(client, "loading-failed-contradiction", url, 403);
  emitCanonicalNetworkResourceError(client, url, "loading-failed-contradiction");
  emitActionLoadingFailed(client, "loading-failed-contradiction", "net::ERR_FAILED_BEFORE_DRIFT");
  assert.equal(diagnostics.logErrors.length, 0);
  assert.equal(diagnostics.requestFailures.length, 0);
  emitActionExtraInfo(client, "loading-failed-contradiction", 500);

  const failure = assertDirty(diagnostics, "canonical and loadingFailed contradiction");
  assert.equal((failure.match(/Failed to load resource/g) || []).length, 1);
  assert.equal((failure.match(/ERR_FAILED_BEFORE_DRIFT/g) || []).length, 1);
  removeAllowance();
  diagnostics.dispose();
});

test("response 403 then ExtraInfo 500 revokes the allowance and restores canonical logs", () => {
  const client = makeDiagnosticClient();
  const diagnostics = installDiagnostics(client, { expectedOrigin: origin });
  const url = `${origin}/api/cadence/application-host/v1/missions/mission-1/spacecraft/spacecraft-1/actions`;
  const removeAllowance = diagnostics.allowExpectedFailure(
    (candidate) => candidate.method === "POST" && candidate.url === url,
    { status: 403 },
  );

  emitExpectedActionRequest(client, "expected-403", url);
  emitActionResponse(client, "expected-403", url, 403);
  emitCanonicalNetworkResourceError(client, url, "expected-403", 403);
  emitActionExtraInfo(client, "expected-403", 500);
  emitCanonicalNetworkResourceError(client, url, "expected-403", 403);

  const failure = assertDirty(diagnostics, "response then ExtraInfo disagreement");
  assert.equal((failure.match(/Failed to load resource/g) || []).length, 2);
  assert.match(failure, /response=403, ExtraInfo=500/);
  removeAllowance();
  diagnostics.dispose();
});

test("ExtraInfo 403 then response 500 revokes the allowance and restores canonical logs", () => {
  const client = makeDiagnosticClient();
  const diagnostics = installDiagnostics(client, { expectedOrigin: origin });
  const url = `${origin}/api/cadence/application-host/v1/missions/mission-1/spacecraft/spacecraft-1/actions`;
  const removeAllowance = diagnostics.allowExpectedFailure(
    (candidate) => candidate.method === "POST" && candidate.url === url,
    { status: 403 },
  );

  emitExpectedActionRequest(client, "expected-403", url);
  emitActionExtraInfo(client, "expected-403", 403);
  emitCanonicalNetworkResourceError(client, url, "expected-403", 403);
  emitActionResponse(client, "expected-403", url, 500);
  emitCanonicalNetworkResourceError(client, url, "expected-403", 403);

  const failure = assertDirty(diagnostics, "ExtraInfo then response disagreement");
  assert.equal((failure.match(/Failed to load resource/g) || []).length, 2);
  assert.match(failure, /ExtraInfo=403, response=500/);
  removeAllowance();
  diagnostics.dispose();
});

test("loadingFailed before and after contradictory status evidence remains visible", () => {
  const client = makeDiagnosticClient();
  const diagnostics = installDiagnostics(client, { expectedOrigin: origin });
  const url = `${origin}/api/cadence/application-host/v1/missions/mission-1/spacecraft/spacecraft-1/actions`;
  const removeAllowance = diagnostics.allowExpectedFailure(
    (candidate) => candidate.method === "POST" && candidate.url === url,
    { status: 403 },
  );

  emitExpectedActionRequest(client, "expected-403", url);
  emitActionResponse(client, "expected-403", url, 403);
  client.emit("Network.loadingFailed", {
    requestId: "expected-403",
    errorText: "net::ERR_FAILED_BEFORE_DRIFT",
  });
  emitActionExtraInfo(client, "expected-403", 500);
  client.emit("Network.loadingFailed", {
    requestId: "expected-403",
    errorText: "net::ERR_FAILED_AFTER_DRIFT",
  });

  const failure = assertDirty(diagnostics, "loading failure status disagreement");
  assert.match(failure, /ERR_FAILED_BEFORE_DRIFT/);
  assert.match(failure, /ERR_FAILED_AFTER_DRIFT/);
  removeAllowance();
  diagnostics.dispose();
});

test("cleanup and event-order permutations never hide a canonical error", () => {
  const url = `${origin}/api/cadence/application-host/v1/missions/mission-1/spacecraft/spacecraft-1/actions`;
  for (const order of ["response-first", "log-first", "request-first", "cleanup-first"]) {
    const client = makeDiagnosticClient();
    const diagnostics = installDiagnostics(client, { expectedOrigin: origin });
    const removeAllowance = diagnostics.allowExpectedFailure(
      (candidate) => candidate.method === "POST" && candidate.url === url,
      { status: 403 },
    );

    if (order !== "cleanup-first") emitExpectedActionRequest(client, "expected-403", url);
    if (order === "response-first") emitActionResponse(client, "expected-403", url, 403);
    if (order === "log-first") emitCanonicalNetworkResourceError(client, url);
    if (order === "log-first") emitActionResponse(client, "expected-403", url, 403);
    if (order === "request-first") {
      emitActionResponse(client, "expected-403", url, 403);
      emitCanonicalNetworkResourceError(client, url);
    }
    if (order === "response-first") emitCanonicalNetworkResourceError(client, url);
    if (order === "cleanup-first") {
      removeAllowance();
      emitExpectedActionRequest(client, "expected-403", url);
      emitActionResponse(client, "expected-403", url, 403);
      emitCanonicalNetworkResourceError(client, url);
    } else {
      removeAllowance();
      emitCanonicalNetworkResourceError(client, url, "unexpected-403");
    }

    assertDirty(diagnostics, `cleanup and ${order}`);
    removeAllowance();
    diagnostics.dispose();
  }
});

test("a distinct same-URL browser error remains visible during an active expected failure", () => {
  const client = makeDiagnosticClient();
  const diagnostics = installDiagnostics(client, { expectedOrigin: origin });
  const url = `${origin}/api/cadence/application-host/v1/missions/mission-1/spacecraft/spacecraft-1/actions`;
  const removeAllowance = diagnostics.allowExpectedFailure(
    (candidate) => candidate.method === "POST" && candidate.url === url,
    { status: 403 },
  );

  client.emit("Network.requestWillBeSent", {
    requestId: "expected-403",
    request: { url, method: "POST", headers: {} },
    type: "XHR",
  });
  client.emit("Network.responseReceived", {
    requestId: "expected-403",
    response: { url, status: 403 },
    type: "XHR",
  });
  emitCanonicalNetworkResourceError(client, url, "unrelated-403");
  assert.throws(() => diagnostics.assertClean("same-URL unrelated error"), /browser diagnostics failed/);
  removeAllowance();
  diagnostics.dispose();
});

test("a duplicate canonical error beyond one exact expected request remains visible", () => {
  const client = makeDiagnosticClient();
  const diagnostics = installDiagnostics(client, { expectedOrigin: origin });
  const url = `${origin}/api/cadence/application-host/v1/missions/mission-1/spacecraft/spacecraft-1/actions`;
  const removeAllowance = diagnostics.allowExpectedFailure(
    (candidate) => candidate.method === "POST" && candidate.url === url,
    { status: 403 },
  );

  client.emit("Network.requestWillBeSent", {
    requestId: "expected-403",
    request: { url, method: "POST", headers: {} },
    type: "XHR",
  });
  client.emit("Network.responseReceived", {
    requestId: "expected-403",
    response: { url, status: 403 },
    type: "XHR",
  });
  emitCanonicalNetworkResourceError(client, url);
  emitCanonicalNetworkResourceError(client, url);
  assert.throws(() => diagnostics.assertClean("duplicate canonical error"), /browser diagnostics failed/);
  removeAllowance();
  diagnostics.dispose();
});

test("unrelated diagnostics stay visible with an active or removed expected-failure registration", () => {
  const url = `${origin}/api/cadence/application-host/v1/missions/mission-1/spacecraft/spacecraft-1/actions`;
  const activeClient = makeDiagnosticClient();
  const activeDiagnostics = installDiagnostics(activeClient, { expectedOrigin: origin });
  const removeActiveAllowance = activeDiagnostics.allowExpectedFailure(
    (candidate) => candidate.method === "POST" && candidate.url === url,
    { status: 403 },
  );
  activeClient.emit("Runtime.consoleAPICalled", {
    type: "error",
    args: [{ value: "same-url console error" }],
  });
  activeClient.emit("Runtime.exceptionThrown", {
    exceptionDetails: { text: "same-url runtime exception" },
  });
  activeClient.emit("Log.entryAdded", {
    entry: { source: "javascript", level: "error", text: "same-url JavaScript error", url },
  });
  assert.throws(() => activeDiagnostics.assertClean("active unrelated diagnostics"), /browser diagnostics failed/);
  removeActiveAllowance();
  activeDiagnostics.dispose();

  const removedClient = makeDiagnosticClient();
  const removedDiagnostics = installDiagnostics(removedClient, { expectedOrigin: origin });
  const removeAllowance = removedDiagnostics.allowExpectedFailure(
    (candidate) => candidate.method === "POST" && candidate.url === url,
    { status: 403 },
  );
  removedClient.emit("Network.requestWillBeSent", {
    requestId: "expected-403",
    request: { url, method: "POST", headers: {} },
    type: "XHR",
  });
  removedClient.emit("Network.responseReceived", {
    requestId: "expected-403",
    response: { url, status: 403 },
    type: "XHR",
  });
  removeAllowance();
  emitCanonicalNetworkResourceError(removedClient, url);
  assert.throws(() => removedDiagnostics.assertClean("removed expected-failure registration"), /browser diagnostics failed/);
  removedDiagnostics.dispose();
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
