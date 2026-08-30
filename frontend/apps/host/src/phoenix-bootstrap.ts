import { createApp } from "vue";
import PhoenixHostApp from "./PhoenixHostApp.vue";
import type { PhoenixHostConfig } from "./phoenix-catalog-client";

export function readPhoenixHostConfig(root: HTMLElement): PhoenixHostConfig {
  const applicationKey = root.dataset.applicationKey?.trim();
  const surfaceId = root.dataset.surfaceId?.trim();
  const rawSpacecraftId = root.dataset.spacecraftId;
  if (rawSpacecraftId !== undefined && !rawSpacecraftId.trim()) {
    throw new Error("The Phoenix federation root requires a non-empty data-spacecraft-id.");
  }
  const spacecraftId = rawSpacecraftId?.trim();
  const missionId = root.dataset.missionId?.trim();
  const catalogUrl = root.dataset.catalogUrl?.trim();
  const fallbackHref = root.dataset.fallbackHref?.trim();

  if (!applicationKey || !surfaceId || !missionId || !catalogUrl || !fallbackHref) {
    throw new Error(
      "The Phoenix federation root requires data-application-key, data-surface-id, data-mission-id, data-catalog-url, and data-fallback-href.",
    );
  }

  return {
    applicationKey,
    surfaceId,
    ...(spacecraftId ? { spacecraftId } : {}),
    missionId,
    catalogUrl,
    fallbackHref,
  };
}

export function bootstrapPhoenixHost(root: HTMLElement): void {
  const config = readPhoenixHostConfig(root);
  createApp(PhoenixHostApp, config as unknown as Record<string, unknown>).mount(root);
}
