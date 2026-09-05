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
  load(application: CatalogApplication, options?: FederatedRuntimeLoadOptions): Promise<unknown>;
}

export interface FederatedRuntimeLoadOptions {
  signal?: AbortSignal;
}

export interface ReleaseAwareModuleFederationClient {
  registerRemotes(remotes: Array<{ name: string; entry: string; type: "module" }>): void;
  loadRemote<T = unknown>(id: string): Promise<T | null>;
}

const vueShare = () => ({
  version: Vue.version,
  lib: () => Vue,
  shareConfig: {
    singleton: true,
    strictVersion: true,
    requiredVersion: "^3.5.40",
  },
  scope: ["default"],
  strategy: "loaded-first" as const,
});

type RuntimeSlot = {
  identity: string;
  client: ReleaseAwareModuleFederationClient;
};

type RuntimeFamily = {
  current?: RuntimeSlot;
  fallback?: RuntimeSlot;
};

type ReleaseAwareClientFactory = (runtimeIdentity: string) => ReleaseAwareModuleFederationClient;

export const FEDERATED_LOAD_TIMEOUT_MS = 15_000;

function canonicalManifestUrl(manifestUrl: string): string {
  return new URL(manifestUrl).href;
}

function runtimeIdentity(application: CatalogApplication): string {
  const { release, surface } = application;
  return JSON.stringify([
    release.federation,
    application.applicationKey,
    application.applicationVersion,
    surface.surfaceId,
    surface.version,
    release.remoteName,
    release.exposedModule,
    release.releaseId,
    canonicalManifestUrl(release.manifestUrl),
  ]);
}

function runtimeFamilyIdentity(application: CatalogApplication): string {
  const { release, surface } = application;
  return JSON.stringify([
    release.federation,
    application.applicationKey,
    application.applicationVersion,
    surface.surfaceId,
    surface.version,
    release.remoteName,
    release.exposedModule,
  ]);
}

function runtimeName(identity: string): string {
  return `cadence_host_${Array.from(identity, (character) => character.codePointAt(0)?.toString(16)).join("_")}`;
}

export function createReleaseAwareRuntime(
  createClient: ReleaseAwareClientFactory,
): FederatedRuntime {
  // 2.8.2 has no public disposer. Keep only the active and exact predecessor
  // runtime in this realm, and reject a third distinct immutable release.
  const runtimeFamilies = new Map<string, RuntimeFamily>();

  const clientFor = (application: CatalogApplication, identity: string) => {
    const client = createClient(identity);
    client.registerRemotes([
      {
        name: application.release.remoteName,
        entry: canonicalManifestUrl(application.release.manifestUrl),
        type: "module",
      },
    ]);
    return client;
  };

  return {
    load(application, { signal } = {}) {
      assertNotAborted(signal);
      const familyKey = runtimeFamilyIdentity(application);
      const identity = runtimeIdentity(application);
      const family = runtimeFamilies.get(familyKey) || {};
      let slot = family.current?.identity === identity ? family.current : undefined;

      if (!slot && family.fallback?.identity === identity) {
        slot = family.fallback;
        family.fallback = family.current;
        family.current = slot;
      }

      if (!slot) {
        if (family.current && family.fallback) {
          throw new Error(
            `Approved release ${application.release.releaseId} cannot be loaded because this host realm retains a current and fallback release already.`,
          );
        }

        slot = {
          identity,
          client: clientFor(application, identity),
        };
        family.fallback = family.current;
        family.current = slot;
      }

      runtimeFamilies.set(familyKey, family);
      const exposedModule = application.release.exposedModule.replace(/^\.\//, "");
      const load = slot.client.loadRemote(`${application.release.remoteName}/${exposedModule}`);
      return load.then((remote) => {
        assertNotAborted(signal);
        return remote;
      });
    },
  };
}

const moduleFederationRuntime = createReleaseAwareRuntime((identity) =>
  createInstance({
    name: runtimeName(identity),
    id: identity,
    remotes: [],
    shared: { vue: vueShare() },
  }),
);

const federationRuntimeAdapters: Partial<Record<FederationTransport, FederatedRuntime>> = {
  module_federation: moduleFederationRuntime,
};

export async function loadFederatedApplication(
  application: CatalogApplication,
  runtime?: FederatedRuntime,
  options: { signal?: AbortSignal; timeoutMs?: number } = {},
): Promise<FederatedApplicationModule<Component>> {
  let remote: unknown;
  const timeoutMs = options.timeoutMs ?? FEDERATED_LOAD_TIMEOUT_MS;
  if (!Number.isFinite(timeoutMs) || timeoutMs <= 0) {
    throw new Error("The federated application load timeout must be positive.");
  }

  const controller = new AbortController();
  const onAbort = () => controller.abort(options.signal?.reason);
  options.signal?.addEventListener("abort", onAbort, { once: true });
  if (options.signal?.aborted) onAbort();

  try {
    assertNotAborted(controller.signal);
    const load = (runtime ?? runtimeFor(application)).load(application, {
      signal: controller.signal,
    });
    remote = await withLoadDeadline(load, timeoutMs, controller);
    assertNotAborted(controller.signal);
  } catch (cause) {
    throw new Error(`Approved release ${application.release.releaseId} could not be loaded.`, {
      cause,
    });
  } finally {
    options.signal?.removeEventListener("abort", onAbort);
    controller.abort(new Error("Federated application load settled."));
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

function withLoadDeadline<T>(
  operation: Promise<T>,
  timeoutMs: number,
  controller: AbortController,
): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    let settled = false;
    const timer = setTimeout(() => {
      controller.abort(new Error("Federated application load timed out."));
      finishReject(new Error("Federated application load timed out."));
    }, timeoutMs);

    const finishResolve = (value: T): void => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      controller.signal.removeEventListener("abort", onAbort);
      resolve(value);
    };

    const finishReject = (reason: unknown): void => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      controller.signal.removeEventListener("abort", onAbort);
      reject(reason);
    };

    const onAbort = (): void => {
      finishReject(controller.signal.reason ?? new Error("Federated application load cancelled."));
    };

    controller.signal.addEventListener("abort", onAbort, { once: true });
    operation.then(finishResolve, finishReject);
  });
}

function assertNotAborted(signal?: AbortSignal): void {
  if (signal?.aborted) {
    throw signal.reason ?? new Error("Federated application load cancelled.");
  }
}
