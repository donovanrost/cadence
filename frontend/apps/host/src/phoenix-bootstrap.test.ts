import { describe, expect, it } from "vite-plus/test";
import { readPhoenixHostConfig } from "./phoenix-bootstrap";

describe("Phoenix federation entry", () => {
  it("reads explicit application, surface, context, catalog, and fallback attributes", () => {
    const root = document.createElement("div");
    root.dataset.applicationKey = "comms_overview";
    root.dataset.surfaceId = "overview";
    root.dataset.missionId = "mission-firebird";
    root.dataset.catalogUrl = "/api/cadence/application-host/v1/catalog";
    root.dataset.fallbackHref = "/missions/mission-firebird/comms";

    expect(readPhoenixHostConfig(root)).toEqual({
      applicationKey: "comms_overview",
      surfaceId: "overview",
      missionId: "mission-firebird",
      catalogUrl: "/api/cadence/application-host/v1/catalog",
      fallbackHref: "/missions/mission-firebird/comms",
    });
  });

  it("reads an optional spacecraft context without inventing one for mission routes", () => {
    const root = document.createElement("div");
    root.dataset.applicationKey = "telemetry_decom";
    root.dataset.surfaceId = "packet_bindings";
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

    expect(() => readPhoenixHostConfig(root)).toThrow(
      "data-application-key, data-surface-id, data-mission-id, data-catalog-url, and data-fallback-href",
    );
  });

  it("fails closed when a spacecraft attribute is present but blank", () => {
    const root = document.createElement("div");
    root.dataset.applicationKey = "telemetry_decom";
    root.dataset.surfaceId = "packet_bindings";
    root.dataset.spacecraftId = "  ";
    root.dataset.missionId = "mission-firebird";
    root.dataset.catalogUrl = "/catalog";
    root.dataset.fallbackHref = "/missions/mission-firebird";

    expect(() => readPhoenixHostConfig(root)).toThrow("non-empty data-spacecraft-id");
  });
});
