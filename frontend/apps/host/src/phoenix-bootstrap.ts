import { createApp } from "vue";
import PhoenixHostApp from "./PhoenixHostApp.vue";
import type { PhoenixHostConfig } from "./phoenix-catalog-client";

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

  if (!hostScope && !missionId) {
    throw new Error("The Phoenix federation root requires data-mission-id.");
  }

  if (!applicationKey || !surfaceId || !catalogUrl || !fallbackHref) {
    throw new Error(
      "The Phoenix federation root requires data-application-key, data-surface-id, data-mission-id, data-catalog-url, and data-fallback-href (or data-host-scope with its matching id).",
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
  } as PhoenixHostConfig;

  assertPhoenixDomConfig(config);
  return config;
}

export function bootstrapPhoenixHost(root: HTMLElement): void {
  const config = readPhoenixHostConfig(root);
  createApp(PhoenixHostApp, config as unknown as Record<string, unknown>).mount(root);
}

function readOptionalId(value: string | undefined, label: string): string | undefined {
  if (value !== undefined && !value.trim()) {
    throw new Error(`The Phoenix federation root requires a non-empty data-${label}-id.`);
  }
  return value?.trim();
}

function assertPhoenixDomConfig(config: PhoenixHostConfig): void {
  const scope = config.hostScope ?? (config.spacecraftId === undefined ? "mission" : "spacecraft");

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
