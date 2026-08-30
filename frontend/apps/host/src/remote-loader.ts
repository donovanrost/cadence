import { createInstance } from "@module-federation/runtime";
import {
  assertReleaseMatchesModule,
  type CatalogApplication,
  type FederationTransport,
  type FederatedApplicationModule,
} from "@cadence/plugin-sdk";
import * as Vue from "vue";
import type { Component } from "vue";

export interface FederatedRuntime {
  load(application: CatalogApplication): Promise<unknown>;
}

const moduleFederation = createInstance({
  name: "cadence_host",
  remotes: [],
  shared: {
    vue: {
      version: Vue.version,
      lib: () => Vue,
      shareConfig: {
        singleton: true,
        strictVersion: true,
        requiredVersion: "^3.5.40",
      },
      scope: ["default"],
      strategy: "loaded-first",
    },
  },
});

const moduleFederationRuntime: FederatedRuntime = {
  load(application) {
    moduleFederation.registerRemotes([
      {
        name: application.release.remoteName,
        entry: application.release.manifestUrl,
        type: "module",
      },
    ]);
    const exposedModule = application.release.exposedModule.replace(/^\.\//, "");
    return moduleFederation.loadRemote(`${application.release.remoteName}/${exposedModule}`);
  },
};

const federationRuntimeAdapters: Partial<Record<FederationTransport, FederatedRuntime>> = {
  module_federation: moduleFederationRuntime,
};

export async function loadFederatedApplication(
  application: CatalogApplication,
  runtime?: FederatedRuntime,
): Promise<FederatedApplicationModule<Component>> {
  let remote: unknown;

  try {
    remote = await (runtime ?? runtimeFor(application)).load(application);
  } catch (cause) {
    throw new Error(`Approved release ${application.release.releaseId} could not be loaded.`, {
      cause,
    });
  }

  assertReleaseMatchesModule(application, remote);

  return { manifest: remote.manifest, default: remote.default as Component };
}

function runtimeFor(application: CatalogApplication): FederatedRuntime {
  const runtime = federationRuntimeAdapters[application.release.federation];
  if (!runtime) {
    throw new Error(
      `Federation transport ${application.release.federation} is not supported by this host.`,
    );
  }
  return runtime;
}
