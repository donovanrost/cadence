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
  raceWithSignalAndTimeout,
  runBrowserGate,
  runScenario,
  toOrdinarySerializableResult,
  waitForPageNavigation,
  waitForLatestRequestTerminal,
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
    async send() {
      return {};
    },
    close() {},
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

function expectedFailureFixture({
  requestId = "confirmation-403",
  url = `${origin}/api/cadence/application-host/v1/missions/mission-1/spacecraft/spacecraft-1/actions`,
  status = 403,
  includeResponse = true,
  includeCanonical = true,
  finish = true,
  generation = true,
} = {}) {
  const client = makeDiagnosticClient();
  const diagnostics = installDiagnostics(client, { expectedOrigin: origin });
  const requestGeneration = generation
    ? diagnostics.beginRequestGeneration("confirmation fixture")
    : undefined;
  const cleanup = diagnostics.allowExpectedFailure(
    (candidate) => candidate.method === "POST" && candidate.url === url,
    { status: 403 },
  );
  emitExpectedActionRequest(client, requestId, url);
  if (includeResponse) emitActionResponse(client, requestId, url, status);
  if (includeCanonical) emitCanonicalNetworkResourceError(client, url, requestId, status);
  if (finish) client.emit("Network.loadingFinished", { requestId });
  return {
    client,
    diagnostics,
    cleanup,
    generation: requestGeneration,
    requestId,
    url,
    status,
  };
}

function confirmationEvidence(fixture, overrides = {}) {
  return {
    requestId: fixture.requestId,
    method: "POST",
    url: fixture.url,
    generation: fixture.generation,
    status: fixture.status,
    ...overrides,
  };
}

function syntheticGateDependencies() {
  const client = makeDiagnosticClient();
  const runtime = {
    endpoint: "http://127.0.0.1:43721",
    close: async () => {},
  };
  return {
    client,
    launchChromeImpl: async () => runtime,
    createPageImpl: async () => ({ webSocketDebuggerUrl: "ws://synthetic" }),
    createClientImpl: () => client,
  };
}

function syntheticGateArgs(timeout) {
  return [
    "--comms-url",
    `${origin}/missions/mission-1/applications/comms/federated`,
    ...(timeout ? ["--scenario-timeout-ms", String(timeout)] : []),
  ];
}

function waitForMilliseconds(milliseconds) {
  return new Promise((resolveWait) => setTimeout(resolveWait, milliseconds));
}

function unhandledRejectionProbe() {
  const unhandled = [];
  const onUnhandled = (reason) => unhandled.push(reason);
  process.on("unhandledRejection", onUnhandled);
  return {
    unhandled,
    dispose() {
      process.removeListener("unhandledRejection", onUnhandled);
    },
  };
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
    const firstUrls = browserUrls({
      port: first.port,
      missionId: "mission/one",
      spacecraftId: "sc-1",
    });
    const secondUrls = browserUrls({
      port: second.port,
      missionId: "mission/one",
      spacecraftId: "sc-1",
    });
    assert.notEqual(new URL(firstUrls.commsUrl).origin, new URL(secondUrls.commsUrl).origin);
    assert.equal(
      new URL(firstUrls.commsUrl).pathname,
      "/missions/mission%2Fone/applications/comms/federated",
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
  const base = record({
    url: `${origin}/api/cadence/application-host/v1/missions/mission-1/spacecraft/spacecraft-1/query`,
    body: expected,
  });
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
      () =>
        assertHttpRequestContract(
          { ...base, ...record(invalid) },
          {
            origin,
            method: "POST",
            pathname:
              "/api/cadence/application-host/v1/missions/mission-1/spacecraft/spacecraft-1/query",
            label: "adversarial query",
            body: expected,
            headers: {
              "content-type": "application/json",
              "x-cadence-poc-session": "session-1",
              "x-csrf-token": "csrf-1",
            },
          },
        ),
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
    () =>
      assertHttpRequestContract(record({ headers: { "content-type": "application/json" } }), {
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

test("manifest validation separates declared candidates from required and observed assets", () => {
  const releaseId = `sha256:${"a".repeat(64)}`;
  const releasePrefix = releaseArtifactPrefix("telemetry_decom", releaseId);
  const manifestUrl = `${origin}${releasePrefix}mf-manifest.json`;
  const manifest = {
    metaData: {
      remoteEntry: { name: "remoteEntry.js" },
      ssrRemoteEntry: { name: "remoteEntry.ssr.js" },
    },
    entry: "remoteEntry.js",
    files: ["chunks/Application-1.js", "styles/Application.css", "chunks/unused-async-sibling.js"],
    exposes: [
      {
        path: "./Application",
        assets: {
          js: {
            async: ["chunks/unused-async-sibling.js"],
            sync: ["chunks/Application-1.js"],
          },
          css: { sync: ["styles/Application.css"] },
        },
      },
      { path: "./Failure", assets: { js: { sync: ["chunks/Failure.js"] } } },
    ],
    shared: [
      {
        name: "vue",
        assets: {
          js: {
            async: ["chunks/unused-shared-async.js"],
            sync: ["chunks/shared.js"],
          },
        },
      },
    ],
  };
  const assets = [
    record({
      url: `${origin}${releasePrefix}remoteEntry.js`,
      method: "GET",
      body: undefined,
      resourceType: "Script",
    }),
    record({
      url: `${origin}${releasePrefix}chunks/Application-1.js`,
      method: "GET",
      body: undefined,
      resourceType: "Script",
    }),
    record({
      url: `${origin}${releasePrefix}styles/Application.css`,
      method: "GET",
      body: undefined,
      resourceType: "Stylesheet",
    }),
    record({
      url: `${origin}${releasePrefix}chunks/shared.js`,
      method: "GET",
      body: undefined,
      resourceType: "Script",
    }),
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
    7,
  );
  assert.doesNotThrow(() =>
    assertManifestAssetsRequested(manifest, manifestUrl, assets, releaseOptions),
  );
  assert.doesNotThrow(() =>
    assertManifestAssetsRequested(
      manifest,
      manifestUrl,
      [
        assets[0],
        assets[1],
        assets[3],
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
      ],
      {
        label: "newest duplicate manifest",
        ...releaseOptions,
      },
    ),
  );
  assert.throws(
    () =>
      assertManifestAssetsRequested(manifest, manifestUrl, [assets[0], assets[1], assets[3]], {
        ...releaseOptions,
        label: "missing asset manifest",
      }),
    /was not successfully requested.*Application\.css/,
  );
  assert.throws(
    () =>
      assertManifestAssetsRequested(
        manifest,
        manifestUrl,
        [
          assets[0],
          assets[1],
          assets[3],
          record({
            url: `${origin}${releasePrefix}styles/Application.css`,
            method: "GET",
            body: undefined,
            status: 404,
          }),
        ],
        { ...releaseOptions, label: "404 asset manifest" },
      ),
    /was not successfully requested|HTTP 200/,
  );
  for (const [label, responseHeaders, message] of [
    ["observed async cache", { etag: `"${releaseId}"` }, /immutable caching/],
    [
      "observed async digest",
      { "cache-control": "public, max-age=31536000, immutable", etag: '"sha256:bad"' },
      /strong digest ETag/,
    ],
  ]) {
    const immutableAssets = assets.map((asset) => ({
      ...asset,
      response: {
        ...asset.response,
        headers: {
          "cache-control": "public, max-age=31536000, immutable",
          etag: `"${releaseId}"`,
        },
      },
    }));
    assert.throws(
      () =>
        assertManifestAssetsRequested(
          manifest,
          manifestUrl,
          [
            ...immutableAssets,
            record({
              url: `${origin}${releasePrefix}chunks/unused-async-sibling.js`,
              method: "GET",
              body: undefined,
              resourceType: "Script",
              responseHeaders,
            }),
          ],
          { ...releaseOptions, label, requireImmutableCache: true },
        ),
      message,
    );
  }
  assert.throws(
    () =>
      assertManifestAssetsRequested(
        {
          ...manifest,
          exposes: manifest.exposes.map((expose) =>
            expose.path === "./Application"
              ? {
                  ...expose,
                  assets: {
                    ...expose.assets,
                    js: {
                      ...expose.assets.js,
                      async: ["https://evil.example/unused-async-sibling.js"],
                    },
                  },
                }
              : expose,
          ),
        },
        manifestUrl,
        assets,
        { ...releaseOptions, label: "foreign async candidate" },
      ),
    /escaped the expected origin/,
  );
  assert.throws(
    () =>
      assertManifestAssetsRequested({ entry: "https://evil.example/remote.js" }, manifestUrl, [], {
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
      () =>
        assertReleaseArtifactUrl(invalidUrl, origin, {
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
      () =>
        assertManifestAssetsRequested({ entry: new URL(invalidAsset).href }, manifestUrl, [], {
          ...releaseOptions,
          requiredExposedModule: undefined,
          label: "invalid release asset",
        }),
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
    {
      responseHeaders: { "cache-control": "public, max-age=31536000, immutable", etag: 'W/"weak"' },
    },
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
  assert.throws(
    () => rejectedDiagnostics.assertClean("non-304 cancellation"),
    /browser diagnostics failed/,
  );
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

test("public request failure observations cannot clear private diagnostic failures", () => {
  const client = makeDiagnosticClient();
  const diagnostics = installDiagnostics(client, { expectedOrigin: origin });
  const url = `${origin}/api/failure`;
  client.emit("Network.requestWillBeSent", {
    requestId: "real-500",
    request: { url, method: "GET", headers: {} },
    type: "Fetch",
  });
  client.emit("Network.responseReceived", {
    requestId: "real-500",
    response: { url, status: 500 },
    type: "Fetch",
  });
  client.emit("Network.loadingFinished", { requestId: "real-500" });
  assert.equal(diagnostics.requestFailures.length, 1);
  diagnostics.requestFailures.splice(0);
  assertDirty(diagnostics, "cleared public request failure");
  diagnostics.dispose();
});

test("orphan ExtraInfo metadata is not a request, but bound records must terminate", () => {
  const client = makeDiagnosticClient();
  const diagnostics = installDiagnostics(client, { expectedOrigin: origin });

  client.emit("Network.responseReceivedExtraInfo", {
    requestId: "orphan-extra-info",
    statusCode: 200,
    headers: {},
  });
  assert.doesNotThrow(() => diagnostics.assertClean("orphan ExtraInfo metadata"));

  const boundUrl = `${origin}/assets/application-host/host/host.js`;
  client.emit("Network.requestWillBeSent", {
    requestId: "bound-extra-info",
    request: { url: boundUrl, method: "GET", headers: {} },
    type: "Script",
  });
  client.emit("Network.responseReceivedExtraInfo", {
    requestId: "bound-extra-info",
    statusCode: 200,
    headers: {},
  });
  assertDirty(diagnostics, "request-bound ExtraInfo before completion");
  client.emit("Network.loadingFinished", { requestId: "bound-extra-info" });
  assert.doesNotThrow(() => diagnostics.assertClean("request-bound ExtraInfo completion"));

  const lateBoundUrl = `${origin}/api/cadence/application-host/v1/catalog`;
  client.emit("Network.responseReceivedExtraInfo", {
    requestId: "late-bound-extra-info",
    statusCode: 200,
    headers: {},
  });
  assert.doesNotThrow(() => diagnostics.assertClean("late orphan ExtraInfo metadata"));
  client.emit("Network.requestWillBeSent", {
    requestId: "late-bound-extra-info",
    request: { url: lateBoundUrl, method: "GET", headers: {} },
    type: "Fetch",
  });
  assertDirty(diagnostics, "late-bound ExtraInfo before completion");
  client.emit("Network.loadingFinished", { requestId: "late-bound-extra-info" });
  assert.doesNotThrow(() => diagnostics.assertClean("late-bound ExtraInfo completion"));

  diagnostics.dispose();
});

test("public log error observations cannot clear private diagnostic failures", () => {
  const client = makeDiagnosticClient();
  const diagnostics = installDiagnostics(client, { expectedOrigin: origin });
  client.emit("Log.entryAdded", {
    entry: { level: "error", text: "real browser error", url: `${origin}/failure` },
  });
  assert.equal(diagnostics.logErrors.length, 1);
  diagnostics.logErrors.splice(0);
  assertDirty(diagnostics, "cleared public log error");
  diagnostics.dispose();
});

test("replaced public observation methods cannot alter private verdicts", () => {
  const client = makeDiagnosticClient();
  const diagnostics = installDiagnostics(client, { expectedOrigin: origin });
  const requests = diagnostics.requests;
  const requestFailures = diagnostics.requestFailures;
  const logErrors = diagnostics.logErrors;
  requests.get = () => {
    throw new Error("forged request lookup");
  };
  requests.has = () => false;
  requests.set = () => {
    throw new Error("forged request publication");
  };
  requestFailures.push = () => {
    throw new Error("forged request failure publication");
  };
  logErrors.push = () => {
    throw new Error("forged log publication");
  };

  client.emit("Network.requestWillBeSent", {
    requestId: "private-methods-500",
    request: { url: `${origin}/private-methods`, method: "GET", headers: {} },
    type: "Fetch",
  });
  client.emit("Network.responseReceived", {
    requestId: "private-methods-500",
    response: { url: `${origin}/private-methods`, status: 500 },
    type: "Fetch",
  });
  client.emit("Network.loadingFinished", { requestId: "private-methods-500" });
  client.emit("Log.entryAdded", {
    entry: { level: "error", text: "private method log", url: `${origin}/private-methods` },
  });

  assert.equal(
    diagnostics.requestForGeneration(undefined, () => true).requestId,
    "private-methods-500",
  );
  assertDirty(diagnostics, "replaced public observation methods");
  diagnostics.dispose();
});

test("generation queries ignore tampered public ids, request sets, and boundaries", () => {
  const client = makeDiagnosticClient();
  const diagnostics = installDiagnostics(client, { expectedOrigin: origin });
  const oldGeneration = diagnostics.beginRequestGeneration("old generation");
  emitExpectedActionRequest(client, "old-generation-request", `${origin}/old`);
  const nextGeneration = diagnostics.beginRequestGeneration("next generation");
  emitExpectedActionRequest(client, "next-generation-request", `${origin}/new`);

  diagnostics.requests.get("old-generation-request").generation = nextGeneration.id;
  diagnostics.requests.get("next-generation-request").generation = oldGeneration.id;
  nextGeneration.requestIds.delete("old-generation-request");
  nextGeneration.requestSequence = 0;

  assert.equal(
    diagnostics.requestForGeneration(nextGeneration, () => true).requestId,
    "next-generation-request",
  );
  diagnostics.dispose();
});

test("confirmation detects in-place mutation of a consumed canonical snapshot member", () => {
  const fixture = expectedFailureFixture({ requestId: "mutated-canonical-member" });
  const canonicalEntry = fixture.diagnostics.requests.get(fixture.requestId)
    .expectedFailureAllowance.consumedEntries[0];
  canonicalEntry.text = "forged canonical failure";

  assert.throws(
    () =>
      fixture.diagnostics.confirmExpectedFailure(fixture.cleanup, confirmationEvidence(fixture)),
    /expected failure confirmation rejected.*observation.*changed/,
  );
  assert.equal(fixture.diagnostics.logErrors.length, 1);
  fixture.diagnostics.dispose();
});

test("confirmation detects a consumed canonical snapshot being popped", () => {
  const fixture = expectedFailureFixture({ requestId: "popped-canonical-entry" });
  const exposedAllowance = fixture.diagnostics.requests.get(
    fixture.requestId,
  ).expectedFailureAllowance;
  exposedAllowance.consumedEntries.pop();

  assert.throws(
    () =>
      fixture.diagnostics.confirmExpectedFailure(fixture.cleanup, confirmationEvidence(fixture)),
    /expected failure confirmation rejected.*observation.*changed/,
  );
  assert.equal(fixture.diagnostics.logErrors.length, 1);
  fixture.diagnostics.dispose();
});

test("confirmation detects canonical snapshot accessors without invoking them", () => {
  const fixture = expectedFailureFixture({ requestId: "accessor-canonical-member" });
  const canonicalEntry = fixture.diagnostics.requests.get(fixture.requestId)
    .expectedFailureAllowance.consumedEntries[0];
  let getterCalls = 0;
  Object.defineProperty(canonicalEntry, "text", {
    get: () => {
      getterCalls += 1;
      return "forged canonical failure";
    },
    enumerable: true,
    configurable: true,
  });

  assert.throws(
    () =>
      fixture.diagnostics.confirmExpectedFailure(fixture.cleanup, confirmationEvidence(fixture)),
    /expected failure confirmation rejected.*observation.*accessor/,
  );
  assert.equal(getterCalls, 0);
  assert.equal(fixture.diagnostics.logErrors.length, 1);
  fixture.diagnostics.dispose();
});

test("confirmation rejects a mutated detached canonical snapshot", () => {
  const fixture = expectedFailureFixture({ requestId: "detached-canonical-member" });
  const detached = fixture.diagnostics.requestForGeneration(fixture.generation, () => true);
  const canonicalEntry = detached.expectedFailureAllowance.consumedEntries[0];
  canonicalEntry.text = "forged detached canonical failure";

  assert.throws(
    () =>
      fixture.diagnostics.confirmExpectedFailure(
        fixture.cleanup,
        confirmationEvidence(fixture, { canonicalEvidence: canonicalEntry }),
      ),
    /expected failure confirmation rejected.*provided canonical evidence differs/,
  );
  assert.equal(fixture.diagnostics.logErrors.length, 1);
  fixture.diagnostics.dispose();
});

test("LiveView websocket assertion ignores forged entries in exposed websocket evidence", () => {
  const diagnostics = installDiagnostics(makeDiagnosticClient(), { expectedOrigin: origin });
  diagnostics.webSockets.set("forged-live-ws", {
    requestId: "forged-live-ws",
    generation: undefined,
    boundToRequest: true,
    observedSequence: 1,
    url: `${origin.replace("http:", "ws:")}/live/websocket?vsn=2.0.0`,
    handshakeRequest: { headers: { Origin: origin } },
    handshake: { status: 101 },
  });

  assert.throws(
    () => assertLiveViewWebSocket(diagnostics, origin),
    /did not create a websocket transport/,
  );
  diagnostics.dispose();

  const client = makeDiagnosticClient();
  const liveDiagnostics = installDiagnostics(client, { expectedOrigin: origin });
  const requestId = "private-live-ws";
  const socketUrl = `${origin.replace("http:", "ws:")}/live/websocket?vsn=2.0.0`;
  client.emit("Network.requestWillBeSent", {
    requestId,
    request: { url: socketUrl, method: "GET", headers: {} },
    type: "WebSocket",
  });
  client.emit("Network.webSocketCreated", { requestId, url: socketUrl });
  client.emit("Network.webSocketWillSendHandshakeRequest", {
    requestId,
    request: { url: socketUrl, headers: { Origin: origin } },
  });
  client.emit("Network.webSocketHandshakeResponseReceived", {
    requestId,
    response: { url: socketUrl, status: 101 },
  });
  const exposedSocket = liveDiagnostics.webSockets.get(requestId);
  exposedSocket.url = "wss://evil.example/live/websocket";
  exposedSocket.boundToRequest = false;
  exposedSocket.handshake.status = 403;
  assert.equal(assertLiveViewWebSocket(liveDiagnostics, origin).requestId, requestId);
  liveDiagnostics.dispose();
});

test("exposed response mutations cannot change private diagnostic status truth", () => {
  const fixture = expectedFailureFixture({ requestId: "private-response-status" });
  const exposedRecord = fixture.diagnostics.requests.get(fixture.requestId);
  exposedRecord.response.status = 500;
  exposedRecord.response.headers = { "x-forged": "true" };

  assert.doesNotThrow(() => fixture.diagnostics.assertClean("detached response mutation"));
  assert.match(fixture.diagnostics.describe(), /"status": 403/);
  assert.doesNotMatch(fixture.diagnostics.describe(), /"status": 500/);
  assert.throws(
    () =>
      fixture.diagnostics.confirmExpectedFailure(fixture.cleanup, confirmationEvidence(fixture)),
    /expected failure confirmation rejected.*observation.*changed/,
  );
  fixture.diagnostics.dispose();
});

test("confirmation finalizes one exact terminal 403 without replay or later suppression", () => {
  const fixture = expectedFailureFixture();
  assert.doesNotThrow(() => fixture.diagnostics.assertClean("confirmation baseline"));
  assert.equal(
    fixture.diagnostics.confirmExpectedFailure(fixture.cleanup, confirmationEvidence(fixture)),
    true,
  );

  fixture.cleanup();
  fixture.cleanup();
  assert.equal(fixture.diagnostics.logErrors.length, 0);
  assert.equal(fixture.diagnostics.requestFailures.length, 0);

  fixture.client.emit("Network.loadingFailed", {
    requestId: fixture.requestId,
    errorText: "net::ERR_AFTER_CONFIRMATION",
  });
  assert.equal(fixture.diagnostics.requestFailures.length, 1);
  emitCanonicalNetworkResourceError(fixture.client, fixture.url, "unrelated-after-confirmation");
  assert.equal(fixture.diagnostics.logErrors.length, 1);
  assertDirty(fixture.diagnostics, "unrelated event after confirmation");
  fixture.diagnostics.dispose();
  fixture.diagnostics.dispose();
  fixture.cleanup();
  assert.equal(fixture.diagnostics.logErrors.length, 1);
});

test("confirmation requires exact canonical evidence and exact terminal record identity", () => {
  const forgedEvidence = expectedFailureFixture({ requestId: "forged-canonical" });
  const forgedRecord = forgedEvidence.diagnostics.requests.get(forgedEvidence.requestId);
  const canonicalEntry = forgedRecord.expectedFailureAllowance.consumedEntries[0];
  assert.throws(
    () =>
      forgedEvidence.diagnostics.confirmExpectedFailure(
        forgedEvidence.cleanup,
        confirmationEvidence(forgedEvidence, { canonicalEvidence: { ...canonicalEntry } }),
      ),
    /expected failure confirmation rejected.*identity/,
  );
  assert.equal(forgedEvidence.diagnostics.logErrors.length, 1);
  forgedEvidence.cleanup();
  forgedEvidence.diagnostics.dispose();

  const staleRecord = expectedFailureFixture({ requestId: "stale-terminal-record" });
  const exactRecord = staleRecord.diagnostics.requests.get(staleRecord.requestId);
  const staleClone = { ...exactRecord };
  staleRecord.diagnostics.requests.set(staleRecord.requestId, staleClone);
  assert.throws(
    () =>
      staleRecord.diagnostics.confirmExpectedFailure(
        staleRecord.cleanup,
        confirmationEvidence(staleRecord, {
          canonicalEvidence: exactRecord.expectedFailureAllowance.consumedEntries[0],
        }),
      ),
    /expected failure confirmation rejected.*identity/,
  );
  assert.equal(staleRecord.diagnostics.logErrors.length, 1);
  staleRecord.cleanup();
  staleRecord.diagnostics.dispose();
});

test("finalized expected failures retain exact authority for contradictory late response and ExtraInfo status", () => {
  for (const [label, emitContradiction] of [
    [
      "response",
      (fixture) => emitActionResponse(fixture.client, fixture.requestId, fixture.url, 200),
    ],
    ["ExtraInfo", (fixture) => emitActionExtraInfo(fixture.client, fixture.requestId, 200)],
  ]) {
    const fixture = expectedFailureFixture({ requestId: `late-${label}` });
    const record = fixture.diagnostics.requests.get(fixture.requestId);
    assert.equal(
      fixture.diagnostics.confirmExpectedFailure(fixture.cleanup, confirmationEvidence(fixture)),
      true,
    );
    assert.equal(record.expectedFailureAllowance.record, record);
    assert.equal(record.finalizedExpectedFailure, record.expectedFailureAllowance);
    assert.doesNotThrow(() => fixture.diagnostics.assertClean(`${label} finalized baseline`));

    emitContradiction(fixture);
    assertDirty(fixture.diagnostics, `${label} status after finalization`);
    fixture.diagnostics.dispose();
  }
});

test("expected failure confirmation fails closed on exposed consumed-entry replacements", () => {
  const fixture = expectedFailureFixture({ requestId: "private-consumed-membership" });
  const exposedRecord = fixture.diagnostics.requests.get(fixture.requestId);
  const exposedAllowance = exposedRecord.expectedFailureAllowance;
  const canonicalEntry = exposedAllowance.consumedEntries[0];
  let iteratorCalls = 0;
  const arrayLikeReplacement = { 0: canonicalEntry, length: 1 };
  Object.defineProperty(arrayLikeReplacement, Symbol.iterator, {
    get: () => {
      iteratorCalls += 1;
      return function* hostileIterator() {};
    },
  });

  exposedAllowance.consumedEntries = [canonicalEntry];
  exposedAllowance.consumedEntries = arrayLikeReplacement;
  exposedAllowance.record = {};
  exposedRecord.expectedFailureAllowance = { consumedEntries: [canonicalEntry] };

  assert.throws(
    () =>
      fixture.diagnostics.confirmExpectedFailure(fixture.cleanup, confirmationEvidence(fixture)),
    /expected failure confirmation rejected.*observation changed/,
  );
  assert.equal(iteratorCalls, 0, "confirmation touched the replaced exposed iterator");
  assert.equal(fixture.diagnostics.logErrors.length, 1);
  fixture.diagnostics.dispose();
});

test("expected failure confirmation ignores exposed POST-to-GET mutations", () => {
  const fixture = expectedFailureFixture({ requestId: "private-method-lineage" });
  const exposedRecord = fixture.diagnostics.requests.get(fixture.requestId);
  exposedRecord.method = "GET";
  exposedRecord.expectedFailureAllowance.method = "GET";

  assert.throws(
    () =>
      fixture.diagnostics.confirmExpectedFailure(
        fixture.cleanup,
        confirmationEvidence(fixture, { method: "GET" }),
      ),
    /expected failure confirmation rejected.*request method changed/,
  );
  assert.equal(fixture.diagnostics.logErrors.length, 1);
  fixture.diagnostics.dispose();
});

test("late contradictory status remains authoritative after exposed finalization evidence is erased", () => {
  const fixture = expectedFailureFixture({ requestId: "private-finalization-authority" });
  const exposedRecord = fixture.diagnostics.requests.get(fixture.requestId);
  assert.equal(
    fixture.diagnostics.confirmExpectedFailure(fixture.cleanup, confirmationEvidence(fixture)),
    true,
  );

  delete exposedRecord.finalizedExpectedFailure;
  exposedRecord.statusEvidence = [];
  emitActionResponse(fixture.client, fixture.requestId, fixture.url, 200);
  assertDirty(fixture.diagnostics, "private finalized status authority");
  fixture.diagnostics.dispose();
});

test("confirmation rejects hostile evidence accessors without reading them", () => {
  const fixture = expectedFailureFixture({ requestId: "hostile-confirmation-evidence" });
  let getterCalls = 0;
  const hostileEvidence = {};
  Object.defineProperty(hostileEvidence, "requestId", {
    get: () => {
      getterCalls += 1;
      return fixture.requestId;
    },
    enumerable: true,
  });

  assert.throws(
    () => fixture.diagnostics.confirmExpectedFailure(fixture.cleanup, hostileEvidence),
    /expected failure confirmation rejected.*requestId was an accessor/,
  );
  assert.equal(getterCalls, 0);
  fixture.diagnostics.dispose();
});

test("confirmation rejects proxy evidence without invoking any proxy traps", () => {
  const fixture = expectedFailureFixture({ requestId: "proxy-confirmation-evidence" });
  let trapCalls = 0;
  const hostileEvidence = new Proxy(confirmationEvidence(fixture), {
    getPrototypeOf: () => {
      trapCalls += 1;
      return Object.prototype;
    },
    ownKeys: () => {
      trapCalls += 1;
      return [];
    },
    getOwnPropertyDescriptor: () => {
      trapCalls += 1;
      return undefined;
    },
    get: () => {
      trapCalls += 1;
      return undefined;
    },
    has: () => {
      trapCalls += 1;
      return false;
    },
  });

  assert.throws(
    () => fixture.diagnostics.confirmExpectedFailure(fixture.cleanup, hostileEvidence),
    /expected failure confirmation rejected.*proxy/,
  );
  assert.equal(trapCalls, 0);
  fixture.diagnostics.dispose();
});

test("the browser gate confirms before returning and exposes only ordinary result data", async () => {
  const dependencies = syntheticGateDependencies();
  let diagnostics;
  let cleanupCalls = 0;
  const result = await runBrowserGate(syntheticGateArgs(), {
    ...dependencies,
    runScenarioImpl: async (client, installedDiagnostics) => {
      diagnostics = installedDiagnostics;
      const fixtureUrl = `${origin}/api/cadence/application-host/v1/missions/mission-1/spacecraft/spacecraft-1/actions`;
      const generation = diagnostics.beginRequestGeneration("synthetic browser gate");
      const cleanup = diagnostics.allowExpectedFailure(
        (record) => record.method === "POST" && record.url === fixtureUrl,
        { status: 403 },
      );
      client.emit("Network.requestWillBeSent", {
        requestId: "gate-confirmed-403",
        request: { url: fixtureUrl, method: "POST", headers: {} },
        type: "XHR",
      });
      client.emit("Network.responseReceived", {
        requestId: "gate-confirmed-403",
        response: { url: fixtureUrl, status: 403 },
        type: "XHR",
      });
      emitCanonicalNetworkResourceError(client, fixtureUrl, "gate-confirmed-403");
      client.emit("Network.loadingFinished", { requestId: "gate-confirmed-403" });
      diagnostics.confirmExpectedFailure(cleanup, {
        requestId: "gate-confirmed-403",
        method: "POST",
        url: fixtureUrl,
        generation,
        status: 403,
      });
      const publicResult = { status: "confirmed" };
      Object.defineProperty(publicResult, "cleanupExpectedFailures", {
        value: () => cleanupCalls++,
      });
      publicResult[Symbol("authority")] = cleanup;
      return publicResult;
    },
  });

  assert.deepEqual(result, { status: "confirmed" });
  assert.deepEqual(Object.getOwnPropertyNames(result), ["status"]);
  assert.deepEqual(Object.getOwnPropertySymbols(result), []);
  assert.equal(
    Object.values(result).some((value) => typeof value === "function"),
    false,
  );
  assert.equal(cleanupCalls, 0);
  assert.equal(diagnostics.logErrors.length, 0);
  assert.equal(diagnostics.requestFailures.length, 0);
});

test("the browser gate drains late finalized status events before disposing diagnostics", async () => {
  for (const [label, emitLateStatus] of [
    ["response", (client) => emitActionResponse(client, "gate-late-status", `${origin}/late`, 200)],
    ["ExtraInfo", (client) => emitActionExtraInfo(client, "gate-late-status", 200)],
  ]) {
    let diagnostics;
    await assert.rejects(
      runBrowserGate(syntheticGateArgs(), {
        ...syntheticGateDependencies(),
        runScenarioImpl: async (client, installedDiagnostics) => {
          diagnostics = installedDiagnostics;
          const fixtureUrl = `${origin}/late`;
          const generation = diagnostics.beginRequestGeneration(`late ${label}`);
          const cleanup = diagnostics.allowExpectedFailure(
            (record) => record.method === "POST" && record.url === fixtureUrl,
            { status: 403 },
          );
          emitExpectedActionRequest(client, "gate-late-status", fixtureUrl);
          emitActionResponse(client, "gate-late-status", fixtureUrl, 403);
          emitCanonicalNetworkResourceError(client, fixtureUrl, "gate-late-status");
          client.emit("Network.loadingFinished", { requestId: "gate-late-status" });
          diagnostics.confirmExpectedFailure(cleanup, {
            requestId: "gate-late-status",
            method: "POST",
            url: fixtureUrl,
            generation,
            status: 403,
          });
          setImmediate(() => emitLateStatus(client));
          return { status: "confirmed" };
        },
      }),
      /browser diagnostics failed/,
      label,
    );
    assert.equal(diagnostics.requestFailures.length, 1, `${label} late status was not attributed`);
  }
});

test("browser cleanup remains closure-owned when exposed diagnostics contain a hostile iterator", async () => {
  const { server, port } = await reserveLoopbackPort();
  let pageClosed = false;
  let runtimeClosed = false;
  let iteratorCalls = 0;
  server.on("connection", (socket) => {
    socket.once("data", () => {
      pageClosed = true;
      socket.end("HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
    });
  });

  let diagnostics;
  try {
    await assert.rejects(
      runBrowserGate(syntheticGateArgs(), {
        launchChromeImpl: async () => ({
          endpoint: `ws://127.0.0.1:${port}/devtools/browser/synthetic`,
          close: async () => {
            runtimeClosed = true;
          },
        }),
        createPageImpl: async () => ({
          id: "synthetic-page",
          webSocketDebuggerUrl: "ws://synthetic",
        }),
        createClientImpl: () => makeDiagnosticClient(),
        runScenarioImpl: (client, installedDiagnostics) => {
          diagnostics = installedDiagnostics;
          const fixtureUrl = `${origin}/api/cadence/application-host/v1/missions/mission-1/spacecraft/spacecraft-1/actions`;
          const cleanup = diagnostics.allowExpectedFailure(
            (record) => record.method === "POST" && record.url === fixtureUrl,
            { status: 403 },
          );
          emitExpectedActionRequest(client, "hostile-exposed-iterator", fixtureUrl);
          emitActionResponse(client, "hostile-exposed-iterator", fixtureUrl, 403);
          emitCanonicalNetworkResourceError(client, fixtureUrl, "hostile-exposed-iterator");
          client.emit("Network.loadingFinished", { requestId: "hostile-exposed-iterator" });
          const exposedRecord = diagnostics.requests.get("hostile-exposed-iterator");
          const hostileIterator = {
            [Symbol.iterator]: () => {
              iteratorCalls += 1;
              throw new Error("hostile exposed iterator executed");
            },
          };
          exposedRecord.expectedFailureAllowance.suppressedFailures = hostileIterator;
          exposedRecord.statusEvidence = hostileIterator;
          return { status: "unconfirmed" };
        },
      }),
      /browser diagnostics failed/,
    );
  } finally {
    await new Promise((resolveClose) => server.close(resolveClose));
  }

  assert.equal(iteratorCalls, 0);
  assert.equal(pageClosed, true, "page cleanup did not run after hostile diagnostics exposure");
  assert.equal(
    runtimeClosed,
    true,
    "runtime cleanup did not run after hostile diagnostics exposure",
  );
  assert.ok(diagnostics);
});

test("browser gate validates an injected thenable before assimilation and still closes the runtime", async () => {
  const dependencies = syntheticGateDependencies();
  let runtimeClosed = false;
  let getterCalls = 0;
  const hostileResult = Object.create(null);
  Object.defineProperty(hostileResult, "then", {
    get: () => {
      getterCalls += 1;
      return () => {};
    },
  });

  await assert.rejects(
    runBrowserGate(syntheticGateArgs(), {
      ...dependencies,
      launchChromeImpl: async () => ({
        endpoint: "ws://synthetic",
        close: async () => {
          runtimeClosed = true;
        },
      }),
      runScenarioImpl: () => hostileResult,
    }),
    /arbitrary thenable/,
  );
  assert.equal(getterCalls, 0);
  assert.equal(runtimeClosed, true);
});

test("timeout and signal cleanup invoke each captured close handle exactly once", async () => {
  const client = makeDiagnosticClient();
  let clientCloseCalls = 0;
  client.close = () => {
    clientCloseCalls += 1;
  };
  let runtimeCloseCalls = 0;
  await assert.rejects(
    runBrowserGate(syntheticGateArgs(10), {
      launchChromeImpl: async () => ({
        endpoint: "ws://synthetic",
        close: async () => {
          runtimeCloseCalls += 1;
        },
      }),
      createPageImpl: async () => ({ webSocketDebuggerUrl: "ws://synthetic" }),
      createClientImpl: () => client,
      runScenarioImpl: () => new Promise(() => {}),
    }),
    /federation browser scenario timed out/,
  );
  assert.equal(clientCloseCalls, 1);
  assert.equal(runtimeCloseCalls, 1);
});

test("a page target materialized after SIGTERM is closed exactly once", async () => {
  const runtime = {
    endpoint: "ws://synthetic-runtime",
    close: async () => {},
  };
  let pageMaterialized = false;
  let pageCloseRequests = 0;
  let pageCloseArguments;
  const probe = unhandledRejectionProbe();
  try {
    await assert.rejects(
      runBrowserGate(syntheticGateArgs(), {
        launchChromeImpl: async () => runtime,
        createPageImpl: () =>
          new Promise((resolvePage) => {
            setImmediate(() => process.emit("SIGTERM"));
            setTimeout(() => {
              pageMaterialized = true;
              resolvePage({ id: "late-page", webSocketDebuggerUrl: "ws://synthetic-page" });
            }, 25);
          }),
        closePageImpl: (endpoint, targetId) => {
          pageCloseRequests += 1;
          pageCloseArguments = { endpoint, targetId };
        },
        createClientImpl: () => {
          throw new Error("client acquisition must not start");
        },
        runScenarioImpl: () => {
          throw new Error("scenario must not start");
        },
      }),
      /browser gate received SIGTERM/,
    );
    await waitForMilliseconds(60);
    assert.equal(pageMaterialized, true);
    assert.equal(pageCloseRequests, 1);
    assert.deepEqual(pageCloseArguments, {
      endpoint: "ws://synthetic-runtime",
      targetId: "late-page",
    });
    assert.deepEqual(probe.unhandled, []);
  } finally {
    probe.dispose();
  }
});

test("a runtime delivered asynchronously through onRuntime after SIGTERM is closed exactly once", async () => {
  let runtimeMaterialized = false;
  let runtimeCloseCalls = 0;
  const runtime = {
    endpoint: "ws://synthetic-runtime",
    close: async () => {
      runtimeCloseCalls += 1;
    },
  };
  const probe = unhandledRejectionProbe();
  try {
    await assert.rejects(
      runBrowserGate(syntheticGateArgs(), {
        launchChromeImpl: ({ onRuntime }) => {
          setImmediate(() => {
            process.emit("SIGTERM");
            setTimeout(() => {
              runtimeMaterialized = true;
              onRuntime(runtime);
            }, 25);
          });
          return new Promise(() => {});
        },
        createPageImpl: () => {
          throw new Error("page acquisition must not start");
        },
        runScenarioImpl: () => {
          throw new Error("scenario must not start");
        },
      }),
      /browser gate received SIGTERM/,
    );
    await waitForMilliseconds(60);
    assert.equal(runtimeMaterialized, true);
    assert.equal(runtimeCloseCalls, 1);
    assert.deepEqual(probe.unhandled, []);
  } finally {
    probe.dispose();
  }
});

test("a runtime delivered by the launch promise after SIGTERM is closed exactly once", async () => {
  let runtimeCloseCalls = 0;
  const runtime = {
    endpoint: "ws://synthetic-runtime",
    close: async () => {
      runtimeCloseCalls += 1;
    },
  };
  const probe = unhandledRejectionProbe();
  try {
    await assert.rejects(
      runBrowserGate(syntheticGateArgs(), {
        launchChromeImpl: () => {
          setImmediate(() => process.emit("SIGTERM"));
          return new Promise((resolveRuntime) => setTimeout(() => resolveRuntime(runtime), 25));
        },
        createPageImpl: () => {
          throw new Error("page acquisition must not start");
        },
        runScenarioImpl: () => {
          throw new Error("scenario must not start");
        },
      }),
      /browser gate received SIGTERM/,
    );
    await waitForMilliseconds(60);
    assert.equal(runtimeCloseCalls, 1);
    assert.deepEqual(probe.unhandled, []);
  } finally {
    probe.dispose();
  }
});

test("same-turn runtime callback and launch resolution share one cleanup authority", async () => {
  let runtimeCloseCalls = 0;
  const runtime = {
    endpoint: "ws://synthetic-runtime",
    close: async () => {
      runtimeCloseCalls += 1;
    },
  };
  const probe = unhandledRejectionProbe();
  try {
    await assert.rejects(
      runBrowserGate(syntheticGateArgs(), {
        launchChromeImpl: ({ onRuntime }) => {
          onRuntime(runtime);
          onRuntime(runtime);
          process.emit("SIGTERM");
          return Promise.resolve(runtime);
        },
        createPageImpl: () => {
          throw new Error("page acquisition must not start");
        },
        runScenarioImpl: () => {
          throw new Error("scenario must not start");
        },
      }),
      /browser gate received SIGTERM/,
    );
    assert.equal(runtimeCloseCalls, 1);
    await new Promise((resolveImmediate) => setImmediate(resolveImmediate));
    assert.deepEqual(probe.unhandled, []);
  } finally {
    probe.dispose();
  }
});

test("late runtime close rejection and throw preserve the SIGTERM cause", async () => {
  for (const [kind, closeRuntime] of [
    [
      "rejection",
      (calls) => {
        calls.value += 1;
        return Promise.reject(new Error("late runtime close rejected"));
      },
    ],
    [
      "throw",
      (calls) => {
        calls.value += 1;
        throw new Error("late runtime close threw");
      },
    ],
  ]) {
    const runtimeCloseCalls = { value: 0 };
    const probe = unhandledRejectionProbe();
    try {
      await assert.rejects(
        runBrowserGate(syntheticGateArgs(), {
          launchChromeImpl: ({ onRuntime }) => {
            setImmediate(() => {
              process.emit("SIGTERM");
              setTimeout(
                () =>
                  onRuntime({
                    endpoint: "ws://synthetic-runtime",
                    close: () => closeRuntime(runtimeCloseCalls),
                  }),
                25,
              );
            });
            return new Promise(() => {});
          },
          createPageImpl: () => {
            throw new Error("page acquisition must not start");
          },
          runScenarioImpl: () => {
            throw new Error("scenario must not start");
          },
        }),
        (error) => /browser gate received SIGTERM/.test(error.message),
        `${kind} primary cause`,
      );
      await waitForMilliseconds(60);
      assert.equal(runtimeCloseCalls.value, 1, `${kind} close was not invoked exactly once`);
      assert.deepEqual(probe.unhandled, []);
    } finally {
      probe.dispose();
    }
  }
});

test("late page close rejection and throw preserve the SIGTERM cause", async () => {
  for (const [kind, closePage] of [
    ["rejection", () => Promise.reject(new Error("late page close rejected"))],
    [
      "throw",
      () => {
        throw new Error("late page close threw");
      },
    ],
  ]) {
    let pageCloseCalls = 0;
    const probe = unhandledRejectionProbe();
    try {
      await assert.rejects(
        runBrowserGate(syntheticGateArgs(), {
          launchChromeImpl: async () => ({
            endpoint: "ws://synthetic-runtime",
            close: async () => {},
          }),
          createPageImpl: () =>
            new Promise((resolvePage) => {
              setImmediate(() => process.emit("SIGTERM"));
              setTimeout(
                () =>
                  resolvePage({
                    id: "late-page",
                    webSocketDebuggerUrl: "ws://synthetic-page",
                  }),
                25,
              );
            }),
          closePageImpl: () => {
            pageCloseCalls += 1;
            return closePage();
          },
          runScenarioImpl: () => {
            throw new Error("scenario must not start");
          },
        }),
        (error) => /browser gate received SIGTERM/.test(error.message),
        `${kind} primary cause`,
      );
      await waitForMilliseconds(60);
      assert.equal(pageCloseCalls, 1, `${kind} close was not invoked exactly once`);
      assert.deepEqual(probe.unhandled, []);
    } finally {
      probe.dispose();
    }
  }
});

test("normal runtime, page, and client acquisition each close exactly once", async () => {
  const client = makeDiagnosticClient();
  let clientCloseCalls = 0;
  client.close = () => {
    clientCloseCalls += 1;
  };
  let pageCloseCalls = 0;
  let runtimeCloseCalls = 0;
  const result = await runBrowserGate(syntheticGateArgs(), {
    launchChromeImpl: async () => ({
      endpoint: "ws://synthetic-runtime",
      close: async () => {
        runtimeCloseCalls += 1;
      },
    }),
    createPageImpl: async () => ({
      id: "normal-page",
      webSocketDebuggerUrl: "ws://synthetic-page",
    }),
    closePageImpl: (endpoint, targetId) => {
      pageCloseCalls += 1;
      assert.equal(endpoint, "ws://synthetic-runtime");
      assert.equal(targetId, "normal-page");
    },
    createClientImpl: () => client,
    runScenarioImpl: async () => ({ status: "normal" }),
  });
  assert.deepEqual(result, { status: "normal" });
  assert.equal(pageCloseCalls, 1);
  assert.equal(clientCloseCalls, 1);
  assert.equal(runtimeCloseCalls, 1);
});

test("normal native client acquisition remains owned through final cleanup", async () => {
  const client = makeDiagnosticClient();
  let clientCloseCalls = 0;
  client.close = () => {
    clientCloseCalls += 1;
  };
  let runtimeCloseCalls = 0;
  const probe = unhandledRejectionProbe();
  try {
    const result = await runBrowserGate(syntheticGateArgs(), {
      clientCreationTimeout: 100,
      launchChromeImpl: async () => ({
        endpoint: "ws://synthetic",
        close: async () => {
          runtimeCloseCalls += 1;
        },
      }),
      createPageImpl: async () => ({ webSocketDebuggerUrl: "ws://synthetic" }),
      createClientImpl: () => Promise.resolve(client),
      runScenarioImpl: async () => ({ status: "normal" }),
    });
    assert.deepEqual(result, { status: "normal" });
    assert.equal(clientCloseCalls, 1);
    assert.equal(runtimeCloseCalls, 1);
    await new Promise((resolveImmediate) => setImmediate(resolveImmediate));
    assert.deepEqual(probe.unhandled, []);
  } finally {
    probe.dispose();
  }
});

test("a delayed native client is closed after SIGTERM wins acquisition", async () => {
  const client = makeDiagnosticClient();
  let clientCloseCalls = 0;
  client.close = () => {
    clientCloseCalls += 1;
  };
  let runtimeCloseCalls = 0;
  const probe = unhandledRejectionProbe();
  try {
    await assert.rejects(
      runBrowserGate(syntheticGateArgs(), {
        clientCreationTimeout: 200,
        launchChromeImpl: async () => ({
          endpoint: "ws://synthetic",
          close: async () => {
            runtimeCloseCalls += 1;
          },
        }),
        createPageImpl: async () => ({ webSocketDebuggerUrl: "ws://synthetic" }),
        createClientImpl: () =>
          new Promise((resolveClient) => {
            setImmediate(() => process.emit("SIGTERM"));
            setTimeout(() => resolveClient(client), 25);
          }),
        runScenarioImpl: () => {
          throw new Error("scenario must not start");
        },
      }),
      /browser gate received SIGTERM/,
    );
    await waitForMilliseconds(60);
    assert.equal(clientCloseCalls, 1);
    assert.equal(runtimeCloseCalls, 1);
    assert.deepEqual(probe.unhandled, []);
  } finally {
    probe.dispose();
  }
});

test("a delayed native client is closed after acquisition timeout", async () => {
  const client = makeDiagnosticClient();
  let clientCloseCalls = 0;
  client.close = () => {
    clientCloseCalls += 1;
  };
  let runtimeCloseCalls = 0;
  const probe = unhandledRejectionProbe();
  try {
    await assert.rejects(
      runBrowserGate(syntheticGateArgs(), {
        clientCreationTimeout: 10,
        launchChromeImpl: async () => ({
          endpoint: "ws://synthetic",
          close: async () => {
            runtimeCloseCalls += 1;
          },
        }),
        createPageImpl: async () => ({ webSocketDebuggerUrl: "ws://synthetic" }),
        createClientImpl: () =>
          new Promise((resolveClient) => {
            setTimeout(() => resolveClient(client), 30);
          }),
        runScenarioImpl: () => {
          throw new Error("scenario must not start");
        },
      }),
      /createClient implementation timed out after 10ms/,
    );
    await waitForMilliseconds(60);
    assert.equal(clientCloseCalls, 1);
    assert.equal(runtimeCloseCalls, 1);
    assert.deepEqual(probe.unhandled, []);
  } finally {
    probe.dispose();
  }
});

test("a delayed factory rejection is observed after SIGTERM without an unhandled rejection", async () => {
  let runtimeCloseCalls = 0;
  const probe = unhandledRejectionProbe();
  try {
    await assert.rejects(
      runBrowserGate(syntheticGateArgs(), {
        clientCreationTimeout: 200,
        launchChromeImpl: async () => ({
          endpoint: "ws://synthetic",
          close: async () => {
            runtimeCloseCalls += 1;
          },
        }),
        createPageImpl: async () => ({ webSocketDebuggerUrl: "ws://synthetic" }),
        createClientImpl: () =>
          new Promise((_resolveClient, rejectClient) => {
            setImmediate(() => process.emit("SIGTERM"));
            setTimeout(() => rejectClient(new Error("late client creation rejected")), 25);
          }),
        runScenarioImpl: () => {
          throw new Error("scenario must not start");
        },
      }),
      /browser gate received SIGTERM/,
    );
    await waitForMilliseconds(60);
    assert.equal(runtimeCloseCalls, 1);
    assert.deepEqual(probe.unhandled, []);
  } finally {
    probe.dispose();
  }
});

test("late client close rejection and throw preserve the SIGTERM cause", async () => {
  for (const [kind, closeClient] of [
    [
      "rejection",
      (calls) => {
        calls.value += 1;
        return Promise.reject(new Error("late client close rejected"));
      },
    ],
    [
      "throw",
      (calls) => {
        calls.value += 1;
        throw new Error("late client close threw");
      },
    ],
  ]) {
    const client = makeDiagnosticClient();
    const clientCloseCalls = { value: 0 };
    client.close = () => closeClient(clientCloseCalls);
    let runtimeCloseCalls = 0;
    const probe = unhandledRejectionProbe();
    try {
      await assert.rejects(
        runBrowserGate(syntheticGateArgs(), {
          clientCreationTimeout: 200,
          launchChromeImpl: async () => ({
            endpoint: "ws://synthetic",
            close: async () => {
              runtimeCloseCalls += 1;
            },
          }),
          createPageImpl: async () => ({ webSocketDebuggerUrl: "ws://synthetic" }),
          createClientImpl: () =>
            new Promise((resolveClient) => {
              setImmediate(() => process.emit("SIGTERM"));
              setTimeout(() => resolveClient(client), 25);
            }),
          runScenarioImpl: () => {
            throw new Error("scenario must not start");
          },
        }),
        (error) => /browser gate received SIGTERM/.test(error.message),
        `${kind} primary cause`,
      );
      await waitForMilliseconds(60);
      assert.equal(clientCloseCalls.value, 1, `${kind} close was not invoked exactly once`);
      assert.equal(runtimeCloseCalls, 1);
      assert.deepEqual(probe.unhandled, []);
    } finally {
      probe.dispose();
    }
  }
});

test("duplicate abort and final cleanup calls close a late client exactly once", async () => {
  const client = makeDiagnosticClient();
  let clientCloseCalls = 0;
  client.close = () => {
    clientCloseCalls += 1;
  };
  let runtimeCloseCalls = 0;
  const probe = unhandledRejectionProbe();
  try {
    await assert.rejects(
      runBrowserGate(syntheticGateArgs(), {
        clientCreationTimeout: 200,
        launchChromeImpl: async () => ({
          endpoint: "ws://synthetic",
          close: async () => {
            runtimeCloseCalls += 1;
          },
        }),
        createPageImpl: async () => ({ webSocketDebuggerUrl: "ws://synthetic" }),
        createClientImpl: () =>
          new Promise((resolveClient) => {
            setImmediate(() => {
              process.emit("SIGTERM");
              resolveClient(client);
            });
          }),
        runScenarioImpl: () => {
          throw new Error("scenario must not start");
        },
      }),
      /browser gate received SIGTERM/,
    );
    await waitForMilliseconds(20);
    assert.equal(clientCloseCalls, 1);
    assert.equal(runtimeCloseCalls, 1);
    assert.deepEqual(probe.unhandled, []);
  } finally {
    probe.dispose();
  }
});

test("a never-settling client factory does not delay abort cleanup", async () => {
  let runtimeCloseCalls = 0;
  const probe = unhandledRejectionProbe();
  const startedAt = Date.now();
  try {
    await assert.rejects(
      runBrowserGate(syntheticGateArgs(), {
        clientCreationTimeout: 200,
        launchChromeImpl: async () => ({
          endpoint: "ws://synthetic",
          close: async () => {
            runtimeCloseCalls += 1;
          },
        }),
        createPageImpl: async () => ({ webSocketDebuggerUrl: "ws://synthetic" }),
        createClientImpl: () => {
          setImmediate(() => process.emit("SIGTERM"));
          return new Promise(() => {});
        },
        runScenarioImpl: () => {
          throw new Error("scenario must not start");
        },
      }),
      /browser gate received SIGTERM/,
    );
    assert.ok(Date.now() - startedAt < 500, "abort cleanup waited for the client factory");
    assert.equal(runtimeCloseCalls, 1);
    await new Promise((resolveImmediate) => setImmediate(resolveImmediate));
    assert.deepEqual(probe.unhandled, []);
  } finally {
    probe.dispose();
  }
});

test("diagnostic disposal continues after one unsubscribe throws", async () => {
  const unsubscribeOrder = [];
  const client = {
    on(method) {
      return () => {
        unsubscribeOrder.push(method);
        if (unsubscribeOrder.length === 1) throw new Error("first unsubscribe failed");
      };
    },
  };
  const diagnostics = installDiagnostics(client, { expectedOrigin: origin });
  await assert.rejects(diagnostics.dispose(), /diagnostic unsubscribe cleanup failed/);
  assert.equal(unsubscribeOrder.length, 15);
  assert.equal(new Set(unsubscribeOrder).size, 15);
});

test("rejected client close is awaited, reported, and does not leak an unhandled rejection", async () => {
  const client = makeDiagnosticClient();
  client.close = () => Promise.reject(new Error("client close rejected"));
  const unhandled = [];
  const onUnhandled = (reason) => unhandled.push(reason);
  process.on("unhandledRejection", onUnhandled);
  try {
    await assert.rejects(
      runBrowserGate(syntheticGateArgs(), {
        launchChromeImpl: async () => ({ endpoint: "ws://synthetic", close: async () => {} }),
        createPageImpl: async () => ({ webSocketDebuggerUrl: "ws://synthetic" }),
        createClientImpl: () => client,
        runScenarioImpl: async () => ({ status: "ok" }),
      }),
      /client close rejected/,
    );
    await new Promise((resolveNext) => setImmediate(resolveNext));
  } finally {
    process.removeListener("unhandledRejection", onUnhandled);
  }
  assert.deepEqual(unhandled, []);
});

test("ordinary result conversion rejects hostile arrays before reading or iterating them", () => {
  let mapCalls = 0;
  const ownMap = ["safe"];
  Object.defineProperty(ownMap, "map", {
    value: () => {
      mapCalls += 1;
    },
    enumerable: false,
  });

  let accessorCalls = 0;
  const elementAccessor = [];
  Object.defineProperty(elementAccessor, "0", {
    get: () => {
      accessorCalls += 1;
      return "secret";
    },
    enumerable: true,
  });

  let symbolCalls = 0;
  const ownSymbol = Symbol("authority");
  const symbolArray = ["safe"];
  symbolArray[ownSymbol] = () => {
    symbolCalls += 1;
  };

  let customPrototypeCalls = 0;
  const customPrototypeArray = ["safe"];
  Object.setPrototypeOf(customPrototypeArray, {
    [Symbol.iterator]: () => {
      customPrototypeCalls += 1;
    },
  });

  let functionCalls = 0;
  const elementFunction = [
    () => {
      functionCalls += 1;
    },
  ];
  const hole = new Array(1);
  const extraKey = ["safe"];
  extraKey.extra = "unexpected";
  const serializationHook = ["safe"];
  Object.defineProperty(serializationHook, "toJSON", {
    value: () => {
      functionCalls += 1;
    },
    enumerable: false,
  });

  for (const [label, value, pattern] of [
    ["own map capability", ownMap, /extra own key map/],
    ["element accessor", elementAccessor, /0 was an accessor/],
    ["own symbol", symbolArray, /contained an own symbol/],
    ["custom prototype", customPrototypeArray, /not an ordinary array/],
    ["element function", elementFunction, /non-serializable capability/],
    ["hole", hole, /was a hole/],
    ["extra key", extraKey, /extra own key extra/],
    ["serialization hook", serializationHook, /extra own key toJSON/],
  ]) {
    assert.throws(() => toOrdinarySerializableResult(value), pattern, label);
  }

  assert.equal(mapCalls, 0);
  assert.equal(accessorCalls, 0);
  assert.equal(symbolCalls, 0);
  assert.equal(customPrototypeCalls, 0);
  assert.equal(functionCalls, 0);
});

test("ordinary result conversion rejects proxy arrays before invoking proxy traps", () => {
  let trapCalls = 0;
  const hostileArray = new Proxy(["safe"], {
    getPrototypeOf: () => {
      trapCalls += 1;
      return Array.prototype;
    },
    ownKeys: () => {
      trapCalls += 1;
      return ["0", "length"];
    },
    getOwnPropertyDescriptor: () => {
      trapCalls += 1;
      return undefined;
    },
    get: () => {
      trapCalls += 1;
      return "secret";
    },
    has: () => {
      trapCalls += 1;
      return true;
    },
  });

  assert.throws(() => toOrdinarySerializableResult(hostileArray), /result was a proxy/);
  assert.equal(trapCalls, 0);
});

test("race rejects synchronous thenables without invoking hooks and guards native Promise results", async () => {
  let thenCalls = 0;
  const synchronousThenable = Object.create(null);
  Object.defineProperty(synchronousThenable, "then", {
    get: () => {
      thenCalls += 1;
      return () => {};
    },
  });
  await assert.rejects(
    raceWithSignalAndTimeout(synchronousThenable, { milliseconds: 50, label: "sync thenable" }),
    /arbitrary thenable/,
  );
  assert.equal(thenCalls, 0);

  const nativeResult = { status: "native-promise" };
  assert.deepEqual(
    await raceWithSignalAndTimeout(Promise.resolve(nativeResult), {
      milliseconds: 50,
      label: "native promise",
    }),
    nativeResult,
  );

  await assert.rejects(
    raceWithSignalAndTimeout(Object.create(Promise.prototype), {
      milliseconds: 50,
      label: "forged promise",
    }),
    /arbitrary thenable/,
  );

  let overriddenThenCalls = 0;
  const hostilePromise = Promise.resolve({ status: "hostile-promise" });
  Object.defineProperty(hostilePromise, "then", {
    get: () => {
      overriddenThenCalls += 1;
      return () => {};
    },
  });
  await assert.rejects(
    raceWithSignalAndTimeout(hostilePromise, { milliseconds: 50, label: "hostile promise" }),
    /arbitrary thenable/,
  );
  assert.equal(overriddenThenCalls, 0);

  let resultAccessorCalls = 0;
  const hostileResult = { status: "hostile-result" };
  Object.defineProperty(hostileResult, "cleanup", {
    get: () => {
      resultAccessorCalls += 1;
      return () => {};
    },
    enumerable: true,
  });
  const resolvedHostileResult = await raceWithSignalAndTimeout(Promise.resolve(hostileResult), {
    milliseconds: 50,
    label: "hostile promise result",
  });
  assert.throws(
    () => toOrdinarySerializableResult(resolvedHostileResult),
    /cleanup was an accessor/,
  );
  assert.equal(resultAccessorCalls, 0);
});

test("page navigation rejects a returned thenable before reading its then getter", async () => {
  const listeners = new Map();
  const client = {
    on(method, listener) {
      const methodListeners = listeners.get(method) || new Set();
      methodListeners.add(listener);
      listeners.set(method, methodListeners);
      return () => methodListeners.delete(listener);
    },
  };
  let getterCalls = 0;
  const hostileResult = Object.create(null);
  Object.defineProperty(hostileResult, "then", {
    get: () => {
      getterCalls += 1;
      return () => {};
    },
  });

  await assert.rejects(
    waitForPageNavigation(client, () => hostileResult, { timeout: 50 }),
    /arbitrary thenable/,
  );
  assert.equal(getterCalls, 0);
});

test("the browser gate rejects an unconfirmed allowance after fail-closed cleanup replay", async () => {
  const dependencies = syntheticGateDependencies();
  let diagnostics;
  await assert.rejects(
    runBrowserGate(syntheticGateArgs(), {
      ...dependencies,
      runScenarioImpl: async (client, installedDiagnostics) => {
        diagnostics = installedDiagnostics;
        const fixtureUrl = `${origin}/api/cadence/application-host/v1/missions/mission-1/spacecraft/spacecraft-1/actions`;
        const cleanup = diagnostics.allowExpectedFailure(
          (record) => record.method === "POST" && record.url === fixtureUrl,
          { status: 403 },
        );
        client.emit("Network.requestWillBeSent", {
          requestId: "gate-unconfirmed-403",
          request: { url: fixtureUrl, method: "POST", headers: {} },
          type: "XHR",
        });
        client.emit("Network.responseReceived", {
          requestId: "gate-unconfirmed-403",
          response: { url: fixtureUrl, status: 403 },
          type: "XHR",
        });
        emitCanonicalNetworkResourceError(client, fixtureUrl, "gate-unconfirmed-403");
        client.emit("Network.loadingFinished", { requestId: "gate-unconfirmed-403" });
        return { status: "unconfirmed" };
      },
    }),
    /browser diagnostics failed.*Failed to load resource/s,
  );
  assert.equal(diagnostics.logErrors.length, 1);
  assert.equal(diagnostics.requestFailures.length, 0);
  assertDirty(diagnostics, "unconfirmed gate final diagnostics");
});

test("scenario exceptions revoke an allowance and replay canonical evidence exactly once", async () => {
  const dependencies = syntheticGateDependencies();
  let diagnostics;
  await assert.rejects(
    runBrowserGate(syntheticGateArgs(), {
      ...dependencies,
      runScenarioImpl: async (client, installedDiagnostics) => {
        diagnostics = installedDiagnostics;
        const fixtureUrl = `${origin}/api/cadence/application-host/v1/missions/mission-1/spacecraft/spacecraft-1/actions`;
        diagnostics.allowExpectedFailure(
          (record) => record.method === "POST" && record.url === fixtureUrl,
          { status: 403 },
        );
        client.emit("Network.requestWillBeSent", {
          requestId: "gate-exception-403",
          request: { url: fixtureUrl, method: "POST", headers: {} },
          type: "XHR",
        });
        client.emit("Network.responseReceived", {
          requestId: "gate-exception-403",
          response: { url: fixtureUrl, status: 403 },
          type: "XHR",
        });
        emitCanonicalNetworkResourceError(client, fixtureUrl, "gate-exception-403");
        client.emit("Network.loadingFinished", { requestId: "gate-exception-403" });
        throw new Error("synthetic scenario exception");
      },
    }),
    /synthetic scenario exception/,
  );
  assert.equal(diagnostics.logErrors.length, 1);
  diagnostics.dispose();
  assert.equal(diagnostics.logErrors.length, 1);
});

test("scenario timeout aborts and replays an allowance exactly once", async () => {
  const dependencies = syntheticGateDependencies();
  let diagnostics;
  await assert.rejects(
    runBrowserGate(syntheticGateArgs(10), {
      ...dependencies,
      runScenarioImpl: async (client, installedDiagnostics, _args, { signal }) => {
        diagnostics = installedDiagnostics;
        const fixtureUrl = `${origin}/api/cadence/application-host/v1/missions/mission-1/spacecraft/spacecraft-1/actions`;
        diagnostics.allowExpectedFailure(
          (record) => record.method === "POST" && record.url === fixtureUrl,
          { status: 403 },
        );
        client.emit("Network.requestWillBeSent", {
          requestId: "gate-timeout-403",
          request: { url: fixtureUrl, method: "POST", headers: {} },
          type: "XHR",
        });
        client.emit("Network.responseReceived", {
          requestId: "gate-timeout-403",
          response: { url: fixtureUrl, status: 403 },
          type: "XHR",
        });
        emitCanonicalNetworkResourceError(client, fixtureUrl, "gate-timeout-403");
        client.emit("Network.loadingFinished", { requestId: "gate-timeout-403" });
        await new Promise((_resolve, reject) => {
          signal.addEventListener("abort", () => reject(signal.reason), { once: true });
        });
      },
    }),
    /timed out after 10ms/,
  );
  assert.equal(diagnostics.logErrors.length, 1);
  diagnostics.dispose();
  assert.equal(diagnostics.logErrors.length, 1);
});

test("shutdown abort revokes an allowance and replays canonical evidence exactly once", async () => {
  const dependencies = syntheticGateDependencies();
  let diagnostics;
  await assert.rejects(
    runBrowserGate(syntheticGateArgs(), {
      ...dependencies,
      runScenarioImpl: async (client, installedDiagnostics, _args, { signal }) => {
        diagnostics = installedDiagnostics;
        const fixtureUrl = `${origin}/api/cadence/application-host/v1/missions/mission-1/spacecraft/spacecraft-1/actions`;
        diagnostics.allowExpectedFailure(
          (record) => record.method === "POST" && record.url === fixtureUrl,
          { status: 403 },
        );
        client.emit("Network.requestWillBeSent", {
          requestId: "gate-abort-403",
          request: { url: fixtureUrl, method: "POST", headers: {} },
          type: "XHR",
        });
        client.emit("Network.responseReceived", {
          requestId: "gate-abort-403",
          response: { url: fixtureUrl, status: 403 },
          type: "XHR",
        });
        emitCanonicalNetworkResourceError(client, fixtureUrl, "gate-abort-403");
        client.emit("Network.loadingFinished", { requestId: "gate-abort-403" });
        setImmediate(() => process.emit("SIGTERM"));
        await new Promise((_resolve, reject) => {
          signal.addEventListener("abort", () => reject(signal.reason), { once: true });
        });
      },
    }),
    /browser gate received SIGTERM/,
  );
  assert.equal(diagnostics.logErrors.length, 1);
  diagnostics.dispose();
  assert.equal(diagnostics.logErrors.length, 1);
});

test("confirmation before terminal response replays consumed canonical evidence once", () => {
  const fixture = expectedFailureFixture({ finish: false });
  assert.throws(
    () =>
      fixture.diagnostics.confirmExpectedFailure(fixture.cleanup, confirmationEvidence(fixture)),
    /expected failure confirmation rejected/,
  );
  assert.equal(fixture.diagnostics.logErrors.length, 1);
  fixture.cleanup();
  fixture.diagnostics.dispose();
  assert.equal(fixture.diagnostics.logErrors.length, 1);
  assertDirty(fixture.diagnostics, "confirmation before terminal response");
});

test("confirmation rejects wrong request, generation, or status and replays exactly once", () => {
  const cases = [
    ["wrong request", { requestId: "not-bound" }],
    ["wrong generation", { generation: { id: 99_999 } }],
    ["wrong status", { status: 500 }],
  ];

  for (const [label, overrides] of cases) {
    const fixture = expectedFailureFixture({
      requestId: `confirmation-${label.replaceAll(" ", "-")}`,
    });
    assert.throws(
      () =>
        fixture.diagnostics.confirmExpectedFailure(
          fixture.cleanup,
          confirmationEvidence(fixture, overrides),
        ),
      /expected failure confirmation rejected/,
      label,
    );
    assert.equal(fixture.diagnostics.logErrors.length, 1, `${label} replay count`);
    fixture.cleanup();
    fixture.diagnostics.dispose();
    assert.equal(fixture.diagnostics.logErrors.length, 1, `${label} repeated replay count`);
  }
});

test("confirmation rejects missing, pending, and noncanonical evidence without hiding it", () => {
  const missingLog = expectedFailureFixture({ includeCanonical: false });
  assert.throws(
    () =>
      missingLog.diagnostics.confirmExpectedFailure(
        missingLog.cleanup,
        confirmationEvidence(missingLog),
      ),
    /expected failure confirmation rejected/,
  );
  emitCanonicalNetworkResourceError(missingLog.client, missingLog.url, missingLog.requestId);
  assert.equal(missingLog.diagnostics.logErrors.length, 1);
  missingLog.cleanup();
  missingLog.diagnostics.dispose();

  const pending = expectedFailureFixture({ includeResponse: false, finish: false });
  assert.throws(
    () =>
      pending.diagnostics.confirmExpectedFailure(pending.cleanup, confirmationEvidence(pending)),
    /expected failure confirmation rejected/,
  );
  assert.equal(pending.diagnostics.logErrors.length, 1);
  pending.cleanup();
  pending.diagnostics.dispose();
  assert.equal(pending.diagnostics.logErrors.length, 1);

  const noncanonical = expectedFailureFixture({ includeCanonical: false });
  noncanonical.client.emit("Log.entryAdded", {
    entry: {
      source: "network",
      level: "error",
      text: "not a canonical HTTP status diagnostic",
      url: noncanonical.url,
      networkRequestId: noncanonical.requestId,
    },
  });
  assert.throws(
    () =>
      noncanonical.diagnostics.confirmExpectedFailure(
        noncanonical.cleanup,
        confirmationEvidence(noncanonical),
      ),
    /expected failure confirmation rejected/,
  );
  assert.equal(noncanonical.diagnostics.logErrors.length, 1);
  noncanonical.cleanup();
  noncanonical.diagnostics.dispose();
});

test("confirmation rejects missing required loadingFailed evidence and replays both channels once", () => {
  const fixture = expectedFailureFixture();
  emitActionLoadingFailed(fixture.client, fixture.requestId, "net::ERR_REQUIRED_FAILURE");
  assert.throws(
    () =>
      fixture.diagnostics.confirmExpectedFailure(
        fixture.cleanup,
        confirmationEvidence(fixture, { failureEvidence: [] }),
      ),
    /expected failure confirmation rejected/,
  );
  assert.equal(fixture.diagnostics.logErrors.length, 1);
  assert.equal(fixture.diagnostics.requestFailures.length, 1);
  fixture.cleanup();
  fixture.diagnostics.dispose();
  assert.equal(fixture.diagnostics.logErrors.length, 1);
  assert.equal(fixture.diagnostics.requestFailures.length, 1);
});

test("status contradiction fails confirmation and cannot replay the canonical error twice", () => {
  const fixture = expectedFailureFixture();
  emitActionExtraInfo(fixture.client, fixture.requestId, 500);
  assert.equal(fixture.diagnostics.logErrors.length, 1);
  assert.throws(
    () =>
      fixture.diagnostics.confirmExpectedFailure(fixture.cleanup, confirmationEvidence(fixture)),
    /expected failure confirmation rejected/,
  );
  fixture.cleanup();
  fixture.diagnostics.dispose();
  assert.equal(fixture.diagnostics.logErrors.length, 1);
  assertDirty(fixture.diagnostics, "confirmation status contradiction");
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
  emitActionLoadingFailed(
    client,
    "dispose-suppressed-failure",
    "net::ERR_DISPOSED_EXPECTED_FAILURE",
  );
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
  assert.equal(
    diagnostics.requests.get("completed-without-status").pendingExpectedFailureLog,
    undefined,
  );
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
  assert.throws(
    () => diagnostics.assertClean("same-URL unrelated error"),
    /browser diagnostics failed/,
  );
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
  assert.throws(
    () => diagnostics.assertClean("duplicate canonical error"),
    /browser diagnostics failed/,
  );
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
  assert.throws(
    () => activeDiagnostics.assertClean("active unrelated diagnostics"),
    /browser diagnostics failed/,
  );
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
  assert.throws(
    () => removedDiagnostics.assertClean("removed expected-failure registration"),
    /browser diagnostics failed/,
  );
  removedDiagnostics.dispose();
});

test("the cache-enabled federation browser gate never disables Chrome cache", async () => {
  const source = await readFile(new URL("./federation_browser_smoke.mjs", import.meta.url), "utf8");
  assert.equal(source.includes("Network.setCacheDisabled"), false);
});

test("the Ops representative browser gate pins the predecessor directory page selector", async () => {
  const source = await readFile(new URL("./federation_browser_smoke.mjs", import.meta.url), "utf8");
  const opsConfigStart = source.indexOf('applicationKey: "ops_console"');
  const opsConfigEnd = source.indexOf("catalogPath:", opsConfigStart);
  assert.ok(opsConfigStart >= 0 && opsConfigEnd > opsConfigStart);
  const opsConfig = source.slice(opsConfigStart, opsConfigEnd);
  assert.equal(opsConfig.includes("document.querySelector('#ops-dashboards-page')"), true);
  assert.equal(opsConfig.includes("#ops-dashboard-directory-page"), false);
});

test("the shared host body is read on the first load and reused by later 304 checks", async () => {
  const source = await readFile(new URL("./federation_browser_smoke.mjs", import.meta.url), "utf8");
  const organizationStart = source.indexOf('applicationKey: "organization_admin"');
  const missionStart = source.indexOf('applicationKey: "mission_catalog"', organizationStart);
  assert.ok(organizationStart >= 0 && missionStart > organizationStart);
  assert.match(source.slice(organizationStart, missionStart), /readPublishedHostBody: true/);

  const commsStart = source.indexOf('queryId: "cadence.comms.overview"');
  const commsEnd = source.indexOf("});", commsStart);
  assert.ok(commsStart >= 0 && commsEnd > commsStart);
  assert.doesNotMatch(source.slice(commsStart, commsEnd), /readPublishedHostBody/);
  assert.match(source, /\[200, 304\]\.includes\(hostRecord\.response\.status\)/);
});

test("canonical Comms query assertions follow the trusted surface response envelope", async () => {
  const source = await readFile(new URL("./federation_browser_smoke.mjs", import.meta.url), "utf8");
  const commsStart = source.indexOf("const comms = await assertRemoteSurface");
  const commsEnd = source.indexOf(
    'reportProgress("verifying Comms Overview DOM and network contract")',
    commsStart,
  );
  assert.ok(commsStart >= 0 && commsEnd > commsStart);
  const commsAssertions = source.slice(commsStart, commsEnd);
  assert.match(commsAssertions, /comms\.query\.trusted_surface\.root\.attrs\.id/);
  assert.match(commsAssertions, /comms\.query\.trusted_surface\.overview\.transport\.id/);
  assert.match(commsAssertions, /comms\.query\.trusted_surface\.overview\.transport\.count/);
  assert.doesNotMatch(commsAssertions, /comms\.query\.data\./);
  assert.doesNotMatch(commsAssertions, /comms\.query\.trusted_surface\.data\./);
});

test("refresh causality rejects a duplicate pre-action query and accepts only a new post-action query", () => {
  const pathname = "/api/query";
  const initial = record({ url: `${origin}${pathname}`, requestId: "query-1", startedAtMs: 10 });
  const duplicateBeforeAction = record({
    url: `${origin}${pathname}`,
    requestId: "query-2",
    startedAtMs: 20,
  });
  assert.throws(
    () =>
      requirePostActionRefresh([initial, duplicateBeforeAction], {
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
  assert.equal(
    isIgnoredFavicon(
      record({
        url: `${origin}/favicon.ico`,
        method: "GET",
        body: undefined,
        resourceType: "Image",
      }),
      origin,
    ),
    true,
  );
  assert.equal(
    isIgnoredFavicon(
      record({
        url: `${origin}/favicon.ico?foreign=1`,
        method: "GET",
        body: undefined,
        resourceType: "Image",
      }),
      origin,
    ),
    false,
  );
  assert.equal(
    isIgnoredFavicon(
      record({
        url: "https://evil.example/favicon.ico",
        method: "GET",
        body: undefined,
        resourceType: "Image",
      }),
      origin,
    ),
    false,
  );
  assert.equal(
    isIgnoredFavicon(
      record({
        url: `${origin}/favicon.ico`,
        method: "POST",
        body: undefined,
        resourceType: "Image",
      }),
      origin,
    ),
    false,
  );
  assert.equal(
    isIgnoredFavicon(
      record({
        url: `${origin}/favicon.ico`,
        method: "GET",
        body: undefined,
        resourceType: "Other",
      }),
      origin,
    ),
    true,
  );
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
        return [...listeners.values()].reduce(
          (count, methodListeners) => count + methodListeners.size,
          0,
        );
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
  client.emit("Log.entryAdded", {
    entry: { level: "error", text: "favicon missing", url: favicon },
  });
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
      () =>
        assertLiveViewWebSocket(
          { ...diagnostics, webSockets: new Map([[invalid.requestId, invalid]]) },
          origin,
        ),
      /same-origin HTTP 101 handshake|did not create a websocket transport/,
    );
  }

  assert.throws(
    () =>
      assertLiveViewWebSocket(
        {
          ...diagnostics,
          requests: new Map([["longpoll-1", { url: `${origin}/live/longpoll?vsn=2.0.0` }]]),
        },
        origin,
      ),
    /longpoll transport/,
  );
  assert.throws(
    () =>
      assertLiveViewWebSocket({ ...diagnostics, webSocketFailures: ["origin rejected"] }, origin),
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
      matchesSignInNavigationRequest(
        { ...base, url: `${origin}${pathname}` },
        { expectedOrigin: origin },
      ),
      expected,
      `sign-in request pathname ${pathname} admission mismatch`,
    );
  }
  assert.equal(
    matchesSignInNavigationRequest(
      { ...base, url: "https://evil.example/sign-in" },
      { expectedOrigin: origin },
    ),
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
  for (const url of [`${origin}/sign-in`, `${origin}/sign-in?return_to=%2Fmissions#form`]) {
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
  const client = new Proxy(
    {},
    {
      get() {
        clientAccessed = true;
        throw new Error("browser navigation was reached before sign-in URL validation");
      },
    },
  );
  await assert.rejects(
    runScenario(
      client,
      {},
      [
        "--comms-url",
        `${origin}/missions/mission-1/applications/comms/federated`,
        "--telemetry-url",
        `${origin}/missions/mission-1/telemetry/federated`,
        "--login-url",
        `${origin}/sign-in-extra`,
        "--login-email",
        "operator@example.test",
        "--mission-id",
        "mission-1",
        "--spacecraft-id",
        "spacecraft-1",
        "--catalog-revision-id",
        "catalog-1",
        "--source-endpoint-id",
        "source-1",
        "--expected-apid",
        "42",
      ],
      { secret: { password: "secret" } },
    ),
    /exact \/sign-in pathname/,
  );
  assert.equal(clientAccessed, false, "invalid sign-in URL reached browser navigation");
});

test("binary admission and diagnostics redact secrets without argv or environment transport", () => {
  assert.equal(
    resolveChromeBinary({
      env: { CHROME_BIN: "/missing" },
      candidates: ["/also-missing"],
      fileExists: () => false,
    }),
    undefined,
  );
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

test("latest terminal request waiting cannot be masked by an earlier same-URL completion", async () => {
  const client = makeDiagnosticClient();
  const diagnostics = installDiagnostics(client, { expectedOrigin: origin });
  const url = `${origin}/assets/application-host/host/host.js`;

  emitExpectedActionRequest(client, "host-completed", url);
  emitActionResponse(client, "host-completed", url, 200);
  client.emit("Network.loadingFinished", { requestId: "host-completed" });

  client.emit("Network.requestWillBeSent", {
    requestId: "host-outstanding",
    request: { url, method: "GET", headers: {} },
    type: "Script",
  });
  emitActionResponse(client, "host-outstanding", url, 200);

  const terminal = waitForLatestRequestTerminal(
    diagnostics,
    (record) => record.url === url,
    "host bundle",
    {
      timeout: 500,
    },
  );
  setTimeout(() => client.emit("Network.loadingFinished", { requestId: "host-outstanding" }), 20);
  assert.equal((await terminal).requestId, "host-outstanding");

  client.emit("Network.requestWillBeSent", {
    requestId: "host-failed",
    request: { url, method: "GET", headers: {} },
    type: "Script",
  });
  emitActionResponse(client, "host-failed", url, 503);
  client.emit("Network.loadingFailed", {
    requestId: "host-failed",
    errorText: "net::ERR_HTTP_RESPONSE_CODE_FAILURE",
  });
  await assert.rejects(
    waitForLatestRequestTerminal(diagnostics, (record) => record.url === url, "host bundle", {
      timeout: 500,
    }),
    /host bundle request host-failed failed:/,
  );

  diagnostics.dispose();
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
    () => {
      settledBeforeLifecycle = true;
    },
    () => {
      settledBeforeLifecycle = true;
    },
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

void test("remote failure confirmation consumes only one exact private diagnostic", () => {
  const client = makeDiagnosticClient();
  const diagnostics = installDiagnostics(client, { expectedOrigin: origin });
  const reference = "12345678-1234-1234-1234-123456789abc";
  const message = `Cadence federation failure ${reference} Object`;
  diagnostics.consoleErrors.push(message);
  assert.throws(() => diagnostics.confirmRemoteFailureDiagnostic(reference), /exactly one private/);
  client.emit("Runtime.consoleAPICalled", {
    type: "error",
    args: [{ value: `Cadence federation failure ${reference}` }, { description: "Object" }],
  });
  diagnostics.confirmRemoteFailureDiagnostic(reference);
  diagnostics.assertClean("confirmed expected failure");
  assert.throws(() => diagnostics.confirmRemoteFailureDiagnostic(reference), /exactly one private/);
  client.emit("Runtime.consoleAPICalled", {
    type: "error",
    args: [{ value: "unrelated failure" }],
  });
  assert.throws(() => diagnostics.assertClean("unrelated failure"), /unrelated failure/);
  diagnostics.dispose();
});
