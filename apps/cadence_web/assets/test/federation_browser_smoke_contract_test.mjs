import assert from "node:assert/strict";
import { createServer } from "node:net";
import { test } from "node:test";
import {
  assertHttpRequestContract,
  assertManifestAssetsRequested,
  assertNoPasswordArgument,
  browserUrls,
  createPage,
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
  const manifest = { entry: "remoteEntry.js", files: ["chunks/Application-1.js", "styles/Application.css"] };
  const assets = [
    record({ url: `${origin}/assets/application-host/telemetry-decom/remoteEntry.js`, method: "GET", body: undefined, resourceType: "Script" }),
    record({ url: `${origin}/assets/application-host/telemetry-decom/chunks/Application-1.js`, method: "GET", body: undefined, resourceType: "Script" }),
    record({ url: `${origin}/assets/application-host/telemetry-decom/styles/Application.css`, method: "GET", body: undefined, resourceType: "Stylesheet" }),
  ];
  assert.equal(assertManifestAssetsRequested(manifest, manifestUrl, assets, { origin, label: "telemetry manifest" }).length, 3);
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
  assert.equal(isIgnoredFavicon(record({ url: `${origin}/favicon.ico`, method: "GET", body: undefined, resourceType: "Other" }), origin), false);
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
