import type { CatalogApplication, FirstPartyApplicationManifest } from "@cadence/plugin-sdk";
import { describe, expect, it } from "vite-plus/test";
import {
  APPROVED_FIRST_PARTY_APPLICATIONS,
  createHostContributionBootstrap,
} from "./first-party-composition";

const context = {
  scope: "mission",
  organizationId: "org-1",
  missionId: "mission-1",
  missionName: "Firebird",
  spacecraftId: null,
  spacecraftName: null,
  actor: { displayName: "Mara Vance", permissions: ["applications:view"] },
} as const;

function applicationFor(
  contract: (typeof APPROVED_FIRST_PARTY_APPLICATIONS)[number],
): CatalogApplication {
  const exposedModule =
    contract.applicationKey === "comms_overview" ? "./LegacyApplication" : "./Application";
  const surface = {
    surfaceId: "overview",
    version: 1,
    purpose: "overview" as const,
    scope: "mission" as const,
    placement: "application_workspace" as const,
    navigation: { label: "Overview", order: 1 },
    dataContract: { id: `cadence.${contract.applicationKey}.overview`, version: 1 },
    actions: [],
    renderer: { kind: "federated-vue" as const, exposedModule },
  };

  return {
    applicationKey: contract.applicationKey,
    applicationVersion: 1,
    displayName: contract.applicationKey,
    description: "First-party contribution contract fixture.",
    package: { packageId: contract.packageId, version: 1 },
    surface,
    release: {
      federation: "module_federation",
      releaseId: `sha256:${"a".repeat(64)}`,
      remoteName: contract.remoteName,
      manifestUrl: `/assets/application-host/${contract.publicationBundle}/mf-manifest.json`,
      exposedModule,
    },
  };
}

function moduleFor(application: CatalogApplication): {
  manifest: FirstPartyApplicationManifest;
  default: object;
} {
  return {
    manifest: {
      schema: "cadence.first-party-federated-application.v1",
      hostContract: "cadence.application-host.v1",
      package: { ...application.package, trust: "first_party" },
      compatibility: {
        cadenceApplicationContract: 1,
        cadenceSurfaceContract: 1,
        cadenceFederatedRendererContract: 1,
        cadenceThemeContract: 1,
      },
      application: {
        applicationKey: application.applicationKey,
        version: application.applicationVersion,
        displayName: application.displayName,
        description: application.description,
        installableScopes: [context.scope],
      },
      surfaces: [application.surface],
    },
    default: {},
  };
}

describe("approved first-party host composition", () => {
  it("registers every approved application through the catalog admission boundary", () => {
    const bootstrap = createHostContributionBootstrap();

    for (const contract of APPROVED_FIRST_PARTY_APPLICATIONS) {
      const application = applicationFor(contract);
      const module = moduleFor(application);
      expect(bootstrap.register(application, module)).toBe(module);
    }

    expect(bootstrap.registry.list()).toHaveLength(APPROVED_FIRST_PARTY_APPLICATIONS.length);
    expect(
      bootstrap.registry.list().map(({ manifest }) => manifest.application.applicationKey),
    ).toEqual(APPROVED_FIRST_PARTY_APPLICATIONS.map(({ applicationKey }) => applicationKey));
  });

  it("rejects a known application with a catalog-swapped remote identity", () => {
    const bootstrap = createHostContributionBootstrap();
    const contract = APPROVED_FIRST_PARTY_APPLICATIONS[0];
    const application = applicationFor(contract);
    const module = moduleFor(application);

    expect(() =>
      bootstrap.register(
        { ...application, release: { ...application.release, remoteName: "cadence_imposter" } },
        module,
      ),
    ).toThrow("unexpected package or remote identity");
    expect(bootstrap.registry.list()).toHaveLength(0);
  });

  it("does not replace an already admitted contribution with a later module instance", () => {
    const bootstrap = createHostContributionBootstrap();
    const application = applicationFor(APPROVED_FIRST_PARTY_APPLICATIONS[0]);
    const first = moduleFor(application);
    const second = moduleFor(application);

    expect(bootstrap.register(application, first)).toBe(first);
    expect(bootstrap.register(application, second)).toBe(second);
    expect(bootstrap.registry.list()).toHaveLength(1);
  });
});
