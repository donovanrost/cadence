import { describe, expect, it } from "vite-plus/test";
import { defineApplicationContribution, fullPageSurfaceProps } from "./surface";

const manifest = {
  schema: "cadence.first-party-federated-application.v1",
  hostContract: "cadence.application-host.v1",
  package: { packageId: "cadence.shared-host-test", version: 1, trust: "first_party" },
  compatibility: {
    cadenceApplicationContract: 1,
    cadenceSurfaceContract: 1,
    cadenceFederatedRendererContract: 1,
    cadenceThemeContract: 1,
  },
  application: {
    applicationKey: "shared_host_test",
    version: 1,
    displayName: "Shared host test",
    description: "Tests the domain-agnostic contribution contract.",
    installableScopes: ["mission"],
  },
  surfaces: [
    {
      surfaceId: "overview",
      version: 1,
      purpose: "overview",
      scope: "mission",
      placement: "application_workspace",
      navigation: { label: "Overview", order: 1 },
      dataContract: { id: "cadence.shared-host-test.overview", version: 1 },
      actions: [],
      renderer: { kind: "federated-vue", exposedModule: "./Application" },
    },
  ],
} as const;

const application = {
  applicationKey: "shared_host_test",
  applicationVersion: 1,
  displayName: "Shared host test",
  description: "Tests the domain-agnostic contribution contract.",
  package: { packageId: "cadence.shared-host-test", version: 1 },
  surface: manifest.surfaces[0],
  release: {
    federation: "module_federation",
    releaseId: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    remoteName: "cadence_shared_host_test",
    manifestUrl: "/releases/shared-host-test/mf-manifest.json",
    exposedModule: "./Application",
  },
} as const;

const context = {
  scope: "mission",
  organizationId: "org-1",
  missionId: "mission-1",
  missionName: "Firebird",
  spacecraftId: null,
  spacecraftName: null,
  actor: { displayName: "Mara Vance", permissions: ["applications:view"] },
} as const;

describe("domain-agnostic surface contributions", () => {
  it("validates and preserves a remote contribution loader", () => {
    const load = async () => ({ default: "surface" });
    const contribution = defineApplicationContribution({ manifest, load });
    expect(contribution.manifest.application.applicationKey).toBe("shared_host_test");
    expect(contribution.load).toBe(load);
  });

  it("creates full-page mount props from approved host data", () => {
    const bridge = {} as never;
    expect(fullPageSurfaceProps(application, context, bridge)).toEqual({
      application,
      surface: application.surface,
      context,
      bridge,
    });
  });

  it("rejects a surface that is not a full-page application workspace", () => {
    expect(() =>
      fullPageSurfaceProps(
        { ...application, surface: { ...application.surface, placement: "ops_dock" } },
        context,
        {} as never,
      ),
    ).toThrow("application_workspace");
  });
});
