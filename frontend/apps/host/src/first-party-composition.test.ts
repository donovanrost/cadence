import type { CatalogApplication, FirstPartyApplicationManifest } from "@cadence/plugin-sdk";
import { describe, expect, it } from "vite-plus/test";
import { createHostContributionBootstrap } from "./first-party-composition";

const application = {
  applicationKey: "unlisted_application",
  applicationVersion: 7,
  displayName: "Unlisted application",
  description: "A valid catalog contribution that is unknown to the host source.",
  package: { packageId: "example.unlisted-application", version: 3 },
  surface: {
    surfaceId: "overview",
    version: 2,
    purpose: "overview" as const,
    scope: "organization" as const,
    placement: "application_workspace" as const,
    navigation: { label: "Overview", order: 1 },
    dataContract: { id: "example.unlisted-application.overview", version: 4 },
    actions: [],
    renderer: { kind: "federated-vue" as const, exposedModule: "./Application" },
  },
  release: {
    federation: "module_federation" as const,
    releaseId: "release-7",
    remoteName: "example_unlisted_application",
    manifestUrl: "/assets/application-host/unlisted-application/mf-manifest.json",
    exposedModule: "./Application",
  },
} satisfies CatalogApplication;

function moduleFor(value: CatalogApplication): {
  manifest: FirstPartyApplicationManifest;
  default: object;
} {
  return {
    manifest: {
      schema: "cadence.first-party-federated-application.v1",
      hostContract: "cadence.application-host.v1",
      package: { ...value.package, trust: "first_party" },
      compatibility: {
        cadenceApplicationContract: 1,
        cadenceSurfaceContract: 1,
        cadenceFederatedRendererContract: 1,
        cadenceThemeContract: 1,
      },
      application: {
        applicationKey: value.applicationKey,
        version: value.applicationVersion,
        displayName: value.displayName,
        description: value.description,
        installableScopes: [value.surface.scope],
      },
      surfaces: [value.surface],
    },
    default: {},
  };
}

describe("generic host composition", () => {
  it("admits an unknown but valid Phoenix catalog application", () => {
    const bootstrap = createHostContributionBootstrap();
    const module = moduleFor(application);

    expect(bootstrap.register(application, module)).toBe(module);
    expect(bootstrap.registry.list()).toHaveLength(1);
    expect(
      bootstrap.registry.get(application.applicationKey, application.applicationVersion),
    ).toMatchObject({ manifest: module.manifest });
  });

  it("fails closed when the loaded module identity differs from the admitted catalog", () => {
    const bootstrap = createHostContributionBootstrap();
    const module = moduleFor(application);

    expect(() =>
      bootstrap.register(
        {
          ...application,
          package: { ...application.package, packageId: "example.other-application" },
        },
        module,
      ),
    ).toThrow("does not match the host-approved application contract");
    expect(bootstrap.registry.list()).toHaveLength(0);
  });

  it("does not replace an already admitted contribution with a later module instance", () => {
    const bootstrap = createHostContributionBootstrap();
    const first = moduleFor(application);
    const second = moduleFor(application);

    expect(bootstrap.register(application, first)).toBe(first);
    expect(bootstrap.register(application, second)).toBe(second);
    expect(bootstrap.registry.list()).toHaveLength(1);
  });
});
