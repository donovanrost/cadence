import {
  assertFrontendApplicationCatalog,
  type CatalogApplication,
  type FrontendApplicationCatalog,
  type HostActivityEvent,
  type HostContext,
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
    ).rejects.toMatchObject({ status: 400, code: "invalid_scope" } satisfies Partial<HostBridgeError>);
    expect(fetcher).not.toHaveBeenCalled();
  });

  it("rejects a query outside the selected surface contract before sending it", async () => {
    const fetcher = vi.fn(async () => Response.json({ queryVersion: 1 }));
    const bridge = createHttpHostBridge(session, telemetryApplication, {
      fetch: fetcher as typeof fetch,
    });

    await expect(
      bridge.query({ queryId: "cadence.packet_bindings.other", version: 1, context }),
    ).rejects.toMatchObject({ status: 400, code: "unsupported_query" } satisfies Partial<HostBridgeError>);
    expect(fetcher).not.toHaveBeenCalled();
  });

  it("rejects an action identity or declaration mismatch before sending it", async () => {
    const fetcher = vi.fn(async () =>
      Response.json({ receiptId: "receipt-1", completedAt: "2026-08-22T20:00:00.000Z", result: {} }),
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

    await bridge.execute({
      applicationKey: "telemetry_decom",
      applicationVersion: 1,
      actionId: "save_packet_bindings",
      input: { expectedConfigurationVersion: 7, selectedApids: [100] },
      context,
    });

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
    expect(headers.get("idempotency-key")).toBeTruthy();
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
