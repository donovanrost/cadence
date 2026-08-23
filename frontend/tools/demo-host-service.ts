import { randomUUID } from "node:crypto";
import type { IncomingMessage, ServerResponse } from "node:http";

const APPLICATION_HOST_CONTRACT = "cadence.application-host.v1" as const;
const FRONTEND_APPLICATION_CATALOG_SCHEMA = "cadence.first-party-frontend-catalog.v1" as const;

export type DemoMode = "development" | "production";
export type DemoScenario =
  | "normal"
  | "offline"
  | "incompatible"
  | "malformed"
  | "throw"
  | "viewer"
  | "stale";

export interface DemoRequest {
  method: string;
  url: string;
  headers?: Readonly<Record<string, string | undefined>>;
  body?: unknown;
}

export interface DemoResponse {
  status: number;
  headers?: Readonly<Record<string, string>>;
  body: unknown;
}

interface DemoSession {
  csrfToken: string;
  context: HostContext;
  scenario: DemoScenario;
}

interface HostContext {
  organizationId: string;
  missionId: string;
  missionName: string;
  spacecraftId: string;
  spacecraftName: string;
  actor: {
    displayName: string;
    permissions: string[];
  };
}

interface HostActionReceipt {
  receiptId: string;
  completedAt: string;
  result: unknown;
}

interface CatalogApplication {
  applicationKey: string;
  applicationVersion: number;
  displayName: string;
  description: string;
  package: { packageId: string; version: number };
  surface: {
    surfaceId: string;
    version: number;
    purpose: "overview" | "configuration";
    scope: "spacecraft";
    placement: "application_workspace";
    navigation: { label: string; order: number };
    dataContract: { id: string; version: number };
    actions: string[];
    renderer: { kind: "federated-vue"; exposedModule: string };
  };
  release: {
    federation: "module_federation";
    releaseId: string;
    remoteName: string;
    manifestUrl: string;
    exposedModule: string;
  };
}

interface PacketBindingRecord {
  apid: number;
  description: string;
  fieldCount: number;
  name: string;
  rateHz: number;
  selected: boolean;
}

interface PacketBindingsData {
  configurationVersion: number;
  packets: PacketBindingRecord[];
  queryVersion: 1;
  revision: {
    id: string;
    importedAt: string;
    label: string;
  };
  sourceEndpoint: {
    id: string;
    label: string;
    status: "connected" | "disconnected";
  };
}

const bridgeBaseUrl = "/api/cadence/application-host/v1";

const fullAccessContext: HostContext = {
  organizationId: "org-orbital-research",
  missionId: "mission-firebird",
  missionName: "Firebird",
  spacecraftId: "spacecraft-fb-1",
  spacecraftName: "FB-1 Pathfinder",
  actor: {
    displayName: "Mara Vance",
    permissions: ["applications:view", "applications:configure"],
  },
};

const seedData: PacketBindingsData = {
  queryVersion: 1,
  configurationVersion: 7,
  revision: {
    id: "revision-flight-12",
    label: "XTCE / FLIGHT 12",
    importedAt: "2026-08-22T14:32:00.000Z",
  },
  sourceEndpoint: {
    id: "endpoint-sband-a",
    label: "S-BAND A · PRIME",
    status: "connected",
  },
  packets: [
    {
      apid: 100,
      name: "BUS HOUSEKEEPING",
      description: "Electrical power, thermal, and processor health",
      fieldCount: 18,
      rateHz: 1,
      selected: true,
    },
    {
      apid: 120,
      name: "ATTITUDE STATE",
      description: "Quaternion, body rates, and estimator residuals",
      fieldCount: 24,
      rateHz: 10,
      selected: true,
    },
    {
      apid: 141,
      name: "PROPULSION",
      description: "Tank pressure, line temperature, and valve state",
      fieldCount: 31,
      rateHz: 2,
      selected: false,
    },
    {
      apid: 205,
      name: "PAYLOAD SCIENCE",
      description: "Instrument frame metadata and collection state",
      fieldCount: 42,
      rateHz: 5,
      selected: true,
    },
    {
      apid: 222,
      name: "EVENT REPORT",
      description: "Onboard events, alarms, and sequence markers",
      fieldCount: 12,
      rateHz: 0.2,
      selected: false,
    },
  ],
};

export class DemoHostService {
  readonly #mode: DemoMode;
  readonly #sessions = new Map<string, DemoSession>();
  readonly #receipts = new Map<string, HostActionReceipt>();
  #packetBindings = structuredClone(seedData);

  constructor(mode: DemoMode) {
    this.#mode = mode;
  }

  handle(request: DemoRequest): DemoResponse | undefined {
    const url = new URL(request.url, "http://127.0.0.1:5173");

    if (request.method === "GET" && url.pathname === `${bridgeBaseUrl}/catalog`) {
      return this.#catalogResponse(url);
    }

    if (request.method === "POST" && url.pathname === `${bridgeBaseUrl}/query`) {
      return this.#queryResponse(request);
    }

    if (request.method === "POST" && url.pathname === `${bridgeBaseUrl}/actions`) {
      return this.#actionResponse(request);
    }

    return undefined;
  }

  #catalogResponse(url: URL): DemoResponse {
    const scenario = demoScenario(url.searchParams.get("scenario"));

    if (scenario === "malformed") {
      return json(200, { schema: "cadence.invalid-catalog.v1", applications: "not-a-list" });
    }

    const release = url.searchParams.get("release") === "previous" ? "previous" : "current";
    const sessionId = `poc-${scenario}-${randomUUID()}`;
    const csrfToken = randomUUID();
    const context = contextForScenario(scenario);
    this.#sessions.set(sessionId, { csrfToken, context, scenario });

    const catalog = {
      schema: FRONTEND_APPLICATION_CATALOG_SCHEMA,
      hostContract: APPLICATION_HOST_CONTRACT,
      generatedAt: new Date().toISOString(),
      session: { sessionId, csrfToken, bridgeBaseUrl, context },
      applications: catalogApplications(this.#mode, scenario, release),
    };

    return json(200, catalog, { "cache-control": "no-store" });
  }

  #queryResponse(request: DemoRequest): DemoResponse {
    const authorization = this.#authorize(request);
    if ("response" in authorization) return authorization.response;

    const body = request.body;
    if (!isRecord(body) || !validScope(body.scope, authorization.session.context)) {
      return problem(400, "invalid_scope", "The requested application scope is invalid.");
    }

    if (body.queryId === "cadence.packet_bindings.manage" && body.version === 1) {
      const data = structuredClone(this.#packetBindings);
      if (authorization.session.scenario === "stale") data.configurationVersion -= 1;
      return json(200, data);
    }

    if (body.queryId === "cadence.contract_probe.snapshot" && body.version === 1) {
      return json(200, {
        queryVersion: 1,
        hostContract: APPLICATION_HOST_CONTRACT,
        catalogMode: this.#mode,
        checks: [
          { id: "catalog", label: "Runtime catalog", status: "nominal" },
          { id: "bridge", label: "Host bridge", status: "nominal" },
          { id: "scope", label: "Server-derived scope", status: "nominal" },
        ],
      });
    }

    return problem(404, "unsupported_query", "The host does not provide that query contract.");
  }

  #actionResponse(request: DemoRequest): DemoResponse {
    const authorization = this.#authorize(request);
    if ("response" in authorization) return authorization.response;

    const { session } = authorization;
    if (!session.context.actor.permissions.includes("applications:configure")) {
      return problem(
        403,
        "forbidden",
        "The active operator cannot configure mission applications.",
      );
    }

    const body = request.body;
    if (!isRecord(body) || !validScope(body.scope, session.context)) {
      return problem(400, "invalid_scope", "The requested application scope is invalid.");
    }

    const idempotencyKey = header(request.headers, "idempotency-key");
    if (!idempotencyKey) {
      return problem(400, "idempotency_required", "Host actions require an idempotency key.");
    }

    const existingReceipt = this.#receipts.get(
      `${session.context.actor.displayName}:${idempotencyKey}`,
    );
    if (existingReceipt) return json(200, existingReceipt);

    if (
      body.applicationKey !== "telemetry_decom" ||
      body.applicationVersion !== 1 ||
      body.actionId !== "save_packet_bindings"
    ) {
      return problem(404, "unsupported_action", "The host does not provide that action contract.");
    }

    const input = body.input;
    if (!validSaveInput(input)) {
      return problem(422, "invalid_action_input", "The packet binding input is invalid.");
    }

    if (input.expectedConfigurationVersion !== this.#packetBindings.configurationVersion) {
      return problem(
        409,
        "stale_configuration",
        "Packet bindings changed after this surface loaded.",
      );
    }

    const selected = new Set(input.selectedApids);
    this.#packetBindings = {
      ...this.#packetBindings,
      configurationVersion: this.#packetBindings.configurationVersion + 1,
      packets: this.#packetBindings.packets.map((packet) => ({
        ...packet,
        selected: selected.has(packet.apid),
      })),
    };

    const receipt: HostActionReceipt = {
      receiptId: `receipt-${randomUUID()}`,
      completedAt: new Date().toISOString(),
      result: {
        configurationVersion: this.#packetBindings.configurationVersion,
        selectedCount: input.selectedApids.length,
      },
    };
    this.#receipts.set(`${session.context.actor.displayName}:${idempotencyKey}`, receipt);
    return json(200, receipt);
  }

  #authorize(request: DemoRequest): { session: DemoSession } | { response: DemoResponse } {
    const sessionId = header(request.headers, "x-cadence-poc-session");
    const csrfToken = header(request.headers, "x-csrf-token");
    const session = sessionId ? this.#sessions.get(sessionId) : undefined;

    if (!session || csrfToken !== session.csrfToken) {
      return {
        response: problem(401, "invalid_session", "The authenticated host session is invalid."),
      };
    }

    return { session };
  }
}

export function createDemoHostMiddleware(mode: DemoMode) {
  const service = new DemoHostService(mode);

  return async function demoHostMiddleware(
    request: IncomingMessage,
    response: ServerResponse,
    next: () => void,
  ): Promise<void> {
    const url = request.url ?? "/";
    if (!url.startsWith("/api/cadence/application-host/v1/")) {
      next();
      return;
    }

    let body: unknown;
    if (request.method === "POST") {
      try {
        body = JSON.parse(await requestBody(request));
      } catch {
        writeResponse(
          response,
          problem(400, "invalid_json", "The request body is not valid JSON."),
        );
        return;
      }
    }

    const result = service.handle({
      method: request.method ?? "GET",
      url,
      headers: normalizeHeaders(request.headers),
      body,
    });

    if (!result) {
      next();
      return;
    }

    writeResponse(response, result);
  };
}

function catalogApplications(
  mode: DemoMode,
  scenario: DemoScenario,
  release: "current" | "previous",
): CatalogApplication[] {
  const production = mode === "production";
  const telemetryReleaseId = release === "previous" ? "2026.08.22.1" : "2026.08.22.2";
  const telemetryManifest = production
    ? `http://127.0.0.1:4174/releases/${release}/mf-manifest.json`
    : "http://127.0.0.1:4174/mf-manifest.json";
  const exposedModule = scenario === "throw" ? "./Failure" : "./Application";

  return [
    {
      applicationKey: "telemetry_decom",
      applicationVersion: scenario === "incompatible" ? 2 : 1,
      displayName: "Telemetry Decom",
      description: "Choose the packet inputs decoded for an installed spacecraft.",
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
        renderer: { kind: "federated-vue", exposedModule },
      },
      release: {
        federation: "module_federation",
        releaseId: telemetryReleaseId,
        remoteName: `telemetry_decom_${release}_${telemetryReleaseId.replaceAll(".", "_")}`,
        manifestUrl:
          scenario === "offline" ? "http://127.0.0.1:4199/mf-manifest.json" : telemetryManifest,
        exposedModule,
      },
    },
    {
      applicationKey: "contract_probe",
      applicationVersion: 1,
      displayName: "Contract Probe",
      description: "A development fixture proving that the host can discover another remote.",
      package: { packageId: "cadence.frontend-fixtures", version: 1 },
      surface: {
        surfaceId: "runtime_contracts",
        version: 1,
        purpose: "overview",
        scope: "spacecraft",
        placement: "application_workspace",
        navigation: { label: "Runtime contracts", order: 90 },
        dataContract: { id: "cadence.contract_probe.snapshot", version: 1 },
        actions: [],
        renderer: { kind: "federated-vue", exposedModule: "./Application" },
      },
      release: {
        federation: "module_federation",
        releaseId: "2026.08.22.1",
        remoteName: "contract_probe_current_2026_08_22_1",
        manifestUrl: production
          ? "http://127.0.0.1:4175/releases/current/mf-manifest.json"
          : "http://127.0.0.1:4175/mf-manifest.json",
        exposedModule: "./Application",
      },
    },
  ];
}

function contextForScenario(scenario: DemoScenario): HostContext {
  if (scenario !== "viewer") return structuredClone(fullAccessContext);

  return {
    ...structuredClone(fullAccessContext),
    actor: { displayName: "Noah Chen", permissions: ["applications:view"] },
  };
}

function demoScenario(value: string | null): DemoScenario {
  if (
    value === "offline" ||
    value === "incompatible" ||
    value === "malformed" ||
    value === "throw" ||
    value === "viewer" ||
    value === "stale"
  ) {
    return value;
  }

  return "normal";
}

function validScope(value: unknown, context: HostContext): boolean {
  return (
    isRecord(value) &&
    value.organizationId === context.organizationId &&
    value.missionId === context.missionId &&
    value.spacecraftId === context.spacecraftId
  );
}

function validSaveInput(
  value: unknown,
): value is { expectedConfigurationVersion: number; selectedApids: number[] } {
  return (
    isRecord(value) &&
    Number.isInteger(value.expectedConfigurationVersion) &&
    Array.isArray(value.selectedApids) &&
    value.selectedApids.every(Number.isInteger) &&
    new Set(value.selectedApids).size === value.selectedApids.length
  );
}

function header(headers: DemoRequest["headers"], name: string): string | undefined {
  return headers?.[name.toLowerCase()];
}

function json(
  status: number,
  body: unknown,
  headers: Readonly<Record<string, string>> = {},
): DemoResponse {
  return {
    status,
    headers: { "content-type": "application/json; charset=utf-8", ...headers },
    body,
  };
}

function problem(status: number, code: string, message: string): DemoResponse {
  return json(status, {
    schema: "cadence.application-host-problem.v1",
    code,
    message,
  });
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

async function requestBody(request: IncomingMessage): Promise<string> {
  const chunks: Uint8Array[] = [];
  for await (const chunk of request) {
    chunks.push(typeof chunk === "string" ? Buffer.from(chunk) : chunk);
  }
  return Buffer.concat(chunks).toString("utf8");
}

function normalizeHeaders(headers: IncomingMessage["headers"]): Record<string, string | undefined> {
  return Object.fromEntries(
    Object.entries(headers).map(([name, value]) => [
      name.toLowerCase(),
      Array.isArray(value) ? value.join(", ") : value,
    ]),
  );
}

function writeResponse(response: ServerResponse, result: DemoResponse): void {
  response.writeHead(result.status, result.headers);
  response.end(JSON.stringify(result.body));
}
