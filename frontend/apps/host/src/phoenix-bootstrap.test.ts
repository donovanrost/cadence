import { describe, expect, it } from "vite-plus/test";
import { readPhoenixHostConfig } from "./phoenix-bootstrap";

describe("Phoenix federation entry", () => {
  it("reads only the mission and catalog data attributes from the mount root", () => {
    const root = document.createElement("div");
    root.dataset.missionId = "mission-firebird";
    root.dataset.catalogUrl = "/api/cadence/application-host/v1/catalog";

    expect(readPhoenixHostConfig(root)).toEqual({
      missionId: "mission-firebird",
      catalogUrl: "/api/cadence/application-host/v1/catalog",
    });
  });

  it("fails closed when the Phoenix root omits either required attribute", () => {
    const root = document.createElement("div");
    root.dataset.missionId = "mission-firebird";

    expect(() => readPhoenixHostConfig(root)).toThrow("data-mission-id and data-catalog-url");
  });
});
