import { describe, expect, it } from "vite-plus/test";
import { createApplicationContributionRegistry } from "./contribution-registry";

const manifest = {
  schema: "cadence.first-party-federated-application.v1",
  hostContract: "cadence.application-host.v1",
  package: { packageId: "cadence.registry-test", version: 1, trust: "first_party" },
  compatibility: {
    cadenceApplicationContract: 1,
    cadenceSurfaceContract: 1,
    cadenceFederatedRendererContract: 1,
    cadenceThemeContract: 1,
  },
  application: {
    applicationKey: "registry_test",
    version: 1,
    displayName: "Registry test",
    description: "Tests host contribution registration.",
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
      dataContract: { id: "cadence.registry-test.overview", version: 1 },
      actions: [],
      renderer: { kind: "federated-vue", exposedModule: "./Application" },
    },
  ],
} as const;

describe("host application contribution registry", () => {
  it("registers and resolves contributions by app and version", () => {
    const load = () => ({ default: "renderer" });
    const registry = createApplicationContributionRegistry();
    const contribution = registry.register({ manifest, load });

    expect(registry.get("registry_test")).toBe(contribution);
    expect(registry.get("registry_test", 1)).toBe(contribution);
    expect(registry.list()).toEqual([contribution]);
  });

  it("rejects duplicate immutable contribution identities", () => {
    const contribution = { manifest, load: () => ({}) };
    const registry = createApplicationContributionRegistry([contribution]);
    expect(() => registry.register(contribution)).toThrow("already registered");
  });

  it("rejects malformed contributions before indexing them", () => {
    const registry = createApplicationContributionRegistry();
    expect(() =>
      registry.register({
        manifest: {
          ...manifest,
          package: { ...manifest.package, trust: "third_party" },
        } as never,
        load: () => ({}),
      }),
    ).toThrow("package declaration");
    expect(registry.list()).toHaveLength(0);
  });
});
