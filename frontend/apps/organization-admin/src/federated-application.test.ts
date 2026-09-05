import { describe, expect, it } from "vite-plus/test";
import { manifest } from "./federated-application";
import OrganizationAdminApplication from "./OrganizationAdminApplication.vue";
import { SURFACE_CONTRACTS } from "./organization-admin-contract";
import { surfaceComponents } from "./surface-components";

describe("organization admin federated application", () => {
  it("publishes the complete distinct post-auth surface manifest", () => {
    expect(manifest.application.applicationKey).toBe("organization_admin");
    expect(manifest.package.trust).toBe("first_party");
    expect(manifest.surfaces).toHaveLength(12);
    expect(new Set(manifest.surfaces.map((surface) => surface.surfaceId)).size).toBe(12);
    expect(manifest.package.packageId).toBe("cadence.organization-admin");
    expect(manifest.surfaces.every((surface) => surface.renderer.exposedModule === "./Application")).toBe(
      true,
    );
  });

  it.each(SURFACE_CONTRACTS)("maps $surfaceId to its legacy renderer", (surface) => {
    expect(OrganizationAdminApplication).toBeDefined();
    expect(surfaceComponents[surface.surfaceId]).toBeDefined();
    expect(manifest.surfaces.find(({ surfaceId }) => surfaceId === surface.surfaceId)).toMatchObject({
      dataContract: surface.query,
      actions: surface.actions,
      renderer: { exposedModule: "./Application" },
    });
  });
});
