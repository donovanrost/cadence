import { describe, expect, it } from "vite-plus/test";
import { manifest, pageSurfaces } from "./federated-application";

describe("mission and catalog remote manifest", () => {
  it("declares the first-party host contract", () => {
    expect(manifest.package).toEqual({
      packageId: "cadence.mission-catalog",
      version: 1,
      trust: "first_party",
    });
    expect(manifest.application).toMatchObject({
      applicationKey: "mission_catalog",
      version: 1,
      installableScopes: ["organization", "mission"],
    });
  });

  it("maps every Phoenix-facing page to a remote surface", () => {
    expect(pageSurfaces.map(({ surfaceId }) => surfaceId)).toEqual([
      "mission_list",
      "mission_new",
      "mission_overview",
      "mission_applications",
      "catalog_index",
      "catalog_database_new",
      "catalog_database_show",
      "catalog_revision_show",
      "catalog_artifact_show",
      "catalog_import_run_show",
    ]);

    expect(pageSurfaces.every(({ renderer }) => renderer.kind === "federated-vue")).toBe(true);
    expect(pageSurfaces.every(({ renderer }) => renderer.exposedModule.startsWith("./"))).toBe(
      true,
    );
  });
});
