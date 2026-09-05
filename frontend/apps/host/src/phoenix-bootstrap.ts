import {
  assertHostQueryParams,
  HOST_QUERY_PARAMS_MAX_BYTES,
  type HostQueryParams,
} from "@cadence/plugin-sdk";
import { createApp } from "vue";
import PhoenixHostApp from "./PhoenixHostApp.vue";
import type { PhoenixHostConfig } from "./phoenix-catalog-client";

export interface PhoenixHostMount {
  unmount(): void;
}

const mountedRoots = new WeakMap<HTMLElement, PhoenixHostMount>();

export function readPhoenixHostConfig(root: HTMLElement): PhoenixHostConfig {
  const applicationKey = root.dataset.applicationKey?.trim();
  const surfaceId = root.dataset.surfaceId?.trim();
  const catalogUrl = root.dataset.catalogUrl?.trim();
  const fallbackHref = root.dataset.fallbackHref?.trim();
  const hostScope = root.dataset.hostScope?.trim();
  const organizationId = readOptionalId(root.dataset.organizationId, "organization");
  const userId = readOptionalId(root.dataset.userId, "user");
  const missionId = readOptionalId(root.dataset.missionId, "mission");
  const spacecraftId = readOptionalId(root.dataset.spacecraftId, "spacecraft");
  const queryParams = parsePhoenixQueryParams(root.dataset.queryParams);

  if (!hostScope) {
    throw new Error("The Phoenix federation root requires an explicit data-host-scope.");
  }

  if (!applicationKey || !surfaceId || !catalogUrl || !fallbackHref) {
    throw new Error(
      "The Phoenix federation root requires data-application-key, data-surface-id, data-host-scope, data-catalog-url, and data-fallback-href.",
    );
  }

  const config = {
    applicationKey,
    surfaceId,
    catalogUrl,
    fallbackHref,
    ...(hostScope ? { hostScope: hostScope as PhoenixHostConfig["hostScope"] } : {}),
    ...(organizationId ? { organizationId } : {}),
    ...(userId ? { userId } : {}),
    ...(missionId ? { missionId } : {}),
    ...(spacecraftId ? { spacecraftId } : {}),
    queryParams,
  } as PhoenixHostConfig;

  assertPhoenixDomConfig(config);
  return config;
}

export function parsePhoenixQueryParams(raw: string | undefined): HostQueryParams {
  if (raw === undefined) return {};

  if (new TextEncoder().encode(raw).byteLength > HOST_QUERY_PARAMS_MAX_BYTES) {
    throw new Error("The Phoenix federation root query parameters are too large.");
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new Error("The Phoenix federation root query parameters are invalid JSON.");
  }

  try {
    assertHostQueryParams(parsed);
  } catch {
    throw new Error("The Phoenix federation root query parameters are invalid.");
  }

  return parsed;
}

export function bootstrapPhoenixHost(root: HTMLElement): PhoenixHostMount {
  const existing = mountedRoots.get(root);
  if (existing) return existing;

  const config = readPhoenixHostConfig(root);
  const app = createApp(PhoenixHostApp, config as unknown as Record<string, unknown>);
  app.mount(root);

  let mounted = true;
  const mount: PhoenixHostMount = {
    unmount(): void {
      if (!mounted) return;
      mounted = false;
      mountedRoots.delete(root);
      app.unmount();
    },
  };
  mountedRoots.set(root, mount);
  return mount;
}

export function unmountPhoenixHost(root: HTMLElement): void {
  mountedRoots.get(root)?.unmount();
}

function readOptionalId(value: string | undefined, label: string): string | undefined {
  if (value !== undefined && !value.trim()) {
    throw new Error(`The Phoenix federation root requires a non-empty data-${label}-id.`);
  }
  return value?.trim();
}

function assertPhoenixDomConfig(config: PhoenixHostConfig): void {
  if (!config.hostScope) {
    throw new Error("The Phoenix federation root requires an explicit host scope.");
  }

  if (config.queryParams !== undefined) assertHostQueryParams(config.queryParams);

  const scope = config.hostScope;

  switch (scope) {
    case "organization":
      if (!config.organizationId || config.userId || config.missionId || config.spacecraftId) {
        throw new Error("The Phoenix federation root has an invalid organization scope.");
      }
      break;
    case "user":
      if (!config.userId || config.organizationId || config.missionId || config.spacecraftId) {
        throw new Error("The Phoenix federation root has an invalid user scope.");
      }
      break;
    case "admin":
      if (config.organizationId || config.userId || config.missionId || config.spacecraftId) {
        throw new Error("The Phoenix federation root has an invalid admin scope.");
      }
      break;
    case "mission":
      if (!config.missionId || config.organizationId || config.userId || config.spacecraftId) {
        throw new Error("The Phoenix federation root has an invalid mission scope.");
      }
      break;
    case "spacecraft":
      if (!config.missionId || !config.spacecraftId || config.organizationId || config.userId) {
        throw new Error("The Phoenix federation root has an invalid spacecraft scope.");
      }
      break;
    default:
      throw new Error("The Phoenix federation root has an invalid host scope.");
  }
}
