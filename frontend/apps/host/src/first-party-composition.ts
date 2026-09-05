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
