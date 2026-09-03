import {
  assertFrontendApplicationCatalog,
  type CatalogApplication,
  type FrontendApplicationCatalog,
  type HostActivityEvent,
  type HostContext,
  type HostQueryRequest,
  type HostSessionDescriptor,
} from "@cadence/plugin-sdk";
import { describe, expect, it, vi } from "vite-plus/test";
import { DemoHostService } from "../../../tools/demo-host-service";
import { createHttpHostBridge, HostBridgeError } from "./http-host-bridge";

const context: HostContext = {
  scope: "spacecraft",
  organizationId: "org-1",
  missionId: "mission-1",
  missionName: "Firebird",
  spacecraftId: "spacecraft-1",
  spacecraftName: "FB-1",
  actor: {
    displayName: "Mara Vance",
    permissions: ["applications:view", "applications:configure"],
  },
};

const session: HostSessionDescriptor = {
  sessionId: "session-1",
  csrfToken: "csrf-1",
  bridgeBaseUrl: "/api/cadence/application-host/v1",
  context,
};

const telemetryApplication: CatalogApplication = {
  applicationKey: "telemetry_decom",
  applicationVersion: 1,
  displayName: "Telemetry Decom",
  description: "Telemetry packet bindings.",
  package: { packageId: "cadence.telemetry-applications", version: 1 },
  surface: {
    surfaceId: "packet_bindings",
    version: 1,
    purpose: "configuration",
    scope: "spacecraft",
    placement: "application_workspace",
    navigation: { label: "Packet bindings", order: 20 },
    dataContract: { id: "cadence.packet_bindings.manage", version: 1 },
    actions: ["save_packet_bindings"],
    renderer: { kind: "federated-vue", exposedModule: "./Application" },
  },
  release: {
    federation: "module_federation",
    releaseId: "telemetry-decom-v1",
    remoteName: "cadence_telemetry_decom",
    manifestUrl: "/assets/application-host/telemetry-decom/mf-manifest.json",
    exposedModule: "./Application",
  },
};

function deferred<TResult>() {
  let resolve!: (value: TResult | PromiseLike<TResult>) => void;
  let reject!: (reason?: unknown) => void;
  const promise = new Promise<TResult>((resolvePromise, rejectPromise) => {
    resolve = resolvePromise;
    reject = rejectPromise;
  });
  return { promise, resolve, reject };
}

async function flushMicrotasks(iterations = 6): Promise<void> {
  for (let iteration = 0; iteration < iterations; iteration += 1) {
    await Promise.resolve();
  }
}

function queryRequest(): HostQueryRequest {
  return {
    queryId: "cadence.packet_bindings.manage",
    version: 1,
    context,
  };
}

function actionRequest(idempotencyKey?: string) {
  return {
    applicationKey: "telemetry_decom",
    applicationVersion: 1,
    actionId: "save_packet_bindings",
    input: { expectedConfigurationVersion: 7, selectedApids: [100] },
    context,
    ...(idempotencyKey === undefined ? {} : { idempotencyKey }),
  };
}

describe("the HTTP host bridge", () => {
  it("sends the selected Telemetry application identity and scope", async () => {
    const fetcher = vi.fn(async (_input: RequestInfo | URL, _request?: RequestInit) =>
      Response.json({ queryVersion: 1, configurationVersion: 7, packets: [] }),
    );
    const bridge = createHttpHostBridge(session, telemetryApplication, {
      fetch: fetcher as typeof fetch,
    });
    const activity: HostActivityEvent[] = [];
    bridge.subscribe((event) => activity.push(event));

    await bridge.query({
      queryId: "cadence.packet_bindings.manage",
      version: 1,
      context: {
        ...context,
        actor: { displayName: "Forged operator", permissions: ["applications:admin"] },
      },
    });

    const request = fetcher.mock.calls[0]?.[1];
    const serializedBody = request?.body;
    if (typeof serializedBody !== "string") throw new Error("Expected a serialized request body.");
    const body = JSON.parse(serializedBody) as Record<string, unknown>;
    expect(body).toEqual({
      applicationKey: "telemetry_decom",
      applicationVersion: 1,
      surfaceId: "packet_bindings",
      surfaceVersion: 1,
      queryId: "cadence.packet_bindings.manage",
      queryVersion: 1,
      scope: {
        organizationId: "org-1",
        missionId: "mission-1",
        spacecraftId: "spacecraft-1",
      },
    });
    const headers = new Headers(request?.headers);
    expect(headers.get("content-type")).toBe("application/json");
    expect(headers.get("x-cadence-poc-session")).toBe("session-1");
    expect(headers.get("x-csrf-token")).toBe("csrf-1");
    expect(headers.get("idempotency-key")).toBeNull();
    expect(JSON.stringify(body)).not.toContain("Forged operator");
    expect(activity.map(({ status }) => status)).toEqual(["started", "completed"]);
  });

  it("rejects a request outside the active scope before sending it", async () => {
    const fetcher = vi.fn(async () => Response.json({ queryVersion: 1 }));
    const bridge = createHttpHostBridge(session, telemetryApplication, {
      fetch: fetcher as typeof fetch,
    });

    await expect(
      bridge.query({
        queryId: "cadence.packet_bindings.manage",
        version: 1,
        context: { ...context, spacecraftId: "other-spacecraft", spacecraftName: "Other" },
      }),
    ).rejects.toMatchObject({
      status: 400,
      code: "invalid_scope",
    } satisfies Partial<HostBridgeError>);
    expect(fetcher).not.toHaveBeenCalled();
  });

  it("rejects a query outside the selected surface contract before sending it", async () => {
    const fetcher = vi.fn(async () => Response.json({ queryVersion: 1 }));
    const bridge = createHttpHostBridge(session, telemetryApplication, {
      fetch: fetcher as typeof fetch,
    });

    await expect(
      bridge.query({ queryId: "cadence.packet_bindings.other", version: 1, context }),
    ).rejects.toMatchObject({
      status: 400,
      code: "unsupported_query",
    } satisfies Partial<HostBridgeError>);
    expect(fetcher).not.toHaveBeenCalled();
  });

  it("rejects an action identity or declaration mismatch before sending it", async () => {
    const fetcher = vi.fn(async () =>
      Response.json({
        receiptId: "receipt-1",
        completedAt: "2026-08-22T20:00:00.000Z",
        result: {},
      }),
    );
    const bridge = createHttpHostBridge(session, telemetryApplication, {
      fetch: fetcher as typeof fetch,
    });
    const baseAction = {
      applicationKey: "telemetry_decom",
      applicationVersion: 1,
      actionId: "save_packet_bindings",
      input: {},
      context,
    };

    for (const action of [
      { ...baseAction, applicationKey: "other_application" },
      { ...baseAction, applicationVersion: 2 },
      { ...baseAction, actionId: "undeclared_action" },
    ]) {
      await expect(bridge.execute(action)).rejects.toMatchObject({
        status: 400,
        code: "unsupported_action",
      } satisfies Partial<HostBridgeError>);
    }

    expect(fetcher).not.toHaveBeenCalled();
  });

  it("uses an idempotency key for every host action", async () => {
    const fetcher = vi.fn(async (_input: RequestInfo | URL, _request?: RequestInit) =>
      Response.json({
        receiptId: "receipt-1",
        completedAt: "2026-08-22T20:00:00.000Z",
        result: { configurationVersion: 8 },
      }),
    );
    const bridge = createHttpHostBridge(session, telemetryApplication, {
      fetch: fetcher as typeof fetch,
    });

    const action = {
      applicationKey: "telemetry_decom",
      applicationVersion: 1,
      actionId: "save_packet_bindings",
      input: { expectedConfigurationVersion: 7, selectedApids: [100] },
      context,
      idempotencyKey: "logical-action-retry-1",
    };
    await bridge.execute(action);
    await bridge.execute(action);

    const request = fetcher.mock.calls[0]?.[1];
    const serializedBody = request?.body;
    if (typeof serializedBody !== "string") throw new Error("Expected a serialized request body.");
    expect(JSON.parse(serializedBody)).toEqual({
      applicationKey: "telemetry_decom",
      applicationVersion: 1,
      surfaceId: "packet_bindings",
      surfaceVersion: 1,
      actionId: "save_packet_bindings",
      input: { expectedConfigurationVersion: 7, selectedApids: [100] },
      scope: {
        organizationId: "org-1",
        missionId: "mission-1",
        spacecraftId: "spacecraft-1",
      },
    });
    const headers = new Headers(request?.headers);
    expect(headers.get("x-cadence-poc-session")).toBe("session-1");
    expect(headers.get("x-csrf-token")).toBe("csrf-1");
    expect(headers.get("idempotency-key")).toBe("logical-action-retry-1");
    const secondRequest = (
      fetcher.mock.calls as unknown as Array<[RequestInfo | URL, RequestInit?]>
    )[1]?.[1];
    expect(new Headers(secondRequest?.headers).get("idempotency-key")).toBe(
      "logical-action-retry-1",
    );
    expect(request?.credentials).toBe("same-origin");
  });

  it("preserves structured host failures", async () => {
    const fetcher = vi.fn(async (_input: RequestInfo | URL, _request?: RequestInit) =>
      Response.json(
        {
          schema: "cadence.application-host-problem.v1",
          code: "forbidden",
          message: "The active operator cannot configure mission applications.",
        },
        { status: 403 },
      ),
    );
    const bridge = createHttpHostBridge(session, telemetryApplication, {
      fetch: fetcher as typeof fetch,
    });

    await expect(
      bridge.execute({
        applicationKey: "telemetry_decom",
        applicationVersion: 1,
        actionId: "save_packet_bindings",
        input: { expectedConfigurationVersion: 7, selectedApids: [] },
        context,
      }),
    ).rejects.toMatchObject({ status: 403, code: "forbidden" } satisfies Partial<HostBridgeError>);
  });

  it("stops a rejected action without replaying it and reports a sanitized reference", async () => {
    const fetcher = vi.fn(async () =>
      Response.json(
        {
          schema: "cadence.application-host-problem.v1",
          code: "invalid_csrf",
          message: "SECRET-RAW-CSRF-DETAIL",
        },
        { status: 403 },
      ),
    );
    const onSessionFailure = vi.fn();
    const bridge = createHttpHostBridge(session, telemetryApplication, {
      fetch: fetcher as typeof fetch,
      onSessionFailure,
    });

    const action = {
      applicationKey: "telemetry_decom",
      applicationVersion: 1,
      actionId: "save_packet_bindings",
      input: { expectedConfigurationVersion: 7, selectedApids: [100] },
      context,
      idempotencyKey: "logical-action-retry-2",
    };

    await expect(bridge.execute(action)).rejects.toMatchObject({
      status: 403,
      code: "invalid_csrf",
      message: expect.stringContaining(
        "The action was stopped because its security token was rejected.",
      ),
    });
    expect(fetcher).toHaveBeenCalledTimes(1);
    const sentRequest = (
      fetcher.mock.calls as unknown as Array<[RequestInfo | URL, RequestInit?]>
    )[0]?.[1];
    expect(JSON.stringify(sentRequest)).not.toContain("SECRET-RAW-CSRF-DETAIL");
    expect(onSessionFailure).toHaveBeenCalledWith("action", expect.any(HostBridgeError));

    bridge.invalidate();
    await expect(bridge.execute(action)).rejects.toMatchObject({ code: "stale_context" });
    expect(fetcher).toHaveBeenCalledTimes(1);
  });

  it("maps invalidation before fetch resolution to stale context and suppresses late events", async () => {
    const fetchResult = deferred<Response>();
    let requestSignal: AbortSignal | undefined;
    const fetcher = vi.fn((_input: RequestInfo | URL, request?: RequestInit) => {
      requestSignal = request?.signal ?? undefined;
      return fetchResult.promise;
    });
    const activity: HostActivityEvent[] = [];
    const onSessionFailure = vi.fn();
    const bridge = createHttpHostBridge(session, telemetryApplication, {
      fetch: fetcher as typeof fetch,
      onSessionFailure,
    });
    bridge.subscribe((event) => activity.push(event));

    const pending = bridge.query(queryRequest());
    await flushMicrotasks();
    bridge.invalidate();

    await expect(pending).rejects.toMatchObject({
      status: 409,
      code: "stale_context",
    } satisfies Partial<HostBridgeError>);
    expect(requestSignal?.aborted).toBe(true);

    fetchResult.resolve(Response.json({ queryVersion: 1 }));
    await flushMicrotasks();
    expect(activity.map(({ status }) => status)).toEqual(["started"]);
    expect(onSessionFailure).not.toHaveBeenCalled();

    bridge.invalidate();
  });

  it("maps invalidation during JSON decoding to stale context", async () => {
    const jsonResult = deferred<unknown>();
    const json = vi.fn(() => jsonResult.promise);
    const response = { ok: true, status: 200, json } as unknown as Response;
    const fetcher = vi.fn(() => response);
    const activity: HostActivityEvent[] = [];
    const bridge = createHttpHostBridge(session, telemetryApplication, {
      fetch: fetcher as unknown as typeof fetch,
    });
    bridge.subscribe((event) => activity.push(event));

    const pending = bridge.query(queryRequest());
    await flushMicrotasks();
    expect(json).toHaveBeenCalledTimes(1);
    bridge.invalidate();

    await expect(pending).rejects.toMatchObject({
      status: 409,
      code: "stale_context",
    } satisfies Partial<HostBridgeError>);
    jsonResult.resolve({ queryVersion: 1 });
    await flushMicrotasks();
    expect(activity.map(({ status }) => status)).toEqual(["started"]);
  });

  it("maps a fetch deadline to request_timed_out without session recovery", async () => {
    vi.useFakeTimers();
    try {
      const fetchResult = deferred<Response>();
      let requestSignal: AbortSignal | undefined;
      const fetcher = vi.fn((_input: RequestInfo | URL, request?: RequestInit) => {
        requestSignal = request?.signal ?? undefined;
        return fetchResult.promise;
      });
      const onSessionFailure = vi.fn();
      const bridge = createHttpHostBridge(session, telemetryApplication, {
        fetch: fetcher as typeof fetch,
        onSessionFailure,
        requestTimeoutMs: 25,
      });

      const pending = bridge.query(queryRequest());
      await flushMicrotasks();
      const timeoutExpectation = expect(pending).rejects.toMatchObject({
        status: 0,
        code: "request_timed_out",
      } satisfies Partial<HostBridgeError>);
      await vi.advanceTimersByTimeAsync(25);

      await timeoutExpectation;
      expect(requestSignal?.aborted).toBe(true);
      expect(onSessionFailure).not.toHaveBeenCalled();

      fetchResult.resolve(Response.json({ queryVersion: 1 }));
      await flushMicrotasks();
    } finally {
      vi.useRealTimers();
    }
  });

  it("maps a JSON decoding deadline to request_timed_out", async () => {
    vi.useFakeTimers();
    try {
      const jsonResult = deferred<unknown>();
      const json = vi.fn(() => jsonResult.promise);
      const response = { ok: true, status: 200, json } as unknown as Response;
      const bridge = createHttpHostBridge(session, telemetryApplication, {
        fetch: vi.fn(() => response) as unknown as typeof fetch,
        requestTimeoutMs: 25,
      });

      const pending = bridge.query(queryRequest());
      await flushMicrotasks();
      expect(json).toHaveBeenCalledTimes(1);
      const timeoutExpectation = expect(pending).rejects.toMatchObject({
        status: 0,
        code: "request_timed_out",
      } satisfies Partial<HostBridgeError>);
      await vi.advanceTimersByTimeAsync(25);

      await timeoutExpectation;
      jsonResult.resolve({ queryVersion: 1 });
      await flushMicrotasks();
    } finally {
      vi.useRealTimers();
    }
  });

  it("aborts every concurrent query and action when one bridge is invalidated", async () => {
    const fetchResults = [deferred<Response>(), deferred<Response>()];
    const requestSignals: AbortSignal[] = [];
    let requestIndex = 0;
    const fetcher = vi.fn((_input: RequestInfo | URL, request?: RequestInit) => {
      const signal = request?.signal;
      if (!signal) throw new Error("Expected a request abort signal.");
      requestSignals.push(signal);
      const result = fetchResults[requestIndex];
      requestIndex += 1;
      if (!result) throw new Error("Unexpected request count.");
      return result.promise;
    });
    const bridge = createHttpHostBridge(session, telemetryApplication, {
      fetch: fetcher as typeof fetch,
    });

    const pendingQuery = bridge.query(queryRequest());
    const pendingAction = bridge.execute(actionRequest("concurrent-action-1"));
    await flushMicrotasks();
    bridge.invalidate();

    await Promise.all([
      expect(pendingQuery).rejects.toMatchObject({ code: "stale_context" }),
      expect(pendingAction).rejects.toMatchObject({ code: "stale_context" }),
    ]);
    expect(requestSignals).toHaveLength(2);
    expect(requestSignals.every((signal) => signal.aborted)).toBe(true);

    fetchResults[0]?.resolve(Response.json({ queryVersion: 1 }));
    fetchResults[1]?.resolve(
      Response.json({
        receiptId: "receipt-1",
        completedAt: "2026-08-22T20:00:00.000Z",
        result: {},
      }),
    );
    await flushMicrotasks();
  });

  it("handles a late underlying rejection without an unhandled rejection or late event", async () => {
    const fetchResult = deferred<Response>();
    const activity: HostActivityEvent[] = [];
    const fetcher = vi.fn(() => fetchResult.promise);
    const bridge = createHttpHostBridge(session, telemetryApplication, {
      fetch: fetcher as typeof fetch,
    });
    bridge.subscribe((event) => activity.push(event));

    const pending = bridge.query(queryRequest());
    await flushMicrotasks();
    bridge.invalidate();
    await expect(pending).rejects.toMatchObject({ code: "stale_context" });

    fetchResult.reject(new Error("late underlying failure"));
    await flushMicrotasks();
    expect(activity.map(({ status }) => status)).toEqual(["started"]);
  });

  it("passes signals to successful query and action requests and cleans up each deadline", async () => {
    vi.useFakeTimers();
    try {
      const requestInits: RequestInit[] = [];
      const fetcher = vi.fn((_input: RequestInfo | URL, request?: RequestInit) => {
        if (!request) throw new Error("Expected request options.");
        requestInits.push(request);
        return requestInits.length === 1
          ? Response.json({ queryVersion: 1 })
          : Response.json({
              receiptId: "receipt-1",
              completedAt: "2026-08-22T20:00:00.000Z",
              result: { configurationVersion: 8 },
            });
      });
      const bridge = createHttpHostBridge(session, telemetryApplication, {
        fetch: fetcher as unknown as typeof fetch,
        requestTimeoutMs: 100,
      });

      await bridge.query(queryRequest());
      expect(vi.getTimerCount()).toBe(0);
      await bridge.execute(actionRequest());
      expect(vi.getTimerCount()).toBe(0);
      expect(requestInits).toHaveLength(2);
      expect(requestInits.every(({ signal }) => signal instanceof AbortSignal)).toBe(true);
      expect(requestInits.every(({ signal }) => !signal?.aborted)).toBe(true);
      expect(new Headers(requestInits[1]?.headers).get("idempotency-key")).toMatch(
        /^[0-9a-f-]{36}$/,
      );
    } finally {
      vi.useRealTimers();
    }
  });

  it("recovers once from a query 401 without replaying the query", async () => {
    const fetcher = vi.fn(async () =>
      Response.json(
        {
          schema: "cadence.application-host-problem.v1",
          code: "unauthenticated",
          message: "SECRET-RAW-QUERY-401",
        },
        { status: 401 },
      ),
    );
    const onSessionFailure = vi.fn();
    const bridge = createHttpHostBridge(session, telemetryApplication, {
      fetch: fetcher as typeof fetch,
      onSessionFailure,
    });

    await expect(bridge.query(queryRequest())).rejects.toMatchObject({
      status: 401,
      code: "unauthenticated",
    } satisfies Partial<HostBridgeError>);
    expect(fetcher).toHaveBeenCalledTimes(1);
    expect(onSessionFailure).toHaveBeenCalledTimes(1);
    expect(onSessionFailure).toHaveBeenCalledWith("query", expect.any(HostBridgeError));
  });

  it("recovers once from an action 401 without replaying the action", async () => {
    const fetcher = vi.fn(async () =>
      Response.json(
        {
          schema: "cadence.application-host-problem.v1",
          code: "invalid_session",
          message: "SECRET-RAW-ACTION-401",
        },
        { status: 401 },
      ),
    );
    const onSessionFailure = vi.fn();
    const bridge = createHttpHostBridge(session, telemetryApplication, {
      fetch: fetcher as typeof fetch,
      onSessionFailure,
    });

    await expect(bridge.execute(actionRequest("action-401-retry"))).rejects.toMatchObject({
      status: 401,
      code: "invalid_session",
    } satisfies Partial<HostBridgeError>);
    expect(fetcher).toHaveBeenCalledTimes(1);
    expect(onSessionFailure).toHaveBeenCalledTimes(1);
    expect(onSessionFailure).toHaveBeenCalledWith("action", expect.any(HostBridgeError));
  });
});

describe("the frontend-only demo host service", () => {
  it("discovers two independently released applications", () => {
    const service = new DemoHostService("production");
    const response = service.handle({
      method: "GET",
      url: "/api/cadence/application-host/v1/catalog?release=previous",
    });
    expect(response?.status).toBe(200);
    assertFrontendApplicationCatalog(response?.body);

    expect(response.body.applications.map(({ applicationKey }) => applicationKey)).toEqual([
      "telemetry_decom",
      "contract_probe",
    ]);
    expect(
      response.body.applications.every(({ release }) => release.federation === "module_federation"),
    ).toBe(true);
    expect(response.body.applications[0]?.release.manifestUrl).toContain("/releases/previous/");
  });

  it("derives viewer authority from the server session", () => {
    const service = new DemoHostService("development");
    const catalog = catalogFrom(service, "viewer");
    const response = service.handle({
      method: "POST",
      url: "/api/cadence/application-host/v1/actions",
      headers: sessionHeaders(catalog),
      body: {
        applicationKey: "telemetry_decom",
        applicationVersion: 1,
        actionId: "save_packet_bindings",
        input: { expectedConfigurationVersion: 7, selectedApids: [100] },
        scope: scopeFrom(catalog.session.context),
        actor: { permissions: ["applications:configure"] },
      },
    });

    expect(response).toMatchObject({
      status: 403,
      body: { code: "forbidden" },
    });
  });

  it("returns a conflict when a configuration changes after query", () => {
    const service = new DemoHostService("development");
    const catalog = catalogFrom(service, "stale");
    const query = service.handle({
      method: "POST",
      url: "/api/cadence/application-host/v1/query",
      headers: sessionHeaders(catalog),
      body: {
        queryId: "cadence.packet_bindings.manage",
        version: 1,
        scope: scopeFrom(catalog.session.context),
      },
    });
    const data = query?.body as { configurationVersion: number };

    const action = service.handle({
      method: "POST",
      url: "/api/cadence/application-host/v1/actions",
      headers: sessionHeaders(catalog),
      body: {
        applicationKey: "telemetry_decom",
        applicationVersion: 1,
        actionId: "save_packet_bindings",
        input: { expectedConfigurationVersion: data.configurationVersion, selectedApids: [100] },
        scope: scopeFrom(catalog.session.context),
      },
    });

    expect(action).toMatchObject({
      status: 409,
      body: { code: "stale_configuration" },
    });
  });
});

function catalogFrom(service: DemoHostService, scenario: string): FrontendApplicationCatalog {
  const response = service.handle({
    method: "GET",
    url: `/api/cadence/application-host/v1/catalog?scenario=${scenario}`,
  });
  assertFrontendApplicationCatalog(response?.body);
  return response.body;
}

function sessionHeaders(catalog: FrontendApplicationCatalog): Record<string, string> {
  return {
    "x-cadence-poc-session": catalog.session.sessionId,
    "x-csrf-token": catalog.session.csrfToken,
    "idempotency-key": crypto.randomUUID(),
  };
}

function scopeFrom(hostContext: HostContext) {
  return {
    organizationId: hostContext.organizationId,
    missionId: hostContext.missionId,
    spacecraftId: hostContext.spacecraftId,
  };
}
