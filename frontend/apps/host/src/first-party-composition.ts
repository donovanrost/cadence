import {
  assertReleaseMatchesModule,
  type CatalogApplication,
  type FederatedApplicationModule,
} from "@cadence/plugin-sdk";
import type { Component } from "vue";
import {
  createApplicationContributionRegistry,
  type ApplicationContributionRegistry,
} from "./contribution-registry";

export const APPROVED_FIRST_PARTY_APPLICATIONS = Object.freeze([
  {
    applicationKey: "organization_admin",
    packageId: "cadence.organization_admin",
    remoteName: "cadence_organization_admin",
    publicationBundle: "organization-admin",
  },
  {
    applicationKey: "mission_catalog",
    packageId: "cadence.mission-catalog",
    remoteName: "cadence_mission_catalog",
    publicationBundle: "mission-catalog",
  },
  {
    applicationKey: "spacecraft",
    packageId: "cadence.spacecraft",
    remoteName: "cadence_spacecraft",
    publicationBundle: "spacecraft",
  },
  {
    applicationKey: "telemetry_decom",
    packageId: "cadence.telemetry-applications",
    remoteName: "cadence_telemetry_decom",
    publicationBundle: "telemetry-decom",
  },
  {
    applicationKey: "comms",
    packageId: "cadence.comms",
    remoteName: "cadence_comms",
    publicationBundle: "comms",
  },
  {
    applicationKey: "comms_overview",
    packageId: "cadence.comms_overview",
    remoteName: "cadence_comms",
    publicationBundle: "comms",
  },
  {
    applicationKey: "ops_console",
    packageId: "cadence.ops_console",
    remoteName: "cadence_ops_console",
    publicationBundle: "ops-console",
  },
] as const);

export type HostRemoteModule = FederatedApplicationModule<Component>;

export interface HostContributionBootstrap {
  registry: ApplicationContributionRegistry<HostRemoteModule>;
  register(application: CatalogApplication, module: HostRemoteModule): HostRemoteModule;
}

/**
 * Creates the host-side composition boundary for one catalog/bootstrap realm.
 * Phoenix remains the authority for catalog admission and the federation
 * runtime remains the authority for release-addressed module loading.
 */
export function createHostContributionBootstrap(): HostContributionBootstrap {
  const registry = createApplicationContributionRegistry<HostRemoteModule>();

  return {
    registry,
    register(application, module) {
      assertReleaseMatchesModule(application, module);
      assertKnownFirstPartyIdentity(application);

      const existing = registry.get(application.applicationKey, application.applicationVersion);
      if (existing) {
        assertReleaseMatchesModule(application, {
          manifest: existing.manifest,
          default: module.default,
        });
        // The runtime result remains authoritative for the exact catalog
        // release being mounted; the registry never replaces its first entry.
        return module;
      }

      registry.register({ manifest: module.manifest, load: () => module });
      return module;
    },
  };
}

export function assertKnownFirstPartyIdentity(application: CatalogApplication): void {
  const expected = APPROVED_FIRST_PARTY_APPLICATIONS.find(
    ({ applicationKey }) => applicationKey === application.applicationKey,
  );

  if (!expected) return;
  if (
    application.package.packageId !== expected.packageId ||
    application.release.remoteName !== expected.remoteName
  ) {
    throw new Error(
      `Approved application ${application.applicationKey} has an unexpected package or remote identity.`,
    );
  }
}
