import { beforeEach, describe, expect, it, vi } from "vite-plus/test";
import { createApp } from "vue";
import {
  bootstrapPhoenixHost,
  parsePhoenixQueryParams,
  readPhoenixHostConfig,
} from "./phoenix-bootstrap";

vi.mock("vue", async () => {
  const actual = await vi.importActual<typeof import("vue")>("vue");
  return {
    ...actual,
    createApp: vi.fn(() => ({ mount: vi.fn(), unmount: vi.fn() })),
  };
});

beforeEach(() => {
  vi.mocked(createApp).mockClear();
});

describe("Phoenix federation entry", () => {
  it("reads explicit application, surface, context, catalog, and fallback attributes", () => {
    const root = document.createElement("div");
    root.dataset.applicationKey = "comms_overview";
    root.dataset.surfaceId = "overview";
    root.dataset.hostScope = "mission";
    root.dataset.missionId = "mission-firebird";
    root.dataset.queryParams = JSON.stringify({ mission_id: "mission-firebird" });
    root.dataset.catalogUrl = "/api/cadence/application-host/v1/catalog";
    root.dataset.fallbackHref = "/missions/mission-firebird/comms";

    expect(readPhoenixHostConfig(root)).toEqual({
      applicationKey: "comms_overview",
      surfaceId: "overview",
      hostScope: "mission",
      missionId: "mission-firebird",
      catalogUrl: "/api/cadence/application-host/v1/catalog",
      fallbackHref: "/missions/mission-firebird/comms",
      queryParams: { mission_id: "mission-firebird" },
    });
  });

  it("reads an optional spacecraft context without inventing one for mission routes", () => {
    const root = document.createElement("div");
    root.dataset.applicationKey = "telemetry_decom";
    root.dataset.surfaceId = "packet_bindings";
    root.dataset.hostScope = "spacecraft";
    root.dataset.spacecraftId = "spacecraft-firebird-1";
    root.dataset.missionId = "mission-firebird";
    root.dataset.catalogUrl = "/api/cadence/application-host/v1/catalog";
    root.dataset.fallbackHref = "/missions/mission-firebird/spacecraft/firebird-1/applications";

    expect(readPhoenixHostConfig(root)).toMatchObject({
      applicationKey: "telemetry_decom",
      surfaceId: "packet_bindings",
      spacecraftId: "spacecraft-firebird-1",
      missionId: "mission-firebird",
    });
  });

  it("fails closed when the Phoenix root omits a required attribute", () => {
    const root = document.createElement("div");
    root.dataset.missionId = "mission-firebird";
    root.dataset.hostScope = "mission";

    expect(() => readPhoenixHostConfig(root)).toThrow(
      "data-application-key, data-surface-id, data-host-scope, data-catalog-url, and data-fallback-href",
    );
  });

  it("fails closed when a spacecraft attribute is present but blank", () => {
    const root = document.createElement("div");
    root.dataset.applicationKey = "telemetry_decom";
    root.dataset.surfaceId = "packet_bindings";
    root.dataset.hostScope = "mission";
    root.dataset.spacecraftId = "  ";
    root.dataset.missionId = "mission-firebird";
    root.dataset.catalogUrl = "/catalog";
    root.dataset.fallbackHref = "/missions/mission-firebird";

    expect(() => readPhoenixHostConfig(root)).toThrow("non-empty data-spacecraft-id");
  });

  it.each([
    ["organization", { hostScope: "organization", organizationId: "org-1" }],
    ["user/account", { hostScope: "user", userId: "user-1" }],
    ["admin/global", { hostScope: "admin" }],
  ] as const)("reads the %s root without a mission id", (_label, attributes) => {
    const root = document.createElement("div");
    root.dataset.applicationKey = "organization_admin";
    root.dataset.surfaceId = "overview";
    root.dataset.hostScope = attributes.hostScope;
    if ("organizationId" in attributes) root.dataset.organizationId = attributes.organizationId;
    if ("userId" in attributes) root.dataset.userId = attributes.userId;
    root.dataset.catalogUrl = "/api/cadence/application-host/v1/catalog";
    root.dataset.fallbackHref = "/applications/organization_admin";

    expect(readPhoenixHostConfig(root)).toMatchObject(attributes);
  });

  it("rejects identifiers from a different host scope", () => {
    const root = document.createElement("div");
    root.dataset.applicationKey = "organization_admin";
    root.dataset.surfaceId = "overview";
    root.dataset.hostScope = "organization";
    root.dataset.organizationId = "org-1";
    root.dataset.missionId = "mission-1";
    root.dataset.catalogUrl = "/catalog";
    root.dataset.fallbackHref = "/applications/organization_admin";

    expect(() => readPhoenixHostConfig(root)).toThrow("invalid organization scope");
  });

  it("requires an explicit host scope even when a mission id is present", () => {
    const root = document.createElement("div");
    root.dataset.applicationKey = "mission_catalog";
    root.dataset.surfaceId = "mission_overview";
    root.dataset.missionId = "mission-firebird";
    root.dataset.catalogUrl = "/catalog";
    root.dataset.fallbackHref = "/missions/mission-firebird";

    expect(() => readPhoenixHostConfig(root)).toThrow("explicit data-host-scope");
  });

  it.each([
    ["an array", "[]"],
    ["malformed JSON", "{"],
    ["a prototype-pollution key", '{"__proto__":{"polluted":true}}'],
  ])("rejects %s query parameters", (_label, raw) => {
    expect(() => parsePhoenixQueryParams(raw)).toThrow("query parameters");
  });

  it("rejects oversized and deeply nested query parameters", () => {
    expect(() => parsePhoenixQueryParams(JSON.stringify({ value: "x".repeat(257) }))).toThrow(
      "query parameters",
    );
    expect(() => parsePhoenixQueryParams('{"a":{"b":{"c":{"d":{"e":{"f":"too-deep"}}}}}}')).toThrow(
      "query parameters",
    );
  });

  it("mounts each root once and creates a fresh mount after cleanup", () => {
    const root = document.createElement("div");
    root.dataset.applicationKey = "mission_catalog";
    root.dataset.surfaceId = "mission_overview";
    root.dataset.hostScope = "mission";
    root.dataset.missionId = "mission-firebird";
    root.dataset.catalogUrl = "/catalog";
    root.dataset.fallbackHref = "/missions/mission-firebird";
    document.body.append(root);

    const first = bootstrapPhoenixHost(root);
    const second = bootstrapPhoenixHost(root);

    expect(second).toBe(first);
    expect(createApp).toHaveBeenCalledTimes(1);

    first.unmount();
    first.unmount();
    const third = bootstrapPhoenixHost(root);

    expect(third).not.toBe(first);
    expect(createApp).toHaveBeenCalledTimes(2);
    third.unmount();
    root.remove();
  });

  it("keeps replacement roots independent and cleans up the removed root", () => {
    const firstRoot = document.createElement("div");
    const replacementRoot = document.createElement("div");
    for (const root of [firstRoot, replacementRoot]) {
      root.dataset.applicationKey = "mission_catalog";
      root.dataset.surfaceId = "mission_overview";
      root.dataset.hostScope = "mission";
      root.dataset.missionId = "mission-firebird";
      root.dataset.catalogUrl = "/catalog";
      root.dataset.fallbackHref = "/missions/mission-firebird";
      document.body.append(root);
    }

    const firstMount = bootstrapPhoenixHost(firstRoot);
    const replacementMount = bootstrapPhoenixHost(replacementRoot);
    const createdApps = vi.mocked(createApp).mock.results.map((result) => result.value);

    firstRoot.remove();
    firstMount.unmount();

    expect(createdApps).toHaveLength(2);
    expect(createdApps[0]?.unmount).toHaveBeenCalledTimes(1);
    expect(createdApps[1]?.unmount).not.toHaveBeenCalled();

    replacementMount.unmount();
    replacementRoot.remove();
  });
});
